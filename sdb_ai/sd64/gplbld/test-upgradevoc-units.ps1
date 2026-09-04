# test-upgradevoc-units.ps1 - drive upgrade-voc.ps1's verdict off disk.
#
# 4 Sep 26 Windows port, PRE_RELEASE_FIXES 70.  upgrade-voc.ps1 runs
# "sd -internal UPDATE.ACCOUNTS ALL" at ssPostInstall on an upgrade, and decides
# from SD's own output whether every registered account's VOC was refreshed.
#
# ***IT EXISTS FOR THE ONE THING NOTHING ELSE CAN REACH.***  The script runs
# HIDDEN inside the installer, on a machine that already has a data tree, and
# its whole job is to tell "the walk refreshed every account" apart from "the
# walk ran and did nothing".  Both print a short block of text and both exit 0
# from sd.exe.  A verdict that got that wrong would ship an upgrade reporting
# success over accounts that cannot type the release's new commands - which is
# the defect 70 was filed for, restored silently by its own fix.  Reaching it
# for real costs a guest, an install and an upgrade; reaching it here costs a
# second.
#
# THE FUNCTION IS LIFTED BY AST, NOT COPIED.  A second copy of the decision
# would pass for ever while the shipped one drifted - this tree has paid for
# that shape more than once - so the file is parsed, Get-VocVerdict is taken
# from it by name, and the test refuses if it is not there.
#
# Unelevated, no SD, no install, no network, no run token.  It writes nothing.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$gplbld = ($PSScriptRoot -replace '\\', '/')
$target = "$gplbld/upgrade-voc.ps1"
Write-Host "test-upgradevoc-units: target $target"

$script:pass = 0
$script:fail = 0
function Check($name, $ok, $detail) {
    if ($ok) { $script:pass++; Write-Host ("  [PASS] {0}" -f $name) }
    else     { $script:fail++; Write-Host ("  [FAIL] {0}{1}" -f $name, $(if ($detail) { " -- $detail" } else { '' })) }
}

Write-Host ''
Write-Host '=== 0. the null case is refused: the function is really there ==='

if (-not (Test-Path -LiteralPath $target)) {
    Check 'upgrade-voc.ps1 exists' $false "not found: $target"
    Write-Host ''
    Write-Host 'test-upgradevoc-units: FAILED - the script under test is missing.'
    exit 1
}

$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tok, [ref]$err)
Check ("upgrade-voc.ps1 parses ({0} error(s))" -f $err.Count) ($err.Count -eq 0) `
      (($err | ForEach-Object { $_.Message }) -join '; ')

$fn = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq 'Get-VocVerdict'
     }, $true)
Check ("Get-VocVerdict was found in the shipped script ({0})" -f $fn.Count) ($fn.Count -eq 1) `
      'it has been renamed or inlined - this test would then be measuring nothing'

if ($fn.Count -ne 1) {
    Write-Host ''
    Write-Host 'test-upgradevoc-units: FAILED - nothing to drive.'
    exit 1
}

# Define it in THIS session from the shipped text.
. ([scriptblock]::Create($fn[0].Extent.Text))
Check 'Get-VocVerdict is callable after the lift' `
      ($null -ne (Get-Command Get-VocVerdict -ErrorAction SilentlyContinue)) $null

# --------------------------------------------------------------------------
# The transcripts.  Written from what SD ACTUALLY printed on guest
# "Windows 11 - SSH no SD - Test D", 4 Sep 2026 - the two "Updating" lines and
# their spelling, including SDSYS's mixed separators, are copied from that run
# rather than invented.  Message 10171 is the release's own new line.

$ok2 = @'
Copying records from NEWVOC to VOC...
Every registered account will have its VOC updated, without asking first.
Updating C:/ProgramData/SD/user_accounts/don/voc
Updating C:\ProgramData\SD\sdsys/voc
2 account(s) had their VOC updated from the shipped vocabulary.
'@

# THE COLLISION THIS TEST FOUND ON ITS FIRST RUN, KEPT AS A ROW OF ITS OWN.
# Message 10170's first draft opened with the word "Updating", so the
# per-account counter counted it too: 2 and 3 on a two-account machine, and a
# good upgrade refused.  Both ends were closed - 10170 reworded, and the
# pattern anchored on the path 5004 always carries - and this fixture keeps the
# OLD wording so the pattern half stays measured even after the rewording.
$ok2Collide = @'
Copying records from NEWVOC to VOC...
Updating the VOC of every registered account, without asking first.
Updating C:/ProgramData/SD/user_accounts/don/voc
Updating C:\ProgramData\SD\sdsys/voc
2 account(s) had their VOC updated from the shipped vocabulary.
'@

Write-Host ''
Write-Host '=== 1. the good run ==='

$v = Get-VocVerdict -Text $ok2 -Registered 2
Check 'a complete two-account walk is code 0'      ($v.Code -eq 0)    ("got $($v.Code): $($v.Why)")
Check 'and its count is read as 2'                 ($v.Total -eq 2)   ("got $($v.Total)")
Check 'and the Updating lines agree'               ($v.Visited -eq 2) ("got $($v.Visited)")

$v = Get-VocVerdict -Text $ok2Collide -Registered 2
Check 'a non-5004 line beginning "Updating" is not counted' ($v.Visited -eq 2) `
      ("got $($v.Visited) - the per-account pattern is matching another message")
Check 'so that run is still code 0'                ($v.Code -eq 0) ("got $($v.Code): $($v.Why)")

# ONE ACCOUNT IS A REAL CASE, NOT AN EDGE ONE: a machine whose only account is
# SDSYS.  "1 record" wording is a classic off-by-one for a regex written
# against a plural.
$ok1 = @'
Copying records from NEWVOC to VOC...
Updating C:\ProgramData\SD\sdsys/voc
1 account(s) had their VOC updated from the shipped vocabulary.
'@
$v = Get-VocVerdict -Text $ok1 -Registered 1
Check 'a one-account walk is code 0'               ($v.Code -eq 0)  ("got $($v.Code): $($v.Why)")
Check 'and its count is read as 1'                 ($v.Total -eq 1) ("got $($v.Total)")

Write-Host ''
Write-Host '=== 2. THE CASE THIS FILE EXISTS FOR: a walk that did nothing ==='

# The register was opened, no account was written, and SD exited 0.  Before
# message 10171 existed there was NOTHING in this transcript to tell it from a
# complete run, which is why the count is a product change and not just a
# tighter regex here.
$empty = @'
Copying records from NEWVOC to VOC...
Updating the VOC of every registered account, without asking first.
0 account(s) had their VOC updated from the shipped vocabulary.
'@
$v = Get-VocVerdict -Text $empty -Registered 3
Check 'a zero-account walk is NOT a pass'          ($v.Code -ne 0)  'an empty upgrade would be reported as a good one'
Check 'and it says which zero it means'            ($v.Why -match 'visited NO account') ("got: $($v.Why)")

# The count line missing altogether - the walk stopped part way, or the message
# is not installed on this machine.  Silence must not read as success.
$noCount = @'
Copying records from NEWVOC to VOC...
Updating C:\ProgramData\SD\sdsys/voc
'@
$v = Get-VocVerdict -Text $noCount -Registered 2
Check 'no count line at all is NOT a pass'         ($v.Code -ne 0)  'a truncated walk would be reported as a good one'
Check 'and Total stays -1 rather than 0'           ($v.Total -eq -1) ("got $($v.Total)")

# Nothing at all.  sd.exe produced no output - the shape a broken pipe or a
# process that died before LOGIN gives.
$v = Get-VocVerdict -Text '' -Registered 2
Check 'empty output is NOT a pass'                 ($v.Code -ne 0)  'silence would be reported as a good run'

Write-Host ''
Write-Host '=== 3. the two readings must agree ==='

# A count that outruns the Updating lines.  Either the message is wrong or the
# walk is; the script is not entitled to pick one.
$mismatch = @'
Updating C:\ProgramData\SD\sdsys/voc
7 account(s) had their VOC updated from the shipped vocabulary.
'@
$v = Get-VocVerdict -Text $mismatch -Registered 7
Check 'count 7 against 1 Updating line is NOT a pass' ($v.Code -ne 0) 'the two readings disagreed and it passed anyway'
Check 'and it names both numbers'                     ($v.Why -match '7' -and $v.Why -match '1') ("got: $($v.Why)")

Write-Host ''
Write-Host '=== 4. every refusal SD can print ==='

# THE ANCHOR IS THE REFUSAL WORDING, AND EACH OF THESE ALSO CARRIES A PLAUSIBLE
# SUCCESS LINE.  That is the point: a transcript where the positive pattern
# matches AND a disqualifier appears is not a pass either, which is the trap
# PROJECT_STATUS records as "a check that anchors on a string the failure also
# carries".
$refusals = @(
    @{ Name = 'not SDSYS or not an administrator (10172)'
       Text = "Copying records from NEWVOC to VOC...`nCannot update every registered account from here, so NOTHING has been updated.`n2 account(s) had their VOC updated from the shipped vocabulary."
       Code = 1 },
    @{ Name = 'a trailing token was refused (10173)'
       Text = "UPDATE.ACCOUNTS does not take 'EVERYTHING', so nothing has been changed."
       Code = 1 },
    @{ Name = 'the account register would not open (2200)'
       Text = "Copying records from NEWVOC to VOC...`nCannot open accounts register`n1 account(s) had their VOC updated from the shipped vocabulary."
       Code = 1 },
    @{ Name = 'the verb is not in SDSYS - a tree older than the mechanism'
       Text = "UPDATE.ACCOUNTS is not in your VOC"
       Code = 4 },
    @{ Name = 'the session was not privileged'
       Text = "Command requires administrator privileges"
       Code = 1 }
)
foreach ($r in $refusals) {
    $v = Get-VocVerdict -Text $r.Text -Registered 2
    Check ("refusal is caught: {0}" -f $r.Name) ($v.Code -eq $r.Code) `
          ("expected code $($r.Code), got $($v.Code): $($v.Why)")
}

# AND THE ONE THAT MUST BE ITS OWN ANSWER RATHER THAN A GENERIC FAILURE: an
# installer that says "rerun me" over a tree no rerun can fix wastes the
# reader's afternoon.  sd.iss branches on 4 specifically.
$v = Get-VocVerdict -Text 'UPDATE.ACCOUNTS is not in your VOC' -Registered 2
Check 'the missing verb is code 4, not the generic 1' ($v.Code -eq 4) ("got $($v.Code)")
Check 'and it says the tree predates the verb'        ($v.Why -match 'predates') ("got: $($v.Why)")

Write-Host ''
Write-Host '=== 5. the shape of the return value ==='

# PowerShell collapses a one-element array to a scalar and an empty one to
# $null on the way out of a function, so "no accounts" and "could not read"
# would arrive as the same thing.  A hashtable cannot do that, and this asserts
# it stays one.
$v = Get-VocVerdict -Text $ok2 -Registered 2
Check 'the verdict is a hashtable'   ($v -is [hashtable]) ("got " + $v.GetType().Name)
foreach ($k in @('Code', 'Total', 'Visited', 'Why')) {
    Check ("it carries {0}" -f $k) ($v.ContainsKey($k)) $null
}

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("test-upgradevoc-units: PASSED - {0} of {0} checks passed." -f $script:pass)
    exit 0
}
Write-Host ("test-upgradevoc-units: FAILED - {0} of {1} checks failed." -f $script:fail, ($script:pass + $script:fail))
exit 1
