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
                  'verify-lcnames.ps1', 'VerifyInstall2.ps1',
                  # 29 Aug 26 - verify-sdsysgate.ps1, PRE_RELEASE 62's verifier.
                  # Listed in the commit that creates it, under step 7's rule
                  # and the trap directly above: a gplbld script not on this
                  # list makes the tree report STALE merely because it exists,
                  # and then every verifier that calls this script refuses.
                  # Session 79 paid for that with three scripts at once.
                  'verify-sdsysgate.ps1',
                  # 31 Aug 26 - verify-logtoaccess.ps1, PRE_RELEASE 91's
                  # verifier.  Listed in the commit that creates it, for the
                  # reason the entry directly above spells out: a gplbld script
                  # not on this list makes the tree report STALE merely because
                  # it exists, and then every verifier - this one included -
                  # refuses.  Session 79 paid for that with three at once.
                  'verify-logtoaccess.ps1',
                  'verify-keys.ps1', 'probe-keys.ps1',
                  # 24 Aug 26 - probe-syswrites.ps1, section 7 step 15's
                  # measurement: which of the eight remaining sdusers:(M)
                  # targets an ORDINARY session actually writes.  Listed in
                  # the commit that created it, under step 7's rule - a
                  # script not on this list makes the tree report stale
                  # because it exists, and then every verifier refuses.
                  'probe-syswrites.ps1',
                  # 24 Aug 26 - probe-sshfirewall.ps1, section 7 step 3's
                  # measurement: whether the installer actually scopes who may
                  # reach ssh.  It can only be run on a machine that had NO
                  # OpenSSH server, because ApplySshFirewall exits early unless
                  # SshWasAbsent - which is why the defect it found sat unseen
                  # for eight days.  Listed in the commit that created it, per
                  # step 7's rule.
                  'probe-sshfirewall.ps1',
                  # 25 Aug 26 - probe-sshpreflight.ps1, the both-polarities
                  # test for ssh-preflight.ps1.  It edits sshd_config and
                  # registers a bogus service before putting them back, so it
                  # runs on a throwaway guest and must never reach a user's
                  # machine.  ssh-preflight.ps1 ITSELF ships and is NOT on this
                  # list - stage.py:598 records why.
                  'probe-sshpreflight.ps1',
                  'verify-scramlogin.ps1',
                  # 21 Aug 26 - verify-apiname.ps1, added with the section 2
                  # !valid_os_name measurement.  Listed in the same commit that
                  # created it, which is section 7 step 7's rule: a verifier not
                  # on this list reports the tree stale because it exists, and
                  # then refuses to run on the strength of its own newness.
                  'verify-apiname.ps1',
                  # 22 Aug 26 - verify-parsertokens.ps1, listed in the commit
                  # that created it under section 7 step 7's rule.
                  'verify-parsertokens.ps1',
                  # 30 Aug 26 - suite-only.ps1 and its unit test, the -Only step
                  # filter both runners dot-source.  Owner's ruling, 30 Aug 2026,
                  # dropping the full suite to milestones.  Listed in the commit
                  # that created them, per section 7 step 7's rule - and THIS
                  # LIST IS WHY THAT RULE EXISTS: both files were written, both
                  # were correct, and assert-current went RED purely because
                  # they were new, demanding a twenty-minute cycle that would
                  # have changed nothing.  Neither ships: suite-only.ps1 is dev
                  # tooling dot-sourced by VerifyInstall1/2, which are on this
                  # list themselves, and a test-*-units.ps1 has never shipped.
                  'suite-only.ps1',
                  'test-suiteonly-units.ps1',
                  # 30 Aug 26 - reword-yn-prompts.ps1, the one-shot byte-level
                  # rewording that closed PRE_RELEASE_FIXES 79's wording half.
                  # It is kept rather than deleted because it records exactly
                  # which ten messages moved and how each was checked, and it
                  # re-runs clean (every edit asserts its old text appears
                  # exactly once, so a second run refuses rather than
                  # double-applying).  It edits the SOURCE tree and must never
                  # ship - listed in the commit that created it, and this is the
                  # second time in one session that rule has paid for itself.
                  'reword-yn-prompts.ps1',
                  # 30 Aug 26 - verify-standalone.ps1 IS DELETED, and its entry
                  # with it.  PRE_RELEASE_FIXES 75 removed the stand-alone mode,
                  # so every check in it asked about a system that can no longer
                  # be installed.  A name left here would have been harmless and
                  # wrong: this list is what stops a NEW script failing the
                  # freshness check, and a name in it that matches no file is a
                  # claim nobody can check.
                  # 25 Aug 26 - verify-upgrade.ps1, START HERE item 3's
                  # measurement: whether an install OVER an existing one really
                  # replaces the shipped subset and preserves the rest.  Listed
                  # here proactively rather than after it broke something -
                  # verify-standalone.ps1 had to learn it the other way on its
                  # first run, before it was deleted.
                  #
                  # IT DOES NOT CALL assert-current, so unlike its neighbours it
                  # could not block ITSELF - it would make every OTHER verifier
                  # refuse instead, which is the worse failure because the cause
                  # is a file none of them mention.  It cannot call it: an
                  # upgrade test needs the install to be the OLD build while
                  # source is the NEW one, so between -Snapshot and -Compare the
                  # tree is EXPECTED to be stale.
                  'verify-upgrade.ps1',
                  # 22 Aug 26 - verify-batchjob.ps1, step 9's guard, same rule.
                  'verify-batchjob.ps1',
                  # 28 Aug 26 - verify-profiledir.ps1, PRE_RELEASE_FIXES.md 36's
                  # last unexercised leg: CREATE.ACCOUNT refusing a name whose
                  # profile directory is still on the disk (10124).  b56 and b57
                  # both ran the whole suite and neither log mentions 10124 or
                  # 10125, because every other verifier is careful to use a
                  # fresh name - so the one rule that had never fired was the
                  # one nothing could vouch for.  Listed in the commit that
                  # created it, under step 7's rule.
                  'verify-profiledir.ps1',
                  # 28 Aug 26 - test-sysmsg-units.ps1, PRE_RELEASE_FIXES.md 51.
                  # Get-SysMsgPattern has gone blind three times in three ways,
                  # each found by a run rather than a test; this is the test.
                  # No elevation, no run number, no accounts - it reads the
                  # installed messages and lifts the shipped functions out of
                  # the AST.  Listed in the commit that created it, under step
                  # 7's rule.
                  'test-sysmsg-units.ps1',
                  # 28 Aug 26 - test-fixlist-units.ps1, the checker for
                  # PRE_RELEASE_FIXES.md's own index.  Owner's instruction after
                  # a session filed three entries onto numbers the table had
                  # been using for a week, and reported 36 open when 18 were.
                  # Reads files only - no install, no elevation, no run number.
                  # Listed in the commit that created it, under step 7's rule.
                  'test-fixlist-units.ps1',
                  # 29 Aug 26 - the PRE_RELEASE 59 trio: the throwaway
                  # non-administrator account the unelevated half runs as.
                  # sdtestuser.ps1 is DOT-SOURCED and not run, sdtestuser-admin
                  # .ps1 is its elevated half, and test-sdtestuser-units.ps1
                  # needs no install, no elevation, no account and no ssh.
                  # None of the three ships; stage.py and sd.iss name none of
                  # them, which the check below re-derives rather than trusting
                  # this comment.
                  #
                  # ***THEY WERE WRITTEN ON 29 Aug AND NOT LISTED, AND THIS
                  # SCRIPT WAS ALREADY EXITING 1 BECAUSE OF IT.***  Measured,
                  # not predicted: after the 10:35:46 install it named all
                  # three under "STALE: 3 source file(s) are newer than the
                  # install" and refused - so verify-nocase, verify-lcnames and
                  # every other verifier that calls it would have refused too,
                  # on the strength of three files' mtimes.  That is precisely
                  # the trap the entries above were each added for, and it had
                  # already sprung.  The rule is section 7 step 7's: LIST IT IN
                  # THE COMMIT THAT CREATES IT.
                  'sdtestuser.ps1', 'sdtestuser-admin.ps1',
                  'test-sdtestuser-units.ps1',
                  # 29 Aug 26 - clean-deadvoc.ps1, PRE_RELEASE 60's one-shot:
                  # it removes the <ACCT>BP.OUT records verify-catgate left in
                  # SDSYS's VOC, one per suite run since b59.  Listed IN THE
                  # COMMIT THAT CREATES IT, which is the rule the sdtestuser
                  # trio above was added without and paid for - assert-current
                  # was exiting 1 on their mtimes, and every verifier that
                  # calls it refuses on that.
                  'clean-deadvoc.ps1',
                  # 28 Aug 26 - gen_includes.py, found by listing what in this
                  # directory is on NEITHER this list nor stage.py's.  It is not
                  # a fault today only because nobody has edited it since the
                  # install: the moment somebody does, the tree reports STALE
                  # for a build helper that ships nothing, and every verifier
                  # refuses.  That is the trap the entries above were each
                  # added for, sitting unsprung.
                  'gen_includes.py',
                  # 22 Aug 26 - VerifyInstall1.ps1, the second runner,
                  # listed in the commit that created it under the same rule.
                  # It is a RUNNER and not a verifier, so it ships no more than
                  # VerifyInstall2.ps1 two lines above does - both only
                  # invoke things already on this list.
                  'VerifyInstall1.ps1',
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
                  # 23 Aug 26 - probe-console, section 7 step 13 leg 1's
                  # instrument.  Listed IN THE COMMIT THAT CREATES IT, which is
                  # the rule verify-scram.c was added without and paid for two
                  # lines above.  All three parts: the source, the runner, and
                  # the build product, because probe-console.ps1 COMPILES ON
                  # EVERY RUN - so an unlisted .exe would make the tree report
                  # stale the moment anybody used the instrument.
                  'probe-console.c', 'probe-console.ps1', 'probe-console.exe',
                  # 23 Aug 26 - probe-s4u, section 7 step 14 shape (b)'s
                  # instrument.  Same three parts and the same reason as
                  # probe-console directly above: the runner COMPILES ON EVERY
                  # RUN, so an unlisted .exe would report the tree stale the
                  # moment anybody used it.  Listed in the commit that creates
                  # it, which is the rule verify-scram.c was added without.
                  'probe-s4u.c', 'probe-s4u.ps1', 'probe-s4u.exe',
                  # 23 Aug 26 - probe-impersonate, the instrument that decides
                  # section 7 step 14 between shapes (a) and (b): does
                  # ImpersonateLoggedOnUser govern the MSYS2 runtime's open(),
                  # which is how SD opens every data file (dh_file.c:815).
                  # Same three parts and the same reason as probe-s4u above.
                  'probe-impersonate.c', 'probe-impersonate.ps1',
                  'probe-impersonate.exe',
                  # 24 Aug 26 - probe-impfork, which re-asks probe-impersonate's
                  # question in the shape an API session actually has (a
                  # fork()ed and exec()d Cygwin child, sdwind.c:491) and adds
                  # the ownership leg that separates b28's two explanations.
                  # Same three parts and the same reason as probe-impersonate
                  # directly above: the runner COMPILES ON EVERY RUN, so an
                  # unlisted .exe would report the tree stale the moment
                  # anybody used the instrument.
                  'probe-impfork.c', 'probe-impfork.ps1', 'probe-impfork.exe',
                  # 24 Aug 26 - probe-sessionfork.ps1, step 14 (a2).  It asks
                  # whether the API SESSION forks at all, which is the tension
                  # probe-impfork left: fork() is the only thing that drops the
                  # impersonation, and nothing on the login-to-write path looks
                  # like it forks.  Listed in the commit that creates it, under
                  # section 7 step 7's rule.  PowerShell only, so no build
                  # product to list alongside it.
                  'probe-sessionfork.ps1',
                  # 29 Aug 26 - probe-osadmin, START HERE step 1's instrument:
                  # what do IsAdmin() and IsElevated() answer for an UNELEVATED
                  # administrator, which is what PRE_RELEASE 56 clause 2 needs
                  # LOGIN to be able to tell apart.  Same three parts and the
                  # same reason as the probe- entries above: the runner COMPILES
                  # ON EVERY RUN, so an unlisted .exe would report the tree stale
                  # the moment anybody used the instrument.  Listed in the commit
                  # that creates it, under section 7 step 7's rule.
                  'probe-osadmin.c', 'probe-osadmin.ps1', 'probe-osadmin.exe',
                  # 29 Aug 26 - verify-txn.ps1, the regression guard for
                  # PRE_RELEASE 11 / UPSTREAM 17: a nested COMMIT used to
                  # orphan the outer transaction's cache and lose its writes
                  # with no message.  A silent data-loss defect is the kind
                  # that comes back unnoticed, which is why it gets a verifier
                  # rather than a one-off probe.  Listed in the commit that
                  # creates it, under section 7 step 7's rule.
                  'verify-txn.ps1',
                  # 24 Aug 26 - probe-catprivate.ps1, section 7 step 15's
                  # one owed measurement: after the sdusers:(RX) lock on
                  # sdsys\cat, does CATALOG (private) still write the record.
                  # A probe, not a suite verifier - it runs once on the
                  # current install and does not join VerifyInstall*.  Listed
                  # in the commit that creates it, under section 7 step 7's
                  # rule.  PowerShell only, no build product to list.
                  'probe-catprivate.ps1',
                  # 24 Aug 26 - testsdcli.bp, the BASIC source that used to
                  # ship at sdsys/bp/TESTSDCLI.  verify-scramlogin.ps1 drops
                  # it into place at run time and removes it, so it stays
                  # out of every end user's install.  PROJECT_STATUS.md 7
                  # step 3.  Listed in the commit that moves it, under
                  # section 7 step 7's rule.
                  'testsdcli.bp',
                  # 24 Aug 26 - verify-lineendings, section 7 step 16 (a).  It
                  # plants CRLF records from OUTSIDE SD, which is what an
                  # external editor does, and asserts they read back with no
                  # trailing CR - with a LONE CR fixture as the control, since
                  # a fix that stripped every CR would pass the rest and
                  # corrupt data.  Its straddle fixture puts a CRLF exactly on
                  # the 2048-byte SEQ_BUFFER_SIZE boundary, which is the case
                  # no small fixture reaches.  Listed in the commit that
                  # creates it, under section 7 step 7's rule.
                  'verify-lineendings.ps1',
                  # 23 Aug 26 - section 7 step 14's end-to-end check: does an
                  # API session actually run CONFINED to the user, not just
                  # logged in as them.  Listed in the commit that creates it.
                  'verify-apiidentity.ps1',
                  # 23 Aug 26 - section 7 step 15's guard, listed in the commit
                  # that creates it under section 7 step 7's rule.  It CALLS
                  # this script and refuses on a non-zero exit, so an unlisted
                  # verify-pcodeacl.ps1 would report the tree stale because
                  # verify-pcodeacl.ps1 exists, and then refuse to run on the
                  # strength of its own newness - verify-accountacl's trap.
                  #
                  # secure-pcode.ps1 IS DELIBERATELY NOT ON THIS LIST.  It is an
                  # INSTALLER script - stage.py copies it to {app} and sd.iss
                  # runs it - so it SHIPS, and a shipped file must stay watched.
                  'verify-pcodeacl.ps1',
                  # 24 Aug 26 - section 7 step 15's second guard, for the seven
                  # paths the owner ruled read-only on 24 Aug.  Listed in the
                  # commit that creates it, under section 7 step 7's rule, and
                  # it has the self-blocking shape the verify-accountacl.ps1
                  # note below describes: it CALLS this script and refuses on a
                  # non-zero exit, so an unlisted verify-sysdiracl.ps1 would
                  # report the tree stale because verify-sysdiracl.ps1 exists,
                  # and then refuse to run on the strength of its own newness.
                  #
                  # secure-sysdirs.ps1 IS DELIBERATELY NOT ON THIS LIST, for
                  # the reason the note just above gives for secure-pcode.ps1:
                  # it SHIPS.  Listing it would also do nothing - the cross-check
                  # below reinstates anything quoted in stage.py or sd.iss, and
                  # it is quoted in both - so the entry would rot into a
                  # comment that looks like a rule.  THE HANDOFF ASKED FOR BOTH
                  # SCRIPTS HERE and that half of it is wrong; this is the note
                  # rather than the entry.
                  'verify-sysdiracl.ps1',
                  # 24 Aug 26 - unit tests for verify-apiidentity's two
                  # helpers, listed in the commit that creates them.  They
                  # lift the functions out of that script by AST, touch
                  # nothing but %TEMP%, and make no claim about the installed
                  # tree - so they are not verify-* and are in neither
                  # post-cycle runner.  Both cover a bug that was paid for:
                  # section 6's WHO-pattern and icacls-ordering traps.
                  'test-apiidentity-units.ps1',
                  # 24 Aug 26 - test-verdict-units.ps1, the unit test for the
                  # Write-Verdict function added to verify-createaccount.ps1
                  # and verify-sshonly.ps1 the same day.  Same shape and same
                  # reasoning as test-apiidentity-units.ps1 directly above: it
                  # lifts the function out of both scripts BY AST so it cannot
                  # drift from what it tests, touches nothing, and makes no
                  # claim about the installed tree.  Listed in the commit that
                  # creates it, under section 7 step 7's rule.
                  #
                  # IT ALSO ASSERTS THE TWO COPIES ARE IDENTICAL, which is the
                  # part worth keeping: the "if one changes, change both"
                  # comment in those files is a hope, and session 51 paid for
                  # exactly that shape when the tier VOC counts lived in two
                  # files and nothing failed when they disagreed.
                  'test-verdict-units.ps1',
                  # 24 Aug 26 - verify-cmdaudit.ps1, section 7 step 9's guard.
                  # It reads LOGIN's own audit record to prove batch.command was
                  # non-empty for a command line and empty for an interactive
                  # session - the gate's INPUT, which is the half of that step
                  # that can be automated at all.  Listed in the commit that
                  # creates it, under section 7 step 7's rule, and it has the
                  # self-blocking shape: it CALLS this script and refuses on a
                  # non-zero exit, so an unlisted copy would report the tree
                  # stale because it exists and then refuse to run on the
                  # strength of its own newness.
                  'verify-cmdaudit.ps1',
                  # 23 Aug 26 - setup-devbox.ps1 builds a DEVELOPMENT machine
                  # from nothing.  It never ships and never reaches an install
                  # - it runs BEFORE there is a clone, let alone a tree - and
                  # is listed in the commit that creates it, which is the rule
                  # verify-scram.c was added without and paid for above.
                  'setup-devbox.ps1',
                  # 19 Aug 26 - "make check" in gplsrc\sdclilib builds these
                  # two INTO THAT DIRECTORY rather than into localtest\, so
                  # they are the same false stale the localtest\ exclusion was
                  # added for, by a different route: run the client's own
                  # tests and every verify script afterwards refuses, for a
                  # reason that has nothing to do with the installed tree.
                  'smoke-test.exe', 'internal-state-test.exe',
                  # 20 Aug 26 - the MODIFY.PASSWORD trailing-token verifier, added
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
                  # 21 Aug 26 - the remote-route verifier, same reasoning.  It
                  # replaced verify-rdpaccount.ps1, which went with RDPACCOUNT
                  # on 21 Aug 2026.
                  #
                  # sync-route-groups.ps1 IS DELIBERATELY NOT ON THIS LIST.  It
                  # is an INSTALLER script - stage.py copies it to {app} and
                  # sd.iss runs it - so it must be compared like deny-logon.ps1
                  # and allow-ssh-groups.ps1 are.  Listing it here would hide a
                  # stale copy of the one step that decides who may ssh in.
                  'verify-routes.ps1',
                  # 20 Aug 26 - the peer-identification and errlog-trim
                  # verifier, same reasoning.  It calls this script too, so
                  # leaving it out has the self-blocking shape the
                  # verify-accountacl.ps1 note above describes.
                  'verify-peerlog.ps1',
                  # 20 Aug 26 - section 8's API-privilege verifier and the
                  # BASIC probe it copies into a throwaway account.  The .sb is
                  # SOURCE FOR A TEST, not a shipped program: nothing in
                  # stage.py or sd.iss names it, and it is compiled inside the
                  # account the verifier creates and deleted with it.  Its
                  # sibling gplsrc\sdclilib\tests\api_admin_probe.c needs no
                  # line here - Check B already excludes sdclilib\tests\.
                  # 21 Aug 26 - and apiosexecprobe.sb, which is the same
                  # verifier's SECOND probe.  Split out of apiadminprobe.sb
                  # because the os.execute leg ABORTS when it is refused, and
                  # an abort discards the output an API session has captured -
                  # so while they shared a program, every run where the gate
                  # worked threw away the $cred measurement on its way out.
                  'verify-apiadmin.ps1', 'apiadminprobe.sb',
                  'apiosexecprobe.sb',
                  # 30 Aug 26 - capture-state.ps1, PRE_RELEASE 39's instrument.
                  # IT RUNS IN THE GUEST, NOT HERE, reached over the xfer shared
                  # folder, so it is installed nowhere and ships nowhere.  On the
                  # list for the trap this list exists for: a gplbld script that
                  # is not named here is newer than the install the moment it is
                  # written, and assert-current then refuses the tree BECAUSE of
                  # the new file - which is exactly how verify-tiers.ps1 cost a
                  # run on 25 Aug.
                  'capture-state.ps1',
                  # 30 Aug 26 - verify-sdsyswrite.ps1, PRE_RELEASE 73's verifier:
                  # can a session that reached SDSYS by LOGTO from an UNELEVATED
                  # start write $cred and os.users?  Nothing had ever asked, which
                  # is the hole 68 lived in.  Runs from VerifyInstall1, ships
                  # nowhere.
                  'verify-sdsyswrite.ps1',
                  # 21 Aug 26 - housekeeping for the Windows side, which no
                  # cycle touches: the account-creating verifiers leave a
                  # profile behind each run and nothing had ever removed them.
                  # Ships nowhere - it is run by hand, elevated.
                  'clean-test-profiles.ps1',
                  # 26 Aug 26 - cleanup-devlitter.ps1, section 7 step 18's one
                  # command: the leaked Windows users and sdu_ groups, then the
                  # profile sweep above, then the home directory, then the spent
                  # VM clone.  Listed in the commit that created it, per step
                  # 7's rule - a script not on this list makes the tree report
                  # stale because it exists, and then every verifier refuses.
                  #
                  # It reads its name pattern OUT OF clean-test-profiles.ps1
                  # rather than carrying a copy, so the two cannot drift; both
                  # are on this list for the same reason and neither ships.
                  'cleanup-devlitter.ps1',
                  # 26 Aug 26 - mkdoc.py AND mkpdf.ps1 WERE HERE AND ARE GONE
                  # FROM THIS REPOSITORY.  Owner's ruling, 26 Aug 2026,
                  # question 15: the documentation toolchain follows the
                  # documentation into SDCoreWindowsDocs, so the doc repository
                  # is self-contained and can build its own pages on any
                  # machine without a checkout of sd4windows.  They now live at
                  # <docs>/tools/mkdoc.py and <docs>/tools/mkpdf.ps1.
                  #
                  # DO NOT RE-ADD EITHER NAME.  An entry here for a file that
                  # does not exist is not caught by anything - the list is only
                  # filtered against what gplbld actually holds - so a stale
                  # name would sit unnoticed and read as though the script were
                  # still here.  If documentation ever ships from THIS
                  # repository, stage.py names it and the $shipsAs cross-check
                  # below puts it under the guard, which is the correct answer
                  # from that moment.
                  # 21 Aug 26 - DELETE.ACCOUNT, both directions.  It calls this
                  # script and refuses on a non-zero exit, so leaving it out is
                  # the self-blocking shape the verify-accountacl.ps1 note above
                  # describes - and it would arrive on its very first run.
                  'verify-delaccount.ps1',
                  # 21 Aug 26 - phase 4's refusal verifier: the required access
                  # keyword, the mandatory password and its unwind, a GROUP
                  # account, and ADOPT without the one-shot marker.  Same
                  # reasoning again, and the same self-blocking shape - it calls
                  # this script first and refuses on a non-zero exit.
                  'verify-accountrules.ps1',
                  # 22 Aug 26 - check-install's [not yet] verifier, and it
                  # arrived as the self-blocking shape rather than as a warning
                  # about it: written, committed and handed over WITHOUT this
                  # line, so its very first elevated run refused - naming
                  # itself as the newer file.  Note that check-install.ps1 is
                  # NOT on this list and must not be: it ships, and the cross-
                  # check below would put it back under the guard anyway.
                  'verify-notyet.ps1',
                  # 22 Aug 26 - the API-across-a-real-network staging script.
                  # Listed IN THE COMMIT THAT CREATES IT, which is the rule the
                  # entry above learned the hard way: verify-notyet.ps1 went in
                  # without this line and its first elevated run refused, naming
                  # itself as the newer file.  It drives VBoxManage and copies
                  # two build products to a folder outside the tree; stage.py
                  # and sd.iss name neither it nor them.
                  'stage-apiremote.ps1',
                  # 25 Aug 26 - test-deletioncheck-units.ps1, the unit test for
                  # THIS script's Find-InstalledDeletions.  Listed in the
                  # commit that creates it, under section 7 step 7's rule -
                  # and it has the self-blocking shape twice over, because an
                  # unlisted test of assert-current would make assert-current
                  # report the tree stale on account of the test's own newness,
                  # which is what verify-notyet.ps1 paid for.
                  #
                  # IT IS THE ONLY POSITIVE CONTROL THIS CHECK HAS.  On a
                  # healthy tree Find-InstalledDeletions correctly returns
                  # nothing, so a run that had silently stopped working looks
                  # exactly like a run that passed; only a planted deletion in
                  # a fixture tells the two apart.
                  'test-deletioncheck-units.ps1',
                  # 25 Aug 26 - test-upgradeiss-units.py, the unit test for
                  # stage.py's write_upgrade_iss().  Same shape and the same
                  # reasoning as test-apiidentity-units.ps1 above: it IMPORTS
                  # stage.py rather than restating its lists, so it cannot
                  # drift from what it tests, touches nothing but %TEMP%, and
                  # makes no claim about the installed tree.  Listed in the
                  # commit that creates it, under section 7 step 7's rule.
                  #
                  # WHAT IT GUARDS IS WORTH THE LINE: write_upgrade_iss()
                  # decides what an upgrade DELETES from a live database, and
                  # the failure it exists to catch is $cred landing on the
                  # replace list, after which every account is unreachable.
                  'test-upgradeiss-units.py',
                  # 26 Aug 26 - test-edittokens-units.py, the unit test for
                  # gpl.bp/EDIT's mark tokens: @vm <-> "~~" and @sm <-> "~`".
                  # Listed IN THE COMMIT THAT CREATES IT, under section 7 step
                  # 7's rule.  It reads nothing and writes nothing.
                  #
                  # WHY IT EXISTS RATHER THAN A CYCLE FINDING OUT.  The
                  # conversion is two change() calls each way and it LOOKS
                  # obviously correct; it is not.  A literal "~" immediately
                  # before a mark merges with the substitution and comes back
                  # on the other side of it, and no token search would have
                  # caught that.  The test models change() in Python - left to
                  # right, non-overlapping, which is what str.replace does -
                  # and asserts both directions on 14 records.
                  #
                  # IT REFUSES THE NULL CASE: it also asserts that some records
                  # are editable AND some are refused, because a guard that
                  # answered "refused" to everything would otherwise pass a
                  # table of nothing but negatives.
                  'test-edittokens-units.py',
                  # 26 Aug 26 - mkbasicsyntax.py and checksyntax.py, the pair
                  # that BUILD and VALIDATE microcfg/syntax/sdbasic.yaml, the
                  # SD BASIC highlighting the MICRO verb uses.  Listed in the
                  # commit that creates them, under section 7 step 7's rule.
                  #
                  # ***THE YAML THEY PRODUCE IS NOT ON THIS LIST AND MUST NOT
                  # BE.*** It SHIPS - stage.py copies gplbld/microcfg to
                  # ProgramFiles\micro - so assert-current watches it like any
                  # other shipped file.  These two are the build tools, they
                  # are named by nothing in stage.py or sd.iss, and they run
                  # by hand when BCOMP's tables change.
                  #
                  # mkbasicsyntax.py READS THE COMPILER rather than carrying a
                  # word list: 218 statements, 37 reserved words and 176
                  # intrinsics come out of BCOMP's own tables, so the
                  # highlighting cannot drift from the language.
                  #
                  # checksyntax.py exists because micro reports a syntax file
                  # it cannot parse by simply not highlighting, which looks
                  # exactly like a file that did not match the filename.  It
                  # catches an illegal YAML escape - "\." is not one, and a
                  # regex written the natural way invalidates the whole FILE -
                  # and a pattern RE2 could not compile.
                  'mkbasicsyntax.py',
                  'checksyntax.py',
                  # 26 Aug 26 - mkvocdoc.py, which builds the two X-type VOC
                  # records CONFIG GPL and CONFIG CONTRIB display, from
                  # sdsys/licence and sdsys/contrib.  Listed in the commit
                  # that creates it, under section 7 step 7's rule.
                  #
                  # THE RECORDS IT WRITES ARE NOT ON THIS LIST AND MUST NOT
                  # BE: they are in sdsys/voc_template, which is mirrored to
                  # the install, so assert-current watches them like any other
                  # shipped record.  This is the generator and ships nowhere.
                  #
                  # ITS --check MODE IS THE POINT.  The text exists twice on
                  # purpose - the file has to keep shipping because SD is
                  # GPL-3 and sdsys/licence is the distribution's only copy of
                  # the licence - so the generator makes the record FROM the
                  # file and --check asserts they still agree.
                  'mkvocdoc.py',
                  # 26 Aug 26 - check-stale-leads.py, which reads
                  # PROJECT_STATUS.md and reports entries whose OPENING status
                  # claim is contradicted later in the same entry.  Listed IN
                  # THE COMMIT THAT CREATES IT, under section 7 step 7's rule.
                  # It reads one markdown file and writes nothing; neither
                  # stage.py nor sd.iss names it.
                  #
                  # WHY IT EXISTS: on 26 Aug 2026 the owner said "i have been
                  # getting a different list of things left to do each time i
                  # ask", and he was right.  FOUR entries that day led with a
                  # superseded "still open" paragraph and carried their own
                  # correction further down - section 4's ssh-options bullet,
                  # step 3's limitssh bullet, step 14 ("WHAT IS STILL A
                  # DECISION" 338 lines above "STEP 14 IS CLOSED"), and item
                  # 5's own heading.  A reader stops at the first status
                  # sentence, so the entry lies to everyone who does not read
                  # all of it.  Three careful reads missed what this found in
                  # one pass, which is the argument for a script over a
                  # resolution to read more carefully.
                  'check-stale-leads.py',
                  # 26 Aug 26 - test-staleleads-units.py, the control test for
                  # the script above.  Listed IN THE COMMIT THAT CREATES IT,
                  # under section 7 step 7's rule.  It copies PROJECT_STATUS.md
                  # to %TEMP%, corrupts the copy seven ways and requires the
                  # checker to fail each time; it writes nothing in the tree.
                  #
                  # IT IS THE ONLY REASON A CLEAN RUN OF THE CHECKER MEANS
                  # ANYTHING.  check-stale-leads.py exits 0 on the real file,
                  # which is indistinguishable from a script that has silently
                  # stopped working - both print a clean run.  Case [0] is a
                  # POSITIVE control: if the unmodified file does not pass,
                  # every injected failure below it proves nothing.
                  'test-staleleads-units.py',
                  # 26 Aug 26 - check-client-sync.py, which compares the API
                  # client across the three trees: gplsrc/sdclilib is the
                  # source, ../winsdclilib is its mirror, ../sdclilib32 builds
                  # from this tree and holds no source.  Listed IN THE COMMIT
                  # THAT CREATES IT, under section 7 step 7's rule.  It reads
                  # those trees and writes nothing.
                  #
                  # IT EXISTS BECAUSE THE ABSENCE OF IT COST TWICE: the 32-bit
                  # client that SHIPPED SENDING PASSWORDS IN CLEAR, built from
                  # a mirror that had not moved since 15 Aug and had no SCRAM
                  # in it; and the SV_EMSG_PAIR transposition that survived ten
                  # days in three repositories at once.  Both were found by a
                  # human running a grep on a hunch, neither by anything that
                  # runs.  --self-test builds broken fixtures and requires a
                  # rejection from each, so a clean run means something.
                  'check-client-sync.py',
                  # 26 Aug 26 - probe-sshremote.ps1, the HOST half of the ssh
                  # scoping test: it dials the GUEST's port 22 across the
                  # bridged segment.  probe-sshfirewall.ps1 is the guest half
                  # and reads the rule.  Listed IN THE COMMIT THAT CREATES IT,
                  # under section 7 step 7's rule.  It runs on the host, opens
                  # outbound TCP and reads the ARP table; it never touches the
                  # installed tree, and stage.py and sd.iss name neither it nor
                  # probe-sshfirewall.ps1.
                  #
                  # WHAT IT CLOSES: every ssh reachability dial in this
                  # project's record goes to LOOPBACK, so "RemoteAddress =
                  # 127.0.0.1" has only ever been READ, never shown to refuse
                  # anybody.  -SelfTest proves the dialer tells connect,
                  # refuse and time-out apart without needing a guest.
                  'probe-sshremote.ps1',
                  # 28 Aug 26 - verify-vocverbs.ps1, verify-acctmsgs.ps1 and
                  # test-vocverbs-units.ps1, the witnesses for the eight
                  # PRE_RELEASE fixes that shipped into the 28 Aug 00:53:34
                  # install and that nothing had run.  Listed IN THE COMMIT
                  # THAT CREATES THEM, under section 7 step 7's rule - a script
                  # not on this list makes the tree report stale because it
                  # EXISTS, and then every verifier refuses on the strength of
                  # its own newness.  verify-standalone.ps1 walked into exactly
                  # that on its first run.
                  #
                  # AND THE TIMING IS THE WHOLE REASON THEY ARE HERE AT ALL:
                  # the eight fixes are installed NOW, so they can be witnessed
                  # without spending a cycle - but only while this script still
                  # answers 0, which it cannot do if these three are watched.
                  # None is named in stage.py or sd.iss; they read the install
                  # and create only fixtures they remove again.
                  'verify-vocverbs.ps1',
                  'verify-acctmsgs.ps1',
                  'test-vocverbs-units.ps1',
                  # 28 Aug 26 - test-acctmsgs-units.ps1, added with the policy
                  # -aware rewrite of entry 22's refusal arm.  Same rule, same
                  # commit.  It reads the password policy and changes nothing.
                  'test-acctmsgs-units.ps1',
                  # 28 Aug 26 - verify-tierchange.ps1, PROJECT_STATUS item 5.5
                  # and the three rows of PRE_RELEASE 19 that verify-tiers
                  # section 6 does not cover.  Same rule, same commit.
                  'verify-tierchange.ps1',
                  # 28 Aug 26 - verify-doors.ps1 and verify-doors-admin.ps1, the
                  # SUSPENDED door pair: PRE_RELEASE 19's last row and 38.  Same
                  # rule, same commit.  They are a PAIR because the two halves
                  # need opposite tokens - the fixture is elevated, the logto
                  # measurement must not be.
                  'verify-doors.ps1',
                  'verify-doors-admin.ps1',
                  # 28 Aug 26 - verify-doors-suite.ps1 was WIRED INTO
                  # VerifyInstall1 on 28 Aug and never added here, so the -Run
                  # b50 run's own assert-current listed it under "newer than
                  # the install".  It is the third member of the same pair and
                  # ships no more than the other two do.  The omission is the
                  # exact trap the entries above describe: an unlisted script
                  # makes the tree report stale merely by existing, and then
                  # every verifier that calls this first refuses.
                  'verify-doors-suite.ps1',
                  # 28 Aug 26 - test-doorsargv-units.ps1, the unit test for the
                  # suite's elevation argument list, after Suspend and Remove
                  # died before their UAC prompt on the b50 run.  Needs no
                  # install, no elevation and no account, so it is the cheap
                  # guard the suite itself cannot be: the suite costs three UAC
                  # prompts and a single-use prefix to find out.
                  'test-doorsargv-units.ps1',
                  # 28 Aug 26 - test-reclaim-units.ps1, the unit test for
                  # reclaim-profiles.ps1's refusal table (PRE_RELEASE_FIXES 36).
                  # Listed in the commit that created it, under step 7's rule.
                  # THE SWEEP ITSELF SHIPS AND IS NOT ON THIS LIST, nor is
                  # secure-reclaim.ps1 - stage.py names both.  Only the test
                  # stays out: it needs no install, no elevation and no store,
                  # which is exactly why it can guard a script whose real path
                  # runs as LocalSystem at boot and cannot be exercised by hand.
                  'test-reclaim-units.ps1',
                  # 28 Aug 26 - test-tiercounts-units.ps1, after -Run b52 step
                  # 19 found verify-tierapi.ps1 claiming ADMINISTRATOR = 417
                  # while verify-tiers.ps1 claimed 416 and the tree said 416.
                  # One fact in two files with nothing comparing them.  It
                  # re-derives all three counts from sdsys/newvoc and checks
                  # both files against the TREE rather than against each other,
                  # because two files agreeing on a wrong number is exactly as
                  # broken as two disagreeing.  No install, no elevation.
                  'test-tiercounts-units.ps1',
                  # 31 Aug 26 - test-stemcoverage-units.ps1, PRE_RELEASE 86's
                  # checker.  ***LISTED AFTER IT SPRANG THE TRAP, NOT BEFORE,
                  # AND THAT IS THE POINT OF WRITING IT DOWN AGAIN.*** It was
                  # created on 31 Aug at 00:14:57 against a 30 Aug 22:42:46
                  # install and not listed, so the very next unelevated run
                  # refused: "STALE: 1 source file(s) are newer than the
                  # install", naming this file, and verify-sdsyswrite exited 2
                  # having measured nothing.  A step that was green in the same
                  # run is what made the tree stale for the step after it.
                  #
                  # THE COST WAS ONE RUN TOKEN, WHICH IS THE CHEAP VERSION -
                  # session 79 paid it with three scripts at once and the
                  # sdtestuser trio paid it again.  The rule those entries state
                  # is section 7 step 7's and it has now been broken four times:
                  # LIST IT IN THE COMMIT THAT CREATES IT.  A gplbld script that
                  # does not ship makes the tree report STALE merely by
                  # existing, and then every verifier that calls this script
                  # refuses - so the failure never looks like a missing list
                  # entry, it looks like the tree needing a cycle.
                  'test-stemcoverage-units.ps1',
                  # 31 Aug 26 - the three that measured PRE_RELEASE 12, 24 and
                  # 87.  LISTED IN THE COMMIT THAT ADDS THEM, which is the rule
                  # the entry above was added for after breaking it.
                  #
                  # THEY ARE PROBES, NOT SUITE STEPS, AND THAT IS DELIBERATE.
                  # Neither is wired into a runner: promoting them costs two
                  # more steps against a full run the owner has asked to keep
                  # short, and that is his call.  They are here so the work is
                  # not lost with the session that wrote it - each is
                  # re-runnable by hand and each closed an entry.
                  #   probe-nolockmsg.ps1  12 and 87.  Unelevated, seconds, no
                  #                        run token.  It is the cheap one.
                  #   probe-tasklock.ps1   24.  Raises one consent of its own
                  #                        for "sd -cleanup".
                  #   check-msglen.py      whether a message fits k_error()'s
                  #                        buffer once sysmsg() has expanded it.
                  'probe-nolockmsg.ps1', 'probe-tasklock.ps1', 'check-msglen.py',
                  # 31 Aug 26 - probe-taskflags, PRE_RELEASE 85 and 67's
                  # instrument.  Listed in the commit that creates it, under
                  # section 7 step 7's rule.  BOTH names are needed: the
                  # freshness scan walks every file in the tree and matches on
                  # NAME, so the .iss would report the tree stale exactly as a
                  # .ps1 would.
                  #
                  # ***IT RETIRES "ONLY A PERSON CAN JUDGE THE TASKS PAGE".***
                  # That sentence is written into 67 and 85 and it cost four
                  # builds and three hand-offs, the last of which reached a
                  # WRONG conclusion.  This drives the checkboxes through
                  # Inno's own click path (TNewCheckListBox.CheckItem) and
                  # reads the states back, unelevated, in about ten seconds,
                  # with no cycle, no install and no run token.  It still does
                  # not judge LAYOUT - wording, order, indentation - so eyes
                  # are retired from the STATE question only.
                  #
                  # It compiles a probe installer with no [Files], no [Run] and
                  # no app dir, which aborts at the tasks page, so it installs
                  # nothing.  Leg 2 writes a previous-selection value under its
                  # OWN throwaway HKCU key and removes it again; SD's key is
                  # read-only throughout.
                  'probe-taskflags.ps1', 'probe-taskflags.iss',
                  # 31 Aug 26 - test-sdpath-units.ps1, the unit test for
                  # sd-path.ps1 (PRE_RELEASE 89).  A test-*-units.ps1 has never
                  # shipped.  ***sd-path.ps1 ITSELF SHIPS AND IS DELIBERATELY
                  # NOT HERE*** - it is in stage.py's list, which records why:
                  # the verb drives it, so it has to be on the user's machine.
                  'test-sdpath-units.ps1')

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
    $newer += Get-ChildItem $t -Recurse -File -ErrorAction SilentlyContinue |
              Where-Object { $_.FullName -notmatch '\\__pycache__\\' -and
                             $_.FullName -notmatch '\\localtest\\' -and
                             $_.FullName -notmatch '\\sdclilib\\tests\\' -and
                             -not ($_.Extension -in '.md', '.txt' -and -not (& $shipsAs $_.Name)) -and
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
