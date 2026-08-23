# probe-console.ps1 - build and run probe-console.c IN A REAL CONSOLE.
#
#   powershell -File probe-console.ps1        UNELEVATED, in a REAL console
#
# Exit 0 the probe ran, 2 it could not be set up.  Like probe-keys.ps1 there is
# nothing here to pass or fail: it is an instrument, and a person reads what it
# prints.  It is not in VerifyInstall1 or VerifyInstall2 for that reason.
#
# WHAT IT IS FOR.  Section 7 step 13, leg 1 - linuxio.c's six termios calls to
# the Console API - is only doable before the toolchain flip if SetConsoleMode()
# from an MSYS2 process sticks.  Under MSYS2 fd 0 is a Cygwin descriptor and
# Cygwin's tty layer is what implements termios, so both layers would be trying
# to own the console.  probe-console.c's header has the full reasoning.
#
# IT MUST BE A REAL CONSOLE, and this refuses a redirected stdin - the same
# guard, and for the same reason, as probe-keys.ps1: piping into it would
# measure the pipe and give a confident answer to the wrong question.
#
# BUILT WITH THE MSYS2 COMPILER ON PURPOSE.  sd.exe is built against the MSYS2
# runtime (5.4), and the whole question is what that runtime does, so building
# this with the UCRT64 compiler would measure a process SD is not.
#
# NOT INSTALLED AND NOT SHIPPED - it must be on assert-current.ps1's
# $neverShipped list, or it reports the tree stale because it exists.

$ErrorActionPreference = 'Stop'

# The console test, before anything else is done.  [Console]::IsInputRedirected
# is the reliable form here: a redirected stdin is exactly the case this must
# refuse, and it answers without reading a byte.
if ([Console]::IsInputRedirected) {
    Write-Host 'probe-console: standard input is redirected.'
    Write-Host 'Run this in a REAL console window - do not pipe into it.'
    exit 2
}

$cc  = '/c/msys64/usr/bin/gcc.exe'
$ccW = 'C:\msys64\usr\bin\gcc.exe'
if (-not (Test-Path -LiteralPath $ccW)) {
    Write-Host "probe-console: no MSYS2 compiler at $ccW"
    exit 2
}

$src = Join-Path $PSScriptRoot 'probe-console.c'
$exe = Join-Path $PSScriptRoot 'probe-console.exe'

# THE COMPILER'S OWN DIRECTORY MUST BE ON PATH, and this is not optional: gcc
# itself resolves fine by full path, but the subprograms it spawns - cc1.exe,
# in usr/lib/gcc/x86_64-pc-cygwin/... - find their DLLs through PATH, and
# without it the build dies with
#   "cc1.exe: error while loading shared libraries: ?: cannot open shared
#    object file"
# which names no file and reads like a broken toolchain.  The Makefile carries
# the same note for UCRT_BIN; this hit on the first build here, 23 Aug 2026.
$saved = $env:PATH
$env:PATH = 'C:\msys64\usr\bin;' + $env:PATH
try {
    Write-Host 'probe-console: building with the MSYS2 compiler...'
    # The same warning flags sd itself is built with (Makefile, "sd:" target),
    # so a warning here is a warning that would show up in the real build.
    & $ccW -std=gnu17 -Wall -Wformat=2 -Wno-format-nonliteral -O1 -o $exe $src
    if ($LASTEXITCODE -ne 0) {
        Write-Host "probe-console: build failed (exit $LASTEXITCODE)"
        exit 2
    }
} finally {
    $env:PATH = $saved
}

Write-Host ''
& $exe
$code = $LASTEXITCODE
Write-Host ''
Write-Host "probe-console: exit $code"
exit $code
