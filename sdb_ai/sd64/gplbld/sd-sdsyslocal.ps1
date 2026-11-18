# sd-sdsyslocal.ps1 - the Windows half of LOCAL.SDSYS: the two lists of Windows users who may reach SDSYS FROM THIS COMPUTER.
#
#   ... -List ssh|api -Action status                 one line, what the list holds now; nothing changes
#   ... -List ssh|api -Action add -Name fred         add a user (an existing local Windows account, in sdusers)
#   ... -List ssh|api -Action remove -Name fred      take a user off
#   ... -List ssh|api -Action clear                  remove the list (none listed, as delivered)
#   [-Dir <directory>] [-DryRun]                     for the unit test only (test-localsdsys-units.py); LOCALSDSYS never passes them
#
# Run by SD through !ps_script_out, from gpl.bp LOCALSDSYS and TOOL_REMOTE, as SDSYS's ELEVATED helper (the verb is the administrator's).
# Carried 18 Nov 2026 from Linux's "sd-elevate sdsys-local" (S.267, Linux 38cfb301; Windows RELEASE_1.1 339).  The rules are Linux's, with
# the Windows answers Linux gave in mail 2026-11-18T0745:
#
#   EMPTY AS DELIVERED: no file.  Removing the last name, or clear, removes the file.  At most 32 names a list.
#   THE FILES are <ProgramData>\SD\sd-tls\sdsys-local-ssh and ...\sdsys-local-api: one entry a line, "<name> <SID>", ASCII, LF.  The SID is
#   the identity (Q3): a renamed account keeps its place and the report shows the name it has now; an account deleted and made again under
#   the same name is a new SID and is not listed.  The folder is the one the installer's secure-tls.ps1 makes SYSTEM and Administrators only,
#   so a listed user cannot read the lists (Linux's are 0644: tighter here, an OS consequence).  This script never makes the folder.  Neither
#   it nor a list may be a link; a list's owner is set to Administrators; the write is a new file beside it, then File.Replace or Move.
#   A NAME MAY BE LISTED (Q4, Q5) when it is an existing LOCAL Windows account (found case-blind, stored in the account's own spelling),
#   enabled, RID 1000 or more (not a built-in account), a member of the group sdusers, and none of SDSYS, SDRADMIN, sdrunin, sdrelay.  The
#   name itself: 1 to 20 characters, none of " / \ [ ] : ; | = , + * ? < > @ or a space, no control character (Windows' own rule, and the
#   space because LOCAL.SDSYS reads the name as one word).
#   WHO READS THEM: the SD service and an elevated SDSYS session (K$SDSYS.LOCAL, win32localsdsys.c), which hold each file to the same rules
#   and treat a file that breaks any of them as an empty list.
#
# Output: Linux's lines, word for word but for "the administrators'" where Linux says "root's" -
#   "sdsys local ssh: none listed" / "sdsys local ssh: listed fred bob" /
#   "sdsys local ssh: unsafe, treated as none listed (<file> is not a plain file of the administrators'; clear removes it)" /
#   "sd-sdsyslocal: sdsys local ssh: added fred; listed now: fred" / "... removed fred; listed now: none" /
#   "... fred is listed already; nothing was changed" / "... fred is not listed; nothing was changed" / "... cleared, none listed" /
#   "... none listed already; nothing was changed" / "sd-sdsyslocal: the ssh list holds 32 names already, the most it takes: nothing was changed".
# Exit 0 done, 1 refused (a name, the count), 2 could not run (not elevated, no folder, a link, a write that failed).
#
# START-HISTORY:
# 18 Nov 26 Windows port - written for RELEASE_1.1 339 (Linux S.267).
# END-HISTORY

param(
    [ValidateSet('ssh', 'api')]
    [string]$List = 'ssh',
    [ValidateSet('add', 'remove', 'clear', 'status')]
    [string]$Action = 'status',
    [string]$Name = '',
    [string]$Dir = '',
    [switch]$DryRun
)

# Windows PowerShell's own module folders, as gpl.bp/ps_scripto sets them (RELEASE_1.1 111): Get-LocalUser and Get-LocalGroupMember.
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"

$ErrorActionPreference = 'Stop'
$Prog = 'sd-sdsyslocal'

# Straight to the process's standard output, not the pipeline (the PowerShell function output trap; sd-sdsysapi.ps1's Say).
function Say([string]$t) { [Console]::Out.WriteLine($t) }
function Refuse([string]$t) { Say ("${Prog}: " + $t + '; nothing was changed'); exit 1 }
function Fail([string]$t) { Say ("${Prog}: " + $t); exit 2 }

# BEGIN pure - no file, no account, no exit: test-localsdsys-units.py lifts this block and runs it on fixtures.

$SdLocalMax = 32
$SdLocalNever = @('sdsys', 'sdradmin', 'sdrunin', 'sdrelay', 'system', 'administrator', 'guest', 'defaultaccount', 'wdagutilityaccount')

# '' when N may be a name in a list, else why not (the words after "'N' is not a Windows user name").
function Test-SdLocalName([string]$n) {
    if ($n.Length -lt 1 -or $n.Length -gt 20) { return 'it must be 1 to 20 characters' }
    foreach ($c in $n.ToCharArray()) {
        if ([int]$c -lt 32 -or [int]$c -eq 127) { return 'it holds a control character' }
        if ('"/\[]:;|=,+*?<>@ '.IndexOf($c) -ge 0) { return ('it holds the character ' + $c) }
    }
    if ($n.Trim('.') -eq '') { return 'it is only dots' }
    return ''
}

# A list file's text as entries (@{Name; Sid}), or $null when it breaks a rule: not ASCII printable plus LF/CR, a line that is not
# "<name> <SID>", a SID that is not a local account's form, a SID twice, more than 32 lines.  An empty text is an empty list.
function Read-SdLocalText([string]$text) {
    $out = @()
    if ($null -eq $text) { return , $out }
    foreach ($c in $text.ToCharArray()) {
        $v = [int]$c
        if (($v -lt 32 -and $v -ne 10 -and $v -ne 13) -or $v -gt 126) { return $null }
    }
    $seen = @{}
    foreach ($ln in ($text -split "`n")) {
        $l = $ln.TrimEnd("`r")
        if ($l -eq '') { continue }
        $m = [regex]::Match($l, '^(\S+) (S-1-5-21-[0-9]+-[0-9]+-[0-9]+-[0-9]+)$')
        if (-not $m.Success) { return $null }
        if ((Test-SdLocalName $m.Groups[1].Value) -ne '') { return $null }
        $sid = $m.Groups[2].Value
        if ($seen.ContainsKey($sid)) { return $null }
        $seen[$sid] = $true
        $out += , @{ Name = $m.Groups[1].Value; Sid = $sid }
    }
    if ($out.Count -gt $SdLocalMax) { return $null }
    return , $out
}

function Format-SdLocalText($entries) {
    $t = ''
    foreach ($e in $entries) { $t += ($e.Name + ' ' + $e.Sid + "`n") }
    return $t
}

# The change: ENTRIES (as read), WHAT add|remove, ACCT @{Name; Sid} for add (already checked) or NAME for remove.  Returns
# @{ Kind = 'changed'|'same'|'refused'; Entries; Line } - Line is what is said (without the "sd-sdsyslocal: " head for 'refused').
function Get-SdLocalChange($entries, [string]$kind, [string]$what, $acct, [string]$name) {
    $keep = @()
    $found = $null
    foreach ($e in $entries) {
        $hit = $false
        if ($what -eq 'add') { $hit = ($e.Sid -eq $acct.Sid) }
        else { $hit = ($e.Name -ieq $name) -or ($null -ne $acct -and $e.Sid -eq $acct.Sid) }
        if ($hit) { $found = $e } else { $keep += , $e }
    }
    if ($what -eq 'add') {
        if ($null -ne $found) {
            return @{ Kind = 'same'; Entries = $entries; Line = ("sdsys local ${kind}: " + $acct.Name + ' is listed already; nothing was changed') }
        }
        if ($keep.Count -ge $SdLocalMax) {
            return @{ Kind = 'refused'; Entries = $entries; Line = ("the $kind list holds $SdLocalMax names already, the most it takes") }
        }
        $keep += , @{ Name = $acct.Name; Sid = $acct.Sid }
        $shown = $acct.Name
        $done = 'added'
    } else {
        if ($null -eq $found) {
            return @{ Kind = 'same'; Entries = $entries; Line = ("sdsys local ${kind}: $name is not listed; nothing was changed") }
        }
        $shown = $found.Name
        $done = 'removed'
    }
    $now = 'none'
    if ($keep.Count -gt 0) { $now = (@($keep | ForEach-Object { $_.Name }) -join ' ') }
    return @{ Kind = 'changed'; Entries = $keep; Line = ("sdsys local ${kind}: $done $shown; listed now: $now") }
}

# END pure

# ---------------------------------------------------------------- the place

if ($Dir -ne '') {
    $SetDir = $Dir
} else {
    $SetDir = Join-Path (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD') 'sd-tls'
    if (-not $DryRun) {
        $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Fail 'this needs an elevated administrator (SDSYS at its console); nothing was changed'
        }
    }
}
$SetFile = Join-Path $SetDir ('sdsys-local-' + $List)
$AdminsSid = 'S-1-5-32-544'
$SystemSid = 'S-1-5-18'

function Assert-Place {
    if (-not (Test-Path -LiteralPath $SetDir -PathType Container)) {
        Fail ("$SetDir is missing; the installer makes it (secure-tls.ps1).  Nothing was changed")
    }
    if ((Get-Item -LiteralPath $SetDir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Fail ("$SetDir is a link: refused.  Nothing was changed")
    }
}

# The list as entries, or $null when the file is there and breaks a rule (a link, not a file, an owner other than SYSTEM or Administrators,
# a grant to anyone else, 8 KB or more, or its text).  Absent: an empty list.  -Dir (the unit test) skips the owner and the grants.
function Read-SdLocalFile {
    if (-not (Test-Path -LiteralPath $SetFile)) { return , @() }
    $it = Get-Item -LiteralPath $SetFile -Force
    if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $null }
    if ($it.PSIsContainer) { return $null }
    if ($it.Length -ge 8192) { return $null }
    if ($Dir -eq '') {
        $acl = Get-Acl -LiteralPath $SetFile
        $owner = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value
        if ($owner -ne $AdminsSid -and $owner -ne $SystemSid) { return $null }
        foreach ($r in $acl.Access) {
            if ($r.AccessControlType -ne 'Allow') { continue }
            $who = $r.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            if ($who -ne $AdminsSid -and $who -ne $SystemSid) { return $null }
        }
    }
    try { $text = [IO.File]::ReadAllText($SetFile, [Text.Encoding]::GetEncoding(28591)) } catch { return $null }
    # Taken into a variable and wrapped again: returned straight through, a one-entry list would unroll into its hashtable.
    $parsed = Read-SdLocalText $text
    if ($null -eq $parsed) { return $null }
    return , @($parsed)
}

# The name a SID has now ('' when it has none); the report shows it (Q3).
function Get-NameNow([string]$sid) {
    try {
        $acc = (New-Object Security.Principal.SecurityIdentifier($sid)).Translate([Security.Principal.NTAccount]).Value
        return ($acc -split '\\')[-1]
    } catch { return '' }
}

# The account a name may be listed as: @{Name; Sid}, or a refusal (exit 1).
function Get-ListableAccount([string]$n) {
    $why = Test-SdLocalName $n
    if ($why -ne '') { Refuse ("'$n' is not a Windows user name ($why)") }
    if ($SdLocalNever -contains $n.ToLowerInvariant()) {
        if ($n -ieq 'sdsys') { Refuse 'SDSYS is the administrator itself and is never listed' }
        Refuse ("$n is an account of SD's or of Windows' own and is never listed")
    }
    $u = Get-LocalUser -Name $n -ErrorAction SilentlyContinue
    if ($null -eq $u) { Refuse ("there is no local Windows user '$n'") }
    $sid = $u.SID.Value
    if ($sid -notmatch '^S-1-5-21-[0-9]+-[0-9]+-[0-9]+-([0-9]+)$') { Refuse ("'" + $u.Name + "' is not a local account of this computer") }
    $rid = [int64]$Matches[1]
    if ($rid -lt 1000) { Refuse ("'" + $u.Name + "' is a built-in account (RID $rid, below 1000)") }
    if (-not $u.Enabled) { Refuse ("'" + $u.Name + "' is disabled") }
    $g = Get-LocalGroup -Name 'sdusers' -ErrorAction SilentlyContinue
    if ($null -eq $g) { Fail 'the group sdusers is missing; nothing was changed' }
    $in = $false
    try {
        foreach ($m in @(Get-LocalGroupMember -SID $g.SID.Value -ErrorAction Stop)) {
            if ($null -ne $m.SID -and $m.SID.Value -eq $sid) { $in = $true; break }
        }
    } catch { Fail ('cannot list the group sdusers: ' + $_.Exception.Message + '; nothing was changed') }
    if (-not $in) { Refuse ("'" + $u.Name + "' is not in the group sdusers, so it is not an SD user") }
    return @{ Name = $u.Name; Sid = $sid }
}

function Write-SdLocalFile($entries) {
    if ($entries.Count -eq 0) {
        try { if (Test-Path -LiteralPath $SetFile) { Remove-Item -LiteralPath $SetFile -Force } }
        catch { Fail ("could not remove ${SetFile}: " + $_.Exception.Message + '.  Nothing was changed') }
        return
    }
    $tmp = Join-Path $SetDir ('.sdsys-local.' + [Guid]::NewGuid().ToString('N'))
    try {
        $bytes = [Text.Encoding]::ASCII.GetBytes((Format-SdLocalText $entries))
        $fs = New-Object IO.FileStream($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Close() }
        if ($Dir -eq '') {
            $acl = Get-Acl -LiteralPath $tmp
            $acl.SetOwner((New-Object Security.Principal.SecurityIdentifier($AdminsSid)))
            Set-Acl -LiteralPath $tmp -AclObject $acl
        }
        if (Test-Path -LiteralPath $SetFile) {
            [IO.File]::Replace($tmp, $SetFile, [NullString]::Value)
        } else {
            [IO.File]::Move($tmp, $SetFile)
        }
    } catch {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        Fail ("could not write ${SetFile}: " + $_.Exception.Message + '.  Nothing was changed')
    }
}

# ---------------------------------------------------------------- the actions

if ($Action -eq 'status' -or $Action -eq 'clear') {
    if ($Name -ne '') { Refuse ("sdsys-local $List $Action takes no name") }
} elseif ($Name -eq '') {
    Refuse ("sdsys-local $List $Action needs a user name")
}

if ($DryRun -and $Dir -eq '') { Say ("${Prog}: would $Action the $List list in $SetFile"); exit 0 }
Assert-Place

switch ($Action) {
    'status' {
        $entries = Read-SdLocalFile
        if ($null -eq $entries) {
            Say ("sdsys local ${List}: unsafe, treated as none listed ($SetFile is not a plain file of the administrators'; clear removes it)")
        } elseif ($entries.Count -eq 0) {
            Say ("sdsys local ${List}: none listed")
        } else {
            $names = @()
            foreach ($e in $entries) {
                $now = $e.Name
                if ($Dir -eq '') { $now = Get-NameNow $e.Sid; if ($now -eq '') { $now = $e.Name + '(no-such-account)' } }
                $names += $now
            }
            Say ("sdsys local ${List}: listed " + ($names -join ' '))
        }
        exit 0
    }
    'clear' {
        if (-not (Test-Path -LiteralPath $SetFile)) { Say ("${Prog}: sdsys local ${List}: none listed already; nothing was changed"); exit 0 }
        try { Remove-Item -LiteralPath $SetFile -Force } catch { Fail ("could not remove ${SetFile}: " + $_.Exception.Message) }
        Say ("${Prog}: sdsys local ${List}: cleared, none listed")
        exit 0
    }
    default {
        if ((Test-Path -LiteralPath $SetFile) -and ((Get-Item -LiteralPath $SetFile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            Fail ("$SetFile is a link: refused, nothing was changed (clear removes it)")
        }
        $entries = Read-SdLocalFile
        if ($null -eq $entries) { Fail ("$SetFile is not a plain file of the administrators': nothing was changed (clear removes the file)") }
        $acct = $null
        if ($Action -eq 'add') {
            if ($Dir -ne '') {
                # The unit test: the account is a fixture, "name=SID" in -Name, already listable.
                $p = $Name.Split('=')
                $acct = @{ Name = $p[0]; Sid = $p[1] }
                $why = Test-SdLocalName $acct.Name
                if ($why -ne '') { Refuse ("'" + $acct.Name + "' is not a Windows user name ($why)") }
            } else {
                $acct = Get-ListableAccount $Name
            }
        } else {
            $why = Test-SdLocalName $Name
            if ($why -ne '') { Refuse ("'$Name' is not a Windows user name ($why)") }
            if ($Dir -eq '') {
                $u = Get-LocalUser -Name $Name -ErrorAction SilentlyContinue
                if ($null -ne $u) { $acct = @{ Name = $u.Name; Sid = $u.SID.Value } }
            }
        }
        $r = Get-SdLocalChange $entries $List $Action $acct $Name
        if ($r.Kind -eq 'refused') { Refuse $r.Line }
        if ($r.Kind -eq 'changed') { Write-SdLocalFile $r.Entries }
        Say ("${Prog}: " + $r.Line)
        exit 0
    }
}
