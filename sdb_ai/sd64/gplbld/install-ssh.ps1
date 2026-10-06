# install-ssh.ps1 - install and start OpenSSH Server.  PROJECT_STATUS.md 5.9.
#
#   powershell -ExecutionPolicy Bypass -File install-ssh.ps1
#   powershell -ExecutionPolicy Bypass -File install-ssh.ps1 -Show    report where the server would come from, change nothing
#
# Exit 0  installed and running
#      2  installed, but a RESTART is needed before the service exists
#      1  failed
#
# WITH -Show the exit code is the answer: 10 = nothing would be downloaded (a server is already here, or
# an OpenSSH MSI is at hand), 0 = the Windows capability, a Feature-on-Demand download from Windows Update,
# 1 = could not tell.  SSHSRVR reads it to decide whether "ssh.server install" has to warn about the download.
#
# IT IS THE INSTALLER'S OPT-IN TASK, AND DEFAULT OFF SINCE 1 Sep 2026.  The
# history reversed twice, so it is worth stating plainly: an opt-in checkbox
# originally; UNCONDITIONAL 16 Aug 2026 on the premise - SINCE SHOWN WRONG - that
# SD accounts sign in over ssh and nothing else, the API "carried over ssh too";
# an opt-in choice again 30 Aug 2026 (sd.iss [Tasks], the three-state ssh
# ruling); and default UNCHECKED 1 Sep 2026, because the Feature-on-Demand
# download can take up to an hour and forcing it on every install is a
# deal-breaker.  THE PREMISE WAS WRONG: the API is a separate port-4247 listener,
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

# 06 Oct 26 - RELEASE_1.1 121.  -Msi <path> is Microsoft's OpenSSH MSI, which the SD installer finds in
# "ssh-server" beside itself and passes here when the ssh box is ticked, so the server installs as ONE step
# of the SD install and works with no network.  Without it (or with a path that is not there) this
# script does what it always did: the Windows capability, which downloads from Windows Update.
# The MSI puts sshd.exe in Program Files\OpenSSH, not System32\OpenSSH, so every script that looks for the
# server looks in both (ssh-preflight, allow-ssh-groups, remove-ssh, sd.iss SshdInstalled).
# 06 Oct 26 - RELEASE_1.1 121, owner: "ssh.server already answered use bundled MSI".  The SD installer keeps a copy of
# the MSI it was given in <install folder>\ssh-server, whether or not the ssh box was ticked, so that the verb
# "ssh.server install" - which runs this script with no -Msi - installs the same way, offline, after Setup is gone.
# A -Msi that is given and exists wins; otherwise the newest kept copy beside this script is used; with neither it
# is the Windows capability as before.
param(
    [string]$Msi = '',
    [switch]$Show
)

if (($Msi -eq '') -or (-not (Test-Path -LiteralPath $Msi))) {
    # Newest by VERSION, not by name: "v9.5.0.0" sorts above "v10.0.0.0" as text.
    $kept = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'ssh-server') -Filter 'OpenSSH-Win64-*.msi' -File `
                -ErrorAction SilentlyContinue |
              Sort-Object { try { [version]($_.BaseName -replace '^OpenSSH-Win64-v', '') } catch { [version]'0.0' } } -Descending)
    if ($kept.Count -gt 0) { $Msi = $kept[0].FullName }
}

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

    # An sshd.exe from the MSI counts as installed too: the capability reads NotPresent when the server came
    # from the MSI, and re-adding the capability on top would download a second copy for nothing.
    $pf = $(if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles })
    $msiSshd = Join-Path $pf 'OpenSSH\sshd.exe'

    # -Show: say where the server would come from and stop.  The branches below, in the same order and with the
    # same tests, are what decide it for real; 10 is "no download".
    if ($Show) {
        if ($state -eq 'Installed' -or (Test-Path -LiteralPath $msiSshd)) {
            Write-Output 'install-ssh: an OpenSSH server is already installed'
            exit 10
        }
        if ($Msi -ne '' -and (Test-Path -LiteralPath $Msi) -and $state -ne 'UninstallPending') {
            Write-Output ('install-ssh: the server would be installed from ' + $Msi + ' (no download)')
            exit 10
        }
        Write-Output 'install-ssh: the server would be downloaded from Windows Update'
        exit 0
    }

    if ($state -eq 'Installed') {
        Write-Log "install-ssh: OpenSSH Server was already installed"
    } elseif (Test-Path -LiteralPath $msiSshd) {
        Write-Log ("install-ssh: OpenSSH Server was already installed (" + $msiSshd + ")")
    } elseif ($Msi -ne '' -and (Test-Path -LiteralPath $Msi) -and $state -ne 'UninstallPending') {
        # ADDLOCAL=Server: the server programs only.  The log is msiexec's own, kept beside ours.
        Write-Log ("install-ssh: installing OpenSSH Server from " + $Msi + " (no download)")
        Append-Log ('install-ssh: msi sha256 ' + (Get-FileHash -LiteralPath $Msi -Algorithm SHA256).Hash)
        $msiLog = Join-Path (Split-Path -Parent $LogPath) 'ssh-msi.log'
        $p = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') `
                -ArgumentList @('/i', ('"' + $Msi + '"'), '/qn', 'ADDLOCAL=Server', '/l*v', ('"' + $msiLog + '"')) `
                -Wait -PassThru
        Append-Log ('install-ssh: msiexec exit ' + $p.ExitCode + '  (0 done, 3010 done and a restart wanted; log ' + $msiLog + ')')
        if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) {
            Write-Log ('install-ssh: FAILED - the OpenSSH MSI exited ' + $p.ExitCode)
            exit 1
        }
        if (-not (Test-Path -LiteralPath $msiSshd)) {
            Write-Log ('install-ssh: FAILED - the OpenSSH MSI reported success but left no ' + $msiSshd)
            exit 1
        }
        if ($p.ExitCode -eq 3010 -and $null -eq (Get-Service -Name sshd -ErrorAction SilentlyContinue)) {
            Write-Log "install-ssh: installed, RESTART REQUIRED before the service can start"
            exit 2
        }
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
