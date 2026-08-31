# test-suiteonly-units.ps1 - unit tests for suite-only.ps1's Select-SuiteSteps,
# the -Only filter both VerifyInstall runners use to pick steps.
#
# 30 Aug 26 Windows port.  Written WITH the filter, not after it, because the
# thing that can go wrong here is the thing nobody sees: a selection that quietly
# matches no steps, so the runner runs nothing and reports every step it ran
# exited 0.  That is the null case CLAUDE.md's instrument rule names outright.
#
# ***THE POINT OF THE FIXTURE IS THE POSITIVE CASE.***  Every honest call of this
# filter on a good name returns "some steps", and so does a filter that has quietly
# stopped filtering at all.  The only way to tell them apart is to require that a
# narrowing request actually NARROWS - by count, against a fixture whose size is
# known here - which is what the "removes" checks below do.
#
# Unelevated, no SD, no install, no network, no run token.  It writes nothing.
# NOT a verifier: it makes no claim about the installed tree, so it is not named
# verify-* and belongs in neither post-cycle runner.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# Forward slashes so the path carries no backslash, per CLAUDE.md's inline rule.
$src = ($PSScriptRoot -replace '\\', '/') + '/suite-only.ps1'
Write-Host "test-suiteonly-units: subject $src"
if (-not (Test-Path -LiteralPath $src)) {
    Write-Host 'suite-only.ps1 not found beside this script'
    exit 2
}

$tok = $null; $err = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tok, [ref]$err)
if ($err.Count -gt 0) {
    Write-Host "suite-only.ps1 has $($err.Count) parse error(s) - fix those first:"
    $err | ForEach-Object { Write-Host ("  {0} line {1}" -f $_.Message, $_.Extent.StartLineNumber) }
    exit 2
}

. $src

if (-not (Get-Command Select-SuiteSteps -ErrorAction SilentlyContinue)) {
    Write-Host 'suite-only.ps1 parsed but defined no Select-SuiteSteps - an embedded BOM does exactly this.'
    exit 2
}

$pass = 0; $fail = 0
function Check($name, $expected, $got) {
    if ("$expected" -ceq "$got") {
        $script:pass++; Write-Host ("  [PASS] {0}: {1}" -f $name, $got)
    } else {
        $script:fail++; Write-Host ("  [FAIL] {0}: expected '{1}', got '{2}'" -f $name, $expected, $got)
    }
}

# ---------------------------------------------------------------------------
# THE LEAK CONTROL, FIRST, AND IT IS NOT THEORETICAL.  A dot-sourced file's
# FILE-SCOPE Set-StrictMode binds the caller, so suite-only.ps1 putting strict
# mode at the top would change how both runners behave everywhere else in them -
# a trap this tree has already recorded.  This process is deliberately lax: if
# referencing an undefined variable now throws, the strict mode leaked.
$leaked = $false
try   { $null = $no_such_variable_here_31415 }
catch { $leaked = $true }
Write-Host ''
Write-Host '=== 0. dot-sourcing must not impose StrictMode on the caller ==='
Check 'strict mode did NOT leak into this scope' 'False' $leaked

# ---------------------------------------------------------------------------
# The fixture.  Five steps, in a deliberate order that is NOT alphabetical for
# the pair used by the ordering check below.
$fixture = @(
    @{ Name = 'verify-alpha.ps1';   P = @{} },
    @{ Name = 'verify-bravo.ps1';   P = @{} },
    @{ Name = 'verify-charlie.ps1'; P = @{} },
    @{ Name = 'verify-delta.ps1';   P = @{} },
    @{ Name = 'verify-echo.ps1';    P = @{} }
)
$N = $fixture.Count
Write-Host ''
Write-Host "=== the fixture is $N steps: $((($fixture | ForEach-Object { $_.Name }) -join ', ')) ==="

function Names($r) { return (($r.Steps | ForEach-Object { $_.Name }) -join ',') }

Write-Host ''
Write-Host '=== 1. no -Only is a pass-through, and is NOT partial ==='
foreach ($empty in @('', '   ', $null)) {
    $r = Select-SuiteSteps -Steps $fixture -Only $empty -Runner 'T'
    Check ("empty -Only ('" + $empty + "') keeps every step") $N $r.Steps.Count
    Check ("empty -Only ('" + $empty + "') is not partial")   'False' $r.Partial
    Check ("empty -Only ('" + $empty + "') has no error")     'True'  ($r.Error -eq '')
}

Write-Host ''
Write-Host '=== 2. a good name selects exactly it, and IS partial ==='
foreach ($form in @('verify-bravo.ps1', 'verify-bravo', 'VERIFY-BRAVO', 'Verify-Bravo.PS1')) {
    $r = Select-SuiteSteps -Steps $fixture -Only $form -Runner 'T'
    Check ("'$form' selects one step")        1 $r.Steps.Count
    Check ("'$form' selects the right one")   'verify-bravo.ps1' (Names $r)
    Check ("'$form' is marked partial")       'True' $r.Partial
    Check ("'$form' has no error")            'True' ($r.Error -eq '')
}

Write-Host ''
Write-Host '=== 3. THE POSITIVE CONTROL: a narrowing request must actually narrow ==='
# A filter that had stopped filtering would return all five here and still look
# healthy to every check that only asks "did I get steps back".
$r = Select-SuiteSteps -Steps $fixture -Only 'verify-bravo' -Runner 'T'
Check 'one name returns FEWER steps than the fixture' 'True' ($r.Steps.Count -lt $N)
Check 'and exactly one fewer than four'                1    $r.Steps.Count

Write-Host ''
Write-Host '=== 4. order is the RUNNER''S, not the order the names were typed ==='
# verify-credacl-must-be-first is a real ordering constraint in VerifyInstall1,
# so a -Only that honoured the typed order would silently break it.
$r = Select-SuiteSteps -Steps $fixture -Only 'verify-delta,verify-bravo' -Runner 'T'
Check 'two names, typed reversed, come back in fixture order' 'verify-bravo.ps1,verify-delta.ps1' (Names $r)
$r = Select-SuiteSteps -Steps $fixture -Only 'verify-delta;verify-bravo' -Runner 'T'
Check 'a semicolon separates too'                            'verify-bravo.ps1,verify-delta.ps1' (Names $r)
$r = Select-SuiteSteps -Steps $fixture -Only ' verify-delta , verify-bravo ' -Runner 'T'
Check 'surrounding spaces are trimmed'                       'verify-bravo.ps1,verify-delta.ps1' (Names $r)

Write-Host ''
Write-Host '=== 5. duplicates collapse rather than tripping the count assertion ==='
$r = Select-SuiteSteps -Steps $fixture -Only 'verify-bravo,verify-bravo.ps1' -Runner 'T'
Check 'the same step named twice is one step' 1     $r.Steps.Count
Check 'and is not an error'                   'True' ($r.Error -eq '')

Write-Host ''
Write-Host '=== 6. selecting everything is not "partial" ==='
$all = (($fixture | ForEach-Object { $_.Name }) -join ',')
$r = Select-SuiteSteps -Steps $fixture -Only $all -Runner 'T'
Check 'naming all five keeps all five' $N     $r.Steps.Count
Check 'naming all five is NOT partial'  'False' $r.Partial

Write-Host ''
Write-Host '=== 7. THE REFUSALS - an unknown name must never select nothing quietly ==='
$r = Select-SuiteSteps -Steps $fixture -Only 'verify-nope' -Runner 'T'
Check 'an unknown name is an error'            'True' ($r.Error -ne '')
Check 'the error names the offending step'     'True' ($r.Error -match 'verify-nope\.ps1')
Check 'the error lists the valid names'        'True' ($r.Error -match 'verify-charlie\.ps1')
Check 'and it says nothing was run'            'True' ($r.Error -match 'Nothing was run')

# MIXED MUST REFUSE, NOT PARTIALLY SUCCEED.  Running the half that matched would
# be the worst outcome: a green run that silently skipped what the operator
# actually asked for.
$r = Select-SuiteSteps -Steps $fixture -Only 'verify-bravo,verify-nope' -Runner 'T'
Check 'one good name plus one bad is still an error' 'True' ($r.Error -ne '')
Check 'and the good one is NOT run on its own'       'True' ($r.Error -match 'verify-nope\.ps1')

foreach ($junk in @(',', ' ; , ', ';;')) {
    $r = Select-SuiteSteps -Steps $fixture -Only $junk -Runner 'T'
    Check ("separators only ('$junk') is an error") 'True' ($r.Error -ne '')
    Check ("separators only ('$junk') says so")     'True' ($r.Error -match 'names no step at all')
}

Write-Host ''
Write-Host '=== 8. the runner name appears in every refusal, so the log says WHO refused ==='
$r = Select-SuiteSteps -Steps $fixture -Only 'verify-nope' -Runner 'VerifyInstall2'
Check 'the refusal is attributed' 'True' ($r.Error -match '^VerifyInstall2:')

Write-Host ''
if ($fail -gt 0) {
    Write-Host ("test-suiteonly-units: FAILED - {0} passed, {1} failed" -f $pass, $fail)
    exit 1
}
Write-Host ("test-suiteonly-units: PASSED - {0} of {0} checks passed." -f $pass)
exit 0
