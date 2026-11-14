# witness-vm-lib.ps1 - shared helpers for the Core VM witness sitting of 13 Nov 2026 (witness-vm-*.ps1).
#
# Dot-sourced, never run.  It defines functions and one compiled type (SdWit.Native) and does nothing else at load time.
# The sitting sheet is .claude/vm-sitting-core-sheet-20261113.md; the plan .claude/vm-sitting-core-plan-20261113.md.
#
# THE INSTRUMENT RULES THIS FILE CARRIES FOR EVERY WITNESS SCRIPT (CLAUDE.md):
#   * every result line names the row, the check, the verdict and the EVIDENCE (the value, path or output it read);
#   * a verdict is PASS only when the success wording (or the measured state) was seen AND no failure wording was;
#     an empty output, a seat that did not run or a probe that read nothing is NOT-MEASURED, never PASS;
#   * nothing here prints with Write-Output: a function that returns a value prints with Write-Host only, so its return
#     value is never an array of printed lines (memory ps-function-output-trap; free guard test-psreturn-units.ps1).
#
# Verdicts: PASS, FAIL, FINDING (a measure-first row measured the unwanted answer), NOT-MEASURED (with the reason),
# INFO (a measurement with no pass mark, e.g. a timing).  A script's exit code: 1 if any FAIL or FINDING, 2 if nothing
# was measured at all, else 0.
#
# NO Set-StrictMode AT FILE SCOPE: a dot-sourced file's strict mode would bind the caller (the suite-only.ps1 trap).
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting (rows 197-279).  Not run: it needs the VM.
# END-HISTORY

$script:WitResults = New-Object System.Collections.ArrayList
$script:WitLog = ''
$script:WitName = 'witness'
$script:WitRoot = 'C:\SD-witness'
$script:WitDataDir = Join-Path $env:ProgramData 'SD'
$script:WitSdsys = Join-Path (Join-Path $env:ProgramData 'SD') 'sdsys'
$script:WitSdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

# The SDSYS seat (Invoke-WitSd calls Invoke-SdViaSeat and Expand-SeatCommands), loaded here before any call, as every seat
# caller does (test-sdsysseat-units.ps1 checks it).
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')

if (-not ('SdWit.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;
using System.Threading;
using Microsoft.Win32.SafeHandles;

namespace SdWit
{
    public class PipeFacts
    {
        public int OpenError;
        public string Sddl = "";
        public int SddlError;
        public uint ServerPid;
        public int ServerPidError;
    }

    public class SendResult
    {
        public int OpenError;
        public int WriteError;
        public int ReadError;
        public int Answer = -1;
        public bool TimedOut;
    }

    public class TokenFacts
    {
        public int Error;
        public string Stage = "";
        public string User = "";
        public string Groups = "";
        public int PrivilegeCount = -1;
        public string Privileges = "";
        public string Integrity = "";
        public int Elevated = -1;
        public int InJob = -1;
    }

    public static class Native
    {
        const uint OPEN_EXISTING = 3;
        const uint SQOS_IDENT = 0x00100000 | 0x00010000;
        const uint READ_CONTROL = 0x00020000;
        const uint PIPE_CLIENT = 0x0001 | 0x0002 | 0x0080 | 0x00100000;
        const int ERROR_PIPE_BUSY = 231;

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr sa, uint disp, uint flags, IntPtr tmpl);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool WaitNamedPipeW(string name, uint timeout);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool WriteFile(SafeFileHandle h, byte[] buf, uint n, out uint done, IntPtr ov);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool ReadFile(SafeFileHandle h, byte[] buf, uint n, out uint done, IntPtr ov);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CancelIoEx(SafeFileHandle h, IntPtr ov);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetNamedPipeServerProcessId(SafeFileHandle h, out uint pid);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern uint GetSecurityInfo(SafeFileHandle h, int type, uint info, IntPtr owner, IntPtr group, IntPtr dacl, IntPtr sacl, out IntPtr sd);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool ConvertSecurityDescriptorToStringSecurityDescriptorW(IntPtr sd, uint rev, uint info, out IntPtr str, out uint len);
        [DllImport("kernel32.dll")]
        static extern IntPtr LocalFree(IntPtr p);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool LogonUserW(string user, string domain, string pw, int type, int provider, out IntPtr token);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)]
        static extern bool GetTokenInformation(IntPtr token, int cls, IntPtr buf, int len, out int ret);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool ConvertSidToStringSidW(IntPtr sid, out IntPtr str);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool LookupPrivilegeNameW(string system, IntPtr luid, StringBuilder name, ref int len);
        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool IsProcessInJob(IntPtr proc, IntPtr job, out bool result);

        static SafeFileHandle OpenPipe(string path, uint access, out int err)
        {
            err = 0;
            for (int i = 0; i < 3; i++)
            {
                SafeFileHandle h = CreateFileW(path, access, 0, IntPtr.Zero, OPEN_EXISTING, SQOS_IDENT, IntPtr.Zero);
                if (!h.IsInvalid) { err = 0; return h; }
                err = Marshal.GetLastWin32Error();
                h.Dispose();
                if (err != ERROR_PIPE_BUSY) return null;
                WaitNamedPipeW(path, 2000);
            }
            return null;
        }

        // Connect as a client asking only READ_CONTROL, read the owner and DACL as SDDL, and the server's pid.
        public static PipeFacts PipeInfo(string path)
        {
            PipeFacts f = new PipeFacts();
            int err;
            SafeFileHandle h = OpenPipe(path, READ_CONTROL, out err);
            f.OpenError = err;
            if (h == null) return f;
            using (h)
            {
                IntPtr sd;
                uint rc = GetSecurityInfo(h, 6, 1 | 4, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, out sd);
                if (rc != 0) { f.SddlError = (int)rc; }
                else
                {
                    IntPtr str;
                    uint len;
                    if (ConvertSecurityDescriptorToStringSecurityDescriptorW(sd, 1, 1 | 4, out str, out len))
                    {
                        f.Sddl = Marshal.PtrToStringUni(str);
                        LocalFree(str);
                    }
                    else { f.SddlError = Marshal.GetLastWin32Error(); }
                    LocalFree(sd);
                }
                uint pid;
                if (GetNamedPipeServerProcessId(h, out pid)) f.ServerPid = pid; else f.ServerPidError = Marshal.GetLastWin32Error();
            }
            return f;
        }

        // Open as a client with the given access and close again: 0 opened, else the Windows error.
        public static int PipeProbe(string path, uint access)
        {
            int err;
            SafeFileHandle h = OpenPipe(path, access, out err);
            if (h != null) h.Dispose();
            return err;
        }

        // Connect with data access only (no FILE_CREATE_PIPE_INSTANCE, no write attributes), write ONE message, read the answer.
        public static SendResult PipeSend(string path, byte[] msg, int timeoutMs)
        {
            SendResult r = new SendResult();
            int err;
            SafeFileHandle h = OpenPipe(path, PIPE_CLIENT, out err);
            r.OpenError = err;
            if (h == null) return r;
            using (h)
            {
                uint done;
                if (!WriteFile(h, msg, (uint)msg.Length, out done, IntPtr.Zero)) { r.WriteError = Marshal.GetLastWin32Error(); return r; }
                byte[] buf = new byte[16];
                int got = -1;
                int rerr = 0;
                SafeFileHandle hh = h;
                Thread t = new Thread(delegate()
                {
                    uint n;
                    if (ReadFile(hh, buf, (uint)buf.Length, out n, IntPtr.Zero)) got = (int)n; else rerr = Marshal.GetLastWin32Error();
                });
                t.IsBackground = true;
                t.Start();
                if (!t.Join(timeoutMs)) { r.TimedOut = true; CancelIoEx(h, IntPtr.Zero); t.Join(2000); }
                r.ReadError = rerr;
                if (got > 0) r.Answer = buf[0];
            }
            return r;
        }

        // LogonUser of the given type (2 interactive, 3 network, 4 batch, 5 service): 0 if Windows let it, else the error
        // (1385 = the logon type is not granted, 1326 = bad name or password, 1331 = disabled, 1909 = locked out).
        public static int LogonTest(string user, string domain, string pw, int type)
        {
            IntPtr tok;
            if (!LogonUserW(user, domain, pw, type, 0, out tok)) return Marshal.GetLastWin32Error();
            CloseHandle(tok);
            return 0;
        }

        // Open a path for the given access AS the user (network logon, impersonated on this thread).  0 opened, a
        // positive Windows error if the open was refused, a NEGATIVE Windows error if the logon itself failed.
        public static int OpenAs(string user, string domain, string pw, string path, uint access, bool directory)
        {
            IntPtr tok;
            if (!LogonUserW(user, domain, pw, 3, 0, out tok)) return -Marshal.GetLastWin32Error();
            try
            {
                using (WindowsImpersonationContext ctx = WindowsIdentity.Impersonate(tok))
                {
                    uint flags = directory ? 0x02000000u : 0u;
                    SafeFileHandle h = CreateFileW(path, access, 7, IntPtr.Zero, OPEN_EXISTING, flags, IntPtr.Zero);
                    int e = h.IsInvalid ? Marshal.GetLastWin32Error() : 0;
                    h.Dispose();
                    return e;
                }
            }
            finally { CloseHandle(tok); }
        }

        static IntPtr Info(IntPtr tok, int cls)
        {
            int need;
            GetTokenInformation(tok, cls, IntPtr.Zero, 0, out need);
            if (need <= 0) return IntPtr.Zero;
            IntPtr buf = Marshal.AllocHGlobal(need);
            if (!GetTokenInformation(tok, cls, buf, need, out need)) { Marshal.FreeHGlobal(buf); return IntPtr.Zero; }
            return buf;
        }

        static string SidText(IntPtr sid)
        {
            IntPtr str;
            if (sid == IntPtr.Zero || !ConvertSidToStringSidW(sid, out str)) return "?";
            string s = Marshal.PtrToStringUni(str);
            LocalFree(str);
            return s;
        }

        // The token of a process: user, groups with attributes, privileges, integrity label, elevation, and whether the
        // process is in a job.  Run as SYSTEM where an administrator cannot open the process (witness-vm-system.ps1).
        public static TokenFacts ReadToken(uint pid)
        {
            TokenFacts f = new TokenFacts();
            IntPtr p = OpenProcess(0x1000, false, pid);
            if (p == IntPtr.Zero) { f.Error = Marshal.GetLastWin32Error(); f.Stage = "OpenProcess"; return f; }
            try
            {
                bool inJob;
                if (IsProcessInJob(p, IntPtr.Zero, out inJob)) f.InJob = inJob ? 1 : 0;
                IntPtr tok;
                if (!OpenProcessToken(p, 0x0008, out tok)) { f.Error = Marshal.GetLastWin32Error(); f.Stage = "OpenProcessToken"; return f; }
                try
                {
                    IntPtr b = Info(tok, 1);
                    if (b != IntPtr.Zero) { f.User = SidText(Marshal.ReadIntPtr(b)); Marshal.FreeHGlobal(b); }
                    b = Info(tok, 2);
                    if (b != IntPtr.Zero)
                    {
                        int n = Marshal.ReadInt32(b);
                        StringBuilder sb = new StringBuilder();
                        int step = IntPtr.Size * 2;
                        for (int i = 0; i < n; i++)
                        {
                            IntPtr at = new IntPtr(b.ToInt64() + IntPtr.Size + (long)i * step);
                            IntPtr sid = Marshal.ReadIntPtr(at);
                            int attrs = Marshal.ReadInt32(new IntPtr(at.ToInt64() + IntPtr.Size));
                            sb.Append(SidText(sid)).Append("|0x").Append(attrs.ToString("X")).Append(";");
                        }
                        f.Groups = sb.ToString();
                        Marshal.FreeHGlobal(b);
                    }
                    b = Info(tok, 3);
                    if (b != IntPtr.Zero)
                    {
                        int n = Marshal.ReadInt32(b);
                        f.PrivilegeCount = n;
                        StringBuilder sb = new StringBuilder();
                        for (int i = 0; i < n; i++)
                        {
                            IntPtr luid = new IntPtr(b.ToInt64() + 4 + (long)i * 12);
                            int attrs = Marshal.ReadInt32(new IntPtr(luid.ToInt64() + 8));
                            StringBuilder name = new StringBuilder(64);
                            int len = 64;
                            string nm = LookupPrivilegeNameW(null, luid, name, ref len) ? name.ToString() : "?";
                            sb.Append(nm).Append("|0x").Append(attrs.ToString("X")).Append(";");
                        }
                        f.Privileges = sb.ToString();
                        Marshal.FreeHGlobal(b);
                    }
                    b = Info(tok, 25);
                    if (b != IntPtr.Zero) { f.Integrity = SidText(Marshal.ReadIntPtr(b)); Marshal.FreeHGlobal(b); }
                    b = Info(tok, 20);
                    if (b != IntPtr.Zero) { f.Elevated = Marshal.ReadInt32(b); Marshal.FreeHGlobal(b); }
                }
                finally { CloseHandle(tok); }
            }
            finally { CloseHandle(p); }
            return f;
        }
    }
}
'@
}

# ---------------------------------------------------------------------------------------------------- printing and verdicts

# Prints one line to the screen and the log.  Returns nothing.
function Write-Wit([string]$Text = '') {
    Write-Host $Text
    if ($script:WitLog -ne '') { try { Add-Content -LiteralPath $script:WitLog -Value $Text -Encoding UTF8 } catch { } }
}

# Prints a block of raw text, every line, indented - the instrument rule: the output is shown every time, not only when
# it looked wrong.  Returns nothing.
function Write-WitRaw([string]$Label, [string]$Text) {
    Write-Wit ('    --- ' + $Label + ' (raw) ---')
    if ([string]::IsNullOrEmpty($Text)) { Write-Wit '    | <nothing>'; return }
    foreach ($l in ($Text -split "`r?`n")) { Write-Wit ('    | ' + $l.TrimEnd()) }
    Write-Wit '    --- end ---'
}

# Starts the log for a script.  Returns nothing; sets $script:WitLog.
function Start-Wit([string]$Name, [string[]]$Sections) {
    $script:WitName = $Name
    $logDir = Join-Path $script:WitRoot 'logs'
    try {
        if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
        $script:WitLog = Join-Path $logDir ($Name + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
        Set-Content -LiteralPath $script:WitLog -Value '' -Encoding UTF8
    } catch {
        $alt = Join-Path $env:LOCALAPPDATA 'SD-witness'
        if (-not (Test-Path -LiteralPath $alt)) { $null = New-Item -ItemType Directory -Path $alt -Force }
        $script:WitLog = Join-Path $alt ($Name + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
    }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $pr = New-Object Security.Principal.WindowsPrincipal($id)
    Write-Wit ('==== ' + $Name + '   ' + (Get-Date).ToString('s') + '   log ' + $script:WitLog)
    Write-Wit ('  machine ' + $env:COMPUTERNAME + '   user ' + $id.Name + '   elevated ' +
               $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator) + '   pid ' + $PID)
    Write-Wit ('  script  ' + $MyInvocation.PSCommandPath)
    Write-Wit ('  sections asked for: ' + ($Sections -join ','))
}

function Test-WitElevated {
    $pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Records one result and prints it.  Returns nothing.
function Add-WitResult {
    param([string]$Row, [string]$Check, [ValidateSet('PASS', 'FAIL', 'FINDING', 'NOT-MEASURED', 'INFO')][string]$Verdict, [string]$Evidence = '')
    $null = $script:WitResults.Add([pscustomobject]@{ Row = $Row; Check = $Check; Verdict = $Verdict; Evidence = $Evidence })
    Write-Wit ('  [{0}] RELEASE_1.1 {1}: {2}' -f $Verdict, $Row, $Check)
    if ($Evidence -ne '') { Write-Wit ('         evidence: ' + $Evidence) }
}

# Pure: does the text carry the success wording and none of the failure wording?  Returns a hashtable.
function Test-WitText {
    param([string]$Text, [string]$Success, [string[]]$Failure = @())
    $r = @{ Empty = [string]::IsNullOrWhiteSpace($Text); Ok = $false; Bad = ''; Hit = '' }
    if ($r.Empty) { return $r }
    foreach ($f in $Failure) {
        if ($f -ne '' -and $Text -match $f) { $r.Bad = $Matches[0]; return $r }
    }
    if ($Text -match $Success) { $r.Ok = $true; $r.Hit = $Matches[0] }
    return $r
}

# Scores a text against a success anchor and failure anchors, and records it.  An empty text is NOT-MEASURED.
function Set-WitVerdict {
    param([string]$Row, [string]$Check, [string]$Text, [string]$Success, [string[]]$Failure = @(), [string]$Evidence = '')
    $t = Test-WitText -Text $Text -Success $Success -Failure $Failure
    if ($t.Empty) { Add-WitResult $Row $Check 'NOT-MEASURED' ('there was no output to read. ' + $Evidence); return }
    if ($t.Bad -ne '') { Add-WitResult $Row $Check 'FAIL' ("failure wording seen: '" + $t.Bad + "'. " + $Evidence); return }
    if ($t.Ok) { Add-WitResult $Row $Check 'PASS' ("success wording seen: '" + $t.Hit + "'. " + $Evidence); return }
    Add-WitResult $Row $Check 'FAIL' ("the success wording /" + $Success + "/ is not in the output. " + $Evidence)
}

# Scores a measured value against the wanted one.  $Measured = $false makes it NOT-MEASURED with $Why.
function Set-WitCompare {
    param([string]$Row, [string]$Check, $Wanted, $Got, [bool]$Measured = $true, [string]$Why = '', [string]$Evidence = '')
    if (-not $Measured) { Add-WitResult $Row $Check 'NOT-MEASURED' ($Why + ' ' + $Evidence); return }
    $ok = ([string]$Wanted -ceq [string]$Got)
    $v = 'FAIL'
    if ($ok) { $v = 'PASS' }
    Add-WitResult $Row $Check $v ('wanted ' + [string]$Wanted + ', got ' + [string]$Got + '. ' + $Evidence)
}

# Prints the per-row summary, writes it beside the log, and returns the exit code (prints with Write-Host only).
function Complete-Wit {
    Write-Wit ''
    Write-Wit ('==== SUMMARY ' + $script:WitName + ' (' + $script:WitResults.Count + ' results)')
    $rows = @($script:WitResults | Select-Object -ExpandProperty Row -Unique | Sort-Object)
    foreach ($r in $rows) {
        foreach ($x in @($script:WitResults | Where-Object { $_.Row -eq $r })) {
            Write-Wit ('  {0,-12} {1,-13} {2}' -f ('RELEASE_1.1 ' + $x.Row), $x.Verdict, $x.Check)
        }
    }
    $n = @{}
    foreach ($v in 'PASS', 'FAIL', 'FINDING', 'NOT-MEASURED', 'INFO') { $n[$v] = @($script:WitResults | Where-Object { $_.Verdict -eq $v }).Count }
    Write-Wit ('  PASS {0}   FAIL {1}   FINDING {2}   NOT-MEASURED {3}   INFO {4}' -f $n['PASS'], $n['FAIL'], $n['FINDING'], $n['NOT-MEASURED'], $n['INFO'])
    $csv = $script:WitLog -replace '\.log$', '.results.csv'
    try { $script:WitResults | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8; Write-Wit ('  results: ' + $csv) } catch { }
    $code = 0
    if (($n['PASS'] + $n['FAIL'] + $n['FINDING']) -eq 0) {
        Write-Wit '  NOTHING WAS MEASURED - this run is not a result (exit 2).'
        $code = 2
    } elseif (($n['FAIL'] + $n['FINDING']) -gt 0) {
        $code = 1
    }
    Write-Wit ('  log: ' + $script:WitLog + '   exit ' + $code)
    return $code
}

# -Only handling.  Returns the list of sections to run, or $null after printing why (the caller exits 2).
function Resolve-WitSections([string[]]$Only, [string[]]$Known) {
    $want = @()
    foreach ($o in @($Only)) { foreach ($p in ($o -split ',')) { if ($p.Trim() -ne '') { $want += $p.Trim().ToLower() } } }
    if ($want.Count -eq 0) {
        Write-Host ('pass -Only with one or more of: ' + ($Known -join ','))
        Write-Host 'nothing was run (exit 2): the sitting sheet names the sections for each step.'
        return $null
    }
    foreach ($w in $want) {
        if ($Known -notcontains $w) {
            Write-Host ("'" + $w + "' is not a section of this script; the sections are: " + ($Known -join ','))
            Write-Host 'nothing was run (exit 2).'
            return $null
        }
    }
    return $want
}

# ---------------------------------------------------------------------------------------------------- SD through the seat

# Runs SD lines as SDSYS through sdsys-seat.ps1 (the caller dot-sources it).  Returns the seat's result object; prints the
# commands (passwords redacted) and SD's raw output with Write-Host.
function Invoke-WitSd {
    param([string[]]$Commands, [string]$Label, [int]$TimeoutSec = 120, [string[]]$Secrets = @(), [switch]$Internal)
    Write-Wit ('  SD as SDSYS (seat): ' + $Label)
    foreach ($c in $Commands) {
        $shown = $c
        foreach ($s in $Secrets) { if ($s -ne '' -and $c -ceq $s) { $shown = '<password, not shown>' } }
        Write-Wit ('    > ' + $shown)
    }
    $t0 = Get-Date
    $r = Invoke-SdViaSeat -Commands @(Expand-SeatCommands $Commands) -TimeoutSec $TimeoutSec -Internal:$Internal
    $secs = [int]((Get-Date) - $t0).TotalSeconds
    if (-not $r.Ok) {
        Write-Wit ('    THE SEAT DID NOT RUN (' + $secs + ' s): ' + $r.Why + '  [' + $r.Detail + ']')
    } else {
        $txt = $r.Text
        foreach ($s in $Secrets) { if ($s -ne '') { $txt = $txt.Replace($s, '<password>') } }
        Write-WitRaw ($Label + ', ' + $secs + ' s') $txt
    }
    return $r
}

# Runs SD lines over ssh as a fixture account (sdtestuser.ps1, dot-sourced by the caller).  Returns the result object
# (ExitCode, Out, Err) or $null if ssh could not be started; prints the raw output.
function Invoke-WitSsh {
    param([string]$User, [string]$Password, [string[]]$Commands, [string]$Label)
    Write-Wit ('  SD over ssh as ' + $User + ': ' + $Label)
    foreach ($c in $Commands) { Write-Wit ('    > ' + $c) }
    $t0 = Get-Date
    $r = $null
    try { $r = Invoke-SdAsTestUser -Name $User -Password $Password -Commands $Commands } catch { Write-Wit ('    ssh could not be run: ' + $_.Exception.Message) }
    if ($null -ne $r) {
        Write-Wit ('    ssh exit ' + $r.ExitCode + ', ' + [int]((Get-Date) - $t0).TotalSeconds + ' s')
        Write-WitRaw ($Label + ' stdout') $r.Out
        if ($r.Err -ne '') { Write-WitRaw ($Label + ' stderr') $r.Err }
    }
    return $r
}

# ---------------------------------------------------------------------------------------------------- the audit trail

function Get-WitAuditPath { return (Join-Path $script:WitSdsys 'audit') }

# The trail's length now: a mark to read new lines from.  -1 if it cannot be read.
function Get-WitAuditMark {
    $p = Get-WitAuditPath
    try { return (Get-Item -LiteralPath $p -ErrorAction Stop).Length } catch { return -1 }
}

# Lines written since a mark (rotation-aware: a trail shorter than the mark was rotated, so the newest rotated file's tail
# past the mark is read first).  Returns a string array; an unreadable trail returns @('<unreadable: why>').
function Get-WitAuditSince([long]$Mark) {
    $p = Get-WitAuditPath
    $out = New-Object System.Collections.ArrayList
    try {
        $len = (Get-Item -LiteralPath $p -ErrorAction Stop).Length
        $from = $Mark
        if ($Mark -lt 0) { $from = 0 }
        if ($len -lt $from) {
            $rot = Get-ChildItem -LiteralPath $script:WitSdsys -Filter 'audit.*' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
            if ($null -ne $rot) { foreach ($l in @(Read-WitFileFrom $rot.FullName $from)) { $null = $out.Add($l) } }
            $from = 0
        }
        foreach ($l in @(Read-WitFileFrom $p $from)) { $null = $out.Add($l) }
    } catch {
        return @('<unreadable: ' + $_.Exception.Message + '>')
    }
    return $out.ToArray()
}

function Read-WitFileFrom([string]$Path, [long]$Offset) {
    $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    try {
        if ($Offset -gt $fs.Length) { $Offset = 0 }
        $null = $fs.Seek($Offset, [IO.SeekOrigin]::Begin)
        $sr = New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)
        $txt = $sr.ReadToEnd()
        $sr.Dispose()
    } finally { $fs.Dispose() }
    return @($txt -split "`r?`n" | Where-Object { $_ -ne '' })
}

# ---------------------------------------------------------------------------------------------------- Windows facts

# secedit's user-rights export as right -> list of SIDs (without the '*'), or names where secedit wrote a name.
function Get-WitRights {
    $f = Join-Path $env:TEMP ('witrights-' + $PID + '.inf')
    $map = @{}
    try {
        $null = & secedit.exe /export /areas USER_RIGHTS /cfg $f 2>&1
        foreach ($l in @(Get-Content -LiteralPath $f -ErrorAction Stop)) {
            if ($l -match '^\s*(Se\w+)\s*=\s*(.*)$') { $map[$Matches[1]] = @($Matches[2].Split(',') | ForEach-Object { $_.Trim().TrimStart('*') } | Where-Object { $_ -ne '' }) }
        }
    } catch { $map['__error'] = @($_.Exception.Message) }
    finally { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    return $map
}

function Get-WitSid([string]$Name) {
    try { return (New-Object Security.Principal.NTAccount($Name)).Translate([Security.Principal.SecurityIdentifier]).Value } catch { return '' }
}

function Get-WitGroupMembers([string]$Group) {
    try { return @(Get-LocalGroupMember -Group $Group -ErrorAction Stop | ForEach-Object { ($_.Name -split '\\')[-1].ToLower() }) } catch { return @('<group unreadable: ' + $_.Exception.Message + '>') }
}

# One pipe's facts as a hashtable with a printable summary; prints nothing.
function Get-WitPipe([string]$Name) {
    $f = [SdWit.Native]::PipeInfo('\\.\pipe\' + $Name)
    $srv = ''
    if ($f.ServerPid -gt 0) { try { $srv = (Get-Process -Id $f.ServerPid -ErrorAction Stop).Path } catch { $srv = 'pid ' + $f.ServerPid } }
    return @{ Name = $Name; OpenError = $f.OpenError; Sddl = $f.Sddl; SddlError = $f.SddlError; ServerPid = $f.ServerPid; Server = $srv
              Summary = ('open=' + $f.OpenError + ' sddl=' + $f.Sddl + ' sddlErr=' + $f.SddlError + ' server=' + $srv) }
}

# The DACL ACEs of an SDDL as objects (Type, Rights as a number where SDDL gave hex or a known alias, Sid).
function Get-WitAces([string]$Sddl) {
    $aces = @()
    $alias = @{ 'FA' = 0x1F01FF; 'GA' = 0x10000000; 'FR' = 0x120089; 'FW' = 0x120116; 'GR' = 0x80000000; 'GW' = 0x40000000 }
    foreach ($m in [regex]::Matches($Sddl, '\(([^;]*);([^;]*);([^;]*);[^;]*;[^;]*;([^)]*)\)')) {
        $rt = $m.Groups[3].Value
        $num = -1
        if ($rt -match '^0x([0-9A-Fa-f]+)$') { $num = [Convert]::ToInt64($Matches[1], 16) } elseif ($alias.ContainsKey($rt)) { $num = $alias[$rt] }
        $aces += [pscustomobject]@{ Type = $m.Groups[1].Value; Flags = $m.Groups[2].Value; Rights = $rt; Mask = $num; Sid = $m.Groups[4].Value }
    }
    return $aces
}

# The loopback-UNC open of a pipe goes through the SMB server, so PIPE_REJECT_REMOTE_CLIENTS must refuse it while the
# local open succeeds.  Returns @{ Measured; Local; Remote; Why } - Measured false when the SMB server is not running
# (then the loopback open says nothing about the flag).
function Test-WitPipeRemote([string]$Name) {
    $svc = Get-Service -Name LanmanServer -ErrorAction SilentlyContinue
    $local = [SdWit.Native]::PipeProbe('\\.\pipe\' + $Name, 0x00020000)
    $remote = [SdWit.Native]::PipeProbe('\\localhost\pipe\' + $Name, 0x00020000)
    $why = ''
    $measured = $true
    if ($null -eq $svc -or $svc.Status -ne 'Running') { $measured = $false; $why = 'the Server service (LanmanServer) is not running, so a loopback UNC open cannot reach the pipe at all' }
    elseif ($local -ne 0 -and $local -ne 5) { $measured = $false; $why = ('the LOCAL open failed with ' + $local + ', so there is no control') }
    return @{ Measured = $measured; Local = $local; Remote = $remote; Why = $why }
}

# Runs a gplbld script as LocalSystem through a one-shot scheduled task and returns @{ Ok; Text; Why }.
function Invoke-WitAsSystem {
    param([string]$Script, [string]$Arguments, [string]$OutFile, [int]$TimeoutSec = 60)
    $name = 'SDWitnessSystem_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $made = $false
    try {
        Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
        $act = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "' + $Script + '" ' + $Arguments + ' -Out "' + $OutFile + '"')
        $pri = New-ScheduledTaskPrincipal -UserId 'NT AUTHORITY\SYSTEM' -LogonType ServiceAccount -RunLevel Highest
        $set = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Seconds ($TimeoutSec + 30))
        Register-ScheduledTask -TaskName $name -Action $act -Principal $pri -Settings $set -Force | Out-Null
        $made = $true
        Start-ScheduledTask -TaskName $name
        $deadline = (Get-Date).AddSeconds($TimeoutSec)
        while (-not (Test-Path -LiteralPath $OutFile) -and (Get-Date) -lt $deadline) { Start-Sleep -Milliseconds 300 }
        if (-not (Test-Path -LiteralPath $OutFile)) {
            $last = '?'
            try { $last = (Get-ScheduledTaskInfo -TaskName $name).LastTaskResult } catch { }
            return @{ Ok = $false; Text = ''; Why = ('the SYSTEM task wrote nothing in ' + $TimeoutSec + ' s (LastTaskResult ' + $last + ')') }
        }
        Start-Sleep -Milliseconds 300
        return @{ Ok = $true; Text = [IO.File]::ReadAllText($OutFile); Why = '' }
    } catch {
        return @{ Ok = $false; Text = ''; Why = ('the SYSTEM task could not be run: ' + $_.Exception.Message) }
    } finally {
        if ($made) { try { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop } catch { } }
    }
}

# ---------------------------------------------------------------------------------------------------- the fixtures file

function Get-WitFixturePath { return (Join-Path $script:WitRoot 'fixtures.json') }

# The fixture accounts' throwaway passwords, written by witness-vm-admin.ps1 -Only fixtures, readable by the invoking
# Windows user, SYSTEM and Administrators only.  Returns a hashtable, or $null if there is none.
function Read-WitFixtures {
    $p = Get-WitFixturePath
    if (-not (Test-Path -LiteralPath $p)) { return $null }
    try {
        $o = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
        $h = @{}
        foreach ($pr in $o.PSObject.Properties) { $h[$pr.Name] = [string]$pr.Value }
        return $h
    } catch { return $null }
}

function Save-WitFixtures([hashtable]$Map, [string]$ReaderSid) {
    $p = Get-WitFixturePath
    ($Map | ConvertTo-Json) | Set-Content -LiteralPath $p -Encoding ASCII
    $acl = New-Object Security.AccessControl.FileSecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($s in @('S-1-5-18', 'S-1-5-32-544')) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', 'Allow')))
    }
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($ReaderSid)), 'Read', 'Allow')))
    Set-Acl -LiteralPath $p -AclObject $acl
}

# ---------------------------------------------------------------------------------------------------- group D probes
#
# The BASIC probes for rows 241 (OSPATH), 251 (OPENTEMP) and 263 (DIGEST), the same set for the account with its OS switch
# OFF (zzwitoff) and the control account with it ON (zzwiton).  witness-vm-admin.ps1 -Only fixtures WRITES them into each
# account's bp; witness-vm-user.ps1 RUNS them over ssh and judges them.  One definition, so the two cannot drift.  Pure: it
# returns the list and prints nothing.  Each prints one line R<id>[...] that appears only when the program ran.
#   $Acct the account directory (C:\ProgramData\SD\user_accounts\<name>), $Out the folder outside it for that account.
function Get-WitDProbes([string]$Acct, [string]$Out) {
    $ospathLine = { param($id, $expr) @('$include err.h', ('   x = ' + $expr),
                    (("   crt 'R" + $id + "[':x:'|':status():'|':") + '(status() = ER$PERM):'']'''), 'end') }
    $tempLines = { param($id, $arg) @('$include err.h', "   taken = 'else'", ('   opentemp ' + $arg + " to f then taken = 'then' else null"),
                   '   st = status()', "   p = '' ; b = '' ; a = ''", "   if taken = 'then' then", "      write 'x' on f, 'r1'",
                   '      p = fileinfo(f, 2)', '      b = ospath(p, 2)', '      close f', '      a = ospath(p, 2)', '   end',
                   (("   crt 'R" + $id + "[':taken:'|':st:'|':") + '(st = ER$PERM):''|'':p:''|'':b:''|'':a:'']'''), 'end') }
    $q = { param($p) "'" + $p + "'" }
    $list = @(
        @{ Id = 'g2';  Name = 'zzwg2';  Kind = 'ospath'; Lines = (& $ospathLine 'g2' ('ospath(' + (& $q (Join-Path $Out 'o.txt')) + ', 2)')) }
        @{ Id = 'g5';  Name = 'zzwg5';  Kind = 'ospath'; Lines = (& $ospathLine 'g5' ('ospath(' + (& $q (Join-Path $Out 'd5.txt')) + ', 5)')) }
        @{ Id = 'g13'; Name = 'zzwg13'; Kind = 'ospath'; Lines = (& $ospathLine 'g13' ('ospath(' + (& $q (Join-Path $Out 'm13')) + ', 13)')) }
        @{ Id = 'g18'; Name = 'zzwg18'; Kind = 'ospath'; Lines = (& $ospathLine 'g18' ('ospath(' + (& $q (Join-Path $Out 'o.txt')) + ', 18)')) }
        @{ Id = 'j2';  Name = 'zzwj2';  Kind = 'ospath'; Lines = (& $ospathLine 'j2' ('ospath(' + (& $q (Join-Path $Acct 'zzjunc\o.txt')) + ', 2)')) }
        @{ Id = 'j5';  Name = 'zzwj5';  Kind = 'ospath'; Lines = (& $ospathLine 'j5' ('ospath(' + (& $q (Join-Path $Acct 'zzjunc\j5.txt')) + ', 5)')) }
        @{ Id = 'dg';  Name = 'zzwdg';  Kind = 'digest'; Lines = (& $ospathLine 'dg' ('digest(' + (& $q (Join-Path $Out 'o.txt')) + ", @true, 'SHA256')")) }
        @{ Id = 'dj';  Name = 'zzwdj';  Kind = 'digest'; Lines = (& $ospathLine 'dj' ('digest(' + (& $q (Join-Path $Acct 'zzjunc\o.txt')) + ", @true, 'SHA256')")) }
        @{ Id = 'di';  Name = 'zzwdi';  Kind = 'digest'; Lines = (& $ospathLine 'di' ('digest(' + (& $q (Join-Path $Acct 'zzin.txt')) + ", @true, 'SHA256')")) }
        @{ Id = 't1';  Name = 'zzwt1';  Kind = 'temp';   Lines = (& $tempLines 't1' '') }
        @{ Id = 't5';  Name = 'zzwt5';  Kind = 'temp';   Lines = (& $tempLines 't5' (& $q (Join-Path $Out 't5.tmp'))) }
        @{ Id = 't2';  Name = 'zzwt2';  Kind = 'temp2';  Lines = @(
               "   opentemp to f1 then t1 = 'then' else t1 = 'else'", "   opentemp to f2 then t2 = 'then' else t2 = 'else'",
               "   p1 = '' ; p2 = ''", "   if t1 = 'then' then p1 = fileinfo(f1, 2)", "   if t2 = 'then' then p2 = fileinfo(f2, 2)",
               "   if t1 = 'then' then close f1", "   if t2 = 'then' then close f2",
               "   crt 'Rt2[':t1:'|':t2:'|':p1:'|':p2:'|':system(38):']'", 'end') }
    )
    return $list
}

# Reads one probe's R<id>[...] line from SD's output: the fields, or $null when the program did not print it.
function Get-WitProbeFields([string]$Text, [string]$Id) {
    $m = [regex]::Match($Text, ('(?m)^\s*R' + [regex]::Escape($Id) + '\[(.*)\]\s*$'))
    if (-not $m.Success) { return $null }
    return ,@($m.Groups[1].Value -split '\|')
}

# A BASIC source record written into an account's bp (a directory file): LF line ends, no BOM, as SD writes them.
function Write-WitBasic([string]$AccountDir, [string]$Name, [string[]]$Lines) {
    $bp = Join-Path $AccountDir 'bp'
    if (-not (Test-Path -LiteralPath $bp)) { throw ('no bp at ' + $bp) }
    $txt = (($Lines -join "`n") + "`n")
    [IO.File]::WriteAllText((Join-Path $bp $Name), $txt, (New-Object Text.UTF8Encoding($false)))
}
