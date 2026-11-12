<#
.SYNOPSIS
    Relocate the Windows "Downloads" known folder to a dedicated sub-folder on
    another drive, with pre-flight checks, verified file migration, complete
    backups and an honest pass/fail report.

.DESCRIPTION
    Fixes the three registry values that control Downloads:
      - {374DE290-123F-4565-9164-39C4925E467B}  "Downloads"
      - {7D83EE9B-2244-4E70-B1F5-5393042AF1E4}  "Local Downloads" (nav pane / This PC)
      - the named "Downloads" value (legacy readers)
    Also writes desktop.ini so the folder keeps its localized display name and
    icon, migrates existing files with per-file verification, and refreshes the
    shell namespace.

    A bare drive root (F:\) is REJECTED: that is exactly the mistake that makes
    the whole drive appear as Downloads.

.PARAMETER TargetPath
    Destination SUB-folder, e.g. "F:\Downloads". Never a bare drive root.

.PARAMETER NoMoveExisting
    Change only the registry pointer, leaving existing files where they are.
    A [switch] is used deliberately: a [bool] parameter cannot be set reliably
    from a "powershell.exe -File ..." command line (v1.0.0's
    -MoveExisting:$false form fails there with a conversion error).

.PARAMETER BackupDir
    Where .reg backups and the migration manifest are written. Default $env:USERPROFILE.

.PARAMETER NoExplorerRestart
    Do not restart explorer.exe (remote / unattended sessions).

.PARAMETER WhatIf
    Alias: -DryRun. Print the full plan and pre-flight report. Writes NOTHING:
    no .reg files, no folders, no registry changes, no desktop.ini.

.PARAMETER AllowExistingFiles
    Permit overwriting same-named files already present in the destination.
    Without this switch, name collisions are a blocking pre-flight error.

.PARAMETER LocalizedResource
    Resource string used for LocalizedResourceName in desktop.ini. The default
    resolves to the system-localized name (downloads / 下载) on zh-CN Windows.
    Override it for other display languages or a custom label.

.OUTPUTS
    Structured [OK]/[INFO]/[WARN]/[ERROR]/[DRYRUN]/[SKIP] lines plus a final
    ===== SUMMARY ===== block. Exit code is 0 only when every check passed.

.EXIT CODES
    0  success (or a clean DryRun)
    2  pre-flight validation failed - nothing was changed
    3  backup failed - nothing was changed
    4  one or more files failed to migrate
    5  post-write verification failed (registry / desktop.ini)
    1  unexpected exception

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads" -DryRun

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/relocate_downloads.ps1 -TargetPath "F:\Downloads"

.NOTES
    Windows PowerShell 5.1+. No administrator rights required (HKCU only).
    Author: banshan83 | v1.1.1
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [switch]$NoMoveExisting,
    [string]$BackupDir = $env:USERPROFILE,
    [switch]$NoExplorerRestart,
    [Alias('DryRun')][switch]$WhatIf,
    [switch]$AllowExistingFiles,
    [string]$LocalizedResource = '@%SystemRoot%\system32\shell32.dll,-21798'
)

$ErrorActionPreference = 'Stop'
# StrictMode 1.0 (uninitialised variables only). 2.0 would throw on a missing
# registry property on a clean install, which is a normal condition here.
Set-StrictMode -Version 1.0

# --- shared, side-effect-free helpers -----------------------------------------
$common = Join-Path $PSScriptRoot 'lib\DownloadsCommon.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Output "[ERROR] Missing helper: $common"
    exit 1
}
. $common

$c = Get-DlrConstants
$DL_GUID  = $c.DownloadsGuid
$LDL_GUID = $c.LocalDownloadsGuid
$usf      = $c.UserShellFolders
$sf       = $c.ShellFolders
$doMove   = -not $NoMoveExisting

$failures = New-Object System.Collections.Generic.List[string]
$warnings = New-Object System.Collections.Generic.List[string]

function Stop-Dlr {
    param([int]$Code, [string]$Reason)
    Write-DlrLog ERROR $Reason
    Write-Output ''
    Write-Output '===== SUMMARY ====='
    Write-Output ("Result       : FAILED (exit $Code)")
    Write-Output ("Reason       : $Reason")
    Write-Output ("Failures     : $($failures.Count)")
    foreach ($f in $failures) { Write-Output ("  - $f") }
    Write-Output 'Changes made : see the log above. Nothing is silently assumed.'
    exit $Code
}

try {
    # ==== 0. Environment ========================================================
    Write-Output '===== Windows Downloads Relocator v1.1.1 ====='
    if ($PSVersionTable.PSVersion.Major -lt 5) {
        Stop-Dlr 2 "Windows PowerShell 5.1 or newer is required (found $($PSVersionTable.PSVersion))."
    }
    Write-DlrLog OK ("PowerShell $($PSVersionTable.PSVersion) / $([Environment]::OSVersion.VersionString)")
    Write-DlrLog INFO ("Mode: " + $(if ($WhatIf) { 'DRY RUN (read-only, writes nothing)' } else { 'APPLY' }))

    $current = Get-DlrCurrentDownloads
    Write-DlrLog INFO "Current Downloads location: $current"
    if (Test-DlrBareRoot $current) {
        $warnings.Add("The CURRENT Downloads path is a bare drive root ($current) - this is the whole-drive bug. This run will repair it.")
    }

    # ==== 1. Target validation =================================================
    $check = Test-DlrTargetPath -Path $TargetPath -CurrentPath $current -SystemDrive $env:SystemDrive
    foreach ($e in $check.Errors)   { $failures.Add("target: $e") }
    foreach ($w in $check.Warnings) { $warnings.Add("target: $w") }
    foreach ($w in $check.Warnings) { Write-DlrLog WARN $w }
    foreach ($e in $check.Errors)   { Write-DlrLog ERROR $e }
    if (-not $check.Valid) { Stop-Dlr 2 'Target validation failed; no changes were made.' }

    $target = $check.Normalized
    Write-DlrLog OK "Target validated: $target (drive $($check.Drive))"

    # ==== 2. Pre-flight: inventory, space, collisions, locks, running apps =====
    Write-Output ''
    Write-Output '----- PRE-FLIGHT / 迁移前检查 -----'
    $before = Get-DlrFolderSnapshot -Path $current
    Write-DlrLog INFO ("Source: exists=$($before.Exists), files=$($before.FileCount), folders=$($before.DirCount), total=$(Format-DlrBytes $before.TotalBytes)")

    $free = Get-DlrFreeSpace -DriveLetter $check.Drive
    if ($free -lt 0) {
        $failures.Add('preflight: could not determine free space on the target drive')
        Write-DlrLog ERROR 'Could not determine free space on the target drive.'
    } else {
        Write-DlrLog INFO ("Target free space: $(Format-DlrBytes $free)")
        if ($doMove -and ($current -ine $target) -and $before.Exists) {
            $need = [long]($before.TotalBytes * 1.05) + 16MB
            if ($free -lt $need) {
                $msg = "Not enough free space: need about $(Format-DlrBytes $need), have $(Format-DlrBytes $free)."
                $failures.Add("preflight: $msg")
                Write-DlrLog ERROR $msg
            } else {
                Write-DlrLog OK 'Free space is sufficient for the migration.'
            }
        }
    }

    # Name collisions in an existing destination
    $collisions = @()
    if ((Test-Path -LiteralPath $target -PathType Container) -and ($current -ine $target)) {
        foreach ($rel in $before.Files.Keys) {
            $dest = Join-Path $target $rel
            if (Test-Path -LiteralPath $dest -PathType Leaf) { $collisions += $rel }
        }
    }
    if ($collisions.Count -gt 0) {
        if ($AllowExistingFiles) {
            $warnings.Add("preflight: $($collisions.Count) same-named file(s) in destination will be overwritten (-AllowExistingFiles).")
            Write-DlrLog WARN "$($collisions.Count) same-named file(s) in destination will be overwritten."
        } else {
            $msg = "$($collisions.Count) same-named file(s) already exist in '$target'. Re-run with -AllowExistingFiles to overwrite, or choose a clean destination. First: $($collisions[0])"
            $failures.Add("preflight: $msg")
            Write-DlrLog ERROR $msg
        }
    } else {
        Write-DlrLog OK 'No destination name collisions.'
    }

    # Writability probe - skipped entirely in DryRun so preview truly writes nothing
    if ($WhatIf) {
        Write-DlrLog DRYRUN 'Skipping the destination write-probe (preview is strictly read-only).'
    } else {
        $probeDir = $target
        if (-not (Test-Path -LiteralPath $probeDir)) {
            # probe the nearest existing parent without creating the destination yet
            $probeDir = Split-Path -Path $target -Parent
        }
        $probe = Join-Path $probeDir ('.dlr_probe_' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::WriteAllText($probe, 'ok')
            [IO.File]::Delete($probe)
            Write-DlrLog OK "Destination is writable (probe in $probeDir)."
        } catch {
            $msg = "Destination is not writable: $($_.Exception.Message)"
            $failures.Add("preflight: $msg")
            Write-DlrLog ERROR $msg
        }
    }

    # Apps that could lock files or overwrite configs
    $running = Get-DlrRunningApps -ProcessNames @('chrome','msedge','firefox','WeChat','Weixin','QQ','TIM','BaiduNetdisk','QuarkCloudDrive','aDrive','Thunder','explorer')
    if ($running.Count -gt 0) {
        $warnings.Add("preflight: running apps may lock files or rewrite their configs: $($running -join ', ')")
        Write-DlrLog WARN "These apps are running; close them for a clean migration: $($running -join ', ')"
    } else {
        Write-DlrLog OK 'No common file-holding apps detected.'
    }

    Write-Output ("Pre-flight result: errors=$($failures.Count), warnings=$($warnings.Count)")
    if ($failures.Count -gt 0) { Stop-Dlr 2 'Pre-flight checks failed; no files or registry values were changed.' }
    Write-Output '-------------------------------'

    # ==== 3. Dry run plan (strictly read-only) =================================
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $bakUsf = Join-Path $BackupDir ("Downloads_UserShellFolders_{0}.reg" -f $timestamp)
    $bakSf  = Join-Path $BackupDir ("Downloads_ShellFolders_{0}.reg" -f $timestamp)
    $manifest = Join-Path $BackupDir ("Downloads_Manifest_{0}.json" -f $timestamp)

    if ($WhatIf) {
        Write-Output ''
        Write-Output '----- DRY-RUN PLAN / 预览计划 -----'
        Write-DlrLog DRYRUN "Would export registry backups (via reg.exe, preserving REG_EXPAND_SZ):"
        Write-DlrLog DRYRUN "  $bakUsf"
        Write-DlrLog DRYRUN "  $bakSf"
        Write-DlrLog DRYRUN "  $manifest (migration manifest for restore_downloads.ps1)"
        Write-DlrLog DRYRUN "Would create folder: $target"
        if ($doMove -and ($current -ine $target) -and $before.Exists) {
            Write-DlrLog DRYRUN "Would migrate $($before.FileCount) file(s) / $(Format-DlrBytes $before.TotalBytes) from '$current', then verify each file."
        } else {
            Write-DlrLog DRYRUN 'Would SKIP file migration (-NoMoveExisting or same path).'
        }
        Write-DlrLog DRYRUN "Would set SHSetKnownFolderPath(Downloads) + 3 registry values -> $target"
        Write-DlrLog DRYRUN "Would write desktop.ini (LocalizedResourceName=$LocalizedResource) and set Hidden+System / ReadOnly attributes"
        Write-DlrLog DRYRUN $(if ($NoExplorerRestart) { 'Would NOT restart Explorer (-NoExplorerRestart).' } else { 'Would restart Explorer and re-launch it.' })
        Write-DlrLog DRYRUN 'Would verify all 3 registry values, desktop.ini content and folder attributes.'
        Write-Output ''
        Write-Output '===== SUMMARY ====='
        Write-Output 'Result       : DRY RUN OK (no files, registry keys or backups were written)'
        Write-Output ("Pre-flight   : errors=0, warnings=$($warnings.Count)")
        foreach ($w in $warnings) { Write-Output ("  ! $w") }
        Write-Output ("Next step    : re-run without -DryRun / -WhatIf to apply.")
        exit 0
    }

    # ==== 4. Backups (full fidelity, verified) =================================
    Write-Output ''
    Write-Output '----- BACKUP / 备份 -----'
    if (-not (Test-Path -LiteralPath $BackupDir)) {
        New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
    }
    $exports = @(
        @{ Key = $c.UserShellFoldersReg; File = $bakUsf },
        @{ Key = $c.ShellFoldersReg;     File = $bakSf  }
    )
    foreach ($e in $exports) {
        & reg.exe export $e.Key $e.File /y 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $e.File) -or ((Get-Item -LiteralPath $e.File).Length -lt 60)) {
            Stop-Dlr 3 "Registry backup failed for $($e.Key) -> $($e.File). Nothing else was changed."
        }
        Write-DlrLog OK "Exported $($e.Key) -> $($e.File)"
    }

    $manifestObj = [ordered]@{
        Skill        = 'windows-downloads-relocator'
        Version      = '1.1.1'
        Timestamp     = (Get-Date).ToString('o')
        OldPath       = $current
        NewPath       = $target
        MoveExisting  = $doMove
        SourceFiles   = $before.FileCount
        SourceBytes   = $before.TotalBytes
        RegistryBackups = @($bakUsf, $bakSf)
        UserShellFolders = $c.UserShellFoldersReg
        ShellFolders     = $c.ShellFoldersReg
        DownloadsGuid      = $DL_GUID
        LocalDownloadsGuid = $LDL_GUID
    }
    try {
        ($manifestObj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $manifest -Encoding UTF8
        Write-DlrLog OK "Wrote migration manifest -> $manifest"
    } catch {
        Stop-Dlr 3 "Could not write the migration manifest: $($_.Exception.Message)"
    }

    # ==== 5. Create destination ================================================
    if (-not (Test-Path -LiteralPath $target -PathType Container)) {
        try {
            New-Item -ItemType Directory -Path $target -Force | Out-Null
            Write-DlrLog OK "Created folder: $target"
        } catch {
            Stop-Dlr 4 "Could not create '$target': $($_.Exception.Message)"
        }
    } else {
        Write-DlrLog SKIP "Folder already exists: $target"
    }

    # ==== 6. Verified file migration ===========================================
    $migration = [pscustomobject]@{ Attempted = $false; Checked = 0; Failed = 0; Details = @() }
    if ($doMove -and ($current -ine $target) -and $before.Exists -and $before.FileCount -gt 0) {
        Write-Output ''
        Write-Output '----- MIGRATION / 文件迁移 -----'
        $migration.Attempted = $true
        Write-DlrLog INFO "Moving $($before.FileCount) file(s) from '$current' to '$target' ..."

        # Pass 1: robocopy. Exit codes 0-7 = success, >=8 = real failure.
        $rcOut = & robocopy.exe $current $target /E /MOVE /COPY:DAT /R:2 /W:2 /NFL /NDL /NJH /NJS /NP 2>&1
        $rc = $LASTEXITCODE
        if ($rc -ge 8) {
            $msg = "robocopy reported a failure (exit code $rc). Output tail: $(($rcOut | Select-Object -Last 4) -join ' | ')"
            $warnings.Add("migration: $msg")
            Write-DlrLog WARN $msg
        } else {
            Write-DlrLog OK "robocopy finished (exit code $rc = success)."
        }

        # Pass 2: per-file verification + one targeted retry for anything left behind
        $cmp = Compare-DlrSnapshot -Before $before -Destination $target
        $stillMissing = @($cmp.Missing) + @($cmp.SizeMismatch)
        if ($stillMissing.Count -gt 0) {
            Write-DlrLog WARN "$($stillMissing.Count) item(s) not yet verified; retrying individually ..."
            foreach ($rel in $stillMissing) {
                $src = Join-Path $current $rel
                $dst = Join-Path $target $rel
                $done = $false
                if (Test-Path -LiteralPath $src -PathType Leaf) {
                    try {
                        $dstParent = Split-Path -Path $dst -Parent
                        if (-not (Test-Path -LiteralPath $dstParent)) { New-Item -ItemType Directory -Path $dstParent -Force | Out-Null }
                        Copy-Item -LiteralPath $src -Destination $dst -Force -ErrorAction Stop
                        if ((Get-Item -LiteralPath $dst -Force).Length -eq (Get-Item -LiteralPath $src -Force).Length) {
                            Remove-Item -LiteralPath $src -Force -ErrorAction Stop
                            $done = $true
                        }
                    } catch { $done = $false }
                }
                if (-not $done) {
                    $failures.Add("migration: '$rel' could not be moved/verified (locked, in use, or unreadable)")
                    Write-DlrLog ERROR "FAILED to migrate: $rel"
                } else {
                    Write-DlrLog OK "Retry succeeded: $rel"
                }
            }
        }

        # Final verification - never claim success without checking
        $final = Compare-DlrSnapshot -Before $before -Destination $target
        $migration.Checked = $final.Checked
        $migration.Failed  = $final.Missing.Count + $final.SizeMismatch.Count
        foreach ($m in $final.Missing)      { Write-DlrLog ERROR "Missing after migration: $m" }
        foreach ($m in $final.SizeMismatch) { Write-DlrLog ERROR "Size mismatch after migration: $m" }
        if ($final.Ok) {
            Write-DlrLog OK "Verified $($final.Checked)/$($final.Checked) file(s) present with matching sizes."
            # Clean up now-empty source directories left by /MOVE (best effort)
            if (Test-Path -LiteralPath $current) {
                $leftover = @(Get-ChildItem -LiteralPath $current -Recurse -Force -ErrorAction SilentlyContinue)
                if ($leftover.Count -eq 0) {
                    try { Remove-Item -LiteralPath $current -Force -ErrorAction SilentlyContinue } catch {}
                }
            }
        } else {
            $failures.Add("migration: $($migration.Failed) of $($migration.Checked) file(s) were NOT migrated")
            Write-DlrLog ERROR "Migration incomplete: $($migration.Failed) of $($migration.Checked) file(s) failed. Originals were kept where possible."
        }
    } else {
        Write-DlrLog SKIP 'File migration skipped (-NoMoveExisting, same path, or empty source).'
    }

    # ==== 7. Registry pointers =================================================
    Write-Output ''
    Write-Output '----- KNOWN FOLDER POINTERS / 注册表指向 -----'
    $apiOk = $false
    try {
        if (-not ('DlrShellApi' -as [type])) {
            $src = @'
using System;
using System.Runtime.InteropServices;
public class DlrShellApi {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHSetKnownFolderPath(ref Guid rfid, uint dwFlags, IntPtr hToken, string pszPath);
    [DllImport("shell32.dll")]
    public static extern void SHChangeNotify(int wEventId, uint uFlags, IntPtr dwItem1, IntPtr dwItem2);
}
'@
            Add-Type -TypeDefinition $src -ErrorAction Stop
        }
        $g = [Guid]$DL_GUID
        $hr = [DlrShellApi]::SHSetKnownFolderPath([ref]$g, 0, [IntPtr]::Zero, $target)
        if ($hr -eq 0) {
            $apiOk = $true
            Write-DlrLog OK 'SHSetKnownFolderPath(Downloads) returned S_OK (0x00000000).'
        } else {
            $warnings.Add("SHSetKnownFolderPath returned HRESULT 0x$('{0:X8}' -f $hr); registry writes are authoritative.")
            Write-DlrLog WARN "SHSetKnownFolderPath returned HRESULT 0x$('{0:X8}' -f $hr); continuing with registry writes."
        }
    } catch {
        $warnings.Add("SHSetKnownFolderPath unavailable ($($_.Exception.Message)); registry writes are authoritative.")
        Write-DlrLog WARN "SHSetKnownFolderPath unavailable: $($_.Exception.Message)"
    }

    $writes = @(
        @{ Path = $usf; Name = $DL_GUID;    Required = $true  },
        @{ Path = $usf; Name = 'Downloads'; Required = $true  },
        @{ Path = $usf; Name = $LDL_GUID;  Required = $true  },
        @{ Path = $sf;  Name = 'Downloads'; Required = $false },
        @{ Path = $sf;  Name = $DL_GUID;   Required = $false },
        @{ Path = $sf;  Name = $LDL_GUID;  Required = $false }
    )
    foreach ($w in $writes) {
        try {
            Set-ItemProperty -Path $w.Path -Name $w.Name -Value $target -Type ExpandString -Force -ErrorAction Stop
            $readBack = (Get-ItemProperty -Path $w.Path -Name $w.Name -ErrorAction Stop).$($w.Name)
            if ($readBack -ine $target) {
                throw "read-back mismatch: got '$readBack'"
            }
            Write-DlrLog OK "Set $($w.Path | Split-Path -Leaf) :: $($w.Name) = $target"
        } catch {
            $msg = "Could not set $($w.Name) in $($w.Path): $($_.Exception.Message)"
            if ($w.Required) { $failures.Add("registry: $msg"); Write-DlrLog ERROR $msg }
            else             { $warnings.Add("registry: $msg"); Write-DlrLog WARN $msg }
        }
    }

    # ==== 8. Localized name + icon =============================================
    Write-Output ''
    Write-Output '----- DISPLAY NAME / 显示名称与图标 -----'
    $diPath = Join-Path $target 'desktop.ini'
    $diLines = @(
        '[.ShellClassInfo]',
        "CLSID2=$DL_GUID",
        "LocalizedResourceName=$LocalizedResource",
        'IconResource=%SystemRoot%\system32\imageres.dll,-184'
    )
    try {
        Set-Content -LiteralPath $diPath -Value $diLines -Encoding ASCII -Force
        $di = Get-Item -LiteralPath $diPath -Force
        $di.Attributes = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
        $folder = Get-Item -LiteralPath $target -Force
        $folder.Attributes = $folder.Attributes -bor [IO.FileAttributes]::ReadOnly
        Write-DlrLog OK "Wrote desktop.ini (LocalizedResourceName=$LocalizedResource)."
        Write-DlrLog INFO 'Note: the display name follows the Windows UI language; 下载 appears on zh-CN, Downloads on en-US.'
        if ('DlrShellApi' -as [type]) {
            # SHCNE_ASSOCCHANGED = 0x08000000, SHCNF_IDLIST = 0
            [DlrShellApi]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
            Write-DlrLog OK 'Notified the shell to refresh folder metadata (SHChangeNotify).'
        }
    } catch {
        $failures.Add("desktop.ini: $($_.Exception.Message)")
        Write-DlrLog ERROR "Could not write desktop.ini: $($_.Exception.Message)"
    }

    # ==== 9. Explorer refresh ==================================================
    if (-not $NoExplorerRestart) {
        try {
            Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2
            if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
                Start-Process -FilePath "$env:WINDIR\explorer.exe" -ErrorAction SilentlyContinue
            }
            Write-DlrLog OK 'Explorer restarted (re-launched explicitly if needed).'
        } catch {
            $warnings.Add("Explorer restart failed: $($_.Exception.Message)")
            Write-DlrLog WARN "Explorer restart failed (a manual sign-out/reboot will refresh it): $($_.Exception.Message)"
        }
    } else {
        Write-DlrLog SKIP 'Explorer restart skipped (-NoExplorerRestart); reboot or sign out to refresh.'
    }

    # ==== 10. Final verification ===============================================
    Write-Output ''
    Write-Output '----- VERIFICATION / 最终校验 -----'
    $pv = Get-ItemProperty -Path $usf
    $checks = @(
        @{ Label = 'Downloads (GUID)';       Value = $pv.$DL_GUID },
        @{ Label = 'Local Downloads (GUID)'; Value = $pv.$LDL_GUID },
        @{ Label = 'Downloads (named)';      Value = $pv.Downloads }
    )
    foreach ($k in $checks) {
        if ($k.Value -ieq $target) { Write-DlrLog OK "VERIFY $($k.Label) = $($k.Value)" }
        else {
            $failures.Add("verification: $($k.Label) = '$($k.Value)', expected '$target'")
            Write-DlrLog ERROR "VERIFY $($k.Label) = '$($k.Value)' (expected '$target')"
        }
    }
    $diOk = $false
    if (Test-Path -LiteralPath $diPath) {
        $diText = Get-Content -LiteralPath $diPath -Raw
        $diOk = ($diText -match 'CLSID2=') -and ($diText -match 'LocalizedResourceName=') -and ($diText -match 'IconResource=')
    }
    if ($diOk) { Write-DlrLog OK 'VERIFY desktop.ini contains CLSID2 + LocalizedResourceName + IconResource' }
    else {
        $failures.Add('verification: desktop.ini is missing or incomplete')
        Write-DlrLog ERROR 'VERIFY desktop.ini missing or incomplete'
    }
    $attrOk = ((Get-Item -LiteralPath $target -Force).Attributes -band [IO.FileAttributes]::ReadOnly) -ne 0
    if ($attrOk) { Write-DlrLog OK 'VERIFY destination folder has the ReadOnly flag (required for desktop.ini)' }
    else { $warnings.Add('verification: destination folder lacks the ReadOnly flag'); Write-DlrLog WARN 'VERIFY destination folder lacks the ReadOnly flag' }

    # ==== 11. Honest summary ===================================================
    Write-Output ''
    Write-Output '===== SUMMARY ====='
    Write-Output ("Mode         : $(if ($WhatIf) { 'DryRun' } else { 'Apply' })")
    Write-Output ("From / To    : $current  ->  $target")
    Write-Output ("Files        : checked=$($migration.Checked), failed=$($migration.Failed)")
    Write-Output ("Backups      : $bakUsf | $bakSf | $manifest")
    Write-Output ("Warnings     : $($warnings.Count)")
    foreach ($w in $warnings) { Write-Output ("  ! $w") }
    Write-Output ("Failures     : $($failures.Count)")
    foreach ($f in $failures) { Write-Output ("  - $f") }

    if ($failures.Count -gt 0) {
        Write-Output 'Result       : FAILED - see the failures above. Re-run after resolving them.'
        Write-Output ("Rollback     : powershell -ExecutionPolicy Bypass -File scripts/restore_downloads.ps1 -Manifest `"$manifest`" -DryRun")
        exit $(if ($migration.Failed -gt 0) { 4 } else { 5 })
    }
    Write-Output 'Result       : SUCCESS'
    Write-Output 'Next         : run scripts/set_app_downloads.ps1, then verify with a test download.'
    exit 0
}
catch {
    $msg = $_.Exception.Message
    Write-DlrLog ERROR "Unexpected exception: $msg"
    Write-Output ''
    Write-Output '===== SUMMARY ====='
    Write-Output "Result       : FAILED (exit 1) - unexpected exception: $msg"
    Write-Output 'Backups      : see [OK] Exported lines above (if any).'
    exit 1
}
