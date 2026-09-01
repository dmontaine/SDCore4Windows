# verify-basicfuncs.ps1 - do SD BASIC's intrinsic functions and operators
#                         return the RIGHT ANSWERS?
#
#   powershell -File verify-basicfuncs.ps1 [-Account don] [-Keep]
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
