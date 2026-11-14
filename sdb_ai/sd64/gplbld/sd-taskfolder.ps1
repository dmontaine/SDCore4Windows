# sd-taskfolder.ps1 - the Task Scheduler folder \SD, SYSTEM and Administrators only.  ONE copy, dot-sourced by remote-admin.ps1 (the
# remote administration broker and its SYSTEM check task), sd-jobs.ps1 (SET.JOB's tasks) and finish-install.ps1 (made at install).
#
# 13 Nov 26 Windows port - written for RELEASE_1.1 281, moved here out of remote-admin.ps1 (RELEASE_1.1 280) so SET.JOB uses the same rule.
#
# WHY.  Measured on the host 13 Nov 2026: Task Scheduler's root folder grants Authenticated Users WRITE, inherited by every subfolder
# ((A;CI;FW;;;AU)), and CREATOR OWNER full control of what it makes; an ORDINARY unelevated user can create a top-level folder, and owns
# it.  So with inherited defaults any signed-in user could make \SD before SD does, or put a task under one of SD's names in it, and SD's
# tasks - which run as SDSYS, or as SYSTEM - would be registered into their folder, or over their task.  That it is exploitable was not
# measured; the door is shut instead.  Also measured: the COM GetFolder('\SD') throws 0x80070002 when \SD is missing (Register-
# ScheduledTask makes a missing folder silently, with the inherited defaults).
#
# Initialize-SdTaskFolder($svc) - $svc a connected Schedule.Service.  Returns the ITaskFolder \SD: made with $SdTaskFolderSddl when it is
# missing; one that exists is used only when its OWNER is SYSTEM, Administrators or a member of Administrators (Test-SdAdminOwner; anyone
# else could have put anything in it: refused, nothing changed) and is then given $SdTaskFolderSddl, which takes away the Authenticated Users write it inherited.  Prints nothing and
# throws on any doubt.  Callers also delete a task of the name they are about to register, so nothing is ever updated in place.
# Needs an elevated administrator (or SYSTEM).  gplbld/test-remoteadmin-units.ps1 rows R10 and R11 guard it.

$SdTaskFolderSddl = 'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'

function Test-SdAdminOwner([string]$sid) {
    # True for SYSTEM, Administrators, or an account that is a member of Administrators: a folder such an account owns is as trusted as the
    # group (an upgraded machine's \SD may be owned by SDSYS, which SET.JOB registered its tasks as - not measured, so allowed).  The
    # members are read through the WinNT provider, which, unlike Get-LocalGroupMember, does not fail on an orphaned member.  Any doubt: false.
    if (@('S-1-5-18', 'S-1-5-32-544') -contains $sid) { return $true }
    try {
        $name = (New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')).Translate([Security.Principal.NTAccount]).Value.Split('\')[-1]
        $grp = [ADSI]("WinNT://./$name,group")
        foreach ($m in @($grp.psbase.Invoke('Members'))) {
            $bytes = $m.GetType().InvokeMember('objectSid', 'GetProperty', $null, $m, $null)
            if ($null -ne $bytes -and (New-Object Security.Principal.SecurityIdentifier([byte[]]$bytes, 0)).Value -eq $sid) { return $true }
        }
    } catch { return $false }
    return $false
}

function Initialize-SdTaskFolder($svc) {
    try { $f = $svc.GetFolder('\SD') } catch { return $svc.GetFolder('\').CreateFolder('SD', $SdTaskFolderSddl) }
    $owner = (New-Object Security.AccessControl.RawSecurityDescriptor($f.GetSecurityDescriptor(0x1))).Owner
    if ($null -eq $owner -or -not (Test-SdAdminOwner $owner.Value)) {
        throw ('the task folder \SD is owned by ' + $(if ($null -eq $owner) { 'nobody' } else { $owner.Value }) + ', which is not SYSTEM, Administrators or one of its members, so it is not used; delete it (an elevated administrator: schtasks /delete and the folder in Task Scheduler) and run this again')
    }
    $f.SetSecurityDescriptor($SdTaskFolderSddl, 0)
    return $f
}
