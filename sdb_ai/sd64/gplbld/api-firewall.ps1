# api-firewall.ps1 - decide whether other computers may reach this machine's
# SD API port.  PROJECT_STATUS.md 5.9, and the posture B reversal in 8.
#
#   powershell -File api-firewall.ps1 -Open              any address
#   powershell -File api-firewall.ps1 -Restrict          this machine only
#   powershell -File api-firewall.ps1 -Remove            take the rule away
#   powershell -File api-firewall.ps1 -Show              report, change nothing
#   powershell -File api-firewall.ps1 -Open -Port 4243   a port other than the default
#
# Exit 0 applied, 1 failed, 2 refused.  ELEVATED - creating a firewall rule is
# a machine-wide change.
#
# WHY THIS IS NOT ssh-firewall.ps1 WITH A DIFFERENT PORT, which was the first
# thing tried.  That script TOGGLES a rule somebody else created: installing
# the OpenSSH capability creates OpenSSH-Server-In-TCP and enables it, so the
# question there is only how wide it should be.  NOTHING CREATES A RULE FOR
# 4243.  So this one owns its rule - it makes it, it names it, and -Remove
# takes it away on uninstall, which ssh-firewall must never do to Microsoft's.
#
# THE RULE IS OURS, AND THE NAME SAYS SO.  An administrator reading wf.msc
# should be able to tell at a glance which rules SD put there and remove them
# with the product.  Hence the SD- prefix and a description naming the config
# parameter that decides whether anything is listening at all.
#
# RemoteAddress, NOT Enabled=False, for -Restrict.  Same reasoning as
# ssh-firewall.ps1: both leave a local client working, because Windows does not
# filter loopback, but a DISABLED rule reads as something that got switched off
# and troubleshooting switches those back on.  A rule scoped to 127.0.0.1 and
# ::1 states the intent where somebody will read it.
#
# THE PORT IS NOT READ FROM sd.conf, deliberately.  This runs during
# installation, before the data tree is necessarily complete, and a rule that
# silently opened a DIFFERENT port from the one it was asked to open would be
# worse than one that needs telling.  The caller passes -Port; the default
# matches gplbld/stage.py's SD_CONF template.
#
# IT DOES NOT CHECK WHETHER SD IS LISTENING, and that is not an oversight: the
# rule outlives any particular run of the service, APIPORT can be commented out
# and back in without touching the firewall, and a rule for a port nothing has
# opened yet admits nothing.  api-firewall says who MAY reach the port; sd.conf
# says whether there is one.

param(
    [int]$Port = 4243,
    [switch]$Open,
    [switch]$Restrict,
    [switch]$Remove,
    [switch]$Show
)

$ErrorActionPreference = 'Stop'

$ruleName    = 'SD-API-In-TCP'
$displayName = 'SD API (SDClient)'

function Get-ApiRule {
    return (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)
}

function Write-State($rule) {
    if ($null -eq $rule) {
        Write-Output '  rule: not present'
        return
    }
    $filter = $rule | Get-NetFirewallPortFilter
    $addr   = ($rule | Get-NetFirewallAddressFilter).RemoteAddress
    Write-Output ('  rule: {0}  Enabled {1}  Direction {2}  Action {3}' -f
                  $rule.Name, $rule.Enabled, $rule.Direction, $rule.Action)
    Write-Output ('        LocalPort {0}  RemoteAddress {1}' -f
                  $filter.LocalPort, ($addr -join ', '))
}

if ($Port -lt 1 -or $Port -gt 65535) {
    Write-Output "api-firewall: -Port is $Port, which is not a port number"
    exit 1
}

try {
    if ($Show) {
        Write-State (Get-ApiRule)
        exit 0
    }

    $modes = @($Open, $Restrict, $Remove) | Where-Object { $_ }
    if ($modes.Count -ne 1) {
        Write-Output 'api-firewall: give exactly one of -Open, -Restrict, -Remove or -Show'
        exit 1
    }

    # Elevation is checked only for the modes that change something, so -Show
    # stays usable from an ordinary window - which is where somebody asking
    # "can anyone reach my API port?" actually is.
    $pr = New-Object Security.Principal.WindowsPrincipal(
              [Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output 'api-firewall: this needs an ELEVATED PowerShell - a firewall rule is machine-wide.'
        exit 2
    }

    if ($Remove) {
        $rule = Get-ApiRule
        if ($null -eq $rule) {
            Write-Output 'api-firewall: no rule to remove'
            exit 0
        }
        Remove-NetFirewallRule -Name $ruleName
        Write-Output "api-firewall: removed $ruleName"
        exit 0
    }

    $remote = if ($Open) { 'Any' } else { @('127.0.0.1', '::1') }

    # IDEMPOTENT, because the installer runs it on every install including a
    # reinstall over the top.  An existing rule is UPDATED rather than removed
    # and remade: remaking it would lose any grouping or profile scoping an
    # administrator had applied by hand, and would leave a window with no rule.
    $rule = Get-ApiRule
    if ($null -eq $rule) {
        $null = New-NetFirewallRule -Name $ruleName -DisplayName $displayName `
                    -Description ('Inbound TCP for the SD API listener.  ' +
                                  'Whether anything is listening is set by APIPORT in sd.conf.') `
                    -Direction Inbound -Protocol TCP -LocalPort $Port `
                    -Action Allow -Enabled True -RemoteAddress $remote
        Write-Output "api-firewall: created $ruleName for port $Port"
    }
    else {
        Set-NetFirewallRule -Name $ruleName -LocalPort $Port -Protocol TCP `
                            -Enabled True -RemoteAddress $remote
        Write-Output "api-firewall: updated $ruleName for port $Port"
    }

    if ($Open) {
        Write-Output "api-firewall: other computers MAY reach the SD API on port $Port"
    } else {
        Write-Output "api-firewall: the SD API is reachable FROM THIS MACHINE ONLY"
    }

    Write-State (Get-ApiRule)
    exit 0
}
catch {
    Write-Output ('api-firewall: FAILED - ' + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    exit 1
}
