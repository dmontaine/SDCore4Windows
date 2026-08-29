# cleanup-devlitter.ps1 - section 7 step 18, the last task of the development
# phase.  ELEVATED.
#
#   powershell -File cleanup-devlitter.ps1 -SelfTest   check the name rules only
#   powershell -File cleanup-devlitter.ps1 -List       show what would go
#   powershell -File cleanup-devlitter.ps1             remove it
#   powershell -File cleanup-devlitter.ps1 -IncludeVM  ...and the spent VM clone
#
# Exit 0 done (or nothing to do), 1 refused or something failed, 2 self-test
# failed or the run measured nothing.
#
# WHY IT EXISTS AND WHY IT IS LAST.  Every cycle and every suite run leaves
# Windows accounts, groups and profiles behind; cycle.ps1 deletes the two SD
# trees and neither of those.  Cleaning before the last test run would simply
# be re-done, so this runs after item 4's guest work and the final suite run.
# Owner, 26 Aug 2026.
#
# THE ORDER IS NOT ARBITRARY - ACCOUNTS BEFORE PROFILES.  clean-test-profiles.ps1
# REFUSES a profile whose SID still has a local account, deliberately, so that
# it only ever touches orphans.  On 26 Aug that left SEVEN profiles unreachable
# behind eight accounts nothing would delete.  Remove the accounts first and
# those profiles become ordinary orphans.
#
# IT DOES NOT DUPLICATE THE PROFILE SWEEP, IT CALLS IT.  clean-test-profiles.ps1
# handles the ProfileList registry entry as well as the directory, which is the
# whole reason it uses Remove-CimInstance; a second implementation here would be
# a second thing to get wrong.
#
# WHAT IT WILL NOT TOUCH, and this is the part to read before running it:
#
#   - C:\Users\dmont\sdout      live build output, cycle.ps1's default -Out.
#   - the SD account register   deliberately left by seven verifiers, and all of
#                               it is one run's residue that the next cycle
#                               deletes with the tree.  Nothing to clean.
#   - ..\winsdclilib, ..\sdclilib32   the real client repositories, one level up
#                               from this tree.  Never in scope.
#   - sdadmins, sdapi, sdssh, sdsshonly, sdusers, sdu_don, sdu_test1
#                               REAL groups.  See the safety note below.

param(
    [switch]$List,
    [switch]$SelfTest,
    [switch]$IncludeVM
)

$ErrorActionPreference = 'Stop'

$Home_       = 'C:\Users\dmont'
$KeepInHome  = @('sdout')
$Sweep       = Join-Path $PSScriptRoot 'clean-test-profiles.ps1'
# 28 Aug 26 - THIS NAME IS SPENT AND IS DELIBERATELY NOT REPOINTED.
#   sshRemoteTest-C1 was deleted by the 7.18 cleanup and no longer exists;
#   VBoxManage lists Beardog, "Windows 11 - Template" and sdStandalone-C1.
#   ***THE ONE THAT DOES EXIST IS NOT A SUBSTITUTE***: PROJECT_STATUS records
#   that sdStandalone-C1 carries the stand-alone install that closed H.5 and is
#   to be deleted BY HAND when nobody needs it, so pointing -IncludeVM at it
#   would turn a documented manual decision into a side effect of a sweep.
#   What was wrong was the REPORTING - the header line said "left alone" about
#   a VM that is not there, which reads as "still present" - so the line below
#   now says whether it exists.
$VMName      = 'sshRemoteTest-C1'
$VBoxManage  = 'C:\Program Files\Oracle\VirtualBox\VBoxManage.exe'

# ---------------------------------------------------------------------------
# THE NAME RULE COMES FROM clean-test-profiles.ps1, IT IS NOT RETYPED HERE.
# Two copies of a pattern is two things to keep in step, and that file's own
# history is a record of exactly that going wrong: its stem list drifted from
# VerifyInstall2.ps1's and reached 3 of 14 stems.  Read it out of the script
# that owns it, and refuse if it cannot be found.
# ---------------------------------------------------------------------------
function Get-LitterPattern {
    if (-not (Test-Path -LiteralPath $Sweep)) {
        throw "cannot find $Sweep - the name rule lives there and is not duplicated here."
    }
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Sweep, [ref]$t, [ref]$e)
    if ($e.Count -ne 0) { throw "$Sweep has $($e.Count) parse error(s); refusing to read a pattern out of a broken script." }
    $want = @('stems', 'bare', 'rx')
    $found = @{}
    foreach ($a in $ast.FindAll({
            param($n) $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                      $n.Left -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true)) {
        $nm = $a.Left.VariablePath.UserPath
        if ($want -contains $nm -and -not $found.ContainsKey($nm)) { $found[$nm] = $a.Extent.Text }
    }
    foreach ($w in $want) { if (-not $found.ContainsKey($w)) { throw "could not find `$$w in $Sweep" } }
    $stems = $null; $bare = $null; $rx = $null
    foreach ($w in $want) { Invoke-Expression $found[$w] }
    if ([string]::IsNullOrWhiteSpace($rx)) { throw "the pattern read out of $Sweep is empty." }
    return $rx
}

# ---------------------------------------------------------------------------
# A GROUP IS ONLY A CANDIDATE IF IT IS sdu_<something that matches>.
#
# THIS IS THE WHOLE SAFETY ARGUMENT AND IT IS WORTH STATING.  The machine
# carries SEVEN real sd-prefixed groups - sdadmins, sdapi, sdssh, sdsshonly,
# sdusers, sdu_don and sdu_test1 - and `don` and `test1` are real accounts.
# Two independent things keep them out:
#
#   1. only names beginning "sdu_" are considered at all, which excludes
#      sdadmins, sdapi, sdssh, sdsshonly and sdusers outright; and
#   2. the REMAINDER after "sdu_" must match the litter pattern, which "don"
#      and "test1" do not - they carry none of the verifier stems.
#
# And since 26 Aug the pattern REQUIRES a run suffix, so even a bare stem like
# "sdapi" or "sdssh" cannot match.  That change was made for this reason.
# ---------------------------------------------------------------------------
function Get-LitterGroups([string]$rx) {
    @(Get-LocalGroup -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -like 'sdu_*' -and ($_.Name -replace '^sdu_', '') -match $rx
    })
}

function Get-LitterUsers([string]$rx) {
    @(Get-LocalUser -ErrorAction SilentlyContinue | Where-Object { $_.Name -match $rx })
}

# 28 Aug 26 - COUNT THE DISK, NOT THE REGISTRY.  PRE_RELEASE 41.
#
# ***THE BEFORE/AFTER PROFILE COUNTS CANNOT SEE THEIR OWN BLIND SPOT.***  Both
# use Get-CimInstance Win32_UserProfile, which enumerates from the ProfileList
# registry key - the SAME list clean-test-profiles.ps1 works from.  A directory
# whose entry has been removed is not a Win32_UserProfile object, so it is
# invisible to the cleaner AND to the counter that is supposed to check the
# cleaner.  The AFTER figure could only ever read zero.
#
# MEASURED 28 Aug 2026: "profiles matching : 7 -> 0" and "every section reached
# zero", with sdapiab49, sdapiidb49 and sdapinb49 still on disk.
#
# THIS IS A SECOND, INDEPENDENT INSTRUMENT and that is the whole point: it
# reaches the thing the first one cannot, so the two disagreeing is the signal.
# It reports; the removal decision is PRE_RELEASE 36's.
# ***REPARSE POINTS ARE EXCLUDED, AND THAT IS A SAFETY GUARD, NOT TIDINESS.***
# Found by the positive control on 28 Aug 2026: run with a pattern of '.', this
# returns "All Users", "Default User", "Default" and "Public" - and "All Users"
# is a JUNCTION TO C:\ProgramData, which is where SD's whole data tree lives.
# The caller prints a "Remove-Item -Recurse -Force" line for whatever comes back
# here.  The stem pattern cannot match those names today, so nothing was ever
# at risk; the guard is here because the suggestion is generated from this list
# and must be safe whatever the pattern later becomes.  A profile directory is
# never a reparse point.
function Get-OrphanDirs([string]$rx) {
    $known = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
               ForEach-Object { $_.LocalPath })
    return @(Get-ChildItem -LiteralPath (Join-Path $env:SystemDrive 'Users') -Directory -Force `
                           -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match $rx -and
                            $known -notcontains $_.FullName -and
                            -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
}

function Get-HomeLitter {
    @(Get-ChildItem -LiteralPath $Home_ -Filter 'sd*' -Force -ErrorAction SilentlyContinue |
      Where-Object { $KeepInHome -notcontains $_.Name })
}

# ===========================================================================
# -SelfTest - the name rules, against fixtures.  Needs no elevation, changes
# nothing.  Run it after ANY change to clean-test-profiles.ps1's stem list.
# ===========================================================================
if ($SelfTest) {
    $rx = Get-LitterPattern
    Write-Output 'cleanup-devlitter -SelfTest'
    Write-Output ("  pattern read from : {0}" -f $Sweep)
    Write-Output ("  pattern           : {0}" -f $rx)
    Write-Output ''
    $bad = 0
    # Groups that MUST be treated as litter.
    foreach ($n in @('sdu_sdapiidb43', 'sdu_sdacctb41', 'sdu_sdtapib431', 'sdu_sdarb43n')) {
        $ok = $n -like 'sdu_*' -and ($n -replace '^sdu_', '') -match $rx
        if (-not $ok) { Write-Output "  FAIL group must be litter but is not: $n"; $bad++ }
    }
    # Groups that MUST SURVIVE.  The first five are real SD groups; the last
    # two belong to real accounts.
    foreach ($n in @('sdadmins', 'sdapi', 'sdssh', 'sdsshonly', 'sdusers',
                     'sdu_don', 'sdu_test1')) {
        $hit = $n -like 'sdu_*' -and ($n -replace '^sdu_', '') -match $rx
        if ($hit) { Write-Output "  FAIL group must SURVIVE but matched: $n"; $bad++ }
    }
    # Users.
    foreach ($n in @('sdapiidb43', 'sdacctb41', 'sdtapib431')) {
        if ($n -notmatch $rx) { Write-Output "  FAIL user must be litter but is not: $n"; $bad++ }
    }
    foreach ($n in @('don', 'test1', 'Administrator', 'Guest', 'DefaultAccount',
                     'WDAGUtilityAccount', 'sdout')) {
        if ($n -match $rx) { Write-Output "  FAIL user must SURVIVE but matched: $n"; $bad++ }
    }
    # THE LAYER THAT IS ACTUALLY LOAD-BEARING, ASSERTED DIRECTLY.
    #
    # The note at the top of this file says two independent things keep the
    # real groups out: the "sdu_" gate, and the pattern.  Both are true, but a
    # control run on 26 Aug 2026 - the gate removed, expecting sdadmins and
    # friends to slip through - came back GREEN.  It is the PATTERN that stops
    # them, and the gate is the redundant layer.
    #
    # "sdapi" and "sdssh" ARE STEMS.  They are excluded only because the
    # pattern requires a run suffix, which it has done since 26 Aug 2026 and
    # did not before.  If anyone ever makes that suffix optional again, those
    # two become matchable and only the sdu_ gate stands between this script
    # and the product's own groups.  So it fails HERE, loudly, instead.
    foreach ($n in @('sdapi', 'sdssh', 'sdacct', 'sdrt', 'sdtapi', 'sdacl',
                     'sdapia', 'sdcatg', 'sddel', 'sdtiert', 'sdapiid',
                     'sdapin', 'sdscram', 'sdar')) {
        if ($n -match $rx) {
            Write-Output "  FAIL a BARE STEM matches the pattern: $n"
            Write-Output '       The run suffix has been made optional again.  Two of these'
            Write-Output '       (sdapi, sdssh) are REAL SD GROUPS.  Fix the pattern in'
            Write-Output '       clean-test-profiles.ps1 before running any cleanup.'
            $bad++
        }
    }

    # The home keep-list.
    if ($KeepInHome -notcontains 'sdout') { Write-Output '  FAIL sdout is not on the keep list'; $bad++ }
    Write-Output ("  {0} case(s) failed" -f $bad)
    Write-Output ''
    if ($bad -gt 0) { Write-Output 'cleanup-devlitter -SelfTest: FAILED'; exit 2 }
    Write-Output 'cleanup-devlitter -SelfTest: PASSED - litter matched, real accounts and groups untouched.'
    exit 0
}

# ===========================================================================
# From here on it reads and changes the machine.
# ===========================================================================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'cleanup-devlitter: this needs an ELEVATED PowerShell.'
    Write-Output '  Removing a local user, a group or a profile all need it.'
    exit 1
}

$rx = Get-LitterPattern

Write-Output '=========================================================='
Write-Output 'cleanup-devlitter - section 7 step 18'
Write-Output '=========================================================='
Write-Output ("  mode            : {0}" -f $(if ($List) { 'LIST ONLY - nothing will be changed' } else { 'REMOVE' }))
Write-Output ("  pattern source  : {0}" -f $Sweep)
Write-Output ("  pattern         : {0}" -f $rx)
Write-Output ("  home directory  : {0}   (keeping: {1})" -f $Home_, ($KeepInHome -join ', '))
# ***SAY WHETHER IT IS THERE, NOT JUST WHAT WOULD HAPPEN TO IT.***  "left
# alone" about a VM that does not exist reads as "still present", which is a
# stale lead in an instrument's own output.
$vmKnown = $false
if (Test-Path -LiteralPath $VBoxManage) {
    try { $vmKnown = ((& $VBoxManage list vms 2>$null) -join "`n") -match [regex]::Escape($VMName) } catch { }
}
$vmState = $(if (-not $vmKnown) { "$VMName is NOT registered - nothing to delete" }
             elseif ($IncludeVM) { "$VMName WILL be deleted" }
             else                { "$VMName left alone (-IncludeVM to delete)" })
Write-Output ("  VM clone        : {0}" -f $vmState)
Write-Output ''

$users  = Get-LitterUsers  $rx
$groups = Get-LitterGroups $rx
$homeItems  = Get-HomeLitter

# THE NULL CASE, OUT LOUD.  Every section below asks what is PRESENT, so a
# machine with nothing on it reports a clean sweep having done nothing at all.
# Say which sections were empty rather than printing a tidy zero.
Write-Output '--- BEFORE ---'
Write-Output ("  local users matching the pattern : {0}   (of {1} local users)" -f $users.Count, @(Get-LocalUser).Count)
Write-Output ("  sdu_ groups matching             : {0}   (of {1} local groups)" -f $groups.Count, @(Get-LocalGroup).Count)
Write-Output ("  sd* items in the home directory  : {0}" -f $homeItems.Count)
$profBefore = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
                Where-Object { (Split-Path $_.LocalPath -Leaf) -match $rx })
Write-Output ("  profiles matching                : {0}   (of {1} profiles)" -f $profBefore.Count, @(Get-CimInstance Win32_UserProfile).Count)
$orphBefore = @(Get-OrphanDirs $rx)
Write-Output ("  C:\Users dirs with NO profile    : {0}   (PRE_RELEASE 41 - the line above cannot see these)" -f $orphBefore.Count)

# 26 Aug 26 - SAY THE REBOOT UP FRONT.  A profile cannot be removed while its
# registry hive is loaded, and after a suite run EVERY hive is still loaded:
# 35 of 35 on 24 Aug, 30 of 30 on 26 Aug.  That is the normal state, not an
# edge case, so section [3] removes nothing and the run exits 1.
#
# It used to be discovered by running the whole thing and reading the sweep's
# output afterwards.  Now it is counted here, BEFORE anything is deleted, so
# -List answers "do I need to reboot first" without touching the machine.
$loadedNow = @($profBefore | Where-Object { $_.Loaded -and -not $_.Special })
if ($loadedNow.Count -gt 0) {
    Write-Output ''
    Write-Output ("  *** {0} of those profiles have a LOADED registry hive." -f $loadedNow.Count)
    Write-Output '  *** A loaded profile CANNOT be removed, so section [3] will skip them'
    Write-Output '  *** and this run will end INCOMPLETE with everything else already done.'
    Write-Output '  ***'
    Write-Output '  *** REBOOT FIRST, then run this again.  A reboot unloads every hive.'
    Write-Output '  *** Sections 1, 2, 4 and 5 are safe to run now and are not undone by'
    Write-Output '  *** rebooting - they simply find nothing the second time.'
}
Write-Output ''

if ($users.Count -eq 0 -and $groups.Count -eq 0 -and $homeItems.Count -eq 0 -and $profBefore.Count -eq 0) {
    Write-Output 'cleanup-devlitter: nothing matched in ANY section.'
    Write-Output '  That is either a clean machine or a pattern that has stopped matching.'
    Write-Output '  Run -SelfTest to tell the two apart before believing this.'
    exit 0
}

foreach ($u in $users)  { Write-Output ("  user   {0}" -f $u.Name) }
foreach ($g in $groups) { Write-Output ("  group  {0}" -f $g.Name) }
foreach ($h in $homeItems)  { Write-Output ("  home   {0}{1}" -f $h.Name, $(if ($h.PSIsContainer) { '\' } else { '' })) }
Write-Output ''

if ($List) {
    Write-Output 'cleanup-devlitter: -List, so nothing was changed.'
    Write-Output '  Profiles are swept by clean-test-profiles.ps1; run it with -List to see those.'
    exit 0
}

$failed = @()

# --- 1. ACCOUNTS FIRST, so the profile sweep sees orphans -------------------
Write-Output '--- [1] Windows users ---'
foreach ($u in $users) {
    try { Remove-LocalUser -Name $u.Name -ErrorAction Stop; Write-Output ("  removed user  {0}" -f $u.Name) }
    catch { $failed += ("user {0} - {1}" -f $u.Name, $_.Exception.Message) }
}
if ($users.Count -eq 0) { Write-Output '  none' }

Write-Output '--- [2] sdu_ groups ---'
foreach ($g in $groups) {
    try { Remove-LocalGroup -Name $g.Name -ErrorAction Stop; Write-Output ("  removed group {0}" -f $g.Name) }
    catch { $failed += ("group {0} - {1}" -f $g.Name, $_.Exception.Message) }
}
if ($groups.Count -eq 0) { Write-Output '  none' }

# --- 3. PROFILES, via the script that owns that job -------------------------
Write-Output '--- [3] profiles (clean-test-profiles.ps1) ---'
& $Sweep
$sweepRc = $LASTEXITCODE
Write-Output ("  clean-test-profiles.ps1 exit {0}" -f $sweepRc)
if ($sweepRc -ne 0) { $failed += "clean-test-profiles.ps1 exited $sweepRc" }

# --- 4. THE HOME DIRECTORY --------------------------------------------------
Write-Output '--- [4] home directory ---'
foreach ($h in $homeItems) {
    try {
        Remove-Item -LiteralPath $h.FullName -Recurse -Force -ErrorAction Stop
        Write-Output ("  removed {0}" -f $h.Name)
    } catch { $failed += ("home {0} - {1}" -f $h.Name, $_.Exception.Message) }
}
if ($homeItems.Count -eq 0) { Write-Output '  none' }

# --- 5. THE SPENT VM CLONE --------------------------------------------------
if ($IncludeVM) {
    Write-Output '--- [5] the VM clone ---'
    if (-not (Test-Path -LiteralPath $VBoxManage)) {
        $failed += "VBoxManage not found at $VBoxManage"
    } else {
        $running = & $VBoxManage list runningvms
        if ($running -match [regex]::Escape($VMName)) {
            $failed += "$VMName is RUNNING - shut it down first; refusing to delete a running VM"
        } else {
            $known = & $VBoxManage list vms
            if ($known -match [regex]::Escape($VMName)) {
                & $VBoxManage unregistervm $VMName --delete | Out-Null
                $still = & $VBoxManage list vms
                if ($still -match [regex]::Escape($VMName)) { $failed += "$VMName is still registered after unregistervm" }
                else { Write-Output ("  removed VM {0}" -f $VMName) }
            } else {
                Write-Output ("  VM {0} is not registered - nothing to do" -f $VMName)
            }
        }
    }
}

# --- AFTER ------------------------------------------------------------------
Write-Output ''
Write-Output '--- AFTER ---'
$uAfter = (Get-LitterUsers  $rx).Count
$gAfter = (Get-LitterGroups $rx).Count
$hAfter = (Get-HomeLitter).Count
$pAfter = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
            Where-Object { (Split-Path $_.LocalPath -Leaf) -match $rx }).Count
Write-Output ("  local users matching : {0} -> {1}" -f $users.Count, $uAfter)
Write-Output ("  sdu_ groups matching : {0} -> {1}" -f $groups.Count, $gAfter)
Write-Output ("  home sd* items       : {0} -> {1}" -f $homeItems.Count, $hAfter)
Write-Output ("  profiles matching    : {0} -> {1}" -f $profBefore.Count, $pAfter)
$orphAfter = @(Get-OrphanDirs $rx)
Write-Output ("  C:\Users, no profile : {0} -> {1}" -f $orphBefore.Count, $orphAfter.Count)
foreach ($d in $orphAfter) { Write-Output ("      still there: " + $d.FullName) }
Write-Output ("  sdout still present  : {0}   (must be True)" -f (Test-Path -LiteralPath (Join-Path $Home_ 'sdout')))
Write-Output ''

if (-not (Test-Path -LiteralPath (Join-Path $Home_ 'sdout'))) {
    Write-Output 'cleanup-devlitter: FAILED - sdout is gone, and it is live build output.'
    exit 1
}
if ($failed.Count -gt 0) {
    foreach ($f in $failed) { Write-Output ("  FAILED: " + $f) }
    Write-Output ("cleanup-devlitter: {0} failure(s)." -f $failed.Count)
    exit 1
}

# 26 Aug 26 - DO NOT SAY "done" OVER A SUMMARY THAT SAYS OTHERWISE.  The first
# real run printed "cleanup-devlitter: done." three lines under
# "profiles matching : 77 -> 30", because clean-test-profiles.ps1 had exited 0
# on a PARTIAL sweep and this trusted the exit code over its own AFTER counts.
# Both ends are fixed; this is the half that does not depend on the other.
#
# THE NUMBERS ARE ALREADY ON SCREEN - so judge on them.  An instrument that
# prints a disagreement and then contradicts it in its closing line is worse
# than one that prints nothing, because the closing line is what gets read.
if ($pAfter -gt 0) {
    Write-Output ("cleanup-devlitter: INCOMPLETE - {0} profile(s) remain." -f $pAfter)
    Write-Output '  Almost always the loaded-hive case: a profile cannot be removed while'
    Write-Output '  its registry hive is loaded, and after a suite run every one of them is.'
    Write-Output '  REBOOT, then run this again - sections 1, 2, 4 and 5 will find nothing'
    Write-Output '  left to do and section 3 will finish the job.'
    exit 1
}
# 28 Aug 26 - AND THE SECOND INSTRUMENT GETS THE SAME AUTHORITY AS THE FIRST.
# PRE_RELEASE 41.  "every section reached zero" was printed on 28 Aug 2026 over
# three directories that were still on disk, because every section was counted
# with the one enumeration that could not see them.  A closing line that can
# only ever agree with the cleaner is not a check.
if ($orphAfter.Count -gt 0) {
    Write-Output ("cleanup-devlitter: INCOMPLETE - {0} director(ies) in C:\Users match the" -f $orphAfter.Count)
    Write-Output '  pattern and have NO ProfileList entry, so nothing that enumerates profiles'
    Write-Output '  can remove them - this tool included.  They are named above.'
    Write-Output '  Remove by hand when nothing needs them, elevated:'
    Write-Output ('    Remove-Item -LiteralPath "' + $orphAfter[0].FullName + '" -Recurse -Force')
    Write-Output '  A reboot does NOT clear these: it unloads hives, and these have no entry'
    Write-Output '  to unload.  PRE_RELEASE 36 is where the lifecycle is being ruled on.'
    exit 1
}
Write-Output 'cleanup-devlitter: done - every section reached zero.'
exit 0
