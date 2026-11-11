<#
.SYNOPSIS
    Point common Windows applications' default download directory at a new path.

.DESCRIPTION
    Updates the download location in the most common desktop apps so they follow
    the relocated Downloads folder:
      * Chromium browsers (Chrome, Edge, Brave, Opera, Vivaldi) - Preferences JSON
      * Mozilla Firefox                                       - prefs.js
      * WeChat (微信)                                         - registry best-effort
      * Baidu Netdisk (百度网盘)                              - JSON config best-effort
      * Quark Netdisk (夸克网盘)                              - JSON config best-effort
      * Aliyun Drive (阿里云盘)                               - JSON config best-effort
      * QQ / TIM                                              - registry + manual

    v1.1.0 changes:
      * Real -WhatIf / -DryRun that writes nothing (validated with selftest.ps1).
      * Running apps are detected and SKIPPED by default, because an open browser
        rewrites Preferences on exit and silently discards the change.
      * Every config edit is verified (JSON parses / key reads back) and every
        failure is listed in the final SUMMARY instead of being swallowed.
      * Fixed a PowerShell scoping bug that made netdisk / QQ results disappear
        from the summary.

.PARAMETER TargetPath
    The new download directory, e.g. "F:\Downloads". Must be a sub-folder on a
    fixed local drive (validated), and should match relocate_downloads.ps1.

.PARAMETER WhatIf
    Alias: -DryRun. Report what would be changed. Writes no files, no .bak
    backups and no registry values.

.PARAMETER ApplyToRunningApps
    Edit configs even when the corresponding app is running. Not recommended:
    the app may overwrite the change when it exits.

.OUTPUTS
    [OK]/[INFO]/[WARN]/[ERROR]/[SKIP] lines and an explicit ===== SUMMARY =====
    with three lists: Auto-updated / Manual change required / Failures.

.EXIT CODES
    0  no failures (manual-only items are NOT failures)
    2  target validation failed
    4  one or more auto-updates failed
    1  unexpected exception

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/set_app_downloads.ps1 -TargetPath "F:\Downloads" -DryRun

.NOTES
    Windows PowerShell 5.1+. No administrator rights required.
    Author: banshan83 | v1.1.0
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath,
    [Alias('DryRun')][switch]$WhatIf,
    [switch]$ApplyToRunningApps
)

$ErrorActionPreference = 'Stop'
# StrictMode 1.0 only: registry/config properties legitimately may not exist.
Set-StrictMode -Version 1.0

$common = Join-Path $PSScriptRoot 'lib\DownloadsCommon.ps1'
if (-not (Test-Path -LiteralPath $common)) {
    Write-Output "[ERROR] Missing helper: $common"
    exit 1
}
. $common

# Script-scope collections: functions must NOT use plain `$x +=` here, because
# that creates a function-local variable and silently loses the result (v1.0.0 bug).
$script:changed = New-Object System.Collections.Generic.List[string]
$script:manual  = New-Object System.Collections.Generic.List[string]
$script:failed  = New-Object System.Collections.Generic.List[string]
$script:warnings = New-Object System.Collections.Generic.List[string]

function Add-Ok   ([string]$m) { $script:changed.Add($m);  Write-DlrLog OK $m }
function Add-Warn ([string]$m) { $script:warnings.Add($m); Write-DlrLog WARN $m }
function Add-Fail ([string]$m) { $script:failed.Add($m);   Write-DlrLog ERROR $m }
function Add-Manual ([string]$m) { $script:manual.Add($m) }

function Test-DlrAppBusy {
    param([string]$AppName, [string[]]$ProcessNames)
    if ($ApplyToRunningApps) { return $false }
    $busy = Get-DlrRunningApps -ProcessNames $ProcessNames
    if ($busy.Count -gt 0) {
        Add-Warn "$AppName is running ($($busy -join ', ')); skipped to avoid the app overwriting the change on exit. Close it and re-run, or use -ApplyToRunningApps."
        Add-Manual "${AppName}: close the app, re-run this script (or change it in Settings) to set $TargetPath"
        return $true
    }
    return $false
}

function Backup-DlrFile {
    param([Parameter(Mandatory = $true)][string]$File)
    # In DryRun we never create backups.
    if ($WhatIf) { return $true }
    $bak = $File + '.bak'
    try {
        Copy-Item -LiteralPath $File -Destination $bak -Force -ErrorAction Stop
        if (-not (Test-Path -LiteralPath $bak) -or ((Get-Item -LiteralPath $bak).Length -eq 0 -and (Get-Item -LiteralPath $File).Length -gt 0)) {
            throw 'backup file is missing or empty'
        }
        return $true
    } catch {
        Add-Fail "Backup failed for '$File': $($_.Exception.Message)"
        return $false
    }
}

function Restore-DlrFile {
    param([string]$File)
    $bak = $File + '.bak'
    if (Test-Path -LiteralPath $bak) {
        try { Copy-Item -LiteralPath $bak -Destination $File -Force -ErrorAction Stop } catch {}
    }
}

function Write-DlrText {
    param([string]$File, [string]$Text, [switch]$ValidateJson)
    if ($WhatIf) {
        Write-DlrLog DRYRUN "Would write $File"
        return $true
    }
    if (-not (Backup-DlrFile -File $File)) { return $false }
    try {
        if ($ValidateJson) { $null = $Text | ConvertFrom-Json -ErrorAction Stop }
        Set-Content -LiteralPath $File -Value $Text -Encoding UTF8 -NoNewline -Force -ErrorAction Stop
        # read back
        $back = Get-Content -LiteralPath $File -Raw -Encoding UTF8
        if ($back -ne $Text) { throw 'read-back mismatch' }
        return $true
    } catch {
        Restore-DlrFile -File $File
        Add-Fail "Config edit failed / rolled back for '$File': $($_.Exception.Message)"
        return $false
    }
}

# ---------- generic JSON "download path" key scan (best-effort) ----------
function Set-DlrJsonDownloadPaths {
    param(
        [string]$ConfigPath,
        [string[]]$KeyPatterns
    )
    if (-not (Test-Path -LiteralPath $ConfigPath)) { return $false }
    $txt = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue
    if (-not $txt) { return $false }
    # Only touch real JSON-ish files; .cfg files are often INI or plain text.
    if ($ConfigPath -like '*.json') {
        try { $null = $txt | ConvertFrom-Json -ErrorAction Stop } catch { return $false }
    } else {
        return $false
    }
    $hit = $false
    foreach ($pat in $KeyPatterns) {
        $pattern = '(?i)("' + $pat + '"\s*:\s*")([^"]*)(")'
        $m = [regex]::Match($txt, $pattern)
        if ($m.Success) {
            $old = $m.Groups[2].Value.Replace('\\', '\').Replace('/', '\')
            if ($old -and (Test-Path -LiteralPath $old -PathType Container)) {
                $escaped = $TargetPath.Replace('\', '\\')
                $txt = [regex]::Replace($txt, $pattern, ('$1' + $escaped + '$3'))
                $hit = $true
            }
        }
    }
    if (-not $hit) { return $false }
    return (Write-DlrText -File $ConfigPath -Text $txt -ValidateJson)
}

function Set-DlrAppJsonConfig {
    param(
        [string[]]$BaseDirs,
        [string[]]$KeyPatterns,
        [string]$AppName
    )
    $foundAny = $false
    $updatedAny = $false
    $errorsAny = $false
    foreach ($d in $BaseDirs) {
        if (-not (Test-Path -LiteralPath $d)) { continue }
        $files = @()
        $files += @(Get-ChildItem -LiteralPath $d -Filter '*.json' -Recurse -Depth 2 -ErrorAction SilentlyContinue)
        foreach ($f in $files) {
            $foundAny = $true
            try {
                $r = Set-DlrJsonDownloadPaths -ConfigPath $f.FullName -KeyPatterns $KeyPatterns
                if ($r) {
                    $updatedAny = $true
                    Add-Ok "$AppName : $($f.FullName)"
                }
            } catch {
                $errorsAny = $true
                Add-Fail "$AppName : $($f.FullName) : $($_.Exception.Message)"
            }
        }
    }
    if (-not $foundAny) {
        Write-DlrLog SKIP "$AppName : no JSON config found under the expected locations"
        Add-Manual "${AppName}: not installed, or set the download folder in its Settings UI to $TargetPath"
    } elseif (-not $updatedAny -and -not $errorsAny) {
        Write-DlrLog SKIP "$AppName : config found but no download-path key matched an existing directory"
        Add-Manual "${AppName}: set the download folder in its Settings UI to $TargetPath"
    }
}

# ============================================================================
try {
    Write-Output '===== App Download Path Sync v1.1.0 ====='
    Write-DlrLog INFO ("Mode: " + $(if ($WhatIf) { 'DRY RUN (writes nothing)' } else { 'APPLY' }))

    # ---- validate target (same rules as the core script) ----
    $chk = Test-DlrTargetPath -Path $TargetPath -CurrentPath (Get-DlrCurrentDownloads) -SystemDrive $env:SystemDrive
    foreach ($e in $chk.Errors)   { Write-DlrLog ERROR $e }
    foreach ($w in $chk.Warnings) { Write-DlrLog WARN $w }
    if (-not $chk.Valid) {
        Write-Output '===== SUMMARY ====='
        Write-Output 'Result : FAILED (exit 2) - invalid TargetPath; nothing was changed.'
        exit 2
    }
    $TargetPath = $chk.Normalized
    $esc = $TargetPath.Replace('\', '\\')
    Write-DlrLog OK "Target validated: $TargetPath"
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        Add-Warn "Target folder '$TargetPath' does not exist yet. Run relocate_downloads.ps1 first; app configs will still be pointed at it."
    }

    # ---------- Chromium family ----------
    Write-Output ''
    Write-Output '== Chromium browsers (Chrome / Edge / Brave / Opera / Vivaldi) =='
    if (-not (Test-DlrAppBusy -AppName 'Chromium browser' -ProcessNames @('chrome','msedge','brave','opera','vivaldi'))) {
        $prefs = @()
        if (Test-Path -LiteralPath $env:LOCALAPPDATA) {
            $prefs = @(Get-ChildItem -LiteralPath $env:LOCALAPPDATA -Filter 'Preferences' -Recurse -Depth 5 -ErrorAction SilentlyContinue |
                       Where-Object { $_.FullName -like '*\User Data\*' })
        }
        foreach ($p in $prefs) {
            try {
                $txt = Get-Content -LiteralPath $p.FullName -Raw -Encoding UTF8
                if ($txt -notmatch 'default_directory') {
                    Write-DlrLog SKIP "$($p.FullName) (uses the system Downloads folder already)"
                    continue
                }
                $new = [regex]::Replace($txt, '("default_directory"\s*:\s*")([^"]*)(")', ('$1' + $esc + '$3'))
                if ($new -eq $txt) { Write-DlrLog SKIP "$($p.FullName) (already set to target)"; continue }
                if (Write-DlrText -File $p.FullName -Text $new -ValidateJson) { Add-Ok "Chromium : $($p.FullName)" }
            } catch {
                Add-Fail "Chromium : $($p.FullName) : $($_.Exception.Message)"
            }
        }
        if ($prefs.Count -eq 0) {
            Write-DlrLog SKIP 'No Chromium User Data profiles found'
            Add-Manual 'Chromium browsers: not installed, or already using the system Downloads folder (no change needed)'
        }
    }

    # ---------- Mozilla Firefox ----------
    Write-Output ''
    Write-Output '== Mozilla Firefox =='
    if (-not (Test-DlrAppBusy -AppName 'Firefox' -ProcessNames @('firefox'))) {
        $firefox = @()
        if (Test-Path -LiteralPath $env:APPDATA) {
            $firefox = @(Get-ChildItem -LiteralPath $env:APPDATA -Filter 'prefs.js' -Recurse -Depth 4 -ErrorAction SilentlyContinue |
                         Where-Object { $_.FullName -like '*\Mozilla\Firefox\Profiles\*' })
        }
        foreach ($f in $firefox) {
            try {
                $txt = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
                $dirEsc = $TargetPath.Replace('\', '\\').Replace('"', '\"')
                if ($txt -match 'browser\.download\.folderList') {
                    $txt = $txt -replace 'user_pref\("browser\.download\.folderList",\s*\d+\)', 'user_pref("browser.download.folderList", 2)'
                } else {
                    $txt += "`nuser_pref(`"browser.download.folderList`", 2);"
                }
                if ($txt -match 'browser\.download\.dir') {
                    $txt = $txt -replace 'user_pref\("browser\.download\.dir",\s*"[^"]*"\)', ('user_pref("browser.download.dir", "' + $dirEsc + '");')
                } else {
                    $txt += ("`nuser_pref(`"browser.download.dir`", `"" + $dirEsc + "`");")
                }
                if (Write-DlrText -File $f.FullName -Text $txt) {
                    Add-Ok "Firefox : $($f.FullName)"
                }
            } catch {
                Add-Fail "Firefox : $($f.FullName) : $($_.Exception.Message)"
            }
        }
        if ($firefox.Count -eq 0) {
            Write-DlrLog SKIP 'No Firefox profiles found'
            Add-Manual 'Firefox: not installed, or set it in Settings -> General -> Downloads'
        }
    }

    # ---------- WeChat ----------
    Write-Output ''
    Write-Output '== WeChat (微信) =='
    $wk = 'HKCU:\Software\Tencent\WeChat'
    if (Test-Path -LiteralPath $wk) {
        if ($WhatIf) {
            Write-DlrLog DRYRUN "Would set $wk\FilePath = $TargetPath"
            Add-Ok "WeChat : DRY-RUN would set FilePath = $TargetPath"
        } elseif (Test-DlrAppBusy -AppName 'WeChat' -ProcessNames @('WeChat','Weixin')) {
            # reported by Test-DlrAppBusy
        } else {
            try {
                Set-ItemProperty -LiteralPath $wk -Name 'FilePath' -Value $TargetPath -Type ExpandString -Force -ErrorAction Stop
                $readBack = (Get-ItemProperty -LiteralPath $wk -Name 'FilePath' -ErrorAction Stop).FilePath
                if ($readBack -ine $TargetPath) { throw "read-back mismatch: '$readBack'" }
                Add-Ok "WeChat : HKCU\Software\Tencent\WeChat\FilePath = $TargetPath"
                Add-Manual 'WeChat: also check 设置 -> 文件管理 to confirm the base folder; restart WeChat to apply'
            } catch {
                Add-Fail "WeChat registry update failed: $($_.Exception.Message)"
                Add-Manual "WeChat: 设置 -> 文件管理, set the folder to $TargetPath"
            }
        }
    } else {
        Write-DlrLog SKIP 'WeChat registry key not present'
        Add-Manual "WeChat (微信): 设置 -> 文件管理, set the folder to $TargetPath"
    }

    # ---------- Netdisks ----------
    Write-Output ''
    Write-Output '== Baidu Netdisk (百度网盘) =='
    if (-not (Test-DlrAppBusy -AppName 'Baidu Netdisk' -ProcessNames @('BaiduNetdisk','baidunetdisk','BaiduNetdisk.exe'))) {
        Set-DlrAppJsonConfig -BaseDirs @(
            (Join-Path $env:APPDATA 'Baidu\BaiduNetdisk'),
            (Join-Path $env:LOCALAPPDATA 'Baidu\BaiduNetdisk'),
            (Join-Path $env:APPDATA 'baidu'),
            (Join-Path $env:LOCALAPPDATA 'Baidu')
        ) -KeyPatterns @('downloadPath','downloadpath','download_dir','savePath','savepath','downloaddir','downloadDir','save_dir') -AppName 'Baidu Netdisk'
    }

    Write-Output ''
    Write-Output '== Quark Netdisk (夸克网盘) =='
    if (-not (Test-DlrAppBusy -AppName 'Quark Netdisk' -ProcessNames @('Quark','QuarkCloudDrive','quarkcloud'))) {
        Set-DlrAppJsonConfig -BaseDirs @(
            (Join-Path $env:LOCALAPPDATA 'Quark\QuarkCloudDrive'),
            (Join-Path $env:APPDATA 'Quark\QuarkCloudDrive'),
            (Join-Path $env:LOCALAPPDATA 'Quark'),
            (Join-Path $env:APPDATA 'Quark')
        ) -KeyPatterns @('downloadPath','downloadpath','downloadDir','downloaddir','savePath','savepath','download_dir') -AppName 'Quark Netdisk'
    }

    Write-Output ''
    Write-Output '== Aliyun Drive (阿里云盘) =='
    if (-not (Test-DlrAppBusy -AppName 'Aliyun Drive' -ProcessNames @('aDrive','AliyunDrive','adrive'))) {
        Set-DlrAppJsonConfig -BaseDirs @(
            (Join-Path $env:APPDATA 'AliyunDrive'),
            (Join-Path $env:LOCALAPPDATA 'AliyunDrive'),
            (Join-Path $env:APPDATA 'aDrive'),
            (Join-Path $env:LOCALAPPDATA 'aDrive')
        ) -KeyPatterns @('downloadPath','downloadpath','downloadDir','downloaddir','savePath','savepath','downPath','download_dir') -AppName 'Aliyun Drive'
    }

    # ---------- QQ / TIM ----------
    Write-Output ''
    Write-Output '== QQ / TIM =='
    if (Test-DlrAppBusy -AppName 'QQ / TIM' -ProcessNames @('QQ','TIM','QQ.exe')) {
        # reported by Test-DlrAppBusy
    } else {
        $qqDone = $false
        foreach ($k in @('HKCU:\Software\Tencent\QQ','HKCU:\Software\Tencent\TIM')) {
            if (-not (Test-Path -LiteralPath $k)) { continue }
            try {
                $props = Get-ItemProperty -LiteralPath $k -ErrorAction SilentlyContinue
                foreach ($prop in $props.PSObject.Properties) {
                    if ($prop.Name -notmatch '(?i)FileSave|FilePath|DownLoad|SaveDir|DownDir') { continue }
                    $v = $prop.Value
                    if (-not $v -or -not (Test-Path -LiteralPath $v -PathType Container)) { continue }
                    if ($WhatIf) {
                        Write-DlrLog DRYRUN "Would set $k :: $($prop.Name) = $TargetPath"
                        $qqDone = $true
                        continue
                    }
                    try {
                        Set-ItemProperty -LiteralPath $k -Name $prop.Name -Value $TargetPath -Type String -Force -ErrorAction Stop
                        $readBack = (Get-ItemProperty -LiteralPath $k -Name $prop.Name -ErrorAction Stop).$($prop.Name)
                        if ($readBack -ine $TargetPath) { throw "read-back mismatch: '$readBack'" }
                        Add-Ok "QQ/TIM : $k :: $($prop.Name) = $TargetPath"
                        $qqDone = $true
                    } catch {
                        Add-Fail "QQ/TIM : $k :: $($prop.Name) : $($_.Exception.Message)"
                    }
                }
            } catch {
                Add-Fail "QQ/TIM : could not read $k : $($_.Exception.Message)"
            }
        }
        if (-not $qqDone) {
            Write-DlrLog SKIP 'QQ / TIM stores the receive folder per account; no matching registry value found'
            Add-Manual "QQ / TIM: 设置 -> 文件管理 -> 文件接收目录 -> 更改, set to $TargetPath (default 文档\Tencent Files\<QQ号>\FileRecv)"
        }
    }

    # ---------- Always-manual apps ----------
    Add-Manual 'Thunder (迅雷): 设置 -> 任务默认属性 -> 下载目录'
    Add-Manual 'Telegram: Settings -> Advanced -> Download path'
    Add-Manual 'Steam: 设置 -> 下载 -> 内容库文件夹'
    Add-Manual 'NetEase Cloud Music / QQ Music / other players: 设置 -> 下载目录'
    Add-Manual 'Game launchers (Epic / Ubisoft / Battle.net): Settings -> install / download path'
    Add-Manual 'OneDrive / cloud-sync clients: their own settings (Known Folder redirection may be reverted by the client)'

    # ---------- Summary ----------
    Write-Output ''
    Write-Output '===== SUMMARY / 摘要 ====='
    Write-Output ("Auto-updated ($($script:changed.Count)):")
    foreach ($x in $script:changed) { Write-Output ("  + $x") }
    Write-Output ''
    Write-Output ("Warnings ($($script:warnings.Count)):")
    foreach ($x in $script:warnings) { Write-Output ("  ! $x") }
    Write-Output ''
    Write-Output ("Manual change required ($($script:manual.Count)):")
    foreach ($x in $script:manual) { Write-Output ("  * $x") }
    Write-Output ''
    Write-Output ("Failures ($($script:failed.Count)):")
    foreach ($x in $script:failed) { Write-Output ("  - $x") }
    Write-Output ''
    Write-Output 'NOTE: close each app before its config is edited, then restart it to apply.'
    Write-Output '注意：修改配置前请先关闭对应软件，修改后重启软件生效。'
    if ($WhatIf) {
        Write-Output 'Result : DRY RUN OK - no file, .bak backup or registry value was written.'
        exit 0
    }
    if ($script:failed.Count -gt 0) {
        Write-Output "Result : COMPLETED WITH ERRORS (exit 4) - $($script:failed.Count) item(s) failed; see Failures above."
        exit 4
    }
    Write-Output 'Result : SUCCESS - no automatic update failed. Manual items above still need your action.'
    exit 0
}
catch {
    Write-DlrLog ERROR "Unexpected exception: $($_.Exception.Message)"
    Write-Output ''
    Write-Output '===== SUMMARY ====='
    Write-Output "Result : FAILED (exit 1) - $($_.Exception.Message)"
    exit 1
}
