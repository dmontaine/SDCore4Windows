# verify-sdsysgate.ps1 - prove that SDSYS refuses a real non-administrator, and
# that it is the IDENTITY test that refuses rather than a failed elevation.
# PRE_RELEASE_FIXES 62, which is 56's remainder.
#
#   VerifyInstall2.ps1 -Run <token>           the only supported way to run it
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# ***WHAT 62 IS.***  elevate('START') gates on Start-Process -Verb RunAs
# succeeding and tests NOBODY'S identity.  That verb gives an administrator a
# CONSENT prompt and a standard user a CREDENTIAL prompt - so a standard user
# holding an administrator's password reached SDSYS, and @logname then recorded
# the elevation against somebody who had not consented.  CPROC:2634 closed it
# by testing K$OS.ADMINISTRATOR BEFORE the elevate call.  Nothing tested that.
#
# ***MATCHING sysmsg 10002 IS NOT A TEST OF IT, AND THIS IS THE WHOLE REASON
# THE SCRIPT IS SHAPED THE WAY IT IS.***  CPROC prints 10002 on BOTH refusal
# paths:
#
#     CPROC:2637  identity gate       audit 'reason=not an administrator'
#     CPROC:2651  elevation failed    audit 'reason=elevation refused or unavailable'
#
# and the session is reached over ssh, which has NO INTERACTIVE DESKTOP, so
# UAC cannot render and elevate('START') would fail there ANYWAY.  A check that
# anchored on 10002 would therefore pass with the identity gate DELETED - the
# "pattern shared by the success and failure outputs" that CLAUDE.md calls a
# false positive with a check's name on it.
#
# ***SO THE DECISIVE READING IS THE AUDIT REASON, AND ONLY THAT.***  The two
# paths differ nowhere else.  'reason=not an administrator' means the identity
# gate fired; 'reason=elevation refused or unavailable' means execution reached
# the elevate call, which is the defect this entry is about.  The second is a
# DISQUALIFIER here, not a pass.
#
# ***WHICH IS WHY THIS RUNS ELEVATED AND LIVES IN VerifyInstall2.***  The audit
# trail is locked to SYSTEM and Administrators by secure-audit.ps1 - measured
# 29 Aug 2026, an unelevated read of C:\ProgramData\SD\sdsys\audit is
# "Permission denied".  verify-cmdaudit.ps1 is in that runner for the same
# reason and VerifyInstall2.ps1:350 says so in as many words.
#
# ***AND IT MAKES ITS OWN ACCOUNT RATHER THAN BORROWING ONE.***  VerifyInstall1
# creates one non-administrator account for the UNELEVATED half and removes it
# before handing over, so there is none left by the time this runner starts.
# This runner is already elevated, so CREATE.ACCOUNT costs no extra UAC prompt.
#
# WHAT IT CANNOT DO, SAID OUT LOUD.  It cannot exercise the original hole.  That
# needed a standard user at an INTERACTIVE DESKTOP typing an administrator's
# password into a RunAs credential prompt, and no non-interactive test can
# produce one - the same limit verify-notyet.ps1 records for step 9's password
# prompt.  What it proves is the property that closed the hole: the identity
# test is reached, it refuses, and the elevate call is never entered.
#
# THE PREFIX IS SINGLE-USE, like every other account-creating verifier here.
# It comes from the -Run token (PRE_RELEASE 54's rule), and a spent one is
# refused rather than reused, because an account left over from an earlier run
# would be measured instead of a fresh one.

[CmdletBinding()]
param(
    # NOT Mandatory, DELIBERATELY.  A Mandatory parameter with nothing to bind
    # makes PowerShell's BINDER prompt, which inside a runner is a hang rather
    # than an error - the trap that cost a run on 28 Aug 2026 and the reason
    # verify-nocase.ps1's own parameters are declared this way.  The refusal
    # below is the guard, and it must be reachable.
    [string] $Prefix = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$audit = Join-Path $env:ProgramData  'SD\sdsys\audit'

# ------------------------------------------------------------- the reporter

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $step; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
}

# ------------------------------------------------------------- preconditions

if ($Prefix -eq '') {
    Write-Output 'verify-sdsysgate: refusing - no -Prefix was given.'
    Write-Output '  It names the throwaway account and must come from the run token, so a'
    Write-Output '  second run on the same machine cannot silently measure the first run''s'
    Write-Output '  leftover account.  Run it the supported way:'
    Write-Output ''
    Write-Output '      C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\VerifyInstall1.ps1 -ThenElevated -Run <token>'
    Write-Output ''
    exit 2
}

$account = $Prefix.ToLower()

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-sdsysgate: this needs an ELEVATED session and this one is not.'
    Write-Output '  The audit trail is locked to SYSTEM and Administrators (secure-audit.ps1),'
    Write-Output '  and the audit REASON is the only thing that tells the identity refusal'
    Write-Output '  apart from a failed elevation - sysmsg 10002 is printed by both.'
    Write-Output '  Run it from VerifyInstall2, or from an ELEVATED PowerShell.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-sdsysgate: the installed tree does not match source - run a cycle first.'
    Write-Output '  This measures CPROC and LOGIN, which are BASIC: a stale install answers'
    Write-Output '  for the code the change replaced.'
    exit 2
}

foreach ($p in @($sdExe, $audit)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("verify-sdsysgate: {0} does not exist - nothing could be measured." -f $p)
        exit 2
    }
}

if ($null -ne (Get-LocalUser -Name $account -ErrorAction SilentlyContinue)) {
    Write-Output ("verify-sdsysgate: refusing - the Windows account '{0}' already exists." -f $account)
    Write-Output '  The prefix is single-use.  Measuring a leftover account would be measuring'
    Write-Output '  the previous run, and it may not even be a non-administrator any more.'
    Write-Output ("  Remove it, or use a fresh -Run token.")
    exit 2
}

# ***ECHO THE REAL INPUTS, NOT THE INTENDED ONES.***  A probe whose arguments
# were clobbered reported a pass on 23 Aug 2026 and the echoed line is what
# caught it.
Write-Output ("verify-sdsysgate: as {0}, ELEVATED" -f $id.Name)
Write-Output ("  sd      {0}" -f $sdExe)
Write-Output ("  audit   {0}" -f $audit)
Write-Output ("  account {0}   (from -Prefix '{1}')" -f $account, $Prefix)
Write-Output ''

# ------------------------------------------------------------- SD, elevated

# Piped stdin, inside a job with a timeout.  Start-Process
# -RedirectStandardInput hands sd.exe a FILE HANDLE and SD answers
# ":Process terminated" and runs nothing - written down 14 Aug 2026 and paid
# for again on 29 Aug.  Nothing here may use it.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    if ($null -eq $commands -or $commands.Count -eq 0) {
        throw 'Invoke-SD: no commands given; that would start a session, measure nothing and look like a pass.'
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** It leaves the session's user-table slot and locks behind, so"
        $out += "*** sdwind will not shut down and cycle.ps1 will refuse to start."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# ------------------------------------------------------------- the account

$password = New-SdTestPassword
$created  = $false

try {
    Write-Output '=== 1. a real non-administrator account ==========================='

    $mk  = New-SdTestUserScript -Name $account -Password $password
    $out = Invoke-SD $mk
    Write-Output '  --- CREATE.ACCOUNT said: ---'
    Write-Output $out

    # ***THE CONTROL IS WINDOWS, NOT SD's OWN WORDING.***  A verb that refused
    # still echoes the account name, so reading the transcript for it is the
    # false-positive shape CLAUDE.md names.  Get-LocalUser is independent of
    # anything SD printed.
    $lu = Get-LocalUser -Name $account -ErrorAction SilentlyContinue
    $created = ($null -ne $lu)
    Note 'the account exists in Windows' $true $created $true
    if (-not $created) {
        Write-Output 'verify-sdsysgate: the account was not created - nothing below could measure anything.'
        exit 2
    }

    # AND IT MUST NOT BE AN ADMINISTRATOR, or the whole test is inverted: an
    # administrator is SUPPOSED to be admitted, so a refusal would prove nothing
    # and an admission would look like the defect.
    $admins = @()
    try {
        $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction Stop |
                    ForEach-Object { ($_.Name -split '\\')[-1].ToLower() })
    } catch {
        Write-Output ('verify-sdsysgate: could not read the Administrators group - ' + $_.Exception.Message)
        Write-Output '  That check is the one that makes a refusal meaningful, so this refuses too.'
        exit 2
    }
    Note 'the Administrators group was readable' $true ($admins.Count -gt 0) $true
    Note 'the account is NOT an administrator' $false ($admins -contains $account) $true
    Write-Output ("  Administrators has {0} member(s); '{1}' among them: {2}" -f
                  $admins.Count, $account, ($admins -contains $account))
    Write-Output ''

    # --------------------------------------------------------- the measurement

    Write-Output '=== 2. the audit trail, before ===================================='
    $before = ''
    try { $before = [IO.File]::ReadAllText($audit) }
    catch {
        Write-Output ('verify-sdsysgate: the audit trail could not be read - ' + $_.Exception.Message)
        exit 2
    }
    Write-Output ("  audit is {0} bytes before" -f $before.Length)
    Write-Output ''

    Write-Output '=== 3. the account tries both routes =============================='
    Write-Output '  ssh in as a NON-administrator (LOGIN case 1 - the account s own), then LOGTO SDSYS.'

    $r = $null
    try {
        $r = Invoke-SdAsTestUser -Name $account -Password $password `
                 -Commands @('WHO', 'LOGTO SDSYS', 'WHO')
    } catch {
        Write-Output ("verify-sdsysgate: could not drive SD as {0} - {1}" -f $account, $_.Exception.Message)
        exit 2
    }
    $text = ($r.Out | Out-String)

    Write-Output ("  ssh exit {0}, {1} characters of output" -f $r.ExitCode, $text.Length)
    if ($r.Err -ne '') {
        Write-Output '  --- ssh stderr ---'
        foreach ($l in ($r.Err -split "`n")) {
            if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
        }
    }
    Write-Output '  --- the session said: ---'
    Write-Output $text

    # A SESSION THAT NEVER STARTED MUST NOT SCORE.  Over ssh the same silence
    # has causes that are nothing to do with the gate - a refused password,
    # sshd down, ForceCommand not starting SD - and every one of them would
    # otherwise read as "SDSYS was not reached", which is the answer being
    # looked for.
    Note 'the session produced output' $true ($text.Trim().Length -gt 0) $true
    if ($text.Trim().Length -eq 0) {
        Write-Output 'verify-sdsysgate: the session said nothing - it never ran, so nothing was measured.'
        exit 2
    }

    # ROUTE 1: LOGIN.  The account is where a NON-ADMINISTRATOR must land.
    #
    # 05 Sep 26 - THE REASON GIVEN HERE WAS FALSE.  PRE_RELEASE 167.  It said
    # "An ssh session is never elevated, so LOGIN:568's case cannot be taken".
    # An ssh session IS elevated for a member of Administrators - sshd runs as
    # LocalSystem and builds an unfiltered token - and that case WAS taken,
    # measured 5 Sep 2026.  This step passed anyway because the account it uses
    # is not an administrator, which is the only reason the wrong reason never
    # showed.  The right reason is the tier: an ordinary account cannot match
    # LOGIN's administrator case whatever its token says.
    #
    # AN ADMINISTRATOR CANNOT REACH THIS STEP AT ALL NOW - LOGIN refuses the
    # ssh session outright (PROJECT_STATUS.md 5.25).  verify-sshadmin.ps1 is
    # the step that measures THAT; this one stays the non-administrator leg.
    Note 'the session landed in the account (WHO names it)' $true `
         ($text -match ('(?i)\b' + [regex]::Escape($account) + '\b')) $true

    # 10002 IS RECORDED BUT IS NOT THE MEASUREMENT - see the header.  It is
    # printed by the identity refusal AND by a failed elevation, so it is kept
    # as evidence and scored as NOT decisive.
    Note 'SD printed the SDSYS refusal (10002 - not decisive)' $true `
         ($text -match 'restricted to privileged users') $false

    Write-Output ''
    Write-Output '=== 4. the audit trail, after - THE DECISIVE READING =============='
    $after = ''
    try { $after = [IO.File]::ReadAllText($audit) } catch { }
    $tail = ''
    if ($after.Length -gt $before.Length) { $tail = $after.Substring($before.Length) }
    Write-Output ("  audit is {0} bytes after, {1} new" -f $after.Length, $tail.Length)

    # ***THE NULL CASE FIRST.***  If the trail did not grow there is nothing to
    # read, and every pattern below would report "absent" - which for two of
    # them is the answer this script hopes to see.  A test that passes because
    # it did nothing must fail.
    Note 'the audit trail grew' $true ($tail.Length -gt 0) $true
    if ($tail.Length -eq 0) {
        Write-Output 'verify-sdsysgate: the audit trail did not grow - nothing was recorded, so nothing is proved.'
    } else {
        Write-Output '  --- new audit records ---'
        foreach ($l in ($tail -split "`n")) {
            if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
        }
    }

    # AND A CONTROL ON THE READER ITSELF: the session logged in, so the tail
    # must carry a LOGIN record.  Without this, a tail full of something else
    # entirely would still let the two tests below "pass" by absence.
    Note 'the tail carries this session s LOGIN record' $true `
         ($tail -match 'LOGIN account=') $true

    # ***THE MEASUREMENT.***  Present = the identity gate fired.
    Note 'refused BY IDENTITY (reason=not an administrator)' $true `
         ($tail -match 'LOGTO REFUSED account=SDSYS reason=not an administrator') $true

    # ***THE DISQUALIFIER.***  Present = execution reached elevate('START'),
    # which is the defect.  Over ssh that call fails for want of a desktop and
    # prints the SAME 10002, so this is the only thing that tells them apart.
    Note 'the elevate call was NEVER reached' $false `
         ($tail -match 'reason=elevation refused or unavailable') $true

    # AND NOTHING WAS GRANTED.
    Note 'no elevation was granted' $false `
         ($tail -match 'ELEVATION GRANTED account=SDSYS') $true

} finally {
    if ($created) {
        Write-Output ''
        Write-Output '=== 5. removing the account ======================================='
        try {
            $rmOut = Invoke-SD (Remove-SdTestUserScript -Name $account)
            Write-Output '  --- DELETE.ACCOUNT said: ---'
            Write-Output $rmOut
        } catch {
            Write-Output ('  DELETE.ACCOUNT failed - ' + $_.Exception.Message)
        }
        $still = Get-LocalUser -Name $account -ErrorAction SilentlyContinue
        if ($null -ne $still) {
            Write-Output ("  *** THE ACCOUNT '{0}' IS STILL THERE - remove it before the next run." -f $account)
        } else {
            Write-Output ("  '{0}' is gone." -f $account)
        }
    }
}

# ------------------------------------------------------------------ verdict

Write-Output ''
$results | Format-Table -AutoSize | Out-String | Write-Output

$decisive = @($results | Where-Object { $_.Decisive -eq 'yes' })
$failed   = @($decisive | Where-Object { $_.Result -eq 'FAIL' })
Write-Output ("verify-sdsysgate: {0} decisive check(s), {1} failed." -f $decisive.Count, $failed.Count)

# REFUSE A RUN THAT SCORED NOTHING.  An empty decisive list would print
# "0 failed" and exit 0 - the suite row this project has already been given
# once, on a suite that had never run a step.
if ($decisive.Count -eq 0) {
    Write-Output 'verify-sdsysgate: no decisive check ran - that is a broken test, not a pass.'
    exit 2
}

if ($fatal) { exit 1 }
exit 0
