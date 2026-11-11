<#
.SYNOPSIS
    Roll back a Downloads relocation performed by relocate_downloads.ps1.

.DESCRIPTION
    Reads the JSON manifest written by relocate_downloads.ps1 and restores the
    three registry pointers (Downloads GUID, Local Downloads GUID, named value)
    to the pre-migration path. It also writes a desktop.ini-free state check and
    refreshes Explorer.

    IMPORTANT: file migration is a physical move. This script restores the
    POINTER only; it never moves files back. Move them manually if required.

.PARAMETER Manifest
    Path to Downloads_Manifest_<timestamp>.json. If omitted, the newest manifest
    in -BackupDir is used.

.PARAMETER BackupDir
    Directory to search for manifests when -Manifest is not given.
    Default $env:USERPROFILE.

.PARAMETER ImportFullBackup
    Also import the two .reg exports with reg.exe import. This restores EVERY
    value under the two shell-folder keys, which may undo unrelated user
    customisations. Off by default.

.PARAMETER WhatIf
    Alias: -DryRun. Report the rollback plan without changing anything.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/restore_downloads.ps1 -Manifest "$env:USERPROFILE\Downloads_Manifest_20261112-003000.json" -DryRun

.NOTES
    Windows PowerShell 5.1+. Author: banshan83 | v1.1.0
#>
[CmdletBinding()]
param(
    [string]$Manifest,
    [string]$BackupDir = $env:USERPROFILE,
    [switch]$ImportFullBackup,
    [Alias('DryRun')][switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
$common = Join-Path $PSScriptRoot 'lib\DownloadsCommon.ps1'
if (-not (Test-Path -LiteralPath $common)) { Write-Output "[ERROR] Missing helper: $common"; exit 1 }
. $common
$c = Get-DlrConstants

try {
    Write-Output '===== Downloads Relocation Rollback v1.1.0 ====='
    Write-DlrLog INFO ("Mode: " + $(if ($WhatIf) { 'DRY RUN (writes nothing)' } else { 'APPLY' }))

    if (-not $Manifest) {
        $found = @(Get-ChildItem -LiteralPath $BackupDir -Filter 'Downloads_Manifest_*.json' -ErrorAction SilentlyContinue |
                   Sort-Object LastWriteTime -Descending)
        if ($found.Count -eq 0) {
            Write-DlrLog ERROR "No Downloads_Manifest_*.json found in '$BackupDir'. Pass -Manifest explicitly."
            exit 2
        }
        $Manifest = $found[0].FullName
    }
    if (-not (Test-Path -LiteralPath $Manifest)) {
        Write-DlrLog ERROR "Manifest not found: $Manifest"
        exit 2
    }
    $m = Get-Content -LiteralPath $Manifest -Raw -Encoding UTF8 | ConvertFrom-Json
    Write-DlrLog INFO "Manifest   : $Manifest"
    Write-DlrLog INFO "Old path   : $($m.OldPath)"
    Write-DlrLog INFO "New path   : $($m.NewPath)"
    Write-DlrLog INFO "Recorded at: $($m.Timestamp)"
    Write-DlrLog WARN 'Files are NOT moved back by this script. Only the registry pointer is restored.'

    if ($WhatIf) {
        Write-DlrLog DRYRUN "Would set the 3 registry values back to '$($m.OldPath)'."
        Write-DlrLog DRYRUN "Would call SHSetKnownFolderPath(Downloads) -> '$($m.OldPath)'."
        if ($ImportFullBackup) {
            foreach ($b in $m.RegistryBackups) { Write-DlrLog DRYRUN "Would import $b" }
        }
        Write-DlrLog DRYRUN 'Would restart Explorer.'
        Write-Output '===== SUMMARY ====='
        Write-Output 'Result : DRY RUN OK - nothing was changed.'
        exit 0
    }

    if ($ImportFullBackup) {
        foreach ($b in $m.RegistryBackups) {
            if (-not (Test-Path -LiteralPath $b)) { Write-DlrLog WARN "Backup missing, skipped: $b"; continue }
            & reg.exe import $b 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) { Write-DlrLog OK "Imported $b" }
            else { Write-DlrLog ERROR "reg.exe import failed for $b (exit $LASTEXITCODE)" }
        }
    }

    $targets = @(
        @{ Path = $c.UserShellFolders; Name = $c.DownloadsGuid },
        @{ Path = $c.UserShellFolders; Name = $c.LocalDownloadsGuid },
        @{ Path = $c.UserShellFolders; Name = 'Downloads' },
        @{ Path = $c.ShellFolders;     Name = 'Downloads' }
    )
    $bad = 0
    foreach ($t in $targets) {
        try {
            Set-ItemProperty -Path $t.Path -Name $t.Name -Value $m.OldPath -Type ExpandString -Force -ErrorAction Stop
            $rb = (Get-ItemProperty -Path $t.Path -Name $t.Name -ErrorAction Stop).$($t.Name)
            if ($rb -ine $m.OldPath) { throw "read-back mismatch: '$rb'" }
            Write-DlrLog OK "Restored $($t.Name) = $($m.OldPath)"
        } catch {
            $bad++
            Write-DlrLog ERROR "Could not restore $($t.Name): $($_.Exception.Message)"
        }
    }
    try {
        if (-not ('DlrShellApi' -as [type])) {
            Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class DlrShellApi{[DllImport("shell32.dll",CharSet=CharSet.Unicode)]public static extern int SHSetKnownFolderPath(ref Guid rfid,uint dwFlags,IntPtr hToken,string pszPath);[DllImport("shell32.dll")]public static extern void SHChangeNotify(int e,uint f,IntPtr a,IntPtr b);}' -ErrorAction Stop
        }
        $g = [Guid]$c.DownloadsGuid
        $null = [DlrShellApi]::SHSetKnownFolderPath([ref]$g, 0, [IntPtr]::Zero, $m.OldPath)
        [DlrShellApi]::SHChangeNotify(0x08000000, 0, [IntPtr]::Zero, [IntPtr]::Zero)
        Write-DlrLog OK 'Notified the shell (SHSetKnownFolderPath + SHChangeNotify).'
    } catch {
        Write-DlrLog WARN "Shell API unavailable: $($_.Exception.Message)"
    }

    try {
        Get-Process -Name explorer -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 2
        if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) { Start-Process -FilePath "$env:WINDIR\explorer.exe" -ErrorAction SilentlyContinue }
        Write-DlrLog OK 'Explorer restarted.'
    } catch { Write-DlrLog WARN "Explorer restart failed: $($_.Exception.Message)" }

    Write-Output ''
    Write-Output '===== SUMMARY ====='
    Write-Output "Restored pointer : $($m.OldPath)"
    Write-Output "Failed writes    : $bad"
    Write-Output 'Files            : NOT moved back (physical move). Copy them manually if needed.'
    if ($bad -gt 0) { Write-Output 'Result           : FAILED (exit 5)'; exit 5 }
    Write-Output 'Result           : SUCCESS'
    exit 0
}
catch {
    Write-DlrLog ERROR "Unexpected exception: $($_.Exception.Message)"
    exit 1
}
