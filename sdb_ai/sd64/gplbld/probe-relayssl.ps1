# probe-relayssl.ps1 - UNELEVATED.  RELEASE_1.1 43 option 2's two falsified-ifs.
#
# The owner chose option 2 on 16 Sep 26: the TLS relay becomes a RELOCATED MSYS2
# program at Low integrity, so gplsrc/sd_tlssrv.c stays ONE source shared with
# Linux.  probe-relocrt proved a relocated runtime starts at Low beside sd, and
# probe-relocattr proved it gets its own object-directory key.  Neither involved
# OpenSSL, and the relay is nothing without it.  This drives probe-relayssl.exe,
# which asks the LOADER where it got each module and refuses a collision.
#
#   falsified-if (i)  the relay's OpenSSL cannot be built against the relocated
#                     runtime                                    -> child exit 4
#   falsified-if (ii) the second msys-2.0.dll cannot be staged without colliding
#                     with sd's on PATH                          -> child exit 3
#
# THE CONDITION IS THE PRODUCT'S, NOT A CONVENIENT ONE: a Medium MSYS2 process of
# the SHIPPED runtime is held alive throughout, because sd always is one, and
# that is what killed the MSYS2-at-Low relay before relocation.
#
# TWO RULES FROM 16 Sep, BOTH PAID FOR, BOTH APPLIED HERE:
#  * Check a child's imports (objdump -p) before staging copies of it - a
#    relocated sleep.exe missing msys-intl-8.dll died in the LOADER and put 32
#    CSRSS error dialogs on the owner's screen.
#  * NEVER COUNT A PROCESS BECAUSE IT EXISTS.  A process blocked on a hard-error
#    dialog has not exited, so HasExited called them all healthy.  The holder
#    must SAY it started, and so must the child.
#
# Exit 0 = ANSWERED: relocated OpenSSL relay runs at Low, own modules only
# Exit 1 = FALSIFIED: the child named which of (i)/(ii) failed
# Exit 2 = COULD NOT RUN: a control failed, so nothing was measured

function Say([string]$s) { Write-Host $s }

$gplbld    = 'C:/Users/Don/SDCoreProject/sd4windows/sdb_ai/sd64/gplbld'
$msysbin   = 'C:/msys64/usr/bin'
$stage     = Join-Path $env:TEMP ('relayssl-' + (Get-Date -Format 'HHmmss-fff'))
$rt        = Join-Path $stage 'relay'
$cygshared = "$gplbld/probe-cygshared.exe"
$relayssl  = "$gplbld/probe-relayssl.exe"
$lowmsys   = "$gplbld/probe-lowmsys.exe"

# The exact closure probe-relayssl.exe imports (objdump -p), all of which must
# come from the relay's own directory.
$needed = @('msys-2.0.dll', 'msys-ssl-3.dll', 'msys-crypto-3.dll')

Say "== Inputs, resolved"
Say "  gplbld        : $gplbld"
Say "  relay exe     : $relayssl"
Say "  holder        : $lowmsys --sleep  (imports msys-2.0.dll only)"
Say "  stage         : $rt"
foreach ($f in @($cygshared, $relayssl, $lowmsys)) {
  if (-not (Test-Path $f)) { Say "COULD NOT RUN: missing $f"; exit 2 }
}
foreach ($d in $needed) {
  if (-not (Test-Path "$msysbin/$d")) { Say "COULD NOT RUN: missing $msysbin/$d"; exit 2 }
}

New-Item -ItemType Directory -Force -Path $rt | Out-Null
foreach ($d in $needed) { Copy-Item "$msysbin/$d" (Join-Path $rt $d) -Force }
Copy-Item $relayssl (Join-Path $rt 'probe-relayssl.exe') -Force
$relocExe = Join-Path $rt 'probe-relayssl.exe'
Say "  staged        : $($needed -join ', ') + probe-relayssl.exe"

# PATH with NO msys64 on it: the staged copies are the only reachable ones, so a
# pass cannot be the shipped runtime answering.
$sys      = "$env:SystemRoot\system32;$env:SystemRoot"
$origPath = $env:PATH
$relayPath = "$rt;$sys"
$script:n = 0

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
  $script:lastOut = ''
  foreach ($f in @($o, $e)) {
    if ((Test-Path $f) -and (Get-Item $f).Length -gt 0) {
      $txt = Get-Content $f
      $script:lastOut += ($txt -join "`n")
      $txt | ForEach-Object { Write-Host "  | $_" }
    }
  }
  return [int]$p.ExitCode
}

$holder = $null
$medium = $null; $low = $null; $lowText = ''
try {
  Say "== The holder: a Medium MSYS2 process of the SHIPPED runtime (sd's condition)"
  $holderOut = Join-Path $stage 'holder.txt'
  $holder = Start-Process -FilePath $lowmsys -ArgumentList '--sleep' -PassThru -WindowStyle Hidden `
                          -RedirectStandardOutput $holderOut `
                          -RedirectStandardError (Join-Path $stage 'holder-err.txt')
  Start-Sleep -Milliseconds 1200
  if (-not ((Test-Path $holderOut) -and (Select-String -Path $holderOut -Pattern 'msyshello: started' -Quiet))) {
    Say "COULD NOT RUN: the holder never executed - it did not say it started."
    exit 2
  }
  Say "  holder        : $(((Get-Content $holderOut | Select-String 'msyshello: started').Line).Trim())"

  Say "== CONTROL: the relocated relay at MEDIUM (must RUN, or a Low failure means nothing)"
  $medium = Run-Native $relocExe $null $relayPath
  Say "  control exit  : $medium"

  Say "== MEASUREMENT: the relocated relay at LOW, shipped runtime held"
  $low = Run-Native $cygshared @('--low', $relocExe) $relayPath
  $lowText = $script:lastOut
  Say "  measured exit : $low"
}
finally {
  $env:PATH = $origPath
  if ($holder -and -not $holder.HasExited) { Stop-Process -Id $holder.Id -Force -ErrorAction SilentlyContinue }
  Say "  holder stopped"
}

Say ""
Say "== Verdict"
Say "  control (relocated at Medium) : exit $medium"
Say "  measured (relocated at Low)   : exit $low"

if ($medium -eq 3) {
  Say "COULD NOT RUN: even at Medium the staged copies were not what loaded."
  Say "  That is a staging fault in this script, not a finding about Low."
  exit 2
}
if ($medium -ne 0) {
  Say "COULD NOT RUN: the control failed (exit $medium), so the relocated build is"
  Say "  broken and a Low failure would not have been about integrity."
  exit 2
}

# The child's own wording decides, not the launcher's exit code.
$ranLow    = $lowText -match 'relayssl: started.*integrity 0x1000'
$ownModules = $lowText -match 'ALL THREE MODULES CAME FROM THIS DIRECTORY'
$tlsOk     = $lowText -match 'TLS 1\.3 server context OK, RNG OK'
$collision = $lowText -match 'COLLISION'
Say "  child ran at Low (0x1000)     : $ranLow"
Say "  all modules from own dir      : $ownModules"
Say "  TLS 1.3 context + RNG         : $tlsOk"

if (-not $ranLow) {
  Say "COULD NOT RUN: the child never reported Low integrity, so what ran is unknown."
  exit 2
}
if ($collision -or -not $ownModules) {
  Say "FALSIFIED (ii): the relocated relay loaded a module from outside its own"
  Say "  directory - sd's copy won. Option 2 cannot be staged this way."
  exit 1
}
if (-not $tlsOk) {
  Say "FALSIFIED (i): OpenSSL does not work against the relocated runtime at Low."
  exit 1
}
Say ""
Say "ANSWERED: a RELOCATED MSYS2 relay runs at LOW integrity, with a Medium"
Say "  process of the shipped runtime alive, loading msys-2.0.dll, msys-ssl-3.dll"
Say "  and msys-crypto-3.dll from ITS OWN directory, and OpenSSL builds a TLS 1.3"
Say "  server context and draws entropy there.  Both of option 2's recorded"
Say "  falsified-ifs are answered.  Not covered here: the account switch, the"
Say "  privilege strip, and the socket/pipe handover to a RELOCATED child."
exit 0
