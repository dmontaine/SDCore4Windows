<#
.SYNOPSIS
    Does SDConnectLocal carry a session, and does its grant check refuse an
    account the caller is not granted?

.DESCRIPTION
    THE POINT IS THAT NOTHING ELSE TESTS THIS PATH.  PRE_RELEASE_FIXES 163.
    SDConnectLocal is a SECOND transport - a named pipe and a spawned sd.exe,
    not a socket - and it is the only route into SD that sends NO PASSWORD AT
    ALL.  vb.local.login (APISRVR request type 25) takes the identity from the
    process owner, so the whole of the access decision is the grant check.

    Until this script existed that check was exercised by "make check-local",
    by hand, on one machine, and by nothing in either half of the suite.  A
    passwordless authentication path with no standing test is the kind of thing
    this project files entries about, so it is now a step.

    THE CONTROL IS THE POINT, and it is why the binary tests two accounts:

      <account>  the caller is a member of its sdu_ group -> MUST be admitted
      SDSYS      ACC$GROUP names the group "sdsys", which  -> MUST be refused
                 does not exist on Windows

    A connection that succeeds proves nothing on its own - a grant check that
    was never reached would also let it through.  Only the pair means anything,
    and the binary's exit codes tell the two failures apart: 1 is "the account
    was refused" and 2 is "SDSYS was ADMITTED", which is the one that makes the
    success above it worthless.

    IT MUST RUN UNELEVATED, and it refuses otherwise rather than reporting a
    comfortable answer.  The identity being tested is the process owner's: an
    elevated session is a different principal and lands somewhere else, so a
    green from an elevated shell would be measuring the wrong thing.

.PARAMETER Account
    The SD account to be admitted.  Defaults to the caller's own user name
    upper-cased, which is the account CREATEA/adopt-account make for them.

.PARAMETER Exe
    The test binary.  "make sd" builds it; there is no reason to override this
    except to test this script.

.EXAMPLE
    gplbld\verify-localconnect.ps1
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.  The convention is stated here because six API verifiers
# once left it to be inferred and a "could not run" was read as a pass -
# PRE_RELEASE_FIXES 151.

# ***NEVER PUT $PSScriptRoot IN A param() DEFAULT.  MEASURED 4 Sep 2026.***
# With [CmdletBinding()] present it is EMPTY during parameter binding when the
# script is run as a CHILD PROCESS - "powershell.exe -File <script>" - and
# populated when it is run IN-PROCESS with "& <script>".  Without
# [CmdletBinding()] it is populated either way, which is what makes it look
# like it works.
#
# THE TWO INVOCATIONS ARE BOTH USED HERE, so this is not academic: the runners
# call verifiers in-process with "&", and every elevated child in this project
# is launched with Start-Process -ArgumentList '-File', which is the form that
# breaks.  The failure is a Join-Path binding error before the first line of
# the body runs, so nothing the script would have printed ever appears.
#
# Defaulted empty and resolved in the body instead.
[CmdletBinding()]
param(
    [string] $Account = '',
    [string] $Exe = ''
)

$ErrorActionPreference = 'Stop'

if ($Exe -eq '') {
    $Exe = Join-Path $PSScriptRoot '..\gplsrc\sdclilib\localtest\local-connect-test.exe'
}

function Refuse([string]$why) {
    Write-Output ''
    Write-Output ("COULD NOT RUN: " + $why)
    exit 2
}

Write-Output '=== verify-localconnect: SDConnectLocal and its grant check ==='
Write-Output ''

# ---------------------------------------------------------------------------
# [0] The tree must match source, like every other verifier that measures the
# INSTALLED system.  This one spawns the installed sd.exe through the installed
# DLL, so a stale tree makes the result describe a system that no longer exists.
# ---------------------------------------------------------------------------

Write-Output '== [0] Checking the installed tree matches source'
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Refuse 'assert-current says the installed tree does not match source'
}
Write-Output ''

# ---------------------------------------------------------------------------
# [1] The inputs, echoed before anything runs - CLAUDE.md's instrument rule.
# The three false verdicts of 23 Aug 2026 were all instruments that never
# reached the condition they claimed to measure, and echoing the real arguments
# is what caught one of them.
# ---------------------------------------------------------------------------

if ($Account -eq '') { $Account = $env:USERNAME.ToUpper() }

$id       = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal $id).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
$sdBin    = Join-Path $env:ProgramFiles 'SD\usr\bin'

Write-Output '== [1] What this run is measuring'
Write-Output ("  caller          {0}" -f $id.Name)
Write-Output ("  elevated        {0}" -f $elevated)
Write-Output ("  account         {0}   (the treatment; SDSYS is the control)" -f $Account)
Write-Output ("  test binary     {0}" -f $Exe)
Write-Output ("  installed bin   {0}   (prepended to PATH for the child)" -f $sdBin)
Write-Output ''

# ***UNELEVATED OR NOT AT ALL.***  IsInRole reports the TOKEN, which is what
# decides here - not whether the person is an administrator.  See the header.
if ($elevated) {
    Refuse ('this must run UNELEVATED - SDConnectLocal sends no password and the ' +
            'grant check reads the process owner, so an elevated token measures a ' +
            'different principal')
}

if (-not (Test-Path -LiteralPath $Exe)) {
    Refuse ("the test binary is not at $Exe.  Build it: run 'make sd' (or " +
            "'make sdclilib') from sdb_ai\sd64.")
}
if (-not (Test-Path -LiteralPath (Join-Path $sdBin 'sd.exe'))) {
    Refuse ("no sd.exe at $sdBin - SDConnectLocal starts the server by looking " +
            'for it beside the DLL, so there is nothing to connect to')
}

# The account has to exist, or "refused" would be indistinguishable from
# "there was nothing to admit" - and that reads as a grant check working.
$acctRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Account)
if (-not (Test-Path -LiteralPath $acctRec)) {
    Refuse ("no SD account record at $acctRec - a refusal would then prove " +
            'nothing, because there would be no account to admit')
}
Write-Output ("  account record  {0}   present" -f $acctRec)
Write-Output ''

# ---------------------------------------------------------------------------
# [2] Run it, from a directory holding NEITHER the binary's DLL nor sd.exe.
#
# Windows searches an executable's own directory first.  localtest\ holds only
# the test, so the loader falls through to PATH, where the INSTALLED bin is
# prepended below - and that is the pair being tested.  System32 goes on too:
# this is a native UCRT64 binary and resolves api-ms-win-crt-* through the OS,
# while some shells rebuild PATH without System32 and the failure then names a
# CRT DLL, which reads as a broken toolchain rather than a search path.
# ---------------------------------------------------------------------------

Write-Output '== [2] Running the test'
$exeDir  = Split-Path -Parent $Exe
$oldPath = $env:PATH
$out     = $null
$code    = -1
try {
    $env:PATH = $sdBin + ';' + (Join-Path $env:SystemRoot 'System32') + ';' + $oldPath
    Push-Location $exeDir
    try {
        $out  = & $Exe $Account 2>&1
        $code = $LASTEXITCODE
    } finally { Pop-Location }
} finally { $env:PATH = $oldPath }

# PRINT THE RAW OUTPUT EVERY TIME, not only when it looks wrong.  A subtle
# refusal is one no conditional print will catch, because the condition is the
# thing that was wrong - CLAUDE.md, after verify-apiidentity's Step 3.
Write-Output '  --- the binary said ---'
foreach ($line in @($out)) { Write-Output ('  | ' + $line) }
Write-Output '  --- end ---'
Write-Output ("  exit code {0}" -f $code)
Write-Output ''

# ---------------------------------------------------------------------------
# [3] The verdict, anchored on the SUCCESS wording rather than on any string
# the failure also carries.  The binary prints "PASS: <account> admitted, SDSYS
# refused." on the positive path ONLY; the account name appears on every path,
# so matching that would be a false positive with a check's name on it.
# ---------------------------------------------------------------------------

$text    = (@($out) -join "`n")
$success = ($text -match 'PASS: .+ admitted, SDSYS refused\.')
$bad     = ($text -match 'FAIL:')

Write-Output '== [3] Verdict'
Write-Output ("  exit 0                      {0}" -f ($code -eq 0))
Write-Output ("  success wording present     {0}" -f $success)
Write-Output ("  no FAIL wording present     {0}" -f (-not $bad))

switch ($code) {
    0 { }
    1 { Write-Output ("  the account was REFUSED - the grant check is too strict, or " +
                      "the transport is broken") }
    2 { Write-Output ("  SDSYS was ADMITTED - the grant check did not run, which makes " +
                      "any success above it worthless") }
    3 { Write-Output '  the session opened but could not execute a command' }
    4 { Write-Output '  the binary was given no account - this script should have passed one' }
    default { Write-Output '  the binary did not run, or died before it could report' }
}
Write-Output ''

if (($code -eq 0) -and $success -and (-not $bad)) {
    Write-Output 'verify-localconnect: PASSED - the account was admitted and SDSYS refused.'
    Write-Output 'SDConnectLocal carried a session, and the grant check ran.'
    exit 0
}

# A zero exit with the wrong text is a worse answer than a non-zero one, so it
# is called out rather than folded into the general failure.
if (($code -eq 0) -and (-not $success)) {
    Write-Output 'verify-localconnect: FAILED - exit 0 but the success wording is absent.'
    Write-Output 'Read the raw output above; do not take the exit code on trust.'
    exit 1
}

Write-Output 'verify-localconnect: FAILED - see the verdict rows above.'
exit 1
