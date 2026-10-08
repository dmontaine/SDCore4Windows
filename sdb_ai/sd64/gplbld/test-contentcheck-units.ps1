# test-contentcheck-units.ps1 - unit tests for assert-current.ps1's Find-InstalledContentDiffs.
#
# 8 Oct 2026.  The function exists because the time and name checks in assert-current printed "the
# installed tree matches source" over 23 Solo message files whose installed bytes were the old ones: they
# had been edited after the cycle staged its tree and before the install finished, so each was older than
# the install (not "newer") and present (not "deleted").  ***THE POINT OF THE FIXTURES IS THE POSITIVE
# CASE***, exactly as test-deletioncheck-units.ps1 says of its own: on a current tree the check finds
# nothing, so "found nothing" is what a working check and a dead one both say.  Only a planted difference
# that must be found BY NAME tells them apart.  The positive fixture here is the real failure's shape: a
# file whose source mtime is OLDER than the installed copy and whose bytes differ.
#
# THE FUNCTION IS LIFTED OUT OF assert-current.ps1 BY AST, NOT COPIED (a test carrying its own copy passes
# for ever while the shipped one rots).  Unelevated, no SD, no install; it touches nothing but %TEMP%.
#
# Exit 0 every row passed, 1 a row failed, 2 the function could not be loaded.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$src = ($PSScriptRoot -replace '\\', '/') + '/assert-current.ps1'
if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "assert-current.ps1 not found beside this script ($src)"
    exit 2
}
$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tok, [ref]$err)
if ($err.Count -gt 0) {
    Write-Host "assert-current.ps1 has $($err.Count) parse error(s) - fix those first:"
    $err | ForEach-Object { Write-Host ("  {0} line {1}" -f $_.Message, $_.Extent.StartLineNumber) }
    exit 2
}
$fn = $ast.FindAll({ param($x)
    $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $x.Name -eq 'Find-InstalledContentDiffs' }, $true)
if ($fn.Count -ne 1) {
    Write-Host "expected exactly 1 'Find-InstalledContentDiffs' in assert-current.ps1, found $($fn.Count)"
    exit 2
}
. ([scriptblock]::Create($fn[0].Extent.Text))
Write-Host "lifted Find-InstalledContentDiffs from $src"
Write-Host ''

$script:fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  PASS  $name" }
    else { Write-Host "  FAIL  $name  $detail"; $script:fail++ }
}

$root = Join-Path $env:TEMP ('contentcheck-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
function New-Fixture([string]$name) {
    $d = Join-Path $root $name
    foreach ($sub in 'src\messages', 'inst\messages', 'src\syscom\sub', 'inst\syscom\sub') {
        New-Item -ItemType Directory -Force -Path (Join-Path $d $sub) | Out-Null
    }
    return @{ Src = (Join-Path $d 'src'); Inst = (Join-Path $d 'inst') }
}
function Put([string]$path, [string]$text) { [IO.File]::WriteAllBytes($path, [Text.Encoding]::ASCII.GetBytes($text)) }

try {
    Write-Host '== identical trees: nothing found, and it says how many it looked at'
    $f = New-Fixture 'same'
    Put (Join-Path $f.Src 'messages\13016') 'Syntax: restore.account archive'
    Put (Join-Path $f.Inst 'messages\13016') 'Syntax: restore.account archive'
    Put (Join-Path $f.Src 'syscom\sub\x.h') 'abc'
    Put (Join-Path $f.Inst 'syscom\sub\x.h') 'abc'
    $r = Find-InstalledContentDiffs -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('messages', 'syscom')
    Check 'identical: no difference found' ($r.Differ.Count -eq 0 -and $r.Missing.Count -eq 0) ("differ=" + ($r.Differ -join ',') + " missing=" + ($r.Missing -join ','))
    Check 'identical: both files were looked at (the null-case count)' ($r.Checked -eq 2) ("Checked=" + $r.Checked)

    Write-Host ''
    Write-Host '== THE REAL FAILURE: same size, differs only by case, source mtime OLDER than the installed copy'
    $f = New-Fixture 'case'
    Put (Join-Path $f.Src 'messages\13016') 'Syntax: restore.account archive'
    Put (Join-Path $f.Inst 'messages\13016') 'Syntax: RESTORE.ACCOUNT archive'
    (Get-Item (Join-Path $f.Src 'messages\13016')).LastWriteTime  = (Get-Date).AddMinutes(-30)
    (Get-Item (Join-Path $f.Inst 'messages\13016')).LastWriteTime = (Get-Date)
    Put (Join-Path $f.Src 'messages\5102') 'unchanged'
    Put (Join-Path $f.Inst 'messages\5102') 'unchanged'
    $r = Find-InstalledContentDiffs -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('messages')
    Check 'the case-only difference is FOUND, by name' (($r.Differ.Count -eq 1) -and ($r.Differ[0] -eq 'messages\13016')) ("differ=" + ($r.Differ -join ','))
    Check 'the unchanged neighbour is not reported' (@($r.Differ | Where-Object { $_ -like '*5102' }).Count -eq 0) ''
    Check 'both files were looked at' ($r.Checked -eq 2) ("Checked=" + $r.Checked)

    Write-Host ''
    Write-Host '== a different length is found too, in a subdirectory'
    $f = New-Fixture 'len'
    Put (Join-Path $f.Src 'syscom\sub\x.h') 'abcdef'
    Put (Join-Path $f.Inst 'syscom\sub\x.h') 'abc'
    $r = Find-InstalledContentDiffs -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('syscom')
    Check 'the longer source is found' (($r.Differ.Count -eq 1) -and ($r.Differ[0] -eq 'syscom\sub\x.h')) ("differ=" + ($r.Differ -join ','))

    Write-Host ''
    Write-Host '== a file added to source and absent from the install is MISSING'
    $f = New-Fixture 'missing'
    Put (Join-Path $f.Src 'messages\10172') 'new'
    $r = Find-InstalledContentDiffs -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('messages')
    Check 'the absent file is reported as missing, by name' (($r.Missing.Count -eq 1) -and ($r.Missing[0] -eq 'messages\10172')) ("missing=" + ($r.Missing -join ','))
    Check 'and it is not reported as differing' ($r.Differ.Count -eq 0) ''

    Write-Host ''
    Write-Host '== the null case: a directory missing on either side measures nothing, and says so'
    $f = New-Fixture 'null'
    $r = Find-InstalledContentDiffs -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('nosuchdir', 'messages')
    Check 'empty directories: Checked is 0' ($r.Checked -eq 0) ("Checked=" + $r.Checked)
    Check 'a directory that is not there is skipped, not an error' ($r.Differ.Count -eq 0 -and $r.Missing.Count -eq 0) ''
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fail -eq 0) { Write-Host 'test-contentcheck-units: every row passed'; exit 0 }
Write-Host ("test-contentcheck-units: {0} row(s) FAILED" -f $script:fail)
exit 1
