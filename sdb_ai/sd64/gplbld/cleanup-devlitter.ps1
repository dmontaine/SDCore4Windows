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
Write-Output ("  VM clone        : {0}" -f $(if ($IncludeVM) { "$VMName WILL be deleted" } else { "$VMName left alone (-IncludeVM to delete)" }))
Write-Output ''

$users  = Get-LitterUsers  $rx
$groups = Get-LitterGroups $rx
$home_  = Get-HomeLitter

# THE NULL CASE, OUT LOUD.  Every section below asks what is PRESENT, so a
# machine with nothing on it reports a clean sweep having done nothing at all.
# Say which sections were empty rather than printing a tidy zero.
Write-Output '--- BEFORE ---'
Write-Output ("  local users matching the pattern : {0}   (of {1} local users)" -f $users.Count, @(Get-LocalUser).Count)
Write-Output ("  sdu_ groups matching             : {0}   (of {1} local groups)" -f $groups.Count, @(Get-LocalGroup).Count)
Write-Output ("  sd* items in the home directory  : {0}" -f $home_.Count)
$profBefore = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
                Where-Object { (Split-Path $_.LocalPath -Leaf) -match $rx })
Write-Output ("  profiles matching                : {0}   (of {1} profiles)" -f $profBefore.Count, @(Get-CimInstance Win32_UserProfile).Count)
Write-Output ''

if ($users.Count -eq 0 -and $groups.Count -eq 0 -and $home_.Count -eq 0 -and $profBefore.Count -eq 0) {
    Write-Output 'cleanup-devlitter: nothing matched in ANY section.'
    Write-Output '  That is either a clean machine or a pattern that has stopped matching.'
    Write-Output '  Run -SelfTest to tell the two apart before believing this.'
    exit 0
}

foreach ($u in $users)  { Write-Output ("  user   {0}" -f $u.Name) }
foreach ($g in $groups) { Write-Output ("  group  {0}" -f $g.Name) }
foreach ($h in $home_)  { Write-Output ("  home   {0}{1}" -f $h.Name, $(if ($h.PSIsContainer) { '\' } else { '' })) }
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
foreach ($h in $home_) {
    try {
        Remove-Item -LiteralPath $h.FullName -Recurse -Force -ErrorAction Stop
        Write-Output ("  removed {0}" -f $h.Name)
    } catch { $failed += ("home {0} - {1}" -f $h.Name, $_.Exception.Message) }
}
if ($home_.Count -eq 0) { Write-Output '  none' }

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
Write-Output ("  home sd* items       : {0} -> {1}" -f $home_.Count, $hAfter)
Write-Output ("  profiles matching    : {0} -> {1}" -f $profBefore.Count, $pAfter)
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
Write-Output 'cleanup-devlitter: done.'
exit 0
