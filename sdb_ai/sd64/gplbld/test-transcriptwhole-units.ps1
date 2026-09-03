# test-transcriptwhole-units.ps1 - drives transcript-whole.ps1 (PRE_RELEASE 137).
#
# Free: no install, no elevation, no run token.  Everything is a fixture built
# under $env:TEMP and deleted afterwards, except two OPTIONAL live checks
# against real cycle logs, which are reported as SKIPPED rather than passed when
# the logs are not on this machine.
#
# NO Set-StrictMode AT FILE SCOPE HERE EITHER, and that is itself under test:
# case 16 proves dot-sourcing transcript-whole.ps1 does not switch strict mode
# on in its caller.  A strict-mode leak turns every later script that
# dot-sources it into a different language, and it is invisible until something
# reads an unset variable.

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'transcript-whole.ps1')

$script:pass = 0
$script:fail = 0
$script:skip = 0
$script:ran  = 0

function Check {
    param([string] $Name, $Expected, $Actual)
    $script:ran++
    if ($Expected -ceq $Actual) {          # -ceq: PowerShell's -eq ignores case
        $script:pass++
        Write-Host ("  [PASS] {0}" -f $Name)
    } else {
        $script:fail++
        Write-Host ("  [FAIL] {0}`n         expected <{1}>`n         actual   <{2}>" -f $Name, $Expected, $Actual) -ForegroundColor Red
    }
}

# --------------------------------------------------------------------------
# Fixture builders
# --------------------------------------------------------------------------
$root = Join-Path $env:TEMP ('twhole-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $root -Force

function New-Stage {
    param([int] $PayloadFiles, [switch] $NoNonPayload)
    $s = Join-Path $root ('stage-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    $null = New-Item -ItemType Directory -Path (Join-Path $s 'ProgramData') -Force
    for ($i = 1; $i -le $PayloadFiles; $i++) {
        Set-Content -LiteralPath (Join-Path $s ('ProgramData\f{0}' -f $i)) -Value 'x' -Encoding Ascii
    }
    if (-not $NoNonPayload) {
        Set-Content -LiteralPath (Join-Path $s 'MANIFEST.txt') -Value 'm' -Encoding Ascii
        Set-Content -LiteralPath (Join-Path $s 'upgrade.iss')  -Value 'u' -Encoding Ascii
    }
    return $s
}

function New-Transcript {
    param([string[]] $Lines)
    $f = Join-Path $root ('log-' + [guid]::NewGuid().ToString('N').Substring(0, 6) + '.log')
    Set-Content -LiteralPath $f -Value $Lines -Encoding Ascii
    return $f
}

$banner = @(
    'Inno Setup 6 Command-Line Compiler',
    'Copyright (C) 1997-2026 Jordan Russell. All rights reserved.',
    '',
    'Compiler engine version: Inno Setup 6.7.3'
)
function Compressing { param([int] $N, [int] $From = 1)
    $out = @()
    for ($i = $From; $i -lt ($From + $N); $i++) { $out += ('Compressing: C:\stage\ProgramData\f{0}' -f $i) }
    return $out
}

Write-Host ''
Write-Host 'test-transcriptwhole-units - transcript-whole.ps1 (PRE_RELEASE 137)'
Write-Host ("  fixtures under {0}" -f $root)
Write-Host ''

try {
    # ---------------------------------------------------------------- 1 WHOLE
    $s = New-Stage -PayloadFiles 10
    $t = New-Transcript ($banner + (Compressing 10))
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'WHOLE: banner + exactly the payload count'            'WHOLE' $r.Verdict
    Check 'WHOLE: staged counts the non-payload files too'       12      $r.StagedFiles
    Check 'WHOLE: expected excludes the two by name'             10      $r.Expected
    Check 'WHOLE: both front markers seen'                       2       $r.FrontMarkers

    # ------------------------------------------------- 2 TRUNCATED AT FRONT
    $t = New-Transcript (Compressing 4 -From 7)
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'TRUNCATED: no banner but Compressing lines present'   'TRUNCATED AT FRONT' $r.Verdict
    Check 'TRUNCATED: names where the log opens'                 'C:\stage\ProgramData\f7' $r.FirstCompressed

    # -------------------------------------------------- 3 NO NATIVE OUTPUT
    $t = New-Transcript @('== [4] Building the installer', 'some PowerShell line')
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'NO NATIVE OUTPUT: no banner and no Compressing'       'NO NATIVE OUTPUT' $r.Verdict

    # -------------------------------------------------------------- 4 SHORT
    $t = New-Transcript ($banner + (Compressing 6))
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'SHORT: banner present, lines missing'                 'SHORT' $r.Verdict

    # -------------------------------------------------- 5 MORE THAN ONE RUN
    $t = New-Transcript ($banner + (Compressing 10) + $banner + (Compressing 10))
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'MORE THAN ONE RUN: two cycles in one log'             'MORE THAN ONE RUN' $r.Verdict

    # ------------------------------------------- 6-9 NULL CASES, REFUSED LOUD
    $r = Get-TranscriptWholeness -TranscriptPath (Join-Path $root 'nope.log') -StagePath $s
    Check 'NULL: missing transcript is NO VERDICT'               'NO VERDICT' $r.Verdict
    Check 'NULL: missing transcript is not marked readable'      $false       $r.Readable

    $t = New-Transcript @()
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'NULL: empty transcript is NO VERDICT'                 'NO VERDICT' $r.Verdict

    $t = New-Transcript ($banner + (Compressing 10))
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath (Join-Path $root 'no-such-stage')
    Check 'NULL: missing stage is NO VERDICT'                    'NO VERDICT' $r.Verdict

    $emptyStage = Join-Path $root 'empty-stage'
    $null = New-Item -ItemType Directory -Path $emptyStage -Force
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $emptyStage
    Check 'NULL: stage with no files is NO VERDICT, not WHOLE'   'NO VERDICT' $r.Verdict

    # ------------------------------- 10 EXCLUDED BY NAME, NOT BY SUBTRACTING 2
    $sBare = New-Stage -PayloadFiles 5 -NoNonPayload
    $t     = New-Transcript ($banner + (Compressing 5))
    $r     = Get-TranscriptWholeness -TranscriptPath $t -StagePath $sBare
    Check 'BY NAME: nothing to exclude, expected == staged'      5       $r.Expected
    Check 'BY NAME: excluded list is empty'                      0       $r.Excluded.Count
    Check 'BY NAME: still WHOLE'                                 'WHOLE' $r.Verdict

    # ------------------------------------------- 11 THE VERSION IS WILDCARDED
    $t = New-Transcript (@('Inno Setup 7 Command-Line Compiler') + (Compressing 10))
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'WILDCARD: Inno Setup 7 still counts as a front marker' 'WHOLE' $r.Verdict

    # --------- 12 THE ANCHOR MUST NOT MATCH A STRING THE FAILURE ALSO CARRIES
    # cycle.ps1 prints ISCC's PATH, which contains "Inno Setup 6".  If that
    # counted as a front marker every truncated log would report WHOLE.
    $t = New-Transcript (@('   ISCC: C:\Program Files (x86)\Inno Setup 6\ISCC.exe') + (Compressing 4 -From 7))
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'ANCHOR: the ISCC path is not a front marker'          'TRUNCATED AT FRONT' $r.Verdict
    Check 'ANCHOR: zero front markers from the path alone'       0 $r.FrontMarkers

    # ------------------------------- 13 "Compressing:" WITH NOTHING AFTER IT
    $t = New-Transcript ($banner + @('Compressing:', '  Compressing:   ') + (Compressing 10))
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'ARGLESS: a bare Compressing: is not a file'           10      $r.Compressing
    Check 'ARGLESS: verdict unaffected'                          'WHOLE' $r.Verdict

    # -------------------------------- 14 LEADING WHITESPACE IS TOLERATED
    $t = New-Transcript ($banner + @('    Compressing: C:\stage\ProgramData\f1') + (Compressing 9 -From 2))
    $r = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    Check 'INDENT: an indented Compressing line counts'          10      $r.Compressing

    # ------------------------------------- 15 THE PRINTER RETURNS WHOLE ONLY
    $t  = New-Transcript ($banner + (Compressing 10))
    $r  = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    $okWhole = Write-TranscriptWholeness -Result $r -Indent '      | ' 6>$null
    Check 'PRINTER: returns $true for WHOLE'                     $true  $okWhole
    $t  = New-Transcript (Compressing 4)
    $r  = Get-TranscriptWholeness -TranscriptPath $t -StagePath $s
    $okTrunc = Write-TranscriptWholeness -Result $r -Indent '      | ' 6>$null
    Check 'PRINTER: returns $false for TRUNCATED AT FRONT'       $false $okTrunc

    # -------------------------------------- 16 NO STRICT-MODE LEAK TO CALLER
    # This file sets no strict mode.  If transcript-whole.ps1 set it at file
    # scope, dot-sourcing it above would have bound THIS scope and the line
    # below would throw instead of yielding $null.
    $leaked = $false
    try { $null = $ThisVariableWasNeverSet } catch { $leaked = $true }
    Check 'NO LEAK: dot-sourcing did not turn on strict mode'    $false $leaked

    # ---------------------------------------------------------------------
    # OPTIONAL LIVE CHECKS.  Real logs, real verdict classes.  Counted as
    # SKIPPED when absent - a check that did not run must never read as a pass.
    # ---------------------------------------------------------------------
    Write-Host ''
    $liveDir   = Join-Path $env:LOCALAPPDATA 'SD-verify'
    $liveStage = 'C:\Users\dmont\stagetest'
    $live = @(
        @{ Log = 'cycle-20260902-194027.log'; Want = 'banner';    Note = 'the COMPLETE log of 2 Sep 19:40' },
        @{ Log = 'cycle-20260902-174446.log'; Want = 'no-banner'; Note = 'the TRUNCATED log of 2 Sep 17:44' }
    )
    foreach ($L in $live) {
        $p = Join-Path $liveDir $L.Log
        if (-not (Test-Path -LiteralPath $p) -or -not (Test-Path -LiteralPath $liveStage)) {
            $script:skip++
            Write-Host ("  [SKIP] live: {0} - not on this machine" -f $L.Log) -ForegroundColor DarkGray
            continue
        }
        $r = Get-TranscriptWholeness -TranscriptPath $p -StagePath $liveStage
        # Only the FRONT-MARKER class is asserted.  The exact count depends on
        # which build staged the tree, and the tree moves on.
        if ($L.Want -eq 'banner') {
            Check ("LIVE: {0} kept its banner" -f $L.Note) $true ($r.FrontMarkers -gt 0)
            Check ("LIVE: {0} is therefore not TRUNCATED AT FRONT" -f $L.Note) $false ($r.Verdict -ceq 'TRUNCATED AT FRONT')
        } else {
            Check ("LIVE: {0} lost its banner" -f $L.Note) 0 $r.FrontMarkers
            Check ("LIVE: {0} reads TRUNCATED AT FRONT" -f $L.Note) 'TRUNCATED AT FRONT' $r.Verdict
        }
        Write-Host ("         {0} Compressing lines, {1:N0} bytes, verdict {2}" -f $r.Compressing, $r.TranscriptBytes, $r.Verdict)
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host ("  ran {0}, passed {1}, failed {2}, skipped {3}" -f $script:ran, $script:pass, $script:fail, $script:skip)

# REFUSE THE NULL CASE.  A run that asserted nothing must not exit 0 - that is
# the "suite row called the one failing check on a suite that never ran a step"
# failure this project has already paid for.
$minimum = 25
if ($script:ran -lt $minimum) {
    Write-Host ("  REFUSED: only {0} checks ran, expected at least {1} - this did not test anything" -f $script:ran, $minimum) -ForegroundColor Red
    exit 2
}
if ($script:fail -gt 0) { exit 1 }
Write-Host '  transcript-whole.ps1 is sound.'
exit 0
