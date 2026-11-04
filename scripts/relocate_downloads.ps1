<#
.SYNOPSIS
    Relocate the Windows "Downloads" known folder to a new subfolder and align
    every related registration, display name, icon, and file content.

.DESCRIPTION
    Moves the user's Downloads known folder to a target path (e.g. F:\Downloads)
    and fixes the two registry entries that actually control it:
      - {374DE290-123F-4565-9164-39C4925E467B}  "Downloads"        (used by most APIs)
      - {7D83EE9B-2244-4E70-B1F5-5393042AF1E4}  "Local Downloads"  (used by the nav pane / This PC!)
    It also writes the localized desktop.ini so the folder keeps the system
    display name (e.g. Chinese "下载") and the Downloads icon, and migrates the
    existing files. A bare drive root (F:\) is explicitly rejected because that
    is the exact mistake that makes the WHOLE drive appear as Downloads.

.PARAMETER TargetPath
    Destination subfolder, e.g. "F:\Downloads". Must NOT be a bare drive root.

.PARAMETER MoveExisting
    Move existing files/folders from the current Downloads location into the new
    one. Default $true.

.PARAMETER BackupDir
    Where the .reg backups are written. Default $env:USERPROFILE.

.PARAMETER NoExplorerRestart
    Do not restart explorer.exe (useful for remote/unattended sessions).

.PARAMETER WhatIf
    Report the plan without making changes.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,

    [bool]$MoveExisting = $true,
    [string]$BackupDir = $env:USERPROFILE,
    [switch]$NoExplorerRestart,
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

# ---- 0. Validate: reject bare drive root (the whole-drive bug) ----
if ($TargetPath -match '^[A-Za-z]:\\?$') {
    Write-Error "TargetPath '$TargetPath' is a bare drive root. That is the exact mistake that makes the entire drive appear as Downloads. Use a subfolder, e.g. 'F:\Downloads'."
    exit 1
}
$TargetPath = $TargetPath.TrimEnd('\')

$usf = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
$sf  = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
$DL_GUID  = '{374DE290-123F-4565-9164-39C4925E467B}'   # Downloads
$LDL_GUID = '{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}'   # Local Downloads (nav pane / This PC)

function Get-CurrentDownloads {
    $p = Get-ItemProperty $usf -ErrorAction SilentlyContinue
    if ($p.$DL_GUID)  { return $p.$DL_GUID }
    if ($p.Downloads) { return $p.Downloads }
    return $null
}

$current = Get-CurrentDownloads
if (-not $current) { $current = Join-Path $env:USERPROFILE 'Downloads' }
Write-Output ("Current Downloads location: " + $current)

# ---- 1. Backup registry to .reg ----
if (-not (Test-Path $BackupDir)) { New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null }
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$bakUsf = Join-Path $BackupDir ("Downloads_UserShellFolders_{0}.reg" -f $timestamp)
$bakSf  = Join-Path $BackupDir ("Downloads_ShellFolders_{0}.reg" -f $timestamp)

function Export-RegKeyAsReg($keyPath, $outFile) {
    $props = Get-ItemProperty $keyPath -ErrorAction SilentlyContinue
    $lines = @('Windows Registry Editor Version 5.00', '', '[' + $keyPath.Replace('HKCU:\', 'HKEY_CURRENT_USER\') + ']')
    foreach ($name in ($props.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' })) {
        $v = $name.Value
        if ($v -is [string]) { $lines += ('"' + $name.Name + '"="' + $v + '"') }
    }
    $lines += ''
    Set-Content -Path $outFile -Value $lines -Encoding Unicode
}
Export-RegKeyAsReg $usf $bakUsf
Export-RegKeyAsReg $sf  $bakSf
Write-Output ("Registry backups written:`n  $bakUsf`n  $bakSf")

if ($WhatIf) {
    Write-Output ("WHATIF: would set Downloads + Local Downloads -> '$TargetPath', create folder, migrate from '$current', write desktop.ini.")
    exit 0
}

# ---- 2. Create target folder ----
if (-not (Test-Path $TargetPath)) {
    New-Item -ItemType Directory -Path $TargetPath -Force | Out-Null
    Write-Output ("Created " + $TargetPath)
}

# ---- 3. Migrate existing downloads ----
if ($MoveExisting -and ($current -ne $TargetPath) -and (Test-Path $current)) {
    Write-Output ("Migrating existing contents from '$current' to '$TargetPath' ...")
    try {
        & robocopy.exe $current $TargetPath /E /MOVE /R:1 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    } catch {}
    # Fallback for any leftovers robocopy skipped
    Get-ChildItem $current -Force -ErrorAction SilentlyContinue | ForEach-Object {
        try { Move-Item -Path $_.FullName -Destination $TargetPath -Force -ErrorAction Stop } catch {}
    }
    Write-Output "Migration attempt complete."
}

# ---- 4. Set the known folder path (API best-effort, registry always) ----
function Set-DownloadsPath([string]$path) {
    # Try the official API; fall back silently to registry writes (authoritative).
    try {
        $code = 'using System;using System.Runtime.InteropServices;public class KFSetPath{[DllImport("shell32.dll",CharSet=CharSet.Unicode,ExactSpelling=true)]public static extern int SHSetKnownFolderPath([MarshalAs(UnmanagedType.LPStruct)]Guid rfid,uint dwFlags,IntPtr hToken,string pszPath);}'
        Add-Type -TypeDefinition $code -ErrorAction Stop
        $g  = [Guid]$DL_GUID
        $hr = [KFSetPath]::SHSetKnownFolderPath($g, 0, [IntPtr]::Zero, $path)
        Write-Output ("SHSetKnownFolderPath HRESULT: 0x{0:X8}" -f $hr)
    } catch {
        Write-Output ("SHSetKnownFolderPath unavailable ($( $_.Exception.Message.Split([Environment]::NewLine)[0] )); using registry writes.")
    }
    Set-ItemProperty $usf -Name $DL_GUID    -Value $path -Type ExpandString -Force
    Set-ItemProperty $usf -Name 'Downloads' -Value $path -Type ExpandString -Force
    Set-ItemProperty $usf -Name $LDL_GUID   -Value $path -Type ExpandString -Force
    Set-ItemProperty $sf  -Name 'Downloads' -Value $path -Type ExpandString -Force -ErrorAction SilentlyContinue
    try { Set-ItemProperty $sf -Name $DL_GUID  -Value $path -Type ExpandString -Force -ErrorAction SilentlyContinue } catch {}
    try { Set-ItemProperty $sf -Name $LDL_GUID -Value $path -Type ExpandString -Force -ErrorAction SilentlyContinue } catch {}
}
Set-DownloadsPath -path $TargetPath

# ---- 5. Localized display name + icon (desktop.ini) ----
$diPath = Join-Path $TargetPath 'desktop.ini'
$diLines = @(
    '[.ShellClassInfo]',
    'CLSID2={374DE290-123F-4565-9164-39C4925E467B}',
    'LocalizedResourceName=@%SystemRoot%\system32\shell32.dll,-21798',
    'IconResource=%SystemRoot%\system32\imageres.dll,-184'
)
Set-Content -Path $diPath -Value $diLines -Encoding ASCII
$di = Get-Item $diPath -Force
$di.Attributes = [IO.FileAttributes]::Hidden -bor [IO.FileAttributes]::System
$folder = Get-Item $TargetPath -Force
$folder.Attributes = $folder.Attributes -bor [IO.FileAttributes]::ReadOnly
Write-Output "Wrote desktop.ini (localized name + icon)."

# ---- 6. Restart Explorer to refresh the namespace ----
if (-not $NoExplorerRestart) {
    try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue } catch {}
    Start-Sleep -Seconds 2
}

# ---- 7. Verify ----
$pv = Get-ItemProperty $usf
Write-Output ("VERIFY Downloads(GUID)        = [" + $pv.$DL_GUID + "]")
Write-Output ("VERIFY LocalDownloads(GUID)  = [" + $pv.$LDL_GUID + "]")
Write-Output ("VERIFY desktop.ini present    = " + (Test-Path $diPath))
Write-Output "Done. If the sidebar still shows the old location, unpin/re-pin Downloads in Quick Access, or reboot once."

