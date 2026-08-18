# verify-catgate.ps1 - prove that reaching the GLOBAL catalogue requires
# administrator rights by every route, and that nothing else moved.
# PROJECT_STATUS.md section 8, UPSTREAM_FIXES.md 7.
#
#   powershell -File verify-catgate.ps1            create, check, clean up
#   powershell -File verify-catgate.ps1 -Keep      leave the account behind
#   powershell -File verify-catgate.ps1 -Cleanup   remove one left by -Keep
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# WHAT WAS WRONG.  CATALOG chooses the global catalogue two ways: the GLOBAL
# keyword, which has always tested K$ADMINISTRATOR, and a call name beginning
# with one of "*!_$", which set the same mode in three places and tested
# nothing.  So "CATALOG BP MYPROG GLOBAL" was refused and "CATALOG BP $MYPROG"
# was allowed, though they do the same thing.  DELETE.CATALOG tested nothing at
# all by either route.  gcat holds $LOGIN as object code and CPROC:315 calls it
# for every session, so the write was code execution in everybody's session and
# the delete was a denial of service for the whole machine.
#
# HOW A NON-ADMINISTRATOR SESSION IS OBTAINED WITHOUT A PASSWORD, WHICH IS WHAT
# MAKES THIS TESTABLE AT ALL.  SD accounts are in sdsshonly, which carries
# SeDenyInteractiveLogonRight, so Start-Process -Credential cannot start sd.exe
# as one of them - that is section 5.6.2 working, not a fault.  It is not
# needed: CPROC:2657-2671 gives administrator rights up on the way OUT of
# SDSYS, so "LOGTO SDSYS" then "LOGTO <account>" is a genuinely unprivileged
# session in the same pipe.  K$ADMINISTRATOR cannot be forged back - op_kernel.c
# gates setting it on HDR_INTERNAL, and ordinary BASIC cannot reach KERNEL.
#
# A CONSEQUENCE WORTH KNOWING: only SDSYS is administrator.  CPROC sets the flag
# for SDSYS and clears it for everything else, so an ADMINISTRATOR-tier account
# cannot catalogue globally either while it is standing in its own account.
# That is why the control below is run in SDSYS and not in a third tier.
#
# THE EVIDENCE IS THE FILESYSTEM, NOT THE MESSAGE.  gcat and the account's cat
# are directory files, so an entry is a file and its presence or absence is a
# fact rather than a parsed screen.  Messages are checked as well, because a
# refusal for the wrong reason - a missing file, a syntax error - would also
# leave gcat untouched and would otherwise read as a pass.
#
# DRIVING SD FROM POWERSHELL has two traps, both in PROJECT_STATUS.md section 6:
# input must be PIPED, not redirected, and the pipe prepends a BOM to the first
# line, so a blank sacrificial line absorbs it.  Invoke-SD below is
# verify-tiers.ps1's, unchanged.

param(
    [string]$Account = 'sdcatg1',
    [switch]$Keep,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

# Same reasoning as verify-tiers.ps1: the person running an elevated script here
# does not paste its output back, so a result that lives only in a console
# window has not been reported.  Not under C:\ProgramData\SD - cycle.ps1 deletes
# that tree, which is exactly when a before-and-after comparison is wanted.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-catgate-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

$dataDir  = Join-Path $env:ProgramData 'SD'
$sdsys    = Join-Path $dataDir 'sdsys'
$gcat     = Join-Path $sdsys 'gcat'
$acctDir  = Join-Path $dataDir ('user_accounts\' + $Account)
$sdExe    = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

# The scratch file the SDSYS control compiles from, and the call names.
#
# DERIVED FROM -Account, SO EVERY RUN USES A NAME SDSYS HAS NEVER SEEN.  On the
# 11:42:41 run - the first to reuse a fixed name that an earlier run had
# DELETE.FILE'd - "BASIC SDGATEBP SDGATE" produced no .OUT and the two controls
# failed with it.  THAT IS NOT DIAGNOSED.  An earlier note here claimed the
# cause was a missing VOC entry; it was not, it was this script looking for a
# VOC record as a file when VOC is a dynamic file (see the CREATE.FILE check
# below).  Reusing the name may or may not have been the real cause.
#
# Per-run names are cheap and remove the variable either way; the teardown below
# now also clears .DIC and .OUT, which the version that failed did not.  If it
# recurs, the BASIC step prints what SD said instead of failing silently, which
# is what was missing both times.  The account's own names need no such
# treatment: its directory is created fresh by every run.
$ctlFile   = $Account.ToUpper() + 'BP'
$ctlDir    = Join-Path $sdsys $ctlFile
$ctlName   = $Account.ToUpper() + 'G'
$userName  = 'SDGATE2'
$localName = 'SDGATE3'

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

function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

# TWO TEARDOWNS, NOT ONE, AND THE SPLIT IS LOAD-BEARING.  The account debris and
# the control's own fixtures have different lifetimes: a stale ACCOUNT from an
# earlier -Keep run must go BEFORE this run creates its account, while the
# fixtures in SDSYS and gcat are created by section 1 of THIS run and must
# survive until section 7.  One combined function called at both moments wiped
# gcat\$SDGATE half way through the 11:35:44 run and failed two checks in
# sections 4 and 7 - the fix was fine, the teardown was not.
function Remove-Account {
    if (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $Account
        Write-Output ("  removed Windows account " + $Account)
    }
    if (Test-Path -LiteralPath $acctDir) {
        Remove-Item -LiteralPath $acctDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    $g = 'sdu_' + $Account
    if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $g }
}

# The scratch file in SDSYS and anything this test put in gcat.  Both are ours;
# nothing shipped is touched.
#
# THROUGH SD, NOT WITH Remove-Item, because CREATE.FILE also wrote a VOC entry
# in SDSYS and that is a record in a dynamic file - deleting the directory alone
# would leave SDSYS's VOC naming a file that is not there.
function Remove-Fixtures {
    # FORCE, NOT A PIPED "Y".  DELETEF prompts separately for the DATA and DICT
    # parts, each in an unbounded "until yn = 'Y' or 'N'" loop, and only when the
    # stored path differs from the default name.  This script's fixtures are
    # upper case so neither prompt fires today - but that is luck, not design,
    # and the same "Y" pattern hung verify-fold.ps1 on 18 Aug 2026.
    if (Test-Path -LiteralPath $ctlDir) {
        $null = Invoke-SD @("DELETE.FILE $ctlFile FORCE")
    }
    foreach ($p in @($ctlDir, ($ctlDir + '.OUT'), ($ctlDir + '.DIC'), (Join-Path $gcat ('$' + $ctlName)))) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

function Remove-Made {
    Remove-Account
    Remove-Fixtures
    Write-Output '  ACCOUNTS register record left in place - remove with DELETE.ACCOUNT'
}

if ($Cleanup) { Remove-Made; exit 0 }

# CLAUDE.md requires a test cycle to begin with a fresh install; this is what
# makes that enforceable rather than remembered.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-catgate: refusing - see above'
    exit 2
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-catgate: this needs an ELEVATED PowerShell - CREATE.ACCOUNT is gated on K$ADMINISTRATOR.'
    exit 2
}

# The program both halves compile.  Trivial on purpose: this tests who may
# catalogue, not what the compiler does.
$src = @(
    '* Created by verify-catgate.ps1 - safe to delete'
    "   crt 'SDGATE OK'"
) -join "`r`n"

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 0. $LOGIN is in gcat before anything runs ============================='

# The baseline for the check that matters most.  If $LOGIN were already missing,
# "still there at the end" would prove nothing.
$loginPath = Join-Path $gcat '$LOGIN'
Note '$LOGIN present in gcat at start' $true (Test-Path -LiteralPath $loginPath)
if (-not (Test-Path -LiteralPath $loginPath)) {
    Write-Output '  gcat has no $LOGIN - the tree is not one this test can measure.'
    exit 2
}
$loginBefore = (Get-Item -LiteralPath $loginPath).Length

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 1. An administrator can still catalogue globally (the control) ========'

# Without this the whole test passes on a gate that refuses everybody, which
# would be a regression dressed as a fix.
foreach ($p in @($ctlDir, ($ctlDir + '.DIC'), ($ctlDir + '.OUT'))) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}

# EVERY FIXTURE STEP IS CHECKED AND SAYS WHAT SD SAID, because when this section
# fails quietly the two controls fail with it and the summary reads as though
# the FIX were broken.  That happened twice (11:35:44 and 11:42:41); both times
# the gate was fine and the scaffolding was not.  A control that cannot be built
# is "could not be run" - exit 2 - never a FAIL.
$out = Invoke-SD @("CREATE.FILE $ctlFile DIRECTORY")

# ASK SD WHETHER IT MADE THE FILE; DO NOT GO LOOKING FOR THE VOC RECORD.
# A VOC entry is NOT a file on disk: VOC is a DYNAMIC file (CREATEA:575,
# "create.file ... VOC dynamic"), which on disk is a directory of %0, %1
# hashing buckets - sdsys\VOC holds exactly two files however many hundred
# records it has.  A Test-Path for sdsys\VOC\<name> can therefore never be
# true, and the version of this check that did that refused a CREATE.FILE
# which had plainly succeeded, on the 12:46:36 run, printing SD's own
# "Created DATA part as ..." immediately above its complaint.
#
# The directory test is kept as well: the message says what SD believes, the
# path says what is actually there, and the control needs both.
if (($out -notmatch 'Created DATA part as') -or -not (Test-Path -LiteralPath $ctlDir)) {
    Write-Output '  --- SD said: ---'; Write-Output $out
    Write-Output "  CREATE.FILE $ctlFile did not make the file - cannot build the control"
    exit 2
}
Set-Content -LiteralPath (Join-Path $ctlDir $ctlName) -Value $src -Encoding Ascii

$out = Invoke-SD @("BASIC $ctlFile $ctlName")
if (-not (Test-Path -LiteralPath (Join-Path ($ctlDir + '.OUT') $ctlName))) {
    Write-Output '  --- SD said: ---'; Write-Output $out
    Write-Output "  BASIC $ctlFile $ctlName produced no object - cannot build the control"
    exit 2
}

$out = Invoke-SD @("CATALOG $ctlFile `$$ctlName")
Note "SDSYS: `$$ctlName added to global catalogue" $true ($out -match 'added to global catalogue')
Note "SDSYS: gcat gained `$$ctlName"               $true (Test-Path -LiteralPath (Join-Path $gcat ('$' + $ctlName)))
if (-not (Test-Path -LiteralPath (Join-Path $gcat ('$' + $ctlName)))) {
    Write-Output '  --- SD said: ---'; Write-Output $out
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 2. Creating a PROGRAMMER account ======================================'

$inRegister = Test-Path -LiteralPath (Join-Path $sdsys ('ACCOUNTS\' + $Account.ToUpper()))

# A LEFTOVER WINDOWS ACCOUNT WITH NO SD REGISTER ENTRY IS OUR OWN DEBRIS, and
# clearing it keeps this a single command.  -Keep leaves the Windows account and
# the sdu_ group behind, and those are OS objects that a cycle does NOT remove -
# while cycle.ps1 deletes the whole data tree, so the ACCOUNTS record DOES go.
# That combination is unambiguous: our exact test name, present in Windows,
# absent from the register.  Anything else is left alone and reported.
if ((Get-LocalUser -Name $Account -ErrorAction SilentlyContinue) -and -not $inRegister) {
    Write-Output ("  clearing " + $Account + " left by an earlier -Keep run")
    # Remove-Account, NOT Remove-Made: section 1's control fixtures already
    # exist by now and this run still needs them.  See the note on the split.
    Remove-Account
}

if (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue) {
    Write-Output ("  " + $Account + " already exists - run with -Cleanup first")
    exit 2
}
if ($inRegister) {
    Write-Output ("  " + $Account.ToUpper() + " is still in the ACCOUNTS register from an earlier run.")
    Write-Output ("  CREATE.ACCOUNT would refuse it.  Use a fresh name, e.g.:")
    Write-Output ("      " + $PSCommandPath + " -Account sdcatg2")
    exit 2
}

Add-Type -AssemblyName System.Web
$pw  = [System.Web.Security.Membership]::GeneratePassword(24, 6)
$out = Invoke-SD @(('CREATE.ACCOUNT USER ' + $Account + ' PROGRAMMER'), $pw, $pw)
if (-not (Test-Path -LiteralPath $acctDir)) {
    Write-Output '  --- SD said: ---'; Write-Output $out
    Write-Output '  CREATE.ACCOUNT produced no account directory'
    exit 2
}
Write-Output ("  created " + $Account + " (PROGRAMMER)")

# Seed and compile the programs inside the account, so the refusals below fail
# on the privilege test and not on a missing object.  TWO of them, for the
# reason given at the local-catalogue check in section 5.
Set-Content -LiteralPath (Join-Path $acctDir ('BP\' + $userName))  -Value $src -Encoding Ascii
Set-Content -LiteralPath (Join-Path $acctDir ('BP\' + $localName)) -Value $src -Encoding Ascii
$acct = $Account.ToUpper()
$out  = Invoke-SD @("LOGTO $acct", "BASIC BP $userName", "BASIC BP $localName")
Note 'account: BP.OUT gained the object' $true (Test-Path -LiteralPath (Join-Path $acctDir ('BP.OUT\' + $userName)))
Note 'account: BP.OUT gained the second' $true (Test-Path -LiteralPath (Join-Path $acctDir ('BP.OUT\' + $localName)))

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 3. The account is NOT an administrator ================================'

# Stated as a check rather than assumed, because every refusal below is only
# meaningful if this holds.
#
# THE PROBE IS THE *OLD* GATE, ON PURPOSE - CATALOG's GLOBAL keyword, which has
# tested K$ADMINISTRATOR since 13 Aug 2026 and is NOT the code under test here.
# So this establishes "the session is unprivileged" without asking the new code
# to vouch for itself.
#
# IT WAS CREATE.ACCOUNT UNTIL 18 Aug 2026, AND THAT WAS WRONG - it FAILED on the
# 11:27:32 install and the fix was fine.  CREATE.ACCOUNT is one of the ten verbs
# only an ADMINISTRATOR account's VOC carries, so a PROGRAMMER account has no
# such verb: SD answered "not a known verb", the match found no privilege
# message, and the check reported the session as PRIVILEGED when it was not.
# A probe has to be a command the account actually holds.
$out = Invoke-SD @("LOGTO $acct", "CATALOG BP $userName GLOBAL")
Note 'account: refused by the pre-existing GLOBAL gate' $true ($out -match 'administrator privileges')

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 4. THE FIX: global catalogue work is refused ==========================='

$out = Invoke-SD @("LOGTO $acct", "CATALOG BP `$$userName")
Note 'CATALOG BP $SDGATE2 refused'      $true ($out -match 'administrator privileges')
Note 'and gcat did NOT gain $SDGATE2'   $false (Test-Path -LiteralPath (Join-Path $gcat ('$' + $userName)))

# The one that matters most: deleting $LOGIN from gcat stops the whole machine
# signing in, and DELCAT tested nothing at all before.
$out = Invoke-SD @("LOGTO $acct", 'DELETE.CATALOG $LOGIN')
Note 'DELETE.CATALOG $LOGIN refused'    $true ($out -match 'administrator privileges')
Note '$LOGIN still in gcat'             $true (Test-Path -LiteralPath $loginPath)
Note '$LOGIN unchanged in size'         $loginBefore ((Get-Item -LiteralPath $loginPath -ErrorAction SilentlyContinue).Length)

# The keyword route, which was already gated in CATALOG and not at all in DELCAT.
$out = Invoke-SD @("LOGTO $acct", "DELETE.CATALOG $ctlName GLOBAL")
Note "DELETE.CATALOG $ctlName GLOBAL refused" $true ($out -match 'administrator privileges')
Note "and `$$ctlName survives in gcat"        $true (Test-Path -LiteralPath (Join-Path $gcat ('$' + $ctlName)))

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 5. AND NOTHING ELSE MOVED: local and private still work ==============='

# The owner asked for this explicitly: a programmer must keep cataloguing in
# any account they can LOGTO into.  Private is the default mode and writes the
# account's own cat; LOCAL writes the account's own VOC.  Neither touches gcat.
$out = Invoke-SD @("LOGTO $acct", "CATALOG BP $userName")
Note 'CATALOG BP SDGATE2 (private) accepted' $true ($out -match 'added to private catalogue')
Note 'account cat gained SDGATE2'            $true (Test-Path -LiteralPath (Join-Path $acctDir ('cat\' + $userName)))

# A DIFFERENT PROGRAM FOR THE LOCAL CATALOGUE, AND THAT IS NOT TIDINESS - IT IS
# WHAT STOPS THIS SCRIPT HANGING.  Cataloguing the SAME name locally after
# privately makes CATALOG's check.private (CATALOG:463) find the private entry
# and ask "Program is also in private catalogue. Remove?" inside an unbounded
# "loop ... until yn = 'Y' or yn = 'N' repeat".  Driving SD down a pipe there is
# fatal: on the 11:27:32 install the prompt swallowed the remaining commands as
# answers, neither was Y or N, and the run stopped dead at this line - no
# sections 6 or 7, no summary, no exit code.  Two names means neither
# cross-catalogue check ever fires.  NO.QUERY would also silence it, but it
# silences by DELETING the other entry, which is not what this is testing.
$out = Invoke-SD @("LOGTO $acct", "CATALOG BP $localName LOCAL", "CT VOC $localName")
Note 'CATALOG BP SDGATE3 LOCAL accepted'  $true ($out -match 'added to local catalogue')
Note "account VOC holds $localName"       $false ($out -match ("'" + $localName + "' not found"))

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 6. The file layer agrees: gcat is not writable by sdusers ============='

# THE SECOND HALF OF THE PAIR (secure-gcat.ps1).  The BASIC gate above protects
# CATALOG and DELCAT; this protects the directory from anything else, including
# code not yet written and a user with a desktop.  Read from icacls rather than
# Get-Acl because the inherited marker (I) is what says whether /inheritance:r
# actually ran - the exact signature the broken $CRED install left behind on
# 17 Aug 2026, and the reason verify-credacl.ps1 checks the same thing.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'

# BOTH PATHS.  GPL.BP.OUT holds the objects gcat is loaded from, so a lock on
# gcat alone leaves a slower route to the same place.  It was measured still
# inherited on the 11:27:32 install, after gcat locked correctly - which is why
# it is checked here and not assumed to follow.
foreach ($locked in @($gcat, (Join-Path $sdsys 'GPL.BP.OUT'))) {
    $leaf = Split-Path $locked -Leaf
    $acl = & icacls.exe $locked 2>&1
    $aclText = ($acl | Out-String)
    Write-Output $aclText

    # Inherited entries mean the lock did not run at all: the data tree's
    # sdusers:(OI)(CI)(M) would be sitting there under a step that reported
    # success - the exact shape of the $CRED failure of 17 Aug 2026.
    Note "$leaf DACL has no inherited entries" $false ($aclText -match '\(I\)')

    # sdusers must be present - sessions execute out of here - and must be RX.
    Note "$leaf grants sdusers (RX)"  $true  ($aclText -match 'sdusers:\(OI\)\(CI\)\(RX\)')
    Note "$leaf grants sdusers no M/F/W" $false ($aclText -match 'sdusers:\(.*\((M|F|W)\)')
}
$ErrorActionPreference = $prevEap

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 7. An administrator can still DELETE globally (the second control) ===='

$out = Invoke-SD @("DELETE.CATALOG `$$ctlName")
Note "SDSYS: `$$ctlName deleted from the global catalogue" $true ($out -match 'deleted from the global catalogue')
Note "SDSYS: gcat lost `$$ctlName"                         $false (Test-Path -LiteralPath (Join-Path $gcat ('$' + $ctlName)))

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== Summary =============================================================='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
Write-Output ("  {0} of {1} checks passed" -f $passed, $results.Count)

if (-not $Keep) {
    Write-Output ''
    Write-Output 'Cleaning up (use -Keep to leave the account for inspection)'
    Remove-Made
} else {
    Write-Output ''
    Write-Output ('Left behind for inspection: ' + $acctDir)
    Write-Output ('Remove with: ' + $PSCommandPath + ' -Cleanup -Account ' + $Account)
}

try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 } else { exit 0 }
