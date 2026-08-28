# verify-acctmsgs.ps1 - exercise the three PRE_RELEASE fixes that need a real
# account: 22 (CREATE.ACCOUNT says WHY a password was not set), 27
# (MODIFY.ACCOUNT ADD/DELETE writes an audit record), 37 (CREATE.ACCOUNT's two
# access lines no longer contradict each other).
#
#   powershell -File verify-acctmsgs.ps1 -Prefix sdmsga
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# WHY IT EXISTS.  All three shipped into the install of 28 Aug 2026 00:53:34
# and NOTHING HAS RUN ANY OF THEM.  PRE_RELEASE_FIXES.md marks each "COMPILED
# AND INSTALLED - UNTESTED" on purpose.  This is the witness.  Its sibling
# verify-vocverbs.ps1 covers the five that need no account, and they are two
# scripts rather than one because THIS one creates Windows accounts: it can be
# left until the machine is in a state where that is wanted, and its litter is
# accounted for separately.
#
# ***-Prefix IS REQUIRED AND MUST BE A NAME NOBODY HAS USED.***  Four names are
# derived from it and all four must be free in Windows AND in SD's register -
# CREATE.ACCOUNT refuses a name whose ACCOUNTS record survives, several steps
# in, for a reason that reads like something else entirely.  PROJECT_STATUS.md
# names the next free prefix.
#
# RUN IT ELEVATED.  CREATE_USER needs an elevated token; so does reading
# sdsys\audit, which secure-audit.ps1 locks to SYSTEM and Administrators; and
# LOGTO SDSYS is administrator-only.  ***AND ENTRY 22 IS PARTLY ABOUT THAT***:
# status 5 is "SD is not running elevated", and an unelevated run would take
# that arm instead of the two under test - passing a check that measured the
# wrong branch.  10120 is a named disqualifier below for exactly that reason.
#
# ------------------------------------------------------------------ entry 22
#
# ***START HERE'S SUGGESTED TEST DOES NOT WORK ON THIS MACHINE.***  It says
# "give a password Windows refuses (a)".  Measured 28 Aug 2026: "net accounts"
# reports MINIMUM PASSWORD LENGTH 0, and password complexity is off by default
# on a client SKU - so "a" is ACCEPTED here, the account is created for real,
# and the arm meant to prove the refusal message never runs.  A green run would
# have meant nothing.
#
# SO THE TWO ARMS ARE DRIVEN SEPARATELY AND ONLY ONE OF THEM DEPENDS ON POLICY:
#
#   A  MISMATCH -> 10118.  Two different passwords.  Deterministic: SET_PASSWD
#      compares them itself (:101) before Windows is involved at all, so no
#      machine setting can change the answer.
#   B  WINDOWS REFUSED -> 10119.  ***THIS ARM HAS NEVER RUN, AND THE REASON IS
#      A PREMISE OF MINE THAT WAS WRONG.***  It sends a 150-character password
#      on the stated grounds that this is past "the 127-character limit the SAM
#      imposes on a local account whatever the policy says".  ***MEASURED
#      28 Aug 2026: Set-LocalUser ACCEPTED IT*** - the account was created for
#      real and the run recorded SKIP.  Whatever enforces 127 elsewhere,
#      Set-LocalUser on this host does not.
#
#      **The claim was reasoned and written as fact, which is the trap
#      PROJECT_STATUS section 6 calls "measure before writing the comment".**
#      It is left here corrected rather than deleted, because the next session
#      will otherwise reason its way to the same password.
#
#      ***SO THE PASSWORD IS NOW CHOSEN FROM THE POLICY RATHER THAN GUESSED***
#      (28 Aug 2026, owner's decision to change the policy for the test).
#      Get-PasswordPolicy reads MinimumPasswordLength and PasswordComplexity
#      with "secedit /export" - locale-independent, unlike parsing the prose
#      "net accounts" prints - and arm B then breaks whichever rule is in force:
#      one character short of the minimum, or a single character class against
#      complexity.  With NO rule in force there is nothing to break, and the arm
#      says so and SKIPs.
#
#      ***THIS SCRIPT STILL DOES NOT CHANGE THE POLICY, AND THAT IS DELIBERATE.***
#      It reads it and adapts.  Changing a machine's password policy to make a
#      test pass is a change to the MACHINE, not to the test, and it has to be
#      somebody's decision, made once, in the open, and reverted afterwards.
#      PROJECT_STATUS.md START HERE carries the three commands.
#
#      ***THE SKIP IS THE POINT.***  A test that passes because it did nothing
#      must not pass.  SET_PASSWD's generated script catches any Set-LocalUser
#      failure as "exit 1", which is status 1, which is 10119 - so the arm is
#      correct whenever Windows does refuse; nothing here has yet made it.
#
# ------------------------------------------------------------------ entry 27
#
# THE OBSERVABLE IS THE AUDIT TRAIL, READ BY LENGTH.  Only the bytes this run
# added are examined, so a record left by an earlier session cannot score for
# it - verify-cmdaudit.ps1's rule.  The control on the audit row is 10018/10021
# in SD's own output: MODIFYA writes the audit record INSIDE "if stat = 0", so
# a run where the group edit failed must not be read as a missing audit record.
#
# ***IT USES A THROWAWAY SD USER, NOT don.***  MODIFY.ACCOUNT ADD needs a user
# who is already in sdusers and is not already in the target group, and the
# obvious candidate is the owner's own account.  A second throwaway account
# costs one more create and touches no identity anybody uses.
#
# ------------------------------------------------------------------ entry 37
#
# THE TWO LINES COME FROM DIFFERENT GATES - Windows logon rights (CREATEA:838)
# and SD's route keywords (:1640) - and the defect was that both were worded as
# "may sign in over ssh...", so the second read as a contradiction of the first.
# Both new forms are required present AND both old forms required absent; the
# old wording is the disqualifier, because a build that printed both old lines
# would still contain the substring "ssh" that a lazy check would anchor on.
#
# WHAT IT LEAVES BEHIND.  Nothing, if it finishes: all four accounts are
# deleted.  The litter section at the end reports what is actually on disk
# rather than what the delete said - PRE_RELEASE 41 is a sweep that reported
# zero while three orphan directories were still there.

[CmdletBinding()]
param([string]$Prefix = '')

$ErrorActionPreference = 'Stop'

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys   = Join-Path $env:ProgramData  'SD\sdsys'
$audit   = Join-Path $sdsys 'audit'
$accts   = Join-Path $sdsys 'accounts'

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

# A ROW THAT WAS NOT MEASURED, SAID OUT LOUD.  It is deliberately NOT decisive
# and deliberately not a PASS: the verdict line counts only decisive rows, so a
# skipped arm cannot be mistaken for a measured one, and the summary below
# prints every skip with its reason.
function Skip($step, $why) {
    $null = $results.Add([pscustomobject]@{
        Check    = $step
        Expected = 'measured'
        Observed = 'NOT MEASURED'
        Result   = 'SKIP'
        Decisive = 'no'
    })
    Write-Output ("  [SKIP] {0}: {1}" -f $step, $why)
}

# 24 Aug 26 - THE VERDICT LINE.  Kept BYTE-FOR-BYTE IDENTICAL to the copies in
# verify-createaccount.ps1, verify-cmdaudit.ps1 and verify-sshonly.ps1, and
# test-verdict-units.ps1 asserts that across all of them.  If one changes,
# change all of them.
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
# CASE-SENSITIVE, and neither writes anything.  See verify-vocverbs.ps1 for
# both reasons; entry 27's audit record is the one place here where case
# matters, because MODIFYA upper-cases acc.name (:223) and leaves user.name as
# typed, and a check that could not tell those apart would not be checking the
# record's shape at all.
function Test-Say([string]$text, [string]$pattern) {
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return ([regex]::IsMatch($text, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline))
}

# ------------------------------------------------------------------ Invoke-SD
#
# COPIED FROM probe-catprivate.ps1:144 UNCHANGED - the shape PROJECT_STATUS.md
# section 6 says works.  ONE STRING with LF separators is not a style choice
# here: an ARRAY down the pipe puts a phantom empty line after every command,
# and THIS script is the exact case that destroyed verify-createaccount.ps1 on
# 14 Aug 2026 - "input pw1 HIDDEN" ate the phantom, "input pw2 HIDDEN" got the
# real password, the two differed, and the account was left with no password at
# all.  Entry 22 arm A is that same failure as a deliberate test, so the two
# must not be confusable.
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
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

# EVERY SESSION'S RAW OUTPUT IS PRINTED, unconditionally, and the commands are
# echoed from the ARRAY THAT WAS PASSED rather than from SD's echo of them.
# ***PASSWORDS ARE MASKED IN THE ECHO AND NOWHERE ELSE***: SD reads them with
# "input HIDDEN" so they never appear in its output, and this function must not
# be the thing that puts them in a transcript.
#
# IT RETURNS NOTHING AND LEAVES THE OUTPUT IN $script:lastSD.  Returning it
# would hand the caller these Write-Output lines joined to SD's, and every
# pattern below would then be matching this function's own narration.
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

function Test-WinUser([string]$name) {
    try { $null = Get-LocalUser -Name $name -ErrorAction Stop; return $true } catch { return $false }
}

# ------------------------------------------------------- the password policy
#
# ***ARM B CANNOT PICK ITS PASSWORD WITHOUT READING THIS.***  The first version
# guessed - a 150-character password, on the reasoning that 127 is a hard SAM
# limit - and Set-LocalUser accepted it, so the arm recorded SKIP having proved
# nothing.  A refusal has to be MANUFACTURED against the rule that is actually
# in force, and the only way to know that is to read it.
#
# secedit RATHER THAN "net accounts", because "net accounts" is parsed out of
# LOCALISED prose and this must not quietly stop working on a machine that is
# not English.  secedit needs an elevated token, which this script already
# refuses to run without.  "net accounts" stays as the fallback, and an
# unreadable policy is reported as unreadable rather than assumed to be lax.
#
# IT WRITES NOTHING AND CHANGES NOTHING - /export only.  Changing a machine's
# password policy to make a test pass is a change to the MACHINE, not to the
# test, and this script does not make it.
function Get-PasswordPolicy {
    $out = [pscustomobject]@{ MinLength = -1; Complexity = -1; Source = 'unreadable' }
    $cfg = Join-Path $env:TEMP ('verify-acctmsgs-secpol-' + [Guid]::NewGuid().ToString('N') + '.inf')

    # A NATIVE EXE WRITING TO stderr KILLS THE SCRIPT under ErrorActionPreference
    # Stop in Windows PowerShell 5.1, and it does so SILENTLY.  Lowered around
    # the call and restored immediately.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { & secedit /export /areas SECURITYPOLICY /cfg $cfg | Out-Null } catch { }
    $ErrorActionPreference = $prev

    if (Test-Path -LiteralPath $cfg) {
        # 5.1 writes this file as UTF-16; -Raw plus the default reader handles
        # the BOM.  Read, then delete - it is a dump of the security policy and
        # has no business surviving the run.
        $text = ''
        try { $text = Get-Content -LiteralPath $cfg -Raw } catch { }
        Remove-Item -LiteralPath $cfg -Force -ErrorAction SilentlyContinue
        if ($text -match 'MinimumPasswordLength\s*=\s*(\d+)') {
            $out.MinLength = [int]$Matches[1]; $out.Source = 'secedit'
        }
        if ($text -match 'PasswordComplexity\s*=\s*(\d+)') { $out.Complexity = [int]$Matches[1] }
    }

    if ($out.MinLength -lt 0) {
        $prev = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        $na = ''
        try { $na = (& net accounts | Out-String) } catch { }
        $ErrorActionPreference = $prev
        if ($na -match '(?m):\s*(\d+)\s*$' -and $na -match 'assword') {
            # Deliberately weak, and labelled so: this only fires when secedit
            # gave nothing, and it is why the source is reported on its own row.
            if ($na -match '(?im)^.*password length.*?(\d+)\s*$') {
                $out.MinLength = [int]$Matches[1]; $out.Source = 'net accounts'
            }
        }
    }
    return $out
}

# ------------------------------------------------------------- preconditions

if ($Prefix -eq '') {
    Write-Output 'verify-acctmsgs: -Prefix is required, and must be a name nobody has used.'
    Write-Output '  PROJECT_STATUS.md names the next free one.  Example: -Prefix sdmsga'
    exit 2
}
# CREATEA downcases the name and the sdu_ group takes it verbatim, so a
# mixed-case prefix would not match its own group.  verify-accountacl.ps1's
# guard, and its reasoning, unchanged.
if ($Prefix -cnotmatch '^[a-z][a-z0-9_]{1,8}$') {
    Write-Output "verify-acctmsgs: -Prefix is '$Prefix'."
    Write-Output '  Lower case letters, digits and underscore only, starting with a letter,'
    Write-Output '  2 to 9 characters.'
    exit 2
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-acctmsgs: this needs an ELEVATED PowerShell and this one is not.'
    Write-Output '  CREATE_USER needs an elevated token, sdsys\audit is locked to SYSTEM and'
    Write-Output '  Administrators, and LOGTO SDSYS is administrator-only.  Worse than'
    Write-Output '  failing: unelevated, SET_PASSWD returns status 5 and CREATE.ACCOUNT'
    Write-Output '  prints 10120 - so entry 22 would take a THIRD arm and this run would be'
    Write-Output '  measuring the wrong branch.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1') -Quiet | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-acctmsgs: the installed tree does not match source - run a cycle first.'
    Write-Output '  A result from a stale tree is worse than no result: it looks like evidence.'
    exit 2
}

foreach ($p in @($sdExe, $sdsys, $audit, $accts)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("verify-acctmsgs: {0} does not exist - nothing could be measured." -f $p)
        exit 2
    }
}

Add-Type -AssemblyName System.Web

# ------------------------------------------------------------------ the names

$acctMis  = $Prefix + 'a'    # entry 22 arm A - the two passwords differ
$acctLong = $Prefix + 'b'    # entry 22 arm B - Windows refuses the password
$acctReal = $Prefix + 'c'    # entry 37, and the account entry 27 edits
$acctUser = $Prefix + 'u'    # entry 27 - the user added to acctReal's group
$allAccts = @($acctMis, $acctLong, $acctReal, $acctUser)

Write-Output ("verify-acctmsgs: as {0}, ELEVATED" -f $id.Name)
Write-Output ("  sd      {0}" -f $sdExe)
Write-Output ("  audit   {0}" -f $audit)
Write-Output ("  prefix  {0}" -f $Prefix)
Write-Output ("  names   {0}" -f ($allAccts -join ', '))
Write-Output ''

# ***REFUSE BEFORE ANYTHING IS CREATED.***  Three ways a name can be taken, and
# each of them makes a different step fail much later for a reason that reads
# like something else.  Windows account, SD register record, profile directory.
$taken = @()
foreach ($n in $allAccts) {
    if (Test-WinUser $n)                                          { $taken += ($n + ' (Windows account)') }
    if (Test-Path -LiteralPath (Join-Path $accts $n.ToUpper()))    { $taken += ($n + ' (SD ACCOUNTS record)') }
    if (Test-Path -LiteralPath (Join-Path $env:SystemDrive ('Users\' + $n))) { $taken += ($n + ' (profile directory)') }
}
if ($taken.Count -gt 0) {
    Write-Output 'verify-acctmsgs: these names are already in use:'
    $taken | ForEach-Object { Write-Output ('    ' + $_) }
    Write-Output ''
    Write-Output '  CREATE.ACCOUNT would refuse, several steps in, for a reason that reads'
    Write-Output '  like a fault in the fixes under test.  Use a fresh prefix.'
    exit 2
}

$pw1  = [System.Web.Security.Membership]::GeneratePassword(24, 6)
$pw2  = [System.Web.Security.Membership]::GeneratePassword(24, 6)
$pwOk = [System.Web.Security.Membership]::GeneratePassword(24, 6)
$pwU  = [System.Web.Security.Membership]::GeneratePassword(24, 6)
# ***ARM B'S PASSWORD IS CHOSEN FROM THE POLICY, NOT GUESSED.***  Three cases,
# in the order of how certain the refusal is:
#
#   MinLength >= 2   one character SHORT of the minimum.  A length rule is
#                    arithmetic and cannot be argued with, so this is the case
#                    to prefer whenever it exists.
#   Complexity = 1   lower-case letters only, at the minimum length or 14,
#                    whichever is larger.  Complexity wants three of four
#                    character classes, so one class fails it while length
#                    cannot be the reason.
#   otherwise        150 characters, and EXPECTED TO BE ACCEPTED.  Measured
#                    28 Aug 2026 on this host: it was.  Kept only so the arm
#                    attempts something and reports SKIP honestly.
#
# EVERY BRANCH PRINTS WHAT IT READ AND WHAT IT SENT.  A refusal is only evidence
# if the rule it broke is on the record beside it - otherwise 10119 could as
# easily be some unrelated Set-LocalUser failure.
# PURE, so test-acctmsgs-units.ps1 can lift it by AST and drive it with policy
# values this machine does not have.  It picks a password; it reads nothing and
# sets nothing.
function Select-RefusedPassword([int]$min, [int]$complexity) {
    if ($min -ge 2) {
        # Clamped: Windows caps the minimum at 20 today, but a Substring past
        # the end of the seed would throw, and a guard costs one line.
        $seed = 'Aa1Bb2Cc3Dd4Ee5Ff6Gg7Hh8'
        $want = [Math]::Min($min - 1, $seed.Length * 20)
        return [pscustomobject]@{
            Password = ($seed * 20).Substring(0, $want)
            Why      = ('one character short of the minimum of ' + $min)
            Expect   = 'refused'
        }
    }
    if ($complexity -eq 1) {
        $n = [Math]::Max($min, 14)
        return [pscustomobject]@{
            Password = ('a' * $n)
            Why      = ("$n lower-case letters, which fails complexity on character classes, not on length")
            Expect   = 'refused'
        }
    }
    return [pscustomobject]@{
        Password = ('Aa1' * 50)
        Why      = '150 characters - NO RULE IS IN FORCE TO BREAK, so this is expected to be ACCEPTED and the arm to SKIP'
        Expect   = 'accepted'
    }
}

$policy = Get-PasswordPolicy
Write-Output ("  policy  minimum length {0}, complexity {1} (read by {2})" -f
              $policy.MinLength, $policy.Complexity, $policy.Source)

$choice = Select-RefusedPassword $policy.MinLength $policy.Complexity
$pwLong = $choice.Password
$pwWhy  = $choice.Why
Write-Output ("  arm B   sending a password of " + $pwLong.Length + " characters: " + $pwWhy)
Write-Output ("  arm B   expects Windows to have " + $choice.Expect + " it")

# --------------------------------- 22 arm A: the two passwords did not match

Write-Output '=== PRE_RELEASE 22 arm A: a mismatched pair says so (10118) ==============='

# THE UNWIND IS PART OF THE TEST.  Answering N to 10008 must take the whole
# creation back out (CREATEA:549), so the absence of the Windows account
# afterwards is both the clean-up and a check.
Show-SD 'entry 22 arm A' @(
    ('CREATE.ACCOUNT USER ' + $acctMis + ' PROGRAMMER BOTH'),
    $pw1,
    $pw2,
    'N') @($pw1, $pw2)
$a22a = $lastSD

# NULL CASE FIRST.  If create_user never ran, set_passwd was never called and
# every row below would be describing a session that did nothing.
Note '22A null case: the Windows user was created' $true `
     (Test-Say $a22a ('User ' + [regex]::Escape($acctMis) + ' Created')) $true

Note '22A: the mismatch was named (10118)' $true `
     (Test-Say $a22a 'The two passwords did not match, or none was entered\.') $true

# THE OTHER THREE ARMS ARE DISQUALIFIERS.  status() is read once, immediately,
# and exactly one of the four messages must follow it; more than one would mean
# the case statement is not selecting.
Note '22A: it did NOT claim Windows refused the password' $false `
     (Test-Say $a22a 'Windows refused that password') $true
Note '22A: it did NOT claim SD is unelevated' $false `
     (Test-Say $a22a 'SD is not running elevated') $true
Note '22A: it did NOT fall through to the generic status' $false `
     (Test-Say $a22a 'The password could not be set \(status') $true

Note '22A: answering N unwound the creation' $true `
     (Test-Say $a22a 'An account must have a password\. Nothing was created\.') $true
Note '22A: the Windows account is gone' $false (Test-WinUser $acctMis) $true
Note '22A: no ACCOUNTS record was left' $false `
     (Test-Path -LiteralPath (Join-Path $accts $acctMis.ToUpper())) $true

# ------------------------------- 22 arm B: Windows refused the password

Write-Output ''
Write-Output '=== PRE_RELEASE 22 arm B: a refused password says so (10119) =============='

Show-SD 'entry 22 arm B' @(
    ('CREATE.ACCOUNT USER ' + $acctLong + ' PROGRAMMER BOTH'),
    $pwLong,
    $pwLong,
    'N') @($pwLong)
$a22b = $lastSD

Note '22B null case: the Windows user was created' $true `
     (Test-Say $a22b ('User ' + [regex]::Escape($acctLong) + ' Created')) $true

if (Test-Say $a22b 'Windows refused that password') {
    # THE MESSAGE NAMES THE ACCOUNT, which is what 10119's %1 is for, and it is
    # the half a message-only edit could have got wrong.
    Note '22B: the refusal was named, with the account (10119)' $true `
         (Test-Say $a22b ('Windows refused that password for ' + [regex]::Escape($acctLong))) $true
    Note '22B: it did NOT claim the passwords differed' $false `
         (Test-Say $a22b 'The two passwords did not match') $true
    Note '22B: it did NOT claim SD is unelevated' $false `
         (Test-Say $a22b 'SD is not running elevated') $true
    Note '22B: the retry is still offered for this case' $true `
         (Test-Say $a22b 'Retry \(Y/N\)') $true
    Note '22B: answering N unwound the creation' $true `
         (Test-Say $a22b 'An account must have a password\. Nothing was created\.') $true
} else {
    Skip '22B: Windows refused the password' `
         ('this machine accepted a ' + $pwLong.Length + '-character password (' + $pwWhy + ')')
    Write-Output '    Entry 22 arm B measured NOTHING on this host.  The mismatch arm above is'
    Write-Output '    unaffected - it never reaches Windows.'
    Write-Output ("    The policy read was: minimum length " + $policy.MinLength +
                  ", complexity " + $policy.Complexity + ", by " + $policy.Source + '.')
    if ($policy.MinLength -lt 2 -and $policy.Complexity -ne 1) {
        Write-Output '    NO PASSWORD RULE IS IN FORCE, so there is nothing here for Windows to'
        Write-Output '    refuse.  Exercising this arm needs a machine that has one - which is a'
        Write-Output '    change to the MACHINE and is not this script''s to make.'
    } else {
        Write-Output '    A RULE IS IN FORCE AND THE PASSWORD BROKE IT, AND WINDOWS TOOK IT ANYWAY.'
        Write-Output '    That is a finding in its own right: read the raw output above before'
        Write-Output '    concluding anything about CREATE.ACCOUNT.'
    }
    Write-Output ''
    # ***THE ACCOUNT IS REAL NOW.***  The password was accepted, so CREATE.ACCOUNT
    # ran to completion and the trailing N was a stray line at TCL rather than an
    # answer to 10008.  Take it back out before going on.
    Write-Output '    That means the account was fully created.  Removing it.'
    Show-SD 'entry 22 arm B: remove the account the refusal was supposed to prevent' @(
        ('DELETE.ACCOUNT ' + $acctLong), 'Y') @()
}

# EITHER WAY THE NAME MUST BE FREE AGAIN - unwound by CREATEA on the refusal
# path, deleted by hand on the skip path.  This is a clean-up check on both.
Note '22B: nothing was left behind' $false (Test-WinUser $acctLong) $true
Note '22B: no ACCOUNTS record was left' $false `
     (Test-Path -LiteralPath (Join-Path $accts $acctLong.ToUpper())) $true

# --------------------------- 37: the two access lines name different things

Write-Output ''
Write-Output '=== PRE_RELEASE 37: the two access lines no longer contradict ============='

Show-SD 'entry 37' @(
    ('CREATE.ACCOUNT USER ' + $acctReal + ' PROGRAMMER BOTH'),
    $pwOk,
    $pwOk) @($pwOk)
$a37 = $lastSD

Note '37 null case: the account really was created' $true `
     (Test-Path -LiteralPath (Join-Path $accts $acctReal.ToUpper())) $true

# 10034 - the WINDOWS gate.  New wording: "reach this computer".
Note '37: the Windows gate speaks of reaching the computer (10034)' $true `
     (Test-Say $a37 ([regex]::Escape($acctReal) + ' may reach this computer only over ssh')) $true
# 10078 - the SD gate.  New wording: "SD routes for x".
Note '37: the SD gate speaks of SD routes (10078)' $true `
     (Test-Say $a37 ('SD routes for ' + [regex]::Escape($acctReal) + ': ssh and the API\.')) $true

# THE DISQUALIFIERS ARE THE OLD WORDING.  Both lines contained "ssh", so any
# check anchored on that would have passed on the defect; these two strings
# appear only in the messages the fix replaced.
Note '37: the old "may sign in over ssh only" is gone' $false `
     (Test-Say $a37 'may sign in over ssh only') $true
Note '37: the old "may sign in over ssh and use the API" is gone' $false `
     (Test-Say $a37 'may sign in over ssh and use the API') $true

if (-not (Test-Path -LiteralPath (Join-Path $accts $acctReal.ToUpper()))) {
    Write-Output ''
    Write-Output ('  ' + $acctReal + ' was not created, so entry 27 has no account to edit.')
    Write-Output '  Stopping here rather than measuring an audit trail nothing wrote to.'
    Write-Output ''
    $results | Format-Table -AutoSize -Wrap | Out-String | Write-Output
    Write-Verdict 'verify-acctmsgs'
    exit 2
}

# ------------------------------------------- 27: MODIFY.ACCOUNT is audited

Write-Output ''
Write-Output '=== PRE_RELEASE 27: MODIFY.ACCOUNT ADD/DELETE writes an audit record ======'

Show-SD 'entry 27 fixture: a second SD user to add' @(
    ('CREATE.ACCOUNT USER ' + $acctUser + ' PROGRAMMER BOTH'),
    $pwU,
    $pwU) @($pwU)
$a27f = $lastSD

Note '27 fixture: the user joined sdusers' $true `
     (Test-Say $a27f ([regex]::Escape($acctUser) + ' added to sdusers')) $true
if (-not (Test-Say $a27f ([regex]::Escape($acctUser) + ' added to sdusers'))) {
    Write-Output '  MODIFY.ACCOUNT ADD refuses a user who is not in sdusers (10020), so the'
    Write-Output '  edit below would never happen and the missing audit record would prove'
    Write-Output '  nothing.  That is "could not be run".'
    Write-Output ''
    $results | Format-Table -AutoSize -Wrap | Out-String | Write-Output
    Write-Verdict 'verify-acctmsgs'
    exit 2
}

# BY LENGTH, so only the bytes this run adds are read.
$before = [IO.File]::ReadAllText($audit)
Write-Output ("  audit is {0} bytes before" -f $before.Length)

Show-SD 'entry 27' @(
    ('MODIFY.ACCOUNT ' + $acctReal.ToUpper() + ' ADD ' + $acctUser),
    ('MODIFY.ACCOUNT ' + $acctReal.ToUpper() + ' DELETE ' + $acctUser)) @()
$a27 = $lastSD

$after = [IO.File]::ReadAllText($audit)
$tail  = ''
if ($after.Length -gt $before.Length) { $tail = $after.Substring($before.Length) }
Write-Output ("  audit is {0} bytes after, {1} new" -f $after.Length, $tail.Length)
Write-Output '  --- the audit records this run added ---'
foreach ($line in ($tail -split "`n")) {
    if ($line.Trim() -ne '') { Write-Output ('    | ' + $line.Trim()) }
}
Write-Output ''

# THE CONTROL COMES FIRST.  MODIFYA writes the audit record inside "if stat =
# 0", so a group edit that did not happen must not be reported as a missing
# audit record - two different findings that look identical in the trail.
Note '27 control: the ADD really happened (10018)' $true `
     (Test-Say $a27 ([regex]::Escape($acctUser) + ' added to group')) $true
Note '27 control: the DELETE really happened (10021)' $true `
     (Test-Say $a27 ([regex]::Escape($acctUser) + ' removed from group')) $true

Note '27 null case: the audit trail grew' $true ($tail.Length -gt 0) $true

# MODIFYA upper-cases acc.name (:223) and leaves user.name as typed, so the
# record's shape is asserted, not just the presence of the words.
Note '27: the ADD is in the audit trail' $true `
     (Test-Say $tail ('MODIFY\.ACCOUNT ADD account=' + [regex]::Escape($acctReal.ToUpper()) +
                      ' to=' + [regex]::Escape($acctUser))) $true
Note '27: the DELETE is in the audit trail' $true `
     (Test-Say $tail ('MODIFY\.ACCOUNT DELETE account=' + [regex]::Escape($acctReal.ToUpper()) +
                      ' from=' + [regex]::Escape($acctUser))) $true

# -------------------------------------------------------------- clean up

Write-Output ''
Write-Output '=== clean up =============================================================='

Show-SD 'clean up' @(
    ('DELETE.ACCOUNT ' + $acctReal), 'Y',
    ('DELETE.ACCOUNT ' + $acctUser), 'Y') @()
$aClean = $lastSD

foreach ($n in @($acctReal, $acctUser)) {
    Note ('clean up: ' + $n + ' Windows account is gone') $false (Test-WinUser $n) $true
    Note ('clean up: ' + $n + ' ACCOUNTS record is gone') $false `
         (Test-Path -LiteralPath (Join-Path $accts $n.ToUpper())) $true
}

# ***REPORTED FROM DISK, NOT FROM WHAT DELETE.ACCOUNT SAID.***  PRE_RELEASE 41
# is a sweep that reported "every section reached zero" while three orphan
# directories were still there, because its counter and its cleaner shared one
# enumeration.  This reads C:\Users directly.
#
# NOT DECISIVE, DELIBERATELY.  A profile directory is only created when an
# account SIGNS IN, and nothing here signs in - so there should be none, and if
# there is one that is PRE_RELEASE 35/36 and not a fault in the three fixes
# this script exists to witness.  Reported loudly instead of failed quietly.
$litter = @()
foreach ($n in $allAccts) {
    $d = Join-Path $env:SystemDrive ('Users\' + $n)
    if (Test-Path -LiteralPath $d) { $litter += $d }
    if (Test-WinUser $n)           { $litter += ('Windows account ' + $n) }
    if (Test-Path -LiteralPath (Join-Path $accts $n.ToUpper())) { $litter += ('ACCOUNTS record ' + $n.ToUpper()) }
}
if ($litter.Count -gt 0) {
    Write-Output ''
    Write-Output '  *** LEFT BEHIND - read from disk, not from what the delete reported:'
    $litter | ForEach-Object { Write-Output ('      ' + $_) }
    Write-Output '  Nothing here signed in, so a profile directory would be PRE_RELEASE 35/36.'
} else {
    Write-Output ('  nothing left behind: no account, register record or profile directory ' +
                  'for any of ' + ($allAccts -join ', '))
}

# ---------------------------------------------------------------------- report

Write-Output ''
$results | Format-Table -AutoSize -Wrap | Out-String | Write-Output

$skipped = @($results | Where-Object { $_.Result -eq 'SKIP' })
if ($skipped.Count -gt 0) {
    Write-Output ("{0} row(s) were NOT MEASURED and are not counted as passes:" -f $skipped.Count)
    $skipped | ForEach-Object { Write-Output ('    ' + $_.Check) }
}

Write-Verdict 'verify-acctmsgs'

if ($fatal) { exit 1 }
exit 0
