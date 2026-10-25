# secure-sdnet.ps1 - create the folder that holds each person's stored SDNet server logins, and set its ACL
#
#   powershell -ExecutionPolicy Bypass -File secure-sdnet.ps1 -Path "C:\ProgramData\SD\sd-net"
#
# RELEASE_1.1 171 (Linux S.65 slice 2b).  Run by the installer, once, after the icacls that secures the data tree - it has to be after, or
# inheritance would put the data tree's sdusers Modify back on this folder.
#
# WHAT IS KEPT HERE.  set.netlogin keeps, for one person on one defined server, the SCRAM-derived keys (never the password) in
# <Path>\<windows user>\<server>.  On Linux that is /var/lib/sd-net/<user>/<server>, a directory the person owns at mode 700 made by a
# privileged helper under sudo.  Windows has no sudo and the person must be able to make their own directory, so the ACL does it:
#
#   SYSTEM and Administrators   full control, and it is inherited by everything below (so an administrator can always remove a login)
#   sdusers                     list this folder and add a sub-folder to it - THIS FOLDER ONLY, not inherited
#   CREATOR OWNER               full control, inherited by what is made below and applying to the OWNER of it
#
# So an SD user makes <Path>\<their name> and owns it; what that directory inherits is SYSTEM, Administrators and its owner, and NOTHING FOR
# sdusers, so no other SD user can read, write or rename inside it.  An SD user cannot delete or rename another person's directory (the
# folder gives sdusers no delete-child right).  The kernel's SD_FILE_PRIVATE test (win32tls.c win32_private_to_user) reads this ACL again on
# every use and refuses anything that has gained another name, so a mistake here fails closed, not open.
#
# NEVER REMOVES WHAT IS THERE.  The folder is created only if missing; the ACL is re-applied either way, which repairs an install made
# before this step existed.  The people's own directories below it are left exactly as they are.
#
# SIDs for the three well-known identities, because they are renamed on a localised Windows: *S-1-5-18 SYSTEM, *S-1-5-32-544
# BUILTIN\Administrators, *S-1-3-0 CREATOR OWNER.  sdusers is our own name and is safe to write.

param(
    [Parameter(Mandatory = $true)]
    [string]$Path
)

$ErrorActionPreference = 'Stop'

try {
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
        Write-Output "secure-sdnet: created $Path"
    } else {
        Write-Output "secure-sdnet: $Path already exists, keeping it"
    }

    # /inheritance:r in the SAME command as the grants, so the folder is never left reachable by nobody.
    $out = & icacls.exe $Path /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)F' `
        /grant '*S-1-5-32-544:(OI)(CI)F' `
        /grant '*S-1-3-0:(OI)(CI)(IO)F' `
        /grant 'sdusers:(RX,AD)' 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Output "secure-sdnet: icacls failed with $LASTEXITCODE"
        Write-Output ($out -join "`n")
        exit 1
    }

    Write-Output "secure-sdnet: ACL applied"
    exit 0
}
catch {
    Write-Output "secure-sdnet: $($_.Exception.Message)"
    exit 1
}
