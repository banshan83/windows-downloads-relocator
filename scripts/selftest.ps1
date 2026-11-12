<#
.SYNOPSIS
    Automated, side-effect-free regression tests for the Downloads Relocator skill.

.DESCRIPTION
    Run this before publishing a new version. It checks packaging, encodings,
    PowerShell syntax, the v1.0.0 "WhatIf parameter collision" regression,
    frontmatter/version consistency, every file path referenced by the docs,
    the pure helper functions, a full robocopy migration loop in a temp folder,
    and - crucially - that -DryRun really writes ZERO files.

    It never touches the real Downloads folder, the registry, or user configs.

.PARAMETER SkillRoot
    Root of the skill. Defaults to the parent of this script's folder.

.PARAMETER IncludeAppScript
    Also dry-run set_app_downloads.ps1 (slower: scans %LOCALAPPDATA% for browser
    profiles). Off by default.

.PARAMETER DistributionMode
    Use when running from a distribution zip (e.g. downloaded from SkillHub).
    The zip deliberately excludes repo-only dotfiles such as .gitignore, so
    that assertion is skipped. Default mode (source checkout / git clone)
    still checks all 68 assertions.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/selftest.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File scripts/selftest.ps1 -DistributionMode

.EXIT CODES
    0  all tests passed
    1  one or more tests failed

.NOTES
    Windows PowerShell 5.1+. Author: banshan83 | v1.1.0
#>
[CmdletBinding()]
param(
    [string]$SkillRoot,
    [switch]$IncludeAppScript,
    [switch]$DistributionMode
)

$ErrorActionPreference = 'Continue'
if (-not $SkillRoot) { $SkillRoot = Split-Path -Path $PSScriptRoot -Parent }

$pass = New-Object System.Collections.Generic.List[string]
$fail = New-Object System.Collections.Generic.List[string]
$skip = New-Object System.Collections.Generic.List[string]

function Assert-True {
    param([string]$Name, [bool]$Condition, [string]$Detail = '')
    if ($Condition) {
        $script:pass.Add($Name)
        Write-Output ("[PASS] $Name" + $(if ($Detail) { " -- $Detail" } else { '' }))
    } else {
        $script:fail.Add($Name)
        Write-Output ("[FAIL] $Name" + $(if ($Detail) { " -- $Detail" } else { '' }))
    }
}
function Assert-False { param([string]$Name, [bool]$Condition, [string]$Detail = '') Assert-True -Name $Name -Condition (-not $Condition) -Detail $Detail }

Write-Output '===== windows-downloads-relocator SELFTEST ====='
Write-Output ("SkillRoot: $SkillRoot")
Write-Output ("PowerShell: $($PSVersionTable.PSVersion)")
Write-Output ''

# ---------------------------------------------------------------- 1. files ---
Write-Output '--- 1. Packaging ---'
$required = @(
    'SKILL.md', 'README.md', 'CHANGELOG.md', 'LICENSE',
    'scripts\relocate_downloads.ps1', 'scripts\set_app_downloads.ps1',
    'scripts\restore_downloads.ps1', 'scripts\selftest.ps1',
    'scripts\lib\DownloadsCommon.ps1',
    'references\registry-reference.md', 'references\app-paths.md', 'references\FAQ.md',
    'assets\desktop.ini.template', 'assets\example-before-after.svg', 'assets\icon.png'
)
# .gitignore is a repo-only dotfile. SkillHub rejects hidden files, so the
# distribution zip never contains it. Only the source checkout must have it.
if (-not $DistributionMode) { $required += '.gitignore' }
foreach ($r in $required) {
    Assert-True -Name "file exists: $r" -Condition (Test-Path -LiteralPath (Join-Path $SkillRoot $r))
}
Write-Output ''

# ------------------------------------------------------------- 2. encodings ---
Write-Output '--- 2. Encodings ---'
$psFiles = @(Get-ChildItem -LiteralPath (Join-Path $SkillRoot 'scripts') -Filter '*.ps1' -Recurse)
foreach ($f in $psFiles) {
    $bytes = [IO.File]::ReadAllBytes($f.FullName)
    $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
    Assert-True -Name "UTF-8 BOM on $($f.Name)" -Condition $hasBom -Detail 'PS 5.1 mis-parses non-ASCII without a BOM'
}
$skillBytes = [IO.File]::ReadAllBytes((Join-Path $SkillRoot 'SKILL.md'))
$skillNoBom = -not ($skillBytes[0] -eq 0xEF -and $skillBytes[1] -eq 0xBB -and $skillBytes[2] -eq 0xBF)
Assert-True -Name 'SKILL.md has NO BOM' -Condition $skillNoBom -Detail 'package_skill.py rejects a BOM'
Write-Output ''

# ---------------------------------------------------------------- 3. syntax ---
Write-Output '--- 3. PowerShell syntax ---'
foreach ($f in $psFiles) {
    $tok = $null; $errs = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tok, [ref]$errs) | Out-Null
    Assert-True -Name "parses cleanly: $($f.Name)" -Condition ($errs.Count -eq 0) -Detail (($errs | ForEach-Object { $_.Message }) -join ' | ')
}
Write-Output ''

# ------------------------------------------ 4. v1.0.0 regression: WhatIf -----
Write-Output '--- 4. Regression: WhatIf parameter collision (v1.0.0 bug) ---'
$mainText = Get-Content -LiteralPath (Join-Path $SkillRoot 'scripts\relocate_downloads.ps1') -Raw -Encoding UTF8
$collision = ($mainText -match 'SupportsShouldProcess\s*=\s*\$true') -and ($mainText -match '\[switch\]\s*\$WhatIf')
Assert-False -Name 'no CmdletBinding(SupportsShouldProcess)+custom $WhatIf collision' -Condition $collision -Detail 'v1.0.0 failed with "parameter WhatIf defined multiple times" on EVERY invocation'
Assert-True -Name 'DryRun alias declared' -Condition ($mainText -match "Alias\('DryRun'\)")
Assert-True -Name 'file-migration toggle is a switch (works with -File)' -Condition ($mainText -match '\[switch\]\$NoMoveExisting') -Detail 'a [bool]$MoveExisting cannot be set from powershell.exe -File'
$appText = Get-Content -LiteralPath (Join-Path $SkillRoot 'scripts\set_app_downloads.ps1') -Raw -Encoding UTF8
Assert-False -Name 'app script has no same collision' -Condition (($appText -match 'SupportsShouldProcess\s*=\s*\$true') -and ($appText -match '\[switch\]\s*\$WhatIf'))
Assert-True -Name 'app script uses $script: scoped result lists' -Condition ($appText -match '\$script:changed' -and $appText -match '\$script:failed')
Write-Output ''

# ------------------------------------------------------------ 5. frontmatter ---
Write-Output '--- 5. SKILL.md frontmatter / versions ---'
$skillText = Get-Content -LiteralPath (Join-Path $SkillRoot 'SKILL.md') -Raw -Encoding UTF8
$fm = [regex]::Match($skillText, '(?s)\A---\s*\r?\n(.*?)\r?\n---')
Assert-True -Name 'frontmatter block present' -Condition $fm.Success
if ($fm.Success) {
    $body = $fm.Groups[1].Value
    Assert-True -Name 'name: present' -Condition ($body -match '(?m)^name:\s*\S+')
    $descLine = @($body -split "\r?\n" | Where-Object { $_ -match '^description:' } | Select-Object -First 1)
    $descOk = $false
    if ($descLine.Count -eq 1) {
        $line = [string]$descLine[0]
        $descOk = ($line -match '^description:\s*".*"\s*$')
        Assert-False -Name 'description has no < or >' -Condition ($line -match '[<>]') -Detail 'package_skill.py rejects angle brackets'
    }
    Assert-True -Name 'description: quoted single line' -Condition $descOk
    $ver = [regex]::Match($body, '(?m)^version:\s*([\d.]+)')
    Assert-True -Name 'version: present' -Condition $ver.Success
    $version = if ($ver.Success) { $ver.Groups[1].Value } else { '' }
}
$readme = Get-Content -LiteralPath (Join-Path $SkillRoot 'README.md') -Raw -Encoding UTF8
Assert-True -Name 'README badge matches SKILL.md version' -Condition ($readme -match "version-$([regex]::Escape($version))-")
$changelog = Get-Content -LiteralPath (Join-Path $SkillRoot 'CHANGELOG.md') -Raw -Encoding UTF8
Assert-True -Name 'CHANGELOG has an entry for the current version' -Condition ($changelog -match "\[$([regex]::Escape($version))\]")
Write-Output ''

# --------------------------------------------------------------- 6. docs ------
Write-Output '--- 6. Documented assets actually ship ---'
$docText = $skillText + "`n" + $readme
$refs = @([regex]::Matches($docText, '(?<![A-Za-z0-9_])((?:scripts|references|assets)/[A-Za-z0-9_\-./\\]+\.[A-Za-z0-9]+)') |
          ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
foreach ($r in $refs) {
    $p = Join-Path $SkillRoot ($r -replace '/', '\')
    Assert-True -Name "documented path exists: $r" -Condition (Test-Path -LiteralPath $p)
}
$dit = Get-Content -LiteralPath (Join-Path $SkillRoot 'assets\desktop.ini.template') -Raw -Encoding UTF8
Assert-True -Name 'desktop.ini template has CLSID2 + LocalizedResourceName + IconResource' -Condition ($dit -match 'CLSID2=' -and $dit -match 'LocalizedResourceName=' -and $dit -match 'IconResource=')
Write-Output ''

# ------------------------------------------------------------- 7. helpers -----
Write-Output '--- 7. Pure helper unit tests ---'
$common = Join-Path $SkillRoot 'scripts\lib\DownloadsCommon.ps1'
. $common
$k = Get-DlrConstants
Assert-True -Name 'Downloads GUID correct' -Condition ($k.DownloadsGuid -eq '{374DE290-123F-4565-9164-39C4925E467B}')
Assert-True -Name 'Local Downloads GUID correct' -Condition ($k.LocalDownloadsGuid -eq '{7D83EE9B-2244-4E70-B1F5-5393042AF1E4}')
Assert-True -Name "Test-DlrBareRoot('F:\') = true" -Condition (Test-DlrBareRoot 'F:\')
Assert-False -Name "Test-DlrBareRoot('F:\Downloads') = false" -Condition (Test-DlrBareRoot 'F:\Downloads')
Assert-False -Name 'bare drive root rejected' -Condition ((Test-DlrTargetPath -Path 'F:\').Valid)
Assert-False -Name 'UNC path rejected' -Condition ((Test-DlrTargetPath -Path '\\server\share\Downloads').Valid)
Assert-False -Name 'relative path rejected' -Condition ((Test-DlrTargetPath -Path 'Downloads').Valid)
Assert-False -Name 'nested target rejected' -Condition ((Test-DlrTargetPath -Path 'C:\Users\me\Downloads\sub' -CurrentPath 'C:\Users\me\Downloads').Valid)
Write-Output ''

# ------------------------------------------------- 8. migration loop ----------
Write-Output '--- 8. Migration + verification loop (temp folder only) ---'
$tmp = Join-Path $env:TEMP ('dlr-selftest-' + [guid]::NewGuid().ToString('N'))
$src = Join-Path $tmp 'source'
$dst = Join-Path $tmp 'dest'
$bak = Join-Path $tmp 'backups'
try {
    New-Item -ItemType Directory -Path $src -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $src 'nested') -Force | Out-Null
    [IO.File]::WriteAllText((Join-Path $src 'a.txt'), 'alpha')
    [IO.File]::WriteAllText((Join-Path $src 'nested\b.txt'), 'bravo-bravo')
    $before = Get-DlrFolderSnapshot -Path $src
    Assert-True -Name 'snapshot finds 2 files' -Condition ($before.Files.Count -eq 2) -Detail "found $($before.Files.Count)"
    & robocopy.exe $src $dst /E /MOVE /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1 | Out-Null
    $cmp = Compare-DlrSnapshot -Before $before -Destination $dst
    Assert-True -Name 'all files verified after robocopy /MOVE' -Condition $cmp.Ok -Detail "missing=$($cmp.Missing.Count) mismatch=$($cmp.SizeMismatch.Count)"
    Assert-True -Name 'verification counts every source file' -Condition ($cmp.Checked -eq 2)

    # --- 9. DryRun is strictly read-only -------------------------------------
    Write-Output ''
    Write-Output '--- 9. DryRun writes NOTHING (the v1.0.0 bug) ---'
    $dryTarget = Join-Path $tmp 'dry-dest'
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SkillRoot 'scripts\relocate_downloads.ps1') `
              -TargetPath $dryTarget -BackupDir $bak -NoMoveExisting -NoExplorerRestart -DryRun 2>&1
    $dryExit = $LASTEXITCODE
    $dryText = ($out | Out-String)
    Assert-True -Name 'relocate_downloads.ps1 -DryRun exits 0' -Condition ($dryExit -eq 0) -Detail "exit=$dryExit; tail=$((($out | Select-Object -Last 3) -join ' | '))"
    Assert-True -Name 'DryRun reports DRY RUN OK' -Condition ($dryText -match 'DRY RUN OK')
    Assert-True -Name 'DryRun created no destination folder' -Condition (-not (Test-Path -LiteralPath $dryTarget))
    Assert-True -Name 'DryRun wrote no .reg / manifest backups' -Condition (-not (Test-Path -LiteralPath $bak))
    Assert-True -Name 'DryRun did not create desktop.ini' -Condition (-not (Test-Path -LiteralPath (Join-Path $dryTarget 'desktop.ini')))

    if ($IncludeAppScript) {
        Write-Output ''
        Write-Output '--- 9b. set_app_downloads.ps1 -DryRun ---'
        $out2 = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $SkillRoot 'scripts\set_app_downloads.ps1') `
                  -TargetPath $dryTarget -DryRun 2>&1
        Assert-True -Name 'set_app_downloads.ps1 -DryRun exits 0' -Condition ($LASTEXITCODE -eq 0)
    } else {
        $skip.Add('set_app_downloads.ps1 DryRun (use -IncludeAppScript to enable)')
    }
}
catch {
    Assert-True -Name 'temp-folder tests completed without exception' -Condition $false -Detail $_.Exception.Message
}
finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
Write-Output ''

# -------------------------------------------------------------- summary ------
Write-Output '===== SELFTEST SUMMARY ====='
Write-Output ("PASS: $($pass.Count)   FAIL: $($fail.Count)   SKIP: $($skip.Count)")
foreach ($s in $skip) { Write-Output ("  ~ $s") }
foreach ($f in $fail) { Write-Output ("  - $f") }
if ($fail.Count -gt 0) {
    Write-Output 'Result: FAILED (exit 1)'
    exit 1
}
Write-Output 'Result: ALL TESTS PASSED (exit 0)'
exit 0
