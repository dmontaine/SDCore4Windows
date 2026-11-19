# probe-331remote.ps1 - RELEASE_1.1 331 (Linux S.256): the HOST half of the SDSYS-over-the-API sitting.  One API login as sdsys from
# this host to the VM's SD Core, by scram-probe.py (TLS 1.3 + SCRAM, no SD code on the client side), and a verdict on what the VM's
# remote.sdsys api state says must happen.  Sitting plan: .claude/vm-sitting-core-s256-20261116.md steps H1-H5.
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\probe-331remote.ps1 -Vm <VM address> -Expect <state>
#
#   -Expect shut       remote.sdsys api is off (as delivered):           REFUSED with 10174's words
#   -Expect notlisted  it is on for addresses that do not include ours:  REFUSED with 15116's words, naming the address the VM saw
#   -Expect admitted   it is on for our address (or any):                SCRAM VERIFIED and WHO answered inside account sdsys
#
# AN ORDINARY, UNELEVATED PowerShell on the HOST.  It asks for the VM's SDSYS SD password (Read-Host, no echo; its length is printed):
# the door is decided after SCRAM proves the password, so a wrong one (5017) measures nothing and the script says so.  Nothing is changed.
# Exit 0 the expected outcome, 1 a different one, 2 could not run.
#
# START-HISTORY:
# 18 Nov 26  New, for the sitting of 18 Nov (RELEASE_1.1 331), in place of the api_admin_probe.exe witness the s256 sheet asked for:
#            scram-probe.py is already the API client the suites drive.  NOT RUN.
# END-HISTORY

param(
    [Parameter(Mandatory = $true)][string]$Vm,
    [Parameter(Mandatory = $true)][ValidateSet('shut', 'notlisted', 'admitted')][string]$Expect,
    [int]$Port = 4247
)
$ErrorActionPreference = 'Stop'
$Probe = Join-Path $PSScriptRoot 'scram-probe.py'
function Say([string]$s) { Write-Host $s }
function Bail([string]$why) { Say ('CANNOT RUN: ' + $why); Say 'VERDICT: CANNOT RUN'; exit 2 }

Say ('=== probe-331remote ' + (Get-Date -Format s))
Say ('script : ' + $PSCommandPath)
Say ('target : ' + $Vm + ':' + $Port + '   expect: ' + $Expect)
Say ('probe  : ' + $Probe + '   exists: ' + (Test-Path -LiteralPath $Probe))
$py = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $py) { Bail 'python is not on PATH (scram-probe.py is the client)' }
Say ('python : ' + $py.Source)
$ip = $null
if (-not [Net.IPAddress]::TryParse($Vm, [ref]$ip)) { Bail ('-Vm must be an IP address, not ' + $Vm) }
$own = @(Get-NetIPAddress -ErrorAction SilentlyContinue | ForEach-Object { $_.IPAddress })
if ($own -contains $Vm -or $Vm -like '127.*' -or $Vm -eq '::1') { Bail ($Vm + ' is THIS machine - the remote door is measured from another computer (row 344 covers our own addresses)') }
$tcp = New-Object Net.Sockets.TcpClient
try { $tcp.Connect($Vm, $Port); Say ('reach  : ' + $Vm + ':' + $Port + ' accepts a TCP connection') } catch { Bail ('nothing answers at ' + $Vm + ':' + $Port + ' - is the VM''s API open to the network (remote.api on)?') } finally { $tcp.Close() }

$ss = Read-Host -AsSecureString 'The VM''s SDSYS SD password'
$b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ss)
try { $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
if (-not $pw) { Bail 'no password typed' }
Say ('password: ' + $pw.Length + ' characters (not shown)')

$argText = '"' + $Probe + '" --user sdsys --account sdsys --host ' + $Vm + ' --port ' + $Port + ' -- WHO'
Say ''
Say ('  $ ' + $py.Source + ' ' + $argText + '   [SD_SCRAM_PASSWORD: not shown]')
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = $py.Source; $psi.Arguments = $argText; $psi.UseShellExecute = $false
$psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['SD_SCRAM_PASSWORD'] = $pw; $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
$p = [Diagnostics.Process]::Start($psi)
$o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
if (-not $p.WaitForExit(90000)) { $null = & taskkill.exe /PID $p.Id /T /F 2>$null; Say '    TIMED OUT after 90 s - killed' } else { Say ('    exit ' + $p.ExitCode) }
$text = (($o.Result) + ($e.Result)) -replace "`r", ''
if ($text.Contains($pw)) { $text = $text.Replace($pw, '********'); Say '    (the password appeared in the output and is masked)' }
foreach ($l in ($text -split "`n")) { if ($l.Trim()) { Say ('    | ' + $l) } }

$refused  = $text -match '(?m)^SCRAM: login REFUSED at request'
$verified = $text -match '(?m)^SCRAM: server signature VERIFIED'
$is10174  = $text -match 'SDSYS may be reached through the API from another computer only'
$is15116  = $text -match 'SDSYS may use the API from another computer only from an address'
$is12992  = $text -match 'SDSYS may use the API from this computer only'
$wrong    = $text -match 'Invalid username or password'
$whoSdsys = $text -match '(?im)^\s*\|?\s*\d+\s+sdsys\b'
Say ''
Say ('read: refused=' + $refused + ' verified=' + $verified + ' 10174=' + $is10174 + ' 15116=' + $is15116 + ' 12992=' + $is12992 + ' 5017=' + $wrong + ' WHO-in-sdsys=' + $whoSdsys)
if ($wrong) { Bail 'the password was refused (5017): the door is decided after it, so nothing was measured' }
if ($is12992) { Say 'VERDICT: FAIL - the VM treated this host as ITSELF (12992): wrong -Vm address, or the VM saw a loopback peer'; exit 1 }

$ok = switch ($Expect) {
    'shut'      { $refused -and $is10174 -and -not $verified }
    'notlisted' { $refused -and $is15116 -and -not $verified }
    'admitted'  { $verified -and -not $refused -and $whoSdsys }
}
if ($Expect -eq 'notlisted' -and $is15116) {
    $m = [regex]::Match($text, 'and (\S+) is not one of them')
    if ($m.Success) { Say ('the VM saw this host as ' + $m.Groups[1].Value + ' - use that address (or its /24) in remote.sdsys api on') }
}
if ($ok) { Say ('VERDICT: PASS - ' + $Expect + ' as expected'); exit 0 }
Say ('VERDICT: FAIL - expected ' + $Expect + '; see the output above'); exit 1
