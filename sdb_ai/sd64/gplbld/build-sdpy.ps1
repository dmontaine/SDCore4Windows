<#
.SYNOPSIS
    Build sdpy.exe, the section 5.27 Python helper, with the NATIVE UCRT64
    compiler.  No elevation, no install, no cycle.

.DESCRIPTION
    ***IT MUST BE THE UCRT64 COMPILER AND NOT MSYS2's.***  Section 5.3: the
    server is MSYS2 and python.org's DLL is native, and the two runtimes never
    meet in one process.  The helper exists precisely so that boundary is a
    pipe rather than a linker flag, so it is built the way the client DLLs are.

    ***AND IT LINKS -lpython3, NOT -lpython314.***  Section 8 constraint 5,
    measured 12 Sep 2026 by gplbld/probe-pylimited.c: the stable ABI really
    forwards - python3.dll loaded and pulled in the concrete python314.DLL
    behind it - and a binary compiled against a 3.13 floor ran on 3.14.7.  One
    helper therefore serves every Python at or above the floor.

    ***THE PYTHON IS FOUND IN THE HIVE, NOT ON PATH.***  Section 8 constraint 1:
    PATH answered this question wrongly in BOTH directions on this machine.
    python-detect.ps1 is the detector and this asks the same hive it does.

.PARAMETER Cc
    Override the compiler.  Defaults to the UCRT64 gcc.

.OUTPUTS
    Exit 0 built, 2 could not build.  The binary is sdpy.exe beside this script.
#>

[CmdletBinding()]
param(
    [string]$Cc = 'C:\msys64\ucrt64\bin\gcc.exe'
)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$src  = Join-Path $here 'sdpy.c'
$out  = Join-Path $here 'sdpy.exe'

function Say([string]$m) { Write-Output ("build-sdpy: " + $m) }

if (-not (Test-Path -LiteralPath $src)) { Say "no source at $src"; exit 2 }
if (-not (Test-Path -LiteralPath $Cc))  { Say "no compiler at $Cc"; exit 2 }

# --- find the Python, by hive ----------------------------------------------
$root = 'HKLM:\SOFTWARE\Python\PythonCore'
$pyDir = ''
if (Test-Path -LiteralPath $root) {
    foreach ($k in (Get-ChildItem -LiteralPath $root -ErrorAction SilentlyContinue)) {
        $ipK = Join-Path $k.PSPath 'InstallPath'
        if (Test-Path -LiteralPath $ipK) {
            $p = (Get-ItemProperty -LiteralPath $ipK -ErrorAction SilentlyContinue).'(default)'
            if ($p -and (Test-Path -LiteralPath $p)) { $pyDir = $p.TrimEnd('\') }
        }
    }
}
if ($pyDir -eq '') {
    Say 'no all-users Python under HKLM\SOFTWARE\Python\PythonCore.'
    Say '  python-detect.ps1 is the detector; a per-user install cannot be used.'
    exit 2
}

$inc = Join-Path $pyDir 'include'
$lib = Join-Path $pyDir 'libs'
foreach ($d in @($inc, $lib)) {
    if (-not (Test-Path -LiteralPath $d)) { Say "missing $d"; exit 2 }
}
if (-not (Test-Path -LiteralPath (Join-Path $lib 'python3.lib'))) {
    Say "no python3.lib in $lib - the stable ABI import library is not installed."
    exit 2
}

Say ("compiler : " + $Cc)
Say ("python   : " + $pyDir)
Say ("source   : " + $src)
Say ("output   : " + $out)

# ***THE UCRT64 bin MUST BE ON PATH FOR gcc's OWN SUB-TOOLS.***  HISTORY.md,
# 4 Sep 2026: a first UCRT64 build failed SILENTLY because it was not - gcc
# exits 1 having printed nothing at all.
$env:PATH = (Split-Path -Parent $Cc) + ';' + $env:PATH

$args = @(
    $src,
    '-O2', '-Wall', '-Wextra',
    ('-I' + $inc),
    ('-L' + $lib),
    '-lpython3',
    '-o', $out
)
Say ('command  : ' + (Split-Path -Leaf $Cc) + ' ' + ($args -join ' '))
Write-Output ''

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Force }

$log = & $Cc @args 2>&1
$code = $LASTEXITCODE
foreach ($l in $log) { Write-Output ('  ' + $l) }

# REFUSE THE NULL CASE.  A zero exit with no binary is not a build, and gcc can
# exit non-zero having printed nothing when its own tools are unreachable.
if ($code -ne 0) {
    Write-Output ''
    Say ("gcc exited $code" + $(if (@($log).Count -eq 0) { ' AND PRINTED NOTHING - check that the UCRT64 bin is reachable' } else { '' }))
    exit 2
}
if (-not (Test-Path -LiteralPath $out)) {
    Write-Output ''
    Say 'gcc exited 0 but no binary was written.  That is not a build.'
    exit 2
}

$fi = Get-Item -LiteralPath $out
Write-Output ''
Say ("built    : " + $fi.Length + " bytes, " + $fi.LastWriteTime.ToString('HH:mm:ss'))
Say ('warnings : ' + @($log | Where-Object { $_ -match 'warning:' }).Count)
exit 0
