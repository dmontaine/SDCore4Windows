# probe-sshfirewall.ps1 - does the installer actually scope who may reach ssh?
# PROJECT_STATUS.md section 5.9 and section 7 step 3.
#
#   powershell -ExecutionPolicy Bypass -File probe-sshfirewall.ps1
#
# ELEVATED.  Reading firewall rules does not need it; running ssh-firewall.ps1's
# change path does, and this refuses rather than reporting a half measurement.
#
# Exit 0 the scoping is correct, 1 it is not, 2 it could not be measured.
#
# WHY IT EXISTS.  24 Aug 2026, on VM "Windows 11 - sshRemoteTest": the FIRST
# install ever performed on a machine with no OpenSSH server showed that
# ssh-firewall.ps1 -Installed -Restrict has NEVER worked.  It passed
# @('127.0.0.1','::1') to Set-NetFirewallRule, Windows rejects ANY IPv6 loopback
# literal there - "An unspecified, multicast, broadcast, or loopback IPv6
# address was specified" - the call threw, and the rule was left at
# RemoteAddress=Any.  Port 22 open to the local network on every such install,
# which is the exposure section 5.9 exists to prevent.
#
# IT WAS INVISIBLE FOR EIGHT DAYS BECAUSE THE STEP NEVER RAN.  ApplySshFirewall
# exits early unless SshWasAbsent, and every machine it had ever run on already
# had sshd.  A machine WITHOUT ssh is the only rig that can see this, which is
# why this probe exists rather than a line in a verifier that runs anywhere.
#
# THE ADDRESS-FAMILY TRAP, recorded because it produced a false reading here on
# the first attempt.  New-Object Net.Sockets.TcpClient defaults to AF_INET and
# CANNOT dial an IPv6 literal at all - it throws "None of the discovered or
# specified addresses match the socket address family", which looks exactly like
# "::1 is blocked" and is not.  Every dial below names its address family.

# -Expect SAYS WHICH ANSWER IS THE RIGHT ONE, AND IT IS REQUIRED THINKING.
# RemoteAddress=Any is CORRECT when the sshremote task was ticked and is the
# 24 Aug defect when it was not - the rule alone cannot tell you which, and a
# probe that flags both as failure is one people learn to ignore.  So the
# caller states what was chosen in the wizard and this asserts against it.
#
# ***AND IT IS MANDATORY, WHICH IT WAS NOT UNTIL 26 Aug 2026. THE DEFAULT WAS
# THE WHOLE BUG.*** "Required thinking" was written above a parameter that
# defaulted to one of its own two answers, so omitting it did not prompt - it
# silently asserted "Restricted".
#
# WHAT THAT COST, on VM VIRTUAL at 23:36:11 on 25 Aug 2026: the probe was run
# bare on a guest where sshremote HAD been ticked, compared Any against
# Restricted, and printed "[FAIL] ... port 22 is open to the local network.
# This is the 24 Aug 2026 defect" - naming a defect that was not there, on a
# correct installer.
#
# AND IT WAS NOT ONLY A WRONG VERDICT, IT CHANGED THE MACHINE.  The recovery
# section runs ssh-firewall.ps1 -Installed -Restrict, which -Expect Open
# deliberately SKIPS "rather than undoing the state it is measuring".  Reading
# the default undid the very state the next step of the run book needed.
#
# A parameter that decides which of two opposite outcomes is a pass must not
# have a default.  Mandatory prompts; a default guesses.
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Restricted', 'Open')]
    [string]$Expect
)

$ErrorActionPreference = 'Continue'

$rule = 'OpenSSH-Server-In-TCP'
$fail = 0
$blocked = 0

function Head([string]$t) { Write-Host ''; Write-Host ('== ' + $t + ' ' + ('=' * [Math]::Max(1, 62 - $t.Length))) }
function Bad ([string]$t) { $script:fail++;    Write-Host ('  [FAIL] ' + $t) }
function Stop2([string]$t) { $script:blocked++; Write-Host ('  [----] ' + $t) }
function Ok  ([string]$t) { Write-Host ('  [ok]   ' + $t) }

function RemoteAddressNow {
    $r = Get-NetFirewallRule -Name $rule -ErrorAction SilentlyContinue
    if (-not $r) { return $null }
    (($r | Get-NetFirewallAddressFilter).RemoteAddress -join ',')
}

function Dial([string]$addr, [string]$fam) {
    $af = if ($fam -eq 'v6') { [Net.Sockets.AddressFamily]::InterNetworkV6 }
          else                { [Net.Sockets.AddressFamily]::InterNetwork }
    $c = New-Object Net.Sockets.TcpClient($af)
    try {
        $iar = $c.BeginConnect([Net.IPAddress]::Parse($addr), 22, $null, $null)
        $ok  = $iar.AsyncWaitHandle.WaitOne(4000, $false)
        if ($ok -and $c.Connected) { $c.EndConnect($iar); $c.Close(); return 'REACHABLE' }
        $c.Close(); return 'NOT reachable'
    } catch { $c.Close(); return ('NOT reachable: ' + $_.Exception.InnerException.Message) }
}

Head 'What this run actually measured'
Write-Host ('  computer   : ' + $env:COMPUTERNAME)
Write-Host ('  local time : ' + (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
$elev = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ('  elevated   : ' + $elev)
if (-not $elev) { Stop2 'not elevated - the change path cannot be exercised'; }

Head 'Premise - ssh must be present, or there is nothing to scope'
$cap = Get-WindowsCapability -Online -Name 'OpenSSH.Server~~~~0.0.1.0' -ErrorAction SilentlyContinue
if (-not $cap) { Stop2 'OpenSSH.Server capability query returned NOTHING - instrument failure, not a result' }
else {
    Write-Host ('  OpenSSH.Server : ' + $cap.State)
    if ($cap.State -ne 'Installed') { Stop2 'OpenSSH.Server is not installed - nothing to measure' }
}
$svc = Get-Service -Name sshd -ErrorAction SilentlyContinue
if ($svc) { Write-Host ('  sshd           : ' + $svc.Status) } else { Stop2 'no sshd service - nothing to measure' }

$listen = @(Get-NetTCPConnection -LocalPort 22 -State Listen -ErrorAction SilentlyContinue)
if ($listen.Count -eq 0) { Stop2 'NOTHING is listening on port 22 - every reachability line below would be meaningless' }
else { foreach ($l in $listen) { Write-Host ('  listening      : ' + $l.LocalAddress + ':' + $l.LocalPort) } }

if ($blocked -gt 0) {
    Head 'VERDICT'
    Write-Host '  probe-sshfirewall: COULD NOT MEASURE - see the [----] lines above.'
    Write-Host '  This is NOT a pass. A run that measured nothing must not read as green.'
    exit 2
}

Head 'The rule as the installer left it'
$now = RemoteAddressNow
if ($null -eq $now) { Bad ('rule ' + $rule + ' does not exist') }
else {
    $r = Get-NetFirewallRule -Name $rule
    Write-Host ('  Enabled       : ' + $r.Enabled + '   Profile: ' + $r.Profile)
    Write-Host ('  RemoteAddress : ' + $now)
    Write-Host ('  expected      : ' + $Expect + '  (from -Expect, i.e. what was chosen in the wizard)')
    if ($Expect -eq 'Open') {
        if ($now -match 'Any') {
            Ok 'RemoteAddress is Any, and the sshremote task was ticked - correct'
        } else {
            Bad ('sshremote was TICKED but RemoteAddress is ' + $now +
                 ' - the machine is MORE restricted than asked for, and other computers cannot reach ssh')
        }
    } else {
        if ($now -match 'Any') {
            Bad 'sshremote was NOT ticked but RemoteAddress is Any - port 22 is open to the local network. This is the 24 Aug 2026 defect'
        } else {
            Ok ('RemoteAddress is scoped to ' + $now)
        }
    }
}

Head 'ssh-firewall.ps1 -Show, the shipped instrument'
$fw = Join-Path $env:ProgramFiles 'SD\ssh-firewall.ps1'
if (-not (Test-Path -LiteralPath $fw)) { Bad ('not installed at ' + $fw) }
else {
    Write-Host ('  running: powershell -File "' + $fw + '" -Show')
    & powershell.exe -ExecutionPolicy Bypass -File $fw -Show 2>&1 | ForEach-Object { Write-Host ('    | ' + $_) }
    Write-Host ('  exit code : ' + $LASTEXITCODE)
}

Head 'Can the documented recovery reach the restricted state at all'
if ($Expect -eq 'Open') {
    Write-Host '  SKIPPED, deliberately. -Installed -Restrict would scope the rule to'
    Write-Host '  loopback, which is the OPPOSITE of what was asked for on this machine,'
    Write-Host '  and this probe does not undo the thing it is measuring. The restrict'
    Write-Host '  path is exercised by an -Expect Restricted run on its own guest.'
}
elseif (Test-Path -LiteralPath $fw) {
    Write-Host ('  running: powershell -File "' + $fw + '" -Installed -Restrict')
    & powershell.exe -ExecutionPolicy Bypass -File $fw -Installed -Restrict 2>&1 | ForEach-Object { Write-Host ('    | ' + $_) }
    $rc = $LASTEXITCODE
    Write-Host ('  exit code : ' + $rc + '  (0 applied, 1 failed, 2 refused)')
    $after = RemoteAddressNow
    Write-Host ('  RemoteAddress after : ' + $after)
    if ($rc -ne 0) {
        Bad ('-Installed -Restrict exited ' + $rc + ' - the restricted state is UNREACHABLE by the documented route')
    } elseif ($after -match 'Any') {
        Bad 'it exited 0 but RemoteAddress is still Any - success wording without the success'
    } else {
        Ok ('recovery works: RemoteAddress is now ' + $after)
    }
}

Head 'Local use must survive the restriction'
Write-Host '  sshd binds IPv6 as well as IPv4, so BOTH families are dialled, each'
Write-Host '  with a socket of the matching family.'
$v4 = Dial '127.0.0.1' 'v4'
$v6 = Dial '::1'       'v6'
Write-Host ('  127.0.0.1:22 via AF_INET  : ' + $v4)
Write-Host ('  ::1:22       via AF_INET6 : ' + $v6)
if ($v4 -ne 'REACHABLE') { Bad 'IPv4 loopback ssh is not reachable - the restriction broke local use' }
if ($v6 -ne 'REACHABLE') { Bad 'IPv6 loopback ssh is not reachable - dropping ::1 from the rule was NOT safe' }
if ($v4 -eq 'REACHABLE' -and $v6 -eq 'REACHABLE') { Ok 'both loopback families still reachable' }

Head 'WHAT THIS PROBE CANNOT TELL YOU'
Write-Host '  It cannot prove a REMOTE machine is blocked. Windows does not filter'
Write-Host '  traffic that never leaves the host, so dialling this machine on its own'
Write-Host '  LAN address proves nothing, and a VirtualBox NAT port-forward proves'
Write-Host '  less than nothing - measured 24 Aug 2026, the NAT engine completes the'
Write-Host '  handshake itself and no connection ever reaches sshd. That control needs'
Write-Host '  a BRIDGED NIC and a dial from another machine. Section 7 step 2.'

Head 'VERDICT'
if ($fail -eq 0) {
    Write-Host '  probe-sshfirewall: PASSED - ssh is scoped as intended and local use survives.'
    exit 0
} else {
    Write-Host ('  probe-sshfirewall: FAILED - ' + $fail + ' check(s) failed. See the [FAIL] lines.')
    exit 1
}
