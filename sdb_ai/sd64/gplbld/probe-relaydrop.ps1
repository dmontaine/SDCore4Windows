<#
.SYNOPSIS
    Drives probe-relaydrop.c: can a LocalSystem daemon run a CYGWIN child as a
    dedicated BARE account - the Linux setuid("nobody") shape for the TLS relay?

.DESCRIPTION
    RELEASE_1.1 43's successor: option 3c is dead (probe-svcimp - a session
    cannot ADOPT without SeTcb), so the relay/session split replaces it.  The
    relay never adopts; it only needs to DROP to a bare identity.  On Windows
    that is a SPAWN, not a fork()+setuid: the daemon (LocalSystem, holds SeTcb
    and SeAssignPrimaryToken) S4U-mints the relay account's token, strips it
    (every privilege removed, Low integrity) and CreateProcessAsUser()s the
    relay under it.

    THIS IS THE FOUNDATIONAL STEP, not the whole split.  It answers ONE
    question: does a Cygwin/MSYS2 program even RUN under such a token?  The
    socket handover (the relay must be handed the accepted connection) is the
    NEXT probe.

    A throwaway unprivileged local account is created and removed; the real
    accounts are never touched.  The parent runs as SYSTEM via a scheduled
    task, the shape the other probes use.

    ITERATION 3 (16 Sep 26): the socket is used through NATIVE Winsock in the
    child, and exchanged both ways over two Cygwin pipe()s whose far ends the
    child inherits as duplicated handles - the Linux per-connection shape.
    See the .c header.

    Build, from gplbld in MSYS2's bash:
      gcc -O2 -Wall -o probe-relaydrop.exe probe-relaydrop.c -lsecur32 -ladvapi32 -lws2_32 -luserenv

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File probe-relaydrop.ps1
#>

# Exit 0 the question was answered, 1 the claim was falsified, 2 could not run.

[CmdletBinding()]
param(
    [string] $Account = 'sdrelayprobe',
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe     = Join-Path $Gplbld 'probe-relaydrop.exe'
$MsysDll = 'C:\msys64\usr\bin\msys-2.0.dll'
$Task    = 'relaydropparent'
$Stage   = 'C:\ProgramData\relaydrop-run'

function Say($m, $ForegroundColor) {
    if ($ForegroundColor) { Write-Host $m -ForegroundColor $ForegroundColor } else { Write-Host $m }
}
function Step($m)   { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Refuse($m) { Write-Host ''; Write-Host "COULD NOT RUN: $m" -ForegroundColor Yellow; Cleanup; exit 2 }
function Fail($m)   { Write-Host ''; Write-Host "FALSIFIED: $m" -ForegroundColor Red; Cleanup; exit 1 }

function Cleanup {
    if ($script:Keeping) { Say "  -Keep: leaving $Account, $Task and $Stage in place"; return }
    try {
        $t = & schtasks.exe /query /tn $Task 2>$null
        if ($t) { $null = & schtasks.exe /delete /tn $Task /f 2>$null }
    } catch { }
    if ($script:CreatedAccount) {
        try { Remove-LocalUser -Name $Account -ErrorAction SilentlyContinue } catch { }
    }
    try {
        if (Test-Path -LiteralPath $Stage) {
            Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}
$script:Keeping = [bool]$Keep
$script:CreatedAccount = $false

trap {
    Write-Host ''
    Write-Host "UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Cleanup
    exit 3
}

# ---------------------------------------------------------------------------
Step 'Preconditions'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
Say "  running as        : $($id.Name)"
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ''; Write-Host 'COULD NOT RUN: this needs an ELEVATED PowerShell - it creates an account and a SYSTEM task.' -ForegroundColor Yellow
    exit 2
}
if (-not (Test-Path -LiteralPath $Exe))     { Write-Host "COULD NOT RUN: no $Exe - build it first (see the .c header)." -ForegroundColor Yellow; exit 2 }
if (-not (Test-Path -LiteralPath $MsysDll)) { Write-Host "COULD NOT RUN: no $MsysDll - the child cannot start without it." -ForegroundColor Yellow; exit 2 }

# ---------------------------------------------------------------------------
Step 'The throwaway bare account'

if (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue) {
    Say "  $Account already exists - using it, and NOT removing it in cleanup"
} else {
    # A random password satisfies New-LocalUser; it is never used - the mint is
    # S4U (password-free), which is the point.  No group membership: as bare as
    # the account model allows.
    $pw = [Guid]::NewGuid().ToString('N') + 'Aa1!'
    $sec = ConvertTo-SecureString $pw -AsPlainText -Force
    $null = New-LocalUser -Name $Account -Password $sec -PasswordNeverExpires `
        -AccountNeverExpires -UserMayNotChangePassword `
        -Description 'throwaway relay-drop probe account' -ErrorAction Stop
    $script:CreatedAccount = $true
    Say "  created           : $Account (no group membership, random unused password)"
}

# ---------------------------------------------------------------------------
Step 'Staging the binary where the bare account can reach it'

if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
$null = New-Item -ItemType Directory -Path $Stage -Force
Copy-Item -LiteralPath $Exe     -Destination $Stage -Force
Copy-Item -LiteralPath $MsysDll -Destination $Stage -Force

$null = & icacls.exe $Stage /grant "*S-1-5-18:(OI)(CI)F" /T
if ($LASTEXITCODE -ne 0) { Refuse "icacls could not grant SYSTEM on $Stage." }
$null = & icacls.exe $Stage /grant "${Account}:(OI)(CI)M" /T
if ($LASTEXITCODE -ne 0) { Refuse "icacls could not grant $Account on $Stage." }
# Medium integrity, like the proven svcimp harness - the SYSTEM parent writes
# parent.log here.  The Low-integrity drop (which would force a Low output dir)
# is the next iteration, once the account switch is confirmed.
Say "  staged            : $Stage (SYSTEM full; $Account modify; Medium integrity)"

# ---------------------------------------------------------------------------
Step 'Running the parent as LocalSystem'

$ptr = '"' + (Join-Path $Stage 'probe-relaydrop.exe') + '" --parent "' + $Stage + '" ' + $Account
$out = & schtasks.exe /create /tn $Task /tr $ptr /sc once /st 23:59 /ru SYSTEM /rl HIGHEST /f
if ($LASTEXITCODE -ne 0) { Refuse "schtasks /create failed - $($out -join ' ')" }
$out = & schtasks.exe /run /tn $Task
if ($LASTEXITCODE -ne 0) { Refuse "schtasks /run failed - $($out -join ' ')" }
Say '  parent            : started as SYSTEM'

$pLog = Join-Path $Stage 'parent.log'
$cLog = Join-Path $Stage 'child.log'
$deadline = (Get-Date).AddSeconds(45)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path -LiteralPath $pLog) -and
        (Select-String -LiteralPath $pLog -Pattern 'PARENT DONE|REFUSED' -Quiet)) { break }
    Start-Sleep -Milliseconds 500
}

# ---------------------------------------------------------------------------
Step 'What each side did'

foreach ($pair in @(@('parent', $pLog), @('child', $cLog))) {
    Say ''
    Say "  --- $($pair[0]).log ---"
    if (Test-Path -LiteralPath $pair[1]) {
        Get-Content -LiteralPath $pair[1] | ForEach-Object { Say "  | $_" }
    } else { Say '  | <absent>' }
}

if (-not (Test-Path -LiteralPath $pLog)) {
    Say ''
    Say '  --- the SYSTEM task produced no log; its own result (before cleanup): ---'
    $info = & schtasks.exe /query /tn $Task /fo LIST /v 2>&1
    ($info | Select-String -Pattern 'Last Result|Last Run Time|Status|Task To Run') |
        ForEach-Object { Say "  | $($_.ToString().Trim())" }
    Say '  --- stage directory now holds: ---'
    if (Test-Path -LiteralPath $Stage) {
        Get-ChildItem -LiteralPath $Stage -Force | ForEach-Object { Say "  | $($_.Name)" }
    } else { Say '  | <stage gone>' }
    Refuse 'no parent log - read the task Last Result above (0x0 = ran clean but wrote nothing; nonzero = a launch/run error).'
}
$p = Get-Content -LiteralPath $pLog -Raw
if ($p -match 'REFUSED') { Refuse 'the parent refused - its reason is above (likely the mint, the strip, or CreateProcessAsUser).' }
if (-not (Test-Path -LiteralPath $cLog)) {
    Refuse 'the child produced no log: it did not start, or could not write even a Low-integrity file. The parent''s child-exit-code line above is the next clue.'
}

# ---------------------------------------------------------------------------
Step 'Verdict'

$c = Get-Content -LiteralPath $cLog -Raw
$ranAs   = if ($c -match '(?m)running as\s*:\s*(.+?)\s*$') { $Matches[1].Trim() } else { '' }
$privCnt = if ($c -match '(?m)privilege count\s*:\s*(\d+)') { [int]$Matches[1] } else { -1 }
$integ   = if ($c -match '(?m)integrity level\s*:\s*(\S+)') { $Matches[1] } else { '' }
$owner   = if ($c -match '(?m)file I/O owner\s*:\s*(.+?)\s*$') { $Matches[1].Trim() } else { '' }

Say "  child ran as      : $(if ($ranAs) { $ranAs } else { '<not reported>' })"
Say "  privilege count   : $(if ($privCnt -ge 0) { $privCnt } else { '<not reported>' })"
Say "  integrity level   : $(if ($integ) { $integ } else { '<not reported>' })"
Say "  file I/O owner    : $(if ($owner) { $owner } else { '<not reported>' })"

if (-not $ranAs -or $privCnt -lt 0) { Refuse 'the child log is missing the identity or privilege lines.' }

if ($ranAs -like '*\SYSTEM' -or $ranAs -like 'NT AUTHORITY\SYSTEM') {
    Fail "the child ran as $ranAs, not the bare account - the strip/spawn did not change identity. Tier 2's mechanism does not hold as written."
}
if ($ranAs -notlike "*\$Account") {
    Fail "the child ran as $ranAs, which is neither SYSTEM nor $Account - unexpected; read the log."
}
if ($privCnt -ne 0) {
    Fail "the child ran as $ranAs but still holds $privCnt privilege(s) - the strip did not take."
}

# The FOUNDATION (the account switch) must hold first; integrity is Medium by
# design this iteration (the Low drop is deferred).
if ($owner -notlike "*\$Account") {
    Fail "the child ran as $ranAs, $privCnt priv(s), but the file it created is owned by '$owner', not $Account - the account switch is wrong."
}

# The CRUX: did the handed-over socket round-trip?  parent.log ($p) reports the
# parent's side, child.log ($c) the adopt and the bytes it read.
# Iteration 3: the child uses the SOCKET through native Winsock and relays what
# it read over an inherited pipe that the parent reads as a Cygwin fd.  Each leg
# is anchored on wording printed only on its success path, and a leg the child
# never attempted is refused rather than scored.
$sread     = if ($c -match '(?m)socket read\s*:\s*(.+?)\s*$')  { $Matches[1].Trim() } else { '<not reported>' }
$pwrite    = if ($c -match '(?m)pipe write\s*:\s*(.+?)\s*$')   { $Matches[1].Trim() } else { '<not reported>' }
$cread     = if ($c -match '(?m)pipe read\s*:\s*(.+?)\s*$')    { $Matches[1].Trim() } else { '<not reported>' }
$pread     = if ($p -match '(?m)pipe read \(cygwin\)\s*:\s*(.+?)\s*$') { $Matches[1].Trim() } else { '<not reported>' }
$roundTrip = [bool]($p -match 'ROUND TRIP WORKED')
$piped     = [bool]($p -match 'THE PIPE CARRIED')
Say "  socket read (child, native): $sread"
Say "  pipe read   (child, native): $cread"
Say "  pipe write  (child)        : $pwrite"
Say "  pipe read   (parent, cygwin): $pread"
Say "  socket round trip          : $(if ($roundTrip) { 'WORKED' } else { 'did NOT' })"
Say "  pipe channel               : $(if ($piped) { 'WORKED' } else { 'did NOT' })"

if ($sread -like 'NOT ATTEMPTED*' -or $sread -eq '<not reported>') {
    Refuse 'the child never attempted the socket leg - the handles did not reach its command line.'
}

Say ''
if ($roundTrip -and $piped -and ($sread -like '*PING-from-parent*')) {
    Say "ANSWERED (FULL): the bare account '$Account' child read the inherited socket" -ForegroundColor Green
    Say "  through native Winsock, answered on it, and exchanged bytes BOTH WAYS with"
    Say "  a Cygwin parent over inherited duplicates of Cygwin pipe() ends.  The Linux"
    Say "  per-connection shape - relay holds the connection, private channel to sd -"
    Say "  has a working Windows handover.  (Integrity Medium; the Low drop is next.)"
    Cleanup
    exit 0
}

Say "PARTIAL: the account switch HOLDS (child ran as $Account, 0 privileges, file" -ForegroundColor Yellow
Say "  owned by it), but socket=$(if ($roundTrip) { 'ok' } else { 'FAILED' }), pipe=$(if ($piped) { 'ok' } else { 'FAILED' })."
Say "  Read both logs above for which call refused."
Cleanup
exit 2
