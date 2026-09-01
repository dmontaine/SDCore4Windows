# probe-akwrite.ps1 - the normal-path measurement PRE_RELEASE 100 owes.
#
# WHY IT EXISTS.  100 made all seven get_ak_node() callers test the answer and
# abort on 0.  No verifier in either runner drives an AK index write at all:
# verify-vocverbs.ps1 is the only script that touches CREATE.INDEX and it is
# invoked by nothing, AND its fixture indexes a file whose DATA part is empty,
# so it would call get_ak_node zero times even if it ran.  A green suite
# therefore says nothing about the changed code.  This drives it.
#
# WHAT IT HAS TO BEAT, from gplsrc/dh_fmt.h:
#   DH_AK_NODE_SIZE  4096   - a terminal node; overflow it to force the splits
#                             at dh_ak.c:2216/:2237/:2365 and the internal-node
#                             allocations at :3407/:3460
#   AK_BIG_REC_SIZE  3300   - one key's id list past this goes to the big-record
#                             chain at :3831/:3865
#
# So: many DISTINCT keys (splits) plus many records sharing ONE key (big rec).
#
# NULL CASE REFUSED OUT LOUD.  Every count is asserted against the number it
# must be, not merely against "not zero", and the AK subfile is measured before
# and after so a run that indexed nothing cannot score green.
#
# Unelevated on purpose: an ordinary session lands in DON, don's own account.
# Nothing outside that account is touched and every fixture is removed again.

[CmdletBinding()]
param(
    [int]$Unique  = 1200,   # distinct keys  -> terminal splits + internal nodes
    [int]$Same    = 700,    # records sharing ONE key -> the big-record chain
    [string]$Tag  = 'AKP',  # fixture name stem
    [int]$Timeout = 600
)

$ErrorActionPreference = 'Stop'

$sdExe   = 'C:\Program Files\SD\usr\bin\sd.exe'
$acctDir = 'C:\ProgramData\SD\user_accounts\don'

$dirFile  = $Tag + 'DIR'      # DIRECTORY file holding the data records
$dctFile  = $Tag + 'DCT'      # DIRECTORY file holding the dictionary record
$dhFile   = $Tag + 'F'        # the hashed file that gets the index

$fails = 0
$rows  = @()

function Note {
    param([string]$What, $Expected, $Got)
    $ok = ([string]$Expected -ceq [string]$Got)
    if (-not $ok) { $script:fails++ }
    $script:rows += [pscustomobject]@{
        Check = $What; Expected = $Expected; Got = $Got
        Result = $(if ($ok) { 'PASS' } else { 'FAIL' })
    }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
                  $(if ($ok) { 'PASS' } else { 'FAIL' }), $What, $Expected, $Got)
}

function Invoke-SDText {
    param([string[]]$Commands, [int]$TimeoutSec = 120)
    $body = "`n" + (($Commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += "*** SD DID NOT FINISH IN $TimeoutSec s - session slot and locks left behind."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# Show-SD HANDS THE OUTPUT BACK IN $script:lastSD AND RETURNS NOTHING, which is
# verify-vocverbs.ps1's pattern and exists for a measured reason: a PowerShell
# function returns EVERYTHING written to the output stream, so a Show-SD that
# both prints and `return`s hands the caller the display lines joined onto the
# SD text.  The first version of this probe did that, and `$o -match ...` then
# answered System.Object[] instead of a boolean - five checks scored FAIL on a
# product that was fine, and the SELECT counts were each counted twice.
function Show-SD {
    param([string]$Label, [string[]]$Commands, [int]$TimeoutSec = 120)
    Write-Output ("  --- SD session: " + $Label + " ---")
    $Commands | ForEach-Object { Write-Output ("    > " + $_) }
    $o = Invoke-SDText -Commands $Commands -TimeoutSec $TimeoutSec
    $o -split "`n" | ForEach-Object { Write-Output ("    | " + $_) }
    $script:lastSD = $o
}

function Get-AkBytes {
    # Every subfile of the hashed file, so the AK part is visible whatever it is
    # called.  Returns total bytes and the per-file listing.
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @{ Bytes = -1; List = '(absent)' } }
    $f = @(Get-ChildItem -LiteralPath $Path -File -Force -ErrorAction SilentlyContinue)
    $tot = 0; foreach ($x in $f) { $tot += $x.Length }
    return @{ Bytes = $tot
              List  = (($f | Sort-Object Name | ForEach-Object { "{0}={1}" -f $_.Name, $_.Length }) -join ' ') }
}

# ---------------------------------------------------------------- preconditions
Write-Output '=== 0. preconditions, printed rather than assumed ==='
Write-Output ("  sd.exe   : " + $sdExe)
if (-not (Test-Path -LiteralPath $sdExe)) { Write-Output '  ABORT: no sd.exe'; exit 2 }
Write-Output ("  sha256   : " + (Get-FileHash $sdExe -Algorithm SHA256).Hash.Substring(0,16))
Write-Output ("  account  : " + $acctDir)
if (-not (Test-Path -LiteralPath $acctDir)) { Write-Output '  ABORT: no DON account dir'; exit 2 }
$who = [Security.Principal.WindowsIdentity]::GetCurrent()
$elev = (New-Object Security.Principal.WindowsPrincipal($who)).IsInRole(
          [Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Output ("  identity : {0}, elevated {1}" -f $who.Name, $elev)
Write-Output ("  fixture  : {0} / {1} / {2}" -f $dirFile, $dctFile, $dhFile)
Write-Output ("  records  : {0} distinct keys + {1} sharing one key = {2}" -f
              $Unique, $Same, ($Unique + $Same))

$total = $Unique + $Same
if ($total -lt 50) { Write-Output '  ABORT: too few records to split a 4096-byte node'; exit 2 }

foreach ($n in @($dirFile, $dctFile, $dhFile)) {
    if (Test-Path -LiteralPath (Join-Path $acctDir $n)) {
        Write-Output ("  ABORT: {0} already exists - refusing to measure over a leftover." -f $n)
        exit 2
    }
}

# ---------------------------------------------------------------- build fixture
Write-Output ''
Write-Output '=== 1. build the fixture ==='
Show-SD 'create the three files' @(
    ('CREATE.FILE ' + $dctFile + ' DIRECTORY'),
    ('CREATE.FILE ' + $dirFile + ' DIRECTORY'),
    ('CREATE.FILE ' + $dhFile))

$dctDir = Join-Path $acctDir $dctFile
$dirDir = Join-Path $acctDir $dirFile
$dhDir  = Join-Path $acctDir $dhFile
Note 'the dictionary source directory exists' $true (Test-Path -LiteralPath $dctDir)
Note 'the record source directory exists'     $true (Test-Path -LiteralPath $dirDir)
Note 'the hashed file exists'                 $true (Test-Path -LiteralPath $dhDir)
if ($fails -gt 0) { Write-Output '  ABORT: fixture did not build.'; exit 2 }

# D-type dictionary item for field 1: type, location, conversion, name, format, S/M
$dictRec = @('D', '1', '', 'F1', '20L', 'S') -join "`r`n"
Set-Content -LiteralPath (Join-Path $dctDir 'F1') -Value $dictRec -Encoding Ascii

# The data records.  A directory-file record is a file; field 1 is its first line.
for ($i = 1; $i -le $Unique; $i++) {
    $k = 'K{0:d6}' -f $i
    Set-Content -LiteralPath (Join-Path $dirDir $k) -Value $k -Encoding Ascii -NoNewline
}
for ($i = 1; $i -le $Same; $i++) {
    $k = 'S{0:d6}' -f $i
    Set-Content -LiteralPath (Join-Path $dirDir $k) -Value 'SAMEKEY' -Encoding Ascii -NoNewline
}
$made = @(Get-ChildItem -LiteralPath $dirDir -File).Count
Note 'the source directory holds every record' $total $made

# ---------------------------------------------------------------- copy + index
Write-Output ''
Write-Output '=== 2. copy the records in, BEFORE any index exists ==='
Show-SD 'copy dictionary and data' @(
    ('COPY FROM ' + $dctFile + ' TO DICT ' + $dhFile + ' F1'),
    ('COPY FROM ' + $dirFile + ' TO ' + $dhFile + ' ALL'),
    ('COUNT ' + $dhFile)) -TimeoutSec $Timeout
Note 'the records were counted in the hashed file' $true `
     ([bool]($lastSD -match ('\b' + $total + ' record\(s\) counted')))

$before = Get-AkBytes -Path $dhDir
Write-Output ("  BEFORE the index: {0} bytes  [{1}]" -f $before.Bytes, $before.List)

Write-Output ''
Write-Output '=== 3a. CREATE.INDEX defines the index - IT DOES NOT BUILD IT ==='
# gpl.bp/CREATEI:33 says so outright: "The two commands are identical except
# that MAKE.INDEX automatically goes on to build the index."  So CREATE.INDEX
# alone leaves the En(abled) column N and the AK subfile empty, and a SELECT
# then falls back to a SEQUENTIAL SCAN and answers correctly having touched no
# index at all.  THE FIRST RUN OF THIS PROBE SCORED 15/15 THAT WAY - correct
# counts, header-plus-one-node subfile, and get_ak_node effectively unexercised.
# That is the null case this file exists to refuse, so the build is separate and
# the En column is asserted.
Show-SD 'define the index' @(
    ('CREATE.INDEX ' + $dhFile + ' F1'),
    ('LIST.INDEX ' + $dhFile + ' ALL')) -TimeoutSec $Timeout
Note 'CREATE.INDEX reported success (2617)' $true ([bool]($lastSD -match 'Added index for F1'))
Note 'the file reads back with exactly one index' $true ([bool]($lastSD -match 'Number of indices = 1'))
Note 'and it is NOT yet enabled - the control for what follows' $true `
     ([bool]($lastSD -match '(?m)^F1\s+N\s'))
Note 'no refusal wording in the index build' $false `
     ([bool]($lastSD -match 'not found|no such|syntax error|already exists'))

$defined = Get-AkBytes -Path $dhDir
Write-Output ("  AFTER CREATE.INDEX (defined, empty): {0} bytes  [{1}]" -f $defined.Bytes, $defined.List)

Write-Output ''
Write-Output '=== 3b. BUILD.INDEX - THIS is what drives get_ak_node ==='
Show-SD 'build the index over every record' @(
    ('BUILD.INDEX ' + $dhFile + ' ALL'),
    ('LIST.INDEX ' + $dhFile + ' ALL')) -TimeoutSec $Timeout
Note 'the index is now ENABLED (En = Y)' $true ([bool]($lastSD -match '(?m)^F1\s+Y\s'))
Note 'no refusal wording in the build' $false `
     ([bool]($lastSD -match 'not found|no such|syntax error'))

$after = Get-AkBytes -Path $dhDir
Write-Output ("  AFTER  BUILD.INDEX: {0} bytes  [{1}]" -f $after.Bytes, $after.List)
$grew = $after.Bytes - $defined.Bytes
Write-Output ("  the BUILD cost {0} bytes = {1} nodes of {2}" -f
              $grew, [math]::Round($grew / 4096.0, 1), 4096)

# THE NULL-CASE GUARD, SIZED FROM THE DATA RATHER THAN GUESSED.  1200 distinct
# 7-character keys cannot fit in one 4096-byte terminal node, so a real build
# MUST allocate many.  Four nodes is a floor well below the arithmetic and well
# above "the root and nothing else", which is what the unbuilt index looked like.
Note 'the build allocated MANY nodes, not one' $true ($grew -gt (4 * 4096))

# ---------------------------------------------------------------- read it back
Write-Output ''
Write-Output '=== 4. read through the index - the answers are the measurement ==='
# clear.select BEFORE EVERY SELECT, and it is not tidiness.  Measured on the
# first run of this probe: a SELECT with a list still active runs AGAINST THAT
# LIST, so "WITH F1 = K000001" answered 0 records because the previous SELECT
# had left the 200 SAMEKEY records selected and K000001 is not among them.  A
# correct index scored a FAIL, which is the instrument fault this file's own
# rules are about - the product was right and the question was wrong.
$lastKey = 'K' + ('{0:d6}' -f $Unique)
Show-SD 'query by the indexed field' @(
    'clear.select',
    ('SELECT ' + $dhFile + ' WITH F1 = "SAMEKEY"'),
    'clear.select',
    ('SELECT ' + $dhFile + ' WITH F1 = "K000001"'),
    'clear.select',
    ('SELECT ' + $dhFile + ' WITH F1 = "' + $lastKey + '"'),
    'clear.select') -TimeoutSec $Timeout

$sel = @([regex]::Matches($lastSD, '(\d+) record\(s\) selected') |
         ForEach-Object { [int]$_.Groups[1].Value })
Write-Output ("  the three SELECT counts, in order: " + ($sel -join ', '))

# THE COUNTS ARE ASSERTED AS AN ORDERED TRIPLE, not merely as "non-zero".  A
# broken AK header answers wrongly rather than not at all, so the numbers are
# the measurement and each is checked against the number it must be.
Note 'exactly three SELECTs answered (none skipped, none doubled)' 3 $sel.Count
if ($sel.Count -eq 3) {
    Note ('the big-record key returns all ' + $Same)       $Same $sel[0]
    Note 'the FIRST distinct key returns exactly 1'        1     $sel[1]
    Note ('the LAST distinct key (' + $lastKey + ') returns exactly 1') 1 $sel[2]
}

# ---------------------------------------------------------------- clean up
Write-Output ''
Write-Output '=== 5. clean up, and prove it ==='
Show-SD 'delete the fixture' @(
    ('DELETE.FILE ' + $dhFile + ' no.query'),
    ('DELETE.FILE ' + $dirFile + ' no.query'),
    ('DELETE.FILE ' + $dctFile + ' no.query')) -TimeoutSec $Timeout

foreach ($p in @($dhDir, $dirDir, $dctDir)) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
}
$left = @(@($dhDir, $dirDir, $dctDir) | Where-Object { Test-Path -LiteralPath $_ })
Note 'no fixture directory is left behind' 0 $left.Count
$stray = @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue)
Note 'no stray sd.exe session is left behind' 0 $stray.Count

# ---------------------------------------------------------------- verdict
Write-Output ''
$rows | Format-Table -AutoSize | Out-String | Write-Output
$decisive = @($rows).Count
if ($decisive -eq 0) {
    Write-Output 'probe-akwrite: FAILED - no checks ran at all.'
    exit 1
}
if ($fails -gt 0) {
    Write-Output ("probe-akwrite: FAILED - {0} of {1} check(s) failed." -f $fails, $decisive)
    exit 1
}
Write-Output ("probe-akwrite: PASSED - {0} of {0} checks passed." -f $decisive)
Write-Output ("  {0} records ({1} distinct keys + {2} on one key) indexed by BUILD.INDEX." -f
              $total, $Unique, $Same)
Write-Output ("  The build allocated {0} bytes = {1} AK nodes, every one of them through" -f
              $grew, [math]::Round($grew / 4096.0, 1))
Write-Output '  get_ak_node(), and the index then answered all three queries correctly.'
exit 0
