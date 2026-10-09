# verify-sdsysbatch.ps1 - SDSYS's own door through LOGIN's batch gate: a command given on the sd.exe
# COMMAND LINE runs for SDSYS with NO entry in batch.jobs, because the gate is bypassed for
# K$ADMINISTRATOR.  RELEASE_1.1 129.
#
#   powershell -ExecutionPolicy Bypass -File verify-sdsysbatch.ps1
#
# ***ELEVATED POWERSHELL, and SDSYS SIGNED IN***, as every seat verifier (sdsys-seat.ps1).
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test could not be run
# (not elevated, no seat, SDSYS already listed in batch.jobs, the probe would not plant).
#
# WHY IT EXISTS.  verify-batchjob.ps1 (the account's half: the default refuses, the list admits, an
# argument and a wrong type are refused, the ACL holds) used to end with a row asking an ELEVATED session
# for the same command with no entry.  On 29 Aug that row was moved to SDSYS (an elevated session cannot
# stand in an ordinary account); on 18 Sep RELEASE_1.1 64 made the elevated helper land in the installing
# user's account instead, so the row's planter answered "Cannot read source record" and every full run
# printed "COULD NOT BE MEASURED" - for three weeks nothing witnessed the administrator's side of the
# gate, and a regression that made SDSYS subject to batch.jobs (or removed the gate for everyone) would
# have shown only on the account half.  Entry 129 of PROJECT_STATUS.
#
# WHAT IT MEASURES, AND WHY THIS SHAPE.
#   login:1208 judges "batch.command" - the word given AFTER sd.exe on the command line - and
#   skips the whole of batch.permitted when kernel(K$ADMINISTRATOR,-1) is true.  Since RELEASE_1.1 64
#   that is true for exactly one caller, the OS SDSYS account with an elevated, interactive token, so the
#   command line has to be run AS that account: the seat (a scheduled task inside SDSYS's live session)
#   with -CommandWord, a validated single token handed to sd.exe as its argument.
#   Interactive lines piped into a plain session are NOT gated at all, so planting and removing the probe
#   uses them freely (the same point verify-batchjob makes for the account).
#
# THE ROWS, each with its opposite somewhere:
#   plant   a one-shot BASIC program writes a PA record 'COUNT VOC' into SDSYS's VOC (prints a marker)
#   runs    "sd.exe zzbatchsyspa" AS SDSYS, with NO batch.jobs record for SDSYS, prints "record(s) counted"
#   not refused  none of the three refusal wordings (10096 not a command that account / 10097 arguments /
#           10098 type) appears - a refusal could also have been the reason it did not "run"
#   control the same word after the probe is deleted from the VOC no longer runs, so the marker above was
#           the PARAGRAPH and not some other path to "record(s) counted"
#   The opposite of "SDSYS runs it with no entry" - "an ordinary account is refused with no entry" - is
#   verify-batchjob's first row, on the same gate, in the same suite.
#
# THE PRECONDITION IS ASSERTED, NOT ASSUMED: if batch.jobs already holds a record for SDSYS the run cannot
# tell the bypass from the listing, so it exits 2 and DELETES NOTHING it did not write.  The cleanup runs
# on every path out (finally): DELETE VOC through the seat, then the source and object files.
#
# SAYING WHAT IT DOES NOT REACH: it does not prove the bypass is the ONLY thing admitting SDSYS - only
# that a session which is not on the list runs, and that a plain account's identical case is refused
# (the other file).  A gate removed for everyone would fail verify-batchjob; a gate that wrongly kept
# SDSYS on the list would fail here.

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-sdsysbatch-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ('transcript: ' + $logPath)

function Stop-Here([int] $Code) { try { Stop-Transcript | Out-Null } catch { }; exit $Code }

$results = New-Object System.Collections.ArrayList
$failed  = $false
function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got; Result = $(if ($pass) { 'PASS' } else { 'FAIL' }) })
    Write-Output ('  [{0}] {1}: expected {2}, got {3}' -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

# The seat.  A seat that did not run THROWS (Invoke-SdSeatText), so a missing precondition is exit 2 by
# way of Assert-SdSeat below, never a thrown error that reads as a product failure.
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Write-Output ''; Write-Output 'verify-sdsysbatch: refusing - see above'; Stop-Here 2 }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-sdsysbatch: this needs an ELEVATED PowerShell - the seat registers a task for another account.'
    Stop-Here 2
}

$sdsys   = Join-Path $env:ProgramData 'SD\sdsys'
$listDir = Join-Path $sdsys 'batch.jobs'
$sysBp   = Join-Path $sdsys 'bp'
$sysProg = 'ZZBATCHS'
$sysPa   = 'zzbatchsyspa'
$sysSrc  = Join-Path $sysBp $sysProg
$sysObj  = Join-Path (Join-Path $sdsys 'bp.out') $sysProg

foreach ($p in @($listDir, $sysBp)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Output ('verify-sdsysbatch: REFUSED - no ' + $p); Stop-Here 2 }
}
$sysRec = Join-Path $listDir 'SDSYS'
if (Test-Path -LiteralPath $sysRec) {
    Write-Output ('verify-sdsysbatch: REFUSED - batch.jobs already carries a record for SDSYS: ' + $sysRec)
    Write-Output '  This row measures a session with NO entry, so it cannot be measured while that record stands,'
    Write-Output '  and this will not delete a record it did not write.  Remove it by hand if it is stale.'
    Stop-Here 2
}

Assert-SdSeat -Label 'verify-sdsysbatch'

# Message fragments, each wholly inside ONE line of its message (10096, 10097 and 10098 wrap with \n):
# .Contains() and not a regex, exactly as verify-batchjob does.
function SawRefusal([string]$t) { return $t.Contains('is not a command that account') }
function SawArgs([string]$t)    { return $t.Contains('must be a single name with nothing') }
function SawType([string]$t)    { return $t.Contains('has to be a paragraph or a sentence') }
function SawRan([string]$t)     { return $t.Contains('record(s) counted') }

$planter = @(
    ('* ' + $sysProg + ' - written by gplbld/verify-sdsysbatch.ps1.  Safe to delete.')
    "      OPEN 'voc' TO F ELSE STOP 'cannot open VOC'"
    "      R = 'PA' : @FM : 'COUNT VOC'"
    ('      WRITE R ON F, ''' + $sysPa + '''')
    ('      CRT ''' + $sysProg + '-DONE''')
) -join "`n"

$measured = $false
$ranText = ''; $afterText = ''; $plantText = ''
$seatError = ''; $plantFailed = $false
try {
    # Written from this elevated process; the seat (SDSYS) compiles and runs it.  ISO-8859-1 as every
    # other planter: the BASIC compiler reads bytes.
    [System.IO.File]::WriteAllText($sysSrc, $planter + "`n", [System.Text.Encoding]::GetEncoding('iso-8859-1'))

    Write-Output ''
    Write-Output '=== plant: a one-shot BASIC program writes the probe paragraph into SDSYS''s VOC ======'
    # PIPED into a plain session: interactive lines are not what the batch gate judges.
    # A seat that did not run THROWS; it is caught here so the cleanup below still runs and the exit is
    # 2 ("could not run"), not the 1 an uncaught error would give.
    try { $plantText = Invoke-SdSeatText -Commands @(('BASIC bp ' + $sysProg), ('RUN bp ' + $sysProg)) }
    catch { $seatError = $_.Exception.Message }
    if ($seatError -eq '') {
        foreach ($l in @($plantText -split "`n")) { if ($l -match '\S') { Write-Output ('    | ' + $l.TrimEnd()) } }
        if (-not $plantText.Contains($sysProg + '-DONE')) {
            $plantFailed = $true
        } else {
            Write-Output ('  planted: ' + $sysPa + ' in SDSYS''s VOC (marker ' + $sysProg + '-DONE seen)')
            Write-Output ''
            Write-Output '=== measure: sd.exe <word> on the COMMAND LINE, as SDSYS, with no batch.jobs record =========='
            Write-Output ('  batch.jobs record for SDSYS present: ' + (Test-Path -LiteralPath $sysRec) + '   (must be False)')
            # Commands @('OFF'): a command-line run ignores stdin; the seat needs at least one non-blank line.
            try { $ranText = Invoke-SdSeatText -Commands @('OFF') -CommandWord $sysPa; $measured = $true }
            catch { $seatError = $_.Exception.Message }
            if ($measured) {
                foreach ($l in @($ranText -split "`n")) { if ($l -match '\S') { Write-Output ('    | ' + $l.TrimEnd()) } }
                Write-Output ''
                Note 'precondition: no batch.jobs record for SDSYS during the run' $false (Test-Path -LiteralPath $sysRec)
                Note 'SDSYS, not listed: the paragraph RAN ("record(s) counted")' $true (SawRan $ranText)
                Note 'SDSYS, not listed: no "is not a command that account" refusal' $false (SawRefusal $ranText)
                Note 'SDSYS, not listed: no "single name with nothing" refusal' $false (SawArgs $ranText)
                Note 'SDSYS, not listed: no "paragraph or a sentence" type refusal' $false (SawType $ranText)
            }
        }
    }
}
finally {
    # UNCONDITIONAL, "DELETE VOC" and not DELETE.FILE (PRE_RELEASE 60 and 61): a VOC record that outlives
    # what it names is the defect those entries are about.  Piped, so the gate is not in the way.
    $cleanText = ''
    try { $cleanText = Invoke-SdSeatText -Commands @(('DELETE VOC ' + $sysPa)) } catch { Write-Output ('verify-sdsysbatch: WARNING - the VOC cleanup did not run: ' + $_.Exception.Message) }
    foreach ($f in @($sysSrc, $sysObj)) {
        if (Test-Path -LiteralPath $f) {
            try { Remove-Item -LiteralPath $f -Force } catch { Write-Output ('verify-sdsysbatch: WARNING - could not remove ' + $f) }
        }
    }
    Write-Output ''
    Write-Output '=== cleanup ===================================================================='
    foreach ($l in @($cleanText -split "`n")) { if ($l -match '\S') { Write-Output ('    | ' + $l.TrimEnd()) } }
}

if ($seatError -ne '') {
    Write-Output ''
    Write-Output ('verify-sdsysbatch: the SDSYS seat did not run - ' + $seatError)
    Write-Output 'verify-sdsysbatch: COULD NOT RUN - this says nothing about the product.'
    Stop-Here 2
}
if ($plantFailed) {
    Write-Output ''
    Write-Output 'verify-sdsysbatch: the probe could not be planted (no marker in the output above), so nothing would be measured.'
    Write-Output 'verify-sdsysbatch: COULD NOT RUN - this is not a failure of the product.'
    Stop-Here 2
}

if ($measured) {
    # THE CONTROL, after the cleanup: the same word must no longer run, so the "record(s) counted" above
    # was this paragraph and not some other way of getting that text.
    Write-Output ''
    Write-Output '=== control: the same word after the probe is deleted ====================================='
    try {
        $afterText = Invoke-SdSeatText -Commands @('OFF') -CommandWord $sysPa
    } catch { $afterText = 'SEAT-ERROR: ' + $_.Exception.Message }
    foreach ($l in @($afterText -split "`n")) { if ($l -match '\S') { Write-Output ('    | ' + $l.TrimEnd()) } }
    Note 'CONTROL: after the cleanup the same word no longer runs' $false (SawRan $afterText)
    Note 'CONTROL: and the seat itself still answered (not a seat error)' $false ($afterText.StartsWith('SEAT-ERROR'))
}

Write-Output ''
Write-Output '=== Summary =============================================================='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
Write-Output ('  {0} of {1} checks passed' -f $passed, $results.Count)
if ($failed) {
    Write-Output 'VERDICT: FAIL - SDSYS did not run a command-line command that is not on batch.jobs (the administrator bypass at login:1208 is not working)'
} else {
    Write-Output 'VERDICT: PASS - SDSYS runs a command-line command with no batch.jobs entry, and the same word stops running when the probe is gone'
}
Stop-Here $(if ($failed) { 1 } else { 0 })
