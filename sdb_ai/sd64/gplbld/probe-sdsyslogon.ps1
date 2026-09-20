<#
.SYNOPSIS
    WHY CAN THE SDSYS ACCOUNT NOT SIGN IN AT THE CONSOLE?  RELEASE_1.1 78.

.DESCRIPTION
    ***THIS STOPPED BEING A TEST-RIG QUESTION THE MOMENT IT WAS MEASURED.***
    RELEASE_1.1 64 made the Windows SDSYS account the ONLY administrator SD
    has, and PROJECT_STATUS.md 5.25 rules that administration happens at the
    console, in a session where UAC can render.  So if SDSYS cannot sign in
    interactively, this product cannot be administered on this machine at all
    except through the install's own "sd -internal" door - and that door is
    gated on K$INTERNAL, not available to a person.

    WHAT IS ALREADY MEASURED, 19 Sep 2026, and it is why this file exists:

      - the owner switched user to SDSYS SEVERAL TIMES.  Each attempt appeared
        to accept the password and begin entering, then terminated and returned
        him to his own session with no desktop ever shown.
      - "net user SDSYS" reads Account active YES, no logon script, no user
        profile path, no home directory, Workstations allowed All, Logon hours
        All.  Nothing in the account object forbids it.
      - SDSYS is in sdusers and Administrators, and NOT in sdsshonly - which is
        the only group the installer gives the deny rights to (sd.iss:2331,
        deny-logon.ps1).  The owner's own account is in sdusers too and signs
        in fine, so sdusers cannot be carrying a deny right.
      - C:\Users\SDSYS EXISTS and its ProfileList entry is present and points at
        it.  No .bak entry, so this is not the classic corrupt-profile case.
      - ***AND THE PROFILE SERVICE LOGGED NOTHING FOR ANY OF THE ATTEMPTS.***
        Its Operational log's last entry is 18:15:43, which matches a PROBE
        SPAWN, and there are 0 entries after 19:05 while the attempts happened
        at 19:10-19:14.  So the session ends BEFORE a profile is loaded.
      - "Last logon" on the account reads 19:00:56, which is also a probe spawn
        (probe-sdsysseat-20260919-190055.log), NOT an interactive sign-in.  A
        LogonUser/batch logon as SDSYS works; the console one does not.

    WHAT IS NOT MEASURED IS THE CAUSE, and every remaining candidate needs an
    ELEVATED read: the Security log's 4624/4625 rows with their Status and
    SubStatus, the local user-rights assignment, and the ACL on the profile
    directory.  That is all this script does - it READS.  It changes nothing,
    creates nothing and signs nobody in.

    ***IT REFUSES THE NULL CASE.***  If the Security log holds no logon row for
    the account inside the window, it says so and stops rather than concluding
    from an empty set - "nothing was attempted" and "the attempt was refused"
    are different answers.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\probe-sdsyslogon.ps1

    ELEVATED PowerShell.  Run it AFTER a failed sign-in attempt, so the window
    below covers it.  No password is asked for.
#>

[CmdletBinding()]
param(
    [string] $Account = 'SDSYS',
    # How far back to read the Security log.  The attempt must be inside it.
    [int]    $Minutes = 60
)

$ErrorActionPreference = 'Stop'
function Say([string]$t)  { Write-Output ('  ' + $t) }
function Head([string]$t) { Write-Output ''; Write-Output ('== ' + $t) }

Write-Output 'probe-sdsyslogon: RELEASE_1.1 78 - why does the console sign-in end before the desktop?'
Write-Output ('  script  : ' + $PSCommandPath)
Write-Output ('  account : ' + $Account)
Write-Output ('  window  : the last ' + $Minutes + ' minutes')

$pr = New-Object Security.Principal.WindowsPrincipal(
          [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'probe-sdsyslogon: this needs an ELEVATED PowerShell - the Security log, the'
    Write-Output '  user-rights assignment and the profile ACL are all elevated reads.'
    exit 2
}

$u = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
if ($null -eq $u) { Write-Output ("probe-sdsyslogon: there is no local {0} account." -f $Account); exit 2 }
$sid = $u.SID.Value
Say ('SID     : ' + $sid)

# --------------------------------------------------------------- user rights
Head 'the local user-rights assignment - who is DENIED an interactive logon'

# secedit is the only built-in route to the rights database; deny-logon.ps1's
# own header says so.  Export, read, and resolve every SID to a name, because
# "S-1-5-21-...-2545" tells a reader nothing.
$cfg = Join-Path $env:TEMP ('sdrights-' + [Guid]::NewGuid().ToString('N').Substring(0,8) + '.inf')
$log = [System.IO.Path]::ChangeExtension($cfg, '.log')
& "$env:SystemRoot\System32\secedit.exe" /export /areas USER_RIGHTS /cfg $cfg /log $log /quiet | Out-Null
if (-not (Test-Path -LiteralPath $cfg)) {
    Say 'secedit wrote no export - the rights could not be read, so nothing here is measured'
} else {
    $wanted = @('SeDenyInteractiveLogonRight', 'SeInteractiveLogonRight',
                'SeDenyRemoteInteractiveLogonRight', 'SeDenyBatchLogonRight',
                'SeBatchLogonRight')
    $lines = Get-Content -LiteralPath $cfg -Encoding Unicode
    $seen = 0
    foreach ($w in $wanted) {
        $row = $lines | Where-Object { $_ -match ('^\s*' + $w + '\s*=') }
        if ($null -eq $row) { Say ("{0,-34} (not assigned to anybody)" -f $w); continue }
        $seen++
        $vals = ($row -split '=', 2)[1].Trim() -split ','
        $names = foreach ($v in $vals) {
            $v = $v.Trim()
            $n = $v
            try {
                if ($v.StartsWith('*')) {
                    $n = (New-Object Security.Principal.SecurityIdentifier($v.Substring(1))
                          ).Translate([Security.Principal.NTAccount]).Value + '  [' + $v.Substring(1) + ']'
                }
            } catch { $n = $v + '  [unresolvable]' }
            $n
        }
        Say ("{0,-34} {1}" -f $w, ($names -join ' ; '))
    }
    if ($seen -eq 0) { Say 'REFUSED: not one of these rights was found in the export - the parse is blind' }
    Remove-Item -LiteralPath $cfg -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $log -ErrorAction SilentlyContinue
}

# ------------------------------------------------------------------- profile
Head 'the profile directory this account would load'

$dir = Join-Path $env:SystemDrive ('Users\' + $Account)
Say ('path    : ' + $dir + '   exists=' + (Test-Path -LiteralPath $dir))
if (Test-Path -LiteralPath $dir) {
    try {
        $acl = Get-Acl -LiteralPath $dir
        Say ('owner   : ' + $acl.Owner)
        foreach ($r in $acl.Access) {
            Say ('  {0,-45} {1,-20} {2}' -f $r.IdentityReference, $r.FileSystemRights, $r.AccessControlType)
        }
        $mine = $acl.Access | Where-Object { $_.IdentityReference -match ([regex]::Escape($Account) + '$') }
        Say ('THE ROW THAT MATTERS: does ' + $Account + ' itself appear? ' + [bool]$mine)
    } catch {
        Say ('the ACL could not be read even elevated: ' + $_.Exception.Message)
    }
}

# -------------------------------------------------------------- security log
Head ('what the Security log says about ' + $Account + "'s logons")

$since = (Get-Date).AddMinutes(-$Minutes)
$rows = @()
try {
    $rows = Get-WinEvent -FilterHashtable @{ LogName = 'Security'; StartTime = $since
                                             Id = 4624, 4625, 4634, 4647, 4648 } -ErrorAction Stop |
            Where-Object { $_.Message -match ([regex]::Escape($Account)) }
} catch {
    Say ('the Security log could not be read: ' + $_.Exception.Message)
}

if ($rows.Count -eq 0) {
    Say ("NO logon row for {0} in the last {1} minutes." -f $Account, $Minutes)
    Say 'REFUSED: "nothing was attempted" and "the attempt was refused" are different'
    Say 'answers, and an empty set cannot tell them apart.  Switch user, try the'
    Say 'sign-in, come back and run this again - or raise -Minutes to cover it.'
    Write-Output ''
    Write-Output 'probe-sdsyslogon: nothing measured'
    exit 2
}

Say ("{0} row(s) in the window" -f $rows.Count)
foreach ($r in ($rows | Sort-Object TimeCreated)) {
    $type = ''
    if ($r.Message -match '(?m)^\s*Logon Type:\s*(\d+)')  { $type = 'type ' + $Matches[1] }
    $status = ''
    if ($r.Message -match '(?m)^\s*Status:\s*(\S+)')      { $status = ' status ' + $Matches[1] }
    if ($r.Message -match '(?m)^\s*Sub Status:\s*(\S+)')  { $status += ' sub ' + $Matches[1] }
    $what = switch ($r.Id) {
        4624 { 'LOGON OK' } 4625 { 'LOGON FAILED' } 4634 { 'logoff' }
        4647 { 'user-initiated logoff' } 4648 { 'explicit-credential logon' }
        default { 'id ' + $r.Id }
    }
    Write-Output ('  {0:HH:mm:ss}  {1,-26} {2}{3}' -f $r.TimeCreated, $what, $type, $status)
}

Write-Output ''
Write-Output 'READ IT LIKE THIS.  A 4625 names the refusal in its Status/Sub Status'
Write-Output '  (0xC000006D with sub 0xC0000064 is a bad user name, 0xC000006A a bad'
Write-Output '  password, 0xC0000413 a deny right, 0xC000015B "the user has not been'
Write-Output '  granted the requested logon type").  A 4624 of TYPE 2 or 11 followed'
Write-Output '  seconds later by a 4634 is the shape the owner described: admitted,'
Write-Output '  then the session ended before a desktop - and that points at the shell'
Write-Output '  or the profile rather than at the credential.'
Write-Output ''
Write-Output 'probe-sdsyslogon: read the rows above; this script concludes nothing on its own.'
exit 0
