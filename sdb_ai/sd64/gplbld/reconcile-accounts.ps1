# reconcile-accounts.ps1 - remove the register records whose Windows account
# has gone, and the account directory with them
#
#   powershell -File reconcile-accounts.ps1            sweep (elevated)
#   powershell -File reconcile-accounts.ps1 -List      report, change nothing
#
# Exit 0 ran and the register is clean, 1 ran and something is still there
# (refused, or it would not go), 2 could not be attempted.
#
# PRE_RELEASE_FIXES.md 93 and 65, which are one defect in two files.
#
# WHAT IS WRONG.  @SDSYS/ACCOUNTS is the account register and @SDSYS/OS.USERS
# is the shell-access list, and neither is ever reconciled against Windows.  A
# Windows account can be removed from OUTSIDE SD - net user /delete, an AD
# removal, a decommission script - and nothing in SD is consulted, so the
# record outlives the account.  Measured 1 Sep 2026 immediately after a GREEN
# 41-step suite: 14 of the 15 records for that run named an account that was
# gone.  LIST ACCOUNTS and LIST OS.USERS then answer wrongly, which
# PROJECT_STATUS.md 5.23 makes a blocking defect, and CREATEA:762 refuses to
# recreate the name with 6002 "Account already exists" - true of the record and
# false of the world.
#
# THE RULING IS ON THE FILE, NOT ON ITS READERS.  Owner, 1 Sep 2026: "the
# ACCOUNTS directory should contain no deleted accounts - more than just the
# query, there are lots of ways to read that file and there should be NO
# invalid records in it."  So this is not a reconcile-on-read, not a verb
# somebody has to remember, and not a truer message at one caller: the register
# is the inventory and an inventory with invalid rows is wrong however it is
# read.  SD cannot PREVENT the state, so it must DETECT and REMOVE it.
#
# AND THE DIRECTORY GOES WITH THE RECORD.  Owner, same day: "if a user is
# deleted their directory should be deleted too - if the admin wants to keep
# the data then the accounts should be suspended, not deleted."  The
# keep-the-data path is real and is not a suggestion invented here -
# MODIFYA:916 records that SUSPENDED withdraws nothing on Windows, so
# modify.account <name> suspended needs no access keyword and refuses nothing.
#
# WHY IT LIVES HERE, BESIDE reclaim-profiles.ps1.  Same shape, same reason,
# same place: an external condition SD cannot prevent, swept at service start,
# recorded rather than done silently.  This runs BEFORE "sd -start", so the
# register is not open when its records are removed, and it runs as LocalSystem,
# which is what reaches an account directory whose ACL is sdu_<name> only.
#
# ======================================================================
#   THE THREE THINGS THAT MAKE THIS SAFE
# ======================================================================
#
# 1. AN ACCOUNT WITH NO WINDOWS USER IS NOT A STALE ACCOUNT, AND THE REGISTER
#    SAYS SO ITSELF.  CREATE.ACCOUNT has three types - USER, GROUP and OTHER -
#    and only USER has a Windows login at all (CREATEA:1042, and grant.os.access
#    at :1171 returns early for the other two).  A naive "is there a Windows
#    account of this name" test therefore marks every GROUP and OTHER account
#    dead, and SDSYS with them.  PRE_RELEASE 93 names SDSYS because the check
#    written for that entry did exactly this on its first run.
#
#    SO THE TYPE IS READ, NOT GUESSED.  ACC$GROUP (field 3) is "sdu_<login>"
#    for a USER account and the group's own name otherwise, so it both
#    identifies the type AND carries the Windows login this record is about.
#    SDSYS's record says "sdsys" and is exempt by that rule rather than by its
#    name - the name is checked too, as a second row, because the entry names
#    it and a belt is cheap.
#
# 2. "I COULD NOT TELL" IS NOT "NO".  This is PRE_RELEASE 96's defect, and a
#    sweep that deletes on it is the expensive version: a name-service failure
#    would delete the whole register.  Every lookup here reports THREE states -
#    resolved, definitely absent, could not tell - and only the middle one is
#    acted on.  There is a control as well as a per-record test: the local
#    account enumeration must succeed and be non-empty before any verdict is
#    believed, because a machine with zero local accounts does not exist and an
#    empty answer is a broken instrument rather than an empty register.
#
# 3. BOTH HALVES OR NEITHER, AND THE DIRECTORY FIRST.  reclaim-profiles.ps1's
#    order and reason, unchanged: the record is the only handle anything else
#    has on the directory, so removing it first would strand a directory nobody
#    can find again.  A record whose directory would not go is kept and
#    reported, and the next start tries again.
#
# WHAT IT REFUSES TO TOUCH.  This deletes directories as LocalSystem from paths
# named in a file, so the same backstop reasoning as reclaim-profiles applies -
# the file's ACL is the containment, and this list is what stands behind it:
#
#   the lookup did not complete                a name service that is down
#   the record id is an escaped file name      %E/%G/%L, cannot be decoded here
#   ACC$GROUP does not begin sdu_              GROUP, OTHER, SDSYS: no login
#   the account is named sdsys                 the same, said by name
#   the Windows account still resolves         not stale at all
#   the directory is not <root>\<record id>    a record pointing somewhere else
#   the directory IS the account root          or the root itself
#
# A record that fails any of them is skipped BY NAME and left where it is, so
# the next run reports it again and the consistency verifier keeps failing,
# rather than a person having to notice a silence.
#
# WHAT IT DELIBERATELY DOES NOT DO.  The sdu_<name> Windows GROUP is left
# alone.  The ruling names the record and the directory, a group is not part of
# the register, and over-deleting as LocalSystem is the worse failure - so a
# surviving group is LOGGED against the record and left for a person.
#
# START-HISTORY:
# 03 Sep 26 Windows port - written.  PRE_RELEASE_FIXES.md 93 and 65.
# END-HISTORY

param(
    # The data tree.  Overridable so the units test and a diagnosis can point
    # this at a synthetic tree; it grants nothing, because the caller must
    # already be elevated to reach any removal.
    [string] $DataDir = '',

    # The account container, normally CONFIG('USRDIR') read from sd.conf.
    # Overridable for the same reason and read for the reason reclaim-profiles
    # reads ProfilesDirectory: it is a setting, not a constant, and assuming it
    # would refuse every record on a machine that has moved its accounts.
    [string] $AccountsRoot = '',

    # Report and change nothing.  NEEDS NO ELEVATION: both register files grant
    # sdusers ReadAndExecute, so a member can see what is pending without
    # having to run the destructive mode to find out.
    [switch] $List
)

# Continue, not Stop.  A native executable writing to stderr under Stop
# terminates the script where it stands; the cmdlets that must be caught carry
# -ErrorAction Stop individually instead.
$ErrorActionPreference = 'Continue'

# --- saying what happened --------------------------------------------------
#
# This runs at boot with no console and nobody watching, so the log IS the
# instrument.  Write-Host rather than Write-Output on purpose: Write-Output
# inside a function joins the function's return value, and the helpers below
# return things.

$progData = $env:ProgramData
if ([string]::IsNullOrEmpty($progData)) { $progData = 'C:\ProgramData' }

if ($DataDir -eq '') { $DataDir = Join-Path $progData 'SD' }

$LogPath = Join-Path $DataDir 'reconcile-accounts.log'

function Log($m) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Write-Host $line
    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding ASCII -ErrorAction Stop
    } catch { }
}

function Norm($p) {
    # A comparable form: absolute, no trailing separator.  GetFullPath throws on
    # a malformed path, which is itself an answer - the caller treats '' as
    # "cannot be compared" and refuses the record.
    if ([string]::IsNullOrEmpty($p)) { return '' }
    try { return ([System.IO.Path]::GetFullPath($p)).TrimEnd('\') } catch { return '' }
}

# ======================================================================
#   WHICH WINDOWS LOGIN, IF ANY, A REGISTER RECORD IS ABOUT.
#
# CREATEA:1042 writes "sdu_<login>" into ACC$GROUP for a USER account and the
# group's own name for a GROUP one; the OTHER arm assigns neither.  So this
# both identifies the account TYPE and carries the login, and '' means "this
# account correctly has no Windows user" rather than "the field was empty".
#
# IT IS A FUNCTION SO THAT IT CAN BE TESTED.  Inline in the loop it would be a
# regex nobody drives, in the one place where reading it wrongly deletes an
# account directory.
# ======================================================================

function Get-RecordLogin([string]$group) {
    if ([string]::IsNullOrEmpty($group)) { return '' }
    if ($group -match '^(?i)sdu_(.+)$') { return $Matches[1].Trim() }
    return ''
}

# ======================================================================
#   WHETHER A RECORD MAY BE ACTED ON AT ALL.
#
# FOUR ANSWERS, AND TWO OF THEM ARE THE HEALTHY ONES.  The first version of
# this returned '' or a refusal, and a clean register then reported "2 refused"
# and exited 1 - every valid record counted as a fault, which is the shape
# CLAUDE.md's instrument rules exist to catch, arrived at by an author who had
# just quoted them.  A live account is the ORDINARY state of a correct record,
# not a refusal to act on a bad one:
#
#   ''             act: the record is stale and may be removed
#   'valid: ...'   the Windows account resolves, so the record is correct
#   'exempt: ...'  this account correctly has no Windows account at all
#   anything else  REFUSE, and it counts towards a non-zero exit
#
# PURE ON PURPOSE - every
# input is passed in and it touches neither the filesystem nor Windows -
# because this is the security boundary of the whole script and it has to be
# testable without a register, an account or an elevated token.
# gplbld/test-reconcile-units.ps1 lifts this function out of this file WITH THE
# PowerShell PARSER and drives the table above; there is no second copy to
# drift.  The same technique, and the same reason, as reclaim-profiles.ps1's
# Get-RefusalReason.
#
#   $kind         'accounts' or 'os.users'
#   $recordId     the file name, which is the account name or the login
#   $group        ACC$GROUP as read; '' for an os.users record
#   $dir          ACC$PATH as read; '' for an os.users record
#   $rootNorm     the account container, normalised, or '' if unresolvable
#   $winUser      the Windows login this record is about; '' if it has none
#   $liveAccount  how the login resolved, or '' if it did not
#   $lookupOk     $false if the lookup could not complete - see point 2 above

function Get-ReconcileRefusal([string]$kind, [string]$recordId,
                              [string]$group, [string]$dir,
                              [string]$rootNorm, [string]$winUser,
                              [string]$liveAccount, [bool]$lookupOk) {

    if ($recordId -eq '') { return 'the record has no id' }

    # AN ESCAPED FILE NAME.  SD escapes a record id that is not a legal file
    # name as %E, %G, %L and so on (PROJECT_STATUS 5.20, PRE_RELEASE 128).
    # Decoding one here would be a second implementation of that mapping, and
    # a wrong one deletes the wrong account.
    if ($recordId.StartsWith('%')) {
        return ('{0} is an escaped record id and this does not decode them' -f $recordId)
    }

    # THE LOOKUP FIRST, BEFORE ANYTHING CONCLUDES FROM IT.  PRE_RELEASE 96: a
    # predicate that answers "no" and "I could not tell" with the same value is
    # the defect, and here the same value would mean deleting the register.
    if (-not $lookupOk) {
        return ('the Windows account lookup for {0} did not complete, so nothing here can be called stale' -f $recordId)
    }

    if ($kind -eq 'accounts') {
        # A RECORD WITH NO PATHNAME IS CORRUPT, NOT A GROUP ACCOUNT.  CREATEA
        # sets pathname on all three arms (:392 for USER, and the GROUP and
        # OTHER arms likewise), so ACC$PATH is empty only on a truncated or
        # half-written record.  This row is BEFORE the type rows deliberately:
        # without it an empty file reads as ACC$GROUP="" and would be exempted
        # as an OTHER account, which is a corrupt record scored healthy.
        if ($dir -eq '') {
            return ('the record has no ACC$PATH, so it is truncated rather than a GROUP or OTHER account')
        }

        # SDSYS BY NAME.  PRE_RELEASE 93 names it, so it is said out loud as
        # well as covered by the rule below.
        if ($recordId.ToLower() -eq 'sdsys') {
            return 'exempt: sdsys has no Windows user by design'
        }

        # AND EVERY OTHER ACCOUNT THAT CORRECTLY HAS NONE.  CREATEA:1042 writes
        # "sdu_<login>" into ACC$GROUP for a USER account and the group name for
        # a GROUP one; OTHER gets neither arm.  So this is the account TYPE,
        # read from the record rather than guessed from the name.
        if ($winUser -eq '') {
            return ('exempt: ACC$GROUP is "{0}", so this is not a USER account and has no Windows login' -f $group)
        }
    }

    if ($winUser -eq '') { return 'the record names no Windows login' }

    # NOT STALE AT ALL, AND THAT IS THE ORDINARY STATE.
    if ($liveAccount -ne '') {
        return ('valid: {0} still resolves to a live Windows account ({1})' -f $winUser, $liveAccount)
    }

    if ($kind -ne 'accounts') { return '' }

    # --- the directory half ------------------------------------------------

    $dirNorm = Norm $dir
    if ($dirNorm -eq '') { return 'the record names no usable directory' }
    if ($rootNorm -eq '') { return 'the account root could not be resolved' }
    if ($dirNorm -eq $rootNorm) {
        return ('the record names the account root itself ({0})' -f $rootNorm)
    }

    $parentNorm = Norm ([System.IO.Path]::GetDirectoryName($dirNorm))
    if ($parentNorm -ne $rootNorm) {
        return ('{0} is not directly under the account root {1}' -f $dirNorm, $rootNorm)
    }

    # AND THE LEAF MUST BE THIS RECORD.  CREATE.ACCOUNT builds <root>\<name>,
    # so anything else is a record that has been renamed or repointed, and
    # acting on it would take another account's directory.
    $leaf = [System.IO.Path]::GetFileName($dirNorm)
    if ($leaf.ToLower() -ne $recordId.ToLower()) {
        return ('the directory leaf is {0} and the record is named {1}' -f $leaf, $recordId)
    }

    return ''
}

# ======================================================================
#   WHICH COUNTER A VERDICT MOVES.
#
# Separate from the table above, and pure, because getting THIS wrong is what
# made a clean register exit 1 - the table was right and the reading of it was
# not.  Four categories, and only 'refused' is a fault.
#
# NOTE FOR ANYONE EDITING THE CALLERS: this is deliberately if/elseif rather
# than a switch, and so are the two loops that use it.  "continue" inside a
# PowerShell switch continues the SWITCH, not the enclosing foreach, so a
# switch here would fall through into the removal code on every record.
# ======================================================================

function Get-Verdict([string]$why) {
    if ($why -eq '') { return 'act' }
    if ($why.StartsWith('valid: '))  { return 'valid' }
    if ($why.StartsWith('exempt: ')) { return 'exempt' }
    return 'refused'
}

# --- where things are ------------------------------------------------------

$sysDir      = Join-Path $DataDir 'sdsys'
$accountsDir = Join-Path $sysDir 'accounts'
$osUsersDir  = Join-Path $sysDir 'os.users'

# Rule 1 of the instrument section: the resolved inputs, not the intended ones.
Log '=========================================================='
Log ('reconcile-accounts: data tree {0}' -f $DataDir)
Log ('reconcile-accounts: mode      {0}' -f $(if ($List) { 'LIST (nothing will be changed)' } else { 'SWEEP' }))

# THE ACCOUNT ROOT IS READ FROM sd.conf, NOT ASSUMED.  USRDIR is a setting
# (config.c:352) whose compiled default is C:\ProgramData\SD\user_accounts, and
# a machine that has moved its accounts would otherwise fail the "directly
# under the root" test on every record and reclaim nothing, for ever.
$rootSource = 'the -AccountsRoot argument'
if ($AccountsRoot -eq '') {
    $rootSource = 'the compiled default (config.c:140)'
    $AccountsRoot = Join-Path $DataDir 'user_accounts'
    $conf = Join-Path $DataDir 'sd.conf'
    if (Test-Path -LiteralPath $conf) {
        try {
            $lines = @(Get-Content -LiteralPath $conf -ErrorAction Stop)
            foreach ($l in $lines) {
                $t = $l.Trim()
                if ($t.StartsWith('#')) { continue }
                if ($t -match '^(?i)USRDIR\s*=\s*(.+)$') {
                    $v = $Matches[1].Trim()
                    if ($v -ne '') {
                        $AccountsRoot = [Environment]::ExpandEnvironmentVariables($v)
                        $rootSource = ('USRDIR in {0}' -f $conf)
                    }
                }
            }
        } catch {
            Log ('reconcile-accounts: could not read {0} - {1}' -f $conf, $_.Exception.Message)
        }
    }
}
$rootNorm = Norm $AccountsRoot
Log ('reconcile-accounts: account root {0}, from {1}' -f $rootNorm, $rootSource)

# ELEVATION IS GATED ON THE SWEEP, NOT ON THE SCRIPT - reclaim-profiles.ps1's
# reasoning, and it applies here for a second reason: both register files grant
# sdusers ReadAndExecute (secure-accounts.ps1, secure-osusers.ps1), so -List
# genuinely works for an ordinary member and refusing it would only teach
# people to run the sweep to find out what is pending.
if (-not $List) {
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log 'reconcile-accounts: NOT ELEVATED - removing an account directory and a register record both need an elevated token.  Nothing was attempted.  Use -List to see what is pending.'
        exit 2
    }
}

# ======================================================================
#   THE CONTROL, BEFORE ANY VERDICT IS BELIEVED.
#
# CLAUDE.md: a test that passes because it did nothing must fail, not pass.
# The failure mode here is worse than a false pass - an enumeration that comes
# back empty because the machinery is broken would make EVERY record look
# stale - so the instrument is checked before it is used.  A Windows machine
# with zero local accounts does not exist.
# ======================================================================

$localUsers = $null
try {
    $localUsers = @(Get-LocalUser -ErrorAction Stop)
} catch {
    Log ('reconcile-accounts: CANNOT ENUMERATE LOCAL ACCOUNTS - {0}' -f $_.Exception.Message)
    Log 'reconcile-accounts: nothing was measured and nothing was changed.  Every record would have looked stale.'
    exit 2
}
if ($localUsers.Count -eq 0) {
    Log 'reconcile-accounts: the local account enumeration returned ZERO accounts, which no Windows machine has.  The lookup is broken, not the register.'
    Log 'reconcile-accounts: nothing was measured and nothing was changed.'
    exit 2
}

$localNames = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
foreach ($u in $localUsers) { [void]$localNames.Add($u.Name) }
Log ('reconcile-accounts: control - {0} local Windows account(s) enumerated' -f $localNames.Count)

# ======================================================================
#   THE LOOKUP ITSELF, WITH ITS THIRD ANSWER.
#
# Returns @{ live = '<how it resolved>' ; ok = $true/$false }.  "ok" is false
# ONLY when the question could not be answered, which is the state PRE_RELEASE
# 96 is about; an account that is genuinely gone comes back live='' with
# ok=$true.  The local set answers most of it; the SID translation is there
# because the installer adopts whatever account installed SD, and on a domain
# member that is not a local account.
# ======================================================================

function Resolve-WindowsAccount([string]$name, $localSet) {
    if ($name -eq '') { return @{ live = ''; ok = $true } }

    if ($localSet.Contains($name)) { return @{ live = ('local account ' + $name); ok = $true } }

    try {
        $sid = ([System.Security.Principal.NTAccount]$name).Translate([System.Security.Principal.SecurityIdentifier])
        return @{ live = ('resolves to ' + $sid.Value); ok = $true }
    } catch [System.Security.Principal.IdentityNotMappedException] {
        # THE ONE ANSWER THAT MEANS GONE.  Windows was asked and said no such
        # identity, which is different from Windows not answering.
        return @{ live = ''; ok = $true }
    } catch {
        return @{ live = ''; ok = $false }
    }
}

# --- the records -----------------------------------------------------------
#
# NOT SilentlyContinue, and PRE_RELEASE 49 is the reason: an unreadable
# directory and an empty one must not arrive at the same sentence.
#
# ***IT RETURNS A HASHTABLE AND NOT AN ARRAY, AND THAT IS THE WHOLE POINT.***
# Measured 3 Sep 2026 on the first run the SERVICE made, which is the first run
# where os.users was empty: a PowerShell function that returns @() hands the
# caller $null, and one that returns a single-element array hands it a bare
# FileInfo.  So "an empty register" and "a register I could not read" arrived
# at the caller as the same value, the caller counted the healthy case as
# unreadable, and the service logged "register reconcile: exited with 1" on a
# perfectly good machine with NOT ONE LINE saying why.
#
# That is exactly the shape the comment above cites PRE_RELEASE 49 for, reached
# through PowerShell's return semantics rather than through -ErrorAction, and
# the fix is to stop returning a collection at all: `ok` says whether the
# question was answered, `items` is only meaningful when it was.

function Get-Records([string]$dir) {
    if (-not (Test-Path -LiteralPath $dir)) {
        return @{ ok = $true; absent = $true; why = ''; items = @() }
    }
    try {
        $found = @(Get-ChildItem -LiteralPath $dir -File -ErrorAction Stop)
        return @{ ok = $true; absent = $false; why = ''; items = $found }
    } catch {
        return @{ ok = $false; absent = $false; why = $_.Exception.Message; items = @() }
    }
}

$considered = 0
$cleared    = 0
$valid      = 0
$exempt     = 0
$refused    = 0
$stuck      = 0
$unreadable = 0

# ======================================================================
#   ACCOUNTS - the record and the directory
# ======================================================================

Log '--- @SDSYS/ACCOUNTS'
$accRead = Get-Records $accountsDir
$accRecords = @($accRead.items)
if (-not $accRead.ok) {
    Log ('reconcile-accounts: CANNOT READ ACCOUNTS at {0} - {1}' -f $accountsDir, $accRead.why)
    Log 'reconcile-accounts: this is NOT an empty register - nothing was measured there.'
    $unreadable++
} elseif ($accRead.absent) {
    Log ('reconcile-accounts: no ACCOUNTS file at {0}.  There is always one on an installed tree, so this is news.' -f $accountsDir)
    $unreadable++
} elseif ($accRecords.Count -eq 0) {
    # REFUSE THE NULL CASE OUT LOUD.  An empty register is not the ordinary
    # state - SDSYS's own record is always there - so an empty one is news.
    Log 'reconcile-accounts: 0 records in ACCOUNTS.  That is not the ordinary state: sdsys always has one.  Nothing was changed.'
    $unreadable++
} else {
    Log ('reconcile-accounts: {0} ACCOUNTS record(s) to consider' -f $accRecords.Count)

    foreach ($f in $accRecords) {
        $considered++
        Log ('--- accounts/{0}' -f $f.Name)

        $rec = @()
        try {
            $rec = @(Get-Content -LiteralPath $f.FullName -ErrorAction Stop)
        } catch {
            Log ('    could not be read - {0}.  Left where it is.' -f $_.Exception.Message)
            $refused++
            continue
        }

        # SD writes CRLF (task 7.16); Get-Content splits on the line break and
        # leaves nothing behind, but a stray CR from a hand-edited record would
        # otherwise end up inside a group name, so it is trimmed here.
        $path  = ''
        $group = ''
        if ($rec.Count -ge 1) { $path  = ([string]$rec[0]).Trim() }
        if ($rec.Count -ge 3) { $group = ([string]$rec[2]).Trim() }

        $winUser = Get-RecordLogin $group

        $look = Resolve-WindowsAccount $winUser $localNames

        # Rule 1 again: what the record actually said and what Windows actually
        # answered, before anything is concluded from either.
        Log ('    ACC$PATH={0} ACC$GROUP={1} login={2} windows={3}' -f $path, $group, `
             $(if ($winUser -eq '') { '(none)' } else { $winUser }), `
             $(if (-not $look.ok) { 'COULD NOT TELL' } elseif ($look.live -eq '') { 'ABSENT' } else { $look.live }))

        $why = Get-ReconcileRefusal 'accounts' $f.Name $group $path $rootNorm $winUser $look.live $look.ok
        $verdict = Get-Verdict $why
        if ($verdict -eq 'valid') {
            Log ('    {0}.  Nothing to do.' -f $why)
            $valid++
            continue
        }
        if ($verdict -eq 'exempt') {
            Log ('    {0}.  Left alone.' -f $why)
            $exempt++
            continue
        }
        if ($verdict -eq 'refused') {
            Log ('    REFUSED: {0}.  The record is left where it is, so the next run reports it again.' -f $why)
            $refused++
            continue
        }

        $dirNorm = Norm $path
        $dirWas  = Test-Path -LiteralPath $dirNorm
        Log ('    before: directory {0}, record present' -f $(if ($dirWas) { 'present' } else { 'gone' }))

        # THE GROUP IS REPORTED AND NOT REMOVED - see the header.
        $grpLeft = $null
        try { $grpLeft = Get-LocalGroup -Name $group -ErrorAction Stop } catch { }
        if ($null -ne $grpLeft) {
            Log ('    note: the Windows group {0} still exists.  It is not part of the register and is deliberately left for a person.' -f $group)
        }

        if ($List) { $stuck++; continue }

        # --- the directory first, and the record only if it went ------------
        if ($dirWas) {
            try {
                Remove-Item -LiteralPath $dirNorm -Recurse -Force -ErrorAction Stop
            } catch {
                Log ('    the directory would not go - {0}' -f $_.Exception.Message)
            }
        }
        $dirGone = -not (Test-Path -LiteralPath $dirNorm)

        if (-not $dirGone) {
            Log '    still pending - the record is KEPT, because the record is the only handle anything has on that directory.'
            $stuck++
            continue
        }

        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            Log '    after:  directory gone, record cleared'
            $cleared++
        } catch {
            Log ('    the directory went but the record would not clear - {0}' -f $_.Exception.Message)
            $stuck++
        }
    }
}

# ======================================================================
#   OS.USERS - the record alone.  There is no directory, and DELACC's
#   drop.os.access is the shape being copied: the record is keyed by the
#   PERSON, so it may only go where the Windows login itself is gone.
# ======================================================================

Log '--- @SDSYS/OS.USERS'
$osRead = Get-Records $osUsersDir
$osRecords = @($osRead.items)
if (-not $osRead.ok) {
    Log ('reconcile-accounts: CANNOT READ OS.USERS at {0} - {1}' -f $osUsersDir, $osRead.why)
    Log 'reconcile-accounts: this is NOT an empty list - nothing was measured there.'
    $unreadable++
} elseif ($osRead.absent) {
    # ORDINARY, AND NOT ONLY IN THEORY.  This sweep runs BEFORE "sd -start", so
    # on the very first boot of a fresh install it looks at the tree the
    # installer laid down and nothing has adopted an account yet.
    Log ('reconcile-accounts: no OS.USERS file at {0} yet - nothing to reconcile.' -f $osUsersDir)
} elseif ($osRecords.Count -eq 0) {
    Log 'reconcile-accounts: 0 records in OS.USERS.  That is an ordinary state - only ADMINISTRATOR-tier accounts get one.'
} else {
    Log ('reconcile-accounts: {0} OS.USERS record(s) to consider' -f $osRecords.Count)

    foreach ($f in $osRecords) {
        $considered++
        Log ('--- os.users/{0}' -f $f.Name)

        $look = Resolve-WindowsAccount $f.Name $localNames
        Log ('    login={0} windows={1}' -f $f.Name, `
             $(if (-not $look.ok) { 'COULD NOT TELL' } elseif ($look.live -eq '') { 'ABSENT' } else { $look.live }))

        $why = Get-ReconcileRefusal 'os.users' $f.Name '' '' $rootNorm $f.Name $look.live $look.ok
        $verdict = Get-Verdict $why
        if ($verdict -eq 'valid') {
            Log ('    {0}.  Nothing to do.' -f $why)
            $valid++
            continue
        }
        if ($verdict -eq 'exempt') {
            Log ('    {0}.  Left alone.' -f $why)
            $exempt++
            continue
        }
        if ($verdict -eq 'refused') {
            Log ('    REFUSED: {0}.  The record is left where it is, so the next run reports it again.' -f $why)
            $refused++
            continue
        }

        if ($List) { $stuck++; continue }

        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            Log '    after:  record cleared'
            $cleared++
        } catch {
            Log ('    the record would not clear - {0}' -f $_.Exception.Message)
            $stuck++
        }
    }
}

Log ('reconcile-accounts: {0} considered, {1} valid, {2} exempt, {3} cleared, {4} still there, {5} refused' -f `
     $considered, $valid, $exempt, $cleared, $stuck, $refused)

# AND SAY WHICH OF THE TWO CLEAN ENDINGS THIS WAS.  "0 refused" on a register
# nobody could read reads exactly like "0 refused" on a healthy one.
if (($stuck + $refused + $unreadable) -eq 0) {
    Log ('reconcile-accounts: the register is consistent - every record names an account that exists, or is one of the {0} that correctly has none.' -f $exempt)
}

# A refused record is not a pending one in the arithmetic above, but it is
# certainly not finished business, so it counts towards the non-zero exit.  So
# does a register half that could not be read at all: reporting 0 there would
# be the null case this script refuses everywhere else.
if (($stuck + $refused + $unreadable) -gt 0) { exit 1 }
exit 0
