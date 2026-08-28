# VerifyInstall1.ps1 - the verifiers that need NO elevation, in one command
#
#   Run from an ORDINARY PowerShell.  It REFUSES an elevated one - see below.
#
# WHY IT EXISTS, 22 Aug 2026.  VerifyInstall2.ps1 runs nine verifiers and
# there were twenty-four in this directory.  Seven of the fifteen it leaves out
# need no elevation at all, which meant they could be run by anybody, at any
# time, for free - and so nobody ran them.  Between 21 Aug and 22 Aug not one of
# the seven appears in any transcript, and three of the twenty-four
# (verify-scramlogin, verify-setpw, verify-tierapi) were not named anywhere in
# PROJECT_STATUS.md at all.  That is the same failure verify-delaccount had:
# a verifier nobody runs is a guard that has already stopped guarding, and
# nothing reports its absence.
#
# IT MUST NOT BE RUN ELEVATED, AND THAT IS NOT TIDINESS.  verify-credacl.ps1
# asks whether an ORDINARY user can read or write sdsys\$cred.  secure-cred.ps1
# grants Administrators Full, so an elevated session can do both by design - it
# would pass every check while proving the opposite of what the file claims.  A
# test that passes for the wrong reason is worse than one that is not run,
# because it is believed.  The others are indifferent to the token; this one
# decides the rule, so the gate below is unconditional.
#
# IT SPENDS NO PREFIXES, which is the other reason to run it often.  Every step
# in VerifyInstall2.ps1 burns a single-use account name, so re-running it
# to check something costs seven names and an argument list.  Nothing here
# creates a Windows account: the probes live inside the invoking user's own SD
# account, or in a temporary copy of a config file, and each step cleans up
# after itself.  Run it as many times as you like.
#
# WHAT IT COVERS NOW, LATER THE SAME DAY: EVERYTHING.  This said "eight
# verifiers need elevation and are still not in either runner - apiport,
# catgate, nonet, osusers, scramlogin, sshonly, tierapi, apiname", and every one
# of those is now in a runner.  There are TWENTY-NINE verify-*.ps1 here; this
# file runs ELEVEN and hands the other EIGHTEEN to VerifyInstall2.ps1, so NONE
# is left to be remembered.  (Twenty-seven until 23 Aug 2026, when PROC, SED and
# UPDATE.RECORD were removed from the system and verify-editkeys.ps1 went with
# them - it tested nothing else.)  Checked by listing both runners' step tables against
# the directory, not by eye.
#
# 24 Aug 26 - THE COUNTS ABOVE WERE STALE AND THE INVARIANT WAS ACTUALLY
# BROKEN, which is worth more than the arithmetic.  They read 26 / 9 / 17
# while the directory held 29 and verify-lineendings.ps1 was in NEITHER
# table - written 23 Aug, never added, never run by either runner.  The
# header said this would happen "the moment a verifier is added without a
# row in one of the two tables"; it had, and the stale total is what hid
# it.  If these three numbers are edited again, re-derive them from the
# directory rather than adjusting them by one.
#
# THAT IS A PROPERTY TO KEEP, NOT A SCORE.  The failure this file was written
# for - a guard nobody runs has already stopped guarding - returns the moment a
# verifier is added without a row in one of the two tables.  Add the row in the
# same commit, the way PROJECT_STATUS.md 4.0 says to.

[CmdletBinding()]
param(
    # Keep going after a failing step.  Off by default: a failed check here
    # usually means the install is not what the last cycle left, and the next
    # step's result would be describing the same broken tree.
    [switch] $ContinueOnFailure,

    # 22 Aug 26 - HAND OVER TO VerifyInstall2.ps1 AS THE LAST ACT, so the
    # whole suite is ONE command.  Requires -Run, which is passed straight
    # through.  It raises ONE UAC prompt for the handover, on top of the ~3
    # verify-osusers raises on its own account.
    #
    #     VerifyInstall1.ps1 -ThenElevated -Run b2
    #
    # THIS IS NOT THE SAME AS COLLAPSING THE TWO RUNNERS, and the difference is
    # the whole reason it is allowed.  Two PROCESSES with the correct token
    # each: this one keeps a genuine ordinary token for verify-credacl and
    # verify-osusers, and the child gets a real elevated one from UAC.  What
    # cannot be done - and was asked and answered on 22 Aug - is the reverse,
    # an elevated parent manufacturing an ordinary child: runas /trustlevel
    # yields a RESTRICTED token, not this user's normal one, and a security
    # test answered by the wrong token is worse than one nobody runs.
    #
    # UNELEVATED FIRST IS ALSO THE BETTER ORDER, measured 22 Aug: this half
    # sees the tree closest to what the cycle left, before sixteen steps of
    # account, sd.conf and service churn.
    [switch] $ThenElevated,

    # Passed to VerifyInstall2.ps1 -Run.  Ignored without -ThenElevated.
    [string] $Run = '',

    # 22 Aug 26 - Skip the "are you sure" prompt.  For anything that is not a
    # person at a keyboard: a scripted run, or the installer, which cannot
    # answer a Read-Host and would hang for ever waiting to.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'

# 22 Aug 26 - CHECKED FIRST, because the alternative is discovering it after
# eight steps and about four UAC prompts.  VerifyInstall2.ps1 refuses
# without -Run too, but by then this half has already been spent.
if ($ThenElevated -and (-not $Run)) {
    Write-Output 'VerifyInstall1: -ThenElevated needs -Run <token>, which is passed straight through.'
    Write-Output '  Pick one nobody has used; the elevated runner checks all thirteen derived'
    Write-Output '  names against Get-LocalUser before it runs anything.'
    Write-Output ''
    Write-Output '      VerifyInstall1.ps1 -ThenElevated -Run b2'
    exit 2
}
if ($Run -and ($Run -notmatch '^[a-z0-9]+$')) {
    Write-Output ("VerifyInstall1: -Run is '{0}'." -f $Run)
    Write-Output '  Lower case letters and digits only - it becomes part of a Windows account name.'
    exit 2
}

# ---------------------------------------------------------------------------
# THE GATE.  Refuse elevation outright, for the verify-credacl reason above.
if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'VerifyInstall1: this is an ELEVATED PowerShell, and these checks need an ordinary one.'
    Write-Output ''
    Write-Output '  verify-credacl.ps1 asks whether an ORDINARY user can read or write sdsys\$cred.'
    Write-Output '  Administrators are granted Full by secure-cred.ps1, so an elevated run would pass'
    Write-Output '  every check and prove the opposite of what it claims.  Open a normal PowerShell.'
    exit 2
}

# ---------------------------------------------------------------------------
# 22 Aug 26 - IS SD ACTUALLY RUNNING?  The same guard as the elevated runner and
# for the same reason: assert-current compares hashes and mtimes, so a STOPPED
# server is perfectly "current" and every verifier prints a green
# "matches source" line immediately before failing on its first SD command.
#
# Five of the seven steps here drive real SD sessions (credacl is the exception,
# and allowgroups touches only a copy of sshd_config), so a stopped server fails
# most of this file one step at a time.
#
# IT REFUSES RATHER THAN STARTING IT - and here it could not start it anyway:
# this runner deliberately holds an UNELEVATED token, which cannot start a
# service.  Saying so plainly beats five identical failures.
$svc = Get-Service -Name 'SD' -ErrorAction SilentlyContinue
$sdwind = @(Get-Process -Name 'sdwind' -ErrorAction SilentlyContinue)
if ((-not $svc) -or ($svc.Status -ne 'Running') -or ($sdwind.Count -eq 0)) {
    Write-Output 'VerifyInstall1: REFUSING - SD is not running.'
    Write-Output ("  service: {0}    sdwind processes: {1}" -f
                  $(if ($svc) { $svc.Status } else { 'not installed' }), $sdwind.Count)
    Write-Output ''
    Write-Output '  Starting it needs elevation, which this runner does not have by design.'
    Write-Output '  From an ELEVATED shell:   C:\Windows\System32\sc.exe start SD'
    exit 2
}

# ---------------------------------------------------------------------------
# 22 Aug 26 - SAY WHAT THIS IS ABOUT TO DO, AND ASK.  Owner's instruction.  It
# runs for several minutes, creates and deletes Windows accounts, restarts the
# SD service and asks for elevation more than once - none of which a person
# should discover halfway through.
#
# THE INSTALL LOCATION IS ASSUMED, AND SINCE 22 Aug IT IS PINNED.  Everything
# below finds SD at "$env:ProgramFiles\SD"; sd.iss now sets DisableDirPage and
# UsePreviousAppDir=no so there is no other answer.  The check is kept anyway,
# because an install made BEFORE that change can still be somewhere else, and a
# suite that cannot find sd.exe should say so in one line rather than in
# twenty-four.
$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output ('VerifyInstall1: SD is not where these scripts look for it - ' + $sdExe)
    # Inno records the real location; read it rather than guessing.
    foreach ($k in @('HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                     'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*')) {
        Get-ItemProperty $k -ErrorAction SilentlyContinue |
            Where-Object { $_.DisplayName -like 'SD *' -and $_.InstallLocation } |
            ForEach-Object { Write-Output ('  the installer recorded: ' + $_.InstallLocation) }
    }
    Write-Output '  These scripts hardcode Program Files (21 of them, and assert-current.ps1).'
    Write-Output '  Reinstall to the default location, or move the install back.'
    exit 2
}

if (-not $Yes) {
    Write-Output ''
    Write-Output '  VerifyInstall1 - does this SD installation actually work?'
    Write-Output '  ---------------------------------------------------------------------'
    Write-Output '  It runs the checks that need an ORDINARY account, then hands over to'
    Write-Output '  VerifyInstall2 for the ones that need an administrator.  Together they'
    Write-Output '  exercise account creation and deletion, the permission tiers, the file'
    Write-Output '  and catalogue ACLs, ssh and API logins, and the audit trail.'
    Write-Output ''
    Write-Output '  BEFORE YOU SAY YES, it will:'
    Write-Output '    * take several minutes, and look idle for stretches of it'
    Write-Output '    * CREATE AND DELETE Windows user accounts and groups, named from -Run'
    Write-Output '    * RESTART THE SD SERVICE more than once, so log anyone else out first'
    Write-Output '    * ask for elevation about four times - it is not unattended'
    Write-Output ('    * write what it finds under ' + (Join-Path $env:LOCALAPPDATA 'SD-verify'))
    Write-Output ''
    Write-Output '  It puts back what it changes.  Nothing here alters your own data.'
    Write-Output ''
    # 22 Aug 26 - Read-Host DOES NOT SIMPLY FAIL TO ANSWER when nobody is there.
    # Measured: in a NonInteractive host it THROWS - "Windows PowerShell is in
    # NonInteractive mode.  Read and Prompt functionality is not available" -
    # and under the installer's Exec with SW_HIDE there is no console to type
    # into at all.  Either way the caller gets a stack trace or a hang instead
    # of a result, so the absence of a person is caught and NAMED here.
    $answer = $null
    try   { $answer = Read-Host '  Run the checks now? (y/n)' }
    catch {
        Write-Output ''
        Write-Output 'VerifyInstall1: nothing is available to answer that question.'
        Write-Output '  This host cannot prompt, so the run needs the decision made up front:'
        Write-Output ''
        Write-Output '      VerifyInstall1.ps1 -Yes -ThenElevated -Run <token>'
        Write-Output ''
        Write-Output '  Nothing was run.'
        exit 2
    }
    if ($answer -notmatch '^(y|yes)$') {
        Write-Output '  Nothing was run.'
        exit 0
    }
}

# The same transcript reasoning as cycle.ps1 and the elevated runner: a run
# whose output is not kept is a run that has to be repeated to be quoted.  Not
# under C:\ProgramData\SD, which a cycle deletes.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$summary = Join-Path $logDir ('post-cycle-unelevated-' + $stamp + '.txt')

# 22 Aug 26 - AND IT NOW ACTUALLY KEEPS ONE.  The paragraph above claimed "the
# same transcript reasoning as cycle.ps1 and the elevated runner" and then kept
# only the SUMMARY - sixteen words of exit codes - while both of those keep the
# whole run.  So a failing unelevated step left its exit code and nothing else.
#
# IT MATTERED FOR FOUR OF THE EIGHT.  verify-allowgroups, verify-credacl,
# verify-nocase and verify-setpw are the only verifiers with no Start-Transcript
# of their own, so on this path their detail reached a console and stopped
# there.  The other four write their own and were never at risk, which is why
# nothing had noticed.
#
# THE FILE'S OWN HEADER IS THE ARGUMENT FOR THIS: it justifies its existence by
# observing that "not one of the seven appears in any transcript" - using the
# transcript trail as the evidence that a guard had stopped guarding - while
# leaving no such trail behind itself.
$transcript = Join-Path $logDir ('VerifyInstall1-' + $stamp + '.log')
# 24 Aug 26 - CLOSE ANY TRANSCRIPT THIS WINDOW ALREADY HAS OPEN, FIRST.
# PowerShell 5.1 keeps a transcript ACTIVE until it is stopped or the session
# ends, and supports several at once - every active one receives every line.
# So a run in a window where an earlier run left one open writes into BOTH.
#
# MEASURED 24 Aug 2026, twice.  After the 15:13:25 cycle,
# cycle-20260824-133558.log held two complete cycles.  Then at 15:53, one
# verify-tierapi run appended itself to cycle-20260824-133558.log,
# cycle-20260824-151325.log AND verify-tiers-20260824-134341.log - three logs
# from earlier runs, all still open in that window, all growing at once.
#
# Stopping the stale ones here is what bounds it: at most one transcript is
# active, and it is this run's.  Stop-Transcript throws when none is running,
# which is the loop's exit condition and is not an error.
$stale = 0
while ($true) {
    try { Stop-Transcript -ErrorAction Stop | Out-Null; $stale++ } catch { break }
}
if ($stale -gt 0) {
    Write-Output ("closed $stale transcript(s) this window had left open")
}
try { Start-Transcript -Path $transcript -Force | Out-Null } catch { }
Write-Output ("transcript: " + $transcript)

# ---------------------------------------------------------------------------
# ORDER.  verify-credacl first, because it is the one that decides a security
# rule and the one the gate above exists for: if the session is somehow still
# privileged, it fails here rather than after six passing steps have suggested
# the tree is fine.  The rest are independent of each other - none creates an
# account, and each cleans up what it made - so the remaining order is only
# cheapest-first, to fail fast on a stale tree.
#
# Name => hashtable of parameters, splatted by NAME.  An empty hashtable means
# "no arguments", which splats correctly too.  See VerifyInstall2.ps1's
# comment for why this is a hashtable and not an array: an array binds
# POSITIONALLY and silently gave verify-tiers.ps1 a $Prefix of "-Prefix".
$steps = @(
    @{ Name = 'verify-credacl.ps1';     P = @{} },
    # 23 Aug 26 - section 7 step 15's guard, and it sits DIRECTLY BESIDE
    # verify-credacl for that step's reason: both ask what an ORDINARY token
    # can write, both are meaningless from an elevated one, and both refuse
    # elevation themselves rather than trusting this runner's gate.  It spends
    # no prefix, creates no account, and cleans up the one file it makes.
    @{ Name = 'verify-pcodeacl.ps1';    P = @{} },
    # 24 Aug 26 - section 7 step 15's second guard, and it sits here for the
    # same reason verify-pcodeacl does: it asks what an ORDINARY token can
    # write, it is meaningless from an elevated one, and it refuses elevation
    # itself rather than trusting this runner's gate.  It spends no prefix,
    # creates no account, and removes the probe files it makes.
    #
    # IT CARRIES A NEGATIVE CONTROL, which is why it is worth a row of its own
    # rather than being folded into the step above: $ipc must come back
    # WRITABLE.  Without that, a run where something locked the whole data
    # tree - breaking every session - would score exactly like a healthy one.
    @{ Name = 'verify-sysdiracl.ps1';   P = @{} },
    # 22 Aug 26 - MOVED HERE FROM VerifyInstall2.ps1, WHERE IT EXITED 2
    # WITHOUT MEASURING ANYTHING.  verify-osusers.ps1:243 refuses an elevated
    # window: "CPROC admits K$ADMINISTRATOR whatever OS.USERS says, so an
    # elevated run is admitted by elevation and says nothing about the list."
    # That is verify-credacl's reason in a different guise, which is why the
    # two sit together.
    #
    # IT PROMPTS FOR UAC TWICE, by its own design - it starts unelevated as the
    # account holder and asks for elevation only for the steps that write
    # OS.USERS.  So this runner is NOT unattended once it reaches this step.
    # It is second so that the prompt comes early rather than after five
    # silent minutes.
    @{ Name = 'verify-osusers.ps1';     P = @{} },
    @{ Name = 'verify-nocase.ps1';      P = @{} },
    @{ Name = 'verify-setpw.ps1';       P = @{} },
    @{ Name = 'verify-allowgroups.ps1'; P = @{} },
    @{ Name = 'verify-keys.ps1';        P = @{} },
    @{ Name = 'verify-lcnames.ps1';     P = @{} },
    # 24 Aug 26 - section 7 step 16's guard, and IT WAS IN NEITHER RUNNER
    # from the day it was written (23 Aug) until now.  That is precisely
    # the failure this file's header describes - "a verifier nobody runs
    # is a guard that has already stopped guarding, and nothing reports
    # its absence" - reached by the route the header warns about: a
    # verifier added without a row in either step table.  Found by
    # listing both tables against the directory, which is what that
    # header says to do and what nobody had done since.
    #
    # IT BELONGS HERE: no elevation, no prefix, no account, and it
    # cleans up its own fixtures.  It raises no UAC prompt, so it does
    # not change what this runner costs a person to sit through.
    # Measured on the 15:14:28 install before being added, 17/17 PASS,
    # so it is not being wired in untested.
    @{ Name = 'verify-lineendings.ps1'; P = @{} },
    # 22 Aug 26 - section 7 step 12's guard.  It belongs in THIS runner rather
    # than VerifyInstall2: it spends no prefix, creates nothing, and needs no
    # elevation, which is this file's whole entry condition.
    @{ Name = 'verify-parsertokens.ps1'; P = @{} },
    # 22 Aug 26 - section 7 step 9's guard, and it is here for the same reason
    # verify-osusers is: the measurement MUST be made with an ordinary token,
    # because an elevated session passes the batch gate on its own.  IT RAISES
    # TWO UAC PROMPTS ITSELF, for the two steps that write SDSYS batch.jobs -
    # so this runner now costs about five in total rather than three.
    @{ Name = 'verify-batchjob.ps1';     P = @{} }
)

# 28 Aug 26 - THE SUSPENDED DOOR PAIR, AS ONE STEP.  PRE_RELEASE 38, on the
# owner's ruling of 28 Aug 2026.  It is LAST, and it is CONDITIONAL on -Run.
#
# WHY IT IS IN THIS RUNNER AND NOT THE ELEVATED ONE.  Its five phases need
# ALTERNATING tokens - Create elevated, Control ordinary, Suspend elevated,
# Refused ordinary, Remove elevated - and an elevated parent cannot make an
# ordinary child (line 70 above: runas /trustlevel gives a RESTRICTED token,
# not this user's normal one).  So the ordinary half has to be the PARENT, and
# that is this file.  verify-doors-suite.ps1 raises the three elevated children.
#
# LAST, because it is the only step here that creates a Windows account, and
# every step before it should see the tree the cycle left rather than one this
# runner has churned - the same reason this runner precedes VerifyInstall2.
#
# ***CONDITIONAL, AND THE REASON IS NOT TIDINESS.***  The prefix becomes an
# account name, and it is SINGLE-USE: the Control leg signs in over ssh, which
# leaves a profile directory DELETE.ACCOUNT cannot remove while its hive is
# mounted (PRE_RELEASE 35/36), and Windows gives a rebuilt account a SUFFIXED
# home instead.  Without -Run there is no token to derive a fresh name from,
# and calling a Mandatory -Prefix with nothing would PROMPT - which inside a
# runner is a hang, not an error.  That trap cost a run on 28 Aug 2026.
#
# IT ADDS THREE UAC PROMPTS to this runner's five.
if ($Run) {
    # 28 Aug 26 - BUILT AND COUNTED, not appended with a bare +.  A hashtable
    # on the right of + is folded into the array as one element only if it is
    # wrapped first; the count is asserted below rather than assumed.
    $doorStep = @{ Name = 'verify-doors-suite.ps1'; P = @{ Prefix = "sddr$Run" } }
    $before = @($steps).Count
    $steps  = @($steps) + @($doorStep)
    if (@($steps).Count -ne ($before + 1)) {
        Write-Output ("VerifyInstall1: the step list is {0} after adding one to {1}." -f
                      @($steps).Count, $before)
        exit 2
    }
} else {
    Write-Output 'VerifyInstall1: no -Run, so the SUSPENDED door pair is NOT in this run.'
    Write-Output '  It creates a Windows account and its prefix is single-use, so it needs a'
    Write-Output '  token to derive a fresh name from.  Add -Run <token> to include it.'
}

$lines  = @()
$failed = 0
foreach ($s in $steps) {
    $path = Join-Path $PSScriptRoot $s.Name
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Output ''
        Write-Output ('===== ' + $s.Name + ' - NOT FOUND, skipped =====')
        $lines += ('{0,-28} {1}' -f $s.Name, 'NOT FOUND')
        $failed++
        continue
    }
    Write-Output ''
    Write-Output ('===== ' + $s.Name + ' =====')
    $splat = $s.P
    & $path @splat
    $code = $LASTEXITCODE

    # 28 Aug 26 - CLOSE WHAT THE STEP LEFT OPEN, AND SAY SO.  PRE_RELEASE 40.
    #
    # A verifier that calls Start-Transcript and exits without stopping it leaves
    # it open ON THIS PROCESS - the steps run in the runner's own session - so it
    # goes on recording every verifier that follows.  Measured 27 Aug 2026:
    # verify-sshonly-20260827-232336.log carried verify-apiadmin's two [FAIL]
    # rows and the whole suite's summary from six verifiers later, and a wrong
    # per-verifier count was issued and withdrawn on exactly that.
    #
    # ***FIXED HERE RATHER THAN IN FIFTEEN VERIFIERS, ON PURPOSE.***  The entry
    # proposed a try/finally around each verifier's body; this is one place, it
    # cannot be forgotten by the next verifier somebody writes, and it also
    # covers the case a try/finally does not - a step that dies outright.
    #
    # AND IT REPORTS RATHER THAN TIDYING SILENTLY.  A leak is a defect in the
    # step that leaked, and a fix that hides it would leave nobody any way to
    # find out which one.  Stop-Transcript throws when none is running: that is
    # the loop's exit condition, not an error.
    $leaked = 0
    while ($true) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null; $leaked++ } catch { break }
    }
    # THE RUNNER'S OWN TRANSCRIPT IS AMONG THEM and has to come back, or every
    # step after the first would go unrecorded.  -Append, so the file is one
    # continuous record rather than being truncated per step.
    try { Start-Transcript -Path $transcript -Append | Out-Null } catch { }
    if ($leaked -gt 1) {
        Write-Output ("  NOTE: {0} left {1} transcript(s) open - PRE_RELEASE 40. Closed." -f
                      $s.Name, ($leaked - 1))
    }

    if ($code -ne 0) { $failed++ }
    $lines += ('{0,-28} exit {1}' -f $s.Name, $code)

    if ($code -ne 0 -and -not $ContinueOnFailure) {
        Write-Output ''
        Write-Output ("VerifyInstall1: STOPPING - {0} exited {1}." -f $s.Name, $code)
        Write-Output '  Re-run with -ContinueOnFailure to see the rest anyway.'
        break
    }
}

Write-Output ''
Write-Output '===== post-cycle-unelevated summary ====='
$lines | ForEach-Object { Write-Output $_ }
$lines | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ''
Write-Output ('summary written to: ' + $summary)

if ($failed -gt 0) {
    Write-Output ("VerifyInstall1: {0} step(s) did not exit 0." -f $failed)
    if ($ThenElevated) {
        Write-Output '  NOT handing over to VerifyInstall2.ps1 - fix these first, or'
        Write-Output '  re-run with -ContinueOnFailure to hand over anyway.'
        if (-not $ContinueOnFailure) { exit 1 }
    } else { exit 1 }
} else {
    Write-Output 'VerifyInstall1: every step exited 0.'
}

if (-not $ThenElevated) { exit ([int]($failed -gt 0)) }

# ---------------------------------------------------------------------------
# THE HANDOVER.  One UAC prompt, then the elevated runner in its own process
# with its own token.
#
# -RedirectStandardOutput CANNOT BE USED WITH -Verb, so the redirection goes
# INSIDE the child instead - "& '<script>' ... *> '<log>'".  PowerShell refuses
# the combination outright; this is not a preference.
#
# AND THE CHILD'S WINDOW CLOSES WHEN IT FINISHES, taking its scrollback with
# it, so -Quiet is passed as well: without it the only record of seventeen
# steps would be the summary file, and every failing check would be gone.  With
# it, each step's full output is already in its own file before the window
# goes.
#
# ABSOLUTE PATHS THROUGHOUT.  An elevated child starts in C:\WINDOWS\system32,
# which is the trap cycle.ps1's header records costing a run - "ISCC WAS RUN
# FROM C:\WINDOWS\system32, where gplbld\sd.iss does not resolve".
$elevated = Join-Path $PSScriptRoot 'VerifyInstall2.ps1'
if (-not (Test-Path -LiteralPath $elevated)) {
    Write-Output ("VerifyInstall1: -ThenElevated, but {0} is not there." -f $elevated)
    exit 2
}

$elevLog = Join-Path $logDir ('post-cycle-elevated-' + $stamp + '.log')
Write-Output ''
Write-Output '===== handing over to VerifyInstall2.ps1 ====='
Write-Output ("  -Run {0}" -f $Run)
Write-Output ('  output: ' + $elevLog)
Write-Output '  EXPECT A UAC PROMPT NOW - approving it is what elevates the child.'

# 22 Aug 26 - Tee-Object, NOT "*> file".  Owner, watching the elevated window
# through a whole run: "it is not printing the steps", "it is also supposed to
# print any failures".  Both true, and this line was why.
#
# -Quiet's contract (VerifyInstall2.ps1:456) is "FULL OUTPUT TO A FILE PER STEP,
# PROGRESS AND FAILURES ON THE SCREEN", and it writes every one of those with
# Write-Host - the progress line, ' OK'/' FAILED', the [FAIL] lines and the
# dying step's last 8 lines.  WRITE-HOST GOES TO THE INFORMATION STREAM in
# PowerShell 5+, "*>" captures all six streams, so the whole of it went into
# the file and the window sat blank for ten minutes looking hung.
#
# VerifyInstall2.ps1:500 STATES THIS EXACT MECHANIC for the inner redirect -
# "Write-Host goes to the INFORMATION stream in PowerShell 5+, which is why it
# is caught here".  The knowledge was there and was not carried one level up.
#
# AND THE EXIT CODE HAD TO BE RESTATED, WHICH IS NOT WHAT WAS EXPECTED.  The
# reasoning written here first was that "*>" propagates the script's code and a
# PIPELINE would lose it, so the explicit exit was insurance.  MEASURED, WITH A
# SCRIPT THAT EXITS 7, and the first half was simply wrong:
#
#   & probe *> log                                  -> child exit 1
#   & probe *>&1 | Tee-Object -FilePath log         -> child exit 1
#   & probe *>&1 | Tee-Object -FilePath log; exit $LASTEXITCODE  -> child exit 7
#
# "*>" NEVER CARRIED THE CODE EITHER.  powershell -Command answers 1 for any
# non-zero, and the b2 run's "VERIFYINSTALL1 EXIT: 1" looked like proof it
# worked ONLY BECAUSE VerifyInstall2's failure code is also 1.  Two different
# things collide on the same number and the coincidence hid the fault.
#
# WHAT THAT COST, and it is the reason this matters rather than a tidy-up:
# VerifyInstall2 has NINE "exit 2" paths - unusable -Run token, prefix already
# spent, SD not running - against ONE "exit 1" (:563).  This script reports the
# child's code as its own (:381), so every "THE SUITE COULD NOT RUN" was
# delivered as "A STEP FAILED".  A reused prefix and a broken product are
# opposite conclusions and they were indistinguishable from the exit code.
#
# So the explicit exit is not insurance against the pipeline.  It is the only
# thing that has ever made this code mean what it says.
#
# '; exit $LASTEXITCODE' IS CONCATENATED AS A SINGLE-QUOTED LITERAL and is not
# part of the -f string: inside double quotes PowerShell would substitute THIS
# shell's $LASTEXITCODE when the string is built, freezing the child's verdict
# to whatever the parent last did.
#
# WHAT IT COSTS: Write-Host's red and green do not survive the pipeline, so the
# failures print in plain text.  The words still say FAILED; only the emphasis
# goes.  The -NoNewline on the progress line was already not holding under "*>"
# - the log shows '[ 1/16] verify-fold' and ' OK' on separate lines - so that is
# unchanged rather than newly broken.
$inner = ("& '{0}' -Run '{1}' -Quiet *>&1 | Tee-Object -FilePath '{2}'" `
            -f $elevated, $Run, $elevLog) + '; exit $LASTEXITCODE'
try {
    $child = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-Command', $inner) `
                -Verb RunAs -Wait -PassThru -ErrorAction Stop
} catch {
    # THE CANCELLED-PROMPT PATH.  Declining UAC throws here rather than
    # returning a code, and the raw exception says only "The operation was
    # canceled by the user" - which is also what a DESKTOP-LESS shell gets when
    # no prompt can be shown at all (VerifyInstall2.ps1's header, 19 Aug).
    # The two are indistinguishable from the message, so name both.
    Write-Output ''
    Write-Output ('VerifyInstall1: the elevated half did not start - ' + $_.Exception.Message)
    Write-Output '  Either the UAC prompt was declined, or this shell has no desktop to show'
    Write-Output '  one on.  The unelevated results above still stand.  To run the other half:'
    Write-Output ("      {0} -Run {1}" -f $elevated, $Run)
    exit 1
}

Write-Output ('post-cycle-elevated exited ' + $child.ExitCode)
if (Test-Path -LiteralPath $elevLog) {
    Write-Output ''
    Get-Content -LiteralPath $elevLog | Select-String -Pattern '^\[|FAILED|did not exit 0|all \d+ steps exited' |
        ForEach-Object { Write-Output ('  ' + $_.Line) }
    Write-Output ''
    Write-Output ('  full elevated output: ' + $elevLog)
}
exit $child.ExitCode
