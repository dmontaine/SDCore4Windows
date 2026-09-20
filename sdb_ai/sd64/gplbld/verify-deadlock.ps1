# verify-deadlock.ps1 - GETLOCKS answers for a lock whose owner's session is
# gone, instead of dereferencing NULL.  RELEASE_1.1_FIXES.md 7 (Linux #7).
# ***ELEVATED POWERSHELL.  IT KILLS AN SD SESSION ON PURPOSE.***
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-deadlock.ps1
#
# Exit 0 the daemon reclaimed the killed owner within the window and errlog
# shows it was the daemon (RELEASE_1.1 37 witnessed) and SD stayed usable;
# 1 a check failed (a hang, a forced logout, SD unusable afterwards, or the
# owner NOT reclaimed); 2 the test could not be built or the instrument check
# refused.  17 Sep 26: "(gone)" (RELEASE_1.1 7) is reported if seen but no
# longer expected - see the verdict block for why it is unreachable here.
#
# ***READ THIS BEFORE RUNNING IT.*** Owner's go-ahead, 14 Sep 2026: "yes, after
# 3b's cycle".  PROJECT_STATUS.md section 4 records that killing sd sessions
# with Stop-Process once left the install answering EVERY new session "Forced
# logout", for twenty minutes, recoverable only elevated.  So this is a staged
# fault, it is not a suite step, and a cycle is expected afterwards IF IT
# KILLED ANYTHING (its last line says).  If SD is unusable when it finishes,
# the recovery it prints is, elevated:
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
# ***15 Sep 2026 - THE HOLDER WAS REBUILT AFTER ITS FIRST RUN.***  It was a
# .NET Process fed by StandardInput.WriteLine, waiting at INPUT.  WriteLine
# sends CRLF, SD took the stray line end as the INPUT answer, and the holder
# released at once ("HOLD=LOCKED" then "HOLD=RELEASED"); the probe then
# correctly saw no lock and the run refused, killing nothing.  And that
# sd.exe wrote to the owner's CONSOLE - its banner arrived unindented and about
# forty lines of this script's output vanished from the screen.  So now:
#   - the holder reads NO stdin: it loops, sleeping, until a record
#     'zzdlrelease' appears in zzdlfile;
#   - it runs in a background job like every other session here, so it has no
#     console to draw on;
#   - "holding" is proved by the $internal probe seeing the live lock with a
#     real owner name, polled for up to 60 s - not by any line the holder prints;
#   - the holder's PID is the one sd.exe that appeared since the job started,
#     and anything other than exactly one refuses the kill;
#   - this script writes its own transcript under %LOCALAPPDATA%\SD-verify.
#
# ***15 Sep 2026, SECOND RUN - THE HOLDER WORKED AND THE PROBE MISSED IT.***
# HOLD=LOCKED, held through the 60 s poll, released only by the record; the
# probe printed "locks=1 seen=0" and the run refused at the instrument check.
# A NOCASE file's lock id is UPPER-CASED in the lock table (op_lock.c:630) and
# since D2 every hashed file is NOCASE, so GETLOCKS answered ZZDLREC to a probe
# comparing against 'zzdlrec'.  The compare now folds, and every lock the probe
# sees is printed (OTHER-LOCK ...) whether it matches or not.
#
#   1. INSTRUMENT CHECK, before anything is killed: the probe must see the lock
#      with a real owner name.  If it does not, the holder is released cleanly
#      (the release record is written) and the run REFUSES - nothing is killed.
#   2. the holder's sd.exe is killed BY THAT PID, never by name;
#   3. the probe runs again at once, then every 20 s for up to 6 minutes (the
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
# outstays it; the holder job is stopped in cleanup whatever happened.

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-deadlock-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Write-Output ''; Write-Output 'verify-deadlock: refusing - see assert-current above'; try { Stop-Transcript | Out-Null } catch { }; exit 2 }

$wpr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $wpr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-deadlock: this needs an ELEVATED session - the probe runs under sd -internal.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$appDir   = Join-Path $env:ProgramFiles 'SD'
$sdExe    = Join-Path $appDir 'usr\bin\sd.exe'
$restart  = Join-Path $appDir 'restart-sd.ps1'
$sdsys    = Join-Path $env:ProgramData 'SD\sdsys'
$bp       = Join-Path $sdsys 'bp'
$bpOut    = Join-Path $sdsys 'bp.out'
$holdSrc  = Join-Path $bp 'zzdlhold'
$probeSrc = Join-Path $bp 'zzdlprobe'

Write-Output '===== verify-deadlock.ps1 ====='
Write-Output ("  sd.exe   : " + $sdExe)
Write-Output ("  fixture  : SDSYS file zzdlfile, lock on zzdlrec, release record zzdlrelease; programs " + $holdSrc + ", " + $probeSrc)
Write-Output ("  RECOVERY if SD is unusable afterwards (elevated): " + $sdExe + " -cleanup ; then " + $restart + " ; then a cycle")
foreach ($p in @($sdExe, $bp)) { if (-not (Test-Path -LiteralPath $p)) { Write-Output ("verify-deadlock: missing " + $p); try { Stop-Transcript | Out-Null } catch { }; exit 2 } }

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ("  [PASS] " + $name) }
    else { $script:fail++; Write-Output ("  [FAIL] " + $name + $(if ($detail) { "  ->  $detail" } else { '' })) }
}

# Returns the transcript as ONE string and prints nothing (a function's
# Write-Output joins its return value - verify-nocaseupgrade's first run).
. (Join-Path $PSScriptRoot 'internal-marker.ps1')
function Invoke-Bounded([string[]]$lines, [bool]$internal, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"
    # RELEASE_1.1 82 (D2'): LOGIN admits an "sd -internal" session only against a one-shot
    # marker, deleted on admission - written here immediately before the session.
    $marked = $false
    if ($internal) { $marked = Set-SdInternalMarker -SdsysDir $sdsys -Writer 'verify-deadlock' }
    $job = Start-Job -ScriptBlock {
        param($exe, $text, $int)
        if ($int) { $text | & $exe '-internal' 2>&1 } else { $text | & $exe 2>&1 }
    } -ArgumentList $sdExe, $body, $internal
    $done = [bool](Wait-Job $job -Timeout $TimeoutSec)
    if (-not $done) { Stop-Job $job -ErrorAction SilentlyContinue }
    if ($marked) { $null = Remove-SdInternalMarker -SdsysDir $sdsys }
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
function Get-SdPids { return @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id }) }

# The holder: takes the lock, then waits for the release RECORD - no stdin.
$holdBasic = @'
* zzdlhold - written by verify-deadlock.ps1.  Safe to delete.
   open 'zzdlfile' to f else stop 'HOLD=NOFILE'
   readu r from f, 'zzdlrec' locked
      crt 'HOLD=BUSY'
      stop
   end then
      crt 'HOLD=LOCKED'
   end
   for t = 1 to 900
      read flag from f, 'zzdlrelease' then exit
      sleep 1
   next t
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
* The id is UPPER-CASED in the lock table on a NOCASE file (op_lock.c:630),
* and since D2 every hashed file is one - the first run of this probe
* compared case-sensitively and reported locks=1 seen=0.  Every lock is
* printed, matched or not, so a miss shows what was there.
   locks = getlocks('', 0)
   n = dcount(locks, @fm)
   seen = 0
   for i = 2 to n
      s = locks<i>
      if upcase(s<1,5>) = 'ZZDLREC' then
         seen += 1
         crt 'LOCK user=' : s<1,3> : ' type=' : s<1,4> : ' name=[' : s<1,6> : ']'
      end else
         crt 'OTHER-LOCK file=' : s<1,1> : ' id=[' : s<1,5> : '] user=' : s<1,3> : ' type=' : s<1,4>
      end
   next i
   crt 'PROBE-DONE locks=' : (n - 1) : ' seen=' : seen
end
'@

$holdJob = $null
$holdPid = 0
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
    # throw, not exit: an exit here would skip the health check's exit code.
    if (-not $built) { throw 'the fixture did not build - nothing killed, nothing measured' }

    $b0 = Get-LockState
    Show 'probe with no holder' $b0.Text
    Row 'CONTROL: before any holder, the probe runs and sees no zzdlrec lock' ($b0.State -eq 'none') "state $($b0.State)"
    if ($b0.State -ne 'none') { throw 'the probe did not give a clean "no lock" before the holder - nothing killed' }

    # ---- 1. the holder, in a job, and the instrument check ------------------
    $pidsBefore = Get-SdPids
    $holdBody = "`nTERM 200,9999`nRUN bp zzdlhold`nOFF`n"
    $holdJob = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe 2>&1 } -ArgumentList $sdExe, $holdBody
    Write-Output ("  holder job started (id " + $holdJob.Id + "); sd.exe PIDs before it: " + ($pidsBefore -join ', '))

    $a0 = $null
    $deadline = (Get-Date).AddSeconds(60)
    do {
        Start-Sleep -Seconds 2
        if ($holdJob.State -ne 'Running') { break }
        $a0 = Get-LockState
    } while ($a0.State -ne 'named' -and (Get-Date) -lt $deadline)
    if ($null -ne $a0) { Show 'probe with the holder running' $a0.Text }
    Row 'the holder job is still running (it has not released)' ($holdJob.State -eq 'Running') "job state $($holdJob.State)"
    $named = @(); if ($null -ne $a0) { $named = @($a0.Rows | Where-Object { $_.Name -ne '' -and $_.Name -ne '(gone)' }) }
    $seesIt = ($null -ne $a0) -and ($a0.State -eq 'named') -and ($named.Count -ge 1)
    Row 'INSTRUMENT: the probe sees the live lock with a real owner name' $seesIt $(if ($null -eq $a0) { 'no probe ran' } else { "state $($a0.State)" })
    if (-not $seesIt -or $holdJob.State -ne 'Running') { throw 'the probe cannot see a live lock - releasing the holder cleanly, nothing killed' }
    Write-Output ("  live lock: user " + $named[0].User + ", type " + $named[0].Type + ", name [" + $named[0].Name + "]")

    $newPids = @(Get-SdPids | Where-Object { $pidsBefore -notcontains $_ })
    Write-Output ("  sd.exe PIDs that appeared since the holder started: " + $(if ($newPids.Count) { $newPids -join ', ' } else { '(none)' }))
    Row 'exactly one new sd.exe - the holder - so the kill has one target' ($newPids.Count -eq 1) "found $($newPids.Count)"
    if ($newPids.Count -ne 1) { throw 'cannot tell which sd.exe is the holder - releasing it cleanly, nothing killed' }
    $holdPid = $newPids[0]

    # ---- 2. kill the holder's sd.exe ----------------------------------------
    Write-Output ("  KILLING the holder, PID " + $holdPid)
    Stop-Process -Id $holdPid -Force
    $killed = $true
    Start-Sleep -Seconds 2
    Row 'the holder process is gone' ($null -eq (Get-Process -Id $holdPid -ErrorAction SilentlyContinue))

    # ---- 3. probe until "(gone)" or no lock ---------------------------------
    $seen = @()
    $end = (Get-Date).AddMinutes(6)
    $last = $null
    do {
        $s = Get-LockState
        $last = $s
        $desc = ($s.Rows | ForEach-Object { "user $($_.User) $($_.Type) [$($_.Name)]" }) -join '; '
        Write-Output ("  " + (Get-Date).ToString('HH:mm:ss') + "  probe state: " + $s.State + $(if ($desc) { "  - " + $desc } else { '' }))
        $seen += $s.State
        if ($s.State -in @('gone', 'none', 'hang', 'forced', 'noprobe')) { break }
        Start-Sleep -Seconds 20
    } while ((Get-Date) -lt $end)
    Show 'last probe' $last.Text

    Row 'no probe hung (the Linux fault held FILE_TABLE_LOCK and stopped every session)' ($seen -notcontains 'hang')
    Row 'no probe was answered "Forced logout"' ($seen -notcontains 'forced')
    Row 'every probe ran to PROBE-DONE' ($seen -notcontains 'noprobe')
    $gone = ($seen -contains 'gone')
    # 17 Sep 26 - RELEASE_1.1 37 IS THE THING THIS RUN CAN WITNESS, AND 7 IS NOT.
    # 37's cause was measured (the daemon's cleanup never ran on an install:
    # system() has no shell) and fixed in sdwind.c; with it fixed the daemon's
    # five-minute tick reaps the killed owner's slot AND its locks together, so
    # the probe goes "named" then "none" - and the daemon writes two errlog
    # lines while it does: "Lost user N (pid P): running ... -cleanup" and
    # cleanup()'s own "Cleanup removed user N (pid P, ...)".  Both are read
    # here, because a "none" that arrived some other way (a hand-run cleanup,
    # a restart) is not the daemon's work.  "(gone)" - a lock outliving its
    # owner's slot - cannot occur on this tree since PRE_RELEASE 24 made
    # remove_user() give the locks away with the slot, under the same two
    # semaphores GETLOCKS reads under; the fix in op_lock.c stays as defence and
    # this script no longer scores its absence as a miss.
    $reclaimed = (($seen -contains 'named') -and ($seen[-1] -eq 'none'))
    Row '37: the killed owner was reclaimed within the window (named, then none)' $reclaimed ("saw " + (($seen | Select-Object -Unique) -join ' then '))
    $errlog = Join-Path $sdsys 'errlog'
    $tail = ''
    try { $tail = (Get-Content -LiteralPath $errlog -Tail 40 -ErrorAction Stop) -join "`n" } catch { $tail = '' }
    $daemonLine  = $tail -match ('Lost user \d+ \(pid \d+\): running .*-cleanup')
    $removedLine = $tail -match ('Cleanup removed user \d+ \(pid \d+, ')
    Row '37: errlog carries the DAEMON''s "Lost user ... running ... -cleanup" line' $daemonLine
    Row '37: errlog carries cleanup()''s "Cleanup removed user" line' $removedLine
    Row '37: control - no "Cleanup not run" / "Cleanup did not complete" in the tail' (-not ($tail -match 'Cleanup not run|Cleanup did not complete'))
    if ($gone) {
        Row '7: GETLOCKS reported the dead owner as "(gone)" - a state 24 should make unreachable; READ THE RUN' $true
    } else {
        Write-Output ''
        Write-Output ("  7: '(gone)' not seen - the probe saw " + (($seen | Select-Object -Unique) -join ' then ') + ".  Expected: a lock cannot")
        Write-Output '     outlive its owner''s slot since PRE_RELEASE 24, so the fixed line in op_lock.c is a'
        Write-Output '     defence with no witness here.  Not scored (RELEASE_1.1_FIXES 7, 17 Sep 2026).'
    }
    $exit = $(if ($fail -gt 0) { 1 } elseif ($reclaimed -and $daemonLine -and $removedLine) { 0 } else { 2 })
}
catch {
    Write-Output ("verify-deadlock: " + $_.Exception.Message)
    if ($exit -eq 2 -and $fail -gt 0 -and $killed) { $exit = 1 }
}
finally {
    Write-Output '  --- cleanup ---'
    if ($null -ne $holdJob) {
        if (-not $killed -and $holdJob.State -eq 'Running') {
            # RELEASE IT CLEANLY: write the record the holder waits for.
            $rel = Invoke-Bounded @('COPY FROM VOC TO zzdlfile who,zzdlrelease') $false
            $null = Wait-Job $holdJob -Timeout 30
            Write-Output ("  holder released by record: job state " + $holdJob.State)
        }
        if ($holdJob.State -eq 'Running') { Stop-Job $holdJob -ErrorAction SilentlyContinue }
        Show 'holder job output' ((@(Receive-Job $holdJob -ErrorAction SilentlyContinue) | Out-String) -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '')
        Remove-Job $holdJob -Force -ErrorAction SilentlyContinue
    }
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
        $exit = 1
    }
    $leftFile = Test-Path -LiteralPath (Join-Path $sdsys 'zzdlfile')
    Row 'cleanup: zzdlfile and both programs removed' (-not $leftFile -and -not (Test-Path -LiteralPath $holdSrc) -and -not (Test-Path -LiteralPath $probeSrc)) $(if ($leftFile) { 'zzdlfile remains (a lock may still hold it)' } else { '' })
    Write-Output ''
    Write-Output ("verify-deadlock: $pass passed, $fail failed; exit $exit" + $(if ($killed) { ' - a session WAS killed; run a cycle before measuring anything else' } else { ' - nothing was killed' }))
    try { Stop-Transcript | Out-Null } catch { }
}
exit $exit
