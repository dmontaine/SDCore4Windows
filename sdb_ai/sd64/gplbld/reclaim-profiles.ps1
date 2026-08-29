# reclaim-profiles.ps1 - remove the profiles SD had to leave behind
#
#   powershell -File reclaim-profiles.ps1            sweep (elevated)
#   powershell -File reclaim-profiles.ps1 -List      report, change nothing
#
# Exit 0 ran and nothing is pending, 1 ran and something is still pending,
# 2 could not be attempted (not elevated).  ALL THREE ARE ORDINARY: 1 is a
# state, not a fault - a hive that is still up at this boot comes down at the
# next one.
#
# PRE_RELEASE_FIXES.md 36, and this is the half of that ruling that "something
# comes back for it".
#
# WHY THERE IS ANYTHING TO COME BACK FOR.  Deleting a Windows account cannot
# delete its profile while Windows still has the profile's registry hive
# mounted - which is the ORDINARY state after somebody has signed in - because
# the hive locks a file inside the directory.  Measured 27 Aug 2026 on one
# object, before and after, with nothing between the two but a reboot:
# C:\Users\b50home refused both Remove-Item (IOException, UsrClass.dat in use)
# and Rename-Item (Access denied); the identical Remove-Item removed it
# silently afterwards.
#
# So gpl.bp/DELETE_USER keeps BOTH halves when it cannot take the directory -
# the folder and its ProfileList entry - and writes a record here naming the
# SID, the account and the directory.  This runs at every SD service start,
# which is every boot, as LocalSystem, by which time the previous boot's hives
# are down.
#
# IT READS THE RECORD, NOT ProfileList, AND THAT IS THE POINT.  Everything else
# that cleans up a profile enumerates Win32_UserProfile, which reads from
# ProfileList - so a directory whose entry has gone is invisible to all of it.
# That state is not hypothetical: C:\Users\sdapiab49, sdapiidb49 and sdapinb49
# were on this host on 28 Aug 2026 with a directory and no entry, a sweep
# predicted in advance skipped all three exactly as predicted, and they had to
# be deleted by hand.  A sweep built on ProfileList would inherit that hole.
#
# WHAT IT REFUSES TO TOUCH, AND WHY THAT LIST IS LONG.  This runs as LocalSystem
# and deletes directories named in a file.  The store's ACL (secure-reclaim.ps1)
# is the control that keeps other people out of that file; everything below is
# the backstop for the case where it is not, and each line answers a way a
# planted record could do harm:
#
#   the file name is not the SID inside it              a record was renamed
#   the SID is not a local-account SID (S-1-5-21-..)    a well-known identity
#   a live local account still holds that SID           not an orphan at all
#   the directory is not directly under the profiles    somewhere else entirely
#     root, or IS the root
#   the leaf is Default, Public, All Users, ...         a standard profile
#   a ProfileList entry exists and names a DIFFERENT    the record disagrees
#     directory                                           with Windows
#
# THERE IS NO OWNER ROW IN THAT LIST AND ITS ABSENCE IS DELIBERATE - the
# owner's ruling on PRE_RELEASE 50, 28 Aug 2026.  See Get-RefusalReason.
#
# A record that fails any of them is skipped BY NAME and left where it is, so
# the next run reports it again rather than a person having to notice a silence.
#
# BOTH HALVES OR NEITHER.  The directory goes first and the ProfileList entry
# only if the directory went - the same order and the same reason as
# DELETE_USER: the entry is the only handle anything else has.  The record is
# removed only when both are gone.
#
# NO RESTART IS ASKED FOR ANYWHERE.  Owner's ruling: the reclaim rides the next
# boot that happens anyway.

param(
    [string] $Path = '',

    # THE PROFILES ROOT, NORMALLY READ FROM THE REGISTRY.  Overridable so that
    # gplbld/test-reclaim-units.ps1 can drive the refusal table against a
    # synthetic tree, and so that a diagnosis can point this at what a machine
    # USED to have.  It grants nothing: the caller must already be elevated to
    # reach any removal, and an elevated caller can delete anything anyway.
    [string] $ProfilesRoot = '',

    # Report and change nothing.  NEEDS NO ELEVATION, because nothing it does
    # requires any: reading ProfilesDirectory, testing a path and reading a
    # file's owner are all unprivileged.  Only the sweep is gated.
    [switch] $List
)

# Continue, not Stop.  A native executable writing to stderr under Stop
# terminates the script where it stands, and icacls does exactly that when it
# has anything to say - so the cmdlets that must be caught carry
# -ErrorAction Stop individually instead.
$ErrorActionPreference = 'Continue'

$ProfileListKey = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList'

# --- saying what happened --------------------------------------------------
#
# This runs at boot with no console and nobody watching, so the log IS the
# instrument.  Write-Host rather than Write-Output on purpose: Write-Output
# inside a function joins the function's return value, and the helpers below
# return things.

$dataDir = $env:ProgramData
if ([string]::IsNullOrEmpty($dataDir)) { $dataDir = 'C:\ProgramData' }
$dataDir = Join-Path $dataDir 'SD'

$LogPath = Join-Path $dataDir 'reclaim-profiles.log'

function Log($m) {
    $line = '{0}  {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m
    Write-Host $line
    try {
        Add-Content -LiteralPath $LogPath -Value $line -Encoding ASCII -ErrorAction Stop
    } catch { }
}

# --- where things are ------------------------------------------------------

if ($Path -eq '') { $Path = Join-Path $dataDir 'profile-reclaim' }

# Rule 1 of the instrument section: the resolved inputs, not the intended ones.
Log ('reclaim-profiles: store {0}' -f $Path)
Log ('reclaim-profiles: mode  {0}' -f $(if ($List) { 'LIST (nothing will be changed)' } else { 'SWEEP' }))

# ELEVATION IS GATED ON THE SWEEP, NOT ON THE SCRIPT.  -List reads a registry
# value, tests some paths and reads some owners, none of which needs a
# privileged token - and refusing to REPORT without elevation would only teach
# people to run the destructive mode to find out what is pending.
if (-not $List) {
    $me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Log 'reclaim-profiles: NOT ELEVATED - removing a profile directory and a ProfileList entry both need an elevated token.  Nothing was attempted.  Use -List to see what is pending.'
        exit 2
    }
}

# THE PROFILES ROOT IS READ, NOT ASSUMED.  It is a REG_EXPAND_SZ and it is not
# always C:\Users; a machine that has moved its profiles would otherwise have
# every recorded path fail the "directly under the root" test and nothing would
# ever be reclaimed.
$profilesRoot = $ProfilesRoot
if ([string]::IsNullOrEmpty($profilesRoot)) {
    try {
        $profilesRoot = (Get-ItemProperty -LiteralPath $ProfileListKey -Name ProfilesDirectory -ErrorAction Stop).ProfilesDirectory
    } catch { }
}
if ([string]::IsNullOrEmpty($profilesRoot)) { $profilesRoot = Join-Path $env:SystemDrive 'Users' }
$profilesRoot = [Environment]::ExpandEnvironmentVariables($profilesRoot)

function Norm($p) {
    # A comparable form: absolute, no trailing separator.  GetFullPath throws on
    # a malformed path, which is itself an answer - the caller treats '' as
    # "cannot be compared" and refuses the record.
    if ([string]::IsNullOrEmpty($p)) { return '' }
    try { return ([System.IO.Path]::GetFullPath($p)).TrimEnd('\') } catch { return '' }
}

# ======================================================================
#   WHETHER A RECORD MAY BE ACTED ON AT ALL.
#
# Returns '' to proceed, or the reason to refuse.  PURE ON PURPOSE - every
# input is passed in and it touches neither the filesystem nor the registry -
# because this is the security boundary of the whole script and it has to be
# testable without a store, a reboot or an elevated token.
# gplbld/test-reclaim-units.ps1 lifts this function out of this file WITH THE
# PowerShell PARSER and drives the table below; there is no second copy to
# drift.  See that file for what each row is protecting against.
#
# THE STANDARD-PROFILE LIST LIVES IN HERE rather than beside the other
# constants, for the same reason: a copy in the test would be a copy that can
# go stale, and this one cannot.

function Get-RefusalReason([string]$fileName, $rec,
                           [string]$rootNorm, [string]$liveAccount,
                           [string]$entryPath) {

    $standardLeaves = @('Default', 'Default User', 'Public', 'All Users',
                        'defaultuser0', 'systemprofile', 'LocalService',
                        'NetworkService')

    # THERE IS NO OWNER CHECK, AND THAT IS THE OWNER'S RULING ON PRE_RELEASE 50
    # (28 Aug 2026), NOT AN OVERSIGHT.
    #
    # It used to refuse any record not owned by S-1-5-18 or S-1-5-32-544.  That
    # refused EVERY record DELETE_USER will ever write: a file created by an
    # elevated process is owned by THE CREATOR'S OWN SID, not by
    # BUILTIN\Administrators, and DELETE_USER runs in the session that issued
    # DELETE.ACCOUNT - an administrator's.  Measured on the 28 Aug 20:48:24
    # install: five genuine records, five refusals, nothing reclaimable on any
    # machine.  The producer could never satisfy the consumer.
    #
    # THE CONTAINMENT IS THE STORE'S ACL, AND THIS SCRIPT ASSERTS IT ITSELF a
    # few lines above - /inheritance:r, SYSTEM and Administrators only, at every
    # boot, BEFORE a single record is read.  An ordinary user cannot create a
    # file in there to be the owner of.  The removed check was standing in for
    # that ACL and its own comment said as much.
    #
    # The owner is still read and still LOGGED against every record: rule 1 of
    # the instrument section wants what was actually seen.  It is evidence now,
    # not a gate.

    if ($null -eq $rec) { return 'could not be parsed' }

    $sid  = [string]$rec['sid']
    $dir  = [string]$rec['directory']

    # A record that has been renamed.  The file name is the SID, so this costs
    # nothing and removes a way of pointing an old record at a new subject.
    if ($fileName -ne $sid) {
        return ('the file is named {0} and the record says {1}' -f $fileName, $sid)
    }

    # A local account's SID: S-1-5-21-<3 sub-authorities>-<RID>, RID >= 1000.
    # Anything else is a built-in or a domain identity and has no business here.
    if ($sid -notmatch '^S-1-5-21-\d+-\d+-\d+-(\d+)$') {
        return 'not a local-account SID'
    }
    if ([int64]$Matches[1] -lt 1000) {
        return ('RID {0} is below 1000, so this is a built-in account' -f $Matches[1])
    }

    # NOT AN ORPHAN AT ALL.  A SID that still resolves to a live local account
    # means the record is stale or wrong, and deleting that profile would take a
    # working account's home.
    if ($liveAccount -ne '') {
        return ('{0} is still a live local account ({1}), so this is not an orphan' -f $sid, $liveAccount)
    }

    $dirNorm = Norm $dir
    if ($dirNorm -eq '') { return 'the record names no usable directory' }
    if ($rootNorm -eq '') { return 'the profiles root could not be resolved' }
    if ($dirNorm -eq $rootNorm) {
        return ('the record names the profiles root itself ({0})' -f $rootNorm)
    }
    $parentNorm = Norm ([System.IO.Path]::GetDirectoryName($dirNorm))
    if ($parentNorm -ne $rootNorm) {
        return ('{0} is not directly under the profiles root {1}' -f $dirNorm, $rootNorm)
    }
    $leaf = [System.IO.Path]::GetFileName($dirNorm)
    if ($standardLeaves -contains $leaf) {
        return ('{0} is a standard Windows profile' -f $leaf)
    }

    # AND WINDOWS' OWN OPINION, WHERE IT STILL HAS ONE.  If the entry survives,
    # the record and the entry must agree about where the directory is; if they
    # do not, one of them is about something else and neither is safe to act on.
    if ($entryPath -ne '') {
        if ((Norm $entryPath) -ne $dirNorm) {
            return ('the ProfileList entry names {0} and the record names {1}' -f (Norm $entryPath), $dirNorm)
        }
    }

    return ''
}

$rootNorm = Norm $profilesRoot
Log ('reclaim-profiles: profiles root {0}{1}' -f $rootNorm,
     $(if ($ProfilesRoot -ne '') { ' (overridden on the command line)' } else { '' }))

# --- the store's own ACL ---------------------------------------------------
#
# Re-asserted at every boot rather than trusted from install time, because the
# parent grants sdusers Modify and this directory can be created by DELETE_USER
# on a tree that predates secure-reclaim.ps1.  See that script's header for what
# the ACL is protecting against.

if (-not $List) {
    if (-not (Test-Path -LiteralPath $Path)) {
        try {
            New-Item -ItemType Directory -Path $Path -Force -ErrorAction Stop | Out-Null
            Log ('reclaim-profiles: created the store at {0}' -f $Path)
        } catch {
            Log ('reclaim-profiles: could not create {0} - {1}' -f $Path, $_.Exception.Message)
            exit 2
        }
    }
    $icaclsOut = & "$env:SystemRoot\System32\icacls.exe" $Path /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)F' `
        /grant '*S-1-5-32-544:(OI)(CI)F' 2>&1
    if ($LASTEXITCODE -ne 0) {
        Log ('reclaim-profiles: icacls on the store failed with {0} - {1}' -f $LASTEXITCODE, ($icaclsOut -join ' '))
    }
}

if (-not (Test-Path -LiteralPath $Path)) {
    Log 'reclaim-profiles: no store, so nothing has ever been recorded.  Nothing to do.'
    exit 0
}

# --- the records -----------------------------------------------------------

# NOT SilentlyContinue - PRE_RELEASE 49.  The store is granted to SYSTEM and
# Administrators only, so an unelevated -List gets UnauthorizedAccessException
# here.  Swallowing it produced an empty array, and the empty-store branch below
# then announced "nothing was left behind to reclaim" as a fact.  Two different
# states - nothing recorded, and not allowed to look - must not arrive at the
# same sentence.  REFUSE, and say which one this is.

try {
    $records = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction Stop)
} catch {
    Log ('reclaim-profiles: CANNOT READ the store at {0} - {1}' -f $Path, $_.Exception.Message)
    Log 'reclaim-profiles: this is NOT an empty store - nothing was measured and nothing was changed.  The store is granted to SYSTEM and Administrators only, so -List needs an ELEVATED shell.'
    exit 2
}

# REFUSE THE NULL CASE OUT LOUD.  An empty store is the ordinary state and it
# must not read as "swept everything" in a log somebody skims a month later.
if ($records.Count -eq 0) {
    Log 'reclaim-profiles: 0 records in the store - nothing was left behind to reclaim.  Nothing was measured and nothing was changed.'
    exit 0
}

Log ('reclaim-profiles: {0} record(s) to consider' -f $records.Count)

function Read-Record($file) {
    # key=value per line, written by gpl.bp/DELETE_USER.  Returns a hashtable;
    # missing keys come back absent and the caller refuses on them.
    $h = @{}
    $lines = @(Get-Content -LiteralPath $file.FullName -ErrorAction Stop)
    foreach ($l in $lines) {
        $i = $l.IndexOf('=')
        if ($i -gt 0) {
            $k = $l.Substring(0, $i).Trim()
            $v = $l.Substring($i + 1).Trim()
            if ($k -ne '') { $h[$k] = $v }
        }
    }
    return $h
}

function Get-OwnerSid($file) {
    # THE SID, NOT THE NAME.  "NT AUTHORITY\SYSTEM" and "BUILTIN\Administrators"
    # are both renamed on a localised Windows, and this is a security test.
    try {
        return (Get-Acl -LiteralPath $file.FullName -ErrorAction Stop).GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    } catch { return '' }
}

function Get-ProfileEntryPath($sid) {
    # The ProfileImagePath Windows currently records for this SID, expanded, or
    # '' if there is no entry.  REG_EXPAND_SZ again.
    $k = Join-Path $ProfileListKey $sid
    if (-not (Test-Path -LiteralPath $k)) { return '' }
    $p = ''
    try { $p = (Get-ItemProperty -LiteralPath $k -Name ProfileImagePath -ErrorAction Stop).ProfileImagePath } catch { }
    if ([string]::IsNullOrEmpty($p)) { return '' }
    return [Environment]::ExpandEnvironmentVariables($p)
}

$reclaimed = 0
$pending   = 0
$refused   = 0

foreach ($f in $records) {

    Log ('--- {0}' -f $f.Name)

    $ownerSid = Get-OwnerSid $f

    $rec = $null
    try { $rec = Read-Record $f } catch {
        Log ('    could not be read - {0}' -f $_.Exception.Message)
    }

    $sid  = [string]$rec['sid']
    $acct = [string]$rec['account']
    $dir  = [string]$rec['directory']

    # Rule 1 of the instrument section: what the record actually said, before
    # anything is concluded from it.
    Log ('    sid={0} account={1} directory={2} owner={3}' -f $sid, $acct, $dir, $ownerSid)

    # The two live lookups the pure test cannot make, made here and passed in.
    $liveAccount = ''
    if ($sid -ne '') {
        $live = @(Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -eq $sid })
        if ($live.Count -gt 0) { $liveAccount = $live[0].Name }
    }
    $entryPath = ''
    if ($sid -ne '') { $entryPath = Get-ProfileEntryPath $sid }

    $why = Get-RefusalReason $f.Name $rec $rootNorm $liveAccount $entryPath
    if ($why -ne '') {
        Log ('    REFUSED: {0}.  The record is left where it is, so the next run reports it again.' -f $why)
        $refused++
        continue
    }

    $dirNorm = Norm $dir

    # --- state before ------------------------------------------------------
    $key      = Join-Path $ProfileListKey $sid
    $dirWas   = Test-Path -LiteralPath $dirNorm
    $keyWas   = Test-Path -LiteralPath $key
    Log ('    before: directory {0}, ProfileList entry {1}' -f $(if ($dirWas) { 'present' } else { 'gone' }), $(if ($keyWas) { 'present' } else { 'gone' }))

    if ($List) {
        $pending++
        continue
    }

    # --- the directory first ----------------------------------------------
    if ($dirWas) {
        try {
            Remove-Item -LiteralPath $dirNorm -Recurse -Force -ErrorAction Stop
        } catch {
            Log ('    the directory would not go - {0}' -f $_.Exception.Message)
        }
    }
    $dirGone = -not (Test-Path -LiteralPath $dirNorm)

    # --- and the entry ONLY if it went -------------------------------------
    if ($dirGone -and (Test-Path -LiteralPath $key)) {
        try {
            Remove-Item -LiteralPath $key -Recurse -Force -ErrorAction Stop
        } catch {
            Log ('    the ProfileList entry would not go - {0}' -f $_.Exception.Message)
        }
    }
    $keyGone = -not (Test-Path -LiteralPath $key)

    Log ('    after:  directory {0}, ProfileList entry {1}' -f $(if ($dirGone) { 'gone' } else { 'present' }), $(if ($keyGone) { 'gone' } else { 'present' }))

    if ($dirGone -and $keyGone) {
        try {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            Log ('    reclaimed - both halves gone, record cleared')
        } catch {
            Log ('    both halves gone but the record would not clear - {0}.  The next run will find nothing to do and clear it then.' -f $_.Exception.Message)
        }
        $reclaimed++
    } else {
        Log '    still pending - the record is kept for the next start'
        $pending++
    }
}

Log ('reclaim-profiles: {0} considered, {1} reclaimed, {2} still pending, {3} refused' -f $records.Count, $reclaimed, $pending, $refused)

# A refused record is not a pending one in the arithmetic above, but it is
# certainly not finished business, so it counts towards the non-zero exit.
if (($pending + $refused) -gt 0) { exit 1 }
exit 0
