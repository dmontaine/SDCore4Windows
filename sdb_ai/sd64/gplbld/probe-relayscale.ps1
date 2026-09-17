# probe-relayscale.ps1 - UNELEVATED.  RELEASE_1.1 43's runtime choice, asked as
# a LOAD question by the owner: "which option will work best if there are 50
# remote users using the api simultaneously?"
#
# The relay is PER CONNECTION, so 50 simultaneous API users means 50 relay
# processes alive at once.  The two candidate runtimes differ in what starting
# one costs and in what 50 of them share:
#   native UCRT64  - no emulation layer, no shared state between relays
#   MSYS2 (relocated) - msys-2.0.dll per process, and every unregistered copy
#                       shares ONE \BaseNamedObjects\msys-2.0S5-<key> namespace
#                       and its shared sections (probe-relockey.ps1 measured the
#                       sharing; this measures what it costs at 50).
#
# WHAT THIS MEASURES AND WHAT IT DOES NOT.  It launches -Count processes of each
# runtime as fast as it can and waits for all of them, reporting how many
# started, how long the whole wave took, and the failure mode of any that did
# not.  It does NOT model TLS, sockets, or the S4U mint - those are the same
# work whichever runtime is chosen.  Both waves run at MEDIUM integrity so the
# comparison isolates RUNTIME cost; whether each can run at Low is already
# settled separately (probe-relocrt.ps1).
#
# The shipped C:\msys64 runtime is held alive throughout, because that is the
# product's condition: sd is always a live process of it.
#
# Exit 0 = both waves completed; the comparison is in the verdict
# Exit 1 = a wave lost processes - that IS the finding, and it is named
# Exit 2 = could not run

[CmdletBinding()]
param(
  [int]$Count = 50,
  [int]$Waves = 3
)

function Say([string]$s) { Write-Host $s }

$gplbld  = 'C:/Users/Don/SDCoreProject/sd4windows/sdb_ai/sd64/gplbld'
$msysbin = 'C:/msys64/usr/bin'
$stage   = Join-Path $env:TEMP 'relayscale'
$rt      = Join-Path $stage 'rt'

$native = "$gplbld/probe-relaychild.exe"   # --hello: initialise and exit 7
$msys   = "$gplbld/probe-lowmsys.exe"      # exit 0

Say "== Inputs, resolved"
Say "  count per wave: $Count"
Say "  waves each    : $Waves"
Say "  native child  : $native   (--hello, expected exit 7)"
Say "  msys2 child   : $msys     (relocated copy, expected exit 0)"
Say "  stage         : $stage"
if ($Count -lt 1) { Say "COULD NOT RUN: -Count must be at least 1"; exit 2 }
foreach ($f in @($native, $msys, "$msysbin/msys-2.0.dll", "$msysbin/sleep.exe")) {
  if (-not (Test-Path $f)) { Say "COULD NOT RUN: missing $f"; exit 2 }
}

if (Test-Path $stage) { Remove-Item -Recurse -Force $stage -ErrorAction SilentlyContinue }
New-Item -ItemType Directory -Force -Path $rt | Out-Null
Copy-Item "$msysbin/msys-2.0.dll" (Join-Path $rt 'msys-2.0.dll') -Force
Copy-Item $msys                   (Join-Path $rt 'probe-lowmsys.exe') -Force
$msysReloc = Join-Path $rt 'probe-lowmsys.exe'
Say "  relocated msys: $msysReloc"

# One wave: launch $Count copies without waiting, then wait for all.
function Wave([string]$exe, $argl, [int]$okCode, [string]$label) {
  $procs = New-Object System.Collections.ArrayList
  $sw = [System.Diagnostics.Stopwatch]::StartNew()
  for ($i = 0; $i -lt $Count; $i++) {
    try {
      if ($argl) { $p = Start-Process -FilePath $exe -ArgumentList $argl -PassThru -WindowStyle Hidden -ErrorAction Stop }
      else       { $p = Start-Process -FilePath $exe                     -PassThru -WindowStyle Hidden -ErrorAction Stop }
      [void]$procs.Add($p)
    } catch {
      Say "  launch $i FAILED: $($_.Exception.Message)"
    }
  }
  $launched = $procs.Count
  $launchMs = $sw.ElapsedMilliseconds
  foreach ($p in $procs) { try { $p.WaitForExit(60000) | Out-Null } catch {} }
  $sw.Stop()
  $codes = @()
  foreach ($p in $procs) { try { $codes += [int]$p.ExitCode } catch { $codes += -999 } }
  $ok  = @($codes | Where-Object { $_ -eq $okCode }).Count
  $bad = @($codes | Where-Object { $_ -ne $okCode })
  $distinct = ($bad | Sort-Object -Unique | ForEach-Object { "0x{0:x}" -f $_ }) -join ', '
  Say ("  {0,-22} launched {1,3}/{2}  all-exited {3,6} ms  (launch {4} ms)  ok {5,3}  bad {6,3} {7}" -f `
       $label, $launched, $Count, $sw.ElapsedMilliseconds, $launchMs, $ok, $bad.Count, $(if ($bad.Count) { "[$distinct]" } else { '' }))
  return [pscustomobject]@{
    Label = $label; Launched = $launched; Ms = $sw.ElapsedMilliseconds
    Ok = $ok; Bad = $bad.Count; Codes = $distinct
  }
}

$holder = $null
$nat = @(); $cyg = @()
try {
  Say "== The holder (a Medium MSYS2 process of the SHIPPED runtime - sd's condition)"
  $holder = Start-Process -FilePath "$msysbin/sleep.exe" -ArgumentList '300' -PassThru -WindowStyle Hidden
  Start-Sleep -Milliseconds 700
  if ($holder.HasExited) { Say "COULD NOT RUN: the holder exited immediately"; exit 2 }
  Say "  holder pid    : $($holder.Id), alive"

  Say "== Waves of $Count, at MEDIUM integrity (isolates runtime cost)"
  for ($w = 1; $w -le $Waves; $w++) {
    Say "  -- wave $w"
    $nat += Wave $native    @('--hello') 7 "native UCRT64"
    $cyg += Wave $msysReloc $null        0 "MSYS2 relocated"
  }
}
finally {
  if ($holder -and -not $holder.HasExited) {
    Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue; Say "  holder stopped"
  }
}

if ($nat.Count -eq 0 -or $cyg.Count -eq 0) { Say "COULD NOT RUN: no wave completed"; exit 2 }

$natMs  = [math]::Round((($nat | Measure-Object Ms -Average).Average), 0)
$cygMs  = [math]::Round((($cyg | Measure-Object Ms -Average).Average), 0)
$natOk  = ($nat | Measure-Object Ok  -Sum).Sum
$cygOk  = ($cyg | Measure-Object Ok  -Sum).Sum
$natBad = ($nat | Measure-Object Bad -Sum).Sum
$cygBad = ($cyg | Measure-Object Bad -Sum).Sum
$total  = $Count * $Waves

Say ""
Say "== Verdict  ($Count concurrent, $Waves waves, $total each)"
Say ("  native UCRT64   : {0,6} ms mean per wave   ok {1}/{2}   bad {3}" -f $natMs, $natOk, $total, $natBad)
Say ("  MSYS2 relocated : {0,6} ms mean per wave   ok {1}/{2}   bad {3}" -f $cygMs, $cygOk, $total, $cygBad)
if ($natMs -gt 0) { Say ("  ratio           : MSYS2 is {0}x the native wall clock" -f ([math]::Round($cygMs / [double]$natMs, 1))) }
Say ("  per-process     : native {0} ms, MSYS2 {1} ms (wave wall clock / {2}; overlapped, so a floor not a latency)" -f `
     [math]::Round($natMs / [double]$Count, 1), [math]::Round($cygMs / [double]$Count, 1), $Count)

if ($natBad -gt 0 -or $cygBad -gt 0) {
  Say ""
  Say "FINDING: a wave LOST processes - native $natBad, MSYS2 $cygBad."
  Say "  A relay runtime that drops processes under concurrency fails the load"
  Say "  question outright, whatever its wall clock. The exit codes are above."
  exit 1
}

# ---------------------------------------------------------------------------
# PHASE 2 - the one that matches the product.  The waves above START and EXIT;
# a relay LIVES for the length of its session, so 50 API users means 50 relays
# alive AT ONCE.  That is option 2's specific risk and native has nothing like
# it: every relocated MSYS2 process shares one msys-2.0S5-<key> namespace and
# its shared sections, and Cygwin's shared region has a FIXED process table.
# Held with the relocated sleep.exe, which runs on the relocated runtime.
# ---------------------------------------------------------------------------
Say ""
Say "== PHASE 2: $Count MSYS2 relays ALIVE AT ONCE, in one shared namespace"
Copy-Item "$msysbin/sleep.exe" (Join-Path $rt 'sleep.exe') -Force
$liveExe = Join-Path $rt 'sleep.exe'
Say "  holder exe    : $liveExe"

$live = New-Object System.Collections.ArrayList
$holder2 = $null
$aliveCount = 0
try {
  $holder2 = Start-Process -FilePath "$msysbin/sleep.exe" -ArgumentList '60' -PassThru -WindowStyle Hidden
  for ($i = 0; $i -lt $Count; $i++) {
    try { [void]$live.Add((Start-Process -FilePath $liveExe -ArgumentList '30' -PassThru -WindowStyle Hidden -ErrorAction Stop)) }
    catch { Say "  start $i FAILED: $($_.Exception.Message)" }
  }
  Start-Sleep -Milliseconds 2500
  $aliveCount = @($live | Where-Object { -not $_.HasExited }).Count
  $died = @($live | Where-Object { $_.HasExited })
  Say "  started       : $($live.Count)/$Count"
  Say "  alive together: $aliveCount"
  if ($died.Count -gt 0) {
    $dc = ($died | ForEach-Object { try { "0x{0:x}" -f [int]$_.ExitCode } catch { '?' } } | Sort-Object -Unique) -join ', '
    Say "  DIED EARLY    : $($died.Count)  [$dc]"
  }
}
finally {
  foreach ($p in $live) { if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
  if ($holder2 -and -not $holder2.HasExited) { Stop-Process -Id $holder2.Id -Force -ErrorAction SilentlyContinue }
  Say "  phase 2 stopped"
}

Say ""
Say "== Verdict, phase 2"
Say "  $Count relocated MSYS2 processes alive at once, shipped runtime held: $aliveCount survived"
if ($aliveCount -lt $Count) {
  Say ""
  Say "FINDING: only $aliveCount of $Count stayed alive together."
  Say "  The shared namespace does not carry $Count concurrent relays, which is"
  Say "  decisive against the relocated-MSYS2 option at this load."
  exit 1
}

Say ""
Say "ANSWERED: both runtimes completed every process at $Count concurrent, and"
Say "  $Count relocated MSYS2 processes also lived together in one namespace."
Say "  The measured difference is wall clock (above), and NOTE THAT Start-Process"
Say "  DOMINATES IT - the launch figure is most of each wave - so read the RATIO,"
Say "  which is same-launcher, not the per-process milliseconds."
Say "  Nothing here models TLS, the socket handover, or the S4U mint per"
Say "  connection - that last is the untested scaling risk at this load, and it"
Say "  is the same work whichever runtime is chosen."
exit 0
