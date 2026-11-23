# sync-route-groups.ps1 - create the two groups that decide which REMOTE route
# an SD account may use, and seed sdssh so an existing install does not lose ssh.
#
#   powershell -ExecutionPolicy Bypass -File sync-route-groups.ps1            create and seed
#   powershell -ExecutionPolicy Bypass -File sync-route-groups.ps1 -Check     print what it would do
#   powershell -ExecutionPolicy Bypass -File sync-route-groups.ps1 -FirstInstall   create; every route group starts EMPTY (the installer, no data tree)
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

# 18 Nov 26 - four-version audit round 2 (Linux's mail 2026-11-18T0220, item 1): -FirstInstall, which sd.iss passes when
# there was no data tree before this run, makes a NEW sdssh stay EMPTY.  On a first install the [Run] step has just put the
# installing user in sdusers, so seeding from it delivered that user with ssh ON, unasked - Linux Core creates sdssh empty
# and its ATTACH turns nothing on (the owner's rule: delivered closed, the administrator opens it; the wizard's "open every
# access gate" box is how the person asks for ssh).  The seed stays for an upgrade from before the route split, which keeps
# the ssh the system already had.
#
# 22 Nov 26 - RELEASE_1.1 393 (owner, 22 Nov: "Yes, reset them, and tell linux"; Linux S.310).  -FirstInstall now EMPTIES every
# route group that was already there, not only a new sdssh.  An uninstall with nobody to answer it keeps the groups (row 369(b)),
# so deleting the data afterwards left old members in sdssh/sdapi, and a "fresh" install inherited ssh and API access it never
# granted (light verify b363, verify-accountrules).  No data tree means no SD account, so no membership can be one an
# administrator chose here.  An upgrade or a Keep reinstall finds the tree, does not pass -FirstInstall, and touches nothing.
# The installing user's own gates are applied after this (sd.iss: SyncRouteGroups before AttachInstallerAccount).  sdusers,
# sdsshonly and sdsshnokey are not route groups and are left alone: the last two only restrict.
param([switch]$Check, [switch]$FirstInstall)

$ErrorActionPreference = 'Stop'

$SshGroup    = 'sdssh'
$ApiGroup    = 'sdapi'
$SeedFrom    = 'sdusers'
$SshComment  = 'SD accounts that may sign in over ssh'
$ApiComment  = 'SD accounts that may use the API'
# 25 Oct 26 - RELEASE_1.1 171 (Linux S.65).  The two groups of the files-only SDNet login route: sdfiles lets a person log in over the API to
# files and nothing else, sdfileswrite adds the right to change them.  Created EMPTY and never seeded (core direction 1: off until an
# administrator names a person, with modify.account files-on / files-write-on).  Like sdapi they carry no Windows right; SD reads them by name.
$FilesGroup      = 'sdfiles'
$FilesWriteGroup = 'sdfileswrite'
$FilesComment      = 'SD accounts that may use the API for files only'
# New-LocalGroup caps -Description at 48 characters (RELEASE_1.1 186: the longer wording was refused and the group never made).
$FilesWriteComment = 'SD files-only API accounts that may write files'
# 25 Oct 26 - Linux ef9d594 (S.73 item 3): the third level, sdfilesadmin, lets the files-only login ADMINISTER files on this server (configure, index, create,
# delete, the file's counter).  Created EMPTY like the other two (modify.account files-admin-on names a person); it carries no Windows right.
$FilesAdminGroup   = 'sdfilesadmin'
$FilesAdminComment = 'SD files-only API accounts that are file admins'
# 13 Nov 26 - RELEASE_1.1 246 (Linux S.69 step 2, installsdcore.sh's sdaiusers): the AI gate.  A person in sdaiusers may use the AI provider the
# administrator chose, through the helper service sd-ai, which reads the membership of the caller's SID at every request.  Created EMPTY and never
# seeded (high security delivered: modify.account ai-on names a person; the installer's "open every access gate" box gives the installing user's
# account ai-on through attach-account.ps1 -OpenGates).  It carries no Windows right; the helper reads it by name.
$AiGroup   = 'sdaiusers'
$AiComment = 'SD accounts that may use the AI'

$failed = $false

function Say($msg) { Write-Output ("sync-route-groups: " + $msg) }

# Sets $script:GroupCreated: $true if the group had to be created, $false if it
# was already there.  Throws on a real failure.
#
# 13 Nov 26 - RELEASE_1.1 277.  THE ANSWER GOES IN A VARIABLE, NOT THE PIPELINE.
# This returned $true/$false after calling Say, which writes to the output
# stream, so the caller got an ARRAY (Say's line and the flag): never empty,
# always true.  `-not $sshIsNew` was therefore always false, and an existing
# sdssh was re-seeded every run - putting back members an administrator had
# taken off ssh - while Say's "already there" line was swallowed.  Now the
# function returns nothing, its lines reach the output, and the flag is read
# from $script:GroupCreated (memory ps-function-output-trap, a fourth time).
$script:GroupCreated = $false
function Ensure-Group([string]$name, [string]$comment) {
    $script:GroupCreated = $false
    $g = Get-LocalGroup -Name $name -ErrorAction SilentlyContinue
    if ($null -ne $g) {
        Say "$name is already there"
        return
    }
    if ($Check) {
        Say "would create $name"
        $script:GroupCreated = $true
        return
    }
    $null = New-LocalGroup -Name $name -Description $comment
    Say "created $name"
    $script:GroupCreated = $true
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
        Say "cannot read the members of $name - $($_.Exception.Message)" | Out-Host   # 13 Nov 26 RELEASE_1.1 277: else $null never comes back
        return $null
    }
    foreach ($m in $ms) {
        $n = ($m.Name -split '\\')[-1]
        if ($n -match '^S-1-') { continue }
        if ($n -ne '') { $null = $out.Add($n) }
    }
    return $out.ToArray()
}

# 22 Nov 26 - RELEASE_1.1 393: take every member out of a group that was already there.  Through ADSI, not Get-LocalGroupMember:
# Windows PowerShell 5.1's cmdlet throws on a group holding an ORPHANED SID (a member whose Windows account was deleted), and a
# group left by an earlier install is exactly where those are.  ADSI lists an orphan by its SID path and removes it like any
# other.  Reports each one, and refuses the null case: a group it could not read, or left non-empty, is a failure.
function Get-AdsiMemberPaths($group) {
    $paths = New-Object System.Collections.ArrayList
    foreach ($m in @($group.psbase.Invoke('Members'))) {
        $null = $paths.Add($m.GetType().InvokeMember('ADsPath', 'GetProperty', $null, $m, $null))
    }
    return ,$paths.ToArray()
}
function Clear-Group([string]$name) {
    try {
        $g = [ADSI]("WinNT://$env:COMPUTERNAME/$name,group")
        $paths = Get-AdsiMemberPaths $g
    } catch {
        Say "COULD NOT READ the members of $name to empty it - $($_.Exception.Message)"
        $script:failed = $true
        return
    }
    if ($paths.Count -eq 0) { Say "$name was already there and empty"; return }
    foreach ($p in $paths) {
        $shown = $p -replace '^WinNT://', ''
        if ($Check) { Say "would take $shown out of $name"; continue }
        try {
            $g.psbase.Invoke('Remove', $p)
            Say "took $shown out of $name (left from an earlier install)"
        } catch {
            Say "FAILED to take $shown out of $name - $($_.Exception.Message)"
            $script:failed = $true
        }
    }
    if ($Check) { return }
    try { $left = (Get-AdsiMemberPaths ([ADSI]("WinNT://$env:COMPUTERNAME/$name,group"))).Count } catch { $left = -1 }
    if ($left -ne 0) {
        Say "$name was NOT emptied: $left member(s) left (-1: it could not be read back)"
        $script:failed = $true
    }
}

try {
    $existed = @()
    Ensure-Group $SshGroup $SshComment
    $sshIsNew = $script:GroupCreated
    if (-not $script:GroupCreated) { $existed += $SshGroup }
    Ensure-Group $ApiGroup $ApiComment
    if (-not $script:GroupCreated) { $existed += $ApiGroup }
    Ensure-Group $FilesGroup $FilesComment
    if (-not $script:GroupCreated) { $existed += $FilesGroup }
    Ensure-Group $FilesWriteGroup $FilesWriteComment
    if (-not $script:GroupCreated) { $existed += $FilesWriteGroup }
    Ensure-Group $FilesAdminGroup $FilesAdminComment
    if (-not $script:GroupCreated) { $existed += $FilesAdminGroup }
    Ensure-Group $AiGroup $AiComment
    if (-not $script:GroupCreated) { $existed += $AiGroup }

    if ($FirstInstall) {
        if ($existed.Count -eq 0) {
            Say "no route group was there before this install - all were created empty"
        } else {
            Say ("no data tree, so the route groups start empty: emptying " + ($existed -join ', '))
            foreach ($g in $existed) { Clear-Group $g }
        }
    }

    if ($FirstInstall) {
        Say "$SshGroup starts empty - a first install gives nobody ssh; an administrator gives it with modify.account <account> ssh (or both)"
    } elseif (-not $sshIsNew) {
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
