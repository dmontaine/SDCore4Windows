# remove-sdaccounts.ps1 - take away the Windows accounts SD created.
#
#   powershell -File remove-sdaccounts.ps1                    report only
#   powershell -File remove-sdaccounts.ps1 -Remove -Keep don  do it
#
# Exit 0 it ran, 2 it refused.  REPORT IS THE DEFAULT: a script that deletes
# Windows accounts should need -Remove typed at it.
#
# PRE_RELEASE_FIXES 39, owner's ruling 29 Aug 2026: "A second separate prompt,
# however deleting the windows accounts should not delete the account of the
# person doing the installation so that there is at least one remaining account
# that can log into windows."
#
# WHY IT EXISTS.  Uninstalling used to leave every account SD created - enabled,
# with its password and its group memberships - while REMOVING the sshd_config
# AllowGroups and ForceCommand that confined them.  So an account that could
# only ever reach SD over ssh became an ordinary account with a shell on the
# server, which is the thing that confinement exists to prevent, arriving by the
# far door.
#
# ---------------------------------------------------------------------------
# THE CANDIDATE SET IS sdusers MEMBERSHIP, AND THAT IS WHAT MAKES IT SAFE.
# CREATE.ACCOUNT adds every account it makes to sdusers and nothing else does,
# so the group IS the list of accounts SD created.  An account nobody made
# through SD is not in it and is never a candidate - the exclusion is
# structural rather than a name test that could be got wrong.
#
# TWO REFUSALS, AND THEY ARE THE POINT OF THE FILE:
#
#   1. -Keep NAMES THE ACCOUNT THAT MUST SURVIVE, AND IS REQUIRED WITH -Remove.
#      The owner's exclusion is "by construction", so a missing or unmatched
#      -Keep is a refusal, not a warning: it means the construction did not
#      happen and nobody would find out until the next sign-in.
#
#   2. IT REFUSES TO REMOVE THE LAST ADMINISTRATOR.  The purpose clause of the
#      ruling is "so that there is at least one remaining account that can log
#      into windows", which is a property to CHECK rather than a name to skip.
#      SD accounts are in sdsshonly and cannot sign in at the console at all,
#      but the installing user's own adopted account IS an sdusers member and
#      IS an administrator - which is exactly why the ruling exists.  So the
#      set that would remain is computed and the whole sweep stops if it is
#      empty.  That overrides the prompt's answer; it is the one case where it
#      does.
#
# WHAT IT DOES NOT DO: it does not reimplement profile removal.  A profile
# cannot be deleted while its registry hive is loaded (PRE_RELEASE 35/36), and
# reclaim-profiles.ps1 owns both halves of that - the directory and the
# ProfileList entry - reading a record rather than enumerating ProfileList.  A
# second path here would diverge from it.  This tries the supported API once
# per account and REPORTS what is left, rather than pretending.
#
# IT SHIPS.  stage.py copies it to C:\Program Files\SD and sd.iss calls it from
# the uninstaller, so it is NOT on assert-current.ps1's $neverShipped list.

[CmdletBinding()]
param(
    # Without this it reports and changes nothing.
    [switch] $Remove,

    # The account that must survive.  Required with -Remove.
    [string] $Keep = ''
)

$ErrorActionPreference = 'Stop'

function Say([string]$s) { Write-Output $s }

Say ''
Say 'remove-sdaccounts: the Windows accounts SD created'
Say '=================================================='
Say ("  mode : " + $(if ($Remove) { 'REMOVE' } else { 'report only (pass -Remove to act)' }))
Say ("  keep : " + $(if ($Keep -ne '') { $Keep } else { '(none given)' }))

# --- elevation ---------------------------------------------------------------
$elevated = ([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)
Say ("  token: " + $(if ($elevated) { 'elevated' } else { 'NOT elevated' }))
#
# 29 Aug 26 - THE ELEVATION REFUSAL IS AT THE ACT STEP, NOT HERE, AND THAT IS
# DELIBERATE.  It used to fire first, which meant the two argument refusals
# below could not be exercised at all without an elevated shell - so the only
# way to test the guards that stop this deleting the wrong accounts was to run
# it in the state where it CAN delete accounts.  A guard you can only test
# armed is a guard nobody tests.  Everything from here to "--- act ---" reads
# and decides; nothing writes.

# --- the candidate set -------------------------------------------------------
$members = @()
try {
    $members = @(Get-LocalGroupMember -Group 'sdusers' -ErrorAction Stop |
                 ForEach-Object { ($_.Name -split '\\')[-1] })
} catch {
    Say ''
    Say ("There is no sdusers group here (" + $_.Exception.Message + ").")
    Say 'SD created no accounts on this machine, so there is nothing to remove.'
    exit 0
}

Say ''
Say ("  sdusers members: " + $(if ($members.Count) { $members -join ', ' } else { '(none)' }))

if ($members.Count -eq 0) {
    Say ''
    Say 'Nothing to remove.'
    exit 0
}

# --- who is an administrator, before anything moves --------------------------
#
# READ BEFORE, NOT AFTER, and kept for the refusal below.  Local users only:
# a domain account in the group is not ours to reason about and is never a
# candidate anyway.
$admins = @()
try {
    $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
                Where-Object { $_.ObjectClass -eq 'User' } |
                ForEach-Object { ($_.Name -split '\\')[-1] })
} catch {
    Say ''
    Say ('REFUSED: the Administrators group could not be read (' + $_.Exception.Message + ').')
    Say 'Without it the "one account must remain" check cannot be made, and this'
    Say 'will not delete accounts it cannot prove are safe to delete.'
    exit 2
}
Say ("  local administrators: " + $(if ($admins.Count) { $admins -join ', ' } else { '(none)' }))

# --- classify ----------------------------------------------------------------
$toRemove = New-Object System.Collections.ArrayList
$kept     = New-Object System.Collections.ArrayList

foreach ($m in $members) {
    $user = $null
    try { $user = Get-LocalUser -Name $m -ErrorAction Stop } catch { }

    if ($null -eq $user) {
        $null = $kept.Add([pscustomobject]@{ Account = $m; Why = 'not a local user - not ours to remove' })
        continue
    }
    if ($Keep -ne '' -and $m -ieq $Keep) {
        $null = $kept.Add([pscustomobject]@{ Account = $m; Why = 'the account this uninstall must not remove' })
        continue
    }
    $null = $toRemove.Add($m)
}

# --- REFUSAL 1: -Keep is required with -Remove, and must have matched ---------
if ($Remove) {
    if ($Keep -eq '') {
        Say ''
        Say 'REFUSED: -Remove needs -Keep <account>.'
        Say 'The exclusion is meant to hold by construction, so an unnamed account to'
        Say 'keep means the construction did not happen.  Nothing was removed.'
        exit 2
    }
    if (-not ($members | Where-Object { $_ -ieq $Keep })) {
        Say ''
        Say ("REFUSED: -Keep names " + $Keep + ", which is not an sdusers member here.")
        Say 'That means it is either the wrong name or an account SD did not create,'
        Say 'and either way the exclusion cannot be shown to have worked.  Nothing was'
        Say 'removed.'
        exit 2
    }
}

# --- REFUSAL 2: never remove the last administrator --------------------------
$remainingAdmins = @($admins | Where-Object { $n = $_; -not ($toRemove | Where-Object { $_ -ieq $n }) })
Say ("  administrators that would remain: " +
     $(if ($remainingAdmins.Count) { $remainingAdmins -join ', ' } else { 'NONE' }))

if ($toRemove.Count -gt 0 -and $remainingAdmins.Count -eq 0) {
    Say ''
    Say 'REFUSED: this would remove every local administrator.'
    Say 'The ruling this implements exists so that at least one account can still'
    Say 'sign in to Windows afterwards, and that overrides the answer given to the'
    Say 'prompt.  Nothing was removed.'
    exit 2
}

# --- report ------------------------------------------------------------------
Say ''
Say 'KEEPING:'
if ($kept.Count -eq 0) { Say '  (nothing)' }
else { $kept | ForEach-Object { Say ('  ' + $_.Account.PadRight(20) + $_.Why) } }

Say ''
Say ('REMOVING (' + $toRemove.Count + '):')
if ($toRemove.Count -eq 0) { Say '  (nothing)' }
else { $toRemove | ForEach-Object { Say ('  ' + $_) } }

if (-not $Remove) {
    Say ''
    Say 'Report only - nothing was changed.  Pass -Remove to act.'
    exit 0
}

# --- act ---------------------------------------------------------------------
#
# THE LAST GATE, AND THE FIRST LINE THAT COULD CHANGE ANYTHING IS BELOW IT.
if (-not $elevated) {
    Say ''
    Say 'REFUSED: removing a local account needs an elevated token.'
    Say 'Everything above was read-only, so the report stands - but nothing was removed.'
    exit 2
}

$done = 0
$left = New-Object System.Collections.ArrayList

foreach ($name in $toRemove) {
    Say ''
    Say ("--- " + $name)

    # The account's own group, sdu_<name> for a user account.  Read the SID
    # before the user goes, for the profile step below.
    $sid = $null
    try { $sid = (Get-LocalUser -Name $name -ErrorAction Stop).SID.Value } catch { }

    foreach ($g in @(('sdu_' + $name), ('sdg_' + $name))) {
        if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) {
            try {
                Remove-LocalGroup -Name $g -ErrorAction Stop
                Say ("    group  $g removed")
            } catch {
                Say ("    group  $g NOT removed: " + $_.Exception.Message)
            }
        }
    }

    try {
        Remove-LocalUser -Name $name -ErrorAction Stop
        Say '    user   removed'
        $done++
    } catch {
        Say ('    user   NOT removed: ' + $_.Exception.Message)
        $null = $left.Add($name)
        continue
    }

    # ONE ATTEMPT THROUGH THE SUPPORTED API, AND THE TRUTH EITHER WAY.  This is
    # not a reimplementation of reclaim-profiles.ps1 - it is the ordinary case,
    # and a profile whose hive is still loaded is REPORTED rather than forced.
    if ($null -ne $sid) {
        $prof = $null
        try { $prof = Get-CimInstance Win32_UserProfile -Filter ("SID='" + $sid + "'") -ErrorAction Stop } catch { }
        if ($null -eq $prof) {
            Say '    profile none recorded'
        } else {
            $path = $prof.LocalPath
            try {
                Remove-CimInstance -InputObject $prof -ErrorAction Stop
                Say ("    profile removed: " + $path)
            } catch {
                Say ("    profile LEFT BEHIND: " + $path)
                Say '            Windows will not remove a profile whose registry hive is still'
                Say '            loaded.  It goes at the next restart, or by hand.'
            }
        }
    }
}

Say ''
Say ('remove-sdaccounts: removed ' + $done + ' of ' + $toRemove.Count + ' account(s); kept ' + $kept.Count + '.')
if ($left.Count -gt 0) {
    Say ('  still present: ' + ($left -join ', '))
}
exit 0
