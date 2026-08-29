# secure-reclaim.ps1 - create the profile-reclaim store and lock it to SYSTEM
#
#   powershell -File secure-reclaim.ps1 -Path "C:\ProgramData\SD\profile-reclaim"
#
# PRE_RELEASE_FIXES.md 36.  Run by the installer, once, after the icacls that
# secures the data tree - it has to be after, or inheritance would put the
# tree's sdusers:Modify straight back on this directory.
#
# WHAT THE STORE IS.  gpl.bp/DELETE_USER writes one file per SID here when it
# has to leave a profile behind: the SID, the account name and the DIRECTORY.
# gplbld/reclaim-profiles.ps1 reads them when the SD service starts - as
# LocalSystem, at boot, by which time the previous boot's hives are down - and
# deletes the directory and the ProfileList entry together.
#
# WHY IT NEEDS AN ACL OF ITS OWN, AND THIS IS THE WHOLE REASON THE FILE EXISTS.
# C:\ProgramData\SD grants sdusers:(OI)(CI)M, inherited by everything
# underneath.  Left to inherit, this store would be a LIST OF DIRECTORIES THAT
# EVERY SD USER CAN EDIT AND THAT LocalSystem LATER DELETES.  That is a local
# privilege escalation, and it is the same shape as the one PS_SCRIPT's header
# records for SDSYS\PSTMP: a file written by one privilege level and executed
# by a higher one, in a directory the lower level can rewrite in between.
#
# SYSTEM AND ADMINISTRATORS ONLY.  Nothing else needs to read it: the writer is
# DELETE_USER running through the session's elevated helper, and the reader is
# the service.  sdusers is not granted anything at all - unlike the audit trail,
# where SD itself has to append as an ordinary user.
#
# THE SWEEP DOES NOT TRUST THIS ANYWAY.  reclaim-profiles.ps1 re-asserts the
# ACL at every boot, skips any record file not owned by SYSTEM or
# Administrators, and validates the SID and the path in every record before it
# removes anything.  This step is what makes the directory exist with the right
# ACL BEFORE any SD user could create it first, which is the case the
# validation alone cannot cover.
#
# NEVER DISCARDS PENDING RECORDS.  The directory is created only if missing, so
# reinstalling over a machine with reclaims outstanding does not throw away work
# the next boot was going to do.  The ACL is reapplied either way, which is what
# repairs an install whose store was created by DELETE_USER before this step
# existed.

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Output "secure-reclaim: created $Path"
    } else {
        $n = @(Get-ChildItem -LiteralPath $Path -File -ErrorAction SilentlyContinue).Count
        Write-Output "secure-reclaim: $Path already exists, keeping it ($n record(s) pending)"
    }

    # /inheritance:r removes the Modify the data tree grants sdusers.  It has to
    # be in the same command as the grants, or the directory is briefly - and on
    # failure permanently - accessible to nobody at all.
    #
    # SIDs for the two built-in identities, because both are renamed on a
    # localised Windows: *S-1-5-18 is SYSTEM, *S-1-5-32-544 is
    # BUILTIN\Administrators.
    #
    # (OI)(CI) so the record files inherit it too.  Without it the ACL would
    # stop at the directory and each file would carry whatever it was created
    # with.
    $out = & icacls.exe $Path /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)F' `
        /grant '*S-1-5-32-544:(OI)(CI)F' 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Output "secure-reclaim: icacls failed with $LASTEXITCODE"
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-reclaim: SYSTEM and Administrators only"
    exit 0
}
catch {
    Write-Output "secure-reclaim: $($_.Exception.Message)"
    exit 1
}
