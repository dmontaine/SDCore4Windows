# verify-twins.ps1 - no two record ids can differ only by case.
# RELEASE_1.1_FIXES.md 5, D2 (owner, 14 Sep 2026: "whatever is needed to
# prevent two record ids that differ only by case, anywhere").  ***ELEVATED
# POWERSHELL.***
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-twins.ps1
#
# Exit 0 every check passed, 1 a check failed, 2 the fixture could not be built
# (never a FAIL).
#
# WHAT IT MEASURES, AND WHY EACH LEG.  The kernel makes every hashed file it
# creates case insensitive (gplsrc\op_dio1.c), so a twin cannot be written and
# a rebuild that would keep only one is refused.  The legs:
#   A. a fresh file is NOCASE            - CREATE.FILE zztwn, then WRITE 'jack'
#                                          and 'JACK'; LIST shows ONE record,
#                                          stored 'jack' (the first spelling).
#   B. CASE is refused for a normal user - CREATE.FILE zzx CASE, not internal,
#                                          answers 10176 and makes no file.
#   C. an OLD case-sensitive file with a - built only by sd -internal (the one
#      twin is refused by CONFIGURE.FILE   way to make a CASE file); two records
#                                          'jack'/'JACK' planted; CONFIGURE.FILE
#                                          NO.CASE answers 10177 / ER$TWIN and
#                                          the file is LEFT case sensitive with
#                                          BOTH records - nothing lost.
#   D. the control - a single-spelling   - CONFIGURE.FILE NO.CASE on a CASE file
#      file converts cleanly              holding only 'jack' succeeds and the
#                                          record survives.
#
# ***WHY IT MUST BE ELEVATED AND WHY IT IS NOT verify-callcase's neighbour.***
# The design named VerifyInstall1, but building a case-sensitive fixture is the
# one thing only sd -internal can do (op_dio1.c honours KEEPCASE in internal
# mode alone), and sd -internal needs elevation (check_admin).  So it runs in
# VerifyInstall2, elevated, where verify-dictrename already drives sd -internal.
#
# ***RED BEFORE THE FIX.***  Legs A and C are the decisive pre-fix rows: on a
# build without op_dio1.c's default, a fresh file is case SENSITIVE, so leg A
# stores two records, and the CONFIGURE rebuild in leg C silently drops one
# instead of refusing.  assert-current refuses this on an install without the
# change, so the red half is the scratch run recorded in RELEASE_1.1 5.
#
# BOUNDED: every SD session is a job, killed after the timeout; it plants only
# zztw* names in SDSYS and deletes them, and asserts none is left.

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-twins: refusing - see assert-current above'
    exit 2
}

$appDir = Join-Path $env:ProgramFiles 'SD'
$sdExe  = Join-Path $appDir 'usr\bin\sd.exe'
$sdsys  = Join-Path $env:ProgramData 'SD\sdsys'

Write-Output '===== verify-twins.ps1 ====='
Write-Output ("  sd.exe : " + $sdExe)
Write-Output ("  sdsys  : " + $sdsys)
if (-not (Test-Path -LiteralPath $sdExe)) { Write-Output 'verify-twins: no sd.exe'; exit 2 }

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ("  [PASS] " + $name) }
    else { $script:fail++; Write-Output ("  [FAIL] " + $name + ($(if ($detail) { "  ->  $detail" } else { '' }))) }
}

# A LOGTO SDSYS session (elevated lands in SDSYS anyway; explicit for clarity).
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe 2>&1 } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else { Stop-Job $job; $out = Receive-Job $job; $out += "*** SD did not finish in $TimeoutSec s" }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}
# sd -internal, the only way to build a case-sensitive file.  It runs in SDSYS.
function Invoke-SDInternal([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe '-internal' 2>&1 } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else { Stop-Job $job; $out = Receive-Job $job; $out += "*** SD -internal did not finish in $TimeoutSec s" }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}
function Listed([string]$text) {
    $m = [regex]::Match($text, '(?m)^(\d+) record\(s\) listed')
    if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}
# A LIST row for exactly this id, case sensitive: id at line start, 2+ spaces.
function HasRow([string]$text, [string]$id) {
    return ($text -cmatch ('(?m)^' + [regex]::Escape($id) + '(\s{2,}|\s*$)'))
}

$names = @('zztwn', 'zztwc', 'zztwk', 'zzx')
function Cleanup {
    $null = Invoke-SD @(
        'DELETE.FILE zztwn FORCE', 'DELETE.FILE zztwc FORCE',
        'DELETE.FILE zztwk FORCE', 'DELETE.FILE zzx FORCE')
    $left = @()
    foreach ($n in $names) {
        if (Test-Path -LiteralPath (Join-Path $sdsys $n)) { $left += $n }
    }
    return $left
}

$exit = 2
try {
    Write-Output '  --- cleaning any earlier fixture ---'
    $null = Cleanup

    # ---- A. a fresh file is NOCASE ----------------------------------------
    # Two records are written through the editor: jack, then JACK.  On a
    # NOCASE file the second is a rewrite of the first, so one record remains,
    # stored under the first spelling (jack).
    $a = Invoke-SD @(
        'CREATE.FILE zztwn',
        'ED zztwn jack', 'I', 'ok-lower', '.', 'FI',
        'ED zztwn JACK', 'I', 'ok-UPPER', '.', 'FI',
        'LIST zztwn ID.SUP')
    $naCount = Listed $a
    Row 'A: a fresh file folds - writing jack then JACK leaves ONE record' ($naCount -eq 1) "LIST counted $naCount"
    $storedLower = HasRow $a 'jack'
    $storedUpper = HasRow $a 'JACK'
    Row 'A: the surviving id is the first spelling, jack (not JACK)' ($storedLower -and -not $storedUpper) "jack=$storedLower JACK=$storedUpper"

    # ---- B. CASE is refused for a normal (non-internal) session -----------
    $b = Invoke-SD @('CREATE.FILE zzx CASE')
    $bRefused = ($b -match '10176' -or $b -match 'case insensitive in every file')
    $bNoFile = -not (Test-Path -LiteralPath (Join-Path $sdsys 'zzx'))
    Row 'B: CREATE.FILE ... CASE is refused outside internal mode (10176)' $bRefused
    Row 'B: and no file was created' $bNoFile

    # ---- C. an old CASE file with a twin: CONFIGURE.FILE refuses ----------
    # Build the fixture with sd -internal, the only maker of a CASE file.
    $mk = Invoke-SDInternal @('CREATE.FILE zztwc CASE')
    $caseMade = (Test-Path -LiteralPath (Join-Path $sdsys 'zztwc'))
    Row 'C-setup: sd -internal built a case-sensitive file' $caseMade "$mk"
    if ($caseMade) {
        # Plant both spellings; on a CASE file these are two records.
        $plant = Invoke-SDInternal @(
            'ED zztwc jack', 'I', 'keep-lower', '.', 'FI',
            'ED zztwc JACK', 'I', 'keep-UPPER', '.', 'FI',
            'LIST zztwc ID.SUP')
        $planted = Listed $plant
        Row 'C-setup: the CASE file holds both jack and JACK (2 records)' ($planted -eq 2) "counted $planted"

        $conf = Invoke-SD @('CONFIGURE.FILE zztwc NO.CASE')
        $refused = ($conf -match '10177' -or $conf -match 'differ only by case')
        Row 'C: CONFIGURE.FILE NO.CASE refuses the twinned file (10177)' $refused "$conf"

        $after = Invoke-SD @('LIST zztwc ID.SUP')
        $stillTwo = (Listed $after) -eq 2
        Row 'C: the file is LEFT AS IT WAS - both records survive, nothing lost' $stillTwo "counted $(Listed $after)"
    }

    # ---- D. control: a single-spelling CASE file converts cleanly ---------
    $mk2 = Invoke-SDInternal @('CREATE.FILE zztwk CASE')
    if (Test-Path -LiteralPath (Join-Path $sdsys 'zztwk')) {
        $null = Invoke-SDInternal @('ED zztwk jack', 'I', 'only-one', '.', 'FI')
        $conf2 = Invoke-SD @('CONFIGURE.FILE zztwk NO.CASE', 'LIST zztwk ID.SUP')
        $ok = ((Listed $conf2) -eq 1) -and ($conf2 -notmatch '10177')
        Row 'D CONTROL: a file with only jack converts to NOCASE and keeps it' $ok "$conf2"
    } else {
        Row 'D CONTROL: fixture built' $false 'could not build zztwk'
    }

    $exit = $(if ($fail -eq 0) { 0 } else { 1 })
}
finally {
    Write-Output '  --- cleanup ---'
    $left = Cleanup
    Row 'cleanup: no fixture file left in SDSYS' ($left.Count -eq 0) ("left: " + ($left -join ', '))
    if ($left.Count -ne 0 -and $exit -eq 0) { $exit = 1 }
}

Write-Output ''
Write-Output ("verify-twins: $pass passed, $fail failed.")
if ($exit -eq 0) { Write-Output 'verify-twins: PASSED - no two ids can differ only by case; an old twin is refused, not silently merged.' }
exit $exit
