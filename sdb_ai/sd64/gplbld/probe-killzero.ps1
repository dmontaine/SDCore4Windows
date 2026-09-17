<#
.SYNOPSIS
    RELEASE_1.1 37: from the DAEMON'S vantage - LocalSystem, session 0 - does
    kill(pid, 0) see a LIVE elevated console session, and does it see a KILLED
    one as gone?  ELEVATED PowerShell.  It starts one SD session and kills it.

.DESCRIPTION
    sdwind.c:262 marks a user lost when kill(pid, 0) fails with anything but
    EPERM, and clopts.c:360 (sd -cleanup) uses the same test.  probe-system.c
    has already shown the daemon's cleanup can never start on an install (no
    /bin/sh; system() 127) - but before that is fixed the OTHER half must be
    known: whether SYSTEM in session 0 can see the console sessions' Cygwin
    pids at all.  An unelevated probe could not see sdwind (ESRCH for a live
    process), so visibility across tokens is not a given.  If SYSTEM sees a
    live session-1 process as ESRCH, a working cleanup would reap LIVE users -
    the 22 Aug 2026 "Forced logout" symptom (PROJECT_STATUS 4).

    What runs: an ELEVATED sd session is started (stdin a pipe, so it sits at
    the prompt in SDSYS), its Cygwin pid is read while it lives, then
    probe-killzero.exe is run as SYSTEM (scheduled task, the daemon's token
    and session) against that pid and, as a control, sdwind's own pid.  Then
    the session is killed and the SYSTEM probe runs again.  The same probe runs
    from this elevated shell each time, as the sd -cleanup-by-hand vantage.

    THE KILL is the staged fault PROJECT_STATUS 4 warns about; the owner asked
    for this measurement (17 Sep 2026).  Afterwards the killed session's slot
    stays until an elevated sd -cleanup, which this script runs at the end and
    reports - that run is itself a measurement of clopts.c:360.

.OUTPUTS
    Exit 0 measured, 2 could not run.  There is no falsified-if: the rows are
    the finding either way, and are read into RELEASE_1.1 37.
#>

[CmdletBinding()]
param([switch] $Keep)

$ErrorActionPreference = 'Stop'
$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$Probe  = Join-Path $Gplbld 'probe-killzero.exe'
$SdBin  = Join-Path $env:ProgramFiles 'SD\usr\bin'
$Sd     = Join-Path $SdBin 'sd.exe'
$Task   = 'killzeroprobe'
$Stage  = 'C:\ProgramData\killzero-run'
$env:PATH = $SdBin + ';' + $env:PATH        # the probe must load SD's runtime

function Say($m) { Write-Host $m }
function Step($m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Cleanup {
    if ($script:Keeping) { Say "  -Keep: leaving $Task and $Stage"; return }
    try { $t = & schtasks.exe /query /tn $Task 2>$null; if ($t) { $null = & schtasks.exe /delete /tn $Task /f 2>$null } } catch { }
    try { if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}
function Refuse($m) { Write-Host ''; Write-Host "COULD NOT RUN: $m" -ForegroundColor Yellow; Cleanup; exit 2 }
$script:Keeping = [bool]$Keep
trap { Write-Host ''; Write-Host "UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red; Cleanup; exit 3 }

function Probe-Here([string[]]$pids, [string]$label) {
    Say "--- probe from THIS shell (elevated): $label ---"
    $o = @(& $Probe @pids 2>&1 | ForEach-Object { "$_" })
    $o | ForEach-Object { Say "  $_" }
    return $o
}

# The SYSTEM run: one scheduled task per call, output to a file in the stage.
$script:sysRun = 0
function Probe-System([string[]]$pids, [string]$label) {
    $script:sysRun++
    $out = Join-Path $Stage ("system-$($script:sysRun).txt")
    $tr = 'cmd.exe /c ""' + (Join-Path $Stage 'probe-killzero.exe') + '" ' + ($pids -join ' ') + ' > "' + $out + '" 2>&1"'
    Say "--- probe as SYSTEM (scheduled task): $label ---"
    Say "  task: $tr"
    $r = & schtasks.exe /create /tn $Task /tr $tr /sc once /st 23:59 /ru SYSTEM /rl HIGHEST /f
    if ($LASTEXITCODE -ne 0) { Refuse "schtasks /create failed - $($r -join ' ')" }
    $r = & schtasks.exe /run /tn $Task
    if ($LASTEXITCODE -ne 0) { Refuse "schtasks /run failed - $($r -join ' ')" }
    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $out) -and (Select-String -LiteralPath $out -Pattern 'kill\(pid,0\)|REFUSED|usage' -Quiet)) { break }
        Start-Sleep -Milliseconds 400
    }
    Start-Sleep -Milliseconds 500
    if (-not (Test-Path -LiteralPath $out)) { Say '  (the SYSTEM task wrote nothing)'; return @() }
    $o = @(Get-Content -LiteralPath $out)
    $o | ForEach-Object { Say "  $_" }
    return $o
}

# NOT $pid: that is an AUTOMATIC variable (the running process's id) and is
# read-only - the parser accepts it as a parameter name and the first
# assignment throws "Cannot overwrite variable pid".  Same class as the $args
# trap in CLAUDE.md; cost this probe its first elevated run, 17 Sep 2026.
function Verdict([string[]]$o, [string]$cygpid) {
    $line = $o | Where-Object { $_ -match 'kill\(pid,0\)' } | Select-Object -First 1
    if (-not $line) { return 'NO ANSWER' }
    if ($line -match 'reads this as (ALIVE|LOST)') { return $Matches[1] + '  (' + ($line -replace '^\s+', '') + ')' }
    return $line
}

# ---------------------------------------------------------------------------
Step 'Preconditions'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'COULD NOT RUN: this needs an ELEVATED PowerShell.' -ForegroundColor Yellow; exit 2
}
if (-not (Test-Path -LiteralPath $Probe)) { Write-Host "COULD NOT RUN: no $Probe - build it (see the .c header)." -ForegroundColor Yellow; exit 2 }
if (-not (Test-Path -LiteralPath $Sd)) { Write-Host "COULD NOT RUN: no $Sd." -ForegroundColor Yellow; exit 2 }
$sdwind = Get-Process -Name sdwind -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $sdwind) { Write-Host 'COULD NOT RUN: sdwind is not running.' -ForegroundColor Yellow; exit 2 }
Say "  running as : $($id.Name), elevated"
Say "  sdwind     : winpid $($sdwind.Id)"
if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
$null = New-Item -ItemType Directory -Path $Stage -Force
Copy-Item -LiteralPath $Probe -Destination $Stage -Force
$null = & icacls.exe $Stage /grant "*S-1-5-18:(OI)(CI)F" /T
if ($LASTEXITCODE -ne 0) { Refuse "icacls could not grant SYSTEM on $Stage." }

# ---------------------------------------------------------------------------
Step 'An elevated SD session, sitting at the prompt'
$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $Sd
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.CreateNoWindow = $true
$p = [System.Diagnostics.Process]::Start($psi)
Say "  session    : sd.exe winpid $($p.Id)"
Start-Sleep -Seconds 5
$who = ("`nWHO`nOFF`n" | & $Sd) -join "`n"
Say '  WHO from another session:'
($who -split "`n") | Where-Object { $_ -match '^\d+ \S+' } | ForEach-Object { Say "    $_" }

$o = Probe-Here @("w$($p.Id)", "w$($sdwind.Id)") 'the live session and sdwind, by Windows pid'
$cyg = -1; $cygWind = -1
$cur = ''
foreach ($l in $o) {
    if ($l -match 'winpid (\d+) -> cygwin pid (-?\d+)') { if ([int]$Matches[1] -eq $p.Id) { $cyg = [int]$Matches[2] } elseif ([int]$Matches[1] -eq $sdwind.Id) { $cygWind = [int]$Matches[2] } }
}
Say "  cygwin pid : session $cyg, sdwind $cygWind"
if ($cyg -lt 0) { $p.Kill(); Refuse 'this elevated shell cannot see the live session it started - nothing below can be measured.' }

$rows = New-Object System.Collections.ArrayList
function Note($what, $verdict) { $null = $rows.Add([pscustomobject]@{ Vantage = $what; Answer = $verdict }); Say "  >> $what : $verdict" }

Note 'elevated shell, LIVE session'  (Verdict $o "$cyg")
$s = Probe-System @("$cyg") 'the LIVE elevated session, by cygwin pid'
Note 'SYSTEM session 0, LIVE session' (Verdict $s "$cyg")
if ($cygWind -gt 0) {
    $s2 = Probe-System @("$cygWind") 'sdwind itself (control: SYSTEM sees its own)'
    Note 'SYSTEM session 0, LIVE sdwind (control)' (Verdict $s2 "$cygWind")
}

# ---------------------------------------------------------------------------
Step "Killing the session (winpid $($p.Id), cygwin pid $cyg)"
Stop-Process -Id $p.Id -Force
Start-Sleep -Seconds 3
Say "  HasExited  : $($p.HasExited)"
$o = Probe-Here @("$cyg") 'the KILLED session'
Note 'elevated shell, KILLED session' (Verdict $o "$cyg")
$s = Probe-System @("$cyg") 'the KILLED session'
Note 'SYSTEM session 0, KILLED session' (Verdict $s "$cyg")
$p.Dispose()

# ---------------------------------------------------------------------------
Step 'sd -cleanup from this elevated shell (clopts.c:360, the by-hand recovery)'
$who1 = ("`nWHO`nOFF`n" | & $Sd) -join "`n"
Say '  WHO before cleanup:'
($who1 -split "`n") | Where-Object { $_ -match '^\d+ \S+' } | ForEach-Object { Say "    $_" }
$cl = & $Sd -cleanup 2>&1 | ForEach-Object { "$_" }
Say ("  sd -cleanup said: " + $(if ($cl) { $cl -join ' | ' } else { '(nothing)' }))
$who2 = ("`nWHO`nOFF`n" | & $Sd) -join "`n"
Say '  WHO after cleanup:'
($who2 -split "`n") | Where-Object { $_ -match '^\d+ \S+' } | ForEach-Object { Say "    $_" }
$errlog = Join-Path $env:ProgramData 'SD\sdsys\errlog'
if (Test-Path -LiteralPath $errlog) {
    Say '  errlog tail:'
    Get-Content -LiteralPath $errlog -Tail 6 | ForEach-Object { Say "    $_" }
}

Say ''
$rows | Format-Table -AutoSize | Out-String | Write-Host
Cleanup
Write-Host 'probe-killzero: MEASURED - read the table into RELEASE_1.1 37.' -ForegroundColor Green
exit 0
