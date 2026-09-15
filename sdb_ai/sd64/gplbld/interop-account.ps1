<#
.SYNOPSIS
    Create (or remove) a throwaway non-administrator API account on THIS Windows
    server so a remote SD client can log in over TLS, and open the firewall for
    it.  The Windows half of the RELEASE_1.1 41 interop witness; the parallel to
    SD Core for Linux's gplbld/interop-account.sh.

.DESCRIPTION
    THE REVERSE OF THE RUN ALREADY DONE.  15 Sep 2026 a Windows client logged in
    to the Linux server (RELEASE_1.1 41).  The reverse - a Linux client against
    this Windows server - needs a non-administrator account here with an API
    credential, and it needs the firewall open so the other machine can reach
    port 4243 at all.  This does both, and -Remove takes both away again.

    IT DOES NOT SET THE PASSWORD ITSELF, AND THAT IS DELIBERATE.  MODIFY.PASSWORD
    is run interactively (finish-install.ps1's pattern) so the person at the
    keyboard types it with echo off; it never reaches this script, the command
    line, or a mailbox.  The owner then hands it to the other agent directly, as
    the mailbox rules require.

    NON-ADMINISTRATOR, ON PURPOSE.  An SD administrator is refused over the API
    from any other machine (apisrvr's remote-admin refusal), so an admin account
    could not exercise the remote path even if it had a credential.  The account
    is PROGRAMMER tier with API access (member of sdapi via the API keyword) and
    is asserted NOT to be a Windows Administrator - the same control
    verify-scramlogin.ps1 uses.

    IT CHANGES THE INSTALLED SYSTEM.  It creates a Windows + SD account and adds
    a firewall rule; -Remove deletes the account, its user profile and group,
    clears its $cred record and removes the firewall rule.  The SD ACCOUNTS and
    $CRED register rows are left by CREATE.ACCOUNT's convention (as
    verify-scramlogin leaves its own) - -Remove clears $cred but a leftover
    register row is removed with DELETE.ACCOUNT.

    NOT SHIPPED.  On assert-current.ps1's $neverShipped list, like the verifiers
    and probes.

.PARAMETER Create
    Make the account and open the firewall, then prompt for the password.

.PARAMETER Remove
    Tear it all down: account, profile, group, $cred record, firewall rule.

.PARAMETER Name
    The throwaway account name.  Default zzinteropw (the Linux side used
    zzinterop; the trailing w keeps them distinct in a shared write-up).

.PARAMETER Port
    The API port.  4243 is the shipped default and what the listener uses.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\interop-account.ps1 -Create
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\interop-account.ps1 -Remove
#>

# Exit 0 done, 1 a step failed, 2 could not run (not elevated, tree stale, name
# clash, or neither -Create nor -Remove).

[CmdletBinding()]
param(
    [switch] $Create,
    [switch] $Remove,
    [string] $Name = 'zzinteropw',
    [int]    $Port = 4243
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$upper  = $Name.ToUpper()

function Say($m)  { Write-Host $m }
function Step($m) { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Die($m, $code) { Write-Host ''; Write-Host $m -ForegroundColor Red; exit $code }

# Drives an SD session from SDSYS on stdin.  Verbatim shape from
# verify-scramlogin.ps1's Invoke-SD - a blank first line absorbs the BOM, TERM
# stops pagination, OFF ends it, and the escape strip removes erase-line codes.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# ---------------------------------------------------------------------------
if (-not ($Create -xor $Remove)) {
    Die 'Pass exactly one of -Create or -Remove.' 2
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Die 'Run this from an ELEVATED PowerShell - it creates a Windows account and adds a firewall rule.' 2
}

# THE CYCLE RULE.  Anything that touches the install asserts the tree matches
# source first, or the result describes a tree that no longer exists.
Step 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Die 'assert-current refuses - run gplbld/cycle.ps1 first.' 2 }

if (-not (Test-Path -LiteralPath $sdExe)) { Die "No installed sd.exe at $sdExe." 2 }

$accRec  = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $upper)
$credRec = Join-Path $env:ProgramData ('SD\sdsys\$cred\' + $upper)

# ===========================================================================
if ($Remove) {
    Step "Removing the interop account $Name and its firewall rule"

    # DELETE.ACCOUNT takes the name and nothing else (verify-apiidentity's
    # 24 Aug lesson: no trailing keyword).  Left silent if it was never there.
    if (Test-Path -LiteralPath $accRec) {
        $out = Invoke-SD @("DELETE.ACCOUNT $upper")
        Say "  DELETE.ACCOUNT $upper run"
    } else {
        Say "  no ACCOUNTS record $upper - nothing to delete in SD"
    }

    if (Get-LocalUser -Name $Name -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $Name
        Say "  removed Windows account $Name"
    }
    $prof = Join-Path $env:ProgramData ('SD\user_accounts\' + $Name)
    if (Test-Path -LiteralPath $prof) {
        Remove-Item -LiteralPath $prof -Recurse -Force -ErrorAction SilentlyContinue
        Say "  removed profile $prof"
    }
    $grp = 'sdu_' + $Name
    if (Get-LocalGroup -Name $grp -ErrorAction SilentlyContinue) {
        Remove-LocalGroup -Name $grp
        Say "  removed group $grp"
    }
    # Clear the credential so no login survives the account (Linux clears its
    # $cred on --remove for the same reason).
    if (Test-Path -LiteralPath $credRec) {
        Remove-Item -LiteralPath $credRec -Force -ErrorAction SilentlyContinue
        Say "  cleared `$cred record $upper"
    }

    Step 'Removing the firewall rule'
    & (Join-Path $Gplbld 'api-firewall.ps1') -Remove -Port $Port
    Say ''
    Say "interop-account: removed.  The API listener stays up (APIPORT is unchanged);"
    Say "only the firewall rule and this account are gone."
    exit 0
}

# ===========================================================================
# -Create
if (Get-LocalUser -Name $Name -ErrorAction SilentlyContinue) {
    Die "$Name already exists as a Windows account.  Use -Name for a fresh one, or -Remove first." 2
}
if (Test-Path -LiteralPath $accRec) {
    Die "$upper is still in the ACCOUNTS register.  Remove it with -Remove (DELETE.ACCOUNT) first." 2
}

Step "Creating the throwaway PROGRAMMER + API account $Name"

# CREATE.ACCOUNT USER also makes a Windows account and needs a Windows password
# on stdin twice.  It is generated and never used by the interop - the API
# login uses the SD credential set below, not this - so it is not printed.
Add-Type -AssemblyName System.Web
$winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6)

$out = Invoke-SD @("CREATE.ACCOUNT USER $Name PROGRAMMER API", $winPw, $winPw)
if (-not (Test-Path -LiteralPath $accRec)) {
    Write-Host $out
    Die 'CREATE.ACCOUNT did not register the account.' 1
}
Say "  account $Name created (ACCOUNTS record present)"

# NON-ADMINISTRATOR CONTROL, as verify-scramlogin/apiidentity: CREATE.ACCOUNT
# does not make administrators, but it is checked rather than assumed - an
# administrator would be refused over the API from a remote box anyway, so a
# run that produced one would test nothing.
$admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name })
if ($admins -match "\\$Name$") {
    Die "$Name is a Windows Administrator - it would be refused over the API from another machine.  Removing it is safest: rerun with -Remove." 1
}
Say "  $Name is NOT a Windows Administrator - the remote API path is reachable for it"

# ---------------------------------------------------------------------------
Step "Opening the firewall for port $Port (any address)"

# api-firewall.ps1 -Open allows any remote address, which matches the Linux
# side's posture for this run (ufw off there).  It is a LAN test and -Remove
# closes it again; the owner is told so below.
& (Join-Path $Gplbld 'api-firewall.ps1') -Open -Port $Port
if ($LASTEXITCODE -ne 0) { Die 'api-firewall.ps1 -Open failed - the remote box could not reach this one.' 1 }

# ---------------------------------------------------------------------------
Step "Confirming the API listener is up on $Port"

$listen = @(netstat -an | Select-String 'LISTENING' |
            Where-Object { $_ -match (':' + $Port + '\s') })
foreach ($l in $listen) { Say ('   ' + $l.ToString().Trim()) }
if ($listen.Count -eq 0) {
    Die "Nothing is listening on $Port.  Enable it with api-listener.ps1 -On and restart SD, then rerun." 1
}
Say "  a listener is up on $Port"

# ---------------------------------------------------------------------------
Step "Set the API password for $Name  (you type it - it is not stored here)"

Say ''
Say "SD will now ask for a new password for $upper.  Type it (twice), with echo off."
Say "It is the password the Linux client will use.  Hand it to the Linux side"
Say "directly - never in the mailbox."
Say ''

# INTERACTIVE, finish-install.ps1's pattern: -NoNewWindow -Wait so sd inherits
# this console and the person types with echo off.  The password never touches
# this script.
try {
    $null = Start-Process -FilePath $sdExe `
                -ArgumentList '-QUIET','MODIFY.PASSWORD',$upper `
                -NoNewWindow -Wait -PassThru -ErrorAction Stop
    Write-Host ''
} catch {
    Die ('SD could not be started for MODIFY.PASSWORD: ' + $_.Exception.Message) 1
}

# DID A PASSWORD ACTUALLY GET SET?  finish-install.ps1's check: a $cred record
# for the account means MODIFY.PASSWORD wrote one.  Pressing Enter on an empty
# password leaves none - a legitimate decline, reported rather than failed.
if ((Test-Path -LiteralPath (Join-Path $env:ProgramData 'SD\sdsys\$cred')) -and
    (-not (Test-Path -LiteralPath $credRec))) {
    Write-Host ("No password was set for $upper - the account cannot log in until one is.") -ForegroundColor Yellow
    Write-Host ("Rerun MODIFY.PASSWORD, or -Remove and start again.") -ForegroundColor Yellow
    exit 1
}
Say "  `$cred record for $upper is present - a password is set"

# ---------------------------------------------------------------------------
# What to hand to the Linux side.  The LAN address is read, not assumed.
$ip = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue |
        Where-Object { $_.IPAddress -like '192.168.*' } |
        ForEach-Object { $_.IPAddress })
$addr = if ($ip.Count -gt 0) { $ip -join ', ' } else { '(no 192.168.* address found - read it with ipconfig)' }

Say ''
Say '=== interop account ready for the Linux client ============================'
Say "  host    : $addr    port $Port"
Say "  user    : $Name"
Say "  account : $upper"
Say "  password: the one you just typed - hand it to the Linux side directly"
Say ''
Say "  Disposable: run this with -Remove when the interop run is done."
Say "  The firewall is OPEN to any address until then."
exit 0
