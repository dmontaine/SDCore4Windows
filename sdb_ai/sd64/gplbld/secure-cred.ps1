# secure-cred.ps1 - lock the credential store to SYSTEM and Administrators
#
#   powershell -File secure-cred.ps1 -Path "C:\ProgramData\SD\sdsys\$CRED"
#
# PROJECT_STATUS.md 7 step 6.  Run by the installer, once, AFTER the icacls
# that secures the data tree - it has to be after, or inheritance puts the
# directory's Modify straight back, which is the same ordering secure-audit.ps1
# needs and for the same reason.
#
# WHAT IS IN THIS FILE, because it decides how alarming the exposure is:
# a per-account SALT and an ARGON2 VERIFIER derived from the password
# (INT$KEYS.H:263).  No password is stored, in this or any other shape.
#
# SO WHY LOCK IT AT ALL, AND IT IS NOT ABOUT READING.  The data tree grants
# sdusers Modify, which every SD user needs to use the database.  Inherited
# onto the credential store that means an ordinary user can WRITE another
# account's verifier - derive one from a password they choose, overwrite the
# record, and then authenticate through the API as that account.  Reading a
# verifier is of limited use against Argon2; replacing one is a straight
# privilege escalation.  That is the risk this closes.
#
# THE FILE SHAPE IS NOT A CONTROL AND MUST NOT BE MISTAKEN FOR ONE.  $CRED is a
# directory file, so each account is a separate record file; a dynamic file
# would put the same bytes in %0 instead, equally readable to anyone with
# access.  Obscurity either way - the ACL below is the whole of the protection.
#
# WHO CAN STILL REACH IT, and this is what makes it workable (17 Aug 2026):
#
#   API sessions        YES - the SD service runs as LocalSystem (checked:
#                       Win32_Service StartName), and sdwind forks "sd -n -q"
#                       children that inherit it, so they read this as SYSTEM.
#   Elevated console    YES - an administrator running SET.PASSWORD.  That is
#                       why SET.PASSWORD is an administration verb.
#   Ordinary console    NO, deliberately.  In stage 1 SD runs as the invoking
#                       user, so a user who could change their own password
#                       could also rewrite everybody's.  The consequence is
#                       that copying SET.PASSWORD into a user's VOC will not
#                       work at the file layer until section 5.7's service
#                       model lands - the verb permits it, the ACL does not.
#
# Exit 0 done, 1 failed, 2 could not be attempted.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Path
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Path)) {
    # NOT AN ERROR AND NOT SILENT.  The bootstrap creates $CRED, so its absence
    # means the staged tree is not what this expects; say so rather than
    # leaving a wide-open credential store behind a script that reported
    # success.
    Write-Output "secure-cred: $Path does not exist - nothing secured"
    exit 2
}

# SIDS, NOT NAMES, so a localised Windows does not break the installer:
#   *S-1-5-18       NT AUTHORITY\SYSTEM
#   *S-1-5-32-544   BUILTIN\Administrators
#
# /inheritance:r in the SAME command as the grants, or the object is briefly -
# and on a busy machine observably - left with no ACEs at all.
#
# sdusers is granted NOTHING here.  That is the entire point, and it is the
# difference from secure-audit.ps1, which grants them append-only so SD can
# still write the trail as the user.  Nothing needs to reach this file as an
# ordinary user.
$out = & icacls.exe $Path /inheritance:r `
    /grant '*S-1-5-18:(OI)(CI)(F)' `
    /grant '*S-1-5-32-544:(OI)(CI)(F)' 2>&1

if ($LASTEXITCODE -ne 0) {
    Write-Output "secure-cred: icacls failed with $LASTEXITCODE"
    Write-Output $out
    exit 1
}

Write-Output "secure-cred: $Path locked to SYSTEM and Administrators"
exit 0
