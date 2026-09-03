# transcript-whole.ps1 - IS THIS CYCLE LOG COMPLETE ENOUGH TO READ AFTERWARDS?
#
# PRE_RELEASE 137.  Dot-source it; it defines two functions and runs nothing.
#
# ---------------------------------------------------------------------------
# WHY THIS EXISTS
#
# PowerShell 5.1 transcribes NATIVE-command output by scraping the console
# screen buffer, and under a fast producer it drops lines.  ISCC is a fast
# producer.  Measured 2 Sep 2026 on two cycle logs an hour apart:
#
#   cycle-20260902-170323.log   3,670 Compressing lines   COMPLETE
#   cycle-20260902-174446.log   1,881 Compressing lines   ~1,789 LOST from the
#                                                         FRONT, banner and all
#
# cycle.ps1's $TranscriptDegraded flag was wrong in BOTH directions the same
# day, so it does not predict this and never could: it tests whether the window
# has run a cycle before, and the loss does not depend on that.
#
# ***THE VERDICT WAS NEVER AT RISK AND THAT IS THE POINT.***  cycle.ps1 gates on
# $LASTEXITCODE, so a failed ISCC still fails the run.  What is lost is the
# ability to read WHY - and a compile error lands in exactly the dropped region,
# the front.  What it cost on 2 Sep 2026: the staged tree held 1,974 message
# files, the log named 866 and carried no 5-digit id at all, so messages\10165 -
# the message that run existed to compile - read as "never went into the
# installer".  It took the INSTALLER SIZE to prove otherwise.  This script makes
# a short log say so itself instead.
#
# ---------------------------------------------------------------------------
# WHAT IT MEASURES, AND WHY THE EXPECTED NUMBER IS EXACT RATHER THAN A FUDGE
#
# Measured 3 Sep 2026 by diffing the 19:40 log's Compressing paths against the
# stage tree: ISCC prints ONE "Compressing:" line per [Files] entry, and the
# stage tree contains exactly TWO files that are not [Files] payload -
#
#   MANIFEST.txt   stage.py:27, "deliberately outside both of them so that
#                  packaging never picks it up"
#   upgrade.iss    sd.iss:643, "#include AddBackslash(Stage)" - a compile-time
#                  include, not a file entry
#
# - so expected = (files under <stage>) - (those two, when present).  On the
# 19:40 build that is 3,673 - 2 = 3,671, and the log holds 3,671.  EXACT, which
# is what lets a single dropped line be seen.
#
# ***THE TWO ARE EXCLUDED BY NAME, NOT BY SUBTRACTING 2.***  If one is renamed
# the count stops matching and this reports SHORT, which is correct: somebody
# should look.  A hardcoded 2 would have gone on being silently right and then
# silently wrong.
#
# ---------------------------------------------------------------------------
# THE ANCHOR IS ISCC'S OWN BANNER, NOT ANYTHING WE PASSED IT
#
# CLAUDE.md's rule: match the wording the tool prints on the POSITIVE path.
# "Inno Setup N Command-Line Compiler" and "Compiler engine version:" are
# printed by ISCC itself and cannot appear because we asked for something - and
# critically, they are the FIRST thing it prints, so their absence beside a
# non-zero Compressing count is proof the front was dropped rather than a guess.
#
# The major version is a wildcard deliberately.  Pinning "Inno Setup 6" would
# make an Inno 7 upgrade report every whole log as truncated, which is the
# failure mode where an instrument lies in the safe-looking direction.
#
# ***IT DOES NOT AND MUST NOT REPORT ON THE COMPILE.***  A FAILED compile also
# prints the banner.  This answers "was ISCC's output captured", never "did it
# succeed" - that is $LASTEXITCODE's job and conflating them would give the
# cycle two verdicts that can disagree.

function Get-TranscriptWholeness {
    <#
      .SYNOPSIS
        Compares a cycle transcript's captured ISCC output against the staged
        tree it was built from.  Reads only; returns an object, prints nothing.
    #>
    param(
        [Parameter(Mandatory = $true)][string] $TranscriptPath,
        [Parameter(Mandatory = $true)][string] $StagePath
    )
    # INSIDE the function, never at file scope: a file-scope Set-StrictMode
    # binds every caller that dot-sources this, and cycle.ps1 is not written
    # under strict mode.
    Set-StrictMode -Version Latest

    # The two stage-root files that are not [Files] payload.  See the header.
    $nonPayload = @('MANIFEST.txt', 'upgrade.iss')

    $r = [pscustomobject]@{
        TranscriptPath  = $TranscriptPath
        StagePath       = $StagePath
        Readable        = $false
        TranscriptBytes = -1
        StagedFiles     = -1
        Excluded        = @()
        Expected        = -1
        Compressing     = -1
        FirstCompressed = ''
        FrontMarkers    = -1
        Verdict         = 'NO VERDICT'
        Why             = ''
    }

    # --- null case 1: no transcript ----------------------------------------
    if (-not (Test-Path -LiteralPath $TranscriptPath)) {
        $r.Why = "the transcript does not exist at $TranscriptPath"
        return $r
    }
    try {
        $r.TranscriptBytes = (Get-Item -LiteralPath $TranscriptPath).Length
        $lines = @(Get-Content -LiteralPath $TranscriptPath -ErrorAction Stop)
    } catch {
        $r.Why = "the transcript could not be read: $($_.Exception.Message)"
        return $r
    }
    # Get-Content on an empty file yields $null, and @() around it yields an
    # empty array rather than one null element - but say so out loud either way.
    if ($lines.Count -eq 0) {
        $r.Why = 'the transcript is empty - nothing was captured at all'
        return $r
    }
    $r.Readable = $true

    # --- null case 2: no stage tree ----------------------------------------
    if (-not (Test-Path -LiteralPath $StagePath)) {
        $r.Why = "the stage tree does not exist at $StagePath, so there is nothing to expect"
        return $r
    }
    $staged = @(Get-ChildItem -LiteralPath $StagePath -Recurse -File -ErrorAction SilentlyContinue)
    $r.StagedFiles = $staged.Count
    if ($r.StagedFiles -eq 0) {
        # An os.walk that hit a permission error also returns nothing, and the
        # SHA of nothing is a confident wrong answer.  Refuse it out loud.
        $r.Why = "the stage tree at $StagePath holds no files - either it was deleted or it could not be read"
        return $r
    }

    $r.Excluded = @($nonPayload | Where-Object {
        Test-Path -LiteralPath (Join-Path $StagePath $_)
    })
    $r.Expected = $r.StagedFiles - $r.Excluded.Count
    if ($r.Expected -le 0) {
        $r.Why = "expected count came out at $($r.Expected), which cannot be right"
        return $r
    }

    # --- what the transcript actually received ------------------------------
    $comp = @($lines | Where-Object { $_ -match '^\s*Compressing:\s*\S' })
    $r.Compressing = $comp.Count
    if ($comp.Count -gt 0 -and $comp[0] -match '^\s*Compressing:\s*(.+?)\s*$') {
        $r.FirstCompressed = $Matches[1]
    }

    # ISCC's own front matter.  Two distinct markers; either one proves the
    # front survived.  Version is wildcarded on purpose - see the header.
    $markers = 0
    if (@($lines | Where-Object { $_ -match 'Inno Setup\s+\d+\s+Command-Line Compiler' }).Count -gt 0) { $markers++ }
    if (@($lines | Where-Object { $_ -match 'Compiler engine version:' }).Count -gt 0)                 { $markers++ }
    $r.FrontMarkers = $markers

    # --- the verdict --------------------------------------------------------
    if ($markers -eq 0 -and $r.Compressing -eq 0) {
        $r.Verdict = 'NO NATIVE OUTPUT'
        $r.Why     = "not one line of ISCC's output reached this transcript - no banner and no Compressing lines. Expected $($r.Expected)."
    } elseif ($markers -eq 0) {
        $lost = $r.Expected - $r.Compressing
        $r.Verdict = 'TRUNCATED AT FRONT'
        $r.Why     = ("ISCC's banner is absent but $($r.Compressing) Compressing lines are present, so the FRONT was dropped: " +
                      "about $lost lines missing, and the log opens part-way through at '$($r.FirstCompressed)'. " +
                      'A compile error would have been in the dropped region.')
    } elseif ($r.Compressing -eq $r.Expected) {
        $r.Verdict = 'WHOLE'
        $r.Why     = "banner present and $($r.Compressing) Compressing lines for $($r.Expected) payload files."
    } elseif ($r.Compressing -gt $r.Expected) {
        # 24 Aug 2026 really happened: cycle-20260824-133558.log held TWO
        # complete cycles because an earlier transcript was never stopped.
        $r.Verdict = 'MORE THAN ONE RUN'
        $r.Why     = ("$($r.Compressing) Compressing lines against $($r.Expected) payload files - this log holds more than one " +
                      'run, so every count read from it belongs to an unknown mixture of them.')
    } else {
        $lost = $r.Expected - $r.Compressing
        $r.Verdict = 'SHORT'
        $r.Why     = ("banner present but $($r.Compressing) Compressing lines against $($r.Expected) payload files - " +
                      "$lost missing from the middle or the end.")
    }
    return $r
}

function Write-TranscriptWholeness {
    <#
      .SYNOPSIS
        Prints what Get-TranscriptWholeness measured - inputs first, then the
        verdict.  Returns $true only for WHOLE.
    #>
    param(
        [Parameter(Mandatory = $true)] $Result,
        [string] $Indent = '   '
    )
    Set-StrictMode -Version Latest

    $r = $Result
    # RULE 1 OF THE INSTRUMENT SECTION: the real inputs, not the intended ones.
    Write-Host ("{0}transcript : {1}" -f $Indent, $r.TranscriptPath)
    Write-Host ("{0}stage      : {1}" -f $Indent, $r.StagePath)

    if ($r.Verdict -eq 'NO VERDICT') {
        Write-Host ("{0}TRANSCRIPT COMPLETENESS: NO VERDICT - {1}" -f $Indent, $r.Why) -ForegroundColor Yellow
        Write-Host ("{0}  This is not a pass.  Nothing was compared." -f $Indent) -ForegroundColor Yellow
        return $false
    }

    Write-Host ("{0}staged {1:N0} files, {2:N0} are payload ({3} excluded by name{4})" -f
        $Indent, $r.StagedFiles, $r.Expected, $r.Excluded.Count,
        $(if ($r.Excluded.Count) { ': ' + ($r.Excluded -join ', ') } else { '' }))
    Write-Host ("{0}transcript holds {1:N0} Compressing lines, {2:N0} bytes, {3} of 2 ISCC front markers" -f
        $Indent, $r.Compressing, $r.TranscriptBytes, $r.FrontMarkers)
    if ($r.FirstCompressed) {
        Write-Host ("{0}first compressed file in the log: {1}" -f $Indent, $r.FirstCompressed)
    }

    if ($r.Verdict -eq 'WHOLE') {
        Write-Host ("{0}TRANSCRIPT COMPLETENESS: WHOLE - {1}" -f $Indent, $r.Why) -ForegroundColor Green
        return $true
    }

    # WARNS, NEVER FAILS.  The run is sound - cycle.ps1 gates on exit codes,
    # not on transcript text - and blocking a cycle over a logging artefact
    # would cost more than it saves.  Same decision as $TranscriptDegraded.
    Write-Host ("{0}TRANSCRIPT COMPLETENESS: {1}" -f $Indent, $r.Verdict) -ForegroundColor Yellow
    Write-Host ("{0}  {1}" -f $Indent, $r.Why) -ForegroundColor Yellow
    Write-Host ("{0}  The BUILD is unaffected - ISCC's exit code decided that, and it is checked" -f $Indent) -ForegroundColor Yellow
    Write-Host ("{0}  separately.  What is unreliable is reading this log to find out why." -f $Indent) -ForegroundColor Yellow
    return $false
}
