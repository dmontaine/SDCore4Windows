# probe-osadmin.ps1 - build and run probe-osadmin.c, and cross-check it against
#                     Windows' own answer.
#
#   powershell -File probe-osadmin.ps1
#
# RUN IT TWICE - once from an ORDINARY, UNELEVATED PowerShell and once from an
# ELEVATED one.  THE COMPARISON IS THE MEASUREMENT.  One run on its own says
# nothing: "IsElevated() = FALSE" is the expected answer in one leg and the
# alarming one in the other, and only the pair distinguishes "the two calls
# disagree, so there is a discriminator" from "they agree, so there is not".
#
# Exit 0 the probe measured, 2 it could not.  Like probe-keys.ps1 and
# probe-console.ps1 there is nothing here to pass or fail: it is an INSTRUMENT,
# a person reads what it prints, and it is deliberately not in VerifyInstall1
# or VerifyInstall2.
#
# WHAT IT IS FOR.  PROJECT_STATUS.md "START HERE" step 1, which every other
# piece of PRE_RELEASE_FIXES 56 clause 2 waits on: does anything in the running
# process distinguish "this session is already elevated" from "this person is an
# administrator"?  probe-osadmin.c's header has the full reasoning, including
# why a BASIC probe reading kernel(K$ADMINISTRATOR,-1) CANNOT answer it.
#
# IT NEEDS NO INSTALL, NO SD, NO ACCOUNT AND NO -Run TOKEN.  It asks the
# operating system through the MSYS2 runtime and nothing else, so it costs no
# cycle and leaves nothing behind but its own .exe, which is untracked.
#
# A REDIRECTED STDIN IS FINE HERE, unlike probe-console.ps1 - this reads no
# input and measures no terminal, so piping into it changes nothing it looks at.
# It prints isatty(0) so a redirected run is visible rather than silent.
#
# NOT INSTALLED AND NOT SHIPPED - probe-osadmin.c and probe-osadmin.ps1 are both
# on assert-current.ps1's $neverShipped list, or they report the tree stale
# because they exist, and then every verifier refuses.

$ErrorActionPreference = 'Stop'

$ccW = 'C:\msys64\usr\bin\gcc.exe'
if (-not (Test-Path -LiteralPath $ccW)) {
    Write-Host "probe-osadmin: no MSYS2 compiler at $ccW"
    exit 2
}

$src = Join-Path $PSScriptRoot 'probe-osadmin.c'
$exe = Join-Path $PSScriptRoot 'probe-osadmin.exe'

if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "probe-osadmin: source not found at $src"
    exit 2
}

# --- The independent witness, taken BEFORE the probe runs. -------------------
#
# Windows' own answer to the same two questions, through an API that has nothing
# to do with the MSYS2 runtime.  It is the control: the whole finding is that
# getgrouplist() and getgroups() disagree for an unelevated administrator, and a
# second instrument saying the same thing is what makes that a measurement
# rather than a quirk of one library.  If these two ever disagree, THAT is the
# news and neither answer should be used until it is understood.
$id        = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($id)
$winElev   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

Write-Host ''
Write-Host 'probe-osadmin - the Windows-side witness, before the probe runs'
Write-Host '=============================================================='
Write-Host ("  identity                     : {0}" -f $id.Name)
Write-Host ("  WindowsPrincipal.IsInRole    : {0}   (Administrator role - TRUE only when ELEVATED)" -f $winElev)
Write-Host ("  so this shell is             : {0}" -f $(if ($winElev) { 'ELEVATED' } else { 'not elevated' }))
Write-Host ''

# --- Build. ------------------------------------------------------------------
#
# THE COMPILER'S OWN DIRECTORY MUST BE ON PATH, and this is not optional: gcc
# resolves fine by full path, but the subprograms it spawns - cc1.exe - find
# their DLLs through PATH, and without it the build dies with
#   "cc1.exe: error while loading shared libraries: ?: cannot open shared
#    object file"
# which names no file and reads like a broken toolchain.  probe-console.ps1
# carries the same note; it hit there first on 23 Aug 2026.
#
# AND THE COMPILER IS CALLED THROUGH cmd.exe RATHER THAN DIRECTLY.  Under
# $ErrorActionPreference = 'Stop' a native exe writing to stderr raises a
# terminating NativeCommandError, so one gcc warning would kill this script with
# no error text at all - which reads exactly like the probe running and finding
# nothing.  Measured in probe-s4u.ps1, 23 Aug 2026.  The redirect also keeps the
# output, which "& $exe" has been observed to drop.
$saved = $env:PATH
$env:PATH = 'C:\msys64\usr\bin;' + $env:PATH
$buildLog = Join-Path $env:TEMP 'probe-osadmin-build.txt'
try {
    Write-Host 'probe-osadmin: building with the MSYS2 compiler...'
    # The same warning flags sd itself is built with (Makefile, "sd:" target),
    # so a warning here is a warning that would show up in the real build.
    $cmd = '"{0}" -std=gnu17 -Wall -Wformat=2 -Wno-format-nonliteral -O1 -o "{1}" "{2}" > "{3}" 2>&1' -f $ccW, $exe, $src, $buildLog
    & cmd.exe /c $cmd
    $buildCode = $LASTEXITCODE
} finally {
    $env:PATH = $saved
}

if (Test-Path -LiteralPath $buildLog) {
    $buildOut = @(Get-Content -LiteralPath $buildLog)
    if ($buildOut.Count -gt 0) {
        Write-Host '  compiler said:'
        $buildOut | ForEach-Object { Write-Host "    $_" }
    } else {
        Write-Host '  compiler said nothing - 0 warnings, 0 errors.'
    }
}

if ($buildCode -ne 0) {
    Write-Host "probe-osadmin: build failed (exit $buildCode)"
    exit 2
}
if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "probe-osadmin: build reported success but $exe is not there"
    exit 2
}

# --- Run, capturing the output to a file. ------------------------------------
#
# The output IS the result here, so it goes through cmd.exe to a file and is
# read back, rather than through "& $exe" - which has lost whole blocks of a
# transcript in this tree before.  The path is printed so it can be reread.
$runLog = Join-Path $env:TEMP 'probe-osadmin-run.txt'
if (Test-Path -LiteralPath $runLog) { Remove-Item -LiteralPath $runLog -Force }

& cmd.exe /c ('"{0}" > "{1}" 2>&1' -f $exe, $runLog)
$code = $LASTEXITCODE

Write-Host ''
if (-not (Test-Path -LiteralPath $runLog)) {
    Write-Host "probe-osadmin: the probe wrote no output file at $runLog"
    Write-Host "probe-osadmin: exit 2"
    exit 2
}

$out = @(Get-Content -LiteralPath $runLog)
# A run that printed nothing must not be reported as a run.  An empty capture
# and a clean exit 0 are indistinguishable from a measurement that happened,
# which is the exact shape PROJECT_STATUS "an instrument shows what it DID"
# refuses.  Byte size beside the line count, for the same reason.
$bytes = (Get-Item -LiteralPath $runLog).Length
if ($out.Count -eq 0 -or $bytes -eq 0) {
    Write-Host "probe-osadmin: the probe produced 0 lines / $bytes bytes."
    Write-Host 'probe-osadmin: nothing was measured.  Exit 2.'
    exit 2
}

$out | ForEach-Object { Write-Host $_ }

Write-Host ''
Write-Host ("  transcript: {0} ({1} lines, {2} bytes)" -f $runLog, $out.Count, $bytes)
Write-Host ''

# --- The cross-check. --------------------------------------------------------
#
# ANCHORED ON THE ONE LINE THE PROBE PRINTS EXACTLY ONCE AND ONLY WHEN IT GOT
# ALL THE WAY THROUGH.  Every refusal path prints "ANSWER: undetermined" and
# returns before this line is reached, so the two cannot both appear.
#
# THE FIRST VERSION OF THIS ANCHORED ON "IsElevated() = FALSE" AND WAS WRONG -
# measured 29 Aug 26 on this probe's own first run, which refused a perfectly
# good measurement.  That string is printed TWICE on the success path, in
# section 2 and again in the ANSWER summary, so the "exactly one" guard below
# fired on a run that had measured cleanly.  Section 8's rule, from the other
# side: a pattern has to be unique to the outcome it claims, and being printed
# twice breaks that as surely as being printed on the failure path does.
#
# -cmatch, ANCHORED AT THE START, AND BOTH POLARITIES COUNTED SEPARATELY.
# "UNELEVATED" contains "ELEVATED", so a case-insensitive or unanchored match
# for one would find the other; "an ELEVATED" is not a substring of
# "an UNELEVATED", and the leading ^ANSWER makes that explicit rather than
# lucky.
$trimmed   = @($out | ForEach-Object { $_.Trim() })
$sawTrue   = @($trimmed | Where-Object { $_ -cmatch '^ANSWER: this shell is an ELEVATED administrator\.$' }).Count
$sawFalse  = @($trimmed | Where-Object { $_ -cmatch '^ANSWER: this shell is an UNELEVATED administrator\.$' }).Count
$refused   = @($trimmed | Where-Object { $_ -cmatch '^ANSWER: undetermined' }).Count

Write-Host 'THE TWO INSTRUMENTS, SIDE BY SIDE'
Write-Host '================================='
if ($refused -gt 0) {
    Write-Host '  the probe REFUSED - see its own text above.  Nothing to compare.'
    Write-Host "probe-osadmin: exit $code"
    exit 2
}
if (($sawTrue + $sawFalse) -ne 1) {
    Write-Host ("  the probe printed {0} TRUE and {1} FALSE readings of IsElevated()." -f $sawTrue, $sawFalse)
    Write-Host '  Exactly one was expected.  The output above is not parseable; read it by eye.'
    Write-Host "probe-osadmin: exit 2"
    exit 2
}
$probeElev = ($sawTrue -eq 1)

Write-Host ("  WindowsPrincipal (Win32)     : elevated = {0}" -f $winElev)
Write-Host ("  getgroups()      (MSYS2)     : elevated = {0}" -f $probeElev)
if ($probeElev -eq $winElev) {
    Write-Host '  THEY AGREE.  The MSYS2 runtime is reporting the token Windows reports.'
} else {
    Write-Host '  *** THEY DISAGREE.  THAT IS THE NEWS - do not use either answer'
    Write-Host '  *** until it is understood.  kernel.c:240 seeds K$ADMINISTRATOR'
    Write-Host '  *** from the MSYS2 answer, so it is the one SD acts on.'
}

Write-Host ''
Write-Host "probe-osadmin: exit $code"
exit $code
