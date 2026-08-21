# clean-test-profiles.ps1 - remove the Windows profiles left behind by the
# verifiers that create accounts.  ELEVATED.
#
#   powershell -File clean-test-profiles.ps1 -List     show what would go
#   powershell -File clean-test-profiles.ps1           remove them
#
# Exit 0 done (or nothing to do), 1 refused or failed.
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
    [switch]$List
)

$ErrorActionPreference = 'Stop'

# The prefixes the account-creating verifiers use.  Keep in step with them:
# verify-createaccount.ps1 (sdacct), verify-sshonly.ps1 (sdsshprobe),
# verify-tiers.ps1 (sdtiert), verify-accountacl.ps1 (sdacl),
# verify-routes.ps1 (sdrt), verify-apiadmin.ps1 (sdapia).
# A trailing digit or the ".<COMPUTERNAME>" suffix Windows adds is allowed.
$rx = '^(sdacct|sdsshprobe|sdtiert|sdacl|sdrt|sdapia)[0-9]*(\.[A-Za-z0-9-]+)?$'

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

if ($all.Count -eq 0) { Write-Output 'clean-test-profiles: nothing to do.'; exit 0 }

$skipSpecial = @($all | Where-Object { $_.Special })
$skipLoaded  = @($all | Where-Object { -not $_.Special -and $_.Loaded })
$skipLive    = @($all | Where-Object { -not $_.Special -and -not $_.Loaded -and $live -contains $_.SID })
$targets     = @($all | Where-Object { -not $_.Special -and -not $_.Loaded -and $live -notcontains $_.SID })

foreach ($p in $skipSpecial) { Write-Output ("  skipped (special): " + $p.LocalPath) }
foreach ($p in $skipLoaded)  { Write-Output ("  skipped (loaded, someone is signed in): " + $p.LocalPath) }
foreach ($p in $skipLive)    { Write-Output ("  skipped (the account still exists - remove the account first): " + $p.LocalPath) }

if ($targets.Count -eq 0) { Write-Output 'clean-test-profiles: nothing removable.'; exit 0 }

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

if ($failed.Count -gt 0) { exit 1 }
exit 0
