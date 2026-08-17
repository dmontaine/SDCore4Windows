# assert-current.ps1 - refuse to test a tree that source has moved past
#
#   powershell -File assert-current.ps1            check, print why
#   powershell -File assert-current.ps1 -Quiet     check, print only on failure
#
# Exit 0 the installed tree matches source, 1 it is stale, 2 the question
# cannot be answered (nothing installed, no repository).
#
# WHY THIS EXISTS AS CODE RATHER THAN A RULE.  CLAUDE.md has required since
# 15 Aug 2026 that a test cycle begin with a fresh install, and the rule was
# still broken twice on 15 Aug 2026 - both times in the same way, and neither
# time by ignoring it.  The rule says when a cycle BEGINS and says nothing
# about what ENDS one, so "install, start testing, edit source, keep reading
# results" passes it while producing measurements of a tree that no longer
# exists.  The two cases:
#
#   * sd.iss was edited after the installer was built, and the run in flight
#     carried on being read afterwards.
#   * GPL.BP/OS_GROUP was hand-recompiled into the installed tree and
#     LIST.GRANTS then measured on it.
#
# A result from a stale tree is worse than no result: it looks like evidence.
# PROJECT_STATUS.md section 6 records what that has already cost.
#
# THE BIAS IS DELIBERATE.  A false "stale" costs one install; a false "current"
# costs an investigation of a bug that was fixed hours ago.  So touching a file
# without changing it fails this check, and that is the right way round.
#
# HASHING sd.exe IS NOT ENOUGH ON ITS OWN, which is the trap this is really
# for.  Most changes in this project are BASIC, messages, dictionaries and the
# installer script - none of which touch sd.exe.  A guard that compared only
# the binary would have passed, cheerfully, through every stale test today.

param([switch]$Quiet)

$ErrorActionPreference = 'Continue'

$sd64    = Split-Path $PSScriptRoot -Parent                        # ...\sdb_ai\sd64
$built   = Join-Path $sd64 'bin\sd.exe'
$inst    = 'C:\Program Files\SD\usr\bin\sd.exe'
$instTree = 'C:\ProgramData\SD\sdsys'

function Note($m) { if (-not $Quiet) { Write-Output $m } }
function Bad($m)  { Write-Output "STALE: $m" }

if (-not (Test-Path $inst))     { Write-Output 'assert-current: nothing installed'; exit 2 }
if (-not (Test-Path $built))    { Write-Output 'assert-current: no bin/sd.exe - run "make sd"'; exit 2 }
if (-not (Test-Path $instTree)) { Write-Output 'assert-current: no installed data tree'; exit 2 }

$stale = $false

# --- A. the binary.  Cheap, decisive when it fires, and blind to everything else.
$hi = (Get-FileHash $inst).Hash
$hb = (Get-FileHash $built).Hash
if ($hi -ne $hb) {
    Bad ("installed sd.exe {0} does not match bin/sd.exe {1}" -f $hi.Substring(0,16), $hb.Substring(0,16))
    $stale = $true
} else {
    Note ("  sd.exe matches: {0}" -f $hi.Substring(0,16))
}

# --- B. everything the binary cannot see.
#
# The install moment is when the data tree was CREATED - the files inside it
# keep their source timestamps, having been copied from the staging tree, so
# their own mtimes say nothing about when they were installed.
$installed = (Get-Item $instTree).CreationTime
Note ("  installed at: {0}" -f $installed.ToString('dd MMM HH:mm:ss'))

# 17 Aug 26 - THE TEST SCRIPTS DO NOT MAKE AN INSTALL STALE, and leaving them in
# cost a run.  verify-tiers.ps1 was written after an install, and the first thing
# it does is call this script, which then refused BECAUSE of verify-tiers.ps1 -
# a verification script blocking itself.  Worse, the advice printed below said
# "stage.py --force --bootstrap", so the response was to hand-run the sequence
# that cycle.ps1 exists to replace, and that failed on semaphores.
#
# THE RULE IS THE SAME ONE localtest\ AND __pycache__ ALREADY USE: a file that is
# neither compiled into sd.exe nor staged into the install cannot make the
# installed tree differ from source.  These drive and measure an install; they
# never enter one.
#
# AND IT IS SELF-POLICING, because an exclusion list is exactly the sort of thing
# that rots into a false "current".  Each name is checked against stage.py and
# sd.iss below, and one that turns up in either is NOT excluded - so wiring a
# script into the install silently puts it back under the guard rather than
# silently leaving it out.  That keeps the bias in the header: a false stale
# costs one install, a false current costs an investigation.
$neverShipped = @('assert-current.ps1', 'cycle.ps1', 'verify-tiers.ps1',
                  'verify-createaccount.ps1', 'verify-sshonly.ps1',
                  'verify-allowgroups.ps1', 'verify-apiport.ps1')

$shipEvidence = ''
foreach ($f in @('stage.py', 'sd.iss')) {
    $p = Join-Path $PSScriptRoot $f
    if (Test-Path $p) { $shipEvidence += (Get-Content -LiteralPath $p -Raw) }
}
# QUOTED OR PATH-PREFIXED, not merely mentioned.  The first version of this
# matched the bare name and immediately reinstated assert-current.ps1, because
# stage.py line 268 discusses it in a COMMENT.  A file that actually ships is
# named the way a ship list names one - 'deny-logon.ps1' in stage.py's tuple, or
# ...\deny-logon.ps1" in sd.iss's Source line - so the quote or the separator is
# the thing that distinguishes a reference from a remark.
$shipsAs = { param($n) $shipEvidence -match ("[""'\\/]" + [regex]::Escape($n)) }

$excluded   = @($neverShipped | Where-Object { -not (& $shipsAs $_) })
$reinstated = @($neverShipped | Where-Object {      (& $shipsAs $_) })
if ($reinstated.Count -gt 0) {
    Note ("  note: {0} now appears in stage.py or sd.iss, so it is watched again" -f ($reinstated -join ', '))
}

$trees = @('gplsrc', 'sdsys', 'gplbld') | ForEach-Object { Join-Path $sd64 $_ }
$newer = @()
foreach ($t in $trees) {
    if (-not (Test-Path $t)) { continue }
    # 17 Aug 26 - localtest\ joins __pycache__ as BUILD OUTPUT that happens to
    # sit inside a watched tree.  "make check-local" compiles the step 11 test
    # into gplsrc\sdclilib\localtest, so without this every run of that test
    # would leave this script reporting STALE for ever afterwards - a false
    # stale that no reinstall clears, because the next run recreates it.
    # This does NOT loosen the guard: nothing there is a source of sd.exe or of
    # the installed tree, and the other sdclilib test binaries are excluded by
    # the same reasoning if they are ever moved beside it.
    $newer += Get-ChildItem $t -Recurse -File -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and
                             $_.FullName -notmatch '\\localtest\\' -and
                             $excluded -notcontains $_.Name -and
                             $_.LastWriteTime -gt $installed }
}

if ($newer.Count -gt 0) {
    Bad ("{0} source file(s) are newer than the install:" -f $newer.Count)
    $newer | Sort-Object LastWriteTime -Descending | Select-Object -First 10 | ForEach-Object {
        Write-Output ("       {0}  {1}" -f $_.LastWriteTime.ToString('dd MMM HH:mm:ss'), $_.FullName.Substring($sd64.Length + 1))
    }
    if ($newer.Count -gt 10) { Write-Output ("       ... and {0} more" -f ($newer.Count - 10)) }
    $stale = $true
} else {
    Note '  no source file is newer than the install'
}

if ($stale) {
    Write-Output ''
    Write-Output 'REFUSING - any measurement taken now describes a tree that no longer exists.'
    Write-Output ''
    Write-Output 'Run one cycle, from an ELEVATED PowerShell:'
    Write-Output ("    " + (Join-Path $PSScriptRoot 'cycle.ps1'))
    Write-Output ''
    # 17 Aug 26 - IT NAMES THE SCRIPT, NOT THE STEPS.  This used to print
    # "stage.py --force --bootstrap, ISCC, uninstall, delete BOTH trees,
    # install", and somebody following that advice ran stage.py by hand against
    # a machine whose SD service was still up.  sd -stop shut the daemon down,
    # the semaphores outlived it, sd -start refused, and the staged tree was
    # left in the seed state - which is the state that shipped a
    # catalogue-less install on 16 Aug.  cycle.ps1 stops the service first.
    Write-Output 'It stops the service, stages, bootstraps, builds the installer, uninstalls,'
    Write-Output 'deletes BOTH trees and installs.  Do not hand-run the steps - CLAUDE.md.'
    exit 1
}

Note 'assert-current: the installed tree matches source'
exit 0
