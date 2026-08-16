# secure-psdir.ps1 - the directory !ps_script writes privileged scripts into
#
#   powershell -File secure-psdir.ps1 -Path "C:\ProgramData\SD\sdsys\PSTMP"
#
# PROJECT_STATUS.md 7 step 4.  Run by the installer, AFTER the icacls that
# secures the data tree and BEFORE adopt-account.ps1, which reaches SDSYS and
# is the install's own first caller of !ps_script.
#
# WHAT THIS CLOSES, measured 16 Aug 2026.  !ps_script used to write each script
# into the CURRENT ACCOUNT DIRECTORY, which for an SDSYS session is
# C:\ProgramData\SD\sdsys.  The data tree grants sdusers Modify and it is
# inherited, so every file there carries sdusers:(I)(OI)(CI)(M) - checked on
# the installed tree.  Two consequences, and the second is the serious one:
#
#   * DISCLOSURE.  !set_passwd's script carries a new Windows password in
#     clear, and any SD user could read it in the window before it is deleted.
#
#   * ELEVATION.  Any SD user could REWRITE another user's pending script
#     between SD writing it and the elevated helper executing it, and the
#     helper would run their content with full privilege.  That is a local
#     privilege escalation, not merely a leak, and it is why this is worth a
#     directory of its own rather than a tighter ACL on one file.
#
# HOW THE ACL WORKS, and it is not the same shape as the audit trail's.
#
#   sdusers on the DIRECTORY ONLY, with no (OI)(CI): list, create, traverse.
#     Enough for SD to openpath the directory and write a record into it, and
#     no rights at all on files it did not create.  Listing is granted on
#     purpose - SD's directory-file layer opens the directory itself, and the
#     names are predictable anyway, being derived from the SD user number.
#     DC (DeleteChild) is deliberately NOT granted, so one user cannot delete
#     another's file to make room for their own.
#
#   CREATOR OWNER as (OI)(IO)(F): inherited by FILES only, so whoever creates
#     a script owns it and has full control of that one file - enough to write
#     it, run it and delete it afterwards - while every other SD user has
#     nothing on it.
#
#   Administrators and SYSTEM keep (OI)(CI)(F), which is what lets the elevated
#     helper read the script it is asked to run.
#
# KNOWN EDGE, left as a comment rather than engineered around.  The file name
# carries the SD user number, which is reused as sessions come and go.  If a
# session dies between the write and the delete, its file stays owned by that
# user, and a later session that is given the same number under a DIFFERENT
# user cannot write it - !ps_script fails and the verb reports an error.  That
# is a nuisance, not a hole: it fails closed, and an administrator can delete
# the file.  It needs a crash inside a window of milliseconds to happen at all.

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Output "secure-psdir: created $Path"
    } else {
        Write-Output "secure-psdir: $Path already exists"
    }

    # Any script left behind by an earlier install belongs to nobody now and
    # could carry a password.  Clear them before the ACL goes on.
    Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue |
        Remove-Item -Force -ErrorAction SilentlyContinue

    # /inheritance:r and every grant in ONE command - see secure-audit.ps1 for
    # why splitting them is dangerous.  SIDs for the built-ins because all
    # three are renamed on a localised Windows: *S-1-5-18 SYSTEM,
    # *S-1-5-32-544 BUILTIN\Administrators, *S-1-3-0 CREATOR OWNER.
    $out = & icacls.exe $Path /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)(F)' `
        /grant '*S-1-5-32-544:(OI)(CI)(F)' `
        /grant '*S-1-3-0:(OI)(IO)(F)' `
        /grant 'sdusers:(RD,WD,AD,X,RA,S)' 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Output "secure-psdir: icacls failed with $LASTEXITCODE"
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-psdir: per-creator ACL applied"
    exit 0
}
catch {
    Write-Output "secure-psdir: $($_.Exception.Message)"
    exit 1
}
