# sample-sdstate.ps1 - watch the SD service and its processes during a restart,
# from OUTSIDE the thing under test.
#
# PRE_RELEASE_FIXES 176.  The fixed restart-sd.ps1 waits for Running before it
# reports, so it always prints "after service=Running" - the fix ERASES the
# evidence of the window it exists to survive.  An instrument that asks the
# subject to report on itself cannot answer this, so this samples the state
# independently and looks for the race directly.
#
# THE WINDOW is any sample where a PROCESS EXISTS and the service is NOT yet
# Running.  That is the exact condition the old loop exited on (it waited for a
# process) while the verdict required Running - so a sample of that shape is
# proof the old code would have reported a good restart as a failure.
#
# IT REFUSES THE NULL CASE OUT LOUD.  If the service never left Running, no
# restart happened while this was watching and the run measured NOTHING - it
# says so and exits 2 rather than reporting a comfortable "0 windows seen".

param(
    [int] $Seconds      = 300,
    [int] $IntervalMs   = 100
)

$ErrorActionPreference = 'Continue'

$out = Join-Path $env:TEMP ('sdstate-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.csv')

Write-Output ('sample-sdstate: output   ' + $out)
Write-Output ('sample-sdstate: duration ' + $Seconds + 's, every ' + $IntervalMs + 'ms')
Write-Output ('sample-sdstate: started  ' + (Get-Date -Format 'HH:mm:ss.fff'))

$rows     = New-Object System.Collections.Generic.List[object]
$deadline = (Get-Date).AddSeconds($Seconds)

while ((Get-Date) -lt $deadline) {
    $svc = $null
    try { $svc = Get-Service -Name 'SD' -ErrorAction Stop } catch { }
    $status = if ($svc) { [string]$svc.Status } else { 'NO-SERVICE' }

    $procs = @(Get-Process -Name 'sdwind', 'sd', 'sdsvc' -ErrorAction SilentlyContinue)
    $names = ($procs | ForEach-Object { $_.Name + '(' + $_.Id + ')' }) -join ' '

    $rows.Add([pscustomobject]@{
        Time    = (Get-Date -Format 'HH:mm:ss.fff')
        Status  = $status
        NProc   = $procs.Count
        Procs   = $names
    })

    Start-Sleep -Milliseconds $IntervalMs
}

$rows | Export-Csv -Path $out -NoTypeInformation -Encoding UTF8

# ---------------------------------------------------------------------------
# Verdict
# ---------------------------------------------------------------------------
$states   = ($rows | Select-Object -ExpandProperty Status | Sort-Object -Unique)
$window   = @($rows | Where-Object { $_.NProc -gt 0 -and $_.Status -ne 'Running' })
$stopped  = @($rows | Where-Object { $_.Status -ne 'Running' })

Write-Output ''
Write-Output ('sample-sdstate: ' + $rows.Count + ' samples, states seen: ' + ($states -join ', '))

if ($stopped.Count -eq 0) {
    Write-Output ''
    Write-Output 'sample-sdstate: REFUSING - the service was Running in EVERY sample.'
    Write-Output '  No restart happened while this was watching, so nothing was measured.'
    Write-Output '  This is not "no window found"; it is "the question was never asked".'
    exit 2
}

Write-Output ('sample-sdstate: ' + $stopped.Count + ' sample(s) not Running - a restart WAS observed')
Write-Output ('sample-sdstate: ' + $window.Count + ' sample(s) show THE WINDOW (process present, service not yet Running)')

if ($window.Count -gt 0) {
    Write-Output ''
    Write-Output '  --- the window, as sampled ---'
    $window | ForEach-Object {
        Write-Output ('  ' + $_.Time + '  ' + $_.Status + '  procs=' + $_.NProc + '  ' + $_.Procs)
    }
    Write-Output ''
    Write-Output '  176 REPRODUCED: the old loop would have exited here and the verdict'
    Write-Output '  below it required Running, so a good restart scored as a failure.'
} else {
    Write-Output ''
    Write-Output '  No window in this run: every sample with a process also had the service'
    Write-Output '  Running.  That does NOT clear 176 - it means the race did not occur in'
    Write-Output '  these restarts, which is exactly what the slower machine always did.'
}

Write-Output ''
Write-Output '  --- the transitions, one line per state change ---'
$prev = $null
foreach ($r in $rows) {
    $key = $r.Status + '/' + [string]($r.NProc -gt 0)
    if ($key -ne $prev) {
        Write-Output ('  ' + $r.Time + '  ' + $r.Status + '  procs=' + $r.NProc + '  ' + $r.Procs)
        $prev = $key
    }
}

exit 0
