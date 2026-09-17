# install-service.ps1 - create, start and remove the SD Windows service
#
#   powershell -ExecutionPolicy Bypass -File install-service.ps1 -Install [-AppDir <dir>]
#   powershell -ExecutionPolicy Bypass -File install-service.ps1 -Remove
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
#
# THE RELAY ACCOUNT, 16 Sep 2026 - RELEASE_1.1 43.  The API's TLS relay
# (sdtlsrelay.exe, one per connection) runs as a BARE local account, "sdrelay":
# no group, no privilege, Low integrity - the Linux relay's "nobody".  sd mints
# its token with S4U on the service's own SeTcb, so the account needs no
# password anyone knows; the random one set here is never used and cannot be
# changed by the account.  It is created BEFORE the service starts, because the
# first API connection needs it, and removed with the service.
#
# WHAT KEEPS IT BARE.  New-LocalUser puts it in no group (Authenticated Users
# and Everyone are implicit, and are what let it read Program Files).  Four
# deny rights stop anyone signing in AS it - interactive, remote interactive,
# batch, service; NOT network, which is the logon type S4U performs.  The
# account is not disabled, because a disabled account cannot be S4U-logged-on
# either (STATUS_ACCOUNT_DISABLED).  It is deliberately NOT in sdusers: that
# group is what reaches the data tree, and a relay that parses hostile bytes
# must not.  Every step here is idempotent, like the rest of this script.

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

# A RECORD OF WHAT THE HIDDEN RUN SAID.  The installer runs this with
# runhidden and reads nothing back, so until 16 Sep 2026 a failure here left
# no trace anywhere - the relay account's creation failed on the first cycle
# and the only evidence was a verifier an hour later.  Appended, one run
# after another, beside reconcile-accounts.log; the data directory exists
# by the time the installer reaches this step.  Best effort: a machine where
# the transcript cannot start still gets its service.
$logPath = Join-Path $env:ProgramData 'SD\install-service.log'
try { Start-Transcript -Path $logPath -Append -Force | Out-Null } catch { }

function Say($m) { Write-Output "install-service: $m" }
Say ("{0}  {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $(if ($Install) { '-Install' } elseif ($Remove) { '-Remove' } else { '(no switch)' }))

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

# --- the relay account --------------------------------------------------------
#
# The name is SD_RELAY_ACCOUNT in gplsrc/sd_tls.h; sd asks LSA for it by name.
$RelayAccount = 'sdrelay'
$RelayDenies  = @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight',
                  'SeDenyBatchLogonRight', 'SeDenyServiceLogonRight')

# LsaAddAccountRights by SID - the same helper gplbld/probe-svcimp.ps1 carries.
# Rights are LSA policy, not a property of the account, so New-LocalUser cannot
# set them and Remove-LocalUser does not need to clear them (they go with the
# SID).  Returns a Win32 error, 0 = ok.
Add-Type -Language CSharp @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

public static class SdLsaRights {
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES {
        public int Length; public IntPtr RootDirectory; public IntPtr ObjectName;
        public uint Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService;
    }
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern uint LsaOpenPolicy(IntPtr SystemName, ref LSA_OBJECT_ATTRIBUTES oa, int access, out IntPtr handle);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern uint LsaAddAccountRights(IntPtr policy, byte[] sid, LSA_UNICODE_STRING[] rights, int count);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr policy);
    [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint status);

    const int POLICY_CREATE_ACCOUNT = 0x00000010;
    const int POLICY_LOOKUP_NAMES   = 0x00000800;

    public static int Add(string sidStr, string[] rights) {
        LSA_OBJECT_ATTRIBUTES oa = new LSA_OBJECT_ATTRIBUTES();
        oa.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
        IntPtr h;
        uint st = LsaOpenPolicy(IntPtr.Zero, ref oa, POLICY_CREATE_ACCOUNT | POLICY_LOOKUP_NAMES, out h);
        if (st != 0) return LsaNtStatusToWinError(st);
        try {
            SecurityIdentifier sid = new SecurityIdentifier(sidStr);
            byte[] b = new byte[sid.BinaryLength];
            sid.GetBinaryForm(b, 0);
            LSA_UNICODE_STRING[] arr = new LSA_UNICODE_STRING[rights.Length];
            for (int i = 0; i < rights.Length; i++) {
                arr[i].Buffer = Marshal.StringToHGlobalUni(rights[i]);
                arr[i].Length = (ushort)(rights[i].Length * 2);
                arr[i].MaximumLength = (ushort)((rights[i].Length + 1) * 2);
            }
            st = LsaAddAccountRights(h, b, arr, arr.Length);
            for (int i = 0; i < arr.Length; i++) Marshal.FreeHGlobal(arr[i].Buffer);
            return LsaNtStatusToWinError(st);
        } finally { LsaClose(h); }
    }
}
'@

function New-RandomPassword {
    # 32 characters from a CSPRNG.  Never used: S4U needs no password.  It only
    # has to satisfy New-LocalUser and the password policy, and be unguessable.
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%+=?'
    $s = ''
    foreach ($b in $bytes) { $s += $chars[$b % $chars.Length] }
    return $s
}

# New-LocalUser caps -Description at 48 CHARACTERS and refuses a longer one at
# parameter binding.  The first version of this was 88 characters long, the
# refusal was caught and swallowed, and the install completed with no account
# and no API - found by verify-relayidentity on the first cycle, 16 Sep 2026.
# test-installservice-units.ps1 now measures this literal's length.
$RelayDescription = 'SD API TLS relay. Do not sign in as this account'

# THE VERDICT IS A SCRIPT VARIABLE, NOT A RETURN VALUE.  Say writes to the
# pipeline, so a function that Says and then returns $false hands its caller an
# ARRAY - strings and a boolean - and "-not (array)" is $false.  That is how
# the swallowed refusal above still passed the gate.  The gate below also asks
# Windows whether the account exists rather than trusting this variable alone.
$script:RelayAccountOk = $false

function Install-RelayAccount {
    $u = Get-LocalUser -Name $RelayAccount -ErrorAction SilentlyContinue
    if ($null -eq $u) {
        $sec = ConvertTo-SecureString (New-RandomPassword) -AsPlainText -Force
        try {
            $u = New-LocalUser -Name $RelayAccount -Password $sec -PasswordNeverExpires `
                -AccountNeverExpires -UserMayNotChangePassword `
                -Description $RelayDescription -ErrorAction Stop
        } catch {
            Say "could not create the relay account ${RelayAccount}: $($_.Exception.Message)"
            return
        }
        Say "created the relay account $RelayAccount (no group, random unused password)"
    } else {
        Say "relay account $RelayAccount exists"
        if (-not $u.Enabled) {
            Enable-LocalUser -Name $RelayAccount
            Say "  it was disabled; enabled (S4U cannot log a disabled account on)"
        }
    }
    # Groups: it must be in NONE.  A previous install, or a hand, may have added
    # one; report and remove, because membership is what would widen the relay.
    foreach ($g in @(Get-LocalGroup)) {
        $m = Get-LocalGroupMember -Group $g.Name -ErrorAction SilentlyContinue |
             Where-Object { $_.SID -eq $u.SID }
        if ($m) {
            Remove-LocalGroupMember -Group $g.Name -Member $u.SID -ErrorAction SilentlyContinue
            Say "  removed $RelayAccount from $($g.Name)"
        }
    }
    $rc = [SdLsaRights]::Add($u.SID.Value, [string[]]$RelayDenies)
    if ($rc -ne 0) {
        Say "LsaAddAccountRights failed (win32=$rc) denying logon to $RelayAccount"
        return
    }
    Say "  denied interactive, remote interactive, batch and service logon"
    $script:RelayAccountOk = $true
}

function Remove-RelayAccount {
    $u = Get-LocalUser -Name $RelayAccount -ErrorAction SilentlyContinue
    if ($null -eq $u) { Say "no relay account $RelayAccount; nothing to remove"; return }
    Remove-LocalUser -Name $RelayAccount -ErrorAction SilentlyContinue
    if (Get-LocalUser -Name $RelayAccount -ErrorAction SilentlyContinue) {
        Say "could not remove the relay account $RelayAccount"
    } else {
        Say "relay account $RelayAccount removed"
    }
}

# --- remove ----------------------------------------------------------------
#
# IDEMPOTENT, like the rest of the installer's helpers: an absent service is
# success, because the uninstaller must not fail on a machine where the service
# was never created or was removed by hand.
if ($Remove) {
    $s = Get-Svc
    if ($null -eq $s) { Say "no $SvcName service; nothing to remove"; Remove-RelayAccount; exit 0 }

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
    Remove-RelayAccount
    exit 0
}

# --- install ---------------------------------------------------------------
if (-not (Test-Path $svcExe)) {
    Say "no $svcExe - was the install complete?"
    exit 2
}

# The relay account BEFORE the service: the service's first API connection
# asks LSA for it.  The gate reads the STATE - does Windows have the account -
# as well as the verdict, because the first cycle showed a verdict that lied
# (see above).  A missing account is reported and makes this exit 1, but the
# SERVICE IS STILL CREATED: without it nothing in SD runs, with it only the API
# is refused, and each refusal says why in the SD error log ("cannot log the
# relay account sdrelay on").  install-service.log holds this line.
Install-RelayAccount
$relayMissing = (-not $script:RelayAccountOk) -or
                (-not (Get-LocalUser -Name $RelayAccount -ErrorAction SilentlyContinue))
if ($relayMissing) {
    Say "THE RELAY ACCOUNT $RelayAccount IS NOT IN PLACE - every API connection will be refused until it is (rerun: install-service.ps1 -Install, elevated)"
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
    if ($relayMissing) { Say 'exit 1: the service runs but the relay account is missing (above)'; exit 1 }
    exit 0
}

Say ("$SvcName did not reach Running (status {0})" -f $(if ($null -eq $s) { 'absent' } else { $s.Status }))
exit 1
