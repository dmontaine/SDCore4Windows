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
# IT SPENDS NO PREFIXES WITHOUT -Run, which is the other reason to run it often.
# Every step in VerifyInstall2.ps1 burns a single-use account name, so
# re-running it to check something costs seven names and an argument list.
# Without -Run nothing here creates a Windows account: the probes live inside
# the invoking user's own SD account, or in a temporary copy of a config file,
# and each step cleans up after itself.
#
# 29 Aug 26 - THAT SENTENCE SAID "IT SPENDS NO PREFIXES" FLATLY AND HAD BEEN
# UNTRUE SINCE 28 Aug, when the door pair arrived and derived sddr<Run> from
# the token.  PRE_RELEASE 59 adds a second, sdtu<Run>.  BOTH NAMES ARE
# SINGLE-USE - an ssh sign-in leaves a profile directory DELETE.ACCOUNT cannot
# remove while its hive is mounted (PRE_RELEASE 35/36) - so a -Run token is
# spent by this runner as surely as by the elevated one, and re-using one is
# refused rather than being made to work.  WITH -Run, run it once per token.
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
# 04 Sep 26 - RE-DERIVED AGAIN, on adding verify-localconnect.ps1
# (PRE_RELEASE_FIXES 163).  THE BLOCK BELOW READ 47 / 19 / 24 AND WAS STALE IN
# TWO COLUMNS, not one: this file gained verify-localconnect and VerifyInstall2
# had already gained verify-privundetermined.  Adjusting by one would have left
# the arithmetic wrong and hidden the second change, which is the whole reason
# the rule says re-derive:
#
#     49 verify-*.ps1 in the directory
#     20 named in this file           (19 before verify-localconnect)
#     25 named in VerifyInstall2.ps1  (24 before verify-privundetermined)
#     -- 45 accounted for, FOUR not named in either table, AND ALL FOUR ARE
#        CORRECTLY OUT - the same four as the previous re-derivation, checked
#        rather than assumed:
#
#   verify-doors.ps1, verify-doors-admin.ps1  CHILDREN of verify-doors-suite.ps1
#   verify-acctmsgs.ps1                       a child of those and of
#                                             verify-tierchange.ps1
#   verify-upgrade.ps1                        CANNOT be a step: a two-phase
#                                             hand-run (-Snapshot, install over
#                                             the top, -Compare) that brackets
#                                             an installer run
#
# AND NO FILE IS IN BOTH TABLES, checked the same way and none found.
#
# (The superseded 4 Sep block follows, kept because its reasoning stands.)
# 04 Sep 26 - RE-DERIVED FROM THE DIRECTORY, NOT ADJUSTED BY ONE, on adding
# verify-editors.ps1 (PRE_RELEASE 66).  The 31 Aug figures below it read 44 /
# 17 / 22 and were stale in every column, which is what re-deriving is for:
#
#     47 verify-*.ps1 in the directory
#     19 named in this file           (18 before verify-editors)
#     24 named in VerifyInstall2.ps1
#     -- 43 accounted for, FOUR not named in either table, AND ALL FOUR ARE
#        CORRECTLY OUT - checked one at a time rather than counted:
#
#   verify-doors.ps1, verify-doors-admin.ps1  CHILDREN of verify-doors-suite.ps1
#   verify-acctmsgs.ps1                       a child of those and of
#                                             verify-tierchange.ps1
#   verify-upgrade.ps1                        CANNOT be a step: a two-phase
#                                             hand-run (-Snapshot, install over
#                                             the top, -Compare) that brackets
#                                             an installer run
#
# ***verify-vocverbs.ps1 WAS IN THAT LIST AND IS NOW A STEP OF ITS OWN IN
# VerifyInstall2*** - which is why the count of correctly-out files went five to
# four while the directory grew.  Adjusting the old numbers by one would have
# hidden that and left the arithmetic wrong in the other direction.
#
# AND NO FILE IS IN BOTH TABLES, checked the same way.  A verifier named twice
# would run twice, spend two prefixes from one token, and the second run would
# fail on residue the first left - which reads as a product defect.
#
# (The superseded 31 Aug block follows, kept because its rule is the one above.)
# 31 Aug 26 - RE-DERIVED FROM THE DIRECTORY, NOT ADJUSTED BY ONE, on adding
# verify-basicfuncs.ps1 (PRE_RELEASE 106).  THE NUMBERS ABOVE WERE STALE AGAIN
# AND THE ARITHMETIC NO LONGER CLOSES, which is the point of re-deriving:
#
#     44 verify-*.ps1 in the directory
#     17 named in this file           (16 before verify-basicfuncs)
#     22 named in VerifyInstall2.ps1  (21 before verify-tierchange)
#     -- 39 accounted for, FIVE not named in either table, AND ALL FIVE ARE
#        CORRECTLY OUT - checked one at a time rather than counted:
#
#   verify-doors.ps1, verify-doors-admin.ps1  CHILDREN of verify-doors-suite.ps1
#   verify-acctmsgs.ps1, verify-vocverbs.ps1  children of those and of
#                                             verify-tierchange.ps1
#   verify-upgrade.ps1                        CANNOT be a step: a two-phase
#                                             hand-run (-Snapshot, install over
#                                             the top, -Compare) that brackets
#                                             an installer run
#
# ***THE SIXTH WAS verify-tierchange.ps1 AND IT IS NOW WIRED INTO
# VerifyInstall2*** (PRE_RELEASE 107, owner's ruling 31 Aug 2026).  It was
# genuinely orphaned and it is the PARENT of the two children above, so one
# step put THREE verifiers back.  Do not fix a mismatch here by editing a
# number - re-derive all three from the directory, which is how 107 was found.
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

    # 30 Aug 26 - RUN ONLY THE NAMED STEP(S).  Owner's ruling, 30 Aug 2026,
    # after b73, b74 and b75 each cost about twenty minutes: "add -Only, and
    # drop the full run to milestones".
    #
    #     VerifyInstall1.ps1 -Only verify-lcnames
    #     VerifyInstall1.ps1 -Only verify-nocase,verify-lineendings
    #
    # Comma or semicolon separated, with or without .ps1, case-insensitive.
    # THE FILTER IS SHARED WITH VerifyInstall2 (suite-only.ps1) rather than
    # written twice - see its header for why, and for what it refuses.
    #
    # ***A PARTIAL RUN SAYS SO, EVERYWHERE IT REPORTS.***  The banner, the
    # summary and the closing line all carry PARTIAL, and the closing line never
    # reads "every step exited 0" on one.  A partial green that reads like a
    # full one is the exact shape this project keeps being caught by.
    #
    # IT DOES NOT COMBINE WITH -ThenElevated, deliberately, and the check below
    # says so with both commands spelled out.  The two halves own different step
    # names, so a single -Only would have to be validated against a list this
    # runner cannot see without starting the other one - and "name not in THIS
    # half" and "name not in EITHER half" are different answers that must not be
    # guessed between.  Run the elevated half directly for a targeted step.
    #
    # 31 Aug 26 - [string[]] SO BOTH SHELL FORMS BIND.  As [string] this refused
    # the documented multi-name form outright: PowerShell parses "a,b" in
    # argument position as an ARRAY before binding, so -Only a,b died with
    # "Cannot process argument transformation on parameter 'Only'" and only
    # -Only 'a,b' worked.  CLAUDE.md documents "-Only <step[,step]>" with every
    # example single-name, so the quoting requirement appeared nowhere and cost
    # a round trip the first time the two-name form was used in anger.
    #
    # THE FILTER IS UNCHANGED AND STILL TAKES A STRING.  The array is joined
    # with a comma at the call site below and suite-only.ps1 splits on [,;] as
    # it always did - one copy of the filter, and its 48 unit tests still drive
    # exactly what runs.  An empty array and @('') are both falsy in PowerShell
    # and both join to '', so -Only and -Only '' stay pass-throughs.
    [string[]] $Only = @(),

    # 22 Aug 26 - Skip the "are you sure" prompt.  For anything that is not a
    # person at a keyboard: a scripted run, or the installer, which cannot
    # answer a Read-Host and would hang for ever waiting to.
    [switch] $Yes,

    # 04 Sep 26 - PRE_RELEASE 165.  KEEP THE OLD ROUTE: a UAC prompt per
    # elevated step, which is what every run before b119 did.
    #
    # ***IT EXISTS FOR THE REASON verify-doors-suite.ps1's -NoHelper DOES***, and
    # that reason is written into PRE_RELEASE 48: "a rework of how a suite
    # elevates should not be the only way to run it the week it lands".  The
    # elevate-once path is new; this is the one the suite has gone green on
    # since b53, and it is one switch away if the new one misbehaves.
    [switch] $NoHelper
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

# 30 Aug 26 - CHECKED HERE FOR THE SAME REASON -ThenElevated IS: before anything
# is spent.  See the -Only parameter comment for why the two do not combine.
if ($Only -and $ThenElevated) {
    Write-Output 'VerifyInstall1: -Only and -ThenElevated do not combine.'
    Write-Output '  The two halves own different step names, so one -Only cannot be checked'
    Write-Output '  against both without starting the other runner - and "not in this half"'
    Write-Output '  and "not in either half" are different answers to guess between.'
    Write-Output ''
    Write-Output '  For a step in THIS half, unelevated:'
    Write-Output '      VerifyInstall1.ps1 -Only <step>'
    Write-Output ''
    Write-Output '  For a step in the ELEVATED half, from an ELEVATED PowerShell:'
    Write-Output '      VerifyInstall2.ps1 -Run <token> -Only <step>'
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
    Write-Output '      including a NON-ADMINISTRATOR test account the ordinary-user checks'
    Write-Output '      run as, made once at the start and removed at the end'
    Write-Output '    * RESTART THE SD SERVICE more than once, so log anyone else out first'
    Write-Output '    * ask for elevation ONCE, at the start, and then not again'
    Write-Output '      (-NoHelper puts back the old prompt-per-step route)'
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
    # 30 Aug 26 - FIRST, AND IT IS THE ONLY STEP THAT COULD BE.
    # PRE_RELEASE_FIXES 82.  It is not a verifier: it reads
    # ..\sdsys\newvoc in the SOURCE tree and the two tier verifiers beside it,
    # re-derives all three VOC counts, and checks each file against the
    # directory.  No install, no elevation, no account, no prefix, no run
    # token, and under a second.
    #
    # WHY IT IS WORTH A STEP AT ALL.  A stale tier count does not fail here -
    # it fails at verify-tiers and verify-tierapi, two of the most expensive
    # steps in the suite, one of them LAST in the elevated half.  On 30 Aug 2026
    # -Run b70 was spent discovering that verify-tierapi still carried 416 after
    # 78 took ADMINISTRATOR to 419; this file, run afterwards, named it in under
    # a second.  It had been written on 28 Aug for that exact failure and was
    # wired into nothing, so the guard sat unrun while the failure it was
    # written for happened again.
    #
    # ***IT DOES NOT WEAKEN verify-credacl's CLAIM TO BE FIRST***, which the
    # comment above states and which matters: credacl fails if this session is
    # somehow privileged, and must do so before passing steps suggest the tree
    # is fine.  This step cannot pass or fail on privilege - it never looks at a
    # token, an ACL or the installed tree - so a green line from it says nothing
    # about the thing credacl is guarding.  It says the SOURCE is
    # self-consistent, which is a different claim and is a precondition for
    # believing either tier step later.
    @{ Name = 'test-tiercounts-units.ps1'; P = @{} },
    # 30 Aug 26 - PRE_RELEASE 86's unbuilt recommendation, and it is here for the
    # REASON THE STEP ABOVE GIVES, not by analogy with it: a guard that exists
    # and runs nowhere is what let 86 happen at all.  clean-test-profiles.ps1
    # carries a hand-kept stem list, a verifier that invents a name family must
    # add its stem there, and that has now been missed FOUR TIMES over three
    # occasions - sddr (45), sdgate and sdtu (86), sdprof and sdsw (found by this
    # file on its first run).
    #
    # ***IT FAILS THE QUIET WAY, WHICH IS WHY IT HAS TO BE A STEP.*** An
    # uncovered name is not refused and not counted; the sweep never sees it, so
    # cleanup-devlitter.ps1 reports a clean run over a machine still carrying the
    # litter and nothing anywhere goes red.  86 was only ever found because
    # somebody counted C:\Users against the pattern by hand, once.
    #
    # SAME STANDING AS THE STEP ABOVE with respect to verify-credacl: it reads
    # two source files and compares them, and never looks at a token, an ACL or
    # the installed tree - so it cannot pass or fail on privilege and does not
    # dilute credacl's claim to be the first thing that can.
    @{ Name = 'test-stemcoverage-units.ps1'; P = @{} },
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
    # 04 Sep 26 - PRE_RELEASE 66's standing guard: are the full-screen editors
    # BUNDLED, and does gpl.bp/EDIT's find.editor resolve the bundled copy
    # rather than whatever winget left on PATH?  No account, no prefix, no run
    # token; it reads the install, stage.py's BUNDLED_EDITORS and EDIT's own
    # path literal, and runs install-editors.ps1 -CheckOnly.
    #
    # ***IT IS HERE BECAUSE THE REGRESSION IS SILENT.***  If the bundling broke,
    # find.editor's PATH fallback would find the winget copy and every verb
    # would go on working - against an editor of unknown version, which is the
    # entire defect 66 was filed for.  Nothing would go red.  Same shape as the
    # stem-coverage step above, and the same argument for making it a step.
    #
    # AFTER verify-credacl AND ITS TWO NEIGHBOURS, NOT BESIDE THE test-* STEPS:
    # those two read source files only, which is why they may precede the step
    # that decides what an ORDINARY token can do.  This one reads the installed
    # tree, so it goes after.  And after verify-osusers so it does not delay
    # that step's UAC prompt, which is early on purpose.
    @{ Name = 'verify-editors.ps1';     P = @{} },
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
    # 31 Aug 26 - PRE_RELEASE 91's guard, and it is in THIS runner because an
    # ELEVATED one could not measure it at all: an elevated session lands in
    # SDSYS, and "an administrator AS THEMSELVES" is the entire property.  It
    # needs the test account for two different jobs at once - as a target the
    # caller was never granted, and as the non-administrator control - so it
    # goes next to the other two that take it.  Creates nothing, spends no
    # prefix, raises no prompt.
    @{ Name = 'verify-logtoaccess.ps1'; P = @{} },
    # 22 Aug 26 - section 7 step 12's guard.  It belongs in THIS runner rather
    # than VerifyInstall2: it spends no prefix, creates nothing, and needs no
    # elevation, which is this file's whole entry condition.
    @{ Name = 'verify-parsertokens.ps1'; P = @{} },
    # 22 Aug 26 - section 7 step 9's guard, and it is here for the same reason
    # verify-osusers is: the measurement MUST be made with an ordinary token,
    # because an elevated session passes the batch gate on its own.  IT RAISES
    # TWO UAC PROMPTS ITSELF, for the two steps that write SDSYS batch.jobs -
    # so this runner now costs about five in total rather than three.
    @{ Name = 'verify-batchjob.ps1';     P = @{} },
    # 29 Aug 26 - PRE_RELEASE 11 / UPSTREAM 17's regression guard: a nested
    # COMMIT used to orphan the outer transaction's cache and lose its writes
    # with no message at all.  A SILENT data-loss defect is the kind that comes
    # back unnoticed, which is why it earns a standing verifier rather than the
    # one-off probe that found it.
    #
    # IT BELONGS IN THIS RUNNER: no elevation, no prefix, no account of its own
    # and NO UAC PROMPT - it compiles and runs a probe in the caller's own SD
    # account and removes it again, so it does not change what this runner costs
    # a person to sit through.  It REFUSES an elevated shell, because an
    # elevated session lands in SDSYS where the probe is not.
    #
    # Measured on the 18:36:04 install before being added - 9 of 9 PASS - so it
    # is not being wired in untested, which is the rule verify-lineendings above
    # records.
    @{ Name = 'verify-txn.ps1';          P = @{} },

    # 04 Sep 26 - SDConnectLocal AND ITS GRANT CHECK.  PRE_RELEASE_FIXES 163.
    #
    # IT BELONGS IN THIS RUNNER AND NOWHERE ELSE, for the same reason
    # verify-txn does and more sharply: SDConnectLocal sends NO PASSWORD at
    # all.  vb.local.login (APISRVR request 25) takes the identity from the
    # PROCESS OWNER, so the whole access decision is the grant check - and an
    # elevated token is a different principal, which would measure something
    # else and pass.  The script refuses an elevated shell rather than
    # answering.
    #
    # WHY IT IS A STEP AT ALL: until today this path was exercised by "make
    # check-local", by hand, on one machine, and by nothing in either half of
    # the suite.  A passwordless authentication route with no standing test is
    # not a gap this project leaves open on purpose.
    #
    # NO PREFIX, NO ACCOUNT, NO UAC PROMPT: it connects as the caller to the
    # caller's own account, runs WHO, and disconnects.  The control is SDSYS,
    # which MUST be refused - without it a success would only show that an
    # account exists.  Measured before being wired in (CLAUDE.md): DON
    # admitted with "WHO -> 1 DON", SDSYS refused with "User not allowed in
    # requested account".
    @{ Name = 'verify-localconnect.ps1'; P = @{} },

    # 03 Sep 26 - PRE_RELEASE 93 and 65's guard: the account register and
    # os.users must contain only records for accounts that exist.
    #
    # IT IS IN THIS RUNNER BECAUSE THE PROPERTY IS ABOUT WHAT AN ORDINARY USER
    # SEES.  Both files grant sdusers ReadAndExecute, and a stale record matters
    # precisely because LIST ACCOUNTS shows it to everybody; checking it from an
    # elevated window would measure a file nobody reads that way.  No prefix, no
    # account, no UAC prompt, and it changes nothing.
    #
    # ***AND IT WOULD HAVE CAUGHT WHAT A 41-STEP GREEN SUITE DID NOT.*** On
    # 1 Sep 2026 the b100 suite passed 753 checks with the register 93% invalid,
    # because no step asserted it was internally consistent.  Entry 93 asks for
    # exactly this check in exactly those words.
    #
    # Measured before being added - 7 of 7 PASS on the live tree, and 4 of 7
    # with two FAILs on a deliberately dirty one, so it has been watched both
    # ways rather than only passing.
    @{ Name = 'verify-register.ps1';     P = @{} },

    # 31 Aug 26 - DOES THE LANGUAGE ITSELF ANSWER CORRECTLY?  PRE_RELEASE 106,
    # on the owner's ruling of 31 Aug 2026.  §5.24.  The §5.23 sweeps asked
    # whether a status was discarded; this asks the question underneath them,
    # and nothing else in the tree asks it: no other step checks that ABS,
    # OCONV, LOCATE or the operators return the right values, so a pcode or
    # opcode change that broke one would have surfaced as a wrong report from a
    # user rather than as a red step here.
    #
    # IT IS THE SAME SHAPE AS verify-txn ABOVE, which is why it sits beside it:
    # no elevation, no prefix, no account of its own and NO UAC PROMPT - it
    # compiles and runs a probe in the caller's own SD account and removes it
    # again, so it does not change what this runner costs a person to sit
    # through.  About 20 seconds.
    #
    # THE STRUCTURAL HALF IS NOT HERE AND DOES NOT NEED TO BE.  Whether the
    # compiler and the runtime agree about opcode numbers is settled at build
    # time - gplsrc/opcodes.h is an X-macro table that kernel.c:75 turns into
    # dispatch[] by #include, and gen_includes.py generates gpl.bp/OPCODES.H
    # from the same file - so there is nothing for a runtime step to catch.
    # §5.24 records that measurement so it is not repeated by hand.
    #
    # Measured on the 13:33:28 install before being added - 169 of 169 cases,
    # 0 failures - so it is not being wired in untested, which is the rule
    # verify-txn and verify-lineendings above both record.
    @{ Name = 'verify-basicfuncs.ps1';   P = @{} },
    # 02 Sep 26 - THE AK INDEX WRITE PATH.  PRE_RELEASE_FIXES 112, owner's
    # ruling.  It sits HERE, beside verify-txn and verify-basicfuncs, because
    # the three ask the same kind of question - does the engine itself answer
    # correctly - where every step above asks about accounts, ACLs or doors.
    #
    # VerifyInstall1 AND NOT VerifyInstall2, WHICH IS WHERE THE RULING PUT IT.
    # Its own header: "Unelevated on purpose: an ordinary session lands in DON,
    # don's own account."  VerifyInstall2 is the elevated runner, so this step
    # would measure something other than what it was written to measure.
    # Flagged to the owner rather than transposed silently.
    #
    # WHY IT IS WORTH A SUITE STEP AT ALL: no verifier in either runner drives
    # an AK index write.  verify-vocverbs is the only script that touches
    # CREATE.INDEX, and its fixture indexes an empty DATA part with a verb that
    # defines an index without building one - so get_ak_node is called zero
    # times there.  100's seven callers had nothing exercising them.
    #
    # RUN-SPECIFIC TAG, for 54's reason: a fixed name passes once and collides
    # with its own leftovers afterwards.  It cleans up and asserts it did - "no
    # fixture directory is left behind", "no stray sd.exe session" - but an
    # interrupted run is exactly when that does not happen.
    #
    # LAST, AND CHEAP TO LOSE: it makes and removes its own fixture in don and
    # touches nothing else, so a failure here costs no other step.
    @{ Name = 'probe-akwrite.ps1';       P = @{ Tag = "akp$Run" } }
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
# ***IT USED TO ADD THREE UAC PROMPTS to this runner's five, with PRE_RELEASE
# 73's verifier below adding a fourth.  SINCE PRE_RELEASE 165 IT ADDS NONE***:
# both are given -HelperPipe and ADOPT the helper this runner started, so
# neither starts one and - the part that matters - neither STOPS one.  See
# $helperAware below, and elevate-once.ps1's header for why an adopting step
# stopping the helper would take the consent away from the rest of the run.
if ($Run) {
    # 28 Aug 26 - BUILT AND COUNTED, not appended with a bare +.  A hashtable
    # on the right of + is folded into the array as one element only if it is
    # wrapped first; the count is asserted below rather than assumed.
    $doorStep = @{ Name = 'verify-doors-suite.ps1'; P = @{ Prefix = "sddr$Run" } }

    # 30 Aug 26 - PRE_RELEASE 73's verifier, and it belongs in THIS runner rather
    # than the elevated one for a sharper version of the gate at the top of this
    # file.  It asks whether a session that reached SDSYS by LOGTO from an
    # UNELEVATED start can write $cred and os.users; run elevated it would pass
    # every row and prove the opposite.  IT CANNOT BE DELEGATED TO VerifyInstall2
    # EITHER - an elevated parent cannot make an ordinary child, because
    # runas /trustlevel yields a RESTRICTED token rather than the user's own.
    #
    # ONE MORE CONSENT, NOT ONE PER LEG.  It starts the helper on SD'S OWN pipe
    # name - gpl.bp/ELEVATE:121 builds 'sd-elev-' : @logname - so SD's own
    # elevate('START') inside LOGTO SDSYS finds one already serving and asks for
    # nothing further.
    #
    # ***EXPECT IT RED UNTIL 68 IS FIXED, AND THAT IS THE POINT OF ADDING IT.***
    # Two rows fail by design, the unelevated $cred and os.users writes, and
    # three controls prove the probe is sound: setup created the account, the
    # unelevated session reached SDSYS and READ it, and the same write from an
    # ELEVATED session succeeded.  A GREEN run before 68 is fixed means the probe
    # is broken, not that the product is well.
    #
    # IT GOES LAST DELIBERATELY.  A failing step stops this runner unless
    # -ContinueOnFailure is given, so a known-red step anywhere else would hide
    # every step behind it.  Last, it hides nothing.
    $writeStep = @{ Name = 'verify-sdsyswrite.ps1'; P = @{ Prefix = "sdsw$Run" } }

    $before = @($steps).Count
    $steps  = @($steps) + @($doorStep) + @($writeStep)
    if (@($steps).Count -ne ($before + 2)) {
        Write-Output ("VerifyInstall1: the step list is {0} after adding two to {1}." -f
                      @($steps).Count, $before)
        exit 2
    }
} else {
    Write-Output 'VerifyInstall1: no -Run, so the SUSPENDED door pair is NOT in this run,'
    Write-Output '  and neither is verify-sdsyswrite.ps1 (PRE_RELEASE 73).'
    Write-Output '  Both create a Windows account and both prefixes are single-use, so they need'
    Write-Output '  a token to derive a fresh name from.  Add -Run <token> to include them.'
    Write-Output '  WITHOUT THEM THIS RUNNER CANNOT SEE PRE_RELEASE 68 AT ALL - a clean run with'
    Write-Output '  no -Run is not evidence that the LOGTO-reached SDSYS can write its stores.'
}

# ---------------------------------------------------------------------------
# 29 Aug 26 - THE NON-ADMINISTRATOR TEST ACCOUNT.  PRE_RELEASE 59.
#
# WHY THIS RUNNER OWNS IT.  Five steps here - lcnames, osusers, nocase,
# lineendings, batchjob - meant "run sd as an ordinary user", and that only ever
# worked because the owner is an administrator WITH an ordinary account.
# PRE_RELEASE 56 abolished that combination: an administrator is elevated at
# LOGIN and lands in SDSYS, so on -Run b59 all five found SDSYS's files where
# they expected the account's.  Every one refused the null case rather than
# scoring a false pass, which is the only reason this is a repair and not a
# retraction.
#
# ***ONE ACCOUNT FOR THE WHOLE HALF, MADE ONCE HERE.***  Creating it needs
# elevation, so it costs a UAC prompt; five verifiers each making their own
# would cost five.  CLAUDE.md's rule is to remove the need for a prompt rather
# than to skip the step, and this is the removal it asks for.
#
# ***IT COST TWO PROMPTS, ONE AT EACH END. IT NOW COSTS NONE.***  PRE_RELEASE
# 165, 04 Sep 2026.  This paragraph used to end "reusing that here would take
# this to one - but it is ~150 lines of machinery in that file, and this whole
# mechanism has never run, so a second unproven thing is not layered on the
# first.  Filed as the follow-up in PRE_RELEASE 59."  The mechanism has since
# run on b54 and every suite run after it, so the caution was paid off; the
# machinery is now in elevate-once.ps1, shared rather than copied, and both the
# create and the remove above go through the consent given once at the top.
#
# CONDITIONAL ON -Run, for the door step's reason exactly: the name becomes a
# Windows account and is SINGLE-USE, because an ssh sign-in leaves a profile
# directory DELETE.ACCOUNT cannot remove while its hive is mounted
# (PRE_RELEASE 35/36).  Without a token there is no fresh name to derive.
#
# BEFORE THE STEP LIST, NOT AFTER IT, which is the opposite of the door step
# and for a reason: nocase is in the MIDDLE of the list, so the account has to
# exist before the loop starts.  Checked rather than assumed that this does not
# disturb the steps that run before it - credacl, pcodeacl and sysdiracl ask
# what an ordinary token can write in the SYSTEM directories and cannot see an
# extra user account; lcnames takes an -Account and resolves exactly one
# directory out of the listing (verify-lcnames.ps1:133); nothing here counts
# accounts.
. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

# ---------------------------------------------------------------------------
# 04 Sep 26 - ONE CONSENT FOR THE WHOLE RUN.  PRE_RELEASE 165, on the owner's
# ruling "do the elevate fix before 1.0".
#
# WHAT THIS REPLACES.  Every elevated thing below used to raise its own UAC
# prompt: the test account's creation and its removal, verify-osusers,
# verify-batchjob's two, verify-doors-suite's helper, verify-sdsyswrite's
# helper, and the handover to VerifyInstall2 - the "ask for elevation about six
# times" the banner above warns about.  ***b115 WAS LOST TO A SINGLE STRAY
# KEYSTROKE LANDING ON ONE OF THEM***, twenty minutes gone, the step correctly
# reporting "The operation was canceled by the user".
#
# ***AND IT IS THE DIRECTION CLAUDE.md ASKS FOR, NOT THE ONE IT FORBIDS.***
# "Pursue it by removing the need for a prompt, not by skipping the step."
# Nothing here is skipped and nothing measures less: the same children run, with
# the same tokens, and every one of them still prints what it did.  -Silent is
# the forbidden shape; this is sd-elevate.ps1's, which SD itself uses.
#
# STARTED HERE, WHICH IS AFTER THE GATES AND BEFORE THE FIRST ELEVATION.  The
# "are you sure" question, the elevated-shell refusal and the SD-running check
# have all been answered by this line, so nobody is asked for consent for a run
# that was never going to happen.
#
# ONLY WHEN THE RUN CONTAINS AN ELEVATED STEP AT ALL.  Every one of them is
# conditional on -Run: the five that need the test account, the door pair and
# the write step.  Without it this half elevates nowhere, and asking anyway
# would be a prompt bought for nothing.
. (Join-Path $PSScriptRoot 'elevate-once.ps1')
$helperPipe = ''
if ($Run) {
    $st = Start-SdElevationHelper -Purpose 'this whole run' -NoHelper:$NoHelper
    $helperPipe = $st.Pipe
    if ($st.Active) {
        Write-Output ''
        Write-Output '===== elevation: ONE consent covers this half ====='
        Write-Output ('  pipe: ' + $st.Pipe)
        Write-Output '  You should not be asked again until the run finishes.'
    } else {
        Write-Output ''
        Write-Output '===== elevation: A PROMPT PER STEP ====='
        Write-Output ('  ' + $st.Reason)
        Write-Output '  The run still happens; it just asks more often.  Do not walk away from it.'
    }
} else {
    Write-Output 'VerifyInstall1: no -Run, so nothing in this half elevates and no helper is started.'
}

# Run sdtestuser-admin.ps1 elevated, through the helper when one is serving.
#
# ***A SELF-CONTAINED LAUNCHER, BECAUSE THE HELPER PASSES NO ARGUMENTS.***  It
# is sent a script PATH and runs it with Get-Content | Invoke-Expression
# (sd-elevate-helper.ps1:241), so everything this child needs is baked into the
# file.  That is the same shape verify-doors-suite.ps1 uses and its measurement
# carries over verbatim: a %TEMP% file carries SYSTEM, Administrators and the
# user and NOBODY ELSE, while Win32_Process.CommandLine hands a same-user
# process an argument verbatim - so moving the password off the command line and
# into a file that is deleted in the finally is a step UP, not a compromise.
#
# ***THIS FUNCTION MUST NOT Write-Output.***  It returns a hashtable, and a
# PowerShell function's return value is its whole output stream - the trap that
# has now cost this project three separate bugs, one of them in elevate-once.ps1
# yesterday.  Narration goes to Write-Host, which Start-Transcript records.
function Invoke-SdTestUserAdmin {
    param(
        # PASSED, NOT INHERITED.  $admin is assigned inside the "if ($Run)" block
        # below, and an if does not make a scope in PowerShell - so reading it
        # from here would work and would depend on that.  A parameter says what
        # this needs.
        [string] $AdminScript = '',
        [string] $Action   = '',
        [string] $Name     = '',
        [string] $Password = '',
        [string] $LogFile  = '',
        [switch] $Sweep
    )
    if ([string]::IsNullOrEmpty($AdminScript)) {
        Write-Host '  REFUSING: no sdtestuser-admin.ps1 path was given. Nothing was run.'
        return @{ Ok = $false; ExitCode = 2; Route = 'refused'; Reason = 'no admin script path' }
    }
    # REFUSE THE QUOTING HAZARD RATHER THAN GENERATING A BROKEN SCRIPT.  Every
    # value is embedded in a single-quoted PowerShell string, which processes no
    # escapes - so a backslash in a path is safe and an apostrophe is not.
    foreach ($v in @($AdminScript, $Action, $Name, $Password, $LogFile)) {
        if ($v -match "'") {
            Write-Host '  REFUSING: a value contains an apostrophe and would break the launcher quoting.'
            return @{ Ok = $false; ExitCode = 2; Route = 'refused'; Reason = 'apostrophe in a value' }
        }
    }

    $work = Join-Path $env:TEMP ('sdtu-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $work
    try {
        $launcher = Join-Path $work 'run.ps1'
        $call = "& '$AdminScript' -Action '$Action' -Name '$Name'"
        if ($Password -ne '') { $call += " -Password '$Password'" }
        if ($LogFile  -ne '') { $call += " -LogFile '$LogFile'" }
        if ($Sweep)           { $call += ' -Sweep' }
        # exit with the child's own code, or the whole point of the launcher is
        # lost: the helper returns what the SCRIPT exited with.
        $src = @($call, 'exit $LASTEXITCODE') -join "`r`n"
        [System.IO.File]::WriteAllText($launcher, $src + "`r`n", [System.Text.Encoding]::ASCII)

        # RULE 1: print the real call, with the password masked.  A create that
        # did nothing is diagnosed from this line.
        $shown = $call
        if ($Password -ne '') { $shown = $shown.Replace("'$Password'", '<password>') }
        Write-Host ('      ' + $shown)

        return (Invoke-ElevatedScript -Launcher $launcher -Why ('sdtestuser-admin ' + $Action))
    } finally {
        # IT CARRIES THE SECRET, so this removal is not tidiness.
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$testUser = ''
$testPw   = ''
if ($Run) {
    $testUser = "sdtu$Run"
    $admin = Join-Path $PSScriptRoot 'sdtestuser-admin.ps1'
    if (-not (Test-Path -LiteralPath $admin)) {
        Write-Output ("VerifyInstall1: {0} is not there - cannot make the test account." -f $admin)
        exit 2
    }

    Write-Output ''
    Write-Output '===== the non-administrator test account (PRE_RELEASE 59) ====='
    Write-Output ("  name: {0}" -f $testUser)

    # ***LOOK FOR ORPHANS FROM AN INTERRUPTED RUN, AND NAME THEM.***  A Ctrl-C
    # does NOT run the finally below - measured on b62, 29 Aug 2026 - so an
    # interrupted run leaves its test account live and enabled in sdusers and
    # sdssh, with a password that existed only in the dead process.  The next
    # run then hits the single-use guard and reports "ALREADY EXISTS", which is
    # correct and tells nobody that a DIFFERENT run left something behind.
    #
    # ***IT SWEEPS THEM NOW. OWNER'S RULING, 29 Aug 2026, asked and answered.***
    # This block reported and did not act for one commit; the owner's answer to
    # "report or sweep?" was "sweep".
    #
    # THE REMOVAL HAPPENS IN THE ELEVATED CHILD THAT CREATE ALREADY RAISES, so
    # it costs no extra UAC prompt - CLAUDE.md's rule, "pursue it by removing
    # the need for a prompt, not by skipping the step".  And the child builds
    # its OWN candidate list rather than taking one from here: this is code that
    # deletes Windows accounts, so the only thing this side controls is whether
    # to sweep, not what.  The guard and its three conditions are in
    # sdtestuser-admin.ps1 beside the deletion.
    #
    # THIS SIDE STILL SCANS, and that is not redundant: it is what puts the list
    # in the UNELEVATED transcript, which is the one a person is reading. The
    # elevated child's window closes with its scrollback.
    $orphans = @()
    foreach ($u in @(Get-LocalUser -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -like 'sdtu*' -and $_.Name -ne $testUser })) {
        $orphans += $u.Name
    }
    # THE ACCOUNTS RECORD TOO, because either half alone is a broken account and
    # a record with no Windows user is the one nothing else would notice.
    foreach ($r in @(Get-ChildItem (Join-Path $env:ProgramData 'SD\sdsys\accounts') `
                        -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -like 'SDTU*' })) {
        if (($orphans -notcontains $r.Name) -and
            ($r.Name -ne $testUser.ToUpper())) { $orphans += $r.Name }
    }
    if ($orphans.Count -gt 0) {
        Write-Output ''
        Write-Output ("  {0} TEST ACCOUNT(S) FROM AN EARLIER RUN ARE STILL HERE:" -f $orphans.Count)
        foreach ($o in $orphans) { Write-Output ('      ' + $o) }
        Write-Output '  An interrupted run (Ctrl-C) does not reach the removal, so these are live'
        Write-Output '  and enabled with passwords nothing wrote down.  THE ELEVATED CHILD BELOW'
        Write-Output '  WILL REMOVE THEM, in the same prompt it uses to create this run''s account.'
        Write-Output '  It re-derives the list itself and prints what it skipped and why.'
        Write-Output ''
    } else {
        Write-Output '  no stray test accounts from earlier runs.'
    }

    # CREATE.ACCOUNT is gated on K$ADMINISTRATOR, so this needs elevation
    # either way; what changed on 04 Sep 26 is WHERE the consent comes from.
    if ($helperPipe -ne '') {
        Write-Output '  No prompt: the consent given at the top of this run covers it.'
    } else {
        Write-Output '  EXPECT A UAC PROMPT NOW - CREATE.ACCOUNT is gated on K$ADMINISTRATOR.'
    }

    # GENERATED HERE AND KEPT HERE.  New-SdTestPassword measures that the value
    # survives the askpass batch BEFORE anything is created, so a bad draw costs
    # nothing and leaves no account behind.  It is passed to the elevated child
    # as an argument rather than scraped out of its output, for the reason
    # verify-doors-suite.ps1 records: the alternative is redirecting an elevated
    # child's stdout to a file, which is the one copy nobody deletes.
    $testPw = New-SdTestPassword

    # -LogFile, because -RedirectStandardOutput CANNOT be used with -Verb and
    # the elevated window closes with its scrollback.  Without it the create
    # would be a verdict with no evidence.
    $tuLog = Join-Path $logDir ('testuser-create-' + $stamp + '.log')
    $tuRes = Invoke-SdTestUserAdmin -AdminScript $admin -Action 'Create' -Name $testUser `
                                    -Password $testPw -LogFile $tuLog -Sweep

    # ***THE LOG IS PRINTED BEFORE THE VERDICT IS READ, AND ON BOTH PATHS.***
    # -LogFile exists because -RedirectStandardOutput cannot be used with -Verb
    # and the elevated window closes with its scrollback; through the helper the
    # child is hidden and there is no window at all.  Either way this file is the
    # only evidence, so it is printed whether the create worked or not.
    if (Test-Path -LiteralPath $tuLog) {
        Get-Content -LiteralPath $tuLog | ForEach-Object { Write-Output ('  ' + $_) }
    }

    # DID NOT RUN and RAN AND FAILED ARE DIFFERENT ANSWERS, and they used to
    # arrive on the same path: the catch below reported a declined prompt, and
    # a non-zero exit reported a failed create.  Invoke-ElevatedScript keeps
    # them apart - Ok is "did a child run", ExitCode is "what did it say".
    if (-not $tuRes.Ok) {
        Write-Output ('VerifyInstall1: the test account could not be created - ' + $tuRes.Reason)
        Write-Output '  Nothing was created and nothing was measured.'
        exit 2
    }
    if ($tuRes.ExitCode -ne 0) {
        Write-Output ("VerifyInstall1: sdtestuser-admin Create exited {0} - stopping." -f $tuRes.ExitCode)
        Write-Output '  The five steps that need it would each fail with their own wording for'
        Write-Output '  one cause, which is worse than one refusal here.'
        exit 2
    }

    # ***THE DECISIVE CHECK, AND IT HAS TO BE MADE BY THIS PROCESS.***  The
    # grant is applied by an ELEVATED child and used by an UNELEVATED parent,
    # so nothing the child can do proves it worked - an elevated write goes
    # through Administrators\FullControl whether the ACE landed or not.  This
    # token is the only one that can answer.
    try {
        $tuHome = Assert-SdTestUserHomeWritable -Name $testUser
        Write-Output ('  writable by this unelevated process: ' + $tuHome)
    } catch {
        Write-Output ''
        Write-Output ('VerifyInstall1: ' + $_.Exception.Message)
        Write-Output ''
        Write-Output '  The account exists and this process cannot plant a probe in it, so the'
        Write-Output '  five steps that need it would all fail for a reason none of them names.'
        Write-Output ("  REMOVE IT BY HAND - the name is single-use and is now spent:")
        Write-Output ("      {0} -Action Remove -Name {1}    (ELEVATED PowerShell)" -f $admin, $testUser)
        exit 2
    }
} else {
    Write-Output 'VerifyInstall1: no -Run, so there is NO non-administrator test account.'
    Write-Output '  The five steps that need one are NOT in this run - PRE_RELEASE 59.  They'
    Write-Output '  create a Windows account whose name is single-use, so they need a token to'
    Write-Output '  derive a fresh one from.  Add -Run <token> to include them.'
}

# THE FIVE STEPS THAT NEED IT.  The recommendation this followed is written
# into PRE_RELEASE 59, and the reason mattered more than the order: prove the
# pattern on the SMALLEST verifier first, because "a broken verifier that
# PASSES is the worst outcome this file records, and replicating an unproven
# pattern four times is how that happens".
#
# ***verify-nocase WENT GREEN ON b61, SO THE PATTERN IS PROVEN AND THE CAUTION
# HAS BEEN PAID OFF.***  3 of 3 decisive checks, including the DHFILE=0 control
# that is the point of that test - the first measurement this project has taken
# as a real non-administrator.  verify-lineendings.ps1 follows it now.
#
# STILL OUT: verify-lcnames.ps1 (1049 lines) and verify-batchjob.ps1 (368,
# with its own two-prompt elevation dance).  verify-osusers.ps1 is 931 lines
# with 32 references to the person's own identity in os.users and is
# deliberately NOT in this group at all.
$needsTestUser = @('verify-nocase.ps1', 'verify-lineendings.ps1',
                   'verify-logtoaccess.ps1')

# 04 Sep 26 - THE STEPS THAT TAKE -HelperPipe.  PRE_RELEASE 165.  These four are
# the only things in this half that raise a UAC prompt of their own; each now
# adopts the runner's helper instead.  test-elevonce-units.ps1 checks this list
# against the scripts' actual parameter blocks, in BOTH directions, so a script
# that gains the parameter without joining this list - or joins it without
# having the parameter - fails in a second instead of costing a run its prompts.
$helperAware = @('verify-osusers.ps1', 'verify-batchjob.ps1',
                 'verify-doors-suite.ps1', 'verify-sdsyswrite.ps1')

# AN ArrayList RATHER THAN "$kept += $s", and the door step above says why in
# its own words: a hashtable on the right of + is folded into an array as one
# element only if it is wrapped first, and getting that wrong is silent.  The
# counts are asserted below rather than assumed.
$kept    = New-Object System.Collections.ArrayList
$skipped = 0
foreach ($s in $steps) {
    if ($needsTestUser -contains $s.Name) {
        if ($testUser -eq '') {
            Write-Output ("VerifyInstall1: SKIPPING {0} - it needs the test account." -f $s.Name)
            $skipped++
            continue
        }
        $s.P['TestUser']     = $testUser
        $s.P['TestPassword'] = $testPw
    }
    # 04 Sep 26 - TELL THE HELPER-AWARE STEPS WHICH PIPE IS ALREADY SERVING.
    # PRE_RELEASE 165.
    #
    # ***AN EXPLICIT LIST, NOT A try/catch ON THE SPLAT.***  Passing -HelperPipe
    # to a step that has no such parameter is a binding error that reads like a
    # broken runner, and swallowing it would hide a step somebody forgot to
    # wire.  The list is checked against the four scripts by
    # test-elevonce-units.ps1, so adding a fifth without adding it here fails in
    # a second rather than costing a run its prompts.
    #
    # ***AND THE STEP MUST NOT STOP WHAT IT DID NOT START.***  Every step runs
    # IN-PROCESS ("& $path @splat" below), so they all share this runner's $PID,
    # and the helper's owner set is keyed by pid - so one step sending
    # "-Stop -OwnerPid $PID" would empty the set and kill the consent for the
    # rest of the run.  elevate-once.ps1's Stop is a no-op on an adopted pipe
    # and that is where the rule is enforced, not here.
    if (($helperAware -contains $s.Name) -and ($helperPipe -ne '')) {
        $s.P['HelperPipe'] = $helperPipe
    }
    $null = $kept.Add($s)
}
if (($kept.Count + $skipped) -ne @($steps).Count) {
    Write-Output ("VerifyInstall1: the step list is {0} kept + {1} skipped from {2}." -f
                  $kept.Count, $skipped, @($steps).Count)
    exit 2
}
$steps = $kept.ToArray()

# 30 Aug 26 - -Only, LAST, so it filters the list the runner would actually have
# run: after the door and write steps are appended and after the test-account
# skips.  Filtering earlier would let -Only name a step this run was never going
# to reach and call that a match.
. (Join-Path $PSScriptRoot 'suite-only.ps1')
$sel = Select-SuiteSteps -Steps $steps -Only ($Only -join ',') -Runner 'VerifyInstall1'
if ($sel.Error -ne '') { Write-Output $sel.Error; exit 2 }
$partial   = $sel.Partial
$fullCount = @($steps).Count
$steps     = @($sel.Steps)
if ($partial) {
    Write-Output ''
    Write-Output ('***** PARTIAL RUN - {0} of {1} step(s), because -Only was given *****' -f
                  @($steps).Count, $fullCount)
    Write-Output ('      ' + (($steps | ForEach-Object { $_.Name }) -join ', '))
    Write-Output '      This run says NOTHING about the steps it did not run.'
}

$lines  = @()
$failed = 0
# 03 Sep 26 - PRE_RELEASE_FIXES.md 152.  COUNTED SEPARATELY, NOT COUNTED
# DIFFERENTLY.  $failed keeps its meaning exactly - every step that did not
# exit 0, refusals included - so the exit logic at the foot of this file is
# untouched and a step that COULD NOT RUN still never reads as a pass.  This is
# the extra count beside it, so the closing line can say which kind of red a
# red suite is: "the API is broken" and "six steps refused on a stale tree"
# looked identical on b106 and were a whole reading apart.
#
# THE RUNNER'S OWN EXIT CODE IS DELIBERATELY NOT CHANGED.  A half that only
# refused is arguably a 2, but cycle.ps1 and anything else reading this expect
# 1 for "not clean", and entry 152 says not to move it without asking.
$refused = 0

# 29 Aug 26 - THE STEP LOOP IS IN A try SO THE TEST ACCOUNT IS ALWAYS REMOVED.
# PRE_RELEASE 59.
#
# ***THIS IS NOT BELT AND BRACES, IT IS THE FAILURE ALREADY IN THE RECORD.***
# sddrb50a is on this machine now - "STILL LIVE, ENABLED AND UNSUSPENDED in
# sdusers, sdssh and sdapi, its Remove leg never ran" - because the run it
# belonged to stopped at a failing step.  The loop below has a "break" on
# exactly that path, so a removal written after it would be skipped by the case
# it is most needed in.  A finally covers break and a thrown error.
#
# ***BUT IT DOES NOT COVER Ctrl-C, AND THIS FILE CLAIMED IT DID.***  The
# sentence here read "a finally is skipped by nothing: break, a thrown error and
# Ctrl-C all run it", and that was written without measuring.  MEASURED TWICE,
# 29 Aug 2026, and the two disagree:
#
#   * a pipeline stop from Stop-Job DOES run the finally - a probe that wrote a
#     marker file in one wrote it every time;
#   * the b62 run at 12:58:50 was Ctrl-C'd at the console and DID NOT.  Its
#     transcript carries six "The pipeline has been stopped." lines, no
#     "removing the test account" line, no "WAS NOT REMOVED" line, and no
#     testuser-remove log was written at all.  sdtub62 was left live and
#     enabled, and the next two runs were refused by the single-use guard.
#
# ***SO THE DURABLE FIX IS RECOVERY AT THE START OF THE NEXT RUN, NOT STRONGER
# CLEANUP AT THE END OF THIS ONE.***  Nothing in-process is guaranteed against
# Ctrl-C, so the orphan check above this loop is the half that always runs.
# Keep the finally - it covers the common cases - but do not rely on it alone.
#
# THE LOOP BODY IS NOT RE-INDENTED, DELIBERATELY.  Wrapping fifty lines in a
# level of indentation would make the diff unreadable for a review whose whole
# question is "what changed here", and PowerShell does not care.
try {

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
    # 03 Sep 26 - PRE_RELEASE 152.  2 is the convention's "could not be run"
    # (entry 151 made the six API verifiers honour it).  The row is annotated
    # so the summary FILE carries the distinction too, not just the console.
    if ($code -eq 2) { $refused++ }
    $lines += ('{0,-28} exit {1}{2}' -f $s.Name, $code,
               $(if ($code -eq 2) { '  COULD NOT RUN' } else { '' }))

    if ($code -ne 0 -and -not $ContinueOnFailure) {
        Write-Output ''
        Write-Output ("VerifyInstall1: STOPPING - {0} exited {1}." -f $s.Name, $code)
        Write-Output '  Re-run with -ContinueOnFailure to see the rest anyway.'
        break
    }
}

} finally {
    if ($testUser -ne '') {
        Write-Output ''
        Write-Output ('===== removing the test account ' + $testUser + ' =====')
        if ($helperPipe -ne '') {
            Write-Output '  No prompt: the consent given at the top of this run still covers it.'
        } else {
            Write-Output '  EXPECT A UAC PROMPT - DELETE.ACCOUNT is gated on K$ADMINISTRATOR.'
        }
        $rmLog = Join-Path $logDir ('testuser-remove-' + $stamp + '.log')
        $rmCode = -1
        # ***THE HELPER IS STILL SERVING HERE, AND THAT IS DELIBERATE.***  This
        # is the step-loop's finally; the helper is stopped further down, after
        # the handover.  A removal that had to ask for consent of its own is
        # exactly the prompt somebody walks away from - and the account it
        # leaves behind is live, enabled, and holding a password that existed
        # only in this process.
        $rmRes = Invoke-SdTestUserAdmin -AdminScript (Join-Path $PSScriptRoot 'sdtestuser-admin.ps1') `
                                        -Action 'Remove' -Name $testUser -LogFile $rmLog
        if ($rmRes.Ok) { $rmCode = $rmRes.ExitCode }
        else { Write-Output ('  the removal did not start - ' + $rmRes.Reason) }
        if (Test-Path -LiteralPath $rmLog) {
            Get-Content -LiteralPath $rmLog | ForEach-Object { Write-Output ('  ' + $_) }
        }
        # ***SAY IT LOUDLY, BECAUSE A LEFT-BEHIND ACCOUNT IS LIVE AND ENABLED.***
        # It is in sdusers and sdssh with a password nothing has written down -
        # this process generated it and is about to end.  The name is spent
        # either way (PRE_RELEASE 35/36), so the next run needs a new -Run token
        # whatever happens here.
        if ($rmCode -ne 0) {
            Write-Output ''
            Write-Output ("  *** {0} WAS NOT REMOVED (exit {1}). IT IS LIVE AND ENABLED. ***" -f
                          $testUser, $rmCode)
            Write-Output '  Its password was generated in this process and is not written down.'
            Write-Output '  From an ELEVATED PowerShell:'
            Write-Output ('      {0} -Action Remove -Name {1}' -f
                          (Join-Path $PSScriptRoot 'sdtestuser-admin.ps1'), $testUser)
        }
    }
}

Write-Output ''
if ($partial) {
    Write-Output ('===== post-cycle-unelevated summary - PARTIAL, {0} of {1} step(s) =====' -f
                  @($steps).Count, $fullCount)
} else {
    Write-Output '===== post-cycle-unelevated summary ====='
}
$lines | ForEach-Object { Write-Output $_ }
$lines | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ''
Write-Output ('summary written to: ' + $summary)

if ($failed -gt 0) {
    # 03 Sep 26 - PRE_RELEASE 152.  SAY WHICH KIND OF RED.  A step that refused
    # measured nothing, so it is neither a pass nor a product finding, and a
    # summary that calls both "did not exit 0" sends the reader to the wrong
    # place - which is what b106 cost.
    if ($refused -gt 0) {
        Write-Output ("VerifyInstall1: {0} step(s) did not exit 0 - {1} FAILED a check, {2} COULD NOT RUN." -f
                      $failed, ($failed - $refused), $refused)
        Write-Output '  A step that could not run measured nothing: it is not a product finding.'
        Write-Output '  Read those steps first - a stale tree or a missing tool refuses every one.'
    } else {
        Write-Output ("VerifyInstall1: {0} step(s) did not exit 0." -f $failed)
    }
    if ($ThenElevated) {
        Write-Output '  NOT handing over to VerifyInstall2.ps1 - fix these first, or'
        Write-Output '  re-run with -ContinueOnFailure to hand over anyway.'
        if (-not $ContinueOnFailure) { Stop-SdElevationHelper; exit 1 }
    } else { Stop-SdElevationHelper; exit 1 }
} elseif ($partial) {
    # 30 Aug 26 - NEVER "every step exited 0" ON A PARTIAL RUN.  That sentence is
    # a claim about the whole half, and on a -Only run it would be false in the
    # one direction that matters: it would read as a clean suite to anyone who
    # skimmed the last line, which is how these logs are read.
    Write-Output ("VerifyInstall1: PARTIAL - {0} of {1} step(s) run, all exited 0." -f
                  @($steps).Count, $fullCount)
    Write-Output '  The other steps were NOT run and this says nothing about them.'
} else {
    Write-Output 'VerifyInstall1: every step exited 0.'
}

# 04 Sep 26 - THE HELPER GOES BEFORE THIS HALF DOES.  PRE_RELEASE 165.
#
# ***AN ELEVATED PROCESS OUTLIVING THE RUN THAT ASKED FOR IT IS THE ONE THING
# sd-elevate-helper.ps1's HEADER SAYS TO AVOID ABOVE ALL***, so every exit from
# here on stops it explicitly rather than relying on the backstop.
#
# THE BACKSTOP IS REAL AND IS NOT AN EXCUSE TO SKIP THIS.  The helper wakes
# every 2000 ms while idle, prunes owners whose process has gone
# (sd-elevate-helper.ps1:114) and exits when the set empties - so even a Ctrl-C,
# which VerifyInstall1.ps1:1080 records as running no finally at all, leaves it
# alive for about two seconds and no longer.
if (-not $ThenElevated) { Stop-SdElevationHelper; exit ([int]($failed -gt 0)) }

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
    Stop-SdElevationHelper
    exit 2
}

$elevLog = Join-Path $logDir ('post-cycle-elevated-' + $stamp + '.log')
Write-Output ''
Write-Output '===== handing over to VerifyInstall2.ps1 ====='
Write-Output ("  -Run {0}" -f $Run)
Write-Output ('  output: ' + $elevLog)
if ($helperPipe -ne '') {
    Write-Output '  No prompt: the elevated helper starts it, in a VISIBLE window.'
    Write-Output '  The helper is already elevated, so its child inherits the token and'
    Write-Output '  Windows asks for nothing - PRE_RELEASE 165.'
} else {
    Write-Output '  EXPECT A UAC PROMPT NOW - approving it is what elevates the child.'
}

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

# 04 Sep 26 - THE SAME COMMAND, IN A FILE.  PRE_RELEASE 165.
#
# ***THE COMMAND ITSELF IS UNCHANGED, AND THAT IS DELIBERATE.***  Every clause
# of $inner above was paid for: Tee-Object rather than "*>" because Write-Host
# goes to the INFORMATION stream and the window sat blank for ten minutes
# looking hung; the concatenated '; exit $LASTEXITCODE' because neither "*>" nor
# a bare pipeline carries the child's code, and nine "exit 2" paths were being
# delivered as "A STEP FAILED".  None of that is re-derived here - the string is
# built exactly as before and only the way it is DELIVERED has changed.
#
# WHY A FILE.  The helper is handed a script PATH and runs it; it passes no
# arguments and takes no -Command.  Running from a file also removes the
# quoting layer that -Command adds, which is a reduction in surface rather than
# an increase.
$hoWork = Join-Path $env:TEMP ('sdvi1-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $hoWork
$child = $null
try {
    $hoLauncher = Join-Path $hoWork 'handover.ps1'
    [System.IO.File]::WriteAllText($hoLauncher, $inner + "`r`n", [System.Text.Encoding]::ASCII)

    # -Visible: through the helper this runs in an ordinary window, because the
    # helper is already elevated and its child inherits the token with no
    # consent.  -Interactive: VerifyInstall2 ran without -NonInteractive before
    # this change, and a Read-Host under -NonInteractive THROWS rather than
    # waiting - see elevate-once.ps1's parameter.
    $child = Invoke-ElevatedScript -Launcher $hoLauncher -Visible -Interactive `
                                   -Why ('VerifyInstall2 -Run ' + $Run)
} finally {
    Remove-Item -LiteralPath $hoWork -Recurse -Force -ErrorAction SilentlyContinue
}

# THE CANCELLED-PROMPT PATH, which is now a returned reason rather than a
# thrown one.  Declining UAC and a DESKTOP-LESS shell produce the same message
# - "The operation was canceled by the user" - so both are named.
if (-not $child.Ok) {
    Write-Output ''
    Write-Output ('VerifyInstall1: the elevated half did not start - ' + $child.Reason)
    Write-Output '  The unelevated results above still stand.  To run the other half:'
    Write-Output ("      {0} -Run {1}" -f $elevated, $Run)
    Stop-SdElevationHelper
    exit 1
}

Write-Output ('post-cycle-elevated exited ' + $child.ExitCode)
Write-Output ('  elevated route: ' + $child.Route)
Stop-SdElevationHelper
if (Test-Path -LiteralPath $elevLog) {
    Write-Output ''
    Get-Content -LiteralPath $elevLog | Select-String -Pattern '^\[|FAILED|did not exit 0|all \d+ steps exited' |
        ForEach-Object { Write-Output ('  ' + $_.Line) }
    Write-Output ''
    Write-Output ('  full elevated output: ' + $elevLog)
}
exit $child.ExitCode
