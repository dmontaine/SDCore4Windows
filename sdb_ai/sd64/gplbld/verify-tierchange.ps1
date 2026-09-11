# verify-tierchange.ps1 - the three rows of PRE_RELEASE 19 that verify-tiers.ps1
# section 6 does not cover and an elevated piped session CAN reach: the required
# access keyword, what leaves with ADMINISTRATOR, and the "left alone" count.
#
#   powershell -File verify-tierchange.ps1 -Prefix sdtc1
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# ***WHAT THIS IS AND IS NOT.***  PRE_RELEASE 19's table lists seven things the
# tier change needs proved.  verify-tiers.ps1 section 6 covers the round trip,
# the write-once rule, the VOC across a release update and the null case, and
# says in its own output that it does NOT cover the three doors.  ***THE THREE
# DOORS ARE STILL NOT COVERED HERE EITHER*** - they need an UNELEVATED session,
# an ssh login and an API pair, and that is PRE_RELEASE 38, not this file.  What
# is left, and what this measures, is the middle three:
#
#   the required keyword   leaving ADMINISTRATOR without naming a route is
#                          REFUSED with 10111 and changes nothing (MODIFYA:216)
#   what leaves with it    Windows Administrators membership AND the os.users
#                          record, the two things the tier granted (tier.os.remove)
#   the "left alone" count a VOC record that no longer matches what a tier build
#                          would have written is KEPT, not deleted, and counted
#                          in 10113's third number (tier.del.one)
#
# ***THE ARITHMETIC IS THE INSTRUMENT, AND NOT ONE COUNT IS TYPED.***  This is
# the trap PROJECT_STATUS records as "a constant typed into a label drifts from
# the value beside it": verify-tiers printed "the 21 administration verbs are
# still ABSENT ... 20 20 PASS" because 21 was typed and 20 was measured.  So
# nothing here knows that ADMINISTRATOR is 416 or PROGRAMMER 396.  It measures
# the account's own VOC three times - as PROGRAMMER, as ADMINISTRATOR, and as
# PROGRAMMER again - and asserts the relations between them:
#
#   A > P                  the promotion added verbs at all (the null case: a
#                          tier change that moved nothing must FAIL, not pass)
#   D = A + added - removed  the count moved exactly as 10113 reported it
#   ***D = P + kept***     THE DECISIVE ONE.  A clean downgrade would land back
#                          on P.  It lands on P plus exactly the records that
#                          were kept - so the edited record is provably still
#                          there AND provably the only difference.
#
# HOW A RECORD IS MADE TO DIFFER, WITHOUT AN EDITOR.  tier.del.one removes an id
# only if what is in the account's VOC is byte-identical to what a tier build
# would write; anything else is kept.  ".S <name> 1" saves the previous command
# as an S-type sentence under that name, which no tier build would ever produce.
# It prompts 5045 to overwrite, which is answered - that prompt is EXPECTED and
# is not the argument-prompt trap, because the argument was given.
#
# RUN IT ELEVATED.  MODIFY.ACCOUNT is kernel(K$ADMINISTRATOR,-1), seeded from
# IsElevated() at process start, so an unelevated session stops at 2001 before
# the parser ever runs - and CREATE.ACCOUNT and LOGTO SDSYS need it too.
#
# ***-Prefix IS REQUIRED AND MUST BE FRESH.***  One account is derived from it.
#
# WHAT IT LEAVES BEHIND.  Nothing, if it finishes.  ***THE ACCOUNT IS A WINDOWS
# ADMINISTRATOR FOR PART OF THE RUN***, which is the point of the test, so the
# downgrade is asserted before the delete and the litter section reads Windows
# rather than trusting what DELETE.ACCOUNT said.
#
# 11 Sep 26 - IT NOW MAKES TWO ACCOUNTS, <Prefix>a and <Prefix>b.  Section 6
# (RELEASE_1.1_FIXES.md 13) needs a STANDARD account to promote, and the first
# one is created PROGRAMMER and is a Windows administrator by section 2.  Both
# are deleted and both are read back from disk in the litter check.

[CmdletBinding()]
param([string]$Prefix = '')

$ErrorActionPreference = 'Stop'

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys = Join-Path $env:ProgramData  'SD\sdsys'
$accts = Join-Path $sdsys 'accounts'
$osusr = Join-Path $sdsys 'os.users'
# 11 Sep 26 - section 6 reads the shipped record it expects to be copied.
$newvoc = Join-Path $sdsys 'newvoc'

# The verb whose VOC record is made to differ.  Any of TIER.ADD.ADMINISTRATOR's
# twenty would do; this one is named nowhere else in the run, so a stray match
# cannot be mistaken for it.  It is never executed - only saved over.
$adminVerb = 'list.locks'

# 11 Sep 26 - SECTION 6's SUBJECT.  RELEASE_1.1_FIXES.md 13.
#
# It must satisfy two things at once, and both were measured on 11 Sep 26
# rather than assumed: it is in newvoc/TIER.OMIT.STANDARD, so a STANDARD
# account does NOT have it and the promotion to PROGRAMMER must ADD it; and
# its field 1 in newvoc is a DESCRIPTION rather than a bare type letter, which
# is the only shape RELEASE_1.1 1 could damage.  41 of that list's 42 ids
# qualify; "basic" is one of them.
#
# ***THE EXPECTED TEXT IS NEVER TYPED HERE.***  It is read from the shipped
# newvoc record at run time and compared with what the account ended up with,
# because a constant typed into this file is a second place for the value to
# live - the trap verify-tiers records as "a label carrying a constant drifts
# from the value beside it".
$upgradeVerb = 'basic'

$results = New-Object System.Collections.ArrayList
$fatal   = $false
$lastSD  = ''

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

# 24 Aug 26 - THE VERDICT LINE.  Kept BYTE-FOR-BYTE IDENTICAL to the copies in
# verify-createaccount.ps1, verify-cmdaudit.ps1, verify-sshonly.ps1,
# verify-vocverbs.ps1 and verify-acctmsgs.ps1, and test-verdict-units.ps1
# asserts that across all of them.  If one changes, change all of them.
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

# --------------------------------------------------------------- text helpers
#
# CASE-SENSITIVE and silent, for the reasons verify-vocverbs.ps1 gives: a
# function that both prints and returns hands the caller its own narration
# joined to what it measured.
function Test-Say([string]$text, [string]$pattern) {
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return ([regex]::IsMatch($text, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline))
}

# ***A POSITIVE MATCH IS NOT A PASS IF A REFUSAL MATCHED TOO.***  MODIFYA's
# refusals name the account as readily as its successes do, so every tier
# assertion goes through this: the success wording must be present AND every
# disqualifier absent.  CLAUDE.md, "a check must anchor on the SUCCESS wording".
$tierBad = @('Unable to change the tier', 'is already', 'cannot suspend',
             'no record of the tier', 'is a group account')
function Get-Said([string]$text, [string]$good) {
    if (-not (Test-Say $text $good)) { return 'not said' }
    foreach ($b in $tierBad) { if (Test-Say $text ([regex]::Escape($b))) { return ('refused: ' + $b) } }
    return 'said'
}

function Get-VocCount([string]$text) {
    if ($text -match '(\d+)\s+record\(s\) counted') { return [int]$Matches[1] }
    return -1
}

# 10113 is "VOC: %1 records added, %2 removed, %3 left alone".  Returned as a
# record so the three numbers can be asserted against the counts, not read.
function Get-VocDelta([string]$text) {
    if ($text -match 'VOC:\s*(\d+)\s+records added,\s*(\d+)\s+removed,\s*(\d+)\s+left alone') {
        return [pscustomobject]@{ Added=[int]$Matches[1]; Removed=[int]$Matches[2]
                                  Kept=[int]$Matches[3]; Found=$true }
    }
    return [pscustomobject]@{ Added=-1; Removed=-1; Kept=-1; Found=$false }
}

function Get-AccountTier($name) {
    $rec = Join-Path $accts $name.ToUpper()
    if (-not (Test-Path -LiteralPath $rec)) { return '<no ACCOUNTS record>' }
    $f = Get-Content -LiteralPath $rec
    if ($f.Count -lt 5) { return '<blank>' }
    if ([string]::IsNullOrEmpty($f[4])) { return '<blank>' }
    return $f[4]
}

# BY SID, not by the name "Administrators", which is localised.  MODIFYA itself
# uses S-1-5-32-544 for the same reason.
function Test-LocalAdmin([string]$name) {
    try {
        $g = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction Stop
        $m = Get-LocalGroupMember -Group $g.Name -ErrorAction Stop
        foreach ($x in $m) { if ($x.Name -match ('\\' + [regex]::Escape($name) + '$')) { return $true } }
        return $false
    } catch { return $false }
}

function Test-WinUser([string]$name) {
    try { $null = Get-LocalUser -Name $name -ErrorAction Stop; return $true } catch { return $false }
}

# os.users is a directory file: one record per permitted user, id = the name.
function Test-OsUser([string]$name) {
    foreach ($n in @($name, $name.ToUpper())) {
        if (Test-Path -LiteralPath (Join-Path $osusr $n)) { return $true }
    }
    return $false
}

# ------------------------------------------------------------------ Invoke-SD
#
# COPIED FROM probe-catprivate.ps1:144 UNCHANGED.  ONE STRING with LF
# separators - an ARRAY down the pipe puts a phantom empty line after every
# command and an "input" statement eats it (PROJECT_STATUS section 6).  That is
# also why PRE_RELEASE 19's "the test cannot be piped" was wrong: a password
# prompt is answered perfectly well by the next LINE of one string.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 90) {
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** It also leaves the session's user-table slot and locks behind,"
        $out += "*** so sdwind will not shut down and cycle.ps1 will refuse to"
        $out += "*** start.  Stop-Process the sdwind PID it names."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# Every session's raw output printed unconditionally, commands echoed from the
# ARRAY THAT WAS PASSED rather than from SD's echo of them.  Passwords masked.
function Show-SD([string]$title, [string[]]$commands, [string[]]$secrets) {
    Write-Output ("  --- SD session: " + $title + " ---")
    foreach ($c in $commands) {
        $shown = $c
        foreach ($s in $secrets) {
            if ($s -ne '' -and $shown -eq $s) { $shown = '<password, ' + $s.Length + ' characters>' }
        }
        Write-Output ("    > " + $shown)
    }
    $out = Invoke-SD $commands
    Write-Output '    --- SD said: ---'
    foreach ($line in ($out -split "`n")) { Write-Output ("    | " + $line.TrimEnd()) }
    Write-Output ''
    $script:lastSD = $out
}

# ------------------------------------------------------------- preconditions

if ($Prefix -eq '') {
    Write-Output 'verify-tierchange: -Prefix is required, and must be a name nobody has used.'
    Write-Output '  PROJECT_STATUS.md names the next free one.  Example: -Prefix sdtc1'
    exit 2
}
if ($Prefix -cnotmatch '^[a-z][a-z0-9_]{1,8}$') {
    Write-Output "verify-tierchange: -Prefix is '$Prefix'."
    Write-Output '  Lower case letters, digits and underscore only, starting with a letter,'
    Write-Output '  2 to 9 characters - CREATEA downcases the name and the sdu_ group takes it'
    Write-Output '  verbatim, so a mixed-case prefix would not match its own group.'
    exit 2
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-tierchange: this needs an ELEVATED PowerShell and this one is not.'
    Write-Output '  MODIFY.ACCOUNT is kernel(K$ADMINISTRATOR,-1), seeded from IsElevated() at'
    Write-Output '  process start, so an unelevated session stops at 2001 before the parser.'
    Write-Output '  CREATE.ACCOUNT and LOGTO SDSYS need elevation too.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1') -Quiet | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-tierchange: the installed tree does not match source - run a cycle first.'
    Write-Output '  A result from a stale tree is worse than no result: it looks like evidence.'
    exit 2
}

# $osusr IS IN THIS LIST ON PURPOSE.  Test-OsUser answers "no record" for a
# directory that is not there at all, so a missing os.users would make section
# 2's "an os.users record exists" FAIL as though the tier change were broken.
# An instrument that cannot reach its subject must say so, not score it.
foreach ($p in @($sdExe, $sdsys, $accts, $osusr, $newvoc)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("verify-tierchange: {0} does not exist - nothing could be measured." -f $p)
        exit 2
    }
}

Add-Type -AssemblyName System.Web

$acct = $Prefix + 'a'
# 11 Sep 26 - SECTION 6's ACCOUNT.  RELEASE_1.1_FIXES.md 13.
$acct2 = $Prefix + 'b'

Write-Output ("verify-tierchange: as {0}, ELEVATED" -f $id.Name)
Write-Output ("  sd      {0}" -f $sdExe)
Write-Output ("  account {0}" -f $acct)
Write-Output ("  account {0}   (section 6, STANDARD -> PROGRAMMER)" -f $acct2)
Write-Output ("  verb    {0}   (the VOC record made to differ)" -f $adminVerb)
Write-Output ("  verb    {0}   (section 6's subject, read from newvoc)" -f $upgradeVerb)
Write-Output ''

foreach ($a in @($acct, $acct2)) {
    $taken = @()
    if (Test-WinUser $a)                                       { $taken += 'Windows account' }
    if (Test-Path -LiteralPath (Join-Path $accts $a.ToUpper())) { $taken += 'SD ACCOUNTS record' }
    if (Test-Path -LiteralPath (Join-Path $env:SystemDrive ('Users\' + $a))) { $taken += 'profile directory' }
    if ($taken.Count -gt 0) {
        Write-Output ("verify-tierchange: " + $a + " already exists as: " + ($taken -join ', '))
        Write-Output '  CREATE.ACCOUNT would refuse several steps in, for a reason that reads like'
        Write-Output '  a fault in the tier change.  Use a fresh prefix.'
        exit 2
    }
}

# ------------------------------------------------------- 1. a PROGRAMMER account

Write-Output '=== 1. a PROGRAMMER account, and its VOC counted ==========================='

$pw = [System.Web.Security.Membership]::GeneratePassword(24, 6)
Show-SD 'create' @(('CREATE.ACCOUNT USER ' + $acct + ' PROGRAMMER BOTH'), $pw, $pw) @($pw)

Note 'the account was created' $true `
     (Test-Path -LiteralPath (Join-Path $accts $acct.ToUpper())) $true
if (-not (Test-Path -LiteralPath (Join-Path $accts $acct.ToUpper()))) {
    Write-Output '  Nothing below would be measuring a tier change.  That is "could not be run".'
    Write-Verdict 'verify-tierchange'
    exit 2
}
Note 'ACC$TIER is PROGRAMMER' 'PROGRAMMER' (Get-AccountTier $acct) $true
Note 'a PROGRAMMER is not a Windows administrator' $false (Test-LocalAdmin $acct) $true

Show-SD 'count the PROGRAMMER VOC' @(('LOGTO ' + $acct.ToUpper()), 'COUNT VOC') @()
$P = Get-VocCount $lastSD
Note 'the PROGRAMMER VOC was counted' $true ($P -gt 0) $true
Write-Output ("  P = " + $P + "  (measured, not assumed)")

# ------------------------------------------------------------ 2. promote

Write-Output ''
Write-Output '=== 2. promote to ADMINISTRATOR ==========================================='

Show-SD 'promote' @(('MODIFY.ACCOUNT ' + $acct.ToUpper() + ' ADMINISTRATOR')) @()
$aOut = $lastSD

Note 'promote says 10109 "Account X is now ADMINISTRATOR"' 'said' `
     (Get-Said $aOut ('Account\s+' + [regex]::Escape($acct.ToUpper()) + '\s+is now\s+ADMINISTRATOR')) $true
Note 'ACC$TIER is ADMINISTRATOR' 'ADMINISTRATOR' (Get-AccountTier $acct) $true

# THE TWO THINGS THE TIER GRANTS ON WINDOWS.  Both are asserted here so that
# their removal in section 4 is a CHANGE and not just an absence.
Note 'promoted: now a Windows administrator' $true (Test-LocalAdmin $acct) $true
Note 'promoted: an os.users record exists'   $true (Test-OsUser $acct) $true

Show-SD 'count the ADMINISTRATOR VOC' @(('LOGTO ' + $acct.ToUpper()), 'COUNT VOC') @()
$A = Get-VocCount $lastSD
Write-Output ("  A = " + $A + "  (measured, not assumed)")

# ***THE NULL CASE.***  A tier change that moved no VOC records must FAIL, not
# pass: everything below describes a difference between A and P.
Note 'the promotion actually added VOC records (A > P)' $true ($A -gt $P) $true

# ------------------------------------- 3. make one admin verb's record differ

Write-Output ''
Write-Output '=== 3. make one ADMINISTRATOR verb differ from the template ================'

# .S writes an S-type sentence under that name, which no tier build produces.
# The 5045 overwrite prompt is EXPECTED and answered - the argument was given,
# so this is not the missing-argument prompt that hangs a pipe.
Show-SD 'edit one VOC record' @(
    ('LOGTO ' + $acct.ToUpper()),
    'WHO',
    ('.S ' + $adminVerb + ' 1'),
    'Y',
    ('.L ' + $adminVerb)) @()
$eOut = $lastSD

Note ($adminVerb + ' is now an S-type record') $true `
     (Test-Say $eOut '^[ \t]*001[ \t]+S[ \t]*\r?$') $true
if (-not (Test-Say $eOut '^[ \t]*001[ \t]+S[ \t]*\r?$')) {
    Write-Output '  The record was not changed, so the downgrade below would have nothing to'
    Write-Output '  keep and the "left alone" row would pass by describing zero.'
    Write-Verdict 'verify-tierchange'
    exit 2
}

# ------------------------------------------- 4. the downgrade needs a keyword

Write-Output ''
Write-Output '=== 4. leaving ADMINISTRATOR without naming a route is REFUSED ============='

Show-SD 'downgrade with no route word' @(('MODIFY.ACCOUNT ' + $acct.ToUpper() + ' PROGRAMMER')) @()
$rOut = $lastSD

Note 'refused with 10111, naming the account' $true `
     (Test-Say $rOut ('Say what remote access ' + [regex]::Escape($acct.ToUpper()) +
                      ' is to have: ssh, api, both or none')) $true

# THE DISQUALIFIER IS THE SUCCESS WORDING.  10111 printed alongside a completed
# change would mean the refusal was cosmetic.
Note 'it did NOT also say the tier changed' $false `
     (Test-Say $rOut ('Account\s+' + [regex]::Escape($acct.ToUpper()) + '\s+is now')) $true

# AND NOTHING MOVED - the register and both Windows grants are unchanged.  A
# refusal that had already done half the work would pass the two rows above.
Note 'refused: ACC$TIER is still ADMINISTRATOR' 'ADMINISTRATOR' (Get-AccountTier $acct) $true
Note 'refused: still a Windows administrator'   $true (Test-LocalAdmin $acct) $true
Note 'refused: the os.users record is still there' $true (Test-OsUser $acct) $true

# ------------------------------- 5. the downgrade, and what leaves with it

Write-Output ''
Write-Output '=== 5. downgrade with BOTH: what leaves, and what is left alone ============'

Show-SD 'downgrade' @(('MODIFY.ACCOUNT ' + $acct.ToUpper() + ' PROGRAMMER BOTH')) @()
$dOut = $lastSD

Note 'downgrade says 10109 "Account X is now PROGRAMMER"' 'said' `
     (Get-Said $dOut ('Account\s+' + [regex]::Escape($acct.ToUpper()) + '\s+is now\s+PROGRAMMER')) $true
Note 'ACC$TIER is PROGRAMMER again' 'PROGRAMMER' (Get-AccountTier $acct) $true

# WHAT LEAVES WITH ADMINISTRATOR.  Both were asserted PRESENT in section 2, so
# each of these is a transition and not merely an absence.
Note 'downgraded: no longer a Windows administrator' $false (Test-LocalAdmin $acct) $true
Note 'downgraded: the os.users record is gone'       $false (Test-OsUser $acct) $true
# .ToUpper() IS LOAD-BEARING, AND ITS ABSENCE COST A FALSE FAIL ON b89.
# Test-Say is deliberately case-sensitive (see its note above), MODIFYA prints
# the account upcased - "os.users: the record for SDTCB89A is removed" - and
# -Prefix is required to be lower case (:243, -cnotmatch).  So a pattern built
# from $acct raw can NEVER match, whatever the product does.  Every other
# account-naming check here already upcases (:381, :387, :404); this one did
# not, and reported "expected True, got False" against an output carrying the
# message in full.  ***THAT IS THE FAILURE-WORDING TRAP RUN BACKWARDS***: the
# CLAUDE.md rule guards against a pattern the failure path also matches, and
# this is a pattern the SUCCESS path cannot match - a false FAIL rather than a
# false PASS.  Both come of not reading the tool's real output once.
Note 'downgraded: it SAID the os.users record went (10115)' $true `
     (Test-Say $dOut ('os\.users: the record for ' + [regex]::Escape($acct.ToUpper()) + ' is removed')) $true

# THE "LEFT ALONE" RULE.
$delta = Get-VocDelta $dOut
Note '10113 was printed with its three counts' $true $delta.Found $true
Write-Output ("  10113: added " + $delta.Added + ", removed " + $delta.Removed +
              ", left alone " + $delta.Kept)

# 11 Sep 26 - EXACTLY ONE, NOT "AT LEAST ONE".  RELEASE_1.1_FIXES.md 12.
#
# Section 3 above plants exactly ONE mismatched record and exits 2 if it did
# not - so on a healthy tree the answer is 1, and 1 is the only answer that
# means what this row claims.  The guard beside it already refused the
# describes-ZERO case; this refuses the describes-EVERYTHING case, which is the
# same hole at the other end.
#
# ***IT DOES NOT CATCH RELEASE_1.1 1, AND THE FIRST VERSION OF THIS COMMENT
# CLAIMED IT DID.  CORRECTED THE SAME DAY, BY READING THE RECORDS.***  The
# reasoning was: entry 1 left every record "left alone", so "at least one"
# passed while describing a total failure.  That is true of the defect and
# FALSE OF THIS FILE, because of which layer this file exercises.
#
# tier.build.rec only truncated field 1 when field 1 was LONGER than its type
# prefix - a description like "Verb to compile SDBasic program".  THE 22
# RECORDS IN TIER.ADD.ADMINISTRATOR ARE ALL BARE TYPE LETTERS IN voc_template
# (list.locks is "V"), so the strip was a NO-OP on this layer and the
# PROGRAMMER<->ADMINISTRATOR round trip this file drives behaved correctly with
# the defect in place.  Kept would have been 1 here either way.
#
# ***SO b131's GREEN WAS HONEST, AND THE GAP IS COVERAGE RATHER THAN A LOOSE
# THRESHOLD.***  Entry 1 is reachable only on a transition that adds records
# read from newvoc, where 41 of the 42 TIER.OMIT.STANDARD records DO carry a
# description.  RELEASE_1.1 13 is that missing witness.
#
# ***WHAT WOULD FALSIFY THE ROW BELOW.***  A healthy downgrade that legitimately
# keeps more than one record.  If it goes red with Kept > 1 on a tree nobody has
# edited, THIS NUMBER is the thing to question, not the product.
Note 'exactly one record was LEFT ALONE - the one section 3 planted' 1 $delta.Kept $true

Show-SD 'count the VOC after the downgrade' @(('LOGTO ' + $acct.ToUpper()), 'COUNT VOC',
                                              ('.L ' + $adminVerb)) @()
$D = Get-VocCount $lastSD
Write-Output ("  D = " + $D + "  (measured, not assumed)")

# THE COUNT MOVED EXACTLY AS 10113 REPORTED.  A message that says one thing
# while the VOC does another is the failure this catches.
Note 'the VOC moved exactly as 10113 reported (D = A + added - removed)' `
     ($A + $delta.Added - $delta.Removed) $D $true

# ***THE DECISIVE ROW.***  A clean downgrade lands back on P.  This one lands on
# P plus exactly the kept records - so the edited record is provably still
# there, and provably the only difference.  Nothing here is a typed constant.
Note 'D = P + kept: the kept record is the only difference' ($P + $delta.Kept) $D $true

# AND READ IT BACK, because the arithmetic above would also hold if some OTHER
# record had been kept and this one deleted.
Note ($adminVerb + ' survived the downgrade, still S-type') $true `
     (Test-Say $lastSD '^[ \t]*001[ \t]+S[ \t]*\r?$') $true

# ------------------------------- 6. STANDARD -> PROGRAMMER keeps descriptions

# 11 Sep 26 - RELEASE_1.1_FIXES.md 13.  THE ONE TRANSITION NOTHING ELSE DRIVES.
#
# ***WHY THIS SECTION EXISTS, AND IT IS NOT "MORE COVERAGE".***  RELEASE_1.1 1
# was MODIFYA's tier.build.rec still applying the type-letter strip that
# PRE_RELEASE 136 removed from CREATEA.  b131 was GREEN IN BOTH HALVES with
# that defect four days old, and sections 1 to 5 above would have passed too -
# not because they are loose, but because of WHICH RECORDS THEY TOUCH.
#
# The strip only damaged a field 1 that was LONGER than its type prefix.
# Measured 11 Sep 26: all 22 TIER.ADD.ADMINISTRATOR records are bare type
# letters in voc_template (list.locks is "V"), and none is K-type with a
# field 3 - the other shape the strip reached.  So the PROGRAMMER<->ADMINISTRATOR
# round trip above is a NO-OP for the defect in both directions.
#
# 41 of the 42 TIER.OMIT.STANDARD records DO carry a description, and they are
# read from newvoc.  ***A STANDARD -> PROGRAMMER PROMOTION IS THEREFORE THE ONLY
# TRANSITION THAT CAN SEE IT, AND NO VERIFIER PERFORMED ONE*** - swept 11 Sep 26:
# every MODIFY.ACCOUNT in every verifier is the round trip above or
# verify-tiers:713's restore, and b135 printed what THAT does:
# "VOC: 0 records added, 0 removed, 0 left alone", because suspension does not
# strip the VOC and the restore does not rebuild it.
#
# ***THE SHAPE OF THE DEFECT IS "V" WHERE A SENTENCE BELONGS*** - the same thing
# the owner saw in a listf on 2 Sep 2026 that PRE_RELEASE 136 was filed for.

Write-Output ''
Write-Output '=== 6. STANDARD -> PROGRAMMER: the added records keep their text ==========='

# ***WHAT THE ACCOUNT SHOULD END UP WITH, READ FROM THE SHIPPED RECORD.***  Not
# typed: see $upgradeVerb's note.  Field 1 is the first line of the newvoc file.
$srcRec = Join-Path $newvoc $upgradeVerb
if (-not (Test-Path -LiteralPath $srcRec)) {
    Write-Output ("  newvoc record '" + $upgradeVerb + "' is not there: " + $srcRec)
    Write-Output '  Nothing below could be compared against anything.  That is "could not be run".'
    Write-Verdict 'verify-tierchange'
    exit 2
}
$wantF1 = (Get-Content -LiteralPath $srcRec -TotalCount 1) -replace '\r$', ''
Write-Output ("  newvoc\" + $upgradeVerb + " field 1 = '" + $wantF1 + "'   (read, not typed)")

# ***REFUSE THE NULL CASE, AND IT IS A REAL ONE HERE.***  If the shipped record's
# field 1 were a bare type letter, the strip this section hunts would be a no-op
# on it and every row below would PASS while measuring nothing - which is exactly
# how sections 1 to 5 missed the defect.  A two-character prefix like "PA" is a
# legitimate bare form, so the test is "longer than 2", not "longer than 1".
if ($wantF1.Length -le 2) {
    Write-Output ("  field 1 is '" + $wantF1 + "', a bare type code - so this section could not")
    Write-Output '  tell a stripped record from a whole one.  Pick a $upgradeVerb whose newvoc'
    Write-Output '  field 1 is a description; 41 of TIER.OMIT.STANDARD''s 42 ids are.'
    Write-Verdict 'verify-tierchange'
    exit 2
}

$pw2 = [System.Web.Security.Membership]::GeneratePassword(24, 6)
Show-SD 'create a STANDARD account' @(
    ('CREATE.ACCOUNT USER ' + $acct2 + '  BOTH'), $pw2, $pw2) @($pw2)

Note 'the STANDARD account was created' $true `
     (Test-Path -LiteralPath (Join-Path $accts $acct2.ToUpper())) $true
if (-not (Test-Path -LiteralPath (Join-Path $accts $acct2.ToUpper()))) {
    Write-Output '  Nothing below would be measuring an upgrade.  That is "could not be run".'
    Write-Verdict 'verify-tierchange'
    exit 2
}
Note 'ACC$TIER is STANDARD' 'STANDARD' (Get-AccountTier $acct2) $true

# THE CONTROL, AND IT RUNS BEFORE THE PROMOTION.  A STANDARD account must NOT
# already hold the verb; if it did, the promotion would add nothing and the row
# below would be reading a record this test never caused to be written.
Show-SD 'the STANDARD account does not have it yet' @(
    ('LOGTO ' + $acct2.ToUpper()), ('.L ' + $upgradeVerb)) @()
Note ($upgradeVerb + ' is ABSENT before the promotion') $false `
     (Test-Say $lastSD ('^[ \t]*001[ \t]+' + [regex]::Escape($wantF1))) $true

Show-SD 'promote STANDARD -> PROGRAMMER' @(
    ('MODIFY.ACCOUNT ' + $acct2.ToUpper() + ' PROGRAMMER BOTH')) @()
$uOut = $lastSD

Note 'promote says 10109 "Account X is now PROGRAMMER"' 'said' `
     (Get-Said $uOut ('Account\s+' + [regex]::Escape($acct2.ToUpper()) + '\s+is now\s+PROGRAMMER')) $true
Note 'ACC$TIER is PROGRAMMER' 'PROGRAMMER' (Get-AccountTier $acct2) $true

# ***THE SECOND NULL-CASE GUARD.***  A promotion that wrote no records leaves the
# VOC exactly as it was, and the row below would then be describing a record
# that was never re-written - passing by measuring nothing.  This is not
# hypothetical: it is precisely what verify-tiers:713's restore does.
$uDelta = Get-VocDelta $uOut
Note '10113 was printed with its three counts' $true $uDelta.Found $true
Write-Output ("  10113: added " + $uDelta.Added + ", removed " + $uDelta.Removed +
              ", left alone " + $uDelta.Kept)
Note 'the promotion actually ADDED records' $true ($uDelta.Added -ge 1) $true

# ***THE DECISIVE ROW.***  Field 1 of the account's copy must be the whole
# sentence the shipped record carries.  RELEASE_1.1 1 left a bare type letter
# here - "V" where "Verb to compile SDBasic program" belongs.
Show-SD 'read the added record back' @(
    ('LOGTO ' + $acct2.ToUpper()), ('.L ' + $upgradeVerb)) @()

$gotF1 = ''
foreach ($line in ($lastSD -split "`n")) {
    if ($line -match '^[ \t]*001[ \t]+(.+?)[ \t]*\r?$') { $gotF1 = $Matches[1]; break }
}
Note ($upgradeVerb + ' field 1 after the promotion') $wantF1 $gotF1 $true

# AND SAY WHAT A FAILURE MEANS, because the two strings differ by a lot and the
# reason is one specific defect.
if ($gotF1 -ne $wantF1) {
    Write-Output ''
    Write-Output '  *** The account''s copy does not match the shipped record.'
    Write-Output ("      shipped: '" + $wantF1 + "'")
    Write-Output ("      account: '" + $gotF1 + "'")
    Write-Output '  If the account holds only the first character, this is RELEASE_1.1 1:'
    Write-Output '  MODIFYA tier.build.rec applying the type-letter strip PRE_RELEASE 136'
    Write-Output '  removed from CREATEA.  Nothing else in this file can see that.'
}

# -------------------------------------------------------------- clean up

Write-Output ''
Write-Output '=== clean up =============================================================='

Show-SD 'delete the STANDARD account' @(('DELETE.ACCOUNT ' + $acct2), 'Y') @()
Note 'clean up: the second Windows account is gone' $false (Test-WinUser $acct2) $true
Note 'clean up: the second ACCOUNTS record is gone' $false `
     (Test-Path -LiteralPath (Join-Path $accts $acct2.ToUpper())) $true

Show-SD 'delete the account' @(('DELETE.ACCOUNT ' + $acct), 'Y') @()

Note 'clean up: the Windows account is gone' $false (Test-WinUser $acct) $true
Note 'clean up: the ACCOUNTS record is gone' $false `
     (Test-Path -LiteralPath (Join-Path $accts $acct.ToUpper())) $true
# ***THE ONE THAT MATTERS MOST.***  This account was a Windows administrator for
# part of the run.  If the delete failed, that is what is left behind.
Note 'clean up: not left in the Windows administrators group' $false (Test-LocalAdmin $acct) $true

$litter = @()
foreach ($a in @($acct, $acct2)) {
    $d = Join-Path $env:SystemDrive ('Users\' + $a)
    if (Test-Path -LiteralPath $d) { $litter += $d }
    if (Test-OsUser $a)            { $litter += ('os.users record ' + $a) }
}
if ($litter.Count -gt 0) {
    Write-Output '  *** LEFT BEHIND - read from disk, not from what the delete reported:'
    $litter | ForEach-Object { Write-Output ('      ' + $_) }
    Write-Output '  Nothing here signed in, so a profile directory would be PRE_RELEASE 35/36.'
} else {
    Write-Output ('  nothing left behind for ' + $acct + ' or ' + $acct2)
}

Write-Output ''
Write-Output '  THE THREE DOORS ARE NOT TESTED HERE, AND THIS IS NOT A PASS:'
Write-Output '    LOGIN (ssh/console), logto, and the API all need a session this file'
Write-Output '    cannot have - unelevated, as the suspended account.  PRE_RELEASE 38'
Write-Output '    carries the shape.  Nothing here counts them as covered.'

# ---------------------------------------------------------------------- report

Write-Output ''
$results | Format-Table -AutoSize -Wrap | Out-String | Write-Output

Write-Verdict 'verify-tierchange'

if ($fatal) { exit 1 }
exit 0
