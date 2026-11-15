# probe-pipeinst.ps1 - RELEASE_1.1 304: may an ORDINARY token add an instance of one of SD's service pipes while the server runs?
#
# 14 Nov 26 Windows port - written for row 304.  VM sit2 step 4 (witness-vm-user.ps1 pipes) asked CreateFile for FILE_CREATE_PIPE_INSTANCE
#   (0x4) as a CLIENT on \\.\pipe\sd-audit and \\.\pipe\sd-ai and got 0 (wanted 5), while Get-Acl on sd-audit showed no 0x4 for sdusers.
#   A client open asking 0x4 is not the act that matters.  THE DECISIVE TEST IS THE SERVER-SIDE ONE: CreateNamedPipe on the same name from
#   this token.  If it succeeds, this token could serve a rogue instance and read what SD's sessions send (the audit lines) - a FAIL.  The
#   handle is closed at once; nothing else is changed.
#
# What it prints, per pipe (the instrument rules in CLAUDE.md):
#   - the token it ran as (user, sdusers in it, Administrators enabled, integrity level) - the input;
#   - the instance a READ_CONTROL|READ_ATTRIBUTES client open reached: its owner and DACL as SDDL, and the server's process id and name;
#   - the step-4 check repeated (a client open asking 0x4 alone), and 0x4|READ_CONTROL, which if granted shows THAT instance's DACL;
#   - CreateNamedPipe's result: 5 = refused (PASS), success = FAIL, anything else = INCONCLUSIVE with the number.
#   A pipe that does not exist (2) is NOT-MEASURED and is NOT created: making the first instance of an absent pipe is a different
#   question (squatting while the service is down), and this probe must not leave a pipe behind.
#
# Exit: 0 every measured pipe refused and at least one measured; 1 any FAIL or INCONCLUSIVE; 2 nothing measured (the null case).
# Run it in an ORDINARY, UNELEVATED window (it refuses an elevated one: Administrators full control would make every answer moot).

param([string[]]$Names = @('sd-audit', 'sd-ai', 'sd-runin', 'sd-radmin'))

$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
public static class SdPipeInst {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateFileW(string n, uint a, uint s, IntPtr sa, uint d, uint f, IntPtr t);
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern IntPtr CreateNamedPipeW(string n, uint om, uint pm, uint max, uint ob, uint ib, uint to, IntPtr sa);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool CloseHandle(IntPtr h);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool GetNamedPipeServerProcessId(IntPtr h, out uint pid);
    [DllImport("advapi32.dll", SetLastError = true)]
    static extern uint GetSecurityInfo(IntPtr h, int type, uint info, out IntPtr owner, out IntPtr group, out IntPtr dacl, out IntPtr sacl, out IntPtr sd);
    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool ConvertSecurityDescriptorToStringSecurityDescriptorW(IntPtr sd, uint rev, uint info, out IntPtr str, out uint len);
    [DllImport("kernel32.dll")]
    static extern IntPtr LocalFree(IntPtr p);

    static readonly IntPtr INVALID = new IntPtr(-1);
    const uint OPEN_EXISTING = 3;
    const uint SQOS_IDENT = 0x00110000;      // SECURITY_SQOS_PRESENT | SECURITY_IDENTIFICATION: the server may not impersonate us
    const uint OWNER_DACL = 0x1 | 0x4;       // OWNER_SECURITY_INFORMATION | DACL_SECURITY_INFORMATION

    static string SddlOf(IntPtr h) {
        IntPtr o, g, d, s, sd;
        uint rc = GetSecurityInfo(h, 6, OWNER_DACL, out o, out g, out d, out s, out sd);
        if (rc != 0) return "(GetSecurityInfo " + rc + ")";
        IntPtr str; uint len;
        string r = "(convert failed)";
        if (ConvertSecurityDescriptorToStringSecurityDescriptorW(sd, 1, OWNER_DACL, out str, out len)) { r = Marshal.PtrToStringUni(str); LocalFree(str); }
        LocalFree(sd);
        return r;
    }

    // A client open with the given access; returns the Win32 error (0 = opened).  With wantFacts, the opened instance's SDDL and server.
    public static int Open(string n, uint access, bool wantFacts, out string sddl, out string server) {
        sddl = ""; server = "";
        IntPtr h = CreateFileW(n, access, 0, IntPtr.Zero, OPEN_EXISTING, SQOS_IDENT, IntPtr.Zero);
        if (h == INVALID) return Marshal.GetLastWin32Error();
        if (wantFacts) {
            sddl = SddlOf(h);
            uint pid;
            if (GetNamedPipeServerProcessId(h, out pid)) {
                string nm = "?";
                try { nm = Process.GetProcessById((int)pid).ProcessName; } catch { nm = "(not readable)"; }
                server = pid + " " + nm;
            } else { server = "(GetNamedPipeServerProcessId " + Marshal.GetLastWin32Error() + ")"; }
        }
        CloseHandle(h);
        return 0;
    }

    // The decisive test: add an instance of an EXISTING pipe from this token.  Closed at once if it was made.
    public static int MakeInstance(string n) {
        // PIPE_ACCESS_DUPLEX (3), no FILE_FLAG_FIRST_PIPE_INSTANCE; PIPE_TYPE_BYTE|PIPE_WAIT|PIPE_REJECT_REMOTE_CLIENTS (8)
        IntPtr h = CreateNamedPipeW(n, 3, 8, 255, 512, 512, 0, IntPtr.Zero);
        if (h == INVALID) return Marshal.GetLastWin32Error();
        CloseHandle(h);
        return 0;
    }
}
'@

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
$adminOn = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$sdusersSid = $null
try { $sdusersSid = (New-Object Security.Principal.NTAccount('sdusers')).Translate([Security.Principal.SecurityIdentifier]).Value } catch { $sdusersSid = $null }
$inSdusers = ($null -ne $sdusersSid) -and (@($id.Groups | Where-Object { $_.Value -eq $sdusersSid }).Count -gt 0)
$il = (& whoami.exe /groups | Select-String -Pattern 'Mandatory Label\\(\S+ Mandatory Level)' | ForEach-Object { $_.Matches[0].Groups[1].Value } | Select-Object -First 1)

Write-Host ('probe-pipeinst  ' + (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') + '  host ' + $env:COMPUTERNAME + '  script ' + $PSCommandPath)
Write-Host ('  token: ' + $id.Name + '; sdusers (' + $sdusersSid + ') in it: ' + $inSdusers + '; Administrators enabled: ' + $adminOn + '; ' + $il)
Write-Host ('  pipes asked: ' + ($Names -join ', '))
if ($adminOn) {
    Write-Host '  REFUSED: this window is elevated.  Run it in an ORDINARY, unelevated PowerShell.'
    exit 2
}
if (@($Names).Count -eq 0) { Write-Host '  REFUSED: no pipe names given.'; exit 2 }

$measured = 0; $bad = 0
foreach ($n in $Names) {
    $path = '\\.\pipe\' + $n
    Write-Host ''
    Write-Host ('=== ' + $path)
    $sd = ''; $srv = ''
    $e0 = [SdPipeInst]::Open($path, [uint32](0x00020000 -bor 0x0080), $true, [ref]$sd, [ref]$srv)
    if ($e0 -eq 2) {
        Write-Host '  NOT-MEASURED  the pipe does not exist (2): no server is running, and this probe does not create one'
        continue
    }
    if ($e0 -eq 0) {
        Write-Host ('  instance reached by a READ_CONTROL|READ_ATTRIBUTES open: server ' + $srv)
        Write-Host ('    SDDL: ' + $sd)
    } else {
        Write-Host ('  a READ_CONTROL|READ_ATTRIBUTES open failed with ' + $e0 + ' (the pipe exists; its DACL is not readable from this token)')
    }
    $d1 = ''; $d2 = ''
    $e1 = [SdPipeInst]::Open($path, [uint32]0x4, $false, [ref]$d1, [ref]$d2)
    Write-Host ('  client open asking 0x4 alone (step 4''s check): ' + $e1 + $(if ($e1 -eq 0) { ' (opened)' } elseif ($e1 -eq 5) { ' (refused)' } else { '' }))
    $s3 = ''; $v3 = ''
    $e3 = [SdPipeInst]::Open($path, [uint32](0x4 -bor 0x00020000 -bor 0x0080), $true, [ref]$s3, [ref]$v3)
    if ($e3 -eq 0) { Write-Host ('  client open asking 0x4|READ_CONTROL|READ_ATTRIBUTES: opened; server ' + $v3 + '; SDDL: ' + $s3) }
    else { Write-Host ('  client open asking 0x4|READ_CONTROL|READ_ATTRIBUTES: ' + $e3) }
    $e2 = [SdPipeInst]::MakeInstance($path)
    $measured++
    if ($e2 -eq 5) { Write-Host '  PASS          CreateNamedPipe from this token is refused (5): no rogue instance can be added' }
    elseif ($e2 -eq 0) { Write-Host '  FAIL          CreateNamedPipe from this token SUCCEEDED: an ordinary user can add an instance (closed at once)'; $bad++ }
    else { Write-Host ('  INCONCLUSIVE  CreateNamedPipe returned ' + $e2 + ' (neither refused for access nor made)'); $bad++ }
}

Write-Host ''
Write-Host ('measured ' + $measured + ' of ' + @($Names).Count + '; failed or inconclusive ' + $bad)
if ($measured -eq 0) { Write-Host 'NOTHING MEASURED: no pipe was running.  This is not a pass.'; exit 2 }
if ($bad -gt 0) { exit 1 }
Write-Host 'probe-pipeinst: every running pipe refused a new instance from this token'
exit 0
