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

# --- A2. the binary is only as current as the last "make sd".
#
# 18 Aug 26 - CHECK A COMPARES TWO BINARIES AND CANNOT SEE AN UNCOMPILED SOURCE
# CHANGE, which is how a C edit reached a commit having never run.  to_file.c
# was changed at 19:15, cycle.ps1 ran at 19:38 - and cycle.ps1 CONTAINS NO
# "make".  It stages what is already in bin\.  So the installed sd.exe matched
# bin/sd.exe (both two hours old, both equal), check B compared source mtimes
# against the INSTALL time and to_file.c was older than that, and both checks
# passed on a binary that did not contain the change.
#
# THE HEADER ABOVE REASONS ABOUT THE OPPOSITE DIRECTION - "most changes here are
# BASIC, so hashing sd.exe is not enough" - and that is true and is why B
# exists.  This is the other half: for the changes that ARE C, the binary is the
# only thing that carries them, and nothing checked that it had been rebuilt.
#
# WHAT MADE IT COSTLY RATHER THAN OBVIOUS: the test for the change PASSED.
# to_file.c moved the hold file's relative path from $HOLD to $hold, NTFS matches
# either spelling against the $hold directory, so printing to the hold file
# worked on the old binary exactly as it does on the new one.  A green run on a
# stale binary is the failure this whole script exists to prevent.
#
# AGAINST THE OLDEST BINARY IN bin\, not sd.exe alone, so a change under
# gplsrc\sdclilib or gplsrc\sdsvc counts too - those build sdclilib.dll and
# sdsvc.exe, which ship in the same install.  A source change that rebuilds none
# of them is still a false stale, and that is the right way round.
$binaries = @(Get-ChildItem (Join-Path $sd64 'bin') -File |
              Where-Object { $_.Extension -in '.exe', '.dll' })
if ($binaries.Count -eq 0) {
    Bad 'bin\ holds no binaries - run "make sd"'
    $stale = $true
} else {
    $oldestBuilt = ($binaries | Sort-Object LastWriteTime | Select-Object -First 1)
    # 18 Aug 26 - THE SAME TWO EXCLUSIONS CHECK B USES BELOW, and A2 was written
    # without them.  That produced a FALSE STALE THAT NO REINSTALL CLEARS:
    # "make check-local" builds gplsrc\sdclilib\localtest\local-connect-test.exe,
    # which is then newer than everything in bin\, and the next run of
    # check-local recreates it.  The post-cycle sequence this repository
    # documents is cycle, then check-local, then the verify scripts - so every
    # verify script after the first refused to run.  Check B's comment below
    # foresaw exactly this; A2 simply did not inherit it.  Nothing under
    # localtest\ or __pycache__ is a source of sd.exe, so this does not loosen
    # the guard.
    # 19 Aug 26 - sdclilib\tests\ excluded here too, and Check B's comment gives
    # the reasoning.  Nothing in that directory is compiled INTO sd.exe or the
    # client DLL - the tests link against the DLL, they are not part of it - so
    # "run make sd" is the wrong instruction for an edit there and the sequence
    # it interrupts is the one that would have run the test.
    # 19 Aug 26 - AND BUILD PRODUCTS ARE NOT SOURCE.  A2 asks one question -
    # "is any SOURCE newer than the binaries" - and a .exe, .dll, .a or .o is
    # by definition an answer to it, not part of it.  "make check" in
    # gplsrc\sdclilib builds smoke-test.exe and internal-state-test.exe INTO
    # THAT DIRECTORY rather than into localtest\, so running the client's own
    # tests made this report "run make sd" for ever afterwards - the same false
    # stale localtest\ was added for, arriving by a different route.  Filtering
    # on the extension rather than on a list of names means the next build
    # product to appear there is covered before anybody trips over it.
    $buildProducts = '\.(exe|dll|a|o|obj|lib|exp)$'

    # 20 Aug 26 - AND DOCUMENTATION IS NOT SOURCE EITHER, for the same reason
    # and by the same test: nothing compiles a .md into sd.exe or the client
    # DLL, and gplsrc is not installed at all - it is C source, and stage.py
    # ships sdsys.  So an edit to gplsrc\sdclilib\VENDORING.md answered "run
    # make sd, then run a cycle", and BOTH would have been pointless: the
    # rebuild has nothing to read and the install has nothing to receive.
    #
    # FOUND BY DOING IT.  Editing VENDORING.md to record the client packaging
    # work turned this check red, on a tree that had just cycled and passed the
    # whole suite - so the next session would have spent an install on a
    # markdown file, or learned to distrust the guard, which is worse.
    #
    # THE RULE IS THE ONE THE EXCLUSIONS ABOVE ALREADY FOLLOW: a file that
    # cannot reach the binaries or the install cannot make either of them
    # stale.  Extension rather than a list of names, so the next document is
    # covered before anybody trips over it.
    $documentation = '\.(md|txt)$'
    $uncompiled  = @(Get-ChildItem (Join-Path $sd64 'gplsrc') -Recurse -File |
                     Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and
                                    $_.FullName -notmatch '\\localtest\\' -and
                                    $_.FullName -notmatch '\\sdclilib\\tests\\' -and
                                    $_.Name -notmatch $buildProducts -and
                                    $_.Name -notmatch $documentation -and
                                    $_.LastWriteTime -gt $oldestBuilt.LastWriteTime })
    if ($uncompiled.Count -gt 0) {
        Bad ("{0} source file(s) are newer than bin\{1} ({2}) - run 'make sd':" -f
             $uncompiled.Count, $oldestBuilt.Name,
             $oldestBuilt.LastWriteTime.ToString('dd MMM HH:mm:ss'))
        $uncompiled | Sort-Object LastWriteTime -Descending | Select-Object -First 10 |
            ForEach-Object {
                Write-Output ("       {0}  {1}" -f
                    $_.LastWriteTime.ToString('dd MMM HH:mm:ss'),
                    $_.FullName.Substring($sd64.Length + 1))
            }
        $stale = $true
    } else {
        Note ("  bin\ built {0}, no source newer" -f
              $oldestBuilt.LastWriteTime.ToString('dd MMM HH:mm:ss'))
    }
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
                  'verify-allowgroups.ps1', 'verify-apiport.ps1',
                  'verify-credacl.ps1', 'verify-nocase.ps1',
                  'verify-osusers.ps1', 'verify-catgate.ps1',
                  'verify-fold.ps1', 'verify-nonet.ps1',
                  'verify-lcnames.ps1', 'post-cycle-elevated.ps1',
                  'verify-keys.ps1', 'probe-keys.ps1',
                  'verify-editkeys.ps1', 'verify-scramlogin.ps1',
                  # 19 Aug 26 - verify-scram.c and its build product were added
                  # on 19 Aug and never listed here, so both showed up under
                  # "newer than the install" from the moment they existed.
                  # THE .exe MATTERS MORE THAN IT LOOKS: docs/SCRAM_HANDOFF.md
                  # tells the next session to rebuild it by hand, which would
                  # have made this script report STALE afterwards - and
                  # verify-scramlogin.ps1 refuses to run without it, so
                  # rebuilding the C test would have blocked the BASIC one for
                  # a reason with nothing to do with either.
                  'verify-scram.c', 'verify-scram.exe',
                  # 19 Aug 26 - phase 4's client-side equivalent, and the
                  # 32-bit build of it.  Same reasoning: test source and build
                  # products that live in a watched tree and never ship.
                  'verify-scramclient.c', 'verify-scramclient.exe',
                  'verify-scramclient32.exe',
                  # 19 Aug 26 - "make check" in gplsrc\sdclilib builds these
                  # two INTO THAT DIRECTORY rather than into localtest\, so
                  # they are the same false stale the localtest\ exclusion was
                  # added for, by a different route: run the client's own
                  # tests and every verify script afterwards refuses, for a
                  # reason that has nothing to do with the installed tree.
                  'smoke-test.exe', 'internal-state-test.exe',
                  # 20 Aug 26 - the SET.PASSWORD trailing-token verifier, added
                  # the same day as the guard it tests.  A verify script is not
                  # shipped by stage.py or sd.iss and cannot reach an installed
                  # tree, so without this line WRITING a test would make every
                  # test refuse to run - which is the toll section 7 step 11
                  # already recorded for remote_connect_test.c.
                  'verify-setpw.ps1',
                  # 20 Aug 26 - and the tier/API verifier, same reasoning.
                  'verify-tierapi.ps1',
                  # 20 Aug 26 - section 8's per-account ACL verifier, same
                  # reasoning again.  It is the one that would hurt most to
                  # leave out: it CALLS this script and refuses on a non-zero
                  # exit, so an unlisted verify-accountacl.ps1 would report the
                  # tree stale because verify-accountacl.ps1 exists, and then
                  # refuse to run on the strength of its own newness.
                  'verify-accountacl.ps1',
                  # 20 Aug 26 - section 8's RDPACCOUNT verifier, same reasoning.
                  'verify-rdpaccount.ps1')

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
    # 19 Aug 26 - gplsrc\sdclilib\tests\ joins them, and for the same reason.
    # 20 Aug 26 - AND DOCUMENTATION, which is the same toll by a third route:
    # editing gplsrc\sdclilib\VENDORING.md turned this red on a tree that had
    # just cycled and passed the whole suite, so the next session would have
    # spent an install on a markdown file - or learned to distrust the guard,
    # which is worse.  Nothing under gplsrc is installed at all; stage.py
    # ships sdsys.
    #
    # BUT IT ASKS $shipsAs RATHER THAN EXCLUDING THE EXTENSION OUTRIGHT.  A
    # blunt filter would hide a .md or .txt that somebody later DOES ship, and
    # that is the dangerous direction: a false stale costs one install, a false
    # current costs an investigation.  This way a document is watched again the
    # moment it appears in stage.py or sd.iss, which is exactly what the
    # $neverShipped list above already does by name.
    # It is TEST SOURCE: eight .c files, not one of them named in stage.py or
    # sd.iss, none of which can reach an installed tree.  PROJECT_STATUS
    # section 7 step 11 recorded that editing remote_connect_test.c owed a full
    # cycle before verify-apiport.ps1 would run again - and verify-apiport
    # calls this script first, so improving the test blocked the test.  A cycle
    # that reinstalls nothing is not a guard, it is a toll.
    $newer += Get-ChildItem $t -Recurse -File -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and
                             $_.FullName -notmatch '\\localtest\\' -and
                             $_.FullName -notmatch '\\sdclilib\\tests\\' -and
                             -not ($_.Extension -in '.md', '.txt' -and -not (& $shipsAs $_.Name)) -and
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
