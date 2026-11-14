# witness-vm-stop.ps1 - row 203 (RELEASE_1.1): does an idle SD session outlive sd -stop's SIGTERM, and if it does, is it
# ended ten seconds later with the count printed, and does the next sd -start succeed?  Core VM witness sitting, 13 Nov 2026.
#
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-stop.ps1
#
# ELEVATED PowerShell in the VM, SDSYS signed in (the seat), the fixture account zzwitoff made (witness-vm-admin.ps1 -Only
# fixtures).  RUN IT LAST BUT ONE in the sitting (before the reinstall): it stops SD.  No SD window may be open.
#
# What it does, printed as it goes: opens two idle sessions - an ssh session of zzwitoff sitting at the TCL prompt, and a
# phantom of SDSYS sleeping (PHANTOM SLEEP 600) - lists every sd.exe with its user, runs "sd -stop" and prints what it said
# and how long it took, lists what is left, then "sd -start" and a fresh session through the seat.
#
# IT NEVER ENDS AN SD PROCESS ITSELF (memory never-stop-process-an-sd-session): ending them is the product's job under
# test.  Anything still running afterwards is reported, left alone, and the summary says so.  It has no sections: it is
# one measurement, about 90 seconds.  Exit 0 passed, 1 FAIL, 2 could not run.
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting.  Parse-checked; not run (it needs the VM).
# END-HISTORY

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

Start-Wit 'witness-vm-stop' @('stop203')
if (-not (Test-WitElevated)) { Write-Wit 'CANNOT RUN: not elevated (sd -stop needs an elevated session).'; exit 2 }
$fix = Read-WitFixtures
if ($null -eq $fix -or -not $fix.ContainsKey('zzwitoff')) { Write-Wit 'CANNOT RUN: no zzwitoff password on file: run witness-vm-admin.ps1 -Only fixtures first.'; exit 2 }
$sdDir = Join-Path $env:ProgramFiles 'SD'

function Get-SdProcs {
    return @(Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.Path -and $_.Path.StartsWith($sdDir, [StringComparison]::OrdinalIgnoreCase) } |
             ForEach-Object { [pscustomobject]@{ Id = $_.Id; Name = $_.ProcessName; User = $_.UserName } })
}
function Write-Procs([string]$Label, $Procs) {
    Write-Wit ('  ' + $Label + ': ' + @($Procs).Count + ' process(es) from ' + $sdDir)
    foreach ($p in @($Procs)) { Write-Wit ('    pid ' + $p.Id + ' ' + $p.Name + ' ' + $p.User) }
}

# The idle ssh session: stdin held open, so SD waits at its prompt.
$wd = Join-Path $env:TEMP ('witness-stop-' + $PID)
if (-not (Test-Path -LiteralPath $wd)) { $null = New-Item -ItemType Directory -Path $wd }
$ask = Join-Path $wd 'askpass.cmd'
Set-Content -Path $ask -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
$psi = New-Object Diagnostics.ProcessStartInfo
$psi.FileName = (Get-Command ssh.exe).Source
$psi.Arguments = '-o StrictHostKeyChecking=no -o UserKnownHostsFile=NUL -o ConnectTimeout=20 -o LogLevel=ERROR -o PreferredAuthentications=password -o NumberOfPasswordPrompts=1 zzwitoff@localhost whoami'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
$psi.EnvironmentVariables['SDPROBEPW'] = $fix['zzwitoff']
$psi.EnvironmentVariables['SSH_ASKPASS'] = $ask
$psi.EnvironmentVariables['SSH_ASKPASS_REQUIRE'] = 'force'
$psi.EnvironmentVariables['DISPLAY'] = 'localhost:0'
$ssh = [Diagnostics.Process]::Start($psi)
$sshOut = $ssh.StandardOutput.ReadToEndAsync()
$sshErr = $ssh.StandardError.ReadToEndAsync()
$ssh.StandardInput.WriteLine('')
$ssh.StandardInput.WriteLine('WHO')
$ssh.StandardInput.Flush()
Write-Wit '  an ssh session of zzwitoff is open and idle at the prompt (waiting 10 seconds for its sign-in)'
Start-Sleep -Seconds 10

$ph = Invoke-WitSd -Commands @('PHANTOM SLEEP 600') -Label 'a phantom of SDSYS that sleeps 10 minutes'
$phOk = ($ph.Ok -and $ph.Text -match 'Started phantom user (\d+)')
Write-Wit ('  phantom started: ' + $phOk)

$before = Get-SdProcs
Write-Procs 'before sd -stop' $before
$sessions = @($before | Where-Object { $_.Name -eq 'sd' })
if ($sessions.Count -lt 2) { Add-WitResult '203' 'two idle sessions were open before sd -stop' 'NOT-MEASURED' ('only ' + $sessions.Count + ' sd.exe found (the ssh session or the phantom did not start)') }

Write-Wit '  sd -stop (it waits up to ten seconds for SIGTERM, then ends the rest)'
$t0 = Get-Date
$stopOut = & (Join-Path $sdDir 'usr\bin\sd.exe') -stop 2>&1 | ForEach-Object { [string]$_ }
$secs = [Math]::Round(((Get-Date) - $t0).TotalSeconds, 1)
$st = $stopOut -join "`n"
Write-WitRaw ('sd -stop (' + $secs + ' s, exit ' + $LASTEXITCODE + ')') $st
Start-Sleep -Seconds 3
$after = Get-SdProcs
Write-Procs 'after sd -stop' $after
$sshGone = $ssh.WaitForExit(5000)
Write-Wit ('  the ssh client ended: ' + $sshGone)

$killed = [regex]::Match($st, '(\d+) process\(es\) still running after ten seconds were ended with SIGKILL')
if ($killed.Success) { Add-WitResult '203' ('an idle session outlived SIGTERM: ' + $killed.Groups[1].Value + ' process(es) were ended with SIGKILL after ten seconds and the count printed') 'INFO' $killed.Value }
else { Add-WitResult '203' 'no SD process outlived SIGTERM (no SIGKILL count printed)' 'INFO' ('sd -stop took ' + $secs + ' s') }
Set-WitVerdict '203' 'sd -stop says SD has been shut down' $st 'SD \(64 Bit\) has been shut down' @('Error \d+ deleting shared memory', 'needs an elevated session', 'did not stop when it was asked to')
$left = @($after | Where-Object { $_.Name -eq 'sd' -or $_.Name -eq 'sdwind' })
if ($left.Count -eq 0) { Add-WitResult '203' 'after sd -stop no SD session or daemon is left' 'PASS' ('before: ' + (($sessions | ForEach-Object { $_.Id }) -join ',')) }
else { Add-WitResult '203' 'after sd -stop no SD session or daemon is left' 'FAIL' ('still running (LEFT ALONE, not killed): ' + (($left | ForEach-Object { 'pid ' + $_.Id + ' ' + $_.Name + ' ' + $_.User }) -join '; ')) }

Write-Wit '  sd -start'
$startOut = & (Join-Path $sdDir 'usr\bin\sd.exe') -start 2>&1 | ForEach-Object { [string]$_ }
$sst = $startOut -join "`n"
Write-WitRaw ('sd -start (exit ' + $LASTEXITCODE + ')') $sst
Set-WitVerdict '203' 'the next sd -start succeeds' $sst 'SD \(64 Bit\) has been started' @('did not shut down cleanly', 'already started', 'did not start within 10 seconds', 'fork\(\) failed')
Start-Sleep -Seconds 3
$w = Invoke-WitSd -Commands @('WHO') -Label 'a new session after the restart'
Set-WitVerdict '203' 'a new session works after the restart' $w.Text '(?m)^\s*\d+\s+SDSYS\b' @('SD has not been started', 'restricted to privileged users')

try { $ssh.StandardInput.Close() } catch { }
if ($ssh.WaitForExit(5000)) { Write-WitRaw 'the idle ssh session''s output' ($sshOut.Result + "`n" + $sshErr.Result) }
else { Write-Wit ('  the ssh client (pid ' + $ssh.Id + ') is still running; its output is not read (left alone)') }
Remove-Item -LiteralPath $wd -Recurse -Force -ErrorAction SilentlyContinue
$code = Complete-Wit
exit $code
