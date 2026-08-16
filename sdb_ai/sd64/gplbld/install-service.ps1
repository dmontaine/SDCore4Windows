# install-service.ps1 - create, start and remove the SD Windows service
#
#   powershell -File install-service.ps1 -Install [-AppDir <dir>]
#   powershell -File install-service.ps1 -Remove
#
# Exit 0 done, 1 failed, 2 could not be attempted (not elevated, no sdsvc.exe).
#
# WHY SD IS A SERVICE.  Owner's decision, 15 Aug 2026: SD must be running after
# every Windows startup, and it must be running when the installer finishes.
# Until now there was no service at all - "sd -start" had to be typed after
# every restart, which PROJECT_STATUS.md 7 step 3 recorded as an installer
# loose end and which made the closing dialog tell users to start SD by hand.
#
# WHAT RUNS.  sdsvc.exe, the native service wrapper beside sd.exe - see
# gplsrc/sdsvc/sdsvc.c for why the service is a separate native program rather
# than a switch on sd.exe.  It owns the lifecycle only: sd -start when Windows
# starts the service, sd -stop when Windows stops it.
#
# THIS IS NOT THE SERVICE ACCOUNT MODEL IN 5.7.  That one gives SD a dedicated
# identity that owns the data tree, with sessions reaching it over a named
# pipe, and it is stage 2.  This runs as LocalSystem and changes nothing about
# who owns the files.  LocalSystem is chosen because it is elevated - sd -start
# is gated on IsElevated() - and because it needs no password to manage.

param(
    [switch] $Install,
    [switch] $Remove,
    [string] $AppDir = ''
)

$ErrorActionPreference = 'Continue'

$SvcName    = 'SD'
$SvcDisplay = 'String Database (SD)'
$SvcDesc    = 'Runs the SD multivalue database. Stopping this service ends every SD session on this machine.'

# NOT A param DEFAULT.  In a script with a mandatory parameter or
# [CmdletBinding()], $PSScriptRoot evaluates to the empty string in a param
# default - measured 15 Aug 2026, and it cost a whole install in
# adopt-account.ps1 before it was understood.  Assigned in the body instead.
if ($AppDir -eq '') { $AppDir = $PSScriptRoot }

$svcExe = Join-Path $AppDir 'usr\bin\sdsvc.exe'

function Say($m) { Write-Output "install-service: $m" }

$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Say 'not elevated - creating or removing a service needs an elevated token'
    exit 2
}

if (-not ($Install -or $Remove)) {
    Say 'pass -Install or -Remove'
    exit 2
}

function Get-Svc { return (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) }

# --- remove ----------------------------------------------------------------
#
# IDEMPOTENT, like the rest of the installer's helpers: an absent service is
# success, because the uninstaller must not fail on a machine where the service
# was never created or was removed by hand.
if ($Remove) {
    $s = Get-Svc
    if ($null -eq $s) { Say "no $SvcName service; nothing to remove"; exit 0 }

    if ($s.Status -ne 'Stopped') {
        Say "stopping $SvcName"
        Stop-Service -Name $SvcName -Force -ErrorAction SilentlyContinue
        # Stop-Service returns before the SCM has finished; sc delete on a
        # still-stopping service leaves it marked for deletion until reboot.
        $deadline = (Get-Date).AddSeconds(30)
        while ((Get-Date) -lt $deadline) {
            $s = Get-Svc
            if ($null -eq $s -or $s.Status -eq 'Stopped') { break }
            Start-Sleep -Milliseconds 500
        }
    }

    & "$env:SystemRoot\System32\sc.exe" delete $SvcName | Out-Null
    if ($LASTEXITCODE -ne 0) { Say "sc delete failed, exit $LASTEXITCODE"; exit 1 }
    Say "$SvcName removed"
    exit 0
}

# --- install ---------------------------------------------------------------
if (-not (Test-Path $svcExe)) {
    Say "no $svcExe - was the install complete?"
    exit 2
}

if ($null -ne (Get-Svc)) {
    Say "$SvcName already exists; removing it first so binPath is not stale"
    & "$env:SystemRoot\System32\sc.exe" stop $SvcName | Out-Null
    Start-Sleep -Seconds 2
    & "$env:SystemRoot\System32\sc.exe" delete $SvcName | Out-Null
    Start-Sleep -Seconds 1
}

# binPath needs the executable quoted - the path contains a space in the
# default install location, and sc.exe otherwise reads "C:\Program" as the
# binary and the rest as arguments.  The space after "binPath=" is required by
# sc.exe and is not a typo.
$bin = '"' + $svcExe + '"'
& "$env:SystemRoot\System32\sc.exe" create $SvcName binPath= $bin start= auto DisplayName= $SvcDisplay | Out-Null
if ($LASTEXITCODE -ne 0) { Say "sc create failed, exit $LASTEXITCODE"; exit 1 }

& "$env:SystemRoot\System32\sc.exe" description $SvcName $SvcDesc | Out-Null

# RECOVERY: restart twice, then leave it alone.  A daemon that cannot start is
# not made to work by trying for ever, and a restart loop hides the fault.
& "$env:SystemRoot\System32\sc.exe" failure $SvcName reset= 86400 actions= restart/5000/restart/15000/none/0 | Out-Null

Say "$SvcName created, start= auto"

Start-Service -Name $SvcName -ErrorAction SilentlyContinue
$deadline = (Get-Date).AddSeconds(60)
while ((Get-Date) -lt $deadline) {
    $s = Get-Svc
    if ($null -ne $s -and $s.Status -eq 'Running') { break }
    Start-Sleep -Milliseconds 500
}

$s = Get-Svc
if ($null -ne $s -and $s.Status -eq 'Running') {
    Say "$SvcName is running"
    # Judge on what it was for, not on the SCM's opinion: the service exists to
    # get sdwind up.  Reported rather than failed - the daemon can take a
    # moment longer than the service does.
    $w = (Get-Process sdwind -ErrorAction SilentlyContinue | Measure-Object).Count
    Say "sdwind processes: $w"
    exit 0
}

Say ("$SvcName did not reach Running (status {0})" -f $(if ($null -eq $s) { 'absent' } else { $s.Status }))
exit 1
