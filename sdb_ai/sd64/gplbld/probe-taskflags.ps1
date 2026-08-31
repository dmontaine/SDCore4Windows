# probe-taskflags.ps1 - drive the wizard's tasks page and read back what it did.
#
#   C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\probe-taskflags.ps1
#
# ORDINARY UNELEVATED PROMPT.  It compiles a probe installer that has no
# [Files], no [Run] and no app dir, walks it to the tasks page, drives the
# checkboxes, and aborts.  It installs nothing and needs no run token, no
# cycle and no elevation.  ~10 seconds.
#
# Exit 0 both legs measured, 2 anything that would make the answer a guess.
#
# ***WHAT IT IS FOR - READ PRE_RELEASE 67 AND 85 BEFORE CHANGING IT.***  Those
# two entries were written round the sentence "only a person can judge this",
# because ISCC checks that tasks COMPILE, not that they BEHAVE, and no cycle or
# suite run ever renders the tasks page.  Between them they cost four builds
# and three hand-offs to the owner, and 85's second hand-off reached a wrong
# conclusion - "the flags did not work" - that this script disproves in ten
# seconds.  See probe-taskflags.iss's header for how it clicks.
#
# NOT INSTALLED AND NOT SHIPPED - both this and the .iss must be on
# assert-current.ps1's $neverShipped list, or the tree reports STALE merely
# because they exist, and then every verifier that calls assert-current
# refuses.  Session 79 paid for that with three scripts at once.

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$Iss    = Join-Path $Gplbld 'sd.iss'
$Probe  = Join-Path $Gplbld 'probe-taskflags.iss'
$Iscc   = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
$Work   = Join-Path $env:TEMP 'probe-taskflags'
$Hkcu   = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\SDProbeTaskFlags_is1'
# SD's own AppId, from sd.iss:38.  READ ONLY - nothing here writes to it.
$SdKey  = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{9F2B7C41-3D6A-4E58-9B0F-5C7A1E2D8B34}_is1'

# The four entries this probe copies out of sd.iss.
$Names = @('sshserver', 'sshserver\sshremote', 'apiremote', 'apiremote\apinetwork')

Write-Host 'probe-taskflags - inputs actually used'
Write-Host "  gplbld    : $Gplbld"
Write-Host "  sd.iss    : $Iss"
Write-Host "  probe .iss: $Probe"
Write-Host "  ISCC      : $Iscc"
Write-Host "  work dir  : $Work"
Write-Host ''

foreach ($f in @($Iss, $Probe, $Iscc)) {
    if (-not (Test-Path -LiteralPath $f)) {
        Write-Host "probe-taskflags: missing $f"
        exit 2
    }
}

# --- the drift guard -------------------------------------------------------
# probe-taskflags.iss holds a COPY of sd.iss's four [Tasks] entries, and a copy
# is exactly the thing that rots into a false PASS: change sd.iss's flags, leave
# the copy, and this measures a pair that no longer ships.  So compare them
# every run and refuse rather than report.
function Get-TaskEntries {
    param([string]$Path)
    $raw = Get-Content -LiteralPath $Path -Raw
    if ($null -eq $raw) { $raw = '' }
    # Join Inno's backslash line-continuations into one logical line each.
    $joined = [regex]::Replace($raw, '\\\r?\n\s*', ' ')
    $out = @{}
    foreach ($n in $Names) {
        $pat = '(?m)^\s*Name:\s*"' + [regex]::Escape($n) + '"\s*;(.*)$'
        $m = [regex]::Match($joined, $pat)
        if (-not $m.Success) { $out[$n] = '<ABSENT>'; continue }
        $body = $m.Groups[1].Value
        # Flags are the whole question; normalise whitespace so a reflow of the
        # source is not reported as a behaviour change.
        $fm = [regex]::Match($body, 'Flags:\s*([^;]*)')
        if ($fm.Success) {
            $out[$n] = ($fm.Groups[1].Value -replace '\s+', ' ').Trim()
        } else {
            $out[$n] = '<NO FLAGS>'
        }
    }
    return $out
}

$inSd    = Get-TaskEntries -Path $Iss
$inProbe = Get-TaskEntries -Path $Probe

$drift = 0
Write-Host 'FLAGS, sd.iss vs the probe''s copy:'
foreach ($n in $Names) {
    $a = $inSd[$n]
    $b = $inProbe[$n]
    # -cne: PowerShell compares case-insensitively by default, and Inno flag
    # names are lower case by convention rather than by rule.
    if ($a -cne $b) {
        $drift = $drift + 1
        Write-Host "  DRIFT  $n"
        Write-Host "         sd.iss : '$a'"
        Write-Host "         probe  : '$b'"
    } else {
        Write-Host "  same   $n : '$a'"
    }
}
if ($inSd['sshserver'] -eq '<ABSENT>' -and $inSd['apiremote'] -eq '<ABSENT>') {
    # Refuse the null case out loud: finding nothing in sd.iss must not read as
    # "no drift".
    Write-Host ''
    Write-Host 'VOID: no task entries were found in sd.iss at all, so the'
    Write-Host '      comparison above compared nothing.'
    exit 2
}
if ($drift -gt 0) {
    Write-Host ''
    Write-Host "REFUSED: $drift entry/entries differ.  sd.iss has moved and the"
    Write-Host '         probe would measure a pair that no longer ships.'
    Write-Host '         Copy the changed entries into probe-taskflags.iss.'
    exit 2
}
Write-Host ''

# --- what the machine already remembers ------------------------------------
# Context, not a measurement: leg 2 is about this value existing at all.
Write-Host 'SD''s RECORDED TASK SELECTION (read-only, HKLM):'
if (Test-Path -LiteralPath $SdKey) {
    $sel = (Get-ItemProperty -LiteralPath $SdKey).'Inno Setup: Selected Tasks'
    $ver = (Get-ItemProperty -LiteralPath $SdKey).'Inno Setup: Setup Version'
    Write-Host "  Selected Tasks : '$sel'"
    Write-Host "  Setup Version  : '$ver'"
    Write-Host '  sd.iss does not set UsePreviousTasks, so it DEFAULTS TO YES and'
    Write-Host '  this string becomes the tasks page defaults on the next install.'
} else {
    $sel = 'addtopath,sshremoteopen,apiremote,apiremote\apinetwork'
    Write-Host '  SD is not installed on this machine.'
    Write-Host "  Leg 2 will use the string recorded on 31 Aug 2026 instead:"
    Write-Host "  '$sel'"
}
Write-Host ''

# --- run one leg -----------------------------------------------------------
function Invoke-Leg {
    param([int]$Leg)

    $log = Join-Path $Work "leg$Leg.log"
    $exe = Join-Path $Work 'probe-taskflags.exe'
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue

    # ***ISCC WRITES ITS ERRORS TO stderr, AND 2>&1 IS NOT ENOUGH ON ITS OWN.***
    # Under ErrorActionPreference Stop a native command writing to stderr raises
    # a terminating NativeCommandError, so the redirect captures the text and
    # the script dies anyway - which is what happened the first time this ran,
    # killing it before it could print ISCC's own message.  The preference has
    # to come down for the duration of the call.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    if ($Leg -eq 2) {
        $out = & $Iscc '/DLEG2' "/O$Work" $Probe 2>&1
    } else {
        $out = & $Iscc "/O$Work" $Probe 2>&1
    }
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($rc -ne 0) {
        Write-Host "  ISCC exit $rc compiling leg ${Leg}:"
        $out | Select-Object -Last 12 | ForEach-Object { Write-Host "    $_" }
        return $null
    }

    # ***WAIT ON THE LOG, NOT ON THE WINDOW.***  The probe writes its transcript
    # and THEN asks the wizard to close, so the log appearing is the completed
    # measurement and the close is only tidiness.  WizardForm.Close proved
    # unreliable on 31 Aug 2026 - a wizard that does not have focus does not
    # always act on it - and waiting for the process to exit turned a run that
    # had already succeeded into a 30-second hang, twice.  So: poll for the
    # file, then kill the window whether or not it managed to close itself.
    #
    # An instrument that can hang forever is worse than one that fails, and a
    # hung command has cost this project whole sessions.
    Remove-Item -LiteralPath $log -Force -ErrorAction SilentlyContinue
    $p = Start-Process -FilePath $exe -ArgumentList "/TASKLOG=`"$log`"" -PassThru

    $deadline = (Get-Date).AddSeconds(30)
    while (-not (Test-Path -LiteralPath $log) -and (Get-Date) -lt $deadline) {
        if ($p.HasExited) { break }
        Start-Sleep -Milliseconds 200
    }
    $wrote = Test-Path -LiteralPath $log

    if (-not $p.HasExited) {
        try { $p.Kill() } catch { }
        try { $p.WaitForExit(5000) | Out-Null } catch { }
    }

    if (-not $wrote) {
        Write-Host "  NO LOG - the tasks page was never reached (setup exit $($p.ExitCode))."
        return $null
    }
    return (Get-Content -LiteralPath $log)
}

New-Item -ItemType Directory -Force -Path $Work | Out-Null

# ---- leg 1: the flags on their own ----------------------------------------
Write-Host '############ LEG 1 - UsePreviousTasks=no, the flags alone ############'
$leg1 = Invoke-Leg -Leg 1
if ($null -ne $leg1) { $leg1 | ForEach-Object { Write-Host $_ } }
Write-Host ''

# ---- leg 2: with a previous selection restored -----------------------------
# Written under the PROBE's own throwaway key.  SD's key is never touched.
Write-Host '############ LEG 2 - UsePreviousTasks=yes, selection restored ############'
Write-Host "  pre-writing '$sel'"
Write-Host "  under $Hkcu"
New-Item -Path $Hkcu -Force | Out-Null
New-ItemProperty -LiteralPath $Hkcu -Name 'Inno Setup: Selected Tasks' `
    -Value $sel -PropertyType String -Force | Out-Null
$back = (Get-ItemProperty -LiteralPath $Hkcu).'Inno Setup: Selected Tasks'
if ($back -cne $sel) {
    Write-Host '  MISMATCH on read-back; leg 2 would measure the wrong thing.'
    $leg2 = $null
} else {
    Write-Host '  read back and matched.'
    Write-Host ''
    $leg2 = Invoke-Leg -Leg 2
    if ($null -ne $leg2) { $leg2 | ForEach-Object { Write-Host $_ } }
}

# Always clean up the probe's own key, whatever happened above.
if (Test-Path -LiteralPath $Hkcu) {
    Remove-Item -LiteralPath $Hkcu -Recurse -Force -Confirm:$false
}
Write-Host ''
Write-Host "leg 2 key removed, still present: $(Test-Path -LiteralPath $Hkcu)"

# --- verdict ---------------------------------------------------------------
Write-Host ''
$bad = 0
foreach ($pair in @(@('1', $leg1), @('2', $leg2))) {
    $n = $pair[0]; $lines = $pair[1]
    if ($null -eq $lines) {
        Write-Host "LEG ${n}: DID NOT RUN."
        $bad = $bad + 1
        continue
    }
    # Anchor on the wording the probe prints ONLY when it drove both pairs -
    # not on any string the VOID path also carries.
    if ($lines -match 'VERDICT: both pairs were driven') {
        Write-Host "LEG ${n}: measured."
    } else {
        Write-Host "LEG ${n}: VOID - it did not drive both pairs."
        $bad = $bad + 1
    }
}
if ($bad -gt 0) { exit 2 }

Write-Host ''
Write-Host 'Both legs measured.  Compare their AS RENDERED lines: that is where'
Write-Host 'a restored selection overrides the `unchecked` flags.'
exit 0
