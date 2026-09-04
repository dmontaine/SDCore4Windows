# verify-editors.ps1 - are the full-screen editors BUNDLED, and does the EDIT
# verb resolve the bundled copy rather than whatever winget left on PATH?
#
#   VerifyInstall1.ps1 -Run <token>           the supported way to run it
#   VerifyInstall1.ps1 -Only verify-editors   just this step
#
# Exit 0 all decisive checks passed, 1 a check failed, 2 refused/VOID.
# UNELEVATED, no account, no prefix, no run token - everything here is a read.
# It is indifferent to the token, so it makes no claim on being early in the
# runner and does not dilute verify-credacl's claim to be first.
#
# ===========================================================================
# WHY THIS EXISTS
# ===========================================================================
#
# PRE_RELEASE_FIXES 66.  micro and Microsoft Edit used to be DOWNLOADED by
# install-editors.ps1 while SD installed - unpinned, so a user installing next
# year got whatever winget had that day and a key-binding table that may not
# describe it.  They are now staged from the out-of-git SD-Untracked tree into
# {app}\usr\bin beside sd.exe, SHA-256-pinned, and gpl.bp/EDIT's find.editor
# resolves that fixed path BEFORE falling back to a PATH lookup.
#
# ***IT FAILS THE QUIET WAY, WHICH IS WHY IT IS WORTH A STEP.***  If the
# bundling regressed - a staging list edited, a path literal changed - nothing
# would break.  find.editor's fallback would find the winget copy and every
# verb would go on working, against an editor of unknown version.  The whole
# defect 66 was filed for would be back with no symptom at all.  That is the
# same shape as the stem-coverage hole two steps above this one.
#
# WHAT IT DOES NOT COVER, SAID OUT LOUD.  Nobody can launch a full-screen
# editor from a non-interactive step, so this measures everything the launch
# depends on and never the launch.  Resolving is not running.
#
# THE LISTS ARE READ, NOT RETYPED.  The SHA-256 pins come out of stage.py's
# BUNDLED_EDITORS and the destination out of gpl.bp/EDIT's own literal.
# Copying either here would make this a second place to keep them in step,
# which is the defect rather than the fix.
#
# EVERY SECTION CARRIES A CONTROL, because three of these checks could pass by
# accident: a probe that always answers the bundled path (section 2's control
# points it at a name that is not there and requires the fallback to fire), a
# log predicate that matches anything (section 3's control runs it over a
# synthetic FAILING log and requires a red), and a Test-Path that answers true
# for everything (section 1's control asks for an editor that does not exist).
#
# NOT SHIPPED - must be on assert-current.ps1's $neverShipped list, added in
# the same commit that creates this file (section 7 step 7's rule).

$ErrorActionPreference = 'Stop'

$pass = 0
$fail = 0
function Row($ok, $text) {
    if ($ok) { $script:pass++; Write-Output "[PASS] $text" }
    else     { $script:fail++; Write-Output "[FAIL] $text" }
}

Write-Output 'verify-editors: are the full-screen editors bundled, and does EDIT find them?'

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-editors: refusing - see above'
    exit 2
}

$App    = Join-Path $env:ProgramFiles 'SD'
$UsrBin = Join-Path $App 'usr\bin'
$Log    = Join-Path $env:ProgramData 'SD\install-editors.log'
$Stage  = Join-Path $PSScriptRoot 'stage.py'
$Edit   = Join-Path $PSScriptRoot '..\sdsys\gpl.bp\EDIT'
$psh    = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

Write-Output ''
Write-Output ("  app     : " + $App)
Write-Output ("  usr\bin : " + $UsrBin)
Write-Output ("  log     : " + $Log)
Write-Output ("  pins    : " + $Stage)
Write-Output ("  verb    : " + $Edit)

foreach ($p in @($UsrBin, $Stage, $Edit, $psh)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("verify-editors: refusing - not found: " + $p)
        exit 2
    }
}

$sd = Join-Path $UsrBin 'sd.exe'
if (Test-Path -LiteralPath $sd) {
    $i = Get-Item -LiteralPath $sd
    Write-Output ("  sd.exe  : {0} bytes, written {1}" -f $i.Length, $i.LastWriteTime)
}

# ---------------------------------------------------------------------------
# THE PINS, READ OUT OF stage.py.  A shape change there must stop this run
# rather than quietly measure nothing - an empty pin list would make section 1
# pass by having nothing to check, which is the null case the instrument rules
# refuse.
# ---------------------------------------------------------------------------
$src = Get-Content -LiteralPath $Stage -Raw
$m   = [regex]::Match($src, '(?ms)^BUNDLED_EDITORS\s*=\s*\[(.*?)\]')
if (-not $m.Success) {
    Write-Output 'verify-editors: refusing - could not read BUNDLED_EDITORS out of stage.py; its shape changed.'
    exit 2
}
$pins = @{}
foreach ($e in [regex]::Matches($m.Groups[1].Value, "\(\s*'([^']+)'\s*,\s*'([0-9a-fA-F]{64})'\s*\)")) {
    $pins[$e.Groups[1].Value] = $e.Groups[2].Value.ToLower()
}
if ($pins.Count -eq 0) {
    Write-Output 'verify-editors: refusing - BUNDLED_EDITORS parsed to nothing, so there is nothing to check.'
    exit 2
}
Write-Output ''
Write-Output ("  BUNDLED_EDITORS holds {0}: {1}" -f $pins.Count, (($pins.Keys | Sort-Object) -join ', '))

# ---------------------------------------------------------------------------
# 1. THE FILES LAND, AND THEY ARE THE PINNED BYTES
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 1. the editors are in {app}\usr\bin, and are the pinned copies ---'
foreach ($exe in ($pins.Keys | Sort-Object)) {
    $dst = Join-Path $UsrBin $exe
    if (Test-Path -LiteralPath $dst) {
        $it = Get-Item -LiteralPath $dst
        $h  = (Get-FileHash -LiteralPath $dst -Algorithm SHA256).Hash.ToLower()
        Write-Output ("      {0}: {1} bytes, written {2}" -f $exe, $it.Length, $it.LastWriteTime)
        Write-Output ("      sha256 {0}" -f $h)
        Row $true "$exe is in usr\bin"
        # -ceq: PowerShell compares case-insensitively by default, and a hash
        # that differs only in case would be accepted and called verified.
        Row ($h -ceq $pins[$exe]) "$exe matches stage.py's pin"
    } else {
        Write-Output ("      {0}: ABSENT" -f $exe)
        Row $false "$exe is in usr\bin"
        Row $false "$exe matches stage.py's pin"
    }
}
# CONTROL: Test-Path must not answer true for an editor that is not there.
Row (-not (Test-Path -LiteralPath (Join-Path $UsrBin 'nosucheditor.exe'))) `
    'control: usr\bin does NOT hold nosucheditor.exe'

# ---------------------------------------------------------------------------
# 2. THE PROBE gpl.bp/EDIT BUILDS
#
# The verb's find.editor concatenates the string below and hands it to
# OS.EXECUTE, which runs powershell.exe -NoProfile -NonInteractive -Command with
# the WHOLE command as one argv element (op_sh.c:346, :357).  The same shell and
# the same switches are used here, so this measures the shipped mechanism rather
# than a paraphrase of it.
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 2. find.editor resolves the bundled copy, not a PATH lookup ---'

# The destination literal is EDIT's, read from EDIT.
$editSrc = Get-Content -LiteralPath $Edit -Raw
$mBun    = [regex]::Match($editSrc, "bundled\s*=\s*'([^']+)'\s*:\s*editor\.exe")
if (-not $mBun.Success) {
    Write-Output 'verify-editors: refusing - could not read find.editor''s bundled path out of gpl.bp/EDIT.'
    Write-Output '  Either the verb no longer prefers the bundled copy - which is the defect 66'
    Write-Output '  was filed for - or find.editor was rewritten and this check needs rewriting.'
    exit 2
}
$prefix = $mBun.Groups[1].Value
Write-Output ("      EDIT's literal : '{0}'" -f $prefix)
Write-Output ("      shell          : {0} -NoProfile -NonInteractive -Command" -f $psh)
# The literal and the install must be the same directory.  Compared as paths,
# not as strings: EDIT writes forward slashes on purpose.
Row (($prefix.TrimEnd('/') -replace '/', '\') -ieq $UsrBin) `
    "EDIT's literal names the installed usr\bin"

function New-Probe($dir, $exe) {
    $b = $dir + $exe
    $p  = "`$b = '" + $b + "'; "
    $p += 'if (Test-Path -LiteralPath $b) { $b } else { '
    $p += '$c = Get-Command -Name ' + $exe
    $p += ' -CommandType Application -ErrorAction SilentlyContinue; '
    $p += 'if ($c) { $c[0].Source } }'
    return $p
}

foreach ($exe in ($pins.Keys | Sort-Object)) {
    $probe = New-Probe $prefix $exe
    Write-Output ("      probe : {0}" -f $probe)
    $res = (& $psh -NoProfile -NonInteractive -Command $probe 2>&1 | Out-String).Trim()
    Write-Output ("      answer: '{0}'" -f $res)
    Row ($res -ne '') "$exe probe answered something (null case refused)"
    Row ($res -ceq ($prefix + $exe)) "$exe probe resolves to the bundled copy"

    # CONTROL: the same probe pointed at a directory that holds nothing must
    # NOT answer the bundled path.  Without this, a probe that returned its own
    # first literal whatever happened would score a pass above.
    $ctlDir = 'C:/SD-no-such-directory-verify-editors/'
    $ctl    = (& $psh -NoProfile -NonInteractive -Command (New-Probe $ctlDir $exe) 2>&1 | Out-String).Trim()
    Write-Output ("      control answer: '{0}'" -f $ctl)
    Row ($ctl -cne ($ctlDir + $exe)) "control: $exe probe does not invent a path that is not there"
}

# ---------------------------------------------------------------------------
# 3. WHAT install-editors.ps1 HAS EVER RECORDED ON THIS MACHINE
#
# READ BEFORE SECTION 3b RUNS, and the two checks below are deliberately
# append-proof: 3b's -CheckOnly appends a run of its own, a kept-database
# upgrade preserves older runs, so anything anchored on "the last run" would
# describe this script rather than the installer the second time it is used.
#   A - no run ANYWHERE has ever downloaded.
#   B - every "already present" line ANYWHERE names the bundled path.
# Both hold whoever wrote the line, which is what makes them safe to re-run.
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 3. install-editors has never downloaded, and always names the bundled path ---'
if (-not (Test-Path -LiteralPath $Log)) {
    Write-Output ("      ABSENT: " + $Log)
    Row $false 'install-editors wrote a log'
} else {
    $lines = @(Get-Content -LiteralPath $Log)
    $runs  = @($lines | Select-String -SimpleMatch 'editors wanted:').Count
    Write-Output ("      {0}: {1} line(s), {2} run(s) recorded" -f $Log, $lines.Count, $runs)
    $lines | ForEach-Object { Write-Output ("      " + $_) }
    Row ($lines.Count -gt 0 -and $runs -gt 0) 'the log holds at least one complete run (null case refused)'
}

# The two predicates, as functions, so the synthetic control below drives the
# SAME code rather than a copy of it.
function Test-NoDownload($text) {
    return -not ($text -match 'running winget|winget install|Downloading')
}
function Test-AllBundled($text, $bin) {
    $seen = [regex]::Matches($text, '(?m)already present - (.+?)\s\sversion')
    if ($seen.Count -eq 0) { return $false }   # nothing found is not a pass
    foreach ($s in $seen) {
        if (-not ($s.Groups[1].Value.StartsWith($bin, 'OrdinalIgnoreCase'))) { return $false }
    }
    return $true
}

if (Test-Path -LiteralPath $Log) {
    $text = (Get-Content -LiteralPath $Log) -join "`n"
    Row (Test-NoDownload $text)        'A: no run in the log ever downloaded an editor'
    Row (Test-AllBundled $text $UsrBin) 'B: every "already present" line names {app}\usr\bin'
    Row ($text -match 'every editor is present') 'the log carries the success line "every editor is present"'
    foreach ($bad in @('no micro.exe on this machine', 'no edit.exe on this machine',
                       'NOT AVAILABLE', 'FAILED - ')) {
        Row (-not ($text -match [regex]::Escape($bad))) ("the log does NOT carry '" + $bad + "'")
    }
}

# CONTROL: the two predicates over a synthetic FAILING log.  If they cannot go
# red they are not checks, and neither could be exercised any other way without
# breaking the install.
$badLog = @"
install-editors: editors wanted: edit -> edit.exe, micro -> micro.exe
install-editors: edit: already present - C:\WINDOWS\system32\edit.exe  version 1.2.1
install-editors: micro: no micro.exe on this machine
install-editors: micro: running winget install --id zyedidia.micro --exact
install-editors: every editor is present
"@
Row (-not (Test-NoDownload $badLog))          'control: predicate A goes RED on a log that downloaded'
Row (-not (Test-AllBundled $badLog $UsrBin))  'control: predicate B goes RED on a log naming system32'
Row (-not (Test-AllBundled 'nothing here' $UsrBin)) 'control: predicate B refuses a log with no editor line'

# ---------------------------------------------------------------------------
# 3b. A LIVE -CheckOnly RUN.  This exercises install-editors' OWN Find-Editor,
# which is a different code path from find.editor above and the one the
# installer uses.  -CheckOnly so it can never install anything.  It runs LAST
# because it appends to the log section 3 has just read.
# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '--- 3b. install-editors.ps1 -CheckOnly agrees, live ---'
$ie = Join-Path $App 'install-editors.ps1'
if (-not (Test-Path -LiteralPath $ie)) {
    Write-Output ("      ABSENT: " + $ie)
    Row $false 'install-editors.ps1 is installed at {app}'
} else {
    Write-Output ("      running: {0} -CheckOnly" -f $ie)
    $out  = & $psh -NoProfile -ExecutionPolicy Bypass -File $ie -CheckOnly 2>&1
    $code = $LASTEXITCODE
    $t2   = ($out | Out-String)
    ($t2.TrimEnd() -split "`r?`n") | ForEach-Object { Write-Output ("      " + $_) }
    Row ($t2.Trim() -ne '') 'the -CheckOnly run produced output (null case refused)'
    Row ($code -eq 0) ("the -CheckOnly run exited 0 (got " + $code + ")")
    Row (Test-AllBundled $t2 $UsrBin) 'its Find-Editor returns the bundled path for every editor'
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output ("verify-editors: {0} PASS, {1} FAIL" -f $pass, $fail)
if (($pass + $fail) -eq 0) {
    Write-Output 'verify-editors: VOID - nothing was checked.'
    exit 2
}
if ($fail -gt 0) {
    Write-Output 'VERIFY-EDITORS: FAILED'
    exit 1
}
Write-Output 'VERIFY-EDITORS: all checks passed.'
exit 0
