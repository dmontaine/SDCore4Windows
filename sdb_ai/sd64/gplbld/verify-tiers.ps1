# verify-tiers.ps1 - prove the three VOC tiers, and that they survive a VOC
# update.  PROJECT_STATUS.md section 8.
#
#   powershell -File verify-tiers.ps1            create, check, clean up
#   powershell -File verify-tiers.ps1 -Keep      leave the three accounts behind
#   powershell -File verify-tiers.ps1 -Cleanup   remove ones left by -Keep
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# WHY THREE ACCOUNTS AND NOT ONE.  Checking that a standard account lacks the
# withheld verbs proves nothing on its own - a copy loop that skipped
# everything, or one that silently omitted nothing, would each pass half of it.
# The controls are the other two tiers, and the decisive comparisons are
# BETWEEN accounts:
#
#   STANDARD       has neither the 42 withheld capabilities nor the 21
#                  administration verbs
#   PROGRAMMER     has the 42 and NOT the 21       <- controls the add list
#   ADMINISTRATOR  has both                        <- controls the omit list
#
# COUNT VOC IS THE PRIMARY INSTRUMENT, because it is exact and arithmetic
# rather than a spot check.  Installed NEWVOC holds 395 names, of which "%t" is
# a dynamic-file artefact and not a record, and TIER.OMIT.STANDARD and
# TIER.ADD.ADMINISTRATOR are lists that must never be copied - so 392 records
# reach a full VOC.  CREATEA then adds four of its own ($COMMAND.STACK, $hold,
# $savedlists, BP).  That gives:
#
#   ADMINISTRATOR  392 + 21 + 4 = 417
#   PROGRAMMER     392      + 4 = 396
#   STANDARD       392 - 42 + 4 = 354
#
# 28 Aug 26 - ADMINISTRATOR IS 416, AND ONLY ADMINISTRATOR MOVED.  encrypt.field
# was deleted from voc_template and from TIER.ADD.ADMINISTRATOR: it is a V
# record pointing at $CRYPTO, which does not exist anywhere in the tree, so
# every administrator account shipped with a verb that could only ever answer
# "Unable to load '$CRYPTO' object code".  PRE_RELEASE_FIXES.md 25.
#
# 30 Aug 26 - ADMINISTRATOR IS 419, AND ONLY ADMINISTRATOR MOVED.
# PRE_RELEASE_FIXES 78 adds three administrator verbs - remote.api, remote.ssh
# and ssh.server - so the owner can change after an install what only the
# installer could change before.  They go in voc_template ONLY and are listed in
# TIER.ADD.ADMINISTRATOR, which is stage.py's rule for an administrative verb:
# "putting it in newvoc hands it to every account SD creates".
#
# RE-DERIVED FROM THE DIRECTORY, NOT ADJUSTED BY THREE, as this block requires:
# newvoc holds 395 names, less "%t" and the two list records = 392;
# TIER.ADD.ADMINISTRATOR is now 24 lines, 1 description + 23 verbs;
# TIER.OMIT.STANDARD is unchanged at 43 lines, 1 + 42.  So
# ADMINISTRATOR 392 + 23 + 4 = 419, PROGRAMMER 392 + 4 = 396 and STANDARD
# 392 - 42 + 4 = 354.  ***STANDARD AND PROGRAMMER DO NOT MOVE***, and that is
# the check on the arithmetic rather than a coincidence: the three verbs are
# only ever ADMINISTRATOR's, so they leave one of the three sums and not the
# other two.  A run where PROGRAMMER or STANDARD also moved would mean one of
# them reached newvoc, which is the mistake stage.py's comment warns about.
#
# (Was: 21 lines, 1 + 20, ADMINISTRATOR 392 + 20 + 4 = 416.)
#
# 26 Aug 26 - BACK TO 392/417/396/354, AND THE ROUTE BACK IS THE 24 Aug ENTRY
# BELOW RUN IN REVERSE.  The MICRO verb returned (owner's ruling, same day), so
# NEWVOC gained a name and TIER.OMIT.STANDARD gained a line - PROGRAMMER and
# ADMINISTRATOR each rise by one and ***STANDARD DOES NOT MOVE***, because
# micro is withheld from STANDARD, so it joins both sides of "392 - 42" at
# once.  micro fills the slot modify vacated, which is why the numbers are
# exactly the pre-24-Aug ones rather than merely near them.
#
# ***THAT UNCHANGED 354 IS THE INSTRUMENT.*** It was measured on the 26 Aug
# 14:50 install before these constants were touched: STANDARD read 354 while
# PROGRAMMER and ADMINISTRATOR read 396 and 417, which is the arithmetic
# confirming itself against a real VOC rather than against this comment.
#
# 24 Aug 26 - WAS 392/417/396/354 UNTIL MODIFY WAS REMOVED FROM SD CORE
# (owner's ruling, same day).  NEWVOC lost one name and
# TIER.OMIT.STANDARD lost one line, so PROGRAMMER and ADMINISTRATOR each
# drop by one and ***STANDARD DOES NOT MOVE***: modify was withheld from
# STANDARD already, so it leaves both sides of "391 - 41" at once.  That
# unchanged 354 is a check on the arithmetic, not a coincidence to
# explain away.  Re-derive these from the directory, never adjust by one.
#
# 24 Aug 26 - WAS 391/408/418, AND THE COUNTS MOVED WHEN THE OWNER'S RULING ON
# THE 30/45/65 SPLIT LANDED (PROJECT_STATUS.md 8, "THE SPLIT, settled 24 Aug
# 2026").  Twelve verb records were deleted from NEWVOC (config, listu,
# list.readu, list.locks, clear.locks, lock, logout, set.date, sh, !,
# clean.account, umask) so all A verbs now live in voc_template only; UMASK
# was deleted from voc_template too.  TIER.OMIT.STANDARD grew from 17 to 42
# and TIER.ADD.ADMINISTRATOR from 10 to 21.  All three counts were re-derived
# from the arithmetic above rather than copied off a passing run.
#
# 23 Aug 26 - WAS 410/407 AND 421/411/393, AND THE THREE COUNTS MOVED TOGETHER
# WHEN PROC, SED AND UPDATE.RECORD WENT.  Three NEWVOC records were deleted -
# listpq, sed, update.record - and "sed" left TIER.OMIT.STANDARD with them.
# STANDARD fell by 2 rather than 3 BECAUSE it never had "sed" to lose: it was
# already withheld.  That asymmetry is the check that the two changes are
# consistent with each other.
#
# Three different numbers, each derived rather than observed-and-blessed, so a
# fault in either list moves one of them.  The targeted LIST VOC checks below
# then say WHICH records moved, which a count cannot.
#
# THE LAST CHECK IS THE ONE THE TIER RECORD EXISTS FOR.  UPDATE.ACCOUNT re-runs
# LOGIN's update.voc, which before 17 Aug 2026 re-copied the whole of NEWVOC and
# handed a standard account its compiler and editors back.  It is ungated, and
# the same routine is reached from an ordinary login by the $RELEASE prompt, so
# this is the half that has to hold.
#
# 28 Aug 26 - SECTION 6 ADDS SUSPENDED, AND ONLY THE HALF THIS FILE CAN REACH.
# PRE_RELEASE 38 named this verifier for the ssh and logto doors; it cannot
# test either, because the logto check sits after CPROC's elevated bypass and
# this script refuses to run unelevated.  Section 6 covers the record, the
# write-once guard on ACC$PRIOR.TIER that PRE_RELEASE 21 left unmeasured, and
# the VOC across UPDATE.ACCOUNT.  It says out loud that the doors are untested
# rather than scoring them.  The reasoning is at the section.
#
# DRIVING SD FROM POWERSHELL has two traps, both from verify-createaccount.ps1
# and both in PROJECT_STATUS.md section 6: input must be PIPED, not redirected,
# and the pipe prepends a BOM to the first line, so a blank sacrificial line
# absorbs it.

param(
    [string]$Prefix = 'sdtier',
    [switch]$Keep,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

# 17 Aug 26 - IT WRITES A TRANSCRIPT, because the first run of this script
# proved nothing.  The default cleanup deletes the account directories, and the
# VOCs are IN them, so the run destroyed the very evidence it had gathered -
# leaving three ACCOUNTS records, no VOC to count, and a PASS/FAIL table that
# existed only in a console window.  In this project the person running an
# elevated script does not paste its output back (CLAUDE.md's testing section is
# written around exactly that), so a verifier whose result lives only on screen
# has not reported anything.
#
# -Keep IS THE STRONGER RUN AND IS WORTH PREFERRING: it leaves the three
# accounts, so the VOCs can be read back independently rather than the script's
# own summary being taken on trust.  A verifier with a bug in it reports a pass.
# 17 Aug 26 - NOT UNDER C:\ProgramData\SD: cycle.ps1 deletes that tree, so a
# transcript kept there survives only until the next cycle - which is exactly
# when somebody would want to compare before and after.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-tiers-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

# Same gate as verify-createaccount.ps1, and for the same reason: CLAUDE.md
# requires a test cycle to begin with a fresh install, and this is what makes
# that enforceable rather than remembered.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-tiers: refusing - see above'
    exit 2
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-tiers: this needs an ELEVATED PowerShell - CREATE.ACCOUNT is gated on K$ADMINISTRATOR.'
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

# The tiers, and what each account is expected to come out as.
#
# 30 Aug 26 - STANDARD 354 -> 355, PRE_RELEASE_FIXES.md 7.  sort.item left
#   TIER.OMIT.STANDARD (43 lines -> 42, so 42 names -> 41) on the owner's
#   ruling: it and list.item are one program - $QPROC verbs 11 and 10 - and the
#   24 Aug read-only-inspector ruling named list.item and not its twin, so the
#   omission was never a decision.  ***PROGRAMMER 396 AND ADMINISTRATOR 419 MUST
#   NOT MOVE***: only STANDARD is derived by subtracting this list, so either of
#   the others moving would mean the name reached newvoc instead.
$Tiers = @(
    [pscustomobject]@{ Name = $Prefix + '1'; Keyword = '';              Tier = 'STANDARD';      Count = 355 }
    [pscustomobject]@{ Name = $Prefix + '2'; Keyword = 'PROGRAMMER';    Tier = 'PROGRAMMER';    Count = 396 }
    [pscustomobject]@{ Name = $Prefix + '3'; Keyword = 'ADMINISTRATOR'; Tier = 'ADMINISTRATOR'; Count = 419 }
)

# The 42 a standard account does not get.  NEWVOC/TIER.OMIT.STANDARD is the
# authority; this list is checked against it below rather than trusted, because
# a test that carries its own stale copy of the thing under test is no test.
# 18 Aug 26 - LOWER CASE, because the command ids moved (PROJECT_STATUS.md
# 5.12 (b)).  Compare-Object below is case insensitive and would not have
# noticed, which is exactly why this is spelled the way the record now is.
# 23 Aug 26 - "sed" REMOVED, and the check above is what caught it: the shipped
# TIER.OMIT.STANDARD lost the line when the editor went, and this copy did not,
# so "shipped TIER.OMIT.STANDARD matches this test" failed with 1 difference.
# That check is the reason this list is allowed to exist at all - keep it.
# 24 Aug 26 - GREW FROM 17 TO 42 with the owner's split ruling.  Four groups,
# same order as the shipped record: P1 compilers/editors/catalogue (15), P2
# file & index definition (14), P3 bulk record edit (9), P4 process
# introspection (4).  sh and ! are no longer here - they moved to
# TIER.ADD.ADMINISTRATOR because the ruling puts them ADMIN-only rather than
# PROGRAMMER-and-above.
$Withheld = @(
    # P1 - compilers, editors, code catalogue
    'basic','catalog','catalogue','delete.catalog','delete.catalogue',
    'compile.dict','cd','generate','phantom','run','map','debug','ed','edit','micro',
    # P2 - file and index definition
    'create.file','delete.file','clear.file','configure.file',
    'analyse.file','analyze.file','fstat','hsm','set.trigger',
    'create.index','delete.index','build.index','make.index','list.index',
    # P3 - bulk record edit
    'copy','copyp','delete','rename','reformat','sreformat','sort.item','delete.common','cname',
    # P4 - process introspection
    'pstat','pdebug','pdump','dump'
)

# The 23 only an administrator gets.  MODIFY.PASSWORD joined on 17 Aug 2026 -
# owner's ruling, and an administrator can add it to a user's VOC if they want
# users setting their own.  The program already tells the two cases apart:
# your own password needs the current one, anyone else's needs admin rights.
# 24 Aug 26 - GREW FROM 10 TO 21 with the owner's split ruling.  The A3
# system-state and A4 shell-escape verbs moved out of NEWVOC entirely because
# a PROGRAMMER should not have sh, !, config, listu, list.readu, list.locks,
# clear.locks, lock, logout, set.date, or clean.account either.
#
# 30 Aug 26 - AND FROM 20 TO 23 with PRE_RELEASE 78's three verbs.  They are
# administrator-only for the same reason config and lock are: they change what
# the MACHINE offers - the ssh server, the API listener, who may reach either -
# rather than what one account sees.
#
# ***THIS LIST AND THE Count IN $Tiers ARE TWO PLACES AND BOTH MOVE.***  On
# 30 Aug 2026 I changed ADMINISTRATOR 416 -> 419 and did NOT change this list,
# and section 0 caught it on the next run: "shipped TIER.ADD.ADMINISTRATOR
# matches this test: expected 0, got 3", naming all three, followed by "add
# list length: expected 20, got 23".  That is this test working exactly as the
# comment below it promises - it exists so that nobody gets away with "updating
# the record and not the test, or the other way about" - and it is why the
# SHIPPED record is compared against rather than trusted.
$AdminVerbs = @(
    # A1 - account and grant administration
    'create.account','delete.account','modify.account','update.account','clean.account',
    'grant','revoke','list.grants','unlock','modify.password',
    # A2 - the machine's network services
    'remote.api','remote.ssh','ssh.server',
    # A3 - system-wide state
    'config','listu','list.readu','list.locks','clear.locks','lock','logout','set.date',
    # A4 - shell escapes
    'sh','!'
)

# Neither list record may ever land in a VOC.
$ListRecs = @('TIER.OMIT.STANDARD','TIER.ADD.ADMINISTRATOR')

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

# DO NOT USE THIS FOR "sd -start" - see verify-createaccount.ps1's Start-SD and
# PROJECT_STATUS.md section 6.  Nothing here starts SD; cycle.ps1 leaves the
# service running.
#
# 24 Aug 26 - TERM 200,9999 IS RE-APPLIED AFTER EVERY LOGTO the caller passes,
# AND FOR THE REASON THIS FUNCTION HAS ALWAYS HAD SUCH A LINE ONCE UP FRONT.
# LOGIN re-initialises terminal depth and width from env('LINES')/env('COLUMNS')
# on every account switch (LOGIN:201-209), so a TERM set BEFORE a LOGTO is
# wiped by that LOGTO.  Section 3 stopped fitting inside the default page depth
# on 24 Aug when the split grew LIST VOC's output from ~29 to ~65 lines, and
# the resulting page prompt hung the pipe forever - a page prompt reads from
# the same stdin the script is feeding, so once OFF has been written no answer
# ever arrives.  This function now inserts a fresh TERM after every LOGTO the
# caller supplied, so a section that swaps accounts stays in the wide terminal
# it asked for.  PROJECT_STATUS.md section 8, fiftieth session.
function Invoke-SD([string[]]$commands) {
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

function Get-VocCount($text) {
    if ($text -match '(\d+)\s+record\(s\) counted') { return [int]$Matches[1] }
    return -1
}

# LIST VOC prints found records in a table and missing ones as
#   'NAME' not found
# so absence is read from the message and presence from its absence.  Ids are
# quoted going in, which is what keeps "!" and dotted names intact.
function Get-Missing($text, [string[]]$ids) {
    $missing = @()
    foreach ($id in $ids) {
        if ($text -match ("'" + [regex]::Escape($id) + "' not found")) { $missing += $id }
    }
    return $missing
}

function Get-AccountTier($name) {
    $rec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $name.ToUpper())
    if (-not (Test-Path -LiteralPath $rec)) { return '<no ACCOUNTS record>' }
    $f = Get-Content -LiteralPath $rec
    if ($f.Count -lt 5) { return '<blank>' }
    if ([string]::IsNullOrEmpty($f[4])) { return '<blank>' }
    return $f[4]
}

# 28 Aug 26 - ACC$PRIOR.TIER, field 6 (SYSCOM/KEYS.H:289) - the tier SUSPENDED
# displaced.  Section 6 is the only reader; it is what proves a restore read the
# record rather than defaulting to something that happens to look right.
function Get-AccountPriorTier($name) {
    $rec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $name.ToUpper())
    if (-not (Test-Path -LiteralPath $rec)) { return '<no ACCOUNTS record>' }
    $f = Get-Content -LiteralPath $rec
    if ($f.Count -lt 6) { return '<blank>' }
    if ([string]::IsNullOrEmpty($f[5])) { return '<blank>' }
    return $f[5]
}

# 28 Aug 26 - ANCHOR ON THE SUCCESS WORDING, AND REFUSE IF A FAILURE WORDING IS
# ALSO PRESENT.  CLAUDE.md, "a check must anchor on the SUCCESS wording": the
# account name and the tier keyword are in SD's echo of the command and in
# every refusal, so matching either proves nothing.  $positive must be text the
# verb prints ONLY when it did the thing - here sysmsg 10109 "Account %1 is now
# %2" - and $bad are the refusals that would otherwise hide underneath a match.
# Returns a string so Note can compare it, and so a failure names WHICH refusal.
function Get-Said($text, [string]$positive, [string[]]$bad) {
    foreach ($b in $bad) {
        if ($text -match $b) { return ('refused: ' + $b) }
    }
    if ($text -match $positive) { return 'said' }
    return 'not said'
}

# Rule 1 of the instrument section: print what the tool actually did, every
# time, not only when the verdict looks wrong.  A subtle refusal is one no
# conditional print catches, because the condition is the thing that was wrong.
#
# 28 Aug 26 - WHAT THIS PRINTS IS POST-ANSI-STRIP, SO ECHOES CAN LOOK MANGLED.
# Invoke-SD removes escape sequences before returning, and SD redraws its
# command line as it echoes, so the two halves of a redraw arrive joined: the
# 00:07:29 run printed "MODIFY.ACSDTIER2 PROGRAMMER" one line above the real
# "MODIFY.ACCOUNT SDTIER2 PROGRAMMER".  ***THAT IS THIS FUNCTION'S RENDERING,
# NOT SD'S OUTPUT, AND NO CHECK READS IT*** - every Note anchors on a sysmsg
# the verb prints on its own line.  Do not go looking for a parser bug in SD.
# If a run ever needs the true bytes, the fix is in Invoke-SD, which is where
# the stripping happens.
function Show-Raw($label, $text) {
    Write-Output ('    --- ' + $label + ' said: ---')
    foreach ($line in ($text -split "`n")) {
        if ($line.Trim() -ne '') { Write-Output ('    | ' + $line.TrimEnd()) }
    }
}

function Remove-Made {
    foreach ($t in $Tiers) {
        if (Get-LocalUser -Name $t.Name -ErrorAction SilentlyContinue) {
            Remove-LocalUser -Name $t.Name
            Write-Output ("  removed Windows account " + $t.Name)
        }
        $d = Join-Path $env:ProgramData ('SD\user_accounts\' + $t.Name)
        if (Test-Path -LiteralPath $d) {
            Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
        }
        $g = 'sdu_' + $t.Name
        if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $g }
    }
    # The SD half is left deliberately: DELETE.ACCOUNT is its own subject and
    # removing the register records here would hide a CREATE.ACCOUNT that had
    # half failed.  A rerun is refused by CREATE.ACCOUNT itself, which is the
    # right way round.
    Write-Output '  ACCOUNTS register records left in place - remove with DELETE.ACCOUNT'
}

if ($Cleanup) { Remove-Made; exit 0 }

# ---------------------------------------------------------------------------
Write-Output '=== 0. The omit list this test asserts against ============================'

# Read the shipped list and compare it with $Withheld.  If they disagree the
# test is out of date, and saying so is worth more than failing obscurely.
$omitRec  = Join-Path $env:ProgramData 'SD\sdsys\newvoc\TIER.OMIT.STANDARD'
$shipped  = @(Get-Content -LiteralPath $omitRec | Select-Object -Skip 1)
$diff     = (Compare-Object $shipped $Withheld -SyncWindow 100)
Note 'shipped TIER.OMIT.STANDARD matches this test' 0 ($diff | Measure-Object).Count
if ($diff) { $diff | ForEach-Object { Write-Output ("    {0} {1}" -f $_.SideIndicator, $_.InputObject) } }
Note 'omit list length' $Withheld.Count $shipped.Count

# 17 Aug 26 - AND THE SAME FOR THE ADD LIST, which was NOT cross-checked and
# should always have been: the reasoning above - "a test that carries its own
# stale copy of the thing under test is no test" - is not specific to the omit
# list.  It went unnoticed while the add list never changed; MODIFY.PASSWORD
# joining it on 17 Aug 2026 is exactly the edit that would have slipped
# through, updating the record and not the test, or the other way about.
$addRec    = Join-Path $env:ProgramData 'SD\sdsys\newvoc\TIER.ADD.ADMINISTRATOR'
$shippedAd = @(Get-Content -LiteralPath $addRec | Select-Object -Skip 1)
$diffAd    = (Compare-Object $shippedAd $AdminVerbs -SyncWindow 100)
Note 'shipped TIER.ADD.ADMINISTRATOR matches this test' 0 ($diffAd | Measure-Object).Count
if ($diffAd) { $diffAd | ForEach-Object { Write-Output ("    {0} {1}" -f $_.SideIndicator, $_.InputObject) } }
Note 'add list length' $AdminVerbs.Count $shippedAd.Count

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 1. Creating one account per tier ======================================'

Add-Type -AssemblyName System.Web
foreach ($t in $Tiers) {
    if (Get-LocalUser -Name $t.Name -ErrorAction SilentlyContinue) {
        Write-Output ("  " + $t.Name + " already exists - run with -Cleanup first")
        exit 2
    }
    # 17 Aug 26 - AND CHECK THE REGISTER, NOT JUST WINDOWS.  Remove-Made
    # deliberately leaves the ACCOUNTS record behind (see its comment), so after
    # one run the Windows account is gone and the SD account is not.
    # CREATE.ACCOUNT then refuses the name for a reason that has nothing to do
    # with the tiers, several steps further on, and reads like a tier fault.
    # Give it a fresh prefix instead: -Prefix sdtierb.
    if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $t.Name.ToUpper()))) {
        Write-Output ("  " + $t.Name.ToUpper() + " is still in the ACCOUNTS register from an earlier run.")
        Write-Output ("  CREATE.ACCOUNT would refuse it.  Use a fresh set of names, e.g.:")
        Write-Output ("      " + $PSCommandPath + " -Keep -Prefix sdtierb")
        exit 2
    }
    $pw  = [System.Web.Security.Membership]::GeneratePassword(24, 6)
    $cmd = ('CREATE.ACCOUNT USER ' + $t.Name + ' ' + $t.Keyword + ' BOTH').Trim()
    Write-Output ("  " + $cmd)
    $out = Invoke-SD @($cmd, $pw, $pw)
    # 19 Aug 26 - THE REGISTER RECORD, NOT THE OUTPUT TEXT.  This used to be
    # "if ($out -notmatch $t.Name)", A CHECK THAT COULD NEVER FAIL: SD echoes
    # the command it was given, so the account name is in the output whether
    # CREATE.ACCOUNT worked or refused.  A run in which nothing at all was
    # created therefore walked past this and first showed up in section 3 as
    # all three tiers holding 429 records with nothing withheld - which reads
    # exactly like the silent tier-filter failure 5.12 warns about, and is
    # not.  429 is how many records voc_template holds: LOGTO had failed and
    # left every session in SDSYS.  Assert the thing CREATE.ACCOUNT is FOR.
    $rec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $t.Name.ToUpper())
    if (-not (Test-Path -LiteralPath $rec)) {
        Write-Output '  --- SD said: ---'
        Write-Output $out
        Write-Output ('  CREATE.ACCOUNT wrote no accounts record for ' + $t.Name.ToUpper())
        Write-Output '  Everything after this would measure SDSYS, not the account.'
        exit 2
    }
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 2. The recorded tier (ACCOUNTS field 5) ==============================='

foreach ($t in $Tiers) { Note ($t.Name + ' ACC$TIER') $t.Tier (Get-AccountTier $t.Name) }
Note 'DON ACC$TIER (the ADOPT default)' 'ADMINISTRATOR' (Get-AccountTier 'DON')

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 3. COUNT VOC per tier ================================================='

$vocText = @{}
foreach ($t in $Tiers) {
    $text = Invoke-SD @(('LOGTO ' + $t.Name.ToUpper()), 'COUNT VOC',
                        ("LIST VOC " + (($Withheld + $AdminVerbs + $ListRecs |
                            ForEach-Object { "'" + $_ + "'" }) -join ' ')))
    $vocText[$t.Name] = $text
    Note ($t.Name + ' COUNT VOC') $t.Count (Get-VocCount $text)
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 4. Which records, per tier ============================================'

foreach ($t in $Tiers) {
    $text = $vocText[$t.Name]

    # The 42 withheld: absent for STANDARD, present for the other two.
    $missWithheld = Get-Missing $text $Withheld
    $wantWithheld = $(if ($t.Tier -eq 'STANDARD') { $Withheld.Count } else { 0 })
    Note ($t.Name + ' withheld capabilities MISSING') $wantWithheld ($missWithheld | Measure-Object).Count
    if ($missWithheld -and $t.Tier -ne 'STANDARD') {
        Write-Output ('    missing: ' + ($missWithheld -join ' '))
    }

    # The 21 admin: present for ADMINISTRATOR only.  This is the control that
    # stops a broken add list looking like a working one.
    $missAdmin = Get-Missing $text $AdminVerbs
    $wantAdmin = $(if ($t.Tier -eq 'ADMINISTRATOR') { 0 } else { $AdminVerbs.Count })
    Note ($t.Name + ' administration verbs MISSING') $wantAdmin ($missAdmin | Measure-Object).Count

    # Neither list record, in any tier.
    Note ($t.Name + ' TIER.* list records MISSING') 2 ((Get-Missing $text $ListRecs) | Measure-Object).Count
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 5. UPDATE.ACCOUNT must not give the standard account its verbs back ==='

# The whole reason ACC$TIER exists.  Before 17 Aug 2026 this restored all of
# them - the count has moved since and the sentence is about the behaviour.
$std  = $Tiers[0]
$text = Invoke-SD @(('LOGTO ' + $std.Name.ToUpper()), 'UPDATE.ACCOUNT', 'COUNT VOC',
                    ("LIST VOC " + (($Withheld | ForEach-Object { "'" + $_ + "'" }) -join ' ')))
Note 'standard COUNT VOC after UPDATE.ACCOUNT' $std.Count (Get-VocCount $text)
Note 'standard withheld still MISSING after UPDATE.ACCOUNT' $Withheld.Count ((Get-Missing $text $Withheld) | Measure-Object).Count

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 6. SUSPENDED: the record, the write-once guard, and the VOC ==========='

# 28 Aug 26 - PRE_RELEASE 38 asked for SUSPENDED coverage and named this file
# for the ssh and logto doors.  ***THAT PART OF 38 IS WRONG AND THIS SECTION
# DELIBERATELY DOES NOT ATTEMPT IT.***  CPROC's logto.authorised puts the
# suspension test AFTER two privileged bypasses (CPROC:3729 elevated,
# CPROC:3755 elevation just obtained), which is a recorded judgement call at
# CPROC:3765, not an oversight.  This verifier REFUSES to run unelevated -
# CREATE.ACCOUNT is gated on K$ADMINISTRATOR - so every LOGTO it issues takes
# the bypass.  A door test written here would enter a suspended account, and
# report a product fault that is the design working.  What the doors need is
# an UNELEVATED session as a user the suspension actually denies; the shape is
# in PRE_RELEASE 38.
#
# WHAT IS HONESTLY TESTABLE FROM AN ELEVATED SESSION IS THE OTHER HALF OF THE
# FEATURE, and it is the half with a write-once rule and a VOC in it:
#
#   the record      ACC$TIER goes to SUSPENDED and ACC$PRIOR.TIER keeps the
#                   tier it displaced (SYSCOM/KEYS.H:287,289)
#   the guard       a second suspend returns at the equality test (10110) and
#                   so never reaches the field-6 write - PRE_RELEASE 21 says
#                   that guard is the whole write-once mechanism now that the
#                   unreachable inner test is deleted, and nothing measured it
#   the VOC         "SUSPENDED denies access and changes nothing else"
#                   (MODIFYA:98).  UPDATE.ACCOUNT on a suspended account must
#                   resolve SUSPENDED to ACC$PRIOR.TIER (LOGIN:283, :1212) or
#                   a release update strips a suspended account's verbs - the
#                   exact failure section 5 exists for, on the tier that has
#                   no VOC of its own
#
# THE PROGRAMMER ACCOUNT IS USED ON PURPOSE.  Restoring to PROGRAMMER proves
# field 6 was READ; a STANDARD account would be restored to the value a
# defaulting bug would also produce, and would pass either way.
$susp     = $Tiers[1]
$suspName = $susp.Name.ToUpper()
$suspRe   = [regex]::Escape($suspName)

# The refusals that must not be hiding under a positive match.  10114 "Unable
# to change the tier", 10110 "is already", 10112 "cannot suspend your own",
# 10108 "no record of the tier it held".
$tierBad = @('Unable to change the tier', 'is already', 'cannot suspend',
             'no record of the tier')

$cmd = 'MODIFY.ACCOUNT ' + $suspName + ' SUSPENDED'
Write-Output ('  ' + $cmd)
$out = Invoke-SD @($cmd)
Show-Raw $cmd $out
Note 'suspend says 10109 "Account X is now SUSPENDED"' 'said' `
     (Get-Said $out ('Account\s+' + $suspRe + '\s+is now\s+SUSPENDED') $tierBad)
Note ($susp.Name + ' ACC$TIER after suspend') 'SUSPENDED' (Get-AccountTier $susp.Name)
Note ($susp.Name + ' ACC$PRIOR.TIER holds the displaced tier') 'PROGRAMMER' `
     (Get-AccountPriorTier $susp.Name)

# THE WRITE-ONCE GUARD, WHICH IS THE ONE PRE_RELEASE 21 LEFT UNMEASURED.  Run
# the identical command a second time: it must stop at the equality test with
# 10110 and NOT write field 6, because at that point old.tier IS SUSPENDED and
# a write would overwrite PROGRAMMER with it - losing the only record of what
# the account was, permanently.  The second Note is the one that matters; the
# first only says the guard was the thing that stopped it.
Write-Output ('  ' + $cmd + '   (again - the equality guard, PRE_RELEASE 21)')
$out2 = Invoke-SD @($cmd)
Show-Raw 'second suspend' $out2
Note 'second suspend says 10110 "is already"' 'said' `
     (Get-Said $out2 ($suspRe + '\s+is already\s+SUSPENDED') @('is now', 'Unable to change the tier'))
Note ($susp.Name + ' ACC$PRIOR.TIER survived the second suspend') 'PROGRAMMER' `
     (Get-AccountPriorTier $susp.Name)

# THE VOC IS UNTOUCHED, AND THIS ALSO REFUSES THE NULL CASE.  If the LOGTO had
# been refused the session would still be standing in SDSYS and COUNT VOC would
# answer with SDSYS's VOC, which is not 396 - so a test that measured nothing
# FAILS here rather than passing quietly.  The elevated bypass is asserted
# rather than worked around: if CPROC:3765 is ever changed, this check is what
# says so.
$text = Invoke-SD @(('LOGTO ' + $suspName), 'COUNT VOC')
Note 'elevated LOGTO enters a suspended account (CPROC:3765)' $susp.Count (Get-VocCount $text)

# AND UPDATE.ACCOUNT MUST NOT STRIP IT.  Section 5 asks this of a standard
# account; a suspended one is the harder case, because SUSPENDED is not a VOC
# tier and update.voc has to resolve it to field 6 to know what to copy.
$text = Invoke-SD @(('LOGTO ' + $suspName), 'UPDATE.ACCOUNT', 'COUNT VOC',
                    ("LIST VOC " + (($Withheld + $AdminVerbs |
                        ForEach-Object { "'" + $_ + "'" }) -join ' ')))
Note 'suspended COUNT VOC after UPDATE.ACCOUNT' $susp.Count (Get-VocCount $text)
# 28 Aug 26 - THE COUNTS IN THESE TWO LABELS ARE INTERPOLATED, NOT TYPED.  They
# read "the 42 withheld" and "the 21 administration verbs" when they were
# written, and the 00:53:34 run printed "the 21 administration verbs are still
# ABSENT ... 20 20 PASS" - a passing row whose own name contradicted it, because
# PRE_RELEASE 25 removed encrypt.field.  A label carrying a constant is a second
# place for the number to live and it drifts silently; the row above it derives
# everything, so this one does too.
Note ("suspended: the " + $Withheld.Count + " withheld are still PRESENT") 0 `
     ((Get-Missing $text $Withheld) | Measure-Object).Count
Note ("suspended: the " + $AdminVerbs.Count + " administration verbs are still ABSENT") $AdminVerbs.Count `
     ((Get-Missing $text $AdminVerbs) | Measure-Object).Count

# RESTORE, AND IT IS A CHECK RATHER THAN TIDYING UP.  Naming a tier on a
# suspended account lifts the suspension into that tier (MODIFYA:94), and 10108
# - "has no record of the tier it held" - is the disqualifier that says field 6
# was lost somewhere above.
$cmdR = 'MODIFY.ACCOUNT ' + $suspName + ' PROGRAMMER'
Write-Output ('  ' + $cmdR)
$outR = Invoke-SD @($cmdR)
Show-Raw $cmdR $outR
Note 'restore says 10109 "Account X is now PROGRAMMER"' 'said' `
     (Get-Said $outR ('Account\s+' + $suspRe + '\s+is now\s+PROGRAMMER') $tierBad)
Note ($susp.Name + ' ACC$TIER after restore') 'PROGRAMMER' (Get-AccountTier $susp.Name)

Write-Output ''
Write-Output '  THE THREE DOORS ARE NOT TESTED ABOVE, AND THIS IS NOT A PASS:'
Write-Output '    LOGIN (ssh/console)  LOGIN:477 -> 10107.  Needs a real ssh login as the'
Write-Output '                         suspended account.  verify-sshonly.ps1 has the'
Write-Output '                         SSH_ASKPASS machinery; this file does not.'
Write-Output '    logto                CPROC:3776 -> 10107.  UNTESTABLE FROM HERE - the'
Write-Output '                         check sits after the elevated bypass asserted above.'
Write-Output '    the API              APISRVR:507 -> 10003, which reads identically to'
Write-Output '                         "no such account" and "not granted", so only a'
Write-Output '                         controlled pair on one account can tell them apart.'
Write-Output '  PRE_RELEASE 38 carries the shape.  Nothing here counts them as covered.'

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== Summary ==============================================================='
$results | Format-Table -AutoSize | Out-String | Write-Output

if (-not $Keep) {
    Write-Output '=== Cleanup ==============================================================='
    Remove-Made
} else {
    Write-Output ('-Keep: the three accounts are still there.  Remove with -Cleanup.')
}

# The verdict goes in BEFORE the transcript is stopped, or the one line anybody
# would look for is the one line the file does not have.
if ($failed) { Write-Output 'VERIFY-TIERS: FAILED - see the table.' }
else         { Write-Output 'VERIFY-TIERS: all checks passed.' }
Write-Output ("transcript: " + $logPath)
try { Stop-Transcript | Out-Null } catch { }

if ($failed) { exit 1 }
exit 0
