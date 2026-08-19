# secure-osusers.ps1 - lock the shell permission list so only an administrator
# can change who is on it.
#
#   powershell -File secure-osusers.ps1 -Path "C:\ProgramData\SD\sdsys\os.users" ...
#
# PROJECT_STATUS.md 7 step 7.  Run by the installer, once, AFTER the icacls that
# secures the data tree - it has to be after, or inheritance puts the
# directory's Modify straight back.  Same ordering rule as secure-cred.ps1 and
# for the same reason.
#
# READ-ONLY TO sdusers, WHICH IS THE DIFFERENCE FROM secure-cred.ps1.  $CRED
# grants ordinary users nothing at all; this one must let them READ, because
# CPROC checks the list from the user's OWN process when they type SH.  What
# they must never have is WRITE: a user who can add their own name to this file
# grants themselves a shell, which is the whole of what it prevents.
#
# THE ACL IS THE ENTIRE CONTROL.  There is nothing else - no checksum, no
# signature, no second copy.  The data tree grants sdusers Modify and this file
# sits inside it, so without this script the list is writable by exactly the
# people it exists to restrain.  That is not hypothetical: $CRED was written to
# be locked, its installer step silently did nothing, and it stayed open for a
# whole session (PROJECT_STATUS.md 4, and the entry it corrected).
#
# WHY THE DICTIONARY IS LOCKED TOO, though it does not enforce anything.  CPROC
# reads the flags POSITIONALLY - rec<1> and rec<2> - so rewriting OS.USERS.DIC
# cannot change who is permitted.  It is locked because an administrator reads
# the list through that dictionary, and a user who could redefine SH to point
# at another field could make LIST OS.USERS show something other than the truth.
# Cheap to prevent, and a wrong answer to "who has a shell?" is worth
# preventing.
#
# Exit 0 done, 1 failed, 2 could not be attempted.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string[]] $Path
)

$ErrorActionPreference = 'Stop'

# THE try/catch IS NOT DECORATION.  Under Stop, redirecting a native command's
# stderr - the 2>&1 below - turns each line into a NativeCommandError that
# TERMINATES, so an icacls that says anything at all on stderr would kill this
# script before it reached the $LASTEXITCODE test.  Uncaught, that exits with a
# PowerShell error and no message anyone will see, because the installer runs
# it hidden.  secure-cred.ps1 was the last script here to be missing this.
try {
    $missing = @($Path | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        # NOT AN ERROR AND NOT SILENT.  stage.py creates both of these, so their
        # absence means the staged tree is not what this expects.  Say so rather
        # than leaving a writable permission list behind a script that reported
        # success.
        foreach ($m in $missing) {
            Write-Output "secure-osusers: $m does not exist - nothing secured"
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
        # (RX) IS READ AND EXECUTE, NOT MODIFY.  (OI)(CI) so the records inside
        # these directory files inherit it - each record is a real file.
        #
        # /inheritance:r in the SAME command as the grants, or the object is
        # briefly - and on a busy machine observably - left with no ACEs at all.
        $out = & icacls.exe $p /inheritance:r `
            /grant '*S-1-5-18:(OI)(CI)(F)' `
            /grant '*S-1-5-32-544:(OI)(CI)(F)' `
            /grant 'sdusers:(OI)(CI)(RX)' 2>&1

        if ($LASTEXITCODE -ne 0) {
            Write-Output "secure-osusers: icacls failed on $p with $LASTEXITCODE"
            Write-Output ($out -join "`n")
            exit 1
        }

        Write-Output "secure-osusers: $p is readable by sdusers, writable only by administrators"
    }

    exit 0
}
catch {
    Write-Output "secure-osusers: $($_.Exception.Message)"
    exit 1
}
