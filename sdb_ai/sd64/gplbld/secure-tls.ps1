# secure-tls.ps1 - the directory the API's TLS relay keeps its server identity in
#
#   powershell -ExecutionPolicy Bypass -File secure-tls.ps1 -Path "C:\ProgramData\SD\sd-tls"
#
# RELEASE_1.1 41 (Linux S.19), and the Windows shape of Linux's /etc/sd-tls.
# Run by the installer, AFTER the icacls that secures the data tree - it has to
# be after, or inheritance would put sdusers Modify back on this directory.
#
# WHAT THIS CLOSES.  The API's TLS relay (gplsrc/sd_tlssrv.c) reads
# <DataDir>\sd-tls\api.pem, an Ed25519 private key and its self-signed
# certificate, and generates it there on the first API connection.  The data
# tree grants sdusers Modify with inheritance (sd.iss's icacls), so ANYTHING
# under C:\ProgramData\SD that is not separately locked is readable and
# renameable by every SD user.  Left to inherit, the server's private key
# would be one of them - and worse, an SD user could create this directory
# FIRST, own it, and hand the relay a key directory they control.
#
# So this directory, like the audit trail and the profile-reclaim store, is
# broken out of the inheritance and granted to SYSTEM and Administrators only.
# The relay (win32tls.c win32_admin_only) REFUSES the directory - and the file
# - in any other state, so a install that skipped this step accepts no API
# connection rather than running with a readable key.
#
# WHY IT IS DONE HERE AND NOT LEFT TO THE RELAY, which could mkdir it on first
# use: the relay runs as LocalSystem and a directory it created under the
# sdusers-writable parent would inherit sdusers Modify - the very thing being
# closed.  Creating it during the install, with the ACL set in the same
# command as the inheritance break, is the only point at which no SD user has
# a window to create it first.  The relay therefore never creates it (see
# sd_tlssrv.c load_identity): absent means this step did not run.
#
# NEVER DELETES AN EXISTING IDENTITY.  The directory is created only if
# missing, so reinstalling over a running machine keeps the key its clients
# have been talking to.  The ACL is reapplied either way, which repairs an
# install whose directory was created before this step existed.

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Output "secure-tls: created $Path"
    } else {
        Write-Output "secure-tls: $Path already exists, keeping it"
    }

    # /inheritance:r removes the Modify the data tree grants sdusers.  It has
    # to be in the same command as the grants, or the directory is briefly -
    # and on failure permanently - accessible to nobody at all.
    #
    # SIDs for the two built-in identities, because both are renamed on a
    # localised Windows: *S-1-5-18 is SYSTEM, *S-1-5-32-544 is
    # BUILTIN\Administrators.
    #
    # (OI)(CI) so api.pem inherits it too - the relay checks the FILE is
    # admin-only as well as the directory, and a file LocalSystem creates here
    # then carries exactly these two grants and no sdusers.
    $out = & icacls.exe $Path /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)F' `
        /grant '*S-1-5-32-544:(OI)(CI)F' 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Output "secure-tls: icacls failed with $LASTEXITCODE"
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-tls: SYSTEM and Administrators only"
    exit 0
}
catch {
    Write-Output "secure-tls: $($_.Exception.Message)"
    exit 1
}
