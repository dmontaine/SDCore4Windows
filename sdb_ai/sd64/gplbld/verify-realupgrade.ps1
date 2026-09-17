# verify-realupgrade.ps1 - the REAL upgrade witness for D2's case-insensitivity
# walk: install shipped W1.0-0 (pre-D2, case sensitive), snapshot, install the
# current build over the top, compare.  RELEASE_1.1_FIXES.md 5, the half that
# verify-nocaseupgrade.ps1 explicitly cannot reach.  ***ELEVATED POWERSHELL.***
#
#   powershell -ExecutionPolicy Bypass -File <this> -Snapshot    (on the W1.0-0 tree, BEFORE the upgrade)
#   ... install the current sd-setup-W1.1-0.exe OVER THE TOP, without uninstalling ...
#   powershell -ExecutionPolicy Bypass -File <this> -Compare     (on the upgraded tree, AFTER)
#
# Exit 0 every check passed, 1 a check failed, 2 the test could not be run
# (a precondition was not met - never a FAIL).
#
# WHY IT EXISTS, AND WHAT IT REACHES THAT verify-nocaseupgrade DOES NOT.
# verify-nocaseupgrade forces a case-sensitive state on a FRESH install and runs
# the installed driver by hand.  Three things it names as out of reach happen
# only in a genuine two-installer upgrade, and this is their witness:
#   1. the installer's OWN call - sd.iss RefreshNocase, gated on DataTreeUpgrade.
#      A fresh install never fires it; here the current installer over W1.0-0
#      does, and nocase-upgrade.log is the proof it ran and did real work.
#   2. the LIVE SDSYS VOC skip when that VOC is GENUINELY case sensitive.  On a
#      fresh install the VOC is already NOCASE, so the skip is never exercised
#      for real.  W1.0-0's VOC is case sensitive, so the walk must skip it AND
#      leave every record - the exact fault op_lock/UPGRADE_NOCASE's FL$PATH
#      skip was written for.
#   3. a real hashed data file converting losslessly across the installer, not
#      under a hand-run driver.
#
# THE PRE-D2 PRECONDITION IS THE NULL-CASE GUARD.  -Snapshot builds its fixture
# with plain CREATE.FILE (W1.0-0's default is case sensitive; the CASE keyword
# is a D2-era addition and is NOT used here so the source compiles on the older
# binary) and REFUSES, exit 2, unless the fixture AND the live VOC both read
# FL$NOCASE=0.  A tree where they are already NOCASE is not a pre-D2 W1.0-0
# tree, so there would be nothing for the walk to convert and a green run would
# mean nothing.
#
# THE STATE SURVIVES THE INSTALLER because the snapshot is written under
# C:\ProgramData\SD-verify, which no installer touches - never under the two
# trees the upgrade replaces or preserves.
#
# WHAT IT DOES NOT REACH, said here so a green run is not read as more: a
# SEPARATE registered (non-SDSYS) account's VOC.  The fixture is planted in
# SDSYS, which exercises UPGRADE_NOCASE's do.account path and the live-VOC skip;
# a second account would add CREATE.ACCOUNT on the W1.0-0 tree and is left for a
# later leg.  This is stated, not measured away.
#
# BOUNDED: every SD session runs as a job with a timeout; any sd.exe a timed-out
# session leaves is not this script's to kill (it starts none by name).
#
# -SetupLog <file> (with -Compare): RELEASE_1.1 40's witness.  Install the W1.1-0
# build with /LOG="<file>"; sd.iss's SayStep writes each upgrade caption it puts
# on the wizard into that log as "SayStep: <caption>", so the three captions -
# shown for a few seconds each on a fast box - leave a record.  The three must
# be present, in the order the steps run (dictionaries, VOCs, nocase), and the
# file must exist: a missing log is exit 2, never a pass.  A FIRST install must
# write none of them; that half is gated in the code (after DataTreeWasAbsent)
# and is not measured here, because the fresh install is not this script's.
#
# -Prepare: the teardown that has to come BEFORE the W1.0-0 install, which was
# four hand steps with a race in the middle (Inno's uninstaller copies itself and
# returns at once, so a Remove-Item typed next runs while it is still working).
# Stops SD the way cycle.ps1 does, runs unins000 /VERYSILENT and waits for the
# Program Files tree to go, deletes BOTH trees (the uninstaller keeps the data by
# design - RELEASE_1.1 38), proves the shipped W1.0-0 installer is the right file
# by hash, and stops: the W1.0-0 install itself is interactive (its wizard
# collects the SDSYS password; a silent install has none, HISTORY.md 23 Aug).
# THE TRAP IT EXISTS FOR: installing W1.0-0 over an existing tree is a
# DataTreeUpgrade that PRESERVES the 1.1 accounts, giving a W1.0-0/1.1 mix that
# is not pre-D2 - -Snapshot would then refuse.
[CmdletBinding()]
param(
    [switch] $Prepare,
    [switch] $Snapshot,
    [switch] $Compare,
    [string] $SetupLog = ''
)
$ErrorActionPreference = 'Stop'

$modes = @($Prepare, $Snapshot, $Compare | Where-Object { $_ }).Count
if ($modes -ne 1) {
    Write-Output 'verify-realupgrade: pass exactly one of -Prepare, -Snapshot or -Compare.'
    Write-Output '  -Prepare  tears the current install down so W1.0-0 can install onto an ABSENT tree;'
    Write-Output '  -Snapshot on the W1.0-0 tree BEFORE installing the current build over the top;'
    Write-Output '  -Compare  on the upgraded tree AFTER (with -SetupLog <file> for RELEASE_1.1 40).'
    exit 2
}
if ($Snapshot -and $SetupLog) {
    Write-Output 'verify-realupgrade: -SetupLog goes with -Compare (the log is written by the W1.1-0 install, which comes after -Snapshot).'
    exit 2
}

$wpr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $wpr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-realupgrade: this needs an ELEVATED session and this one is not.'
    exit 2
}

$appDir   = Join-Path $env:ProgramFiles 'SD'
$sdExe    = Join-Path $appDir 'usr\bin\sd.exe'
$dataDir  = Join-Path $env:ProgramData 'SD'
$sdsys    = Join-Path $dataDir 'sdsys'
$logFile  = Join-Path $dataDir 'nocase-upgrade.log'
$snapDir  = Join-Path $env:ProgramData 'SD-verify'
$snapFile = Join-Path $snapDir 'realupgrade-snapshot.json'
$fixture  = 'zzruclean'
$probeName = 'zzruprobe'
$probeSrc  = Join-Path (Join-Path $sdsys 'bp') $probeName
$probeObj  = Join-Path (Join-Path $sdsys 'bp.out') $probeName

$pass = 0; $fail = 0
function Row([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Write-Output ("  [" + $(if ($ok) { 'PASS' } else { 'FAIL' }) + "] " + $name + $(if ($detail) { "  ->  " + $detail } else { '' }))
}
function Invoke-Bounded([string[]]$lines, [bool]$internal, [int]$TimeoutSec = 120) {
    $body = "`n" + ((@('TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock {
        param($exe, $text, $int)
        if ($int) { $text | & $exe '-internal' 2>&1 } else { $text | & $exe 2>&1 }
    } -ArgumentList $sdExe, $body, $internal
    $done = [bool](Wait-Job $job -Timeout $TimeoutSec)
    if (-not $done) { Stop-Job $job -ErrorAction SilentlyContinue }
    $out = (@(Receive-Job $job -ErrorAction SilentlyContinue) | Out-String) -replace ([char]27 + '\[[0-9]*[A-Za-z]'), ''
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if (-not $done) { $out += "`n*** DID NOT FINISH IN $TimeoutSec s" }
    return [string]$out
}
function Show([string]$label, [string]$text) {
    Write-Output ("  --- " + $label + " ---")
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '^\s*:?\s*$|Ladybridge|free software|welcome to modify|conditions\.  For|^SD Core for|^SD, the') { continue }
        Write-Output ("    " + $l)
    }
}
# The probe opens the planted fixture and the LIVE VOC and prints, for each, its
# FL$NOCASE (1008) and - for the fixture - FL$AK (13) and every id as STORED.
# The VOC's ids are not listed (it is large); its record COUNT and two sentinel
# records (WHO, LOGIN) stand for "nothing was lost".  Long-standing intrinsics
# only, so W1.0-0's BCOMP and the current one both compile it.
#
# THE SENTINEL MATCH IS CASE-INSENSITIVE, AND THAT IS THE WHOLE POINT OF THE
# TREE IT RUNS ON.  16 Sep 2026: this compared id to the literals 'WHO' and
# 'LOGIN' exactly, and a genuine pre-D2 W1.0-0 VOC stores them LOWER case - so
# SENT came back empty and -Snapshot refused (exit 2) on the one tree it was
# written for.  Measured in the same transcript: "COPY FROM VOC TO <fix>
# who,jack" matched on a file whose FL$NOCASE is 0 and copied 1 record, so the
# stored spelling is 'who'.  It now folds with upcase() and reports the id AS
# STORED, so the evidence shows the real spelling and the check still means
# "this record survived" on BOTH sides of the upgrade - the tree is case
# sensitive before it and NOCASE after, and the sentinel must span that.
# The PowerShell -match that reads this is case-insensitive by default, so
# '[who]' still satisfies '\[WHO\]'.
$probeBasic = @'
* zzruprobe - written by verify-realupgrade.ps1.  Safe to delete.
   open 'zzruclean' to f then
      ids = ''
      select f to 9
      loop
         readnext id from 9 else exit
         ids := '[' : id : ']'
      repeat
      crt 'FIX zzruclean NOCASE=' : fileinfo(f, 1008) : ' AK=' : fileinfo(f, 13) : ' IDS=' : ids
      close f
   end else
      crt 'FIX zzruclean NOFILE'
   end
   open 'VOC' to v then
      n = 0 ; sent = ''
      select v to 8
      loop
         readnext id from 8 else exit
         n += 1
         if upcase(id) = 'WHO' then sent := '[' : id : ']'
         if upcase(id) = 'LOGIN' then sent := '[' : id : ']'
      repeat
      crt 'VOCINFO NOCASE=' : fileinfo(v, 1008) : ' COUNT=' : n : ' SENT=' : sent
      close v
   end else
      crt 'VOCINFO NOFILE'
   end
end
'@

function Get-Probe {
    $t = Invoke-Bounded @("BASIC bp $probeName", "RUN bp $probeName") $true
    $fx = [regex]::Match($t, '(?m)^FIX zzruclean (?:NOCASE=(\d+) AK=(\d+) IDS=(.*?)|NOFILE)\s*$')
    $vc = [regex]::Match($t, '(?m)^VOCINFO (?:NOCASE=(\d+) COUNT=(\d+) SENT=(.*?)|NOFILE)\s*$')
    $ids = @()
    if ($fx.Success -and $fx.Groups[1].Success) {
        $ids = @([regex]::Matches($fx.Groups[3].Value, '\[([^\]]*)\]') | ForEach-Object { $_.Groups[1].Value })
        [string[]]$arr = $ids; [Array]::Sort($arr, [StringComparer]::Ordinal); $ids = $arr
    }
    return [pscustomobject]@{
        Text       = $t
        FixOk      = $fx.Success -and $fx.Groups[1].Success
        FixNoCase  = $(if ($fx.Groups[1].Success) { [int]$fx.Groups[1].Value } else { -1 })
        FixAk      = $(if ($fx.Groups[2].Success) { [int]$fx.Groups[2].Value } else { -1 })
        FixIds     = ($ids -join ',')
        VocOk      = $vc.Success -and $vc.Groups[1].Success
        VocNoCase  = $(if ($vc.Groups[1].Success) { [int]$vc.Groups[1].Value } else { -1 })
        VocCount   = $(if ($vc.Groups[2].Success) { [int]$vc.Groups[2].Value } else { -1 })
        VocSent    = $(if ($vc.Groups[3].Success) { $vc.Groups[3].Value } else { '' })
    }
}
function Remove-Fixture {
    $null = Invoke-Bounded @("DELETE.FILE $fixture FORCE") $false
    foreach ($f in @($probeSrc, $probeObj)) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
}

Write-Output '===== verify-realupgrade.ps1 ====='
Write-Output ("  mode     : " + $(if ($Prepare) { '-Prepare (tear down for a W1.0-0 install onto an absent tree)' } elseif ($Snapshot) { '-Snapshot (pre-D2 W1.0-0 tree)' } else { '-Compare (upgraded tree)' }))
Write-Output ("  sd.exe   : " + $sdExe)
Write-Output ("  snapshot : " + $snapFile)

# ---------------------------------------------------------------------------
if ($Prepare) {
    $shipped = 'C:\Users\Don\SDCoreProject\SD-Untracked\realupgrade\sd-setup-W1.0-0-SHIPPED.exe'
    $shippedShaPrefix = 'B7D37FB6'      # PROJECT_STATUS.md handoff 73: byte-identical to SDCore-W1.0-0.zip's installer
    $exit = 2
    try {
        # The W1.0-0 installer first, so a wrong or missing file is found before
        # anything is torn down.
        Write-Output ("  W1.0-0   : " + $shipped)
        if (-not (Test-Path -LiteralPath $shipped)) { Write-Output '  the shipped W1.0-0 installer is not there.  Nothing torn down.'; exit 2 }
        $sha = (Get-FileHash -LiteralPath $shipped -Algorithm SHA256).Hash
        Write-Output ("  sha256   : " + $sha)
        if (-not $sha.StartsWith($shippedShaPrefix)) { Write-Output "  that is not the SHIPPED W1.0-0 installer (sha256 should begin $shippedShaPrefix).  Nothing torn down."; exit 2 }

        # 1. stop SD - cycle.ps1 step 1's shape: the wait is on the PROCESSES.
        Write-Output ''
        Write-Output '  --- 1. stopping SD ---'
        if (Get-Service -Name SD -ErrorAction SilentlyContinue) { & "$env:SystemRoot\System32\sc.exe" stop SD | Out-Null }
        $deadline = (Get-Date).AddSeconds(45)
        while ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        if ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $sdExe)) {
            Write-Output '  a daemon is still up - asking sd -stop'
            $stopOut = (& $sdExe -stop 2>&1 | Out-String)
            $stopOut -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Output "    $_" }
            $deadline = (Get-Date).AddSeconds(20)
            while ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
        }
        $left = @(Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue)
        if ($left.Count -gt 0) {
            Write-Output ("  still running: " + (($left | ForEach-Object { "$($_.Name)($($_.Id))" }) -join ', ') + " - somebody's session; not killed from here.  Close it and run -Prepare again.")
            exit 2
        }
        Write-Output '  SD is down (no sdwind, no sd)'

        # 2. uninstall - Inno's uninstaller copies itself and returns at once, so
        #    wait for the TREE to go, as cycle.ps1 step 5 does.
        Write-Output ''
        Write-Output '  --- 2. uninstalling (/VERYSILENT - keeps the data by design; step 3 removes it) ---'
        $unins = Join-Path $appDir 'unins000.exe'
        if (Test-Path -LiteralPath $unins) {
            & $unins /VERYSILENT
            $deadline = (Get-Date).AddSeconds(120)
            while ((Test-Path -LiteralPath $appDir) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
            Write-Output ("  uninstaller ran; $appDir " + $(if (Test-Path -LiteralPath $appDir) { 'still present (RELEASE_1.1 38 keeps sd.conf - step 3 takes it)' } else { 'gone' }))
        } else {
            Write-Output "  nothing installed at $appDir"
        }

        # 3. both trees - the W1.0-0 install must land on an ABSENT data tree.
        Write-Output ''
        Write-Output '  --- 3. deleting BOTH trees ---'
        foreach ($t in @($appDir, $dataDir)) {
            if (Test-Path -LiteralPath $t) { Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $t) { Write-Output "  could not delete $t - something still has a handle on it.  Close any SD session or Explorer window and run -Prepare again."; exit 2 }
            Write-Output "  $t gone"
        }
        Row 'both trees are absent (the W1.0-0 install will be a first install, pre-D2)' ((-not (Test-Path -LiteralPath $appDir)) -and (-not (Test-Path -LiteralPath $dataDir)))
        Row 'no sdwind or sd process remains' (@(Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue).Count -eq 0)
        $exit = $(if ($fail -gt 0) { 1 } else { 0 })
        if ($exit -eq 0) {
            Write-Output ''
            Write-Output '  NEXT (elevated): run the shipped W1.0-0 installer INTERACTIVELY, defaults, and give SDSYS a password:'
            Write-Output "        $shipped"
            Write-Output '  then this script with -Snapshot.'
        }
    }
    catch { Write-Output ("verify-realupgrade: " + $_.Exception.Message); $exit = $(if ($fail -gt 0) { 1 } else { 2 }) }
    Write-Output ''
    Write-Output ("verify-realupgrade -Prepare: $pass passed, $fail failed; exit $exit")
    exit $exit
}

if (-not (Test-Path -LiteralPath $sdExe)) { Write-Output "verify-realupgrade: no sd.exe at the path above - is SD installed?"; exit 2 }

# ---------------------------------------------------------------------------
if ($Snapshot) {
    $exit = 2
    try {
        if (-not (Test-Path -LiteralPath $snapDir)) { $null = New-Item -ItemType Directory -Path $snapDir -Force }
        Remove-Fixture
        # Build the fixture the W1.0-0 way: plain CREATE.FILE (default is case
        # sensitive pre-D2).  Two clean lower-case ids, no pair - must convert.
        $mk = Invoke-Bounded @(
            "CREATE.FILE $fixture",
            "COPY FROM VOC TO $fixture who,jack",
            "COPY FROM VOC TO $fixture who,fred") $true
        Show 'build the case-sensitive fixture (sd -internal)' $mk
        [IO.File]::WriteAllText($probeSrc, ($probeBasic -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
        Write-Output ("  wrote " + $probeSrc)

        $p = Get-Probe
        Show 'probe BEFORE the upgrade' $p.Text
        Row 'the fixture built and the probe read it' $p.FixOk $(if ($p.FixOk) { "NOCASE=$($p.FixNoCase) AK=$($p.FixAk) IDS=$($p.FixIds)" } else { 'no FIX line' })
        Row 'the probe read the live VOC' $p.VocOk $(if ($p.VocOk) { "NOCASE=$($p.VocNoCase) COUNT=$($p.VocCount) SENT=$($p.VocSent)" } else { 'no VOCINFO line' })
        if (-not $p.FixOk -or -not $p.VocOk) { Write-Output '  nothing measured - the probe did not report both files'; exit 2 }

        # THE PRE-D2 PRECONDITION - the null-case guard.
        $preOk = ($p.FixNoCase -eq 0) -and ($p.VocNoCase -eq 0) -and ($p.FixIds -ceq 'fred,jack') -and ($p.FixAk -eq 0)
        Row 'PRECONDITION: this is a pre-D2 tree - fixture and live VOC both case sensitive (FL$NOCASE=0)' $preOk `
            "fixture NOCASE=$($p.FixNoCase) ids=$($p.FixIds); VOC NOCASE=$($p.VocNoCase)"
        if (-not $preOk) {
            Write-Output '  This is NOT a pre-D2 W1.0-0 tree (something already reads NOCASE, or the'
            Write-Output '  fixture ids are wrong).  There would be nothing for the walk to convert, so'
            Write-Output '  the upgrade could not be witnessed.  Install shipped W1.0-0 first.'
            exit 2
        }
        $sentOk = ($p.VocSent -match '\[WHO\]') -and ($p.VocSent -match '\[LOGIN\]')
        Row 'the live VOC holds the sentinels WHO and LOGIN (baseline for "nothing lost")' $sentOk "SENT=$($p.VocSent)"
        if (-not $sentOk) { Write-Output '  the VOC sentinels are not both present - cannot use them as a loss baseline'; exit 2 }

        $snap = [pscustomobject]@{
            When       = (Get-Date).ToString('o')
            SdExeSha   = (Get-FileHash -LiteralPath $sdExe -Algorithm SHA256).Hash
            SdExeMtime = (Get-Item -LiteralPath $sdExe).LastWriteTime.ToString('o')
            FixIds     = $p.FixIds
            FixNoCase  = $p.FixNoCase
            VocCount   = $p.VocCount
            VocNoCase  = $p.VocNoCase
            VocSent    = $p.VocSent
            LogMtime   = $(if (Test-Path -LiteralPath $logFile) { (Get-Item -LiteralPath $logFile).LastWriteTime.ToString('o') } else { '' })
        }
        $snap | ConvertTo-Json | Set-Content -LiteralPath $snapFile -Encoding UTF8
        Write-Output ''
        Write-Output ("  snapshot written: " + $snapFile)
        Write-Output ("    fixture ids=" + $snap.FixIds + "  VOC count=" + $snap.VocCount + "  sd.exe " + $snap.SdExeSha.Substring(0,16))
        Write-Output ''
        Write-Output '  NEXT: install the current sd-setup-W1.1-0.exe OVER THE TOP (do NOT uninstall),'
        Write-Output '        then run this script with -Compare, elevated.'
        $exit = $(if ($fail -gt 0) { 1 } else { 0 })
    }
    catch { Write-Output ("verify-realupgrade: " + $_.Exception.Message); $exit = 2 }
    Write-Output ''
    Write-Output ("verify-realupgrade -Snapshot: $pass passed, $fail failed; exit $exit")
    exit $exit
}

# ---------------------------------------------------------------------------
if ($Compare) {
    $exit = 2
    try {
        if (-not (Test-Path -LiteralPath $snapFile)) {
            Write-Output "verify-realupgrade: no snapshot at $snapFile - run -Snapshot on the W1.0-0 tree first."
            exit 2
        }
        $snap = Get-Content -LiteralPath $snapFile -Raw | ConvertFrom-Json
        Write-Output ("  snapshot from " + $snap.When + ": fixture ids=" + $snap.FixIds + " VOC count=" + $snap.VocCount)

        # The installed tree must now be the CURRENT source (the upgrade installed it).
        $ac = & (Join-Path $PSScriptRoot 'assert-current.ps1'); $acCode = $LASTEXITCODE
        Row 'the upgraded tree matches current source (assert-current exit 0)' ($acCode -eq 0) "exit $acCode"
        if ($acCode -ne 0) { Write-Output '  assert-current refused - the tree under test is not the current build; see above.'; exit 2 }

        # sd.exe must have CHANGED across the upgrade - a real over-the-top install.
        $nowSha = (Get-FileHash -LiteralPath $sdExe -Algorithm SHA256).Hash
        Row 'the upgrade replaced sd.exe (hash differs from the W1.0-0 snapshot)' ($nowSha -ne $snap.SdExeSha) `
            ("was " + $snap.SdExeSha.Substring(0,16) + ", now " + $nowSha.Substring(0,16))

        # 1. RefreshNocase RAN and did real work - the only caller is the installer.
        $logOk = Test-Path -LiteralPath $logFile
        $logText = $(if ($logOk) { Get-Content -LiteralPath $logFile -Raw } else { '' })
        Show 'nocase-upgrade.log (written by the installer''s RefreshNocase)' $logText
        # 16 Sep 26 - THE GUTTER IS WHY THIS COULD NEVER MATCH.  This read
        # '(?m)^\s*COMPLETE\s*$', and upgrade-nocase.ps1 relays SD's report
        # through a "  | " gutter, so the real line is "  | COMPLETE" and \s*
        # does not admit the pipe.  Measured on the first real upgrade: the row
        # reported "no COMPLETE line" and exited 2 while the row BELOW it passed
        # with Converted=10 - two checks over one log contradicting each other,
        # which is the tell.  It gated rows 3a/3b and 2a/2b/2c, so a matcher
        # fault read as "the pre-D2 state was not what -Snapshot recorded".
        #
        # trouble=True is deliberately NOT a disqualifier here.  This row asks
        # only whether the INSTALLER RAN THE WALK, and COMPLETE is printed on
        # the finished path only; the $ipc lock failure that sets trouble is a
        # real but separate defect, tracked as RELEASE_1.1 51.
        $complete = $logText -match '(?m)^\s*(?:\|\s*)?COMPLETE\s*$'
        $conv = [regex]::Match($logText, 'Converted\s+(\d+)\s+of\s+(\d+)\s+file')
        $converted = $(if ($conv.Success) { [int]$conv.Groups[1].Value } else { -1 })
        Row 'INSTALLER RAN THE WALK: nocase-upgrade.log exists and says COMPLETE' ($logOk -and $complete) `
            $(if (-not $logOk) { 'no log' } elseif ($complete) { 'COMPLETE' } else { 'no COMPLETE line' })
        Row 'NOT A NO-OP: the walk converted at least one real file' ($converted -ge 1) "Converted=$converted"
        if (-not ($logOk -and $complete) -or $converted -lt 1) {
            Write-Output '  RefreshNocase either did not run or found nothing to convert - the pre-D2'
            Write-Output '  state was not what -Snapshot recorded.  Not a pass.'
            exit 2
        }

        $p = Get-Probe
        Show 'probe AFTER the upgrade' $p.Text
        Row 'the probe read the fixture and the VOC after the upgrade' ($p.FixOk -and $p.VocOk) `
            $(if ($p.FixOk -and $p.VocOk) { "fixture NOCASE=$($p.FixNoCase) ids=$($p.FixIds); VOC NOCASE=$($p.VocNoCase) COUNT=$($p.VocCount)" } else { 'a file did not open' })
        if (-not $p.FixOk) {
            Row '3. the planted file survived the upgrade (records not lost)' $false 'zzruclean NOFILE - the upgrade deleted it'
        } else {
            # 3. the real hashed file converted, losslessly.
            Row '3a. the planted file is now NOCASE (converted by the walk)' ($p.FixNoCase -eq 1) "NOCASE=$($p.FixNoCase)"
            Row '3b. every id survived, case for case (nothing lost)' ($p.FixIds -ceq $snap.FixIds) "was [$($snap.FixIds)], now [$($p.FixIds)]"
        }
        if ($p.VocOk) {
            # 2. the LIVE SDSYS VOC skip - left case sensitive, every record kept.
            Row '2a. the live SDSYS VOC was LEFT case sensitive (FL$NOCASE=0 - skipped, not rebuilt)' ($p.VocNoCase -eq 0) "NOCASE=$($p.VocNoCase)"
            Row '2b. the live VOC lost no records (count did not fall; refresh may add verbs)' ($p.VocCount -ge $snap.VocCount) "was $($snap.VocCount), now $($p.VocCount)"
            Row '2c. the VOC sentinels WHO and LOGIN are still present' (($p.VocSent -match '\[WHO\]') -and ($p.VocSent -match '\[LOGIN\]')) "SENT=$($p.VocSent)"
        }

        # 4. RELEASE_1.1 40 - the upgrade captions, read back from the setup log.
        if ($SetupLog) {
            Write-Output ''
            Write-Output "  --- setup log (installer run with /LOG): $SetupLog ---"
            if (-not (Test-Path -LiteralPath $SetupLog)) {
                Write-Output '  the setup log is not there - was the W1.1-0 installer run with /LOG="<that path>"?  Not a pass.'
                exit 2
            }
            $setupText = Get-Content -LiteralPath $SetupLog -Raw
            $sayLines = @([regex]::Matches($setupText, '(?m)^.*SayStep: .*$') | ForEach-Object { $_.Value.Trim() })
            Show 'SayStep lines in the setup log' ($sayLines -join "`n")
            $captions = @(
                "Bringing this release's dictionaries forward into your database...",
                'Refreshing the vocabulary of every account...',
                'Checking every file for record ids that differ only by case...'
            )
            $positions = @()
            foreach ($c in $captions) {
                $i = $setupText.IndexOf('SayStep: ' + $c)
                $positions += $i
                Row "4. caption on the wizard, logged: '$c'" ($i -ge 0) $(if ($i -ge 0) { 'present' } else { 'ABSENT' })
            }
            Row '4. exactly three SayStep lines - each step announced once, none unaccounted for' ($sayLines.Count -eq 3) "count=$($sayLines.Count)"
            Row '4. in the order the steps run: dictionaries, then VOCs, then nocase' `
                (($positions[0] -ge 0) -and ($positions[0] -lt $positions[1]) -and ($positions[1] -lt $positions[2])) ("offsets " + ($positions -join ', '))
        } else {
            Write-Output ''
            Write-Output '  (no -SetupLog given: RELEASE_1.1 40''s captions were not checked)'
        }

        Write-Output ''
        Write-Output '  --- cleanup: removing the fixture and probe ---'
        Remove-Fixture
        Remove-Item -LiteralPath $snapFile -Force -ErrorAction SilentlyContinue
        $left = Test-Path -LiteralPath (Join-Path $sdsys $fixture)
        Row 'cleanup: the fixture and snapshot are gone' (-not $left) $(if ($left) { "$fixture remains" } else { '' })

        $exit = $(if ($fail -gt 0) { 1 } else { 0 })
    }
    catch { Write-Output ("verify-realupgrade: " + $_.Exception.Message); $exit = $(if ($fail -gt 0) { 1 } else { 2 }) }
    Write-Output ''
    Write-Output ("verify-realupgrade -Compare: $pass passed, $fail failed; exit $exit")
    Write-Output '  A cycle is owed afterwards to restore a clean current install.'
    exit $exit
}
