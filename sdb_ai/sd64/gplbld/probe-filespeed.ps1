# probe-filespeed.ps1 - is a DIRECTORY file measurably slower than a DYNAMIC file?
#
#   powershell -ExecutionPolicy Bypass -File probe-filespeed.ps1 [-Records 1000] [-ReadPasses 5] [-Rounds 3] [-Keep]
#
# Exit 0 measured, 2 could not run.  ***AN ORDINARY UNELEVATED PROMPT*** - it runs in
# the caller's own SD account, the shape verify-basicfuncs.ps1 already proved.
#
# 21 Sep 2026.  The owner asked whether SDSYS's VOC could be a directory file again
# (sdsys/changelog, Version 0.9-3: upstream moved it "back to dynamic" for speed).  He
# recalled a measurement showing the difference was marginal; none is written in
# PROJECT_STATUS.md or HISTORY.md.  This is that measurement.
#
# WHAT IT DOES.  One BASIC program per file type (the same source, only the file name
# differs) opens a scratch file, CLEARFILEs it, then times with SYSTEM(1020) - wall clock
# milliseconds of the day - N writes of new records, ReadPasses passes of N reads, and N
# rewrites of the same records.  The two file types alternate in ABBA order across the
# rounds, so a warm OS cache or a slower first run cannot favour either.
#
# THE INSTRUMENT RULES, EACH ONE ACTED ON:
#   - The files are made with CREATE.FILE ... NO.QUERY (nothing can prompt a piped
#     session) and the script says what is on disk afterwards, so "directory" and
#     "dynamic" are read off the file system, not taken from the verb's word.
#   - Every read is COMPARED: the program totals the bytes it wrote and each read pass
#     must return the same count of records and the same total bytes.  A pass that read
#     nothing scores as a refusal, not as a fast pass.
#   - sd.exe runs in a process with a timeout, so a prompt it cannot answer ends in a
#     kill and a message rather than a stray process (PROJECT_STATUS.md section 6).
#   - The raw output of every run is printed.

[CmdletBinding()]
param(
    [string]$Account   = $env:USERNAME,
    [int]   $Records   = 1000,
    [int]   $ReadPasses = 5,
    [int]   $Rounds    = 3,
    [int]   $TimeoutSec = 300,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$Root   = Join-Path $env:ProgramData 'SD\user_accounts'
$acctDir = Join-Path $Root $Account
$bpDir  = Join-Path $acctDir 'bp'
$outDir = Join-Path $acctDir 'BP.OUT'

$FileDyn = 'zzfsd'
$FileDir = 'zzfsf'
$ProgDyn = 'ZZFSPD'
$ProgDir = 'ZZFSPF'

function Say([string]$m) { Write-Host $m }

$script:inTry = $false
$script:finalOk = $false

# Inside the try block a refusal must THROW, so the finally block still cleans up the
# scratch files; before it, there is nothing to clean and it exits at once.
function Bail([int]$code, [string]$why) {
    if ($script:inTry -and $code -ne 0) { throw $why }
    Say ''
    if ($code -eq 0) { Say "probe-filespeed: MEASURED - $why" }
    else             { Say "probe-filespeed: COULD NOT RUN - $why" }
    exit $code
}

# A piped sd session with a leash.  Blank first line absorbs any BOM, TERM stops it
# paginating, OFF ends it.  Killed at $TimeoutSec, and the output so far is returned in
# the exception so a hang is never a silent one.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $sdExe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput  = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError  = $true
    $psi.CreateNoWindow = $true
    $p = [System.Diagnostics.Process]::Start($psi)
    $outTask = $p.StandardOutput.ReadToEndAsync()
    $errTask = $p.StandardError.ReadToEndAsync()
    $p.StandardInput.Write($body)
    $p.StandardInput.Close()
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        try { $p.Kill() } catch { }
        $null = $p.WaitForExit(5000)
        throw ("sd.exe did not finish in $TimeoutSec s and was killed.  Output so far:`n" + $outTask.Result)
    }
    $text = $outTask.Result
    return ($text -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '')
}

function Get-Median([double[]]$v) {
    $s = @($v | Sort-Object)
    $n = $s.Count
    if ($n -eq 0) { return [double]::NaN }
    if ($n % 2 -eq 1) { return $s[($n - 1) / 2] }
    return ($s[$n / 2 - 1] + $s[$n / 2]) / 2
}

# The BASIC source.  __FILE__ and the two counts are replaced; nothing else varies
# between the two programs.
$Template = @'
* ZZFSPEED - times writes, reads and rewrites of N records on ONE file.
n = __N__
passes = __PASSES__
open '__FILE__' to fd else
   print 'OPENFAIL|__FILE__'
   stop
end
clearfile fd
base = ''
for f = 1 to 5
   base<f> = str('ABCDEFGHIJ', 4) : f
next f
want = 0
t0 = system(1020)
for i = 1 to n
   rec = base
   rec<6> = i
   write rec on fd, 'R':i
   want = want + len(rec)
next i
t1 = system(1020)
gosub elapsed
print 'PHASE|WRITE|':ms:'|':n:'|':want
for p = 1 to passes
   nread = 0
   got = 0
   t0 = system(1020)
   for i = 1 to n
      read r from fd, 'R':i then
         nread = nread + 1
         got = got + len(r)
      end else
         null
      end
   next i
   t1 = system(1020)
   gosub elapsed
   print 'PHASE|READ':p:'|':ms:'|':nread:'|':got
next p
want2 = 0
t0 = system(1020)
for i = 1 to n
   rec = base
   rec<6> = i
   write rec on fd, 'R':i
   want2 = want2 + len(rec)
next i
t1 = system(1020)
gosub elapsed
print 'PHASE|REWRITE|':ms:'|':n:'|':want2
print 'PROBE.DONE'
stop
elapsed:
   ms = t1 - t0
   if ms < 0 then ms = ms + 86400000
   return
end
'@

# ---------------------------------------------------------------------------
# Refusals, before anything is written.
if (-not (Test-Path -LiteralPath $sdExe)) { Bail 2 "no sd.exe at $sdExe - SD does not look installed." }
if (-not (Test-Path -LiteralPath $bpDir)) { Bail 2 "no bp directory at $bpDir - pass -Account with an SD account name." }
if ($Records -lt 100 -or $ReadPasses -lt 1 -or $Rounds -lt 1) { Bail 2 'Records must be at least 100, ReadPasses and Rounds at least 1.' }

Say "probe-filespeed: account     $Account"
Say "probe-filespeed: account dir $acctDir"
Say "probe-filespeed: sd.exe      $sdExe"
Say "probe-filespeed: records     $Records   read passes $ReadPasses   rounds $Rounds   timeout $TimeoutSec s"
Say "probe-filespeed: files       $FileDyn (DYNAMIC)   $FileDir (DIRECTORY)"
Say "probe-filespeed: programs    $ProgDyn   $ProgDir   (in $bpDir)"
Say ''

Say '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
Say ''

foreach ($n in @($FileDyn, $FileDir)) {
    if (Test-Path -LiteralPath (Join-Path $acctDir $n)) { Bail 2 "$n already exists in $acctDir - remove it first (DELETE.FILE $n)." }
}
foreach ($n in @($ProgDyn, $ProgDir)) {
    if (Test-Path -LiteralPath (Join-Path $bpDir $n)) { Bail 2 "$n already exists in $bpDir - remove it first." }
}

$results = New-Object System.Collections.ArrayList   # one row per run x phase
$made = $false
$failMsg = $null
$plan = @()

$script:inTry = $true
try {
    # 1. The two programs.
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    foreach ($pair in @(@($ProgDyn, $FileDyn), @($ProgDir, $FileDir))) {
        $src = $Template.Replace('__FILE__', $pair[1]).Replace('__N__', [string]$Records).Replace('__PASSES__', [string]$ReadPasses)
        $src = $src.Replace("`r`n", "`n")
        [System.IO.File]::WriteAllText((Join-Path $bpDir $pair[0]), $src, $utf8)
    }

    # 2. Make the two files, then compile.  Both are made before either is timed.
    Say '--- create the files -----------------------------------------------'
    $made = $true
    $out = Invoke-SD @("CREATE.FILE $FileDyn DYNAMIC NO.QUERY", "CREATE.FILE $FileDir DIRECTORY NO.QUERY")
    Write-Host $out
    foreach ($n in @($FileDyn, $FileDir)) {
        if (-not (Test-Path -LiteralPath (Join-Path $acctDir $n))) { Bail 2 "CREATE.FILE did not make $n under $acctDir - the output above says why." }
    }
    Say ''

    Say '--- compile --------------------------------------------------------'
    foreach ($pn in @($ProgDyn, $ProgDir)) {
        $out = Invoke-SD @("BASIC BP $pn")
        Write-Host $out
        $sawCount = ($out -match '\b0 error')
        $sawBad   = ($out -match '[1-9][0-9]* error') -or ($out -match 'Compilation error')
        if ($sawBad -or -not $sawCount) {
            Bail 2 "$pn did not compile.  Anchor is BCOMP's '0 error(s)'; saw0errors=$sawCount sawErrors=$sawBad.  The output above says why."
        }
    }
    Say ''

    # 3. The runs.  ABBA across rounds.
    $plan = @()
    for ($r = 1; $r -le $Rounds; $r++) {
        if ($r % 2 -eq 1) { $plan += ,@($r, 'dynamic', $ProgDyn); $plan += ,@($r, 'directory', $ProgDir) }
        else              { $plan += ,@($r, 'directory', $ProgDir); $plan += ,@($r, 'dynamic', $ProgDyn) }
    }
    Say ('--- runs, in this order: ' + (($plan | ForEach-Object { "r$($_[0])/$($_[1])" }) -join '  ') + ' ---')
    $shapeChecked = $false
    foreach ($step in $plan) {
        $round = $step[0]; $kind = $step[1]; $prog = $step[2]
        Say ''
        Say "== round $round, $kind file: RUN BP $prog"
        $run = Invoke-SD @("RUN BP $prog")
        Write-Host $run
        if ($run -match 'OPENFAIL') { Bail 2 "$prog could not open its file - nothing was measured." }
        if ($run -notmatch 'PROBE\.DONE') { Bail 2 "$prog did not reach PROBE.DONE - nothing was measured." }

        $rows = @([regex]::Matches($run, '(?m)^PHASE\|([A-Z0-9]+)\|(\d+)\|(\d+)\|(\d+)'))
        $wantRows = 2 + $ReadPasses
        if ($rows.Count -ne $wantRows) { Bail 2 "$prog printed $($rows.Count) PHASE line(s), expected $wantRows - a phase was skipped." }

        $wantBytes = [int64]$rows[0].Groups[4].Value
        foreach ($m in $rows) {
            $ph = $m.Groups[1].Value; $ms = [int]$m.Groups[2].Value
            $cnt = [int]$m.Groups[3].Value; $bytes = [int64]$m.Groups[4].Value
            if ($cnt -ne $Records)    { Bail 2 "$prog phase $ph handled $cnt record(s), expected $Records - it did not do the work." }
            if ($bytes -ne $wantBytes){ Bail 2 "$prog phase $ph moved $bytes byte(s), the write moved $wantBytes - the data read is not the data written." }
            $null = $results.Add([pscustomobject]@{ Round = $round; Kind = $kind; Phase = $(if ($ph -like 'READ*') { 'READ' } else { $ph }); Ms = $ms })
        }

        # What is on disk, once per type, read off the file system - after its first
        # run has cleared the file, so this shows the shape, not the contents.
        $fname = $(if ($kind -eq 'dynamic') { $FileDyn } else { $FileDir })
        $entries = @(Get-ChildItem -LiteralPath (Join-Path $acctDir $fname) -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
        Say ("   on disk after the run: $fname has $($entries.Count) entr" + $(if ($entries.Count -eq 1) { 'y' } else { 'ies' }) + " " + $(if ($entries.Count -le 6) { '(' + ($entries -join ' ') + ')' } else { '(first: ' + (($entries | Select-Object -First 4) -join ' ') + ' ...)' }))
    }

    # 4. Results.
    Say ''
    Say ('--- result: milliseconds per phase (N = ' + $Records + ' records) ----------')
    $fmt = '{0,-9} {1,-10} {2,10} {3,10} {4,10}   runs'
    Say ($fmt -f 'phase', 'file', 'median', 'min', 'max')
    $ratios = @{}
    foreach ($ph in @('WRITE', 'READ', 'REWRITE')) {
        $med = @{}
        foreach ($kind in @('dynamic', 'directory')) {
            $v = @($results | Where-Object { $_.Phase -eq $ph -and $_.Kind -eq $kind } | ForEach-Object { [double]$_.Ms })
            $med[$kind] = Get-Median $v
            $mn = ($v | Measure-Object -Minimum).Minimum; $mx = ($v | Measure-Object -Maximum).Maximum
            Say (($fmt -f $ph, $kind, $med[$kind], $mn, $mx) + "   $($v.Count)")
        }
        if ($med['dynamic'] -gt 0) { $ratios[$ph] = $med['directory'] / $med['dynamic'] }
        else { $ratios[$ph] = [double]::NaN }
    }
    Say ''
    foreach ($ph in @('WRITE', 'READ', 'REWRITE')) {
        $r = $ratios[$ph]
        $per = @{}
        foreach ($kind in @('dynamic', 'directory')) {
            $v = @($results | Where-Object { $_.Phase -eq $ph -and $_.Kind -eq $kind } | ForEach-Object { [double]$_.Ms })
            $per[$kind] = (Get-Median $v) * 1000.0 / $Records
        }
        Say ("  {0,-8} directory / dynamic = {1:N2}x   ({2:N0} us vs {3:N0} us per record, median)" -f $ph, $r, $per['directory'], $per['dynamic'])
    }
    Say ''
    # THE FLOOR.  The programs leave their records in place at the end (the next run's
    # CLEARFILE, before its timers start, and DELETE.FILE in cleanup remove them), so
    # what is on disk now is what the last runs read.  Say what it is, then read the
    # directory file's own files with plain .NET as the operating-system floor.
    Say '--- what is on disk, and the operating-system floor ------------------'
    $dynPath = Join-Path $acctDir $FileDyn
    $dynParts = @(Get-ChildItem -LiteralPath $dynPath -Force -File -ErrorAction SilentlyContinue)
    Say ("   $FileDyn : $($dynParts.Count) file(s) " + '(' + (($dynParts | ForEach-Object { "$($_.Name) $($_.Length) bytes" }) -join ', ') + ')')
    $dirPath = Join-Path $acctDir $FileDir
    $dirFiles = @(Get-ChildItem -LiteralPath $dirPath -Force -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    Say "   $FileDir : $($dirFiles.Count) file(s), one per record (expected $Records after a directory-file run)"
    if ($dirFiles.Count -eq $Records) {
        $raw = @()
        for ($pass = 1; $pass -le $ReadPasses; $pass++) {
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            $tot = 0
            foreach ($f in $dirFiles) { $tot += [System.IO.File]::ReadAllBytes($f).Length }
            $sw.Stop()
            $raw += $sw.Elapsed.TotalMilliseconds
        }
        $rawMed = Get-Median ([double[]]$raw)
        Say ('   plain .NET ReadAllBytes of those ' + $dirFiles.Count + ' files, ms per pass: ' + (($raw | ForEach-Object { '{0:N1}' -f $_ }) -join '  '))
        Say ('   median {0:N1} ms = {1:N0} us per file, {2} bytes read per pass' -f $rawMed, ($rawMed * 1000.0 / $Records), $tot)
    } else {
        Say '   the last run was not a directory-file run, so the floor was not measured this time.'
    }
    Say ''
    Say 'NOT MEASURED: VOC-specific behaviour (case folding, the %-encoded ids), concurrent sessions,'
    Say 'a cold OS cache, or Defender exclusions other than whatever this machine has now.'
    $script:finalOk = $true
}
catch {
    $failMsg = $_.Exception.Message
}
finally {
    $script:inTry = $false
    if (-not $Keep) {
        Say ''
        Say '--- cleanup --------------------------------------------------------'
        try {
            if ($made) {
                $out = Invoke-SD @("DELETE.FILE $FileDyn", "DELETE.FILE $FileDir", "COUNT VOC WITH @ID LIKE `"zzfs...`"")
                Write-Host $out
                if ($out -notmatch '(?m)^0 record\(s\) counted') { Say '  WARNING: the COUNT of leftover zzfs* VOC records did not read 0 - check by hand.' }
            }
        } catch { Say "  (DELETE.FILE step failed - $($_.Exception.Message))" }
        foreach ($p in @((Join-Path $bpDir $ProgDyn), (Join-Path $bpDir $ProgDir), (Join-Path $outDir $ProgDyn), (Join-Path $outDir $ProgDir))) {
            if (Test-Path -LiteralPath $p) {
                try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop } catch { Say "  (could not remove $p - $($_.Exception.Message))" }
            }
        }
        $left = @($FileDyn, $FileDir | ForEach-Object { Join-Path $acctDir $_ }) + @((Join-Path $bpDir $ProgDyn), (Join-Path $bpDir $ProgDir), (Join-Path $outDir $ProgDyn), (Join-Path $outDir $ProgDir)) | Where-Object { Test-Path -LiteralPath $_ }
        Say ("cleanup: " + @($left).Count + ' scratch item(s) left on disk' + $(if (@($left).Count) { ': ' + (@($left) -join ', ') } else { '' }))
    } else {
        Say "cleanup: -Keep given, the scratch files and programs are left in $acctDir."
    }
}

if ($failMsg) { Bail 2 $failMsg }
if ($script:finalOk) { Bail 0 "$($results.Count) timed phases across $(@($plan).Count) runs." }
Bail 2 'the run ended without a result and without an error - nothing was measured.'
