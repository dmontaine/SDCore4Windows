# secure-sysdirs.ps1 - take Modify off the SDSYS system directories that
# nothing writes, leaving them readable by SD users and writable only by
# administrators.
#
#   powershell -File secure-sysdirs.ps1 -Path "C:\ProgramData\SD\sdsys\accounts"
#
# PROJECT_STATUS.md 7 step 15, on the OWNER'S RULING of 24 Aug 2026.  Run by
# the installer, once per path, AFTER the icacls that secures the data tree -
# it has to be after, or inheritance puts the Modify straight back.  Same
# ordering rule as secure-pcode.ps1, secure-gcat.ps1, secure-cred.ps1 and
# secure-osusers.ps1, and for the same reason.
#
# THE SEVEN PATHS ARE NAMED BY sd.iss, NOT BY THIS SCRIPT, so that one file
# holds the list and this one holds the mechanism - the shape secure-pcode.ps1
# and secure-gcat.ps1 already have.  They are:
#
#   <DataDir>\sdsys\accounts   <DataDir>\sdsys\newvoc
#   <DataDir>\sdsys\$map       <DataDir>\sdsys\bp
#   <DataDir>\sdsys\messages   <DataDir>\sdsys\cat
#   <DataDir>\sd.conf
#
# ***$ipc IS DELIBERATELY NOT ONE OF THEM AND MUST NOT BE ADDED.***  It is the
# ONE of the eight inherited-Modify targets that an ordinary session was
# MEASURED writing: every session modifies $ipc\%0, PHANTOM writes its command
# there (sd.c:55) and APISRVR:214 opens it.  Locking it breaks every session
# and every phantom.  verify-sysdiracl.ps1 carries $ipc as its NEGATIVE
# CONTROL for exactly this reason - a run where $ipc has stopped being
# writable is a failure, not a tighter pass.
#
# WHAT THE EVIDENCE WAS, since "nothing writes it" is the whole justification.
# gplbld\probe-syswrites.ps1 drove a real session on the 15:14:28 install of
# 24 Aug 2026 - 15 verbs echoed, including SETPTR for the spooler and the
# SELECT/SAVE.LIST/GET.LIST/DELETE.LIST family - plus a separate PHANTOM pass
# that refused itself unless a second sd.exe appeared.  Only $ipc\%0 changed.
# op_dio2.c:1405's net_sysdir_shared[] is SD's own answer to the same
# question: accounts, bp, cat and sd.conf are not on it, so a stock account
# VOC does not name them at all.
#
# THE FOUR WRITERS THAT REMAIN ARE ALL ADMINISTRATIVE, and all of them keep
# their access through the Administrators grant below: CREATE.ACCOUNT and
# DELETE.ACCOUNT write accounts, compiling into SDSYS's bp needs LOGTO SDSYS
# and elevation, CATALOG in SDSYS is elevated, and CONFIG is an administrator
# verb.  Those four rows were REASONED rather than measured when the ruling
# was made; the cycle that installs this script is what settles them.
#
# WHAT IT PREVENTS IS WRITING, NOT READING - like secure-pcode.ps1 and
# secure-gcat.ps1, and NOT like secure-cred.ps1.  Every one of these paths is
# read on the ordinary session path: sd.conf is read at start-up by every
# sd.exe, messages and $map are read by the interpreter, newvoc is read by
# CREATE.ACCOUNT, and accounts is read whenever a name is resolved.  Removing
# sdusers outright would also stop an ordinary token ENUMERATING them, and
# this project has already paid for that once - check-install.ps1 aborted with
# "Access is denied" because Test-Path THROWS on an ACL denial.
#
# ***sd.conf IS A FILE AND THE OTHER SIX ARE DIRECTORIES.***  (OI) and (CI) are
# container-inherit flags and icacls REFUSES them on a file, so the grant is
# branched on PSIsContainer rather than written once.  This is the one thing
# the secure-pcode.ps1 precedent does not cover, and it is why this script
# reports the kind of each path it touched: a run that silently treated the
# file as a directory would have granted nothing at all.
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
    # REFUSE THE NULL CASE OUT LOUD.  Mandatory stops -Path being omitted; it
    # does not stop -Path " " or -Path @(), and either would walk the loop zero
    # times and exit 0 having secured nothing.  A step that passes because it
    # did nothing is the failure this project has paid for most often.
    #
    # MEASURED, NOT ASSUMED, 24 Aug 2026: the null case is refused TWICE, by
    # two different mechanisms, and this guard is only the second of them.
    #   -Path ''   never reaches here.  PowerShell's PARAMETER BINDER rejects
    #              it first - "Missing an argument for parameter 'Path'" - and
    #              the script exits 1 having run no line of its own.
    #   -Path ' '  binds as a one-element array of blank and DOES reach here,
    #              which is what this test is for.
    # Both refuse; neither passes silently.  Do not delete this on the strength
    # of the binder alone - @() and a whitespace argument get past it.
    $wanted = @($Path | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($wanted.Count -eq 0) {
        Write-Output 'secure-sysdirs: -Path resolved to nothing - no directory was secured'
        exit 2
    }

    $missing = @($wanted | Where-Object { -not (Test-Path -LiteralPath $_) })
    if ($missing.Count -gt 0) {
        # NOT AN ERROR AND NOT SILENT, for secure-gcat.ps1's reason: stage.py
        # creates these and the install fills them, so an absence means the
        # staged tree is not what this expects.  Say so rather than leaving a
        # writable system directory behind a script that reported success.
        foreach ($m in $missing) {
            Write-Output "secure-sysdirs: $m does not exist - nothing secured"
        }
        exit 2
    }

    foreach ($p in $wanted) {
        $item = Get-Item -LiteralPath $p -Force

        # SIDS, NOT NAMES, for the two built-in identities, so a localised
        # Windows does not break the installer:
        #   *S-1-5-18       NT AUTHORITY\SYSTEM
        #   *S-1-5-32-544   BUILTIN\Administrators
        # sdusers is our own name and is safe to write.
        if ($item.PSIsContainer) {
            $kind   = 'directory'
            $grants = @('*S-1-5-18:(OI)(CI)(F)',
                        '*S-1-5-32-544:(OI)(CI)(F)',
                        'sdusers:(OI)(CI)(RX)')
        } else {
            $kind   = 'file'
            $grants = @('*S-1-5-18:(F)',
                        '*S-1-5-32-544:(F)',
                        'sdusers:(RX)')
        }

        # ECHO WHAT IS ABOUT TO BE PASSED, not what was intended - the rule a
        # $args-clobbered Start-Process cost this project a day for.  The
        # resolved path and the exact ACE strings, so a run that granted the
        # wrong thing is readable in the transcript rather than inferred.
        Write-Output ("secure-sysdirs: {0} [{1}] <- /inheritance:r {2}" -f
                      $item.FullName, $kind, ($grants -join ' '))

        # /inheritance:r in the SAME command as the grants, or the object is
        # briefly - and on a busy machine observably - left with no ACEs at
        # all.  NO /T: these are the only objects being restamped, and a walk
        # is what section 6's "empties the parent, loses the walk, exits 0"
        # trap needs to bite.
        $out = & icacls.exe $item.FullName /inheritance:r `
            /grant $grants[0] `
            /grant $grants[1] `
            /grant $grants[2] 2>&1
        $text = ($out | Out-String)

        # THE EXIT CODE IS NOT THE ONLY INSTRUMENT - section 6, and it cost two
        # runs of verify-apiidentity.  icacls can print a refusal on stderr and
        # still exit 0 when the item named on the command line succeeded.
        # "Failed processing 0 files" is printed on EVERY success, so the
        # disqualifier has to be a NON-ZERO count; matching the bare phrase is
        # what made Assert-Icacls refuse its own success path.
        $refused = ($text -match 'Access is denied') -or
                   ($text -match 'Failed processing [1-9]')

        if (($LASTEXITCODE -ne 0) -or $refused) {
            Write-Output "secure-sysdirs: icacls failed on $($item.FullName) with $LASTEXITCODE"
            Write-Output $text
            exit 1
        }

        Write-Output ("secure-sysdirs: {0} is readable by sdusers, writable only by administrators" -f
                      $item.FullName)
    }

    exit 0
}
catch {
    Write-Output "secure-sysdirs: $($_.Exception.Message)"
    exit 1
}
