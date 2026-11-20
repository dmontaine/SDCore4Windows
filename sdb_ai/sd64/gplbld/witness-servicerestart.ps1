# witness-servicerestart.ps1 - RELEASE_1.1 295: the SD service does NOT restart SD after "sd -stop", and DOES after the daemon dies.
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\witness-servicerestart.ps1
#
# ELEVATED.  It ends SD twice (every SD session on this computer ends with it) and leaves SD running at the end.  About 2 minutes.
#   A  "sd -stop": after 25 s the service must be Stopped, no sdwind.exe, and sdsvc.log must say "exit code 0 ... not as a failure".
#      Then Start-Service SD, and SD must be up again within 60 s.
#   B  the daemon dies (sdwind.exe of C:\Program Files\SD ended by force): within 45 s the service must be Running again with a NEW
#      sdwind.exe, and sdsvc.log must name a non-zero exit code and "has GONE".
# Verdicts: PASS, FAIL, NOT RUN (with the reason; a step that could not run is never PASS).  Exit 0 all PASS, 1 a FAIL, 2 could not run.
#
# 19 Nov 26  New, RELEASE_1.1 295 (sdsvc d23229d5: Linux's rule, a clean exit is a stop).

$ErrorActionPreference = 'Continue'
$Sd      = 'C:\Program Files\SD\usr\bin\sd.exe'
$Wind    = 'C:\Program Files\SD\usr\bin\sdwind.exe'
$SvcLog  = 'C:\ProgramData\SD\sdsvc.log'
$Results = New-Object System.Collections.Generic.List[object]

function Say([string]$m) { Write-Host $m }
function Add-Row([string]$Step, [string]$Check, [string]$Verdict, [string]$Evidence) {
    $Results.Add([pscustomobject]@{ Step = $Step; Check = $Check; Verdict = $Verdict; Evidence = $Evidence })
    Say ('  [' + $Verdict + '] ' + $Step + ': ' + $Check)
    if ($Evidence) { Say ('         evidence: ' + $Evidence) }
}
# A function's @() is unrolled on return (one process comes back as the bare object), so EVERY caller wraps it: @(Get-Winds).
# 19 Nov 26: the first run refused "one sdwind.exe" with one running, because .Count of the bare object was not 1.
function Get-Winds { @(Get-CimInstance Win32_Process -Filter "Name='sdwind.exe'" | Where-Object { $_.ExecutablePath -ieq $Wind }) }
function Get-SvcState { $s = Get-Service -Name SD -ErrorAction SilentlyContinue; if ($s) { [string]$s.Status } else { 'absent' } }
function Get-LogMark { if (Test-Path -LiteralPath $SvcLog) { (Get-Item -LiteralPath $SvcLog).Length } else { 0 } }
function Get-LogSince([long]$Mark) {
    if (-not (Test-Path -LiteralPath $SvcLog)) { return @() }
    $fs = [IO.File]::Open($SvcLog, 'Open', 'Read', 'ReadWrite')
    try { $null = $fs.Seek($Mark, 'Begin'); $r = New-Object IO.StreamReader($fs); $t = $r.ReadToEnd() } finally { $fs.Close() }
    return @($t -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
}
function Show-Lines([string]$Title, [string[]]$Lines) {
    Say ('    --- ' + $Title + ' ---')
    if ($Lines.Count -eq 0) { Say '    | <nothing>' } else { foreach ($l in $Lines) { Say ('    | ' + $l) } }
    Say '    --- end ---'
}

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
Say ('witness-servicerestart  ' + (Get-Date -Format 's') + '  user ' + $env:USERNAME + '  elevated ' + $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Say ('  sd.exe ' + $Sd + ' (present ' + (Test-Path $Sd) + ')   sdwind ' + $Wind + '   sdsvc.log ' + $SvcLog)
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Say 'CANNOT RUN: this needs an ELEVATED PowerShell.  Nothing was done (exit 2).'; exit 2 }
if (-not (Test-Path $Sd)) { Say 'CANNOT RUN: SD is not installed here.  Nothing was done (exit 2).'; exit 2 }
$flag = (& sc.exe qfailureflag SD | Out-String)
Say ('  failure flag: ' + (($flag -split "`r?`n" | Where-Object { $_ -match 'FAILURE_ACTIONS' }) -join ' '))
$w0 = @(Get-Winds)
Say ('  BEFORE: service ' + (Get-SvcState) + ', sdwind pid(s) ' + (($w0 | ForEach-Object { $_.ProcessId }) -join ','))
if ((Get-SvcState) -ne 'Running' -or $w0.Count -ne 1) { Say 'CANNOT RUN: the SD service must be Running with one sdwind.exe first (Start-Service SD).  Nothing was done (exit 2).'; exit 2 }

# ---------------------------------------------------------------------------------------------------------------------- A: sd -stop
Say ''
Say '=== A: sd -stop must NOT be followed by a restart'
$mark = Get-LogMark
Say ('  > "' + $Sd + '" -stop')
$out = (& $Sd -stop 2>&1 | Out-String)
Show-Lines 'sd -stop said (raw)' @($out -split "`r?`n" | Where-Object { $_.Trim() -ne '' })
Say '  waiting 25 seconds (a restart would come after 5) ...'
Start-Sleep -Seconds 25
$st = Get-SvcState; $w = @(Get-Winds); $lines = @(Get-LogSince $mark)
Show-Lines 'sdsvc.log since the mark (raw)' $lines
Add-Row 'A' 'the service is Stopped 25 s after sd -stop' $(if ($st -eq 'Stopped') { 'PASS' } else { 'FAIL' }) ('service ' + $st)
Add-Row 'A' 'no sdwind.exe was started again' $(if ($w.Count -eq 0) { 'PASS' } else { 'FAIL' }) ('sdwind pid(s) now: ' + (($w | ForEach-Object { $_.ProcessId }) -join ',') + $(if ($w.Count -eq 0) { 'none' } else { '' }))
$clean = @($lines | Where-Object { $_ -match 'exit code 0 after' -and $_ -match 'not as a failure' })
if ($lines.Count -eq 0) { Add-Row 'A' 'sdsvc.log names the clean exit' 'NOT RUN' 'nothing new in sdsvc.log' }
else { Add-Row 'A' 'sdsvc.log names the clean exit' $(if ($clean.Count -gt 0) { 'PASS' } else { 'FAIL' }) $(if ($clean.Count) { $clean[0] } else { 'no "exit code 0 after ... not as a failure" line' }) }

Say '  > Start-Service SD   (waiting up to 60 seconds for it and sdwind.exe)'
Start-Service -Name SD -ErrorAction SilentlyContinue
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline -and -not ((Get-SvcState) -eq 'Running' -and @(Get-Winds).Count -eq 1)) { Start-Sleep -Seconds 1 }
$st = Get-SvcState; $w1 = @(Get-Winds)
Add-Row 'A' 'Start-Service brings SD back' $(if ($st -eq 'Running' -and $w1.Count -eq 1) { 'PASS' } else { 'FAIL' }) ('service ' + $st + ', sdwind pid(s) ' + (($w1 | ForEach-Object { $_.ProcessId }) -join ','))

# ---------------------------------------------------------------------------------------------------------------------- B: a death
Say ''
Say '=== B: the daemon dies, and the service must start SD again'
if ($st -ne 'Running' -or $w1.Count -ne 1) { Add-Row 'B' 'the row' 'NOT RUN' 'SD was not back up after A' }
else {
    $old = $w1[0].ProcessId
    Start-Sleep -Seconds 5            # sdsvc polls once a second; let it settle on this daemon
    $mark = Get-LogMark
    Say ('  > Stop-Process -Id ' + $old + ' -Force   (sdwind.exe ' + $Wind + ')')
    Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
    Say '  waiting up to 45 seconds for the service to start SD again ...'
    $deadline = (Get-Date).AddSeconds(45)
    $w2 = @()
    while ((Get-Date) -lt $deadline) {
        $w2 = @(Get-Winds)
        if ((Get-SvcState) -eq 'Running' -and $w2.Count -eq 1 -and $w2[0].ProcessId -ne $old) { break }
        Start-Sleep -Seconds 1
    }
    $st = Get-SvcState; $lines = @(Get-LogSince $mark)
    Show-Lines 'sdsvc.log since the mark (raw)' $lines
    $new = if ($w2.Count -eq 1) { $w2[0].ProcessId } else { 0 }
    Add-Row 'B' 'the service is Running again with a NEW sdwind.exe' $(if ($st -eq 'Running' -and $new -ne 0 -and $new -ne $old) { 'PASS' } else { 'FAIL' }) ('service ' + $st + ', old pid ' + $old + ', new pid ' + $new)
    $gone = @($lines | Where-Object { $_ -match 'has GONE' })
    $code = @($lines | Where-Object { $_ -match 'exit code' -and $_ -notmatch 'exit code 0 after' })
    if ($lines.Count -eq 0) { Add-Row 'B' 'sdsvc.log names the death' 'NOT RUN' 'nothing new in sdsvc.log' }
    else { Add-Row 'B' 'sdsvc.log names a non-zero exit code and "has GONE"' $(if ($gone.Count -and $code.Count) { 'PASS' } else { 'FAIL' }) (($code + $gone) -join ' / ') }
}

# ---------------------------------------------------------------------------------------------------------------------- summary
Say ''
$n = @{}; foreach ($v in 'PASS', 'FAIL', 'NOT RUN') { $n[$v] = @($Results | Where-Object { $_.Verdict -eq $v }).Count }
Say ('SUMMARY: PASS {0}   FAIL {1}   NOT RUN {2}   (AFTER: service {3}, sdwind {4})' -f $n['PASS'], $n['FAIL'], $n['NOT RUN'], (Get-SvcState), ((Get-Winds | ForEach-Object { $_.ProcessId }) -join ','))
if ($Results.Count -eq 0) { Say 'nothing was measured (exit 2)'; exit 2 }
if ($n['FAIL']) { exit 1 }
if ($n['NOT RUN']) { exit 2 }
exit 0
