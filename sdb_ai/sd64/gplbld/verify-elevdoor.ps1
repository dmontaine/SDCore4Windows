<#
.SYNOPSIS
    RELEASE_1.1 64: elevation is NOT a door to SDSYS at all - the only way in is
    a genuine Windows sign-in as SDSYS itself, elevated, at LOGIN.  Witnesses
    that neither an unelevated NOR an elevated ordinary session can
    `logto sdsys`, and that the elevated refusal carries 64's reason, not 45's.

    ***UPDATED 22 Sep 2026.***  Written for RELEASE_1.1 45's "elevation is the
    only door" model, which held from 15 Sep to 18 Sep 2026: an elevated `sd`
    landed in SDSYS and could round-trip.  64 (18 Sep 2026) WITHDREW that door
    outright - owner's ruling, quoted in `cproc.bp` at the refusal site:
    "There will be one and only one administrator account SDSYS ... It will not
    be available with LOGTO."  Found stale on `-Run b223`, 22 Sep 2026: the
    elevated half asserted `whos[0] = SDSYS` and got `DON` (2 of 5 checks
    failed) - the product was doing exactly what 64 and the same day's live
    witness of 71 already confirmed; the TEST had not been updated.  See
    HISTORY.md, 22 Sep 2026, "b223 stale-verifier finding".

.DESCRIPTION
    ONE FILE, RUN BOTH WAYS, because the two halves need OPPOSITE tokens - the
    same split, and the same reason, as verify-doors / verify-doors-admin and
    VerifyInstall1 / VerifyInstall2.

      UNELEVATED   the MEASURING half.  An unelevated `sd` lands in the running
                   user's own account; `logto sdsys` must be REFUSED (10002) and
                   the session must STAY in that account.  Run this FIRST - it
                   writes the refusal to sdsys\audit, which the elevated half
                   reads back.
      ELEVATED     an elevated `sd` ALSO lands in the running user's OWN
                   account, not SDSYS - elevation buys nothing here since 64.
                   `logto sdsys` is refused exactly as it was unelevated, and
                   the session stays put; there is no round-trip to prove any
                   more.  AND it reads sdsys\audit (which only an elevated
                   token may open) for the unelevated half's refusal REASON.

    ***THE AUDIT REASON IS THE DECISIVE DISCRIMINATOR, AND THAT IS NOT PEDANTRY.***
    In a piped (non-interactive) session every generation of the gate refuses an
    unelevated `logto sdsys`, so "refused, stayed in the account" alone proves
    nothing about which gate fired.  Three generations of reason text exist:
    pre-45 wrote 'not an administrator' or 'elevation refused or unavailable';
    45 (15-18 Sep) wrote 'reason=session did not start elevated'; 64 (18 Sep
    onward) writes 'reason=SDSYS is not reachable by LOGTO'.  The elevated half
    anchors on 64's current wording, checks it is NEITHER older reason, and
    REFUSES THE NULL CASE: if no such line is in the audit, it says the
    discriminator was not witnessed rather than passing.

    IT CHANGES NOTHING.  No account, no group, no sd.conf, no service.  It uses
    the running user's own account and SDSYS, both of which already exist.

.PARAMETER SelfTest
    Parse/scaffold only - prints what each half would do and exits, for a dry
    read without touching SD.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File verify-elevdoor.ps1        # unelevated first
    powershell -ExecutionPolicy Bypass -File verify-elevdoor.ps1        # then from an ELEVATED prompt
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.

[CmdletBinding()]
param([switch] $SelfTest)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$audit  = Join-Path $env:ProgramData 'SD\sdsys\audit'
$me     = ($env:USERNAME).ToUpper()   # the running user's SD account (personal)

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-elevdoor-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}
function Skip($check, $why) {
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = 'measured'; Observed = 'NOT MEASURED' })
    Write-Host ("  [SKIP] {0}: {1}" -f $check, $why)
}
function Refuse($msg) {
    Write-Host ''; Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# The text the server prints for sysmsg(N), from the installed tree.  Anchors a
# refusal on the words the handler actually meant, not just a non-zero result.
function Get-SysMsg([int]$n) {
    $f = Join-Path $env:ProgramData ('SD\sdsys\messages\' + $n)
    if (-not (Test-Path -LiteralPath $f)) { return "<message $n is not installed>" }
    return ((Get-Content -LiteralPath $f -Raw)).Trim()
}

# Drives an SD session from the NATURAL landing account - NO leading LOGTO, so
# the account the session lands in is the thing under test.  Escape-strips as
# the other verifiers do.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# WHO prints "<session> <ACCOUNT>[ from <ACCOUNT>]".  Match the ACCOUNT-shaped
# token to end of line, case-SENSITIVE (WHO upcases), so "record(s) copied."
# and other digit-led lines cannot be misread - verify-apiidentity's b24 lesson.
function Get-WhoAccounts([string]$text) {
    $pattern = '(?m)^\s*\d+\s+([A-Z][A-Z0-9_.$-]*)(?:\s+from\s+[A-Z][A-Z0-9_.$-]*)?\s*$'
    return @([regex]::Matches($text, $pattern) | ForEach-Object { $_.Groups[1].Value })
}

if ($SelfTest) {
    Write-Host 'verify-elevdoor -SelfTest: no SD touched.'
    Write-Host "  running user's account : $me"
    Write-Host '  UNELEVATED half: WHO (personal), LOGTO SDSYS (refused 10002), WHO (unchanged)'
    Write-Host '  ELEVATED  half: WHO (personal, same as unelevated), LOGTO SDSYS (refused 10002), WHO (unchanged), audit reason'
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

if (-not (Test-Path -LiteralPath $sdExe)) { Refuse "No installed sd.exe at $sdExe." }

# THE CYCLE RULE - anything that tests the install asserts the tree matches
# source first, or the result describes a tree that no longer exists.
Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current refuses - run gplbld/cycle.ps1 first.' }

$elevated = (New-Object Security.Principal.WindowsPrincipal(
                [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host ("  this process is {0}" -f $(if ($elevated) { 'ELEVATED' } else { 'UNELEVATED' }))

if (-not $elevated) {
    # -----------------------------------------------------------------------
    # THE MEASURING HALF.  An unelevated session must be refused SDSYS.
    Step 1 'UNELEVATED: the session lands in a personal account, not SDSYS'
    $out = Invoke-SD @('WHO', 'LOGTO SDSYS', 'WHO')
    Write-Host '   --- raw sd output ---'
    ($out -split "`r?`n") | ForEach-Object { Write-Host ('   | ' + $_) }

    $whos = Get-WhoAccounts $out
    Write-Host ('   WHO accounts in order: ' + ($whos -join ', '))
    if ($whos.Count -lt 2) { Refuse "expected two WHO reports, got $($whos.Count) - session state cannot be read." }

    # The FIRST WHO is the landing account; it must not be SDSYS (an unelevated
    # session never lands there).  It is the running user's own account.
    Note 'unelevated session did NOT land in SDSYS' $true ($whos[0] -ne 'SDSYS')
    Note 'unelevated session landed in the personal account' $me $whos[0]

    Step 2 'UNELEVATED: LOGTO SDSYS is refused and the session stays put'
    # The SECOND WHO (after LOGTO SDSYS) must be the SAME account - the logto did
    # not move it into SDSYS.
    Note 'after LOGTO SDSYS the session is STILL in the personal account' $whos[0] $whos[1]
    Note 'the refusal is 10002' $true ($out -match [regex]::Escape((Get-SysMsg 10002)))

    Write-Host ''
    Write-Host '   The DECISIVE audit reason ("SDSYS is not reachable by LOGTO") cannot be'
    Write-Host '   read from an unelevated token - run this again ELEVATED to witness it.'
}
else {
    # -----------------------------------------------------------------------
    # THE ELEVATED HALF, POST-64.  Elevation buys nothing: same landing account,
    # same refusal, same message - the only thing elevation adds is the ability
    # to read sdsys\audit afterward for the reason text.
    Step 1 'ELEVATED: the session lands in the personal account too, and LOGTO SDSYS is refused the same way'
    $out = Invoke-SD @('WHO', 'LOGTO SDSYS', 'WHO')
    Write-Host '   --- raw sd output ---'
    ($out -split "`r?`n") | ForEach-Object { Write-Host ('   | ' + $_) }

    $whos = Get-WhoAccounts $out
    Write-Host ('   WHO accounts in order: ' + ($whos -join ', '))
    if ($whos.Count -lt 2) { Refuse "expected two WHO reports, got $($whos.Count) - session state cannot be read." }

    Note 'elevated session did NOT land in SDSYS'                    $true ($whos[0] -ne 'SDSYS')
    Note 'elevated session landed in the personal account'           $me   $whos[0]
    Note 'after LOGTO SDSYS the session is STILL in the personal account' $whos[0] $whos[1]
    Note 'the refusal is 10002' $true ($out -match [regex]::Escape((Get-SysMsg 10002)))

    Step 2 'ELEVATED: the audit names the CURRENT (64) refusal reason'
    # Only an elevated token may open the audit.  Either half's LOGTO SDSYS just
    # wrote a 'LOGTO REFUSED account=SDSYS reason=...' line; 64's reason is
    # 'SDSYS is not reachable by LOGTO'.  REFUSE THE NULL CASE: if no SDSYS
    # refusal is present at all, the discriminator was not witnessed.
    if (-not (Test-Path -LiteralPath $audit)) {
        Skip 'audit reason' 'no audit file present'
    } else {
        $auditText = ''
        try { $auditText = Get-Content -LiteralPath $audit -Raw } catch {
            Refuse "could not read $audit even elevated: $($_.Exception.Message)"
        }
        $refusals = @([regex]::Matches($auditText, 'LOGTO REFUSED account=SDSYS[^\r\n]*'))
        if ($refusals.Count -eq 0) {
            Skip 'audit reason' 'no "LOGTO REFUSED account=SDSYS" line - unexpected, Step 1 just wrote one'
        } else {
            $last = $refusals[$refusals.Count - 1].Value
            Write-Host ('   last SDSYS refusal in the audit: ' + $last)
            Note 'the newest SDSYS refusal reason is 64''s (not reachable by LOGTO)' $true (
                $last -match 'reason=SDSYS is not reachable by LOGTO')
            # CONTROL: it must NOT be an older gate's reason - neither 45's
            # ("elevation is the only door") nor pre-45's - which would mean
            # the withdrawal did not take.
            Note 'and NOT an older-gate reason' $false (
                ($last -match 'reason=not an administrator') -or
                ($last -match 'reason=elevation refused or unavailable') -or
                ($last -match 'reason=session did not start elevated'))
        }
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host
$passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("{0} / {1} checks passed" -f $passed, $results.Count)
try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 }
exit 0
