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
#   STANDARD       has neither the 17 withheld capabilities nor the 10
#                  administration verbs
#   PROGRAMMER     has the 17 and NOT the 10       <- controls the add list
#   ADMINISTRATOR  has both                        <- controls the omit list
#
# COUNT VOC IS THE PRIMARY INSTRUMENT, because it is exact and arithmetic
# rather than a spot check.  Installed NEWVOC holds 407 names, of which "%t" is
# a dynamic-file artefact and not a record, and TIER.OMIT.STANDARD and
# TIER.ADD.ADMINISTRATOR are lists that must never be copied - so 404 records
# reach a full VOC.  CREATEA then adds four of its own ($COMMAND.STACK, $hold,
# $savedlists, BP).  That gives:
#
#   ADMINISTRATOR  404 + 10 + 4 = 418     (9 until MODIFY.PASSWORD joined them)
#   PROGRAMMER     404     + 4 = 408
#   STANDARD       404 - 17 + 4 = 391
#
# 23 Aug 26 - WAS 410/407 AND 421/411/393, AND THE THREE COUNTS MOVED TOGETHER
# WHEN PROC, SED AND UPDATE.RECORD WENT.  Three NEWVOC records were deleted -
# listpq, sed, update.record - and "sed" left TIER.OMIT.STANDARD with them, so
# the omit list is 17.  STANDARD fell by 2 rather than 3 BECAUSE it never had
# "sed" to lose: it was already withheld.  That asymmetry is the check that the
# two changes are consistent with each other, and all three numbers below were
# re-derived from it rather than copied off a failing run.
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
$Tiers = @(
    [pscustomobject]@{ Name = $Prefix + '1'; Keyword = '';              Tier = 'STANDARD';      Count = 391 }
    [pscustomobject]@{ Name = $Prefix + '2'; Keyword = 'PROGRAMMER';    Tier = 'PROGRAMMER';    Count = 408 }
    [pscustomobject]@{ Name = $Prefix + '3'; Keyword = 'ADMINISTRATOR'; Tier = 'ADMINISTRATOR'; Count = 418 }
)

# The 17 a standard account does not get.  NEWVOC/TIER.OMIT.STANDARD is the
# authority; this list is checked against it below rather than trusted, because
# a test that carries its own stale copy of the thing under test is no test.
# 18 Aug 26 - LOWER CASE, because the command ids moved (PROJECT_STATUS.md
# 5.12 (b)).  Compare-Object below is case insensitive and would not have
# noticed, which is exactly why this is spelled the way the record now is.
# 23 Aug 26 - "sed" REMOVED, and the check above is what caught it: the shipped
# TIER.OMIT.STANDARD lost the line when the editor went, and this copy did not,
# so "shipped TIER.OMIT.STANDARD matches this test" failed with 1 difference.
# That check is the reason this list is allowed to exist at all - keep it.
$Withheld = @('basic','catalog','catalogue','run','ed','edit','copy','copyp',
              'delete.catalog','delete.catalogue','modify','compile.dict','cd',
              'generate','phantom','sh','!')

# The 10 only an administrator gets.  MODIFY.PASSWORD joined on 17 Aug 2026 -
# owner's ruling, and an administrator can add it to a user's VOC if they want
# users setting their own.  The program already tells the two cases apart:
# your own password needs the current one, anyone else's needs admin rights.
$AdminVerbs = @('create.account','delete.account','modify.account','update.account',
                'grant','revoke','list.grants','unlock','encrypt.field',
                'modify.password')

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
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
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

    # The 17: absent for STANDARD, present for the other two.
    $missWithheld = Get-Missing $text $Withheld
    $wantWithheld = $(if ($t.Tier -eq 'STANDARD') { $Withheld.Count } else { 0 })
    Note ($t.Name + ' withheld capabilities MISSING') $wantWithheld ($missWithheld | Measure-Object).Count
    if ($missWithheld -and $t.Tier -ne 'STANDARD') {
        Write-Output ('    missing: ' + ($missWithheld -join ' '))
    }

    # The 9: present for ADMINISTRATOR only.  This is the control that stops a
    # broken add list looking like a working one.
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
