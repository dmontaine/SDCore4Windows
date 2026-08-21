<#
.SYNOPSIS
    The two remote routes: is a new account confined to ssh and refused the API,
    can each be withdrawn and restored independently, and is RDPACCOUNT gone?

.DESCRIPTION
    Owner's rule, 21 Aug 2026: NOBODY SD CREATES REACHES THE KEYBOARD UNLESS
    THEY ARE AN ADMINISTRATOR, and the two routes that remain - ssh and the API
    - are settable per account.  This measures all three halves of that.

    THE KEYBOARD CHECK IS A LOGON, NOT A GROUP LISTING.  Membership of
    sdsshonly is the mechanism, but what matters is whether Windows lets the
    account sign in interactively, so it calls LogonUser with
    LOGON32_LOGON_INTERACTIVE and reads the result.  A test that only read the
    group would pass just as happily on a machine where deny-logon.ps1 had
    never run.

      admitted      the account may sign in at a console or over Remote Desktop
      refused 1385  ERROR_LOGON_TYPE_NOT_GRANTED - the deny right applies

    ITS CONTROL IS AN ADMINISTRATOR ACCOUNT MADE IN THE SAME RUN.  "the standard
    account is refused" means nothing on a machine where everybody is refused -
    a broken LogonUser call, a wrong password, a disabled account all read the
    same way.  The administrator must be ADMITTED, seconds apart, on the same
    install.

    AND THE INVARIANT IS RE-CHECKED AFTER EVERY ssh AND API CHANGE.  That is
    the whole point of deleting RDPACCOUNT: no verb in MODIFY.ACCOUNT may put
    an account back at the keyboard.  Asserting it once at creation would not
    catch a route verb that quietly touched sdsshonly.

    WHAT THIS DOES NOT DO: it never opens an API connection, so it proves that
    sdapi membership is SET correctly and not that APISRVR REFUSES a session
    without it.  That assertion lives in verify-apiadmin.ps1, which builds a
    real SCRAM login and now checks both answers.  The two together cover the
    control; either alone does not.

.PARAMETER Prefix
    Stem for the throwaway accounts: <prefix>s (standard) and <prefix>a
    (administrator, the control).  Use a stem nobody has used - CREATE.ACCOUNT
    refuses a name it has seen.  A third name, <prefix>x, is offered to
    CREATE.ACCOUNT with the dead RDPACCOUNT keyword and must NOT be created.

.PARAMETER Keep
    Leave the accounts behind for poking at.  They still need DELETE.ACCOUNT.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-routes.ps1 -Prefix sdrt1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

# 21 Aug 26 - SUPERSEDED BY PHASE 2 AND REFUSES RATHER THAN FAILING OBSCURELY.
#
# This script asserts the SSH / NO.SSH / API / NO.API keyword pairs and the
# eight messages 10063-10071 that went with them.  Owner's decision of 21 Aug
# 2026 replaced all of it with SSH | API | BOTH | NONE and messages
# 10076-10081, so those eight message files no longer exist - and Shown()
# answers $false for a message it cannot read, which would score this run as
# eight failures that look like a broken feature.
#
# REFUSING IS THE HONEST ANSWER while the rewrite is outstanding.  A verifier
# that cannot pass is not evidence of anything, and this project has paid five
# times for checks that could not fail; one that CANNOT SUCCEED is the same
# fault from the other side.  Phase 4 rewrites it for the four keywords.
$retired = @(10063, 10064, 10065, 10066, 10067, 10068, 10069, 10070, 10071)
$gone = @($retired | Where-Object {
    -not (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\messages\' + $_))) })
if ($gone.Count -gt 0) {
    Write-Host ''
    Write-Host 'verify-routes: SUPERSEDED - this script has not been rewritten yet.' -ForegroundColor Yellow
    Write-Host ('  It asserts messages that Phase 2 retired: ' + ($gone -join ', ')) -ForegroundColor Yellow
    Write-Host '  The routes are now set with SSH | API | BOTH | NONE, on both'          -ForegroundColor Yellow
    Write-Host '  CREATE.ACCOUNT and MODIFY.ACCOUNT.  See PROJECT_STATUS.md, Phase 4.'   -ForegroundColor Yellow
    exit 2
}

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-routes-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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

# The installed sysmsg(N) as a REGEX, with each %1/%2 replaced by ".*" and every
# literal run escaped.  Read from the install rather than hard-coded, so a
# reworded message fails the check that names it instead of going blind.
#
# SPLIT ON EVERY %n, NOT TRUNCATED AT THE FIRST.  The version this is copied
# from took the text before the first '%', and every message here BEGINS with
# %1 - so the pattern was the empty string and six checks failed on a run where
# the feature worked.  20 Aug 2026, verify-rdpaccount.ps1's own history.
function Get-SysMsgPattern([int]$n) {
    $f = Join-Path $env:ProgramData ('SD\sdsys\messages\' + $n)
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $t = ((Get-Content -LiteralPath $f -Raw)).Trim()
    if ($t -eq '') { return '' }
    $parts = [regex]::Split($t, '%\d')
    return (($parts | ForEach-Object { [regex]::Escape($_) }) -join '.*')
}

function Shown($out, [int]$n) {
    $p = Get-SysMsgPattern $n
    return ($p -ne '' -and $out -match $p)
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
public class SdRouteLogon {
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
    $rc = [SdRouteLogon]::Try($user, $pass, 2)
    if ($rc -eq 0) { return 'admitted' }
    if ($rc -eq 1385) { return 'refused 1385' }
    return ("refused " + $rc)
}

function InGroup($group, $user) {
    $m = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like ("*\" + $user) }
    return [bool]$m
}

# ---------------------------------------------------------------------------
if (-not $Prefix) {
    Write-Host 'verify-routes: -Prefix is required, and must be a stem nobody has used.'
    Write-Host '  Example: -Prefix sdrt1'
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
foreach ($g in @('sdsshonly', 'sdssh', 'sdapi')) {
    if (-not (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue)) {
        Fail "the $g group does not exist - sync-route-groups.ps1 did not run, and it is the subject of this test."
    }
}

$stdAcc = $Prefix + 's'    # standard - confined to ssh, no API
$admAcc = $Prefix + 'a'    # administrator - the control
$rdpAcc = $Prefix + 'x'    # offered with RDPACCOUNT, must NOT be created
$made   = @()

foreach ($a in @($stdAcc, $admAcc, $rdpAcc)) {
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
    $cmd = "CREATE.ACCOUNT USER $name BOTH"
    if ($extra -ne '') { $cmd += " $extra" }
    $out = Invoke-SD @($cmd, $pw, $pw)
    $rec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $name.ToUpper())
    if (-not (Test-Path -LiteralPath $rec)) { Write-Host $out; Fail "CREATE.ACCOUNT did not register $name" }
    $script:made += $name
    return @{ Password = $pw; Out = $out }
}

try {
    # -----------------------------------------------------------------------
    Step 1 "A new account: CREATE.ACCOUNT USER $stdAcc"

    $s = New-Acct $stdAcc ''
    Note 'message 10034 shown (ssh only)'   $true (Shown $s.Out 10034)
    Note 'message 10063 shown (may ssh)'    $true (Shown $s.Out 10063)
    Note 'IS in sdsshonly'                  $true  (InGroup 'sdsshonly' $stdAcc)
    Note 'IS in sdssh'                      $true  (InGroup 'sdssh' $stdAcc)
    # THE DEFAULT-OFF DECISION, 21 Aug 2026.  If this ever reads $true, either
    # CREATEA joined sdapi or something else did, and every new account can
    # reach the API as LocalSystem until the containment gate lands.
    Note 'NOT in sdapi'                     $false (InGroup 'sdapi' $stdAcc)
    Note 'may NOT sign in at the keyboard'  'refused 1385' (InteractiveLogon $stdAcc $s.Password)

    # -----------------------------------------------------------------------
    Step 2 "THE CONTROL: an administrator account CAN sign in"

    # Without this, step 1's refusal would pass on a machine where LogonUser
    # refuses everybody - a wrong password, a disabled account, a broken
    # P/Invoke all read as "refused" and none of them is the deny right.
    $a = New-Acct $admAcc 'ADMINISTRATOR'
    Note 'admin is in Administrators'   $true  (InGroup 'Administrators' $admAcc)
    Note 'admin NOT in sdsshonly'       $false (InGroup 'sdsshonly' $admAcc)
    Note 'admin CAN sign in'            'admitted' (InteractiveLogon $admAcc $a.Password)

    # -----------------------------------------------------------------------
    Step 3 "RDPACCOUNT is gone"

    # It must be refused as an unknown keyword, and - the half that matters -
    # it must not leave a half-made account behind.  more.args runs BEFORE the
    # account is created, so sysmsg(2018) means nothing was made.
    $out = Invoke-SD @("CREATE.ACCOUNT USER $rdpAcc RDPACCOUNT")
    Note 'RDPACCOUNT refused (message 2018)' $true (Shown $out 2018)
    Note 'no ACCOUNTS record was written'    $false (Test-Path -LiteralPath (
             Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $rdpAcc.ToUpper())))
    Note 'no Windows account was created'    $false ([bool](
             Get-LocalUser -Name $rdpAcc -ErrorAction SilentlyContinue))

    # -----------------------------------------------------------------------
    Step 4 "ssh can be withdrawn and restored, and the keyboard stays shut"

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc NO.SSH")
    Note 'NO.SSH: message 10065'        $true  (Shown $out 10065)
    Note 'NO.SSH: out of sdssh'         $false (InGroup 'sdssh' $stdAcc)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc NO.SSH")
    Note 'NO.SSH twice says already'    $true  (Shown $out 10066)

    # THE INVARIANT.  No route verb may hand back the keyboard - that is the
    # whole reason RDPACCOUNT was deleted rather than split.
    Note 'still in sdsshonly'           $true  (InGroup 'sdsshonly' $stdAcc)
    Note 'still refused at the keyboard' 'refused 1385' (InteractiveLogon $stdAcc $s.Password)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc SSH")
    Note 'SSH: message 10063'           $true  (Shown $out 10063)
    Note 'SSH: back in sdssh'           $true  (InGroup 'sdssh' $stdAcc)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc SSH")
    Note 'SSH twice says already'       $true  (Shown $out 10064)

    # -----------------------------------------------------------------------
    Step 5 "the API can be granted and withdrawn, independently of ssh"

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc API")
    Note 'API: message 10068'           $true  (Shown $out 10068)
    Note 'API: in sdapi'                $true  (InGroup 'sdapi' $stdAcc)
    # INDEPENDENT, which is the point of two groups rather than one flag.
    Note 'API left ssh alone'           $true  (InGroup 'sdssh' $stdAcc)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc API")
    Note 'API twice says already'       $true  (Shown $out 10069)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc NO.API")
    Note 'NO.API: message 10070'        $true  (Shown $out 10070)
    Note 'NO.API: out of sdapi'         $false (InGroup 'sdapi' $stdAcc)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc NO.API")
    Note 'NO.API twice says already'    $true  (Shown $out 10071)

    Note 'still in sdsshonly after API work' $true (InGroup 'sdsshonly' $stdAcc)
    Note 'still refused at the keyboard'     'refused 1385' (InteractiveLogon $stdAcc $s.Password)

    # -----------------------------------------------------------------------
    Step 6 "sshd allows sdssh and no longer allows sdusers"

    # The group work above is worth nothing if sshd is still pointed at
    # sdusers: NO.SSH would report success and change nothing an ssh client
    # would notice.
    #
    # 21 Aug 26 - AND THE FIRST RUN FAILED THESE THREE, WHICH IS A REAL FINDING
    # AND NOT A FAULT IN THE CHECK.  sshd_config was stock: no AllowGroups and
    # no ForceCommand either.  The cause is a one-way ratchet in the installer,
    # and it predates this work:
    #
    #   * UNINSTALL always calls RemoveAllowGroups (sd.iss CurUninstallStepChanged),
    #     which strips SD's block.
    #   * INSTALL offers the "limitssh" task only under Check: SshServerAbsent,
    #     which is "was %SystemRoot%\System32\OpenSSH\sshd.exe missing when this
    #     install began" (sd.iss, SshWasAbsent).
    #   * SD's own first install puts sshd.exe there for ever.
    #
    # So the limiting works exactly once, on the first install on a machine with
    # no ssh server, and every cycle after that removes it and cannot re-apply
    # it.  Both halves go together, and the second is the sharp one: without
    # ForceCommand an ssh session lands at a PowerShell PROMPT rather than in
    # SD, so an account confined to sdsshonly gets a shell on the server - which
    # is the thing that confinement exists to prevent, arriving by the far door.
    #
    # THE DIAGNOSIS IS PRINTED RATHER THAN LEFT TO BE REDISCOVERED.  A bare
    # "expected True, got False" here reads like the sdssh change broke
    # something, and it did not.
    $cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (Test-Path -LiteralPath $cfg) {
        $body  = @(Get-Content -LiteralPath $cfg)
        $allow = @($body | Where-Object { $_ -match '^\s*AllowGroups\b' })
        $line  = ($allow -join ' ')
        $force = @($body | Where-Object { $_ -match '^\s*ForceCommand\b' }).Count -gt 0

        Note 'sshd_config has an AllowGroups line' $true ($allow.Count -gt 0)
        Note 'AllowGroups names sdssh'             $true ($line -match '\bsdssh\b')
        Note 'AllowGroups no longer names sdusers' $false ($line -match '\bsdusers\b')
        Note 'sshd_config has a ForceCommand line' $true $force

        if ($allow.Count -eq 0 -and -not $force) {
            $sshd = Join-Path $env:SystemRoot 'System32\OpenSSH\sshd.exe'
            Write-Host ''
            Write-Host 'DIAGNOSIS: SD has written nothing to sshd_config on this machine.' -ForegroundColor Yellow
            Write-Host ('   sshd.exe present before this install: ' +
                        (Test-Path -LiteralPath $sshd) +
                        '  -> the "limitssh" task is NOT OFFERED when it is present') -ForegroundColor Yellow
            Write-Host '   and uninstall strips the block every cycle, so it cannot come back.' -ForegroundColor Yellow
            Write-Host '   ssh is therefore open to any Windows account, and an ssh session' -ForegroundColor Yellow
            Write-Host '   gets a PowerShell prompt instead of SD.  sd.iss Check: SshServerAbsent.' -ForegroundColor Yellow
            Write-Host '   To apply it by hand, from an ELEVATED prompt:' -ForegroundColor Yellow
            Write-Host ('       powershell -File "' +
                        (Join-Path $env:ProgramFiles 'SD\allow-ssh-groups.ps1') + '" -Installed') -ForegroundColor Yellow
        }
    } else {
        Note 'sshd_config present' $true $false
    }
}
catch {
    $script:failed = $true
    Write-Host ''
    Write-Host ('verify-routes: THREW - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $null = $results.Add([pscustomobject]@{
        Check = 'the run completed without throwing'; Expected = $true; Observed = $false })
}
finally {
    if (-not $Keep) {
        Step 7 'Putting the system back'

        foreach ($x in $made) {
            # OUT OF sdsshonly FIRST, AND UNCONDITIONALLY.  If an account under
            # test ended up locked out of its own console when it should not
            # have been, deleting it in that state destroys the evidence of
            # which half broke.  Costs nothing when everything held.
            foreach ($g in @('sdsshonly', 'sdssh', 'sdapi')) {
                if (InGroup $g $x) {
                    try { Remove-LocalGroupMember -Group $g -Member $x -ErrorAction Stop
                          Write-Host "   took $x out of $g" } catch { }
                }
            }
            if (Get-LocalUser -Name $x -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name $x
                Write-Host "   removed Windows account $x"
            }
            $d = Join-Path $env:ProgramData ('SD\user_accounts\' + $x)
            if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
            $g = 'sdu_' + $x
            if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $g }
            $prof = Join-Path $env:SystemDrive ('Users\' + $x)
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
    Write-Host 'verify-routes: FAILED' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

Write-Host ''
Write-Host ('verify-routes: the keyboard is shut, ssh and the API move independently, ' +
            'and RDPACCOUNT is gone.') -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
