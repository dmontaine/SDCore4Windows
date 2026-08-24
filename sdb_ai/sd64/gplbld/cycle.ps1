<#
.SYNOPSIS
    Run one whole test cycle: stop SD, stage, build the installer, uninstall,
    delete both trees, install.

.DESCRIPTION
    ONE ELEVATED POWERSHELL COMMAND FOR THE WHOLE CYCLE.  Owner's instruction,
    17 Aug 2026: the cycle had grown to four commands across three shells, and
    it used to be PowerShell and fewer steps.  Every step below was already
    written down in CLAUDE.md and PROJECT_STATUS.md; this only puts them behind
    one call so that none of them can be skipped, reordered, or run from the
    wrong directory.

    IT EXISTS BECAUSE THE HAND-RUN SEQUENCE FAILED TWICE IN ONE ATTEMPT, both
    times on something the script can simply not get wrong:

      * The SD SERVICE WAS STILL RUNNING.  The staged etc/fstab points /dev/shm
        at the LIVE tree, so the bootstrap's "sd -start" collided with the live
        server and pass 1 produced nothing.  The staged tree was left in the
        seed state - gcat 4 entries, $BCOMP 70,697, $CPROC 0 bytes - which is
        exactly the state that shipped a catalogue-less install on 16 Aug.
      * ISCC WAS RUN FROM C:\WINDOWS\system32, where "gplbld\sd.iss" does not
        resolve.  It answered "The system cannot find the path specified",
        which does not name the file it could not find.

    WHAT IT DELIBERATELY DOES NOT DO: reuse an existing install, skip the
    delete, or install over the top.  CLAUDE.md: a test cycle begins with a
    fresh install, never a reinstall, because the installer never overwrites an
    existing C:\ProgramData\SD\sdsys.

.PARAMETER Stage
    Staging tree.  Rebuilt from scratch; --force is always passed.

.PARAMETER Out
    Where ISCC writes the installer.

.PARAMETER SkipInstall
    Stop after building the installer.  The old tree is left alone - nothing is
    uninstalled and nothing is deleted - so this is the safe way to check that
    a change compiles without spending an install.

.NOTES
    THERE IS NO -Silent.  It was removed 23 Aug 2026 on the owner's ruling:
    "unattended deployment is not supported in sd - install can only happen at
    the keyboard or in a remoted session."  sd.iss refuses a silent install
    outright, so there is nothing here to pass one.

    It had been added 17 Aug 2026 with this script and was never part of
    anybody's pattern.  Its single use, by a session that wanted a cycle
    nobody had to watch, produced an install with no password on any account
    and cost two sessions to diagnose.  A cycle needs a person; that is now
    true of the tooling and not only of the convention.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\cycle.ps1
#>

[CmdletBinding()]
param(
    [string] $Stage = 'C:\Users\dmont\stagetest',
    [string] $Out   = 'C:\Users\dmont\sdout',
    [switch] $SkipInstall
)

$ErrorActionPreference = 'Stop'

# 17 Aug 26 - A TRANSCRIPT, for the same reason verify-tiers.ps1 has one: this
# runs elevated, which usually means a window nobody is going to copy back, and
# a cycle that failed at step 3 looks exactly like one that failed at step 7
# once the window has gone.  Start-Transcript flushes as it goes, so the file is
# readable even on the Fail paths below, which exit without stopping it.
#
# NOT UNDER C:\ProgramData\SD, WHICH STEP 6 DELETES.  The first version of this
# put it there and the transcript would have erased itself half way through its
# own run.  LOCALAPPDATA is the same directory whether or not the shell is
# elevated - elevation does not change which user this is - so an unelevated
# session afterwards can find what an elevated one wrote.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$script:CycleLog = Join-Path $logDir ('cycle-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $script:CycleLog -Force | Out-Null } catch { }
Write-Host "transcript: $script:CycleLog"

# 24 Aug 26 - STOP THE TRANSCRIPT ON EVERY EXIT PATH.  PowerShell 5.1 keeps a
# transcript ACTIVE until it is stopped or the whole session ends, and it
# supports SEVERAL AT ONCE - every active one receives every line.  So running
# this script a second time in the SAME elevated window left the first run's
# log open, and it went on recording the second run.
#
# MEASURED 24 Aug 2026, and it had already corrupted the record: after the
# 15:13:25 cycle, cycle-20260824-133558.log - the log for the 13:36:51 install
# that PROJECT_STATUS cites - held TWO "CYCLE COMPLETE" lines and two step-1
# banners, and verify-tiers-20260824-134341.log had an entire cycle appended
# after its own output.  Neither carried a "transcript end" marker, because
# neither was ever stopped.
#
# WHY IT SURVIVED THIS LONG: a run launched as its own process
# (powershell -File ...) closes the file when the process exits, so the log is
# clean and carries its end marker.  The bleed only appears when the documented
# usage is followed literally - typing the script path at an already-open
# elevated prompt - which is the usage this script is written for.
function StopCycleTranscript {
    try { Stop-Transcript | Out-Null } catch { }
}

# gplbld\ -> sd64\.  Every path below is absolute and derived from this script's
# own location, which is the whole point: the hand-run sequence broke on a
# relative path resolved against C:\WINDOWS\system32.
$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sd64    = Split-Path -Parent $Gplbld
$Iss     = Join-Path $Gplbld 'sd.iss'
# ISCC: THE DEFAULT PATH FIRST, THEN THE REGISTRY.  23 Aug 2026 - this was a
# bare hardcoded path until setup-devbox.ps1's first real run reported Inno
# installed and ISCC not present at it.  The default is still tried first, so
# on a machine where it is in the usual place this resolves to exactly the
# string that used to be here and nothing about a cycle changes.  The fallback
# reads what Inno's own installer wrote, which covers a per-user winget
# install or a non-default location.  setup-devbox.ps1's Resolve-Iscc is the
# same lookup and says why in more detail.
$Iscc    = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
if (-not (Test-Path -LiteralPath $Iscc)) {
    # HKCU AND LOCALAPPDATA ARE NOT PADDING - the first clean-VM run, 23 Aug
    # 2026, got a PER-USER Inno install at
    # %LOCALAPPDATA%\Programs\Inno Setup 6\ISCC.exe.  A per-user install writes
    # its uninstall key under HKCU, not HKLM, so an HKLM-only lookup would have
    # missed it and this script would have reported ISCC missing on a machine
    # that has it.  That is also what setup-devbox.ps1's message promises, so
    # the two must agree or the promise is false.
    foreach ($k in @(
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1',
        'HKCU:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Inno Setup 6_is1')) {
        try {
            $loc = (Get-ItemProperty -LiteralPath $k -ErrorAction Stop).InstallLocation
        } catch { continue }
        if ([string]::IsNullOrWhiteSpace($loc)) { continue }
        $cand = Join-Path $loc 'ISCC.exe'
        if (Test-Path -LiteralPath $cand) { $Iscc = $cand; break }
    }
}
if (-not (Test-Path -LiteralPath $Iscc)) {
    # Last resort, and the one that actually caught the VM: a per-user install
    # whose registry key is missing or unreadable still puts ISCC here.
    $userIscc = Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'
    if (Test-Path -LiteralPath $userIscc) { $Iscc = $userIscc }
}
$Bash    = 'C:\msys64\usr\bin\bash.exe'
$SvcName = 'SD'
$PfTree  = 'C:\Program Files\SD'
$PdTree  = 'C:\ProgramData\SD'

function Step($n, $msg) { Write-Host ""; Write-Host "== [$n] $msg" -ForegroundColor Cyan }
function Fail($msg) {
    Write-Host ""
    Write-Host "CYCLE STOPPED: $msg" -ForegroundColor Red

    # SAY WHEN SD IS LEFT DOWN.  Step 1 stops the service and nothing restarts
    # it on the way out, so a cycle that aborts at step 4 - as the 19 Aug 2026
    # sd.iss run did - leaves the machine with no SD and no indication of it.
    # It is NOT restarted here: a re-run stops it again immediately, and
    # starting a server against a half-staged tree is worse than leaving it
    # down.  The point is that it should never be a surprise.
    $svc = Get-Service -Name $SvcName -ErrorAction SilentlyContinue
    if ($svc -and $svc.Status -ne 'Running') {
        Write-Host ""
        Write-Host ("SD IS STOPPED - step 1 stopped it and this run did not get far enough to " +
                    "reinstall.  Both trees are untouched until step 6.") -ForegroundColor Yellow
        Write-Host "  Re-run this script when the fault is fixed, or start it now with:  sc.exe start $SvcName" -ForegroundColor Yellow
    }

    StopCycleTranscript
    exit 1
}

# ---------------------------------------------------------------------------
# Convert a Windows path to the /c/... form MSYS2 wants.  Passing a backslash
# path through bash -lc gets it eaten as escapes.
function ToMsys([string] $p) {
    $p = $p -replace '\\', '/'
    if ($p -match '^([A-Za-z]):(.*)$') { return "/$($Matches[1].ToLower())$($Matches[2])" }
    return $p
}

# ---------------------------------------------------------------------------
# ELEVATION.  bootstrap.py checks this too and says so clearly, but by then the
# seed phase has already rewritten the staging tree, so checking here saves the
# tree as well as the time.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail "this needs an ELEVATED PowerShell.  Right-click, Run as administrator."
}

foreach ($p in @($Iscc, $Bash, $Iss)) {
    if (-not (Test-Path -LiteralPath $p)) { Fail "not found: $p" }
}

# BOTH DIRECTORIES ARE PINNED ABSOLUTE HERE, and this is the second guard on the
# same fault.  A relative path in either is resolved against the shell's cwd,
# which for an elevated window is C:\WINDOWS\system32 - so the failure mode is
# not "it did not work" but "it worked somewhere you will not look".
foreach ($n in 'Stage', 'Out') {
    $v = (Get-Variable -Name $n).Value
    if (-not [System.IO.Path]::IsPathRooted($v)) {
        Fail "-$n must be an absolute path, and '$v' is not."
    }
    Set-Variable -Name $n -Value ([System.IO.Path]::GetFullPath($v))
}

# LINT sd.iss BEFORE ANYTHING EXPENSIVE, AND BEFORE THE SERVICE GOES.  ISPP
# treats a line whose first non-blank character is "#" as a preprocessor
# directive, so a Pascal character constant wrapped onto its own line - the
# "#13#10#13#10 +" idiom in the message strings - is read as a directive and
# ISCC answers "Unknown preprocessor directive" without saying why.
#
# THE RULE WAS ALREADY WRITTEN DOWN, at sd.iss's InitializeWizard comment, AND
# IT STILL BIT: the account-ACL message added on 19 Aug 2026 wrapped one, ~480
# lines away from the note, and cost a cycle that had already stopped the
# service, staged and bootstrapped before ISCC ever saw the file.  A comment
# that far from the code being written is not a guard.  This is.
$issDirectives = @('define', 'undef', 'include', 'if', 'ifdef', 'ifndef',
                   'ifexist', 'ifnexist', 'elif', 'else', 'endif', 'for',
                   'sub', 'endsub', 'expr', 'insert', 'append', 'emit',
                   'error', 'pragma', 'file', 'x', 'dim', 'redim')
$issBad = @(Get-Content -LiteralPath $Iss | ForEach-Object { $_ } |
            Select-String -Pattern '^\s*#\s*(\w*)' |
            Where-Object { $issDirectives -notcontains $_.Matches[0].Groups[1].Value.ToLower() })
if ($issBad.Count -gt 0) {
    foreach ($b in $issBad) {
        Write-Host ("   sd.iss:{0}: {1}" -f $b.LineNumber, $b.Line.Trim()) -ForegroundColor Red
    }
    Fail ("sd.iss has {0} line(s) starting with '#' that ISPP will read as a preprocessor " -f $issBad.Count +
          "directive.  Move the constant to the END of the previous line, as every other #13#10 in that file is.")
}

# ---------------------------------------------------------------------------
Step 1 "Stopping SD"

# THE STEP THE HAND-RUN CYCLE MISSED.  Stop-Service returns before the SCM has
# finished and before sdwind has gone, so the wait is on the PROCESS, which is
# what actually holds the shared segment and /dev/shm.
if (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) {
    & "$env:SystemRoot\System32\sc.exe" stop $SvcName | Out-Null
}

$deadline = (Get-Date).AddSeconds(45)
while ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
}

# 21 Aug 26 - AND THEN ASK SD ITSELF, because stopping the SERVICE does not
# always take the DAEMON with it.  Measured 21 Aug 2026, 17:05: sc.exe stop
# returned, the service went to Stopped, and sdwind(15956) - started at 16:25:45
# by verify-apiadmin's "sc.exe start SD" - was still there 45 seconds later with
# its parent gone.  The cycle failed at step 1 and cost a run.
#
# sdsvc.c ALREADY DOES THIS on its own stop path (run_sd("-stop") at :433, :467
# and :482), so this is not a second mechanism - it is the same call, made again
# from outside, for the case where the service exited without its daemon
# following.  A daemon whose parent has gone is nobody's child and the SCM has
# nothing left to stop.
#
# STILL NOT A KILL.  "sd -stop" refuses while users are logged in, which is
# exactly the protection the comment below describes: it ends an idle daemon and
# leaves somebody's live session alone.  Only if it declines do we fail.
$stopSaidOk = $false
if (Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) {
    $sdExe = Join-Path $PfTree 'usr\bin\sd.exe'
    if (Test-Path -LiteralPath $sdExe) {
        Write-Host '   service stopped but a daemon is still up - asking sd -stop'
        $stopOut = (& $sdExe -stop 2>&1 | Out-String)
        $stopOut -split "`r?`n" | Where-Object { $_.Trim() } | ForEach-Object { Write-Host "     $_" }
        $stopSaidOk = ($stopOut -match 'has been shut down')
        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
            Start-Sleep -Milliseconds 500
        }
    }
}

$left = Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue
if ($left) {
    # Named, not killed.  A surviving sd is somebody's session, and ending it
    # from here would take their work with it.
    #
    # THE TWO CASES READ DIFFERENTLY, and telling them apart is the whole point
    # of saying which processes are left: an "sd" is a SESSION and somebody has
    # to close it, an "sdwind" alone is a DAEMON that has just refused both the
    # service and "sd -stop", which means it believes somebody is still logged
    # in to it.
    $names = @($left | ForEach-Object { $_.Name } | Sort-Object -Unique)
    $advice = if ($names -contains 'sd') {
        'Close any SD session and run this again.'
    } elseif ($stopSaidOk) {
        # 21 Aug 26 - THE CASE THAT COST TWO RUNS, and it needs naming because
        # every ordinary reading of it is wrong.  "sd -stop" REPORTED SUCCESS -
        # "SD (64 Bit) has been shut down" - and the daemon was still there.
        #
        # It happens when there is MORE THAN ONE sdwind.  Measured 21 Aug: a
        # second daemon started at 16:30:55 outside the service and logged "API
        # listener not started: cannot bind port 4243", because the one from
        # 16:25:45 already had it.  "sd -stop" reaches whichever daemon owns the
        # shared segment it finds, stops that one, and says so - truthfully -
        # while the older one keeps running with the port and a segment nothing
        # can now reach.
        #
        # ENDING IT IS SAFE AND IS THE ONLY RECOVERY.  It is a DAEMON, not
        # somebody's session - the test above has already established no "sd"
        # process exists - and it has been asked to stop and did not.  The
        # script still will not do it: an automatic kill here is exactly the
        # thing the "named, not killed" rule exists to prevent, and a daemon
        # that ignores a successful shutdown is worth a human look.
        'BUT "sd -stop" REPORTED SUCCESS, so this daemon is orphaned from the shared ' +
        'segment - there was probably a second sdwind. It is not a session and nothing ' +
        'else will end it:' + "`n" +
        # PARENTHESISED, because -join binds LOOSER than +: without them
        # "'a' + $x -join ',' + 'b'" parses as "('a' + $x) -join (',' + 'b')"
        # and the advice line comes out as nonsense at the moment it is needed.
        '      Stop-Process -Id ' + (($left | ForEach-Object { $_.Id }) -join ',') + ' -Force'
    } else {
        'No SD session is running, so the daemon is refusing for another reason - ' +
        'check for an API session, then "sd -stop" by hand.'
    }
    Fail ("SD is still running after 45s: " +
          (($left | ForEach-Object { "$($_.Name)($($_.Id))" }) -join ', ') +
          "`n  " + $advice)
}
Write-Host "   SD is stopped"

# ---------------------------------------------------------------------------
Step 2 "Staging and bootstrapping into $Stage"

# Through an MSYS2 LOGIN shell.  A non-login shell has no usable Windows TMP,
# and stage.py must be run by the MSYS2 (Cygwin) python - bootstrap.py's
# is_elevated() asks getgroups(), which a native Windows python cannot answer.
#
# Output goes to the console, NOT to a pipe or a redirect file, and this is not
# a style choice: "sd -start" forks sdwind, which inherits whatever handles it
# is given and holds them for life.  Start-Process -Wait -RedirectStandardOutput
# never returns from it - PROJECT_STATUS.md section 6, and it cost a session.
$cmd = "cd '$(ToMsys $Sd64)' && python3 gplbld/stage.py --stage '$(ToMsys $Stage)' --force --bootstrap"
& $Bash -lc $cmd
if ($LASTEXITCODE -ne 0) { Fail "stage.py exited $LASTEXITCODE - the staged tree is not usable" }

# ---------------------------------------------------------------------------
Step 3 "Checking the staged tree is whole"

# stage.py refuses a half-bootstrapped tree itself (check_bootstrap_complete).
# This is the same test again, and it is not redundant: it is what stands
# between a silent bootstrap failure and an installer built from the wreckage,
# which is exactly what happened on 16 Aug 2026.  assert-current.ps1 CANNOT
# cover this - it compares an install against SOURCE, and gcat is a build
# product with no source counterpart.
# EVERY LOCAL HERE IS PREFIXED, and that is a scar rather than a style.  This
# block first used $out for the GPL.BP.OUT count, and PowerShell variable names
# are CASE-INSENSITIVE, so it silently overwrote the $Out PARAMETER with the
# number 193.  ISCC was then handed "/O193" and wrote the installer into a
# relative "193\" directory under whatever the shell's cwd happened to be -
# C:\WINDOWS\system32.  The check below caught it, but as "no sd-setup-*.exe is
# in 193", which names the symptom and not the cause.
$Sdsys = Join-Path $Stage 'ProgramData\sdsys'
function CountIn($sub) {
    $d = Join-Path $Sdsys $sub
    if (Test-Path -LiteralPath $d) { (Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue).Count } else { -1 }
}
$nGcat   = CountIn 'gcat'
$nOut    = CountIn 'gpl.bp.out'
# 19 Aug 26 - THE TERMINFO DATABASE, and it is counted RECURSIVELY because it is
# sharded a level deep: sdtermlb.c:166 opens <sysdir>\terminfo\<first letter>\<name>,
# so CountIn would report 0 for a perfectly good one.  Without it, no terminal
# type resolves - "Unrecognised terminal name" for vt100 and everything else -
# and NOTHING ELSE WOULD SAY SO: it is not tracked (it is "make terminfo"
# output), stage.py only checks that the DIRECTORY exists, and sd.iss copies the
# staged tree with a wildcard.  So an sdtic that failed half way, or a stale
# terminfo/ left by an interrupted build, ships silently and the first anyone
# hears of it is a user whose terminal does not work.
$nTinfo  = $(
    $d = Join-Path $Sdsys 'terminfo'
    if (Test-Path -LiteralPath $d) {
        (Get-ChildItem -LiteralPath $d -Recurse -File -ErrorAction SilentlyContinue).Count
    } else { -1 })
$szCproc = if (Test-Path -LiteralPath (Join-Path $Sdsys 'gcat\$CPROC')) {
               (Get-Item -LiteralPath (Join-Path $Sdsys 'gcat\$CPROC')).Length } else { -1 }
$szBcomp = if (Test-Path -LiteralPath (Join-Path $Sdsys 'gcat\$BCOMP')) {
               (Get-Item -LiteralPath (Join-Path $Sdsys 'gcat\$BCOMP')).Length } else { -1 }

# 18 Aug 26 - 129/190, NOT 132/193.  Removing SDNet took three programs with it
# (commit c893308), so the old figures have read three high since the 17:21
# cycle.  The thresholds below did not move and did not need to: they are set
# far enough back to catch a bootstrap that failed, not to police a count.
Write-Host ("   gcat {0} (want ~129)   gpl.bp.out {1} (want ~190)   terminfo {2} (want ~100)" -f $nGcat, $nOut, $nTinfo)
Write-Host ("   `$CPROC {0} bytes (want >0)   `$BCOMP {1} (want ~88,000 - 70,697 is the seed)" -f $szCproc, $szBcomp)

$faults = @()
if ($szCproc -le 0)   { $faults += '$CPROC is the 0-byte placeholder - the bootstrap never reached the last step' }
if ($nGcat   -lt 100) { $faults += "gcat holds $nGcat entries" }
if ($nOut    -lt 150) { $faults += "gpl.bp.out holds $nOut objects" }
if ($nTinfo  -lt 50)  { $faults += "terminfo holds $nTinfo entries - run 'make terminfo'; no terminal type would resolve" }
if ($szBcomp -eq 70697) { $faults += '$BCOMP is bbcmp.py''s seed, not BCOMP''s own object' }
if (-not (Test-Path -LiteralPath (Join-Path $Sdsys 'voc'))) { $faults += "voc is absent - 'sd -i' did not complete" }
if ($faults) { Fail ("the staged tree is not whole:`n  - " + ($faults -join "`n  - ")) }
Write-Host "   staged tree is whole"

# ---------------------------------------------------------------------------
Step 4 "Building the installer"

if (-not (Test-Path -LiteralPath $Out)) { New-Item -ItemType Directory -Path $Out | Out-Null }
& $Iscc "/DStage=$Stage" "/O$Out" $Iss
if ($LASTEXITCODE -ne 0) { Fail "ISCC exited $LASTEXITCODE" }

$setup = Get-ChildItem -LiteralPath $Out -Filter 'sd-setup-*.exe' |
         Sort-Object LastWriteTime -Descending | Select-Object -First 1
if (-not $setup) { Fail "ISCC reported success but no sd-setup-*.exe is in $Out" }
Write-Host ("   {0}, {1:N0} bytes, {2}" -f $setup.Name, $setup.Length, $setup.LastWriteTime)

if ($SkipInstall) {
    Write-Host ""
    Write-Host "-SkipInstall: stopping here.  The installed tree is untouched and STALE." -ForegroundColor Yellow
    StopCycleTranscript
    exit 0
}

# ---------------------------------------------------------------------------
Step 5 "Uninstalling"

# AN UNINSTALLER FIX CANNOT BE VERIFIED IN THE CYCLE THAT SHIPS IT.
# unins000.exe is generated at INSTALL time, so this runs the PREVIOUS
# install's code.  PROJECT_STATUS.md header, item 1.
$unins = Join-Path $PfTree 'unins000.exe'
if (Test-Path -LiteralPath $unins) {
    # Inno's uninstaller copies itself and returns immediately, so waiting on
    # the process we launched proves nothing.  Wait for the TREE to go.
    #
    # Not piped to Out-Null, for the reason given at step 2: a pipe is a handle
    # the spawned copy inherits, and PowerShell then waits on a stream rather
    # than on the work.
    & $unins /VERYSILENT
    $deadline = (Get-Date).AddSeconds(120)
    while ((Test-Path -LiteralPath $PfTree) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
    Write-Host ("   uninstaller ran; $PfTree {0}" -f $(if (Test-Path -LiteralPath $PfTree) { 'still present' } else { 'gone' }))
} else {
    Write-Host "   nothing installed at $PfTree"
}

# ---------------------------------------------------------------------------
Step 6 "Deleting BOTH trees"

# NOT OPTIONAL AND NOT A TIDY-UP.  The installer deliberately never overwrites
# an existing C:\ProgramData\SD\sdsys, so leaving it means the next install
# silently keeps the tree that first created it - and every measurement taken
# afterwards describes THAT build.  CLAUDE.md, and the four-fault run in
# HISTORY.md.
foreach ($t in @($PfTree, $PdTree)) {
    if (Test-Path -LiteralPath $t) {
        Remove-Item -LiteralPath $t -Recurse -Force -ErrorAction SilentlyContinue
    }
    if (Test-Path -LiteralPath $t) {
        Fail "could not delete $t - something still has a handle on it.  Close any SD session or Explorer window and run this again."
    }
    Write-Host "   $t gone"
}

# ---------------------------------------------------------------------------
Step 7 "Installing"

# 23 Aug 26 - NO SILENT SWITCH, and sd.iss would refuse one anyway.  The wizard
# runs, a person answers it, and the install ends by collecting a password.
$installArgs = @()

# 17 Aug 26 - Start-Process -Wait, NOT "& $setup".  THE CALL OPERATOR DOES NOT
# WAIT FOR A GUI-SUBSYSTEM PROCESS, and Setup.exe is one - PE subsystem 2,
# measured on sd-setup-1.0-2.exe rather than assumed.  So the deadline below
# used to start when the WIZARD OPENED instead of when it was dismissed, and
# five minutes of somebody reading the wizard was indistinguishable from an
# install that never ran.
#
# It cost exactly that on the cycle of 13:30:47: step 8 stopped with "no
# C:\ProgramData\SD\sdsys\gcat after the install - it did not complete", the
# install then finished normally at 13:43, and the tree was whole - gcat 132,
# GPL.BP.OUT 193, and a file-by-file comparison against the stage came back
# empty.  A FALSE FAILURE HERE IS AS EXPENSIVE AS A FALSE PASS: it reads as the
# broken-bootstrap install of 16 Aug, which is the one thing this script exists
# to catch, and the natural response is to spend another cycle.
#
# And it is aimed at the default: non-silent is deliberate, because the wizard
# pages are part of what a cycle shows (PROJECT_STATUS.md 7 step 3), so the
# longer the operator does what the default asks of them, the likelier the
# failure.
#
# THE COUNT DEADLINE BELOW IS KEPT AS THE BACKSTOP, not replaced.  If Inno ever
# does respawn itself for elevation this returns early again, and the tree
# stays what decides - the same rule adopt-account.ps1 follows.
if ($installArgs.Count -gt 0) {
    Start-Process -FilePath $setup.FullName -ArgumentList $installArgs -Wait
} else {
    Start-Process -FilePath $setup.FullName -Wait
}

# THE WAIT IS FOR THE TREE TO MATCH THE STAGE, NOT FOR ONE FILE TO EXIST.  This
# waited for gcat\$CPROC and then counted immediately, and $CPROC is nowhere near
# the last thing written: the first run of this script reported
# "GPL.BP.OUT 5" on an install that was fine and finished with 193.  A number
# read off a half-copied tree is the exact failure mode step 3 exists to catch,
# and here it was being printed as the result.
#
# So it waits until the installed counts REACH the staged ones - which are known,
# having just been measured - and only then reports.  A tree that never gets
# there is a real fault and says so, instead of being reported as a small number
# nobody can interpret.  This still judges on the TREE rather than on Setup's
# exit status - the same rule adopt-account.ps1 follows - even now that the
# wait above means the wizard has actually closed by the time it starts.
$igcatDir = Join-Path $PdTree 'sdsys\gcat'
$ioutDir  = Join-Path $PdTree 'sdsys\gpl.bp.out'
function InstalledCount($d) {
    if (Test-Path -LiteralPath $d) { (Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue).Count } else { 0 }
}

$deadline = (Get-Date).AddSeconds(300)
while ((Get-Date) -lt $deadline) {
    if (((InstalledCount $igcatDir) -ge $nGcat) -and ((InstalledCount $ioutDir) -ge $nOut)) { break }
    Start-Sleep -Seconds 1
}

# One more pass: the counts can reach target while the last file is still being
# written, and a settled tree costs two seconds to confirm.
$before = -1
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
    $now = (InstalledCount $igcatDir) + (InstalledCount $ioutDir)
    if ($now -eq $before) { break }
    $before = $now
    Start-Sleep -Seconds 2
}

# ---------------------------------------------------------------------------
Step 8 "What was installed"

if (-not (Test-Path -LiteralPath $igcatDir)) {
    Fail "no $igcatDir after the install - it did not complete"
}

$iGcat = InstalledCount $igcatDir
$iOut  = InstalledCount $ioutDir
Write-Host ("   gcat {0} (staged {1})   GPL.BP.OUT {2} (staged {3})" -f $iGcat, $nGcat, $iOut, $nOut)
$b = Get-Item -LiteralPath (Join-Path $igcatDir '$BCOMP') -ErrorAction SilentlyContinue
if ($b) { Write-Host ("   `$BCOMP {0:N0} bytes" -f $b.Length) }

# Reported against the stage rather than against a remembered constant, so this
# stays true when the counts legitimately change.
if (($iGcat -lt $nGcat) -or ($iOut -lt $nOut)) {
    Fail ("the install is SHORT of the staged tree - gcat {0}/{1}, GPL.BP.OUT {2}/{3}.`n" +
          "  Nothing measured on this tree means anything." -f $iGcat, $nGcat, $iOut, $nOut)
}

# ---------------------------------------------------------------------------
# Step 9 - DID ANYBODY GET A PASSWORD?
#
# ADDED 23 Aug 2026, after this cost two sessions.  sd.iss:1276 is
# "if InstallReachedPostInstall and not WizardSilent then RunFinishingStep;",
# and RunFinishingStep (sd.iss:1211) is where the password is taken - by leaving
# the user in an SD session, the owner's decision of 21 Aug 2026.  SO A -Silent
# INSTALL COLLECTS NO PASSWORD AT ALL, and the tree otherwise looks complete.
#
# WHAT THAT COSTS, and it is not only the login: no ssh, no API, and any
# ELEVATED session that runs "sd <command>" from a console stops at the
# credential prompt and blocks for ever, because LOGIN:639 sees a tty and
# assumes somebody is there to type.  That is the fault the forty-fourth session
# handed over as an unexplained start-up hang.
#
# READ, NOT INFERRED FROM -Silent.  A non-silent install where the user pressed
# Enter on an empty line is the same state and deserves the same warning; and if
# the step is ever fixed to run silently this check keeps working unchanged.
# This script is already elevated, which is what makes $cred readable at all -
# it is SYSTEM and Administrators only.
Write-Host ""
$credDir = Join-Path $env:ProgramData 'SD\sdsys\$cred'
$nCred   = 0
try   { $nCred = @(Get-ChildItem -LiteralPath $credDir -File -Force -ErrorAction Stop).Count }
catch { $nCred = -1 }

if ($nCred -eq 0) {
    Write-Host "NO ACCOUNT HAS A PASSWORD - the credential register is empty." -ForegroundColor Yellow
    Write-Host "  A -Silent install skips the password step entirely (sd.iss:1276)." -ForegroundColor Yellow
    Write-Host "  Until one is set: no ssh, no API, and an ELEVATED 'sd <command>' at a" -ForegroundColor Yellow
    Write-Host "  console will BLOCK at the password prompt - which stalls the verify suite." -ForegroundColor Yellow
    Write-Host "  Set one now, at a console:  sd" -ForegroundColor Yellow
} elseif ($nCred -lt 0) {
    Write-Host "Could not read $credDir - cannot say whether any account has a password." -ForegroundColor Yellow
} else {
    Write-Host "   credential register: $nCred account(s) with a password"
}

Write-Host ""
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "CYCLE COMPLETE - the install matches source.  Measure now, and stop measuring at the next source change." -ForegroundColor Green
    StopCycleTranscript
} else {
    Write-Host ""
    Write-Host "INSTALLED, BUT assert-current REFUSES - read what it listed above before believing any measurement." -ForegroundColor Yellow
    StopCycleTranscript
    exit 1
}
