# remove-ssh.ps1 - take the Windows OpenSSH SERVER capability off this machine.
# PRE_RELEASE_FIXES 78.
#
#   powershell -File remove-ssh.ps1 -Show     report, change nothing
#   powershell -File remove-ssh.ps1           remove the capability
#
# Exit 0 removed (see the restart note below), 1 the removal failed, 2 the
# question could not be answered or there was nothing to remove.
#
# THE MIRROR OF install-ssh.ps1, and it uses the same capability name -
# OpenSSH.Server~~~~0.0.1.0.  The CLIENT capability is a different one and is
# NOT touched: ssh.exe, scp.exe and sftp.exe stay, because removing the server
# is about who can reach THIS machine, not about reaching others from it.
#
# ***THE REMOVAL IS STAGED BEHIND A REBOOT, AND SAYING SO IS MOST OF THIS
# SCRIPT'S JOB.***  Measured on the development host 30 Aug 2026: after
# Remove-WindowsCapability reported success, sshd.exe was STILL on disk, the
# sshd service was STILL Running/Automatic, the registry key was still there and
# RebootPending was True.  An administrator who runs this, sees ssh still
# working and reports a bug is the predictable outcome of not saying it - and
# the wizard read the machine correctly on exactly this state the same day.
#
# ***AND IT LEAVES C:\ProgramData\ssh BEHIND, WHICH IS A TRAP WITH TEETH.***
# Windows does not remove that directory with the capability, so sshd_config
# survives while sshd_config_default (which ships WITH the capability) does not.
# ssh-preflight.ps1 then takes its middle branch - "SD compares this computer's
# ssh configuration against the copy Windows ships, and that copy is missing" -
# and REFUSES THE NEXT SD INSTALL.  Measured 30 Aug 2026 by reading that
# script's three branches.  This one reports the directory so the administrator
# can decide; it does NOT delete it, because host keys live there and deleting
# them makes every client that knows this machine warn on the next connection.
#
# WHAT IT DOES NOT DO: it does not check whether SD accounts still need ssh.
# That is the caller's business and SSHSRVR does it, because the account
# register is SD's to read and this script has no session to read it with.

param(
    [switch]$Show
)

$ErrorActionPreference = 'Stop'

$CapName = 'OpenSSH.Server~~~~0.0.1.0'
$Sshd    = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
$SshDir  = Join-Path $env:ProgramData 'ssh'

function Say([string]$t) { Write-Output ("remove-ssh: " + $t) }

function Report([string]$label) {
    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    Say ("{0,-7} sshd.exe={1} service={2} ProgramData\ssh={3}" -f `
         $label,
         (Test-Path -LiteralPath $Sshd),
         $(if ($svc) { $svc.Status } else { 'ABSENT' }),
         (Test-Path -LiteralPath $SshDir))
}

Say ("capability : " + $CapName)
Say ("sshd.exe   : " + $Sshd)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # THE CHECK COMES BEFORE Get-WindowsCapability AND COVERS -Show TOO, because
    # -Online needs elevation even to READ - measured 30 Aug 2026, it fails with
    # "The requested operation requires elevation".  So -Show is not a
    # read-only escape from this and the message must not imply it is.
    Say 'not elevated - Windows will not report or change a capability without it'
    exit 1
}

try {
    $cap = Get-WindowsCapability -Online -Name $CapName
} catch {
    Say ('the capability list could not be read: ' + $_.Exception.Message)
    exit 2
}

if ($null -eq $cap) {
    Say 'Windows does not offer that capability on this machine at all'
    exit 2
}

Say ("state      : " + $cap.State)

# 30 Aug 26 - "before" IS A LIE ON THE -Show PATH, because nothing comes after
# it.  "ssh.server" with no keyword runs -Show, and the first thing it printed
# to the owner on 30 Aug 2026 was a line labelled "before" that was the whole
# output.  A label that promises a second half has to deliver one.
Report $(if ($Show) { 'state' } else { 'before' })

if ($Show) { exit 0 }

# NOT INSTALLED IS NOT A FAILURE, but it is not a removal either, and it must
# not report one.  A caller that treats "nothing to do" as "done" is the null
# case the instrument rule refuses.
if ($cap.State -ne 'Installed') {
    Say 'it is not installed, so there is nothing to remove'
    exit 2
}

try {
    $r = Remove-WindowsCapability -Online -Name $CapName
} catch {
    Say ('the removal failed: ' + $_.Exception.Message)
    exit 1
}

Report 'after'

# ***THE READ-BACK, AND IT IS EXPECTED TO DISAGREE WITH THE SUCCESS.***  On a
# machine that needs a restart, sshd.exe is still on disk here and the service
# is still Running - that is not a failure and must not be reported as one.
# What is reported is the truth: the removal is accepted and incomplete.
if ($r.RestartNeeded -or (Test-Path -LiteralPath $Sshd)) {
    Say 'ACCEPTED, BUT A RESTART IS NEEDED. Windows has staged the removal; the'
    Say 'ssh server is still on this machine and still running until you reboot.'
} else {
    Say 'removed, and no restart was required'
}

if (Test-Path -LiteralPath $SshDir) {
    # 1 Sep 26 - SAY WHICH INSTALL.  PRE_RELEASE_FIXES 116.  This paragraph used
    # to read "SD will REFUSE to install here again", and it is printed at an SD
    # prompt to somebody who has just typed "ssh.server remove" - so "install
    # here again" attaches to the ssh server, which is the one thing it does NOT
    # mean.  The refusal is ssh-preflight.ps1's, and sd.iss is its only caller;
    # SSHSRVR maps INSTALL to install-ssh.ps1, which calls no script at all.
    # MEASURED ON THE GUEST, 1 Sep 2026, in exactly this state: ssh.server
    # install was NOT refused and put the server back, while ssh-preflight.ps1
    # returned exit 2 - so both halves of the old sentence were wrong about
    # which install they governed.  It had already misled two readers with the
    # source open (entry 78 and PROJECT_STATUS's HANDOFF 8).
    #
    # AND IT IS "STOPS", NOT "REFUSES".  The branch that fires is the middle one,
    # "CANNOT DETERMINE", which the script treats as a refusal - the outcome is
    # the same and the reason is different, and the reason is what tells the
    # reader how to clear it.
    Say ''
    Say ('NOTE: ' + $SshDir + ' has been left in place. It holds the host keys and')
    Say 'sshd_config. Windows does not remove it with the capability.'
    Say ''
    Say 'That matters for ONE thing: running the SD INSTALLER on this machine'
    Say 'again. Setup compares sshd_config against the copy Windows ships,'
    Say 'sshd_config_default - and that copy went WITH the capability. Without'
    Say 'it Setup cannot tell whether the configuration has been edited, so it'
    Say 'stops rather than guess.'
    Say ''
    Say '"ssh.server install" is NOT affected: it puts the server back, and'
    Say 'sshd_config_default comes back with it. If you do not intend to run an'
    Say 'ssh server on this machine again, remove that directory as well.'
}

exit 0
