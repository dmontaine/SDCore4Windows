<#
.SYNOPSIS
    The Linux 1.2-0 area 1 sandbox suites, run against the INSTALLED SD in the
    caller's own account (RELEASE_1.1 143).  ***AN ORDINARY UNELEVATED PROMPT.***

.DESCRIPTION
    gplbld\verify-carry-NAME.py are byte copies of SD Core for Linux's
    sandbox-NAME.py (Linux Dev 1c94d00..ba885ac: bundles A-1..A-9, B-1..B-5, B-9,
    the second sitting parts 1-32, the data collections, akcase).  Each one writes
    probe programs into <box>\sys\bp, compiles and runs them in an SD session, and
    judges what the session printed.  Linux gives them a private sandbox; here:

      * the BOX is %LOCALAPPDATA%\SD-verify\carry-box-<time>, holding
          sys            a JUNCTION to the caller's own account directory, so the
                         suite's bp, bp.out, cat, $hold ... are that account's;
          user_accounts  an empty directory (Linux passes it as the cwd);
      * verify-carry-run.py stands in for Linux's sandbox-fromtree.py: every
        session the suite asks for is sd.exe with the same stdin Linux sends
        ("TERM 200,9999", the commands, "OFF").  The suites are NOT edited.

    ***WHAT A ROW MEANS HERE.***  The suites were written against a Linux sandbox
    that plays SDSYS.  A row that depends on that, or on a Linux path, a shell
    command or an sd.conf location, can fail on Windows without the feature being
    wrong.  Linux's expected-output lists (P:\sdcore-mail\parity\linux-core-carry-18oct\expected)
    mark such rows "Linux-only"; $Known below names the rows judged N/A on
    Windows, each with its reason, and they are printed as N/A, never as PASS.
    The first run on a fresh install is expected to find some; add them, with the
    reason, rather than loosening a row.

    ***THE INSTRUMENT IS WHAT THE SUITES PRINT.***  This step prints every
    suite's own PASS/FAIL lines, then a table of rows per suite.  A suite that
    exits 0 having printed no PASS line is COULD NOT RUN, not a pass.

    Needs: an installed SD that matches source (assert-current first), python on
    PATH (the free guards need it too), and a session that lands in an ordinary
    account.  It writes fixtures into that account's bp and the suites' own
    zz-named files, which the suites remove again.

.PARAMETER Suite
    Suite names without the verify-carry- prefix (func-b4, coll ...), comma
    separated or as a list.  Default: every verify-carry-*.py in this folder.

.PARAMETER Account
    The SD account the sessions land in (the caller's).

.OUTPUTS
    Exit 0 every suite passed, 1 a row failed, 2 a suite could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\verify-carry.ps1 -Suite func-b4,conv-b3
#>

[CmdletBinding()]
param(
    [string[]]$Suite = @(),
    [string]$Account = $env:USERNAME,
    [switch]$Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Run     = Join-Path $Gplbld 'verify-carry-run.py'
$Root    = Join-Path $env:ProgramData 'SD\user_accounts'
$AcctDir = Join-Path $Root $Account

# Rows judged N/A on Windows: 'suite' = @{ 'start of the row label' = 'reason' }.  Empty until the first
# run on a fresh install shows which rows are a Linux mechanism and not a feature.
$Known = @{}

function Say([string]$m) { Write-Host $m }
function Bail([int]$code, [string]$why) {
    Say ''
    if ($code -eq 0) { Say "verify-carry: PASSED - $why" }
    elseif ($code -eq 1) { Say "verify-carry: FAILED - $why" }
    else { Say "verify-carry: COULD NOT RUN - $why" }
    exit $code
}

# --- which suites ---------------------------------------------------------------------------------
$all = @(Get-ChildItem -LiteralPath $Gplbld -File -Filter 'verify-carry-*.py' |
         Where-Object { $_.Name -ne 'verify-carry-run.py' } |
         ForEach-Object { $_.Name -replace '^verify-carry-', '' -replace '\.py$', '' } | Sort-Object)
if ($all.Count -lt 10) { Bail 2 "only $($all.Count) verify-carry-*.py found in $Gplbld; expected 18." }
$names = @($Suite | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($names.Count -eq 0) { $names = $all }
foreach ($n in $names) {
    if ($all -notcontains $n) { Bail 2 "no suite called '$n'. Known: $($all -join ', ')" }
}

Say "verify-carry: account   $Account"
Say "verify-carry: suites    $($names -join ', ')"
Say "verify-carry: launcher  $Run"
Say ''

if (-not (Test-Path -LiteralPath $Run)) { Bail 2 "verify-carry-run.py is missing from $Gplbld." }
$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path -LiteralPath $sdExe)) { Bail 2 "no sd.exe at $sdExe - SD does not look installed." }
if (-not (Test-Path -LiteralPath (Join-Path $AcctDir 'bp'))) { Bail 2 "no bp file at $AcctDir\bp - pass -Account with an SD account name." }
if ($null -eq (Get-Command python -ErrorAction SilentlyContinue)) { Bail 2 'python is not on PATH.' }
$pyv = (& python -c "import sys; print(sys.version_info[0])" 2>&1 | Out-String).Trim()
if ($pyv -ne '3') { Bail 2 "python on PATH is not Python 3 (it answered '$pyv')." }

# --- the install must match source ---------------------------------------------------------------
Say '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }

# --- the box ---------------------------------------------------------------------------------------
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
$box = Join-Path $logDir ('carry-box-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$null = New-Item -ItemType Directory -Path $box -Force
$null = New-Item -ItemType Directory -Path (Join-Path $box 'user_accounts') -Force
$null = New-Item -ItemType Junction -Path (Join-Path $box 'sys') -Target $AcctDir
Say "verify-carry: box       $box"
Say "verify-carry: sys       -> $AcctDir  (a junction)"
if (-not (Test-Path -LiteralPath (Join-Path $box 'sys\bp'))) { Bail 2 'the junction does not show the account bp file.' }
Say ''

$rows = @()
$worst = 0
try {
    foreach ($n in $names) {
        $file = Join-Path $Gplbld "verify-carry-$n.py"
        Say "=== $n ====================================================="
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        $pass = 0; $fail = 0; $na = 0; $failed = @()
        # Windows PowerShell 5.1 turns a native command's stderr into a terminating error when
        # ErrorActionPreference is Stop and 2>&1 is used; the suites print to stderr on a failed row.
        $ErrorActionPreference = 'Continue'
        $lines = @(& python -X utf8 $Run $file $box 2>&1 | ForEach-Object { "$_" })
        $rc = $LASTEXITCODE
        $ErrorActionPreference = 'Stop'
        foreach ($l in $lines) {
            $mark = $false
            if ($l -match '^\s*\[FAIL\]\s*(.*)$') {
                $label = $Matches[1]
                $why = $null
                if ($Known.ContainsKey($n)) {
                    foreach ($k in $Known[$n].Keys) { if ($label.StartsWith($k)) { $why = $Known[$n][$k] } }
                }
                if ($why) { $na++; Say ("  [N/A ] " + $label + "   (" + $why + ")"); $mark = $true }
                else { $fail++; $failed += $label }
            } elseif ($l -match '^\s*\[PASS\]') { $pass++ }
            if (-not $mark) { Say $l }
        }
        $sw.Stop()
        if ($rc -ge 2 -or ($rc -eq 0 -and $pass -eq 0)) { $verdict = 'COULD NOT RUN'; $worst = [Math]::Max($worst, 2) }
        elseif ($fail -gt 0 -or ($rc -eq 1 -and $na -eq 0)) { $verdict = 'FAIL'; $worst = [Math]::Max($worst, 1) }
        else { $verdict = 'PASS' }
        $rows += [pscustomobject]@{ Suite = $n; Rows = ($pass + $fail + $na); Pass = $pass; Fail = $fail; NA = $na; Exit = $rc; Secs = [int]$sw.Elapsed.TotalSeconds; Verdict = $verdict }
        Say ''
    }
} finally {
    if (-not $Keep) {
        # Remove the junction ITSELF first, and delete the rest of the box only once it is gone:
        # a recursive Remove-Item through a live junction would delete the account it points at.
        $sysLink = Join-Path $box 'sys'
        if (Test-Path -LiteralPath $sysLink) { [System.IO.Directory]::Delete($sysLink, $false) }
        if (-not (Test-Path -LiteralPath $sysLink)) {
            Remove-Item -LiteralPath $box -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Write-Host "WARNING: the junction $sysLink is still there; the box was left alone." -ForegroundColor Red
        }
        if (-not (Test-Path -LiteralPath (Join-Path $AcctDir 'bp'))) {
            Write-Host 'WARNING: the account bp file is missing after cleanup' -ForegroundColor Red
        }
    }
}

Say '--- summary --------------------------------------------------------'
$rows | Format-Table Suite, Rows, Pass, Fail, NA, Exit, Secs, Verdict -AutoSize | Out-String -Width 200 | ForEach-Object { Say $_.TrimEnd() }
$totR = ($rows | Measure-Object Rows -Sum).Sum
$totF = ($rows | Measure-Object Fail -Sum).Sum
$totN = ($rows | Measure-Object NA -Sum).Sum
Say ("verify-carry: {0} suite(s), {1} row(s), {2} failed, {3} N/A on Windows" -f $rows.Count, $totR, $totF, $totN)

if ($worst -eq 2) { Bail 2 'at least one suite could not run (or printed no PASS row): nothing may be concluded from it.' }
if ($worst -eq 1) { Bail 1 "$totF row(s) failed." }
Bail 0 "$totR row(s) in $($rows.Count) suite(s)."
