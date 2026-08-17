# secure-accounts.ps1 - the containers account directories are created in
#
#   powershell -File secure-accounts.ps1 -Path "C:\ProgramData\SD\user_accounts"
#
# PROJECT_STATUS.md 5.7.  Run by the installer AFTER the icacls that secures the
# data tree, for both user_accounts and group_accounts.  This is HALF of the
# per-account work: it governs the container, and CREATE.ACCOUNT puts the real
# ACL on each account directory at the end of building it.
#
# WHAT THIS IS FOR.  The data tree grants sdusers Modify with (OI)(CI), so every
# account directory inherits it and any SD user can read - and rewrite - any
# other account's files outside SD.  Measured on the installed tree, 16 Aug 2026:
# gcat and GPL.BP.OUT both carry sdusers:(I)(OI)(CI)(M), and account directories
# carry the same.  Owner's decision the same day: build the isolation.
#
# THIS IS THE secure-psdir.ps1 PATTERN, one directory along, and the reasoning
# there applies here almost unchanged.  What differs:
#
#   sdusers gets AD, NOT WD.  Account directories are directories, so adding a
#     subdirectory (AD) is the right to grant; nothing creates a loose FILE in
#     these containers, so WD is withheld.  secure-psdir grants both because
#     !ps_script writes files.
#
#   DC IS WITHHELD, which is the point.  With Modify inherited, one SD user can
#     delete another's whole account directory.  Without DeleteChild on the
#     container, removing an account directory needs rights on the directory
#     ITSELF, which its own ACL decides.
#
#   CREATOR OWNER is (OI)(CI)(IO)(F), inherited by subdirectories as well as
#     files - and that is load-bearing, not symmetry.  CREATEA:328 creates the
#     account directory and then populates VOC, the dictionaries and cat as far
#     as about line 600, all as the invoking user.  With sdusers holding nothing
#     inheritable, CREATOR OWNER is the ONLY thing giving that session rights to
#     its own new directory.  Take it away and account creation fails at the
#     first write.
#
# A CONSEQUENCE TO KNOW ABOUT BEFORE IT IS FOUND AS A BUG.  Once CREATE.ACCOUNT
# replaces the account directory's ACL with sdu_<name>, an administrator who is
# NOT in that group can no longer read or delete it from an ordinary session -
# because sd.exe stays unelevated for life and their Administrators membership
# is deny-only in that token.  DELETE.ACCOUNT therefore has to remove the
# directory through the elevated helper (!ps_script) rather than with SD's own
# file I/O, or be run from an already-elevated window.  That is not fixed here.

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Output "secure-accounts: created $Path"
    } else {
        Write-Output "secure-accounts: $Path already exists"
    }

    # NOTHING IS CLEARED OUT HERE, unlike secure-psdir.  These containers hold
    # the user's accounts; an install that emptied them would destroy the
    # database.  Existing account directories keep whatever ACL they have -
    # there is no migration, and PROJECT_STATUS.md 7 step 3 records that.

    # /inheritance:r and every grant in ONE command - see secure-audit.ps1 for
    # why splitting them is dangerous.  SIDs for the built-ins because all three
    # are renamed on a localised Windows: *S-1-5-18 SYSTEM, *S-1-5-32-544
    # BUILTIN\Administrators, *S-1-3-0 CREATOR OWNER.
    $out = & icacls.exe $Path /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)(F)' `
        /grant '*S-1-5-32-544:(OI)(CI)(F)' `
        /grant '*S-1-3-0:(OI)(CI)(IO)(F)' `
        /grant 'sdusers:(RD,AD,X,RA,S)' 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Output "secure-accounts: icacls failed with $LASTEXITCODE"
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-accounts: container ACL applied to $Path"
    exit 0
}
catch {
    Write-Output "secure-accounts: $($_.Exception.Message)"
    exit 1
}
