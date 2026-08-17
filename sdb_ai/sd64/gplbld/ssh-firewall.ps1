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
# A rule scoped to 127.0.0.1 and ::1 states the intent where an administrator
# will read it, in wf.msc, and survives being re-enabled by somebody who did not
# know why it was off.
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
    [switch]$Show
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
    if ($null -eq $rule) {
        Write-Output "ssh-firewall: no inbound OpenSSH rule found - the capability has probably not finished registering it, which a restart completes"
        exit 2
    }

    if ($Show) {
        Write-State $rule
        exit 0
    }

    if (-not $Installed) {
        Write-Output "ssh-firewall: -Installed not given - SD only changes the firewall rule of an ssh server it installed itself (5.9)"
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
        Set-NetFirewallRule -Name $rule.Name -RemoteAddress @('127.0.0.1', '::1') -Enabled True
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
