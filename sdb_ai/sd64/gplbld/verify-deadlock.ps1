# verify-deadlock.ps1 - GETLOCKS answers for a lock whose owner's session is
# gone, instead of dereferencing NULL.  RELEASE_1.1_FIXES.md 7 (Linux #7).
# ***ELEVATED POWERSHELL.  IT KILLS AN SD SESSION ON PURPOSE.***
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-deadlock.ps1
#
# Exit 0 "(gone)" was reported and SD stayed usable, 1 a check failed (a hang,
# a forced logout, SD unusable afterwards), 2 the fixed path was not reached or
# the test could not be built.
#
# ***READ THIS BEFORE RUNNING IT.*** Owner's go-ahead, 14 Sep 2026: "yes, after
# 3b's cycle".  PROJECT_STATUS.md section 4 records that killing sd sessions
# with Stop-Process once left the install answering EVERY new session "Forced
# logout", for twenty minutes, recoverable only elevated.  So this is a staged
# fault, it is not a suite step, and a cycle is expected afterwards.  If SD is
# unusable when it finishes, the recovery it prints is, elevated:
#   sd -cleanup           (C:\Program Files\SD\usr\bin\sd.exe -cleanup)
#   then restart-sd.ps1   (C:\Program Files\SD\restart-sd.ps1), then a cycle.
#
# WHAT IT MEASURES.  op_getlocks() builds each lock's owner name from
# UserPtr(owner), which is NULL for a user number no longer mapped; the fix
# (op_lock.c lock_owner_name) answers "(gone)".  LIST.READU never prints the
# name - it is field 6 of GETLOCKS() - so the probe calls GETLOCKS itself and
# prints that field.  GETLOCKS shows OTHER users' locks only to an $internal
# program (op_lock.c:981), so the probe is compiled and run under sd -internal.
#
#   1. a holder session takes READU on zzdlfile 'zzdlrec' and waits at INPUT;
#   2. INSTRUMENT CHECK, before anything is killed: the probe must see that
#      lock with a real owner name.  If it does not, the holder is ended
#      cleanly (it answers its INPUT and logs off) and the run REFUSES - nothing
#      is killed on an instrument that cannot see the lock;
#   3. the holder's own sd.exe is killed BY THE PID THIS SCRIPT STARTED, never
#      by name;
#   4. the probe runs again at once, then every 20 s for up to 6 minutes (the
#      daemon's lost-user scan is every 5), until it sees "(gone)" or no lock.
#
# ***THE NULL CASE IS LIKELY AND IS NOT A PASS.***  Whether a killed owner's
# lock is ever visible with its user unmapped is NOT KNOWN: the slot may stay
# mapped (the probe keeps printing the old name) until a cleanup that releases
# the lock with it (the probe then sees no lock).  Neither reaches the fixed
# line, so either ends exit 2, "not reached", with every observation printed.
# Only a probe line naming "(gone)" is the witness.
#
# BOUNDED: every probe is a job with a timeout, reported as a hang if it
# outstays it; the holder is a Process this script owns.

$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Write-Output ''; Write-Output 'verify-deadlock: refusing - see assert-current above'; exit 2 }

$wpr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $wpr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-deadlock: this needs an ELEVATED session - the probe runs under sd -internal.'
    exit 2
}

$appDir  = Join-Path $env:ProgramFiles 'SD'
$sdExe   = Join-Path $appDir 'usr\bin\sd.exe'
$restart = Join-Path $appDir 'restart-sd.ps1'
$sdsys   = Join-Path $env:ProgramData 'SD\sdsys'
$bp      = Join-Path $sdsys 'bp'
$bpOut   = Join-Path $sdsys 'bp.out'
$holdSrc = Join-Path $bp 'zzdlhold'
$probeSrc = Join-Path $bp 'zzdlprobe'

Write-Output '===== verify-deadlock.ps1 ====='
Write-Output ("  sd.exe   : " + $sdExe)
Write-Output ("  fixture  : SDSYS file zzdlfile, record zzdlrec; programs " + $holdSrc + ", " + $probeSrc)
Write-Output ("  RECOVERY if SD is unusable afterwards (elevated): " + $sdExe + " -cleanup ; then " + $restart + " ; then a cycle")
foreach ($p in @($sdExe, $bp)) { if (-not (Test-Path -LiteralPath $p)) { Write-Output ("verify-deadlock: missing " + $p); exit 2 } }

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ("  [PASS] " + $name) }
    else { $script:fail++; Write-Output ("  [FAIL] " + $name + $(if ($detail) { "  ->  $detail" } else { '' })) }
}

# Returns the transcript as ONE string and prints nothing (a function's
# Write-Output joins its return value - verify-nocaseupgrade's first run).
function Invoke-Bounded([string[]]$lines, [bool]$internal, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock {
        param($exe, $text, $int)
        if ($int) { $text | & $exe '-internal' 2>&1 } else { $text | & $exe 2>&1 }
    } -ArgumentList $sdExe, $body, $internal
    $done = [bool](Wait-Job $job -Timeout $TimeoutSec)
    if (-not $done) { Stop-Job $job -ErrorAction SilentlyContinue }
    $out = (@(Receive-Job $job -ErrorAction SilentlyContinue) | Out-String) -replace ([char]27 + '\[[0-9]*[A-Za-z]'), ''
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    if (-not $done) { $out += "`n*** DID NOT FINISH IN $TimeoutSec s" }
    return [string]$out
}
function Show([string]$label, [string]$text) {
    Write-Output ("  --- " + $label + " ---")
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match '^\s*:?\s*$|Ladybridge|free software|welcome to modify|conditions\.  For|^SD Core for') { continue }
        Write-Output ("    " + $l)
    }
}
# One probe: its state and the lines that decided it.  Prints nothing.
function Get-LockState {
    $t = Invoke-Bounded @('RUN bp zzdlprobe') $true
    $rows = @([regex]::Matches($t, '(?m)^LOCK user=(\S*) type=(\S*) name=\[([^\]]*)\]') | ForEach-Object {
        [pscustomobject]@{ User = $_.Groups[1].Value; Type = $_.Groups[2].Value; Name = $_.Groups[3].Value } })
    $state = 'unknown'
    if ($t -match 'DID NOT FINISH') { $state = 'hang' }
    elseif ($t -match 'Forced logout') { $state = 'forced' }
    elseif ($t -notmatch 'PROBE-DONE') { $state = 'noprobe' }
    elseif (@($rows | Where-Object { $_.Name -eq '(gone)' }).Count -gt 0) { $state = 'gone' }
    elseif ($rows.Count -gt 0) { $state = 'named' }
    else { $state = 'none' }
    return [pscustomobject]@{ State = $state; Rows = $rows; Text = $t }
}

$holdBasic = @'
* zzdlhold - written by verify-deadlock.ps1.  Safe to delete.
   open 'zzdlfile' to f else stop 'HOLD=NOFILE'
   readu r from f, 'zzdlrec' locked
      crt 'HOLD=BUSY'
      stop
   end then
      crt 'HOLD=LOCKED'
   end
   prompt ''
   input x
   release f, 'zzdlrec'
   crt 'HOLD=RELEASED'
end
'@
$probeBasic = @'
$internal
program zzdlprobe
* zzdlprobe - written by verify-deadlock.ps1.  Safe to delete.
* GETLOCKS field 1 is the limits; every later field is one lock:
* file_id VM pathname VM userno VM type VM id VM username (LISTRDU:98).
   locks = getlocks('', 0)
   n = dcount(locks, @fm)
   seen = 0
   for i = 2 to n
      s = locks<i>
      if s<1,5> = 'zzdlrec' then
         seen += 1
         crt 'LOCK user=' : s<1,3> : ' type=' : s<1,4> : ' name=[' : s<1,6> : ']'
      end
   next i
   crt 'PROBE-DONE locks=' : (n - 1) : ' seen=' : seen
end
'@

$holder = $null
$killed = $false
$exit = 2
try {
    # ---- build -----------------------------------------------------------
    $null = Invoke-Bounded @('DELETE.FILE zzdlfile FORCE') $false
    foreach ($pr in @(@($holdSrc, $holdBasic), @($probeSrc, $probeBasic))) {
        [IO.File]::WriteAllText($pr[0], ($pr[1] -replace "`r`n", "`n"), (New-Object Text.UTF8Encoding $false))
        Write-Output ("  wrote " + $pr[0])
    }
    $mk = Invoke-Bounded @('CREATE.FILE zzdlfile', 'COPY FROM VOC TO zzdlfile who,zzdlrec', 'BASIC bp zzdlhold') $false
    Show 'build: file, record, holder program' $mk
    $mk2 = Invoke-Bounded @('BASIC bp zzdlprobe') $true
    Show 'build: probe program (sd -internal)' $mk2
    $built = ($mk -match '1 record\(s\) copied') -and ([regex]::Matches($mk + $mk2, '(?m)^Compiled 1 program\(s\) with no errors').Count -eq 2)
    Row 'setup: the file, the record and both programs were built' $built
    if (-not $built) { Write-Output '  nothing killed, nothing measured'; exit 2 }

    $b0 = Get-LockState
    Show 'probe with no holder' $b0.Text
    Row 'CONTROL: before any holder, the probe runs and sees no zzdlrec lock' ($b0.State -eq 'none') "state $($b0.State)"
    if ($b0.State -ne 'none') { Write-Output '  nothing killed'; exit 2 }

    # ---- 1. the holder ------------------------------------------------------
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $sdExe
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $holder = [Diagnostics.Process]::Start($psi)
    $holdOut = New-Object Text.StringBuilder
    $holdErr = New-Object Text.StringBuilder
    $oEvt = Register-ObjectEvent -InputObject $holder -EventName OutputDataReceived -MessageData $holdOut -Action { if ($null -ne $EventArgs.Data) { [void]$Event.MessageData.AppendLine($EventArgs.Data) } }
    $eEvt = Register-ObjectEvent -InputObject $holder -EventName ErrorDataReceived -MessageData $holdErr -Action { if ($null -ne $EventArgs.Data) { [void]$Event.MessageData.AppendLine($EventArgs.Data) } }
    $holder.BeginOutputReadLine()
    $holder.BeginErrorReadLine()
    Write-Output ("  holder sd.exe started, PID " + $holder.Id)
    foreach ($l in @('', 'TERM 200,9999', 'RUN bp zzdlhold')) { $holder.StandardInput.WriteLine($l) }
    $holder.StandardInput.Flush()
    $deadline = (Get-Date).AddSeconds(60)
    while ((Get-Date) -lt $deadline -and $holdOut.ToString() -notmatch 'HOLD=(LOCKED|BUSY|NOFILE)') { Start-Sleep -Milliseconds 500 }
    Show 'holder so far' ($holdOut.ToString() + $holdErr.ToString())
    $locked = ($holdOut.ToString() -match 'HOLD=LOCKED')
    Row 'the holder took READU on zzdlrec and is waiting' $locked
    if (-not $locked) { throw 'the holder never reported HOLD=LOCKED - ending it cleanly, nothing killed' }

    # ---- 2. the instrument check, before any kill ---------------------------
    $a0 = Get-LockState
    Show 'probe with the holder alive' $a0.Text
    $named = @($a0.Rows | Where-Object { $_.Name -ne '' -and $_.Name -ne '(gone)' })
    Row 'INSTRUMENT: the probe sees the live lock with a real owner name' (($a0.State -eq 'named') -and ($named.Count -ge 1)) "state $($a0.State)"
    if (-not (($a0.State -eq 'named') -and ($named.Count -ge 1))) { throw 'the probe cannot see the live lock - ending the holder cleanly, nothing killed' }
    Write-Output ("  live lock: user " + $named[0].User + ", type " + $named[0].Type + ", name [" + $named[0].Name + "]")

    # ---- 3. kill the holder's own sd.exe -------------------------------------
    Write-Output ("  KILLING the holder, PID " + $holder.Id + " (the process this script started)")
    $holder.Kill()
    $null = $holder.WaitForExit(15000)
    $killed = $true
    Row 'the holder process is gone' $holder.HasExited

    # ---- 4. probe until "(gone)" or no lock ---------------------------------
    $seen = @()
    $end = (Get-Date).AddMinutes(6)
    $last = $null
    do {
        $s = Get-LockState
        $last = $s
        $stamp = (Get-Date).ToString('HH:mm:ss')
        $desc = ($s.Rows | ForEach-Object { "user $($_.User) $($_.Type) [$($_.Name)]" }) -join '; '
        Write-Output ("  " + $stamp + "  probe state: " + $s.State + $(if ($desc) { "  - " + $desc } else { '' }))
        $seen += $s.State
        if ($s.State -in @('gone', 'none', 'hang', 'forced', 'noprobe')) { break }
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $end)
    Show 'last probe' $last.Text

    Row 'no probe hung (the Linux fault held FILE_TABLE_LOCK and stopped every session)' ($seen -notcontains 'hang')
    Row 'no probe was answered "Forced logout"' ($seen -notcontains 'forced')
    Row 'every probe ran to PROBE-DONE' ($seen -notcontains 'noprobe')
    $gone = ($seen -contains 'gone')
    if ($gone) {
        Row 'DECISIVE: GETLOCKS reported the dead owner as "(gone)"' $true
    } else {
        Write-Output ''
        Write-Output ("  NOT REACHED: the probe saw " + (($seen | Select-Object -Unique) -join ' then ') + ", never '(gone)'.")
        Write-Output '  The killed owner stayed mapped until its lock went with it, so the fixed'
        Write-Output '  line never ran.  This is not a pass and not a product failure.'
    }
    $exit = $(if ($fail -gt 0) { 1 } elseif ($gone) { 0 } else { 2 })
}
catch {
    Write-Output ("verify-deadlock: " + $_.Exception.Message)
    if ($exit -eq 2 -and $fail -gt 0) { $exit = 1 }
}
finally {
    Write-Output '  --- cleanup ---'
    if ($null -ne $holder -and -not $holder.HasExited) {
        # END IT CLEANLY: answer its INPUT and log off, never kill on this path.
        try { $holder.StandardInput.WriteLine('x'); $holder.StandardInput.WriteLine('OFF'); $holder.StandardInput.Flush() } catch { }
        $null = $holder.WaitForExit(20000)
        Write-Output ("  holder ended cleanly: " + $holder.HasExited)
    }
    Get-EventSubscriber -ErrorAction SilentlyContinue | Where-Object { $_.SourceObject -eq $holder } | Unregister-Event -ErrorAction SilentlyContinue
    $cl = Invoke-Bounded @('DELETE.FILE zzdlfile FORCE') $false
    foreach ($f in @($holdSrc, $probeSrc, (Join-Path $bpOut 'zzdlhold'), (Join-Path $bpOut 'zzdlprobe'))) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    $health = Invoke-Bounded @('WHO') $false
    $healthy = ($health -match '(?m)^\d+ \S+') -and ($health -notmatch 'Forced logout') -and ($health -notmatch 'DID NOT FINISH')
    Show 'health check: a new session runs WHO' $health
    Row 'AFTERWARDS: a new SD session still works' $healthy
    if (-not $healthy) {
        Write-Output ''
        Write-Output '  SD IS NOT USABLE.  Recovery, from this elevated shell:'
        Write-Output ("    " + $sdExe + " -cleanup")
        Write-Output ("    powershell -ExecutionPolicy Bypass -File " + $restart)
        Write-Output '  and then a cycle.'
        if ($exit -ne 1) { $exit = 1 }
    }
    $leftFile = Test-Path -LiteralPath (Join-Path $sdsys 'zzdlfile')
    Row 'cleanup: zzdlfile and both programs removed' (-not $leftFile -and -not (Test-Path -LiteralPath $holdSrc) -and -not (Test-Path -LiteralPath $probeSrc)) $(if ($leftFile) { 'zzdlfile remains (a lock may still hold it)' } else { '' })
}

Write-Output ''
Write-Output ("verify-deadlock: $pass passed, $fail failed; exit $exit" + $(if ($killed) { ' - a session was killed; run a cycle before measuring anything else' } else { '' }))
exit $exit
