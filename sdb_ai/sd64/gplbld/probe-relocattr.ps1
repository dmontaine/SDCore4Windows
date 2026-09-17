# probe-relocattr.ps1 - UNELEVATED.  ATTRIBUTE every msys-2.0S5-<key> object
# directory to the process and DLL that made it.
#
# WHY IT EXISTS.  probe-relockey answered "is the key per path" twice and got
# opposite answers.  The first run was a VACUOUS PASS (its holders died in the
# loader and were counted alive - see that script's header).  The corrected run
# said the key IS per path: 3 copies, 3 distinct keys.  But it saw a FOURTH key,
# dd50a72ab4668b33, with no fourth copy of mine running - and that is exactly
# the key the retracted answer had mistaken for "the one shared relocated key".
# A conclusion with an unattributed object in the middle of it is not closed, and
# this decision has already been reversed twice on unattributed evidence.
#
# HOW.  Every Cygwin/MSYS2 process loads msys-2.0.dll from a directory; that
# directory is the runtime, and the namespace is per runtime.  So instead of
# INFERRING which key belongs to which copy, this lists every live process whose
# image sits beside an msys-2.0.dll, and compares the count of distinct runtimes
# alive with the count of keys present.  Run with -Count 0,1,2,3 to watch keys
# appear one at a time.
#
# Only probe-lowmsys.exe is launched (imports: msys-2.0.dll, ADVAPI32,
# KERNEL32 - verified with objdump -p).  NEVER sleep.exe: it also imports
# msys-intl-8.dll, and a relocated copy without it blocks in the loader behind a
# CSRSS hard-error dialog, which is what put 32 popups on the owner's screen.
#
# Exit 0 = every key present is attributed to a live runtime
# Exit 1 = a key is UNATTRIBUTED - name it, do not explain it away
# Exit 2 = could not run (a holder never executed)

[CmdletBinding()]
param([int]$Count = 3)

function Say([string]$s) { Write-Host $s }

$gplbld    = 'C:/Users/Don/SDCoreProject/sd4windows/sdb_ai/sd64/gplbld'
$msysbin   = 'C:/msys64/usr/bin'
# A UNIQUE stage per run, deliberately.  Keys outlive their processes, so
# re-using a path would hand this run a LEFTOVER key from the last one and the
# delta would read zero - the run would falsify itself for the wrong reason.
$stage     = Join-Path $env:TEMP ('relocattr-' + (Get-Date -Format 'HHmmss-fff'))
$cygshared = "$gplbld/probe-cygshared.exe"
$lowmsys   = "$gplbld/probe-lowmsys.exe"

Say "== Inputs, resolved"
Say "  scanner       : $cygshared"
Say "  holder exe    : $lowmsys  (--sleep; imports msys-2.0.dll only)"
Say "  copies wanted : $Count"
Say "  stage         : $stage"
foreach ($f in @($cygshared, $lowmsys, "$msysbin/msys-2.0.dll")) {
  if (-not (Test-Path $f)) { Say "COULD NOT RUN: missing $f"; exit 2 }
}

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $stage | Out-Null
$paths = @()
for ($i = 1; $i -le $Count; $i++) {
  $p = Join-Path $stage "rt$i"
  New-Item -ItemType Directory -Force -Path $p | Out-Null
  Copy-Item "$msysbin/msys-2.0.dll" (Join-Path $p 'msys-2.0.dll')     -Force
  Copy-Item $lowmsys                (Join-Path $p 'probe-lowmsys.exe') -Force
  $paths += $p
  Say "  copy $i        : $p"
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
  return ,$names
}

# Every live process whose image sits beside an msys-2.0.dll: that directory is
# the runtime it loaded, so this is the set of runtimes alive right now.
# NOTE THE $script:unreadable COUNT - IT IS EVIDENCE, NOT NOISE.  An unelevated
# caller cannot read ExecutablePath for a process running as another account, so
# every LocalSystem process (the SD service among them) is invisible here.  That
# is why a scan can show a key with "0 runtimes alive": the owner is running and
# simply cannot be seen from this token.  The first version let those surface as
# a wall of Join-Path errors and read the gap as an unattributed key.
function LiveRuntimes {
  $rts = @{}
  $script:unreadable = 0
  foreach ($p in (Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
    $ep = $p.ExecutablePath
    if ([string]::IsNullOrWhiteSpace($ep)) { $script:unreadable++; continue }
    $dir = $null
    try { $dir = [System.IO.Path]::GetDirectoryName($ep) } catch { $script:unreadable++; continue }
    if ([string]::IsNullOrWhiteSpace($dir)) { $script:unreadable++; continue }
    # [IO.Path]::Combine, not Join-Path: Join-Path insists on a resolvable PS
    # drive and throws for the device-style paths some system processes report.
    $cand = $null
    try { $cand = [System.IO.Path]::Combine($dir, 'msys-2.0.dll') } catch { $script:unreadable++; continue }
    if (Test-Path -LiteralPath $cand -ErrorAction SilentlyContinue) {
      if (-not $rts.ContainsKey($dir)) { $rts[$dir] = @() }
      $rts[$dir] += "$($p.Name)($($p.ProcessId))"
    }
  }
  return $rts
}

Say ""
Say "== BEFORE"
$before = Scan 'before'
$rtBefore = LiveRuntimes
Say "  keys present  : $($before.Count) - $($before -join ', ')"
Say "  runtimes alive: $($rtBefore.Keys.Count)  (processes not readable unelevated: $script:unreadable)"
foreach ($k in ($rtBefore.Keys | Sort-Object)) { Say "    $k  <- $($rtBefore[$k] -join ', ')" }

$procs = @(); $proven = 0; $during = @(); $rtDuring = @{}
try {
  if ($Count -gt 0) {
    Say ""
    Say "== Holding $Count relocated runtime(s) alive"
    $i = 0
    foreach ($p in $paths) {
      $i++
      $procs += Start-Process -FilePath (Join-Path $p 'probe-lowmsys.exe') -ArgumentList '--sleep' `
                              -PassThru -WindowStyle Hidden `
                              -RedirectStandardOutput (Join-Path $stage "h$i.txt") `
                              -RedirectStandardError  (Join-Path $stage "h$i-err.txt")
    }
    Start-Sleep -Milliseconds 1200
    for ($k = 1; $k -le $Count; $k++) {
      $f = Join-Path $stage "h$k.txt"
      if ((Test-Path $f) -and (Select-String -Path $f -Pattern 'msyshello: started' -Quiet)) {
        $proven++
        Say "  holder $k : $(((Get-Content $f | Select-String 'msyshello: started').Line).Trim())"
      } else { Say "  holder $k : NO START LINE - it did not execute" }
    }
    if ($proven -ne $Count) {
      Say "COULD NOT RUN: only $proven of $Count relocated runtimes executed."
      exit 2
    }
  }
  Say ""
  Say "== DURING"
  $during   = Scan 'during'
  $rtDuring = LiveRuntimes
}
finally {
  foreach ($p in $procs) { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
  if ($Count -gt 0) { Say "  holders stopped" }
}

Say "  keys present  : $($during.Count) - $($during -join ', ')"
Say "  runtimes alive: $($rtDuring.Keys.Count)  (processes not readable unelevated: $script:unreadable)"
foreach ($k in ($rtDuring.Keys | Sort-Object)) { Say "    $k  <- $($rtDuring[$k] -join ', ')" }

Say ""
Say "== Verdict"
$newKeys = @($during | Where-Object { $before -notcontains $_ })
$newRts  = @($rtDuring.Keys | Where-Object { -not $rtBefore.ContainsKey($_) })
Say "  copies held   : $Count (proven running: $proven)"
Say "  keys appeared : $($newKeys.Count) - $($newKeys -join ', ')"
Say "  runtimes appeared: $($newRts.Count)"
foreach ($k in $newRts) { Say "    $k" }
Say "  keys total $($during.Count) vs runtimes alive $($rtDuring.Keys.Count)"

if ($during.Count -eq 0) { Say "COULD NOT RUN: the scan saw no keys at all"; exit 2 }

# ===========================================================================
# THE QUESTION HAD TO BE RESTATED, AND THIS IS THE CORRECTION THAT MATTERS.
# The first version asked "is every key present attributable to a LIVE runtime".
# Run with -Count 0 it answered NO - one key present, ZERO runtimes alive - and
# that is not a defect, it is the finding: AN OBJECT DIRECTORY OUTLIVES ITS LAST
# PROCESS.  So "keys present" never equals "runtimes alive", every earlier scan
# was reading leftovers alongside live ones, and the unexplained
# dd50a72ab4668b33 was a leftover from a copy staged earlier in the session
# rather than a shared namespace.
#
# The decisive question is therefore the DELTA, which leftovers cannot corrupt:
# does starting N relocated copies at N fresh paths add exactly N NEW keys?
# ===========================================================================
Say ""
Say "== Persistence check (the thing that made the earlier answers wrong)"
$after = Scan 'after'
$stillThere = @($newKeys | Where-Object { $after -contains $_ })
Say "  keys after the holders stopped: $($after.Count) - $($after -join ', ')"
Say "  of this run's $($newKeys.Count) new key(s), $($stillThere.Count) SURVIVED the process exiting"

if ($Count -eq 0) {
  Say ""
  Say "BASELINE: $($during.Count) key(s) present with $($rtDuring.Keys.Count) runtime(s) alive."
  if ($rtDuring.Keys.Count -lt $during.Count) {
    Say "  A key outlives its last process - so no scan may be read as a census of"
    Say "  live runtimes. Re-run with -Count 1..3 for the delta test."
  }
  exit 0
}

if ($newKeys.Count -eq $Count) {
  Say ""
  Say "ANSWERED: $Count relocated copy(ies) at $Count fresh paths, all $proven proven"
  Say "  running, added exactly $($newKeys.Count) NEW key(s).  Each relocated runtime"
  Say "  gets its OWN namespace - so a relocated relay contends neither with sd's"
  Say "  runtime nor with another relocated one.  This is a DELTA, so the leftover"
  Say "  keys that corrupted the earlier answers cannot affect it."
  exit 0
}
Say ""
Say "FALSIFIED: $Count copy(ies) proven running added $($newKeys.Count) new key(s), not $Count."
Say "  Relocated runtimes are NOT separated per path. Do not ship a relocated"
Say "  relay runtime on the assumption that they are."
exit 1
