# remove-ssh.ps1 - take the Windows OpenSSH SERVER capability off this machine.
# PRE_RELEASE_FIXES 78.
#
#   powershell -ExecutionPolicy Bypass -File remove-ssh.ps1 -Show     report, change nothing
#   powershell -ExecutionPolicy Bypass -File remove-ssh.ps1           remove the capability
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
#
# 24 Sep 26 - dism.exe, NOT Get-/Remove-WindowsCapability.  RELEASE_1.1 109:
# on the owner's test machine the cmdlets threw "Class not registered" while
# dism.exe worked.  dism-capability.ps1, shared with install-ssh.ps1, holds why.
# Exit codes are unchanged; a dism failure also prints dism's own lines.

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
    # THE CHECK COMES BEFORE THE CAPABILITY QUERY AND COVERS -Show TOO, because
    # /Online needs elevation even to READ - measured 30 Aug 2026 on the cmdlet,
    # "The requested operation requires elevation"; dism.exe refuses the same
    # way.  So -Show is not a read-only escape from this and the message must
    # not imply it is.
    Say 'not elevated - Windows will not report or change a capability without it'
    exit 1
}

# 06 Oct 26 - RELEASE_1.1 121.  A SERVER THAT CAME FROM THE OpenSSH MSI IS REMOVED WITH THE MSI.  When the SD
# installer finds Microsoft's OpenSSH MSI beside itself it installs the server from that (install-ssh.ps1 -Msi),
# into Program Files\OpenSSH; the Windows capability then reads "not present", and the capability route below
# would answer "nothing to remove" about a server that is plainly there.  So: no sshd.exe in System32 and one in
# Program Files means the MSI's, and that is removed with msiexec /x on its own product code, found in the
# Uninstall key (ProductName "OpenSSH", Manufacturer Microsoft Corporation, the key is the GUID - read from the
# MSI's database, 6 Oct 2026).  An MSI removal needs no restart, unlike the capability's staged one.
$MsiSshd = Join-Path $(if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }) 'OpenSSH\sshd.exe'
if ((-not (Test-Path -LiteralPath $Sshd)) -and (Test-Path -LiteralPath $MsiSshd)) {
    $Sshd = $MsiSshd
    $code = ''
    foreach ($root in 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
                      'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall') {
        foreach ($k in @(Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
            if ($k.PSChildName -notmatch '^\{[0-9A-Fa-f-]{36}\}$') { continue }
            $prop = Get-ItemProperty -LiteralPath $k.PSPath -ErrorAction SilentlyContinue
            if ($prop -and $prop.DisplayName -ceq 'OpenSSH') { $code = $k.PSChildName; break }
        }
        if ($code) { break }
    }
    Say ("server     : installed from the OpenSSH MSI (" + $Sshd + "), product code " + $(if ($code) { $code } else { 'NOT FOUND' }))
    Report $(if ($Show) { 'machine' } else { 'before' })
    if ($Show) { exit 0 }
    if (-not $code) {
        Say 'the OpenSSH MSI is not listed among the installed programs, so it cannot be removed from here'
        exit 2
    }
    $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') `
            -ArgumentList @('/x', $code, '/qn', '/norestart') -Wait -PassThru
    Say ('msiexec /x ' + $code + ' exited ' + $p.ExitCode + '  (0 done, 3010 done and a restart wanted)')
    if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { exit 1 }
    Report 'after'
    if (Test-Path -LiteralPath $Sshd) { Say 'sshd.exe is STILL there after the MSI removal'; exit 1 }
    Say 'removed, and no restart was required'
    if (Test-Path -LiteralPath $SshDir) {
        Say ''
        Say ('NOTE: ' + $SshDir + ' has been left in place. It holds the host keys and')
        Say 'sshd_config, and the MSI does not remove it. Running the SD INSTALLER on this machine again'
        Say 'compares sshd_config with sshd_config_default, which went with the server; Setup treats a'
        Say 'missing copy as "cannot tell" and stops. "ssh.server install" puts the server back.'
    }
    exit 0
}

try {
    . (Join-Path $PSScriptRoot 'dism-capability.ps1')
    $q = Invoke-Dism -DismArgs '/Get-CapabilityInfo', ('/CapabilityName:' + $CapName)
} catch {
    Say ('the capability list could not be read: ' + $_.Exception.Message)
    exit 2
}

if ($q.Code -ne 0) {
    Say ('the capability list could not be read: dism exited ' + $q.Code)
    foreach ($l in $q.Lines) { Say ('    ' + $l) }
    exit 2
}

$state = Get-CapabilityState $q
if ($state -eq '') {
    Say 'Windows does not offer that capability on this machine at all'
    exit 2
}

Say ("state      : " + $state)

# 30 Aug 26 - "before" IS A LIE ON THE -Show PATH, because nothing comes after
# it.  "ssh.server" with no keyword runs -Show, and the first thing it printed
# to the owner on 30 Aug 2026 was a line labelled "before" that was the whole
# output.  A label that promises a second half has to deliver one.
#
# 02 Sep 26 - AND THE LABEL THAT REPLACED IT COLLIDED.  PRE_RELEASE_FIXES.md
# 127.  "state" is already used eleven lines above for the CAPABILITY state
# ("state      : Installed"), so witnessing 115 on 2 Sep 2026 produced a
# four-line report naming "state" twice, meaning two different things:
#
#     state      : Installed                                  <- the capability
#     state   sshd.exe=True service=Running ...               <- the machine
#
# A reader cannot tell which one is authoritative.  "machine" says whose state
# it is, is exactly the 7 characters the {0,-7} field holds, and leaves
# "before"/"after" on the acting paths untouched.
Report $(if ($Show) { 'machine' } else { 'before' })

if ($Show) { exit 0 }

# NOT INSTALLED IS NOT A FAILURE, but it is not a removal either, and it must
# not report one.  A caller that treats "nothing to do" as "done" is the null
# case the instrument rule refuses.
if ($state -ne 'Installed') {
    Say 'it is not installed, so there is nothing to remove'
    exit 2
}

$r = Invoke-Dism -DismArgs '/Remove-Capability', ('/CapabilityName:' + $CapName), '/NoRestart'
if ($r.Code -ne 0 -and $r.Code -ne $DismRestartNeeded) {
    Say ('the removal failed: dism exited ' + $r.Code)
    foreach ($l in $r.Lines) { Say ('    ' + $l) }
    exit 1
}

Report 'after'

# ***THE READ-BACK, AND IT IS EXPECTED TO DISAGREE WITH THE SUCCESS.***  On a
# machine that needs a restart, sshd.exe is still on disk here and the service
# is still Running - that is not a failure and must not be reported as one.
# What is reported is the truth: the removal is accepted and incomplete.
if ($r.Code -eq $DismRestartNeeded -or (Test-Path -LiteralPath $Sshd)) {
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
