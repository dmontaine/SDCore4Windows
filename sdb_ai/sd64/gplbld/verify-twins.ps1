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
#   B. CASE and NO.CASE are not words   - CREATE.FILE zzx CASE and ... NO.CASE
#      of CREATE.FILE (8 Nov 26)           each make no file.
#   C. an OLD case-sensitive file with a - built only by sd -internal (a
#      twin is refused by CONFIGURE.FILE   create.file statement with flags 4,
#                                          program zztwfix); two records
#                                          'jack'/'JACK' planted; CONFIGURE.FILE
#                                          NO.CASE answers 10177 / ER$TWIN and
#                                          the file is LEFT case sensitive with
#                                          BOTH records - nothing lost.
#   D. the control - a single-spelling   - CONFIGURE.FILE NO.CASE on a CASE file
#      file converts cleanly              holding only 'jack' succeeds and the
#                                          record survives.
#
# ***WHY IT MUST BE ELEVATED AND WHY IT IS NOT verify-callcase's neighbor.***
# The design named VerifyInstall1, but building a case-sensitive fixture is the
# one thing only sd -internal can do (op_dio1.c honors KEEPCASE in internal
# mode alone), and sd -internal needs elevation (check_admin).  So it runs in
# VerifyInstall2, elevated, where verify-dictrename already drives sd -internal.
#
# ***RED BEFORE THE FIX.***  Legs A and C are the decisive pre-fix rows: on a
# build without op_dio1.c's default, a fresh file is case SENSITIVE, so leg A
# stores two records, and the CONFIGURE rebuild in leg C silently drops one
# instead of refusing.  assert-current refuses this on an install without the
# change, so the red half is the scratch run recorded in RELEASE_1.1 5.
#
# BOUNDED: every SD session is a task in the SDSYS seat (sdsys-seat.ps1), killed
# after the timeout; it plants only zztw* names in SDSYS and deletes them, and
# asserts none is left.  ***SDSYS MUST BE SIGNED IN*** (RELEASE_1.1 76).
#
# 8 Nov 26 - from Linux 7de9f2c0 (S.87 batch 13 part 6): CREATE.FILE lost the
# words CASE and NO.CASE.  Leg B now asserts both make no file, and the
# case-sensitive fixtures of C and D are made by bp zztwfix, a create.file
# statement with flags 4 run in the internal session, as Linux's sandbox-nocase
# now does.  Not run since the change.

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

# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT (sdsys-seat.ps1; verify-createaccount
# was the pilot).  THE "LOGTO SDSYS" PREFIX THIS USED TO SEND IS REFUSED (10002)
# FROM ANY SESSION THAT DID NOT START AS THE OS SDSYS ACCOUNT with an elevated,
# interactive token, and an elevated Don is not one.  So the commands go to a task
# inside SDSYS's own live session and the text comes back through a file; the TERM
# line this sent first is added by the helper.  A seat that did not run THROWS
# rather than returning ''.  SDSYS must be signed in: `query session` shows its row.
# Both doors are the seat's: plain for the ordinary legs, -Internal for the one
# thing only sd -internal can do (build a case-sensitive file).
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 180) {
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec)
}
function Invoke-SDInternal([string[]]$commands, [int]$TimeoutSec = 180) {
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec -Internal)
}
function Listed([string]$text) {
    $m = [regex]::Match($text, '(?m)^(\d+) record\(s\) (listed|counted)')
    if ($m.Success) { return [int]$m.Groups[1].Value } else { return -1 }
}
# A LIST row for exactly this id, case sensitive: id at line start, 2+ spaces.
function HasRow([string]$text, [string]$id) {
    return ($text -cmatch ('(?m)^' + [regex]::Escape($id) + '(\s{2,}|\s*$)'))
}

$names = @('zztwn', 'zztwc', 'zztwk', 'zzx', 'zztwe', 'zztwc.dic', 'zztwk.dic', 'bp\zztwfix', 'bp.out\zztwfix')
function Cleanup {
    $null = Invoke-SD @(
        'DELETE.FILE zztwn FORCE', 'DELETE.FILE zztwc FORCE',
        'DELETE.FILE zztwk FORCE', 'DELETE.FILE zzx FORCE',
        'DELETE.FILE zztwe FORCE')
    foreach ($p in @('bp\zztwfix', 'bp.out\zztwfix')) {
        $full = Join-Path $sdsys $p
        if (Test-Path -LiteralPath $full) { Remove-Item -LiteralPath $full -Force -Confirm:$false }
    }
    $left = @()
    foreach ($n in $names) {
        if (Test-Path -LiteralPath (Join-Path $sdsys $n)) { $left += $n }
    }
    return $left
}

# 8 Nov 26 - the fixture builder for legs C and D (from Linux 7de9f2c0): zztwc
# holds jack and JACK, zztwk holds jack only; each has a dictionary and a VOC
# record.  Run in the internal session, the only one whose KEEPCASE (flags 4)
# the kernel honors.
$fixLines = @(
    "   nm = 'zztwc':@fm:'zztwk'",
    "   for i = 1 to 2",
    "      create.file nm<i> dynamic flags 4 on error crt 'FIX create failed ':nm<i> ; stop",
    "      create.file nm<i>:'.dic' dynamic flags 4 on error crt 'FIX create failed dict ':nm<i> ; stop",
    "   next i",
    "   openpath 'zztwc' to f else crt 'FIX no zztwc' ; stop",
    "   write 'x' to f, 'jack' ; write 'y' to f, 'JACK'",
    "   openpath 'zztwk' to f else crt 'FIX no zztwk' ; stop",
    "   write 'x' to f, 'jack'",
    "   open 'voc' to v else crt 'FIX no voc' ; stop",
    "   write 'F':@fm:'zztwc':@fm:'zztwc.dic' to v, 'zztwc'",
    "   write 'F':@fm:'zztwk':@fm:'zztwk.dic' to v, 'zztwk'",
    "   crt 'FIX done'",
    "end")

# 20 Sep 26 - RELEASE_1.1 76: PROVE BOTH SEAT DOORS BEFORE PLANTING ANYTHING, so a
# missing SDSYS session is exit 2 ("could not run"), not a thrown error at the
# first SD call that reads as a product failure.  See sdsys-seat.ps1.
Assert-SdSeat -Label 'verify-twins'
Assert-SdSeat -Label 'verify-twins' -Internal

$exit = 2
try {
    Write-Output '  --- cleaning any earlier fixture ---'
    $null = Cleanup

    # Records are planted with COPY, not ED: ED driven down a pipe never wrote
    # the record (measured b161) AND left the file open in a session that then
    # DENIED CONFIGURE.FILE exclusive access.  COPY writes a record and its
    # session ends cleanly, so the file is free for CONFIGURE.FILE.  The source
    # is SDSYS's own VOC record 'who' - any existing record does; only its id in
    # the target matters here, never its data.  COUNT, not LIST, reports the
    # record tally ('n record(s) counted').

    # ---- A. a fresh file is NOCASE ----------------------------------------
    # jack then JACK: on a NOCASE file the second is a rewrite of the first, so
    # one record remains, stored under the first spelling (jack).
    $a = Invoke-SD @(
        'CREATE.FILE zztwn',
        'COPY FROM VOC TO zztwn who,jack OVERWRITING',
        'COPY FROM VOC TO zztwn who,JACK OVERWRITING',
        'COUNT zztwn',
        'LIST zztwn @ID')
    $naCount = Listed $a
    Row 'A: a fresh file folds - writing jack then JACK leaves ONE record' ($naCount -eq 1) "COUNT said $naCount"
    $storedLower = HasRow $a 'jack'
    $storedUpper = HasRow $a 'JACK'
    Row 'A: the surviving id is the first spelling, jack (not JACK)' ($storedLower -and -not $storedUpper) "jack=$storedLower JACK=$storedUpper"

    # ---- B. CASE and NO.CASE are not words of CREATE.FILE (8 Nov 26) ------
    # The session must have answered something: an empty reply would pass the
    # no-file rows having measured nothing.
    $b = Invoke-SD @('CREATE.FILE zzx CASE')
    Row 'B: the session answered CREATE.FILE ... CASE' ($b.Trim().Length -gt 0) 'empty reply'
    Row 'B: CREATE.FILE ... CASE makes no file' (-not (Test-Path -LiteralPath (Join-Path $sdsys 'zzx'))) "$b"
    $b2 = Invoke-SD @('CREATE.FILE zzx NO.CASE')
    Row 'B: the session answered CREATE.FILE ... NO.CASE' ($b2.Trim().Length -gt 0) 'empty reply'
    Row 'B: CREATE.FILE ... NO.CASE makes no file either' (-not (Test-Path -LiteralPath (Join-Path $sdsys 'zzx'))) "$b2"

    # ---- C. an old CASE file with a twin: CONFIGURE.FILE refuses ----------
    # The internal session is the only maker of a CASE file, and the whole
    # fixture - both files and their records - is made by bp zztwfix in that ONE
    # session, which then ends, so nothing holds zztwc when CONFIGURE.FILE (a
    # separate session) asks for exclusive access.
    $fixSrc = Join-Path $sdsys 'bp\zztwfix'
    Write-Output ("  fixture program: " + $fixSrc)
    [System.IO.File]::WriteAllText($fixSrc, (($fixLines -join "`n") + "`n"), (New-Object System.Text.ASCIIEncoding))
    $mk = Invoke-SDInternal @(
        'BASIC bp zztwfix',
        'RUN bp zztwfix',
        'COUNT zztwc')
    Write-Output $mk
    Row 'C-setup: bp zztwfix ran to its end (FIX done)' ($mk -match 'FIX done') "$mk"
    $caseMade = (Test-Path -LiteralPath (Join-Path $sdsys 'zztwc'))
    Row 'C-setup: sd -internal built a case-sensitive file' $caseMade
    $planted = Listed $mk
    Row 'C-setup: the CASE file holds both jack and JACK (2 records)' ($planted -eq 2) "COUNT said $planted"

    $conf = Invoke-SD @('CONFIGURE.FILE zztwc NO.CASE')
    $refused = ($conf -match '10177' -or $conf -match 'differ only by case')
    Row 'C: CONFIGURE.FILE NO.CASE refuses the twinned file (10177)' $refused "$conf"

    $after = Invoke-SD @('COUNT zztwc')
    $stillTwo = (Listed $after) -eq 2
    Row 'C: the file is LEFT AS IT WAS - both records survive, nothing lost' $stillTwo "COUNT said $(Listed $after)"

    # ---- D. control: a single-spelling CASE file converts cleanly ---------
    # zztwk was made by bp zztwfix in leg C's setup.
    if (Test-Path -LiteralPath (Join-Path $sdsys 'zztwk')) {
        $conf2 = Invoke-SD @('CONFIGURE.FILE zztwk NO.CASE', 'COUNT zztwk')
        $ok = ((Listed $conf2) -eq 1) -and ($conf2 -notmatch '10177')
        Row 'D CONTROL: a file with only jack converts to NOCASE and keeps it' $ok "$conf2"
    } else {
        Row 'D CONTROL: fixture built' $false 'could not build zztwk'
    }

    # ---- E. COPY onto the same record with DELETING keeps it (RELEASE_1.1 36)
    # On a NOCASE file jack and JACK are one record, so COPY ... jack,JACK
    # OVERWRITING DELETING wrote the record and then deleted the only copy.
    # CONTROL: a copy to a DIFFERENT id with DELETING must still move it, or
    # the fix would be a DELETING that no longer deletes anything.
    $e = Invoke-SD @(
        'CREATE.FILE zztwe',
        'COPY FROM VOC TO zztwe who,jack',
        'COPY FROM zztwe jack,JACK OVERWRITING DELETING',
        'COUNT zztwe')
    Row 'E: COPY jack,JACK OVERWRITING DELETING keeps the one record' ((Listed $e) -eq 1) "COUNT said $(Listed $e)"
    Row 'E: and says it was copied onto itself (10187)' ($e -match 'was copied onto itself, so it was not deleted') "$e"
    $e2 = Invoke-SD @('COPY FROM zztwe jack,jill DELETING', 'COUNT zztwe', 'LIST zztwe @ID')
    Row 'E CONTROL: COPY jack,jill DELETING still moves it (one record, stored jill)' `
        (((Listed $e2) -eq 1) -and (HasRow $e2 'jill') -and -not (HasRow $e2 'jack')) "$e2"

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
