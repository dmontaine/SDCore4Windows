# probe-failaudit.ps1 - is a REFUSED API login written to the audit trail when the
# client drops the connection during the server's three-second failed-login delay?
#
#   powershell -ExecutionPolicy Bypass -File <repo>\sdb_ai\sd64\gplbld\probe-failaudit.ps1 [-Port 4249] [-AuditFile <path>]
#
# WHY IT EXISTS.  Linux's release witness found (4 Oct 2026, mail 2026-10-04T1641) that
# apisrvr's scram.bad.cred does "sleep 3" BEFORE it goes to exit.vb.scram.fail, the one
# place a refused SCRAM login is audited, and that a client which drops during the
# sleep ends the process first: 5 of 5 early drops wrote nothing on Linux.  Both Windows
# apisrvr copies have the same order; whether the PROCESS survives a client drop here is a
# question about sdwind and the socket, which only a run can answer.
#
# THE METHOD, Linux's: count "API REFUSED user=<name>" lines in the audit file, start
# scram-probe.py with a WRONG password (by default for a name that does not exist: an
# unknown account goes to scram.bad.cred like a wrong password, refused at request 47; pass
# -Name <a real account> to take the request-48 path instead), kill the
# client K seconds later, wait, count again.  A CONTROL run first lets the client wait out
# the delay; it must add exactly one line, or nothing below means anything.
#
# THE INSTRUMENT PRINTS WHAT IT DID: the port, the audit file and its size, the name, the
# exact probe command line, the count before and after every run, and how long each client
# really lived.  It REFUSES THE NULL CASES - nothing listening, an unreadable audit file, a
# control that did not audit, a client that was already gone before the kill - and exits 2
# saying so rather than reporting a result.
#
# Exit 0 every early drop was audited, 1 at least one was NOT (the defect is present),
# 2 refused before a measurement was made.
#
# Solo: -Port 4249 and the default -AuditFile (the user's own tree).  The full product:
# -Port 4247 -AuditFile C:\ProgramData\SD\sdsys\audit, which an ordinary user cannot read,
# so run it from an ELEVATED PowerShell.  No password, key or token is used: the probe's
# password is a random string that matches no account.

param(
    [int]$Port = 4249,
    [string]$AuditFile = (Join-Path $env:USERPROFILE 'SDCoreSolo\sdsys\audit'),
    [string]$Name = ('zzfailaudit' + (Get-Random -Minimum 1000 -Maximum 9999))
)

$ErrorActionPreference = 'Stop'
# A fixed list, not a parameter: "-File x.ps1 -KillAfter a,b" binds only the first (trap).
$KillAfter = @(0.6, 1.0, 1.5, 2.0, 2.5)
$WaitAfter = 8

$Probe = Join-Path $PSScriptRoot 'scram-probe.py'
$py = Get-Command py.exe -ErrorAction SilentlyContinue
$script:out = @()

function Say([string]$s) { Write-Host $s }
function Refuse([string]$why) { Say ''; Say ('REFUSED - nothing was measured: ' + $why); exit 2 }

function Get-RefusedCount {
    $fs = [IO.File]::Open($AuditFile, 'Open', 'Read', 'ReadWrite')
    try {
        $text = (New-Object IO.StreamReader($fs, [Text.Encoding]::GetEncoding(28591))).ReadToEnd()
    } finally { $fs.Close() }
    return @($text -split "`n" | Where-Object { $_ -match ('API REFUSED user=' + [regex]::Escape($Name) + '(\s|$)') }).Count
}

# One client run.  $KillSeconds -le 0 means let it finish (the control).  Returns how long
# the client lived, whether it was still running when it was killed, and what it printed.
function Invoke-Client([double]$KillSeconds) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $py.Source
    $psi.Arguments = '-3 "' + $Probe + '" --host 127.0.0.1 --port ' + $Port + ' --user ' + $Name
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['SD_SCRAM_PASSWORD'] = 'zz-matches-no-account-' + (Get-Random -Minimum 100000 -Maximum 999999)
    $psi.EnvironmentVariables['PYTHONIOENCODING'] = 'utf-8'
    Say ('    $ ' + $psi.FileName + ' ' + $psi.Arguments + '   [SD_SCRAM_PASSWORD: random, matches nothing]')
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    $stillRunning = $false
    if ($KillSeconds -gt 0) {
        if (-not $p.WaitForExit([int]($KillSeconds * 1000))) {
            $stillRunning = $true
            $null = & taskkill.exe /PID $p.Id /T /F 2>$null
            $null = $p.WaitForExit(5000)
        }
    } else {
        if (-not $p.WaitForExit(60000)) { $null = & taskkill.exe /PID $p.Id /T /F 2>$null }
    }
    $sw.Stop()
    $text = (($o.Result) + ($e.Result)) -replace "`r", ''
    return [pscustomobject]@{ Seconds = [math]::Round($sw.Elapsed.TotalSeconds, 2); StillRunningAtKill = $stillRunning; Text = $text }
}

Say ('=== probe-failaudit ' + (Get-Date -Format s))
Say ('script     : ' + $PSCommandPath)
Say ('port       : ' + $Port)
Say ('audit file : ' + $AuditFile)
Say ('name       : ' + $Name + '   (a wrong password is sent for it; a name that is not an account is refused at request 47, a real one at 48)')
Say ('probe      : ' + $Probe + '   exists: ' + (Test-Path -LiteralPath $Probe))
Say ('py.exe     : ' + $(if ($py) { $py.Source } else { 'NOT FOUND' }))

if (-not $py) { Refuse 'py.exe is not on PATH.' }
if (-not (Test-Path -LiteralPath $Probe)) { Refuse ('scram-probe.py is not beside this script: ' + $Probe) }
$listen = @(Get-NetTCPConnection -State Listen -LocalPort $Port -ErrorAction SilentlyContinue)
if ($listen.Count -eq 0) { Refuse ('nothing is listening on port ' + $Port + '.') }
Say ('listening  : pid ' + (($listen | ForEach-Object { $_.OwningProcess } | Select-Object -Unique) -join ', '))
if (-not (Test-Path -LiteralPath $AuditFile)) { Refuse ('no audit file at ' + $AuditFile) }
try { $c0 = Get-RefusedCount } catch { Refuse ('the audit file cannot be read from this window (' + $_.Exception.Message + ') - the full product needs an ELEVATED PowerShell.') }
Say ('audit size : ' + (Get-Item -LiteralPath $AuditFile).Length + ' bytes; "API REFUSED user=' + $Name + '" lines now: ' + $c0)

Say ''
Say '== CONTROL: the client waits out the delay'
$before = Get-RefusedCount
$r = Invoke-Client 0
Start-Sleep -Seconds 2
$after = Get-RefusedCount
Say ('    client lived ' + $r.Seconds + ' s; audit lines ' + $before + ' -> ' + $after)
foreach ($l in ($r.Text -split "`n")) { if ($l.Trim()) { Say ('    | ' + $l) } }
if ($r.Text -notmatch 'login REFUSED at request') { Refuse 'the control client did not get the server''s refusal, so it did not reach the bad-credential path.' }
if ($r.Seconds -lt 2.5) { Refuse ('the control client lived only ' + $r.Seconds + ' s; the three-second delay was not in the way, so the kill times below would not land inside it.') }
if ($after -ne $before + 1) { Refuse ('the control wrote ' + ($after - $before) + ' audit lines, not 1 - the counting or the audit path is not what this probe assumes.') }
Say '    control: the refusal reached the client after the delay AND added exactly one line'

Say ''
Say ('== TREATMENT: the client is killed K seconds in, then ' + $WaitAfter + ' s are allowed for the server')
$lost = 0
$rows = @()
foreach ($k in $KillAfter) {
    $before = Get-RefusedCount
    $r = Invoke-Client $k
    if (-not $r.StillRunningAtKill) { Refuse ('the client had already ended before the ' + $k + ' s kill (it lived ' + $r.Seconds + ' s) - not a measurement of an early drop.') }
    Start-Sleep -Seconds $WaitAfter
    $after = Get-RefusedCount
    $delta = $after - $before
    if ($delta -lt 1) { $lost++ }
    $rows += ('K=' + $k + ' s: killed at ' + $r.Seconds + ' s, audit lines ' + $before + ' -> ' + $after + '  (' + $(if ($delta -ge 1) { 'AUDITED' } else { 'NOT AUDITED' }) + ')')
    Say ('    ' + $rows[-1])
}

Say ''
Say '== RESULT'
foreach ($row in $rows) { Say ('  ' + $row) }
if ($lost -eq 0) {
    Say ('PASS: all ' + $KillAfter.Count + ' early drops were audited.  The record is written even when the client leaves during the delay.')
    exit 0
}
Say ('DEFECT PRESENT: ' + $lost + ' of ' + $KillAfter.Count + ' early drops wrote NO audit record.  Linux measured 5 of 5.')
exit 1
