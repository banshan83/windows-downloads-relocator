<#
.SYNOPSIS
    Shared, side-effect-free helpers for the Windows Downloads Relocator scripts.

.DESCRIPTION
    Dot-source this file (`. $PSScriptRoot/lib/DownloadsCommon.ps1`).
    It deliberately performs NO writes to disk or registry, so it is safe to
    load from selftest.ps1 and to unit-test in isolation.

    Everything here is a pure validator / enumerator / formatter. All mutating
    work lives in relocate_downloads.ps1 and set_app_downloads.ps1.

.NOTES
    Windows PowerShell 5.1 compatible (no PS7-only syntax).
#>

# ---------------------------------------------------------------- constants ---
function Get-DlrConstants {
    return @{
        DownloadsGuid      = '{374DE290-123F-4565-9164-39C4925E467B}'
        LocalDownloadsGuid = '{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}'
        UserShellFolders   = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        ShellFolders       = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
        UserShellFoldersReg = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\User Shell Folders'
        ShellFoldersReg     = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Explorer\Shell Folders'
    }
}

# -------------------------------------------------------------------- logging ---
function Write-DlrLog {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('OK', 'INFO', 'WARN', 'ERROR', 'DRYRUN', 'SKIP')]
        [string]$Level,
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $tag = '[{0,-6}]' -f $Level
    Write-Output ("$tag $Message")
}

function Format-DlrBytes {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N2} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N2} KB' -f ($Bytes / 1KB)) }
    return ("$Bytes B")
}

# ---------------------------------------------------------- current location ---
function Get-DlrCurrentDownloads {
    $c = Get-DlrConstants
    # Use -Name + ErrorAction so a missing value on a clean install is a normal
    # fallback, not a StrictMode exception.
    try {
        $v = (Get-ItemProperty -Path $c.UserShellFolders -Name $c.DownloadsGuid -ErrorAction Stop).$($c.DownloadsGuid)
        if ($v) { return [string]$v }
    } catch { }
    try {
        $v = (Get-ItemProperty -Path $c.UserShellFolders -Name 'Downloads' -ErrorAction Stop).Downloads
        if ($v) { return [string]$v }
    } catch { }
    return (Join-Path $env:USERPROFILE 'Downloads')
}

function Test-DlrBareRoot {
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    return ($Path -match '^[A-Za-z]:\\?$')
}

# ---------------------------------------------------------- target validation ---
<#
    Returns a PSCustomObject:
      Normalized  - trimmed absolute path (only meaningful when Valid)
      Valid       - $true when there are no blocking errors
      Errors      - blocking problems (migration must NOT proceed)
      Warnings    - non-blocking problems (user should review)
      Drive       - drive letter, e.g. 'F:'
#>
function Test-DlrTargetPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$CurrentPath = '',
        [string]$SystemDrive = $env:SystemDrive
    )

    $errors   = New-Object System.Collections.Generic.List[string]
    $warnings = New-Object System.Collections.Generic.List[string]
    $norm     = ''

    if ([string]::IsNullOrWhiteSpace($Path)) {
        $errors.Add('TargetPath is empty.')
        return [pscustomobject]@{ Normalized = ''; Valid = $false; Errors = $errors.ToArray(); Warnings = $warnings.ToArray(); Drive = '' }
    }

    $norm = $Path.Trim().TrimEnd('\', '/')

    # 1. UNC / network paths are not valid Known Folder targets
    if ($norm.StartsWith('\\')) {
        $errors.Add("UNC / network path '$norm' is not supported: Known Folders must resolve to a local fixed volume.")
    }

    # 2. Must be an absolute, drive-letter path
    if ($norm -notmatch '^[A-Za-z]:\\') {
        $errors.Add("TargetPath '$norm' must be an absolute local path such as 'F:\Downloads'.")
    }

    # 3. The whole-drive trap (the exact bug this skill was written to fix)
    if (Test-DlrBareRoot $norm) {
        $errors.Add("TargetPath '$norm' is a bare drive root. Windows would register the WHOLE drive as Downloads. Use a sub-folder, e.g. 'F:\Downloads'.")
    }

    # 4. Illegal characters / over-long paths
    if ($norm -match '[<>\|"\?\*]') {
        $errors.Add("TargetPath contains characters that are illegal in a Windows path: $norm")
    }
    if ($norm.Length -gt 240) {
        $errors.Add("TargetPath is longer than 240 characters; Explorer may fail to resolve it.")
    }

    $driveLetter = ''
    if ($norm -match '^([A-Za-z]:)\\') { $driveLetter = $Matches[1] }

    # 5. Drive must exist and be a fixed local volume
    if ($driveLetter) {
        try {
            $d = Get-PSDrive -Name $driveLetter.TrimEnd(':') -PSProvider FileSystem -ErrorAction Stop
            $wmi = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$driveLetter'" -ErrorAction SilentlyContinue
            if ($wmi) {
                # DriveType: 2=Removable 3=Fixed 4=Network 5=CD-ROM 6=RAM disk
                if ($wmi.DriveType -ne 3) {
                    $errors.Add("Drive $driveLetter is not a fixed local disk (DriveType=$($wmi.DriveType)). Known Folders must live on a fixed volume, not removable / network / optical media.")
                }
            }
        } catch {
            $errors.Add("Drive $driveLetter does not exist or is not accessible: $($_.Exception.Message)")
        }
    }

    # 6. Warn about putting Downloads back on the system drive (defeats the purpose)
    if ($driveLetter -and $SystemDrive -and ($driveLetter.ToUpper() -eq $SystemDrive.TrimEnd(':').ToUpper() + ':')) {
        $warnings.Add("Target is on the system drive ($SystemDrive). This will NOT free space on the system volume.")
    }

    # 7. Refuse protected / structurally dangerous locations
    $protected = @()
    foreach ($v in @($env:USERPROFILE, $env:WINDIR, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:SystemDrive)) {
        if ($v) { $protected += $v.TrimEnd('\') }
    }
    foreach ($p in $protected) {
        if ($norm -ieq $p) {
            $errors.Add("TargetPath '$norm' is a protected system/profile root. Use a dedicated sub-folder.")
            break
        }
    }

    # 8. Never nest inside (or above) the current Downloads location
    if ($CurrentPath) {
        $cur = $CurrentPath.TrimEnd('\')
        if ($norm -ieq $cur) {
            $warnings.Add("Target equals the current Downloads path; only the registry / desktop.ini will be refreshed.")
        } elseif ($norm.StartsWith($cur + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $errors.Add("TargetPath '$norm' is INSIDE the current Downloads folder '$cur'. Moving files into their own sub-folder would recurse. Choose a separate path.")
        } elseif ($cur.StartsWith($norm + '\', [StringComparison]::OrdinalIgnoreCase)) {
            $warnings.Add("TargetPath '$norm' is a PARENT of the current Downloads folder. Existing files from '$cur' will be moved one level up.")
        }
    }

    return [pscustomobject]@{
        Normalized = $norm
        Valid      = ($errors.Count -eq 0)
        Errors     = $errors.ToArray()
        Warnings   = $warnings.ToArray()
        Drive      = $driveLetter
    }
}

# ------------------------------------------------------------- preflight data ---
<#
    Enumerate a folder into a stable, comparable snapshot.
    Returns: Files (relative path -> length), FileCount, DirCount, TotalBytes, Exists
#>
function Get-DlrFolderSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $files = @{}
    $fileCount = 0
    $dirCount = 0
    $total = [long]0
    $exists = Test-Path -LiteralPath $Path -PathType Container

    if ($exists) {
        $base = (Get-Item -LiteralPath $Path -Force).FullName.TrimEnd('\')
        $items = @(Get-ChildItem -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue)
        foreach ($i in $items) {
            if ($i.PSIsContainer) {
                $dirCount++
            } else {
                $fileCount++
                $total += $i.Length
                # Build the relative path by walking DirectoryInfo.Parent instead of
                # slicing FullName by string length. Short (8.3) vs long path names
                # can make the two prefixes differ by a few characters and corrupt
                # the slice - which used to make verification report false failures.
                $parts = New-Object System.Collections.Generic.List[string]
                $parts.Add($i.Name)
                $parent = $i.Directory
                $guard = 0
                while ($parent -and ($parent.FullName.TrimEnd('\') -ine $base) -and ($guard -lt 64)) {
                    $parts.Insert(0, $parent.Name)
                    $parent = $parent.Parent
                    $guard++
                }
                $rel = $parts -join '\'
                # desktop.ini is generated by this skill, not user data
                if ($rel -ine 'desktop.ini') { $files[$rel] = [long]$i.Length }
            }
        }
    }
    return [pscustomobject]@{
        Path      = $Path
        Exists    = $exists
        Files     = $files
        FileCount = $fileCount
        DirCount  = $dirCount
        TotalBytes = $total
    }
}

<#
    Compare a pre-migration snapshot against the destination folder.
    Returns: Missing (relative paths), SizeMismatch (relative paths), Checked, DestinationCount
#>
function Compare-DlrSnapshot {
    param(
        [Parameter(Mandatory = $true)]$Before,
        [Parameter(Mandatory = $true)][string]$Destination
    )
    $after = Get-DlrFolderSnapshot -Path $Destination
    $missing = New-Object System.Collections.Generic.List[string]
    $mismatch = New-Object System.Collections.Generic.List[string]

    foreach ($rel in $Before.Files.Keys) {
        $destFile = Join-Path $Destination $rel
        if (-not (Test-Path -LiteralPath $destFile -PathType Leaf)) {
            $missing.Add($rel)
        } elseif ((Get-Item -LiteralPath $destFile -Force).Length -ne $Before.Files[$rel]) {
            $mismatch.Add($rel)
        }
    }
    return [pscustomobject]@{
        Missing          = $missing.ToArray()
        SizeMismatch     = $mismatch.ToArray()
        Checked          = $Before.Files.Count
        DestinationCount = $after.FileCount
        Ok               = (($missing.Count -eq 0) -and ($mismatch.Count -eq 0))
    }
}

# ------------------------------------------------------------ process detection ---
function Get-DlrRunningApps {
    param([string[]]$ProcessNames)
    $running = New-Object System.Collections.Generic.List[string]
    foreach ($n in $ProcessNames) {
        if (Get-Process -Name $n -ErrorAction SilentlyContinue) { $running.Add($n) }
    }
    return $running.ToArray()
}

# ------------------------------------------------------------- free space -------
function Get-DlrFreeSpace {
    param([Parameter(Mandatory = $true)][string]$DriveLetter)
    try {
        $wmi = Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DeviceID='$DriveLetter'" -ErrorAction Stop
        return [long]$wmi.FreeSpace
    } catch {
        return [long]-1
    }
}
