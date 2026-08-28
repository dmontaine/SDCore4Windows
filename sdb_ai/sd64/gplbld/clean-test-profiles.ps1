# clean-test-profiles.ps1 - remove the Windows profiles left behind by the
# verifiers that create accounts.  ELEVATED.
#
#   powershell -File clean-test-profiles.ps1 -SelfTest check the pattern only
#   powershell -File clean-test-profiles.ps1 -List     show what would go
#   powershell -File clean-test-profiles.ps1           remove them
#
# Exit 0 done (or nothing to do), 1 refused or failed.
#
# -SelfTest needs no elevation and touches nothing: it runs the name pattern
# against fixtures and exits.  Run it after ANY change to the stem list.
#
# WHY THIS EXISTS.  A cycle deletes the DATA tree but not the Windows side -
# PROJECT_STATUS.md section 6 - and verify-createaccount.ps1 deliberately leaves
# what it made, because what DELETE.ACCOUNT should remove is still undecided.
# So every run of it leaves an account, a group and a PROFILE, and the profiles
# are the ones nothing has ever cleaned: 26 of them had piled up under C:\Users
# by 21 Aug 2026, dating back to 14 Aug.
#
# IT REMOVES THE PROFILE, NOT THE DIRECTORY, AND THAT IS THE WHOLE POINT.
# Deleting C:\Users\<name> by hand leaves the ProfileList registry entry behind,
# and Windows then honours that entry the next time an account of the same name
# appears - by creating the profile at C:\Users\<name>.<COMPUTERNAME> instead.
# That is exactly where sdacct19.GITORLI, sdacct20.GITORLI, sdacct27.GITORLI and
# sdsshprobe.GITORLI came from: the same test name reused after the directory
# had been removed but the entry had not.  Remove-CimInstance on
# Win32_UserProfile takes both halves, which is why it is used here rather than
# Remove-Item.
#
# THREE SAFETY TESTS, AND THE THIRD IS THE ONE THAT MATTERS.  Special profiles
# (SYSTEM, LocalService, NetworkService) are skipped; loaded profiles are
# skipped, because a loaded profile means somebody is signed in; and any profile
# whose SID STILL HAS A LOCAL ACCOUNT is refused outright.  The third means this
# only ever removes ORPHANS - if a test account still exists, its profile is
# left alone and the account is dealt with first.
#
# THE PREFIX IS NARROW ON PURPOSE.  It matches the names the verifiers actually
# use and not "anything starting with sd": a real account called sdsomething
# would otherwise be inside the blast radius of a cleanup script.

param(
    [switch]$List,
    [switch]$SelfTest
)

$ErrorActionPreference = 'Stop'

# The prefixes the account-creating verifiers use.  Keep in step with them:
# verify-createaccount.ps1 (sdacct), verify-sshonly.ps1 (sdsshprobe),
# verify-tiers.ps1 (sdtiert), verify-tierapi.ps1 (sdtapi),
# verify-accountacl.ps1 (sdacl), verify-routes.ps1 (sdrt),
# verify-apiadmin.ps1 (sdapia), verify-catgate.ps1 (sdcatg),
# verify-delaccount.ps1 (sddel).
# A trailing digit or the ".<COMPUTERNAME>" suffix Windows adds is allowed.
#
# 21 Aug 26 - A TRAILING LETTER IS ALLOWED TOO.  A prefix is a STEM here, not
# the whole name: the scripts that make more than one account per run append a
# letter to tell them apart - verify-routes makes <prefix>s, <prefix>a and
# <prefix>x, and verify-delaccount's subjects are <prefix>s and <prefix>b.
# "sdrt4s" matched nothing, so those names were outside the sweep; sdcatg and
# sdtapi were missing from the list outright.
#
# NO ORPHAN OF THOSE SHAPES WAS FOUND WHEN THIS WAS WIDENED - the machine held
# four profiles, three of them special and the fourth the owner's.  So this
# closes a hole rather than clearing a backlog, and the reason the hole never
# filled is worth knowing: verify-routes signs its accounts in with LogonUser
# and NOTHING ELSE, and LogonUser alone creates no profile.  A profile needs
# LoadUserProfile, an ssh session or userenv!CreateProfile.
#
# IT DOES WIDEN THE BLAST RADIUS BY ONE CHARACTER and that is accepted rather
# than overlooked: the stems stay specific, and the third safety test below - a
# profile whose SID still has a local account is refused outright - is what
# actually keeps this to orphans.
# 24 Aug 26 - sdapiidb added, for verify-apiidentity.ps1.  It had piled up
# TWELVE accounts (b19-b30) before anyone looked, which is exactly the backlog
# this list exists to prevent.
#
# THE STEM IS "sdapiidb" AND NOT "sdapiid", AND THAT IS NOT A TYPO.  The suffix
# class below is [0-9]*[a-z]? - digits THEN an optional letter - while these
# names are a letter THEN digits ("sdapiidb29").  Widening the class to
# [a-z]?[0-9]* would have fixed the match and widened the blast radius of every
# other stem at the same time, which is what the note above warns against.
# Taking the "b" into the stem matches these names and nothing else.
#
# It also does not collide with "sdapia" (verify-apiadmin): that stem needs an
# 'a' where these names have an 'i', so neither can match the other's accounts.
# 24 Aug 26 - AND THE SAME HOLE WAS ALREADY OPEN FOR THE WHOLE b-SERIES.
# Looking for sdapiidb's leftovers turned up 35 test profiles under C:\Users,
# and 29 of them - every sdacctb<n> and sdsshb<n> - failed this regex for the
# identical reason. The "b" runs name themselves <stem>b<number>, so the letter
# comes BEFORE the digits and [0-9]*[a-z]? cannot match them. They have been
# invisible to this sweep since the b-series started.
#
# Fixed the same way, by taking the "b" into the stem rather than loosening the
# suffix class for everything. sdsshb is listed separately from sdsshprobe
# because they are different names, not two spellings of one.
#
# THE BACKLOG ITSELF WAS CLEARED on 24 Aug 2026: all 35 removed, C:\Users back
# to dmont and Public, and no ProfileList entry left behind. It needed a reboot
# first - every one of the 35 hives was still loaded, which is the stuck-hive
# case handled below.
# 26 Aug 26 - THE PER-STEM "b" FIX WAS APPLIED TO THREE STEMS AND MISSED
# ELEVEN, AND THAT IS MEASURED, NOT ARGUED.  Against this machine on 26 Aug the
# old pattern reached 9 of the 30 sd* profile directories and 22 of the 77
# Win32_UserProfile entries.  Composing "<stem>b99" for each of the fourteen
# stems VerifyInstall2.ps1 actually builds, it matched THREE: sdacct, sdssh,
# sdapiid - exactly the three the 24 Aug note b-ified, and nothing since.
#
# SO THE NOTE ABOVE IS OVERRIDDEN, DELIBERATELY, AND HERE IS WHY IT NO LONGER
# HOLDS.  It rejected widening the suffix class because that "would have
# widened the blast radius of every other stem at the same time", and chose to
# take the "b" into the stem instead.  That route needs THIS list and
# VerifyInstall2.ps1's -Run block to be kept in step BY HAND, and they drifted
# the day after it was written: sdar, sdapin, sdapi and sdscram were never here
# at all, and sdtiert, sdtapi, sdacl, sdrt, sdapia, sdcatg and sddel never got
# their "b".  A fix that has to be repeated eleven times is a fix that will be
# missed eleven times.
#
# AND THE REPLACEMENT IS NARROWER THAN WHAT IT REPLACES, NOT WIDER.  The old
# suffix [0-9]*[a-z]? could be EMPTY, so every bare stem matched itself -
# measured on the control, "sdacct", "sdrt" and "sdtapi" all matched with no
# run token at all.  That did no harm while the stem list was what it was.
#
# IT WOULD START DOING HARM WITH THIS LIST, WHICH IS THE REASON THE SUFFIX IS
# NOW REQUIRED RATHER THAN OPTIONAL.  Completing the stems adds "sdapi" and
# "sdssh", and those are the names of REAL SD GROUPS - sdapi, sdssh, sdusers,
# sdadmins and sdsshonly are the product's own.  Left optional, this pattern
# would match two of them exactly.  Nothing here would act on that, because it
# is only ever applied to profile directory NAMES and no profile is called
# that; but the next thing to reuse this regex for a user or group sweep would
# have gone straight at them.  So a run suffix is required, no bare stem
# matches, and the two names that do legitimately appear bare - sdsshprobe and
# sdnotyet - are spelled out as literals instead.
#
# THE SHAPE.  A run token is "<letter><digits>" (b41, b43) and a verifier may
# append its own digit or letter to tell several accounts apart (sdtapib431,
# sdarb43n).  So: an optional single leading letter, then AT LEAST ONE DIGIT,
# then any run of letters and digits.  Requiring the digit is what keeps a
# word-shaped real account out - "sdapiary" and "sdsshonly" both fail on it.
# The letter is not written as a literal "b" on purpose: -Run only has to be
# [a-z0-9]+, so a c-series or an x-series would re-open this exact hole.
#
# -SelfTest below is the part that makes this stay true.  It carries the eleven
# shapes that were missed and the group names that must never match.
$stems = @('sdtiert', 'sdapiid', 'sdscram', 'sdacct', 'sdapia', 'sdapin',
           'sdcatg', 'sdtapi', 'sdacl', 'sddel', 'sdssh', 'sdapi',
           'sdrt', 'sdar')
$bare  = @('sdsshprobe', 'sdnotyet')
$rx = '^((' + ($stems -join '|') + ')[a-z]?[0-9]+[a-z0-9]*|' +
      ($bare -join '|') + ')(\.[A-Za-z0-9-]+)?$'

if ($SelfTest) {
    # THE FIXTURES ARE THE POINT.  Every "must match" below is a name this
    # machine or the suite has really produced; every "must not" is either a
    # real SD group, a real account, or the word-shaped near-miss the narrow
    # stem list exists to keep out.
    $must = @(
        # the three that already worked
        'sdacctb43', 'sdsshb43', 'sdapiidb43',
        # THE ELEVEN THAT DID NOT.  This is the regression list.
        'sdtiertb431', 'sdscramb43', 'sdapiab43', 'sdapinb43', 'sdcatgb43',
        'sdtapib431', 'sdaclb43', 'sddelb43s', 'sdapib43', 'sdrtb43s',
        'sdarb43n',
        # the pre-b-series shapes, which must keep working
        'sdacct14', 'sdrt5s', 'sdacl2', 'sdapia2', 'sddel5', 'sdcatg1',
        # the bare literals
        'sdsshprobe', 'sdnotyet',
        # and the .<COMPUTERNAME> form Windows creates when a stale
        # ProfileList entry survives its directory
        'sdacct19.GITORLI', 'sdsshprobe.GITORLI'
    )
    $mustNot = @(
        # REAL SD GROUPS - the old pattern matched the first two.
        'sdapi', 'sdssh', 'sdusers', 'sdadmins', 'sdsshonly', 'sdu_don',
        # a bare stem is not litter on its own
        'sdacct', 'sdrt', 'sdtapi',
        # real things on this machine
        'dmont', 'Public', 'sdout', 'sdclilib',
        # word-shaped near-misses
        'sdapiary', 'sdrtserver', 'sdaclmanager',
        # the SD system account and the owner's
        'sdsys', 'don'
    )
    $bad = 0
    Write-Output ("clean-test-profiles -SelfTest: pattern under test")
    Write-Output ("  {0}" -f $rx)
    Write-Output ''
    foreach ($n in $must) {
        if ($n -notmatch $rx) { Write-Output ("  FAIL must match but does not : {0}" -f $n); $bad++ }
    }
    foreach ($n in $mustNot) {
        if ($n -match $rx)    { Write-Output ("  FAIL must NOT match but does : {0}" -f $n); $bad++ }
    }
    # THE NULL-CASE GUARD.  A regex that matched nothing at all would pass every
    # "must not" row and fail every "must" row; one that matched EVERYTHING
    # would do the reverse.  Both counts are asserted so neither reads as clean.
    $mHit = @($must    | Where-Object { $_ -match $rx }).Count
    $nHit = @($mustNot | Where-Object { $_ -match $rx }).Count
    Write-Output ("  must-match   : {0} of {1} matched" -f $mHit, $must.Count)
    Write-Output ("  must-not     : {0} of {1} matched (0 is correct)" -f $nHit, $mustNot.Count)
    if ($must.Count -eq 0 -or $mustNot.Count -eq 0) {
        Write-Output '  REFUSED: a fixture list is empty, so this measured nothing.'
        exit 1
    }
    Write-Output ''
    if ($bad -gt 0) {
        Write-Output ("clean-test-profiles -SelfTest: FAILED - {0} case(s)." -f $bad)
        exit 1
    }
    Write-Output ("clean-test-profiles -SelfTest: PASSED - {0} of {0} must-match, {1} of {1} correctly rejected." -f $must.Count, $mustNot.Count)
    exit 0
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'clean-test-profiles: this needs an ELEVATED PowerShell - removing a user profile needs SeRestorePrivilege.'
    exit 1
}

$live = @(Get-LocalUser -ErrorAction SilentlyContinue |
          Select-Object -ExpandProperty SID | ForEach-Object { $_.Value })

$all = @(Get-CimInstance Win32_UserProfile | Where-Object {
    (Split-Path $_.LocalPath -Leaf) -match $rx
})

# 28 Aug 26 - THE DIRECTORY SCAN, BECAUSE THE PROFILE LIST CANNOT SEE ITS OWN
# BLIND SPOT.  PRE_RELEASE 41.
#
# ***$all IS BOTH THE WORK LIST AND THE MEASUREMENT, AND THAT IS THE DEFECT.***
# Get-CimInstance Win32_UserProfile enumerates from the ProfileList registry
# key.  A directory whose entry has been removed is not a Win32_UserProfile
# object at all, so it is invisible TWICE: this sweep cannot clean it, and the
# BEFORE/AFTER block in cleanup-devlitter.ps1 cannot count it.  The AFTER figure
# was never a measurement of the machine - it was a measurement of the same list
# the cleaner had just emptied, and it can only ever read zero.
#
# MEASURED 28 Aug 2026: "profiles matching : 7 -> 0" and "every section reached
# zero", with sdapiab49, sdapiidb49 and sdapinb49 still on disk and their
# Windows accounts already gone.  ***THE NAMES WERE NEVER THE PROBLEM*** - all
# three match $rx, which this script prints at the top of its own run.  Only the
# SOURCE of the list missed them.
#
# ***IT REPORTS AND DOES NOT DELETE.***  Whether these should be removed is a
# separate decision - PRE_RELEASE 36 is where the lifecycle is being ruled on -
# and the instrument rule's demand is narrower than that: what it must not do is
# report zero.  So they are named, with the reason, and they set the exit code,
# because "skipped" is not "done" and this file already says so twice above.
#
# IT RUNS BEFORE THE "nothing to do" RETURN ON PURPOSE.  The measured case had
# $all.Count going to zero with three directories still there; an unreachable
# scan placed after that return would have been skipped in exactly the run that
# needed it.
$profilePaths = @($all | ForEach-Object { $_.LocalPath })
$usersDir     = Join-Path $env:SystemDrive 'Users'
# ***REPARSE POINTS ARE EXCLUDED, AND THAT IS A SAFETY GUARD.***  Found by the
# positive control on 28 Aug 2026: with a permissive pattern this list includes
# "All Users", which is a JUNCTION TO C:\ProgramData - where SD's whole data
# tree lives - and the block below prints a "Remove-Item -Recurse -Force" line
# for whatever is in it.  The stem pattern cannot match that name today, so
# nothing was at risk; the guard is here because the suggestion is generated
# from this list.  A profile directory is never a reparse point.
$unreachable  = @(Get-ChildItem -LiteralPath $usersDir -Directory -Force -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -match $rx -and
                                 $profilePaths -notcontains $_.FullName -and
                                 -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })

if ($unreachable.Count -gt 0) {
    Write-Output ''
    Write-Output ("  {0} UNREACHABLE director(ies): they match the pattern and are on disk," -f $unreachable.Count)
    Write-Output '  but have no ProfileList entry, so nothing that enumerates profiles can'
    Write-Output '  see them - this sweep included.  They are reported, not deleted:'
    foreach ($d in $unreachable) { Write-Output ("    " + $d.FullName) }
    Write-Output '  Remove by hand when nothing needs them, elevated:'
    Write-Output ('    Remove-Item -LiteralPath "' + $unreachable[0].FullName + '" -Recurse -Force')
}

if ($all.Count -eq 0) {
    if ($unreachable.Count -gt 0) {
        Write-Output ''
        Write-Output 'clean-test-profiles: nothing this sweep can reach, but the machine is NOT'
        Write-Output '  clean - see the unreachable directories above.  Exiting non-zero so the'
        Write-Output '  caller does not read "nothing to do" as "nothing left".'
        exit 1
    }
    Write-Output 'clean-test-profiles: nothing to do.'
    exit 0
}

# 24 Aug 26 - THE "loaded" SKIP USED TO ASSERT A CAUSE IT HAD NOT CHECKED.
# It printed "loaded, someone is signed in" for all 35 orphans, about accounts
# that had just been DELETED - nobody was signed in as any of them and nobody
# could be. The Loaded flag was right (all 35 hives really are in HKEY_USERS,
# 76 of them); the EXPLANATION bolted onto it was invented.
#
# A loaded hive whose account no longer exists is a STUCK hive, not a session:
# Windows unloads at logoff, and one that outlives its own account was never
# released - a process holding a handle into it, or a logon killed rather than
# ended. Several sd sessions have been Stop-Process'd to escape hangs.
#
# So the two cases are separated and each says only what it knows. The stuck
# ones also get the remedy, because "skipped" with no way forward is what left
# this sitting for weeks.
$skipSpecial     = @($all | Where-Object { $_.Special })
$skipLoadedLive  = @($all | Where-Object { -not $_.Special -and $_.Loaded -and $live -contains $_.SID })
$skipLoadedStuck = @($all | Where-Object { -not $_.Special -and $_.Loaded -and $live -notcontains $_.SID })
$skipLive        = @($all | Where-Object { -not $_.Special -and -not $_.Loaded -and $live -contains $_.SID })
$targets         = @($all | Where-Object { -not $_.Special -and -not $_.Loaded -and $live -notcontains $_.SID })

foreach ($p in $skipSpecial)    { Write-Output ("  skipped (special): " + $p.LocalPath) }
foreach ($p in $skipLoadedLive) { Write-Output ("  skipped (hive loaded AND the account exists - may be signed in): " + $p.LocalPath) }
foreach ($p in $skipLoadedStuck){ Write-Output ("  skipped (STUCK HIVE - loaded but the account is gone): " + $p.LocalPath) }
foreach ($p in $skipLive)       { Write-Output ("  skipped (the account still exists - remove the account first): " + $p.LocalPath) }

if ($skipLoadedStuck.Count -gt 0) {
    Write-Output ''
    Write-Output ("  {0} STUCK HIVE(S). Their accounts are gone, so nobody is signed in;" -f $skipLoadedStuck.Count)
    Write-Output '  the registry hive was simply never unloaded, and a profile cannot be'
    Write-Output '  removed while it is loaded. Clear them one of two ways:'
    Write-Output '    - reboot, which unloads every hive, then re-run this; or'
    Write-Output '    - unload each one, elevated:  reg unload HKU\<SID>'
    Write-Output '  The SIDs are:'
    foreach ($p in $skipLoadedStuck) { Write-Output ("    {0}   {1}" -f $p.SID, (Split-Path $p.LocalPath -Leaf)) }
}

if ($targets.Count -eq 0) {
    if ($skipLoadedStuck.Count -gt 0) {
        Write-Output ''
        Write-Output 'clean-test-profiles: nothing removable YET - see the stuck hives above.'
        exit 1
    }
    Write-Output 'clean-test-profiles: nothing removable.'
    exit 0
}

if ($List) {
    Write-Output ("clean-test-profiles: {0} profile(s) would be removed:" -f $targets.Count)
    foreach ($p in $targets) { Write-Output ("  " + $p.LocalPath) }
    exit 0
}

$ok = 0
$failed = @()
foreach ($p in $targets) {
    $lp = $p.LocalPath
    try {
        Remove-CimInstance -InputObject $p -ErrorAction Stop
        $ok++
        Write-Output ("  removed: " + $lp)
    } catch {
        $failed += ("{0} - {1}" -f $lp, $_.Exception.Message)
    }
}

Write-Output ("clean-test-profiles: removed {0}, failed {1}" -f $ok, $failed.Count)
foreach ($f in $failed) { Write-Output ("  FAILED: " + $f) }

# A directory left behind after the profile went is reported rather than
# deleted: at that point it is no longer a profile, and something holding a
# file open is the usual reason.  Say so instead of retrying blindly.
foreach ($p in $targets) {
    if (Test-Path -LiteralPath $p.LocalPath) {
        Write-Output ("  note: directory still present after removal: " + $p.LocalPath)
    }
}

# 26 Aug 26 - A PARTIAL SWEEP USED TO REPORT TOTAL SUCCESS, AND IT DID SO ON A
# REAL RUN BEFORE ANYONE NOTICED.
#
# The stuck-hive "exit 1" above lives inside `if ($targets.Count -eq 0)`, so it
# only ever fired when NOTHING was removable.  On 26 Aug 2026 the machine had
# BOTH: 47 stale entries whose directories were long gone, and 30 whose hives
# were still loaded.  It removed the 47, skipped the 30, printed
# "removed 47, failed 0" - which is true - and exited 0.
#
# ITS CALLER THEN BELIEVED THE EXIT CODE.  cleanup-devlitter.ps1 treats a
# non-zero exit here as a failed section; getting 0 it printed "done." over a
# summary that said, three lines above, "profiles matching : 77 -> 30".
#
# SKIPPED IS NOT DONE.  A stuck hive is unfinished work with a known remedy -
# the reboot printed above - so it sets the exit code whether or not anything
# else succeeded.  "failed 0" refers to the removals ATTEMPTED and stays true;
# what was missing was any accounting for the ones never attempted.
if ($failed.Count -gt 0) { exit 1 }
# 28 Aug 26 - AND THE UNREACHABLE ONES COUNT HERE TOO.  PRE_RELEASE 41.  Without
# this a run that removed everything it could see would exit 0 with directories
# still on disk, which is the reported-zero defect in its other form: not a
# wrong count, but a right count of the wrong set.
if ($unreachable.Count -gt 0) {
    Write-Output ''
    Write-Output ("clean-test-profiles: INCOMPLETE - {0} removed, {1} unreachable (no ProfileList entry)." -f
                  $ok, $unreachable.Count)
    Write-Output '  They are listed above.  Exiting non-zero so the caller does not read a'
    Write-Output '  sweep of what it could see as a sweep of the machine.'
    exit 1
}
if ($skipLoadedStuck.Count -gt 0) {
    Write-Output ''
    Write-Output ("clean-test-profiles: INCOMPLETE - {0} removed, {1} still held by a loaded hive." -f $ok, $skipLoadedStuck.Count)
    Write-Output '  Reboot and run this again.  Exiting non-zero so the caller does not'
    Write-Output '  read a partial sweep as a finished one.'
    exit 1
}
exit 0
