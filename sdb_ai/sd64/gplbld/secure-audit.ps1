# secure-audit.ps1 - create the audit trail and make it append-only
#
#   powershell -File secure-audit.ps1 -Path "C:\ProgramData\SD\sdsys\audit"
#
# PROJECT_STATUS.md 7 step 4.  Run by the installer, once, after the icacls
# that secures the data tree - it has to be after, or inheritance would put
# the directory's Modify back on this file.
#
# WHAT THIS BUYS, AND IT WAS MEASURED RATHER THAN ASSUMED (16 Aug 2026).  The
# data tree grants sdusers Modify, which every SD user needs in order to use
# the database at all.  Inherited onto the audit trail that would mean the
# people it records could read it, rewrite it and delete it.  With the ACL
# below, against a caller holding only these rights:
#
#   append a record      works        <- SD needs exactly this and no more
#   read the file        refused
#   truncate to nothing  refused
#   overwrite in place   refused
#   rename or delete     refused
#
# AD is AppendData and NOT WriteData, and the difference is the whole point:
# with WriteData an ordinary user can blank the file or overwrite individual
# records, both measured.  RA (ReadAttributes) is what lets SD see the size to
# decide on rotation.  S (Synchronize) is required for any normal file access.
#
# It is also why SD writes this file through win32audit.c instead of the POSIX
# runtime: open(O_WRONLY|O_APPEND) asks for GENERIC_WRITE, which contains
# WriteData, and fails against this ACL with errno 13.
#
# ADMINISTRATORS AND SYSTEM KEEP FULL CONTROL.  Owner's decision, 16 Aug 2026:
# "admins are highly trusted - we are increasing security not maximizing it".
# So this raises the floor against ordinary SD users and does not pretend to
# constrain somebody who can take ownership anyway.  Rotation relies on it -
# sd -start renames the file, and only an elevated session can.
#
# NEVER TRUNCATES AN EXISTING TRAIL.  The file is created only if missing, so
# reinstalling over a machine that has been running does not discard its
# history.  The ACL is reapplied either way, which is what repairs an install
# whose audit file was created by SD before this step existed.

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
        Write-Output "secure-audit: created $Path"
    } else {
        Write-Output "secure-audit: $Path already exists, keeping it"
    }

    # /inheritance:r removes the Modify the data tree grants sdusers.  It has
    # to be in the same command as the grants, or the file is briefly - and on
    # failure permanently - accessible to nobody at all.
    #
    # SIDs for the two built-in identities, because both are renamed on a
    # localised Windows: *S-1-5-18 is SYSTEM, *S-1-5-32-544 is
    # BUILTIN\Administrators.  sdusers is our own name and is safe to write.
    $out = & icacls.exe $Path /inheritance:r `
        /grant '*S-1-5-18:(F)' `
        /grant '*S-1-5-32-544:(F)' `
        /grant 'sdusers:(AD,RA,S)' 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Output "secure-audit: icacls failed with $LASTEXITCODE"
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-audit: append-only ACL applied"
    exit 0
}
catch {
    Write-Output "secure-audit: $($_.Exception.Message)"
    exit 1
}
