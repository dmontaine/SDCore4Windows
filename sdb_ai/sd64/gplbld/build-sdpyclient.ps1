<#
.SYNOPSIS
    Build SD's side of the helper pipe with the MSYS2 compiler and drive the
    native helper with it.  No elevation, no install, no cycle.

.DESCRIPTION
    PROJECT_STATUS.md section 5.27.  ***THE TOOLCHAIN IS THE TEST.***
    sdpy_client.c is compiled into sd.exe, so it is built here with
    /usr/bin/gcc - the MSYS2 compiler sd.exe is built with (Makefile:48) - and
    it drives sdpy.exe, which is NATIVE UCRT64 linked against python.org's
    python3.dll.

    Section 5.3 rules that the two runtimes never meet in one process, and
    section 5.27 chose the helper over a shim DLL on exactly that ground. But
    the ruling only says they must not SHARE a process; it never established
    that they could TALK, and nothing in this tree had shown it. This is what
    shows it.

    ***THE PATH LINE IS NOT DECORATION.***  gcc.exe finds its own DLLs beside
    itself; the cc1.exe it spawns does not, and resolves through PATH. Without
    it the compile dies with "cannot open shared object file" and no object -
    Makefile:150 records the same trap for the UCRT64 compiler, and this
    script met it for the MSYS2 one.

.OUTPUTS
    Exit 0 built and every row passed, 1 a row failed, 2 could not build or run.
#>

[CmdletBinding()]
param(
    [string]$Cc = 'C:\msys64\usr\bin\gcc.exe'
)

$ErrorActionPreference = 'Stop'
$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$client = Join-Path $here 'sdpy_client.c'
$driver = Join-Path $here 'test-sdpyclient.c'
$out    = Join-Path $here 'test-sdpyclient.exe'
$helper = Join-Path $here 'sdpy.exe'

function Say([string]$m) { Write-Output ("build-sdpyclient: " + $m) }

foreach ($f in @($client, $driver)) {
    if (-not (Test-Path -LiteralPath $f)) { Say "missing $f"; exit 2 }
}
if (-not (Test-Path -LiteralPath $Cc)) { Say "no MSYS2 compiler at $Cc"; exit 2 }
if (-not (Test-Path -LiteralPath $helper)) {
    Say "no sdpy.exe beside this script - build it first with build-sdpy.ps1."
    Say '  There is nothing to drive, and a run with nothing to drive is not a result.'
    exit 2
}

Say ("compiler : " + $Cc + "  (the one sd.exe is built with)")
Say ("helper   : " + $helper + "  (native UCRT64)")
Say ("output   : " + $out)

# See the header: cc1.exe resolves its DLLs through PATH, not from beside gcc.
$env:PATH = (Split-Path -Parent $Cc) + ';' + $env:PATH

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

$args = @('-std=gnu17', '-O2', '-Wall', '-Wextra', $client, $driver, '-o', $out)
Say ('command  : gcc ' + ($args -join ' '))
Write-Output ''
$log = & $Cc @args 2>&1
$code = $LASTEXITCODE
foreach ($l in $log) { Write-Output ('  ' + $l) }

if ($code -ne 0) {
    Say ("gcc exited $code" + $(if (@($log).Count -eq 0) { ' AND PRINTED NOTHING - is the MSYS2 bin on PATH?' } else { '' }))
    exit 2
}
if (-not (Test-Path -LiteralPath $out)) {
    Say 'gcc exited 0 and wrote no binary.  That is not a build.'
    exit 2
}
Say ('built    : ' + (Get-Item -LiteralPath $out).Length + ' bytes, ' +
     @($log | Where-Object { $_ -match 'warning:' }).Count + ' warning(s)')
Write-Output ''

& $out $helper
$runCode = $LASTEXITCODE
Write-Output ''
if ($runCode -eq 0) { Say 'the MSYS2 side and the native helper agree.' }
else { Say "the driver exited $runCode." }
exit $runCode
