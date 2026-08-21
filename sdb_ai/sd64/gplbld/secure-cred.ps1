# secure-cred.ps1 - lock the credential store to SYSTEM and Administrators
#
#   powershell -File secure-cred.ps1 -Path "C:\ProgramData\SD\sdsys\$cred"
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
#   Elevated console    YES - an administrator running MODIFY.PASSWORD.  That is
#                       why MODIFY.PASSWORD is an administration verb.
#   Ordinary console    NO, deliberately.  In stage 1 SD runs as the invoking
#                       user, so a user who could change their own password
#                       could also rewrite everybody's.  The consequence is
#                       that copying MODIFY.PASSWORD into a user's VOC will not
#                       work at the file layer until section 5.7's service
#                       model lands - the verb permits it, the ACL does not.
#
# Exit 0 done, 1 failed, 2 could not be attempted.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Path
)

$ErrorActionPreference = 'Stop'

# THE try/catch IS NOT DECORATION, and this script was the only one of the four
# without it until 17 Aug 2026.  Under Stop, redirecting a native command's
# stderr - the 2>&1 below - turns each line into a NativeCommandError that
# TERMINATES, so an icacls that says anything at all on stderr would kill this
# script before it reached the $LASTEXITCODE test.  Uncaught, that exits with a
# PowerShell error and no message anyone will see, because the installer runs
# it hidden.  Caught, it is exit 1 and a line saying why.
try {
    if (-not (Test-Path -LiteralPath $Path)) {
        # NOT AN ERROR AND NOT SILENT.  The bootstrap creates $CRED, so its
        # absence means the staged tree is not what this expects; say so rather
        # than leaving a wide-open credential store behind a script that
        # reported success.
        #
        # THIS IS THE BRANCH THAT RAN FOR THE WHOLE OF 16-17 Aug 2026, and it
        # was telling the truth.  sd.iss single quoted the path and passed it
        # to -File, which strips nothing, so $Path arrived as "'C:\...\$CRED'"
        # - quotes and all - and really did not exist.  Fixed in sd.iss, where
        # the measurement is written up; the usage line at the top of this file
        # always showed the correct form.
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
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-cred: $Path locked to SYSTEM and Administrators"
    exit 0
}
catch {
    Write-Output "secure-cred: $($_.Exception.Message)"
    exit 1
}
