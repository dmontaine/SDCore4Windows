# sync-route-groups.ps1 - create the two groups that decide which REMOTE route
# an SD account may use, and seed sdssh so an existing install does not lose ssh.
#
#   powershell -File sync-route-groups.ps1            create and seed
#   powershell -File sync-route-groups.ps1 -Check     print what it would do
#
# Exit 0 success, 1 failure.  Prints what it did either way.
#
# THE TWO ROUTES, AND THERE IS NO THIRD.  Owner's decision, 21 Aug 2026: an SD
# account reaches the machine over ssh, through an API client, or not at all.
# The console and Remote Desktop belong to administrators, and RDPACCOUNT - the
# keyword that used to lift that - is gone, because sdsshonly carries BOTH
# SeDenyInteractiveLogonRight and SeDenyRemoteInteractiveLogonRight, so lifting
# the Remote Desktop denial lifted the console denial with it.
#
#   sdssh    sshd's AllowGroups names this          (allow-ssh-groups.ps1)
#   sdapi    APISRVR tests this after the SCRAM proof succeeds
#
# NEITHER GROUP CARRIES A WINDOWS RIGHT.  They are read - by sshd and by SD -
# rather than enforced by LSA, which is what makes them safe to create here
# without the care deny-logon.ps1 needs.
#
# WHY CREATION AND SEEDING ARE ONE SCRIPT, and not "net localgroup" in [Run]
# beside sdsshonly.  THE SEEDING TRIGGER IS "DID THIS RUN CREATE IT", and that
# question can only be answered by whatever did the creating.  Split them and
# the installer would create the group in [Run], find it already present here,
# decline to seed, and hand sshd an EMPTY AllowGroups target - which locks out
# every account on an existing installation at the moment sshd is restarted.
#
# WHY SEED FROM sdusers.  Until this change sshd allowed sdusers, so "every
# member of sdusers" IS the set that could ssh in a moment ago.  Copying it
# forward makes the change invisible to a working deployment, which is the
# whole point: the new group exists to make ssh WITHDRAWABLE, not to withdraw
# it from anybody.
#
# AND WHY sdapi IS NEVER SEEDED.  Owner's decision, 21 Aug 2026: the API is off
# for an account until an administrator says otherwise.  APIPORT is already off
# by default (gplsrc/config.h), so an empty sdapi takes nothing away from a
# deployment that works today; and an API session runs as LocalSystem - measured
# 20 Aug 2026, gplbld/verify-apiadmin.ps1 - so until the containment gate lands,
# every account that may use the API may rewrite $cred.  An empty group is the
# safe starting point and one MODIFY.ACCOUNT ... API undoes it per account.

param([switch]$Check)

$ErrorActionPreference = 'Stop'

$SshGroup    = 'sdssh'
$ApiGroup    = 'sdapi'
$SeedFrom    = 'sdusers'
$SshComment  = 'SD accounts that may sign in over ssh'
$ApiComment  = 'SD accounts that may use the API'

$failed = $false

function Say($msg) { Write-Output ("sync-route-groups: " + $msg) }

# Returns $true if the group had to be created, $false if it was already there.
# Throws on a real failure.
function Ensure-Group([string]$name, [string]$comment) {
    $g = Get-LocalGroup -Name $name -ErrorAction SilentlyContinue
    if ($null -ne $g) {
        Say "$name is already there"
        return $false
    }
    if ($Check) {
        Say "would create $name"
        return $true
    }
    $null = New-LocalGroup -Name $name -Description $comment
    Say "created $name"
    return $true
}

# The member names of a group, as bare names with any DOMAIN\ or MACHINE\
# prefix stripped.  Same normalisation !os_group's LISTMEM does, and for the
# same reason: a name that comes out here has to go straight back in below.
#
# AN ORPHANED SID IS SKIPPED, NOT FATAL.  Get-LocalGroupMember returns members
# whose account has been deleted as raw SIDs, and on some Windows builds it
# throws rather than returning them.  Neither is a reason to abandon the seed.
function Get-Members([string]$name) {
    $out = New-Object System.Collections.ArrayList
    try {
        $ms = Get-LocalGroupMember -Group $name -ErrorAction Stop
    } catch {
        Say "cannot read the members of $name - $($_.Exception.Message)"
        return $null
    }
    foreach ($m in $ms) {
        $n = ($m.Name -split '\\')[-1]
        if ($n -match '^S-1-') { continue }
        if ($n -ne '') { $null = $out.Add($n) }
    }
    return $out.ToArray()
}

try {
    $sshIsNew = Ensure-Group $SshGroup $SshComment
    $null     = Ensure-Group $ApiGroup $ApiComment

    if (-not $sshIsNew) {
        Say "$SshGroup already existed - not seeding, its membership is whatever an administrator left"
    } else {
        $members = Get-Members $SeedFrom
        if ($null -eq $members) {
            # THIS IS THE ONE FAILURE WORTH SHOUTING ABOUT.  A group that exists
            # and is empty is what sshd will enforce, so a silent failure here
            # is a lockout that shows up at the next connection and not before.
            Say "COULD NOT SEED $SshGroup FROM $SeedFrom - it is EMPTY, and sshd allows only its members."
            Say "Add the accounts that should reach this machine over ssh:  net localgroup $SshGroup <name> /add"
            $failed = $true
        } elseif ($members.Count -eq 0) {
            Say "$SeedFrom has no members - $SshGroup left empty, which is correct on a first install"
        } else {
            foreach ($m in $members) {
                if ($Check) { Say "would add $m to $SshGroup"; continue }
                try {
                    Add-LocalGroupMember -Group $SshGroup -Member $m -ErrorAction Stop
                    Say "added $m to $SshGroup"
                } catch {
                    # Already a member is not a failure; anything else is.
                    if ($_.Exception.Message -match 'already a member') {
                        Say "$m is already in $SshGroup"
                    } else {
                        Say "FAILED to add $m to $SshGroup - $($_.Exception.Message)"
                        $failed = $true
                    }
                }
            }
        }
    }
} catch {
    Say "FAILED - $($_.Exception.Message)"
    $failed = $true
}

if ($failed) { exit 1 }
exit 0
