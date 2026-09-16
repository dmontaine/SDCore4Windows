<#
.SYNOPSIS
    Drives probe-svcimp.c: can a VIRTUAL SERVICE ACCOUNT adopt a broker-minted
    token?  RELEASE_1.1 43's gate, owner's option 1 (16 Sep 2026).

.DESCRIPTION
    43's plan (option 3c) runs the service, sdwind, the relay and each session
    as NT SERVICE\SD, with a small LocalSystem broker doing the two privileged
    things.  Its load-bearing claim is that a session under a virtual service
    account can impersonate a broker-minted token and adopt it across fork()
    so files come out owned by the USER.

    ***HALF OF THAT IS ALREADY MEASURED AND IS NOT RE-ASKED HERE.***
    probe-impfork.c's Q4, 24 Aug 2026 (HISTORY.md:4523), settled the mechanism
    from a LocalSystem caller: the bare CW_SET_EXTERNAL_TOKEN LOSES the
    identity, and register-then-seteuid CARRIES it, file owned by the user.
    The only new variable here is THE CALLER'S ACCOUNT.

    WHY A THROWAWAY SERVICE.  Only the SCM can put a process under a virtual
    service account - runas and schtasks cannot - so the worker is a service
    named sdprobe running as NT SERVICE\sdprobe.  The real SD service is never
    touched, which is what the owner chose over reconfiguring it.

    THE SCM WILL REPORT 1053 AND THAT IS EXPECTED, NOT A FAILURE.  The worker
    is an ordinary program, not a service that answers the SCM, so after ~30 s
    the SCM gives up waiting and reports "did not respond in a timely
    fashion".  The process runs regardless and finishes well inside that
    window; the verdict is read from its log, never from sc's exit code.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File probe-svcimp.ps1 -Account Don
#>

# Exit 0 the question was answered, 1 the claim was falsified, 2 could not run.

[CmdletBinding()]
param(
    [string] $Account = $env:USERNAME,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Exe     = Join-Path $Gplbld 'probe-svcimp.exe'
$MsysDll = 'C:\msys64\usr\bin\msys-2.0.dll'
$Svc     = 'sdprobe'
$Task    = 'sdprobebroker'
$Stage   = 'C:\ProgramData\sdprobe-run'

# 16 Sep 26 (RELEASE_1.1 43).  Grant history, most recent last:
#   run 1  none granted            -> seteuid 1314, account lacked the pair
#   run 2  the mild pair granted   -> seteuid 1314 (pair present but OFF)
#   run 3  the pair granted+ENABLED -> seteuid 1314 anyway - the pair is not it
#   run 4  + SeTcb  <- THIS RUN, the CONFIRMATION experiment
# The pair (SeAssignPrimaryToken + SeIncreaseQuota) is the standard "launch as
# another user" pair and, even enabled, did not clear 1314.  By elimination the
# missing right is SeTcb (LocalSystem, the proven Q4 run, holds it and does NOT
# hold SeCreateToken).  Adding it here answers ONE question: does the runtime's
# seteuid need SeTcb?  If yes, option 3c collapses into 3a (SeTcb on the session
# = SYSTEM by another name) and is dead as designed.  Granted to the account SID
# before the worker token is minted at sc start, REVOKED in cleanup.
$Privs   = @('SeAssignPrimaryTokenPrivilege', 'SeIncreaseQuotaPrivilege', 'SeTcbPrivilege')

# LsaAddAccountRights / LsaRemoveAccountRights by SID.  sc privs can only
# RESTRICT a service token to a subset it already holds, so it cannot add one;
# the grant has to go on the account's LSA rights, which the SCM reads when it
# mints the service token at start.  Returns the Win32 error (0 = ok) so the
# caller can refuse rather than measure a grant that never landed.
Add-Type -Language CSharp @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;

public static class LsaRights {
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
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern uint LsaRemoveAccountRights(IntPtr policy, byte[] sid, bool allRights, LSA_UNICODE_STRING[] rights, int count);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr policy);
    [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint status);

    const int POLICY_CREATE_ACCOUNT = 0x00000010;
    const int POLICY_LOOKUP_NAMES   = 0x00000800;

    static LSA_UNICODE_STRING S(string s) {
        LSA_UNICODE_STRING u = new LSA_UNICODE_STRING();
        u.Buffer = Marshal.StringToHGlobalUni(s);
        u.Length = (ushort)(s.Length * 2);
        u.MaximumLength = (ushort)((s.Length + 1) * 2);
        return u;
    }
    static byte[] SidBytes(string sidStr) {
        SecurityIdentifier sid = new SecurityIdentifier(sidStr);
        byte[] b = new byte[sid.BinaryLength];
        sid.GetBinaryForm(b, 0);
        return b;
    }
    static IntPtr Open() {
        LSA_OBJECT_ATTRIBUTES oa = new LSA_OBJECT_ATTRIBUTES();
        oa.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
        IntPtr h;
        uint st = LsaOpenPolicy(IntPtr.Zero, ref oa, POLICY_CREATE_ACCOUNT | POLICY_LOOKUP_NAMES, out h);
        if (st != 0) throw new Exception("LsaOpenPolicy win32=" + LsaNtStatusToWinError(st));
        return h;
    }
    static int Apply(string sidStr, string[] rights, bool remove) {
        IntPtr h = Open();
        try {
            LSA_UNICODE_STRING[] arr = new LSA_UNICODE_STRING[rights.Length];
            for (int i = 0; i < rights.Length; i++) arr[i] = S(rights[i]);
            uint st = remove ? LsaRemoveAccountRights(h, SidBytes(sidStr), false, arr, arr.Length)
                             : LsaAddAccountRights(h, SidBytes(sidStr), arr, arr.Length);
            for (int i = 0; i < arr.Length; i++) Marshal.FreeHGlobal(arr[i].Buffer);
            return LsaNtStatusToWinError(st);
        } finally { LsaClose(h); }
    }
    public static int Add(string sidStr, string[] rights)    { return Apply(sidStr, rights, false); }
    public static int Remove(string sidStr, string[] rights) { return Apply(sidStr, rights, true);  }
}
'@

function Say($m, $ForegroundColor) {
    if ($ForegroundColor) { Write-Host $m -ForegroundColor $ForegroundColor } else { Write-Host $m }
}
function Step($m)   { Write-Host ''; Write-Host "== $m" -ForegroundColor Cyan }
function Refuse($m) { Write-Host ''; Write-Host "COULD NOT RUN: $m" -ForegroundColor Yellow; Cleanup; exit 2 }
function Fail($m)   { Write-Host ''; Write-Host "FALSIFIED: $m" -ForegroundColor Red; Cleanup; exit 1 }

function Cleanup {
    if ($script:Keeping) { Say "  -Keep: leaving $Svc and $Stage in place"; return }
    # Revoke first, while the SID is still known, so no standing policy change
    # outlives the probe.  Best-effort like the rest of Cleanup.
    if ($script:GrantedSid) {
        try {
            $rc = [LsaRights]::Remove($script:GrantedSid, $Privs)
            Say ("  revoked privileges: " + $(if ($rc -eq 0) { 'ok' } else { "win32=$rc" }))
        } catch { }
    }
    # EVERYTHING HERE IS BEST-EFFORT AND NOTHING MAY THROW.  Cleanup is called
    # from Refuse and Fail, so a teardown that raises would abandon the very
    # litter it exists to remove - and with $ErrorActionPreference='Stop' a
    # native command's stderr is enough to do that (PowerShell 5.1 wraps it in
    # a NativeCommandError).  Hence try/catch and no stream redirection.
    # Asked for only when it is there, so a teardown after an early refusal
    # does not print "The system cannot find the file specified" and read as a
    # fault of its own.
    try {
        $q = & sc.exe query $Svc
        if ($q -and ($q | Select-String -Quiet 'SERVICE_NAME')) { $null = & sc.exe delete $Svc }
    } catch { }
    try {
        $t = & schtasks.exe /query /tn $Task
        if ($t) { $null = & schtasks.exe /delete /tn $Task /f }
    } catch { }
    try {
        if (Test-Path -LiteralPath $Stage) {
            Remove-Item -LiteralPath $Stage -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch { }
}
$script:Keeping = [bool]$Keep
$script:GrantedSid = $null   # set once the privileges are granted, so Cleanup revokes them

# Any UNEXPECTED terminating error must still revoke the grant and remove the
# service - a run that dies between grant and revoke would otherwise leave SeTcb
# on the account.  Refuse/Fail clean up on the planned exits; this covers the
# unplanned ones.  ('exit' is not a terminating error, so it does not trip this.)
trap {
    Write-Host ''
    Write-Host "UNEXPECTED ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Cleanup
    exit 3
}

# ---------------------------------------------------------------------------
Step 'Preconditions'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
Say "  running as        : $($id.Name)"
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host ''; Write-Host 'COULD NOT RUN: this needs an ELEVATED PowerShell - it creates a service and a SYSTEM task.' -ForegroundColor Yellow
    exit 2
}
if (-not (Test-Path -LiteralPath $Exe))     { Write-Host "COULD NOT RUN: no $Exe - build it first (see the .c header)." -ForegroundColor Yellow; exit 2 }
if (-not (Test-Path -LiteralPath $MsysDll)) { Write-Host "COULD NOT RUN: no $MsysDll - the worker cannot start without it." -ForegroundColor Yellow; exit 2 }
if (-not (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue)) {
    Write-Host "COULD NOT RUN: '$Account' is not a local account to mint a token for." -ForegroundColor Yellow; exit 2
}

# A LEFTOVER FROM A PREVIOUS RUN IS REFUSED RATHER THAN REUSED: its binary and
# its account would be whatever that run left, and the verdict would describe
# something nobody chose.
$qOut = $null
try { $qOut = & sc.exe query $Svc } catch { $qOut = $null }
if ($qOut -and ($qOut | Select-String -Quiet 'SERVICE_NAME')) {
    Write-Host "COULD NOT RUN: a '$Svc' service already exists.  Remove it first:  sc.exe delete $Svc" -ForegroundColor Yellow
    exit 2
}
Say "  target account    : $Account"
Say "  worker will run as: NT SERVICE\$Svc"

# ---------------------------------------------------------------------------
Step 'Staging the binary where a service account can read it'

if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
$null = New-Item -ItemType Directory -Path $Stage -Force
Copy-Item -LiteralPath $Exe     -Destination $Stage -Force
Copy-Item -LiteralPath $MsysDll -Destination $Stage -Force

# SYSTEM can be granted now - it always resolves.  The SERVICE account cannot,
# and that ordering is the whole of the next section.
$null = & icacls.exe $Stage /grant "*S-1-5-18:(OI)(CI)F" /T
if ($LASTEXITCODE -ne 0) { Refuse "icacls could not grant SYSTEM on $Stage." }
Say "  staged            : $Stage (SYSTEM granted; the service account follows)"

# ---------------------------------------------------------------------------
Step 'Creating the throwaway service under its virtual account'

$bin = '"' + (Join-Path $Stage 'probe-svcimp.exe') + '" --worker "' + $Stage + '" ' + $Account
$out = & sc.exe create $Svc binPath= $bin obj= "NT SERVICE\$Svc" start= demand
Say ("  sc create         : " + ($out -join ' ').Trim())
if ($LASTEXITCODE -ne 0) { Refuse "sc create failed - $($out -join ' ')" }

# ***THE GRANT COMES AFTER THE CREATE, AND IT COST TWO RUNS TO LEARN WHY.***
# A virtual service account is not a principal the LSA can map until its
# service exists.  Measured 16 Sep 2026, both spellings refused before the
# create with "No mapping between account names and security IDs was done":
# the NAME "NT SERVICE\sdprobe", and then the SID form "*S-1-5-80-..." taken
# from sc showsid - which DERIVES the SID happily without the service (it is
# a hash of the name), so having the right SID is not the same as having a
# principal.  sc create is what registers it.  The service is created but NOT
# STARTED here, so the grant is still in place before anything runs as that
# account, which is what the worker needs.
$null = & icacls.exe $Stage /grant "NT SERVICE\${Svc}:(OI)(CI)F" /T
if ($LASTEXITCODE -ne 0) { Refuse "icacls could not grant NT SERVICE\$Svc on $Stage even after sc create." }
Say "  granted           : NT SERVICE\$Svc on $Stage"

# ---------------------------------------------------------------------------
Step 'Granting the adopt privileges to the service account (before it starts)'

# The SID, not the name: LsaAddAccountRights takes a SID, and a virtual service
# account's SID is a hash of its name that sc derives without the service even
# existing - but it does exist here, so this is the plain read.
$sid = $null
foreach ($ln in (& sc.exe showsid $Svc)) {
    if ($ln -match 'SERVICE SID:\s*(S-1-\S+)') { $sid = $Matches[1]; break }
}
if (-not $sid) { Refuse "could not read the service SID from 'sc showsid $Svc'." }
Say "  service SID       : $sid"

# Set BEFORE the add so a partial grant is still revoked by Cleanup.
$script:GrantedSid = $sid
$rc = [LsaRights]::Add($sid, $Privs)
if ($rc -ne 0) {
    Refuse "LsaAddAccountRights (win32=$rc) granting $($Privs -join ', ') - the retest would measure the wrong thing."
}
Say "  granted privileges: $($Privs -join ', ')"
Say "  (revoked in cleanup; the worker token picks them up at sc start)"

# NOT -Wait: sc start BLOCKS for the SCM's full 30 s timeout on a program that
# does not answer the SCM, and the broker cannot start until the worker has
# published its pid.
Start-Process -FilePath 'sc.exe' -ArgumentList @('start', $Svc) -NoNewWindow | Out-Null
Say '  sc start          : launched (1053 from the SCM is expected - see the header)'

$pidFile = Join-Path $Stage 'worker.pid'
$deadline = (Get-Date).AddSeconds(20)
while (-not (Test-Path -LiteralPath $pidFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 500 }
if (-not (Test-Path -LiteralPath $pidFile)) {
    Say ''
    if (Test-Path -LiteralPath (Join-Path $Stage 'worker.log')) {
        Say '  --- worker.log ---'; Get-Content -LiteralPath (Join-Path $Stage 'worker.log') | ForEach-Object { Say "  | $_" }
    }
    Refuse 'the worker never published a pid - it did not start, or it refused (read worker.log above).'
}
Say "  worker pid        : $((Get-Content -LiteralPath $pidFile -TotalCount 1).Trim())"

# ---------------------------------------------------------------------------
Step 'Running the broker as LocalSystem'

$btr = '"' + (Join-Path $Stage 'probe-svcimp.exe') + '" --broker "' + $Stage + '" ' + $Account
$out = & schtasks.exe /create /tn $Task /tr $btr /sc once /st 23:59 /ru SYSTEM /rl HIGHEST /f
if ($LASTEXITCODE -ne 0) { Refuse "schtasks /create failed - $($out -join ' ')" }
$out = & schtasks.exe /run /tn $Task
if ($LASTEXITCODE -ne 0) { Refuse "schtasks /run failed - $($out -join ' ')" }
Say '  broker            : started as SYSTEM'

$wLog = Join-Path $Stage 'worker.log'
$bLog = Join-Path $Stage 'broker.log'
$deadline = (Get-Date).AddSeconds(40)
while ((Get-Date) -lt $deadline) {
    if ((Test-Path -LiteralPath $wLog) -and
        (Select-String -LiteralPath $wLog -Pattern 'WORKER DONE|REFUSED' -Quiet)) { break }
    Start-Sleep -Milliseconds 500
}

# ---------------------------------------------------------------------------
Step 'What each side did'

foreach ($pair in @(@('broker', $bLog), @('worker', $wLog))) {
    Say ''
    Say "  --- $($pair[0]).log ---"
    if (Test-Path -LiteralPath $pair[1]) {
        Get-Content -LiteralPath $pair[1] | ForEach-Object { Say "  | $_" }
    } else { Say '  | <absent>' }
}

if (-not (Test-Path -LiteralPath $wLog)) { Refuse 'no worker log at all.' }
$w = Get-Content -LiteralPath $wLog -Raw
if ($w -match 'REFUSED') { Refuse 'the worker refused - its reason is above.' }

function OwnerOf($text, $marker) {
    $m = [regex]::Match($text, [regex]::Escape($marker) + '\s+created file owned by (.+)')
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return ''
}
$plain   = OwnerOf $w '[plain fork child]'
$adopted = OwnerOf $w '[adopted child]'

Step 'Verdict'
Say "  plain fork   file owned by : $(if ($plain)   { $plain }   else { '<not reported>' })"
Say "  adopted fork file owned by : $(if ($adopted) { $adopted } else { '<not reported>' })"

if (-not $plain -or -not $adopted) { Refuse 'one of the two children did not report an owner.' }

# THE CONTROL MUST REPRODUCE THE DEFECT FIRST.  If a plain fork already writes
# a user-owned file then this machine is not in the state the claim is about,
# and a pass below would mean nothing - probe-impfork's row 1 exists for the
# same reason.
if ($plain -like "*\$Account") {
    Refuse "the CONTROL did not reproduce the defect: a plain fork already wrote a file owned by $plain.  Nothing below would be evidence."
}
Say "  control      : plain fork lost the identity ($plain) - the defect is reproduced"

if ($adopted -like "*\$Account") {
    Say ''
    Say "ADOPTED: the worker's fork wrote a file owned by $adopted." -ForegroundColor Green
    Say "  Worker ran as NT SERVICE\$Svc, granted+enabled: $($Privs -join ', ')."
    Say "  READ AGAINST WHAT WAS GRANTED: a pass that needed SeTcb means the"
    Say "  runtime needs SeTcb for the adopt, so option 3c collapses into 3a"
    Say "  (SYSTEM by another name).  Only a pass with the MILD PAIR ALONE would"
    Say "  open 3c's gate."
    Cleanup
    exit 0
}

Fail ("the adopted child wrote a file owned by $adopted, not by $Account.  " +
      "That is 43's stated falsified-if: option 3c does not close the gap as planned.")
