# secure-log.ps1 - create a log only administrators can see or write
#
#   powershell -File secure-log.ps1 -Path "C:\ProgramData\SD\sd-elevate.log"
#
# PROJECT_STATUS.md 7 step 4.  Run by the installer, once, AFTER the icacls that
# secures the data tree - run before, and inheritance puts the directory's
# Modify straight back on the file.  Same ordering constraint as secure-audit.
#
# WHY THIS IS NOT secure-audit.ps1 WITH A SWITCH.  That script produced this
# project's append-only audit trail and its ACL was measured right, six ways.
# Adding a mode to it to serve a DIAGNOSTIC would put a verified security path
# at risk for no gain; the two files want genuinely different ACLs, and forty
# lines is a cheap price for not touching the other one.
#
# AND THE ACL HERE IS THE STRICTER OF THE TWO, which is worth saying because it
# looks like the weaker case.  The audit trail must keep sdusers:AppendData
# because UNELEVATED SD sessions write it themselves.  Nothing unelevated ever
# writes this file: it is written only by sd-elevate-helper.ps1, which is
# elevated by definition.  So sdusers needs nothing at all here - not append,
# not even read - and gets nothing.
#
# WHY NOT THE USER'S AppData, which was considered and rejected 16 Aug 2026.
# %LOCALAPPDATA% grants the user Full Control and, decisively, the user OWNS it.
# An owner keeps implicit WRITE_DAC, so a tightened ACL there can be reset by
# the very person the log is about.  C:\ProgramData\SD is owned by
# BUILTIN\Administrators and cannot be taken back by an ordinary SD user.
# Obscurity would have been the only protection; this is enforcement.
#
# NEVER TRUNCATES AN EXISTING LOG, for the reason secure-audit gives: a
# reinstall over a running machine should not discard its history.  The ACL is
# reapplied either way.

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType File -Path $Path -Force | Out-Null
        Write-Output "secure-log: created $Path"
    } else {
        Write-Output "secure-log: $Path already exists, keeping it"
    }

    # /inheritance:r and the grants in ONE command, or the file is briefly - and
    # on failure permanently - reachable by nobody at all.
    #
    # SIDs rather than names for the two built-ins, because both are renamed on
    # a localised Windows: *S-1-5-18 is SYSTEM, *S-1-5-32-544 is
    # BUILTIN\Administrators.  sdusers is deliberately absent.
    $out = & icacls.exe $Path /inheritance:r `
        /grant '*S-1-5-18:(F)' `
        /grant '*S-1-5-32-544:(F)' 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Output "secure-log: icacls failed with $LASTEXITCODE"
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-log: administrators-only ACL applied"
    exit 0
}
catch {
    Write-Output "secure-log: $($_.Exception.Message)"
    exit 1
}
