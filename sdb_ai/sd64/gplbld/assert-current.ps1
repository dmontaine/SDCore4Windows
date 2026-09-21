# assert-current.ps1 - refuse to test a tree that source has moved past
#
#   powershell -ExecutionPolicy Bypass -File assert-current.ps1            check, print why
#   powershell -ExecutionPolicy Bypass -File assert-current.ps1 -Quiet     check, print only on failure
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
#   * gpl.bp/os_group was hand-recompiled into the installed tree and
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

# ---------------------------------------------------------------------------
# ABSENT AND FORBIDDEN ARE DIFFERENT ANSWERS, AND THIS LINE USED TO GIVE THE
# WRONG ONE.  PRE_RELEASE_FIXES 182, 6 Sep 2026.  `Test-Path` on the data tree
# THREW `UnauthorizedAccessException: Access is denied` - a fresh install had
# recreated sdusers with a new SID and the caller's logon token predated it -
# and the -not on a call that returned nothing took the false branch.  So a
# 40-minute-old, perfectly good install was reported as
# `no installed data tree`, exit 2.
#
# THE TWO STATES WANT OPPOSITE CURES: absent wants a cycle, forbidden wants a
# new logon.  Naming the wrong one sends the reader an hour in the wrong
# direction, and Handoff 45 had already recorded that this exit 2 is "CORRECT
# rather than a fault" - true the day nothing was installed, and the sentence a
# later session would read while holding a denial in its hand.
# ***-ErrorAction Stop IS LOAD-BEARING, AND THE FIRST VERSION OF THIS FIX DID
# NOT HAVE IT.*** Measured 6 Sep 2026 against a directory carrying a DENY ACE
# for the running user: `Test-Path` reports "Access is denied" as a
# NON-TERMINATING error - it writes to the error stream and RETURNS - so a bare
# try/catch never fires and the classifier still answered `absent`.  The fix
# was driven before it was believed, which is the only reason that was found;
# `-ErrorAction Stop` promotes it, and then the catch is reached.
$treeState = 'absent'
try { if (Test-Path -LiteralPath $instTree -ErrorAction Stop) { $treeState = 'present' } }
catch { $treeState = 'denied' }

if ($treeState -eq 'denied') {
    Write-Output ("assert-current: {0} exists but this session cannot read it - Access is denied." -f $instTree)
    Write-Output '  THIS IS NOT A STALE TREE AND NOT A MISSING ONE.  The commonest cause is a'
    Write-Output '  logon token older than the install: a cycle recreates the sdusers group with'
    Write-Output '  a NEW SID, and Windows fixes group membership at sign-in, so a session that'
    Write-Output '  started before the install carries none of the SIDs the new ACLs grant to.'
    Write-Output '  SIGN OUT AND BACK IN, or restart, then run this again.  See PRE_RELEASE 182.'
    exit 2
}
if ($treeState -eq 'absent') { Write-Output 'assert-current: no installed data tree'; exit 2 }

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
#
# 03 Sep 26 - THE RULE MOVED TO gplbld/stale-binaries.ps1 AND NOTHING ABOUT IT
# CHANGED.  cycle.ps1's step 0 asks the same question to decide whether to run
# "make sd" before it stages anything, and a second hand-maintained copy of the
# exclusions below would be the defect three of this tree's free guards already
# exist to catch.  The wording this check prints is still its own.
. (Join-Path $PSScriptRoot 'stale-binaries.ps1')
$binState = Get-BinaryStaleness $sd64
if (-not $binState.ok) {
    Bad $binState.reason
    $stale = $true
} else {
    $oldestBuilt = $binState.oldest
    # WHAT COUNTS AS SOURCE, AND THE FALSE STALE EACH EXCLUSION WAS PAID FOR,
    # ARE IN stale-binaries.ps1 - localtest\, __pycache__, sdclilib\tests\,
    # build products by extension, and documentation.  They are unchanged; they
    # moved so that cycle.ps1 asks this question with the same answer.
    $uncompiled = @($binState.uncompiled)
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
# 21 Sep 26 - THE HARNESS FAMILY IS DERIVED, NOT LISTED.  Owner: cut the
# bookkeeping.  This list held 250 hand-kept names, about 210 of them scripts called
# verify-*, test-*, probe-*, check-* or clean-*, and every new script had to be added
# here by hand - which is why this was the most-edited file in gplbld (205 commits).
#
# NOW: every file in gplbld whose name starts verify-, test-, probe-, check- or
# clean- is exempt UNLESS stage.py or sd.iss names it (the self-policing rule
# below is unchanged, so check-install.ps1, which ships, stays watched).  Writing a
# new script in that family needs NO edit here.  The list below is only the
# harness files that do not follow that convention - 40 names, and it should not
# grow: name a new harness script in the family instead.
#
# EQUIVALENCE WAS PROVED against the old list before this replaced it, over the
# names present in gplsrc, sdsys and gplbld with the same ship evidence: ZERO files
# that were exempt became watched, and nine probe .c files that were watched
# (and so could have raised a false stale) became exempt.
$harnessFamily = '^(verify|test|probe|check|clean)-'
$neverShipped = @(
    # suite runners and guards
    'VerifyInstall1.ps1', 'VerifyInstall2.ps1', 'assert-current.ps1', 'cycle.ps1',
    'stale-binaries.ps1', 'strip-comments.ps1', 'suite-only.ps1', 'transcript-whole.ps1',
    'elevate-once.ps1', 'diff-capture.ps1', 'capture-state.ps1',
    # helpers the harness dot-sources or drives
    'sdtestuser.ps1', 'sdtestuser-admin.ps1', 'sdsys-seat.ps1', 'sdsys-run.ps1',
    'interop-account.ps1', 'stage-apiremote.ps1', 'python-detect.ps1',
    # generators and build tools that run from source
    'build-sdpy.ps1', 'build-sdpyclient.ps1', 'gen_includes.py', 'mkbasicsyntax.py',
    'mkvocdoc.py', 'checksyntax.py', 'scan-msgdiff.py', 'reword-yn-prompts.ps1',
    # fixtures and measurement stubs without the probe- prefix
    'apiadminprobe.sb', 'apiosexecprobe.sb', 'basicfuncs.sb', 'testsdcli.bp',
    'relay-hold.py', 'sample-sdstate.ps1', 'scram-probe.py',
    'internal-state-test.exe', 'smoke-test.exe', 'sdpy.exe',
    # VM rig and mailbox
    'vm-clone.ps1', 'vm-shares.ps1', 'vm-type.ps1', 'mail.sh')

# 02 Sep 26 - COMMENTS ARE STRIPPED FIRST.  PRE_RELEASE_FIXES 143, and it is the
# quote-or-slash rule below failing in the one place it was documented.
#
# The rule reads a SEPARATOR as evidence of a ship line, and sd.iss:4577 quotes
# "gplbld/probe-taskdialog.iss" - the rejected spelling - inside the paragraph
# explaining that spelling it that way is what makes the probe read as shipping.
# One match, in a comment, and the 21:28:26 cycle duly reported the probe as
# watched again when C:\Program Files\SD does not contain it.  The fix at :4569
# (name it with no separator) works; its own explanation cancelled it.
#
# SO THE FIX IS THE STRIPPER, NOT THE SENTENCE.  Rewording line 4577 would work
# once and lose the explanation, and the next comment that quotes a path would
# do it again - the class this tree has now paid for twice, 131 and 143.
# strip-comments.ps1 is the shared copy; test-retired-wording-units.ps1 grew it
# and now reads it from there too.
. (Join-Path $PSScriptRoot 'strip-comments.ps1')

$shipEvidence = ''
foreach ($f in @(@{ N = 'stage.py'; K = 'hash' }, @{ N = 'sd.iss'; K = 'iss' })) {
    $p = Join-Path $PSScriptRoot $f.N
    if (Test-Path $p) { $shipEvidence += (Get-StrippedText -Path $p -Kind $f.K) + "`n" }
}
# QUOTED OR PATH-PREFIXED, not merely mentioned.  The first version of this
# matched the bare name and immediately reinstated assert-current.ps1, because
# stage.py line 268 discusses it in a COMMENT.  A file that actually ships is
# named the way a ship list names one - 'deny-logon.ps1' in stage.py's tuple, or
# ...\deny-logon.ps1" in sd.iss's Source line - so the quote or the separator is
# the thing that distinguishes a reference from a remark.
$shipsAs = { param($n) $shipEvidence -match ("[""'\\/]" + [regex]::Escape($n)) }

# ***THE CONTROL, AND STRIPPING IS WHAT MAKES IT NECESSARY.***  The two callers
# of the stripper err in OPPOSITE directions: for the wording lint an
# over-strip hides a retired phrase, which its header calls the safe way to
# fail; here an over-strip hides a real Source line, the file stays excluded,
# and the tree reports CURRENT when it is stale - the expensive direction this
# script's own header names.  So a name known to ship is asserted to survive the
# strip, and a failure is fatal rather than a note: it means the evidence this
# whole section reasons from has been eaten.
#
# BOTH CANARIES ARE REAL SHIP LINES, one per file and per syntax - install-sdsys
# is named in an sd.iss line and in stage.py, deny-logon is a stage.py tuple
# member - so a strip that breaks either syntax is caught by the one that uses it.
$shipCanaries = @('install-sdsys.ps1', 'deny-logon.ps1')
$canaryMissing = @($shipCanaries | Where-Object { -not (& $shipsAs $_) })
if ($shipEvidence.Trim().Length -eq 0 -or $canaryMissing.Count -gt 0) {
    Write-Host ''
    Write-Host 'assert-current: CANNOT ANSWER - the ship evidence is not readable.' -ForegroundColor Red
    Write-Host ("  stripped evidence: {0} chars from stage.py and sd.iss" -f $shipEvidence.Trim().Length)
    if ($canaryMissing.Count -gt 0) {
        Write-Host ("  these ship and were NOT found after comment-stripping: {0}" -f ($canaryMissing -join ', '))
        Write-Host '  strip-comments.ps1 is eating shipped text, so every exclusion below is'
        Write-Host '  untrustworthy and a stale tree could report CURRENT.'
    }
    exit 2
}

# 21 Sep 26 - THE HARNESS FAMILY IS ENUMERATED HERE, NOT LISTED ABOVE.  Every gplbld
# file named verify-/test-/probe-/check-/clean-* is exempt unless stage.py or
# sd.iss names it, which is the same test the residual list gets.  An empty
# enumeration cannot be a quiet pass: it would exempt nothing and every harness
# edit would read as a stale install, so it refuses out loud instead.
$familyNames = @(Get-ChildItem -LiteralPath $PSScriptRoot -File -ErrorAction SilentlyContinue |
                 Where-Object { $_.Name -match $harnessFamily } | ForEach-Object { $_.Name })
if ($familyNames.Count -lt 50) {
    Write-Host ''
    Write-Host 'assert-current: CANNOT ANSWER - the harness script family did not resolve.' -ForegroundColor Red
    Write-Host ("  {0} files named {1} under {2}; expected well over 50." -f $familyNames.Count, $harnessFamily, $PSScriptRoot)
    exit 2
}
$excluded   = @((@($neverShipped) + $familyNames) | Where-Object { -not (& $shipsAs $_) } | Sort-Object -Unique)
$reinstated = @($neverShipped | Where-Object {      (& $shipsAs $_) })
if ($reinstated.Count -gt 0) {
    Note ("  note: {0} now appears in stage.py or sd.iss, so it is watched again" -f ($reinstated -join ', '))
}
Note ("  {0} harness scripts exempt: {1} by name family, {2} named in the residual list" -f
      $excluded.Count, @($familyNames | Where-Object { $excluded -contains $_ }).Count, $neverShipped.Count)

# 21 Aug 26 - THE ONE FILE THAT SHIPS AND IS DELIBERATELY NOT WATCHED.  Owner's
# decision.  Every list above exempts something that CANNOT reach the install;
# sdsys\changelog can, and is exempt anyway, so it needs its own list and its
# own justification.
#
# THE TOLL IT ENDS.  CLAUDE.md requires a changelog entry in the same commit as
# any user-visible change, so nearly every commit touches it - and every touch
# turned this script red, which makes the whole verify suite refuse, because
# each verifier calls this first.  The install that clears it reinstalls a text
# file nobody has read since it was written.  A guard that charges a cycle for
# writing documentation teaches the next session to skip the documentation or
# to skip the guard, and both are worse than what it is protecting against.
#
# IT CANNOT GO ON $neverShipped, and that is not a technicality.  That list is
# self-policing - anything on it that turns up quoted in stage.py or sd.iss is
# put BACK under the guard - and changelog is quoted, at stage.py:848 (it was
# :140 until 25 Aug 26, when it stopped shipping into the data tree and started
# shipping to {app}; it still ships, so this reasoning is unchanged).  So it
# would be reinstated on the next run and the exemption would silently do
# nothing.  Kept separate so the two lists keep their different meanings: that
# one says "this cannot make the install stale", this one says "this can, and
# we accept it".
#
# WHAT IS ACCEPTED: an installed tree may carry a changelog one or more entries
# behind source.  It is documentation for a user, read by nothing - no verifier
# measures it, no program reads it, and it cannot change behaviour.  That is the
# whole of the exposure, and it is why this file and no other is on this list.
#
# AND IT IS NOT SILENT, which is the condition the header's bias imposes: a
# false "current" costs an investigation, so the one place this script knowingly
# reports current on a stale file, it says so - by name, and NOT through Note(),
# so -Quiet does not swallow it.
#
# PATH-ANCHORED, NOT BY NAME.  The lists above match a bare file name because
# their names are distinctive; "changelog" is not, and a second one appearing
# anywhere under gplsrc, sdsys or gplbld must still be watched.
$shippedButExempt = @('sdsys\changelog')

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
    # 04 Sep 26 - IT NOW ASKS Test-IsSdSource RATHER THAN RE-STATING IT, AND
    # THE RE-STATEMENT HAD ALREADY DRIFTED.  PRE_RELEASE_FIXES 161.
    #
    # The three path exclusions above were written here by hand AND in
    # stale-binaries.ps1, which is "two files describe one fact and are kept in
    # step by hand" - the shape three of this tree's free guards exist to
    # catch, in the very file that was extracted to end it.  They agreed on the
    # three paths and DISAGREED ON BUILD PRODUCTS: A2 has excluded .exe/.dll/
    # .a/.o since 19 Aug 2026, this copy never did.  So "make check" in
    # gplsrc\sdclilib left smoke-test.exe and internal-state-test.exe reported
    # here as SOURCE NEWER THAN THE INSTALL, demanding a cycle for two files
    # that cannot reach an install - gplsrc is not installed at all.  161 made
    # it loud rather than made it true: that directory now produces four DLLs,
    # four import libraries and five test executables instead of four files.
    #
    # THE .md/.txt NUANCE IS KEPT, and it is the reason this is not simply a
    # call.  Test-IsSdSource excludes documentation outright; here a document
    # is watched again the moment stage.py or sd.iss names it, because a false
    # "current" costs an investigation while a false "stale" costs one install.
    $newer += Get-ChildItem $t -Recurse -File -ErrorAction SilentlyContinue |
              Where-Object { ( (Test-IsSdSource $_.FullName $_.Name) -or
                               ($_.Extension -in '.md', '.txt' -and (& $shipsAs $_.Name)) ) -and
                             $excluded -notcontains $_.Name -and
                             $_.LastWriteTime -gt $installed }
}

# Partitioned AFTER the filter rather than folded into it, so the exemption is
# one readable step and the conditions above stay as they were.
$exemptNewer = @($newer | Where-Object { $shippedButExempt -contains $_.FullName.Substring($sd64.Length + 1) })
$newer       = @($newer | Where-Object { $shippedButExempt -notcontains $_.FullName.Substring($sd64.Length + 1) })
foreach ($e in $exemptNewer) {
    Write-Output ("  EXEMPT: {0} is newer than the install ({1}) - the installed tree carries an older copy" -f
        $e.FullName.Substring($sd64.Length + 1), $e.LastWriteTime.ToString('dd MMM HH:mm:ss'))
}

# --- B2. A RENAME MOVES NO TIMESTAMP, so section B cannot see one.
#
# 22 Aug 26 - FOUND BY DOING IT.  sdsys\accounts\SDSYS was renamed to lower case
# with "git mv", which PRESERVES mtime, so the file was not newer than the
# install and NOTHING HERE RAISED A WORD.  Four other files in that commit forced
# the cycle; had the rename been the only change, it would have shipped untested
# and this script would have said the tree matched source.
#
# A CASE-ONLY RENAME IS THE HARDER HALF, and it is the one that happened.
# Windows compares names case-insensitively, so "SDSYS" and "sdsys" look like the
# same file to any ordinary test - Test-Path, -eq, a hashtable lookup.  Only an
# ORDINAL comparison of the two spellings sees it, which is what -cne does below.
#
# IT COMPARES THE SHIPPED TREE ONLY.  sdsys\ is what stage.py copies into
# ProgramData, so a source path there should have an installed counterpart with
# the SAME SPELLING.  gplsrc is compiled rather than copied and gplbld drives the
# install, so neither has a path-for-path image to compare against.
#
# THE EXCLUSIONS ARE MEASURED, NOT GUESSED.  Comparing the two trees on a
# known-good install gave exactly SEVEN source paths with no counterpart, all of
# them a bare README that keeps an otherwise-empty build-output directory in git
# - $hold, cat, pcode.out, bp.out, prt, gcat, gpl.bp.out.  Nothing else differs,
# so both checks are silent on a current tree and the bias in this file's header
# is kept: a false stale costs one install, a false current costs an
# investigation.
#
# AND IT MUST NOT REPORT CLEAN WHEN IT CHECKED NOTHING.  The first version built
# the installed path as "Join-Path $instTree 'sdsys'" - but $instTree IS ALREADY
# ...\ProgramData\SD\sdsys, so it looked for sdsys\sdsys, found nothing, skipped
# the whole comparison and printed "no source file is renamed" anyway.  It sailed
# past the very rename it had just been written for.  A guard that cannot run has
# to SAY SO; silence here is a false current, which this file's header prices at
# an investigation.
$renamed = @()
$checkedNames = $false
# 25 Aug 26 - THE RETIRED NAMES, ASKED OF stage.py RATHER THAN LISTED HERE.
#
# THE WALK BELOW REPORTS ANY SOURCE FILE UNDER sdsys THAT IS NOT INSTALLED
# UNDER sdsys, to catch a rename.  A RETIRED name breaks that assumption: it is
# still in source and is deliberately NOT in the data tree any more.
#
# IT COST A CYCLE AND A VERIFY RUN, 25 Aug 2026.  changelog moved to {app} on
# 25 Aug - the data tree never overwrote it, so a user's changelog was frozen
# at their install date.  The first cycle after that move installed perfectly
# and then reported "sdsys\changelog is not in the install at all", the whole
# tree STALE, and VerifyInstall1 refused at its first step.  The install was
# right; this check was wrong.
#
# READ FROM stage.py FOR THE REASON --list-mirrors IS: a copy of the list here
# is a second list to keep true, and the thing it would go stale about is
# exactly what this check then mis-reports.
# HOISTED HERE, above BOTH readers.  The mirrors block below used to define
# these and it runs later in the file, so leaving them there would have left
# $stagePy empty at this point - the retired list would have come back empty
# and this fix would have done nothing, silently.
$stagePy = Join-Path $PSScriptRoot 'stage.py'
$python  = Get-Command python -ErrorAction SilentlyContinue

$retired    = @()
$retiredErr = ''
if (-not (Test-Path $stagePy)) {
    $retiredErr = "$stagePy is not there"
} elseif (-not $python) {
    $retiredErr = 'python is not on PATH, so stage.py cannot be asked'
} else {
    $retiredRaw = & $python.Source $stagePy --list-retired 2>&1
    if ($LASTEXITCODE -ne 0) {
        $retiredErr = "stage.py --list-retired exited $LASTEXITCODE"
    } else {
        $retired = @($retiredRaw | ForEach-Object { "$_".Trim() } |
                     Where-Object { $_ -match '^[A-Za-z0-9._$-]+$' })
    }
}

# THE FAILURE DIRECTION IS SAFE AND IS STILL SAID OUT LOUD.  An empty or
# unreadable list leaves the walk exactly as strict as it was before today, so
# it can only produce the FALSE STALE above - loud and wrong - never a silent
# pass.  It is reported rather than swallowed so nobody debugs the symptom.
if ($retiredErr) {
    Note ("  could not read the retired list ({0}) - a name retired from the data tree will report STALE" -f $retiredErr)
} elseif ($retired.Count -gt 0) {
    Note ("  {0} retired name(s) excluded from the rename walk: {1}" -f $retired.Count, ($retired -join ' '))
}

$srcSys  = Join-Path $sd64 'sdsys'
$instSys = $instTree
if ((Test-Path $srcSys) -and (Test-Path $instSys)) {
    $checkedNames = $true
    $instByLower = @{}
    Get-ChildItem $instSys -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $rel = $_.FullName.Substring($instSys.Length + 1)
        $instByLower[$rel.ToLowerInvariant()] = $rel
    }
    Get-ChildItem $srcSys -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and $_.Name -ne 'README' } |
        ForEach-Object {
            $rel = $_.FullName.Substring($srcSys.Length + 1)
            $key = $rel.ToLowerInvariant()

            # 25 Aug 26 - SKIP THE RETIRED NAMES.  Matched on the FIRST PATH
            # SEGMENT so a retired directory covers everything under it, and a
            # retired file matches itself.  changelog is the only one today.
            $seg = $rel.Split([char]'\')[0]
            if ($retired -contains $seg) { return }
            if ($instByLower.ContainsKey($key)) {
                # -cne is the whole point: -ne would call these equal.
                if ($instByLower[$key] -cne $rel) {
                    $renamed += ("sdsys\{0}  is installed as  sdsys\{1}" -f $rel, $instByLower[$key])
                }
            } else {
                $renamed += ("sdsys\{0}  is not in the install at all" -f $rel)
            }
        }
}

if ($renamed.Count -gt 0) {
    Bad ("{0} source file(s) are named differently in the install:" -f $renamed.Count)
    $renamed | Select-Object -First 10 | ForEach-Object { Write-Output ("       " + $_) }
    if ($renamed.Count -gt 10) { Write-Output ("       ... and {0} more" -f ($renamed.Count - 10)) }
    Write-Output '       (a rename keeps its timestamp, so the check above cannot see one)'
    $stale = $true
} elseif (-not $checkedNames) {
    Bad ("could not compare source and installed file NAMES - {0} or {1} is not there." -f $srcSys, $instSys)
    $stale = $true
} else {
    Note '  no source file is renamed relative to the install'
}

# --- B3. A DELETION MOVES NOTHING AT ALL, so neither B nor B2 can see one.
#
# 24 Aug 26 - FOUND WHILE REMOVING MODIFY.  Three source files were deleted and
# this script reported "no source file is renamed relative to the install" and
# named only the one file that had been EDITED.  The install still held
# GPL.BP/MODIFY, voc_template/modify and newvoc/modify and nothing said so.
#
# THE CAUSE IS THAT EVERYTHING ABOVE IS ONE-DIRECTIONAL.  B and B2 walk SOURCE
# and ask "is this in the install".  A file the install has and source no
# longer does is invisible to both, so a commit that ONLY deletes reports the
# tree current.  It had already happened once before that, with GPL.BP/OPGEN:
# what made that tree stale was an edit in the same commit, not the delete.
#
# ***WHY IT SAT OPEN FOR A YEAR OF SESSIONS: THE OBVIOUS FIX CRIES WOLF FOR
# EVER.*** Walking the whole install and flagging anything absent from source
# flags gcat, gpl.bp.out, voc, errlog, $ipc\%0, $hold, every account and the
# entire runtime - it would report stale on every run on every machine.  This
# file's header prices a false stale at one install, and that price only holds
# while a stale verdict still means something.
#
# SO IT ASKS stage.py WHICH DIRECTORIES ARE A VERBATIM COPY OF SOURCE and looks
# only inside those.  stage.py is already the authority on what belongs in an
# install, and SDSYS_MIRROR carries the measurement that justifies each name.
# accounts is deliberately NOT one of them: it ships holding the SDSYS record
# and then accumulates every account the user creates.
#
# IT ASKS RATHER THAN KEEPING ITS OWN COPY, and that is the same reasoning as
# $shipsAs above.  A list here would be a second list to keep true, and what it
# would go stale about is which directories this script is allowed to call
# deletions in - so it would fail by going quiet, which is the direction this
# file refuses.
#
# THE COMPARISON IS CASE-INSENSITIVE ON PURPOSE.  B2 owns the case-only rename
# and reports it with -cne; matching ordinally here as well would report one
# rename twice, as a rename AND as a deletion, and the second report would send
# the reader looking for a file that is not missing.
function Find-InstalledDeletions {
    param(
        [Parameter(Mandatory = $true)] [string]   $SourceSys,
        [Parameter(Mandatory = $true)] [string]   $InstallSys,
        [Parameter(Mandatory = $true)] [string[]] $Mirrors
    )

    $found   = @()
    $skipped = @()
    $checked = 0

    foreach ($m in $Mirrors) {
        $src = Join-Path $SourceSys  $m
        $ins = Join-Path $InstallSys $m
        if (-not (Test-Path $src) -or -not (Test-Path $ins)) {
            $skipped += $m
            continue
        }

        $srcNames = @{}
        Get-ChildItem $src -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $srcNames[$_.FullName.Substring($src.Length + 1).ToLowerInvariant()] = $true
            }

        Get-ChildItem $ins -Recurse -File -ErrorAction SilentlyContinue |
            ForEach-Object {
                $checked++
                $rel = $_.FullName.Substring($ins.Length + 1)
                if (-not $srcNames.ContainsKey($rel.ToLowerInvariant())) {
                    $found += ("{0}\{1}" -f $m, $rel)
                }
            }
    }

    # Checked is not a statistic, it is the null-case guard.  Every finding
    # below is of the form "this file is NOT in source", and a run that opened
    # no directory at all produces none of them - so without this the quietest
    # possible failure reads as the cleanest possible pass.
    return [pscustomobject]@{
        Deleted = @($found)
        Skipped = @($skipped)
        Checked = $checked
    }
}

$mirrors   = @()
$mirrorRaw = ''
$mirrorErr = ''
# $stagePy and $python are set above, hoisted 25 Aug 2026 so the retired-name
# reader can use them too.  Not re-assigned here: one definition, two readers.

if (-not (Test-Path $stagePy)) {
    $mirrorErr = "$stagePy is not there"
} elseif (-not $python) {
    # A machine with no python cannot have built or staged this install, so a
    # red verdict here is not a false one.  It is loud either way.
    $mirrorErr = 'python is not on PATH, so stage.py cannot be asked'
} else {
    # --list-mirrors answers before stage.py checks anything about the machine,
    # so it needs no build, no MSYS2 and no particular working directory.
    $mirrorRaw = & $python.Source $stagePy --list-mirrors 2>&1
    $mirrorRc  = $LASTEXITCODE
    if ($mirrorRc -ne 0) {
        $mirrorErr = "stage.py --list-mirrors exited $mirrorRc"
    } else {
        # The pattern drops anything that is not a bare directory name, which
        # is also what keeps a stderr line out of the list when 2>&1 merges one
        # into the stream.
        $mirrors = @($mirrorRaw | ForEach-Object { "$_".Trim() } |
                     Where-Object { $_ -match '^[A-Za-z0-9._$-]+$' })
        if ($mirrors.Count -eq 0) {
            $mirrorErr = 'stage.py --list-mirrors named no directories'
        }
    }
}

if ($mirrorErr -ne '') {
    Bad ("cannot check for DELETED files - {0}." -f $mirrorErr)
    Write-Output '       A deletion-only change would otherwise report the tree current.'
    if ("$mirrorRaw" -ne '') {
        Write-Output ('       stage.py said: ' + (("$mirrorRaw" -split "`n")[0]))
    }
    $stale = $true
} else {
    $del = Find-InstalledDeletions -SourceSys $srcSys -InstallSys $instSys `
                                   -Mirrors $mirrors
    if ($del.Skipped.Count -gt 0) {
        Bad ("{0} mirrored director(ies) are missing from source or the install: {1}" -f
             $del.Skipped.Count, ($del.Skipped -join ', '))
        $stale = $true
    } elseif ($del.Checked -eq 0) {
        Bad ("the deletion check opened {0} director(ies) and found no files at all - it measured nothing" -f
             $mirrors.Count)
        $stale = $true
    } elseif ($del.Deleted.Count -gt 0) {
        Bad ("{0} file(s) are in the install but no longer in source:" -f $del.Deleted.Count)
        $del.Deleted | Select-Object -First 10 | ForEach-Object { Write-Output ("       sdsys\" + $_) }
        if ($del.Deleted.Count -gt 10) { Write-Output ("       ... and {0} more" -f ($del.Deleted.Count - 10)) }
        Write-Output '       (a deletion moves no timestamp, so the checks above cannot see one)'
        $stale = $true
    } else {
        Note ("  no installed file has been deleted from source ({0} files across {1} mirrored directories: {2})" -f
              $del.Checked, $mirrors.Count, ($mirrors -join ' '))
    }
}

# --- B4. THE SAME BLINDNESS ONE DIRECTORY OVER: C:\Program Files\SD.
#
# 25 Aug 26 - B3 above covers the data tree.  {app} has the identical gap and
# it is easy to assume away, because sd.iss's own comment there says everything
# under {app} is "replaced on upgrade and removed on uninstall".  THAT IS RIGHT
# ABOUT OVERWRITING AND ABOUT UNINSTALLING AND WRONG ABOUT A RETIRED FILE:
# Inno's [Files] copies and overwrites but never removes a file that is absent
# from the new version, which is precisely why [InstallDelete] exists.  So a
# script dropped from stage.py stays in C:\Program Files\SD until somebody
# uninstalls SD.
#
# IT ASKS $shipsAs, WHICH IS ALREADY THE RIGHT QUESTION AND ALREADY EXISTS.
# That valve answers "does this name appear, quoted or path-prefixed, in
# stage.py or sd.iss" - which is the definition of shipping used everywhere
# else in this file.  Retiring a script removes its name from stage.py, so the
# same valve that puts a $neverShipped script back under the guard reports the
# leftover here.  No second list, and nothing to keep in step.
#
# WHAT IT DELIBERATELY DOES NOT DO.  It looks at the TOP LEVEL of {app} only.
# usr\bin holds the binaries and the MSYS2 DLL closure, which stage.py COMPUTES
# with objdump rather than naming, so there is no list to compare against and a
# name-based check there would report every DLL as unshipped.
#
# AND ITS ONE FALSE-NEGATIVE IS WORTH KNOWING, in the exact shape it has: the
# valve requires the name to be QUOTED or path-prefixed, so a retired script
# mentioned bare in a comment does NOT read as shipped - that is the case its
# own note describes.  What DOES slip through is a retired name still carried
# in QUOTES, which is how this file's own comments write a file name.  So when
# retiring a script, take its name out of the quotes in stage.py rather than
# leaving 'foo.ps1' in the comment that explains its removal.  The failure is
# one missed leftover, not a false alarm, which is the direction this file
# tolerates.
#
# THE EVIDENCE ITSELF IS CHECKED FIRST.  $shipEvidence is the text of stage.py
# and sd.iss; if it came back empty every file below would look unshipped and
# this section would report all twenty-odd of them.  A check whose reference
# data is missing has to say so rather than produce its loudest possible output.
function Find-UnshippedAppFiles {
    param(
        [Parameter(Mandatory = $true)] [string]      $AppRoot,
        [Parameter(Mandatory = $true)] [scriptblock] $ShipsAs
    )

    $orphans = @()
    $seen    = 0

    # TOP LEVEL ONLY, and -File so that usr\ and etc\ are not descended into.
    # unins000.exe and unins000.dat are Inno's own uninstaller, written by the
    # installer rather than shipped by stage.py, so they are not leftovers; the
    # digits are matched because a repeat install can produce unins001.
    Get-ChildItem $AppRoot -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '^unins\d+\.(exe|dat)$' } |
        ForEach-Object {
            $seen++
            if (-not (& $ShipsAs $_.Name)) { $orphans += $_.Name }
        }

    # Checked, for the same reason Find-InstalledDeletions returns one: the
    # finding is "this file is NOT shipped", so a run that opened nothing
    # produces no findings and reads as the cleanest possible pass.
    return [pscustomobject]@{ Orphans = @($orphans); Checked = $seen }
}

$appRoot  = Split-Path (Split-Path (Split-Path $inst -Parent) -Parent) -Parent
$orphans  = @()
$appSeen  = 0
$appWhy   = ''
if ("$shipEvidence".Length -eq 0) {
    $appWhy = 'stage.py and sd.iss read as empty, so every file there would be reported'
} elseif (-not (Test-Path $appRoot)) {
    $appWhy = "$appRoot is not there"
} else {
    $app     = Find-UnshippedAppFiles -AppRoot $appRoot -ShipsAs $shipsAs
    $orphans = $app.Orphans
    $appSeen = $app.Checked
}

if ($appWhy -ne '') {
    Bad ("cannot check {app} for leftover files - " + $appWhy + '.')
    $stale = $true
} elseif ($appSeen -eq 0) {
    # Same null-case guard as B3.  The finding is "this file is not shipped",
    # so a run that saw no files produces none and would read as clean.
    Bad ("{0} holds no files at all - the leftover check measured nothing." -f $appRoot)
    $stale = $true
} elseif ($orphans.Count -gt 0) {
    Bad ("{0} file(s) in {1} are no longer shipped by stage.py or sd.iss:" -f $orphans.Count, $appRoot)
    $orphans | Select-Object -First 10 | ForEach-Object { Write-Output ("       " + $_) }
    if ($orphans.Count -gt 10) { Write-Output ("       ... and {0} more" -f ($orphans.Count - 10)) }
    Write-Output '       (Inno never removes a file dropped from a new version - add it to'
    Write-Output '        PF_RETIRED in stage.py, which emits an [InstallDelete] for it)'
    $stale = $true
} else {
    Note ("  no leftover files in {0} ({1} checked)" -f $appRoot, $appSeen)
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
    # 18 Sep 26 - WITH THE POLICY SWITCH.  RELEASE_1.1 58 (found while it was
    # refusing 58's own stale tree).  This printed a BARE path, and the owner's
    # shells read ExecutionPolicy "Undefined" in every scope - which on a
    # desktop edition is Restricted - so the command this script hands over
    # answered PSSecurityException in his terminal on 12 Sep 2026 while working
    # in an agent's shell at Process=Bypass.  RELEASE_1.1 11 fixed 175 sites SD
    # PRINTS and 32 more in the docs; this one is in the tooling and was missed,
    # which is CLAUDE.md's "every command you hand over" rule owed by a script
    # rather than by a person.
    Write-Output ("    powershell -ExecutionPolicy Bypass -File " +
                  (Join-Path $PSScriptRoot 'cycle.ps1'))
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
