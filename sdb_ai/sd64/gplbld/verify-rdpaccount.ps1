<#
.SYNOPSIS
    RDPACCOUNT: does an account created with the keyword actually get a Windows
    sign-in, does a plain one still not, and can MODIFY.ACCOUNT move an account
    between the two?  PROJECT_STATUS.md section 8.

.DESCRIPTION
    THE MEASUREMENT IS A LOGON, NOT A GROUP LISTING.  Membership of sdsshonly
    is the mechanism, but what matters is whether Windows lets the account sign
    in interactively - so every check here calls LogonUser with
    LOGON32_LOGON_INTERACTIVE and reads the result.  A test that only looked at
    the group would pass just as happily if deny-logon.ps1 had never run.

      admitted      the account may sign in at a console or over Remote Desktop
      refused 1385  ERROR_LOGON_TYPE_NOT_GRANTED - the deny right applies

    ITS CONTROL IS A PLAIN ACCOUNT MADE IN THE SAME RUN.  "RDPACCOUNT can log
    on" means nothing on a machine where everybody can; the control is an
    account created without the keyword, which must be REFUSED, and it is
    created seconds apart from the first on the same install.

    THE ADMINISTRATOR GUARD IS THE CHECK WORTH HAVING.  sdsshonly carries
    SeDenyInteractiveLogonRight and SeDenyRemoteInteractiveLogonRight, so
    MODIFY.ACCOUNT ... NO.RDPACCOUNT run against an administrator's account
    would lock that administrator out of their own console - which is exactly
    what happened on 15 Aug 2026 the first time ADOPT ran, and why CREATEA
    carries the rule that no administrator is ever confined to ssh.
    MODIFY.ACCOUNT is the route CREATEA's comment predicted would arrive.

    IT IS TESTED ON A THROWAWAY ADMINISTRATOR, NEVER ON DON.  If the guard is
    broken the account under test is locked out, and this script must not be
    able to do that to the owner's own account.  The throwaway is removed in a
    finally, and the finally ALSO takes it out of sdsshonly first in case the
    guard let it through - a locked-out account that is then deleted leaves no
    evidence of which of the two failed.

.PARAMETER Prefix
    Stem for the three throwaway accounts: <prefix>r (RDPACCOUNT), <prefix>s
    (plain, the control) and <prefix>a (administrator).  Use a stem nobody has
    used - CREATE.ACCOUNT refuses a name it has seen.

.PARAMETER Keep
    Leave the accounts behind for poking at.  They still need DELETE.ACCOUNT.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-rdpaccount.ps1 -Prefix sdrdp1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-rdpaccount-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results = New-Object System.Collections.ArrayList
$failed  = $false

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
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# The installed sysmsg(N) as a REGEX, with each %1/%2 replaced by ".*" and
# every literal run escaped.  Read from the install rather than hard-coded, so
# a reworded message fails the check that names it instead of going blind.
#
# 20 Aug 26 - IT USED TO TAKE THE TEXT BEFORE THE FIRST "%" AND THAT MEASURED
# NOTHING.  Every message this script asserts STARTS with %1 - "%1 may sign in
# over ssh only" - so the head was the empty string, the "is it installed"
# guard beside it fired, and all six message checks reported FAIL on a run
# where the feature worked perfectly.  12 of 18, first run, 20 Aug 2026.
#
# THE ACCIDENTAL CONTROL IS WHAT MADE IT OBVIOUS: 10034 failed too, and 10034
# is an EXISTING message printed by a path RDPACCOUNT never touched.  A new
# feature cannot break an old message it does not go near, so the fault had to
# be in the checking.  Six failures with one of them impossible is worth more
# than six plausible ones.
#
# verify-accountacl.ps1 carried the same function and did NOT expose it, because
# the one message it reads - 10055, "Could not secure account directory %1" -
# happens to begin with literal text.  Fixed there too rather than left as a
# working accident.
function Get-SysMsgPattern([int]$n) {
    $f = Join-Path $env:ProgramData ('SD\sdsys\messages\' + $n)
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $t = ((Get-Content -LiteralPath $f -Raw)).Trim()
    if ($t -eq '') { return '' }
    $parts = [regex]::Split($t, '%\d')
    return (($parts | ForEach-Object { [regex]::Escape($_) }) -join '.*')
}

# Blank first line absorbs the pipe's BOM, TERM stops pagination, OFF ends it.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

$logonSig = @'
using System;
using System.Runtime.InteropServices;
public class SdRdpLogon {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out IntPtr token);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr handle);
    public static int Try(string user, string pass, int logonType) {
        IntPtr token = IntPtr.Zero;
        bool ok = LogonUser(user, ".", pass, logonType, 0, out token);
        if (!ok) return Marshal.GetLastWin32Error();
        CloseHandle(token);
        return 0;
    }
}
'@

# LOGON32_LOGON_INTERACTIVE = 2.  This is the console/RDP logon right, which is
# what sdsshonly's deny applies to.  1385 is ERROR_LOGON_TYPE_NOT_GRANTED.
function InteractiveLogon($user, $pass) {
    $rc = [SdRdpLogon]::Try($user, $pass, 2)
    if ($rc -eq 0) { return 'admitted' }
    if ($rc -eq 1385) { return 'refused 1385' }
    return ("refused " + $rc)
}

function In-SshOnly($user) {
    $m = Get-LocalGroupMember -Group 'sdsshonly' -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like ("*\" + $user) }
    return [bool]$m
}

# ---------------------------------------------------------------------------
if (-not $Prefix) {
    Write-Host 'verify-rdpaccount: -Prefix is required, and must be a stem nobody has used.'
    Write-Host '  Example: -Prefix sdrdp1'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
if ($Prefix -notmatch '^[a-z][a-z0-9_]*$') {
    Fail ("-Prefix is '$Prefix'.  Lower case letters, digits and underscore only, " +
          'starting with a letter - CREATEA downcases the name and the Windows ' +
          'account takes it verbatim.')
}

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'this needs an ELEVATED PowerShell - CREATE_USER needs an elevated token.'
}

& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'the installed tree does not match source - see above' }

if (-not (Test-Path -LiteralPath $sdExe)) { Fail "no $sdExe" }
if (-not (Get-LocalGroup -Name 'sdsshonly' -ErrorAction SilentlyContinue)) {
    Fail 'the sdsshonly group does not exist - it is the whole subject of this test.'
}

$rdpAcc = $Prefix + 'r'    # created WITH the keyword
$stdAcc = $Prefix + 's'    # created without it - the control
$admAcc = $Prefix + 'a'    # administrator, for the lockout guard
$made   = @()

foreach ($a in @($rdpAcc, $stdAcc, $admAcc)) {
    if (Get-LocalUser -Name $a -ErrorAction SilentlyContinue) {
        Fail "$a already exists as a Windows account - use a fresh -Prefix."
    }
    if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $a.ToUpper()))) {
        Fail ($a.ToUpper() + ' is still in the ACCOUNTS register - use a fresh -Prefix.')
    }
}

Add-Type -TypeDefinition $logonSig -Language CSharp | Out-Null
Add-Type -AssemblyName System.Web

function New-Acct($name, $extra) {
    $pw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $cmd = "CREATE.ACCOUNT USER $name"
    if ($extra -ne '') { $cmd += " $extra" }
    $out = Invoke-SD @($cmd, $pw, $pw)
    $rec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $name.ToUpper())
    if (-not (Test-Path -LiteralPath $rec)) { Write-Host $out; Fail "CREATE.ACCOUNT did not register $name" }
    $script:made += $name
    return @{ Password = $pw; Out = $out }
}

try {
    # -----------------------------------------------------------------------
    Step 1 "CREATE.ACCOUNT USER $rdpAcc RDPACCOUNT"

    $r = New-Acct $rdpAcc 'RDPACCOUNT'
    $m10056 = Get-SysMsgPattern 10056
    Note 'message 10056 shown' $true ($m10056 -ne '' -and $r.Out -match $m10056)
    Note 'NOT in sdsshonly'    $false (In-SshOnly $rdpAcc)
    Note 'may sign in to Windows' 'admitted' (InteractiveLogon $rdpAcc $r.Password)

    # -----------------------------------------------------------------------
    Step 2 "THE CONTROL: CREATE.ACCOUNT USER $stdAcc, no keyword"

    # Without this, "RDPACCOUNT can log on" would pass on a machine where the
    # deny right was never applied to anybody.
    $s = New-Acct $stdAcc ''
    $m10034 = Get-SysMsgPattern 10034
    Note 'message 10034 shown' $true ($m10034 -ne '' -and $s.Out -match $m10034)
    Note 'IS in sdsshonly'     $true  (In-SshOnly $stdAcc)
    Note 'may NOT sign in'     'refused 1385' (InteractiveLogon $stdAcc $s.Password)

    # -----------------------------------------------------------------------
    Step 3 "MODIFY.ACCOUNT $stdAcc RDPACCOUNT - release it"

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc RDPACCOUNT")
    $m10057 = Get-SysMsgPattern 10057
    Note 'message 10057 shown' $true ($m10057 -ne '' -and $out -match $m10057)
    Note 'no longer in sdsshonly' $false (In-SshOnly $stdAcc)
    Note 'now may sign in'     'admitted' (InteractiveLogon $stdAcc $s.Password)

    # Idempotence, and it must SAY so rather than silently succeed.
    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc RDPACCOUNT")
    $m10059 = Get-SysMsgPattern 10059
    Note 'second RDPACCOUNT says already' $true ($m10059 -ne '' -and $out -match $m10059)

    # -----------------------------------------------------------------------
    Step 4 "MODIFY.ACCOUNT $stdAcc NO.RDPACCOUNT - confine it again"

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc NO.RDPACCOUNT")
    $m10058 = Get-SysMsgPattern 10058
    Note 'message 10058 shown' $true ($m10058 -ne '' -and $out -match $m10058)
    Note 'back in sdsshonly'   $true  (In-SshOnly $stdAcc)
    Note 'refused again'       'refused 1385' (InteractiveLogon $stdAcc $s.Password)

    # -----------------------------------------------------------------------
    Step 5 "THE LOCKOUT GUARD: NO.RDPACCOUNT against an ADMINISTRATOR"

    # CREATEA's rule since 15 Aug: no administrator is ever confined to ssh,
    # "whatever route reaches this line".  MODIFY.ACCOUNT is that route.
    $a = New-Acct $admAcc 'ADMINISTRATOR'
    Note 'admin account is an Administrator' $true ([bool](
        Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like ("*\" + $admAcc) }))
    Note 'admin NOT in sdsshonly to start' $false (In-SshOnly $admAcc)

    $out = Invoke-SD @("MODIFY.ACCOUNT $admAcc NO.RDPACCOUNT")
    $m10061 = Get-SysMsgPattern 10061
    Note 'refused with message 10061' $true ($m10061 -ne '' -and $out -match $m10061)
    # THE ONE THAT MATTERS: the refusal must have refused, not merely reported.
    Note 'admin STILL not in sdsshonly' $false (In-SshOnly $admAcc)
    Note 'admin can still sign in'      'admitted' (InteractiveLogon $admAcc $a.Password)
}
catch {
    $script:failed = $true
    Write-Host ''
    Write-Host ('verify-rdpaccount: THREW - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $null = $results.Add([pscustomobject]@{
        Check = 'the run completed without throwing'; Expected = $true; Observed = $false })
}
finally {
    if (-not $Keep) {
        Step 6 'Putting the system back'

        foreach ($a in $made) {
            # OUT OF sdsshonly FIRST, AND UNCONDITIONALLY.  If the step 5 guard
            # had failed, the administrator account would be locked out of its
            # own console; deleting it in that state destroys the evidence of
            # which half broke, and leaves nothing to inspect.  Removing the
            # membership before the account costs nothing when the guard held.
            if (In-SshOnly $a) {
                try { Remove-LocalGroupMember -Group 'sdsshonly' -Member $a -ErrorAction Stop
                      Write-Host "   took $a out of sdsshonly" } catch { }
            }
            if (Get-LocalUser -Name $a -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name $a
                Write-Host "   removed Windows account $a"
            }
            $d = Join-Path $env:ProgramData ('SD\user_accounts\' + $a)
            if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
            $g = 'sdu_' + $a
            if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $g }
            $prof = Join-Path $env:SystemDrive ('Users\' + $a)
            if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Write-Host '   ACCOUNTS records left in place - remove with DELETE.ACCOUNT'
    } else {
        Write-Host ''
        Write-Host ("-Keep: " + ($made -join ', ') + " are still there.") -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host

$passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("$passed/" + @($results).Count + ' checks passed')

if ($failed) {
    Write-Host ''
    Write-Host 'verify-rdpaccount: FAILED' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

Write-Host ''
Write-Host 'verify-rdpaccount: RDPACCOUNT admits, the default refuses, and an administrator cannot be confined.' -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
