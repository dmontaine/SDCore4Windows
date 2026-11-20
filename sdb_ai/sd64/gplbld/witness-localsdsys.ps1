# witness-localsdsys.ps1 - RELEASE_1.1 339 (Linux S.267) on a REAL install: SDSYS reached from this computer by the Windows users the
# administrator lists (local.sdsys ssh / api).  The Windows reading of Linux's gplbld/witness-localsdsys.sh (rows L0-L15), with the rows
# W0-W20 of .claude/localsdsys/DESIGN.md section 8 and the reused-pid row Linux asked for (T0745 Q8) as W21.
#
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-localsdsys.ps1 -Only setup,W5,W0 [-User sdlocalw]
#              [-Unlisted sdlocalx] [-Lan 192.168.56.101] [-WatchSeconds 180]
#
# WHERE: a fresh VM clone with this Core installed, an ELEVATED PowerShell, signed in as the VM's own account.  A SECOND window (an ordinary
# PowerShell, not elevated) is where the person types the ssh commands; the script prints, row by row, exactly what to type there and what to
# answer at each prompt, then waits for Enter and judges from what the system wrote:
#   C:\ProgramData\SD\sdsvc.log           the SD service's door: "sdsys local: refused <word> for pid <P> user <DOMAIN\name>: ..." and
#                                         "sdsys local: started the SDSYS session pid <S> for pid <P> user <DOMAIN\name> (<name>), ..."
#                                         (gplsrc/sdsvc/sdsyslocal.c sl_refuse, sl_serve_one)
#   <SDSYS dir>\audit                     LOGIN's and APISRVR's lines (sdsys/gpl.bp/login sdsys.local, apisrvr's loopback branch)
#   <ProgramData>\SD\sd-tls\sdsys-local-ssh / -api   the two lists, through C:\Program Files\SD\sd-sdsyslocal.ps1
#   OpenSSH/Operational event 4          sshd's own "Accepted <method> for <user> from <addr> port <n>" and its ProcessID
# A secret is never written anywhere by this script: the person types SDSYS's SD password and the test users' Windows passwords into the
# windows that ask for them; rows that start a program AS a test user (W13-W16, W20) ask for that user's Windows password here, with no
# echo, and hold it only in memory for that run.
#
# SECTIONS (-Only is REQUIRED; names are case-blind; several are run in the order below):
#   setup  the two test users (made if absent; the person chooses their Windows passwords) in Users, sdusers and sdssh; the install's
#          facts (sd.exe, the SD and sshd services, the door's "serving" line, the helper, the lists, the OpenSSH channel)
#   W0     MEASURE FIRST (F1-F3): an ssh -t <User>@localhost sd-sdsys while the script watches - the real chain sd.exe -> ... -> the
#          per-connection sshd A -> the sshd service, with images, token users, logon ids and types, creation times; A's event 4; the TCP
#          row; the door's own verdict; the SDSYS child the service started
#   W1     grant: the RIGHT SD password of sdsys -> 15177, audit "elevation granted reason=sdsys local ssh user=<User>"
#   W2     a WRONG SD password -> 15175, audit "elevation refused reason=sdsys local ssh wrong password user=<User>"
#   W3     sdsys with NO SD password -> 15176, audit "... no credential ..." (only on an install where sdsys has none yet)
#   W4     an unlisted user (-Unlisted) -> sdsvc.log "refused not-listed", SD never ran
#   W5     the list empty -> sdsvc.log "refused list-empty", nothing in the audit trail
#   W6     the listed user from this VM's own LAN address -> "refused not-local"
#   W7     the listed user from the HOST over the network -> "refused not-local"
#   W8     sd.exe run by hand at the console as the listed user with SSH_ORIGINAL_COMMAND/SSH_CONNECTION set -> "refused not-ssh"
#   W9     sd-sdsys started from inside an SD session (SH, an account with sh-on) -> "refused session-unsafe"
#   W10    a PHANTOM from the granted SDSYS session -> refused by LOGIN (audit "... SDSYS requires an elevated session why=<word>")
#   W11    plain ssh -t <User>@localhost (no command) is the ordinary session, untouched; ssh without -t asking sd-sdsys gets one line
#   W12    an unsafe list (a grant to Users added by hand) -> status "unsafe, treated as none listed", "refused list-unsafe"; clear repairs
#   W13    API: a listed user's program at 127.0.0.1 signs in as sdsys -> audit "elevation granted reason=sdsys api from=this machine user="
#   W14    API: an unlisted user's program -> refused, audit "... opened by <Unlisted> from this machine why=not-listed"
#   W15    API: remote.sdsys api "any" does not admit a loopback peer; the address helper refuses 127.0.0.1 and ::1
#   W16    API: the listed user's program in its own interactive logon (runas's CreateProcessWithLogonW) is admitted, logon recorded (D6)
#   W17    tool.remote U / X / C on the Remote admin view (the person, in an SDSYS session) -> the local.sdsys audit lines and the file
#   W18    an upgrade keeps both lists (two phases: before, then after the person's upgrade install)
#   W19    a full uninstall removes both lists (two phases: before, then after the person's uninstall)
#   W20    a fake OpenSSH/Operational "Accepted ... from ::1" written BY THE USER carries the writer's pid (F4) and does not open the door
#   W21    the reused-pid attack on the API's peer lookup (T0745 Q8): its OS premise staged on a listener of this script's own; SD's door
#          itself is NOT RUN (the reason is printed)
#   cleanup  both lists cleared; the test users are left in place (named)
#
# VERDICTS: PASS, FAIL, NOT RUN (with the reason - a row that could not run is never PASS), INFO (a measurement with no pass mark).
# A PASS needs the success wording or the measured state AND none of the failure wording.  Exit 0: at least one PASS and no FAIL;
# 1: any FAIL; 2: nothing was measured or the script could not run.  It never ends an SD process.
#
# START-HISTORY:
# 18 Nov 26  New, RELEASE_1.1 339.  Parse-checked only; NOT RUN (it needs the VM).
# END-HISTORY

param(
    [string[]]$Only = @(),
    [string]$User = 'sdlocalw',
    [string]$Unlisted = 'sdlocalx',
    [string]$Lan = '',
    [int]$WatchSeconds = 180
)

$ErrorActionPreference = 'Continue'

$Known = @('setup', 'w0', 'w1', 'w2', 'w3', 'w4', 'w5', 'w6', 'w7', 'w8', 'w9', 'w10', 'w11', 'w12', 'w13', 'w14', 'w15', 'w16', 'w17',
           'w18', 'w19', 'w20', 'w21', 'cleanup')

# ---------------------------------------------------------------------------------------------------------------- the places

$AppDir = Join-Path $env:ProgramFiles 'SD'
$SdExe = Join-Path $AppDir 'usr\bin\sd.exe'
$DataDir = Join-Path $env:ProgramData 'SD'
$TlsDir = Join-Path $DataDir 'sd-tls'
$SshList = Join-Path $TlsDir 'sdsys-local-ssh'
$ApiList = Join-Path $TlsDir 'sdsys-local-api'
$SvcLog = Join-Path $DataDir 'sdsvc.log'
$SdConf = Join-Path $DataDir 'sd.conf'
$Root = 'C:\SD-witness'
$Work = Join-Path $Root 'localsdsys'
$OutDir = Join-Path $Work 'out'
$SysDir = Join-Path $env:SystemRoot 'System32'
$Script:Log = ''
$Script:Results = New-Object System.Collections.ArrayList

# ---------------------------------------------------------------------------------------------------------------- native reads

if (-not ('SdLsw.Native' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;

namespace SdLsw
{
    public class ProcRow { public uint Pid; public uint Ppid; public string Name = ""; }

    public class ProcFacts
    {
        public uint Pid; public int Error; public string Stage = ""; public bool Alive;
        public string Image = ""; public long Created; public string UserSid = ""; public string UserName = "";
        public uint LogonLow; public int LogonHigh; public string Source = ""; public int Elevated = -1; public int Session = -1;
        public string Integrity = ""; public bool IsSystem;
    }

    public class LogonFacts
    {
        public int Status = -1; public uint Type; public uint Session; public string Sid = ""; public string User = "";
        public string Domain = ""; public string Package = "";
    }

    public class SpinResult { public bool Found; public int Tries; public uint LastPid; public long Created; public int Error; }

    public static class Native
    {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct PROCESSENTRY32W
        {
            public uint dwSize; public uint cntUsage; public uint th32ProcessID; public IntPtr th32DefaultHeapID; public uint th32ModuleID;
            public uint cntThreads; public uint th32ParentProcessID; public int pcPriClassBase; public uint dwFlags;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] public string szExeFile;
        }
        [StructLayout(LayoutKind.Sequential)] struct LUID { public uint Low; public int High; }
        [StructLayout(LayoutKind.Sequential)] struct LUID_AND_ATTRIBUTES { public LUID Luid; public uint Attributes; }
        [StructLayout(LayoutKind.Sequential)] struct TOKEN_PRIVILEGES1 { public uint Count; public LUID_AND_ATTRIBUTES P; }
        [StructLayout(LayoutKind.Sequential)] struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
        [StructLayout(LayoutKind.Sequential)]
        struct SECURITY_LOGON_SESSION_DATA
        {
            public uint Size; public LUID LogonId; public LSA_UNICODE_STRING UserName; public LSA_UNICODE_STRING LogonDomain;
            public LSA_UNICODE_STRING AuthenticationPackage; public uint LogonType; public uint Session; public IntPtr Sid; public long LogonTime;
        }
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        struct STARTUPINFO
        {
            public int cb; public string lpReserved; public string lpDesktop; public string lpTitle; public int dwX; public int dwY;
            public int dwXSize; public int dwYSize; public int dwXCountChars; public int dwYCountChars; public int dwFillAttribute;
            public int dwFlags; public short wShowWindow; public short cbReserved2; public IntPtr lpReserved2; public IntPtr hStdInput;
            public IntPtr hStdOutput; public IntPtr hStdError;
        }
        [StructLayout(LayoutKind.Sequential)] struct PROCESS_INFORMATION { public IntPtr hProcess; public IntPtr hThread; public uint dwProcessId; public uint dwThreadId; }

        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr CreateToolhelp32Snapshot(uint flags, uint pid);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool Process32FirstW(IntPtr snap, ref PROCESSENTRY32W e);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool Process32NextW(IntPtr snap, ref PROCESSENTRY32W e);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool CloseHandle(IntPtr h);
        [DllImport("kernel32.dll", SetLastError = true)] static extern IntPtr OpenProcess(uint access, bool inherit, uint pid);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetExitCodeProcess(IntPtr h, out uint code);
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool GetProcessTimes(IntPtr h, out long c, out long e, out long k, out long u);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool QueryFullProcessImageNameW(IntPtr h, int flags, StringBuilder name, ref int size);
        [DllImport("kernel32.dll")] static extern IntPtr GetCurrentProcess();
        [DllImport("kernel32.dll", SetLastError = true)] static extern bool TerminateProcess(IntPtr h, uint code);
        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        static extern bool CreateProcessW(string app, StringBuilder cmd, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string dir, ref STARTUPINFO si, out PROCESS_INFORMATION pi);
        [DllImport("kernel32.dll")] static extern IntPtr LocalFree(IntPtr p);
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool OpenProcessToken(IntPtr proc, uint access, out IntPtr token);
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool GetTokenInformation(IntPtr token, int cls, IntPtr buf, int len, out int ret);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool ConvertSidToStringSidW(IntPtr sid, out IntPtr str);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)] static extern bool LookupPrivilegeValueW(string sys, string name, out LUID luid);
        [DllImport("advapi32.dll", SetLastError = true)] static extern bool AdjustTokenPrivileges(IntPtr tok, bool all, ref TOKEN_PRIVILEGES1 np, int len, IntPtr prev, IntPtr ret);
        [DllImport("secur32.dll")] static extern int LsaGetLogonSessionData(ref LUID id, out IntPtr data);
        [DllImport("secur32.dll")] static extern int LsaFreeReturnBuffer(IntPtr p);

        static List<IntPtr> held = new List<IntPtr>();

        // SeDebugPrivilege on for this process (an elevated administrator has it, disabled).  0, 1300 (not held) or the error.
        public static int EnableDebug()
        {
            IntPtr tok;
            if (!OpenProcessToken(GetCurrentProcess(), 0x0020 | 0x0008, out tok)) return Marshal.GetLastWin32Error();
            try
            {
                LUID l;
                if (!LookupPrivilegeValueW(null, "SeDebugPrivilege", out l)) return Marshal.GetLastWin32Error();
                TOKEN_PRIVILEGES1 tp = new TOKEN_PRIVILEGES1();
                tp.Count = 1; tp.P.Luid = l; tp.P.Attributes = 2;
                if (!AdjustTokenPrivileges(tok, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero)) return Marshal.GetLastWin32Error();
                return Marshal.GetLastWin32Error();
            }
            finally { CloseHandle(tok); }
        }

        // The process table now: pid, parent pid, name.
        public static List<ProcRow> Snapshot()
        {
            List<ProcRow> list = new List<ProcRow>();
            IntPtr s = CreateToolhelp32Snapshot(2, 0);
            if (s == IntPtr.Zero || s == new IntPtr(-1)) return list;
            try
            {
                PROCESSENTRY32W e = new PROCESSENTRY32W();
                e.dwSize = (uint)Marshal.SizeOf(typeof(PROCESSENTRY32W));
                if (Process32FirstW(s, ref e))
                {
                    do { ProcRow r = new ProcRow(); r.Pid = e.th32ProcessID; r.Ppid = e.th32ParentProcessID; r.Name = e.szExeFile; list.Add(r); }
                    while (Process32NextW(s, ref e));
                }
            }
            finally { CloseHandle(s); }
            return list;
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
            if (sid == IntPtr.Zero || !ConvertSidToStringSidW(sid, out str)) return "";
            string s = Marshal.PtrToStringUni(str);
            LocalFree(str);
            return s;
        }

        static string Str(LSA_UNICODE_STRING s)
        {
            if (s.Buffer == IntPtr.Zero || s.Length == 0) return "";
            return Marshal.PtrToStringUni(s.Buffer, s.Length / 2);
        }

        // One process read through ONE handle: alive, creation time, image, and its token's user, logon id, source, elevation, session,
        // integrity.  Error/Stage say where a read stopped.
        public static ProcFacts Proc(uint pid)
        {
            ProcFacts f = new ProcFacts();
            f.Pid = pid;
            IntPtr h = OpenProcess(0x1000, false, pid);
            if (h == IntPtr.Zero) { f.Error = Marshal.GetLastWin32Error(); f.Stage = "OpenProcess"; return f; }
            try
            {
                uint code;
                if (GetExitCodeProcess(h, out code)) f.Alive = (code == 259);
                long c, e, k, u;
                if (GetProcessTimes(h, out c, out e, out k, out u)) f.Created = c;
                StringBuilder sb = new StringBuilder(1024);
                int n = sb.Capacity;
                if (QueryFullProcessImageNameW(h, 0, sb, ref n)) f.Image = sb.ToString();
                IntPtr tok;
                if (!OpenProcessToken(h, 0x0008 | 0x0010, out tok) && !OpenProcessToken(h, 0x0008, out tok))
                {
                    f.Error = Marshal.GetLastWin32Error(); f.Stage = "OpenProcessToken"; return f;
                }
                try
                {
                    IntPtr b = Info(tok, 1);
                    if (b != IntPtr.Zero) { f.UserSid = SidText(Marshal.ReadIntPtr(b)); Marshal.FreeHGlobal(b); }
                    b = Info(tok, 10);
                    if (b != IntPtr.Zero) { f.LogonLow = (uint)Marshal.ReadInt32(b, 8); f.LogonHigh = Marshal.ReadInt32(b, 12); Marshal.FreeHGlobal(b); }
                    b = Info(tok, 7);
                    if (b != IntPtr.Zero)
                    {
                        byte[] nm = new byte[8];
                        Marshal.Copy(b, nm, 0, 8);
                        f.Source = Encoding.ASCII.GetString(nm).TrimEnd((char)0, ' ');
                        Marshal.FreeHGlobal(b);
                    }
                    b = Info(tok, 20);
                    if (b != IntPtr.Zero) { f.Elevated = Marshal.ReadInt32(b); Marshal.FreeHGlobal(b); }
                    b = Info(tok, 12);
                    if (b != IntPtr.Zero) { f.Session = Marshal.ReadInt32(b); Marshal.FreeHGlobal(b); }
                    b = Info(tok, 25);
                    if (b != IntPtr.Zero) { f.Integrity = SidText(Marshal.ReadIntPtr(b)); Marshal.FreeHGlobal(b); }
                }
                finally { CloseHandle(tok); }
            }
            finally { CloseHandle(h); }
            f.IsSystem = (f.UserSid == "S-1-5-18");
            try { f.UserName = new SecurityIdentifier(f.UserSid).Translate(typeof(NTAccount)).Value; } catch { }
            return f;
        }

        // A logon session: its type, its own SID and user, its package.  Status is the NTSTATUS (0 = read).
        public static LogonFacts Logon(uint low, int high)
        {
            LogonFacts r = new LogonFacts();
            LUID l = new LUID();
            l.Low = low; l.High = high;
            IntPtr p;
            r.Status = LsaGetLogonSessionData(ref l, out p);
            if (r.Status != 0 || p == IntPtr.Zero) return r;
            try
            {
                SECURITY_LOGON_SESSION_DATA d = (SECURITY_LOGON_SESSION_DATA)Marshal.PtrToStructure(p, typeof(SECURITY_LOGON_SESSION_DATA));
                r.Type = d.LogonType; r.Session = d.Session; r.Sid = SidText(d.Sid); r.User = Str(d.UserName);
                r.Domain = Str(d.LogonDomain); r.Package = Str(d.AuthenticationPackage);
            }
            finally { LsaFreeReturnBuffer(p); }
            return r;
        }

        // Starts EXE suspended (no window) until one gets pid TARGET, keeping every miss alive so the next start takes a new pid.  The
        // match is kept suspended and alive (ReleaseHeld ends it and every miss).
        public static SpinResult SpinForPid(uint target, string exe, int maxTries, int maxMs)
        {
            SpinResult r = new SpinResult();
            System.Diagnostics.Stopwatch sw = System.Diagnostics.Stopwatch.StartNew();
            string q = ((char)34).ToString();
            while (r.Tries < maxTries && sw.ElapsedMilliseconds < maxMs)
            {
                r.Tries++;
                STARTUPINFO si = new STARTUPINFO();
                si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
                PROCESS_INFORMATION pi;
                StringBuilder cmd = new StringBuilder(q + exe + q);
                if (!CreateProcessW(null, cmd, IntPtr.Zero, IntPtr.Zero, false, 0x00000004 | 0x08000000, IntPtr.Zero, null, ref si, out pi))
                {
                    r.Error = Marshal.GetLastWin32Error();
                    return r;
                }
                CloseHandle(pi.hThread);
                held.Add(pi.hProcess);
                r.LastPid = pi.dwProcessId;
                if (pi.dwProcessId == target)
                {
                    long c, e, k, u;
                    if (GetProcessTimes(pi.hProcess, out c, out e, out k, out u)) r.Created = c;
                    r.Found = true;
                    return r;
                }
            }
            return r;
        }

        public static int ReleaseHeld()
        {
            int n = 0;
            foreach (IntPtr h in held) { TerminateProcess(h, 1); CloseHandle(h); n++; }
            held.Clear();
            return n;
        }
    }
}
'@
}

# ---------------------------------------------------------------------------------------------------------------- printing and verdicts
# Every function here prints with Write-Host only, so a returned value is never folded into printed lines (the function output trap).

function Say([string]$Text = '') {
    Write-Host $Text
    if ($Script:Log -ne '') { try { Add-Content -LiteralPath $Script:Log -Value $Text -Encoding UTF8 } catch { } }
}

function SayRaw([string]$Label, [string]$Text) {
    Say ('    --- ' + $Label + ' (raw) ---')
    if ([string]::IsNullOrEmpty($Text)) { Say '    | <nothing>' } else { foreach ($l in ($Text -split "`r?`n")) { Say ('    | ' + $l.TrimEnd()) } }
    Say '    --- end ---'
}

function Add-Row {
    param([string]$Row, [string]$Check, [ValidateSet('PASS', 'FAIL', 'NOT RUN', 'INFO')][string]$Verdict, [string]$Evidence = '')
    $null = $Script:Results.Add([pscustomobject]@{ Row = $Row; Check = $Check; Verdict = $Verdict; Evidence = $Evidence })
    Say ('  [{0}] {1}: {2}' -f $Verdict, $Row, $Check)
    if ($Evidence -ne '') { Say ('         evidence: ' + $Evidence) }
}

# Scores lines against a success pattern and failure patterns (regex, case-blind).  No lines at all is NOT RUN, never PASS.
function Set-Verdict {
    param([string]$Row, [string]$Check, [string[]]$Lines, [string]$Success, [string[]]$Failure = @(), [string]$Source = '')
    $all = @($Lines | Where-Object { $_ -ne $null -and $_ -ne '' })
    if ($all.Count -eq 0) { Add-Row $Row $Check 'NOT RUN' ('nothing new was written to ' + $Source + ' - nothing to judge'); return }
    foreach ($f in $Failure) {
        $bad = @($all | Where-Object { $_ -match $f })
        if ($bad.Count -gt 0) { Add-Row $Row $Check 'FAIL' ('failure wording /' + $f + '/ in ' + $Source + ': ' + $bad[0]); return }
    }
    $hit = @($all | Where-Object { $_ -match $Success })
    if ($hit.Count -gt 0) { Add-Row $Row $Check 'PASS' ('success wording /' + $Success + '/ in ' + $Source + ': ' + $hit[0]); return }
    Add-Row $Row $Check 'FAIL' ('the success wording /' + $Success + '/ is not in ' + $Source + ' (' + $all.Count + ' new line(s), printed above)')
}

# The person's own observation, recorded as such.  y PASS, n FAIL, anything else NOT RUN.
function Set-PersonVerdict([string]$Row, [string]$Check, [string]$Question) {
    $a = (Read-Host ('  QUESTION (' + $Row + '): ' + $Question + ' [y/n, or Enter if you could not tell]')).Trim().ToLower()
    Say ('  the person answered: ''' + $a + '''')
    if ($a -eq 'y') { Add-Row $Row $Check 'PASS' 'the person saw it in the second window and answered y' }
    elseif ($a -eq 'n') { Add-Row $Row $Check 'FAIL' 'the person answered n: it was NOT shown' }
    else { Add-Row $Row $Check 'NOT RUN' 'the person could not tell' }
}

function Complete-Run {
    Say ''
    Say ('==== SUMMARY witness-localsdsys (' + $Script:Results.Count + ' results)')
    foreach ($x in $Script:Results) { Say ('  {0,-8} {1,-8} {2}' -f $x.Row, $x.Verdict, $x.Check) }
    $n = @{}
    foreach ($v in 'PASS', 'FAIL', 'NOT RUN', 'INFO') { $n[$v] = @($Script:Results | Where-Object { $_.Verdict -eq $v }).Count }
    Say ('  PASS {0}   FAIL {1}   NOT RUN {2}   INFO {3}' -f $n['PASS'], $n['FAIL'], $n['NOT RUN'], $n['INFO'])
    $csv = $Script:Log -replace '\.log$', '.results.csv'
    try { $Script:Results | Export-Csv -LiteralPath $csv -NoTypeInformation -Encoding UTF8; Say ('  results: ' + $csv) } catch { }
    $code = 0
    if ($n['FAIL'] -gt 0) { $code = 1 }
    elseif ($n['PASS'] -eq 0) { Say '  NOTHING PASSED OR FAILED - this run is not a result (exit 2).'; $code = 2 }
    Say ('  log: ' + $Script:Log + '   exit ' + $code)
    return $code
}

# ---------------------------------------------------------------------------------------------------------------- files read from a mark

function Get-Mark([string]$Path) { try { return (Get-Item -LiteralPath $Path -ErrorAction Stop).Length } catch { return [long]-1 } }

# The lines written to PATH past MARK (a file shorter than the mark was rotated or rewritten: read from 0).  ENC 'ansi' or 'utf8'.
function Get-Since([string]$Path, [long]$Mark, [string]$Enc = 'utf8') {
    $txt = ''
    try {
        $fs = New-Object IO.FileStream($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
        try {
            $from = $Mark
            if ($from -lt 0 -or $from -gt $fs.Length) { $from = 0 }
            $null = $fs.Seek($from, [IO.SeekOrigin]::Begin)
            $e = [Text.Encoding]::UTF8
            if ($Enc -eq 'ansi') { $e = [Text.Encoding]::Default }
            $sr = New-Object IO.StreamReader($fs, $e)
            $txt = $sr.ReadToEnd()
            $sr.Dispose()
        } finally { $fs.Dispose() }
    } catch { return @('<unreadable ' + $Path + ': ' + $_.Exception.Message + '>') }
    return @($txt -split "`r?`n" | Where-Object { $_ -ne '' })
}

function Get-AuditPath {
    $sys = Join-Path $DataDir 'sdsys'
    try {
        $m = [regex]::Match([IO.File]::ReadAllText($SdConf), '(?m)^\s*SDSYS\s*=\s*(.+?)\s*$')
        if ($m.Success) { $sys = $m.Groups[1].Value.Trim('"') }
    } catch { }
    return (Join-Path $sys 'audit')
}

# Marks of the two logs, taken before a person's step.  @{ Svc; Audit; Time }
function New-Marks {
    $m = @{ Svc = (Get-Mark $SvcLog); Audit = (Get-Mark $Script:Audit); Time = (Get-Date) }
    Say ('  marks: sdsvc.log at byte ' + $m.Svc + ', audit at byte ' + $m.Audit + ', time ' + $m.Time.ToString('s'))
    return $m
}

# What both logs got since the marks, printed in full.  @{ Svc (only "sdsys local:" lines); SvcAll; Audit }
function Read-Since($Marks) {
    $svcAll = @(Get-Since $SvcLog $Marks.Svc 'ansi')
    $svc = @($svcAll | Where-Object { $_ -match 'sdsys local:' })
    $aud = @(Get-Since $Script:Audit $Marks.Audit 'utf8')
    SayRaw ('sdsvc.log since the mark (' + $SvcLog + ')') ($svcAll -join "`n")
    SayRaw ('audit since the mark (' + $Script:Audit + ')') ($aud -join "`n")
    return @{ Svc = $svc; SvcAll = $svcAll; Audit = $aud }
}

# ---------------------------------------------------------------------------------------------------------------- the person

# Prints what the person does in which window, then waits.  $true when done, $false when the person typed skip.
function Wait-Person([string]$Row, [string[]]$Lines) {
    Say ''
    Say ('  ---- PERSON, row ' + $Row + ' ----')
    foreach ($l in $Lines) { Say ('    ' + $l) }
    $a = (Read-Host ('  Press Enter HERE when that is done (or type skip)')).Trim().ToLower()
    if ($a -eq 'skip') { Say '  the person typed skip'; return $false }
    return $true
}

function Read-Secret([string]$Prompt) { return (Read-Host -AsSecureString $Prompt) }

function Get-Plain([Security.SecureString]$S) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($S)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

# ---------------------------------------------------------------------------------------------------------------- the helper and the lists

function Find-Shipped([string]$Name) {
    $p = Join-Path $AppDir $Name
    if (Test-Path -LiteralPath $p) { return $p }
    $f = Get-ChildItem -LiteralPath $AppDir -Filter $Name -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -ne $f) { return $f.FullName }
    return ''
}

# Runs one of SD's shipped PowerShell helpers as a separate process, as an elevated administrator.  @{ Code; Text }; prints both.
function Invoke-Helper([string]$Path, [string[]]$HelperArgs) {
    if ($Path -eq '' -or -not (Test-Path -LiteralPath $Path)) {
        Say ('  > (the helper is not installed: ''' + $Path + ''')')
        return @{ Code = -1; Text = '' }
    }
    if ($null -eq $HelperArgs -or $HelperArgs.Count -eq 0) { Say '  > (Invoke-Helper was handed no arguments - refused)'; return @{ Code = -1; Text = '' } }
    $al = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $Path) + $HelperArgs
    Say ('  > powershell.exe ' + ($al -join ' '))
    $o = & powershell.exe @al 2>&1 | ForEach-Object { [string]$_ }
    $code = $LASTEXITCODE
    $t = ($o -join "`n")
    SayRaw ('helper, exit ' + $code) $t
    return @{ Code = $code; Text = $t }
}

function Get-ListSddl([string]$Path) {
    try { return (Get-Acl -LiteralPath $Path -ErrorAction Stop).Sddl } catch { return '(' + $_.Exception.Message + ')' }
}

# Both lists as they are on disk: present or absent, owner and DACL, the entries (names and SIDs - nothing secret).
function Show-Lists([string]$When) {
    foreach ($p in @($SshList, $ApiList)) {
        if (Test-Path -LiteralPath $p) {
            $txt = ''
            try { $txt = ([IO.File]::ReadAllText($p)).Replace("`n", ' | ') } catch { $txt = '(unreadable: ' + $_.Exception.Message + ')' }
            Say ('  ' + $When + ': ' + $p + ' PRESENT, sddl ' + (Get-ListSddl $p) + ', text: ' + $txt)
        } else {
            Say ('  ' + $When + ': ' + $p + ' absent')
        }
    }
}

# The entries of a list file as name strings ('' when absent or unreadable).
function Get-ListNames([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    try { return @(([IO.File]::ReadAllText($Path) -split "`n") | Where-Object { $_.Trim() -ne '' } | ForEach-Object { ($_.Trim() -split ' ')[0] }) } catch { return @() }
}

# Makes sure NAME is on list KIND (ssh|api).  $true when it is (already or now).
function Set-Listed([string]$Kind, [string]$Name) {
    $path = $SshList
    if ($Kind -eq 'api') { $path = $ApiList }
    if (@(Get-ListNames $path | Where-Object { $_ -ieq $Name }).Count -gt 0) { Say ('  ' + $Name + ' is on the ' + $Kind + ' list already'); return $true }
    $r = Invoke-Helper $Script:Helper @('-List', $Kind, '-Action', 'add', '-Name', $Name)
    $ok = ($r.Code -eq 0 -and $r.Text -match ('sdsys local ' + $Kind + ': added ' + [regex]::Escape($Name) + '; listed now:'))
    if (-not $ok) { Say ('  could NOT put ' + $Name + ' on the ' + $Kind + ' list (exit ' + $r.Code + ')') }
    return $ok
}

# ---------------------------------------------------------------------------------------------------------------- processes and services

function Format-Ft([long]$Ft) { if ($Ft -le 0) { return '?' } return ([DateTime]::FromFileTimeUtc($Ft).ToString('yyyy-MM-dd HH:mm:ss.fffffff') + 'Z') }

function Get-SvcPid([string]$Name) {
    try { $s = Get-CimInstance Win32_Service -Filter ("Name='" + $Name + "'") -ErrorAction Stop; return [uint32]$s.ProcessId } catch { return [uint32]0 }
}

function Get-CmdLine([uint32]$ProcId) {
    try { return [string](Get-CimInstance Win32_Process -Filter ('ProcessId=' + $ProcId) -ErrorAction Stop).CommandLine } catch { return '' }
}

# One line about a process and its logon: what was read, and what could not be.
function Format-Proc($F, $L) {
    $t = ('pid ' + $F.Pid + '  image ' + $F.Image + '  created ' + (Format-Ft $F.Created) + '  alive ' + $F.Alive + '  user ' + $F.UserName +
          ' (' + $F.UserSid + ')  logon 0x' + ('{0:x}' -f $F.LogonHigh) + ':' + ('{0:x8}' -f $F.LogonLow) + '  source ''' + $F.Source +
          '''  elevated ' + $F.Elevated + '  session ' + $F.Session + '  integrity ' + $F.Integrity)
    if ($F.Error -ne 0) { $t += ('  READ STOPPED at ' + $F.Stage + ' error ' + $F.Error) }
    if ($null -ne $L) {
        if ($L.Status -eq 0) { $t += ('  | logon type ' + $L.Type + ' sid ' + $L.Sid + ' ' + $L.Domain + '\' + $L.User + ' package ' + $L.Package + ' session ' + $L.Session) }
        else { $t += ('  | logon session NOT READ (NTSTATUS 0x' + ('{0:x8}' -f $L.Status) + ')') }
    }
    return $t
}

# The chain from PROCID up to the sshd service (or the top), each step read now.  An array of @{ Pid; Ppid; Name; F; L }.
function Get-Chain([uint32]$ProcId, $Snap, [uint32]$SshdSvc) {
    $by = @{}
    foreach ($r in $Snap) { $by[[uint32]$r.Pid] = $r }
    $chain = New-Object System.Collections.ArrayList
    $cur = $ProcId
    for ($i = 0; $i -lt 12 -and $cur -ne 0; $i++) {
        $f = [SdLsw.Native]::Proc($cur)
        $l = $null
        if ($f.UserSid -ne '') { $l = [SdLsw.Native]::Logon($f.LogonLow, $f.LogonHigh) }
        $row = $by[$cur]
        $pp = [uint32]0
        $nm = '?'
        if ($null -ne $row) { $pp = [uint32]$row.Ppid; $nm = $row.Name }
        $null = $chain.Add(@{ Pid = $cur; Ppid = $pp; Name = $nm; F = $f; L = $l })
        if ($cur -eq $SshdSvc) { break }
        $cur = $pp
    }
    return , $chain.ToArray()
}

function Show-Chain($Chain) {
    $i = 0
    foreach ($c in $Chain) {
        Say ('    [' + $i + '] ' + $c.Name + ' ppid ' + $c.Ppid + '  ' + (Format-Proc $c.F $c.L))
        $i++
    }
}

# OpenSSH/Operational event 4 since a time, printed.  An array of @{ Time; ProcId; Msg }.
function Get-SshdAccepted([DateTime]$Since) {
    $out = New-Object System.Collections.ArrayList
    try {
        $evs = @(Get-WinEvent -FilterHashtable @{ LogName = 'OpenSSH/Operational'; Id = 4; StartTime = $Since } -ErrorAction Stop)
        foreach ($e in $evs) { $null = $out.Add(@{ Time = $e.TimeCreated; ProcId = [uint32]$e.ProcessId; Msg = [string]$e.Message }) }
    } catch {
        if ($_.Exception.Message -notmatch 'No events were found') { Say ('  OpenSSH/Operational could not be read: ' + $_.Exception.Message) }
    }
    foreach ($e in $out) { Say ('    event 4  ' + $e.Time.ToUniversalTime().ToString('yyyy-MM-dd HH:mm:ss.fffffff') + 'Z  ProcessID ' + $e.ProcId + '  ' + $e.Msg) }
    if ($out.Count -eq 0) { Say '    (no OpenSSH/Operational event 4 since then)' }
    return , $out.ToArray()
}

function Test-Loopback([string]$A) {
    if ($A -eq '::1') { return $true }
    $x = $A
    if ($x -like '::ffff:*') { $x = $x.Substring(7) }
    return ($x -match '^127\.\d{1,3}\.\d{1,3}\.\d{1,3}$')
}

# ---------------------------------------------------------------------------------------------------------------- a program as a test user

# Writes the runner scripts this run uses into $Work (no secret in them).  Returns nothing.
function Write-Runners {
    $runner = @(
        '# written by witness-localsdsys.ps1: runs the program its spec names, prints its output, then stays 5 s so the token can be read',
        'param([string]$Spec)',
        '$s = Get-Content -LiteralPath $Spec -Raw | ConvertFrom-Json',
        '[Console]::Out.WriteLine(''runner pid '' + $PID + '' user '' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)',
        '$list = @($s.Argv)',
        '$o = & $s.Exe @list 2>&1',
        'foreach ($l in @($o)) { [Console]::Out.WriteLine([string]$l) }',
        '[Console]::Out.WriteLine(''runner exit '' + $LASTEXITCODE)',
        'Start-Sleep -Seconds ([int]$s.Hold)')
    Set-Content -LiteralPath (Join-Path $Work 'run-as.ps1') -Value $runner -Encoding ASCII
    $writer = @(
        '# written by witness-localsdsys.ps1: writes ONE event to the channel its spec names, as whoever runs it, and says what happened',
        'param([string]$Spec)',
        '$s = Get-Content -LiteralPath $Spec -Raw | ConvertFrom-Json',
        '[Console]::Out.WriteLine(''writer pid '' + $PID + '' user '' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)',
        'try { New-WinEvent -ProviderName $s.Provider -Id ([int]$s.Id) -Payload @($s.Payload) -ErrorAction Stop; [Console]::Out.WriteLine(''written'') }',
        'catch { [Console]::Out.WriteLine(''refused: '' + $_.Exception.Message) }',
        'Start-Sleep -Seconds ([int]$s.Hold)')
    Set-Content -LiteralPath (Join-Path $Work 'write-event.ps1') -Value $writer -Encoding ASCII
}

# Runs SCRIPT (in $Work) with a spec, as Windows user NAME with password PW (a SecureString), in that user's own interactive logon
# (CreateProcessWithLogonW, as runas does).  ENV is extra environment (the SD password of sdsys for the API rows - never printed).
# Reads the runner's token and logon while it holds.  @{ Ok; Why; Code; Out; ProcId; F; L }
function Start-AsUser([string]$Name, [Security.SecureString]$Pw, [string]$RunnerFile, $SpecObj, [hashtable]$Extra, [int]$TimeoutSec = 120) {
    $res = @{ Ok = $false; Why = ''; Code = -1; Out = ''; ProcId = 0; F = $null; L = $null }
    $spec = Join-Path $OutDir ('spec-' + [Guid]::NewGuid().ToString('N') + '.json')
    ($SpecObj | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $spec -Encoding ASCII
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = Join-Path $SysDir 'WindowsPowerShell\v1.0\powershell.exe'
    $psi.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "' + (Join-Path $Work $RunnerFile) + '" -Spec "' + $spec + '"')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.WorkingDirectory = $Work
    $psi.UserName = $Name
    $psi.Domain = $env:COMPUTERNAME
    $psi.Password = $Pw
    $psi.LoadUserProfile = $true
    $psi.EnvironmentVariables['TEMP'] = $OutDir
    $psi.EnvironmentVariables['TMP'] = $OutDir
    $shown = @()
    foreach ($k in $Extra.Keys) { $psi.EnvironmentVariables[$k] = [string]$Extra[$k]; $shown += ($k + '=<' + ([string]$Extra[$k]).Length + ' characters, not shown>') }
    Say ('  > as ' + $env:COMPUTERNAME + '\' + $Name + ' (its own logon, as runas): ' + $psi.FileName + ' ' + $psi.Arguments)
    Say ('    spec: ' + (($SpecObj | ConvertTo-Json -Compress -Depth 4)))
    if ($shown.Count -gt 0) { Say ('    environment added: ' + ($shown -join ', ')) }
    try { $p = [Diagnostics.Process]::Start($psi) } catch { $res.Why = 'the process could not be started as ' + $Name + ': ' + $_.Exception.Message; Say ('    ' + $res.Why); Remove-Item -LiteralPath $spec -Force -ErrorAction SilentlyContinue; return $res }
    $res.ProcId = $p.Id
    $so = $p.StandardOutput.ReadToEndAsync()
    $se = $p.StandardError.ReadToEndAsync()
    Start-Sleep -Milliseconds 400
    $res.F = [SdLsw.Native]::Proc([uint32]$p.Id)
    if ($res.F.UserSid -ne '') { $res.L = [SdLsw.Native]::Logon($res.F.LogonLow, $res.F.LogonHigh) }
    Say ('    the runner as read while it ran: ' + (Format-Proc $res.F $res.L))
    if (-not $p.WaitForExit($TimeoutSec * 1000)) {
        $res.Why = 'it did not end within ' + $TimeoutSec + ' s (pid ' + $p.Id + ', left alone)'
        Say ('    ' + $res.Why)
        return $res
    }
    $res.Code = $p.ExitCode
    $res.Out = ($so.Result + "`n" + $se.Result)
    $res.Ok = $true
    SayRaw ('as ' + $Name + ', exit ' + $res.Code) $res.Out
    Remove-Item -LiteralPath $spec -Force -ErrorAction SilentlyContinue
    return $res
}

# The API rows' common facts: the port, a listener on loopback, python, scram-probe.py, libssl.  @{ Ok; Why; Port; Py; Probe; Ssl }
function Get-ApiFacts {
    $f = @{ Ok = $false; Why = ''; Port = 0; Py = ''; Probe = ''; Ssl = '' }
    $t = ''
    try { $t = [IO.File]::ReadAllText($SdConf) } catch { }
    $m = [regex]::Match($t, '(?m)^\s*APIPORT\s*=\s*(\d+)')
    if ($m.Success) { $f.Port = [int]$m.Groups[1].Value }
    $lis = @()
    if ($f.Port -gt 0) { $lis = @(Get-NetTCPConnection -State Listen -LocalPort $f.Port -ErrorAction SilentlyContinue | ForEach-Object { $_.LocalAddress + ':' + $_.LocalPort + ' pid ' + $_.OwningProcess }) }
    Say ('  sd.conf APIPORT: ' + $f.Port + '   listening: ' + ($lis -join ', '))
    $py = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($null -ne $py) { $f.Py = $py.Source }
    $src = Join-Path $PSScriptRoot 'scram-probe.py'
    if (Test-Path -LiteralPath $src) { $f.Probe = Join-Path $Work 'scram-probe.py'; Copy-Item -LiteralPath $src -Destination $f.Probe -Force }
    foreach ($c in @('C:\sdtools\bin\libssl-3-x64.dll')) { if (Test-Path -LiteralPath $c) { $f.Ssl = $c } }
    Say ('  python: ''' + $f.Py + '''   probe: ''' + $f.Probe + '''   SD_PROBE_LIBSSL: ''' + $f.Ssl + '''')
    if ($f.Port -le 0 -or $lis.Count -eq 0) { $f.Why = 'the API is not listening (sd.conf APIPORT ' + $f.Port + '): as SDSYS, remote.api local, then restart SD - see the step sheet'; return $f }
    if ($f.Py -eq '') { $f.Why = 'no python.exe on PATH'; return $f }
    if ($f.Probe -eq '') { $f.Why = 'no scram-probe.py beside this script'; return $f }
    $f.Ok = $true
    return $f
}

function Get-ProbeSpec($Api, [string]$Who) {
    $argv = @($Api.Probe, '--host', '127.0.0.1', '--port', [string]$Api.Port, '--user', 'sdsys', '--account', 'sdsys', 'WHO')
    return @{ Exe = $Api.Py; Argv = $argv; Hold = 5; Label = $Who }
}

function Get-ProbeEnv($Api, [Security.SecureString]$SdsysPw) {
    $e = @{ SD_SCRAM_PASSWORD = (Get-Plain $SdsysPw) }
    if ($Api.Ssl -ne '') { $e['SD_PROBE_LIBSSL'] = $Api.Ssl }
    return $e
}

# ---------------------------------------------------------------------------------------------------------------- start

$want = @()
foreach ($o in @($Only)) { foreach ($p in ([string]$o -split ',')) { if ($p.Trim() -ne '') { $want += $p.Trim().ToLower() } } }
if ($want.Count -eq 0) {
    Write-Host ('pass -Only with one or more of: ' + ($Known -join ','))
    Write-Host 'nothing was run (exit 2): the step sheet witness-localsdsys-steps.txt names the sections for each step.'
    exit 2
}
foreach ($w in $want) {
    if ($Known -notcontains $w) { Write-Host ("'" + $w + "' is not a section of this script; the sections are: " + ($Known -join ',')); Write-Host 'nothing was run (exit 2).'; exit 2 }
}
$Run = @($Known | Where-Object { $want -contains $_ })

foreach ($d in @($Root, $Work, $OutDir, (Join-Path $Root 'logs'))) { if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force } }
$Script:Log = Join-Path (Join-Path $Root 'logs') ('witness-localsdsys-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Set-Content -LiteralPath $Script:Log -Value '' -Encoding UTF8

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$elevated = (New-Object Security.Principal.WindowsPrincipal($me)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say ('==== witness-localsdsys   ' + (Get-Date).ToString('s') + '   log ' + $Script:Log)
Say ('  machine ' + $env:COMPUTERNAME + '   user ' + $me.Name + '   elevated ' + $elevated + '   pid ' + $PID)
Say ('  script  ' + $MyInvocation.MyCommand.Path)
Say ('  sections: ' + ($Run -join ',') + '   -User ' + $User + '   -Unlisted ' + $Unlisted + '   -Lan ''' + $Lan + '''   -WatchSeconds ' + $WatchSeconds)
if (-not $elevated) { Say 'CANNOT RUN: this needs an ELEVATED PowerShell (Run as administrator).  Nothing was run (exit 2).'; exit 2 }
if ($User -ieq $Unlisted) { Say 'CANNOT RUN: -User and -Unlisted name the same account.  Nothing was run (exit 2).'; exit 2 }

# The work folder: the test users read the runner scripts and write their spec/output files under out (nothing secret is in either).
try {
    $usersSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')
    $acl = Get-Acl -LiteralPath $Work
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($usersSid, 'ReadAndExecute', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $Work -AclObject $acl
    $acl = Get-Acl -LiteralPath $OutDir
    $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule($usersSid, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')))
    Set-Acl -LiteralPath $OutDir -AclObject $acl
} catch { Say ('  the work folder''s grants could not be set: ' + $_.Exception.Message) }
Write-Runners

$dbg = [SdLsw.Native]::EnableDebug()
Say ('  SeDebugPrivilege: ' + $(if ($dbg -eq 0) { 'enabled' } else { 'NOT enabled (error ' + $dbg + ') - reads of SYSTEM processes may stop' }))
$Script:Audit = Get-AuditPath
$Script:Helper = Find-Shipped 'sd-sdsyslocal.ps1'
$Script:ApiHelper = Find-Shipped 'sd-sdsysapi.ps1'
Say ('  sd.exe ' + $SdExe + ' (present ' + (Test-Path -LiteralPath $SdExe) + ')')
Say ('  sdsvc.log ' + $SvcLog + '   audit ' + $Script:Audit + '   sd.conf ' + $SdConf)
Say ('  helper ''' + $Script:Helper + '''   address helper ''' + $Script:ApiHelper + '''')
Say ('  lists ' + $SshList + ' and ' + $ApiList)
$installed = Test-Path -LiteralPath $SdExe
$UserSid = ''
$UnlistedSid = ''
try { $UserSid = (Get-LocalUser -Name $User -ErrorAction Stop).SID.Value } catch { }
try { $UnlistedSid = (Get-LocalUser -Name $Unlisted -ErrorAction Stop).SID.Value } catch { }
Say ('  ' + $User + ' SID ''' + $UserSid + '''   ' + $Unlisted + ' SID ''' + $UnlistedSid + '''')
Show-Lists 'now'

# A row that needs SD installed and the test users made.  $true when it may go on; otherwise it records NOT RUN.
# 19 Nov 26: -NeedAccount for the rows that sign in as the user over ssh and run sd-sdsys (W5, W10, W12).  Without an SD account SD's
# login refuses first ("not in the register", sit5 23:48) and the door is never asked, which W5 then scored NOT RUN with no reason.
function Test-Ready([string]$Row, [switch]$NeedUnlisted, [switch]$NeedAccount) {
    if (-not $installed) { Add-Row $Row 'the row' 'NOT RUN' ('SD is not installed here (' + $SdExe + ' is absent)'); return $false }
    if ($Script:Helper -eq '') { Add-Row $Row 'the row' 'NOT RUN' 'sd-sdsyslocal.ps1 is not under C:\Program Files\SD'; return $false }
    if ($UserSid -eq '') { Add-Row $Row 'the row' 'NOT RUN' ('there is no local user ' + $User + ': run -Only setup first'); return $false }
    if ($NeedAccount) {
        $acctDir = Join-Path $DataDir ('user_accounts\' + $User)
        if (-not (Test-Path -LiteralPath $acctDir)) {
            Add-Row $Row 'the row' 'NOT RUN' ($User + ' has no SD account (' + $acctDir + ' is absent): as SDSYS, create.account for it and modify.account ' + $User + ' sh-on - see the step sheet')
            return $false
        }
    }
    if ($NeedUnlisted -and $UnlistedSid -eq '') { Add-Row $Row 'the row' 'NOT RUN' ('there is no local user ' + $Unlisted + ': run -Only setup first'); return $false }
    return $true
}

# A refusal by the door for a user, from the "sdsys local:" lines.  The word, or '' when none.
function Get-DoorWord($SvcLines, [string]$Name) {
    $m = @($SvcLines | Where-Object { $_ -match ('sdsys local: refused (\S+) for pid \d+ user \S*\\' + [regex]::Escape($Name) + ':') })
    if ($m.Count -eq 0) { return '' }
    $null = $m[-1] -match 'refused (\S+) for pid'
    return $Matches[1]
}

function Get-DoorStarted($SvcLines, [string]$Name) {
    return @($SvcLines | Where-Object { $_ -match ('sdsys local: started the SDSYS session pid \d+ for pid \d+ user \S*\\' + [regex]::Escape($Name) + ' ') })
}

# Judges a row whose expected outcome is a refusal by the door with WORD for NAME, and that nothing was started or granted.
function Set-DoorRefusal([string]$Row, [string]$Name, [string]$Word, $Since) {
    $started = @(Get-DoorStarted $Since.Svc $Name)
    $w = Get-DoorWord $Since.Svc $Name
    if ($started.Count -gt 0) { Add-Row $Row ('the door refused ' + $Name + ' with ' + $Word) 'FAIL' ('the door STARTED an SDSYS session: ' + $started[0]) }
    elseif ($w -eq '') { Add-Row $Row ('the door refused ' + $Name + ' with ' + $Word) 'NOT RUN' ('no "sdsys local:" line for ' + $Name + ' in sdsvc.log since the mark: the asker never reached the door (read the second window)') }
    elseif ($w -eq $Word) { Add-Row $Row ('the door refused ' + $Name + ' with ' + $Word) 'PASS' ('sdsvc.log: refused ' + $w) }
    else { Add-Row $Row ('the door refused ' + $Name + ' with ' + $Word) 'FAIL' ('refused, but with ' + $w + ', not ' + $Word) }
    $g = @($Since.Audit | Where-Object { $_ -match 'elevation granted' })
    if ($g.Count -gt 0) { Add-Row $Row 'nothing was granted' 'FAIL' $g[0] } else { Add-Row $Row 'nothing was granted' 'PASS' ('no "elevation granted" in ' + $Since.Audit.Count + ' new audit line(s)') }
}

function Get-LanAddress {
    if ($Lan -ne '') { return $Lan }
    $a = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -ExpandProperty IPAddress)
    if ($a.Count -gt 0) { return $a[0] }
    return ''
}

$sshCmdLocal = 'ssh -t ' + $User + '@localhost sd-sdsys'

# ================================================================================================================ setup
if ($Run -contains 'setup') {
    Say ''
    Say '=== setup: the test users and the install''s facts'
    foreach ($n in @($User, $Unlisted)) {
        $u = Get-LocalUser -Name $n -ErrorAction SilentlyContinue
        if ($null -eq $u) {
            Say ('  ' + $n + ' does not exist: it is made now.  Choose its Windows password (a test password for this VM; you type it again at ssh''s prompt).')
            $p1 = Read-Secret ('  Windows password for ' + $n)
            $p2 = Read-Secret ('  the same again')
            if ((Get-Plain $p1) -cne (Get-Plain $p2) -or (Get-Plain $p1) -eq '') { Add-Row 'setup' ('make ' + $n) 'NOT RUN' 'the two passwords were empty or not the same; nothing was made'; continue }
            try {
                $null = New-LocalUser -Name $n -Password $p1 -PasswordNeverExpires -AccountNeverExpires -Description 'SD witness RELEASE_1.1 339' -ErrorAction Stop
                Say ('  made ' + $n)
            } catch { Add-Row 'setup' ('make ' + $n) 'FAIL' $_.Exception.Message; continue }
        } else { Say ('  ' + $n + ' exists (enabled ' + $u.Enabled + ', SID ' + $u.SID.Value + ')') }
        foreach ($g in @('Users', 'sdusers', 'sdssh')) {
            $in = $false
            try { $in = (@(Get-LocalGroupMember -Group $g -ErrorAction Stop | Where-Object { ($_.Name -split '\\')[-1] -ieq $n }).Count -gt 0) } catch { Say ('  group ' + $g + ' could not be read: ' + $_.Exception.Message) }
            if (-not $in) { try { Add-LocalGroupMember -Group $g -Member $n -ErrorAction Stop; Say ('  added ' + $n + ' to ' + $g) } catch { Say ('  could NOT add ' + $n + ' to ' + $g + ': ' + $_.Exception.Message) } }
            else { Say ('  ' + $n + ' is in ' + $g) }
        }
        $mem = @()
        foreach ($g in @('Users', 'sdusers', 'sdssh')) { try { if (@(Get-LocalGroupMember -Group $g -ErrorAction Stop | Where-Object { ($_.Name -split '\\')[-1] -ieq $n }).Count -gt 0) { $mem += $g } } catch { } }
        Set-Verdict 'setup' ($n + ' is in Users, sdusers and sdssh') @('member of: ' + ($mem -join ',')) 'member of: Users,sdusers,sdssh$' @() 'Get-LocalGroupMember'
    }
    try { $UserSid = (Get-LocalUser -Name $User -ErrorAction Stop).SID.Value } catch { }
    try { $UnlistedSid = (Get-LocalUser -Name $Unlisted -ErrorAction Stop).SID.Value } catch { }
    Say ('  ' + $User + ' SID ''' + $UserSid + '''   ' + $Unlisted + ' SID ''' + $UnlistedSid + '''')

    foreach ($s in @('SD', 'sshd')) {
        $sv = Get-Service -Name $s -ErrorAction SilentlyContinue
        $st = if ($null -eq $sv) { 'absent' } else { [string]$sv.Status }
        Set-Verdict 'setup' ('the ' + $s + ' service is running') @('status ' + $st) '^status Running$' @() 'Get-Service'
    }
    $sshdSvc = Get-SvcPid 'sshd'
    if ($sshdSvc -gt 0) { $sf = [SdLsw.Native]::Proc($sshdSvc); Say ('  sshd service: ' + (Format-Proc $sf $null)); try { Say ('  sshd.exe version: ' + (Get-Item -LiteralPath $sf.Image).VersionInfo.ProductVersion) } catch { } }
    $ds = ''
    try { $ds = [string](Get-ItemProperty -Path 'HKLM:\SOFTWARE\OpenSSH' -Name DefaultShell -ErrorAction Stop).DefaultShell } catch { $ds = '(not set: Win32-OpenSSH runs the forced command through cmd.exe)' }
    Say ('  HKLM\SOFTWARE\OpenSSH DefaultShell: ' + $ds)
    try {
        $ll = Get-WinEvent -ListLog 'OpenSSH/Operational' -ErrorAction Stop
        Say ('  OpenSSH/Operational: enabled ' + $ll.IsEnabled + ', provider ' + $ll.OwningProviderName + ', records ' + $ll.RecordCount + ', sddl ' + $ll.SecurityDescriptor)
        Set-Verdict 'setup' 'sshd''s channel OpenSSH/Operational is enabled (F3: without it every sd-sdsys is no-session)' @('enabled ' + $ll.IsEnabled) '^enabled True$' @() 'Get-WinEvent -ListLog'
    } catch { Add-Row 'setup' 'sshd''s channel OpenSSH/Operational is enabled' 'NOT RUN' $_.Exception.Message }
    $serving = @(Get-Since $SvcLog 0 'ansi' | Where-Object { $_ -match 'sdsys local: (serving|not started)' })
    if ($serving.Count -gt 0) { Say ('  the door''s last start line: ' + $serving[-1]) }
    Set-Verdict 'setup' 'the SD service serves the door (\\.\pipe\sd-sdsys-local)' @($(if ($serving.Count) { $serving[-1] } else { '' })) 'sdsys local: serving .*sd-sdsys-local' @('sdsys local: not started') 'sdsvc.log'
    Set-Verdict 'setup' 'sd-sdsyslocal.ps1 is installed' @('helper ' + $Script:Helper) 'sd-sdsyslocal\.ps1$' @() 'Find-Shipped'
    Show-Lists 'setup'
}

# ================================================================================================================ W0
if ($Run -contains 'w0' -and (Test-Ready 'W0')) {
    Say ''
    Say ('=== W0 MEASURE FIRST: the real chain of ' + $sshCmdLocal + ' (F1 the chain, F2 the logon type, F3 sshd''s record)')
    if (-not (Set-Listed 'ssh' $User)) { Add-Row 'W0' 'the chain' 'NOT RUN' ($User + ' could not be put on the ssh list (the helper''s output is above)') }
    else {
        $sshdSvc = Get-SvcPid 'sshd'
        $sdSvc = Get-SvcPid 'SD'
        $sshdF = [SdLsw.Native]::Proc($sshdSvc)
        Say ('  sshd service pid ' + $sshdSvc + ': ' + (Format-Proc $sshdF $null))
        Say ('  SD service pid ' + $sdSvc)
        $null = Wait-Person 'W0 (get ready)' @(
            'Open WINDOW B: on the VM, an ORDINARY PowerShell (NOT elevated).',
            'Do not type anything there yet.  Press Enter HERE first; the script then watches for ' + $WatchSeconds + ' seconds.')
        $marks = New-Marks
        $t0 = Get-Date
        Say ''
        Say ('  WATCHING NOW (' + $WatchSeconds + ' s).  In WINDOW B type:   ' + $sshCmdLocal)
        Say ('  at "' + $User + '@localhost''s password:" type ' + $User + '''s Windows password; then LEAVE IT at the "SD password of sdsys:" prompt (type nothing more).')
        # Every sd.exe that is already there is not this login's asker.
        $seen = @{}
        foreach ($r in [SdLsw.Native]::Snapshot()) { if ($r.Name -ieq 'sd.exe') { $seen[$r.Pid] = $true } }
        Say ('  sd.exe processes already running (ignored): ' + $seen.Count)
        $chain = $null
        $tcpAt = @()
        $child = $null
        $childCmd = ''
        $deadline = (Get-Date).AddSeconds($WatchSeconds)
        $childUntil = $null
        while ((Get-Date) -lt $deadline) {
            $snap = [SdLsw.Native]::Snapshot()
            if ($null -eq $chain) {
                foreach ($r in $snap) {
                    if ($r.Name -ine 'sd.exe' -or $seen.ContainsKey($r.Pid)) { continue }
                    $seen[$r.Pid] = $true
                    $f = [SdLsw.Native]::Proc($r.Pid)
                    if ($f.UserSid -eq $UserSid) {
                        $chain = Get-Chain $r.Pid $snap $sshdSvc
                        Say ('  seen at ' + (Get-Date).ToString('HH:mm:ss.fff') + ': sd.exe pid ' + $r.Pid + ' of ' + $User)
                        # 19 Nov 26 (RELEASE_1.1 339): any state, v4 and v6 - sit5's W0 saw none with -State Established
                        # (the refused session closed 0.2 s after the asker appeared), so whose the row is was never read.
                        $tcpAt = @(Get-NetTCPConnection -LocalPort 22 -ErrorAction SilentlyContinue)
                        $childUntil = (Get-Date).AddSeconds(8)
                        break
                    }
                }
            }
            if ($null -ne $chain -and $null -eq $child) {
                foreach ($r in $snap) {
                    if ($r.Name -ieq 'sd.exe' -and $r.Ppid -eq $sdSvc) {
                        $cf = [SdLsw.Native]::Proc($r.Pid)
                        if ($cf.Created -gt 0 -and [DateTime]::FromFileTimeUtc($cf.Created) -ge $t0.ToUniversalTime()) {
                            $child = $cf
                            $childCmd = Get-CmdLine $r.Pid
                            break
                        }
                    }
                }
            }
            if ($null -ne $chain -and ($null -ne $child -or (Get-Date) -gt $childUntil)) { break }
            Start-Sleep -Milliseconds 120
        }
        $null = Wait-Person 'W0' @(
            'WINDOW B now shows "SD password of sdsys:", or "sdsys has no SD password ..." (an install where SDSYS never signed in), or a refusal ("sd-sdsys refused: <word>").',
            'Do NOT type SDSYS''s password (W1 does that).  Press Enter here; the script reads the logs, then tells you to close window B.')
        if ($null -eq $chain) {
            Add-Row 'W0' 'the chain' 'NOT RUN' ('no sd.exe of ' + $User + ' appeared within ' + $WatchSeconds + ' s')
            $null = Read-Since $marks
        } else {
            Say '  THE CHAIN, from the asker up (each read when the asker was first seen):'
            Show-Chain $chain
            Say '  TCP rows on port 22 when the asker was first seen:'
            if ($tcpAt.Count -eq 0) { Say '    (none, in any state)' }
            foreach ($t in $tcpAt) {
                $own = [SdLsw.Native]::Proc([uint32]$t.OwningProcess)
                Say ('    tcp  local ' + $t.LocalAddress + ':' + $t.LocalPort + '  remote ' + $t.RemoteAddress + ':' + $t.RemotePort + '  state ' + $t.State + '  owner ' + $t.OwningProcess + ' ' + $own.Image + '  created ' + $t.CreationTime.ToString('o'))
            }
            Say '  OpenSSH/Operational event 4 since the mark:'
            $evs = Get-SshdAccepted $t0.AddSeconds(-2)
            $since = Read-Since $marks

            # F1: P is SD's sd.exe; up to the first SYSTEM process A only cmd.exe and conhost.exe from the system directory and sshd.exe
            # and sshd-session.exe from the sshd service's own folder, each by full path, of the same user and logon; A is the service's
            # image or that folder's sshd-session.exe, and the service's direct child; every parent made before its child.
            # 19 Nov 26 (RELEASE_1.1 339): the door's rule as sit5's W0 measured OpenSSH 10's chain (conhost, sshd-session).
            $sshDir = Split-Path -Parent $sshdF.Image
            $p0 = $chain[0]
            $why = @()
            if ($p0.F.Image -ine $SdExe) { $why += ('the asker''s image is ' + $p0.F.Image + ', not ' + $SdExe) }
            $aIdx = -1
            for ($i = 1; $i -lt $chain.Count; $i++) { if ($chain[$i].F.IsSystem) { $aIdx = $i; break } }
            $unread = @($chain | Where-Object { $_.F.Error -ne 0 })
            if ($unread.Count -gt 0) { $why += ('a step could not be read: pid ' + $unread[0].Pid + ' at ' + $unread[0].F.Stage + ' error ' + $unread[0].F.Error) }
            if ($aIdx -lt 0) { $why += 'no SYSTEM process above the asker (A not found)' }
            else {
                for ($i = 1; $i -lt $aIdx; $i++) {
                    $c = $chain[$i]
                    $okImg = @((Join-Path $SysDir 'cmd.exe'), (Join-Path $SysDir 'conhost.exe'), (Join-Path $sshDir 'sshd.exe'), (Join-Path $sshDir 'sshd-session.exe'))
                    if (-not ($okImg | Where-Object { $_ -ieq $c.F.Image })) { $why += ('step ' + $i + ' is ' + $c.F.Image + ' (only ' + ($okImg -join ', ') + ' are taken: session-unsafe)') }
                    if ($c.F.UserSid -ne $p0.F.UserSid -or $c.F.LogonLow -ne $p0.F.LogonLow -or $c.F.LogonHigh -ne $p0.F.LogonHigh) { $why += ('step ' + $i + ' (pid ' + $c.Pid + ') is another user or logon') }
                }
                $a = $chain[$aIdx]
                if ($a.F.Image -ine $sshdF.Image -and $a.F.Image -ine (Join-Path $sshDir 'sshd-session.exe')) { $why += ('A (pid ' + $a.Pid + ') image ' + $a.F.Image + ' is neither the sshd service''s ' + $sshdF.Image + ' nor its sshd-session.exe') }
                if ($a.Ppid -ne $sshdSvc) { $why += ('A''s parent is ' + $a.Ppid + ', not the sshd service ' + $sshdSvc) }
            }
            for ($i = 1; $i -lt $chain.Count; $i++) { if ($chain[$i].F.Created -ge $chain[$i - 1].F.Created) { $why += ('pid ' + $chain[$i].Pid + ' was not made before its child ' + $chain[$i - 1].Pid) } }
            $f1 = 'F1: the chain is sd.exe <- only cmd/conhost (system) and sshd/sshd-session (sshd''s folder) of that logon <- A (sshd or sshd-session, SYSTEM) <- the sshd service, oldest first'
            if ($why.Count -eq 0) { Add-Row 'W0' $f1 'PASS' ('A = pid ' + $chain[$aIdx].Pid + '; ' + $chain.Count + ' steps read') }
            else { Add-Row 'W0' $f1 'FAIL' ('F1 FALSIFIED: ' + ($why -join '; ')) }

            # F2: the asker's logon is Network (3) or NetworkCleartext (8), and its SID is the user's own.
            if ($null -eq $p0.L -or $p0.L.Status -ne 0) { Add-Row 'W0' 'F2: the asker''s logon type is 3 or 8 and the logon is the user''s own' 'NOT RUN' 'the asker''s logon session could not be read (printed above)' }
            elseif (($p0.L.Type -eq 3 -or $p0.L.Type -eq 8) -and $p0.L.Sid -eq $UserSid) { Add-Row 'W0' 'F2: the asker''s logon type is 3 or 8 and the logon is the user''s own' 'PASS' ('type ' + $p0.L.Type + ', package ' + $p0.L.Package + ', sid ' + $p0.L.Sid) }
            else { Add-Row 'W0' 'F2: the asker''s logon type is 3 or 8 and the logon is the user''s own' 'FAIL' ('F2 FALSIFIED: type ' + $p0.L.Type + ', sid ' + $p0.L.Sid + ' (the door would say not-ssh or other-user)') }

            # F3: A's own event 4, loopback, this user.
            $aEv = @()
            if ($aIdx -ge 0) { $aPid = $chain[$aIdx].Pid; $aEv = @($evs | Where-Object { $_.ProcId -eq $aPid -and $_.Msg -match 'Accepted ' }) }
            if ($aIdx -lt 0) { Add-Row 'W0' 'F3: sshd''s event 4 with ProcessID = A says Accepted for the user from a loopback address' 'NOT RUN' 'A was not found' }
            elseif ($aEv.Count -eq 0) { Add-Row 'W0' 'F3: sshd''s event 4 with ProcessID = A says Accepted for the user from a loopback address' 'FAIL' ('F3 FALSIFIED: no event 4 with ProcessID ' + $chain[$aIdx].Pid + ' since the mark (the door would say no-session)') }
            else {
                $mm = [regex]::Match($aEv[0].Msg, 'Accepted (\S+) for (\S+) from (\S+) port (\d+)')
                if ($mm.Success -and (($mm.Groups[2].Value -split '\\')[-1] -ieq $User) -and (Test-Loopback $mm.Groups[3].Value)) {
                    Add-Row 'W0' 'F3: sshd''s event 4 with ProcessID = A says Accepted for the user from a loopback address' 'PASS' $aEv[0].Msg
                } else { Add-Row 'W0' 'F3: sshd''s event 4 with ProcessID = A says Accepted for the user from a loopback address' 'FAIL' ('the event does not read as wanted: ' + $aEv[0].Msg) }
                # The door reads the event's time to the whole second only (win32localsdsys.c event_time) and needs it not before A's creation.
                $evUtc = $aEv[0].Time.ToUniversalTime()
                $trunc = New-Object DateTime($evUtc.Year, $evUtc.Month, $evUtc.Day, $evUtc.Hour, $evUtc.Minute, $evUtc.Second, [DateTimeKind]::Utc)
                $aMade = [DateTime]::FromFileTimeUtc($chain[$aIdx].F.Created)
                Add-Row 'W0' 'the event''s time as the door reads it (whole seconds) against A''s creation' 'INFO' ('event ' + $evUtc.ToString('HH:mm:ss.fffffff') + ' read as ' + $trunc.ToString('HH:mm:ss') + '; A made ' + $aMade.ToString('HH:mm:ss.fffffff') + '; margin ' + [int]($trunc - $aMade).TotalMilliseconds + ' ms (negative = the door would refuse no-session)')
                if ($mm.Success) {
                    $port = [int]$mm.Groups[4].Value
                    $row = @($tcpAt | Where-Object { $_.RemotePort -eq $port -and (Test-Loopback ([string]$_.RemoteAddress)) })
                    if ($row.Count -eq 0) { Add-Row 'W0' 'the TCP row of that connection (remote port from the event) is established, owned by the sshd service (M9)' 'FAIL' ('no established port-22 row with remote port ' + $port + ' when the asker was seen') }
                    elseif ([uint32]$row[0].OwningProcess -eq $sshdSvc) { Add-Row 'W0' 'the TCP row of that connection (remote port from the event) is established, owned by the sshd service (M9)' 'PASS' ('remote ' + $row[0].RemoteAddress + ':' + $port + ' owner ' + $row[0].OwningProcess) }
                    else { Add-Row 'W0' 'the TCP row of that connection (remote port from the event) is established, owned by the sshd service (M9)' 'FAIL' ('M9 differs here: owner ' + $row[0].OwningProcess + ', the sshd service is ' + $sshdSvc + ' (the door would say no-session)') }
                }
            }

            # The door's own verdict on this login.
            $st = @(Get-DoorStarted $since.Svc $User)
            $dw = Get-DoorWord $since.Svc $User
            if ($st.Count -gt 0) { Add-Row 'W0' 'the door started an SDSYS session for this login' 'PASS' $st[0] }
            elseif ($dw -ne '') { Add-Row 'W0' 'the door started an SDSYS session for this login' 'FAIL' ('the door refused it: ' + $dw + ' (the measurements above say which step)') }
            else { Add-Row 'W0' 'the door started an SDSYS session for this login' 'NOT RUN' 'no "sdsys local:" line for this user since the mark' }

            # The SDSYS process the service made.
            if ($null -eq $child) { Add-Row 'W0' 'the SDSYS child: SDSYS, source SDsessn, elevated, a child of the SD service, -SDSYSLOCAL <asker pid>' 'NOT RUN' 'no new sd.exe under the SD service was seen' }
            else {
                $cl = $null
                if ($child.UserSid -ne '') { $cl = [SdLsw.Native]::Logon($child.LogonLow, $child.LogonHigh) }
                Say ('  the SDSYS child: ' + (Format-Proc $child $cl))
                Say ('  its command line: ' + $childCmd)
                $cw = @()
                if (($child.UserName -split '\\')[-1] -ine 'SDSYS') { $cw += ('user ' + $child.UserName) }
                if ($child.Source -ne 'SDsessn') { $cw += ('source ''' + $child.Source + '''') }
                if ($child.Elevated -ne 1) { $cw += ('elevated ' + $child.Elevated) }
                if ($childCmd -notmatch ('-SDSYSLOCAL\s+' + $chain[0].Pid + '\b')) { $cw += 'the command line does not name -SDSYSLOCAL <asker pid>' }
                if ($cw.Count -eq 0) { Add-Row 'W0' 'the SDSYS child: SDSYS, source SDsessn, elevated, a child of the SD service, -SDSYSLOCAL <asker pid>' 'PASS' ('pid ' + $child.Pid + ', session ' + $child.Session + ', logon type ' + $(if ($null -ne $cl) { $cl.Type } else { '?' })) }
                else { Add-Row 'W0' 'the SDSYS child: SDSYS, source SDsessn, elevated, a child of the SD service, -SDSYSLOCAL <asker pid>' 'FAIL' ($cw -join '; ') }
            }
        }
        Say '  NOW CLOSE WINDOW B with its X button (that ends the ssh login; the service ends the SDSYS session it started).'
    }
}

# ================================================================================================================ W1 / W2 / W3
foreach ($rowName in @('w1', 'w2', 'w3')) {
    if (-not ($Run -contains $rowName)) { continue }
    $R = $rowName.ToUpper()
    if (-not (Test-Ready $R)) { continue }
    Say ''
    $what = @{ W1 = 'the RIGHT SD password of sdsys'; W2 = 'a WRONG SD password of sdsys (anything but the right one)'; W3 = 'nothing - sdsys must have NO SD password on this install' }[$R]
    Say ('=== ' + $R + ': ' + $sshCmdLocal + ' with ' + $what)
    if (-not (Set-Listed 'ssh' $User)) { Add-Row $R 'the row' 'NOT RUN' ($User + ' could not be put on the ssh list'); continue }
    $marks = New-Marks
    # 19 Nov 26: each line in its own parentheses - the comma binds tighter than +, so 'a' + $x, 'b' + $y made ONE line of an array
    # (sit5's W5 prompt read "...sd-sdsys Type sdlocalw's ...").
    $lines = @(('In WINDOW B (the VM, an ORDINARY PowerShell, not elevated) type:   ' + $sshCmdLocal),
               ('At "' + $User + '@localhost''s password:" type ' + $User + '''s Windows password.'))
    if ($R -eq 'W1') { $lines += @('At "SD password of sdsys:" type SDSYS''s SD password (the right one).', 'At the SD prompt type:   WHO', 'then type:   OFF') }
    if ($R -eq 'W2') { $lines += @('At "SD password of sdsys:" type a WRONG password (for example: wrong).', 'Watch whether the window waits a few seconds before the session ends.') }
    if ($R -eq 'W3') { $lines += @('Type nothing more.  If "SD password of sdsys:" IS asked, sdsys has an SD password: type a wrong one, and answer n below.') }
    if (-not (Wait-Person $R $lines)) { Add-Row $R 'the row' 'NOT RUN' 'the person skipped it'; continue }
    $since = Read-Since $marks
    $st = @(Get-DoorStarted $since.Svc $User)
    if ($st.Count -gt 0) { Add-Row $R 'the door started the SDSYS session' 'PASS' $st[0] } else { Add-Row $R 'the door started the SDSYS session' 'FAIL' ('no "started" line; door word: ''' + (Get-DoorWord $since.Svc $User) + '''') }
    $u = [regex]::Escape($User)
    if ($R -eq 'W1') {
        Set-Verdict 'W1' 'audit: elevation granted reason=sdsys local ssh user=<User>' $since.Audit ('elevation granted reason=sdsys local ssh user=' + $u + '\b') @('elevation refused reason=sdsys local ssh', 'login refused account=sdsys') 'the audit trail'
        Set-PersonVerdict 'W1' '15177 was shown ("SD administration granted: this session is the SDSYS Windows account, elevated, ... ssh login of <User>")' 'Did window B show "SD administration granted: this session is the SDSYS Windows account, elevated"?'
        Set-PersonVerdict 'W1' 'WHO in the granted session answered with the account sdsys' 'Did WHO answer with the account sdsys (a number then SDSYS)?'
    }
    if ($R -eq 'W2') {
        Set-Verdict 'W2' 'audit: elevation refused reason=sdsys local ssh wrong password user=<User>' $since.Audit ('elevation refused reason=sdsys local ssh wrong password user=' + $u + '\b') @('elevation granted') 'the audit trail'
        Set-Verdict 'W2' 'audit: login refused account=sdsys reason=sdsys local ssh wrong password' $since.Audit 'login refused account=sdsys reason=sdsys local ssh wrong password' @('elevation granted') 'the audit trail'
        Set-PersonVerdict 'W2' '15175 was shown ("The SD password of sdsys was not right, so this session is not the administrator and ends here.")' 'Did window B show "The SD password of sdsys was not right"?'
        $a = (Read-Host '  QUESTION (W2): did the window wait about 3 seconds after that message before the session ended? [y/n/Enter]').Trim().ToLower()
        Add-Row 'W2' 'the PWDELAY wait after the refusal (3 s unless sd.conf says otherwise), as the person saw it' 'INFO' ('the person answered ''' + $a + '''')
    }
    if ($R -eq 'W3') {
        $nc = @($since.Audit | Where-Object { $_ -match ('elevation refused reason=sdsys local ssh no credential user=' + $u + '\b') })
        $pw = @($since.Audit | Where-Object { $_ -match 'sdsys local ssh wrong password|elevation granted' })
        if ($nc.Count -gt 0 -and $pw.Count -eq 0) { Add-Row 'W3' 'audit: elevation refused reason=sdsys local ssh no credential user=<User>' 'PASS' $nc[0] }
        elseif ($pw.Count -gt 0) { Add-Row 'W3' 'audit: elevation refused reason=sdsys local ssh no credential user=<User>' 'NOT RUN' ('sdsys HAS an SD password on this install (' + $pw[0] + '); W3 needs an install where it has none yet') }
        else { Add-Row 'W3' 'audit: elevation refused reason=sdsys local ssh no credential user=<User>' 'FAIL' 'no "no credential" line, and no password line either' }
        if ($nc.Count -gt 0) { Set-PersonVerdict 'W3' '15176 was shown ("sdsys has no SD password, so it cannot be reached from another user''s login")' 'Did window B show "sdsys has no SD password"?' }
    }
    $end = @($since.SvcAll | Where-Object { $_ -match 'sdsys local: the SDSYS session pid \d+ for pid \d+ user .* ended' })
    if ($end.Count -gt 0) { Add-Row $R 'the service saw the SDSYS session end' 'INFO' $end[-1] }
}

# ================================================================================================================ W4
if ($Run -contains 'w4' -and (Test-Ready 'W4' -NeedUnlisted)) {
    Say ''
    Say ('=== W4: the unlisted user ' + $Unlisted + ' asks for sd-sdsys (the list holds ' + $User + ')')
    if (-not (Set-Listed 'ssh' $User)) { Add-Row 'W4' 'the row' 'NOT RUN' 'the list could not be given a name' }
    elseif (@(Get-ListNames $SshList | Where-Object { $_ -ieq $Unlisted }).Count -gt 0) { Add-Row 'W4' 'the row' 'NOT RUN' ($Unlisted + ' IS on the ssh list; remove it first') }
    else {
        $marks = New-Marks
        if (Wait-Person 'W4' @('In WINDOW B type:   ssh -t ' + $Unlisted + '@localhost sd-sdsys', ('Type ' + $Unlisted + '''s Windows password.  It should end at once with "sd-sdsys refused: not-listed".'))) {
            $since = Read-Since $marks
            Set-DoorRefusal 'W4' $Unlisted 'not-listed' $since
        } else { Add-Row 'W4' 'the row' 'NOT RUN' 'the person skipped it' }
    }
}

# ================================================================================================================ W5
if ($Run -contains 'w5' -and (Test-Ready 'W5' -NeedAccount)) {
    Say ''
    Say '=== W5: the ssh list EMPTY (as delivered): list-empty, and nothing in the audit trail'
    $before = @(Get-ListNames $SshList)
    Say ('  names on the ssh list before (put back afterwards): ' + ($before -join ' '))
    if ($before.Count -gt 0) { $null = Invoke-Helper $Script:Helper @('-List', 'ssh', '-Action', 'clear') }
    Show-Lists 'W5 before'
    if (Test-Path -LiteralPath $SshList) { Add-Row 'W5' 'the row' 'NOT RUN' 'the ssh list could not be emptied' }
    else {
        $marks = New-Marks
        if (Wait-Person 'W5' @(('In WINDOW B type:   ' + $sshCmdLocal), ('Type ' + $User + '''s Windows password.  It should end at once with "sd-sdsys refused: list-empty".'))) {
            $since = Read-Since $marks
            Set-DoorRefusal 'W5' $User 'list-empty' $since
            $why = @($since.Audit | Where-Object { $_ -match 'why=|sdsys local' })
            if ($since.Audit -match '^<unreadable') { Add-Row 'W5' 'the audit trail has no sdsys-local line and no why=' 'NOT RUN' $since.Audit[0] }
            elseif ($why.Count -eq 0) { Add-Row 'W5' 'the audit trail has no sdsys-local line and no why=' 'PASS' ($since.Audit.Count.ToString() + ' new audit line(s), none naming it') }
            else { Add-Row 'W5' 'the audit trail has no sdsys-local line and no why=' 'FAIL' $why[0] }
        } else { Add-Row 'W5' 'the row' 'NOT RUN' 'the person skipped it' }
    }
    foreach ($n in $before) { $null = Set-Listed 'ssh' $n }
    Show-Lists 'W5 after'
}

# ================================================================================================================ W6 / W7
if ($Run -contains 'w6' -and (Test-Ready 'W6')) {
    Say ''
    $lanA = Get-LanAddress
    Say ('=== W6: the listed user from this VM''s own LAN address ' + $lanA + ' (sshd sees a peer that is not loopback)')
    if ($lanA -eq '') { Add-Row 'W6' 'the row' 'NOT RUN' 'no non-loopback IPv4 address here (pass -Lan)' }
    elseif (-not (Set-Listed 'ssh' $User)) { Add-Row 'W6' 'the row' 'NOT RUN' 'the list could not be given the name' }
    else {
        $marks = New-Marks
        if (Wait-Person 'W6' @('In WINDOW B type:   ssh -t ' + $User + '@' + $lanA + ' sd-sdsys', ('Type ' + $User + '''s Windows password (answer yes if ssh asks about the host key).  It should end with "sd-sdsys refused: not-local".'))) {
            $null = Get-SshdAccepted $marks.Time.AddSeconds(-2)
            $since = Read-Since $marks
            Set-DoorRefusal 'W6' $User 'not-local' $since
        } else { Add-Row 'W6' 'the row' 'NOT RUN' 'the person skipped it' }
    }
}
if ($Run -contains 'w7' -and (Test-Ready 'W7')) {
    Say ''
    $addrs = @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction SilentlyContinue | Where-Object { $_.IPAddress -notlike '127.*' } | ForEach-Object { $_.IPAddress + ' (' + $_.InterfaceAlias + ')' })
    Say ('=== W7: the listed user from the HOST over the network.  This VM''s addresses: ' + ($addrs -join ', '))
    if (-not (Set-Listed 'ssh' $User)) { Add-Row 'W7' 'the row' 'NOT RUN' 'the list could not be given the name' }
    else {
        $marks = New-Marks
        if (Wait-Person 'W7' @('On the HOST (not the VM), in an ordinary PowerShell, type:   ssh -t ' + $User + '@<one of the VM addresses above> sd-sdsys',
                               ('Type ' + $User + '''s Windows password.  It should end with "sd-sdsys refused: not-local".  If the host cannot reach the VM, type skip here.'))) {
            $null = Get-SshdAccepted $marks.Time.AddSeconds(-2)
            $since = Read-Since $marks
            Set-DoorRefusal 'W7' $User 'not-local' $since
        } else { Add-Row 'W7' 'the row' 'NOT RUN' 'the person skipped it (the host could not reach the VM, or was not tried)' }
    }
}

# ================================================================================================================ W8
if ($Run -contains 'w8' -and (Test-Ready 'W8')) {
    Say ''
    Say ('=== W8: sd.exe run by hand at the console as ' + $User + ' with the two ssh variables set (a logon that is not sshd''s)')
    if (-not (Set-Listed 'ssh' $User)) { Add-Row 'W8' 'the row' 'NOT RUN' 'the list could not be given the name' }
    else {
        $marks = New-Marks
        if (Wait-Person 'W8' @('In WINDOW B type:   runas /user:' + $User + ' cmd', ('Type ' + $User + '''s Windows password.  A NEW black window opens (cmd, as ' + $User + ').  In THAT window type these three lines:'),
                               '    set SSH_ORIGINAL_COMMAND=sd-sdsys', '    set SSH_CONNECTION=::1 50000 ::1 22', ('    "' + $SdExe + '"'),
                               'It should print "sd-sdsys refused: not-ssh".  If an ordinary SD session opens instead, type OFF in it.  Then close that window.')) {
            $since = Read-Since $marks
            Set-DoorRefusal 'W8' $User 'not-ssh' $since
        } else { Add-Row 'W8' 'the row' 'NOT RUN' 'the person skipped it' }
    }
}

# ================================================================================================================ W9
if ($Run -contains 'w9' -and (Test-Ready 'W9')) {
    Say ''
    Say ('=== W9: sd-sdsys started from INSIDE an SD session of ' + $User + ' (SH): a second sd.exe on the chain')
    $acct = Join-Path $DataDir ('user_accounts\' + $User)
    $cmdf = Join-Path $Work 'w9-sdsys.cmd'
    Set-Content -LiteralPath $cmdf -Value @('@set SSH_ORIGINAL_COMMAND=sd-sdsys', ('@"' + $SdExe + '"')) -Encoding ASCII
    Say ('  wrote ' + $cmdf + ' (sets SSH_ORIGINAL_COMMAND=sd-sdsys and runs sd.exe; SSH_CONNECTION is the ssh login''s own)')
    if (-not (Test-Path -LiteralPath $acct)) { Add-Row 'W9' 'the row' 'NOT RUN' ($User + ' has no SD account (' + $acct + ' is absent): as SDSYS, create.account for it and modify.account ' + $User + ' sh-on - see the step sheet') }
    elseif (-not (Set-Listed 'ssh' $User)) { Add-Row 'W9' 'the row' 'NOT RUN' 'the list could not be given the name' }
    else {
        $marks = New-Marks
        if (Wait-Person 'W9' @('In WINDOW B type:   ssh -t ' + $User + '@localhost', ('Type ' + $User + '''s Windows password.  At the SD prompt (its own account, sh-on) type:'),
                               ('    SH ' + $cmdf), 'It should print "sd-sdsys refused: session-unsafe".  Then type OFF.  If SH refuses the line, type skip here.')) {
            $since = Read-Since $marks
            Set-DoorRefusal 'W9' $User 'session-unsafe' $since
        } else { Add-Row 'W9' 'the row' 'NOT RUN' 'the person skipped it (SH refused the line, or the account has no sh-on)' }
    }
}

# ================================================================================================================ W10
if ($Run -contains 'w10' -and (Test-Ready 'W10' -NeedAccount)) {
    Say ''
    Say '=== W10: a PHANTOM from the granted SDSYS session is refused by LOGIN'
    if (-not (Set-Listed 'ssh' $User)) { Add-Row 'W10' 'the row' 'NOT RUN' 'the list could not be given the name' }
    else {
        $marks = New-Marks
        if (Wait-Person 'W10' @(('In WINDOW B type:   ' + $sshCmdLocal), ('Type' + $User + '''s Windows password, then at "SD password of sdsys:" the RIGHT SD password of sdsys.'),
                                'At the SD prompt type:   PHANTOM WHO', 'Wait 10 seconds, then type:   OFF')) {
            $since = Read-Since $marks
            $grants = @($since.Audit | Where-Object { $_ -match 'elevation granted reason=sdsys local ssh' })
            $refs = @($since.Audit | Where-Object { $_ -match 'login refused account=sdsys reason=SDSYS requires an elevated session' })
            if ($grants.Count -eq 0) { Add-Row 'W10' 'the phantom of the granted session is refused' 'NOT RUN' 'the parent session was not granted (no "elevation granted reason=sdsys local ssh")' }
            elseif ($grants.Count -gt 1) { Add-Row 'W10' 'the phantom of the granted session is refused' 'FAIL' ($grants.Count.ToString() + ' grants: the phantom was granted too') }
            elseif ($refs.Count -gt 0) {
                Add-Row 'W10' 'the phantom of the granted session is refused' 'PASS' $refs[0]
                $w = ''
                if ($refs[0] -match 'why=(\S+)') { $w = $Matches[1] }
                Add-Row 'W10' 'the refusal''s why word (DESIGN.md wants no-terminal; a phantom carries no -SDSYSLOCAL, so the kernel may answer not-ssh first)' 'INFO' ('why=' + $w)
            } else { Add-Row 'W10' 'the phantom of the granted session is refused' 'FAIL' 'no refusal line for the phantom, and only one grant: did the phantom start?  Read the audit above' }
        } else { Add-Row 'W10' 'the row' 'NOT RUN' 'the person skipped it' }
    }
}

# ================================================================================================================ W11
if ($Run -contains 'w11' -and (Test-Ready 'W11')) {
    Say ''
    Say ('=== W11: plain ssh -t ' + $User + '@localhost is the ordinary session; ssh without -t asking sd-sdsys gets one line')
    if (-not (Set-Listed 'ssh' $User)) { Add-Row 'W11' 'the row' 'NOT RUN' 'the list could not be given the name' }
    else {
        $marks = New-Marks
        if (Wait-Person 'W11 (a)' @('In WINDOW B type:   ssh -t ' + $User + '@localhost', ('Type ' + $User + '''s Windows password.  You get ' + $User + '''s ORDINARY SD login (or LOGIN''s own refusal if it has no SD account).'), 'If an SD prompt appears, type OFF.')) {
            $since = Read-Since $marks
            if ($since.Svc.Count -eq 0) { Add-Row 'W11' 'plain ssh never reached the door' 'PASS' 'no "sdsys local:" line in sdsvc.log since the mark' } else { Add-Row 'W11' 'plain ssh never reached the door' 'FAIL' $since.Svc[0] }
            $lg = @($since.Audit | Where-Object { $_ -match '\blogin\b' -and $_ -match [regex]::Escape($User) })
            if ($lg.Count -gt 0) { Add-Row 'W11' 'LOGIN ran for the user as an ordinary session' 'PASS' $lg[0] } else { Add-Row 'W11' 'LOGIN ran for the user as an ordinary session' 'NOT RUN' ('no audit line names ' + $User + ' with login') }
            Set-PersonVerdict 'W11' 'no "SD password of sdsys:" was asked' 'Was the session FREE of any "SD password of sdsys:" prompt?'
        } else { Add-Row 'W11' 'the row (a)' 'NOT RUN' 'the person skipped it' }
        $marks = New-Marks
        if (Wait-Person 'W11 (b)' @('In WINDOW B type (NO -t this time):   ssh ' + $User + '@localhost sd-sdsys', ('Type ' + $User + '''s Windows password.  It should print one line: "sd-sdsys needs a terminal: ssh -t <user>@localhost sd-sdsys".'))) {
            $since = Read-Since $marks
            if ($since.Svc.Count -eq 0) { Add-Row 'W11' 'sd-sdsys without a terminal never reached the door' 'PASS' 'no "sdsys local:" line since the mark' } else { Add-Row 'W11' 'sd-sdsys without a terminal never reached the door' 'FAIL' $since.Svc[0] }
            Set-PersonVerdict 'W11' 'the one line "sd-sdsys needs a terminal" was printed (Q9)' 'Did window B print "sd-sdsys needs a terminal"?'
        } else { Add-Row 'W11' 'the row (b)' 'NOT RUN' 'the person skipped it' }
    }
}

# ================================================================================================================ W12
if ($Run -contains 'w12' -and (Test-Ready 'W12' -NeedAccount)) {
    Say ''
    Say '=== W12: an UNSAFE ssh list (a grant to Users added by hand): treated as none listed; clear repairs it'
    if (-not (Set-Listed 'ssh' $User)) { Add-Row 'W12' 'the row' 'NOT RUN' 'the list could not be given the name' }
    else {
        Say ('  sddl before: ' + (Get-ListSddl $SshList))
        try {
            $acl = Get-Acl -LiteralPath $SshList
            $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-545')), 'Read', 'Allow')))
            Set-Acl -LiteralPath $SshList -AclObject $acl
        } catch { Say ('  the grant could not be added: ' + $_.Exception.Message) }
        $after = Get-ListSddl $SshList
        Say ('  sddl after:  ' + $after)
        if ($after -notmatch 'S-1-5-32-545|;BU\)') { Add-Row 'W12' 'the row' 'NOT RUN' 'the list''s DACL could not be widened (the sddl above)' }
        else {
            $r = Invoke-Helper $Script:Helper @('-List', 'ssh', '-Action', 'status')
            Set-Verdict 'W12' 'status: unsafe, treated as none listed' @($r.Text) 'sdsys local ssh: unsafe, treated as none listed' @('sdsys local ssh: listed ') 'the helper'
            $marks = New-Marks
            if (Wait-Person 'W12' @(('In WINDOW B type:   ' + $sshCmdLocal), ('Type' + $User + '''s Windows password.  It should end with "sd-sdsys refused: list-unsafe".'))) {
                $since = Read-Since $marks
                Set-DoorRefusal 'W12' $User 'list-unsafe' $since
            } else { Add-Row 'W12' 'the door refused list-unsafe' 'NOT RUN' 'the person skipped it' }
            $r = Invoke-Helper $Script:Helper @('-List', 'ssh', '-Action', 'clear')
            Set-Verdict 'W12' 'clear removes the unsafe list' @($r.Text) 'sdsys local ssh: cleared, none listed' @('could not', 'is a link') 'the helper'
            Set-Verdict 'W12' 'the file is gone after clear' @('present ' + (Test-Path -LiteralPath $SshList)) '^present False$' @() 'Test-Path'
            $null = Set-Listed 'ssh' $User
            Show-Lists 'W12 after'
        }
    }
}

# ================================================================================================================ W13 / W14 / W16 (the API, a program as a test user)
$apiRows = @($Run | Where-Object { $_ -eq 'w13' -or $_ -eq 'w14' -or $_ -eq 'w15' -or $_ -eq 'w16' })
$Api = $null
$SdsysPw = $null
if ($apiRows.Count -gt 0 -and $installed) {
    Say ''
    Say '=== the API rows'' facts'
    $Api = Get-ApiFacts
    if ($Api.Ok) { $SdsysPw = Read-Secret '  SD password of sdsys (for the API rows; not shown, not stored)' }
}

function Invoke-ApiAsUser([string]$Row, [string]$Name, [string]$Sid) {
    if (-not $Api.Ok) { Add-Row $Row 'the row' 'NOT RUN' $Api.Why; return $null }
    $pw = Read-Secret ('  Windows password of ' + $Name + ' (to start the probe as ' + $Name + '; not shown, not stored)')
    $marks = New-Marks
    $r = Start-AsUser $Name $pw 'run-as.ps1' (Get-ProbeSpec $Api $Name) (Get-ProbeEnv $Api $SdsysPw) 120
    Start-Sleep -Seconds 2
    $since = Read-Since $marks
    if (-not $r.Ok) { Add-Row $Row 'the row' 'NOT RUN' $r.Why; return $null }
    if ($r.Out -notmatch ('runner pid \d+ user \S*\\' + [regex]::Escape($Name))) { Add-Row $Row 'the row' 'NOT RUN' ('the runner did not say it ran as ' + $Name); return $null }
    if ($r.Out -notmatch 'SCRAM:') { Add-Row $Row 'the row' 'NOT RUN' 'the probe printed no SCRAM line (python or the probe did not run as that user; its output is above)'; return $null }
    return @{ R = $r; Since = $since }
}

if ($Run -contains 'w13' -and (Test-Ready 'W13')) {
    Say ''
    Say ('=== W13: ' + $User + ' on the API list; its program at 127.0.0.1 signs in as sdsys')
    if (-not (Set-Listed 'api' $User)) { Add-Row 'W13' 'the row' 'NOT RUN' ($User + ' could not be put on the api list') }
    else {
        $x = Invoke-ApiAsUser 'W13' $User $UserSid
        if ($null -ne $x) {
            Set-Verdict 'W13' 'the probe as the listed user signed in as sdsys' @($x.R.Out -split "`n") '^SCRAM: server signature VERIFIED' @('SCRAM: login REFUSED') 'the probe'
            Set-Verdict 'W13' 'audit: elevation granted reason=sdsys api from=this machine user=<User>' $x.Since.Audit ('elevation granted reason=sdsys api from=this machine user=' + [regex]::Escape($User) + '\b') @('api refused user=sdsys') 'the audit trail'
        }
    }
}
if ($Run -contains 'w14' -and (Test-Ready 'W14' -NeedUnlisted)) {
    Say ''
    Say ('=== W14: the unlisted ' + $Unlisted + '''s program at 127.0.0.1 as sdsys (the api list holds ' + $User + ')')
    if (-not (Set-Listed 'api' $User)) { Add-Row 'W14' 'the row' 'NOT RUN' 'the api list could not be given a name' }
    else {
        $x = Invoke-ApiAsUser 'W14' $Unlisted $UnlistedSid
        if ($null -ne $x) {
            Set-Verdict 'W14' 'the probe as the unlisted user is refused' @($x.R.Out -split "`n") '^SCRAM: login REFUSED' @('SCRAM: server signature VERIFIED') 'the probe'
            Set-Verdict 'W14' 'audit: api refused ... sdsys API session opened by <Unlisted> from this machine why=not-listed' $x.Since.Audit ('sdsys API session opened by ' + [regex]::Escape($Unlisted) + ' from this machine why=not-listed') @('elevation granted') 'the audit trail'
        }
    }
}
if ($Run -contains 'w15' -and (Test-Ready 'W15')) {
    Say ''
    Say '=== W15: remote.sdsys api "any" does not admit a loopback peer; the address helper refuses 127.0.0.1 and ::1'
    if ($Script:ApiHelper -eq '') { Add-Row 'W15' 'the row' 'NOT RUN' 'sd-sdsysapi.ps1 is not installed' }
    else {
        $s0 = Invoke-Helper $Script:ApiHelper @('-Action', 'status')
        $prev = ''
        $m = [regex]::Match($s0.Text, 'sdsys over the API from other computers: on, from (.+)$', 'Multiline')
        if ($m.Success) { $prev = $m.Groups[1].Value.Trim() }
        Say ('  remote.sdsys api before: ' + $(if ($prev -ne '') { 'on, from ' + $prev } else { 'off' }) + ' (put back afterwards)')
        $r = Invoke-Helper $Script:ApiHelper @('-Action', 'on', '-Entries', '127.0.0.1')
        Set-Verdict 'W15' 'the address helper refuses 127.0.0.1' ($r.Text -split "`n") 'a loopback address is this computer, which only local.sdsys api lists: 127\.0\.0\.1' @('^sdsys over the API from other computers: on') 'the helper'
        $r = Invoke-Helper $Script:ApiHelper @('-Action', 'on', '-Entries', '::1')
        Set-Verdict 'W15' 'the address helper refuses ::1' ($r.Text -split "`n") 'a loopback address is this computer, which only local.sdsys api lists: ::1' @('^sdsys over the API from other computers: on') 'the helper'
        $r = Invoke-Helper $Script:ApiHelper @('-Action', 'on', '-Entries', 'any')
        Set-Verdict 'W15' 'remote.sdsys api on any (the helper)' ($r.Text -split "`n") 'sdsys over the API from other computers: on, from any' @('nothing was changed') 'the helper'
        if (-not $Api.Ok) { Add-Row 'W15' '"any" does not admit this administrator''s own program at 127.0.0.1 (not on the api list)' 'NOT RUN' $Api.Why }
        else {
            $marks = New-Marks
            $spec = Get-ProbeSpec $Api 'this window'
            $envs = Get-ProbeEnv $Api $SdsysPw
            Say ('  > ' + $spec.Exe + ' ' + ($spec.Argv -join ' ') + '   (as ' + $me.Name + ', elevated; SD_SCRAM_PASSWORD set, not shown)')
            foreach ($k in $envs.Keys) { Set-Item -Path ('Env:' + $k) -Value $envs[$k] }
            $argv = $spec.Argv
            $o = & $spec.Exe @argv 2>&1 | ForEach-Object { [string]$_ }
            Remove-Item -Path 'Env:SD_SCRAM_PASSWORD' -ErrorAction SilentlyContinue
            SayRaw 'the probe as this administrator' ($o -join "`n")
            Start-Sleep -Seconds 2
            $since = Read-Since $marks
            if (@($o | Where-Object { $_ -match '^SCRAM:' }).Count -eq 0) { Add-Row 'W15' '"any" does not admit this administrator''s own program at 127.0.0.1 (not on the api list)' 'NOT RUN' 'the probe printed no SCRAM line: it never reached the login (its output is above)' }
            else {
                Set-Verdict 'W15' '"any" does not admit this administrator''s own program at 127.0.0.1 (not on the api list)' $o '^SCRAM: login REFUSED' @('SCRAM: server signature VERIFIED') 'the probe'
                Set-Verdict 'W15' 'audit: the refusal is the loopback door''s (opened by ... from this machine), not the address list''s' $since.Audit 'sdsys API session opened by \S+ from this machine' @('elevation granted', 'not listed by remote.sdsys api') 'the audit trail'
            }
        }
        if ($prev -ne '') { $null = Invoke-Helper $Script:ApiHelper @('-Action', 'on', '-Entries', ($prev -replace '\s*,\s*', ',' -replace '\s+', ',')) }
        else { $null = Invoke-Helper $Script:ApiHelper @('-Action', 'off') }
    }
}
if ($Run -contains 'w16' -and (Test-Ready 'W16')) {
    Say ''
    Say ('=== W16: ' + $User + '''s program in its OWN interactive logon (runas''s way) is admitted, and the logon is recorded (D6)')
    if (-not (Set-Listed 'api' $User)) { Add-Row 'W16' 'the row' 'NOT RUN' 'the api list could not be given the name' }
    else {
        $x = Invoke-ApiAsUser 'W16' $User $UserSid
        if ($null -ne $x) {
            $L = $x.R.L
            if ($null -eq $L -or $L.Status -ne 0) { Add-Row 'W16' 'the runner''s logon: interactive (2), its SID the user''s' 'NOT RUN' 'the runner''s logon could not be read while it ran' }
            elseif ($L.Type -eq 2 -and $L.Sid -eq $UserSid) { Add-Row 'W16' 'the runner''s logon: interactive (2), its SID the user''s' 'PASS' ('type ' + $L.Type + ' sid ' + $L.Sid + ' package ' + $L.Package) }
            else { Add-Row 'W16' 'the runner''s logon: interactive (2), its SID the user''s' 'FAIL' ('type ' + $L.Type + ' sid ' + $L.Sid) }
            Set-Verdict 'W16' 'admitted as that user (D6: a logon of the user is the user''s own login)' $x.Since.Audit ('elevation granted reason=sdsys api from=this machine user=' + [regex]::Escape($User) + '\b') @('api refused user=sdsys') 'the audit trail'
        }
    }
}

# ================================================================================================================ W17
if ($Run -contains 'w17' -and (Test-Ready 'W17')) {
    Say ''
    Say '=== W17: tool.remote, the Remote admin view: U adds, X removes, C clears (the person, in an SDSYS session)'
    $null = Invoke-Helper $Script:Helper @('-List', 'api', '-Action', 'clear')
    Show-Lists 'W17 before'
    $marks = New-Marks
    if (Wait-Person 'W17' @('In an SDSYS session (the desktop SDSYS console, or a granted ' + $sshCmdLocal + '), type:   tool.remote',
                            'Open the view Remote admin (View > Remote admin).  On the field "Local API users":',
                            ('  U, type ' + $User + ', type it again when asked, and confirm  ->  ' + $User + ' is listed'),
                            ('  X, pick ' + $User + '  ->  removed'),
                            ('  U again to add ' + $User + ', then C  ->  cleared'),
                            'Leave the page and type OFF if this was an ssh session.')) {
        $since = Read-Since $marks
        Set-Verdict 'W17' 'audit: local.sdsys api add user=<User> status=ok' $since.Audit ('local\.sdsys api add user=' + [regex]::Escape($User.ToLower()) + ' status=ok') @() 'the audit trail'
        Set-Verdict 'W17' 'audit: local.sdsys api remove user=<User> status=ok' $since.Audit ('local\.sdsys api remove user=' + [regex]::Escape($User.ToLower()) + ' status=ok') @() 'the audit trail'
        Set-Verdict 'W17' 'audit: local.sdsys api clear status=ok' $since.Audit 'local\.sdsys api clear status=ok' @() 'the audit trail'
        Set-Verdict 'W17' 'the api list is gone after C' @('present ' + (Test-Path -LiteralPath $ApiList)) '^present False$' @() 'Test-Path'
    } else { Add-Row 'W17' 'the row' 'NOT RUN' 'the person skipped it' }
}

# ================================================================================================================ W18 / W19 (two phases each)
$snap18 = Join-Path $Work 'w18-lists-before-upgrade.txt'
$snap19 = Join-Path $Work 'w19-lists-before-uninstall.txt'
function Get-ListsText {
    $t = @()
    foreach ($p in @($SshList, $ApiList)) { if (Test-Path -LiteralPath $p) { $t += ($p + ' = ' + ([IO.File]::ReadAllText($p)).Replace("`n", ' | ')) } else { $t += ($p + ' = (absent)') } }
    return ($t -join "`n")
}
if ($Run -contains 'w18') {
    Say ''
    Say '=== W18: an UPGRADE keeps both lists'
    if (-not (Test-Path -LiteralPath $snap18)) {
        if (Test-Ready 'W18') {
            $ok = (Set-Listed 'ssh' $User) -and (Set-Listed 'api' $User)
            if (-not $ok) { Add-Row 'W18' 'phase 1' 'NOT RUN' 'the lists could not both be given the name' }
            else {
                Set-Content -LiteralPath $snap18 -Value (Get-ListsText) -Encoding ASCII
                SayRaw 'the lists before the upgrade (kept in w18-lists-before-upgrade.txt)' (Get-ListsText)
                Add-Row 'W18' 'phase 1: the lists were recorded; NOW run the upgrade install (step sheet), then -Only W18 again' 'INFO' $snap18
            }
        }
    } else {
        $was = [IO.File]::ReadAllText($snap18).TrimEnd()
        $now = (Get-ListsText).TrimEnd()
        SayRaw 'before the upgrade' $was
        SayRaw 'now' $now
        if (-not $installed) { Add-Row 'W18' 'phase 2' 'NOT RUN' 'SD is not installed now (was it uninstalled rather than upgraded?)' }
        elseif ($was -match '\(absent\)') { Add-Row 'W18' 'phase 2' 'NOT RUN' 'a list was absent before the upgrade: the record proves nothing' }
        else {
            Set-Verdict 'W18' 'both lists are the same after the upgrade' @($(if ($was -ceq $now) { 'same' } else { 'different' })) '^same$' @() 'the two records above'
            foreach ($p in @($SshList, $ApiList)) { Say ('  sddl now ' + $p + ': ' + (Get-ListSddl $p)) }
            $r = Invoke-Helper $Script:Helper @('-List', 'ssh', '-Action', 'status')
            Set-Verdict 'W18' 'the ssh list still reads as listed (not unsafe) after the upgrade' ($r.Text -split "`n")('sdsys local ssh: listed .*\b' + [regex]::Escape($User) + '\b') @('unsafe') 'the helper'
            Remove-Item -LiteralPath $snap18 -Force -ErrorAction SilentlyContinue
        }
    }
}
if ($Run -contains 'w19') {
    Say ''
    Say '=== W19: a FULL UNINSTALL removes both lists'
    if ($installed) {
        if (Test-Ready 'W19') {
            $ok = (Set-Listed 'ssh' $User) -and (Set-Listed 'api' $User)
            if (-not $ok) { Add-Row 'W19' 'phase 1' 'NOT RUN' 'the lists could not both be given the name' }
            else {
                Set-Content -LiteralPath $snap19 -Value (Get-ListsText) -Encoding ASCII
                SayRaw 'the lists before the uninstall' (Get-ListsText)
                Add-Row 'W19' 'phase 1: the lists are present and recorded; NOW uninstall SD fully (step sheet), then -Only W19 again' 'INFO' $snap19
            }
        }
    } elseif (-not (Test-Path -LiteralPath $snap19)) {
        Add-Row 'W19' 'phase 2' 'NOT RUN' 'there is no record that the lists were present before the uninstall (run -Only W19 BEFORE uninstalling)'
    } else {
        SayRaw 'before the uninstall' ([IO.File]::ReadAllText($snap19))
        Show-Lists 'after the uninstall'
        $left = @(@($SshList, $ApiList) | Where-Object { Test-Path -LiteralPath $_ })
        Set-Verdict 'W19' 'both lists are gone after the full uninstall' @('left ' + $left.Count + ': ' + ($left -join ' ')) '^left 0' @() 'Test-Path'
        Say ('  ' + $TlsDir + ' present now: ' + (Test-Path -LiteralPath $TlsDir))
        Remove-Item -LiteralPath $snap19 -Force -ErrorAction SilentlyContinue
    }
}

# ================================================================================================================ W20
if ($Run -contains 'w20' -and (Test-Ready 'W20')) {
    Say ''
    Say ('=== W20: a FAKE OpenSSH/Operational "Accepted ... from ::1" written by ' + $User + ' (F4) does not open the door')
    $prov = ''
    try { $prov = (Get-WinEvent -ListLog 'OpenSSH/Operational' -ErrorAction Stop).OwningProviderName } catch { }
    $tmpl = ''
    try { $tmpl = [string]((Get-WinEvent -ListProvider $prov -ErrorAction Stop).Events | Where-Object { $_.Id -eq 4 } | Select-Object -First 1).Template } catch { }
    Say ('  provider ''' + $prov + '''; event 4''s template: ' + $tmpl)
    $nData = ([regex]::Matches($tmpl, '<data ')).Count
    $lanA = Get-LanAddress
    if ($prov -eq '') { Add-Row 'W20' 'the row' 'NOT RUN' 'the OpenSSH/Operational channel or its provider could not be read' }
    elseif (-not (Set-Listed 'ssh' $User)) { Add-Row 'W20' 'the row' 'NOT RUN' 'the list could not be given the name' }
    else {
        $pw = Read-Secret ('  Windows password of ' + $User + ' (to write the event as ' + $User + '; not shown, not stored)')
        # (a) the stamped pid: written by the user, read back
        $tag = 'port ' + (Get-Random -Minimum 40000 -Maximum 49999)
        $text = 'Accepted password for ' + $User + ' from ::1 ' + $tag + ' ssh2'
        $payload = @('sshd: ' + $text)
        if ($nData -ge 2) { $payload = @('sshd', $text) }
        $t0 = Get-Date
        $w = Start-AsUser $User $pw 'write-event.ps1' @{ Provider = $prov; Id = 4; Payload = $payload; Hold = 1 } @{} 60
        $wpid = 0
        if ($w.Out -match 'writer pid (\d+)') { $wpid = [int]$Matches[1] }
        if (-not $w.Ok -or $w.Out -notmatch '(?m)^written') { Add-Row 'W20' '(a) the user''s fake event carries the writer''s own pid' 'NOT RUN' ('the user could not write to the channel: ' + ($w.Out -replace "`r?`n", ' ')) }
        else {
            Start-Sleep -Seconds 1
            $evs = Get-SshdAccepted $t0.AddSeconds(-2)
            $fake = @($evs | Where-Object { $_.Msg -match [regex]::Escape($tag) })
            $sshdPids = @([SdLsw.Native]::Snapshot() | Where-Object { $_.Name -ieq 'sshd.exe' } | ForEach-Object { [uint32]$_.Pid })
            if ($fake.Count -eq 0) { Add-Row 'W20' '(a) the user''s fake event carries the writer''s own pid' 'NOT RUN' 'the event the user wrote was not found again' }
            elseif ($fake[0].ProcId -eq $wpid -and $sshdPids -notcontains $fake[0].ProcId) { Add-Row 'W20' '(a) the user''s fake event carries the writer''s own pid' 'PASS' ('ProcessID ' + $fake[0].ProcId + ' = the writer ' + $wpid + '; sshd pids now: ' + ($sshdPids -join ',')) }
            else { Add-Row 'W20' '(a) the user''s fake event carries the writer''s own pid' 'FAIL' ('F4 FALSIFIED: ProcessID ' + $fake[0].ProcId + ', writer ' + $wpid + ', sshd pids ' + ($sshdPids -join ',')) }
        }
        # (b) a login from the LAN with a fake loopback record for its own port planted while it is made
        if ($lanA -eq '') { Add-Row 'W20' '(b) a LAN login with a planted loopback record is refused not-local' 'NOT RUN' 'no LAN address (pass -Lan)' }
        else {
            $marks = New-Marks
            $null = Wait-Person 'W20 (get ready)' @('Press Enter here, THEN type in WINDOW B:   ssh -t ' + $User + '@' + $lanA + ' sd-sdsys', 'and, slowly, ' + $User + '''s Windows password.  The script plants the fake record as soon as the connection appears.')
            $before = @{}
            foreach ($c in [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpConnections()) { $before[$c.RemoteEndPoint.ToString() + '>' + $c.LocalEndPoint.ToString()] = $true }
            $port = 0
            $until = (Get-Date).AddSeconds($WatchSeconds)
            while ($port -eq 0 -and (Get-Date) -lt $until) {
                foreach ($c in [Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().GetActiveTcpConnections()) {
                    if ($c.LocalEndPoint.Port -eq 22 -and $c.RemoteEndPoint.Address.ToString() -eq $lanA -and -not $before.ContainsKey($c.RemoteEndPoint.ToString() + '>' + $c.LocalEndPoint.ToString())) { $port = $c.RemoteEndPoint.Port; break }
                }
                Start-Sleep -Milliseconds 100
            }
            if ($port -eq 0) { Add-Row 'W20' '(b) a LAN login with a planted loopback record is refused not-local' 'NOT RUN' ('no new connection from ' + $lanA + ' to port 22 within ' + $WatchSeconds + ' s') }
            else {
                $text = 'Accepted password for ' + $User + ' from ::1 port ' + $port + ' ssh2'
                $payload = @('sshd: ' + $text)
                if ($nData -ge 2) { $payload = @('sshd', $text) }
                Say ('  the connection from ' + $lanA + ' port ' + $port + ' appeared; planting "' + $text + '" as ' + $User)
                $null = Start-AsUser $User $pw 'write-event.ps1' @{ Provider = $prov; Id = 4; Payload = $payload; Hold = 0 } @{} 60
                $null = Wait-Person 'W20 (b)' @('Window B should end with "sd-sdsys refused: not-local" (finish typing the password if you have not).')
                $null = Get-SshdAccepted $marks.Time.AddSeconds(-2)
                $since = Read-Since $marks
                Set-DoorRefusal 'W20' $User 'not-local' $since
                Add-Row 'W20' 'what (b) shows' 'INFO' 'the planted record names the real port; "not-local" means the door read A''s own record (its ProcessID), not the planted one; "no-session" would mean it took the planted ::1 text and then found no such TCP row'
            }
        }
    }
}

# ================================================================================================================ W21 (T0745 Q8)
if ($Run -contains 'w21') {
    Say ''
    Say '=== W21: the reused-pid attack on the API''s peer lookup (Linux T0745 Q8)'
    Add-Row 'W21' 'SD''s API door refuses a peer whose TCP-table owner pid was reused by a listed user''s process' 'NOT RUN' 'cannot be staged from outside: SD''s front reads the TCP table at accept (linuxio.c -> sdl_peer_record), and the connect itself triggers the accept, so the creator''s exit and the pid''s reuse cannot be placed between them.  The OS premise rule (b) rests on is staged below on a listener of this script''s own.'
    $lis = New-Object Net.Sockets.TcpListener([Net.IPAddress]::Loopback, 0)
    $lis.Start()
    $lport = $lis.LocalEndpoint.Port
    $aFile = Join-Path $Work 'w21-a.ps1'
    $aOut = Join-Path $OutDir 'w21-a.txt'
    Remove-Item -LiteralPath $aOut -Force -ErrorAction SilentlyContinue
    Set-Content -LiteralPath $aFile -Encoding ASCII -Value @(
        '# written by witness-localsdsys.ps1 (W21): connect, hand the socket to a child, exit without closing it',
        'param([int]$Port, [string]$Out)',
        'Add-Type -Namespace W21 -Name K -MemberDefinition ''[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetHandleInformation(IntPtr h, uint mask, uint flags);''',
        '$c = New-Object Net.Sockets.TcpClient',
        '$c.Connect(''127.0.0.1'', $Port)',
        '$inh = [W21.K]::SetHandleInformation($c.Client.Handle, 1, 1)',
        '$psi = New-Object Diagnostics.ProcessStartInfo',
        '$psi.FileName = (Join-Path $env:SystemRoot ''System32\PING.EXE'')',
        '$psi.Arguments = ''-n 120 127.0.0.1''',
        '$psi.UseShellExecute = $false',
        '$psi.CreateNoWindow = $true',
        '$g = [Diagnostics.Process]::Start($psi)',
        'Set-Content -LiteralPath $Out -Value ($PID.ToString() + '' '' + $g.Id + '' '' + ([Net.IPEndPoint]$c.Client.LocalEndPoint).Port + '' '' + $inh) -Encoding ASCII',
        '[Diagnostics.Process]::GetCurrentProcess().Kill()')
    $pa = New-Object Diagnostics.ProcessStartInfo
    $pa.FileName = Join-Path $SysDir 'WindowsPowerShell\v1.0\powershell.exe'
    $pa.Arguments = ('-NoProfile -ExecutionPolicy Bypass -File "' + $aFile + '" -Port ' + $lport + ' -Out "' + $aOut + '"')
    $pa.UseShellExecute = $false
    $pa.CreateNoWindow = $true
    Say ('  listener 127.0.0.1:' + $lport + '; > ' + $pa.FileName + ' ' + $pa.Arguments)
    $ap = [Diagnostics.Process]::Start($pa)
    $null = $ap.WaitForExit(60000)
    $ap.Dispose()
    $acc = $null
    if ($lis.Pending()) { $acc = $lis.AcceptTcpClient() }
    $aTxt = ''
    if (Test-Path -LiteralPath $aOut) { $aTxt = ([IO.File]::ReadAllText($aOut)).Trim() }
    Say ('  A wrote: ''' + $aTxt + ''' (A pid, child pid, A''s local port, inheritable set)')
    $parts = @($aTxt -split ' ')
    if ($parts.Count -lt 4) { Add-Row 'W21' 'premise: the TCP table still names the dead creator while its child holds the socket' 'NOT RUN' 'A did not report its pid and port' }
    else {
        $aPid = [uint32]$parts[0]
        $cport = [int]$parts[2]
        Start-Sleep -Milliseconds 500
        $aAlive = [SdLsw.Native]::Proc($aPid)
        Say ('  A now: ' + (Format-Proc $aAlive $null))
        $rows = @(Get-NetTCPConnection -LocalPort $cport -RemotePort $lport -ErrorAction SilentlyContinue)
        foreach ($t in $rows) { Say ('    tcp  local ' + $t.LocalAddress + ':' + $t.LocalPort + '  remote ' + $t.RemoteAddress + ':' + $t.RemotePort + '  state ' + $t.State + '  owner ' + $t.OwningProcess + '  created ' + $t.CreationTime.ToString('o')) }
        if ($rows.Count -eq 0) { Add-Row 'W21' 'premise: the TCP table still names the dead creator while its child holds the socket' 'NOT RUN' 'the connection was not in the table (the child did not keep it)' }
        else {
            $own = [uint32]$rows[0].OwningProcess
            if ($own -eq $aPid -and $aAlive.Error -ne 0) { Add-Row 'W21' 'premise: the TCP table still names the dead creator while its child holds the socket' 'PASS' ('owner ' + $own + ' = A, and A cannot be opened (error ' + $aAlive.Error + ')') }
            else { Add-Row 'W21' 'premise: the TCP table still names the dead creator while its child holds the socket' 'INFO' ('owner ' + $own + ', A ' + $aPid + ' (A open error ' + $aAlive.Error + '): the table does not keep a dead creator here') }
            $connMade = $rows[0].CreationTime.ToUniversalTime()
            Say ('  spinning suspended processes (at most 400, 60 s) for one that takes pid ' + $aPid)
            $sp = [SdLsw.Native]::SpinForPid($aPid, (Join-Path $SysDir 'cmd.exe'), 400, 60000)
            Say ('  tries ' + $sp.Tries + ', last pid ' + $sp.LastPid + ', found ' + $sp.Found + ', error ' + $sp.Error)
            if ($sp.Found) {
                $rows2 = @(Get-NetTCPConnection -LocalPort $cport -RemotePort $lport -ErrorAction SilentlyContinue)
                $made = [DateTime]::FromFileTimeUtc($sp.Created)
                Say ('  the reused pid ' + $aPid + ' made ' + $made.ToString('o') + '; the connection made ' + $connMade.ToString('o') + '; table owner now ' + $(if ($rows2.Count) { $rows2[0].OwningProcess } else { '(gone)' }))
                if ($made -gt $connMade) { Add-Row 'W21' 'rule (b): the process now at the owner pid is YOUNGER than the connection, so sdl_peer_record refuses it (other-session)' 'PASS' ('process ' + $made.ToString('HH:mm:ss.fffffff') + ' > connection ' + $connMade.ToString('HH:mm:ss.fffffff')) }
                else { Add-Row 'W21' 'rule (b): the process now at the owner pid is YOUNGER than the connection' 'FAIL' ('process ' + $made.ToString('o') + ' is not after the connection ' + $connMade.ToString('o')) }
            } else { Add-Row 'W21' 'rule (b): the process now at the owner pid is younger than the connection' 'NOT RUN' ('pid ' + $aPid + ' was not reused within the budget') }
            Say ('  ended ' + [SdLsw.Native]::ReleaseHeld() + ' suspended process(es) this row made')
        }
        try { if ($parts[1] -match '^\d+$') { Stop-Process -Id ([int]$parts[1]) -Force -ErrorAction SilentlyContinue; Say ('  ended A''s child (PING.EXE pid ' + $parts[1] + ')') } } catch { }
    }
    if ($null -ne $acc) { $acc.Close() }
    $lis.Stop()
}

# ================================================================================================================ cleanup
if ($Run -contains 'cleanup' -and $installed -and $Script:Helper -ne '') {
    Say ''
    Say '=== cleanup: both lists cleared (as delivered)'
    $r1 = Invoke-Helper $Script:Helper @('-List', 'ssh', '-Action', 'clear')
    $r2 = Invoke-Helper $Script:Helper @('-List', 'api', '-Action', 'clear')
    Set-Verdict 'cleanup' 'both list files are absent' @('left ' + @(@($SshList, $ApiList) | Where-Object { Test-Path -LiteralPath $_ }).Count) '^left 0$' @() 'Test-Path'
    Say ('  the test users ' + $User + ' and ' + $Unlisted + ' are left in place (Remove-LocalUser removes them if wanted).')
}

$code = Complete-Run
exit $code
