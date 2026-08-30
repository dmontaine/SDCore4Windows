# verify-txn.ps1 - does COMMIT end the transaction it commits?
#
#   powershell -File verify-txn.ps1
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# PRE_RELEASE_FIXES 11, UPSTREAM_FIXES 17.  op_txnbgn() did two things -
# incremented txn_depth, and pushed any running transaction onto txn_stack -
# and op_txncmt() undid NEITHER, while BCOMP's st.commit jumps past the
# OP.TXNEND that would have called rollback().  Two symptoms:
#
#   SYSTEM(1008) climbed for ever, so a program could not ask "am I in a
#   transaction"; and a NESTED commit zeroed process.txn_id while leaving the
#   OUTER transaction's cache orphaned on txn_stack, so the outer COMMIT then
#   committed an EMPTY cache and its writes were lost with no message.
#
# ***THE SECOND IS WHY THIS VERIFIER EXISTS.***  Part of a transaction landing
# and part not is the one outcome a transaction exists to prevent, and nothing
# reported it - not an error, not a status, not a log line.  A silent
# data-loss regression is exactly the kind that returns unnoticed.
#
# RUN IT UNELEVATED.  The probe is compiled and run in the caller's OWN SD
# account, and an elevated session lands in SDSYS instead (LOGIN's SDSYS case),
# where the probe is not.  An elevated run would measure the wrong account or
# nothing at all, so it is refused - the same guard, and the same reason, as
# verify-batchjob.ps1.
#
# NOT INSTALLED AND NOT SHIPPED - it must be on assert-current.ps1's
# $neverShipped list, or it reports the tree stale because it exists.

$ErrorActionPreference = 'Stop'

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$probe   = 'ZZTXN'          # the BASIC probe
$dataF   = 'ZZTXNF'         # its scratch file

$results = New-Object System.Collections.ArrayList
$script:fatal = $false

function Note($check, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
}

# ------------------------------------------------------------------- the gate
if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-txn: this is an ELEVATED PowerShell, and the probe lives in your own account.'
    Write-Output '  An elevated session lands in SDSYS, where the probe is not.  Run this from an'
    Write-Output '  ordinary prompt.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-txn: refusing - see above'
    exit 2
}

if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output "verify-txn: refusing - no $sdExe"
    exit 2
}

$account = $env:USERNAME.ToLower()
$acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $account)
if (-not (Test-Path -LiteralPath $acctDir)) {
    Write-Output "verify-txn: refusing - $account has no SD account at $acctDir"
    exit 2
}
$bp = Join-Path $acctDir 'bp'
if (-not (Test-Path -LiteralPath $bp)) {
    Write-Output "verify-txn: refusing - no bp directory at $bp"
    exit 2
}

Write-Output "verify-txn: probing as SD account $account"

# PIPED, INSIDE A JOB, WITH A TIMEOUT.  Start-Process -RedirectStandardInput
# hands sd.exe a FILE HANDLE and SD exits with "Process terminated" (sysmsg
# 5020) having run nothing; a pipe is what works.  The timeout is because a
# session sitting at a prompt otherwise holds its user-table slot and locks,
# and cycle.ps1 then refuses to start.
function Invoke-SdPiped([string[]]$commands, [int]$TimeoutSec = 90) {
    $body = "`n" + (($commands + 'OFF') -join "`n") + "`n"
    $job = Start-Job -ScriptBlock {
        param($exe, $text, $cwd)
        Set-Location $cwd
        $text | & $exe
    } -ArgumentList $sdExe, $body, $acctDir
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += '*** TIMED OUT - it is sitting at a prompt.'
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') | Out-String)
}

# --------------------------------------------------------------- the BASIC
#
# EVERY WRITE INSIDE A TRANSACTION IS PRECEDED BY RECORDLOCKU, because
# op_dio3.c:770 requires the record to be locked by this session already.  A
# write without it fails inside the transaction and the section below it would
# then be measuring the wrong thing.
#
# SECTIONS 1 AND 2 ARE THE CONTROLS AND THEY ARE NOT DECORATION.  A fix that
# broke ordinary commit or rollback would still make section 3 pass, so the
# balanced non-nested cases are asserted alongside it.
$src = @(
    "* $probe - written by gplbld/verify-txn.ps1.  Safe to delete."
    "      crt '$probe.START'"
    "      open '$dataF' to f else"
    "         execute 'create.file $dataF' capturing junk"
    "         open '$dataF' to f else"
    "            crt '$probe.NOFILE status=' : status()"
    "            crt '$probe.END'"
    "            stop"
    "         end"
    "      end"
    "      clearfile f"
    "      write 'base' to f, 'R1'"
    "      write 'base' to f, 'R2'"
    "      write 'base' to f, 'R3'"
    "      release"
    "*     1. a plain committed transaction - the control"
    "      l0 = system(1008)"
    "      begin transaction"
    "         recordlocku f, 'R1'"
    "         write 'one' to f, 'R1'"
    "         commit"
    "      end transaction"
    "      crt '$probe.PLAIN.DELTA=' : system(1008) - l0"
    "      read v from f, 'R1' then crt '$probe.PLAIN.R1=' : v else crt '$probe.PLAIN.R1=none'"
    "      release"
    "*     2. a rolled back transaction - the opposite control"
    "      l0 = system(1008)"
    "      begin transaction"
    "         recordlocku f, 'R2'"
    "         write 'rolled' to f, 'R2'"
    "         rollback"
    "      end transaction"
    "      crt '$probe.RBK.DELTA=' : system(1008) - l0"
    "      read v from f, 'R2' then crt '$probe.RBK.R2=' : v else crt '$probe.RBK.R2=none'"
    "      release"
    "*     3. THE DEFECT - a nested commit"
    "      l0 = system(1008)"
    "      begin transaction"
    "         recordlocku f, 'R2'"
    "         write 'outer' to f, 'R2'"
    "         begin transaction"
    "            crt '$probe.NEST.LEVEL=' : system(1008) - l0"
    "            recordlocku f, 'R3'"
    "            write 'inner' to f, 'R3'"
    "            commit"
    "         end transaction"
    "         crt '$probe.NEST.PARENT=' : (system(1007) # 0)"
    "         commit"
    "      end transaction"
    "      crt '$probe.NEST.DELTA=' : system(1008) - l0"
    "      read v from f, 'R2' then crt '$probe.NEST.OUTER=' : v else crt '$probe.NEST.OUTER=none'"
    "      read v from f, 'R3' then crt '$probe.NEST.INNER=' : v else crt '$probe.NEST.INNER=none'"
    "      release"
    "      close f"
    "      crt '$probe.END'"
    "      stop"
    # A trailing END, or BCOMP prints "WARNING: Final END statement is missing"
    # into the transcript on every run.  It compiles and runs either way, but a
    # warning nobody needs is a warning somebody will chase.
    "   end"
) -join "`n"

$srcPath = Join-Path $bp $probe
[System.IO.File]::WriteAllText($srcPath, $src + "`n",
                               [System.Text.Encoding]::GetEncoding('iso-8859-1'))

function Remove-Probe {
    $null = Invoke-SdPiped @("DELETE.FILE $dataF")
    foreach ($f in @($srcPath, (Join-Path $acctDir ('bp.out\' + $probe)))) {
        if (Test-Path -LiteralPath $f) {
            try { Remove-Item -LiteralPath $f -Force } catch {
                Write-Output "verify-txn: WARNING - could not remove $f"
            }
        }
    }
}

$out = Invoke-SdPiped @("BASIC bp $probe", "RUN bp $probe")

# ***THE NULL CASE, REFUSED OUT LOUD.***  Every check below reads a marker out
# of $out, and a run that never started prints none of them - so every check
# would compare $null against its expectation and could score however the
# comparison happened to fall.  START and END together also prove the program
# did not abort part way, which no individual marker can.
if (-not $out.Contains("$probe.START")) {
    Write-Output 'verify-txn: the probe never ran - nothing below would mean anything.'
    Write-Output $out
    Remove-Probe
    exit 2
}
if (-not $out.Contains("$probe.END")) {
    Write-Output 'verify-txn: the probe STARTED and did not finish - it aborted part way.'
    Write-Output $out
    Remove-Probe
    exit 2
}

Write-Output $out

# Read one "NAME=value" marker.  Returns $null when absent, which the checks
# below treat as a failure rather than as a zero.
function Marker([string]$name) {
    foreach ($line in ($out -split "`r?`n")) {
        $t = $line.Trim()
        if ($t.StartsWith("$probe.$name=")) {
            return $t.Substring("$probe.$name=".Length).Trim()
        }
    }
    return $null
}

# ------------------------------------------------------------- the controls
Note 'control: plain commit is balanced'   '0'     (Marker 'PLAIN.DELTA') $true
Note 'control: plain commit landed'        'one'   (Marker 'PLAIN.R1')    $true
Note 'control: rollback is balanced'       '0'     (Marker 'RBK.DELTA')   $true
Note 'control: rollback discarded'         'base'  (Marker 'RBK.R2')      $true

# ------------------------------------------------------------ the defect
# THE DECISIVE ONE IS NEST.OUTER.  Before the fix it read "base": the inner
# COMMIT orphaned the outer transaction's cache and the outer COMMIT wrote an
# empty one, so the outer record silently kept its old value while the inner
# record landed.  The other three rows say WHY, and would each have been enough
# to notice it, which is the point of having them.
# 29 Aug 26 - THIS ROW EXPECTED 1 ON ITS FIRST RUN AND THE PRODUCT WAS RIGHT.
# l0 is taken OUTSIDE the outer transaction, so inside the inner one the depth
# is two levels above it, not one; the label said "1 above" and the arithmetic
# said 2.  Corrected here rather than by moving l0, because a delta measured
# from outside the pair is also what NEST.DELTA needs, and one baseline for
# both is one thing to get wrong instead of two.
Note 'nested: inside the inner, 2 above'   '2'     (Marker 'NEST.LEVEL')  $true
Note 'nested: parent reinstated on commit' '1'     (Marker 'NEST.PARENT') $true
Note 'nested: the pair is balanced'        '0'     (Marker 'NEST.DELTA')  $true
Note "nested: THE OUTER WRITE LANDED"      'outer' (Marker 'NEST.OUTER')  $true
Note 'nested: the inner write landed'      'inner' (Marker 'NEST.INNER')  $true

Remove-Probe

# ---------------------------------------------------------------------- report
$results | Format-Table -AutoSize | Out-String | Write-Output

if ($fatal) {
    Write-Output 'verify-txn: FAILED.'
    Write-Output ''
    if ((Marker 'NEST.OUTER') -eq 'base') {
        Write-Output '  THE OUTER TRANSACTION LOST ITS WRITE.  This is PRE_RELEASE_FIXES 11 /'
        Write-Output '  UPSTREAM_FIXES 17 returning: op_txncmt() is not leaving the transaction'
        Write-Output '  level it commits, so a nested COMMIT orphans the outer cache on'
        Write-Output '  txn_stack and the outer COMMIT writes an empty one.  See'
        Write-Output '  gplsrc/txn.c, end_txn_level() and its caller at the foot of op_txncmt().'
    }
    exit 1
}

Write-Output 'verify-txn: PASSED - commit ends its own level, and a nested commit keeps the parent.'
exit 0
