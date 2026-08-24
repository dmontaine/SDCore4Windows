# secure-pcode.ps1 - lock the pcode library so only an administrator can change
# the interpreter every SD session runs.
#
#   powershell -File secure-pcode.ps1 -Path "C:\ProgramData\SD\sdsys\bin"
#
# PROJECT_STATUS.md 7 step 15.  Run by the installer, once, AFTER the icacls
# that secures the data tree - it has to be after, or inheritance puts the
# directory's Modify straight back.  Same ordering rule as secure-gcat.ps1,
# secure-cred.ps1 and secure-osusers.ps1, and for the same reason.
#
# WHAT IS IN HERE, AND WHY IT IS NOT THE EXECUTABLES.  <sysdir>\bin holds the
# pcode library and nothing else - `pcode` and `pcode.old`, two files.  The
# programs live in {app}\usr\bin (5.8, and sdwind.c:477 carries the correction
# that cost a silent daemon-not-found).  stage.py:155 names this directory
# "NOT the executables - the pcode library lives here".
#
# WHAT IT PREVENTS IS WRITING, NOT READING - like secure-gcat.ps1 and
# secure-osusers.ps1, and NOT like secure-cred.ps1.  Measured unelevated on the
# 10:01:45 install, 23 Aug 2026, before this script existed:
#
#   sdsys\bin        sdusers:(I)(OI)(CI)(M)
#
# and the write was PROVED rather than inferred from that ACE: as GITORLI\don,
# UNELEVATED - so the Administrators ACE is deny-only and cannot be the grant -
# a file was created in that directory and removed again.
#
# WHY THAT MATTERS MORE THAN IT LOOKS.  sysseg.c:189 builds <sysdir>/bin/pcode,
# :193 opens it and :279 reads it WHOLE into the shared segment at start-up;
# every session then executes it through load_pcode() (sd.c:847).  So an SD user
# who replaces this file runs their own code in EVERY session - SDSYS's and an
# administrator's included - from the next SD start.  It is the same hole
# secure-gcat.ps1 closed for the global catalogue, one level further down: gcat
# decides which catalogued program runs, this decides what the interpreter
# running it IS.
#
# (RX) AND NOT "NOTHING AT ALL", DELIBERATELY.  The threat here is write; the
# contents are the same pcode shipped to every install and built from public
# source, so read is worth nothing to an attacker. Removing sdusers outright
# would also stop an ordinary token ENUMERATING the directory, and this project
# has already paid for that once - check-install.ps1 aborted with "Access is
# denied" because Test-Path THROWS on an ACL denial (4.0.1's session, item 2).
# A verifier that cannot stat a path it does not need to read is a broken suite,
# not a secured one.
#
# NOTHING NEEDS TO WRITE IT AFTER AN INSTALL.  Only the process that creates the
# shared segment reads the file, once, and `sd -start` is gated on IsElevated()
# (sd.c check_admin()), so that is the service as LocalSystem or an elevated
# administrator - both covered by the two grants below.  Ordinary sessions never
# open it at all; they take pcode from shared memory.
#
# Exit 0 done, 1 failed, 2 could not be attempted.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string[]] $Path
)

$ErrorActionPreference = 'Stop'

# THE try/catch IS NOT DECORATION - see secure-gcat.ps1's header.  Under Stop,
# redirecting a native command's stderr turns each line into a NativeCommandError
# that TERMINATES, so an icacls that says anything at all on stderr would kill
# this script before it reached the $LASTEXITCODE test, and the installer runs it
# hidden.
try {
    $missing = @($Path | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        # NOT AN ERROR AND NOT SILENT, for secure-gcat.ps1's reason: stage.py
        # creates this directory and bootstrap.py fills it, so its absence means
        # the staged tree is not what this expects.  Say so rather than leaving a
        # writable interpreter behind a script that reported success.
        foreach ($m in $missing) {
            Write-Output "secure-pcode: $m does not exist - nothing secured"
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
            Write-Output "secure-pcode: icacls failed on $p with $LASTEXITCODE"
            Write-Output ($out -join "`n")
            exit 1
        }

        Write-Output "secure-pcode: $p is readable by sdusers, writable only by administrators"
    }

    exit 0
}
catch {
    Write-Output "secure-pcode: $($_.Exception.Message)"
    exit 1
}
