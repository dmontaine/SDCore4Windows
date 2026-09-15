# verify-nocaseupgrade.ps1 - the UPGRADE's case-insensitivity walk converts the
# files it should, leaves the files it must, and loses nothing.
# RELEASE_1.1_FIXES.md 5, D2 - Handoff 62 item 3, "5a".  ***ELEVATED POWERSHELL.***
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-nocaseupgrade.ps1
#
# Exit 0 every check passed, 1 a check failed, 2 the fixture could not be built
# (never a FAIL).
#
# WHY IT FORCES THE STATE.  gpl.bp/UPGRADE_NOCASE, driven by upgrade-nocase.ps1
# from sd.iss's RefreshNocase, converts an UPGRADED machine's case-sensitive
# hashed files.  A fresh install makes every file NOCASE, and cycle.ps1 always
# installs fresh, so nothing had ever run it.  This builds the pre-D2 state with
# sd -internal (the only maker of a case-sensitive file) and runs the INSTALLED
# driver, the very script the installer runs - verify-dictrename's technique.
#
# THE FIXTURES, all in SDSYS, each with a DATA and a DICT part:
#   zznuclean   case sensitive, holds jack          -> must be CONVERTED
#   zznutwin    case sensitive, holds jack and JACK -> DATA must be LEFT, both
#                                                      records kept, pair named
#   zznuak      case sensitive, holds jack, index f1 -> DATA must be LEFT, named
#                                                      as indexed (10185)
#   zznunc      made the ordinary way (NOCASE)      -> CONTROL, untouched
# Each DICT part that starts case sensitive and holds no pair is expected to be
# converted too.  THE DECISIVE READ IS A PROBE PROGRAM that opens each part and
# prints FL$NOCASE (1008), FL$AK (13) and every id as STORED (select/readnext),
# before and after.  "Nothing lost" is the id list, compared case-sensitively.
#
# WHAT IT CANNOT REACH, SAID HERE SO A GREEN RUN IS NOT READ AS MORE:
#   - SDSYS's OWN live VOC.  On a fresh install it is already NOCASE, so the
#     walk skips it whatever it would have done to a case-sensitive one.  Found
#     by reading 14 Sep 2026: SDSYS's VOC has an F-record 'voc' naming itself,
#     so the walk queues the live VOC through its file list despite skipping it
#     by design.  Witnessed only by a real W1.0-0 -> current upgrade.
#   - the installer's own call (RefreshNocase) and a real account's VOC.  Same.
#   - it ASSUMES A FRESH D2 INSTALL, where every other hashed file is already
#     NOCASE, so the walk touches only these fixtures.  assert-current guards
#     that the install matches source; the converted count row would name any
#     other file the walk converted.
#
# RED BEFORE THE FIX, EXPECTED AND NOT YET SEEN.  Read 14 Sep 2026: phase 1
# builds its probe path from old.path (UPGRADE_NOCASE:218), which is first set
# in phase 2 (:284), so the first case-sensitive file stops the walk before
# COMPLETE.  Falsified if the first run reaches COMPLETE on today's install.
#
# BOUNDED: every SD session and the driver run as jobs with a timeout; any
# sd.exe a timed-out session leaves is killed BY PID DIFF, never by name.

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-nocaseupgrade: refusing - see assert-current above'
    exit 2
}

$wpr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $wpr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-nocaseupgrade: this needs an ELEVATED session and this one is not.'
    Write-Output '  It builds case-sensitive files with sd -internal and runs upgrade-nocase.ps1.'
    exit 2
}

$appDir  = Join-Path $env:ProgramFiles 'SD'
$sdExe   = Join-Path $appDir 'usr\bin\sd.exe'
$driver  = Join-Path $appDir 'upgrade-nocase.ps1'
$dataDir = Join-Path $env:ProgramData 'SD'
$sdsys   = Join-Path $dataDir 'sdsys'
$logFile = Join-Path $dataDir 'nocase-upgrade.log'
$probeName = 'zznuprobe'
$probeSrc  = Join-Path (Join-Path $sdsys 'bp') $probeName
$probeObj  = Join-Path (Join-Path $sdsys 'bp.out') $probeName
$fixtures  = @('zznuclean', 'zznutwin', 'zznuak', 'zznunc')

Write-Output '===== verify-nocaseupgrade.ps1 ====='
Write-Output ("  sd.exe   : " + $sdExe)
Write-Output ("  driver   : " + $driver + " -AppDir " + $appDir + " -DataDir " + $dataDir)
Write-Output ("  sdsys    : " + $sdsys)
Write-Output ("  log      : " + $logFile)
Write-Output ("  fixtures : " + ($fixtures -join ', ') + "; probe " + $probeSrc)
foreach ($p in @($sdExe, $driver, (Join-Path $sdsys 'bp'))) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Output ("verify-nocaseupgrade: missing " + $p); exit 2 }
}

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ("  [PASS] " + $name) }
    else { $script:fail++; Write-Output ("  [FAIL] " + $name + $(if ($detail) { "  ->  $detail" } else { '' })) }
}

function Invoke-Bounded([string[]]$lines, [bool]$internal, [int]$TimeoutSec = 120) {
    $pre = @()
    if (-not $internal) { $pre = @('LOGTO SDSYS') }
    $body = "`n" + ((@($pre) + @('TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"
    $before = @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $job = Start-Job -ScriptBlock {
        param($exe, $text, $int)
        if ($int) { $text | & $exe '-internal' 2>&1 } else { $text | & $exe 2>&1 }
    } -ArgumentList $sdExe, $body, $internal
    $killed = $false
    $killedPids = @()
    if (-not (Wait-Job $job -Timeout $TimeoutSec)) {
        $killed = $true
        Stop-Job $job -ErrorAction SilentlyContinue
        foreach ($p in @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue)) {
            # Recorded into the returned text, not Write-Output: see Get-Probe.
            if ($before -notcontains $p.Id) { $killedPids += $p.Id; try { $p.Kill() } catch { } }
        }
    }
    $out = (@(Receive-Job $job -ErrorAction SilentlyContinue) | Out-String) -replace ([char]27 + '\[[0-9]*[A-Za-z]'), ''
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if ($killed) { $out += "`n*** SD DID NOT FINISH IN $TimeoutSec s - killed stray sd.exe PID(s): $($killedPids -join ', ') - a timed-out session can leave its slot and locks (PROJECT_STATUS.md section 6)" }
    return [string]$out
}
function Show([string]$label, [string]$text) {
    Write-Output ("  --- " + $label + " ---")
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '^\s*:?\s*$|Ladybridge|free software|welcome to modify|conditions\.  For|^SD Core for') { continue }
        Write-Output ("    " + $l)
    }
}

# The probe: one line per fixture part, ids as stored.
$probeBasic = @'
* zznuprobe - written by verify-nocaseupgrade.ps1.  Safe to delete.
   names = 'zznuclean' : @fm : 'zznutwin' : @fm : 'zznuak' : @fm : 'zznunc'
   for i = 1 to 4
      n = names<i>
      for p = 1 to 2
         if p = 1 then
            part = 'DATA'
            dq = ''
         end else
            part = 'DICT'
            dq = 'DICT'
         end
         open dq, n to f then
            ids = ''
            select f to 9
            loop
               readnext id from 9 else exit
               ids := '[' : id : ']'
            repeat
            crt 'FIX ' : n : ' ' : part : ' NOCASE=' : fileinfo(f, 1008) : ' AK=' : fileinfo(f, 13) : ' IDS=' : ids
            close f
         end else
            crt 'FIX ' : n : ' ' : part : ' NOFILE'
         end
      next p
   next i
end
'@
# ***RETURNS ONE OBJECT AND PRINTS NOTHING.***  The first version called Show
# in here, and a PowerShell function's Write-Output becomes part of its RETURN
# VALUE: the caller got an array of text lines with the map at the end, every
# $b['zznuclean/DATA'] was $null, and the run refused its precondition with the
# probe's own output swallowed (14 Sep 2026, the first run).  The caller shows
# .Text; .Lines is the count of FIX lines, so a probe that printed nothing is
# refused by name rather than read as "no fixture".
function Get-Probe {
    $t = Invoke-Bounded @("BASIC bp $probeName", "RUN bp $probeName") $false
    $map = @{}
    foreach ($m in [regex]::Matches($t, '(?m)^FIX (\S+) (DATA|DICT) (?:NOCASE=(\d+) AK=(\d+) IDS=(.*?)|NOFILE)\s*$')) {
        $ids = @([regex]::Matches($m.Groups[5].Value, '\[([^\]]*)\]') | ForEach-Object { $_.Groups[1].Value })
        [string[]]$arr = $ids
        [Array]::Sort($arr, [StringComparer]::Ordinal)
        $map[$m.Groups[1].Value + '/' + $m.Groups[2].Value] = [pscustomobject]@{
            NoFile = -not $m.Groups[3].Success
            NoCase = $(if ($m.Groups[3].Success) { [int]$m.Groups[3].Value } else { -1 })
            Ak     = $(if ($m.Groups[4].Success) { [int]$m.Groups[4].Value } else { -1 })
            Ids    = ($arr -join ',')
        }
    }
    return [pscustomobject]@{ Text = $t; Map = $map; Lines = $map.Count }
}
function Get-TempLeftovers {
    return @(Get-ChildItem -LiteralPath $sdsys -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match '^~SD(SCAN|NOCASE)\.' } | ForEach-Object { $_.Name })
}
function Remove-Fixtures {
    $null = Invoke-Bounded @($fixtures | ForEach-Object { "DELETE.FILE $_ FORCE" }) $false
    foreach ($f in @($probeSrc, $probeObj)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    return @(Get-ChildItem -LiteralPath $sdsys -Force -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match '^(?i)zznu' } | ForEach-Object { $_.Name })
}

$exit = 2
$logLenBefore = $(if (Test-Path -LiteralPath $logFile) { (Get-Item -LiteralPath $logFile).Length } else { -1 })
try {
    Write-Output '  --- clearing any earlier fixture ---'
    $left = Remove-Fixtures
    if ($left.Count) { Write-Output ("verify-nocaseupgrade: could not clear " + ($left -join ', ')); exit 2 }
    $tempBefore = Get-TempLeftovers
    if ($tempBefore.Count) { Write-Output ("verify-nocaseupgrade: walk temp files already in sdsys, not this run's: " + ($tempBefore -join ', ')); exit 2 }

    # ---- build: one sd -internal session for every case-sensitive fixture ----
    $mk = Invoke-Bounded @(
        'CREATE.FILE zznuclean CASE',
        'COPY FROM VOC TO zznuclean who,jack',
        'CREATE.FILE zznutwin CASE',
        'COPY FROM VOC TO zznutwin who,jack',
        'COPY FROM VOC TO zznutwin who,JACK',
        'CREATE.FILE zznuak CASE',
        'COPY FROM VOC TO zznuak who,jack',
        'COPY FROM DICT VOC TO DICT zznuak f1,f1',
        'CREATE.INDEX zznuak f1',
        'BUILD.INDEX zznuak f1') $true
    Show 'build (sd -internal)' $mk
    $mk2 = Invoke-Bounded @('CREATE.FILE zznunc', 'COPY FROM VOC TO zznunc who,jack') $false
    Show 'build the NOCASE control' $mk2
    [IO.File]::WriteAllText($probeSrc, ($probeBasic -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
    Write-Output ("  wrote " + $probeSrc)

    $bp = Get-Probe
    Show 'probe BEFORE' $bp.Text
    Write-Output ("  probe lines read: " + $bp.Lines + " of 8")
    if ($bp.Lines -ne 8) { Write-Output '  verify-nocaseupgrade: the probe did not report all 8 fixture parts - see its output above; nothing measured'; exit 2 }
    $b = $bp.Map
    $want = @{
        'zznuclean/DATA' = @{ NoCase = 0; Ak = 0; Ids = 'jack' }
        'zznutwin/DATA'  = @{ NoCase = 0; Ak = 0; Ids = 'JACK,jack' }
        'zznuak/DATA'    = @{ NoCase = 0; Ak = 1; Ids = 'jack' }
        'zznunc/DATA'    = @{ NoCase = 1; Ak = 0; Ids = 'jack' }
    }
    $setupOk = $true
    foreach ($k in $want.Keys) {
        $g = $b[$k]
        if ($null -eq $g -or $g.NoFile -or $g.NoCase -ne $want[$k].NoCase -or $g.Ak -ne $want[$k].Ak -or $g.Ids -cne $want[$k].Ids) {
            Write-Output ("  fixture " + $k + " is not as built: " + $(if ($null -eq $g) { '(no probe line)' } else { "NOCASE=$($g.NoCase) AK=$($g.Ak) IDS=$($g.Ids)" }))
            $setupOk = $false
        }
    }
    foreach ($n in $fixtures) { if ($null -eq $b["$n/DICT"] -or $b["$n/DICT"].NoFile) { Write-Output "  fixture $n has no DICT part"; $setupOk = $false } }
    Row 'precondition: three case-sensitive fixtures (one twinned, one indexed) and a NOCASE control, as built' $setupOk
    if (-not $setupOk) { Write-Output '  nothing below would be measured'; exit 2 }

    # Which parts the walk should convert: case sensitive, no pair, no index.
    $expectConvert = @($b.Keys | Where-Object { $b[$_].NoCase -eq 0 -and $_ -ne 'zznutwin/DATA' -and $_ -ne 'zznuak/DATA' } | Sort-Object)
    Write-Output ("  expected to convert: " + ($expectConvert -join ', ') + " (" + $expectConvert.Count + ")")

    # ---- run the installed driver, bounded ----------------------------------
    Write-Output ''
    Write-Output ("  running: powershell -NoProfile -ExecutionPolicy Bypass -File " + $driver + " -AppDir " + $appDir + " -DataDir " + $dataDir)
    $job = Start-Job -ScriptBlock {
        param($d, $a, $dd)
        $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $d -AppDir $a -DataDir $dd 2>&1 | Out-String
        $o + "`nDRIVER-EXITCODE=" + $LASTEXITCODE
    } -ArgumentList $driver, $appDir, $dataDir
    $finished = [bool](Wait-Job $job -Timeout 600)
    if (-not $finished) { Stop-Job $job -ErrorAction SilentlyContinue }
    $drv = (@(Receive-Job $job -ErrorAction SilentlyContinue) | Out-String)
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    Show 'driver output' $drv
    $code = [regex]::Match($drv, 'DRIVER-EXITCODE=(-?\d+)')
    $drvExit = $(if ($code.Success) { [int]$code.Groups[1].Value } else { -999 })
    Write-Output ("  driver exit: " + $drvExit)
    $logNew = ''
    if (Test-Path -LiteralPath $logFile) {
        $bytes = [IO.File]::ReadAllBytes($logFile)
        $from = [Math]::Max(0, $logLenBefore)
        if ($bytes.Length -gt $from) { $logNew = [Text.Encoding]::ASCII.GetString($bytes, $from, $bytes.Length - $from) }
    }
    Write-Output ("  log text this run added: " + $logNew.Length + " chars (shown in the driver output above)")

    Row 'the driver finished within 600 s' $finished
    Row 'no runtime abort in the walk (no "Unassigned variable")' ($drv -notmatch 'Unassigned variable') 'the walk stopped on an unassigned variable'
    Row 'the walk reached COMPLETE' ($drv -match '(?m)\|\s*COMPLETE\s*$') 'no COMPLETE line in the report'
    Row 'no file "could not be read or rebuilt" (10183)' ($drv -notmatch 'could not be read or rebuilt') 'the walk reported trouble'
    Row 'the driver exited 2 - done, with a duplicate left and named' ($drvExit -eq 2) "exit $drvExit"
    Row 'the report warns of exactly 1 file holding 1 case-only duplicate (10178)' `
        ($drv -match 'WARNING: 1 file\(s\) hold 1 record id\(s\) that differ only by case') 'no 10178 line with 1 and 1'
    Row 'the report names zznutwin (10184) and its pair, jack / JACK' `
        (($drv -match 'File: \S*[\\/]zznutwin\s*$' -or $drv -match '(?m)File: .*zznutwin\s*$') -and ($drv -cmatch '(jack / JACK|JACK / jack)')) 'no File: line for zznutwin, or no pair line'
    Row 'the report names zznuak as indexed (10185) and counts 1 indexed file (10186)' `
        (($drv -match 'File has indices, so convert it by hand with CONFIGURE\.FILE NO\.CASE: .*zznuak') -and ($drv -match '1 indexed file\(s\) were left')) 'no 10185 naming zznuak, or no 10186 count of 1'
    $conv = [regex]::Match($drv, 'Converted (\d+) of (\d+) file\(s\)')
    Row ("the walk converted exactly the " + $expectConvert.Count + " fixture part(s) expected, and nothing else (10179)") `
        ($conv.Success -and ([int]$conv.Groups[1].Value -eq $expectConvert.Count)) $(if ($conv.Success) { "converted $($conv.Groups[1].Value) of $($conv.Groups[2].Value)" } else { 'no 10179 line' })
    Row 'the log names zznutwin' ($logNew -match 'zznutwin') 'nocase-upgrade.log did not receive the report'

    # ---- after: every part's flags and stored ids ---------------------------
    $ap = Get-Probe
    Show 'probe AFTER' $ap.Text
    Write-Output ("  probe lines read: " + $ap.Lines + " of 8")
    Row 'the AFTER probe reported all 8 fixture parts' ($ap.Lines -eq 8) "read $($ap.Lines)"
    $a = $ap.Map
    foreach ($k in ($b.Keys | Sort-Object)) {
        $g0 = $b[$k]; $g1 = $a[$k]
        if ($null -eq $g1 -or $g1.NoFile) { Row ("$k still exists") $false 'the part is gone'; continue }
        Row ("$k lost nothing - the same ids, case for case") ($g1.Ids -ceq $g0.Ids) "before [$($g0.Ids)] after [$($g1.Ids)]"
        if ($expectConvert -contains $k) {
            Row ("$k was converted to NOCASE") ($g1.NoCase -eq 1) "NOCASE=$($g1.NoCase)"
        } else {
            Row ("$k was left as it was (NOCASE=$($g0.NoCase))") ($g1.NoCase -eq $g0.NoCase) "NOCASE=$($g1.NoCase)"
        }
    }
    Row 'zznuak/DATA still has its index' ($a['zznuak/DATA'].Ak -eq 1) "AK=$($a['zznuak/DATA'].Ak)"
    $tempAfter = Get-TempLeftovers
    Row 'the walk left no ~SDSCAN or ~SDNOCASE temp file in sdsys' ($tempAfter.Count -eq 0) ($tempAfter -join ', ')

    $exit = $(if ($fail -eq 0) { 0 } else { 1 })
}
finally {
    Write-Output '  --- cleanup ---'
    foreach ($t in @(Get-TempLeftovers)) { Remove-Item -LiteralPath (Join-Path $sdsys $t) -Recurse -Force -ErrorAction SilentlyContinue; Write-Output "  removed walk temp $t" }
    $left = Remove-Fixtures
    $vocLeft = Invoke-Bounded @('LIST VOC WITH @ID LIKE "zznu..."') $false
    $vocOk = $vocLeft -match '(?m)^0 record\(s\) listed'
    Write-Output ("  sdsys entries left: " + $(if ($left.Count) { $left -join ', ' } else { '(none)' }) + "; VOC zznu* records: " + $(if ($vocOk) { 'none' } else { 'SOME - see below' }))
    if (-not $vocOk) { Show 'LIST VOC zznu...' $vocLeft }
    $cleanOk = ($left.Count -eq 0) -and $vocOk -and -not (Test-Path -LiteralPath $probeSrc) -and -not (Test-Path -LiteralPath $probeObj)
    Row 'cleanup: no fixture, VOC record or probe left in SDSYS' $cleanOk
    if (-not $cleanOk -and $exit -eq 0) { $exit = 1 }
    if ($logLenBefore -lt 0 -and (Test-Path -LiteralPath $logFile)) {
        Remove-Item -LiteralPath $logFile -Force -ErrorAction SilentlyContinue
        Write-Output ("  removed " + $logFile + " (this run created it; its content is printed above)")
    }
}

Write-Output ''
Write-Output ("verify-nocaseupgrade: $pass passed, $fail failed")
if (($pass + $fail) -eq 0 -and $exit -ne 2) { Write-Output 'verify-nocaseupgrade: COULD NOT RUN - no check ran'; exit 2 }
exit $exit
