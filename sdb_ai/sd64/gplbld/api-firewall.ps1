# api-firewall.ps1 - decide whether other computers may reach this machine's
# SD API port.  PROJECT_STATUS.md 5.9, and the posture B reversal in 8.
#
#   powershell -ExecutionPolicy Bypass -File api-firewall.ps1 -Open              any address
#   powershell -ExecutionPolicy Bypass -File api-firewall.ps1 -Restrict          this machine only
#   powershell -ExecutionPolicy Bypass -File api-firewall.ps1 -Remove            take the rule away
#   powershell -ExecutionPolicy Bypass -File api-firewall.ps1 -Show              report, change nothing
#   powershell -ExecutionPolicy Bypass -File api-firewall.ps1 -ScopeFile <path>  write one word and stop
#   powershell -ExecutionPolicy Bypass -File api-firewall.ps1 -Retarget          move a rule left on the old port 4243 to 4247, scope untouched
#
# Exit 0 applied, 1 failed, 2 refused.  ELEVATED - creating a firewall rule is
# a machine-wide change.  -Show and -ScopeFile are the two read-only modes and
# neither takes the elevation gate.
#
# 01 Oct 26 - THE PORT IS 4247 AND THERE IS NO -Port.  The owner ruled the API
# port fixed and not adjustable (SD_API_PORT in gplsrc/sddefs.h; it was 4243,
# which is OpenQM's).  A rule made by W1.1-1 or earlier still names 4243 and so
# admits nothing on 4247: -Show and -ScopeFile say so rather than describing its
# scope as if it applied, and -Retarget moves the one field, which the installer
# runs on an upgrade, where -Open and -Restrict must not run (they would change
# the scope on the strength of a box nobody saw).  -Open and -Restrict also
# correct the port of an existing rule, since they update it in place.
#
# -ScopeFile EXISTS FOR THE INSTALLER, and ssh-firewall.ps1's -ScopeFile is the
# precedent being copied.  PRE_RELEASE_FIXES 147: after an uninstall that kept
# the database and a reinstall, the API listens and its rule is gone, and the
# closing box has to say so - which it may only do if it MEASURED it.  A message
# that asserted "nobody can reach the API" from the install path alone would be
# a claim about a machine nobody looked at.
#
# THREE ANSWERS, NOT TWO, and that is the difference from the ssh one.  There it
# is always a question about a rule Windows created, so "open" or "restricted"
# covers it.  Here the rule is ours and may be ABSENT, which is the whole state
# 147 is about - so a missing rule answers "none" rather than being an error.
#
# WHY THIS IS NOT ssh-firewall.ps1 WITH A DIFFERENT PORT, which was the first
# thing tried.  That script TOGGLES a rule somebody else created: installing
# the OpenSSH capability creates OpenSSH-Server-In-TCP and enables it, so the
# question there is only how wide it should be.  NOTHING CREATES A RULE FOR
# 4247.  So this one owns its rule - it makes it, it names it, and -Remove
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
# installation, before the data tree is necessarily complete, and sd.conf no
# longer holds a port at all - APIPORT is an on/off switch (gplsrc/config.c) and
# the port is the constant below.  gplbld/test-apiport-units.py checks that it
# is the same number as SD_API_PORT.
#
# IT DOES NOT CHECK WHETHER SD IS LISTENING, and that is not an oversight: the
# rule outlives any particular run of the service, APIPORT can be commented out
# and back in without touching the firewall, and a rule for a port nothing has
# opened yet admits nothing.  api-firewall says who MAY reach the port; sd.conf
# says whether there is one.

param(
    [switch]$Open,
    [switch]$Restrict,
    [switch]$Remove,
    [switch]$Show,
    [switch]$Retarget,
    [string]$ScopeFile = ''
)

$ErrorActionPreference = 'Stop'

# SD_API_PORT (gplsrc/sddefs.h).  Not a parameter, on purpose - see the header.
$Port = 4247

$ruleName    = 'SD-API-In-TCP'
$displayName = 'SD API (SDClient)'

function Get-ApiRule {
    return (Get-NetFirewallRule -Name $ruleName -ErrorAction SilentlyContinue)
}

# THE PORT THE RULE NAMES, as text ('' when there is no rule).  A rule made by
# an earlier build names 4243; asking it about scope as if it admitted traffic
# to 4247 would be a query that answers wrongly (5.23).
function Get-RulePort($rule) {
    if ($null -eq $rule) { return '' }
    return [string](($rule | Get-NetFirewallPortFilter).LocalPort)
}

function Test-RulePortOk($rule) {
    return ((Get-RulePort $rule) -eq [string]$Port)
}

# ONE PLACE DECIDES OPEN OR SHUT, which is ssh-firewall.ps1's rule and its
# comment says why: two copies of this test invite the failure where one is
# updated and the other is not.  -ScopeFile and the read-back verdict at the
# bottom both come here.
#
# A LIST, NOT A SCALAR - RemoteAddress can hold several entries, so this asks
# whether ANY of them is the unrestricted one rather than comparing a joined
# string.  A missing rule is not open.
function Test-RuleOpen($rule) {
    if ($null -eq $rule) { return $false }
    $addrs = ($rule | Get-NetFirewallAddressFilter).RemoteAddress
    return ($addrs -contains 'Any')
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

try {
    # ANSWERED FIRST, AND BEFORE THE ELEVATION GATE BELOW, because it changes
    # nothing and because a caller that gets no answer at all is worse than one
    # that gets "none": the installer's alternative to a measurement is a guess.
    # The file is written before anything is printed, so a caller reading the
    # file rather than the output cannot be told a rule exists by a line that
    # was produced on the way to failing.
    if ($ScopeFile -ne '') {
        $rule = Get-ApiRule
        # A rule that names another port admits nothing on this one, so it is
        # 'none' - the answer the installer's closing box has to give is whether
        # anyone can reach the API, and with a stale rule nobody can.
        if (($null -eq $rule) -or (-not (Test-RulePortOk $rule))) { $verdict = 'none' }
        elseif (Test-RuleOpen $rule)                              { $verdict = 'open' }
        else                                                      { $verdict = 'restricted' }
        [System.IO.File]::WriteAllText($ScopeFile, $verdict, [System.Text.Encoding]::ASCII)
        Write-Output ("api-firewall: current scope is " + $verdict)
        exit 0
    }

    if ($Show) {
        $rule = Get-ApiRule
        Write-State $rule
        # 03 Sep 26 - AND SAY WHAT IT MEANS, matching ssh-firewall.ps1 -Show.
        # PRE_RELEASE_FIXES 148: "remote.api" with no keyword runs this, and
        # until now an administrator asking who may reach the API got a rule
        # dump and no plain answer.  THREE STATES, because our rule can be
        # ABSENT where ssh's - created by the OpenSSH capability - cannot: a
        # machine that kept its database through a reinstall (147) has a
        # listener and no rule, and "state is OFF at the firewall" is the whole
        # point of saying this.  Test-RuleOpen is the SAME test -ScopeFile and
        # the write-back verdict use, so the three cannot disagree.
        if ($null -eq $rule) {
            Write-Output 'api-firewall: state is OFF at the firewall - no rule, so only this computer may reach the API'
        } elseif (-not (Test-RulePortOk $rule)) {
            Write-Output ('api-firewall: state is OFF at the firewall - the rule is for port ' +
                          (Get-RulePort $rule) + ' and the API is on port ' + $Port +
                          ', so only this computer may reach the API')
        } elseif (Test-RuleOpen $rule) {
            Write-Output 'api-firewall: state is ON - other computers on your network may reach the API'
        } else {
            Write-Output 'api-firewall: state is LOCAL - only this computer may reach the API'
        }
        exit 0
    }

    $modes = @($Open, $Restrict, $Remove, $Retarget) | Where-Object { $_ }
    if ($modes.Count -ne 1) {
        Write-Output 'api-firewall: give exactly one of -Open, -Restrict, -Remove, -Retarget or -Show'
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

    # 01 Oct 26 - -Retarget MOVES THE PORT AND NOTHING ELSE, and that is the
    # whole reason it is not -Open or -Restrict.  An upgrade must not choose a
    # scope (the installer never showed the box, so any scope it chose would be
    # a guess in one direction or the other), but it cannot leave the rule on
    # 4243 either: the listener moves to 4247 by itself, and a rule for the old
    # port would shut a site out of an API it had deliberately opened.  Same
    # sources, same service, new number.  No rule is not an error - a site that
    # never provided the API has nothing to move.
    #
    # THE SCOPE IS READ BEFORE AND AFTER AND THE CALL FAILS IF IT MOVED, for the
    # reason the read-back at the bottom of this file exists: a cmdlet that
    # reports success has not shown the rule says what was asked.
    if ($Retarget) {
        $rule = Get-ApiRule
        if ($null -eq $rule) {
            Write-Output 'api-firewall: no rule, so there is no port to move'
            exit 0
        }
        $before      = Get-RulePort $rule
        $scopeBefore = (@(($rule | Get-NetFirewallAddressFilter).RemoteAddress) | Sort-Object) -join ','
        Write-Output "api-firewall: before - rule is for port $before, RemoteAddress $scopeBefore"
        if ($before -eq [string]$Port) {
            Write-Output "api-firewall: already port $Port - nothing to change"
            exit 0
        }
        # ONLY THE OLD PORT MOVES.  A rule on any other port is not one an
        # earlier build of this product made: it is an administrator's own
        # (the old -Port parameter allowed one).  -Show still says it admits
        # nothing on this port.  (Solo shared this rule name until 1 Oct 26 and
        # now has its own, SD-Solo-API-In-TCP; a rule an older Solo left here is
        # moved to 4247 by this script when it finds it on 4243, and Solo's
        # script adopts it instead only when this product is not installed.)
        if ($before -ne '4243') {
            Write-Output "api-firewall: the rule is for port $before, not the old port 4243 - leaving it alone"
            exit 0
        }
        Set-NetFirewallRule -Name $ruleName -LocalPort $Port -Protocol TCP
        $applied    = Get-ApiRule
        $after      = Get-RulePort $applied
        $scopeAfter = (@(($applied | Get-NetFirewallAddressFilter).RemoteAddress) | Sort-Object) -join ','
        Write-Output "api-firewall: after  - rule is for port $after, RemoteAddress $scopeAfter"
        if ($after -ne [string]$Port -or $scopeAfter -ne $scopeBefore) {
            Write-Output "api-firewall: FAILED - asked to move the rule to port $Port and leave who may reach it alone"
            Write-State $applied
            exit 1
        }
        Write-Output "api-firewall: moved $ruleName from port $before to port $Port; who may reach it is unchanged"
        exit 0
    }

    # ***NO '::1'.  WINDOWS REFUSES ANY IPv6 LOOPBACK LITERAL IN -RemoteAddress***
    # - "An unspecified, multicast, broadcast, or loopback IPv6 address was
    # specified" - and the rule is then LEFT AT RemoteAddress=Any, which is the
    # exact exposure this script exists to prevent.
    #
    # ssh-firewall.ps1 HIT THIS FIRST AND FIXED IT; THIS FILE DID NOT GET THE
    # FIX, and it stayed broken until "remote.api local" ran it in front of the
    # owner on 30 Aug 2026.  Its sibling's comment describes this defect word
    # for word.  Third time in one week that a rule was applied in one file and
    # not the other - see CRED_SET and MODIFYA on close-before-write.
    #
    # LOOPBACK IS NOT FILTERED BY WINDOWS FIREWALL AT ALL, so 127.0.0.1 alone
    # loses nothing: an IPv6 loopback connection is not matched against this
    # rule in the first place.  What the scope governs is off-box traffic.
    $remote = if ($Open) { 'Any' } else { '127.0.0.1' }

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

    # ***THE VERDICT IS GATED ON A READ-BACK, NOT ON HAVING MADE THE CALL.***
    # PRE_RELEASE_FIXES 81.  On 30 Aug 2026 this script printed
    #
    #   Set-NetFirewallRule : An unspecified, multicast, broadcast, or loopback
    #   IPv6 address was specified.
    #   api-firewall: updated SD-API-In-TCP for port 4243   (its port then)
    #   api-firewall: the SD API is reachable FROM THIS MACHINE ONLY
    #     rule: ... RemoteAddress Any
    #
    # - a failure, then two claims of success, then its own evidence
    # contradicting them, then exit 0.  "remote.api local" duly reported "The
    # SD API is now LOCAL" while the port was open to the network.
    #
    # THE THROW/CATCH BELOW WAS SUPPOSED TO PREVENT THAT AND DID NOT.  The CIM
    # error came back NON-TERMINATING despite ErrorActionPreference = 'Stop',
    # so execution simply carried on.  Relying on a cmdlet to throw is
    # therefore not enough, and ssh-firewall.ps1 relies on exactly the same
    # thing - it is given the same gate in the same commit.
    #
    # SO THE RULE IS RE-READ AND COMPARED WITH WHAT WAS ASKED FOR.  This is
    # CLAUDE.md's instrument rule applied to a firewall: a step that did
    # nothing must fail rather than pass, and the state it compared has to be
    # the state on the machine rather than the state it intended to set.
    $applied = Get-ApiRule
    $addrs   = @($applied | Get-NetFirewallAddressFilter).RemoteAddress
    $isOpen  = Test-RuleOpen $applied

    if ($isOpen -ne [bool]$Open) {
        Write-Output ('api-firewall: FAILED - the rule was NOT changed.  Asked for ' +
                      $(if ($Open) { 'Any' } else { $remote }) +
                      ', the rule still reads ' + ($addrs -join ','))
        Write-State $applied
        exit 1
    }

    if ($Open) {
        Write-Output "api-firewall: other computers MAY reach the SD API on port $Port"
    } else {
        Write-Output "api-firewall: the SD API is reachable FROM THIS MACHINE ONLY"
    }

    Write-State $applied
    exit 0
}
catch {
    Write-Output ('api-firewall: FAILED - ' + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    exit 1
}
