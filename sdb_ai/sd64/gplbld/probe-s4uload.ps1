<#
.SYNOPSIS
    RELEASE_1.1 43 open point (f): does the S4U mint (LsaLogonUser) hold up
    with fifty API connections arriving at once?  Runs probe-s4uload.exe as
    LocalSystem, against the real relay account, and reads its verdict.

.DESCRIPTION
    Each API connection's sd mints the bare relay account's token with an S4U
    LsaLogonUser before spawning the relay (win32relay.c).  probe-relayscale
    measured fifty relay processes; nothing had put the mint itself under
    concurrency.  probe-s4uload.c measures it as SERIAL (latency floor),
    THREADS (n minting at once, tokens held so n logon sessions are alive
    together), PROCS at n and 2n (the product's one-process-per-connection
    shape), and a LEAK check on LSA's logon-session count before, at peak and
    after.  The .c header has the detail; this script only gets it run as
    SYSTEM - SeTcb is what S4U needs and no interactive account has it - and
    reads the log back.

    IT USES THE INSTALLED sdrelay ACCOUNT, deliberately: that is the account
    the product mints, with the deny-logon rights install-service.ps1 set.  It
    refuses if the account is not there rather than making a stand-in.
    Nothing is created but a scheduled task and a stage directory, both
    removed at the end.

    ELEVATED PowerShell (it creates and runs a SYSTEM task).
    Build the probe first, from gplbld in an MSYS2 UCRT64 bash:
      gcc -O2 -Wall -o probe-s4uload.exe probe-s4uload.c -lsecur32 -ladvapi32

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File probe-s4uload.ps1
    powershell -ExecutionPolicy Bypass -File probe-s4uload.ps1 -N 100
#>

# Exit 0 answered and nothing falsified, 1 falsified, 2 could not run.

[CmdletBinding()]
param(
    [string] $Account = 'sdrelay',
    [int]    $N = 50,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe    = Join-Path $Gplbld 'probe-s4uload.exe'
$Task   = 's4uloadprobe'
$Stage  = 'C:\ProgramData\s4uload-run'

function Say($m, $ForegroundColor) {
    if ($ForegroundColor) { Write-Host $m -ForegroundColor $ForegroundColor } else { Write-Host $m }
}
function Step($m)   { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Cleanup {
    if ($script:Keeping) { Say "  -Keep: leaving $Task and $Stage in place"; return }
    # schtasks /query on an absent task writes to stderr, which under 'Stop'
    # is terminating (probe-s4u.ps1's header) - so it is asked inside try.
    try { $t = & schtasks.exe /query /tn $Task 2>$null; if ($t) { $null = & schtasks.exe /delete /tn $Task /f 2>$null } } catch { }
    try { if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue } } catch { }
}
function Refuse($m) { Write-Host ''; Write-Host "COULD NOT RUN: $m" -ForegroundColor Yellow; Cleanup; exit 2 }
function Fail($m)   { Write-Host ''; Write-Host "FALSIFIED: $m" -ForegroundColor Red; Cleanup; exit 1 }
$script:Keeping = [bool]$Keep

trap { Write-Host ''; Write-Host "UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red; Cleanup; exit 3 }

# ---------------------------------------------------------------------------
Step 'Preconditions'
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
Say "  running as        : $($id.Name)"
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ''; Write-Host 'COULD NOT RUN: this needs an ELEVATED PowerShell - it creates and runs a SYSTEM task.' -ForegroundColor Yellow; exit 2
}
if (-not (Test-Path -LiteralPath $Exe)) { Write-Host "COULD NOT RUN: no $Exe - build it first (native, UCRT64; see the .c header)." -ForegroundColor Yellow; exit 2 }
$u = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
if ($null -eq $u) { Write-Host "COULD NOT RUN: no local account $Account - install-service.ps1 -Install creates it; this probe mints the real one and makes no stand-in." -ForegroundColor Yellow; exit 2 }
Say "  account           : $Account (SID $($u.SID.Value), enabled $($u.Enabled))"
Say "  n                 : $N"
# A control that the exe is the probe and not something else at that path.
$usage = & $Exe 2>&1 | Out-String
if ($usage -notmatch 'probe-s4uload\.exe --run') { Refuse "$Exe did not print probe-s4uload's usage line." }

# ---------------------------------------------------------------------------
Step 'Staging where SYSTEM can run it'
if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
$null = New-Item -ItemType Directory -Path $Stage -Force
Copy-Item -LiteralPath $Exe -Destination $Stage -Force
$null = & icacls.exe $Stage /grant "*S-1-5-18:(OI)(CI)F" /T
if ($LASTEXITCODE -ne 0) { Refuse "icacls could not grant SYSTEM on $Stage." }
Say "  staged            : $Stage"

# ---------------------------------------------------------------------------
Step 'Running as LocalSystem'
$tr = '"' + (Join-Path $Stage 'probe-s4uload.exe') + '" --run ' + $Account + ' "' + $Stage + '" ' + $N
Say "  task command      : $tr"
$out = & schtasks.exe /create /tn $Task /tr $tr /sc once /st 23:59 /ru SYSTEM /rl HIGHEST /f
if ($LASTEXITCODE -ne 0) { Refuse "schtasks /create failed - $($out -join ' ')" }
$out = & schtasks.exe /run /tn $Task
if ($LASTEXITCODE -ne 0) { Refuse "schtasks /run failed - $($out -join ' ')" }
Say '  started as SYSTEM'

$log = Join-Path $Stage 's4uload.log'
# Serial n + threads n + procs n + procs 2n at ~5-50 ms a mint; generous.
$deadline = (Get-Date).AddSeconds(240)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path -LiteralPath $log) -and (Select-String -LiteralPath $log -Pattern 'RUN DONE|REFUSED' -Quiet)) { break }
    Start-Sleep -Milliseconds 500
}

# ---------------------------------------------------------------------------
Step 'What it measured'
if (-not (Test-Path -LiteralPath $log)) {
    $info = & schtasks.exe /query /tn $Task /fo LIST /v 2>&1
    ($info | Select-String -Pattern 'Last Result|Last Run Time|Status|Task To Run') | ForEach-Object { Say "  | $($_.ToString().Trim())" }
    Refuse 'the SYSTEM task wrote no log - read its Last Result above.'
}
Get-Content -LiteralPath $log | ForEach-Object { Say "  | $_" }
$text = Get-Content -LiteralPath $log -Raw

if ($text -match 'REFUSED') { Refuse 'the probe refused (above) - the account or the token, not the load.' }
if ($text -notmatch 'RUN DONE') { Refuse 'the probe did not finish inside 240 s - read the log above for how far it got.' }

# The rows the verdict is drawn from, each anchored on the success wording
# and each with its failure wording as the disqualifier.
$rows = @()
function Row($name, $ok) { $script:rows += [pscustomobject]@{ Check = $name; Result = $(if ($ok) { 'PASS' } else { 'FAIL' }) }; Say ("  [{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $name) }
Say ''
Row 'the first mint succeeded (null case refused)'            ($text -match 'first mint\s+: ok')
Row "SERIAL $N mints reported"                                 ($text -match "SERIAL $N`: min")
Row "THREADS ${N}: every mint succeeded"                       (($text -match "THREADS $N`: ok $N, failed 0") -and ($text -notmatch 'THREADS mint \d+ FAILED'))
Row "PROCS ${N}: launched $N, every mint answered ok"          (($text -match "PROCS $N`: launched $N, ok $N, failed 0, no answer 0") -and ($text -notmatch 'PROCS mint \d+ FAILED'))
Row "PROCS $(2*$N): launched $(2*$N), every mint answered ok"  ($text -match "PROCS $(2*$N)`: launched $(2*$N), ok $(2*$N), failed 0, no answer 0")
Row 'logon sessions rose while the tokens were held (the peak was real)' ($text -match 'sessions at peak\s+: \d+, i\.e\. ([1-9]\d*) more than baseline')
Row 'and fell back afterwards (no leak)'                       (($text -match 'leak\s+: none') -and ($text -notmatch '^\s*LEAK:'))
Row 'the probe''s own verdict is ANSWERED'                     ($text -match 'RUN DONE - ANSWERED')

Say ''
$rows | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($rows | Where-Object { $_.Result -eq 'FAIL' }).Count
Cleanup
if ($failed) { Write-Host "probe-s4uload: FALSIFIED - $failed row(s) failed." -ForegroundColor Red; exit 1 }
Write-Host "probe-s4uload: ANSWERED - the S4U mint holds at $N and $(2*$N) concurrent, with no logon-session leak." -ForegroundColor Green
exit 0
