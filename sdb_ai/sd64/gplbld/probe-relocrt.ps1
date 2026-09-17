# probe-relocrt.ps1 - UNELEVATED.  RELEASE_1.1 43's kept objection.
#
# QUESTION: a native relay is a SECOND relay source beside Linux's sd_tlssrv.c.
# The one alternative that keeps a single source - a separately-pathed second
# copy of msys-2.0.dll for the relay - was rejected UNMEASURED.  The error that
# forced native names a PATH-derived key (\BaseNamedObjects\msys-2.0S5-<hash>),
# so a relocated copy would be EXPECTED to get its own object directory and
# start at Low beside sd.  This measures it.
#
# FALSIFIED-IF: the relocated-runtime program still dies 0xC0000142 at Low while
# a Medium process of the SHIPPED runtime is alive.
#
# Exit 0 = the relocated runtime ran at Low with the shipped one held (the
#          single-source option is alive and it is the owner's call)
# Exit 1 = it did not (the native relay stands)
# Exit 2 = could not run: a control failed, so nothing was measured
#
# TWO HARNESS TRAPS THIS COST, BOTH POWERSHELL 5.1, BOTH CAUGHT BY RUNNING IT:
#  1. "2>&1" on a NATIVE exe wraps each stderr line in a NativeCommandError and
#     sets $? false even on exit 0 - and these children are EXPECTED to write to
#     stderr, so that route loses the measurement.  Redirect to FILES instead.
#  2. A function returns EVERYTHING it emits, so narration inside one lands in
#     the caller's variable alongside the value.  Narrate with Write-Host.

function Say([string]$s) { Write-Host $s }

$gplbld  = 'C:/Users/Don/SDCoreProject/sd4windows/sdb_ai/sd64/gplbld'
$msysdll = 'C:/msys64/usr/bin/msys-2.0.dll'
$holder  = 'C:/msys64/usr/bin/sleep.exe'
$stage   = Join-Path $env:TEMP 'relocrt'
$rt      = Join-Path $stage 'rt'

$cygshared = "$gplbld/probe-cygshared.exe"
$lowmsys   = "$gplbld/probe-lowmsys.exe"

Say "== Inputs, resolved"
Say "  gplbld        : $gplbld"
Say "  shipped dll   : $msysdll"
Say "  holder        : $holder"
Say "  stage         : $stage"
foreach ($f in @($cygshared, $lowmsys, $msysdll, $holder)) {
  if (-not (Test-Path $f)) { Say "COULD NOT RUN: missing $f"; exit 2 }
}

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $rt | Out-Null
Copy-Item $msysdll (Join-Path $rt 'msys-2.0.dll')
Copy-Item $lowmsys (Join-Path $rt 'probe-lowmsys.exe')
$relocExe = Join-Path $rt 'probe-lowmsys.exe'
$relocDll = Join-Path $rt 'msys-2.0.dll'
Say "  relocated exe : $relocExe"
Say "  relocated dll : $relocDll ($((Get-Item $relocDll).Length) bytes)"

$sys = "$env:SystemRoot\system32;$env:SystemRoot"
$origPath = $env:PATH
$script:n = 0

# Run a native exe, capture both streams to files, print them, return the code.
function Run-Native([string]$exe, $argl, [string]$path) {
  $script:n++
  $o = Join-Path $stage "out$($script:n).txt"
  $e = Join-Path $stage "err$($script:n).txt"
  $env:PATH = $path
  if ($argl -and $argl.Count -gt 0) {
    $p = Start-Process -FilePath $exe -ArgumentList $argl -NoNewWindow -Wait -PassThru `
                       -RedirectStandardOutput $o -RedirectStandardError $e
  } else {
    $p = Start-Process -FilePath $exe -NoNewWindow -Wait -PassThru `
                       -RedirectStandardOutput $o -RedirectStandardError $e
  }
  $env:PATH = $origPath
  foreach ($f in @($o, $e)) {
    if ((Test-Path $f) -and (Get-Item $f).Length -gt 0) {
      Get-Content $f | ForEach-Object { Write-Host "  | $_" }
    }
  }
  return [int]$p.ExitCode
}

function Get-MsysDirs([string]$label) {
  Say "== $label - msys object directories in \BaseNamedObjects"
  $script:n++
  $o = Join-Path $stage "obj$($script:n).txt"
  $env:PATH = $origPath
  Start-Process -FilePath $cygshared -NoNewWindow -Wait `
                -RedirectStandardOutput $o `
                -RedirectStandardError (Join-Path $stage "obje$($script:n).txt") | Out-Null
  $names = @()
  if (Test-Path $o) {
    $names = @(Get-Content $o |
      Select-String -Pattern 'Directory\s+(msys-\S+)' |
      ForEach-Object { $_.Matches[0].Groups[1].Value } |
      Sort-Object -Unique)
  }
  if ($names.Count -eq 0) { Say "  (none seen)" } else { $names | ForEach-Object { Say "  $_" } }
  return ,$names
}

$before = Get-MsysDirs 'BEFORE'

Say "== The holder (a Medium MSYS2 process of the SHIPPED runtime, standing in for sd)"
$h = Start-Process -FilePath $holder -ArgumentList '90' -PassThru -WindowStyle Hidden
Start-Sleep -Milliseconds 700
if ($h.HasExited) { Say "COULD NOT RUN: the holder exited immediately"; exit 2 }
Say "  holder pid    : $($h.Id), alive"

$controlA = $null; $controlB = $null; $measured = $null
try {
  Say "== CONTROL A: the SHIPPED runtime at Low, holder alive (must DIE)"
  $controlA = Run-Native $cygshared @('--low', $lowmsys) $origPath
  Say "  control A exit: $controlA"

  Say "== CONTROL B: the RELOCATED runtime at Medium, holder alive (must RUN)"
  $controlB = Run-Native $relocExe $null "$rt;$sys"
  Say "  control B exit: $controlB"

  Say "== MEASUREMENT: the RELOCATED runtime at LOW, holder alive"
  $measured = Run-Native $cygshared @('--low', $relocExe) "$rt;$sys"
  Say "  measured exit : $measured"
}
finally {
  $env:PATH = $origPath
  if (-not $h.HasExited) { Stop-Process -Id $h.Id -Force -ErrorAction SilentlyContinue; Say "  holder stopped" }
}

$after = Get-MsysDirs 'AFTER'
$new = @($after | Where-Object { $before -notcontains $_ })
Say "== New msys object directories that appeared: $(if ($new.Count) { $new -join ', ' } else { '(none)' })"

Say ""
Say "== Verdict"
Say "  control A (shipped at Low, held)  : exit $controlA"
Say "  control B (relocated at Medium)   : exit $controlB"
Say "  measured  (relocated at Low, held): exit $measured"

if ($controlA -eq 0) {
  Say "COULD NOT RUN: control A RAN, so the holder condition was not reproduced."
  Say "  Nothing was measured - the shipped runtime is supposed to die at Low here."
  exit 2
}
if ($controlB -ne 0) {
  Say "COULD NOT RUN: control B failed (exit $controlB), so the relocated copy is broken."
  Say "  A failure at Low would not have been about integrity."
  exit 2
}
if ($measured -eq 0) {
  Say "ANSWERED: the RELOCATED runtime RAN at Low while a Medium process of the"
  Say "  shipped runtime was alive - which the shipped runtime could not do (A)."
  Say "  A separately-pathed msys-2.0.dll keeps ONE relay source. Owner's call:"
  Say "  two runtimes shipped, against two relay sources maintained."
  exit 0
}
Say "FALSIFIED: the relocated runtime ALSO failed at Low (exit $measured)."
Say "  The path-derived-key expectation does not hold, or something else blocks it."
Say "  The native relay stands."
exit 1
