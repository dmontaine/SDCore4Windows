# probe-relockey.ps1 - UNELEVATED.  Is the runtime's object-directory key really
# PER PATH?  The companion to probe-relocrt.ps1, and the reason its result must
# not be overstated.
#
# probe-relocrt measured the OUTCOME: a relocated msys-2.0.dll starts at Low
# while the shipped runtime is held.  The obvious explanation was that the
# \BaseNamedObjects\msys-2.0S5-<key> name is derived from the DLL's PATH.  It is
# NOT that simple - the first relocated copy's key was dd50a72ab4668b33, the
# same key the record had already noted from a DIFFERENT path.  If every
# non-standard layout hashes to one value then two relocated runtimes contend
# with EACH OTHER, which matters for a relay that would ship its own copy.
# So this puts copies at THREE different shapes - a plain directory, a deeper
# one, and a real <root>\usr\bin layout - and holds them all alive at once
# beside the shipped runtime, scanning the namespace ONCE so the keys are seen
# together rather than inferred.
#
# MEASURED 16 Sep 2026, unelevated: 3 copies -> 1 relocated key.  FALSIFIED.
# Relocation does separate the relay from sd (probe-relocrt measured that), but
# every unregistered copy on the machine shares ONE namespace - so the relay
# would share it with any other software shipping an msys-2.0.dll, which is the
# RELEASE_1.1 53 class of exposure rather than a private runtime.
#
# Exit 0 = each path got its own key (3 relocated keys, all distinct)
# Exit 1 = they collide - the key is NOT per-path; say so before relying on it
# Exit 2 = could not run

function Say([string]$s) { Write-Host $s }

$msysbin   = 'C:/msys64/usr/bin'
$stage     = Join-Path $env:TEMP 'relocrt'
$cygshared = 'C:/Users/Don/SDCoreProject/sd4windows/sdb_ai/sd64/gplbld/probe-cygshared.exe'

# Three deliberately different shapes: a plain dir, a deeper one, and one laid
# out like a real install (<root>\usr\bin), since Cygwin strips that suffix.
$paths = @(
  (Join-Path $stage 'rtA'),
  (Join-Path $stage 'deeper\rtB'),
  (Join-Path $stage 'rtC\usr\bin')
)

Say "== Inputs, resolved"
Say "  shipped bin   : $msysbin"
Say "  scanner       : $cygshared"
if (-not (Test-Path $cygshared)) { Say "COULD NOT RUN: missing $cygshared"; exit 2 }

foreach ($p in $paths) {
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  Copy-Item "$msysbin/msys-2.0.dll" (Join-Path $p 'msys-2.0.dll') -Force
  Copy-Item "$msysbin/sleep.exe"    (Join-Path $p 'sleep.exe')    -Force
  Say "  copy          : $p"
}

function Scan([string]$label) {
  $o = Join-Path $stage "k2-$label.txt"
  Start-Process -FilePath $cygshared -NoNewWindow -Wait `
                -RedirectStandardOutput $o `
                -RedirectStandardError (Join-Path $stage "k2-$label-err.txt") | Out-Null
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

$procs = @()
$live = @()
try {
  Say "== Holding the shipped runtime and all three copies alive"
  $procs += Start-Process -FilePath "$msysbin/sleep.exe" -ArgumentList '25' -PassThru -WindowStyle Hidden
  foreach ($p in $paths) {
    $procs += Start-Process -FilePath (Join-Path $p 'sleep.exe') -ArgumentList '25' -PassThru -WindowStyle Hidden
  }
  Start-Sleep -Milliseconds 1200
  $dead = @($procs | Where-Object { $_.HasExited })
  if ($dead.Count -gt 0) { Say "COULD NOT RUN: $($dead.Count) holder(s) exited early"; exit 2 }
  Say "  holders alive : $($procs.Count) (1 shipped + 3 relocated)"
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
Say "  idle          : $($idle.Count) - $($idle -join ', ')"
Say "  all alive     : $($live.Count) - $($live -join ', ')"
$new = @($live | Where-Object { $idle -notcontains $_ })
Say "  relocated keys: $($new.Count) - $($new -join ', ')"

if ($live.Count -eq 0) { Say "COULD NOT RUN: the scan saw nothing"; exit 2 }
if ($new.Count -eq 3) {
  Say "ANSWERED: three copies at three paths produced THREE distinct keys."
  Say "  The key is genuinely per-path.  A relocated relay runtime contends"
  Say "  neither with sd's nor with another relocated one."
  exit 0
}
Say "FALSIFIED: 3 copies produced $($new.Count) relocated key(s), not 3."
Say "  The key is NOT simply per-path.  probe-relockey's 'path-derived' claim"
Say "  is too strong - relocation still separates the relay from sd (relocrt"
Say "  measured that), but do not assume two relocated runtimes are separate."
exit 1
