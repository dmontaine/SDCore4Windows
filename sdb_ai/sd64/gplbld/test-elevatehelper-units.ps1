# test-elevatehelper-units.ps1 - the elevated helper runs only a file SD wrote for it (RELEASE_1.1 191, the Windows reading of Linux F12).
#
#   powershell -ExecutionPolicy Bypass -File test-elevatehelper-units.ps1
#
# FREE CHECK: no elevation, no install.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# WHAT IT DOES.  It takes Test-ScriptRequest out of sd-elevate-helper.ps1 by its syntax tree and RUNS it against a scratch folder standing in for pstmp:
# the right file is accepted; a file of that name elsewhere, a file with another name in the folder, a missing file, a directory and a link are each refused
# and the reason names why.  It then reads the three scripts: only elevate-once.ps1 passes -AnyScript, sd-elevate.ps1 forwards it only when it was given,
# and the helper's default (no switch) takes the strict branch.  Every row prints what it compared.

$ErrorActionPreference = 'Stop'
$gplbld = $PSScriptRoot
$helperPath = Join-Path $gplbld 'sd-elevate-helper.ps1'
$elevPath = Join-Path $gplbld 'sd-elevate.ps1'
$oncePath = Join-Path $gplbld 'elevate-once.ps1'
foreach ($p in $helperPath, $elevPath, $oncePath) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Output "test-elevatehelper-units: CANNOT RUN - $p is not there"; exit 2 }
}

$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { Write-Output ("  [PASS] $name") } else { $script:fail++; Write-Output ("  [FAIL] $name   <- $detail") }
}

$tokens = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($helperPath, [ref]$tokens, [ref]$errs)
Row 'the helper parses with no errors' ($errs.Count -eq 0) ("$($errs.Count) errors")
$fn = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-ScriptRequest' }, $true) | Select-Object -First 1
Row 'Test-ScriptRequest is in the helper (the scan has something to judge)' ($null -ne $fn) 'function not found'
if ($null -eq $fn) { Write-Output "test-elevatehelper-units: FAILED - 1 or more rows"; exit 1 }
. ([scriptblock]::Create($fn.Extent.Text))

$root = Join-Path ([IO.Path]::GetTempPath()) ('elevhelper-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$dir = Join-Path $root 'pstmp'
$other = Join-Path $root 'elsewhere'
$null = New-Item -ItemType Directory -Force -Path $dir, $other
try {
    $good = Join-Path $dir '$PS.TMP.7'
    Set-Content -LiteralPath $good -Value 'exit 0'
    Set-Content -LiteralPath (Join-Path $dir 'evil.ps1') -Value 'exit 0'
    Set-Content -LiteralPath (Join-Path $other '$PS.TMP.7') -Value 'exit 0'
    $null = New-Item -ItemType Directory -Force -Path (Join-Path $dir '$PS.TMP.8')

    $r = Test-ScriptRequest $good $dir
    Row 'a $PS.TMP.<n> file in pstmp is accepted' ($r -eq '') "answered '$r'"
    $r = Test-ScriptRequest (Join-Path $other '$PS.TMP.7') $dir
    Row 'the same name in another folder is refused' ($r -like 'not in *') "answered '$r'"
    $r = Test-ScriptRequest (Join-Path $dir 'evil.ps1') $dir
    Row 'another name in pstmp is refused' ($r -like 'not a*name') "answered '$r'"
    $r = Test-ScriptRequest (Join-Path $dir '$PS.TMP.9') $dir
    Row 'a missing file is refused' ($r -eq 'no such file') "answered '$r'"
    $r = Test-ScriptRequest (Join-Path $dir '$PS.TMP.8') $dir
    Row 'a directory with the right name is refused' ($r -eq 'no such file') "answered '$r'"
    $r = Test-ScriptRequest ($dir + '\..\elsewhere\$PS.TMP.7') $dir
    Row 'a path that climbs out of pstmp is refused' ($r -like 'not in *') "answered '$r'"
    $r = Test-ScriptRequest '' $dir
    Row 'an empty request is refused' ($r -eq 'empty path') "answered '$r'"
    $linkMade = $false
    try {
        $link = Join-Path $dir '$PS.TMP.10'
        New-Item -ItemType SymbolicLink -Path $link -Target $good -ErrorAction Stop | Out-Null
        $linkMade = $true
    } catch { }
    if ($linkMade) {
        $r = Test-ScriptRequest (Join-Path $dir '$PS.TMP.10') $dir
        Row 'a link with the right name is refused' ($r -eq 'a link') "answered '$r'"
    } else {
        Write-Output '  [N/A ] a link with the right name: this shell may not make symbolic links (needs a privilege); the code path is read below'
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

$helper = Get-Content -LiteralPath $helperPath -Raw
$elev = Get-Content -LiteralPath $elevPath -Raw
$once = Get-Content -LiteralPath $oncePath -Raw
Row 'the helper checks every request with Test-ScriptRequest unless -AnyScript' ($helper -match '(?s)if \(\$AnyScript\) \{.*?\} else \{\s*\$why = Test-ScriptRequest \$req \$ScriptDir') 'branch not found'
Row 'the helper tests the link attribute' ($helper -match 'ReparsePoint') 'no ReparsePoint test'
Row 'sd-elevate.ps1 forwards -AnyScript only when it was given' ($elev -match "if \(\`$AnyScript\) \{ \`$args \+= '-AnyScript' \}") 'forwarding line not found'
Row 'elevate-once.ps1 starts its helper with -AnyScript (the developer flow)' (([regex]::Matches($once, '-Start -AnyScript')).Count -ge 2) 'fewer than two Start calls carry it'
$others = Get-ChildItem -LiteralPath $gplbld -Filter '*.ps1' -File | Where-Object { $_.Name -notin 'elevate-once.ps1', 'sd-elevate.ps1', 'sd-elevate-helper.ps1', 'test-elevatehelper-units.ps1' } |
    Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '-AnyScript' }
Row 'no other script asks for -AnyScript' (@($others).Count -eq 0) ('found in: ' + (($others | ForEach-Object { $_.Name }) -join ', '))
$cproc = Get-Content -LiteralPath (Join-Path (Split-Path -Parent $gplbld) 'sdsys\gpl.bp\cproc') -Raw
Row 'an SD session (cproc) never asks for -AnyScript' ($cproc -notmatch 'AnyScript') 'cproc mentions it'

if ($fail -gt 0) { Write-Output "test-elevatehelper-units: FAILED - $fail row(s)"; exit 1 }
Write-Output "test-elevatehelper-units: all rows passed"
exit 0
