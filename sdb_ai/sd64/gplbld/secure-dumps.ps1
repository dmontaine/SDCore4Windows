# secure-dumps.ps1 - make the process-dump directory write-only to SD users
#
#   powershell -File secure-dumps.ps1 -Path "C:\ProgramData\SD\sdsys\dumps"
#
# PRE_RELEASE_FIXES.md 28.  Run by the installer, once, AFTER the icacls that
# secures the data tree - it has to be after, or inheritance would put the
# tree's Modify back on this directory.  Same ordering rule as secure-audit.ps1
# and for the same reason.
#
# WHAT THE DEFECT WAS.  pdump() writes to pcfg.dumpdir, and when DUMPDIR is
# empty it falls back to sysseg->sysdir (pdump.c:98) - the system directory,
# which grants sdusers Modify because every SD user needs it to use the
# database.  A process dump carries the whole variable state of the session
# that wrote it, so every SD user could read every other user's.
#
# WHY NOT SIMPLY ADMINISTRATOR-ONLY, WHICH IS WHAT THE ENTRY FIRST PROPOSED.
# Measured before writing this: pdump is in newvoc/TIER.OMIT.STANDARD, so it is
# withheld from STANDARD accounts and available to PROGRAMMER ones - and
# k_error.c:286 calls it unprompted whenever OptDumpOnError is set.  An
# administrator-only directory would therefore fail to write a programmer's
# dump, on a path that is already handling an error.  Losing the diagnostic
# exactly when it was wanted is a poor trade for tidiness.
#
# SO THE ACL IS secure-audit.ps1's SHAPE, TRANSPOSED FROM A FILE TO A
# DIRECTORY: write-only to the people it is about.
#
#   WD  AddFile          - create a dump.  This is the one right SD needs.
#   AD  AddSubdirectory  - granted with WD as the pair icacls expects
#   X   Traverse         - reach a known path inside the directory
#   S   Synchronize      - required for any normal file access
#
# RD (ListDirectory) is deliberately ABSENT, and it is the whole point: an SD
# user can drop their own dump in and cannot enumerate or open anybody else's.
# A file created here inherits nothing - inheritance is stripped below - so it
# gets the creator's default DACL, which is why a user can still read back the
# dump they just wrote.  That is wanted; reading SOMEBODY ELSE'S is not.
#
# ADMINISTRATORS AND SYSTEM KEEP FULL CONTROL, on the owner's standing
# decision of 16 Aug 2026 recorded in secure-audit.ps1: "admins are highly
# trusted - we are increasing security not maximizing it".  This raises the
# floor against ordinary SD users; it does not pretend to constrain somebody
# who can take ownership anyway.
#
# NEVER REMOVES AN EXISTING DUMP.  The directory is created only if missing and
# nothing in it is touched, so reinstalling over a machine that has been
# running keeps whatever dumps are there.  The ACL is reapplied either way,
# which is what repairs a tree whose dumps directory predates this step.
#
# THE NULL CASE IS REFUSED OUT LOUD (CLAUDE.md): -Path is mandatory, the
# resolved path is echoed, and an icacls failure exits non-zero with its output
# rather than reporting success for work that did not happen.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Path
)

$ErrorActionPreference = 'Stop'

Write-Output "secure-dumps: path $Path"

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Output "secure-dumps: created $Path"
    } else {
        Write-Output "secure-dumps: $Path already exists, keeping it and what is in it"
    }

    # /inheritance:r removes the Modify the data tree grants sdusers.  It has
    # to be in the same command as the grants, or the directory is briefly -
    # and on failure permanently - accessible to nobody at all.
    #
    # SIDs for the two built-in identities, because both are renamed on a
    # localised Windows: *S-1-5-18 is SYSTEM, *S-1-5-32-544 is
    # BUILTIN\Administrators.  sdusers is our own name and is safe to write.
    #
    # (OI)(CI) on the two full-control grants so an administrator can still
    # read dumps written later.  NOT on the sdusers grant: that one must apply
    # to the directory alone, or every dump file would inherit AddFile from it.
    $out = & icacls.exe $Path /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)(F)' `
        /grant '*S-1-5-32-544:(OI)(CI)(F)' `
        /grant 'sdusers:(WD,AD,X,S)' 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Output "secure-dumps: icacls failed with $LASTEXITCODE"
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-dumps: write-only ACL applied - SD users may add a dump, not list or read one"
    exit 0
}
catch {
    Write-Output "secure-dumps: $($_.Exception.Message)"
    exit 1
}
