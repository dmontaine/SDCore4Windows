# install-ssh.ps1 - install and start OpenSSH Server.  PROJECT_STATUS.md 5.9.
#
#   powershell -ExecutionPolicy Bypass -File install-ssh.ps1
#
# Exit 0  installed and running
#      2  installed, but a RESTART is needed before the service exists
#      1  failed
#
# IT IS THE INSTALLER'S OPT-IN TASK, AND DEFAULT OFF SINCE 1 Sep 2026.  The
# history reversed twice, so it is worth stating plainly: an opt-in checkbox
# originally; UNCONDITIONAL 16 Aug 2026 on the premise - SINCE SHOWN WRONG - that
# SD accounts sign in over ssh and nothing else, the API "carried over ssh too";
# an opt-in choice again 30 Aug 2026 (sd.iss [Tasks], the three-state ssh
# ruling); and default UNCHECKED 1 Sep 2026, because the Feature-on-Demand
# download can take up to an hour and forcing it on every install is a
# deal-breaker.  THE PREMISE WAS WRONG: the API is a separate port-4243 listener,
# not carried over ssh (sd.iss:349), and an account granted API access signs in
# over it via SCRAM without any ssh server - so ssh is the INTERACTIVE login
# path, not the only one.  sd.iss gates this with Check: SshServerWanted, so it
# runs ONLY when the box is ticked.  Who may reach the server is separately
# optional, which is ssh-firewall.ps1 and allow-ssh-groups.ps1.
#
# Nothing in this script's WORK changed across any of that: it was already
# idempotent and already reported "was already installed" separately from
# "installed it".  It is also still the by-hand recovery when the download is
# blocked.
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
#
# WHY THERE IS NOW A LOG FILE, RELEASE_1.1 109, 24 Sep 2026.  sd.iss's [Run]
# entry for this script uses Flags: runhidden with no output redirection, so
# every line below went nowhere - a report of "OpenSSH server could NOT be
# installed" carried no reason, including the one line that would explain it
# (the catch below).  Write-Log below is the only change: same text, same
# stdout, also appended to C:\ProgramData\SD\ssh-setup.log so the next failure
# is diagnosable instead of guessed at.
#
# dism.exe, NOT THE *-WindowsCapability CMDLETS, SAME DAY, SAME ENTRY.  What the
# log above was built to catch turned up on the owner's test machine:
# Get-WindowsCapability threw "Class not registered" while dism.exe worked, so
# this script failed at its first real line.  dism-capability.ps1 holds why and
# how; State values and the exit contract (0 / 2 restart / 1) are unchanged.

$LogPath = 'C:\ProgramData\SD\ssh-setup.log'
function Append-Log {
    param([string]$Message)
    try {
        $line = (Get-Date -Format 's') + ' ' + $Message
        Out-File -FilePath $LogPath -InputObject $line -Append -Encoding utf8 -ErrorAction Stop
    } catch {}
}
function Write-Log {
    param([string]$Message)
    Write-Output $Message
    Append-Log $Message
}

$ErrorActionPreference = 'Stop'
$CapName = 'OpenSSH.Server~~~~0.0.1.0'

try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Log "install-ssh: not elevated"
        exit 1
    }

    . (Join-Path $PSScriptRoot 'dism-capability.ps1')

    $q = Invoke-Dism -DismArgs '/Get-CapabilityInfo', ('/CapabilityName:' + $CapName)
    Append-Log ('install-ssh: ran ' + $q.Command + '  -> exit ' + $q.Code)
    foreach ($l in $q.Lines) { Append-Log ('    ' + $l) }
    $state = Get-CapabilityState $q
    if ($q.Code -ne 0 -or $state -eq '') {
        foreach ($l in $q.Lines) { Write-Output ('    ' + $l) }
        Write-Log ('install-ssh: FAILED - dism could not read the OpenSSH capability (exit ' + $q.Code + ', state "' + $state + '")')
        exit 1
    }
    Append-Log ('install-ssh: OpenSSH Server state is ' + $state)

    if ($state -eq 'Installed') {
        Write-Log "install-ssh: OpenSSH Server was already installed"
    } else {
        # SAY WHY WE ARE DOWNLOADING WHEN THE SERVER IS PLAINLY STILL HERE.
        # PRE_RELEASE_FIXES 122.  An earlier "ssh.server remove" only STAGES the
        # removal - it completes on the next reboot - so until then the
        # capability reads UninstallPending (measured 1 Sep 2026) while sshd.exe
        # is still present and the service still Running.  Re-adding the
        # capability is the only SUPPORTED way to cancel that pending removal,
        # and it re-downloads the payload from Windows Update because OpenSSH
        # Server is a Feature-on-Demand: Windows keeps no local copy after
        # install, so there is nothing on disk to re-enable from.  Measured on
        # the host that day: ~19 minutes, after which State returned to Installed
        # and the reboot no longer removes the server.  There is no cheaper
        # supported cancel, so name the reason rather than let a ~19-minute
        # download look like a fresh install of a server that is still running.
        if ($state -eq 'UninstallPending') {
            Write-Log "install-ssh: OpenSSH Server is UninstallPending - an earlier 'ssh.server remove' staged a removal that a reboot would complete."
            Write-Log "install-ssh: the server is still present and running until then; re-adding it now cancels that pending removal,"
            Write-Log "install-ssh: which re-downloads the payload from Windows Update (a Feature-on-Demand keeps no local copy) and can take several minutes."
        } else {
            Write-Log "install-ssh: installing OpenSSH Server (this downloads from Windows Update and can take several minutes)"
        }
        $a = Invoke-Dism -DismArgs '/Add-Capability', ('/CapabilityName:' + $CapName), '/NoRestart'
        Append-Log ('install-ssh: ran ' + $a.Command + '  -> exit ' + $a.Code)
        foreach ($l in $a.Lines) { Append-Log ('    ' + $l) }
        if ($a.Code -eq $DismRestartNeeded) {
            Write-Log "install-ssh: installed, RESTART REQUIRED before the service can start"
            exit 2
        }
        if ($a.Code -ne 0) {
            foreach ($l in $a.Lines) { Write-Output ('    ' + $l) }
            Write-Log ('install-ssh: FAILED - dism /Add-Capability exited ' + $a.Code)
            exit 1
        }
    }

    # The service is registered by the capability, not by us.  If it is not
    # there yet, a restart is outstanding - which is a success, not a failure.
    $svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
    if ($null -eq $svc) {
        Write-Log "install-ssh: installed, but the sshd service is not registered yet - RESTART REQUIRED"
        exit 2
    }

    Set-Service -Name sshd -StartupType Automatic
    if ($svc.Status -ne 'Running') { Start-Service sshd }

    # sshd writes its own default sshd_config on first start, so this is the
    # point at which it exists - worth saying, because AllowGroups (5.6.2) is
    # edited into that file and there is nothing to edit before now.
    $svc = Get-Service -Name sshd
    Write-Log ("install-ssh: sshd is " + $svc.Status + ", StartType=" + (Get-Service sshd).StartType)
    Write-Log ("install-ssh: sshd_config present: " + (Test-Path 'C:\ProgramData\ssh\sshd_config'))
    exit 0
}
catch {
    Write-Log ("install-ssh: FAILED - " + $_.Exception.Message)
    exit 1
}
