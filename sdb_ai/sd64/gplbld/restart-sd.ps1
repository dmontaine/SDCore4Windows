# restart-sd.ps1 - stop SD properly and start it again.
# PRE_RELEASE_FIXES 78.
#
#   powershell -File restart-sd.ps1 -Show     report state, change nothing
#   powershell -File restart-sd.ps1           stop, wait, start, verify
#
# Exit 0 SD is running again and was verified, 1 it is not, 2 the question
# could not be answered (no service installed, sd.exe missing).
#
# WHY THIS IS NOT Restart-Service, AND IT IS MEASURED RATHER THAN PREFERRED.
# cycle.ps1:299 records it: "Stop-Service returns before the SCM has finished
# and before sdwind has gone, so the wait is on the PROCESS, which is what
# actually holds the shared segment and /dev/shm."  And on 21 Aug 2026 at 17:05
# sc.exe stop returned, the service went to Stopped, and sdwind(15956) was still
# there 45 seconds later with its parent gone - the cycle failed at step 1 and
# cost a run.  A Restart-Service here would report success while the OLD
# configuration went on running, which for "remote.api" means telling somebody
# the API is on when no socket was ever reopened.
#
# SO THE SHAPE IS cycle.ps1's, DELIBERATELY: stop the service, wait on the
# PROCESSES, and if a daemon survives its parent, ask SD itself.  sdsvc.c
# already does this on its own stop path (run_sd("-stop") at :433, :467, :482),
# so this is the same call made again from outside for the case where the
# service exited without its daemon following.
#
# ***"sd -stop" TERMINATES SESSIONS.  IT DOES NOT REFUSE.***  Measured in the C
# on 30 Aug 2026, and it corrects cycle.ps1's comment, which says the opposite:
# stop_sd() (gplsrc/sysseg.c:766) walks the user table and sends SIGTERM to
# every entry with a uid and a pid > 0.  There is no "are users logged in"
# check anywhere in it.
#
# THAT MATTERS MOST TO ITS CALLER.  "remote.api" runs from inside SD, so the
# administrator who asks for a restart is themselves a row in that user table
# and their session is one of the ones SIGTERMed.  They will be disconnected
# BEFORE this script can tell them anything, which is why REMOTEAPI prints its
# warning and takes its Y/N before calling this rather than after.
#
# IT SURVIVES ITS CALLER, WHICH IS WHAT MAKES THE ABOVE SAFE.  ps_script hands
# this to the elevated helper (PS_SCRIPT:166), a PowerShell process that is not
# in SD's user table and so is not signalled - so the stop, the wait and the
# start all complete even though the session that asked for them is gone.

param(
    [switch]$Show
)

$ErrorActionPreference = 'Stop'

$SvcName = 'SD'
$SdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

function Say([string]$t) { Write-Output ("restart-sd: " + $t) }

function Get-SdProcs {
    return @(Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue)
}

function Report([string]$label) {
    $svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
    $p   = Get-SdProcs
    $names = if ($p.Count -gt 0) { ($p | ForEach-Object { $_.Name + '(' + $_.Id + ')' }) -join ' ' } else { 'none' }
    Say ("{0,-7} service={1} processes={2}" -f $label, $(if ($svc) { $svc.Status } else { 'ABSENT' }), $names)
}

# THE INSTRUMENT RULE: echo the real inputs before doing anything with them.
Say ("service : " + $SvcName)
Say ("sd.exe  : " + $SdExe)

$svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
if (-not $svc) {
    Say 'the SD service is not installed on this machine - nothing to restart'
    exit 2
}

Report 'before'

if ($Show) { exit 0 }

# ---------------------------------------------------------------------------
# Stop
# ---------------------------------------------------------------------------
& "$env:SystemRoot\System32\sc.exe" stop $SvcName | Out-Null

$deadline = (Get-Date).AddSeconds(45)
while ((Get-SdProcs).Count -gt 0 -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
}

# A DAEMON THAT OUTLIVED ITS SERVICE IS NOBODY'S CHILD and the SCM has nothing
# left to stop, so ask SD.  This is also what terminates the caller's session.
if ((Get-SdProcs).Count -gt 0) {
    if (Test-Path -LiteralPath $SdExe) {
        Say 'service stopped but SD processes remain - asking sd -stop'
        # NATIVE STDERR TERMINATES UNDER ErrorActionPreference Stop, so this is
        # wrapped: a native exe writing to stderr would otherwise kill this
        # script silently, half way through a restart.
        $out = ''
        try { $out = (& $SdExe -stop 2>&1 | Out-String) } catch { $out = $_.Exception.Message }
        $out -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { Say ("  " + $_) }

        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-SdProcs).Count -gt 0 -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
        }
    } else {
        Say 'sd.exe is not where it was expected, so sd -stop cannot be tried'
    }
}

$left = Get-SdProcs
if ($left.Count -gt 0) {
    # NAMED, NOT KILLED - cycle.ps1's rule, and the reason is the same here.
    # Starting a second daemon beside a surviving one is worse than stopping.
    Say ('SD processes are STILL running, so SD was not restarted: ' +
         (($left | ForEach-Object { $_.Name + '(' + $_.Id + ')' }) -join ' '))
    Say 'nothing was started - a second daemon beside a surviving one is worse than none'
    Report 'after'
    exit 1
}

Report 'stopped'

# ---------------------------------------------------------------------------
# Start
# ---------------------------------------------------------------------------
& "$env:SystemRoot\System32\sc.exe" start $SvcName | Out-Null

$deadline = (Get-Date).AddSeconds(45)
while ((Get-SdProcs).Count -eq 0 -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
}

# ***VERIFY, DO NOT ASSUME.***  sc.exe start returns as soon as the SCM has
# accepted the request.  The thing that matters is whether a daemon is actually
# up afterwards, because that is what reopens the API socket - so both the
# service state AND a live process are checked, and a green answer needs both.
Start-Sleep -Milliseconds 500
$svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
$p   = Get-SdProcs
Report 'after'

if ($svc -and $svc.Status -eq 'Running' -and $p.Count -gt 0) {
    Say 'SD is running again'
    exit 0
}

Say 'SD did not come back up - check the service and the SD error log'
exit 1
