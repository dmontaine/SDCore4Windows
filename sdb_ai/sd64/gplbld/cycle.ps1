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

.PARAMETER Silent
    Install with /VERYSILENT.  Off by default: the wizard pages are part of
    what a cycle is meant to show (PROJECT_STATUS.md 7 step 3).

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\cycle.ps1
#>

[CmdletBinding()]
param(
    [string] $Stage = 'C:\Users\dmont\stagetest',
    [string] $Out   = 'C:\Users\dmont\sdout',
    [switch] $SkipInstall,
    [switch] $Silent
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

# gplbld\ -> sd64\.  Every path below is absolute and derived from this script's
# own location, which is the whole point: the hand-run sequence broke on a
# relative path resolved against C:\WINDOWS\system32.
$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sd64    = Split-Path -Parent $Gplbld
$Iss     = Join-Path $Gplbld 'sd.iss'
$Iscc    = 'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
$Bash    = 'C:\msys64\usr\bin\bash.exe'
$SvcName = 'SD'
$PfTree  = 'C:\Program Files\SD'
$PdTree  = 'C:\ProgramData\SD'

function Step($n, $msg) { Write-Host ""; Write-Host "== [$n] $msg" -ForegroundColor Cyan }
function Fail($msg)     { Write-Host ""; Write-Host "CYCLE STOPPED: $msg" -ForegroundColor Red; exit 1 }

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
$left = Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue
if ($left) {
    # Named, not killed.  A surviving sd is somebody's session, and ending it
    # from here would take their work with it.
    Fail ("SD is still running after 45s: " +
          (($left | ForEach-Object { "$($_.Name)($($_.Id))" }) -join ', ') +
          "`n  Close any SD session and run this again.")
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
$nOut    = CountIn 'GPL.BP.OUT'
$szCproc = if (Test-Path -LiteralPath (Join-Path $Sdsys 'gcat\$CPROC')) {
               (Get-Item -LiteralPath (Join-Path $Sdsys 'gcat\$CPROC')).Length } else { -1 }
$szBcomp = if (Test-Path -LiteralPath (Join-Path $Sdsys 'gcat\$BCOMP')) {
               (Get-Item -LiteralPath (Join-Path $Sdsys 'gcat\$BCOMP')).Length } else { -1 }

Write-Host ("   gcat {0} (want ~132)   GPL.BP.OUT {1} (want ~193)" -f $nGcat, $nOut)
Write-Host ("   `$CPROC {0} bytes (want >0)   `$BCOMP {1} (want 87,992 - 70,697 is the seed)" -f $szCproc, $szBcomp)

$faults = @()
if ($szCproc -le 0)   { $faults += '$CPROC is the 0-byte placeholder - the bootstrap never reached the last step' }
if ($nGcat   -lt 100) { $faults += "gcat holds $nGcat entries" }
if ($nOut    -lt 150) { $faults += "GPL.BP.OUT holds $nOut objects" }
if ($szBcomp -eq 70697) { $faults += '$BCOMP is bbcmp.py''s seed, not BCOMP''s own object' }
if (-not (Test-Path -LiteralPath (Join-Path $Sdsys 'VOC'))) { $faults += "VOC is absent - 'sd -i' did not complete" }
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

$installArgs = @()
if ($Silent) { $installArgs += '/VERYSILENT' }

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
$ioutDir  = Join-Path $PdTree 'sdsys\GPL.BP.OUT'
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

Write-Host ""
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "CYCLE COMPLETE - the install matches source.  Measure now, and stop measuring at the next source change." -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "INSTALLED, BUT assert-current REFUSES - read what it listed above before believing any measurement." -ForegroundColor Yellow
    exit 1
}
