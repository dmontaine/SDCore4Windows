# test-stemcoverage-units.ps1 - does the litter sweep's name rule cover every
# account family the runners actually build?
#
#   powershell -ExecutionPolicy Bypass -File test-stemcoverage-units.ps1
#
# Exit 0 covered, 1 a family is not covered, 2 the check measured nothing.
# NO INSTALL, NO ELEVATION, NO RUN TOKEN.  One of the free tests CLAUDE.md says
# to run on every change.
#
# ===========================================================================
# WHY THIS EXISTS
# ===========================================================================
#
# PRE_RELEASE_FIXES 86, and it is the recommendation that entry left unbuilt.
# clean-test-profiles.ps1 carries a hand-kept list of name stems, and a verifier
# that invents a new family has to add its stem there in the same commit.  THAT
# HAS NOW BEEN MISSED THREE TIMES:
#
#   PRE_RELEASE 45   sddr, the door pair's four families, invisible for a day.
#   PRE_RELEASE 86   sdgate and sdtu - 25 of 268 directories on 30 Aug 2026.
#   this file        sdprof and sdsw, found the moment it was first run.
#
# AND IT FAILS THE QUIET WAY EVERY TIME, WHICH IS WHY A COMMENT WAS NEVER GOING
# TO BE ENOUGH.  An uncovered name is not refused and not counted - the sweep
# never sees it at all, so cleanup-devlitter.ps1 reports a clean run over a
# machine still carrying the litter.  Nothing goes red.  The only reason 86 was
# found is that somebody counted the directories on disk against the ones the
# pattern matched, by hand, once.
#
# SO THE FIX IS A COMPARISON, NOT A LONGER COMMENT.  The runners are the
# authority on what names exist: they compose every account name from the -Run
# token, so the families can be read out of them instead of remembered.
#
# ONE DIRECTION IS A FAILURE AND THE OTHER IS NOT.  A family with no stem is a
# hole and fails.  A stem with no family is a RETIRED test, which is harmless -
# it is reported so the list can be pruned, and it does not fail the run.
$ErrorActionPreference = 'Stop'

$root    = $PSScriptRoot
$sweep   = Join-Path $root 'clean-test-profiles.ps1'
$runners = @((Join-Path $root 'VerifyInstall1.ps1'), (Join-Path $root 'VerifyInstall2.ps1'))

Write-Output 'test-stemcoverage-units: does the sweep cover what the runners build?'
Write-Output ('  rule    : ' + $sweep)
foreach ($r in $runners) { Write-Output ('  runner  : ' + $r) }
Write-Output ''

foreach ($f in (@($sweep) + $runners)) {
    if (-not (Test-Path -LiteralPath $f)) {
        Write-Output ('REFUSED: cannot find ' + $f)
        exit 2
    }
}

# ---------------------------------------------------------------------------
# THE RULE, READ OUT OF THE SCRIPT THAT OWNS IT.  Retyping the regex here would
# make this the sixteenth place a stem list has to be kept in step, which is the
# defect rather than the fix.
$src    = Get-Content -LiteralPath $sweep -Raw
$mStems = [regex]::Match($src, '(?ms)^\$stems\s*=\s*@\((.*?)\)')
$mBare  = [regex]::Match($src, '(?m)^\$bare\s*=\s*@\((.*?)\)')
if (-not $mStems.Success -or -not $mBare.Success) {
    Write-Output 'REFUSED: could not read $stems / $bare out of the sweep - its shape changed.'
    exit 2
}
$stems = Invoke-Expression ('@(' + $mStems.Groups[1].Value + ')')
$bare  = Invoke-Expression ('@(' + $mBare.Groups[1].Value + ')')
if ($stems.Count -eq 0) { Write-Output 'REFUSED: the stem list read as empty.'; exit 2 }
$rx = '^((' + ($stems -join '|') + ')[a-z]?[0-9]+[a-z0-9]*|' + ($bare -join '|') + ')(\.[A-Za-z0-9-]+)?$'

Write-Output ('  stems   : ' + $stems.Count + '  ' + ($stems -join ', '))
Write-Output ''

# ---------------------------------------------------------------------------
# THE FAMILIES, READ OUT OF THE RUNNERS.  Every account name is composed from
# the -Run token as "sd<family>$Run", so that literal IS the list.  Reading it
# is what makes this a comparison rather than a second thing to remember.
$families = New-Object System.Collections.Generic.HashSet[string]
$where    = @{}
foreach ($r in $runners) {
    $txt = Get-Content -LiteralPath $r -Raw
    foreach ($m in [regex]::Matches($txt, '"(sd[a-z]+)\$Run"')) {
        $fam = $m.Groups[1].Value
        $null = $families.Add($fam)
        if (-not $where.ContainsKey($fam)) { $where[$fam] = (Split-Path $r -Leaf) }
    }
}

# THE NULL CASE, REFUSED OUT LOUD.  A regex that matched nothing would report
# "every family is covered" - a clean pass for having measured nothing, which is
# the exact failure the instrument rules in CLAUDE.md are about.
if ($families.Count -eq 0) {
    Write-Output 'REFUSED: no families were extracted from the runners at all.'
    Write-Output '  Either the runners stopped composing names as "sd<family>$Run",'
    Write-Output '  or this pattern is wrong.  Either way nothing was measured.'
    exit 2
}
if ($families.Count -lt 10) {
    Write-Output ('REFUSED: only ' + $families.Count + ' famil(y/ies) extracted, which is too few to be real.')
    Write-Output '  The runners build well over a dozen.  Treat this as a broken matcher.'
    exit 2
}

Write-Output ('  families: ' + $families.Count + '  (composed as "sd<family>$Run" in the runners)')
Write-Output ''

# ---------------------------------------------------------------------------
# CONTROLS, BEFORE THE VERDICT.  The matcher has to be shown able to say YES to
# something and NO to something, or a run of all-yes and a run of all-no look
# the same from the outside.
$ctlYes = ('sdacct' + 'b99') -match $rx
$ctlNo  = ('sdzzzq' + 'b99') -match $rx
Write-Output ('  control : a covered name matches      (sdacctb99)  : ' + $ctlYes + '   (must be True)')
Write-Output ('  control : an unknown family does not  (sdzzzqb99)  : ' + $ctlNo  + '   (must be False)')
if ((-not $ctlYes) -or $ctlNo) {
    Write-Output ''
    Write-Output 'REFUSED: the matcher failed its own controls, so its verdicts mean nothing.'
    exit 2
}
Write-Output ''

# ---------------------------------------------------------------------------
# THE COMPARISON.  Both real shapes are tried: the b-series the runners build
# today, and the bare-digit shape older prefixes used - a stem must cover its
# family however the run token is spelled, because -Run is only [a-z0-9]+ and a
# c-series would otherwise re-open the hole (the sweep's own note says so).
$bad = @()
foreach ($fam in ($families | Sort-Object)) {
    $probes = @(($fam + 'b99'), ($fam + '99'), ($fam + 'b99a'))
    $missed = @($probes | Where-Object { $_ -notmatch $rx })
    if ($missed.Count -gt 0) {
        $bad += [pscustomobject]@{ Family = $fam; From = $where[$fam]; Missed = ($missed -join ', ') }
    }
}

$unused = @($stems | Where-Object { -not $families.Contains($_) } | Sort-Object)

if ($bad.Count -gt 0) {
    Write-Output 'NOT COVERED - these families are invisible to the litter sweep:'
    foreach ($b in $bad) {
        Write-Output ('    ' + $b.Family + '   built by ' + $b.From + '   e.g. ' + $b.Missed)
    }
    Write-Output ''
    Write-Output 'Add the stem to $stems in clean-test-profiles.ps1, WITH a fixture in its'
    Write-Output '-SelfTest must-match list and a word-shaped near-miss in must-not.  A stem'
    Write-Output 'added without fixtures is the same fix that has now been missed three times.'
}

if ($unused.Count -gt 0) {
    Write-Output ''
    Write-Output ('Stems with no family in either runner (retired tests, NOT a failure): ' +
                  ($unused -join ', '))
}

Write-Output ''
Write-Output ('test-stemcoverage-units: ' + ($families.Count - $bad.Count) + ' of ' +
              $families.Count + ' famil(y/ies) covered, ' + $bad.Count + ' not.')
if ($bad.Count -gt 0) { exit 1 }
Write-Output 'test-stemcoverage-units: PASSED - every family the runners build is inside the rule.'
exit 0
