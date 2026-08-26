# probe-sshremote.ps1 - does the ssh scoping actually block a REMOTE machine?
# PROJECT_STATUS.md "START HERE" item 4, and section 7 step 3's last bullet.
#
#   powershell -ExecutionPolicy Bypass -File probe-sshremote.ps1 `
#       -Guest 10.0.0.143 -Expect Blocked
#
# RUN ON THE HOST, dialing the GUEST.  Needs no elevation: it opens outbound
# TCP and reads the ARP table, nothing more.  probe-sshfirewall.ps1 is the
# other half and runs ON the guest, where it reads the rule and dials loopback.
#
# Exit 0 the expectation held, 1 it did not, 2 it could not be measured.
#
# ============================================================================
# WHY THIS EXISTS: A CONFIGURATION READING HAS BEEN STANDING IN FOR A
# BEHAVIOURAL ONE
# ============================================================================
#
# ssh-firewall.ps1 sets RemoteAddress=127.0.0.1 and probe-sshfirewall.ps1 reads
# it back.  That reading is trustworthy - it is how the 24 Aug 2026 defect was
# caught, when the rule said Any.  What NOBODY HAS EVER CONFIRMED is that a
# rule reading 127.0.0.1 actually REFUSES a connection from another machine.
#
# Every ssh reachability dial in this project's record goes to LOOPBACK.
# Searched 26 Aug 2026: no dial to port 22 from a non-loopback address exists,
# and that search is a working instrument because it finds the remote API dials
# (10.0.0.143 -> 10.0.0.3) in four places.
#
# ============================================================================
# THE CONTROL IS THE POINT, NOT THE DIAL
# ============================================================================
#
# A refused dial proves nothing on its own.  A guest that is switched off,
# unreachable, or not running sshd refuses IDENTICALLY to one whose firewall is
# doing its job.  That is this project's standing null-case failure and it is
# why -Expect is required rather than defaulted:
#
#   -Expect Open     the sshremote task WAS ticked, RemoteAddress=Any.
#                    The dial MUST SUCCEED.  ***RUN THIS ONE FIRST.***  It is
#                    the proof that the guest is up, sshd is listening, and the
#                    network path works - without which the Blocked run below
#                    is not evidence of anything.
#   -Expect Blocked  the sshremote task was NOT ticked, RemoteAddress=127.0.0.1.
#                    The dial MUST FAIL.
#
# A Blocked run that has not been preceded by an Open run against the same
# guest SAYS SO in its own output and does not claim to have proved the
# scoping.  -ControlPort gives a second, independent reachability witness.
#
# ============================================================================
# THE ADDRESS-FAMILY TRAP, inherited from probe-sshfirewall.ps1
# ============================================================================
#
# New-Object Net.Sockets.TcpClient defaults to AF_INET and CANNOT dial an IPv6
# literal - it throws "None of the discovered or specified addresses match the
# socket address family", which reads exactly like "blocked" and is not.  Every
# dial here names its family and prints it.

[CmdletBinding()]
param(
    # The guest's address on the bridged segment.  No default: a wrong guess
    # would dial something else entirely and report on it.
    [Parameter(Mandatory = $true)]
    [string] $Guest,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Open', 'Blocked')]
    [string] $Expect,

    [int] $Port = 22,

    # A port on the SAME guest that is expected to answer regardless of the ssh
    # rule, giving reachability evidence independent of the thing under test.
    # 0 disables it, and the run then says the witness was not taken.
    [int] $ControlPort = 0,

    [int] $TimeoutMs = 4000,

    [switch] $SelfTest
)

$ErrorActionPreference = 'Continue'

$script:rows = @()
function Row([bool]$ok, [string]$what, [string]$detail) {
    $script:rows += [pscustomobject]@{ Ok = $ok; What = $what; Detail = $detail }
    Write-Host ("  [{0}] {1}{2}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $what,
                $(if ($detail) { "  $detail" } else { '' }))
}

# ONE DIAL, AND IT REPORTS WHICH FAMILY IT USED AND HOW LONG IT TOOK.
# A refusal and a timeout are different answers: a firewall DROP produces a
# timeout, a closed port produces an immediate RST.  Both mean "did not
# connect", but printing which one lets a reader tell a blocking rule from a
# stopped sshd.
function Dial([string]$addr, [int]$port, [int]$timeoutMs) {
    $r = [pscustomobject]@{
        Connected = $false; Family = 'unknown'; Ms = 0; Detail = ''
    }
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $ip = $null
    if (-not [Net.IPAddress]::TryParse($addr, [ref]$ip)) {
        $r.Detail = "not an IP literal - this probe does not resolve names"
        return $r
    }
    $r.Family = $ip.AddressFamily.ToString()
    $c = New-Object Net.Sockets.TcpClient($ip.AddressFamily)
    try {
        $iar = $c.BeginConnect($ip, $port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($timeoutMs, $false)) {
            try {
                $c.EndConnect($iar)
                $r.Connected = $c.Connected
                if (-not $r.Connected) { $r.Detail = 'refused' }
            } catch {
                $r.Detail = 'refused: ' + $_.Exception.InnerException.Message
            }
        } else {
            $r.Detail = "no answer within ${timeoutMs}ms (a DROP looks like this)"
        }
    } catch {
        $r.Detail = 'dial threw: ' + $_.Exception.Message
    } finally {
        $sw.Stop(); $r.Ms = $sw.ElapsedMilliseconds
        try { $c.Close() } catch { }
    }
    return $r
}

# ---------------------------------------------------------------------------
# SELF-TEST.  A dialer that has only ever been pointed at the real guest can
# not be known to work - the same argument that put --self-test on
# check-client-sync.py.  These targets are local and need no guest.
# ---------------------------------------------------------------------------
if ($SelfTest) {
    Write-Host '=== self-test: does Dial tell the three answers apart? ==='
    $ok = 0; $total = 0

    # A port nothing listens on.  THE LABEL SAYS "does not connect", NOT
    # "refuses", and that is a correction rather than pedantry: the first
    # version claimed refusal and the run printed "no answer within 1500ms" -
    # this machine DROPS rather than sending RST, so the case never measured
    # the refusal it named.  Assert only what is asserted.
    #
    # AND IT IS OPERATIONALLY USEFUL: on this network a blocked dial TIMES OUT.
    # Expect the real -Expect Blocked run against the guest to sit for the full
    # timeout rather than answer at once, and do not read the delay as a hang.
    $total++
    $d = Dial '127.0.0.1' 9 1500
    $good = (-not $d.Connected)
    if ($good) { $ok++ }
    Write-Host ("  [{0}] closed local port does not connect  family={1} {2}ms {3}" -f `
        $(if ($good) { 'PASS' } else { 'FAIL' }), $d.Family, $d.Ms, $d.Detail)

    # A port that IS listening here.  Found rather than assumed; if there is
    # none the case is SKIPPED out loud rather than silently passing.
    $listen = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
                Where-Object { $_.LocalAddress -eq '127.0.0.1' -or $_.LocalAddress -eq '0.0.0.0' } |
                Select-Object -First 1)
    if ($listen.Count -eq 1) {
        $total++
        $p = $listen[0].LocalPort
        $d = Dial '127.0.0.1' $p 1500
        $good = $d.Connected
        if ($good) { $ok++ }
        Write-Host ("  [{0}] open local port {1,-5} connects  family={2} {3}ms" -f `
            $(if ($good) { 'PASS' } else { 'FAIL' }), $p, $d.Family, $d.Ms)
    } else {
        Write-Host '  [SKIP] no listening port found to dial - reachability case not taken'
    }

    # An address in a range nothing answers: must TIME OUT, not refuse, and
    # must not be reported as a connection.
    $total++
    $d = Dial '192.0.2.1' 22 1200      # TEST-NET-1, RFC 5737, never routed
    $good = (-not $d.Connected)
    if ($good) { $ok++ }
    Write-Host ("  [{0}] unrouted address does not connect  {1}ms {2}" -f `
        $(if ($good) { 'PASS' } else { 'FAIL' }), $d.Ms, $d.Detail)

    # AF_INET6 is named, not defaulted.
    $total++
    $d = Dial '::1' 9 1500
    $good = ($d.Family -eq 'InterNetworkV6')
    if ($good) { $ok++ }
    Write-Host ("  [{0}] IPv6 literal dialed as {1} (not a family error)" -f `
        $(if ($good) { 'PASS' } else { 'FAIL' }), $d.Family)

    Write-Host ''
    Write-Host ("  $ok of $total self-test cases passed.")
    if ($ok -ne $total) { exit 1 }
    exit 0
}

Write-Host ''
Write-Host '=== what this run is measuring ==================================='
Write-Host ("  host      : " + ((Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
    Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
    Select-Object -ExpandProperty IPAddress) -join ', '))
Write-Host ("  guest     : " + $Guest)
Write-Host ("  port      : " + $Port)
Write-Host ("  expecting : " + $Expect)
Write-Host ("  control   : " + $(if ($ControlPort -gt 0) { "port $ControlPort on the same guest" } else { 'NONE - see the closing note' }))
Write-Host ("  timeout   : " + $TimeoutMs + "ms")

# --- the ARP witness -------------------------------------------------------
# The record's own advice for this rig: "the host ARP entry carrying the VM's
# own MAC is how to tell it is working before blaming anything else."
Write-Host ''
Write-Host '=== [1] is the guest even there? ================================='
$arp = @(Get-NetNeighbor -IPAddress $Guest -ErrorAction SilentlyContinue |
         Where-Object { $_.State -ne 'Unreachable' })
if ($arp.Count -gt 0) {
    Write-Host ("  ARP: " + $Guest + " -> " + ($arp[0].LinkLayerAddress) + "  state " + $arp[0].State)
} else {
    Write-Host ("  ARP: no usable neighbour entry for " + $Guest)
}

if ($ControlPort -gt 0) {
    $cd = Dial $Guest $ControlPort $TimeoutMs
    Write-Host ("  control dial " + $Guest + ":" + $ControlPort + " -> " +
                $(if ($cd.Connected) { 'REACHABLE' } else { 'no answer' }) +
                "  family=" + $cd.Family + " " + $cd.Ms + "ms " + $cd.Detail)
    if (-not $cd.Connected -and $Expect -eq 'Blocked') {
        Write-Host ''
        Write-Host '  CANNOT RUN - the control port did not answer either, so a blocked'
        Write-Host '  ssh dial would prove nothing about the firewall.  Bring the guest'
        Write-Host '  up, or drop -ControlPort and rely on an -Expect Open run instead.'
        exit 2
    }
}

Write-Host ''
Write-Host '=== [2] the dial under test ======================================'
$d = Dial $Guest $Port $TimeoutMs
Write-Host ("  " + $Guest + ":" + $Port + " family=" + $d.Family + "  " + $d.Ms + "ms")
Write-Host ("  result: " + $(if ($d.Connected) { 'CONNECTED' } else { 'did not connect - ' + $d.Detail }))

if ($d.Family -eq 'unknown') {
    Write-Host ''
    Write-Host '  CANNOT RUN - ' + $d.Detail
    exit 2
}

if ($Expect -eq 'Open') {
    Row $d.Connected 'ssh is reachable from this machine (sshremote WAS ticked)' ''
} else {
    Row (-not $d.Connected) 'ssh is REFUSED from this machine (sshremote was NOT ticked)' ''
}

Write-Host ''
Write-Host '=== summary ======================================================'
$bad = @($script:rows | Where-Object { -not $_.Ok })
Write-Host ("  " + $script:rows.Count + " checked, " + $bad.Count + " failed")
Write-Host ''

if ($bad.Count -gt 0) {
    Write-Host 'probe-sshremote: FAILED - the expectation did not hold.'
    exit 1
}

if ($Expect -eq 'Blocked' -and $ControlPort -le 0) {
    Write-Host 'probe-sshremote: the dial was refused, AND THAT IS NOT YET A PROOF.'
    Write-Host '  No control was taken, so an unreachable guest is indistinguishable'
    Write-Host '  from a working firewall rule.  Re-run against the same guest with'
    Write-Host '  sshremote TICKED and -Expect Open, or pass -ControlPort.'
    exit 0
}

Write-Host 'probe-sshremote: PASSED - the expectation held, with a reachability'
Write-Host '  witness, so the result is about the firewall rule and not the rig.'
exit 0
