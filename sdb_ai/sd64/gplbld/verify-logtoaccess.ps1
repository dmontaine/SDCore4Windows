# verify-logtoaccess.ps1 - AN ADMINISTRATOR'S ACCESS SURVIVES A LOGTO.
# PRE_RELEASE_FIXES.md 91, PROJECT_STATUS.md 5.22.
#
#   powershell -File verify-logtoaccess.ps1 -TestUser sdtub83 -TestPassword '<pw>'
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.  VerifyInstall1.ps1 supplies both arguments from the
# throwaway account it makes for -Run.
#
# ***WHAT 91 WAS, AND WHY THE ROW THAT MATTERS IS "TWICE".***  CPROC's
# logto.authorised answered "may this person ENTER this account" with
# K$ADMINISTRATOR, a PRIVILEGE flag.  CPROC:2825 clears it on the way out of
# SDSYS - the owner's ruling of 16 Aug 2026, "LOGTO ends the elevated session" -
# and LOGIN sets it only on its SDSYS case.  So there were two failures wearing
# one face:
#
#   started elevated   the FIRST logto succeeded and silently disarmed every
#                      later one; the second was refused with 10003.
#   signed in as       the flag was never set at all, so the FIRST logto was
#   themselves         refused.  ***THAT IS THE ONLY THING AN ssh SESSION CAN
#                      DO***, and it is the case the owner reported.
#
# This file measures the second one, because it is the one an unelevated parent
# can reach.  It issues THREE logtos in ONE session and counts arrivals: a
# session that entered once and was then refused scores 1, and the fix scores 2.
# ***A SINGLE SUCCESSFUL LOGTO WOULD NOT HAVE DISTINGUISHED THE FIX FROM THE
# DEFECT*** - the defect's first logto worked too.
#
# ***THE CONTROL IS NOT OPTIONAL: WITHOUT IT THIS FILE CANNOT TELL "THE
# ADMINISTRATOR BYPASS WORKS" FROM "THE GATE IS OPEN TO EVERYBODY".***  The
# test account is a non-administrator, and it must still be refused with 10003
# when it reaches for the caller's account.  If that row ever passes by
# admitting the session, the rows above it mean nothing.
#
# ***WHAT IT DOES NOT COVER, SAID OUT LOUD.***
#
#   the elevated-start path.  Reaching SDSYS goes through elevate('START'),
#       which draws UAC on the secure desktop; §4.0.1 records that a nested
#       elevation has no desktop to render on and fails with "The operation was
#       canceled by the user".  An unelevated suite cannot measure it.  The
#       elevated half of the same defect is therefore UNMEASURED HERE.
#   the tier half's negative case - a Windows administrator holding a STANDARD
#       SD account, who must now land in their own account rather than SDSYS
#       (LOGIN:573).  That needs a SECOND Windows administrator and this file
#       creates nobody.  Also UNMEASURED.
#
# IT CHANGES NOTHING.  No account, no group, no file, no service.  Every logto
# it issues is inside one SD session that ends with OFF.
#
# ***IT ONLY WORKS BECAUSE sdtestuser-admin.ps1 GRANTS THE UNELEVATED PARENT AN
# ACE ON THE TEST ACCOUNT'S DIRECTORY.***  PRE_RELEASE 44: an account directory
# admits SYSTEM, Administrators and its own sdu_ group, and Administrators is
# DENY-ONLY in a UAC-filtered token - so without that ACE the logto would pass
# SD's authorisation and then fail the chdir with 5161.  That is a different
# failure from a refusal and the disqualifier row below is what tells them
# apart; if this file is ever pointed at an account without that ACE, expect
# 5161 and do not read it as 91 regressing.

[CmdletBinding()]
param(
    # ***NOT Mandatory, DELIBERATELY, AND THIS IS NOT LAXITY.***  Mandatory
    # makes PowerShell's parameter BINDER refuse before this file's body runs,
    # so the refusal below would be dead code and the caller would get a
    # PROMPT - which in an unattended suite is a hang, not a message.
    # sdtestuser.ps1's Invoke-SdAsTestUser carries the same note for the same
    # reason, and test-sdtestuser-units.ps1 section 8 runs this script with no
    # account at all to prove the refusal really fires.
    [string] $TestUser     = '',
    [string] $TestPassword = ''
)

$ErrorActionPreference = 'Stop'

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$accts   = Join-Path $env:ProgramData  'SD\sdsys\accounts'
$me      = $env:USERNAME
$meU     = $me.ToUpper()
$targetU = $TestUser.ToUpper()

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check    = $step
        Expected = $expected
        Observed = $got
        Result   = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $step, $expected, $got)
}

# 24 Aug 26 - THE VERDICT LINE.  Kept BYTE-FOR-BYTE IDENTICAL to the other
# copies; test-verdict-units.ps1 asserts that across all of them.
function Write-Verdict($name) {
    $all      = @($script:results)
    $decisive = @($all | Where-Object { $_.Decisive -eq 'yes' })
    $failed   = @($decisive | Where-Object { $_.Result -ne 'PASS' })

    Write-Output ""
    if ($decisive.Count -eq 0) {
        Write-Output ("{0}: FAILED - NO DECISIVE CHECK RAN, so this run proves nothing." -f $name)
        Write-Output ("  {0} row(s) recorded, none of them decisive." -f $all.Count)
        $script:fatal = $true
        return
    }
    if ($failed.Count -gt 0) {
        Write-Output ("{0}: FAILED - {1} of {2} decisive checks failed:" -f $name, $failed.Count, $decisive.Count)
        $failed | ForEach-Object { Write-Output ("    " + $_.Check) }
        $script:fatal = $true
        return
    }
    Write-Output ("{0}: PASSED - {1} of {1} decisive checks passed, {2} row(s) in all." -f
                  $name, $decisive.Count, $all.Count)
}

function Test-Say([string]$text, [string]$pattern) {
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return ([regex]::IsMatch($text, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline))
}

# ------------------------------------------------------------------ Invoke-SD
#
# ***NO "LOGTO SDSYS" PREAMBLE, AND THAT IS THE WHOLE POINT.***  The canonical
# Invoke-SD in the other verifiers opens with LOGTO SDSYS, which would put the
# session in the one account whose privilege hides the defect.  This session
# starts in the caller's OWN account and the logtos under test are the only
# ones issued.
#
# PIPED, NOT REDIRECTED.  Start-Process -RedirectStandardInput hands sd.exe a
# FILE HANDLE and SD answers ":Process terminated" (sysmsg 5020, CPROC:473, the
# K$LOGOUT arm) having run nothing - dated 14 Aug 2026 and re-paid for on 29
# Aug.  A Start-Job with the text on the pipeline is what works, and the
# timeout is what stops a waiting session hanging the suite.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# ***COUNT ARRIVALS, DO NOT MATCH THEM.***  The anchors are verify-doors.ps1's,
# measured against real transcripts on -Run b52 and b53 rather than guessed:
# WHO answers "<number> <ACCOUNT> from <PRIOR>", and the "from" clause appears
# ONLY when the session has logto'd.  A session that merely STARTED in the
# account prints the account and no "from", so the clause is what says the
# session ARRIVED - which is the entire claim being made.
#
# Nothing the caller typed can produce that shape: the echo is ":LOGTO <ACCT>",
# which does not begin with a digit.
function Count-Arrivals([string]$text, [string]$acct) {
    $n = 0
    foreach ($l in ($text -split "`n")) {
        if ($l -match ('^\s*\d+\s+' + [regex]::Escape($acct) + '\s+from\s+\S+')) { $n++ }
    }
    return $n
}

# ***"from" NAMES THE SESSION'S HOME ACCOUNT, NOT THE PREVIOUS HOP - MEASURED
# ON -Run b83, 31 Aug 2026, BY GETTING IT WRONG.***  The first version of this
# file counted the return to the caller's own account with Count-Arrivals and
# scored 0 against an expected 1, because WHO answered a bare "78 DON".  The
# three hops settle which reading is right: hop 1 and hop 3 both said
# "78 SDTUB83 from DON", and hop 2 - whose previous account was SDTUB83 - said
# "78 DON" with no clause at all.  A "previous hop" reading would have printed
# "from SDTUB83" there.  So the clause means "this session's home is X and it is
# somewhere else"; at home there is nothing to print.
#
# verify-doors.ps1 says the same thing in its own words - "a session that had
# simply begun in the account would print the account and no from" - and this
# file was written having read that line.  THE LESSON IS THE ONE ITS HEADER
# ALREADY DREW: look at the output the tool prints on the path you are actually
# measuring, not the one next to it.
#
# END-ANCHORED, WHICH IS RIGHT HERE AND WAS WRONG THERE.  The doors pair was
# caught by anchoring the ARRIVAL shape on end-of-line, which matched only the
# case where the logto had NOT happened.  This counts the AT-HOME shape, and
# end-of-line is exactly what distinguishes it from an arrival.
function Count-AtHome([string]$text, [string]$acct) {
    $n = 0
    foreach ($l in ($text -split "`n")) {
        if ($l -match ('^\s*\d+\s+' + [regex]::Escape($acct) + '\s*$')) { $n++ }
    }
    return $n
}

Write-Output '===== verify-logtoaccess - PRE_RELEASE 91 ====='
Write-Output ''

# ***THE TEST-ACCOUNT REFUSAL COMES FIRST, BEFORE assert-current, AND THE ORDER
# IS THE POINT.***  test-sdtestuser-units.ps1 section 8 runs this script with no
# account to prove the refusal fires, and it must be able to do that on a
# machine with no current install - so nothing that needs one may run above it.
#
# ***THE SHORTCUT THIS REFUSES TO TAKE IS FALLING BACK TO THE INVOKING USER.***
# That user is the administrator, and "an administrator can enter the account"
# is the very claim under test: measuring it against itself would pass always.
if ($TestUser -eq '' -or $TestPassword -eq '') {
    Write-Output 'verify-logtoaccess: no test account was supplied - refusing.'
    Write-Output '  It needs -TestUser and -TestPassword: the throwaway non-administrator'
    Write-Output '  account is BOTH the target the caller was never granted AND the control'
    Write-Output '  that must still be refused.  Falling back to the invoking user would'
    Write-Output '  measure the administrator against himself and pass unconditionally.'
    Write-Output '  VerifyInstall1.ps1 -Run <token> supplies both.'
    exit 2
}

Write-Output '--- the real inputs, echoed before anything is measured ---'
Write-Output ("  sd.exe    : " + $sdExe)
Write-Output ("  caller    : " + $me)
Write-Output ("  target    : " + $TestUser + " (the throwaway non-administrator account)")
Write-Output ("  register  : " + $accts)
Write-Output ''

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-logtoaccess: refusing - the installed tree is not current, see above'
    exit 2
}

if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output ("verify-logtoaccess: " + $sdExe + " is not there - refusing.")
    exit 2
}

# ===================================================================
# THE FOUR PRECONDITIONS.  Each one is a way this file could run to completion
# and prove nothing, so each is a refusal rather than a skipped row.
# ===================================================================

# 1. UNELEVATED.  An elevated session lands in SDSYS (LOGIN:573) and its logtos
#    would exercise a different path entirely.  The property under test is the
#    administrator AS THEMSELVES.
if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-logtoaccess: REFUSING - this is an ELEVATED shell.'
    Write-Output '  An elevated session starts in SDSYS, so its logtos measure the'
    Write-Output '  SDSYS path and not "an administrator as themselves", which is the'
    Write-Output '  whole of 91.  Run it from an ORDINARY prompt.'
    exit 2
}

# 2. THE CALLER MUST BE A WINDOWS ADMINISTRATOR.  IsInRole is false above
#    because the token is FILTERED, which says nothing about the person - and
#    the person is what kernel(K$OS.ADMINISTRATOR,0) asks Windows about.  This
#    asks the machine instead, which is the same question the OS answers.
$inAdmins = $false
try {
    $out = & net localgroup Administrators 2>&1 | Out-String
    $inAdmins = Test-Say $out ('(?im)^\s*(\S+\\)?' + [regex]::Escape($me) + '\s*$')
} catch {
    $inAdmins = $false
}
if (-not $inAdmins) {
    Write-Output ("verify-logtoaccess: REFUSING - " + $me + " is not in Administrators.")
    Write-Output '  Every row below assumes the caller is an administrator; run as one.'
    exit 2
}

# 3. THE CALLER'S OWN REGISTER ENTRY MUST CARRY THE ADMINISTRATOR TIER.
#    5.22 - "an administrator has to be both a windows administrator and an sd
#    administrator" - and !sd_admin_tier reads exactly this field.  A caller
#    whose account is PROGRAMMER would be refused CORRECTLY and this file would
#    report it as 91 regressing.
$myRec  = Join-Path $accts $meU
$myTier = ''
if (Test-Path -LiteralPath $myRec) {
    # An empty file gives Get-Content $null, and a [string] cast does NOT make
    # that '' - so the fields are built defensively rather than indexed blind.
    $fields = @(Get-Content -LiteralPath $myRec)
    if ($fields.Count -ge 5) { $myTier = ([string]$fields[4]).Trim().ToUpper() }
}
Write-Output ("  caller tier: '" + $myTier + "' from " + $myRec)
if ($myTier -ne 'ADMINISTRATOR') {
    Write-Output ("verify-logtoaccess: REFUSING - " + $meU + "'s tier is '" + $myTier + "', not ADMINISTRATOR.")
    Write-Output '  !sd_admin_tier reads ACC$TIER (field 5), so this caller is not an SD'
    Write-Output '  administrator and would be refused CORRECTLY.  That is not 91.'
    Write-Output '  modify.account sets the tier.'
    exit 2
}

# 4. ***THE ONE THAT MAKES THIS A TEST AT ALL: THE CALLER MUST NOT BE GRANTED
#    THE TARGET.***  If don is in sdu_<target>, logto.authorised's group test
#    admits him for the ordinary reason and every row below passes without the
#    administrator path being exercised once.
$grantGroup = 'sdu_' + $TestUser.ToLower()
$granted    = $false
try {
    $out = & net localgroup $grantGroup 2>&1 | Out-String
    $granted = Test-Say $out ('(?im)^\s*(\S+\\)?' + [regex]::Escape($me) + '\s*$')
} catch {
    $granted = $false
}
Write-Output ("  " + $me + " in " + $grantGroup + ": " + $granted + "  (must be False)")
if ($granted) {
    Write-Output ("verify-logtoaccess: REFUSING - " + $me + " IS in " + $grantGroup + ".")
    Write-Output '  The group test would admit the caller for the ordinary reason, so'
    Write-Output '  nothing below would exercise the administrator path.  This run would'
    Write-Output '  pass and prove nothing.'
    exit 2
}
Write-Output ''

# ===================================================================
# THE MEASUREMENT.  Three logtos, one session, starting in the caller's own
# account.  Hop 2 goes home and is NOT decisive - the caller is in sdu_<own>,
# so the group test admits it whatever the administrator path does; it is here
# to make hop 3 a genuine re-entry rather than a logto to where we already are.
# ===================================================================

Write-Output '--- session 1: the administrator, unelevated, in their own account ---'
$cmds = @(
    ('LOGTO ' + $targetU), 'WHO',
    ('LOGTO ' + $meU),     'WHO',
    ('LOGTO ' + $targetU), 'WHO'
)
Write-Output ('  commands: ' + ($cmds -join ' ; '))
$out1 = Invoke-SD $cmds

# RULE 1 OF THE INSTRUMENT SECTION, AND RULE 3 OF THE ANCHORING ONE: the raw
# output is printed EVERY time, not only when a row fails.  A subtle refusal is
# one no conditional print will catch, because the condition is the thing that
# was wrong.
Write-Output '  --- SD said: ---'
foreach ($line in ($out1 -split "`n")) { Write-Output ("  | " + $line.TrimEnd()) }
Write-Output ''

$arrivalsTarget = Count-Arrivals $out1 $targetU
$arrivalsHome   = Count-AtHome   $out1 $meU
$refused10003   = Test-Say $out1 'not allowed in requested account'
$noDir5161      = Test-Say $out1 'Unable to change to new directory'

# ***THE 91 ROW.***  2, not 1, and the difference is the whole defect: the
# session that entered once and was then refused scores 1.  0 is the unelevated
# defect - refused on the first.
Note ('arrivals into ' + $targetU + ' (0 = refused first, 1 = the flag was cleared)') `
     2 $arrivalsTarget $true
Note ('back at home in ' + $meU + ' between them, so hop 3 is a real re-entry') `
     1 $arrivalsHome $true
Note 'SD did NOT say 10003 "not allowed in requested account"' $false $refused10003 $true

# A DISQUALIFIER, NOT A REFUSAL.  5161 is the chdir failing AFTER SD's
# authorisation passed, so a run reporting it has been stopped by the token and
# not by the gate - see the ACE note in the header.
Note 'SD did NOT say 5161 "Unable to change to new directory"' $false $noDir5161 $true

# ===================================================================
# THE CONTROL.  A non-administrator reaching for the caller's account must
# still be refused, or the rows above say nothing about administrators.
# ===================================================================

Write-Output ''
Write-Output '--- session 2: THE CONTROL - the non-administrator test account ---'
. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

$ctlCmds = @(('LOGTO ' + $meU), 'WHO')
Write-Output ('  as ' + $TestUser + ', commands: ' + ($ctlCmds -join ' ; '))
# ***.Out, NOT THE OBJECT.***  Invoke-SdAsTestUser returns
# [pscustomobject]@{ ExitCode; Out; Err } (sdtestuser.ps1:144), not a string.
# The first version passed the object straight to the matchers and the rows
# still passed - PowerShell stringified it to "@{ExitCode=0; Out=...; Err=}"
# and the patterns happened to match inside that.  ***A ROW THAT PASSES THROUGH
# AN ACCIDENTAL COERCION IS ONE THAT WILL STOP PASSING FOR A REASON NOBODY CAN
# SEE***, so the field is named.  Seen in the b83 transcript, which printed the
# whole wrapper.
$out2 = (Invoke-SdAsTestUser -Name $TestUser -Password $TestPassword -Commands $ctlCmds).Out

Write-Output '  --- SD said: ---'
foreach ($line in ($out2 -split "`n")) { Write-Output ("  | " + $line.TrimEnd()) }
Write-Output ''

$ctlRefused  = Test-Say $out2 'not allowed in requested account'
$ctlArrivals = Count-Arrivals $out2 $meU

Note ('control: ' + $TestUser + ' was refused with 10003') $true $ctlRefused $true
Note ('control: ' + $TestUser + ' did NOT arrive in ' + $meU) 0 $ctlArrivals $true

# ===================================================================

Write-Output ''
Write-Output '--- rows ---'
$results | Format-Table -AutoSize | Out-String | Write-Output

Write-Output 'NOT MEASURED HERE, and the header says why: the elevated-start half of 91'
Write-Output '(UAC has no desktop in a nested elevation, §4.0.1) and the tier half''s'
Write-Output 'negative case (needs a second Windows administrator, which this creates not).'

Write-Verdict 'verify-logtoaccess'

if ($fatal) { exit 1 }
exit 0
