# verify-upgrade.ps1 - measure a DATA-TREE UPGRADE: install over the top.
# PROJECT_STATUS.md "START HERE" item 3.
#
#   powershell -File verify-upgrade.ps1 -Snapshot     BEFORE the upgrade
#   ... run the installer over the existing install, WITHOUT uninstalling ...
#   powershell -File verify-upgrade.ps1 -Compare      AFTER it
#
# Exit 0 every check passed, 1 a check failed, 2 the test could not be run.
#
# WHY THIS EXISTS.  The upgrade path is the largest untested thing in the
# project: every part of it is gated on DataTreeUpgrade, and every cycle this
# machine has ever run was a FIRST install, so none of it has executed.  It
# also cannot be tested by cycle.ps1 - that script deliberately uninstalls and
# deletes both trees first, which is the opposite of what an upgrade does.
#
# ============================================================================
# THE NULL CASE IS THE WHOLE DIFFICULTY, AND HASHES DO NOT SOLVE IT
# ============================================================================
#
# The obvious test - "the preserved files are unchanged" - passes PERFECTLY on
# an upgrade that never ran.  Nothing happened, so nothing changed, so every
# preservation check is green.  That is a test that passes because it did
# nothing, which CLAUDE.md's instrument rule says must fail.
#
# COMPARING CONTENT DOES NOT RESCUE IT EITHER.  An upgrade built from the same
# source copies back byte-identical files, so "the replaced files changed"
# is false on a legitimate upgrade.  Timestamps do not help: Inno gives a
# copied file its SOURCE file's timestamp.
#
# ============================================================================
# SO THE INSTRUMENT IS A PAIR OF PROBE FILES, AND THEY MUST DISAGREE
# ============================================================================
#
# -Snapshot writes the same marker file into two directories:
#
#   sdsys\bp\$upgrade-probe     - bp is on SDSYS_PRESERVE.  SD ships nothing
#                                 into it, so it is empty and a stray file
#                                 there is harmless.  It MUST SURVIVE.
#   sdsys\gcat\$upgrade-probe   - gcat is on the computed replace list, so
#                                 upgrade.iss deletes the whole directory with
#                                 Type: filesandordirs before [Files] copies it
#                                 back.  It MUST BE GONE.
#
# NEITHER ALONE PROVES ANYTHING.  Both surviving means the installer never ran.
# Both gone means it replaced something it was supposed to keep.  Only the
# DISAGREEMENT is consistent with an upgrade that did what it says, and it
# stays decisive even when every copied byte is identical.
#
# ============================================================================
# THE RETIRED NAME IS FORCED, BECAUSE THIS MACHINE CANNOT REACH IT OTHERWISE
# ============================================================================
#
# SDSYS_RETIRED deletes sdsys\changelog on upgrade.  It is DELETE-ONLY: a first
# install never creates it, so on a machine that has only ever had first
# installs the file is already absent and the check would pass having measured
# nothing.  -Snapshot therefore CREATES it, with known content, putting the
# tree into the state an upgrade-from-an-older-version would be in.  Forcing a
# state to reach a branch is the technique verify-notyet.ps1 uses for the same
# reason: the branch that matters most is otherwise the one never observed.

[CmdletBinding()]
param(
    [switch] $Snapshot,
    [switch] $Compare,

    # Where the snapshot is kept between the two runs.
    #
    # ***NOT %LOCALAPPDATA%, AND THAT IS MEASURED RATHER THAN PREFERRED.***
    # -Snapshot and -Compare are often run by DIFFERENT processes, and one of
    # them may be inside a packaged (MSIX) app - the agent's tooling is.  A
    # packaged process has its %LOCALAPPDATA% WRITES redirected into
    # ...\Packages\<pkg>\LocalCache\Local\, while READS of the same path fall
    # through to the real location when nothing shadows them.  So a snapshot
    # written by one lands somewhere the other cannot see, and -Compare reports
    # "no snapshot" against a file that visibly exists.
    #
    # THAT COST A RUN ON 25 Aug 2026.  -Snapshot at 21:18 reported success and
    # the file was readable back; -Compare from the owner's own elevated shell
    # at 21:22:59 said the snapshot was not there.  Both were right.
    # probe-redirection.ps1 settled it: a write to
    # C:\Users\dmont\AppData\Local\SD-verify turned up under the package cache,
    # while writes to C:\ProgramData\SD-verify and C:\Users\dmont\sdout did not.
    #
    # ProgramData is not redirected and this script already requires elevation,
    # so it is writable and it is the same path for everybody.
    [string] $StatePath = 'C:\ProgramData\SD-verify\upgrade-snapshot.json'
)

$ErrorActionPreference = 'Stop'

if (-not ($Snapshot -xor $Compare)) {
    Write-Output 'verify-upgrade: pass exactly one of -Snapshot or -Compare.'
    Write-Output '  -Snapshot BEFORE installing over the top, -Compare after.'
    exit 2
}

$mode = 'Compare'
if ($Snapshot) { $mode = 'Snapshot' }

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-upgrade-' + $mode.ToLower() + '-' +
                              (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

# NO assert-current HERE, AND THAT IS DELIBERATE - it is the one verifier that
# must not call it.  assert-current compares the INSTALL against SOURCE, and an
# upgrade test needs the install to be the OLD build while source is the NEW
# one; between -Snapshot and -Compare the tree is expected to be stale, and a
# guard that refuses on that would make this script unable to run at all.
# What replaces it: -Compare records the sd.exe hash on both sides and says
# whether the binary moved, so the transcript states what was upgraded to what.
Write-Output 'verify-upgrade: assert-current is deliberately NOT called - see the header.'

$principal = New-Object Security.Principal.WindowsPrincipal(
                 [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output ''
    Write-Output 'verify-upgrade: CANNOT RUN - not elevated.'
    Write-Output '  sdsys\$cred is readable only by administrators, and the probe files'
    Write-Output '  are written into a protected tree.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
Write-Output ('elevated as: ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)

$dataDir = Join-Path $env:ProgramData 'SD'
$sdsys   = Join-Path $dataDir 'sdsys'
$appDir  = Join-Path $env:ProgramFiles 'SD'
$sdExe   = Join-Path $appDir 'usr\bin\sd.exe'

$PROBE      = '$upgrade-probe'
$PROBE_TEXT = 'verify-upgrade.ps1 probe - safe to delete'
$probeKeep  = Join-Path $sdsys ('bp\'   + $PROBE)     # MUST survive
$probeGone  = Join-Path $sdsys ('gcat\' + $PROBE)     # MUST be removed

# stage.py SDSYS_PRESERVE, and the upgrade log's own "an upgrade PRESERVES" line.
$PRESERVE = @('$cred', 'accounts', 'cat', 'os.users', 'os.users.dic',
              'batch.jobs', 'batch.jobs.dic', 'prt', '$hold', 'bp', 'bp.out')

# The computed replace list - the ship lists minus preserve.
$REPLACE  = @('gpl.bp', 'syscom', 'newvoc', 'voc_template', 'messages',
              'sd.voclib', 'licence', 'contrib', 'gpl.bp.out', 'gcat',
              'pcode.out', 'bin', 'terminfo', 'terminfo.src')

# Named by NO ship list, and protected by that alone.  voc is a dynamic file
# made by "sd -i" and declared nowhere; $standalone is the mode marker and
# errlog is the log.  If the upgrade ever reaches these, the default that
# protects them has stopped working.
$UNNAMED  = @('voc', '$standalone', 'errlog')

Write-Output ''
Write-Output '=== what this run is measuring ==================================='
Write-Output ("  mode      : " + $mode)
Write-Output ("  data tree : " + $sdsys)
Write-Output ("  app dir   : " + $appDir)
Write-Output ("  state file: " + $StatePath)
Write-Output ("  preserve  : " + $PRESERVE.Count + " names   replace: " + $REPLACE.Count +
              " names   unnamed: " + $UNNAMED.Count)

if (-not (Test-Path -LiteralPath $sdsys)) {
    Write-Output ''
    Write-Output ("verify-upgrade: CANNOT RUN - there is no data tree at " + $sdsys)
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

# ---------------------------------------------------------------------------
# Fingerprinting.  A directory's fingerprint is the sorted list of its files
# with each file's length and SHA256, hashed again - so a change anywhere
# inside moves it.  CreationTime is recorded separately because it is what
# distinguishes "left alone" from "deleted and recreated with identical
# contents", which is the case content hashing cannot see.
# ---------------------------------------------------------------------------
function Get-Fingerprint([string]$path) {
    $r = [pscustomobject]@{
        Exists = $false; Kind = 'absent'; Hash = ''; Count = 0
        Created = ''; Readable = $true
    }
    if (-not (Test-Path -LiteralPath $path)) { return $r }
    $r.Exists = $true
    $item = Get-Item -LiteralPath $path -Force
    $r.Created = $item.CreationTimeUtc.ToString('o')
    if ($item.PSIsContainer) {
        $r.Kind = 'dir'
        try {
            $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction Stop)
        } catch {
            $r.Readable = $false
            return $r
        }
        $r.Count = $files.Count
        $sb = New-Object System.Text.StringBuilder
        foreach ($f in ($files | Sort-Object FullName)) {
            $rel = $f.FullName.Substring($path.Length)
            $h = ''
            try { $h = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash } catch { $h = 'UNREADABLE' }
            $null = $sb.Append($rel).Append('|').Append($f.Length).Append('|').Append($h).Append("`n")
        }
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($sb.ToString())
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $r.Hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '')
        $sha.Dispose()
    } else {
        $r.Kind = 'file'
        $r.Count = 1
        try { $r.Hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash }
        catch { $r.Readable = $false }
    }
    return $r
}

# EVERY LINE IN HERE IS Write-Host, NOT Write-Output, AND THAT IS LOAD-BEARING.
# A PowerShell function returns everything on the output stream, so a single
# Write-Output beside the return makes the caller's map an ARRAY of
# [string, string, ..., hashtable].  Measured on the 21:14:34 run: the state
# file came back with Preserve holding Count/Length/LongLength/Rank/SyncRoot -
# System.Array's own members - and not one of the per-name rows printed.  It is
# the trap Invoke-SD's comment above describes and verify-notyet.ps1 records as
# "how a refusal came to exit 0 once already".
function Snapshot-Names([string[]]$names) {
    $out = @{}
    foreach ($n in $names) {
        $fp = Get-Fingerprint (Join-Path $sdsys $n)
        $out[$n] = $fp
        Write-Host ("    {0,-16} {1,-7} {2,4} item(s)  {3}  created {4}" -f
            $n, $fp.Kind, $fp.Count,
            $(if ($fp.Hash) { $fp.Hash.Substring(0, 16) } else { '-' }),
            $(if ($fp.Created) { ([datetime]$fp.Created).ToString('dd MMM HH:mm:ss') } else { '-' }))
    }
    return $out
}

# AND THE CLASS-LEVEL GUARD, because renaming one call fixes one function.
# A snapshot whose shape is wrong is worse than no snapshot: -Compare would run
# against it and report on names it never actually recorded.  So the shape is
# asserted before anything is written, and the run refuses if it is wrong.
# Write-Host, NOT Write-Output - AND THE FIRST VERSION OF THIS GUARD GOT IT
# WRONG, which is worth recording because it was the fix FOR that same trap.
# Its Write-Output lines were consumed by the `if (-not (Assert-Map ...))` that
# called it, so nothing printed and the return became [string, bool] - an array,
# which `-not` reads as false, so the guard passed by accident on 21:16:59.
# A guard that cannot report is not a guard.
function Assert-Map($map, [string]$label, [int]$wanted) {
    if ($map -isnot [hashtable]) {
        Write-Host ("  REFUSING - " + $label + " came back as " +
            $map.GetType().Name + ", not a hashtable.  Something wrote to the")
        Write-Host '  output stream inside Snapshot-Names; see its comment.'
        return $false
    }
    if ($map.Count -ne $wanted) {
        Write-Host ("  REFUSING - " + $label + " holds " + $map.Count +
                    " names, expected " + $wanted)
        return $false
    }
    Write-Host ("  " + $label + ": " + $map.Count + " names recorded, shape OK")
    return $true
}

# ===========================================================================
if ($Snapshot) {
# ===========================================================================

    Write-Output ''
    Write-Output '=== [S1] Fingerprinting the tree before the upgrade =============='
    Write-Output '  PRESERVE - these must come back byte-identical:'
    $sPreserve = Snapshot-Names $PRESERVE
    Write-Output '  REPLACE - these are deleted and copied back:'
    $sReplace  = Snapshot-Names $REPLACE
    Write-Output '  UNNAMED - protected only by not being on any list:'
    $sUnnamed  = Snapshot-Names $UNNAMED

    Write-Output ''
    Write-Output '  --- shape of what was recorded, checked before anything is written ---'
    $shapeOk = $true
    if (-not (Assert-Map $sPreserve 'Preserve' $PRESERVE.Count)) { $shapeOk = $false }
    if (-not (Assert-Map $sReplace  'Replace'  $REPLACE.Count))  { $shapeOk = $false }
    if (-not (Assert-Map $sUnnamed  'Unnamed'  $UNNAMED.Count))  { $shapeOk = $false }
    if (-not $shapeOk) {
        Write-Output ''
        Write-Output 'verify-upgrade: CANNOT CONTINUE - the snapshot would be unusable.'
        Write-Output '  Nothing was written and no probe was planted.'
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }

    Write-Output ''
    Write-Output '=== [S2] Planting the probe pair ================================='
    # bp and gcat must both be there, or the probes cannot be planted and the
    # whole instrument is absent.  Refuse rather than carry on.
    foreach ($d in @('bp', 'gcat')) {
        if (-not (Test-Path -LiteralPath (Join-Path $sdsys $d))) {
            Write-Output ("  CANNOT RUN - " + (Join-Path $sdsys $d) + " is not there,")
            Write-Output '  so the probe pair cannot be planted and nothing below would be decisive.'
            try { Stop-Transcript | Out-Null } catch { }
            exit 2
        }
    }
    Set-Content -LiteralPath $probeKeep -Value $PROBE_TEXT -Encoding ASCII
    Set-Content -LiteralPath $probeGone -Value $PROBE_TEXT -Encoding ASCII
    Write-Output ("  planted (must SURVIVE): " + $probeKeep)
    Write-Output ("  planted (must be GONE): " + $probeGone)
    Write-Output ("  both readable back: " +
        ((Test-Path -LiteralPath $probeKeep) -and (Test-Path -LiteralPath $probeGone)))

    Write-Output ''
    Write-Output '=== [S3] Forcing the retired name ==============================='
    # See the header.  A first install never creates sdsys\changelog, so
    # without this the retired-name delete would be measured against a file
    # that was already absent.
    $sdsysChangelog = Join-Path $sdsys 'changelog'
    $hadIt = Test-Path -LiteralPath $sdsysChangelog
    if ($hadIt) {
        Write-Output ("  sdsys\changelog already present - left as it is: " + $sdsysChangelog)
    } else {
        Set-Content -LiteralPath $sdsysChangelog -Value `
            'verify-upgrade.ps1 planted this to reach the SDSYS_RETIRED branch.' -Encoding ASCII
        Write-Output ("  CREATED " + $sdsysChangelog + " to reach the retired-name branch")
    }
    $appChangelog = Join-Path $appDir 'changelog'
    Write-Output ("  {app}\changelog present before: " + (Test-Path -LiteralPath $appChangelog))

    $sdExeHash = ''
    if (Test-Path -LiteralPath $sdExe) {
        $sdExeHash = (Get-FileHash -LiteralPath $sdExe -Algorithm SHA256).Hash
    }
    Write-Output ("  sd.exe before: " + $(if ($sdExeHash) { $sdExeHash.Substring(0, 16) } else { 'ABSENT' }))

    $state = [pscustomobject]@{
        TakenAt        = (Get-Date).ToString('o')
        Sdsys          = $sdsys
        AppDir         = $appDir
        SdExeHash      = $sdExeHash
        InstalledAt    = (Get-Item -LiteralPath $dataDir).CreationTimeUtc.ToString('o')
        Preserve       = $sPreserve
        Replace        = $sReplace
        Unnamed        = $sUnnamed
        PlantedChangelog = (-not $hadIt)
        AppChangelog   = (Test-Path -LiteralPath $appChangelog)
    }
    $stateDir = Split-Path -Parent $StatePath
    if (-not (Test-Path -LiteralPath $stateDir)) {
        $null = New-Item -ItemType Directory -Path $stateDir -Force
    }
    $state | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $StatePath -Encoding UTF8
    # SAY WHAT LANDED, NOT WHAT WAS INTENDED.  A write that was redirected
    # elsewhere still "succeeds" from in here; the length read back is the
    # cheapest evidence that something is actually at that path.
    if (Test-Path -LiteralPath $StatePath) {
        Write-Output ("  read back: " + (Get-Item -LiteralPath $StatePath).Length + " bytes")
    } else {
        Write-Output '  WROTE IT AND IT IS NOT THERE - the path is being redirected.'
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }

    Write-Output ''
    Write-Output ("=== snapshot written to " + $StatePath)
    Write-Output ''
    Write-Output 'NEXT: install OVER this installation - do NOT uninstall, do NOT run'
    Write-Output '  cycle.ps1, which deletes both trees.  Run the installer directly:'
    Write-Output ''
    Write-Output '    C:\Users\dmont\sdout\sd-setup-W1.0-0.exe'
    Write-Output ''
    Write-Output 'THEN:'
    Write-Output ''
    Write-Output '    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-upgrade.ps1 -Compare'
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

# ===========================================================================
# -Compare
# ===========================================================================

if (-not (Test-Path -LiteralPath $StatePath)) {
    Write-Output ''
    Write-Output ("verify-upgrade: CANNOT RUN - no snapshot at " + $StatePath)
    Write-Output '  Run -Snapshot BEFORE the upgrade.  There is nothing to compare against.'
    # AND SAY WHAT IS ACTUALLY THERE.  "Not found" on its own sent a reader
    # hunting for a file that existed the whole time, in a redirected copy of
    # the directory - see the note on $StatePath.  Listing the directory turns
    # that into one glance.
    $stateDir = Split-Path -Parent $StatePath
    Write-Output ''
    Write-Output ("  contents of " + $stateDir + ":")
    if (Test-Path -LiteralPath $stateDir) {
        $found = @(Get-ChildItem -LiteralPath $stateDir -ErrorAction SilentlyContinue)
        if ($found.Count -eq 0) {
            Write-Output '    (empty)'
        } else {
            foreach ($f in $found) { Write-Output ('    ' + $f.Name + '  ' + $f.Length + ' bytes') }
        }
    } else {
        Write-Output '    the directory does not exist either'
    }
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
$state = Get-Content -LiteralPath $StatePath -Raw | ConvertFrom-Json
Write-Output ("  snapshot taken at " + $state.TakenAt)

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

function Skip($check, $why) {
    $null = $script:results.Add([pscustomobject]@{
        Check = $check; Expected = '(not measurable here)'; Observed = $why
        Result = 'SKIP'
    })
    Write-Output ("  [SKIP] {0}: {1}" -f $check, $why)
}

Write-Output ''
Write-Output '=== [1] THE PROBE PAIR - did the upgrade actually run? ==========='
# Read the header.  Neither probe alone proves anything; only the disagreement
# is consistent with an upgrade that did what it says.
$keepThere = Test-Path -LiteralPath $probeKeep
$goneThere = Test-Path -LiteralPath $probeGone
Write-Output ("  " + $probeKeep + " : " + $(if ($keepThere) { 'present' } else { 'GONE' }))
Write-Output ("  " + $probeGone + " : " + $(if ($goneThere) { 'PRESENT' } else { 'gone' }))

Note 'probe in a PRESERVED directory survived' $true  $keepThere
Note 'probe in a REPLACED directory was removed' $false $goneThere

if ($keepThere -and $goneThere) {
    Write-Output ''
    Write-Output '  *** BOTH PROBES SURVIVED.  The installer did not run, or did not'
    Write-Output '  *** take the upgrade path.  EVERY PRESERVATION CHECK BELOW WOULD'
    Write-Output '  *** PASS TRIVIALLY - do not read any of them as evidence.'
}

Write-Output ''
Write-Output '=== [2] PRESERVED names must be byte-identical ==================='
foreach ($n in $PRESERVE) {
    $before = $state.Preserve.$n
    $after  = Get-Fingerprint (Join-Path $sdsys $n)
    if (-not $before.Readable -or -not $after.Readable) {
        Skip ("preserved: " + $n) 'not readable even elevated, so no comparison was made'
        continue
    }
    Note ("preserved unchanged: " + $n) $before.Hash $after.Hash
}

Write-Output ''
Write-Output '=== [3] REPLACED names must all still be present ================='
# Content is NOT compared: an upgrade from the same source copies back
# identical bytes, so a difference is not expected and its absence proves
# nothing.  What matters is that nothing was deleted and left uncopied - the
# hollow pair stage.py refuses to emit.
foreach ($n in $REPLACE) {
    $after = Get-Fingerprint (Join-Path $sdsys $n)
    Note ("replaced present: " + $n) $true $after.Exists
    if ($after.Exists -and $after.Kind -eq 'dir') {
        Note ("replaced not empty: " + $n) $true ($after.Count -gt 0)
    }
}

Write-Output ''
Write-Output '=== [4] UNNAMED names are protected by not being on a list ======='
foreach ($n in $UNNAMED) {
    $before = $state.Unnamed.$n
    $after  = Get-Fingerprint (Join-Path $sdsys $n)
    if (-not $before.Exists) {
        Skip ("unnamed: " + $n) 'was not there before the upgrade either'
        continue
    }
    Note ("unnamed survived: " + $n) $true $after.Exists
}

Write-Output ''
Write-Output '=== [5] The retired name ========================================='
$sdsysChangelog = Join-Path $sdsys 'changelog'
$appChangelog   = Join-Path $appDir 'changelog'
Write-Output ("  sdsys\changelog : " + $(if (Test-Path -LiteralPath $sdsysChangelog) { 'PRESENT' } else { 'gone' }))
Write-Output ("  {app}\changelog : " + $(if (Test-Path -LiteralPath $appChangelog) { 'present' } else { 'GONE' }))
Note 'sdsys\changelog was removed' $false (Test-Path -LiteralPath $sdsysChangelog)
Note '{app}\changelog is present'  $true  (Test-Path -LiteralPath $appChangelog)

Write-Output ''
Write-Output '=== [6] What was upgraded to what ================================'
# assert-current is not called here (see the header), so the transcript has to
# say for itself which binary was there before and which is there now.
$after = ''
if (Test-Path -LiteralPath $sdExe) { $after = (Get-FileHash -LiteralPath $sdExe -Algorithm SHA256).Hash }
Write-Output ("  sd.exe before : " + $(if ($state.SdExeHash) { $state.SdExeHash } else { 'ABSENT' }))
Write-Output ("  sd.exe after  : " + $(if ($after) { $after } else { 'ABSENT' }))
Note 'sd.exe is present after the upgrade' $true ($after -ne '')
if ($after -eq $state.SdExeHash) {
    Write-Output '  the binary did not move - the upgrade was from the SAME build.'
    Write-Output '  That is a valid upgrade test of the DATA tree; it is not a test'
    Write-Output '  that a NEW binary lands.'
}

Write-Output ''
Write-Output '=== summary ========================================================='
$results | Format-Table -AutoSize | Out-String | Write-Output
$passCount = @($results | Where-Object { $_.Result -eq 'PASS' }).Count
$skipCount = @($results | Where-Object { $_.Result -eq 'SKIP' }).Count
$failCount = @($results | Where-Object { $_.Result -eq 'FAIL' }).Count
Write-Output ("{0} passed, {1} failed, {2} skipped, of {3} rows" -f
    $passCount, $failCount, $skipCount, $results.Count)
Write-Output ''
if ($failed) {
    Write-Output 'verify-upgrade: FAILED - read the rows above.'
} else {
    Write-Output 'verify-upgrade: PASSED - the upgrade replaced the shipped subset in'
    Write-Output '  place, kept every preserved name byte-identical, left the unlisted'
    Write-Output '  names alone, and removed the retired one.'
    if ($skipCount -gt 0) {
        Write-Output ''
        Write-Output ("  BUT {0} CHECK(S) COULD NOT BE MADE and are NOT covered by that" -f $skipCount)
        Write-Output '  sentence.  They are listed as SKIP above, with the reason.'
    }
}

# The surviving probe is this script's litter and it goes.  The other one was
# removed by the upgrade, which was the point of it.
if (Test-Path -LiteralPath $probeKeep) {
    Remove-Item -LiteralPath $probeKeep -Force -ErrorAction SilentlyContinue
    Write-Output ''
    Write-Output ("  cleanup: removed " + $probeKeep)
}

try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 } else { exit 0 }
