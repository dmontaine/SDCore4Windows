<#
.SYNOPSIS
    DELETE.ACCOUNT, both directions: the Windows account SD made goes without
    being asked about, and the one SD merely borrowed is refused.

.DESCRIPTION
    Owner's decision, 21 Aug 2026: DELETE.ACCOUNT deletes the associated Windows
    account.  It is part of what the verb does, not an extra it stops to ask
    about (DELACC, the "THE Y/N PROMPT IS GONE" block).  What still protects a
    borrowed login is !is_sd_user, which reads back the description "SD account"
    that CREATE_USER stamps on every account SD creates.

    BOTH DIRECTIONS OR NEITHER RESULT MEANS ANYTHING.  A run that only measured
    the deletion would pass just as happily on a build that deletes every
    Windows account it is pointed at, which is the one outcome that cannot be
    undone.  So the borrowed account is created in the same run, seconds apart,
    on the same install - it is the control, not a second test.

    THE PROFILE HALF IS EXERCISED RATHER THAN HOPED FOR.  A Windows account has
    no profile until something signs in as it, so a freshly created test account
    has nothing to remove and would pass the profile checks vacuously - the
    handoff note of 21 Aug 2026 says exactly this.  Both subjects are therefore
    given a real profile before the verb runs: the same two artefacts an ssh
    login would leave, a directory under C:\Users and a ProfileList entry keyed
    by SID, which are the two halves DELETE_USER targets with Remove-CimInstance.
    Two routes are tried - see the block above $profileSig, which records why
    there are two - and if neither works the profile checks report N/A naming
    the step and the Win32 error.  They never quietly pass.

    ON THE FIRST 21 Aug RUN THEY DID REPORT N/A, and that is what the design is
    for: 30 PASS + 7 N/A of 37, both directions held, and the seven were the
    whole profile half failing to be SET UP rather than failing.  A check that
    could not tell those apart would have called it 37/37.  The setup was fixed
    and the second run went 38 of 38 - so the profile half is now measured, not
    assumed.

    THE ACCOUNT DIRECTORY AND THE PROFILE ARE DIFFERENT THINGS, and since
    21 Aug 2026 one confirmation covers both.  ProgramData\SD\user_accounts\
    <name> is the SD account's DATA; C:\Users\<name> is the Windows profile and
    goes with the login.  ITS WORDING IS CHECKED, not just its presence: 10084
    names the Windows account, 10085 does not, and which one appears must match
    whether !is_sd_user will let that account be removed.  That is the whole
    point of the verb working out what will go BEFORE it asks - a prompt that
    promised to delete a login SD then declined to touch would be worse than
    no prompt.

    HOW "NO SECOND QUESTION" IS PROVED, AND WHY IT IS NOT AN ABSENCE.  Asserting
    that some prompt text is missing from the output is the shape of check this
    project has been bitten by five times - an absent marker read as an answer.
    So the input carries a SENTINEL after the single Y: a word that is in
    nobody's VOC.  If the verb asked exactly one question, the sentinel reaches
    the command processor and comes back as message 5051, "<sentinel> is not in
    your VOC" - a marker that MUST BE PRESENT.  If a second question were asked
    it would swallow the sentinel instead and the check fails.

    AND THE SENTINEL IS FOLLOWED BY TWO Y ANSWERS SO A REGRESSION REPORTS
    RATHER THAN HANGS.  The directory prompt loops until it is given Y or N, so
    a second prompt fed only the sentinel would re-ask, eat the OFF, reach EOF
    at the ":" prompt and spin (PROJECT_STATUS.md section 6).  The padding
    satisfies any extra question, the session still ends, and the sentinel check
    still fails because something consumed it.  Neither Y nor N is a VOC record
    in VOC_TEMPLATE, so in the ordinary case they land harmlessly as unknown
    verbs.

.PARAMETER Prefix
    Stem for two throwaway accounts: <prefix>s, which SD creates and must
    delete, and <prefix>b, which already exists and must be left alone.  Use a
    stem nobody has used - CREATE.ACCOUNT refuses a name it has seen, and the
    spent list is in PROJECT_STATUS.md.

.PARAMETER Keep
    Leave both subjects behind for poking at.  <prefix>b will still be there
    either way if the verb behaved; -Keep also spares it the cleanup.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-delaccount.ps1 -Prefix sddel1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

# ELEVATED, and an elevated window does not paste its output back into the
# session that asked for it - the same reason every other verifier here keeps a
# transcript.  Outside the trees cycle.ps1 deletes.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-delaccount-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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

# A question that could not be asked.  N/A is neither a pass nor a failure and
# does not set $failed; the summary counts it separately.  Copied from
# verify-apiadmin.ps1, whose header records why a third outcome had to exist.
function Skip($check, $why) {
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = 'n/a'; Observed = $why })
    Write-Host ("  [N/A ] {0}: {1}" -f $check, $why) -ForegroundColor Yellow
}

function Fail($msg) {
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# The installed sysmsg(N) as a REGEX: each %n becomes the value supplied for it
# or ".*", and every literal run is escaped.  Read from the install rather than
# hard-coded, so a reworded message fails the check that names it instead of
# going blind.  Positional, because [regex]::Split loses which %n it split on -
# every message used here numbers its placeholders in order.
function Get-SysMsgPattern([int]$n, [string[]]$vals) {
    $f = Join-Path $env:ProgramData ('SD\sdsys\messages\' + $n)
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $t = ((Get-Content -LiteralPath $f -Raw)).Trim()
    if ($t -eq '') { return '' }
    $parts = [regex]::Split($t, '%\d')
    $pat = [regex]::Escape($parts[0])
    for ($i = 1; $i -lt $parts.Count; $i++) {
        if ($vals -and $vals.Count -ge $i -and $vals[$i - 1] -ne '') {
            $pat += [regex]::Escape($vals[$i - 1])
        } else {
            $pat += '.*'
        }
        $pat += [regex]::Escape($parts[$i])
    }
    return $pat
}

function Shown($out, [int]$n, [string[]]$vals) {
    $p = Get-SysMsgPattern $n $vals
    return ($p -ne '' -and $out -match $p)
}

# Blank first line absorbs the pipe's BOM, TERM stops pagination, OFF ends it.
# The pipe is not a convenience: Start-Process -RedirectStandardInput hands SD a
# FILE handle and SD answers "Process terminated" and exits (section 6).
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

# ADOPT is gated on K$INTERNAL, which means "sd -internal", which means separate
# arguments and NOT piped - the shape adopt-account.ps1 uses and the only shape
# that has ever worked for it (PROJECT_STATUS.md 7 step 0).  It also needs a
# running server, which is why Start-SD exists below.
function Invoke-SDInternal([string[]] $SdArgs) {
    $so = Join-Path $env:TEMP ("sd-delacct-out-$PID.txt")
    $se = Join-Path $env:TEMP ("sd-delacct-err-$PID.txt")
    $p = Start-Process -FilePath $sdExe -ArgumentList $SdArgs -NoNewWindow -PassThru `
                       -RedirectStandardOutput $so -RedirectStandardError $se
    $exited = $p.WaitForExit(120000)
    $text = ''
    foreach ($f in @($so, $se)) {
        if (Test-Path $f) {
            $text += (Get-Content $f -Raw)
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $exited) { return "sd $SdArgs did not finish within two minutes" }
    return $text.Trim()
}

# NEVER "Start-Process -Wait" for sd -start: sdwind inherits sd's handles and
# outlives it, so anything waiting on the output streams waits for the daemon.
# Wait for the PROCESS TO APPEAR instead.
function Test-SdRunning { return ((Get-Process sdwind -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) }

function Start-SD {
    if (Test-SdRunning) { return $true }
    $null = Start-Process -FilePath $sdExe -ArgumentList '-start' -NoNewWindow
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-SdRunning) { Write-Host '  sdwind is up'; return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# MAKING A PROFILE WITHOUT A SIGN-IN, TWO WAYS, BECAUSE THE FIRST ONE FAILED.
#
# The profile half of DELETE.ACCOUNT cannot be measured on an account that has
# no profile, and nothing here ever signs one in: LogonUser on its own creates
# no profile whatever the logon type - which is why verify-routes has never left
# one behind - and the account SD makes is in sdsshonly, so an interactive logon
# is refused outright.
#
# ROUTE 1, userenv!CreateProfile.  Documented since Windows 8, makes both halves
# a first sign-in would make.  On the 21 Aug run it returned 0x800706F7,
# RPC_X_BAD_STUB_DATA, for BOTH subjects - so all seven profile checks reported
# N/A and the half went unmeasured.
#
#   THE BUFFER IS MAX_PATH NOW, AND THE COUNT IS THE BUFFER'S OWN CAPACITY.  The
#   failing run passed 320.  CreateProfile is serviced by ProfSvc over RPC and
#   the out parameter is size-constrained there, so a count above MAX_PATH is
#   rejected by the stub rather than by the API - which is what 1783 means and
#   why the error names no parameter.  Passing $sb.Capacity rather than a
#   literal also makes it impossible for the declared size and the real buffer
#   to disagree, which was the other candidate and was eliminated first by
#   measuring what New-Object StringBuilder 320 actually makes.
#
#   CONFIRMED, NOT INFERRED, on the sddel2 run: both subjects got their profile
#   "via CreateProfile" and the run went 38 of 38.  So MAX_PATH was the whole of
#   it, and route 2 below has still never executed.
#
# ROUTE 2, LogonUser + LoadUserProfile, tried only if route 1 fails.  This is
# how a profile really gets made, and it depends on no undocumented constraint:
# LoadUserProfile creates the profile when the user has none.  LOGON32_LOGON_
# NETWORK because it is the one logon type BOTH subjects can pass -
# deny-logon.ps1 sets SeDenyInteractiveLogonRight and SeDenyRemoteInteractive-
# LogonRight and deliberately NOT SeDenyNetworkLogonRight, since Win32-OpenSSH
# needs it (deny-logon.ps1:20).  It needs the account's password, which this
# script generated for both subjects and still holds.
#
# If BOTH fail the checks still report N/A, naming the step and the Win32 error.
# They never quietly pass.
$profileSig = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public class SdDelProfile {
    [DllImport("userenv.dll", CharSet=CharSet.Unicode, ExactSpelling=true)]
    public static extern int CreateProfile(string pszUserSid, string pszUserName,
        [Out] StringBuilder pszProfilePath, uint cchProfilePath);

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct PROFILEINFO {
        public int    dwSize;
        public int    dwFlags;
        public string lpUserName;
        public string lpProfilePath;
        public string lpDefaultPath;
        public string lpServerName;
        public string lpPolicyPath;
        public IntPtr hProfile;
    }

    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out IntPtr token);

    [DllImport("userenv.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool LoadUserProfile(IntPtr hToken, ref PROFILEINFO lpProfileInfo);

    [DllImport("userenv.dll", SetLastError=true)]
    static extern bool UnloadUserProfile(IntPtr hToken, IntPtr hProfile);

    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr handle);

    // Which call failed, so the N/A line can name it.  Two steps can fail here
    // and their error codes overlap - 1385 from LogonUser is a denied logon
    // right, from anywhere else it means nothing.
    public static string LastStep = "";

    // 0 on success, else the Win32 error of the step named by LastStep.
    public static int MakeProfileByLogon(string user, string pass) {
        IntPtr token = IntPtr.Zero;
        LastStep = "LogonUser";
        if (!LogonUser(user, ".", pass, 3, 0, out token))   // LOGON32_LOGON_NETWORK
            return Marshal.GetLastWin32Error();
        try {
            PROFILEINFO pi = new PROFILEINFO();
            pi.dwSize     = Marshal.SizeOf(typeof(PROFILEINFO));
            pi.dwFlags    = 1;                              // PI_NOUI
            pi.lpUserName = user;
            LastStep = "LoadUserProfile";
            if (!LoadUserProfile(token, ref pi))
                return Marshal.GetLastWin32Error();
            // Unloaded again at once: the hive is not wanted, the DIRECTORY and
            // the ProfileList entry it just created are.  A loaded profile also
            // reads as "somebody is signed in" to clean-test-profiles.ps1.
            UnloadUserProfile(token, pi.hProfile);
            LastStep = "";
            return 0;
        } finally {
            CloseHandle(token);
        }
    }
}
'@

function Get-Sid($name) {
    $u = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    if ($u) { return $u.SID.Value }
    return ''
}

function Get-ProfileEntry($sid) {
    if ($sid -eq '') { return $null }
    return (Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
            Where-Object { $_.SID -eq $sid })
}

# Returns the profile path, or '' with $script:profileWhy set to the reason.
# $script:profileHow names the route that worked, so the transcript records
# which one this machine actually needed.
function New-TestProfile($name, $pass) {
    $script:profileWhy = ''
    $script:profileHow = ''
    $sid = Get-Sid $name
    if ($sid -eq '') { $script:profileWhy = "no Windows account $name to give a profile to"; return '' }

    # Route 1.  0x800700B7 is ERROR_ALREADY_EXISTS as an HRESULT: a profile is
    # already there, which is the state this call was asked to reach.
    $sb = New-Object System.Text.StringBuilder 260
    $hr = $script:P::CreateProfile($sid, $name, $sb, [uint32]$sb.Capacity)
    if ($hr -eq 0 -or $hr -eq -2147024713) {
        $script:profileHow = 'CreateProfile'
    } else {
        # Route 2.
        $rc = $script:P::MakeProfileByLogon($name, $pass)
        if ($rc -eq 0) {
            $script:profileHow = 'LogonUser + LoadUserProfile'
        } else {
            $msg = (New-Object System.ComponentModel.Win32Exception -ArgumentList $rc).Message
            $script:profileWhy = ('CreateProfile 0x{0:X8}, then {1} failed {2} ({3})' -f
                                  $hr, $script:P::LastStep, $rc, $msg)
            return ''
        }
    }

    $e = Get-ProfileEntry $sid
    if (-not $e) {
        $script:profileWhy = ('{0} reported success but no Win32_UserProfile entry appeared' -f $script:profileHow)
        return ''
    }
    return $e.LocalPath
}

function Get-Description($name) {
    $u = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    if ($u) { return $u.Description }
    return '<no such account>'
}

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
if (-not $Prefix) {
    Write-Host 'verify-delaccount: -Prefix is required, and must be a stem nobody has used.'
    Write-Host '  Example: -Prefix sddel1'
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
    Fail 'this needs an ELEVATED PowerShell - CREATE_USER, DELETE_USER and CreateProfile all need an elevated token.'
}

& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'the installed tree does not match source - see above' }

if (-not (Test-Path -LiteralPath $sdExe)) { Fail "no $sdExe" }

# EVERY MESSAGE THIS RUN NAMES MUST BE THERE, checked before anything is made.
#
# Shown() answers $false for a message file it cannot read, and several checks
# below EXPECT $false - so a missing or emptied message would score them as
# passes on a run that measured nothing.  6029, 10037 and 10075 are asserted
# absent and never asserted present, so nothing else would catch it.  That is
# the "absent marker read as an answer" shape this project has paid for five
# times (PROJECT_STATUS.md, "THE RULE THAT WAS PAID FOR FIVE TIMES"): assert the
# marker is readable before believing what its absence means.
$needMsgs = @(5051, 10025, 10028, 10036, 10037, 10075, 10084, 10085)
$missing  = @($needMsgs | Where-Object { (Get-SysMsgPattern $_ $null) -eq '' })
if ($missing.Count -gt 0) {
    Fail ('checks here name these messages and the install has none of them: ' +
          ($missing -join ', '))
}

$sdAcc     = $Prefix + 's'   # SD makes this one.  It must go, Windows account and all.
$borrowAcc = $Prefix + 'b'   # somebody else's.  It must be left standing.

foreach ($a in @($sdAcc, $borrowAcc)) {
    if (Get-LocalUser -Name $a -ErrorAction SilentlyContinue) {
        Fail "$a already exists as a Windows account - use a fresh -Prefix."
    }
    if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $a.ToUpper()))) {
        Fail ($a.ToUpper() + ' is still in the ACCOUNTS register - use a fresh -Prefix.')
    }
    if (Test-Path -LiteralPath (Join-Path $env:SystemDrive ('Users\' + $a))) {
        Fail ("C:\Users\$a already exists - a profile from an earlier run.  " +
              'Sweep it with clean-test-profiles.ps1, or use a fresh -Prefix.')
    }
}

if (-not (Start-SD)) { Fail 'sdwind did not appear within 15 seconds - SD will not start.' }

# THE TYPE CARRIES A HASH OF ITS OWN SOURCE IN ITS NAME, and that is what makes
# this script safe to run twice in one window.
#
# Add-Type THROWS on a type name already defined, and a live PowerShell session
# CANNOT be given a new definition of one.  This script is meant to be run more
# than once - a spent prefix is the ordinary reason - so an elevated window that
# has run it before already holds its SdDelProfile.  Guarding by name alone
# gets the OLD definition and dies with "method not found" several steps later;
# guarding by name and refusing was the first fix, and it cost the owner a run
# on 21 Aug 2026 by demanding a fresh window for no reason the operator could
# see.
#
# Naming the type after its source removes the question instead of reporting it.
# Same source, same name, reused.  Edited source, a different name, compiled
# beside the old one, which nothing then refers to.  It cannot go stale, and no
# future edit to $profileSig has to remember any of this.
$md5   = [Security.Cryptography.MD5]::Create()
$stamp = [BitConverter]::ToString(
             $md5.ComputeHash([Text.Encoding]::UTF8.GetBytes($profileSig))
         ).Replace('-', '').Substring(0, 8)
$profileTypeName = 'SdDelProfile_' + $stamp
if (-not ($profileTypeName -as [type])) {
    Add-Type -Language CSharp -TypeDefinition (
        $profileSig -replace 'class SdDelProfile', ('class ' + $profileTypeName)) | Out-Null
}
# Held in a variable because the name is not known until now.  "$P::Member"
# reaches statics on a type held this way exactly as "[Name]::Member" does.
$script:P = $profileTypeName -as [type]
if (-not $script:P) { Fail "could not compile $profileTypeName - see above" }

Add-Type -AssemblyName System.Web

$sentinel = 'SDDELSENTINEL'
$made     = @()   # Windows accounts this script is responsible for

# ---------------------------------------------------------------------------
try {
    # -----------------------------------------------------------------------
    Step 1 "SD makes an account of its own: CREATE.ACCOUNT USER $sdAcc"

    $pw  = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $sdAcc BOTH", $pw, $pw)
    $made += $sdAcc

    $sdRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $sdAcc.ToUpper())
    $sdDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $sdAcc)
    if (-not (Test-Path -LiteralPath $sdRec)) { Write-Host $out; Fail "CREATE.ACCOUNT did not register $sdAcc" }

    Note 'registered in ACCOUNTS'          $true (Test-Path -LiteralPath $sdRec)
    Note 'account directory made'          $true (Test-Path -LiteralPath $sdDir)
    Note 'Windows account made'            $true ([bool](Get-LocalUser -Name $sdAcc -ErrorAction SilentlyContinue))
    Note "sdu_$sdAcc group made"           $true ([bool](Get-LocalGroup -Name ('sdu_' + $sdAcc) -ErrorAction SilentlyContinue))

    # THE MARKER !is_sd_user ACTUALLY READS, and the whole of direction one
    # rests on it.  Compared with -ceq, as IS_SD_USER does, so a description
    # differing only in case would read as somebody else's.
    Note 'description is exactly "SD account"' $true ((Get-Description $sdAcc) -ceq 'SD account')

    # -----------------------------------------------------------------------
    Step 2 "Give it a profile, so the profile half is not tested vacuously"

    $sdSid  = Get-Sid $sdAcc
    $sdProf = New-TestProfile $sdAcc $pw
    if ($sdProf -eq '') {
        Skip 'profile made for the SD account' $script:profileWhy
    } else {
        Note 'profile directory exists'     $true (Test-Path -LiteralPath $sdProf)
        Note 'ProfileList entry exists'     $true ([bool](Get-ProfileEntry $sdSid))
        Write-Host ("   profile: {0}  (via {1})" -f $sdProf, $script:profileHow)
    }

    # -----------------------------------------------------------------------
    Step 3 "DELETE.ACCOUNT $sdAcc - the Windows account must go, unasked"

    # One Y for the account DIRECTORY, then the sentinel, then padding.  See the
    # header: the sentinel coming back as "not in your VOC" is what proves
    # nothing else asked a question.
    $out = Invoke-SD @("DELETE.ACCOUNT $sdAcc", 'Y', $sentinel, 'Y', 'Y')
    Write-Host $out

    # 21 Aug 26 - THE PROMPT CHANGED SHAPE AND SO DID THIS PAIR.  It used to
    # assert 6031, "Delete directory xx (Y/N)?", which asked about the DATA
    # only.  There is one confirmation now and it names what will actually go,
    # so the check is that the LONGER wording was used - the one that promises
    # to remove the Windows account - and that the shorter one was not.
    # Asserting the wording is asserting the design: the whole point of working
    # out del.user before the question was that the prompt cannot over-promise.
    Note 'confirmation named the Windows account (10084)' $true  (Shown $out 10084 @($sdAcc.ToUpper(), $sdAcc))
    Note 'the shorter wording was NOT used (10085)'       $false (Shown $out 10085 @($sdAcc.ToUpper()))
    Note 'the sentinel reached the VOC (5051)'        $true  (Shown $out 5051 @($sentinel))
    Note 'message 10028 shown (OS User deleted)'      $true  (Shown $out 10028 @($sdAcc))
    Note 'message 10025 shown (group deleted)'        $true  (Shown $out 10025 @('sdu_' + $sdAcc))
    Note 'message 10036 NOT shown (not created by SD)' $false (Shown $out 10036 @($sdAcc))
    Note 'message 10037 NOT shown (does not exist)'   $false (Shown $out 10037 @($sdAcc))

    Note 'Windows account is gone'      $false ([bool](Get-LocalUser -Name $sdAcc -ErrorAction SilentlyContinue))
    Note 'sdu_ group is gone'           $false ([bool](Get-LocalGroup -Name ('sdu_' + $sdAcc) -ErrorAction SilentlyContinue))
    Note 'ACCOUNTS record is gone'      $false (Test-Path -LiteralPath $sdRec)
    Note 'account directory is gone'    $false (Test-Path -LiteralPath $sdDir)

    if ($sdProf -eq '') {
        Skip 'ProfileList entry is gone'  'no profile was made - see step 2'
        Skip 'profile directory is gone'  'no profile was made - see step 2'
        Skip 'message 10075 NOT shown'    'no profile was made, so nothing could be left behind'
    } else {
        # BOTH HALVES.  Removing the directory alone leaves the ProfileList
        # entry, and Windows then honours it the next time an account of that
        # name appears by putting the new profile at C:\Users\<name>.<COMPUTER>.
        # That is where the four .GITORLI profiles in DELETE_USER's history
        # came from, so the registry entry is the half worth asserting on.
        Note 'ProfileList entry is gone'    $false ([bool](Get-ProfileEntry $sdSid))
        Note 'profile directory is gone'    $false (Test-Path -LiteralPath $sdProf)
        Note 'message 10075 NOT shown (profile left behind)' $false (Shown $out 10075 @($sdAcc))
    }

    # -----------------------------------------------------------------------
    Step 4 "THE CONTROL: an account SD did not make, adopted with ADOPT"

    # Without this, step 3 would pass just as happily on a build that deletes
    # every Windows account it is pointed at - and that is the one mistake that
    # cannot be undone.  Same install, seconds apart.
    #
    # ENABLED, WITH A GENERATED PASSWORD, and not disabled - deliberately.  It
    # is what a borrowed human login actually is, it is what every other
    # account-creating verifier here makes, and it leaves the two subjects in
    # the SAME STATE for the profile step below: SD's own account is enabled by
    # the time CREATE.ACCOUNT has finished (SET_PASSWD calls Enable-LocalUser),
    # so a disabled control would mean a CreateProfile failure could be either
    # the machine or the account state.  The password is generated, printed
    # nowhere, and the account is removed in step 6.
    $bpw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $null = New-LocalUser -Name $borrowAcc -Password (ConvertTo-SecureString $bpw -AsPlainText -Force) `
                          -Description 'made by hand, not by SD' -ErrorAction Stop
    $made += $borrowAcc

    Note 'the borrowed account exists'                 $true  ([bool](Get-LocalUser -Name $borrowAcc -ErrorAction SilentlyContinue))
    Note 'its description is NOT "SD account"'         $false ((Get-Description $borrowAcc) -ceq 'SD account')

    $bSid  = Get-Sid $borrowAcc
    $bProf = New-TestProfile $borrowAcc $bpw
    if ($bProf -eq '') {
        Skip 'profile made for the borrowed account' $script:profileWhy
    } else {
        Note 'borrowed profile exists'  $true (Test-Path -LiteralPath $bProf)
        Write-Host ("   profile: {0}  (via {1})" -f $bProf, $script:profileHow)
    }

    # CREATE.ACCOUNT USER refuses a name whose Windows account already exists
    # (message 10038); ADOPT is the sanctioned door and needs sd -internal.
    $out = Invoke-SDInternal @('-internal', 'CREATE.ACCOUNT', 'USER', $borrowAcc, 'ADOPT')
    Write-Host $out

    $bRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $borrowAcc.ToUpper())
    $bDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $borrowAcc)
    if (-not (Test-Path -LiteralPath $bRec)) {
        Write-Host $out
        Fail ("ADOPT did not register $borrowAcc, so there is no SD account to " +
              'delete and direction two cannot be measured.')
    }
    Note 'ADOPT registered it'              $true ([bool](Test-Path -LiteralPath $bRec))
    Note "sdu_$borrowAcc group made"        $true ([bool](Get-LocalGroup -Name ('sdu_' + $borrowAcc) -ErrorAction SilentlyContinue))
    # ADOPT changes nothing about the Windows account - the 15 Aug rule in
    # CREATEA - so the description it was made with must still be there.  If
    # this ever failed, direction two would be measuring its own side effect.
    Note 'ADOPT left the description alone' $true ((Get-Description $borrowAcc) -ceq 'made by hand, not by SD')

    # -----------------------------------------------------------------------
    Step 5 "DELETE.ACCOUNT $borrowAcc - the Windows account must SURVIVE"

    $out = Invoke-SD @("DELETE.ACCOUNT $borrowAcc", 'Y', $sentinel, 'Y', 'Y')
    Write-Host $out

    # THE OTHER HALF OF THE SAME ASSERTION.  SD did not create this Windows
    # account, so del.user is empty and the prompt must NOT offer to remove it.
    # A run where 10084 appeared here would mean the caller had been asked to
    # confirm a deletion that !is_sd_user then refused to perform.
    Note 'confirmation used the shorter wording (10085)' $true  (Shown $out 10085 @($borrowAcc.ToUpper()))
    Note 'it did NOT offer the Windows account (10084)'  $false (Shown $out 10084 @($borrowAcc.ToUpper(), $borrowAcc))
    Note 'the sentinel reached the VOC (5051)'         $true  (Shown $out 5051 @($sentinel))
    Note 'message 10036 shown (not created by SD)'     $true  (Shown $out 10036 @($borrowAcc))
    Note 'message 10028 NOT shown (OS User deleted)'   $false (Shown $out 10028 @($borrowAcc))

    # THE DECISIVE ONE.
    Note 'the borrowed Windows account is STILL THERE' $true  ([bool](Get-LocalUser -Name $borrowAcc -ErrorAction SilentlyContinue))
    Note 'its description is untouched'                $true  ((Get-Description $borrowAcc) -ceq 'made by hand, not by SD')

    if ($bProf -eq '') {
        Skip 'the borrowed profile survived'  'no profile was made - see step 4'
        Skip 'its ProfileList entry survived' 'no profile was made - see step 4'
    } else {
        # The other half of "left alone": SD must not destroy the person's data
        # on its way out either.
        Note 'the borrowed profile survived'     $true (Test-Path -LiteralPath $bProf)
        Note 'its ProfileList entry survived'    $true ([bool](Get-ProfileEntry $bSid))
    }

    # The SD side still goes: only the LOGIN is spared.  The group is SD's own
    # work (CREATEA makes sdu_<name> on the adopt path too), so it goes with it.
    Note 'the SD account was still removed'  $false (Test-Path -LiteralPath $bRec)
    Note 'sdu_ group is gone'                $false ([bool](Get-LocalGroup -Name ('sdu_' + $borrowAcc) -ErrorAction SilentlyContinue))
    Note 'account directory is gone'         $false (Test-Path -LiteralPath $bDir)
}
catch {
    $script:failed = $true
    Write-Host ''
    Write-Host ('verify-delaccount: THREW - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $null = $results.Add([pscustomobject]@{
        Check = 'the run completed without throwing'; Expected = $true; Observed = $false })
}
finally {
    if (-not $Keep) {
        Step 6 'Putting the system back'

        # Everything here is litter by definition: if the verb behaved, only
        # the borrowed account is left, and it is left BECAUSE the verb was
        # right to refuse it.  Anything else surviving is reported before it is
        # removed, so a failure is not tidied away silently.
        foreach ($x in $made) {
            $u = Get-LocalUser -Name $x -ErrorAction SilentlyContinue
            if ($u) {
                if ($x -eq $sdAcc) {
                    Write-Host "   NOTE: $x survived DELETE.ACCOUNT and should not have" -ForegroundColor Yellow
                }
                $sid = $u.SID.Value
                Remove-LocalUser -Name $x
                Write-Host "   removed Windows account $x"
                $e = Get-ProfileEntry $sid
                if ($e) {
                    try { Remove-CimInstance -InputObject $e -ErrorAction Stop
                          Write-Host "   removed profile $($e.LocalPath)" } catch {
                          Write-Host "   FAILED to remove profile $($e.LocalPath) - $_" -ForegroundColor Yellow }
                }
            }
            $g = 'sdu_' + $x
            if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) {
                Remove-LocalGroup -Name $g; Write-Host "   removed group $g"
            }
            $d = Join-Path $env:ProgramData ('SD\user_accounts\' + $x)
            if (Test-Path -LiteralPath $d) {
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "   removed $d"
            }
            $r = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $x.ToUpper())
            if (Test-Path -LiteralPath $r) {
                Write-Host "   NOTE: $x is still in the ACCOUNTS register - remove it before reusing the prefix" -ForegroundColor Yellow
            }
        }
    } else {
        Write-Host ''
        Write-Host ("-Keep: " + ($made -join ', ') + " and their profiles are still there.") -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host

# [string] ON BOTH SIDES, AND IT IS NOT TIDINESS.  Expected holds $true for most
# checks here, and PowerShell's -eq coerces the RIGHT operand to the LEFT's type
# - so "$true -eq 'n/a'" is TRUE, and every check expecting $true would have been
# counted as N/A while the pass count read low.  Caught before the first run.
$na    = @($results | Where-Object { [string]$_.Expected -eq 'n/a' }).Count
$asked = @($results | Where-Object { [string]$_.Expected -ne 'n/a' })
$pass  = @($asked | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("verify-delaccount: {0} PASS + {1} N/A of {2}" -f $pass, $na, $results.Count)

if ($failed) {
    Write-Host ''
    Write-Host 'verify-delaccount: FAILED' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

Write-Host ''
Write-Host ('verify-delaccount: the account SD made went without being asked about, ' +
            'and the one it borrowed was refused.') -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
