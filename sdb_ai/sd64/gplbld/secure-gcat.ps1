# secure-gcat.ps1 - lock the global catalogue so only an administrator can
# change the programs SD runs for every session.
#
#   powershell -File secure-gcat.ps1 -Path "C:\ProgramData\SD\sdsys\gcat"
#   powershell -File secure-gcat.ps1 -Path "C:\ProgramData\SD\sdsys\gpl.bp.out"
#
# THE INSTALLER APPLIES IT TO BOTH, one call each (sd.iss, SecureGcat).
# GPL.BP.OUT holds the compiled objects the global catalogue is loaded FROM, so
# leaving it writable leaves a slower version of the same hole: plant an object
# and wait for an administrator to re-catalogue it.  Owner's instruction,
# 18 Aug 2026, after gcat alone measured locked and GPL.BP.OUT still carried
# sdusers:(I)(OI)(CI)(M) on the same install.
#
# PROJECT_STATUS.md 8 ("the B work"), UPSTREAM_FIXES.md 7.  Run by the installer,
# once, AFTER the icacls that secures the data tree - it has to be after, or
# inheritance puts the directory's Modify straight back.  Same ordering rule as
# secure-cred.ps1 and secure-osusers.ps1, and for the same reason.
#
# WHAT IS IN HERE.  gcat is the global catalogue: object code, keyed by call
# name, that every session executes.  $LOGIN is one of its records and CPROC:315
# calls it for EVERY session, administrators included.  Measured unelevated on
# the installed tree, 18 Aug 2026, before this script existed:
#
#   sdsys\gcat        sdusers:(I)(OI)(CI)(M)
#
# So any SD user could overwrite $LOGIN and run their own code in everybody's
# session, or delete it and stop the whole machine signing in.
#
# READ-ONLY TO sdusers, LIKE secure-osusers.ps1 AND NOT LIKE secure-cred.ps1.
# Ordinary sessions must READ this directory - that is what running a catalogued
# program IS - so (RX) rather than nothing at all.  What they must never have is
# write.  (OI)(CI) because each catalogue entry is a real file underneath.
#
# THIS IS THE SECOND HALF OF A PAIR, AND BOTH HALVES ARE WANTED.  CATALOG and
# DELCAT gained a K$ADMINISTRATOR test on 18 Aug 2026; before it, CATALOG tested
# only the spelled-out GLOBAL keyword and DELCAT tested nothing at all, so a
# "*!_$" name prefix reached gcat from any account holding the verb.  The BASIC
# test is the one that gives a clean error message; THIS is the one that does
# not depend on every present and future code path remembering to ask.  A gate
# in one program protects one program.
#
# THE CONSEQUENCE, AND IT IS A REAL BEHAVIOUR CHANGE - decided by the repository
# owner, 18 Aug 2026.  Cataloguing globally now needs a GENUINELY ELEVATED
# session, not merely an administrator one.  sd.exe stays unelevated for life
# and a UAC-filtered token carries Administrators as deny-only, so the grant
# above does nothing for an ordinary session - which is exactly why audit, $CRED
# and PSTMP measure as "Access is denied" from one.  A session that reached
# SDSYS through the elevation helper (CPROC, !elevate) therefore has
# K$ADMINISTRATOR true and an unelevated token: it passes the BASIC gate and is
# refused here.  Recompiling GPL.BP already documents an elevated window
# (PROJECT_STATUS.md 7 step 0), so the supported route is unchanged; what is new
# is that the unsupported one now fails at the file layer instead of working.
#
# Exit 0 done, 1 failed, 2 could not be attempted.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string[]] $Path
)

$ErrorActionPreference = 'Stop'

# THE try/catch IS NOT DECORATION - see secure-osusers.ps1's header.  Under Stop,
# redirecting a native command's stderr turns each line into a NativeCommandError
# that TERMINATES, so an icacls that says anything at all on stderr would kill
# this script before it reached the $LASTEXITCODE test, and the installer runs it
# hidden.
try {
    $missing = @($Path | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        # NOT AN ERROR AND NOT SILENT.  bootstrap.py builds gcat, so its absence
        # means the staged tree is not what this expects.  Say so rather than
        # leaving a writable global catalogue behind a script that reported
        # success - the failure mode secure-cred.ps1 actually had.
        foreach ($m in $missing) {
            Write-Output "secure-gcat: $m does not exist - nothing secured"
        }
        exit 2
    }

    foreach ($p in $Path) {
        # SIDS, NOT NAMES, for the two built-in identities, so a localised
        # Windows does not break the installer:
        #   *S-1-5-18       NT AUTHORITY\SYSTEM
        #   *S-1-5-32-544   BUILTIN\Administrators
        # sdusers is our own name and is safe to write.
        #
        # /inheritance:r in the SAME command as the grants, or the object is
        # briefly - and on a busy machine observably - left with no ACEs at all.
        $out = & icacls.exe $p /inheritance:r `
            /grant '*S-1-5-18:(OI)(CI)(F)' `
            /grant '*S-1-5-32-544:(OI)(CI)(F)' `
            /grant 'sdusers:(OI)(CI)(RX)' 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Output "secure-gcat: icacls failed on $p with $LASTEXITCODE"
            Write-Output ($out -join "`n")
            exit 1
        }

        Write-Output "secure-gcat: $p is executable by sdusers, writable only by administrators"
    }

    exit 0
}
catch {
    Write-Output "secure-gcat: $($_.Exception.Message)"
    exit 1
}
