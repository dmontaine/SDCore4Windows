<#
.SYNOPSIS
    Is SDSYS ADMITTED over SDConnectLocal to an elevated session owned by the
    Windows SDSYS account, and does that session hold administrator rights?

.DESCRIPTION
    RELEASE_1.1 101.  ***THIS IS THE MIRROR OF verify-localconnect.ps1 AND THE
    TWO ARE A PAIR.***  That one runs UNELEVATED as an ordinary user and proves
    SDSYS is REFUSED; this one runs ELEVATED as SDSYS and proves it is ADMITTED.
    Neither means much alone - a route that admitted everybody would pass this
    outright and fail that one's control - so a change to vb.account's SDSYS arm
    should run both.

    WHY IT IS A SEPARATE SCRIPT AND NOT A SWITCH ON THE OTHER ONE.  They need
    OPPOSITE principals, and each refuses the other's.  verify-localconnect
    exits 2 when it is elevated, deliberately, because the identity it measures
    is the process owner's; folding them together would mean one script that
    could not state what it required.

    ***WHAT IT CHECKS BEFORE IT MEASURES ANYTHING, AND WHY REFUSING IS THE
    POINT.***  A pass from the wrong principal measures a different route and is
    the vacuous pass PROJECT_STATUS.md 0 forbids.  So:

      elevated       required.  kernel.c seeds USR_ADMIN from IsElevated() AND
                     connection_type # CN_SOCKET AND IsInteractive(); an
                     unelevated run fails the first term and would report the
                     administrator verb refused, which looks exactly like the
                     IsInteractive() answer this probe exists to find.
      owner = SDSYS  required.  vb.account tests the PROCESS OWNER, so any other
                     account is refused by design and the run would say nothing.

    Both are read from the token here rather than taken on trust, and both are
    printed, so a transcript always names the principal its verdict belongs to.

    ***AND IT IS NOT IN EITHER RUNNER, WHICH IS A FACT ABOUT THE SUITE RATHER
    THAN AN OVERSIGHT.***  VerifyInstall1 is unelevated and VerifyInstall2's
    elevated half runs as whoever started it; neither can promise a session
    owned by SDSYS.  §4.0.1 records why an agent shell cannot make one either.
    So this is run by hand, from the SDSYS desktop, and the suite does not claim
    to cover the admit side.

.PARAMETER Exe
    The probe binary.  "make sd" builds it; there is no reason to override this
    except to test this script.

.PARAMETER AcceptStaleTree
    Run even though assert-current says the tree is stale, and SAY SO in the
    verdict.  ***THIS IS NOT A CONVENIENCE AND IT IS NOT FOR ROUTINE USE.***
    CLAUDE.md allows a stale warning to be overridden by naming the warning and
    why it does not apply - and the ONLY case that fits here is a stale file
    that cannot affect what this probe measures.  What it measures is APISRVR's
    installed BASIC, reached through the installed sd.exe and sdclilib.dll; a
    change to, say, gplsrc/sdclilib/Makefile that only adds a target for a TEST
    binary touches none of those.  A change to a gpl.bp program, to messages, or
    to the client library itself does, and then this switch is simply a way to
    publish a false result.
    ***READ WHAT assert-current NAMED BEFORE USING IT***: the script prints
    every stale file, and the verdict carries the caveat so a transcript can
    never be mistaken for a clean run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File verify-sdsyslocal.ps1
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.  The convention is stated here because six API verifiers
# once left it to be inferred and a "could not run" was read as a pass -
# PRE_RELEASE_FIXES 151.

# ***NEVER PUT $PSScriptRoot IN A param() DEFAULT.  MEASURED 4 Sep 2026.***
# With [CmdletBinding()] present it is EMPTY during parameter binding when the
# script is run as a CHILD PROCESS - "powershell.exe -File <script>" - and
# populated when it is run IN-PROCESS with "& <script>".  verify-localconnect.ps1
# carries the full measurement; the rule is copied, not re-derived.
[CmdletBinding()]
param(
    [string] $Exe = '',
    [switch] $AcceptStaleTree
)

$ErrorActionPreference = 'Stop'

function Say($msg) { Write-Host $msg }

function Refuse($msg) {
    Write-Host ''
    Write-Host "verify-sdsyslocal: CANNOT RUN - $msg"
    Write-Host 'Nothing was measured.'
    exit 2
}

function Fail($msg) {
    Write-Host ''
    Write-Host "verify-sdsyslocal: FAILED - $msg"
    exit 1
}

Say '=== verify-sdsyslocal: SDSYS is admitted over SDConnectLocal ==='

if ($Exe -eq '') {
    $Exe = Join-Path $PSScriptRoot '..\gplsrc\sdclilib\localtest\local-sdsys-probe.exe'
}

# THE PRINCIPAL, READ FROM THE TOKEN AND PRINTED.  Rule 1 of the instrument
# section: say what was actually used, not what was intended.
$id       = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr       = New-Object Security.Principal.WindowsPrincipal($id)
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$who      = $id.Name
$bare     = ($who -split '\\')[-1]

Say ''
Say '--- who is running this'
Say ("  caller    : " + $who)
Say ("  elevated  : " + $elevated)
Say ("  probe     : " + $Exe)

if (-not (Test-Path -LiteralPath $Exe)) {
    Refuse ("the probe binary is not there - build it with `"make sd`", or `"make all`" in gplsrc/sdclilib. Looked for: " + $Exe)
}

# THE TWO REFUSALS, BEFORE ANYTHING CONNECTS.
if (-not $elevated) {
    Refuse 'this session is NOT elevated. SDSYS needs an elevated session (LOGIN''s landing case and kernel.c both), so an unelevated run would report the administrator verb refused for a reason that has nothing to do with the route.'
}
if ($bare -ne 'SDSYS') {
    Refuse ("this session is owned by '" + $bare + "', not SDSYS. vb.account tests the PROCESS OWNER, so any other account is refused by design and this run would measure nothing. Sign in as the Windows SDSYS account and run it from an elevated prompt there.")
}

# assert-current, for the reason every other installed-tree verifier calls it:
# a result from a tree that does not match source is void, not "probably valid".
$assert = Join-Path $PSScriptRoot 'assert-current.ps1'
$staleAccepted = $false
if (Test-Path -LiteralPath $assert) {
    Say ''
    Say '--- assert-current'
    & $assert
    if ($LASTEXITCODE -ne 0) {
        if (-not $AcceptStaleTree) {
            Refuse 'assert-current says the installed tree does not match source. Run a cycle first, or pass -AcceptStaleTree if you have read the stale files above and none of them can affect what this measures (see this script''s header).'
        }
        # SAID HERE AND AGAIN IN THE VERDICT, deliberately.  A caveat printed
        # once, 200 lines above the answer, is one a reader scrolls past.
        $staleAccepted = $true
        Say ''
        Say '  *** -AcceptStaleTree WAS GIVEN.  assert-current REFUSED above and this run'
        Say '  *** continued anyway.  The stale files it named are listed in its output.'
        Say '  *** This result is only as good as the claim that none of them reach'
        Say '  *** APISRVR''s installed BASIC, sd.exe or sdclilib.dll.'
    }
} else {
    Refuse ("assert-current.ps1 is not beside this script (looked for " + $assert + ")")
}

# RUN IT FROM ITS OWN DIRECTORY WITH THE INSTALLED bin ON PATH.  The binary sits
# in localtest/ so that Windows' "executable's own directory first" search finds
# NO sdclilib.dll and NO sd.exe beside it, and falls through to this PATH - which
# is how the INSTALLED pair gets tested rather than the freshly built library.
# gplsrc/sdclilib/Makefile's check-local carries the full reasoning.
$exeFull = (Resolve-Path -LiteralPath $Exe).Path
$exeDir  = Split-Path -Parent $exeFull
$sdBin   = Join-Path $env:ProgramFiles 'SD\usr\bin'

Say ''
Say '--- running the probe'
Say ("  from      : " + $exeDir)
Say ("  PATH head : " + $sdBin)

if (-not (Test-Path -LiteralPath $sdBin)) {
    Refuse ("the installed SD bin directory is not there: " + $sdBin)
}

$oldPath = $env:PATH
$oldCwd  = (Get-Location).Path
try {
    $env:PATH = $sdBin + ';' + $env:PATH
    Set-Location -LiteralPath $exeDir
    $out = & $exeFull $who 2>&1
    $code = $LASTEXITCODE
} finally {
    $env:PATH = $oldPath
    Set-Location -LiteralPath $oldCwd
}

Say '  --- the probe said ---'
foreach ($line in $out) { Say ("  | " + $line) }
Say '  --- end ---'
Say ("  exit code " + $code)

$text = ($out | Out-String)

# ANCHORED ON THE SUCCESS WORDING, with the failure wordings as disqualifiers.
# The exit code alone is not the check: a binary that could not start also
# produces a non-zero code, and one that printed nothing would leave a bare 0
# looking like a pass.
$sawPass = $text -match 'PASS: SDSYS admitted over SDConnectLocal'
$sawFail = $text -match 'FAIL:'

Say ''
Say '--- verdict'
Say ("  exit 0                   : " + ($code -eq 0))
Say ("  success wording present  : " + $sawPass)
Say ("  no FAIL wording present  : " + (-not $sawFail))

if ($code -eq 4) {
    Fail 'SDSYS was entered but the session is NOT an administrator (message 2001). That is kernel.c''s USR_ADMIN seed: IsElevated() and CN_SOCKET both hold for a ConnectLocal child, so IsInteractive() is the term that answered false. The route admits but carries no rights.'
}
if ($code -eq 1) {
    Fail 'SDSYS was REFUSED over SDConnectLocal. Read sdsys/audit for "branch=4 sdsys.not.local.elevated" - it names which of the three terms failed.'
}
if ($code -ne 0) {
    Fail ("the probe exited " + $code + " - read its output above; its header lists what each code means.")
}
if (-not $sawPass) {
    Fail 'the probe exited 0 but did not print its success line. A zero with nothing behind it is not a result.'
}
if ($sawFail) {
    Fail 'the probe exited 0 but its output carries FAIL wording. Read it above before believing the code.'
}

Say ''
if ($staleAccepted) {
    Say 'verify-sdsyslocal: PASSED ON A STALE TREE - SDSYS was admitted over'
    Say 'SDConnectLocal, WHO named SDSYS, and an administrator-only verb ran.'
    Say '*** assert-current REFUSED this tree and -AcceptStaleTree overrode it, so'
    Say '*** this is NOT a clean witness. Re-run it after the next cycle.'
} else {
    Say 'verify-sdsyslocal: PASSED - SDSYS was admitted over SDConnectLocal, WHO named'
    Say 'SDSYS, and an administrator-only verb ran. The local route carries an'
    Say 'administrator session.'
}
exit 0
