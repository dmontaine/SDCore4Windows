# verify-nocaseupgrade.ps1 - the UPGRADE's case-insensitivity walk converts the
# files it should, leaves the files it must, and loses nothing.
# RELEASE_1.1_FIXES.md 5, D2 - Handoff 62 item 3, "5a".  ***ELEVATED POWERSHELL.***
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-nocaseupgrade.ps1
#
# Exit 0 every check passed, 1 a check failed, 2 the fixture could not be built
# (never a FAIL).
#
# WHY IT FORCES THE STATE.  gpl.bp/upgrade_nocase, driven by upgrade-nocase.ps1
# from sd.iss's RefreshNocase, converts an UPGRADED machine's case-sensitive
# hashed files.  A fresh install makes every file NOCASE, and cycle.ps1 always
# installs fresh, so nothing had ever run it.  This builds the pre-D2 state with
# sd -internal (the only maker of a case-sensitive file) and runs the INSTALLED
# driver, the very script the installer runs - verify-dictrename's technique.
#
# THE FIXTURES, each with a DATA and a DICT part.  17 Nov 26 - four-version audit
# round 1, P-3482 (owner's ruling D7): the walk skips SDSYS altogether, as Linux's,
# so the four that must be walked live in a FIXTURE ACCOUNT, ZZNUACCT, at
# C:\ProgramData\SD\zznuacct: a directory, a VOC naming them (relative, as
# CREATE.FILE writes them) and a register record, nothing else (no Windows user
# or group - the walk reads only the register path and the VOC there).  SDSYS's
# VOC names them too, by absolute path, so COPY, CREATE.INDEX and the probe reach
# them from the seat.
#   zznuclean   case sensitive, holds jack          -> must be CONVERTED
#   zznutwin    case sensitive, holds jack and JACK -> DATA must be LEFT, both
#                                                      records kept, pair named
#   zznuak      case sensitive, holds jack, index f1 -> DATA must be LEFT, named
#                                                      as indexed (10185)
#   zznunc      made the ordinary way (NOCASE)      -> CONTROL, untouched
#   zznusys     case sensitive, holds jack, IN SDSYS -> LEFT and not named: the
#                                                      walk does not enter SDSYS
# Each DICT part in the account that starts case sensitive and holds no pair is
# expected to be converted too.  THE DECISIVE READ IS A PROBE PROGRAM that opens
# each part and prints FL$NOCASE (1008), FL$AK (13) and every id as STORED
# (select/readnext), before and after.  "Nothing lost" is the id list, compared
# case-sensitively.
#
# WHAT IT CANNOT REACH, SAID HERE SO A GREEN RUN IS NOT READ AS MORE:
#   - a real account's VOC (ZZNUACCT's is made NOCASE) and the installer's own
#     call (RefreshNocase).  Witnessed only by a real W1.0-0 -> current upgrade.
#   - it ASSUMES A FRESH D2 INSTALL, where every other hashed file is already
#     NOCASE, so the walk converts only these fixtures.  assert-current guards
#     that the install matches source; the converted count row would name any
#     other file the walk converted.
#   - 17 Nov 26: the fixture-account form has NOT completed a run yet: its first
#     (suite b341) hung in the build program (see $buildBasic); the step-traced
#     builder written after it is parse-checked only.
#
# RED BEFORE THE FIX, MEASURED 14 Sep 2026 (the owner's second run; the first
# refused its precondition on this script's own Get-Probe defect).  PREDICTED
# by reading: phase 1's use of old.path before phase 2 set it.  WHAT HAPPENED
# FIRST WAS A THIRD DEFECT: "Select list number out of range at line 136" -
# the walk used lists 13-15 and SD allows 0-12.  Driver exit 1, no COMPLETE,
# 11 FAIL / 20 PASS, and every "lost nothing" row PASSED: nothing converted,
# nothing lost.  The old.path abort was masked, never reached.  All three were
# fixed together; test-selectlists-units.py now guards the list-number class.
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
    Write-Output '  It builds case-sensitive files with sd -internal, through the SDSYS seat, and'
    Write-Output '  runs upgrade-nocase.ps1.'
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
# 16 Nov 26 - RELEASE_1.1 300: the builder of the case-sensitive fixtures (below, $buildBasic).
$buildName = 'zznubuild'
$buildSrc  = Join-Path (Join-Path $sdsys 'bp') $buildName
$buildObj  = Join-Path (Join-Path $sdsys 'bp.out') $buildName
# 17 Nov 26 - P-3482: the fixture account (see the header).  $acctFwd is the path SD is given: one separator throughout.
$acctName  = 'ZZNUACCT'
$acctDir   = Join-Path $dataDir 'zznuacct'
$acctFwd   = $acctDir.Replace([string][char]92, '/')
$acctFixtures = @('zznuclean', 'zznutwin', 'zznuak', 'zznunc')
$sysFixture   = 'zznusys'
$fixtures  = @($acctFixtures + $sysFixture)

Write-Output '===== verify-nocaseupgrade.ps1 ====='
Write-Output ("  sd.exe   : " + $sdExe)
Write-Output ("  driver   : " + $driver + " -AppDir " + $appDir + " -DataDir " + $dataDir)
Write-Output ("  sdsys    : " + $sdsys)
Write-Output ("  account  : " + $acctName + " at " + $acctDir + " (given to SD as " + $acctFwd + ")")
Write-Output ("  log      : " + $logFile)
Write-Output ("  fixtures : " + ($acctFixtures -join ', ') + " in " + $acctName + "; " + $sysFixture + " in SDSYS; probe " + $probeSrc)
foreach ($p in @($sdExe, $driver, (Join-Path $sdsys 'bp'))) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Output ("verify-nocaseupgrade: missing " + $p); exit 2 }
}

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ("  [PASS] " + $name) }
    else { $script:fail++; Write-Output ("  [FAIL] " + $name + $(if ($detail) { "  ->  $detail" } else { '' })) }
}

# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT (sdsys-seat.ps1; verify-createaccount
# was the pilot).  THE "LOGTO SDSYS" PREFIX THE PLAIN LEG USED TO SEND IS REFUSED
# (10002) FROM ANY SESSION THAT DID NOT START AS THE OS SDSYS ACCOUNT with an
# elevated, interactive token, and an elevated Don is not one.  So BOTH legs go to
# a task inside SDSYS's own live session: the plain one as it was, the case-
# sensitive builder through the seat's -Internal door (sd.exe -internal, the only
# maker of a case-sensitive file).  SDSYS must be signed in: `query session` shows
# its row.
#
# ***THE SEAT'S THROW IS TURNED BACK INTO TEXT HERE, AND THAT IS DELIBERATE.***
# Every other converted verifier lets Invoke-SdSeatText throw, but this one's
# cleanup runs through THIS function inside a finally block, and a throw there
# would skip the rest of the sweep and leave the fixtures behind.  A seat that did
# not run comes back as a "*** THE SDSYS SEAT DID NOT RUN" line, so every row that
# reads output fails on it and the run ends exit 2 with the cleanup still done.
# The old version killed stray sd.exe processes on a timeout; the seat stops its
# own task instead, and its report is written when sd.exe exits, so a timed-out call
# returns no SD text (RELEASE_1.1 76's known limit).
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
function Invoke-Bounded([string[]]$lines, [bool]$internal, [int]$TimeoutSec = 180) {
    try {
        return [string](Invoke-SdSeatText -Commands $lines -TimeoutSec $TimeoutSec -Internal:$internal)
    } catch {
        return [string]("`n*** THE SDSYS SEAT DID NOT RUN: " + $_.Exception.Message)
    }
}
# 17 Nov 26 - b341: THE SEAT'S FAILURE LINE WAS FILTERED OUT.  It is one line ("*** THE SDSYS SEAT DID NOT RUN: ... WHAT SD HAD
# PRINTED WHEN IT WAS STOPPED (last lines): <banner> | ... | :RUN bp zznubuild"), and it carries the banner's "free software", so the
# banner filter dropped it whole and "--- build (sd -internal) ---" printed NOTHING.  It is now printed in full, one SD line per row.
function Show([string]$label, [string]$text) {
    Write-Output ("  --- " + $label + " ---")
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '\*\*\* THE SDSYS SEAT DID NOT RUN') {
            foreach ($part in ($l -split ' \| ')) { Write-Output ("    " + $part) }
            continue
        }
        if ($l -match '^\s*:?\s*$|Ladybridge|free software|welcome to modify|conditions\.  For|^SD Core for') { continue }
        Write-Output ("    " + $l)
    }
}

# 16 Nov 26 - RELEASE_1.1 300.  THE CASE-SENSITIVE FIXTURES ARE MADE BY A PROGRAM, NOT BY THE VERB.  This built them with
# "CREATE.FILE zznuclean CASE", and S.87 removed the verb's CASE word (suite b339's red).  The owner's ruling of 16 Nov is
# Linux parity, and Linux's own upgrade test (sandbox-upgradenocase.py) builds its fixtures with the BASIC statement
# CREATE.FILE path DYNAMIC FLAGS 4: DHF_KEEPCASE, a request op_dio1.c honours only in internal mode (the seat's -Internal door,
# sd -internal).  Both parts are made case sensitive, as the verb's CASE made them, and the VOC record is the one CREATE.FILE
# writes for a plain name (F, the name, the name.DIC), so COPY, CREATE.INDEX and DELETE.FILE treat them as before.  A part that
# cannot be made stops the program with a BUILD line, which the precondition row below then names.
# 17 Nov 26 - P-3482: four parts go into the fixture account (zznunc made NOCASE, the control), named by the account's own VOC
# relative to it and by SDSYS's VOC by absolute path; zznusys goes into SDSYS as before; the register record comes last (since
# 17 Nov, written by this script after BUILD done), so a build that stops part way leaves no account for the walk to visit.  @@ACCT@@ is replaced with $acctFwd before the file is written.
# 17 Nov 26 - SUITE b341: THE FIRST RUN OF THIS BUILDER NEVER ENDED.  "RUN bp zznubuild" was SD's last line for 180 s (the seat's
# task still running, LastTaskResult 267009) and not one BUILD line came back, though crt reaches the seat unbuffered (a console
# session's output is written straight to fd 1, linuxio.c write_console; verify-twins' "FIX done" from the same door 15 s earlier).
# So it stopped inside the first seven statements, before the first crt.  Reading them - op_create_dh, create_edit_refusal and
# edit_os_path_refusal (both return at once for SDSYS), make_path (drive letters handled), dh_create_file, the write gates - found
# NOTHING THAT ASKS A QUESTION OR READS INPUT, and no wait that reading alone can prove; NOT FOUND, not guessed at.  What changed:
#   1. A "BUILD step" line BEFORE every statement that touches a file, so a run that hangs again names the statement it is in
#      (the seat's timeout text carries SD's last lines, and Show now prints them - it used to filter the whole line away).
#   2. No statement can ask: every CREATE.FILE has ON ERROR, every OPEN/OPENPATH an ELSE, and the program reads nothing.
#   3. The register record is written by this script after BUILD done, as Linux's sandbox-upgradenocase.py does (reg()), not by
#      the program through OPENPATH @SDSYS : @DS : 'accounts' (a backslash path joined to '/'); one statement fewer in SD.
$buildBasic = @'
* zznubuild - written by verify-nocaseupgrade.ps1.  Safe to delete.
   acct = '@@ACCT@@'
   crt 'BUILD step open VOC'
   open 'VOC' to v else crt 'BUILD no VOC' ; stop
   crt 'BUILD step create ' : acct : '/voc'
   create.file acct : '/voc' dynamic on error crt 'BUILD create failed ' : acct : '/voc' ; stop
   crt 'BUILD step openpath ' : acct : '/voc'
   openpath acct : '/voc' to av else crt 'BUILD cannot open ' : acct : '/voc' ; stop
   names = 'zznuclean' : @fm : 'zznutwin' : @fm : 'zznuak' : @fm : 'zznunc'
   for i = 1 to 4
      n = names<i>
      p = acct : '/' : n
      if n = 'zznunc' then fl = 0 else fl = 4
      crt 'BUILD step create ' : p : '.DIC flags ' : fl
      create.file p : '.DIC' dynamic flags fl on error crt 'BUILD create failed ' : p : '.DIC' ; stop
      crt 'BUILD step create ' : p : ' flags ' : fl
      create.file p dynamic flags fl on error crt 'BUILD create failed ' : p ; stop
      crt 'BUILD step write the account VOC record ' : n
      write 'F' : @fm : n : @fm : n : '.DIC' to av, n
      crt 'BUILD step write the SDSYS VOC record ' : n
      write 'F' : @fm : p : @fm : p : '.DIC' to v, n
      crt 'BUILD made ' : p
   next i
   crt 'BUILD step close the account VOC'
   close av
   n = 'zznusys'
   crt 'BUILD step create ' : n : '.DIC flags 4'
   create.file n : '.DIC' dynamic flags 4 on error crt 'BUILD create failed ' : n : '.DIC' ; stop
   crt 'BUILD step create ' : n : ' flags 4'
   create.file n dynamic flags 4 on error crt 'BUILD create failed ' : n ; stop
   crt 'BUILD step write the SDSYS VOC record ' : n
   write 'F' : @fm : n : @fm : n : '.DIC' to v, n
   crt 'BUILD made ' : n
   crt 'BUILD done'
end
'@

# The probe: one line per fixture part, ids as stored.
$probeBasic = @'
* zznuprobe - written by verify-nocaseupgrade.ps1.  Safe to delete.
   names = 'zznuclean' : @fm : 'zznutwin' : @fm : 'zznuak' : @fm : 'zznunc' : @fm : 'zznusys'
   for i = 1 to 5
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
# 17 Nov 26 - P-3482: the walk makes its work files beside the file it converts, so the fixture account's directory is looked in too.
function Get-TempLeftovers {
    return @(foreach ($d in @($sdsys, $acctDir)) {
        Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^~SD(SCAN|NOCASE)\.' } | ForEach-Object { $_.FullName }
    })
}
# 17 Nov 26 - P-3482: the account's four are dropped from SDSYS's VOC (DELETE, not DELETE.FILE: their pointers are absolute paths
# outside SDSYS) and the register, then the account's directory goes as a whole; zznusys is deleted as before.  Returns what is left:
# SDSYS entries named zznu*, and the account's directory if it is still there.
function Remove-Fixtures {
    $null = Invoke-Bounded @(("DELETE VOC " + ($acctFixtures -join ' ')), "DELETE accounts $acctName", "DELETE.FILE $sysFixture FORCE") $false
    if (Test-Path -LiteralPath $acctDir) { Remove-Item -LiteralPath $acctDir -Recurse -Force -ErrorAction SilentlyContinue }
    foreach ($f in @($probeSrc, $probeObj, $buildSrc, $buildObj)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
    $left = @(Get-ChildItem -LiteralPath $sdsys -Force -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match '^(?i)zznu' } | ForEach-Object { $_.Name })
    if (Test-Path -LiteralPath $acctDir) { $left += $acctDir }
    return $left
}

# 20 Sep 26 - RELEASE_1.1 76: PROVE BOTH SEAT DOORS BEFORE BUILDING ANYTHING, so a
# missing SDSYS session is exit 2 ("could not run") and leaves no fixture behind,
# not a run of rows that fail on empty output.  See sdsys-seat.ps1.
Assert-SdSeat -Label 'verify-nocaseupgrade'
Assert-SdSeat -Label 'verify-nocaseupgrade' -Internal

$exit = 2
$logLenBefore = $(if (Test-Path -LiteralPath $logFile) { (Get-Item -LiteralPath $logFile).Length } else { -1 })
try {
    Write-Output '  --- clearing any earlier fixture ---'
    $left = Remove-Fixtures
    if ($left.Count) { Write-Output ("verify-nocaseupgrade: could not clear " + ($left -join ', ')); exit 2 }
    $tempBefore = Get-TempLeftovers
    if ($tempBefore.Count) { Write-Output ("verify-nocaseupgrade: walk temp files already in sdsys, not this run's: " + ($tempBefore -join ', ')); exit 2 }

    # ---- build: one sd -internal session for every fixture, the account and its register record ----
    $null = New-Item -ItemType Directory -Path $acctDir -Force
    Write-Output ("  made " + $acctDir)
    [IO.File]::WriteAllText($buildSrc, ($buildBasic.Replace('@@ACCT@@', $acctFwd) -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
    Write-Output ("  wrote " + $buildSrc + " (account path " + $acctFwd + ")")
    $mk = Invoke-Bounded @(
        "BASIC bp $buildName",
        "RUN bp $buildName",
        'COPY FROM VOC TO zznuclean who,jack',
        'COPY FROM VOC TO zznutwin who,jack',
        'COPY FROM VOC TO zznutwin who,JACK',
        'COPY FROM VOC TO zznuak who,jack',
        'COPY FROM DICT VOC TO DICT zznuak f1,f1',
        'CREATE.INDEX zznuak f1',
        'BUILD.INDEX zznuak f1',
        'COPY FROM VOC TO zznunc who,jack',
        "COPY FROM VOC TO $sysFixture who,jack") $true
    Show 'build (sd -internal)' $mk
    # 17 Nov 26 - b341: A HANG IS SAID AS A HANG, WITH THE STATEMENT IT WAS IN.  The seat stops a session that does not end within the
    # bound and returns its failure as text (Invoke-Bounded); the last "BUILD step" line SD printed names the statement.
    if ($mk -match '\*\*\* THE SDSYS SEAT DID NOT RUN') {
        $steps = @([regex]::Matches($mk, 'BUILD (?:step|made) [^|\r\n]*') | ForEach-Object { $_.Value.Trim() })
        Write-Output '  verify-nocaseupgrade: THE BUILD SESSION DID NOT END within 180 s - it was stopped, and nothing was measured.'
        Write-Output ('  the last BUILD line SD printed: ' + $(if ($steps.Count) { $steps[$steps.Count - 1] } else { '(none - it stopped before the first statement, or in RUN itself)' }))
        Write-Output '  the statement after that line is the one that did not return; SD''s last lines are printed above.'
        exit 2
    }
    if ($mk -notmatch 'BUILD done') { Write-Output '  verify-nocaseupgrade: the build program did not reach "BUILD done" - see its output above'; exit 2 }
    # The register record, as Linux's sandbox writes it (reg(): a file in the register directory), and only now: a build that
    # stopped part way leaves no account for the walk to visit.  Field 1 is the account's path, the one field the walk reads.
    $regRec = Join-Path (Join-Path $sdsys 'accounts') $acctName
    try {
        [IO.File]::WriteAllText($regRec, $acctFwd, (New-Object Text.ASCIIEncoding))
    } catch {
        Write-Output ('  verify-nocaseupgrade: could not write the register record ' + $regRec + ': ' + $_.Exception.Message); exit 2
    }
    $regBack = [IO.File]::ReadAllText($regRec)
    Write-Output ('  registered ' + $acctName + ' at ' + $regBack + ' (' + $regRec + ')')
    if ($regBack -cne $acctFwd) { Write-Output '  verify-nocaseupgrade: the register record does not read back as written'; exit 2 }
    [IO.File]::WriteAllText($probeSrc, ($probeBasic -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
    Write-Output ("  wrote " + $probeSrc)

    $bp = Get-Probe
    Show 'probe BEFORE' $bp.Text
    Write-Output ("  probe lines read: " + $bp.Lines + " of 10")
    if ($bp.Lines -ne 10) { Write-Output '  verify-nocaseupgrade: the probe did not report all 10 fixture parts - see its output above; nothing measured'; exit 2 }
    $b = $bp.Map
    $want = @{
        'zznuclean/DATA' = @{ NoCase = 0; Ak = 0; Ids = 'jack' }
        'zznutwin/DATA'  = @{ NoCase = 0; Ak = 0; Ids = 'JACK,jack' }
        'zznuak/DATA'    = @{ NoCase = 0; Ak = 1; Ids = 'jack' }
        'zznunc/DATA'    = @{ NoCase = 1; Ak = 0; Ids = 'jack' }
        'zznusys/DATA'   = @{ NoCase = 0; Ak = 0; Ids = 'jack' }
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
    Row 'precondition: three case-sensitive fixtures in ZZNUACCT (one twinned, one indexed), a NOCASE control, and a case-sensitive one in SDSYS, as built' $setupOk
    if (-not $setupOk) { Write-Output '  nothing below would be measured'; exit 2 }

    # Which parts the walk should convert: in the fixture account, case sensitive, no pair, no index.  Nothing in SDSYS (P-3482).
    $expectConvert = @($b.Keys | Where-Object { $b[$_].NoCase -eq 0 -and $_ -ne 'zznutwin/DATA' -and $_ -ne 'zznuak/DATA' -and $_ -notlike "$sysFixture/*" } | Sort-Object)
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
    # ANY SD RUNTIME ERROR, NOT ONE WORDING.  This row first matched only
    # "Unassigned variable" - the abort predicted by reading - and PASSED on the
    # run that stopped on "0000025C: Select list number out of range at line 136
    # of ...UPGRADE_NOCASE".  SD prints every runtime error as
    # "<8 hex>: <text> at line <n> of <object>", so that shape is the anchor.
    $rte = [regex]::Match($drv, '(?m)[0-9A-Fa-f]{8}: .+ at line \d+ of \S+')
    Row 'no SD runtime error in the walk' (-not $rte.Success) $rte.Value
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
    # 17 Nov 26 - P-3482 and the owner's ruling D4: the account walked is named (12035), and SDSYS is not walked, so its fixture
    # appears nowhere in the report.
    Row ("the report names the fixture account (12035: Account " + $acctName + ")") ($drv -match ("(?m)Account " + $acctName + "\s*$")) 'no Account line for the fixture account'
    Row ("the report does not name SDSYS's own fixture " + $sysFixture + " (SDSYS is not walked)") ($drv -notmatch $sysFixture) 'the walk reached into SDSYS'

    # ---- after: every part's flags and stored ids ---------------------------
    $ap = Get-Probe
    Show 'probe AFTER' $ap.Text
    Write-Output ("  probe lines read: " + $ap.Lines + " of 10")
    Row 'the AFTER probe reported all 10 fixture parts' ($ap.Lines -eq 10) "read $($ap.Lines)"
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
    Row 'the walk left no ~SDSCAN or ~SDNOCASE temp file in sdsys or the fixture account' ($tempAfter.Count -eq 0) ($tempAfter -join ', ')

    $exit = $(if ($fail -eq 0) { 0 } else { 1 })
}
finally {
    Write-Output '  --- cleanup ---'
    foreach ($t in @(Get-TempLeftovers)) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue; Write-Output "  removed walk temp $t" }
    $left = @(Remove-Fixtures)
    $vocLeft = Invoke-Bounded @('LIST VOC WITH @ID LIKE "zznu..."') $false
    $vocOk = $vocLeft -match '(?m)^0 record\(s\) listed'
    $regLeft = Invoke-Bounded @("LIST accounts WITH @ID LIKE `"ZZNU...`"") $false
    $regOk = $regLeft -match '(?m)^0 record\(s\) listed'
    Write-Output ("  entries left: " + $(if ($left.Count) { $left -join ', ' } else { '(none)' }) + "; VOC zznu* records: " + $(if ($vocOk) { 'none' } else { 'SOME - see below' }) +
                  "; register ZZNU* records: " + $(if ($regOk) { 'none' } else { 'SOME - see below' }))
    if (-not $vocOk) { Show 'LIST VOC zznu...' $vocLeft }
    if (-not $regOk) { Show 'LIST accounts ZZNU...' $regLeft }
    $cleanOk = ($left.Count -eq 0) -and $vocOk -and $regOk -and -not (Test-Path -LiteralPath $probeSrc) -and -not (Test-Path -LiteralPath $probeObj) -and
               -not (Test-Path -LiteralPath $buildSrc) -and -not (Test-Path -LiteralPath $buildObj)
    Row 'cleanup: no fixture, VOC record, register record, fixture account directory or probe left' $cleanOk
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
