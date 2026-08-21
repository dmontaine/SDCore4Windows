<#
.SYNOPSIS
    The rules CREATE.ACCOUNT enforces and nothing else measures: the access
    keyword is required, a password is mandatory, a GROUP account has neither,
    and ADOPT is refused without the installer's one-shot marker.

.DESCRIPTION
    THIS IS THE REFUSAL SIDE OF PHASES 2 AND 3.  verify-routes.ps1 measures what
    happens when the verbs are given what they want; every check here is about
    what happens when they are not, and until this existed none of it had any
    coverage at all - PROJECT_STATUS.md listed 10082, 10086, 10087 and the ADOPT
    gate as built-but-unmeasured.

    EVERY REFUSAL HAS A CONTROL THAT SUCCEEDS, and that is the whole design.
    "Nothing was created" passes just as happily on a build where
    CREATE.ACCOUNT never creates anything, on a machine out of disk, or on a
    name Windows would have refused anyway.  So each leg refuses first and then
    makes the SAME account a second time with the one thing that was missing:
    the keyword, a matching password, the marker.  A leg whose control does not
    succeed is reported as a failure of the leg, because the refusal it
    measured has been shown to prove nothing.

    THE PASSWORD FAILURE IS PROVOKED WITH TWO DIFFERENT PASSWORDS, not a weak
    one.  !set_passwd returns false with status 3 when "pw1 = '' or pw1 # pw2"
    (SET_PASSWD:100), which is deterministic; a password rejected by Windows
    policy would depend on the policy of the machine the test happens to run on.

    WHAT THE UNWIND HAS TO SHOW is that the WINDOWS account is gone, not just
    that SD made no account.  CREATEA creates the Windows user BEFORE asking for
    a password and calls delete_user() when the answer is no, and its own
    comment claims the unwind is complete because the sdu_ group, the directory,
    the VOC and the register entry are all made further down.  All four are
    checked, so that claim is measured rather than believed.

    IT NEVER OPENS AN API CONNECTION and never signs anybody in.  Those live in
    verify-apiadmin.ps1 and verify-routes.ps1; this one is about what does and
    does not get MADE.

.PARAMETER Prefix
    Stem for the throwaway accounts - four names are used: <prefix>n (offered
    with no access keyword), <prefix>p (offered mismatched passwords), <prefix>g
    (a GROUP account) and <prefix>d (a Windows account made by hand, for ADOPT).
    Use a stem nobody has used: CREATE.ACCOUNT refuses a name it has seen.

.PARAMETER Keep
    Leave everything behind for poking at.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-accountrules.ps1 -Prefix sdar1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$Data   = Join-Path $env:ProgramData 'SD'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-accountrules-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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

# WHAT SD SAID, INDENTED, INTO THE TRANSCRIPT.  Added 21 Aug 2026 after the
# first run of this file: step 3 failed five checks and printed NOT ONE LINE of
# what the verb had actually done, so the diagnosis had to be reconstructed from
# the source and could not be completed.  Every other verifier here prints its
# output; this one did not, and a failing check with no evidence is barely
# better than no check.  It is called on EVERY step, not only on failure - the
# point is that a run which passes is still readable afterwards.
function Said($label, $out) {
    Write-Host "   --- $label ---" -ForegroundColor DarkGray
    foreach ($l in ($out -split "`r?`n")) {
        if ($l.Trim() -ne '') { Write-Host ("     " + $l) -ForegroundColor DarkGray }
    }
}

# The installed sysmsg(N) as a REGEX: each %n becomes the value supplied for it
# or ".*", every literal run escaped.  Read from the install rather than
# hard-coded, so a reworded message fails the check that names it instead of
# going blind.  Copied from verify-delaccount.ps1, whose header records why the
# substitution is positional.
function Get-SysMsgPattern([int]$n, [string[]]$vals) {
    $f = Join-Path $Data ('sdsys\messages\' + $n)
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
# arguments and NOT piped - the shape adopt-account.ps1 uses and the only one
# that has ever worked for it (PROJECT_STATUS.md 7 step 0).
function Invoke-SDInternal([string[]] $SdArgs) {
    $so = Join-Path $env:TEMP ("sd-acctrules-out-$PID.txt")
    $se = Join-Path $env:TEMP ("sd-acctrules-err-$PID.txt")
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

function InGroup($group, $user) {
    $m = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like ("*\" + $user) }
    return [bool]$m
}

function Routes($user) {
    $r = @()
    if (InGroup 'sdssh' $user) { $r += 'ssh' }
    if (InGroup 'sdapi' $user) { $r += 'api' }
    if ($r.Count -eq 0) { return 'none' }
    return ($r -join '+')
}

function AcctRec($name) { return (Join-Path $Data ('sdsys\accounts\' + $name.ToUpper())) }
function UserDir($name) { return (Join-Path $Data ('user_accounts\' + $name)) }
function GrpDir($name)  { return (Join-Path $Data ('group_accounts\' + $name)) }
function HasUser($name) { return [bool](Get-LocalUser  -Name $name -ErrorAction SilentlyContinue) }
function HasGrp($name)  { return [bool](Get-LocalGroup -Name $name -ErrorAction SilentlyContinue) }

# "Is there any trace of this account at all?"  One string, so a half-made
# account reports WHICH half survived instead of failing four checks that each
# say a little of it.
function Traces($name) {
    $t = @()
    if (Test-Path -LiteralPath (AcctRec $name)) { $t += 'register' }
    if (Test-Path -LiteralPath (UserDir $name)) { $t += 'directory' }
    if (HasUser $name)                          { $t += 'windows-user' }
    if (HasGrp ('sdu_' + $name))                { $t += 'sdu_group' }
    if ($t.Count -eq 0) { return 'nothing' }
    return ($t -join '+')
}

# ---------------------------------------------------------------------------
if (-not $Prefix) {
    Write-Host 'verify-accountrules: -Prefix is required, and must be a stem nobody has used.'
    Write-Host '  Example: -Prefix sdar1'
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

# EVERY MESSAGE THIS RUN NAMES MUST BE THERE, checked before anything is made.
#
# Shown() answers $false for a message file it cannot read, and TWO checks below
# expect $false - "10084 NOT shown" in step 3 - so a missing or emptied message
# would score them as passes on a run that measured nothing.  That is the
# "absent marker read as an answer" shape this project has paid for five times
# (PROJECT_STATUS.md, "THE RULE THAT WAS PAID FOR FIVE TIMES"): assert the
# marker is readable before believing what its absence means.
$needMsgs = @(2018, 5051, 10008, 10014, 10015, 10040, 10082, 10084, 10085, 10086, 10087)
$missing  = @($needMsgs | Where-Object { (Get-SysMsgPattern $_ $null) -eq '' })
if ($missing.Count -gt 0) {
    Fail ('checks here name these messages and the install has none of them: ' +
          ($missing -join ', '))
}

if (-not (Start-SD)) { Fail 'SD would not start, and step 4 needs a server for sd -internal.' }

Add-Type -AssemblyName System.Web

$noKw   = $Prefix + 'n'   # offered with no access keyword
$pwAcc  = $Prefix + 'p'   # offered two different passwords
$grpAcc = $Prefix + 'g'   # a GROUP account
$adpAcc = $Prefix + 'd'   # a Windows account made by hand, for ADOPT

foreach ($a in @($noKw, $pwAcc, $grpAcc, $adpAcc)) {
    if (HasUser $a) { Fail "$a already exists as a Windows account - use a fresh -Prefix." }
    if (Test-Path -LiteralPath (AcctRec $a)) {
        Fail ($a.ToUpper() + ' is still in the ACCOUNTS register - use a fresh -Prefix.')
    }
}
if (HasGrp ('sdg_' + $grpAcc)) { Fail "sdg_$grpAcc already exists - use a fresh -Prefix." }

$sentinel    = 'SDARSENTINEL'
$adoptMarker = Join-Path $Data 'sdsys\$adopt'
$madeUsers   = @()      # Windows accounts this script is responsible for
$madeGroups  = @()      # Windows groups likewise

try {
    # -----------------------------------------------------------------------
    Step 1 "CREATE.ACCOUNT USER $noKw with NO access keyword (10082)"

    # Owner's decision, 21 Aug 2026: one of SSH / API / BOTH / NONE is required
    # and there is no default, because "no route" and "nobody said" are
    # different states and the old silent default could not tell them apart.
    #
    # REFUSED BEFORE ANYTHING IS MADE, which is the half that matters.  CREATEA
    # puts the test straight after more.args, so no Windows user, group,
    # directory or register entry exists yet.
    $out = Invoke-SD @("CREATE.ACCOUNT USER $noKw")
    Said "CREATE.ACCOUNT USER $noKw  (no keyword)" $out
    Note 'message 10082 shown (say who may reach this)' $true (Shown $out 10082 @())
    Note 'nothing at all was made'                      'nothing' (Traces $noKw)

    # THE CONTROL, AND IT USES THE SAME NAME ON PURPOSE.  Refusing then
    # succeeding on one name proves the refusal was about the missing keyword
    # and not about the name, the machine or the verb being broken outright.
    $pw  = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $noKw SSH", $pw, $pw)
    Said "CREATE.ACCOUNT USER $noKw SSH  (the control)" $out
    if (HasUser $noKw) { $script:madeUsers += $noKw }
    Note 'CONTROL: the same name with SSH is created' 'register+directory+windows-user+sdu_group' (Traces $noKw)
    Note 'CONTROL: routes are ssh alone'              'ssh' (Routes $noKw)

    # -----------------------------------------------------------------------
    Step 2 "A password is mandatory, and refusing unwinds (10086)"

    # TWO DIFFERENT PASSWORDS, which is what makes !set_passwd fail with status
    # 3 (SET_PASSWD:100) without depending on this machine's password policy.
    # Then N to "Retry (Y/N)", which since 21 Aug 2026 deletes the Windows user
    # and creates nothing instead of warning and carrying on.
    $out = Invoke-SD @("CREATE.ACCOUNT USER $pwAcc SSH", 'Sd-Verify-One-1!', 'Sd-Verify-Two-2!', 'N')
    Said "CREATE.ACCOUNT USER $pwAcc SSH  (mismatched passwords, then N)" $out
    if (HasUser $pwAcc) { $script:madeUsers += $pwAcc }   # only if the unwind failed

    Note 'message 10008 shown (retry?)'   $true (Shown $out 10008 @())
    Note 'message 10086 shown (an account must have a password)' $true (Shown $out 10086 @())

    # ALL FOUR TRACES, NOT JUST THE REGISTER.  CREATEA's own comment claims the
    # unwind is complete because only the Windows user exists at that point;
    # this is what turns that claim into a measurement.  A build that left the
    # Windows user behind would leave an account nothing can ever log in to and
    # a name CREATE.ACCOUNT would refuse for ever after.
    Note 'the unwind left nothing behind' 'nothing' (Traces $pwAcc)

    # THE CONTROL.  Without it, "nothing was made" is equally consistent with a
    # verb that cannot make anything.
    $pw2 = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $pwAcc SSH", $pw2, $pw2)
    Said "CREATE.ACCOUNT USER $pwAcc SSH  (the control)" $out
    if (HasUser $pwAcc) { $script:madeUsers += $pwAcc }
    Note 'CONTROL: matching passwords create the account' 'register+directory+windows-user+sdu_group' (Traces $pwAcc)

    # -----------------------------------------------------------------------
    Step 3 "A GROUP account has no Windows account, no password and no route"

    # Owner, 21 Aug 2026: a group account is reached with LOGTO or an F pointer,
    # so it gets none of the three - and "no password" means the idea does not
    # apply, not that a requirement was waived.  Nothing tested
    # CREATE.ACCOUNT GROUP at all before this.
    #
    # NO ACCESS KEYWORD AND NO PASSWORD ARE FED, and both are assertions: the
    # 10082 test is the USER arm's alone, and the GROUP arm reaches neither
    # create_user() nor set_passwd().  If either rule had been written as a
    # blanket one, this call would hang on a prompt or be refused.
    $out = Invoke-SD @("CREATE.ACCOUNT GROUP $grpAcc")
    Said "CREATE.ACCOUNT GROUP $grpAcc" $out
    if (HasGrp ('sdg_' + $grpAcc)) { $script:madeGroups += ('sdg_' + $grpAcc) }

    # WHERE IT STOPPED, IF IT STOPPED, AND THIS IS THE CHECK THE FIRST RUN
    # NEEDED AND DID NOT HAVE.  CREATEA makes the directory, then the sdg_
    # group, then make.account fills the directory, then the register entry.
    # So the directory's CONTENTS say which of those got as far as running:
    #
    #   empty          -> create.group failed and stopped (10015 will say why)
    #   holds voc      -> make.account ran, so the failure is after it
    #
    # Recorded before the checks below and before any cleanup, because the
    # first run deleted the directory in its finally and took the evidence.
    $gdir = GrpDir $grpAcc
    $gkids = @()
    if (Test-Path -LiteralPath $gdir) {
        $gkids = @(Get-ChildItem -LiteralPath $gdir -Force -ErrorAction SilentlyContinue |
                   ForEach-Object { $_.Name })
    }
    Write-Host ("   group directory holds: " +
                $(if ($gkids.Count -eq 0) { '(nothing)' } else { $gkids -join ', ' })) -ForegroundColor DarkGray

    # NAME THE GROUP STEP'S OWN MESSAGE either way, so the next failure says
    # WHY rather than leaving it to be reconstructed from the source.  10015
    # carries the status code from os_group.
    Note 'message 10014 shown (group created)' $true  (Shown $out 10014 @(('sdg_' + $grpAcc)))
    Note 'message 10015 NOT shown (could not create the group)' $false (Shown $out 10015 @())

    Note 'registered in ACCOUNTS'          $true (Test-Path -LiteralPath (AcctRec $grpAcc))
    Note 'group account directory made'    $true (Test-Path -LiteralPath $gdir)
    Note 'make.account ran (there is a voc)' $true ($gkids -contains 'voc')
    Note "sdg_$grpAcc group made"          $true (HasGrp ('sdg_' + $grpAcc))
    Note 'NO Windows user of that name'    $false (HasUser $grpAcc)
    Note 'NO sdu_ group either'            $false (HasGrp ('sdu_' + $grpAcc))
    # THE CREDENTIAL REGISTER IS KEYED BY ACCOUNT NAME, so an entry here would
    # mean set_passwd or CRED_SET had been reached on a path that must not
    # reach either.  Readable only because this script runs elevated - $cred is
    # locked to SYSTEM and Administrators.
    Note 'NO credential record'            $false (Test-Path -LiteralPath (
             Join-Path $Data ('sdsys\$cred\' + $grpAcc.ToUpper())))

    # MODIFY.ACCOUNT refuses it BY NAME rather than falling through to "is not a
    # member of sdusers", which is true and explains nothing.  route.set tests
    # the sdg_ prefix first for exactly that reason.
    $out = Invoke-SD @("MODIFY.ACCOUNT $grpAcc SSH")
    Said "MODIFY.ACCOUNT $grpAcc SSH" $out
    Note 'MODIFY.ACCOUNT refused: message 10087' $true (Shown $out 10087 @($grpAcc.ToUpper()))
    Note 'still no Windows user'                 $false (HasUser $grpAcc)

    # AND IT IS DELETED WITHOUT BEING ASKED ABOUT A WINDOWS ACCOUNT IT NEVER
    # HAD.  10084 names one and 10085 does not; showing the longer wording here
    # would be the verb promising to remove something that does not exist.
    #
    # ONE Y, THEN THE SENTINEL.  If the verb asked exactly one question the
    # sentinel reaches the command processor and comes back as 5051, "not in
    # your VOC"; a second prompt would swallow it.  The trailing Ys satisfy any
    # extra question so the session still ends.  verify-delaccount.ps1's header
    # carries the full reasoning.
    $out = Invoke-SD @("DELETE.ACCOUNT $grpAcc", 'Y', $sentinel, 'Y', 'Y')
    Said "DELETE.ACCOUNT $grpAcc" $out
    Note 'message 10085 shown (no Windows account named)' $true  (Shown $out 10085 @($grpAcc.ToUpper()))
    Note 'message 10084 NOT shown'                        $false (Shown $out 10084 @())
    Note 'the sentinel reached the VOC (5051)'            $true  (Shown $out 5051 @($sentinel))
    Note 'ACCOUNTS record is gone'                        $false (Test-Path -LiteralPath (AcctRec $grpAcc))
    Note 'group account directory is gone'                $false (Test-Path -LiteralPath (GrpDir $grpAcc))
    Note "sdg_$grpAcc group is gone"                      $false (HasGrp ('sdg_' + $grpAcc))

    # -----------------------------------------------------------------------
    Step 4 "ADOPT is refused without the installer's one-shot marker"

    # Phase 3, 21 Aug 2026.  K$INTERNAL alone is only "somebody typed
    # sd -internal", which any elevated administrator can do; the marker is what
    # makes ADOPT install-only.
    #
    # A REAL WINDOWS ACCOUNT FIRST, because ADOPT refuses a name that is not one
    # - and if it did that here, the refusal below would be measuring the wrong
    # rule entirely.
    $bpw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $null = New-LocalUser -Name $adpAcc -Password (ConvertTo-SecureString $bpw -AsPlainText -Force) `
                          -Description 'made by hand, not by SD' -ErrorAction Stop
    $madeUsers += $adpAcc

    if (Test-Path -LiteralPath $adoptMarker) {
        Remove-Item -LiteralPath $adoptMarker -Force -ErrorAction SilentlyContinue
        Write-Host '   removed a marker that was already there - the install left one behind' -ForegroundColor Yellow
    }

    $out = Invoke-SDInternal @('-internal', 'CREATE.ACCOUNT', 'USER', $adpAcc, 'ADOPT')
    Said "sd -internal CREATE.ACCOUNT USER $adpAcc ADOPT  (no marker)" $out

    # AS AN UNRECOGNISED TOKEN, NOT AS A REFUSAL, and that is deliberate: a
    # keyword a console user may never use is not one they need to know exists,
    # so a message naming it would confirm the guess.  2018 is "Unexpected
    # token (%1)".
    Note 'ADOPT refused as an unknown token (2018)' $true (Shown $out 2018 @('ADOPT'))
    Note 'no SD account was registered'             $false (Test-Path -LiteralPath (AcctRec $adpAcc))
    Note 'the Windows account is untouched'         $true  (HasUser $adpAcc)

    # THE CONTROL, AND IT IS THE WHOLE POINT OF THE LEG.  Same command, same
    # name, seconds apart, with the marker present.  Without this, "ADOPT was
    # refused" would pass on a build where ADOPT is broken outright or where
    # sd -internal never ran at all.
    Set-Content -LiteralPath $adoptMarker -Encoding utf8 `
                -Value "written by verify-accountrules.ps1 for $adpAcc"
    $out = Invoke-SDInternal @('-internal', 'CREATE.ACCOUNT', 'USER', $adpAcc, 'ADOPT')
    Said "sd -internal CREATE.ACCOUNT USER $adpAcc ADOPT  (with the marker)" $out
    $markerLeft = Test-Path -LiteralPath $adoptMarker

    Note 'CONTROL: with the marker, ADOPT registers it' $true (Test-Path -LiteralPath (AcctRec $adpAcc))
    Note 'the marker was consumed'                      $false $markerLeft
    # ADOPT CHANGES NOTHING ABOUT THE WINDOWS ACCOUNT - the 15 Aug rule - so the
    # description it was made with must survive.
    Note 'the description is untouched' 'made by hand, not by SD' (
             (Get-LocalUser -Name $adpAcc -ErrorAction SilentlyContinue).Description)
    # AND IT GETS BOTH ROUTES, because ADOPT forces tier ADMINISTRATOR and an
    # administrator always has both.  Before Phase 2 an ADOPTed account joined
    # NEITHER, and APISRVR:1362 requires sdapi with no exemption - so the person
    # who installed SD could not use its API.  The install exercises this every
    # time; nothing measured it until now.
    Note 'an ADOPTed account has both routes' 'ssh+api' (Routes $adpAcc)
    # 10040, not 10034: ADOPT must not put a borrowed login into sdsshonly.
    Note 'message 10040 shown (keeps its sign-in rights)' $true  (Shown $out 10040 @($adpAcc))
    Note 'NOT put in sdsshonly'                           $false (InGroup 'sdsshonly' $adpAcc)

    # A SECOND ADOPT WITH NO MARKER IS REFUSED AGAIN, which is what "one-shot"
    # means.  It would be refused as "account already exists" too, so this asks
    # for 2018 specifically - the token test comes first in more.args, before
    # anything looks at the register.
    $out = Invoke-SDInternal @('-internal', 'CREATE.ACCOUNT', 'USER', $adpAcc, 'ADOPT')
    Said "sd -internal CREATE.ACCOUNT USER $adpAcc ADOPT  (marker spent)" $out
    Note 'the marker does not work twice (2018)' $true (Shown $out 2018 @('ADOPT'))
}
catch {
    $script:failed = $true
    Write-Host ''
    Write-Host ('verify-accountrules: THREW - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $null = $results.Add([pscustomobject]@{
        Check = 'the run completed without throwing'; Expected = $true; Observed = $false })
}
finally {
    # THE MARKER GOES FIRST AND UNCONDITIONALLY.  Everything else here is a test
    # account; this one is a hole in the install-only gate, and leaving it
    # behind would quietly re-open ADOPT for every session afterwards.
    if (Test-Path -LiteralPath $adoptMarker) {
        Remove-Item -LiteralPath $adoptMarker -Force -ErrorAction SilentlyContinue
        Write-Host '   removed the ADOPT marker'
    }

    if (-not $Keep) {
        Step 5 'Putting the system back'

        foreach ($x in ($madeUsers | Select-Object -Unique)) {
            # OUT OF THE ROUTE GROUPS FIRST, AND UNCONDITIONALLY, as
            # verify-routes.ps1 does: an account left locked out of its own
            # console destroys the evidence of which half broke.
            foreach ($g in @('sdsshonly', 'sdssh', 'sdapi')) {
                if (InGroup $g $x) {
                    try { Remove-LocalGroupMember -Group $g -Member $x -ErrorAction Stop
                          Write-Host "   took $x out of $g" } catch { }
                }
            }
            if (HasUser $x) { Remove-LocalUser -Name $x; Write-Host "   removed Windows account $x" }
            $d = UserDir $x
            if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue }
            if (HasGrp ('sdu_' + $x)) { Remove-LocalGroup -Name ('sdu_' + $x) }
            $prof = Join-Path $env:SystemDrive ('Users\' + $x)
            if (Test-Path -LiteralPath $prof) { Remove-Item -LiteralPath $prof -Recurse -Force -ErrorAction SilentlyContinue }
        }

        foreach ($g in ($madeGroups | Select-Object -Unique)) {
            if (HasGrp $g) { Remove-LocalGroup -Name $g; Write-Host "   removed group $g" }
        }
        $gd = GrpDir $grpAcc
        if (Test-Path -LiteralPath $gd) { Remove-Item -LiteralPath $gd -Recurse -Force -ErrorAction SilentlyContinue }

        Write-Host '   ACCOUNTS records left in place - remove with DELETE.ACCOUNT'
    } else {
        Write-Host ''
        Write-Host ("-Keep: " + (($madeUsers + $madeGroups) -join ', ') + " are still there.") -ForegroundColor Yellow
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
    Write-Host 'verify-accountrules: FAILED' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

Write-Host ''
Write-Host ('verify-accountrules: the keyword is required, the password is mandatory and unwinds, ' +
            'a GROUP account has neither, and ADOPT needs the marker.') -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
