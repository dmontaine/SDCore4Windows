# secure-account-dirs.ps1 - the ACL on each account's OWN directory
#
#   powershell -File secure-account-dirs.ps1 -Root "C:\ProgramData\SD\user_accounts"
#   powershell -File secure-account-dirs.ps1 -Root "..." -Account sdacct1
#   powershell -File secure-account-dirs.ps1 -Root "..." -WhatIf
#
# Exit 0 every directory stamped, 1 at least one failed, 2 it could not run.
#
# PROJECT_STATUS.md section 8, "the B work".  This is the RE-APPLY half;
# secure-accounts.ps1 does the container the directories sit in, and
# CREATE.ACCOUNT stamps a new account at the moment it makes one.
#
# WHY A RE-APPLY STEP EXISTS AT ALL.  Every other ACL step in this installer
# names ONE fixed path.  Accounts are not fixed - there are as many as the site
# has made - so a create-time write alone would leave every account that existed
# before this shipped with the old inherited ACL, for ever.  The installer runs
# this unconditionally, so an upgrade fixes the accounts already on disk.
#
# WHAT IT CLOSES, measured on the 16:54:55 install before the change: from an
# ordinary session as GITORLI\don, listing another account's directory returned
# 6 entries and writing a file into it was ALLOWED.  The account directories
# inherit sdusers:(I)(OI)(CI)(M) from the data tree, so any SD user could read
# and rewrite any other account's files outside SD.
#
# AND SD ITSELF ALREADY REFUSES THAT, which is what makes this safe rather than
# a policy change.  Measured in the same session: LOGTO into that account
# answered "User not allowed in requested account" and left WHO at DON.
# CPROC's logto.authorised admits an elevated session, a session that has just
# obtained privilege, or a member of the account's ACC$GROUP - and an ordinary
# administrator's session is none of those.  So this brings the FILE layer into
# line with the rule SD has been enforcing since 14 Aug 2026; it does not
# invent a new one.  PROJECT_STATUS.md 5.6 has the model.
#
# THE GROUP IS DERIVED, NOT STORED SEPARATELY.  CREATE.ACCOUNT writes ACC$GROUP
# as sdu_<name> (CREATEA:545) and GRANT maintains its membership (GRANTA:201),
# so there is no new mapping to keep in step - the directory name gives the
# group name.  A directory whose group does not exist is REPORTED AND SKIPPED
# rather than stamped: locking a directory to a group nobody can be in would
# take the account away from its own user, and doing that silently across every
# account on the machine is the one failure this must not have.
#
# WHAT IS DELIBERATELY NOT HERE.  Nothing removes a directory, and nothing is
# stamped that does not look like an account - see Test-LooksLikeAccount.  An
# install that mangled these ACLs would lock every user out of their own data,
# so this errs towards leaving things alone.

param(
    [Parameter(Mandatory = $true)] [string]$Root,
    [string]$Account = '',
    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'

function Say($m) { Write-Output "secure-account-dirs: $m" }

if (-not (Test-Path -LiteralPath $Root)) {
    Say "no $Root - nothing to do"
    exit 0
}

# AN ACCOUNT DIRECTORY HAS A voc IN IT.  Without this the loop would stamp any
# stray directory somebody had left under user_accounts, and a mistake here is
# expensive: the account's own user is the one who loses access.  voc is what
# CREATE.ACCOUNT always makes (CREATEA) and what LOGTO always opens, so its
# presence is the closest thing to a definition of "this is an account".
function Test-LooksLikeAccount([string]$dir) {
    return (Test-Path -LiteralPath (Join-Path $dir 'voc'))
}

$targets = @()
if ($Account -ne '') {
    $p = Join-Path $Root $Account
    if (-not (Test-Path -LiteralPath $p)) { Say "no such account directory: $p"; exit 2 }
    $targets = @(Get-Item -LiteralPath $p)
} else {
    $targets = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue)
}

$done = 0; $skipped = 0; $failed = 0

foreach ($d in $targets) {
    $name  = $d.Name
    $group = 'sdu_' + $name

    if (-not (Test-LooksLikeAccount $d.FullName)) {
        Say "skipped $name - no voc, so it is not an account directory"
        $skipped++
        continue
    }

    # A GROUP THAT DOES NOT EXIST IS A SKIP, NOT A STAMP.  icacls would fail on
    # the name anyway, but the point is the intent: no group means nobody could
    # be granted the directory, and locking it would strand the account.
    #
    # 20 Aug 26 - THE $ErrorActionPreference DANCE IS NOT DECORATION, AND THIS
    # SKIP HAD NEVER WORKED.  Under 'Stop', "2>&1" on a NATIVE command turns
    # each stderr line into a terminating NativeCommandError - so a missing
    # group made net.exe's "System error 1376 has occurred." THROW, and this
    # script died at the exact moment it had detected the case it exists to
    # handle.  The sweep is run by the installer over EVERY account directory
    # (sd.iss SecureAccountDirs), so one account whose sdu_ group had been
    # removed - which is what every verifier's cleanup leaves behind - aborted
    # the run and left every LATER account unstamped, reporting failure.
    #
    # Found by gplbld/verify-accountacl.ps1 on the 15:09:33 install, on its
    # first run, from the deliberate no-group directory in its step 6.
    #
    # THE PROJECT ALREADY KNEW THIS TRAP: verify-credacl.ps1 line 143 carries
    # the same guard with a comment dated 17 Aug 2026, and secure-cred.ps1 has
    # it written up at the top.  This file was written on 19 Aug and repeated
    # it anyway.  Same remedy as verify-credacl's, for consistency: drop to
    # 'Continue' for the call, read $LASTEXITCODE, put it back.
    $prevEap = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $null = & net.exe localgroup $group 2>&1
    $groupExists = ($LASTEXITCODE -eq 0)
    $ErrorActionPreference = $prevEap

    if (-not $groupExists) {
        Say "skipped $name - group $group does not exist"
        $skipped++
        continue
    }

    if ($WhatIf) {
        Say "would stamp $name with $group"
        $done++
        continue
    }

    # /inheritance:r AND EVERY GRANT IN ONE COMMAND - secure-audit.ps1 records
    # why splitting them is dangerous: between the two the directory is open.
    # SIDs for the built-ins because both are renamed on a localised Windows:
    # *S-1-5-18 SYSTEM, *S-1-5-32-544 BUILTIN\Administrators.
    #
    # ADMINISTRATORS IS GRANTED AND THAT IS NOT A HOLE.  In an ordinary session
    # the membership is deny-only, so this ACE does nothing there - which is
    # exactly the behaviour wanted, because SD refuses that session too.  It
    # applies to an ELEVATED one, which is the session 5.6 lets bypass the group
    # check, and to the installer.  Without it an administrator could not
    # recover an account directory at all.
    $out = & icacls.exe $d.FullName /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)(F)' `
        /grant '*S-1-5-32-544:(OI)(CI)(F)' `
        /grant ($group + ':(OI)(CI)(M)') 2>&1

    if ($LASTEXITCODE -ne 0) {
        Say "FAILED $name - icacls exit $LASTEXITCODE"
        Write-Output ($out -join "`n")
        $failed++
    } else {
        Say "stamped $name with $group"
        $done++
    }
}

Say "$done stamped, $skipped skipped, $failed failed"
if ($failed -gt 0) { exit 1 }
exit 0
