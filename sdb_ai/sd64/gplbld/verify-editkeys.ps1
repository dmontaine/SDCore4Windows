# verify-editkeys.ps1 - the erase and cursor keys INSIDE the full-screen
# editors.  PROJECT_STATUS.md 5.19.
#
#   powershell -File verify-editkeys.ps1        UNELEVATED
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# WHY IT EXISTS.  PROJECT_STATUS.md 5.17 recorded that the full-screen editors
# carry their own key tables, which neither the _KEYCODE binds nor the terminal
# type reaches, and said the work was "a test that drives a full-screen editor,
# and nothing here does that yet".  This is that test.
#
# THE THING THAT MAKES IT CHEAP, and it is worth saying because the note above
# assumed otherwise: SED and UPDREC read the keyboard with keyin(), which reads
# STANDARD INPUT.  So a full-screen editor is drivable from a pipe exactly as
# the command-line editor is - no console, no elevation, no account of its own.
# What is NOT drivable is the screen, and it does not need to be:
#
#   THE INSTRUMENT IS THE SAVED RECORD.  Type into the editor, save, quit, then
#   read the record back with CT.  It cannot pass by accident because each case
#   below has two spellings of the answer - "AC" if the erase went backwards,
#   "ABC" if it went forwards or did nothing.
#
# EVERY CASE USES A FRESH RANDOM RECORD ID, and that is not tidiness.  A run
# that times out leaves SD killed mid-edit, holding a READU lock on the record
# it had open, and the lock outlives the process: LIST.READU still shows it, a
# dead user owns it, UNLOCK will not take it from an account session, and every
# later run on that id then stops on "Wait for lock to be released? Y or N".
# One timeout would otherwise poison the test for the rest of the install.
# Section 0 reports any that are found rather than failing on them, since they
# are evidence about a PREVIOUS run, not about this build.

param([switch]$Quiet)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-editkeys-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-editkeys: refusing - see above'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path $sdExe)) {
    Write-Output "verify-editkeys: no $sdExe"
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$acctRoot = Join-Path $env:ProgramData 'SD\user_accounts'
$acctDir  = $null
foreach ($n in @($env:USERNAME.ToUpper(), $env:USERNAME)) {
    $p = Join-Path $acctRoot $n
    if (Test-Path -LiteralPath $p) { $acctDir = $p; break }
}
if ($null -eq $acctDir) {
    Write-Output "verify-editkeys: $env:USERNAME has no SD account under $acctRoot"
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
$bp = Join-Path $acctDir 'BP'

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    if (-not $pass) { $script:failed = $true }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

# Bounded, like every other piped instrument here.  A full-screen editor that
# never gets its quit sequence would otherwise hang for ever.
function Invoke-SD([string]$body, [int]$TimeoutSec = 45) {
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else { Stop-Job $job; $out = Receive-Job $job; $out += '<<TIMED OUT>>' }
    $job | Remove-Job -Force -ErrorAction SilentlyContinue
    return (($out -join "`n") -replace "`e\[[0-9;?]*[A-Za-z]", '')
}

$ESC = [char]27
$CX  = [char]24     # Ctrl-X
$CS  = [char]19     # Ctrl-S
$CC  = [char]3      # Ctrl-C
$SAVEQUIT = $CX + $CS + $CX + $CC
$FILE = 'ZZEDKEYS'
$rx = [regex]'(?m)^1:\s*(.*?)\s*$'

function New-Id { return 'ZZK' + (Get-Random -Minimum 100000 -Maximum 999999) }

function Get-Field1([string]$out) {
    if ($out -match '<<TIMED OUT>>')        { return '<timeout>' }
    if ($out -match 'Wait for lock')        { return '<locked>' }
    $m = $rx.Match($out)
    if ($m.Success) { return $m.Groups[1].Value }
    if ($out -match "not on file|'.*' not found") { return '<no record>' }
    return '<unclear>'
}

try {
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 0. the test file, and any lock a previous run left ==================='

    $mk = Invoke-SD ("`n" + (@('TERM 200,9999', "CREATE.FILE $FILE DIRECTORY", 'LIST.READU', 'OFF') -join "`n") + "`n")
    if ($mk -match 'Wait for lock') { Write-Output '  a lock prompt appeared even here - see the header'; }
    $stale = @($mk -split "`n" | Where-Object { $_ -match '\sRU\s+ZZK' })
    if ($stale.Count) {
        Write-Output "  NOTE: $($stale.Count) stale READU lock(s) from an earlier run are still held."
        Write-Output '  They are on retired random ids and cannot affect this run.  They clear'
        Write-Output '  with "sd -CLEANUP" (elevated) or at the next cycle, which rebuilds the'
        Write-Output '  shared memory segment.'
    } else {
        Write-Output '  no stale record locks'
    }

    # A dictionary field, or UPDATE.RECORD answers "No fields to display / edit"
    # and there is nothing to type into.
    $seedSrc = @"
* ZZEDKSEED - dictionary and seed records for verify-editkeys.ps1.
   open 'DICT','$FILE' to df then
      r = 'D' ; r<2> = 1 ; r<3> = '' ; r<4> = 'NAME' ; r<5> = '20L' ; r<6> = 'S'
      write r to df,'NAME'
      print 'DICT=OK'
   end else
      print 'DICT=FAIL'
   end
end
"@
    [IO.File]::WriteAllText((Join-Path $bp 'ZZEDKSEED'),
                            ($seedSrc -replace "`r`n", "`n"),
                            (New-Object Text.UTF8Encoding $false))
    $d = Invoke-SD ("`n" + (@('TERM 200,9999', 'BASIC BP ZZEDKSEED', 'RUN BP ZZEDKSEED', 'OFF') -join "`n") + "`n") 90
    if ($d -notmatch 'DICT=OK') {
        Write-Output '  --- SD said: ---'
        Write-Output $d
        Write-Output 'verify-editkeys: could not build the test dictionary'
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }
    Write-Output "  $FILE created with a NAME field"

    # -----------------------------------------------------------------------
    # SED.  Empty record, so the typing is the whole content.
    #   type AB, erase byte, C  ->  AC if the erase went backwards
    function Test-Sed([string]$mid) {
        $id = New-Id
        $body = "`n" + (@('TERM 200,24', "SED $FILE $id", ('AB' + $mid + 'C' + $SAVEQUIT), "CT $FILE $id", 'OFF') -join "`n") + "`n"
        return (Get-Field1 (Invoke-SD $body))
    }

    Write-Output ''
    Write-Output '=== 1. SED, the erase keys ==============================================='
    Write-Output '  Type AB, the erase byte, then C.  AC means it erased backwards, which is'
    Write-Output '  what a Backspace key does; ABC means it went forwards or did nothing.'

    Note 'SED: DEL (0x7F) erases backwards'    'AC'  (Test-Sed ([char]127))
    Note 'SED: Ctrl-H (0x08) erases backwards' 'AC'  (Test-Sed ([char]8))
    Note 'SED control: no erase byte at all'   'ABC' (Test-Sed '')

    Write-Output ''
    Write-Output '=== 2. SED, the keys that must not have moved ============================'
    Write-Output '  The arrows already worked here and the change must not disturb them.'
    Write-Output '  Type AB, LEFT, X: AXB if LEFT moved the cursor.'

    function Test-SedLeft([string]$seq) {
        $id = New-Id
        $body = "`n" + (@('TERM 200,24', "SED $FILE $id", ('AB' + $seq + 'X' + $SAVEQUIT), "CT $FILE $id", 'OFF') -join "`n") + "`n"
        return (Get-Field1 (Invoke-SD $body))
    }
    Note 'SED: LEFT as ESC [ D' 'AXB' (Test-SedLeft ($ESC + '[D'))
    Note 'SED: LEFT as ESC O D' 'AXB' (Test-SedLeft ($ESC + 'OD'))
    Note 'SED: LEFT as Ctrl-B'  'AXB' (Test-SedLeft ([char]2))

    Write-Output ''
    Write-Output '  AND THE DELETE KEY MUST STILL DELETE FORWARDS, or the two keys have been'
    Write-Output '  swapped rather than fixed.  It has to be tested with the cursor NOT at'
    Write-Output '  the end of the line, where deleting forwards would do nothing and the'
    Write-Output '  check would pass on a Delete key that had stopped working altogether.'
    Write-Output '  Type AB, LEFT, Delete: A, because B is the character removed.'

    function Test-SedDelete() {
        $id = New-Id
        $keys = 'AB' + $ESC + '[D' + $ESC + '[3~' + $SAVEQUIT
        $body = "`n" + (@('TERM 200,24', "SED $FILE $id", $keys, "CT $FILE $id", 'OFF') -join "`n") + "`n"
        return (Get-Field1 (Invoke-SD $body))
    }
    Note 'SED: Delete key (ESC [ 3 ~) deletes forwards' 'A' (Test-SedDelete)

    # -----------------------------------------------------------------------
    # UPDATE.RECORD.  The field starts as AB with the cursor before the A, in
    # insert mode - measured, typing XY into a field holding AB gives XYAB.
    function Set-Seed([string]$id) {
        $src = "* ZZEDKREC`n   open '$FILE' to f then write 'AB' to f,'$id' ; print 'SEED=OK' end else print 'SEED=FAIL'`nend`n"
        [IO.File]::WriteAllText((Join-Path $bp 'ZZEDKREC'), $src, (New-Object Text.UTF8Encoding $false))
        return (Invoke-SD ("`n" + (@('TERM 200,9999', 'BASIC BP ZZEDKREC', 'RUN BP ZZEDKREC', 'OFF') -join "`n") + "`n") 90)
    }

    function Test-Updrec([string]$keys) {
        $id = New-Id
        $s = Set-Seed $id
        if ($s -notmatch 'SEED=OK') { return '<seed failed>' }
        $body = "`n" + (@('TERM 200,24', "UPDATE.RECORD $FILE $id", ($keys + $SAVEQUIT), "CT $FILE $id", 'OFF') -join "`n") + "`n"
        return (Get-Field1 (Invoke-SD $body))
    }

    Write-Output ''
    Write-Output '=== 3. UPDATE.RECORD, the erase keys ====================================='
    Write-Output '  The field holds AB and the cursor starts before the A.  Type X to get'
    Write-Output '  XAB, then the erase byte: AB if it erased the X backwards, XB if it'
    Write-Output '  deleted the A forwards.'

    Note 'UPDREC: DEL (0x7F) erases backwards'    'AB'  (Test-Updrec ('X' + [char]127))
    Note 'UPDREC: Ctrl-H (0x08) erases backwards' 'AB'  (Test-Updrec ('X' + [char]8))
    Note 'UPDREC control: no erase byte at all'   'XAB' (Test-Updrec 'X')

    Write-Output ''
    Write-Output '=== 4. UPDATE.RECORD, the arrows that used to type themselves ============'
    Write-Output '  These were bound to nothing, so get.key fell through and the bytes'
    Write-Output '  landed in the record as text: RIGHT then X used to save CXAB.'

    Note 'UPDREC: RIGHT as ESC [ C' 'AXB' (Test-Updrec ($ESC + '[C' + 'X'))
    Note 'UPDREC: RIGHT as ESC O C' 'AXB' (Test-Updrec ($ESC + 'OC' + 'X'))
    Note 'UPDREC: RIGHT as Ctrl-F'  'AXB' (Test-Updrec ([char]6 + 'X'))
    Note 'UPDREC: Delete key (ESC [ 3 ~) deletes forwards' 'B' (Test-Updrec ($ESC + '[3~'))

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== Summary =============================================================='
    $results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
    $passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
    Write-Output ("  {0} of {1} checks passed" -f $passed, $results.Count)
}
finally {
    # Take the test file away.  DELETE.FILE asks for confirmation, so answer it;
    # an unanswered prompt here would hang the tidy-up rather than the test.
    Write-Output ''
    $null = Invoke-SD ("`n" + (@('TERM 200,9999', "DELETE.FILE $FILE", 'Y', 'OFF') -join "`n") + "`n")
    foreach ($n in @('ZZEDKSEED', 'ZZEDKREC')) {
        foreach ($d in @($bp, (Join-Path $acctDir 'BP.OUT'))) {
            $p = Join-Path $d $n
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
        }
    }
    Write-Output "verify-editkeys: removed $FILE and the helper programs"
    try { Stop-Transcript | Out-Null } catch { }
}

if ($failed) { exit 1 } else { exit 0 }
