# probe-relockey.ps1 - UNELEVATED.  Is the runtime's object-directory key really
# PER PATH?  The companion to probe-relocrt.ps1, and the reason its result must
# not be overstated.
#
# probe-relocrt measured the OUTCOME: a relocated msys-2.0.dll starts at Low
# while the shipped runtime is held.  The obvious explanation was that the
# \BaseNamedObjects\msys-2.0S5-<key> name is derived from the DLL's PATH.  This
# tests that by putting copies at THREE different shapes - a plain directory, a
# deeper one, and a real <root>\usr\bin layout - and holding them all alive at
# once beside the shipped runtime, scanning the namespace ONCE so the keys are
# seen together rather than inferred.
#
# ===========================================================================
# THE FIRST VERSION OF THIS SCRIPT PRODUCED A VACUOUS PASS AND IT IS WHY THE
# PROOF-OF-LIFE CHECK BELOW EXISTS.  It held each copy alive with a relocated
# sleep.exe, and sleep.exe imports msys-intl-8.dll as well as msys-2.0.dll -
# which was NOT copied, and msys64 is not on PATH.  So every holder failed in
# the LOADER, put a "code execution cannot proceed" dialog on the owner's
# screen, and BLOCKED there.  A blocked process is not an exited one, so
# HasExited was false and the script counted all three as alive: it reported a
# result for runtimes that had never executed an instruction.
#
# THE FIX IS NOT "COPY THE OTHER DLL".  It is that a process may not be counted
# because it EXISTS - it must say something only a running one can say.  The
# holder is now probe-lowmsys.exe, whose imports are msys-2.0.dll and system
# DLLs only (objdump -p), run with --sleep so it prints
#   msyshello: started, pid N, integrity 0xNNNN
# to a redirect file and then holds the runtime's objects for 6 s.  Every holder
# must produce that line or the run refuses.
# ===========================================================================
#
# Exit 0 = each path got its own key (3 relocated keys, all distinct)
# Exit 1 = they collide - the key is NOT per-path; say so before relying on it
# Exit 2 = could not run (a holder never executed, or the scan saw nothing)

function Say([string]$s) { Write-Host $s }

$gplbld    = 'C:/Users/Don/SDCoreProject/sd4windows/sdb_ai/sd64/gplbld'
$msysbin   = 'C:/msys64/usr/bin'
$stage     = Join-Path $env:TEMP 'relockey'
$cygshared = "$gplbld/probe-cygshared.exe"
$lowmsys   = "$gplbld/probe-lowmsys.exe"

$paths = @(
  (Join-Path $stage 'rtA'),
  (Join-Path $stage 'deeper\rtB'),
  (Join-Path $stage 'rtC\usr\bin')
)

Say "== Inputs, resolved"
Say "  shipped bin   : $msysbin"
Say "  scanner       : $cygshared"
Say "  holder exe    : $lowmsys  (--sleep; imports msys-2.0.dll only)"
Say "  stage         : $stage"
foreach ($f in @($cygshared, $lowmsys, "$msysbin/msys-2.0.dll", "$msysbin/sleep.exe")) {
  if (-not (Test-Path $f)) { Say "COULD NOT RUN: missing $f"; exit 2 }
}

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue }
foreach ($p in $paths) {
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  Copy-Item "$msysbin/msys-2.0.dll" (Join-Path $p 'msys-2.0.dll')     -Force
  Copy-Item $lowmsys                (Join-Path $p 'probe-lowmsys.exe') -Force
  Say "  copy          : $p"
}

function Scan([string]$label) {
  $o = Join-Path $stage "scan-$label.txt"
  Start-Process -FilePath $cygshared -NoNewWindow -Wait `
                -RedirectStandardOutput $o `
                -RedirectStandardError (Join-Path $stage "scan-$label-err.txt") | Out-Null
  $names = @()
  if (Test-Path $o) {
    $names = @(Get-Content $o |
      Select-String -Pattern 'Directory\s+(msys-\S+)' |
      ForEach-Object { $_.Matches[0].Groups[1].Value } |
      Sort-Object -Unique)
  }
  Say "== $label - msys object directories ($($names.Count))"
  if ($names.Count -eq 0) { Say "  (none seen)" } else { $names | ForEach-Object { Say "  $_" } }
  return ,$names
}

$idle = Scan 'idle'

$procs = @(); $live = @(); $proven = 0
try {
  Say "== Holding the shipped runtime and all three copies alive"
  $procs += Start-Process -FilePath "$msysbin/sleep.exe" -ArgumentList '20' -PassThru -WindowStyle Hidden
  $i = 0
  foreach ($p in $paths) {
    $i++
    $out = Join-Path $stage "holder$i.txt"
    $procs += Start-Process -FilePath (Join-Path $p 'probe-lowmsys.exe') -ArgumentList '--sleep' `
                            -PassThru -WindowStyle Hidden `
                            -RedirectStandardOutput $out `
                            -RedirectStandardError (Join-Path $stage "holder$i-err.txt")
  }
  Start-Sleep -Milliseconds 1400

  # PROOF OF LIFE.  Existing is not running - see the header.
  Say "== Proof of life (each relocated holder must SAY it started)"
  for ($k = 1; $k -le $paths.Count; $k++) {
    $out = Join-Path $stage "holder$k.txt"
    $line = $null
    if (Test-Path $out) { $line = (Get-Content $out -ErrorAction SilentlyContinue | Select-String 'msyshello: started').Line }
    if ($line) { $proven++; Say "  holder $k : $($line.Trim())" }
    else {
      $err = Join-Path $stage "holder$k-err.txt"
      $emsg = if (Test-Path $err) { (Get-Content $err -ErrorAction SilentlyContinue) -join ' ' } else { '' }
      Say "  holder $k : NO START LINE - it did not execute.  $emsg"
    }
  }
  if ($proven -ne $paths.Count) {
    Say "COULD NOT RUN: only $proven of $($paths.Count) relocated runtimes actually executed."
    Say "  Nothing is measured by a process that never ran - this is the exact"
    Say "  failure the header records, refusing this time instead of scoring it."
    exit 2
  }
  $live = Scan 'all-alive'
}
finally {
  foreach ($p in $procs) {
    if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
  }
  Say "  holders stopped"
}

Say ""
Say "== Verdict"
Say "  proof of life : $proven of $($paths.Count) relocated runtimes executed"
Say "  idle          : $($idle.Count) - $($idle -join ', ')"
Say "  all alive     : $($live.Count) - $($live -join ', ')"
$new = @($live | Where-Object { $idle -notcontains $_ })
Say "  relocated keys: $($new.Count) - $($new -join ', ')"

if ($live.Count -eq 0) { Say "COULD NOT RUN: the scan saw nothing"; exit 2 }
if ($new.Count -eq $paths.Count) {
  Say "ANSWERED: $($paths.Count) copies at $($paths.Count) paths produced $($new.Count) DISTINCT keys."
  Say "  The key is genuinely per-path.  A relocated relay runtime contends"
  Say "  neither with sd's nor with another relocated one."
  exit 0
}
Say "FALSIFIED: $($paths.Count) copies produced $($new.Count) relocated key(s), not $($paths.Count)."
Say "  The key is NOT simply per-path.  Relocation still separates the relay"
Say "  from sd (probe-relocrt measured that, with output to prove the child"
Say "  ran), but do not assume two relocated runtimes are separate."
exit 1
