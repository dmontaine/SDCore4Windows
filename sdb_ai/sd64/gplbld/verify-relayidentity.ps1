<#
.SYNOPSIS
    Does the API's TLS relay run as the bare account, at Low integrity, with no
    privilege - and go away when the connection does?  RELEASE_1.1 43.

.DESCRIPTION
    The finding (15 Sep 2026, an AI review of a project using SD): "the
    Windows TLS relay still runs as LocalSystem."  It did - sd_tlssrv.c
    fork()ed it.  The fix spawns sdtlsrelay.exe per connection under an
    S4U-minted token for the local account sdrelay, every privilege removed,
    integrity Low (win32relay.c).  test-tlsrelay-units.py proves the relay
    relays; THIS proves WHO it runs as, on the install, which nothing
    unelevated can see (another account's token is not readable from an
    ordinary shell - PROJECT_STATUS HANDOFF 78's "121 processes unreadable").

    What it does: opens one API connection with gplbld/relay-hold.py (TLS
    handshake, ACK, then a 25 s hold - no login, none is needed), and while
    it is held reads the one new sdtlsrelay.exe's owner, integrity, privilege
    count, parent and module list.  Then it lets go and requires the relay
    gone.

    THE ROWS THAT ARE THE POINT.  Owner sdrelay and integrity Low are the
    split itself; privilege count 0 is what "bare" means; the parent being
    sd.exe running as SYSTEM is the CONTROL that the drop happened at the
    spawn and not to the session (the session keeps SeTcb, by design).  No
    msys-2.0.dll in the relay is the runtime rule stage.py also enforces.

    THE NULL CASE IS REFUSED TWICE.  The hold must print "HELD <binding>", a
    line only a completed handshake produces, or nothing below is measured;
    and the relay count must rise by exactly one while it is held, so a stale
    relay from an earlier run cannot be the one inspected.

    ELEVATED, because reading another account's process token needs it.  No
    prefix and no account of its own: it creates nothing but a connection.
    Enables APIPORT and restarts SD if the listener is down, and puts sd.conf
    back, exactly as verify-apiname does.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 could not run.
#>

param(
    [int]    $Port = 4243,
    [int]    $HoldSeconds = 25,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Hold    = Join-Path $Gplbld 'relay-hold.py'
$conf    = Join-Path $env:ProgramData 'SD\sd.conf'
$backup  = $conf + '.before-relayidentity'
$SvcName = 'SD'
$Account = 'sdrelay'                     # SD_RELAY_ACCOUNT, gplsrc/sd_tls.h
$RelayName = 'sdtlsrelay'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log = Join-Path $logDir ('verify-relayidentity-' + $stamp + '.log')
$holdOut = Join-Path $logDir ('relay-hold-' + $stamp + '.out')
$holdErr = Join-Path $logDir ('relay-hold-' + $stamp + '.err')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results = New-Object System.Collections.ArrayList
$failed  = $false
$portAddedByUs = $false
$holdProc = $null

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

function Fail($msg) {
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

# PRE_RELEASE_FIXES 151: a precondition refusal is exit 2, unless a decisive
# check has already failed - then it stays 1.
function Refuse($msg) {
    if ($script:failed) {
        Fail ($msg + '  (a decisive check had already FAILED, so this is exit 1, not 2)')
    }
    Write-Host ''
    Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

function Stop-SD {
    if (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) {
        & "$env:SystemRoot\System32\sc.exe" stop $SvcName | Out-Null
    }
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    return -not [bool](Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue)
}

function Start-SD {
    & "$env:SystemRoot\System32\sc.exe" start $SvcName | Out-Null
    $deadline = (Get-Date).AddSeconds(45)
    while (-not (Get-Process -Name sdwind -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    return [bool](Get-Process -Name sdwind -ErrorAction SilentlyContinue)
}

# The token questions Get-Process cannot answer: integrity level and the
# number of privileges.  OpenProcess with PROCESS_QUERY_LIMITED_INFORMATION is
# what an elevated caller may do to any process; TOKEN_QUERY reads the label.
Add-Type -Language CSharp @'
using System;
using System.Runtime.InteropServices;

public static class SdTokenPeek {
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern IntPtr OpenProcess(int access, bool inherit, int pid);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool OpenProcessToken(IntPtr proc, int access, out IntPtr token);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern bool GetTokenInformation(IntPtr token, int cls, IntPtr info, int len, out int need);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern IntPtr GetSidSubAuthorityCount(IntPtr sid);
    [DllImport("advapi32.dll", SetLastError=true)]
    static extern IntPtr GetSidSubAuthority(IntPtr sid, int index);
    [DllImport("kernel32.dll")] static extern bool CloseHandle(IntPtr h);

    const int PROCESS_QUERY_LIMITED_INFORMATION = 0x1000;
    const int TOKEN_QUERY = 0x0008;
    const int TokenPrivileges = 3;
    const int TokenIntegrityLevel = 25;

    // Returns "integrity=<rid> privileges=<n>" or "error <what> <win32>".
    public static string Peek(int pid) {
        IntPtr p = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid);
        if (p == IntPtr.Zero) return "error OpenProcess " + Marshal.GetLastWin32Error();
        IntPtr t;
        if (!OpenProcessToken(p, TOKEN_QUERY, out t)) {
            int e = Marshal.GetLastWin32Error(); CloseHandle(p);
            return "error OpenProcessToken " + e;
        }
        try {
            int need;
            IntPtr buf = Marshal.AllocHGlobal(8192);
            try {
                if (!GetTokenInformation(t, TokenIntegrityLevel, buf, 8192, out need))
                    return "error GetTokenInformation(integrity) " + Marshal.GetLastWin32Error();
                IntPtr sid = Marshal.ReadIntPtr(buf);            // TOKEN_MANDATORY_LABEL.Label.Sid
                int count = Marshal.ReadByte(GetSidSubAuthorityCount(sid));
                int rid = Marshal.ReadInt32(GetSidSubAuthority(sid, count - 1));
                if (!GetTokenInformation(t, TokenPrivileges, buf, 8192, out need))
                    return "error GetTokenInformation(privileges) " + Marshal.GetLastWin32Error();
                int privs = Marshal.ReadInt32(buf);               // TOKEN_PRIVILEGES.PrivilegeCount
                return "integrity=" + rid + " privileges=" + privs;
            } finally { Marshal.FreeHGlobal(buf); }
        } finally { CloseHandle(t); CloseHandle(p); }
    }
}
'@

function Get-RelayPids {
    return @(Get-Process -Name $RelayName -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Id)
}

# ---------------------------------------------------------------------------
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Refuse 'Run this from an ELEVATED PowerShell - it reads another account''s process token.'
}

& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current says the install is not current. Cycle first.' }

if (-not (Test-Path -LiteralPath $Hold)) { Refuse "no $Hold beside this script." }
$pyCmd = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not $pyCmd) { Refuse 'python is not on PATH - relay-hold.py is the API client this verifier drives.' }
$Python = $pyCmd.Source
Write-Host "   python : $Python"

try {
    # -----------------------------------------------------------------------
    Step 1 'The relay account, as install-service.ps1 left it'
    $u = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
    Note "local account $Account exists" $true ($null -ne $u)
    if ($null -eq $u) { Refuse "no $Account account - install-service.ps1 -Install creates it; nothing below can run." }
    Note "$Account is enabled (S4U cannot log a disabled account on)" $true $u.Enabled
    $groups = @()
    foreach ($g in @(Get-LocalGroup)) {
        $m = Get-LocalGroupMember -Group $g.Name -ErrorAction SilentlyContinue | Where-Object { $_.SID -eq $u.SID }
        if ($m) { $groups += $g.Name }
    }
    Note "$Account is in no local group" '' ($groups -join ',')

    # -----------------------------------------------------------------------
    Step 2 'A listener to connect to'
    if (-not (Get-Process -Name sdwind -ErrorAction SilentlyContinue)) {
        Refuse 'sdwind is not running - start SD before running this.'
    }
    $listening = [bool](netstat -an | Select-String (':' + $Port) | Select-String 'LISTENING')
    if (-not $listening) {
        Write-Host "  no listener on $Port - enabling APIPORT and restarting SD"
        Copy-Item -LiteralPath $conf -Destination $backup -Force
        $lines = @(Get-Content -LiteralPath $conf) | Where-Object { $_ -notmatch '^\s*APIPORT\s*=' }
        $lines += ('APIPORT=' + $Port)
        Set-Content -LiteralPath $conf -Value $lines -Encoding Ascii
        $portAddedByUs = $true
        if (-not (Stop-SD))  { Refuse 'SD would not stop while enabling the listener.' }
        if (-not (Start-SD)) { Refuse 'SD would not start again after enabling the listener - read the SD error log.' }
        $listening = [bool](netstat -an | Select-String (':' + $Port) | Select-String 'LISTENING')
    }
    if (-not $listening) { Refuse "Nothing is listening on $Port even after enabling APIPORT and restarting." }
    Write-Host ("  listener on {0}: up{1}" -f $Port, $(if ($portAddedByUs) { ' (this run enabled it)' } else { ' (already)' }))

    # -----------------------------------------------------------------------
    Step 3 'Before: how many relays are alive'
    $before = Get-RelayPids
    Write-Host ("  {0} process(es) named {1} before the connection{2}" -f $before.Count, $RelayName,
        $(if ($before.Count) { ' (leftovers of other sessions; only the NEW one is inspected)' } else { '' }))

    # -----------------------------------------------------------------------
    Step 4 "Hold one API connection open ($HoldSeconds s)"
    $holdArgs = @('"' + $Hold + '"', '--port', $Port, '--hold', $HoldSeconds)
    Write-Host ("  {0} {1}" -f $Python, ($holdArgs -join ' '))
    $holdProc = Start-Process -FilePath $Python -ArgumentList $holdArgs -NoNewWindow -PassThru `
        -RedirectStandardOutput $holdOut -RedirectStandardError $holdErr
    $deadline = (Get-Date).AddSeconds(30)
    $heldLine = $null
    while ((Get-Date) -lt $deadline -and -not $heldLine) {
        Start-Sleep -Milliseconds 300
        if (Test-Path -LiteralPath $holdOut) {
            $heldLine = @(Get-Content -LiteralPath $holdOut -ErrorAction SilentlyContinue) | Where-Object { $_ -like 'HELD *' } | Select-Object -First 1
        }
        if ($holdProc.HasExited) { break }
    }
    if (-not $heldLine) {
        Write-Host '--- relay-hold stdout ---'; if (Test-Path $holdOut) { Get-Content $holdOut | Write-Host }
        Write-Host '--- relay-hold stderr ---'; if (Test-Path $holdErr) { Get-Content $holdErr | Write-Host }
        Refuse 'the handshake did not complete (no HELD line) - nothing below can be measured.  If sd refused the connection, the SD error log has the relay''s reason.'
    }
    Write-Host "  $heldLine"
    Note 'the TLS handshake completed and the connection is held' $true $true

    # -----------------------------------------------------------------------
    Step 5 'The relay, while the connection is held'
    Start-Sleep -Milliseconds 500
    $now = Get-RelayPids
    $new = @($now | Where-Object { $before -notcontains $_ })
    Note 'exactly one NEW relay process while one connection is held' 1 $new.Count
    if ($new.Count -lt 1) { Refuse 'no new relay process to inspect.' }
    $pid_ = $new[0]
    $proc = Get-Process -Id $pid_ -IncludeUserName -ErrorAction Stop
    Write-Host ("  pid {0}: {1}  path {2}" -f $pid_, $proc.UserName, $proc.Path)
    Note 'relay runs as the bare account' ("$env:COMPUTERNAME\$Account") $proc.UserName
    Note 'relay binary is the installed one' (Join-Path $env:ProgramFiles 'SD\usr\bin\sdtlsrelay.exe') $proc.Path

    $peek = [SdTokenPeek]::Peek($pid_)
    Write-Host "  token: $peek"
    $rid = if ($peek -match 'integrity=(\d+)') { [int]$Matches[1] } else { -1 }
    $privs = if ($peek -match 'privileges=(\d+)') { [int]$Matches[1] } else { -1 }
    Note 'relay integrity level is Low (0x1000 = 4096)' 4096 $rid
    Note 'relay holds no privilege' 0 $privs

    $modules = @()
    try { $modules = @($proc.Modules | Select-Object -ExpandProperty ModuleName) } catch { Write-Host "  (modules unreadable: $($_.Exception.Message))" }
    Write-Host ("  {0} modules loaded" -f $modules.Count)
    # user32 as well as msys-*: the relay's second cycle died 0xC0000142 because
    # the static OpenSSL imported USER32, whose initialisation needs a desktop
    # the bare account cannot reach (probe-user32desk.c).  Stubs removed it.
    Note 'relay loads no msys-* or user32 DLL (native, desktopless)' '' (($modules | Where-Object { $_ -like 'msys-*' -or $_ -like 'user32*' }) -join ',')
    Note 'control: the module list was readable at all' $true ($modules.Count -gt 0)

    # The control: the SESSION beside it is still SYSTEM.  The drop is the
    # relay's alone - the session keeps SeTcb so it can become the user after
    # SCRAM (win32s4u.c).  A relay parent that is not sd.exe, or an sd.exe
    # that is not SYSTEM, would mean the wrong thing was measured.
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $pid_"
    $parent = Get-Process -Id $cim.ParentProcessId -IncludeUserName -ErrorAction SilentlyContinue
    Write-Host ("  parent pid {0}: {1} as {2}" -f $cim.ParentProcessId, $(if ($parent) { $parent.ProcessName } else { '?' }), $(if ($parent) { $parent.UserName } else { '?' }))
    Note 'relay parent is sd.exe (the session process)' 'sd' $(if ($parent) { $parent.ProcessName } else { '' })
    Note 'control: the session keeps its own token (SYSTEM)' 'NT AUTHORITY\SYSTEM' $(if ($parent) { $parent.UserName } else { '' })

    # -----------------------------------------------------------------------
    Step 6 'After: the relay goes with the connection'
    $waitDeadline = (Get-Date).AddSeconds($HoldSeconds + 30)
    while (-not $holdProc.HasExited -and (Get-Date) -lt $waitDeadline) { Start-Sleep -Milliseconds 500 }
    Note 'relay-hold ended on its own' $true $holdProc.HasExited
    Start-Sleep -Seconds 2
    $after = Get-RelayPids
    Note 'the new relay process is gone' $false ($after -contains $pid_)
}
finally {
    if ($holdProc -and -not $holdProc.HasExited) { try { $holdProc.Kill() } catch { } }
    if ($portAddedByUs -and (Test-Path -LiteralPath $backup)) {
        if (-not $Keep) {
            Copy-Item -LiteralPath $backup -Destination $conf -Force
            Remove-Item -LiteralPath $backup -Force
            Write-Host '   sd.conf restored'
            if (Stop-SD) { $null = Start-SD }
        } else {
            Write-Host "-Keep: APIPORT=$Port is STILL SET.  Put it back with:" -ForegroundColor Yellow
            Write-Host "  Copy-Item '$backup' '$conf' -Force, then restart SD"
        }
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = ($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("verify-relayidentity: {0} of {1} checks passed" -f $pass, $results.Count)
try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 }
exit 0
