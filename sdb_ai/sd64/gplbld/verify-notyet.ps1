# verify-notyet.ps1 - meet check-install.ps1's [not yet] path with a REAL stale
# token.  PROJECT_STATUS.md "WHAT IS ACTUALLY LEFT", item 1.
#
#   powershell -File verify-notyet.ps1            run the test, clean up
#   powershell -File verify-notyet.ps1 -Keep      leave the probe account behind
#   powershell -File verify-notyet.ps1 -Cleanup   remove a probe left by -Keep
#
# Exit 0 every check passed, 1 a check failed, 2 the test could not be run.
#
# WHY THIS EXISTS.  check-install.ps1 has three outcomes and the third - [not
# yet] - is the one a real user meets FIRST, on the logon that ran the
# installer.  Every branch of it has been proved by forcing the state, because
# the only account on this machine has been in sdusers since an earlier install
# and cannot produce a stale token.  So the path that matters most at install
# time is the one path never observed.
#
# THE MECHANISM, AND IT IS THE WHOLE DESIGN.  Windows fixes group membership in
# your access token WHEN YOU SIGN IN.  check-install reads the membership TWICE
# - from the group, and from this process's token - and the pair is what
# separates "sign out and back in" from "the installer never added you":
#
#   in the group, not in the token  ->  [not yet]
#   not in the group at all         ->  [PROBLEM]
#
# SO THE TOKEN HAS TO BE TAKEN BEFORE THE GROUP IS ADDED.  A logon AFTER the add
# carries sdusers and reports [ok], which is why the obvious version of this
# test - create the account, add it, log it on - cannot reach the branch at all.
# The order here is the install-time order exactly:
#
#   1. create the account, put it in Users (a real user has that, sdusers is
#      the only variable this test is allowed to move)
#   2. LogonUser -> token T.  T knows nothing of sdusers.
#   3. add the account to sdusers.  The GROUP now says yes; T still says no.
#   4. run check-install under T          -> must be [not yet]
#   5. LogonUser again -> token F, which DOES carry sdusers
#   6. run check-install under F          -> must be [ok]
#
# STEP 6 IS NOT DECORATION.  Same account, same machine, same script, same
# minute - only the age of the token differs.  Without it a [not yet] could come
# from anything about the probe account, and this file would be asserting that
# something unusual produced an unusual answer.
#
# THE FALSE PASS THIS HAS TO AVOID, because it is the likely one: check-install
# prints [not yet] for TWO different reasons, and the other is "Could not read
# the sdusers group".  Under an impersonated token Get-LocalGroupMember is
# exactly the sort of call that fails, and if it does, the wrong [not yet]
# appears and a careless test calls it a pass.  So the checks below assert the
# EXACT sentence, and separately assert that the other one is ABSENT.
#
# AND [not yet] MUST NOT BE A FAILURE.  Exit 0 is checked as its own row: the
# whole reason the third outcome exists is so that a healthy install is not
# reported as broken to somebody who has just installed it.
#
# WHAT IT DOES NOT DO: create, delete or change anything in SD.  It makes one
# Windows account, puts it in two groups, and removes it.  check-install itself
# only reads.

[CmdletBinding()]
param(
    # Derived nowhere - a fixed name is fine because the account is created and
    # removed in one run.  -Keep and -Cleanup are the pair that survive a run.
    [string] $Account = 'sdnotyet',

    # Leave the probe account behind for inspection.
    [switch] $Keep,

    # Remove a probe left by -Keep, then stop.  Exempt from assert-current:
    # removing an account needs no current tree, and a guard that blocks the
    # undo gets worked around.
    [switch] $Cleanup
)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-notyet-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

$MARKER  = 'SD not-yet verification probe - safe to delete'
$homedir = Join-Path $env:SystemDrive ('Users\' + $Account)
$SdGroup = 'sdusers'
# THE INSTALLED COPY, NOT THE ONE BESIDE THIS SCRIPT, and that is not a
# convenience.  The probe account cannot read C:\Users\<developer>\..., so a
# source-tree path under impersonation fails with "is not recognized as the name
# of a cmdlet, function, script file, or operable program" - which reads like a
# spelling mistake and is actually an ACL.  Measured on the first elevated run.
# It is also the more correct target: this is the file the Start Menu runs, and
# assert-current above has already established that it matches source.
$checkInstall = Join-Path $env:ProgramFiles 'SD\check-install.ps1'

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

# 30 Aug 26 - EVERY PHRASE MATCH IN THIS FILE GOES THROUGH THIS.
# PRE_RELEASE_FIXES.md 84.
#
# check-install writes CONSOLE output and the console wraps it at whatever width
# the run happens to have.  On -Run b74 the sentence arrived as
#
#     [not yet] You are in the "sdusers" group, but this sign-in does not have
#     it
#     yet.
#
# so a literal match for "...does not have it yet" found nothing and the check
# FAILED against a build that was printing exactly the right sentence.  It had
# passed on b73 at a different width, which is the worst property a check can
# have: correct by luck.
#
# ***THE CHECKS THAT PASSED WERE NO BETTER OFF, AND THAT IS WHY ALL SIX MOVED.***
# Four of them assert a phrase ABSENT.  A wrapped line is absent to a literal
# pattern too, so those would have passed just as happily on output that DID
# contain the thing they exist to rule out - PROJECT_STATUS.md's "absent marker
# read as an answer", again.  Repairing only the one that went red would have
# left four blind and looked like a fix.
#
# Same cure PRE_RELEASE 51 applied to Get-SysMsgPattern's Esc-Loose: escape the
# literal runs, join them with \s+.  A line break is whitespace, so the pattern
# stops caring where the console chose to put one.
function Wrapped([string]$phrase) {
    $runs = [regex]::Split($phrase.Trim(), '\s+')
    return (($runs | ForEach-Object { [regex]::Escape($_) }) -join '\s+')
}

# EVERY LINE HERE IS Write-Host, NOT Write-Output.  A PowerShell function
# returns everything it writes to the output stream, so a Write-Output beside
# the return makes the caller's $ok an ARRAY - and `if ($array)` is true for a
# non-empty one, which is how a refusal came to exit 0 once already.
# PROJECT_STATUS.md START HERE, third trap.
function Remove-Probe {
    $u = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
    if ($null -eq $u) {
        Write-Host "cleanup: no local user $Account"
    } elseif ($u.Description -ne $MARKER) {
        # Refusing here is the point.  An account this script did not create is
        # somebody's real account, whatever it happens to be called.
        Write-Host "cleanup: REFUSING to remove $Account - it does not carry this script's marker"
        return $false
    } else {
        # Out of the group first.  Removing the user leaves a dead SID in the
        # group otherwise, and sdusers is a group the product reads.
        try { Remove-LocalGroupMember -Group $SdGroup -Member $Account -ErrorAction Stop }
        catch { }
        Remove-LocalUser -Name $Account
        Write-Host "cleanup: removed local user $Account"
    }

    if (Test-Path $homedir) {
        Remove-Item -Recurse -Force $homedir -ErrorAction SilentlyContinue
        Write-Host "cleanup: removed $homedir"
    }
    return $true
}

# EVERY IMPERSONATED CALL GOES THROUGH HERE.  RunImpersonated has an Action
# overload and a Func<T> one, and PowerShell binds a scriptblock to the ACTION,
# which returns void - so the caller gets $null and every comparison downstream
# comes out of an empty string.  Measured against this process's own token, and
# then met for real: the fix was applied to the check-install call and MISSED on
# the inline token test one screen above it, which duly reported "expected
# False, got " on the first elevated run.  One helper, so the two cannot
# diverge again.  Script scope is visible inside the scriptblock and survives
# it, which is how the value comes back.
function Invoke-AsToken($token, [scriptblock]$body) {
    $script:impResult = $null
    [Security.Principal.WindowsIdentity]::RunImpersonated($token, {
        $script:impResult = & $body
    })
    return $script:impResult
}

# Runs check-install under a given token and returns its output and exit code.
#
# EVERY LINE IT PRINTS IS Write-Host, FOR THE SAME REASON Remove-Probe's are.
# A function returns everything it writes to the OUTPUT stream, so the
# Write-Output version of this returned an ARRAY - the header, each captured
# line, the crash report, and then the object - and $stale.Text and $stale.Crash
# read off that array gave nothing.  The visible symptom on the third elevated
# run was that the "*** check-install DID NOT FINISH ***" block never appeared
# at all while the checks depending on it failed: the diagnosis had been written
# into the return value.  Third time this trap has been paid for in this
# repository - PROJECT_STATUS.md START HERE.
# The script is invoked with & so that its own `exit` ends the script rather
# than this one, and $LASTEXITCODE is what it exited with.
#
# THE RESULT COMES BACK THROUGH $script:, NOT THROUGH THE RETURN VALUE, and that
# is not a style choice.  RunImpersonated has an Action overload and a Func<T>
# one, and PowerShell binds a scriptblock to the ACTION - which returns void.
# Measured 22 Aug 2026 against this process's own token: the call succeeds, the
# scriptblock runs, and the caller gets $null.  Every -match against $null.Text
# is then false, so the "expect true" rows fail and the "expect false" rows
# pass, and the run reports confident nonsense.  Script scope is visible inside
# the scriptblock and survives it - measured the same way.
function Invoke-CheckInstall($token, $label) {
    $out = Invoke-AsToken $token {
        # RUN IT WITH THE PREFERENCE IT NORMALLY HAS, NOT THIS SCRIPT'S.
        # $ErrorActionPreference = 'Stop' at the top of this file is inherited
        # by anything it invokes, so the first non-terminating error inside
        # check-install became fatal and the run died with "Access is denied"
        # instead of reporting.  check-install is WRITTEN to tolerate failures -
        # that is what [PROBLEM] and [not yet] are for - and the Start Menu runs
        # it with the default 'Continue'.  A test must not change the conditions
        # of the thing it is measuring.  Measured on the second elevated run.
        $ErrorActionPreference = 'Continue'
        $ProgressPreference = 'SilentlyContinue'

        # *>&1 AND NOT 2>&1.  check-install writes every line with Write-Host,
        # which is the INFORMATION stream in PowerShell 5+; 2>&1 redirects only
        # the error stream, so it would capture almost nothing and every check
        # below would compare against an empty string.  Measured on the real
        # script: 2>&1 gave 0 characters, *>&1 gave 596.  Same mechanic that
        # cost VerifyInstall1 its on-screen progress - PROJECT_STATUS.md.
        # AND CATCH IT DYING, because it can.  check-install.ps1:82 sets
        # $ErrorActionPreference = 'Stop' for itself, so the preference set
        # above does not reach it and an unguarded non-terminating error inside
        # it is fatal.  Without this the harness reports only "Access is
        # denied" from somewhere, which says nothing about WHERE.
        $o = ''
        $crash = $null
        try {
            $o = & $checkInstall -Brief -Yes -NoPause *>&1 | Out-String
        } catch {
            $o = $o + "`n<<CRASHED>> " + $_.Exception.Message
            $crash = [pscustomobject]@{
                Message = $_.Exception.Message
                Line    = $_.InvocationInfo.ScriptLineNumber
                Stmt    = $_.InvocationInfo.Line
                Stack   = $_.ScriptStackTrace
            }
        }
        [pscustomobject]@{ Text = $o; Code = $LASTEXITCODE; Crash = $crash }
    }
    if ($null -eq $out) {
        # Cannot happen by the route above, but a null here would poison every
        # check downstream silently, so it stops instead.
        throw "Invoke-CheckInstall: nothing came back from the impersonated run ($label)"
    }
    Write-Host ""
    Write-Host ("  --- check-install as $label, exit $($out.Code) ---")
    if ($null -ne $out.Crash) {
        Write-Host "  *** check-install DID NOT FINISH ***"
        Write-Host ("  *** " + $out.Crash.Message)
        Write-Host ("  *** at check-install.ps1 line " + $out.Crash.Line + ":  " + ($out.Crash.Stmt).Trim())
        foreach ($sl in ($out.Crash.Stack -split "`r?`n")) {
            if ($sl.Trim().Length) { Write-Host ("  *** " + $sl.Trim()) }
        }
    }
    foreach ($line in ($out.Text -split "`r?`n")) {
        if ($line.Trim().Length) { Write-Host ("  | " + $line) }
    }
    return $out
}

# WHAT THE CURRENT (impersonated) TOKEN IS, AND WHETHER IT CARRIES sdusers.
#
# BY SID, NOT BY TRANSLATED NAME, and that is a correction rather than a
# preference.  The first version copied check-install's own loop, which calls
# $g.Translate([NTAccount]) inside a try/catch and treats a throw as "absent".
# Under impersonation that translate does not reliably succeed, so the answer
# was False for BOTH tokens - which made "token T does NOT carry it" PASS FOR
# THE WRONG REASON and only showed up because the fresh-token row beside it
# expected True and got False on a token check-install had just called [ok].
# A SID comparison needs no name lookup and cannot fail that way.
#
# It returns the identity NAME too, so the run says whose token each section
# actually ran under instead of leaving it to be inferred.
$tokenFacts = {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    [pscustomobject]@{
        Name       = $id.Name
        HasSdUsers = [bool](@($id.Groups | Where-Object { $_.Value -eq $sdUsersSid }).Count)
        Groups     = @($id.Groups).Count
    }
}

$logonSig = @'
using System;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public class SdStaleToken {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out SafeAccessTokenHandle token);

    public static int LastError = 0;

    // A PRIMARY token for the named local account, held open by the caller.
    // The groups in it are fixed at this moment - which is the whole point.
    // logonType 2 is LOGON32_LOGON_INTERACTIVE, which is the kind of token
    // the person running the installer actually has.
    public static SafeAccessTokenHandle Logon(string user, string pass) {
        SafeAccessTokenHandle token;
        if (!LogonUser(user, ".", pass, 2, 0, out token)) {
            LastError = Marshal.GetLastWin32Error();
            return null;
        }
        LastError = 0;
        return token;
    }
}
'@

# -------------------------------------------------------------------- start --
$staleTok = $null
$freshTok = $null
# THE finally BLOCK RUNS ON THE WAY OUT OF AN `exit` TOO, so without this flag
# every "could not be run" exit above also ran the cleanup - which after a -Keep
# run would delete the probe somebody kept deliberately.  Measured on the first
# unelevated run: it printed "cleanup: no local user" after refusing to start.
$probeMade = $false
try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output "verify-notyet: not elevated - creating a local account and editing a group both need it"
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }

    if ($Cleanup) {
        $ok = Remove-Probe
        try { Stop-Transcript | Out-Null } catch { }
        if ($ok) { exit 0 } else { exit 1 }
    }

    if (-not (Test-Path -LiteralPath $checkInstall)) {
        Write-Output "verify-notyet: check-install.ps1 is not beside this script - cannot run"
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }

    # The tree has to match source: this asserts a SHIPPED script's behaviour,
    # so a stale check-install.ps1 would answer for a version nobody has.
    & (Join-Path $PSScriptRoot 'assert-current.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Output ''
        Write-Output 'verify-notyet: refusing - see above'
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }

    if ($null -eq (Get-LocalGroup -Name $SdGroup -ErrorAction SilentlyContinue)) {
        Write-Output "verify-notyet: there is no $SdGroup group - is SD installed?"
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }

    # An account of this name that this script did not make is somebody's.
    $existing = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
    if ($null -ne $existing -and $existing.Description -ne $MARKER) {
        Write-Output "verify-notyet: $Account exists and does not carry this script's marker - refusing"
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }
    if ($null -ne $existing) { $null = Remove-Probe }

    # Resolved OUTSIDE impersonation, where the lookup is certain to work, and
    # then only compared inside it.
    $sdUsersSid = (Get-LocalGroup -Name $SdGroup).SID.Value
    Write-Output ("  $SdGroup is " + $sdUsersSid)

    Add-Type -TypeDefinition $logonSig -Language CSharp | Out-Null

    # A password nobody chose and nobody keeps.  The alphabet excludes I, l, 1,
    # O and 0 so a human reading it off a console cannot transcribe it wrongly.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 20
    ([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $plain = (-join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })) + '-Aa9'
    $secure = ConvertTo-SecureString $plain -AsPlainText -Force

    Write-Output ""
    Write-Output "=== 1. an account whose token predates its membership ================"

    New-LocalUser -Name $Account -Password $secure -Description $MARKER `
        -AccountNeverExpires -PasswordNeverExpires -UserMayNotChangePassword | Out-Null
    $probeMade = $true
    Write-Output "  created local user $Account (random password, not stored)"

    # BUILTIN\Users by SID, not by name - the name is localised.  Every real
    # user has this; it is not sdusers, and it is what makes an interactive
    # logon possible at all.  sdusers stays the only variable that moves.
    Add-LocalGroupMember -SID 'S-1-5-32-545' -Member $Account
    Write-Output "  added $Account to BUILTIN\Users (needed for an interactive logon)"

    $staleTok = [SdStaleToken]::Logon($Account, $plain)
    if ($null -eq $staleTok) {
        Write-Output ("  LogonUser failed with Win32 error " + [SdStaleToken]::LastError)
        Write-Output "  verify-notyet: cannot take a token for the probe - test could not be run"
        $null = Remove-Probe
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }
    Write-Output "  took token T for $Account - BEFORE any sdusers membership exists"

    Add-LocalGroupMember -Group $SdGroup -Member $Account
    Write-Output "  added $Account to $SdGroup - the group now says yes, token T still says no"

    # The state is now exactly the install-time one.  Prove that before asking
    # check-install anything, so a later disagreement is attributable.
    $meSid = (Get-LocalUser -Name $Account).SID.Value
    $inGroupNow = [bool](@(Get-LocalGroupMember -Group $SdGroup |
                           Where-Object { $_.SID.Value -eq $meSid }).Count)
    Note 'the group carries the probe' $true $inGroupNow

    $staleFacts = Invoke-AsToken $staleTok $tokenFacts
    Write-Output ("  token T is " + $staleFacts.Name + ", " + $staleFacts.Groups + " groups")
    Note 'token T does NOT carry it' $false $staleFacts.HasSdUsers

    Write-Output ""
    Write-Output "=== 2. check-install under the stale token ==========================="

    $stale = Invoke-CheckInstall $staleTok 'token T (stale)'
    $t = $stale.Text

    Note 'check-install finished at all' $true ($null -eq $stale.Crash)

    # 30 Aug 26 - THE POSITIVE CONTROL FOR THE MATCHER, before anything trusts
    # it.  PRE_RELEASE_FIXES.md 84.  The fixture is the b74 output verbatim,
    # wrapped where the console wrapped it; the literal pattern this replaced
    # cannot match it.  If this ever goes red, every phrase check below is blind
    # and none of their verdicts mean anything.
    $wrapFixture = "in the `"sdusers`" group, but this sign-in does not have`nit`nyet."
    Note 'control: the phrase matcher survives a wrapped line' $true `
        ($wrapFixture -match (Wrapped 'in the "sdusers" group, but this sign-in does not have it yet'))

    Note 'says the sign-in has not got it yet' $true `
        ($t -match (Wrapped 'in the "sdusers" group, but this sign-in does not have it yet'))

    # THE FALSE PASS.  The other [not yet] would also contain "[not yet]", and
    # would mean the test measured a broken Get-LocalGroupMember instead.
    Note 'did NOT fall back to "could not read the group"' $false `
        ($t -match (Wrapped 'Could not read the "sdusers" group'))

    Note 'did NOT report it as [ok]' $false `
        ($t -match (Wrapped 'group and this sign-in has it'))

    Note 'did NOT report it as [PROBLEM]' $false `
        ($t -match (Wrapped 'You are not a member of the "sdusers" group'))

    # The reason the third outcome exists at all.
    Note 'a [not yet] is not a failure - exit code' 0 $stale.Code

    # The tree is unreadable on this token, so the catalogue count cannot be
    # answered either.  It must defer, not accuse.
    Note 'the catalogue check defers rather than accusing' $true `
        (($t -match (Wrapped '[not yet]')) -and -not ($t -match (Wrapped '[PROBLEM]')))

    Write-Output ""
    Write-Output "=== 3. the control: same account, a token taken AFTER the add ========"
    Write-Output "  Only the age of the token differs.  If this does not turn green,"
    Write-Output "  section 2 proved nothing about staleness."

    $freshTok = [SdStaleToken]::Logon($Account, $plain)
    if ($null -eq $freshTok) {
        Write-Output ("  LogonUser failed with Win32 error " + [SdStaleToken]::LastError)
        Note 'control: a fresh token could be taken' $true $false
    } else {
        # The token half of the control, asked directly rather than through
        # check-install: this is the mechanism the whole test rests on, and it
        # should be provable without trusting the thing under test.
        $freshFacts = Invoke-AsToken $freshTok $tokenFacts
        Write-Output ("  token F is " + $freshFacts.Name + ", " + $freshFacts.Groups + " groups")
        Note 'token F DOES carry it' $true $freshFacts.HasSdUsers

        $fresh = Invoke-CheckInstall $freshTok 'token F (fresh)'
        $f = $fresh.Text
        Note 'control: fresh token reports [ok]' $true `
            ($f -match (Wrapped 'group and this sign-in has it'))
        Note 'control: no "does not have it yet"' $false `
            ($f -match (Wrapped 'does not have it yet'))
        Note 'control: exit code' 0 $fresh.Code
    }
}
catch {
    Write-Output ""
    Write-Output ("verify-notyet: unexpected error - " + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    $failed = $true
}
finally {
    if ($null -ne $staleTok) { $staleTok.Dispose() }
    if ($null -ne $freshTok) { $freshTok.Dispose() }

    Write-Output ""
    if (-not $probeMade) {
        # Nothing was created on this run, so there is nothing here to undo.
    } elseif ($Keep) {
        Write-Output "-Keep: leaving $Account behind.  Remove it with -Cleanup."
    } else {
        $null = Remove-Probe
    }
}

Write-Output ""
Write-Output "=== summary ========================================================="
$results | Format-Table -AutoSize | Out-String | Write-Output
$passCount = @($results | Where-Object { $_.Result -eq 'PASS' }).Count
Write-Output ("{0}/{1} checks passed" -f $passCount, $results.Count)

try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 } else { exit 0 }
