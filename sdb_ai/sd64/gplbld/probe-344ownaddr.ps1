# probe-344ownaddr.ps1 - RELEASE_1.1 344 (Linux S.264): an API login as SDSYS that arrives at one of THIS MACHINE'S OWN addresses is
# this computer, so it meets the local door (12992, "SDSYS may use the API from this computer only ...") and NEVER remote.sdsys api's
# list (10174, "SDSYS may be reached through the API from another computer only when ...").  apisrvr's K$OWN.ADDR test.
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\probe-344ownaddr.ps1
#
# AN ORDINARY, UNELEVATED PowerShell on the HOST (SD Core installed and current, the API open to the network).  It asks for SDSYS's SD
# password (Read-Host, no echo; only its length is printed): the door is decided AFTER SCRAM proves it, so a wrong password measures
# nothing (the probe then says "Invalid username or password" and this script refuses).  Nothing is changed on the system.
#
# For 127.0.0.1 (the control) and for every IPv4 address of this machine that is up and not link-local, one scram-probe.py login as
# sdsys to port 4247.  PASS for an address: "SCRAM: login REFUSED at request" AND 12992's words AND NOT 10174's.  The audit line
# "api refused user=sdsys reason=sdsys API session opened by ... from this machine" is shown when the audit trail is readable.
# What would falsify 344: an own LAN address answered with 10174 (it was treated as another computer).
# Exit 0 every address PASS, 1 a FAIL, 2 could not run (no python, no address, the control did not behave, the password was wrong).
#
# START-HISTORY:
# 18 Nov 26  New, for the sitting of 18 Nov (RELEASE_1.1 344).  NOT RUN.
# END-HISTORY

$ErrorActionPreference = 'Stop'
$Gplbld = $PSScriptRoot
$Probe  = Join-Path $Gplbld 'scram-probe.py'
$Audit  = Join-Path $env:ProgramData 'SD\sdsys\audit'
$Rx12992 = 'SDSYS may use the API from this computer only'
$Rx10174 = 'SDSYS may be reached through the API from another computer only'
$Rx5017  = 'Invalid username or password'

function Say([string]$s) { Write-Host $s }
function Bail([string]$why) { Say ('CANNOT RUN: ' + $why); Say 'VERDICT: CANNOT RUN'; exit 2 }

Say ('=== probe-344ownaddr ' + (Get-Date -Format s))
Say ('script : ' + $PSCommandPath)
Say ('probe  : ' + $Probe + '   exists: ' + (Test-Path -LiteralPath $Probe))
$py = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $py) { Bail 'python is not on PATH (scram-probe.py is the client)' }
Say ('python : ' + $py.Source)
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if ((New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Bail 'this PowerShell is elevated; use an ordinary one (the client is an ordinary program)' }

Say ''
Say '--- assert-current ---'
& (Join-Path $Gplbld 'assert-current.ps1') | ForEach-Object { Say ('  ' + $_) }
if ($LASTEXITCODE -ne 0) { Bail 'assert-current refuses - the installed SD does not match source' }

$own = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
         Where-Object { $_.IPAddress -ne '127.0.0.1' -and $_.IPAddress -notlike '169.254.*' -and $_.AddressState -eq 'Preferred' } |
         Sort-Object IPAddress | ForEach-Object { [pscustomobject]@{ Ip = $_.IPAddress; If = $_.InterfaceAlias } })
Say ''
Say ('this machine''s own IPv4 addresses (up, not link-local): ' + $(if ($own.Count) { ($own | ForEach-Object { $_.Ip + ' (' + $_.If + ')' }) -join ', ' } else { 'NONE' }))
if ($own.Count -eq 0) { Bail 'no own address besides loopback - nothing to measure' }

$ss = Read-Host -AsSecureString 'SDSYS''s SD password'
$b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
if (-not $pw) { Bail 'no password typed' }
Say ('password: ' + $pw.Length + ' characters (not shown)')

function Read-AuditTail {
    try {
        $fs = [IO.File]::Open($Audit, 'Open', 'Read', 'ReadWrite')
        try { return (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Close() }
    } catch { return $null }
}
function Invoke-Probe([string]$HostIp) {
    $argText = '"' + $Probe + '" --user sdsys --account sdsys --host ' + $HostIp + ' --port 4247 -- WHO'
    Say ''
    Say ('  $ ' + $py.Source + ' ' + $argText + '   [SD_SCRAM_PASSWORD: SDSYS''s, not shown]')
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $py.Source; $psi.Arguments = $argText; $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['SD_SCRAM_PASSWORD'] = $pw; $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
    if (-not $p.WaitForExit(90000)) { $null = & taskkill.exe /PID $p.Id /T /F 2>$null; Say '    TIMED OUT after 90 s - killed' } else { Say ('    exit ' + $p.ExitCode) }
    $text = (($o.Result) + ($e.Result)) -replace "`r", ''
    if ($pw -and $text.Contains($pw)) { $text = $text.Replace($pw, '********'); Say '    (the password appeared in the output and is masked)' }
    foreach ($l in ($text -split "`n")) { if ($l.Trim()) { Say ('    | ' + $l) } }
    return $text
}
function Classify([string]$t) {
    $refused = $t -match '(?m)^SCRAM: login REFUSED at request'
    return [pscustomobject]@{ Refused = $refused; Is12992 = ($t -match $Rx12992); Is10174 = ($t -match $Rx10174); Wrong = ($t -match $Rx5017); Verified = ($t -match 'server signature VERIFIED') }
}

$before = Read-AuditTail
Say ''
Say ('audit trail ' + $Audit + ': ' + $(if ($null -eq $before) { 'NOT READABLE from this shell (the client''s words are the evidence)' } else { 'readable, ' + $before.Length + ' characters' }))

Say ''
Say '=== control: 127.0.0.1 (loopback is this computer; with no local.sdsys api user listed it must be 12992)'
$c = Classify (Invoke-Probe '127.0.0.1')
if ($c.Wrong) { Bail 'the SDSYS password was refused (5017) - the door is decided after the password, so nothing can be measured; run again' }
if ($c.Verified) { Bail 'SDSYS was ADMITTED on loopback - a local.sdsys api user is listed? this probe expects the delivered state (none)' }
if (-not ($c.Refused -and $c.Is12992 -and -not $c.Is10174)) { Bail 'the loopback control did not answer 12992 - see its output; the addresses below would prove nothing' }
Say '  control OK: loopback refused with 12992'

$fails = 0; $passes = 0
foreach ($a in $own) {
    Say ''
    Say ('=== ' + $a.Ip + ' (' + $a.If + ') - an own address: must be the local door (12992), never the remote list (10174)')
    $r = Classify (Invoke-Probe $a.Ip)
    if ($r.Refused -and $r.Is12992 -and -not $r.Is10174 -and -not $r.Verified) { Say ('  PASS 344: ' + $a.Ip + ' refused with 12992, not 10174'); $passes++ }
    elseif ($r.Is10174) { Say ('  FAIL 344: ' + $a.Ip + ' answered 10174 - treated as ANOTHER computer'); $fails++ }
    elseif ($r.Verified) { Say ('  FAIL 344: ' + $a.Ip + ' ADMITTED sdsys'); $fails++ }
    else { Say ('  FAIL 344: ' + $a.Ip + ' - neither 12992 nor 10174 (see the output: is the API listening on this address?)'); $fails++ }
}

$after = Read-AuditTail
if ($null -ne $before -and $null -ne $after -and $after.Length -ge $before.Length) {
    Say ''
    Say '--- audit lines since the start that name sdsys ---'
    $new = @($after.Substring($before.Length) -split "`n" | Where-Object { $_ -match 'sdsys' } | ForEach-Object { $_.TrimEnd() })
    if ($new.Count) { $new | ForEach-Object { Say ('  | ' + $_) } } else { Say '  | (none)' }
}

Say ''
Say ('=== ' + $passes + ' PASS, ' + $fails + ' FAIL over ' + $own.Count + ' own address(es), loopback control OK')
if ($fails) { Say 'VERDICT: FAIL'; exit 1 }
Say 'VERDICT: PASS - every own address met the local door'
exit 0
