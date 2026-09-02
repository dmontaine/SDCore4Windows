# restore-sshonly.ps1 - put every non-administrator SD account back into
# sdsshonly, reading the account register rather than anything local.
#
#   powershell -File restore-sshonly.ps1 -DataDir "C:\ProgramData\SD"
#   powershell -File restore-sshonly.ps1 -DataDir "C:\ProgramData\SD" -Check
#
# Exit 0 nothing to do or all repaired, 1 a repair failed, 2 the step could not
# measure and did nothing.  RUN ELEVATED - local group membership needs it.
#
# ===========================================================================
# WHY THIS EXISTS
# ===========================================================================
#
# PRE_RELEASE_FIXES 135.  AN UNINSTALL DELETES sdsshonly (sd.iss, "net
# localgroup sdsshonly /delete", without asking) AND A WINDOWS LOCAL GROUP
# TAKES ITS MEMBERSHIP WITH IT.  The reinstall creates the group again and
# deny-logon.ps1 reapplies SeDenyInteractiveLogonRight and
# SeDenyRemoteInteractiveLogonRight to it - correctly, and to a group with
# NOBODY IN IT.  So every account that was confined to ssh silently gets the
# console and Remote Desktop back.
#
# Only CREATEA ever added a member, at account-creation time, so nothing put
# them back.  The uninstaller discloses this at removal time; the reinstaller
# does not, and the box it does show says "YOUR DATA IS UNTOUCHED: your
# accounts and their passwords", which reads as a promise about access.
#
# ===========================================================================
# WHY THE REGISTER AND NOT THE sdu_ GROUPS
# ===========================================================================
#
# Owner's instruction, 2 Sep 2026, and his reason is the important half:
# "eventually we will need a utility that allows sd to be moved to a new
# computer - when that happens, everything needs to come back the way it was -
# so uninstall, reinstall is kind of a shadow of that."
#
# The sdu_<name> groups would have been cheaper and they DO survive a
# reinstall - measured on guest Test 10.  THEY DO NOT SURVIVE A MOVE.  On a new
# computer the only thing that arrives is the data tree, so a repair driven by
# anything local closes this entry and is worthless for the thing it is a
# rehearsal for.  <DataDir>\sdsys\accounts holds one record per account, named
# by the account name downcased, and it is preserved by every path that keeps
# the database.  That is the register, and it travels.
#
# ***AND THAT IS WHY THIS READS THE DIRECTORY RATHER THAN RUNNING "LIST
# ACCOUNTS" THROUGH sd -internal.***  Same source, and adopt-account.ps1
# already depends on exactly this layout, so it is not a new assumption.  It
# needs no running server, no start/stop, no two-minute timeout and no parsing
# of SD's output - four failure modes that a step running inside an installer
# does not need, and one of them (sd's handles outliving it) is written up in
# PROJECT_STATUS 6 as having cost two measurements.
#
# ===========================================================================
# THE RULE, WHICH IS NOT THE OBVIOUS ONE
# ===========================================================================
#
# CREATEA:946 - an account joins sdsshonly unless it is an ADOPT or its Windows
# user is a member of S-1-5-32-544, the local Administrators group.  SO THE
# TEST IS ADMINISTRATORS MEMBERSHIP, NOT ACC$TIER.  Reading the tier would be
# the plausible wrong answer: a tier can be changed after creation, and the
# group is what the deny rights actually key on.
#
# ADOPT IS SUBSUMED BY THE ADMINISTRATOR TEST, and that is stated rather than
# relied on silently: the installer requires elevation, so the adopted user is
# an administrator and is skipped by the same test.  If adopt ever becomes
# reachable by a non-administrator, this script would confine them and that
# would be wrong - the 15 Aug rule is that adopt changes nothing about the
# operating system account.
#
# ***IT ONLY EVER ADDS.***  Removing somebody from sdsshonly is a grant of
# console access and is nobody's business but an administrator's.  An account
# that should not be confined is left alone, and said so.
[CmdletBinding()]
param(
    [string] $DataDir = 'C:\ProgramData\SD',

    # Report what would change and change nothing.
    [switch] $Check
)

$ErrorActionPreference = 'Stop'

$Group  = 'sdsshonly'
$AdminS = 'S-1-5-32-544'

function Say($m) { Write-Output ("restore-sshonly: " + $m) }

# RULE 1 OF THE INSTRUMENT SECTION: say what this run actually was, with the
# resolved inputs, before any verdict.
$accountsDir = Join-Path $DataDir 'sdsys\accounts'
Say ("data dir  " + $DataDir)
Say ("register  " + $accountsDir)
Say ("group     " + $Group)
Say ("mode      " + $(if ($Check) { 'CHECK - nothing will be changed' } else { 'repair' }))

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
Say ("elevated  " + $elevated)

# --- REFUSALS, BEFORE ANYTHING IS CLAIMED ----------------------------------
if (-not (Test-Path -LiteralPath $accountsDir)) {
    Say "REFUSED: the account register is not there.  Nothing was examined."
    Say "This step cannot tell 'no accounts' from 'no register', so it reports neither."
    exit 2
}

if (-not (Get-LocalGroup -Name $Group -ErrorAction SilentlyContinue)) {
    Say ("REFUSED: the group " + $Group + " does not exist, so nobody can be put in it.")
    Say "It is created by sd.iss before this step runs; if it is missing, that failed."
    exit 2
}

# The register's records ARE the account names, downcased.  Directories are
# excluded: a record is a file, and anything else here is not an account.
$records = @(Get-ChildItem -LiteralPath $accountsDir -File -Force -ErrorAction SilentlyContinue |
             ForEach-Object { $_.Name })

# ***THE NULL CASE.***  An unreadable register and an empty one look identical
# from here, and "0 accounts, nothing to do" is exactly what a broken read
# would print on its way to a green exit.  SDSYS is always there.
if ($records.Count -eq 0) {
    Say "REFUSED: the register is readable and contains NO account records."
    Say "SDSYS alone should always be present, so this is a broken read rather than"
    Say "an empty system.  Nothing was changed."
    exit 2
}

Say ("register holds " + $records.Count + " account record(s): " + (($records | Sort-Object) -join ', '))

# --- BEFORE ----------------------------------------------------------------
function Get-GroupMembers {
    $m = @()
    try {
        $m = @(Get-LocalGroupMember -Group $Group -ErrorAction Stop |
               ForEach-Object { ($_.Name -split '\\')[-1] })
    } catch {
        # An empty local group throws on some builds rather than returning
        # nothing; that is not the same as a failure to read, but this script
        # cannot tell them apart, so it says so and treats it as empty.
        Say ("note: could not enumerate " + $Group + " (" + $_.Exception.Message + ")")
    }
    return $m
}

$before = @(Get-GroupMembers)
Say ("BEFORE " + $Group + " has " + $before.Count + " member(s): " +
     $(if ($before.Count) { ($before | Sort-Object) -join ', ' } else { '(none)' }))

# --- THE WALK --------------------------------------------------------------
$added   = New-Object System.Collections.ArrayList
$failed  = New-Object System.Collections.ArrayList
$skipped = New-Object System.Collections.ArrayList

foreach ($acct in ($records | Sort-Object)) {
    $u = $acct.ToLowerInvariant()

    $user = Get-LocalUser -Name $u -ErrorAction SilentlyContinue
    if (-not $user) {
        $null = $skipped.Add($u + ' (no Windows user of that name)')
        continue
    }

    $isAdmin = $false
    try {
        $isAdmin = @(Get-LocalGroupMember -SID $AdminS -ErrorAction Stop |
                     Where-Object { ($_.Name -split '\\')[-1] -ieq $u }).Count -gt 0
    } catch {
        # Cannot answer the question the rule turns on.  Do NOT guess: guessing
        # "not an administrator" would confine an administrator, and guessing
        # the other way would leave an account unconfined and call it done.
        $null = $failed.Add($u + ' (could not read Administrators membership: ' +
                            $_.Exception.Message + ')')
        continue
    }

    if ($isAdmin) {
        $null = $skipped.Add($u + ' (local administrator - CREATEA:946 exempts these)')
        continue
    }

    if ($before -contains $u) {
        $null = $skipped.Add($u + ' (already in ' + $Group + ')')
        continue
    }

    if ($Check) {
        $null = $added.Add($u + ' (WOULD be added)')
        continue
    }

    try {
        Add-LocalGroupMember -Group $Group -Member $u -ErrorAction Stop
        $null = $added.Add($u)
    } catch {
        $null = $failed.Add($u + ' (' + $_.Exception.Message + ')')
    }
}

# --- AFTER, AND THE VERDICT ------------------------------------------------
foreach ($s in $skipped) { Say ("  skip  " + $s) }
foreach ($a in $added)   { Say ("  ADD   " + $a) }
foreach ($f in $failed)  { Say ("  FAIL  " + $f) }

$after = @(Get-GroupMembers)
Say ("AFTER  " + $Group + " has " + $after.Count + " member(s): " +
     $(if ($after.Count) { ($after | Sort-Object) -join ', ' } else { '(none)' }))

if ($failed.Count -gt 0) {
    Say ("FAILED: " + $failed.Count + " account(s) could not be put back into " + $Group + ".")
    Say "Those accounts can sign in at the console and over Remote Desktop until this"
    Say "is put right.  Re-run this script from an ELEVATED PowerShell prompt."
    exit 1
}

if ($added.Count -eq 0) {
    Say ("nothing to do - every account in the register is already correct for " + $Group + ".")
    exit 0
}

# THE LEADING '' IS LOad-BEARING AND IS NOT STYLE.  "$int + ' text'" makes
# PowerShell convert the STRING to Int32 - the left operand decides the
# operator - and it throws "Input string was not in a correct format" at the
# moment of success.  Found by the control on 2 Sep 2026: the live run took the
# "nothing to do" branch, which happens to start with a string, so the two
# branches that report work done were the two that could not run.
if ($Check) {
    Say ('' + $added.Count + " account(s) WOULD be added.  Nothing was changed (-Check).")
    exit 0
}

Say ('' + $added.Count + " account(s) restored to " + $Group + ".")
exit 0
