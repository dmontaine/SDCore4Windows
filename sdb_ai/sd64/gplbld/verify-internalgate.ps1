# verify-internalgate.ps1 - "sd -internal" is closed on an installed system, and opens
# for exactly one session against a fresh one-shot marker.
# RELEASE_1.1_FIXES.md 82 (D2'), the S4 witness for R1.  ***ELEVATED POWERSHELL.***
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-internalgate.ps1
#
# Exit 0 every check passed, 1 a check failed, 2 it could not run (never a FAIL).
#
# WHAT IT MEASURES, AND WHY EACH LEG.  LOGIN's K$INTERNAL branch (sdsys/gpl.bp/login,
# internal.gate) admits an "sd -internal" session only while a marker file named
# $internal exists in the SDSYS directory and is fresh, and DELETES it on admission.
# The owner's ruling, 20 Sep 2026: the developer door is closed on a delivered system and
# opened only by whoever legitimately starts an internal session.  The legs:
#   A. no marker              - R1: "sd -internal WHO" gets NO session.  Three things, all
#                               required: no WHO answer, the "Connection terminated" text,
#                               and an audit record saying "no internal marker".
#   B. a fresh marker         - the CONTROL that makes A mean something: with the marker the
#                               same command IS admitted (WHO answers as SDSYS), the marker
#                               is CONSUMED, and the audit says who wrote it.  Without B, A
#                               passes on a machine where "sd -internal" is simply broken.
#   C. single use             - the very next "sd -internal WHO" is refused again: one
#                               marker, one session (R3's "single-use").
#   D. an expired marker      - written, then aged 11 minutes: refused, and CONSUMED, with
#                               "expired" in the audit.  Expiry is the weaker half and is
#                               measured anyway, because a bound nobody has fired is not one.
#   E. recovery               - a fresh marker after the expired one is admitted: the
#                               refusal wedged nothing.
#   F. the seat's door (R5)   - the SDSYS seat's -Internal switch writes its OWN marker and
#                               gets a session; that is the door every converted verifier
#                               that needs sd -internal now uses.
#   G. nothing left behind    - no $internal and no $internal.now in the SDSYS directory.
#
# ***WHAT IT DOES NOT PROVE, SAID PLAINLY.***  The marker is a speed bump for an
# administrator, not a boundary: an administrator can write the file by hand, and this
# script does exactly that.  It measures the DOOR, not a wall.
#
# ***IT NEEDS SDSYS SIGNED IN for leg F only*** (the seat, sdsys-seat.ps1).  The gate legs
# A-E and G need nothing but an elevated shell.
#
# BOUNDED: every session is a process killed after the timeout.

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-internalgate: refusing - see assert-current above'
    exit 2
}

$wpr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $wpr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-internalgate: this needs an ELEVATED session and this one is not.'
    Write-Output '  "sd -internal" refuses an unelevated session before LOGIN is reached, so every'
    Write-Output '  leg here would read as refused for the wrong reason.'
    exit 2
}

. (Join-Path $PSScriptRoot 'internal-marker.ps1')
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')

$appDir = Join-Path $env:ProgramFiles 'SD'
$sdExe  = Join-Path $appDir 'usr\bin\sd.exe'
$data   = Join-Path $env:ProgramData 'SD'
$sdsys  = Join-Path $data 'sdsys'
$audit  = Join-Path $sdsys 'audit'
$marker = Join-Path $sdsys '$internal'
$stamp  = Join-Path $sdsys '$internal.now'
$msg5024 = Join-Path $sdsys 'messages\5024'

Write-Output '===== verify-internalgate.ps1 ====='
Write-Output ("  sd.exe : " + $sdExe)
Write-Output ("  sdsys  : " + $sdsys)
Write-Output ("  marker : " + $marker)
Write-Output ("  audit  : " + $audit)
foreach ($p in @($sdExe, $sdsys, $audit, $msg5024)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Output ("verify-internalgate: missing " + $p); exit 2 }
}
# The refusal wording is READ from the install, not typed here, so a reworded message fails
# the leg that names it instead of the script going blind.
$termText = ((Get-Content -LiteralPath $msg5024 -Raw) -replace '\s+', ' ').Trim()
Write-Output ("  5024   : '" + $termText + "'  (what a refused session prints)")
if ($termText -eq '') { Write-Output 'verify-internalgate: message 5024 is empty - leg A would have nothing to look for'; exit 2 }

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ("  [PASS] " + $name) }
    else { $script:fail++; Write-Output ("  [FAIL] " + $name + $(if ($detail) { "  ->  $detail" } else { '' })) }
}

# Read the audit trail with FileShare::ReadWrite - the daemon holds it open across its own
# writes - lifted from verify-privundetermined.ps1.
function Get-AuditText {
    $fs = [System.IO.File]::Open($audit, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}
# What was written since $before, or $null when the file was trimmed and the old text is no
# longer a prefix - refused rather than guessed at.
function Get-AuditDelta([string]$before) {
    $after = Get-AuditText
    if ($after.Length -ge $before.Length -and $after.StartsWith($before, [System.StringComparison]::Ordinal)) {
        return $after.Substring($before.Length)
    }
    return $null
}

# One "sd -internal <args>" session from THIS elevated shell.  NEVER "-Wait" on the streams:
# sdwind inherits sd's handles and outlives it (PROJECT_STATUS.md 6).  Returns the text and
# whether it finished; prints nothing (a function's Write-Output joins its return value).
function Invoke-InternalSession([string[]]$Cmd, [int]$TimeoutSec = 60) {
    $so = Join-Path $env:TEMP ("sd-intgate-out-$PID.txt")
    $se = Join-Path $env:TEMP ("sd-intgate-err-$PID.txt")
    $args2 = @('-internal') + $Cmd
    $p = Start-Process -FilePath $sdExe -ArgumentList $args2 -NoNewWindow -PassThru `
                       -RedirectStandardOutput $so -RedirectStandardError $se
    $null = $p.Handle
    $done = $p.WaitForExit($TimeoutSec * 1000)
    if (-not $done) { try { $p.Kill() } catch { } }
    $text = ''
    foreach ($f in @($so, $se)) {
        if (Test-Path -LiteralPath $f) { $text += (Get-Content -LiteralPath $f -Raw); Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    return [pscustomobject]@{ Text = "$text"; Done = $done }
}
function Show([string]$label, [string]$text) {
    Write-Output ("  --- " + $label + " ---")
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '^\s*:?\s*$|Ladybridge|free software|welcome to modify|conditions\.  For|^SD Core for') { continue }
        Write-Output ("    " + $l)
    }
}

# THE ANSWER TO "WHO", ANCHORED ON THE SUCCESS WORDING: a line that is a session number and the
# account name.  The echoed command ("WHO") and the refusal text cannot match it.
$whoRx = '(?m)^\s*\d+\s+SDSYS\b'

function Clear-Leftovers {
    foreach ($p in @($marker, $stamp)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue } }
}

$exit = 2
try {
    # ---- the seat's internal door FIRST, so a missing SDSYS session is exit 2 before anything is done ----
    Write-Output '  --- proving the SDSYS seat, through its internal door (leg F needs it) ---'
    Assert-SdSeat -Label 'verify-internalgate' -Internal

    # ---- start clean: a marker left by anything else would be consumed by leg A and read as admission ----
    if (Test-Path -LiteralPath $marker) {
        Write-Output ("  a marker was already there (" + (Get-Content -LiteralPath $marker -TotalCount 1) + ") - removed, so leg A starts closed")
    }
    Clear-Leftovers
    Row 'start: no marker and no scratch file in the SDSYS directory' (-not (Test-Path -LiteralPath $marker) -and -not (Test-Path -LiteralPath $stamp))

    # ---- A. no marker: the door is closed ----------------------------------
    Write-Output ''
    Write-Output '=== A. NO marker: "sd -internal WHO" gets no session (R1) ==========='
    $before = Get-AuditText
    $a = Invoke-InternalSession @('WHO')
    Show 'sd -internal WHO said' $a.Text
    $ad = Get-AuditDelta $before
    Row 'A: the session finished (a refusal is not a hang)' $a.Done
    Row 'A: WHO was NOT answered - no session was opened' ($a.Text -notmatch $whoRx) $a.Text
    Row ("A: the refusal text SD prints was shown ('" + $termText + "')") ($a.Text -match [regex]::Escape($termText)) $a.Text
    Row 'A: the audit trail names the reason: no internal marker' (($null -ne $ad) -and ($ad -match 'LOGIN REFUSED account=SDSYS reason=no internal marker')) "delta: $ad"
    Row 'A: and no admission was recorded' (($null -ne $ad) -and ($ad -notmatch 'INTERNAL SESSION ADMITTED')) "delta: $ad"

    # ---- B. a fresh marker: the CONTROL -------------------------------------
    Write-Output ''
    Write-Output '=== B. a FRESH marker: the same command IS admitted, and the marker is consumed ==='
    $wrote = Set-SdInternalMarker -SdsysDir $sdsys -Writer 'verify-internalgate'
    Row 'B: the marker was written' $wrote
    $before = Get-AuditText
    $b = Invoke-InternalSession @('WHO')
    Show 'sd -internal WHO said' $b.Text
    $ad = Get-AuditDelta $before
    Row 'B: WHO answered as SDSYS - the session was opened' ($b.Text -match $whoRx) $b.Text
    Row 'B: and the refusal text was NOT shown' ($b.Text -notmatch [regex]::Escape($termText)) $b.Text
    Row 'B: the marker was CONSUMED (LOGIN deletes it on admission)' (-not (Test-Path -LiteralPath $marker))
    Row 'B: the audit says who wrote it and how old it was' (($null -ne $ad) -and ($ad -match 'INTERNAL SESSION ADMITTED account=SDSYS writer=verify-internalgate pid=\d+ .* age=-?\d+')) "delta: $ad"

    # ---- C. single use -------------------------------------------------------
    Write-Output ''
    Write-Output '=== C. one marker, ONE session: the next one is refused ==='
    $before = Get-AuditText
    $c = Invoke-InternalSession @('WHO')
    Show 'sd -internal WHO said' $c.Text
    $ad = Get-AuditDelta $before
    Row 'C: WHO was NOT answered' ($c.Text -notmatch $whoRx) $c.Text
    Row 'C: refused for the same reason as A (no marker)' (($null -ne $ad) -and ($ad -match 'reason=no internal marker')) "delta: $ad"

    # ---- D. an expired marker -------------------------------------------------
    Write-Output ''
    Write-Output '=== D. an EXPIRED marker (aged 11 minutes) is refused and consumed ==='
    $null = Set-SdInternalMarker -SdsysDir $sdsys -Writer 'verify-internalgate-aged'
    (Get-Item -LiteralPath $marker).LastWriteTime = (Get-Date).AddMinutes(-11)
    $aged = [int]((Get-Date) - (Get-Item -LiteralPath $marker).LastWriteTime).TotalSeconds
    Write-Output ("  marker aged " + $aged + " s (LOGIN's limit is 600)")
    Row 'D: the marker really is older than 600 s (the fixture is what it claims)' ($aged -gt 600) "aged $aged"
    $before = Get-AuditText
    $d = Invoke-InternalSession @('WHO')
    Show 'sd -internal WHO said' $d.Text
    $ad = Get-AuditDelta $before
    Row 'D: WHO was NOT answered' ($d.Text -notmatch $whoRx) $d.Text
    Row 'D: the audit names the reason: expired' (($null -ne $ad) -and ($ad -match 'reason=the internal marker had expired')) "delta: $ad"
    Row 'D: the expired marker was CONSUMED all the same' (-not (Test-Path -LiteralPath $marker))

    # ---- E. recovery -----------------------------------------------------------
    Write-Output ''
    Write-Output '=== E. a fresh marker AFTER the expired one is admitted ==='
    $null = Set-SdInternalMarker -SdsysDir $sdsys -Writer 'verify-internalgate'
    $e = Invoke-InternalSession @('WHO')
    Show 'sd -internal WHO said' $e.Text
    Row 'E: WHO answered as SDSYS - nothing was wedged by the refusal' ($e.Text -match $whoRx) $e.Text

    # ---- F. the seat's own door -------------------------------------------------
    Write-Output ''
    Write-Output '=== F. the SDSYS seat''s -Internal door writes its own marker and gets a session (R5) ==='
    $f = Invoke-SdViaSeat -Commands @('WHO') -Internal -TimeoutSec 120
    Write-Output ("  seat: Ok={0}  {1}" -f $f.Ok, $f.Detail)
    if ($f.Ok) { Show 'seat WHO said' $f.Text } else { Write-Output ("  why: " + $f.Why) }
    Row 'F: the seat ran' $f.Ok $f.Why
    Row 'F: WHO answered as SDSYS through the seat''s internal door' ($f.Ok -and ($f.Text -match $whoRx)) $f.Text
    Row 'F: the seat left no marker behind' (-not (Test-Path -LiteralPath $marker))

    # ---- G. nothing left behind ---------------------------------------------------------------
    # JUDGED HERE, BEFORE THE SWEEP BELOW: a check made after Clear-Leftovers would pass on a run
    # that leaked, which is the vacuous pass this file exists to refuse.  $internal.now is the
    # scratch file LOGIN writes to read "now" off the filesystem's clock, and it must delete it.
    Write-Output ''
    Write-Output '=== G. nothing left behind ==='
    Row 'G: no $internal in the SDSYS directory' (-not (Test-Path -LiteralPath $marker))
    Row 'G: no $internal.now (LOGIN''s scratch file for the age) in the SDSYS directory' (-not (Test-Path -LiteralPath $stamp))

    $exit = $(if ($fail -eq 0) { 0 } else { 1 })
}
finally {
    Write-Output ''
    Write-Output '  --- cleanup ---'
    Clear-Leftovers
}

Write-Output ''
Write-Output ("verify-internalgate: $pass passed, $fail failed")
if (($pass + $fail) -eq 0 -and $exit -ne 2) { Write-Output 'verify-internalgate: COULD NOT RUN - no check ran'; exit 2 }
if ($fail -gt 0 -and $exit -eq 0) { $exit = 1 }
if ($exit -eq 0) { Write-Output 'verify-internalgate: PASSED - "sd -internal" is closed without a marker, opens for exactly one session against a fresh one, and refuses an expired one.' }
exit $exit
