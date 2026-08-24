# verify-lineendings.ps1 - PROJECT_STATUS.md section 7 step 16 (a).
#
#   powershell -File verify-lineendings.ps1
#
# Exit 0 all decisive checks passed, 1 a check failed, 2 refused/VOID.
#
# WHAT IT ASKS.  A directory file exists so that EXTERNAL EDITORS can edit its
# records.  On Windows those editors write CRLF.  Before this fix, every
# CRLF-terminated field came back with a trailing CR, and because READCSV
# compiles to OP.READSEQ (BCOMP:10230) a conformant RFC 4180 CSV lost the last
# field of every row to a stray CR.  These are the readings that proved it,
# taken on the 11:15:29 install and kept here as the "before" column:
#
#   directory record, CRLF   field 1 LEN=6 LASTCHAR=13   (ALPHA + CR)
#   directory record, LF     field 1 LEN=5 LASTCHAR=65   (ALPHA)
#   READSEQ, CRLF            LINE 1 LEN=6 LASTCHAR=13
#   READCSV, CRLF            row 1 Q LEN=3 LAST=13        (B1 + CR)
#
# THE STRADDLE CHECK IS THE REASON THIS FILE EXISTS RATHER THAN A ONE-LINER.
# Every one of these readers is CHUNKED - SEQ_BUFFER_SIZE is 2048 - so a CRLF
# can land with the CR ending one buffer and the LF starting the next.  A fix
# that inspects "the byte before the LF" is correct on every small fixture and
# wrong about once per 2 KB of real data.  No other check here would catch it,
# and the failure would present as stray CRs with no pattern.  Check 4 builds
# a record whose CRLF sits exactly on the boundary.
#
# AND A LONE CR MUST SURVIVE, because it is data and not a terminator.  A fix
# that strips every CR would pass checks 1-4 and silently corrupt binary-ish
# text.  Check 5 is the control on the fix rather than on the defect.
#
# NOT SHIPPED - must be on assert-current.ps1's $neverShipped list, added in
# the same commit that creates this file (section 7 step 7's rule).

param(
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$acct   = 'C:\ProgramData\SD\user_accounts\don'
$bp     = Join-Path $acct 'bp'

$script:checks = @()
function Note($check, $expected, $got, $decisive = $true) {
    $pass = ($expected -eq $got)
    $script:checks += [pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' }); Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    }
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}
function Fail($msg) { Write-Host ''; Write-Host "verify-lineendings: $msg"; exit 2 }
function Step($n, $m) { Write-Host ''; Write-Host "== [$n] $m" }

# ---- the install must match source, or nothing here describes the build ----
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'assert-current refuses - the install does not match source.' }
if (-not (Test-Path -LiteralPath $sdExe)) { Fail "no sd.exe at $sdExe" }
if (-not (Test-Path -LiteralPath $bp))    { Fail "no account bp directory at $bp" }

Write-Host 'verify-lineendings - section 7 step 16 (a)'
Write-Host "  sd.exe : $sdExe"
Write-Host "  bp dir : $bp"

# ---- fixtures -------------------------------------------------------------
# Words deliberately END IN DIFFERENT LETTERS so a "last character" reading
# cannot be right by coincidence.
$names = @('ZZLECRLF','ZZLELF','ZZLESEQ','ZZLESTRD','ZZLELONE','ZZLECSV',
           'ZZLEWSEQ','ZZLEWCSV','ZZLEWREC')
function Remove-Fixtures {
    foreach ($n in $names + @('ZZLETEST')) {
        foreach ($d in @($bp, (Join-Path $acct 'BP.OUT'), (Join-Path $acct 'cat'))) {
            $p = Join-Path $d $n
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
        }
    }
}
Remove-Fixtures

Step 1 'Planting fixtures from OUTSIDE SD - which is what an editor does'

# 1/2: the same three fields, CRLF and LF.  Different final letters.
$flds = @('ALPHA','BETAX','GAMMAY')
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLECRLF'), [Text.Encoding]::ASCII.GetBytes(($flds -join "`r`n")))
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLELF'),   [Text.Encoding]::ASCII.GetBytes(($flds -join "`n")))

# 3: READSEQ source, CRLF.
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLESEQ'), [Text.Encoding]::ASCII.GetBytes("ONEA`r`nTWOB`r`nTHREEC"))

# 4: THE STRADDLE.  Pad so the CR is the LAST byte of a 2048-byte buffer and
#    the LF is the first byte of the next.  Line 1 is 2047 'P' then CR, LF.
$pad = ('P' * 2047)
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLESTRD'),
    [Text.Encoding]::ASCII.GetBytes($pad + "`r`n" + "AFTERQ`r`n"))
Write-Host "   ZZLESTRD: CR at offset 2047, LF at 2048 - exactly on the SEQ_BUFFER_SIZE boundary"

# 5: A LONE CR, no LF anywhere.  It is DATA and must come back intact.
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLELONE'), [Text.Encoding]::ASCII.GetBytes("LEFT`rRIGHTZ"))

# 6: a conformant RFC 4180 CSV - CRLF terminated, which is what Excel writes.
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLECSV'), [Text.Encoding]::ASCII.GetBytes("A1,B1`r`nA2,B2`r`n"))

# The write targets must exist for OPENSEQ ... OVERWRITE; ZZLEWREC is created
# by SD's own record write and must NOT be pre-made.
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLEWSEQ'), @())
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLEWCSV'), @())

foreach ($n in @('ZZLECRLF','ZZLELF','ZZLESEQ','ZZLESTRD','ZZLELONE','ZZLECSV')) {
    $p = Join-Path $bp $n
    if (-not (Test-Path -LiteralPath $p)) { Remove-Fixtures; Fail "fixture $n was not created - nothing can be measured." }
    Write-Host ("   {0,-9} {1} bytes" -f $n, (Get-Item -LiteralPath $p).Length)
}

# REFUSE THE NULL CASE: the CRLF and LF fixtures must actually differ.
$lenA = (Get-Item -LiteralPath (Join-Path $bp 'ZZLECRLF')).Length
$lenB = (Get-Item -LiteralPath (Join-Path $bp 'ZZLELF')).Length
if ($lenA -eq $lenB) { Remove-Fixtures; Fail 'the CRLF and LF fixtures are the same size - they cannot differ in terminator.' }

Step 2 'Reading them back through SD'

$prog = @'
      OPEN 'BP' TO F ELSE
         CRT 'OPEN BP FAILED'
         STOP
      END
*
* ---- WRITE SIDE, step 16 (b).  What does SD emit? ----
      OPENSEQ 'BP', 'ZZLEWSEQ' OVERWRITE TO WF ELSE
         CRT 'OPENSEQ ZZLEWSEQ FAILED'
         STOP
      END
      WRITESEQ 'ONE' TO WF ELSE CRT 'WRITESEQ FAILED'
      WRITESEQ 'TWO' TO WF ELSE CRT 'WRITESEQ FAILED'
      CLOSESEQ WF
*
      OPENSEQ 'BP', 'ZZLEWCSV' OVERWRITE TO VF ELSE
         CRT 'OPENSEQ ZZLEWCSV FAILED'
         STOP
      END
      WRITECSV 'A1', 'B1' TO VF ELSE CRT 'WRITECSV FAILED'
      WRITECSV 'A2', 'B2' TO VF ELSE CRT 'WRITECSV FAILED'
      CLOSESEQ VF
*
* A directory-file RECORD write: field marks become the newline on disk.
      REC = 'RA':@FM:'RB':@FM:'RC'
      WRITE REC TO F, 'ZZLEWREC' ELSE CRT 'WRITE RECORD FAILED'
      CRT 'WRITES DONE'
      IDS = 'ZZLECRLF':@FM:'ZZLELF':@FM:'ZZLELONE'
      FOR R = 1 TO 3
         ID = IDS<R>
         READ REC FROM F, ID ELSE
            CRT 'READFAIL ':ID
            CONTINUE
         END
         N = DCOUNT(REC, @FM)
         CRT 'REC ':ID:' FIELDS=':N:' LEN=':LEN(REC)
         FOR I = 1 TO N
            FLD = REC<I>
            IF LEN(FLD) THEN LC = SEQ(FLD[1]) ELSE LC = -1
            CRT '  FLD ':ID:' ':I:' LEN=':LEN(FLD):' LAST=':LC
         NEXT I
      NEXT R
*
      GOSUB SEQ.TEST
      GOSUB STRD.TEST
      GOSUB CSV.TEST
      STOP
*
SEQ.TEST:
      OPENSEQ 'BP', 'ZZLESEQ' READONLY TO SF ELSE
         CRT 'OPENSEQ ZZLESEQ FAILED'
         RETURN
      END
      LN = 0
      LOOP
         READSEQ L FROM SF ELSE EXIT
         LN = LN + 1
         IF LEN(L) THEN LC = SEQ(L[1]) ELSE LC = -1
         CRT 'SEQ ':LN:' LEN=':LEN(L):' LAST=':LC
      REPEAT
      CLOSESEQ SF
      RETURN
*
STRD.TEST:
      OPENSEQ 'BP', 'ZZLESTRD' READONLY TO TF ELSE
         CRT 'OPENSEQ ZZLESTRD FAILED'
         RETURN
      END
      LN = 0
      LOOP
         READSEQ L FROM TF ELSE EXIT
         LN = LN + 1
         IF LEN(L) THEN LC = SEQ(L[1]) ELSE LC = -1
         CRT 'STRD ':LN:' LEN=':LEN(L):' LAST=':LC
      REPEAT
      CLOSESEQ TF
      RETURN
*
CSV.TEST:
      OPENSEQ 'BP', 'ZZLECSV' READONLY TO XF ELSE
         CRT 'OPENSEQ ZZLECSV FAILED'
         RETURN
      END
      LN = 0
      LOOP
         READCSV FROM XF TO P, Q ELSE EXIT
         LN = LN + 1
         IF LEN(P) THEN LP = SEQ(P[1]) ELSE LP = -1
         IF LEN(Q) THEN LQ = SEQ(Q[1]) ELSE LQ = -1
         CRT 'CSV ':LN:' PLEN=':LEN(P):' PLAST=':LP:' QLEN=':LEN(Q):' QLAST=':LQ
      REPEAT
      CLOSESEQ XF
      RETURN
      END
'@
# LF only - section 6.
[System.IO.File]::WriteAllBytes((Join-Path $bp 'ZZLETEST'),
    [Text.Encoding]::ASCII.GetBytes((($prog -split "`r?`n") -join "`n") + "`n"))

$body = "`n" + (@('BASIC BP ZZLETEST', 'RUN BP ZZLETEST', 'OFF') -join "`n") + "`n"
$job = Start-Job -ScriptBlock { param($e, $t) $t | & $e } -ArgumentList $sdExe, $body
if (Wait-Job $job -Timeout 120) { $raw = Receive-Job $job } else { Stop-Job $job; $raw = Receive-Job $job; $raw += '*** TIMED OUT' }
Remove-Job $job -Force
$esc = [char]27
$out = (($raw -replace "$esc\[[0-9]*[A-Za-z]", '') | Out-String)

Write-Host '   --- raw output ---'
foreach ($l in ($out -split "`r?`n")) { if ($l.Trim()) { Write-Host "   | $l" } }

# REFUSE THE NULL CASE: if the program never ran, every -notmatch below would
# "pass" by absence.  This is the check that stops a dead run scoring green.
if ($out -notmatch 'REC ZZLECRLF') {
    Remove-Fixtures
    Fail 'the instrument produced no readings - the compile or the RUN failed. Nothing was measured, and that is NOT a pass.'
}

Step 3 'Verdict'

# 1. directory record, CRLF - no field may keep a CR
$crlfFields = [regex]::Matches($out, 'FLD ZZLECRLF (\d+) LEN=(\d+) LAST=(-?\d+)')
Note 'CRLF directory record: fields seen' 3 $crlfFields.Count
$crKept = @($crlfFields | Where-Object { $_.Groups[3].Value -eq '13' }).Count
Note 'CRLF directory record: fields still carrying a CR' 0 $crKept

# 2. control - LF record must be unchanged
$lfFields = [regex]::Matches($out, 'FLD ZZLELF (\d+) LEN=(\d+) LAST=(-?\d+)')
$lfCr = @($lfFields | Where-Object { $_.Groups[3].Value -eq '13' }).Count
Note 'LF control record: fields carrying a CR' 0 $lfCr

# and the two must now agree field for field - that is the whole point
$aLens = ($crlfFields | ForEach-Object { $_.Groups[2].Value }) -join ','
$bLens = ($lfFields   | ForEach-Object { $_.Groups[2].Value }) -join ','
Note 'CRLF and LF records now read identically' $bLens $aLens

# 3. READSEQ
$seq = [regex]::Matches($out, 'SEQ (\d+) LEN=(\d+) LAST=(-?\d+)')
Note 'READSEQ: lines seen' 3 $seq.Count
Note 'READSEQ: lines carrying a CR' 0 @($seq | Where-Object { $_.Groups[3].Value -eq '13' }).Count

# 4. THE STRADDLE - line 1 must be exactly 2047 chars with no CR
$strd = [regex]::Matches($out, 'STRD (\d+) LEN=(\d+) LAST=(-?\d+)')
Note 'straddle: lines seen' 2 $strd.Count
if ($strd.Count -ge 1) {
    Note 'straddle: line 1 length (2047 = the CR was folded, 2048 = it was kept)' '2047' $strd[0].Groups[2].Value
    Note 'straddle: line 1 last char is not a CR' $true ($strd[0].Groups[3].Value -ne '13')
}

# 5. A LONE CR IS DATA - the control on the fix itself
$lone = [regex]::Matches($out, 'REC ZZLELONE FIELDS=(\d+) LEN=(\d+)')
if ($lone.Count -ge 1) {
    # "LEFT" + CR + "RIGHTZ" = 11 bytes, ONE field, CR intact
    Note 'lone CR: record stays one field (a CR is not a terminator)' '1' $lone[0].Groups[1].Value
    Note 'lone CR: record length unchanged (CR preserved as data)' '11' $lone[0].Groups[2].Value
} else {
    Note 'lone CR: record was read' $true $false
}

# 6. READCSV - the last field of every row must be clean
$csv = [regex]::Matches($out, 'CSV (\d+) PLEN=(\d+) PLAST=(-?\d+) QLEN=(\d+) QLAST=(-?\d+)')
Note 'READCSV: rows seen' 2 $csv.Count
Note 'READCSV: last fields carrying a CR' 0 @($csv | Where-Object { $_.Groups[5].Value -eq '13' }).Count
if ($csv.Count -ge 1) {
    Note 'READCSV: last field length (2 = clean, 3 = CR kept)' '2' $csv[0].Groups[4].Value
}

# ---- step 16 (b): what did SD WRITE? --------------------------------------
# Read as raw bytes, because this is the one question a reading through SD
# cannot answer - SD folds CRLF on the way back in, so a round trip would
# report success whatever is on disk.
function Get-Terminator($name) {
    $p = Join-Path $bp $name
    if (-not (Test-Path -LiteralPath $p)) { return 'NOT CREATED' }
    $b = [System.IO.File]::ReadAllBytes($p)
    if ($b.Length -eq 0) { return 'EMPTY' }
    $cr = 0; $lf = 0; $crlf = 0
    for ($i = 0; $i -lt $b.Length; $i++) {
        if ($b[$i] -eq 13) { $cr++; if (($i+1) -lt $b.Length -and $b[$i+1] -eq 10) { $crlf++ } }
        if ($b[$i] -eq 10) { $lf++ }
    }
    Write-Host ("   {0,-9} {1,4} bytes  CR={2} LF={3} pairs={4}  {5}" -f `
        $name, $b.Length, $cr, $lf, $crlf, (($b | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))
    if ($crlf -gt 0 -and $cr -eq $crlf -and $lf -eq $crlf) { return 'CRLF' }
    if ($cr -eq 0 -and $lf -gt 0) { return 'LF' }
    if ($lf -eq 0 -and $cr -gt 0) { return 'CR' }
    return 'MIXED'
}

Write-Host ''
Write-Host '   --- what SD wrote, read as raw bytes ---'
Note 'WRITESEQ writes CRLF'                 'CRLF' (Get-Terminator 'ZZLEWSEQ')
Note 'WRITECSV writes CRLF (RFC 4180)'      'CRLF' (Get-Terminator 'ZZLEWCSV')
Note 'directory-file record write uses CRLF' 'CRLF' (Get-Terminator 'ZZLEWREC')

if (-not $Keep) { Remove-Fixtures } else { Write-Host ''; Write-Host "-Keep: fixtures left in $bp" }

Write-Host ''
$script:checks | Format-Table -AutoSize | Out-String | Write-Host

$failed = @($script:checks | Where-Object { $_.Decisive -eq 'yes' -and $_.Result -eq 'FAIL' })
if ($failed.Count -gt 0) {
    Write-Host "verify-lineendings: FAILED - $($failed.Count) decisive check(s)."
    exit 1
}
Write-Host 'verify-lineendings: PASSED - CRLF is accepted, a lone CR survives, and the straddle case folds.'
exit 0
