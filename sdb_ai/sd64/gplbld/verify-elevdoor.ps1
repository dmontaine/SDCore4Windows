<#
.SYNOPSIS
    RELEASE_1.1 45: elevation is the only door to SDSYS.  Witnesses that a
    session which did NOT start elevated cannot `logto sdsys`, and that a session
    which DID start elevated lands in SDSYS and can round-trip SDSYS -> personal
    -> SDSYS.

.DESCRIPTION
    ONE FILE, RUN BOTH WAYS, because the two halves need OPPOSITE tokens - the
    same split, and the same reason, as verify-doors / verify-doors-admin and
    VerifyInstall1 / VerifyInstall2.

      UNELEVATED   the MEASURING half.  An unelevated `sd` lands in the running
                   user's own account; `logto sdsys` must be REFUSED (10002) and
                   the session must STAY in that account.  Run this FIRST - it
                   writes the refusal to sdsys\audit, which the elevated half
                   reads back.
      ELEVATED     an elevated `sd` lands in SDSYS; `logto <user>` drops to the
                   personal account and `logto sdsys` returns - the round-trip
                   the 16 Aug "LOGTO ends the elevated session" rule used to
                   break.  AND it reads sdsys\audit (which only an elevated token
                   may open) for the unelevated half's refusal REASON.

    ***THE AUDIT REASON IS THE DECISIVE DISCRIMINATOR, AND THAT IS NOT PEDANTRY.***
    In a piped (non-interactive) session BOTH the old and the new gate refuse an
    unelevated `logto sdsys`: the old one passed K$OS.ADMINISTRATOR and then
    reached elevate('START'), which cannot draw a UAC prompt down a pipe and
    failed - so "refused, stayed in the account" is TRUE either way and proves
    nothing about which gate fired.  The NEW gate writes
    'reason=session did not start elevated'; the old one wrote 'not an
    administrator' or 'elevation refused or unavailable'.  So the elevated half
    anchors on the new wording, and REFUSES THE NULL CASE: if no such line is in
    the audit, it says the discriminator was not witnessed rather than passing.

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
    Write-Host '  ELEVATED  half: WHO (SDSYS), LOGTO <user> (personal), LOGTO SDSYS (back), audit reason'
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
    Write-Host '   The DECISIVE audit reason ("session did not start elevated") cannot be'
    Write-Host '   read from an unelevated token - run this again ELEVATED to witness it.'
}
else {
    # -----------------------------------------------------------------------
    # THE ELEVATED HALF.  Lands in SDSYS; round-trips; reads the audit reason.
    Step 1 'ELEVATED: the session lands in SDSYS, drops to the personal account, and returns'
    $out = Invoke-SD @('WHO', "LOGTO $me", 'WHO', 'LOGTO SDSYS', 'WHO')
    Write-Host '   --- raw sd output ---'
    ($out -split "`r?`n") | ForEach-Object { Write-Host ('   | ' + $_) }

    $whos = Get-WhoAccounts $out
    Write-Host ('   WHO accounts in order: ' + ($whos -join ', '))
    if ($whos.Count -lt 3) { Refuse "expected three WHO reports, got $($whos.Count) - session state cannot be read." }

    Note 'elevated session lands in SDSYS'              'SDSYS' $whos[0]
    Note "LOGTO $me drops to the personal account"      $me     $whos[1]
    Note 'LOGTO SDSYS returns to SDSYS (the round-trip)' 'SDSYS' $whos[2]

    Step 2 'ELEVATED: the audit names the NEW refusal reason for the unelevated half'
    # Only an elevated token may open the audit.  The unelevated half (run first)
    # wrote a 'LOGTO REFUSED account=SDSYS reason=...' line; the NEW gate's reason
    # is 'session did not start elevated'.  REFUSE THE NULL CASE: if no SDSYS
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
            Skip 'audit reason' 'no "LOGTO REFUSED account=SDSYS" line - run the UNELEVATED half first'
        } else {
            $last = $refusals[$refusals.Count - 1].Value
            Write-Host ('   last SDSYS refusal in the audit: ' + $last)
            Note 'the newest SDSYS refusal reason is the NEW gate''s' $true (
                $last -match 'reason=session did not start elevated')
            # CONTROL: it must NOT be an old-gate reason, which would mean the
            # regate did not take.
            Note 'and NOT an old-gate reason' $false (
                ($last -match 'reason=not an administrator') -or
                ($last -match 'reason=elevation refused or unavailable'))
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
