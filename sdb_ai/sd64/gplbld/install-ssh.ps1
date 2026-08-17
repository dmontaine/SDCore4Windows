# install-ssh.ps1 - install and start OpenSSH Server.  PROJECT_STATUS.md 5.9.
#
#   powershell -File install-ssh.ps1
#
# Exit 0  installed and running
#      2  installed, but a RESTART is needed before the service exists
#      1  failed
#
# NO LONGER THE INSTALLER'S OPT-IN CHECKBOX.  Owner's decision, 16 Aug 2026: SD
# accounts sign in over ssh and nothing else, and the API is carried over ssh
# too, so sd.iss now runs this whenever the machine has no ssh server - a local
# user reaches SD by ssh'ing to localhost.  What is optional is who may reach
# the server from elsewhere, which is ssh-firewall.ps1.
#
# Nothing in this script changed with that decision, and nothing needed to: it
# was already idempotent and already reported "was already installed"
# separately from "installed it".  The caller changed, not the work.  It is also
# still the by-hand recovery when the download is blocked, which is now a state
# the machine can reach on its own rather than one the user chose.
#
# WHY THIS IS A FILE AND NOT AN INLINE [Run] PARAMETER.  It used to be inline,
# and it carried a brace bug for its whole life: Inno escapes a literal "{" as
# "{{" but needs no escape for "}", so "}}" reached PowerShell as two closing
# braces and the script was a syntax error before it ran.  Ticking the box
# installed nothing and said nothing.  A file can be read and parse-checked on
# its own, which is the entire reason this exists.
#
# WHY THE RESTART CASE IS HANDLED SEPARATELY.  Measured 14 Aug 2026:
# Add-WindowsCapability completed, but the sshd SERVICE did not exist until
# after a reboot.  The previous version ran Set-Service and Start-Service
# unconditionally in the same breath, so on such a machine it threw "no such
# service", hit the catch, and reported total failure for what was in fact a
# success needing a restart.  Distinguish the two: telling someone to reboot is
# useful, telling them it failed is not.

$ErrorActionPreference = 'Stop'

try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output "install-ssh: not elevated"
        exit 1
    }

    $cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0'
    if ($cap.State -ne 'Installed') {
        Write-Output "install-ssh: installing OpenSSH Server (this downloads from Windows Update and can take several minutes)"
        $r = Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
        if ($r.RestartNeeded) {
            Write-Output "install-ssh: installed, RESTART REQUIRED before the service can start"
            exit 2
        }
    } else {
        Write-Output "install-ssh: OpenSSH Server was already installed"
    }

    # The service is registered by the capability, not by us.  If it is not
    # there yet, a restart is outstanding - which is a success, not a failure.
    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Output "install-ssh: installed, but the sshd service is not registered yet - RESTART REQUIRED"
        exit 2
    }

    Set-Service -Name sshd -StartupType Automatic
    if ($svc.Status -ne 'Running') { Start-Service sshd }

    # sshd writes its own default sshd_config on first start, so this is the
    # point at which it exists - worth saying, because AllowGroups (5.6.2) is
    # edited into that file and there is nothing to edit before now.
    $svc = Get-Service -Name sshd
    Write-Output ("install-ssh: sshd is " + $svc.Status + ", StartType=" + (Get-Service sshd).StartType)
    Write-Output ("install-ssh: sshd_config present: " + (Test-Path 'C:\ProgramData\ssh\sshd_config'))
    exit 0
}
catch {
    Write-Output ("install-ssh: FAILED - " + $_.Exception.Message)
    exit 1
}
