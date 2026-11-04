<#
.SYNOPSIS
    Point common Windows applications' default download directory at a new path.

.DESCRIPTION
    Updates the download location in the most common desktop apps so they follow
    the relocated Downloads folder:
      * Chromium browsers (Chrome, Edge, Brave, Opera, Vivaldi ...) - Preferences JSON
      * Mozilla Firefox                                        - prefs.js
      * WeChat (微信)                                          - registry best-effort
      * Baidu Netdisk (百度网盘)                               - JSON config best-effort
      * Quark Netdisk (夸克网盘)                               - JSON config best-effort
      * Aliyun Drive (阿里云盘)                                - JSON config best-effort
      * QQ / TIM                                               - registry + manual
    Apps that cannot be edited safely (Thunder, Telegram, Steam, game launchers ...)
    are reported for manual change via their UI. Each editable file/config is backed
    up to <file>.bak before modification.

.PARAMETER TargetPath
    The new download directory, e.g. "F:\Downloads". Must match what was passed to
    relocate_downloads.ps1.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TargetPath
)

$ErrorActionPreference = 'Stop'
$TargetPath = $TargetPath.TrimEnd('\')
$esc = $TargetPath.Replace('\', '\\')   # JSON/JS escaped backslashes
$changed = @()
$manual  = @()

function Backup-File($file) {
    $bak = $file + '.bak'
    if (-not (Test-Path $bak)) { Copy-Item $file $bak -Force }
}

# ---------- helper: generic JSON "download path" key scan (best-effort) ----------
# Scans a config file for keys whose name matches a download/path pattern and whose
# current value is an existing directory; replaces the value with the new target.
function Set-JsonDownloadPaths {
    param(
        [string]$ConfigPath,
        [string[]]$KeyPatterns
    )
    if (-not (Test-Path $ConfigPath)) { return $false }
    $txt = Get-Content $ConfigPath -Raw -Encoding UTF8
    $hit = $false
    foreach ($pat in $KeyPatterns) {
        $pattern = '(?i)("' + $pat + '"\s*:\s*")([^"]*)(")'
        $m = [regex]::Match($txt, $pattern)
        if ($m.Success) {
            $old = $m.Groups[2].Value.Replace('\\', '\').Replace('/', '\')
            if ($old -and (Test-Path $old -PathType Container)) {
                $txt = $txt -replace $pattern, ("`$1" + $esc + "`$3")
                $hit = $true
            }
        }
    }
    if ($hit) {
        Backup-File $ConfigPath
        Set-Content -Path $ConfigPath -Value $txt -Encoding UTF8 -NoNewline
        return $true
    }
    return $false
}

# Scan a whole config directory (any *.json / *.cfg) for download-path keys.
function Set-AppJsonConfig {
    param(
        [string[]]$BaseDirs,
        [string[]]$KeyPatterns,
        [string]$AppName
    )
    $foundAny = $false
    $updatedAny = $false
    foreach ($d in $BaseDirs) {
        if (-not (Test-Path $d)) { continue }
        $files = @()
        $files += Get-ChildItem -Path $d -Filter '*.json' -Recurse -Depth 2 -ErrorAction SilentlyContinue
        $files += Get-ChildItem -Path $d -Filter '*.cfg'  -Recurse -Depth 2 -ErrorAction SilentlyContinue
        foreach ($f in $files) {
            $foundAny = $true
            if (Set-JsonDownloadPaths -ConfigPath $f.FullName -KeyPatterns $KeyPatterns) {
                $updatedAny = $true
                $changed += ($AppName + ": " + $f.FullName)
                Write-Output ("  [ok]   " + $f.FullName)
            }
        }
    }
    if (-not $foundAny) {
        Write-Output "  (no config files found under expected locations)"
        $manual += ($AppName + ": set the download path manually in its settings UI to " + $TargetPath)
    } elseif (-not $updatedAny) {
        Write-Output ("  (config found but no download-path key matched existing dir; set manually to " + $TargetPath + ")")
        $manual += ($AppName + ": set the download path manually in its settings UI to " + $TargetPath)
    }
}

# ---------- Chromium family ----------
Write-Output "== Chromium browsers (Chrome/Edge/Brave/Opera/Vivaldi) =="
$prefs = @()
if (Test-Path $env:LOCALAPPDATA) {
    $prefs = Get-ChildItem -Path $env:LOCALAPPDATA -Filter 'Preferences' -Recurse -Depth 5 -ErrorAction SilentlyContinue |
             Where-Object { $_.FullName -like '*\User Data\*' }
}
foreach ($p in $prefs) {
    try {
        $txt = Get-Content $p.FullName -Raw -Encoding UTF8
        if ($txt -notmatch 'default_directory') {
            Write-Output ("  [skip] " + $p.FullName + " (uses system Downloads by default)")
            continue
        }
        Backup-File $p.FullName
        $new = $txt -replace '("default_directory"\s*:\s*")([^"]*)(")', "`$1$esc`$3"
        Set-Content -Path $p.FullName -Value $new -Encoding UTF8 -NoNewline
        $changed += ("Chromium: " + $p.FullName)
        Write-Output ("  [ok]   " + $p.FullName)
    } catch {
        Write-Output ("  [warn] failed " + $p.FullName + " : " + $_.Exception.Message)
    }
}
if ($prefs.Count -eq 0) { Write-Output "  (no Chromium User Data profiles found)" }

# ---------- Mozilla Firefox ----------
Write-Output "== Mozilla Firefox =="
$firefox = @()
if (Test-Path $env:APPDATA) {
    $firefox = Get-ChildItem -Path $env:APPDATA -Filter 'prefs.js' -Recurse -Depth 4 -ErrorAction SilentlyContinue |
               Where-Object { $_.FullName -like '*\Mozilla\Firefox\Profiles\*' }
}
foreach ($f in $firefox) {
    try {
        Backup-File $f.FullName
        $txt = Get-Content $f.FullName -Raw -Encoding UTF8
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
        Set-Content -Path $f.FullName -Value $txt -Encoding UTF8 -NoNewline
        $changed += ("Firefox: " + $f.FullName)
        Write-Output ("  [ok]   " + $f.FullName)
    } catch {
        Write-Output ("  [warn] failed " + $f.FullName + " : " + $_.Exception.Message)
    }
}
if ($firefox.Count -eq 0) { Write-Output "  (no Firefox profiles found)" }

# ---------- WeChat (微信) best-effort ----------
Write-Output "== WeChat (微信) =="
$wk = 'HKCU:\Software\Tencent\WeChat'
try {
    if (Test-Path $wk) {
        Set-ItemProperty $wk -Name 'FilePath' -Value $TargetPath -Type ExpandString -Force -ErrorAction Stop
        $changed += ("WeChat FilePath registry -> " + $TargetPath)
        Write-Output ("  [ok]   set HKCU\Software\Tencent\WeChat\FilePath = " + $TargetPath)
        Write-Output "         (WeChat download subfolders live under this base; restart WeChat to apply)"
    } else {
        Write-Output "  (WeChat registry key not present)"
        $manual += 'WeChat (微信): Settings -> 文件管理, set the folder to ' + $TargetPath
    }
} catch {
    Write-Output ("  [warn] " + $_.Exception.Message)
}

# ---------- Baidu Netdisk (百度网盘) ----------
Write-Output "== Baidu Netdisk (百度网盘) =="
$baiduDirs = @(
    Join-Path $env:APPDATA    'Baidu\BaiduNetdisk'
    Join-Path $env:LOCALAPPDATA 'Baidu\BaiduNetdisk'
)
Set-AppJsonConfig -BaseDirs $baiduDirs -KeyPatterns @('downloadPath','downloadpath','download_dir','savePath','savepath','downloaddir') -AppName 'Baidu Netdisk'

# ---------- Quark Netdisk (夸克网盘) ----------
Write-Output "== Quark Netdisk (夸克网盘) =="
$quarkDirs = @(
    Join-Path $env:LOCALAPPDATA 'Quark\QuarkCloudDrive'
    Join-Path $env:APPDATA      'Quark\QuarkCloudDrive'
    Join-Path $env:LOCALAPPDATA 'Quark'
)
Set-AppJsonConfig -BaseDirs $quarkDirs -KeyPatterns @('downloadPath','downloadpath','downloadDir','downloaddir','savePath','savepath') -AppName 'Quark Netdisk'

# ---------- Aliyun Drive (阿里云盘) ----------
Write-Output "== Aliyun Drive (阿里云盘) =="
$aliDirs = @(
    Join-Path $env:APPDATA        'AliyunDrive'
    Join-Path $env:LOCALAPPDATA   'AliyunDrive'
)
Set-AppJsonConfig -BaseDirs $aliDirs -KeyPatterns @('downloadPath','downloadpath','downloadDir','downloaddir','savePath','savepath','downPath') -AppName 'Aliyun Drive'

# ---------- QQ / TIM best-effort (per-account receive folder) ----------
Write-Output "== QQ / TIM =="
$qqDone = $false
$qqKeys = @('HKCU:\Software\Tencent\QQ')
foreach ($k in $qqKeys) {
    if (-not (Test-Path $k)) { continue }
    try {
        $props = Get-ItemProperty $k -ErrorAction SilentlyContinue
        $props.PSObject.Properties | Where-Object { $_.Name -match '(?i)FileSave|FilePath|DownLoad|SaveDir|DownDir' } | ForEach-Object {
            $v = $_.Value
            if ($v -and (Test-Path $v -PathType Container)) {
                try {
                    Set-ItemProperty $k -Name $_.Name -Value $TargetPath -Type String -Force
                    $changed += ("QQ: registry " + $_.Name + " -> " + $TargetPath)
                    $qqDone = $true
                    Write-Output ("  [ok]   " + $k + " : " + $_.Name + " = " + $TargetPath)
                } catch { Write-Output ("  [warn] " + $_.Exception.Message) }
            }
        }
    } catch { Write-Output ("  [warn] " + $_.Exception.Message) }
}
if (-not $qqDone) {
    Write-Output "  (QQ stores the receive folder per-account; registry key not matched)"
    $manual += ('QQ / TIM: 设置 -> 文件管理 -> 文件接收目录 -> 更改, set to ' + $TargetPath + ' (default is 文档\Tencent Files\<QQ号>\FileRecv)')
}

# ---------- Remaining manual apps ----------
$manual += 'Thunder (迅雷): Settings -> 任务默认属性 -> 下载目录'
$manual += 'Telegram: Settings -> Advanced -> Download path'
$manual += 'Steam: Settings -> 下载 -> 内容库文件夹'
$manual += 'NetEase / QQ Music etc.: Settings -> 下载目录'
$manual += 'Game launchers (Epic / Ubisoft / Battle.net): Settings -> install/download path'

Write-Output ""
Write-Output "==== SUMMARY / 摘要 ===="
Write-Output ("Auto-updated (" + $changed.Count + "):")
$changed | ForEach-Object { Write-Output ("  - " + $_) }
Write-Output ""
Write-Output "Manual change required / 需手动修改:"
$manual | ForEach-Object { Write-Output ("  * " + $_) }
Write-Output ""
Write-Output "NOTE: close each app before its config is edited, then restart it to apply."
Write-Output "注意：修改配置前请先关闭对应软件，修改后重启软件生效。"

