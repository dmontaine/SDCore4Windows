<#
.SYNOPSIS
    The two remote routes: does the create-time keyword decide them, is
    MODIFY.ACCOUNT absolute rather than additive, does an administrator get both
    and refuse to be changed, and is RDPACCOUNT gone?

.DESCRIPTION
    Owner's rule, 21 Aug 2026: NOBODY SD CREATES REACHES THE KEYBOARD UNLESS
    THEY ARE AN ADMINISTRATOR, and the two routes that remain - ssh and the API
    - are settable per account.  This measures all three halves of that.

    REWRITTEN 21 AUG 2026 FOR PHASE 2's FOUR KEYWORDS.  It asserted the
    SSH / NO.SSH / API / NO.API pairs and messages 10063-10071, which no longer
    exist; between Phase 2 and this rewrite it refused with exit 2 rather than
    scoring eight failures that would have looked like a broken feature.

    THE ONE ASSERTION THAT MATTERS MOST IS THAT "API" TAKES ssh AWAY.  The
    keyword now says what the access IS, not what to add, so
    "MODIFY.ACCOUNT x API" on an account that had ssh leaves it with the API
    ALONE.  An additive implementation passes every other check in this file:
    the account ends up in sdapi either way, and only the sdssh membership
    afterwards tells the two apart.

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

# 21 Aug 26 - THE REFUSAL THAT STOOD HERE HAS GONE, AND ITS REPLACEMENT IS THE
# OPPOSITE TEST.  Between Phase 2 and this rewrite the script exited 2 if any of
# messages 10063-10071 was missing, because it asserted them and Shown() answers
# $false for a message file it cannot read - eight failures that look like a
# broken feature.
#
# NOW IT REFUSES IF ANY OF THEM IS STILL THERE.  Phase 2 retired all nine, so a
# tree that still has one is a tree this script's assertions do not describe -
# an install that predates Phase 2, most likely, and every route check below
# would be measuring the old verb.  Same guard, pointed the other way, and it
# costs nothing on a correct install.
$retired = @(10063, 10064, 10065, 10066, 10067, 10068, 10069, 10070, 10071)
$left = @($retired | Where-Object {
    Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\messages\' + $_)) })
if ($left.Count -gt 0) {
    Write-Host ''
    Write-Host 'verify-routes: THE INSTALLED TREE PREDATES PHASE 2.' -ForegroundColor Yellow
    Write-Host ('  Messages Phase 2 retired are still installed: ' + ($left -join ', ')) -ForegroundColor Yellow
    Write-Host '  This script asserts SSH | API | BOTH | NONE and messages 10076-10083,' -ForegroundColor Yellow
    Write-Host '  so it would be measuring a verb that is no longer the one under test.' -ForegroundColor Yellow
    Write-Host '  Run a cycle.' -ForegroundColor Yellow
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
    # LOGIN re-inits terminal geometry on every account switch (LOGIN:201-209),
    # so the initial TERM below is wiped by any LOGTO in $commands and long
    # LIST/COUNT output paginates on a stdin the pipe can no longer answer.
    # Full write-up in verify-tiers.ps1's Invoke-SD.
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
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

# $access is the SSH | API | BOTH | NONE word, which Phase 2 made REQUIRED for a
# USER account - there is no default any more, and leaving it out is message
# 10082.  ADMINISTRATOR supplies its own, so the caller passes '' for that one:
# passing a word as well would still work, but it would hide the thing worth
# knowing, which is that an administrator needs no keyword and overrides one.
function New-Acct($name, $access, $extra) {
    $pw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $cmd = "CREATE.ACCOUNT USER $name"
    if ($access -ne '') { $cmd += " $access" }
    if ($extra -ne '')  { $cmd += " $extra" }
    $out = Invoke-SD @($cmd, $pw, $pw)
    $rec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $name.ToUpper())
    if (-not (Test-Path -LiteralPath $rec)) { Write-Host $out; Fail "CREATE.ACCOUNT did not register $name" }
    $script:made += $name
    return @{ Password = $pw; Out = $out }
}

# The two group memberships as one string, so a Note reports what the account
# actually has rather than one half of it.  Reading them together is what makes
# "API took ssh away" a single check instead of two that could both be right
# about the wrong account.
function Routes($user) {
    $r = @()
    if (InGroup 'sdssh' $user) { $r += 'ssh' }
    if (InGroup 'sdapi' $user) { $r += 'api' }
    if ($r.Count -eq 0) { return 'none' }
    return ($r -join '+')
}

try {
    # -----------------------------------------------------------------------
    Step 1 "The keyword decides: CREATE.ACCOUNT USER $stdAcc SSH"

    # SSH RATHER THAN BOTH, deliberately.  This account is the subject of every
    # route change below, and starting it with one route is what lets step 4
    # see the other one being taken away.
    $s = New-Acct $stdAcc 'SSH' ''
    Note 'message 10034 shown (ssh only)'   $true (Shown $s.Out 10034)
    Note 'message 10076 shown (ssh, not the API)' $true (Shown $s.Out 10076)
    Note 'IS in sdsshonly'                  $true  (InGroup 'sdsshonly' $stdAcc)
    # THE KEYWORD IS THE WHOLE OF IT, 21 Aug 2026.  If this reads 'ssh+api'
    # then SSH granted the API as well and the four words mean nothing.
    Note 'routes are ssh alone'             'ssh'  (Routes $stdAcc)
    Note 'may NOT sign in at the keyboard'  'refused 1385' (InteractiveLogon $stdAcc $s.Password)

    # -----------------------------------------------------------------------
    Step 2 "THE CONTROL: an administrator CAN sign in, and gets both routes"

    # Without this, step 1's refusal would pass on a machine where LogonUser
    # refuses everybody - a wrong password, a disabled account, a broken
    # P/Invoke all read as "refused" and none of them is the deny right.
    #
    # NO ACCESS KEYWORD IS GIVEN, and that is an assertion in itself: the tier
    # sets access.given, so an administrator creation must not be refused with
    # 10082 for staying silent.
    $a = New-Acct $admAcc '' 'ADMINISTRATOR'
    Note 'admin is in Administrators'   $true  (InGroup 'Administrators' $admAcc)
    Note 'admin NOT in sdsshonly'       $false (InGroup 'sdsshonly' $admAcc)
    Note 'admin CAN sign in'            'admitted' (InteractiveLogon $admAcc $a.Password)
    # THE PHASE 2 GAP CLOSURE.  Before 21 Aug 2026 the administrator branch
    # joined NEITHER group, and APISRVR:1362 requires sdapi with no exemption -
    # so an SD administrator could not use the API at all.  ssh they reached
    # anyway, because allow-ssh-groups.ps1 names Administrators in its own
    # right, which is why sdapi is the half that was actually broken.
    Note 'admin has both routes'        'ssh+api' (Routes $admAcc)
    Note 'admin: message 10078 shown (both)' $true (Shown $a.Out 10078)

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
    Step 4 "MODIFY.ACCOUNT is ABSOLUTE: the keyword says what the access IS"

    # THE CHECK THIS STEP EXISTS FOR IS THE SECOND LINE, not the first.  An
    # additive implementation - the pre-21-Aug behaviour - also puts the account
    # in sdapi and would pass "routes include api".  What tells the two apart is
    # that ssh is GONE afterwards, on an account created with SSH one step ago.
    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc API")
    Note 'API: message 10077 (API, not ssh)' $true (Shown $out 10077)
    Note 'API: routes are api ALONE'         'api' (Routes $stdAcc)

    # 10080 IS A SEPARATE MESSAGE FROM THE FOUR, deliberately: "nothing changed"
    # is not the same statement as "this is what you have", and route.set says
    # it and returns without touching a group.
    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc API")
    Note 'API twice: message 10080 (nothing changed)' $true (Shown $out 10080)
    Note 'API twice: routes unchanged'                'api' (Routes $stdAcc)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc BOTH")
    Note 'BOTH: message 10078'          $true     (Shown $out 10078)
    Note 'BOTH: routes are ssh+api'     'ssh+api' (Routes $stdAcc)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc NONE")
    Note 'NONE: message 10079'          $true  (Shown $out 10079)
    Note 'NONE: routes are none'        'none' (Routes $stdAcc)

    $out = Invoke-SD @("MODIFY.ACCOUNT $stdAcc SSH")
    Note 'SSH: message 10076'           $true  (Shown $out 10076)
    Note 'SSH: routes are ssh alone'    'ssh'  (Routes $stdAcc)

    # THE INVARIANT, RE-CHECKED AFTER ALL OF IT.  No route verb may hand back
    # the keyboard - that is the whole reason RDPACCOUNT was deleted rather than
    # split.  Asserting it once at creation would not catch a route verb that
    # quietly touched sdsshonly, and NONE and BOTH are new code that could.
    Note 'still in sdsshonly'            $true (InGroup 'sdsshonly' $stdAcc)
    Note 'still refused at the keyboard' 'refused 1385' (InteractiveLogon $stdAcc $s.Password)

    # -----------------------------------------------------------------------
    Step 5 "an administrator is REFUSED, and nothing moves"

    # Owner's rule, 21 Aug 2026: administrators always have both, so there is
    # nothing to set.  It is refused with a message rather than ignored - the
    # difference matters, because silence would read as success to whoever
    # typed it.
    #
    # THE SECOND CHECK IS THE ONE THAT COULD FAIL QUIETLY.  A route.set that
    # printed 10083 and carried on would pass the message check and leave an
    # administrator with no API, which is exactly the state Phase 2 closed.
    $out = Invoke-SD @("MODIFY.ACCOUNT $admAcc NONE")
    Note 'admin refused: message 10083' $true     (Shown $out 10083)
    Note 'admin still has both routes'  'ssh+api' (Routes $admAcc)
    Note 'admin still NOT in sdsshonly' $false    (InGroup 'sdsshonly' $admAcc)
    Note 'admin can still sign in'      'admitted' (InteractiveLogon $admAcc $a.Password)

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
Write-Host ('verify-routes: the keyboard is shut, the four keywords say what the access IS, ' +
            'an administrator has both and cannot be changed, and RDPACCOUNT is gone.') -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
