# verify-basicfuncs.ps1 - do SD BASIC's intrinsic functions and operators
#                         return the RIGHT ANSWERS?
#
#   powershell -ExecutionPolicy Bypass -File verify-basicfuncs.ps1 [-Account don] [-Keep]
#
# Exit 0 every case passed, 1 a case failed, 2 the test could not run.
# ***AN ORDINARY UNELEVATED PROMPT.***  Nothing here needs a privilege, and the
# account it uses is the caller's own.
#
# 31 Aug 26 Windows port - written for the §5.23 audit.  The six sweeps asked
# whether a status was discarded; this asks the question underneath them, which
# is whether the language answers correctly at all.  Every query in the system
# is built out of these functions.
#
# THE MODEL IS PRE_RELEASE 94's PROBE, deliberately: a throwaway record in the
# caller's own bp, compiled there, run unelevated, and removed again - nothing
# is created, no account is made, and the installed tree is not written to.
#
# THREE THINGS IT REFUSES, EACH BECAUSE THE INSTRUMENT RULES REQUIRE IT:
#
#   1. IT REFUSES A STALE INSTALL.  assert-current first, because a result from
#      a tree that does not match source measures the wrong binary.
#   2. IT ANCHORS THE COMPILE ON "0 error(s)", NOT ON THE PROGRAM NAME.  The
#      name appears in BASIC:330's "Compiling ff rr" - printed BEFORE the
#      compile - and again in BCOMP's 2612 "Compilation error in %1", so it is
#      carried on both paths and proves nothing.  BCOMP:1540 prints the count
#      on the happy path and that is the only wording that means success.
#      This is PRE_RELEASE 105's own fix, applied here rather than only filed.
#   3. IT REFUSES THE NULL CASE OUT LOUD.  The probe's last lines are
#      TOTAL|<n>|FAILS|<m> and PROBE.DONE.  A run that compiled but executed
#      nothing prints TOTAL|0, and a run that died half way prints no
#      PROBE.DONE at all; both are exit 2, never "no failures found".
#      The count of OK/FAIL lines is also reconciled against TOTAL, so a probe
#      that stopped silently in the middle cannot score a clean pass.

[CmdletBinding()]
param(
    [string]$Account = $env:USERNAME,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$Root   = Join-Path $env:ProgramData 'SD\user_accounts'
$Probe  = 'ZZBASICFUNCS'          # namespaced so it cannot collide with a program

function Say([string]$m) { Write-Host $m }

# ---------------------------------------------------------------------------
# THE COVERAGE CHECK - RELEASE_1.1_FIXES.md 17, BUGS_FROM_LINUX_PORT.md bug 8.
#
# basicfuncs.sb used to close its exclusion list with "Everything else in
# BCOMP's intrinsics table is exercised below".  That is PROSE: it could not be
# wrong out loud, and an intrinsic added to BCOMP later joined the gap in
# silence.  This function makes the same claim MECHANICAL.
#
# It takes text, not paths, so the units test can drive every verdict without
# an install, an account or an SD.  Returns a hashtable; the caller prints the
# rows.  Nothing here decides the exit code.
function Get-CoverageVerdict([string]$bcompText, [string]$probeText) {

    # BCOMP HAS TWO TABLES AND ONLY ONE IS IN SCOPE.  "intrinsics" is the
    # ordinary set; "int.intrinsics" (BCOMP:619) is the 36 internal ones, which
    # only an $internal program may call.  An UNANCHORED pattern matches both -
    # measured, and it reported 212 instead of 176 the first time this was
    # asked.  The anchor is what makes the number mean something.
    $known = @()
    foreach ($m in [regex]::Matches($bcompText, '(?m)^\s*intrinsics(?:<-1>)?\s*=\s*"([^"]+)"')) {
        $known += $m.Groups[1].Value
    }
    $knownSet = @{}
    foreach ($k in $known) { $knownSet[$k] = $true }

    # COMMENT LINES ARE NOT CODE.  basicfuncs.sb quotes an old case label in a
    # comment explaining a relabelling; counting that as coverage would credit
    # a function nothing calls.
    $codeLines = @()
    $declared  = @()
    $declaredUnknown = @()
    foreach ($line in ($probeText -split "`r?`n")) {
        if ($line -match '^\s*\*') {
            $d = [regex]::Match($line, '^\s*\*\s*NOT\.TESTED:\s*(.+)$')
            if ($d.Success) {
                foreach ($tok in ($d.Groups[1].Value -split '\s+')) {
                    if ($tok -eq '') { continue }
                    if ($knownSet.ContainsKey($tok)) { $declared += $tok }
                    else { $declaredUnknown += $tok }
                }
            }
            continue
        }
        $codeLines += $line
    }
    $declaredSet = @{}
    foreach ($d in $declared) { $declaredSet[$d] = $true }

    # A case label is 'NAME' or 'NAME.variant'.  Longest match wins, so
    # ARG.COUNT is not read as ARG.
    $exercisedSet = @{}
    $operatorLabels = @()
    $strayLabels    = @()
    foreach ($m in [regex]::Matches(($codeLines -join "`n"), "n\s*=\s*'([^']+)'")) {
        $lab  = $m.Groups[1].Value
        $best = ''
        foreach ($k in $knownSet.psbase.Keys) {
            if ($lab -eq $k -or $lab.StartsWith($k + '.')) {
                if ($k.Length -gt $best.Length) { $best = $k }
            }
        }
        if ($best -ne '') { $exercisedSet[$best] = $true }
        elseif ($lab.StartsWith('OP.')) { $operatorLabels += $lab }
        else { $strayLabels += $lab }
    }

    $both        = @()
    $unaccounted = @()
    foreach ($k in $known) {
        $e = $exercisedSet.ContainsKey($k)
        $d = $declaredSet.ContainsKey($k)
        if ($e -and $d) { $both += $k }
        if (-not $e -and -not $d) { $unaccounted += $k }
    }

    # ***.psbase.Count, NOT .Count, AND THAT IS NOT STYLE.***  These hashtables
    # are keyed by BASIC function names and BCOMP has an intrinsic called COUNT.
    # PowerShell resolves $h.Count to the VALUE OF THE KEY "COUNT" when one
    # exists, so the tally came back as "True" - a member lookup silently
    # shadowed by the data.  Measured: the fixture rows passed (no COUNT in
    # them) and the live row against the real tree is what caught it.
    return @{
        Known           = $known.Count
        Exercised       = $exercisedSet.psbase.Count
        Declared        = $declaredSet.psbase.Count
        Both            = @($both | Sort-Object)
        Unaccounted     = @($unaccounted | Sort-Object)
        DeclaredUnknown = @($declaredUnknown)
        OperatorLabels  = $operatorLabels.Count
        StrayLabels     = @($strayLabels | Sort-Object)
    }
}

function Bail([int]$code, [string]$why) {
    Say ''
    if ($code -eq 0) { Say "verify-basicfuncs: PASSED - $why" }
    elseif ($code -eq 1) { Say "verify-basicfuncs: FAILED - $why" }
    else { Say "verify-basicfuncs: COULD NOT RUN - $why" }
    exit $code
}

# Same shape as verify-accountacl.ps1's Invoke-SD: a blank first line absorbs
# the BOM the pipe prepends, TERM stops it paginating, OFF ends it.  No LOGTO
# here - the probe runs in the caller's own account, which is the point.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# ---------------------------------------------------------------------------
# Refusals, before anything is written.

if (-not (Test-Path -LiteralPath $sdExe)) {
    Bail 2 "no sd.exe at $sdExe - SD does not look installed."
}

$acctDir = Join-Path $Root $Account
$bpDir   = Join-Path $acctDir 'bp'
if (-not (Test-Path -LiteralPath $bpDir)) {
    Bail 2 "no bp directory at $bpDir - pass -Account with an SD account name."
}

$srcFile = Join-Path $Gplbld 'basicfuncs.sb'
if (-not (Test-Path -LiteralPath $srcFile)) {
    Bail 2 "basicfuncs.sb is missing from $Gplbld."
}

Say "verify-basicfuncs: account   $Account"
Say "verify-basicfuncs: bp        $bpDir"
Say "verify-basicfuncs: sd.exe    $sdExe"
Say "verify-basicfuncs: probe     $Probe"
Say ''

# 0. COVERAGE, before anything is compiled or run.  It costs nothing, it needs
#    no install, and it is the one check that can say "this file no longer
#    tests what its header claims".
Say '--- coverage -------------------------------------------------------'
$bcompPath = Join-Path $Gplbld '..\sdsys\gpl.bp\BCOMP'
if (-not (Test-Path -LiteralPath $bcompPath)) {
    Bail 2 "cannot read BCOMP at $bcompPath - the coverage claim cannot be checked."
}
Say "  BCOMP           : $((Resolve-Path $bcompPath).Path)"
Say "  probe           : $srcFile"

$cov = Get-CoverageVerdict (Get-Content -LiteralPath $bcompPath -Raw) (Get-Content -LiteralPath $srcFile -Raw)

Say "  BCOMP intrinsics: $($cov.Known)"
Say "  exercised       : $($cov.Exercised)"
Say "  declared        : $($cov.Declared)"
Say "  operator labels : $($cov.OperatorLabels)  (tested by syntax, not by name)"

$covFails = @()

# V1 IS THE NULL-CASE REFUSAL.  If the table did not parse, every count below
# is 0 and every other row passes VACUOUSLY - a test that passes because it did
# nothing must fail.
if ($cov.Known -lt 100) {
    $covFails += "V1 BCOMP's intrinsics table did not parse: $($cov.Known) name(s) found, expected well over 100.  Nothing below was measured."
} else {
    Say "  [PASS] V1 BCOMP's intrinsics table parsed: $($cov.Known) names"
}

if ($cov.Unaccounted.Count -gt 0) {
    $covFails += "V2 named NOWHERE - neither exercised nor declared: $($cov.Unaccounted -join ', ')"
} else {
    Say '  [PASS] V2 every intrinsic is either exercised or declared'
}

if ($cov.Both.Count -gt 0) {
    $covFails += "V3 claimed BOTH ways - declared untested AND exercised: $($cov.Both -join ', ')"
} else {
    Say '  [PASS] V3 no intrinsic is both declared and exercised'
}

if ($cov.DeclaredUnknown.Count -gt 0) {
    $covFails += "V4 declared untested but UNKNOWN to BCOMP: $($cov.DeclaredUnknown -join ', ')"
} else {
    Say '  [PASS] V4 every declared name is one BCOMP knows'
}

# V5 catches a label that names a function this tree does not have.  One did:
# 'ADDS.via.SUM', where BCOMP and OPCODES.H both have no ADDS at all.
if ($cov.StrayLabels.Count -gt 0) {
    $covFails += "V5 case label names no intrinsic and is not an OP. operator case: $($cov.StrayLabels -join ', ')"
} else {
    Say '  [PASS] V5 every case label names an intrinsic or an OP. operator case'
}

if ($covFails.Count -gt 0) {
    Say ''
    foreach ($f in $covFails) { Say "  [FAIL] $f" }
    Bail 1 ("the coverage claim is wrong: $($covFails.Count) row(s) failed.  " +
            'basicfuncs.sb no longer tests what its header says it tests.')
}
Say "  accounted for   : $($cov.Exercised + $cov.Declared) of $($cov.Known)"
Say ''

# 1. The install must match source, or the answers came from the wrong binary.
Say '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Bail 2 'assert-current refuses - the installed tree does not match source.'
}
Say ''

$dest = Join-Path $bpDir $Probe
$obj  = Join-Path $acctDir "BP.OUT\$Probe"

try {
    Copy-Item -LiteralPath $srcFile -Destination $dest -Force

    # 2. Compile, and anchor on the SUCCESS wording.
    Say '--- compile --------------------------------------------------------'
    $out = Invoke-SD @("BASIC BP $Probe")
    Write-Host $out

    $sawCount = ($out -match '\b0 error')
    $sawBad   = ($out -match '[1-9][0-9]* error') -or ($out -match 'Compilation error')
    if ($sawBad -or -not $sawCount) {
        Bail 2 ('the probe did not compile.  Anchor is BCOMP:1540 "0 error(s)"; ' +
                "saw0errors=$sawCount sawErrors=$sawBad.  The output above says why.")
    }
    Say ''

    # 3. Run it.
    Say '--- run ------------------------------------------------------------'
    $run = Invoke-SD @("RUN BP $Probe")
    Write-Host $run
    Say ''

    # 4. Null-case refusals, before any verdict is drawn.
    if ($run -notmatch 'PROBE\.DONE') {
        Bail 2 'the probe did not reach its end (no PROBE.DONE) - nothing was measured.'
    }
    if ($run -notmatch 'TOTAL\|(\d+)\|FAILS\|(\d+)') {
        Bail 2 'the probe printed no TOTAL line - nothing was measured.'
    }
    $total = [int]$Matches[1]
    $fails = [int]$Matches[2]

    if ($total -eq 0) {
        Bail 2 'the probe ran 0 cases.  A test that passes because it did nothing must fail.'
    }

    # Reconcile: the per-case lines must account for every case the probe counted.
    $lines = @($run -split "`n" | Where-Object { $_ -match '^(OK|FAIL)\|' })
    if ($lines.Count -ne $total) {
        Bail 2 ("the probe counted $total case(s) but printed $($lines.Count) case line(s) - " +
                'it stopped part way and the tally cannot be trusted.')
    }

    $failLines = @($run -split "`n" | Where-Object { $_ -match '^FAIL\|' })
    if ($failLines.Count -ne $fails) {
        Bail 2 ("the probe reported $fails failure(s) but printed $($failLines.Count) FAIL line(s).")
    }

    Say '--- result ---------------------------------------------------------'
    Say "cases measured : $total"
    Say "failures       : $fails"
    if ($fails -gt 0) {
        Say ''
        Say 'The failing cases, verbatim:'
        foreach ($l in $failLines) { Say "  $l" }
        Bail 1 "$fails of $total case(s) returned the wrong answer."
    }

    Bail 0 "all $total case(s) returned the expected answer."
}
finally {
    if (-not $Keep) {
        foreach ($p in @($dest, $obj)) {
            if (Test-Path -LiteralPath $p) {
                try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop }
                catch { Say "  (could not remove $p - $($_.Exception.Message))" }
            }
        }
        # Say what the cleanup actually did, rather than assuming it worked.
        $leftS = Test-Path -LiteralPath $dest
        $leftO = Test-Path -LiteralPath $obj
        Say "cleanup: source left=$leftS object left=$leftO"
    } else {
        Say "cleanup: -Keep given, $dest left in place."
    }
}
