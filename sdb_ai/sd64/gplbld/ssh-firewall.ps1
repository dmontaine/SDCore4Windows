# ssh-firewall.ps1 - decide whether other computers may reach this machine's
# ssh server.  PROJECT_STATUS.md 5.9.
#
#   powershell -File ssh-firewall.ps1 -Installed -Restrict   loopback only
#   powershell -File ssh-firewall.ps1 -Installed -Open       any address
#   powershell -File ssh-firewall.ps1 -Show                  report, change nothing
#
# Exit 0 applied, 1 failed, 2 refused or the rule is not there yet.
#
# WHY THIS EXISTS.  The OpenSSH server stopped being optional on 16 Aug 2026 -
# SD accounts sign in over ssh and nothing else, and the API is carried over ssh
# too, so an install without it is an install nobody but the installing user can
# use.  But installing the capability also creates OpenSSH-Server-In-TCP and
# ENABLES it.  Measured on this machine, 16 Aug 2026:
#
#     Name  OpenSSH-Server-In-TCP   Enabled True   Direction Inbound
#     Profile Private               Action Allow   RemoteAddress Any
#
# So making the install unconditional would, on its own, open port 22 to the
# whole local network on EVERY install - including for somebody whose only use
# of ssh is reaching their own machine, which is the case that made ssh
# mandatory in the first place.  The exposure is therefore separated from the
# install: the server is always there, and whether anyone else may reach it is
# the checkbox.
#
# RemoteAddress, NOT Enabled=False.  Both would leave "ssh localhost" working -
# Windows does not filter loopback traffic - but a disabled rule reads as
# something that got switched off, and troubleshooting switches those back on.
# A rule scoped to 127.0.0.1 states the intent where an administrator will read
# it, in wf.msc, and survives being re-enabled by somebody who did not know why
# it was off.
#
# 24 Aug 26 - THAT SAID "127.0.0.1 and ::1" UNTIL TODAY, AND ::1 IS THE ONE
# VALUE WINDOWS WILL NOT TAKE.  Passing it threw on every run, so the rule was
# never scoped at all.  The restrict branch below carries the measurement.
#
# -Installed IS REQUIRED FOR ANY CHANGE, for the reason allow-ssh-groups.ps1
# gives at length: SD does not reconfigure an ssh server it did not install.
# That rule covers this rule as much as it covers sshd_config - restricting the
# firewall of a server that predates SD would break somebody's remote access
# just as thoroughly as editing their config would.
#
# THE RULE IS LOOKED UP TWO WAYS.  The name above is what the capability has
# used for every build seen here, but it is Microsoft's name and not ours, so a
# miss falls back to matching the display name.  Failing to find it is exit 2
# rather than 1: the likely reason is that the capability has not finished
# registering it and a restart is outstanding, which is not a failure.

param(
    [switch]$Installed,
    [switch]$Restrict,
    [switch]$Open,
    [switch]$Show,

    # 30 Aug 26 - PRE_RELEASE_FIXES 76.  Write "open" or "restricted" to this
    # path and exit, changing nothing.  The installer needs the CURRENT scope
    # before it draws the wizard, because it is the default state of the "allow
    # remote access" checkbox on a machine that already has an ssh server: the
    # owner's ruling is that the box shows the truth, so that leaving it alone
    # changes nothing in either direction.
    #
    # A FILE RATHER THAN stdout, because Inno's Exec cannot capture stdout and
    # this file's own record warns off the alternative: sd.iss:712 documents an
    # inline -Command that "carried a brace bug for its entire life".
    # ssh-preflight.ps1 -ReasonFile is the precedent being copied.
    #
    # IT IS READ-ONLY AND SO IT DOES NOT TAKE THE -Installed GATE.  Reading the
    # scope of a server SD did not install is not reconfiguring it (5.9).
    [string]$ScopeFile = ''
)

$ErrorActionPreference = 'Stop'

$ruleName = 'OpenSSH-Server-In-TCP'

# Returns the rule, or $null.
function Get-SshRule {
    $r = Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue
    if ($null -ne $r) { return $r }
    # Microsoft's name, not ours - match on what the user sees instead.
    $r = Get-NetFirewallRule -ErrorAction SilentlyContinue |
             Where-Object { $_.DisplayName -like 'OpenSSH SSH Server*' -and $_.Direction -eq 'Inbound' }
    if ($r -is [array]) { return $r[0] }
    return $r
}

function Write-State($rule) {
    $addr = ($rule | Get-NetFirewallAddressFilter).RemoteAddress -join ','
    Write-Output ("ssh-firewall: " + $rule.Name + "  Enabled=" + $rule.Enabled +
                  "  Profile=" + $rule.Profile + "  RemoteAddress=" + $addr)
}

try {
    $rule = Get-SshRule

    # -ScopeFile IS ANSWERED FIRST, BEFORE THE "no rule" EXIT BELOW, because it
    # has to answer even when there is no rule.  A missing rule is not an error
    # for this question: it means nothing is open, which is exactly what the
    # caller needs to know, and exiting 2 here would leave the installer with no
    # answer at all for a case that has a perfectly good one.
    if ($ScopeFile -ne '') {
        if ($null -eq $rule) {
            $verdict = 'restricted'
        } else {
            # A LIST, NOT A SCALAR.  RemoteAddress can hold several entries, so
            # this asks whether ANY of them is the unrestricted one rather than
            # comparing the joined string.  Case-insensitive on purpose here:
            # Windows' own spelling is "Any" and this is a keyword, not data.
            $addrs = ($rule | Get-NetFirewallAddressFilter).RemoteAddress
            if ($addrs -contains 'Any') { $verdict = 'open' } else { $verdict = 'restricted' }
        }
        [System.IO.File]::WriteAllText($ScopeFile, $verdict, [System.Text.Encoding]::ASCII)
        Write-Output ("ssh-firewall: current scope is " + $verdict)
        exit 0
    }

    if ($null -eq $rule) {
        Write-Output "ssh-firewall: no inbound OpenSSH rule found - the capability has probably not finished registering it, which a restart completes"
        exit 2
    }

    if ($Show) {
        Write-State $rule
        exit 0
    }

    # 30 Aug 26 - THE GATE STAYS, ITS REASON IS NARROWED.  PRE_RELEASE_FIXES 76.
    # It used to mean "SD installed this server, so SD may reconfigure it" (5.9).
    # The owner's ruling of 30 Aug 2026 is that the installer must also offer the
    # scope choice on a server SD did NOT install, so the flag now means the
    # weaker and more accurate thing: THE CALLER HAS ESTABLISHED THAT IT MAY
    # CHANGE THIS RULE.  For the installer that means the reader was shown a
    # checkbox pre-set to the rule's current scope, so an untouched box changes
    # nothing; for a person at a prompt it means they typed it deliberately.
    #
    # THE NAME IS KEPT ON PURPOSE.  It appears in the installer's own closing
    # text and in the documentation as the command to re-run by hand, so
    # renaming it would silently invalidate instructions already given to users.
    # What 5.9 still forbids is untouched: nothing here edits sshd_config.
    if (-not $Installed) {
        Write-Output "ssh-firewall: -Installed not given - it is the deliberate-action gate, and this script will not change a firewall rule without it"
        exit 2
    }

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output "ssh-firewall: not elevated - the firewall cannot be changed without it"
        exit 1
    }

    if ($Open -and $Restrict) {
        Write-Output "ssh-firewall: -Open and -Restrict are contradictory"
        exit 1
    }
    if (-not $Open -and -not $Restrict) {
        Write-Output "ssh-firewall: give -Open or -Restrict"
        exit 1
    }

    if ($Open) {
        # Put it back the way the capability leaves it.  Said explicitly rather
        # than "do nothing", because a REINSTALL may be widening a rule this
        # script restricted last time.
        Set-NetFirewallRule -Name $rule.Name -RemoteAddress Any -Enabled True
        Write-Output "ssh-firewall: other computers MAY reach this machine over ssh"
    }
    else {
        # 24 Aug 26 - 127.0.0.1 ALONE.  THIS LINE USED TO PASS @('127.0.0.1','::1')
        # AND IT THREW EVERY TIME IT RAN, WHICH WAS THE WHOLE BUG.
        #
        # Windows refuses ANY IPv6 loopback literal in -RemoteAddress:
        # "An unspecified, multicast, broadcast, or loopback IPv6 address was
        # specified".  Under ErrorActionPreference Stop the whole call throws,
        # the catch below reports FAILED and exits 1, and the rule is LEFT AT
        # RemoteAddress=Any - port 22 open to the local network, which is the
        # exact exposure this script exists to prevent.
        #
        # IT WAS NEVER A REGRESSION.  sd.iss only calls this when SshWasAbsent,
        # so on every machine it had run on - all of which already had sshd - the
        # step exited before reaching here.  Found on the first install ever
        # performed on a machine with no ssh server, VM Windows 11 -
        # sshRemoteTest, 24 Aug 2026.
        #
        # DROPPING ::1 IS SAFE AND THAT WAS MEASURED, NOT ASSUMED - it matters
        # because sshd binds :::22 as well as 0.0.0.0:22, so an IPv6 "ssh
        # localhost" is a real case.  With the rule scoped to 127.0.0.1 alone,
        # dialled with a socket of the MATCHING address family each time:
        #     127.0.0.1:22 via AF_INET   REACHABLE
        #     ::1:22       via AF_INET6  REACHABLE
        # which is the header's own point above - Windows does not filter
        # loopback traffic at all, so the value here only has to be something no
        # remote address matches.  127.0.0.1/32 is accepted too and normalises
        # to the same thing; the bare address is what wf.msc shows most plainly.
        #
        # probe-sshfirewall.ps1 re-takes this measurement, and it names the
        # address family on every dial: New-Object Net.Sockets.TcpClient defaults
        # to AF_INET and CANNOT dial an IPv6 literal, which fails with "None of
        # the discovered or specified addresses match the socket address family"
        # and reads exactly like "::1 is blocked".  That false reading was drawn
        # here first and nearly became the reason not to make this fix.
        Set-NetFirewallRule -Name $rule.Name -RemoteAddress '127.0.0.1' -Enabled True
        Write-Output "ssh-firewall: ssh is reachable FROM THIS MACHINE ONLY"
    }

    Write-State (Get-NetFirewallRule -Name $rule.Name)
    exit 0
}
catch {
    Write-Output ("ssh-firewall: FAILED - " + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    exit 1
}
