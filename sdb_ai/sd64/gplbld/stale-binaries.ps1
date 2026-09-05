# stale-binaries.ps1 - is anything under gplsrc newer than the binaries in bin\?
#
# DOT-SOURCE IT; it defines functions and runs nothing.
#
#     . (Join-Path $PSScriptRoot 'stale-binaries.ps1')
#     $s = Get-BinaryStaleness $sd64
#
# NOT SHIPPED - it is on assert-current.ps1's $neverShipped list, added in the
# commit that created it.  Nothing installs it and nothing compiles it into
# sd.exe.
#
# ===========================================================================
# WHY IT IS ITS OWN FILE
# ===========================================================================
#
# 03 Sep 26 Windows port.  This rule was assert-current.ps1's check A2 and had
# exactly one consumer.  It now has two: cycle.ps1's step 0 asks the same
# question to decide whether to run "make sd" before staging anything, and it
# must get the SAME answer - a cycle that thought the C was current while
# assert-current thought otherwise would build an installer nobody could then
# measure, which is the failure that produced this step in the first place.
#
# ***THE ALTERNATIVE WAS A SECOND HAND-MAINTAINED COPY, AND THAT IS THE DEFECT
# THREE OF THIS TREE'S FREE GUARDS ALREADY EXIST TO CATCH*** -
# test-stemcoverage-units, test-dirscoverage-units and the CLAUDE.md free-check
# list itself are all "two files describe one fact and are kept in step by
# hand".  The exclusions below were each paid for by a false STALE that cost a
# session; a copy of them would rot silently, and the tell would be a guard
# that had quietly stopped guarding.
#
# gplbld/test-stalebin-units.ps1 drives it.
#
# START-HISTORY:
# 03 Sep 26 Windows port - lifted out of assert-current.ps1 unchanged, so
#           cycle.ps1's new step 0 and the guard cannot disagree.  The rule,
#           the exclusions and their reasons are as they were; only the file
#           they live in is new.
# END-HISTORY

# ===========================================================================
#   WHAT COUNTS AS A BINARY
#
# .exe and .dll BY EXTENSION, which quietly does two useful things:
#   * sd.exe.installed-backup-<date> is NOT one - its extension is
#     ".installed-backup-<date>" - so a kept backup cannot make the oldest
#     binary months old and every source file permanently stale.
#   * libsdclilib.dll.a is NOT one either, for the same reason; it is an import
#     library that is rebuilt with the DLL rather than a thing to compare.
# ===========================================================================

function Get-BinBinaries([string]$sd64) {
    $bin = Join-Path $sd64 'bin'
    if (-not (Test-Path -LiteralPath $bin)) { return @() }
    return @(Get-ChildItem -LiteralPath $bin -File -ErrorAction SilentlyContinue |
             Where-Object { $_.Extension -in '.exe', '.dll' })
}

# ===========================================================================
#   WHAT COUNTS AS SOURCE
#
# EVERY EXCLUSION BELOW WAS PAID FOR BY A FALSE "STALE" THAT NO REINSTALL
# CLEARS.  They are kept verbatim from assert-current.ps1's A2, comments and
# all, because the reasons are the whole value:
#
#   18 Aug 26  localtest\ - "make check-local" builds
#     gplsrc\sdclilib\localtest\local-connect-test.exe, which is then newer than
#     everything in bin\, and the next run recreates it.  The documented
#     post-cycle sequence is cycle, then check-local, then the verify scripts -
#     so every verify script after the first refused to run.  __pycache__ with
#     it; nothing under either is a source of sd.exe.
#
#   19 Aug 26  sdclilib\tests\ - nothing there is compiled INTO sd.exe or the
#     client DLL; the tests link AGAINST the DLL.  So "run make sd" is the wrong
#     instruction for an edit there, and the sequence it interrupts is the one
#     that would have run the test.
#
#   19 Aug 26  BUILD PRODUCTS ARE NOT SOURCE.  This asks one question - "is any
#     SOURCE newer than the binaries" - and a .exe, .dll, .a or .o is by
#     definition an answer to it, not part of it.  "make check" in
#     gplsrc\sdclilib builds smoke-test.exe and internal-state-test.exe INTO
#     THAT DIRECTORY, so running the client's own tests made this report "run
#     make sd" for ever afterwards.  FILTERED ON THE EXTENSION rather than on a
#     list of names, so the next build product is covered before anybody trips
#     over it.
#
#   20 Aug 26  AND DOCUMENTATION IS NOT SOURCE EITHER.  Nothing compiles a .md
#     into sd.exe or the client DLL, and gplsrc is not installed at all.  An
#     edit to gplsrc\sdclilib\VENDORING.md answered "run make sd, then run a
#     cycle", and BOTH would have been pointless: the rebuild has nothing to
#     read and the install has nothing to receive.  Found by doing it, on a tree
#     that had just cycled and passed the whole suite - so the next session
#     would have spent an install on a markdown file, or learned to distrust the
#     guard, which is worse.
#
# THE RULE THEY ALL FOLLOW: a file that cannot reach the binaries or the
# install cannot make either of them stale.
# ===========================================================================

function Test-IsSdSource([string]$fullName, [string]$name) {
    $buildProducts = '\.(exe|dll|a|o|obj|lib|exp)$'
    $documentation = '\.(md|txt)$'

    # 04 Sep 26 - GENERATED, AND BY NAME RATHER THAN BY EXTENSION.
    # PRE_RELEASE_FIXES 161.  gplsrc\sdclilib\qmclient.def is qmclilib.def with
    # its LIBRARY line rewritten by the Makefile, so watching it adds nothing:
    # it cannot change without the file it is generated FROM changing first.
    #
    # ".def" IS A SOURCE EXTENSION HERE and must not be excluded outright.
    # qmclilib.def is the 99-name export list of the two 32-bit DLLs - the one
    # file whose edit changes what they export while no .c file moves - so a
    # blunt '\.def$' would hide exactly the change nothing else would catch.
    $generated = '^qmclient\.def$'

    if ($fullName -match '\\__pycache__\\')     { return $false }
    if ($fullName -match '\\localtest\\')       { return $false }
    if ($fullName -match '\\sdclilib\\tests\\') { return $false }
    # 04 Sep 26 - sdclilib\tools\ joins tests\ for the identical reason, and it
    # arrived with PRE_RELEASE_FIXES 161.  tools\sd_connect.c builds
    # sd-connect.exe, which LINKS AGAINST qmclilib.dll rather than being
    # compiled into it, and which ships nowhere - stage.py's CLIENT_DIRS names
    # the two DLLs explicitly.  So an edit there can no more reach an install
    # than an edit under tests\ can, and answering it with "run a cycle" would
    # be the toll that entry describes rather than a guard.
    if ($fullName -match '\\sdclilib\\tools\\') { return $false }
    if ($name -match $buildProducts)            { return $false }
    if ($name -match $documentation)            { return $false }
    if ($name -match $generated)                { return $false }
    return $true
}

# ===========================================================================
#   THE ANSWER
#
# A HASHTABLE, NOT A COLLECTION.  A PowerShell function returning @() hands the
# caller $null and one returning a single item hands it a bare scalar, so
# "nothing is stale" and "I could not look" would be the same value - measured
# on 3 Sep 2026 in reconcile-accounts.ps1, where it made a healthy service log a
# failure with no line saying why.
#
#   ok          $false ONLY when the question could not be answered
#   reason      why not, when ok is $false
#   binaries    the .exe/.dll files considered - and, for a caller that wants to
#               force a full relink, exactly the set to delete
#   oldest      the oldest of them, which is what source is compared against
#   uncompiled  source files newer than that, newest first
#   stale       $true when uncompiled is not empty
#
# AGAINST THE OLDEST BINARY, NOT sd.exe ALONE, so a change under
# gplsrc\sdclilib or gplsrc\sdsvc counts too - those build sdclilib.dll and
# sdsvc.exe, which ship in the same install.  A source change that rebuilds none
# of them is still a false stale, and that is the right way round: a false
# "stale" costs one build, a false "current" costs an investigation of a bug
# that was fixed hours ago.
# ===========================================================================

function Get-BinaryStaleness([string]$sd64) {
    $binaries = @(Get-BinBinaries $sd64)
    if ($binaries.Count -eq 0) {
        return @{ ok = $false; reason = 'bin\ holds no binaries - run "make sd"';
                  binaries = @(); oldest = $null; uncompiled = @(); stale = $true }
    }

    $gplsrc = Join-Path $sd64 'gplsrc'
    if (-not (Test-Path -LiteralPath $gplsrc)) {
        return @{ ok = $false; reason = ('no gplsrc at ' + $gplsrc);
                  binaries = $binaries; oldest = $null; uncompiled = @(); stale = $true }
    }

    $oldest = ($binaries | Sort-Object LastWriteTime | Select-Object -First 1)

    $uncompiled = @(Get-ChildItem -LiteralPath $gplsrc -Recurse -File -ErrorAction SilentlyContinue |
                    Where-Object { (Test-IsSdSource $_.FullName $_.Name) -and
                                   $_.LastWriteTime -gt $oldest.LastWriteTime } |
                    Sort-Object LastWriteTime -Descending)

    return @{ ok = $true; reason = ''; binaries = $binaries; oldest = $oldest;
              uncompiled = $uncompiled; stale = ($uncompiled.Count -gt 0) }
}
