# test-sdpath-units.ps1 - drive sd-path.ps1's three pure functions.
#
#   C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\test-sdpath-units.ps1
#
# ORDINARY UNELEVATED PROMPT.  No install, no elevation, no run token, no
# registry.  Exit 0 all passed, 1 something failed, 2 could not set up.
#
# ***WHY IT EXISTS.***  sd-path.ps1 edits the machine's system PATH, which is
# the one setting on this list that breaks everything on the box if it is got
# wrong, and it cannot be rehearsed on the real value.  So every rule lives in
# three PURE functions and this lifts them out of the file by AST - the
# technique test-verdict-units.ps1 uses - and drives them against synthetic
# strings.  Lifting rather than copying is the point: a copy would drift, and a
# drifting test of a PATH editor is worse than no test.
#
# NOT SHIPPED - it must be on assert-current.ps1's $neverShipped list.

$ErrorActionPreference = 'Stop'

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $here 'sd-path.ps1'

Write-Host "test-sdpath-units: subject $subject"
if (-not (Test-Path -LiteralPath $subject)) {
    Write-Host 'test-sdpath-units: subject not found.'
    exit 2
}

# --- lift the functions ----------------------------------------------------
$tok = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($subject, [ref]$tok, [ref]$errs)
if ($errs.Count -gt 0) {
    Write-Host "test-sdpath-units: subject has $($errs.Count) parse error(s); nothing lifted."
    exit 2
}

$wanted = @('Test-DirOnPath', 'Get-PathAfterAdd', 'Get-PathAfterRemove')
$lifted = 0
foreach ($name in $wanted) {
    $fn = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true))
    if ($fn.Count -ne 1) {
        Write-Host "test-sdpath-units: expected exactly one $name, found $($fn.Count)."
        exit 2
    }
    . ([scriptblock]::Create($fn[0].Extent.Text))
    Write-Host ("  lifted {0} ({1} chars)" -f $name, $fn[0].Extent.Text.Length)
    $lifted++
}

# REFUSE THE NULL CASE: a run that lifted nothing must not report 0 failures.
if ($lifted -ne $wanted.Count) {
    Write-Host 'test-sdpath-units: VOID - not every function was lifted.'
    exit 2
}
Write-Host ''

$script:pass = 0
$script:fail = 0
function Row {
    param([string]$Case, $Got, $Want)
    $ok = ($Got -ceq $Want)          # -ceq: a case change is still a change.
    if ($ok) { $script:pass++ } else { $script:fail++ }
    $tag = if ($ok) { '[PASS]' } else { '[FAIL]' }
    Write-Host ("  {0} {1}" -f $tag, $Case)
    if (-not $ok) {
        Write-Host ("         got  '{0}'" -f $Got)
        Write-Host ("         want '{0}'" -f $Want)
    }
}

$SD = 'C:\Program Files\SD\usr\bin'

Write-Host '=== 1. Test-DirOnPath - the prefix trap ==='
Row 'present, middle'        (Test-DirOnPath "C:\a;$SD;C:\b" $SD) $true
Row 'present, last'          (Test-DirOnPath "C:\a;$SD" $SD)      $true
Row 'present, only'          (Test-DirOnPath "$SD" $SD)           $true
Row 'absent'                 (Test-DirOnPath 'C:\a;C:\b' $SD)     $false
# The whole reason for padding with ';' either side.
Row 'a LONGER entry that starts with ours is not a match' `
    (Test-DirOnPath 'C:\a;C:\Program Files\SD\usr\binaries;C:\b' $SD) $false
Row 'a SHORTER prefix of ours is not a match' `
    (Test-DirOnPath 'C:\a;C:\Program Files\SD\usr;C:\b' $SD)         $false
Row 'case-insensitive, as PATH is' `
    (Test-DirOnPath 'C:\a;c:\program files\sd\usr\bin;C:\b' $SD)     $true

Write-Host ''
Write-Host '=== 2. Get-PathAfterAdd ==='
Row 'appends at the end'     (Get-PathAfterAdd 'C:\a;C:\b' $SD)  "C:\a;C:\b;$SD"
Row 'does not extend a dangling separator' `
    (Get-PathAfterAdd 'C:\a;C:\b;' $SD) "C:\a;C:\b;$SD"
Row 'collapses a whole trailing run before appending' `
    (Get-PathAfterAdd 'C:\a;C:\b;;;;' $SD) "C:\a;C:\b;$SD"

Write-Host ''
Write-Host '=== 3. Get-PathAfterRemove ==='
Row 'from the middle, rejoins cleanly' `
    (Get-PathAfterRemove "C:\a;$SD;C:\b" $SD) 'C:\a;C:\b'
Row 'from the end, leaves NO dangling separator' `
    (Get-PathAfterRemove "C:\a;C:\b;$SD" $SD) 'C:\a;C:\b'
Row 'from the front' `
    (Get-PathAfterRemove "$SD;C:\a;C:\b" $SD) 'C:\a;C:\b'
Row 'the only entry' (Get-PathAfterRemove "$SD" $SD) ''
Row 'absent -> unchanged' (Get-PathAfterRemove 'C:\a;C:\b' $SD) 'C:\a;C:\b'
Row 'surviving entries keep their CASE' `
    (Get-PathAfterRemove "C:\WINDOWS\System32;$SD" $SD) 'C:\WINDOWS\System32'
Row 'matches case-insensitively while rebuilding from the original' `
    (Get-PathAfterRemove "C:\a;c:\program files\sd\USR\bin;C:\b" $SD) 'C:\a;C:\b'
Row 'a longer entry starting with ours is NOT removed' `
    (Get-PathAfterRemove "C:\a;C:\Program Files\SD\usr\binaries;$SD" $SD) `
    'C:\a;C:\Program Files\SD\usr\binaries'

Write-Host ''
Write-Host '=== 4. THE HISTORICAL CASE - 16 Aug 2026, 23 empty entries in 30 ==='
# Inno always appends, so ours is last; the old code kept the separator before
# it and started the tail after the one following, so each cycle left one more
# empty.  Rebuilt here: six real entries then a run of empties, ours last.
$grown = 'C:\WINDOWS\system32;C:\WINDOWS;C:\WINDOWS\System32\Wbem;' +
         'C:\Program Files\Git\cmd;C:\Program Files\WinGet\Links;C:\tools' +
         (';' * 23) + ";$SD"
$cleared = Get-PathAfterRemove $grown $SD
$realAfter = @(($cleared -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Row 'the whole accumulated run is cleared, not just our slot' `
    ($cleared -match ';;') $false
Row 'and all six real entries survive' $realAfter.Count 6
Row 'in their original order' ($realAfter -join ',') `
    'C:\WINDOWS\system32,C:\WINDOWS,C:\WINDOWS\System32\Wbem,C:\Program Files\Git\cmd,C:\Program Files\WinGet\Links,C:\tools'
# It can only ever delete separators, never an entry - the property that makes
# it safe on a PATH we do not own.
$realBefore = @(($grown -split ';') | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
Row 'exactly one real entry disappeared' ($realBefore.Count - $realAfter.Count) 1

Write-Host ''
Write-Host '=== 5. add-then-remove is an identity on the real-world value ==='
$orig = 'C:\WINDOWS\system32;C:\WINDOWS;%SystemRoot%\System32\Wbem;C:\Program Files\Git\cmd'
$rt   = Get-PathAfterRemove (Get-PathAfterAdd $orig $SD) $SD
Row 'round-trip returns the original exactly' $rt $orig
Row 'and %SystemRoot% is still a variable, not expanded' ($rt -match '%SystemRoot%') $true

Write-Host ''
if ($script:fail -gt 0) {
    Write-Host "test-sdpath-units: FAILED - $($script:pass) passed, $($script:fail) failed."
    exit 1
}
Write-Host "test-sdpath-units: PASSED - $($script:pass) of $($script:pass) checks passed."
exit 0
