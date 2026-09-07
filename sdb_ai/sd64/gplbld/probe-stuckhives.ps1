# probe-stuckhives.ps1 - is Win32_UserProfile.Loaded telling the truth?
#
# WHY THIS EXISTS.  PRE_RELEASE 185's fix made clean-test-profiles.ps1 unload
# each stuck hive itself, and on its first elevated run every attempt answered
# "ERROR: Access is denied" - 40 of 40.  An unelevated look then found the 40
# profiles all marked Loaded=True by WMI while HKEY_USERS held only 4 subkeys,
# none of them theirs.  If that is real, the sweep has been calling every test
# profile "stuck" on a property that is stale, and reg was denied because there
# was no hive at that path to unload.
#
# THE MEASUREMENT CANNOT BE TAKEN UNELEVATED AND THAT IS THE WHOLE POINT.  An
# ordinary token may not enumerate another user's loaded hive, so an unelevated
# count of HKEY_USERS proves nothing either way - which is exactly the kind of
# probe that measured itself twice on 6 Sep 2026.  Run this ELEVATED.
#
# IT PRINTS BOTH LISTS AND THE COMPARISON, and it refuses the null case: no
# matching profiles at all means nothing was measured, and it says so.

$ErrorActionPreference = 'Continue'

$elevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Output ("probe-stuckhives: elevated = " + $elevated)
if (-not $elevated) {
    Write-Output '  REFUSING: unelevated, this cannot see another account''s loaded hive and'
    Write-Output '  a count taken here would look like an answer.  Run it elevated.'
    exit 2
}

Write-Output ("probe-stuckhives: whoami   = " + [Security.Principal.WindowsIdentity]::GetCurrent().Name)
Write-Output ''

# --- what WMI claims -------------------------------------------------------
$prof = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
          Where-Object { (Split-Path $_.LocalPath -Leaf) -match '^sd' })
Write-Output ("Win32_UserProfile rows whose directory starts 'sd': " + $prof.Count)
if ($prof.Count -eq 0) {
    Write-Output '  REFUSING: no test profiles found, so nothing could be compared.'
    exit 2
}
$claimLoaded = @($prof | Where-Object { $_.Loaded })
Write-Output ("  of those, WMI says Loaded=True: " + $claimLoaded.Count)

# --- what the registry actually holds --------------------------------------
$hku = @(Get-ChildItem 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
         ForEach-Object { $_.PSChildName })
Write-Output ("HKEY_USERS subkeys visible to THIS token: " + $hku.Count)
foreach ($k in $hku) { Write-Output ("    " + $k) }
Write-Output ''

# --- the comparison, per profile -------------------------------------------
$claimedAndPresent = 0
$claimedAndAbsent  = 0
foreach ($p in $claimLoaded) {
    $inHku = $hku -contains $p.SID
    if ($inHku) { $claimedAndPresent++ } else { $claimedAndAbsent++ }
}
Write-Output 'PER-PROFILE COMPARISON (WMI Loaded=True only):'
Write-Output ("  hive present in HKEY_USERS : " + $claimedAndPresent)
Write-Output ("  hive NOT in HKEY_USERS     : " + $claimedAndAbsent)
Write-Output ''

# --- and what reg itself says about one of them -----------------------------
# The error text matters: "unable to find the specified registry key" and
# "Access is denied" mean different things, and the fix differs.
$one = @($claimLoaded | Select-Object -First 1)
if ($one.Count -eq 1) {
    $sid = $one[0].SID
    $name = Split-Path $one[0].LocalPath -Leaf
    Write-Output ("reg query on the first one (" + $name + "):")
    $q = & reg.exe query ("HKU\" + $sid) 2>&1
    foreach ($l in @($q | Select-Object -First 4)) { Write-Output ("    " + $l) }
    Write-Output ("  reg query exit code: " + $LASTEXITCODE)
    Write-Output ("reg unload on the same one:")
    $u = & reg.exe unload ("HKU\" + $sid) 2>&1
    foreach ($l in @($u | Select-Object -First 4)) { Write-Output ("    " + $l) }
    Write-Output ("  reg unload exit code: " + $LASTEXITCODE)
}

Write-Output ''
Write-Output 'HOW TO READ THIS:'
Write-Output '  claimed-loaded but NOT in HKEY_USERS, and reg query cannot find the key'
Write-Output '    -> WMI Loaded is stale.  clean-test-profiles must not classify on it;'
Write-Output '       these profiles are removable and the sweep has been skipping them'
Write-Output '       for a reason that is not true.'
Write-Output '  claimed-loaded AND in HKEY_USERS, and reg unload says Access is denied'
Write-Output '    -> the hives are real and something holds a handle into them.  Only a'
Write-Output '       restart clears that, and the unload attempt should say so rather'
Write-Output '       than implying elevation was the missing thing.'
