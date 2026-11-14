# remote-admin.ps1 - remote administration over ssh: the four walls around the Windows account SDRADMIN
#
# 13 Nov 26 Windows port - written for RELEASE_1.1 202, Linux S.106's remote.sdsys (sd-elevate sdsys-ssh, ssh-forcecommand.sh --open-sdsys /
# --close-sdsys / --sdsys-state) in the Windows form of .claude/design-remote-admin-20261113.md, with the owner's answers of 13 Nov 2026.
# 13 Nov 26 Windows port - RELEASE_1.1 280: -On enables SDRADMIN BEFORE the arm is checked (sshd -T -C cannot resolve a disabled account,
# so the installer's REMOTE.SDSYS ON failed every time); a shut arm for a disabled SDRADMIN is checked with sshd -t and says so.
# 13 Nov 26 Windows port - RELEASE_1.1 280: the broker task is registered by SDSYS itself or with SDSYS's Windows password (-SdsysPassword,
# asked by REMOTE.SDSYS at the terminal), before any wall moves; without either -On exits 4 having changed nothing.  Every task cmdlet
# stops on error, and "open" waits for the broker's pipe.
#
#   remote-admin.ps1 -Status          what the machine says, one line per wall; changes nothing
#   remote-admin.ps1 -On              opens remote administration for SDRADMIN (REMOTE.SDSYS ON runs it, after making the account)
#   remote-admin.ps1 -Off             shuts it again; nothing is asked, it tightens
#   remote-admin.ps1 -Off -KeepBroker the remote session's own OFF: run BY the broker, which then stops itself after it has answered
#   remote-admin.ps1 -Remove          the uninstaller's (sd.iss RemoveRemoteAdmin): every wall shut and every trace of this script removed
#
# WHY A SEPARATE ACCOUNT AND NOT SDSYS, which is Linux's.  SDSYS is a member of Windows Administrators and its SD sessions are elevated, so
# sshd's password for it would be a network password to the machine's administrator.  SDRADMIN is an ordinary SD user account (made by
# REMOTE.SDSYS ON through !create_account, so it carries SD's "SD account" stamp and is in sdusers and sdsshonly) that is NEVER in
# Administrators and never elevated.  What it may change it asks for through the broker (sd-radmin.ps1), which runs a FIXED list of SD
# account commands as an elevated SDSYS job; this script never lets it do more.
#
# THE FOUR WALLS, all four moved by -On and -Off together, read back by -Status:
#   account   the Windows account SDRADMIN is ENABLED only while open (Linux cannot do this: its sdsys is also the console login)
#   sdssh     SDRADMIN is in sdssh, the group SD's global "AllowGroups" names, only while open
#   sshd-arm  SD's remote administration block at the END of sshd_config: open (Linux's open arm, ForceCommand sd.exe) or closed
#             ("Match User sdradmin" then "DenyUsers *"); checked with "sshd -T -C" for both spellings of the name before it is kept
#   broker    the task \SD\sdcore-radmin (SDSYS, S4U, highest run level, at start-up) is enabled and running only while open
# and a fifth record, <ProgramData>\SD\remote-admin\state ("on" or "off"), which LOGIN reads: SDRADMIN lands only while it says on.
#
# EVERY TIME -On RUNS it also takes SDRADMIN out of Administrators' reach: it refuses if SDRADMIN is in Administrators; it removes it from
# Users (the owner's Q10), Remote Desktop Users, Remote Management Users, Backup Operators, sdapi and the sdfiles groups; it puts it in
# sdsshonly; and it gives the account itself SeDenyInteractiveLogonRight, SeDenyRemoteInteractiveLogonRight, SeDenyBatchLogonRight and
# SeDenyServiceLogonRight (no console, no Remote Desktop, no scheduled task, no service as SDRADMIN).  SeDenyNetworkLogonRight is NOT
# given: sshd's password sign-in is a network logon (deny-logon.ps1's header).  NOTE: taking the account out of BUILTIN\Users does not take
# Users out of its token - Authenticated Users is itself a member of Users - so that step is the owner's tidiness, not a wall.
#
# THE SUCCESS LINES the verb anchors on: "remote-admin: open" (-On), "remote-admin: closed" (-Off), "remote-admin: removed" (-Remove).
# Exit codes: 0 done; 1 refused or failed (the line before says why); 2 not possible on this machine (no ssh server, no sshd_config, no
# sdssh group, no account SDRADMIN - the verb makes it first); 3 sshd would not take the change and sshd_config is as it was before;
# 4 (-On only) SDSYS's Windows password is needed and was not given - nothing was changed, and REMOTE.SDSYS asks for it and runs -On again.
# -Status always exits 0 when it could read the machine and prints:
#   remote-admin=open|closed|absent|inconsistent  (and odd=<the walls that disagree> when inconsistent)
#   account=enabled|disabled|absent   sdssh=yes|no   sshd-arm=open|closed|none|damaged   broker=running|ready|disabled|absent   state=on|off|none
#
# ELEVATED ONLY: sshd_config, Task Scheduler's SDSYS task and the user rights need an administrator.  REMOTE.SDSYS runs it through SDSYS's
# elevated helper (!ps_script_out); an elevated administrator may run it by hand, as Linux's "sudo sd-elevate sdsys-ssh":
#   powershell -ExecutionPolicy Bypass -File "C:\Program Files\SD\remote-admin.ps1" -Status
#
# NOTHING EXISTS AS DELIVERED: no account, no task, no sshd lines, no state.  The installer runs nothing of this unless its remote
# administration question was answered yes (closed by default, Linux S.155); an upgrade runs nothing of it, so ON stays ON (Q7).

param(
    [switch]$On,
    [switch]$Off,
    [switch]$Status,
    [switch]$Remove,
    [switch]$KeepBroker,
    # 13 Nov 26 - RELEASE_1.1 280.  SDSYS's Windows password, for -On run by anyone but SDSYS: Windows registers an S4U task for SDSYS only
    # for SDSYS itself or for a caller that gives SDSYS's password (measured 13 Nov: an elevated administrator and SYSTEM are refused
    # without it; with it the task registers and keeps logon type S4U, so no password is stored).  REMOTE.SDSYS passes it as a SecureString
    # inside the script !ps_script_out writes to SD's restricted PSTMP file, never on a command line; it is used once and never printed.
    [Security.SecureString]$SdsysPassword = $null,
    # Where sd.exe is, for ForceCommand.  Set in the body, not as a default: $PSScriptRoot is empty in a param default (adopt-account.ps1).
    [string]$SdExe = ''
)

# Windows PowerShell's own module folders, as gpl.bp/ps_scripto sets them (RELEASE_1.1 111): Get-LocalUser and the ScheduledTasks module.
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"

$ErrorActionPreference = 'Stop'
$Prog = 'remote-admin'

# BEGIN radmin_functions
# The pure part: the sshd block and its reading.  gplbld/test-remoteadmin-units.ps1 lifts this block out and drives it.
$RadminUser     = 'sdradmin'
$RadminBegin    = '# --- BEGIN SD remote administration (RELEASE_1.1 202) - remote-admin.ps1 writes this; do not edit within this fence ---'
$RadminEnd      = '# --- END SD remote administration ---'
# Linux's open arm (ssh-forcecommand.sh sdsys_arm_lines), keyword for keyword, less GSSAPIAuthentication: Win32-OpenSSH has no GSSAPI.
$RadminOpenKeys = @(
    @('AuthenticationMethods', 'password'),
    @('KbdInteractiveAuthentication', 'no'),
    @('PasswordAuthentication', 'yes'),
    @('PubkeyAuthentication', 'no'),
    @('HostbasedAuthentication', 'no'),
    @('AuthorizedKeysFile', 'none'),
    @('MaxAuthTries', '3'),
    @('DisableForwarding', 'yes'),
    @('X11Forwarding', 'no'),
    @('AllowAgentForwarding', 'no'),
    @('AllowTcpForwarding', 'no'),
    @('AllowStreamLocalForwarding', 'no'),
    @('PermitTunnel', 'no'),
    @('PermitUserRC', 'no'),
    @('PermitTTY', 'yes')
)

function Get-RadminMatchLine([string]$machine) {
    # Both spellings, as allow-ssh-groups.ps1 gives AllowGroups both: Win32-OpenSSH may hand a local user to Match as "name" or "HOST\name".
    return ('Match User ' + $RadminUser + ',' + $machine.ToLowerInvariant() + '\' + $RadminUser)
}

function Get-RadminArmLines([string]$mode, [string]$machine, [string]$sdExe) {
    # The whole block, markers included.  'open' or 'closed'; anything else is $null.
    $lines = @($RadminBegin, (Get-RadminMatchLine $machine))
    if ($mode -ceq 'open') {
        foreach ($kv in $RadminOpenKeys) { $lines += ('    ' + $kv[0] + ' ' + $kv[1]) }
        $lines += ('    ForceCommand "' + $sdExe + '"')
    } elseif ($mode -ceq 'closed') {
        $lines += '    DenyUsers *'
    } else {
        return $null
    }
    $lines += $RadminEnd
    return ,$lines
}

function Get-RadminNewline([string]$text) {
    if ($text.Contains("`r`n")) { return "`r`n" }
    return "`n"
}

function Remove-RadminBlockText([string]$text) {
    # Every fenced block of ours, markers and their line ends included; nothing outside a fence is touched.
    $nl = Get-RadminNewline $text
    $lines = $text -split "`r?`n"
    $out = New-Object System.Collections.ArrayList
    $in = $false
    foreach ($l in $lines) {
        if ($l -ceq $RadminBegin) { $in = $true; continue }
        if ($in) { if ($l -ceq $RadminEnd) { $in = $false }; continue }
        $null = $out.Add($l)
    }
    return (($out.ToArray()) -join $nl)
}

function Add-RadminBlockText([string]$text, [string[]]$arm) {
    # The block goes LAST, after every Match, so it cannot capture a keyword that was global before it and nothing written after it is
    # read inside it unless somebody appends to the file by hand.  A file that did not end in a line end gets one first.
    $nl = Get-RadminNewline $text
    $base = Remove-RadminBlockText $text
    if ($base.Length -gt 0 -and -not $base.EndsWith("`n")) { $base += $nl }
    return ($base + ($arm -join $nl) + $nl)
}

function Get-RadminArmState([string]$text) {
    # 'open', 'closed', 'none', or 'damaged' (a fence without its end, two fences, or a fence holding neither form).
    $lines = $text -split "`r?`n"
    $begins = @($lines | Where-Object { $_ -ceq $RadminBegin }).Count
    $ends = @($lines | Where-Object { $_ -ceq $RadminEnd }).Count
    if ($begins -eq 0 -and $ends -eq 0) { return 'none' }
    if ($begins -ne 1 -or $ends -ne 1) { return 'damaged' }
    $in = $false; $body = @()
    foreach ($l in $lines) {
        if ($l -ceq $RadminBegin) { $in = $true; continue }
        if ($l -ceq $RadminEnd) { $in = $false; continue }
        if ($in) { $body += $l }
    }
    if ($body.Count -lt 2 -or $body[0] -notmatch '^Match User sdradmin,') { return 'damaged' }
    if ($body.Count -eq 2 -and $body[1] -ceq '    DenyUsers *') { return 'closed' }
    $want = @($RadminOpenKeys | ForEach-Object { '    ' + $_[0] + ' ' + $_[1] })
    if ($body.Count -eq ($want.Count + 2)) {
        for ($k = 0; $k -lt $want.Count; $k++) { if ($body[$k + 1] -cne $want[$k]) { return 'damaged' } }
        if ($body[$body.Count - 1] -cmatch '^    ForceCommand ".+"$') { return 'open' }
    }
    return 'damaged'
}

function ConvertFrom-SshdT([string[]]$tLines) {
    # sshd -T's "keyword value" lines into a table, keyword lower case, FIRST value kept (sshd keeps the first it obtains).
    $eff = @{}
    foreach ($l in $tLines) {
        $l = $l.Trim()
        if ($l -eq '') { continue }
        $sp = $l.IndexOf(' ')
        if ($sp -lt 1) { continue }
        $k = $l.Substring(0, $sp).ToLowerInvariant()
        if (-not $eff.ContainsKey($k)) { $eff[$k] = $l.Substring($sp + 1).Trim() }
    }
    return $eff
}

function Test-RadminEffective([string[]]$tLines, [string]$mode, [string]$sdExe) {
    # '' when sshd would give SDRADMIN exactly the arm asked for; otherwise the first reason it would not.  THE NULL CASE IS REFUSED: an
    # empty answer from sshd is not "nothing disagrees".
    $eff = ConvertFrom-SshdT $tLines
    if ($eff.Count -lt 10) { return 'sshd -T printed no configuration to read' }
    if ($mode -ceq 'closed') {
        $d = ''
        if ($eff.ContainsKey('denyusers')) { $d = $eff['denyusers'] }
        if (@($d -split '\s+') -notcontains '*') { return ('sshd would not refuse SDRADMIN (denyusers "' + $d + '")') }
        return ''
    }
    foreach ($kv in $RadminOpenKeys) {
        $k = $kv[0].ToLowerInvariant()
        if (-not $eff.ContainsKey($k)) { return ('sshd -T does not report ' + $k + ', so the open arm cannot be checked') }
        if ($eff[$k].ToLowerInvariant() -ne $kv[1].ToLowerInvariant()) {
            return ('sshd would give SDRADMIN "' + $k + ' ' + $eff[$k] + '" where the open arm says "' + $kv[1] + '": something sshd reads before the block sets it first')
        }
    }
    $fc = ''
    if ($eff.ContainsKey('forcecommand')) { $fc = $eff['forcecommand'].Trim('"') }
    if ($fc -ine $sdExe) { return ('sshd would force "' + $fc + '" and not SD (' + $sdExe + ')') }
    if ($eff.ContainsKey('denyusers')) { return ('a DenyUsers ("' + $eff['denyusers'] + '") applies to SDRADMIN, so the open arm would not open') }
    if ($eff.ContainsKey('allowusers')) { return ('an AllowUsers ("' + $eff['allowusers'] + '") applies, which leaves SDRADMIN out') }
    if (-not $eff.ContainsKey('allowgroups') -or @($eff['allowgroups'] -split '\s+' | ForEach-Object { ($_ -split '\\')[-1].ToLowerInvariant() }) -notcontains 'sdssh') {
        return 'SD''s own AllowGroups sdssh is not in force, so ssh is not limited to SD''s people; remote administration is not opened on such a server'
    }
    return ''
}
# END radmin_functions

function Out-Line([string]$t) { [Console]::Out.WriteLine($t) }
function Exit-With([int]$code, [string]$why) {
    Out-Line "${Prog}: $why"
    exit $code
}

$LsaSignature = @'
using System;
using System.Runtime.InteropServices;

public class SdRadminLsa {
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_OBJECT_ATTRIBUTES { public int Length; public IntPtr RootDirectory; public IntPtr ObjectName; public int Attributes; public IntPtr SecurityDescriptor; public IntPtr SecurityQualityOfService; }
    [StructLayout(LayoutKind.Sequential)]
    struct LSA_UNICODE_STRING { public ushort Length; public ushort MaximumLength; public IntPtr Buffer; }
    [DllImport("advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr SystemName, ref LSA_OBJECT_ATTRIBUTES ObjectAttributes, int DesiredAccess, out IntPtr PolicyHandle);
    [DllImport("advapi32.dll")] static extern uint LsaAddAccountRights(IntPtr PolicyHandle, byte[] AccountSid, LSA_UNICODE_STRING[] UserRights, int CountOfRights);
    [DllImport("advapi32.dll")] static extern uint LsaRemoveAccountRights(IntPtr PolicyHandle, byte[] AccountSid, bool AllRights, LSA_UNICODE_STRING[] UserRights, int CountOfRights);
    [DllImport("advapi32.dll")] static extern uint LsaClose(IntPtr PolicyHandle);
    [DllImport("advapi32.dll")] static extern int LsaNtStatusToWinError(uint Status);
    const int POLICY_ACCESS = 0x00000010 | 0x00000800;   // POLICY_CREATE_ACCOUNT | POLICY_LOOKUP_NAMES, as deny-logon.ps1
    const uint STATUS_OBJECT_NAME_NOT_FOUND = 0xC0000034;

    public static void Change(byte[] sid, string right, bool add) {
        LSA_OBJECT_ATTRIBUTES attrs = new LSA_OBJECT_ATTRIBUTES();
        attrs.Length = Marshal.SizeOf(typeof(LSA_OBJECT_ATTRIBUTES));
        IntPtr policy;
        uint st = LsaOpenPolicy(IntPtr.Zero, ref attrs, POLICY_ACCESS, out policy);
        if (st != 0) throw new Exception("LsaOpenPolicy failed, winerror " + LsaNtStatusToWinError(st));
        LSA_UNICODE_STRING[] r = new LSA_UNICODE_STRING[1];
        r[0].Buffer = Marshal.StringToHGlobalUni(right);
        r[0].Length = (ushort)(right.Length * 2);
        r[0].MaximumLength = (ushort)((right.Length + 1) * 2);
        try {
            st = add ? LsaAddAccountRights(policy, sid, r, 1) : LsaRemoveAccountRights(policy, sid, false, r, 1);
            if (st != 0 && !(st == STATUS_OBJECT_NAME_NOT_FOUND && !add))
                throw new Exception((add ? "LsaAddAccountRights" : "LsaRemoveAccountRights") + " failed, winerror " + LsaNtStatusToWinError(st));
        } finally {
            Marshal.FreeHGlobal(r[0].Buffer);
            LsaClose(policy);
        }
    }
}
'@
$DenyRights = @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight', 'SeDenyBatchLogonRight', 'SeDenyServiceLogonRight')

function Get-LocalSid([string]$name) {
    try {
        return (New-Object Security.Principal.NTAccount("$([Environment]::MachineName)\$name")).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { return '' }
}

function Get-GroupSid([string]$name) {
    $g = Get-LocalGroup -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $g) { return '' }
    return $g.SID.Value
}

function Test-InGroup([string]$groupSid, [string]$userSid) {
    # Throws when Windows cannot list the group: a caller that must be sure fails closed.
    foreach ($m in @(Get-LocalGroupMember -SID $groupSid -ErrorAction Stop)) {
        if ($null -ne $m.SID -and $m.SID.Value -eq $userSid) { return $true }
    }
    return $false
}

function Remove-FromGroup([string]$groupSid, [string]$userSid, [string]$label) {
    if ($groupSid -eq '') { return }
    $g = Get-LocalGroup -SID $groupSid -ErrorAction SilentlyContinue
    if ($null -eq $g) { return }
    if (Test-InGroup $groupSid $userSid) {
        Remove-LocalGroupMember -SID $groupSid -Member $userSid -ErrorAction Stop
        Out-Line "${Prog}: SDRADMIN taken out of $label"
    }
}

function Add-ToGroup([string]$groupSid, [string]$userSid, [string]$label) {
    if (-not (Test-InGroup $groupSid $userSid)) {
        Add-LocalGroupMember -SID $groupSid -Member $userSid -ErrorAction Stop
        Out-Line "${Prog}: SDRADMIN put in $label"
    }
}

function Set-DenyRights([string]$userSid, [bool]$add) {
    if (-not ('SdRadminLsa' -as [type])) { Add-Type -TypeDefinition $LsaSignature -Language CSharp | Out-Null }
    $sid = New-Object Security.Principal.SecurityIdentifier($userSid)
    $bytes = New-Object byte[] $sid.BinaryLength
    $sid.GetBinaryForm($bytes, 0)
    foreach ($r in $DenyRights) { [SdRadminLsa]::Change($bytes, $r, $add) }
    Out-Line ("${Prog}: " + $(if ($add) { 'SDRADMIN is denied ' } else { 'SDRADMIN no longer carries ' }) + ($DenyRights -join ', '))
}

function Get-StateDir { return (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD\remote-admin') }

function Set-StateFile([string]$word) {
    # The directory: SYSTEM and Administrators full control, sdusers read (LOGIN reads the state as SDRADMIN), nothing inherited.  The
    # broker's log in it gets its own ACL, administrators only (sd-radmin.ps1).
    $dir = Get-StateDir
    if (-not (Test-Path -LiteralPath $dir)) {
        $ds = New-Object Security.AccessControl.DirectorySecurity
        $ds.SetAccessRuleProtection($true, $false)
        $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
            $ds.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
        }
        $users = Get-GroupSid 'sdusers'
        if ($users -ne '') {
            $ds.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($users)), 'ReadAndExecute', $inh, 'None', 'Allow')))
        }
        $ds.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        [IO.Directory]::CreateDirectory($dir, $ds) | Out-Null
    }
    $item = Get-Item -LiteralPath $dir -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "$dir is a link; it was left as it is" }
    [IO.File]::WriteAllText((Join-Path $dir 'state'), ($word + "`n"), [Text.Encoding]::ASCII)
}

function Get-StateWord {
    $f = Join-Path (Get-StateDir) 'state'
    if (-not (Test-Path -LiteralPath $f)) { return 'none' }
    $w = ([IO.File]::ReadAllText($f)).Trim()
    if ($w -ceq 'on' -or $w -ceq 'off') { return $w }
    return 'none'
}

function Get-SshdPath {
    $p = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
    if (-not (Test-Path -LiteralPath $p)) {
        $pf = Join-Path $(if ($env:ProgramW6432) { $env:ProgramW6432 } else { $env:ProgramFiles }) 'OpenSSH\sshd.exe'
        if (Test-Path -LiteralPath $pf) { $p = $pf }
    }
    if (Test-Path -LiteralPath $p) { return $p }
    return ''
}

function Invoke-SshdT([string]$sshd, [string]$spec) {
    # @{ Code; Out = lines; Err = text }.  A Process with both streams read, not Start-Process with temp files and not "2>&1" (which
    # PowerShell 5.1 turns into a terminating error under Stop - allow-ssh-groups.ps1's note).
    # 13 Nov 26 - RELEASE_1.1 280: ONLY SYSTEM CAN ASK THIS ABOUT ANOTHER ACCOUNT.  sshd -T -C builds the named user's token to read its
    # groups (ga_init).  Measured on the host: from an elevated administrator's shell only the CALLER resolves (Don yes; SDSYS, two SD
    # accounts, sdrelay and sdrunin "ga_init, unable to resolve user"); as SYSTEM every enabled account resolves.  REMOTE.SDSYS ON runs
    # this elevated as an administrator, never as SYSTEM, so the check goes through a one-shot SYSTEM task (Invoke-SshdTAsSystem).
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { return (Invoke-SshdTAsSystem $sshd $spec) }
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $sshd
    $psi.Arguments = '-T -C "' + $spec + '"'
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    $p.WaitForExit()
    return @{ Code = $p.ExitCode; Out = @($o.Result -split "`r?`n"); Err = $e.Result.Trim() }
}

function ConvertTo-PsQuoted([string]$s) { return ("'" + $s.Replace("'", "''") + "'") }

function Invoke-SystemTask([string]$body, [string]$what) {
    # 13 Nov 26 - RELEASE_1.1 280.  Runs a fixed PowerShell text as SYSTEM by a one-shot task \SD\sdcore-radmin-check, always removed again,
    # for what only SYSTEM may do here (measured on the host 13 Nov): ask sshd -T -C about another account.  The text is
    # this script's own with no input from anyone, passed base64-encoded so no quoting reaches a shell; it writes @@OUT@@, @@ERR@@ and,
    # last, @@CODE@@, three files under %SystemRoot%\Temp named by a fresh GUID, read and deleted here.  @{ Code; Out = lines; Err }.
    $tag = [Guid]::NewGuid().ToString('N')
    $base = Join-Path $env:SystemRoot ('Temp\sd-radmin-check-' + $tag)
    $files = @(($base + '.out'), ($base + '.err'), ($base + '.code'))
    $text = $body.Replace('@@OUT@@', (ConvertTo-PsQuoted $files[0])).Replace('@@ERR@@', (ConvertTo-PsQuoted $files[1])).Replace('@@CODE@@', (ConvertTo-PsQuoted $files[2]))
    $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($text))
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        Out-Line "${Prog}: $what, as SYSTEM (a few seconds)..."
        $act = New-ScheduledTaskAction -Execute $ps -Argument ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $enc)
        $pr = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        Register-ScheduledTask -TaskName 'sdcore-radmin-check' -TaskPath '\SD\' -Action $act -Principal $pr -Force -ErrorAction Stop | Out-Null
        Start-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin-check' -ErrorAction Stop
        $deadline = (Get-Date).AddSeconds(60)
        while ((Get-Date) -lt $deadline -and -not (Test-Path -LiteralPath $files[2])) { Start-Sleep -Milliseconds 250 }
        if (-not (Test-Path -LiteralPath $files[2])) {
            return @{ Code = -1; Out = @(); Err = 'the step run as SYSTEM did not finish in 60 seconds' }
        }
        Start-Sleep -Milliseconds 200
        $code = -1
        if (-not [int]::TryParse(([IO.File]::ReadAllText($files[2])).Trim(), [ref]$code)) { $code = -1 }
        $out = if (Test-Path -LiteralPath $files[0]) { [IO.File]::ReadAllText($files[0]) } else { '' }
        $err = if (Test-Path -LiteralPath $files[1]) { [IO.File]::ReadAllText($files[1]) } else { '' }
        return @{ Code = $code; Out = @($out -split "`r?`n"); Err = $err.Trim() }
    } finally {
        Unregister-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin-check' -Confirm:$false -ErrorAction SilentlyContinue
        foreach ($f in $files) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue } }
    }
}

function Invoke-SshdTAsSystem([string]$sshd, [string]$spec) {
    # sshd -T -C as SYSTEM.  The sshd path and the spec ("user=<SDRADMIN, either spelling>,host=sdcheck,addr=192.0.2.1") are this
    # script's own.  The configuration it prints is sshd_config's, which every user can already read.
    $body = @(
        ('$psi = New-Object Diagnostics.ProcessStartInfo; $psi.FileName = ' + (ConvertTo-PsQuoted $sshd)),
        ('$psi.Arguments = ' + (ConvertTo-PsQuoted ('-T -C "' + $spec + '"'))),
        '$psi.UseShellExecute = $false; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true; $psi.CreateNoWindow = $true',
        '$p = [Diagnostics.Process]::Start($psi); $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync(); $p.WaitForExit()',
        '[IO.File]::WriteAllText(@@OUT@@, $o.Result)',
        '[IO.File]::WriteAllText(@@ERR@@, $e.Result)',
        '[IO.File]::WriteAllText(@@CODE@@, [string]$p.ExitCode)'
    ) -join "`n"
    return (Invoke-SystemTask $body ('asking sshd what it would give ' + $spec.Split(',')[0]))
}

function Test-BrokerPipe {
    # The broker's own success: its pipe exists (sd-radmin.ps1 makes \\.\pipe\sd-radmin, first instance only).
    return (@([IO.Directory]::GetFiles('\\.\pipe\') | Where-Object { $_ -ieq '\\.\pipe\sd-radmin' }).Count -gt 0)
}

function Register-BrokerTask([string]$xml, [string]$sdsysSid, [Security.SecureString]$pw) {
    # 13 Nov 26 - RELEASE_1.1 280.  The broker runs as SDSYS by S4U, and Windows registers an S4U task for SDSYS only for SDSYS itself or
    # for a caller that gives SDSYS's password.  Measured on the host 13 Nov (probes 4 to 6): an elevated administrator is refused ("Access
    # is denied") in every variant, SYSTEM is refused too, and an elevated administrator that passes SDSYS's password to
    # RegisterTaskDefinition with logon type S4U is accepted and the task KEEPS logon type S4U - nothing is stored.  So SDSYS (REMOTE.SDSYS
    # ON at its console) registers it as itself, and anyone else (the installer) with $pw.  The logon type is read back, and a task that
    # came back as anything but S4U - a stored password - is deleted and refused.  Throws on any failure.
    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq $sdsysSid) {
        Register-ScheduledTask -TaskName 'sdcore-radmin' -TaskPath '\SD\' -Xml $xml -Force -ErrorAction Stop | Out-Null
        return
    }
    if ($null -eq $pw -or $pw.Length -eq 0) { throw 'SDSYS''s Windows password is needed to register the broker task, and none was given' }
    $user = (New-Object Security.Principal.SecurityIdentifier($sdsysSid)).Translate([Security.Principal.NTAccount]).Value
    $svc = New-Object -ComObject Schedule.Service
    $svc.Connect()
    $folder = $svc.GetFolder('\SD')
    $def = $svc.NewTask(0)
    $def.XmlText = $xml
    $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pw)
    try {
        # 6 = TASK_CREATE_OR_UPDATE, 2 = TASK_LOGON_S4U.
        $null = $folder.RegisterTaskDefinition('sdcore-radmin', $def, 6, $user, [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr), 2, $null)
    } catch {
        throw ('the broker task could not be registered with SDSYS''s Windows password (a wrong password is refused here): ' + $_.Exception.Message.Trim())
    } finally {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
    $lt = [int]$folder.GetTask('sdcore-radmin').Definition.Principal.LogonType
    if ($lt -ne 2) {
        try { $folder.DeleteTask('sdcore-radmin', 0) } catch { }
        throw ("the broker task came back with logon type $lt, not S4U, so a password would have been stored; it is deleted")
    }
}

function Test-SshdArm([string]$sshd, [string]$mode, [string]$sdExe) {
    # Both spellings of the name, the way the arm's Match line names it.  '' or why.
    # 13 Nov 26 - RELEASE_1.1 280: sshd -T -C cannot resolve a DISABLED account (ga_init; measured on the host).  An open arm is never
    # written for one (-On enables SDRADMIN first).  A SHUT arm for a disabled SDRADMIN - -On's undo before the enable, or OFF on an
    # account already disabled - is checked as a whole file with "sshd -t" instead, and $script:ArmCheck says so to the caller's line:
    # a disabled account cannot sign in at all, and the DenyUsers arm is the second wall, not the only one.
    $script:ArmCheck = 'sshd -T'
    $acct = Get-LocalUser -Name $RadminUser -ErrorAction SilentlyContinue
    if ($null -ne $acct -and -not $acct.Enabled) {
        if ($mode -cne 'closed') { return 'SDRADMIN is disabled, and sshd cannot resolve a disabled account to check an open arm' }
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = $sshd
        $psi.Arguments = '-t'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.CreateNoWindow = $true
        $p = [Diagnostics.Process]::Start($psi)
        $o = $p.StandardOutput.ReadToEndAsync()
        $e = $p.StandardError.ReadToEndAsync()
        $p.WaitForExit()
        $null = $o.Result
        if ($p.ExitCode -ne 0) { return ('sshd -t refused the configuration: ' + $e.Result.Trim()) }
        $script:ArmCheck = 'sshd -t only: SDRADMIN is disabled, which sshd -T cannot resolve'
        return ''
    }
    foreach ($u in @($RadminUser, ([Environment]::MachineName.ToLowerInvariant() + '\' + $RadminUser))) {
        $r = Invoke-SshdT $sshd ('user=' + $u + ',host=sdcheck,addr=192.0.2.1')
        if ($r.Code -ne 0) { return ('sshd -T refused the configuration: ' + $r.Err) }
        $why = Test-RadminEffective $r.Out $mode $sdExe
        if ($why -ne '') { return ($why + ' (as ' + $u + ')') }
    }
    return ''
}

function Write-SshdArm([string]$cfg, [string]$sshd, [string]$mode, [string]$sdExe) {
    # Writes the arm, checks it, and on any disagreement puts the file back BYTE FOR BYTE.  '' or why.
    $orig = [IO.File]::ReadAllBytes($cfg)
    $text = [Text.Encoding]::ASCII.GetString($orig)
    $arm = Get-RadminArmLines $mode ([Environment]::MachineName) $sdExe
    [IO.File]::WriteAllText($cfg, (Add-RadminBlockText $text $arm), [Text.Encoding]::ASCII)
    $why = ''
    try { $why = Test-SshdArm $sshd $mode $sdExe } catch { $why = $_.Exception.Message }
    if ($why -ne '') { [IO.File]::WriteAllBytes($cfg, $orig) }
    return $why
}

function Get-TaskState {
    $t = Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction SilentlyContinue
    if ($null -eq $t) { return 'absent' }
    switch ([string]$t.State) {
        'Running'  { return 'running' }
        'Ready'    { return 'ready' }
        'Queued'   { return 'ready' }
        'Disabled' { return 'disabled' }
    }
    return 'disabled'
}

function Get-BrokerXml([string]$sdsysSid) {
    $e = { param($t) [Security.SecurityElement]::Escape($t) }
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $script = Join-Path $PSScriptRoot 'sd-radmin.ps1'
    $work = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD\sdsys'
    return @"
<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>SD remote administration helper (remote.sdsys): runs the remote administration account's fixed list of account commands; written by remote-admin.ps1, changed only by remote-admin.ps1</Description></RegistrationInfo>
  <Triggers><BootTrigger><Enabled>true</Enabled></BootTrigger></Triggers>
  <Principals><Principal id="Author"><UserId>$(& $e $sdsysSid)</UserId><LogonType>S4U</LogonType><RunLevel>HighestAvailable</RunLevel></Principal></Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>true</StartWhenAvailable>
    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <WakeToRun>false</WakeToRun>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <RestartOnFailure><Interval>PT1M</Interval><Count>3</Count></RestartOnFailure>
  </Settings>
  <Actions Context="Author"><Exec><Command>$(& $e $ps)</Command><Arguments>-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "$(& $e $script)" -Serve</Arguments><WorkingDirectory>$(& $e $work)</WorkingDirectory></Exec></Actions>
</Task>
"@
}

function Close-Walls([string]$userSid, [bool]$keepBroker, [string]$armMode) {
    # The tightening half, shared by -Off, -Remove and -On's undo.  Each wall is tried whatever happened to the one before; the number of
    # walls left open comes back.  $armMode: 'closed' (OFF) or 'none' (the uninstaller takes the block away altogether).
    $left = 0
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    $sshd = Get-SshdPath
    try {
        if (Test-Path -LiteralPath $cfg) {
            $text = [IO.File]::ReadAllText($cfg)
            if ($armMode -ceq 'none') {
                if ((Get-RadminArmState $text) -ne 'none') {
                    [IO.File]::WriteAllText($cfg, (Remove-RadminBlockText $text), [Text.Encoding]::ASCII)
                    Out-Line "${Prog}: the remote administration block is removed from sshd_config"
                }
            } elseif ($sshd -ne '') {
                $why = Write-SshdArm $cfg $sshd 'closed' (Get-SdExePath)
                if ($why -ne '') { $left++; Out-Line "${Prog}: the sshd arm could not be shut ($why); sshd_config is as it was" }
                else { Out-Line "${Prog}: the sshd arm is shut (DenyUsers; checked by $script:ArmCheck)" }
            }
            if ($null -ne (Get-Service sshd -ErrorAction SilentlyContinue)) { Restart-Service sshd -ErrorAction SilentlyContinue }
        }
    } catch { $left++; Out-Line "${Prog}: sshd_config: $($_.Exception.Message)" }

    if ($userSid -ne '') {
        try { Remove-FromGroup (Get-GroupSid 'sdssh') $userSid 'sdssh' } catch { $left++; Out-Line "${Prog}: sdssh: $($_.Exception.Message)" }
        try {
            $u = Get-LocalUser -SID $userSid -ErrorAction Stop
            if ($u.Enabled) { Disable-LocalUser -SID $userSid -ErrorAction Stop; Out-Line "${Prog}: the Windows account SDRADMIN is disabled" }
        } catch { $left++; Out-Line "${Prog}: the account: $($_.Exception.Message)" }
    }

    try {
        $t = Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction SilentlyContinue
        if ($null -ne $t) {
            if ($armMode -ceq 'none') {
                Unregister-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -Confirm:$false -ErrorAction Stop
                Out-Line "${Prog}: the broker task is removed"
            } else {
                if (-not $keepBroker -and [string]$t.State -eq 'Running') { Stop-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction Stop }
                # 13 Nov 26 - RELEASE_1.1 280: disabling re-saves the task, which for an SDSYS task an administrator may be refused without
                # SDSYS's password (not measured); deleting it is allowed (measured 13 Nov).  So a refused disable deletes it instead: the
                # next ON registers it again, which needs SDSYS or its password anyway.
                $how = 'disabled'
                try { Disable-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction Stop | Out-Null }
                catch {
                    Unregister-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -Confirm:$false -ErrorAction Stop
                    $how = "removed (disabling it was refused: $($_.Exception.Message.Trim()))"
                }
                Out-Line ("${Prog}: the broker task is $how" + $(if ($keepBroker) { '; the broker stops itself when it has answered' } else { '' }))
            }
        }
    } catch { $left++; Out-Line "${Prog}: the broker task: $($_.Exception.Message)" }

    try {
        if ($armMode -ceq 'none') {
            $dir = Get-StateDir
            if (Test-Path -LiteralPath $dir) { Remove-Item -LiteralPath $dir -Recurse -Force; Out-Line "${Prog}: $dir is removed" }
        } else {
            Set-StateFile 'off'
        }
    } catch { $left++; Out-Line "${Prog}: the state: $($_.Exception.Message)" }
    return $left
}

function Get-SdExePath {
    if ($script:SdExe -ne '') { return $script:SdExe }
    return (Join-Path $PSScriptRoot 'usr\bin\sd.exe')
}

function Show-Status {
    $userSid = Get-LocalSid 'SDRADMIN'
    $acct = 'absent'
    if ($userSid -ne '') {
        $u = Get-LocalUser -SID $userSid -ErrorAction SilentlyContinue
        if ($null -ne $u) { $acct = $(if ($u.Enabled) { 'enabled' } else { 'disabled' }) }
    }
    $inSsh = 'no'
    $sshSid = Get-GroupSid 'sdssh'
    if ($userSid -ne '' -and $sshSid -ne '') { if (Test-InGroup $sshSid $userSid) { $inSsh = 'yes' } }
    $arm = 'none'
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (Test-Path -LiteralPath $cfg) { $arm = Get-RadminArmState ([IO.File]::ReadAllText($cfg)) }
    $broker = Get-TaskState
    $state = Get-StateWord

    $openW = @{ account = ($acct -eq 'enabled'); sdssh = ($inSsh -eq 'yes'); 'sshd-arm' = ($arm -eq 'open'); broker = ($broker -eq 'running' -or $broker -eq 'ready'); state = ($state -eq 'on') }
    $nOpen = @($openW.Values | Where-Object { $_ }).Count
    if ($acct -eq 'absent' -and $arm -eq 'none' -and $broker -eq 'absent' -and $state -eq 'none') { $overall = 'absent' }
    elseif ($nOpen -eq 5) { $overall = 'open' }
    elseif ($nOpen -eq 0 -and $arm -ne 'damaged') { $overall = 'closed' }
    else { $overall = 'inconsistent' }
    Out-Line "remote-admin=$overall"
    if ($overall -eq 'inconsistent') {
        $majority = ($nOpen -ge 3)
        $odd = @($openW.Keys | Sort-Object | Where-Object { $openW[$_] -ne $majority })
        if ($arm -eq 'damaged') { $odd = @($odd + 'sshd-arm' | Select-Object -Unique) }
        Out-Line ('odd=' + ($odd -join ','))
    }
    Out-Line "account=$acct"
    Out-Line "sdssh=$inSsh"
    Out-Line "sshd-arm=$arm"
    Out-Line "broker=$broker"
    Out-Line "state=$state"
}

try {
    $n = @($On, $Off, $Status, $Remove | Where-Object { $_ }).Count
    if ($n -ne 1) { Exit-With 1 'usage: remote-admin.ps1 -Status | -On | -Off [-KeepBroker] | -Remove' }
    if ($KeepBroker -and -not $Off) { Exit-With 1 '-KeepBroker goes with -Off only' }
    if ($SdExe -eq '') { $SdExe = Join-Path $PSScriptRoot 'usr\bin\sd.exe' }

    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.SecurityIdentifier]'S-1-5-32-544')) {
        Exit-With 1 'this session is not elevated; sshd_config, the broker task and the user rights need an administrator'
    }

    if ($Status) { Show-Status; exit 0 }

    $userSid = Get-LocalSid 'SDRADMIN'

    if ($Off) {
        Out-Line "${Prog}: -Off: the sshd arm shut, SDRADMIN out of sdssh and disabled, the broker task disabled, the state off"
        $left = Close-Walls $userSid ([bool]$KeepBroker) 'closed'
        if ($left -gt 0) { Exit-With 1 "$left of the walls could not be shut; the lines above say which" }
        Out-Line "${Prog}: closed"
        exit 0
    }

    if ($Remove) {
        # The uninstaller's.  The account itself is left (disabled, out of sdssh, with its deny rights taken off with it) for the
        # uninstaller's "Remove the Windows accounts SD Core created?" question, which removes every account carrying SD's stamp: it stays
        # in sdusers, which is the set that question reads.
        Out-Line "${Prog}: -Remove: the broker task, the sshd block, sdssh and the state go; the account is left disabled for the accounts question"
        $left = Close-Walls $userSid $false 'none'
        if ($userSid -ne '') {
            try { Set-DenyRights $userSid $false } catch { $left++; Out-Line "${Prog}: the user rights: $($_.Exception.Message)" }
        }
        if ($left -gt 0) { Exit-With 1 "$left things could not be removed; the lines above say which" }
        Out-Line "${Prog}: removed"
        exit 0
    }

    # -------------------------------------------------------------------- -On
    $sshd = Get-SshdPath
    if ($sshd -eq '') { Exit-With 2 'there is no ssh server on this machine (sshd.exe); remote administration needs one' }
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (-not (Test-Path -LiteralPath $cfg)) { Exit-With 2 "there is no $cfg; sshd has never started" }
    $sshSid = Get-GroupSid 'sdssh'
    if ($sshSid -eq '') { Exit-With 2 'there is no sdssh group; SD''s ssh access was never set up here' }
    $onlySid = Get-GroupSid 'sdsshonly'
    if ($onlySid -eq '') { Exit-With 2 'there is no sdsshonly group; SD''s ssh-only rule was never set up here' }
    if ($userSid -eq '') { Exit-With 2 'there is no Windows account SDRADMIN; REMOTE.SDSYS ON makes it first' }
    $u = Get-LocalUser -SID $userSid -ErrorAction Stop
    if ($u.Description -cne 'SD account') { Exit-With 1 'the Windows account SDRADMIN was not made by SD (no "SD account" stamp); it is left as it is' }
    if (Test-InGroup 'S-1-5-32-544' $userSid) { Exit-With 1 'SDRADMIN is a member of Administrators; remote administration is never opened for an administrator - take it out first' }
    if (-not (Test-Path -LiteralPath $SdExe)) { Exit-With 2 "there is no $SdExe for ForceCommand" }
    if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'sd-radmin.ps1'))) { Exit-With 2 'sd-radmin.ps1 is not beside this script' }
    $sdsysSid = Get-LocalSid 'SDSYS'
    if ($sdsysSid -eq '') { Exit-With 2 'there is no local account SDSYS to run the broker as' }

    # 13 Nov 26 - RELEASE_1.1 280: THE BROKER TASK FIRST, BEFORE ANY WALL MOVES.  Only SDSYS, or a caller holding SDSYS's Windows password,
    # can register it (Register-BrokerTask's header).  Without either this exits 4 having changed nothing, and REMOTE.SDSYS asks for the
    # password at the terminal and runs -On again.  A wrong password is refused here too, still before anything has changed.
    $asSdsys = ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -eq $sdsysSid)
    if (-not $asSdsys -and ($null -eq $SdsysPassword -or $SdsysPassword.Length -eq 0)) {
        Exit-With 4 'the broker task runs as SDSYS, and this is not SDSYS: SDSYS''s Windows password is needed to register it; nothing was changed'
    }
    try {
        Register-BrokerTask (Get-BrokerXml $sdsysSid) $sdsysSid $SdsysPassword
    } catch {
        Exit-With 1 "$($_.Exception.Message); nothing else was changed"
    } finally {
        $SdsysPassword = $null
    }
    Out-Line "${Prog}: the broker task \SD\sdcore-radmin is registered to run as SDSYS ($(if ($asSdsys) { 'by SDSYS' } else { 'with SDSYS''s password; no password is stored' }))"

    Out-Line "${Prog}: -On: the sshd arm opened for SDRADMIN, SDRADMIN in sdssh and enabled, the broker task \SD\sdcore-radmin running as SDSYS, the state on"
    try {
        # Out of every group that would give it more than an SD user has (Users is the owner's Q10), into sdsshonly, and its own deny rights.
        foreach ($g in @(@('S-1-5-32-545', 'Users'), @('S-1-5-32-555', 'Remote Desktop Users'), @('S-1-5-32-580', 'Remote Management Users'),
                         @('S-1-5-32-551', 'Backup Operators'), @((Get-GroupSid 'sdapi'), 'sdapi'), @((Get-GroupSid 'sdfiles'), 'sdfiles'),
                         @((Get-GroupSid 'sdfileswrite'), 'sdfileswrite'), @((Get-GroupSid 'sdfilesadmin'), 'sdfilesadmin'))) {
            Remove-FromGroup $g[0] $userSid $g[1]
        }
        Add-ToGroup $onlySid $userSid 'sdsshonly'
        Set-DenyRights $userSid $true
    } catch {
        $null = Close-Walls $userSid $false 'closed'
        Exit-With 1 "SDRADMIN's groups or rights could not be set ($($_.Exception.Message)); every wall is shut"
    }

    # 13 Nov 26 - RELEASE_1.1 280: ENABLED BEFORE THE ARM IS CHECKED.  sshd -T -C resolves the user's groups (ga_init), and Win32-OpenSSH
    # cannot resolve a DISABLED account: measured 13 Nov on the host, "ga_init, unable to resolve user" for sdradmin, DefaultAccount and
    # Guest, all disabled, and 86 lines for an enabled account.  Enabled after the check, as first built, -On could never succeed.  Here
    # SDRADMIN is still outside sdssh (AllowGroups refuses it ssh) and already holds its deny rights; an undo below disables it again.
    try {
        Enable-LocalUser -SID $userSid -ErrorAction Stop
    } catch {
        $null = Close-Walls $userSid $false 'closed'
        Exit-With 1 "the Windows account SDRADMIN could not be enabled ($($_.Exception.Message)); every wall is shut"
    }
    Out-Line "${Prog}: the Windows account SDRADMIN is enabled (not yet in sdssh, so ssh still refuses it)"

    $why = Write-SshdArm $cfg $sshd 'open' $SdExe
    if ($why -ne '') {
        $null = Close-Walls $userSid $false 'closed'
        Exit-With 3 "sshd would not give SDRADMIN the open arm: $why.  sshd_config is as it was and every wall is shut"
    }
    Out-Line "${Prog}: the sshd arm is open; sshd -T gives SDRADMIN the open keywords for both spellings of its name"

    # 13 Nov 26 - RELEASE_1.1 280: EVERY TASK CMDLET CARRIES -ErrorAction Stop, AND "open" WAITS FOR THE BROKER'S PIPE.  The ScheduledTasks
    # cmdlets are a module's, and $ErrorActionPreference = 'Stop' above does not reach into a module's scope in Windows PowerShell 5.1:
    # on the 13 Nov host cycle Register-ScheduledTask was refused ("Access is denied"), Enable and Start found no task, and this block
    # carried on, wrote the state on and printed "registered and started" and "open" with no broker - a false success that left the
    # walls open.  Now a failure lands in the catch (every wall shut, the state off), and success is \\.\pipe\sd-radmin existing.
    try {
        Add-ToGroup $sshSid $userSid 'sdssh'
        Restart-Service sshd -ErrorAction Stop
        # Registered above, enabled by its own definition (Get-BrokerXml's <Enabled>true</Enabled>): no Enable-ScheduledTask, which re-saves
        # the task and might want SDSYS's password again.
        Set-StateFile 'on'
        # Started afresh even when it was running: the broker reads SDRADMIN's SID once, at start, for its pipe's access list.
        if ((Get-TaskState) -eq 'running') { Stop-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction Stop }
        Start-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction Stop
        Out-Line "${Prog}: the broker task is registered; waiting for its pipe \\.\pipe\sd-radmin (up to 20 seconds)..."
        $deadline = (Get-Date).AddSeconds(20)
        while ((Get-Date) -lt $deadline -and -not (Test-BrokerPipe)) { Start-Sleep -Milliseconds 250 }
        if (-not (Test-BrokerPipe)) { throw ('the broker started but its pipe \\.\pipe\sd-radmin did not appear in 20 seconds (task state ' + (Get-TaskState) + ')') }
        Out-Line "${Prog}: the broker is running: \\.\pipe\sd-radmin is there"
    } catch {
        $msg = $_.Exception.Message
        $null = Close-Walls $userSid $false 'closed'
        Exit-With 1 "remote administration could not be opened ($msg); every wall is shut again"
    }
    Out-Line "${Prog}: open"
    exit 0
}
catch {
    Out-Line "${Prog}: $($_.Exception.Message)"
    exit 1
}
