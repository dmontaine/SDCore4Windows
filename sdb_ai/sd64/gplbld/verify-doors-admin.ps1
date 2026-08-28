# verify-doors-admin.ps1 - the ELEVATED half of the SUSPENDED door test.
# PRE_RELEASE 19's last row and PRE_RELEASE 38.  It builds the fixture, moves it
# between states, and takes it away again; it measures no door itself.
#
#   powershell -File verify-doors-admin.ps1 -Prefix sddr1 -Phase Create
#   powershell -File verify-doors-admin.ps1 -Prefix sddr1 -Phase Suspend
#   powershell -File verify-doors-admin.ps1 -Prefix sddr1 -Phase Remove
#
# Exit 0 the phase did what it says, 1 it did not, 2 it could not be run.
#
# ***WHY A PAIR, AND WHY FIVE COMMANDS.***  The three doors refuse a SUSPENDED
# account, and proving that needs a CONTROLLED PAIR ON ONE ACCOUNT: the same
# account, the same password, the same commands, admitted before the suspension
# and refused after it.  Anything less proves only that a door can say no.
#
# ***AND THE TWO HALVES CANNOT BE ONE SCRIPT, BECAUSE THEY NEED OPPOSITE
# TOKENS.***  CREATE.ACCOUNT and MODIFY.ACCOUNT are gated on K$ADMINISTRATOR,
# which is seeded from IsElevated() at process start - so the fixture needs an
# elevated process.  But `logto` reaches its suspension test only AFTER
# CPROC:3729's elevated bypass, so an elevated session ENTERS a suspended
# account and a door test written there would report the design working as a
# fault.  ***THE MEASURING HALF MUST BE UNELEVATED, AND IT REFUSES TO RUN
# OTHERWISE.***  That is the same split, and the same reason, as
# VerifyInstall1 / VerifyInstall2.
#
# THE ORDER, AND EACH PHASE PRINTS THE NEXT COMMAND:
#
#   1  -Phase Create    elevated    build the account, permit the caller into it
#   2  verify-doors.ps1 -Phase Control   UNELEVATED   all three doors ADMIT
#   3  -Phase Suspend   elevated    the one variable changes
#   4  verify-doors.ps1 -Phase Refused   UNELEVATED   all three doors REFUSE
#   5  -Phase Remove    elevated    take it away, and read the disk back
#
# ***THE CALLER IS ADDED TO THE ACCOUNT'S GROUP AT Create, AND THAT IS NOT
# CONVENIENCE.***  Without it `logto` is refused for a reason that has nothing
# to do with suspension - "User not allowed in requested account" - and the
# refusal in step 4 would prove nothing, because it would also have happened in
# step 2.  Adding the caller makes the suspension THE ONLY THING THAT CHANGES
# between the two legs.
#
# IT DOES NOT TOUCH sd.conf.  APIPORT was measured ON and listening on this
# host (4243, 28 Aug 2026), so the API door is reachable as the machine stands.
# verify-tierapi.ps1 turns the port on and restores it; that is a bigger
# footprint than this needs, and a verifier that restarts SD to measure a
# refusal has changed the thing it is measuring.  If the port is not answering,
# Create SAYS SO and the measuring half records that door SKIP.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [Parameter(Mandatory = $true)] [ValidateSet('Create', 'Suspend', 'Remove')] [string] $Phase,

    # -Phase Create only.  Empty means "generate one", which is the hand-run
    # path: the phase prints it and the person carries it to the unelevated
    # legs.  verify-doors-suite.ps1 supplies one instead, because it is the
    # UNELEVATED parent and cannot read this elevated child's stdout without
    # writing it to a file.  Checked against the askpass mechanism either way.
    [string] $Password = '',

    [int] $Port = 4243
)

$ErrorActionPreference = 'Stop'

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys = Join-Path $env:ProgramData  'SD\sdsys'
$accts = Join-Path $sdsys 'accounts'
$me    = $env:USERNAME

$results = New-Object System.Collections.ArrayList
$fatal   = $false
$lastSD  = ''

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check    = $step
        Expected = $expected
        Observed = $got
        Result   = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $step, $expected, $got)
}

# 24 Aug 26 - THE VERDICT LINE.  Kept BYTE-FOR-BYTE IDENTICAL to the other
# copies; test-verdict-units.ps1 asserts that across all of them.
function Write-Verdict($name) {
    $all      = @($script:results)
    $decisive = @($all | Where-Object { $_.Decisive -eq 'yes' })
    $failed   = @($decisive | Where-Object { $_.Result -ne 'PASS' })

    Write-Output ""
    if ($decisive.Count -eq 0) {
        Write-Output ("{0}: FAILED - NO DECISIVE CHECK RAN, so this run proves nothing." -f $name)
        Write-Output ("  {0} row(s) recorded, none of them decisive." -f $all.Count)
        $script:fatal = $true
        return
    }
    if ($failed.Count -gt 0) {
        Write-Output ("{0}: FAILED - {1} of {2} decisive checks failed:" -f $name, $failed.Count, $decisive.Count)
        $failed | ForEach-Object { Write-Output ("    " + $_.Check) }
        $script:fatal = $true
        return
    }
    Write-Output ("{0}: PASSED - {1} of {1} decisive checks passed, {2} row(s) in all." -f
                  $name, $decisive.Count, $all.Count)
}

function Test-Say([string]$text, [string]$pattern) {
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return ([regex]::IsMatch($text, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline))
}

# MODIFYA's refusals name the account as readily as its successes do.
$tierBad = @('Unable to change the tier', 'is already', 'cannot suspend',
             'no record of the tier', 'is a group account')
function Get-Said([string]$text, [string]$good) {
    if (-not (Test-Say $text $good)) { return 'not said' }
    foreach ($b in $tierBad) { if (Test-Say $text ([regex]::Escape($b))) { return ('refused: ' + $b) } }
    return 'said'
}

function Get-AccountField($name, $ix) {
    $rec = Join-Path $accts $name.ToUpper()
    if (-not (Test-Path -LiteralPath $rec)) { return '<no ACCOUNTS record>' }
    $f = Get-Content -LiteralPath $rec
    if ($f.Count -lt ($ix + 1)) { return '<blank>' }
    if ([string]::IsNullOrEmpty($f[$ix])) { return '<blank>' }
    return $f[$ix]
}
function Get-AccountTier($name)      { return (Get-AccountField $name 4) }
function Get-AccountPriorTier($name) { return (Get-AccountField $name 5) }

function Test-WinUser([string]$name) {
    try { $null = Get-LocalUser -Name $name -ErrorAction Stop; return $true } catch { return $false }
}

# COPIED FROM probe-catprivate.ps1:144 UNCHANGED - one string with LF
# separators, TERM to stop pagination, OFF to end it, and a timeout that says
# so rather than returning empty.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 90) {
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** Stop-Process the sdwind PID it names."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

function Show-SD([string]$title, [string[]]$commands, [string[]]$secrets) {
    Write-Output ("  --- SD session: " + $title + " ---")
    foreach ($c in $commands) {
        $shown = $c
        foreach ($s in $secrets) {
            if ($s -ne '' -and $shown -eq $s) { $shown = '<password, ' + $s.Length + ' characters>' }
        }
        Write-Output ("    > " + $shown)
    }
    $out = Invoke-SD $commands
    Write-Output '    --- SD said: ---'
    foreach ($line in ($out -split "`n")) { Write-Output ("    | " + $line.TrimEnd()) }
    Write-Output ''
    $script:lastSD = $out
}

# ------------------------------------------------------------- preconditions

if ($Prefix -cnotmatch '^[a-z][a-z0-9_]{1,8}$') {
    Write-Output "verify-doors-admin: -Prefix is '$Prefix'."
    Write-Output '  Lower case letters, digits and underscore only, starting with a letter,'
    Write-Output '  2 to 9 characters - CREATEA downcases the name and the sdu_ group takes it'
    Write-Output '  verbatim, so a mixed-case prefix would not match its own group.'
    exit 2
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-doors-admin: this needs an ELEVATED PowerShell and this one is not.'
    Write-Output '  CREATE.ACCOUNT and MODIFY.ACCOUNT are gated on K$ADMINISTRATOR, seeded from'
    Write-Output '  IsElevated() at process start.  The MEASURING half is the opposite - it'
    Write-Output '  refuses to run elevated - and that is the whole reason these are two files.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1') -Quiet | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-doors-admin: the installed tree does not match source - run a cycle first.'
    exit 2
}

Add-Type -AssemblyName System.Web

$acct    = $Prefix + 'a'
$acctU   = $acct.ToUpper()
$measure = Join-Path $PSScriptRoot 'verify-doors.ps1'

Write-Output ("verify-doors-admin: as {0}, ELEVATED, -Phase {1}" -f $id.Name, $Phase)
Write-Output ("  account {0}" -f $acct)
Write-Output ("  caller  {0}   (added to the account's group so logto is permitted)" -f $me)
Write-Output ''

# ===========================================================================
if ($Phase -eq 'Create') {

    $taken = @()
    if (Test-WinUser $acct)                                       { $taken += 'Windows account' }
    if (Test-Path -LiteralPath (Join-Path $accts $acctU))          { $taken += 'SD ACCOUNTS record' }
    if (Test-Path -LiteralPath (Join-Path $env:SystemDrive ('Users\' + $acct))) { $taken += 'profile directory' }
    if ($taken.Count -gt 0) {
        Write-Output ("verify-doors-admin: " + $acct + " already exists as: " + ($taken -join ', '))
        Write-Output '  Use a fresh prefix.'
        exit 2
    }

    # ***THE CALLER MUST BE IN sdusers OR THE CONTROL LEG IS UNTESTABLE.***
    # MODIFY.ACCOUNT ADD refuses a user who is not (10020), logto would then be
    # refused in BOTH legs, and the refusal in step 4 would prove nothing.
    $inSdusers = $false
    try {
        $inSdusers = @(Get-LocalGroupMember -Group 'sdusers' -ErrorAction Stop |
                       Where-Object { $_.Name -match ('\\' + [regex]::Escape($me) + '$') }).Count -gt 0
    } catch { }
    if (-not $inSdusers) {
        Write-Output ("verify-doors-admin: {0} is not a member of sdusers." -f $me)
        Write-Output '  MODIFY.ACCOUNT ADD would refuse (10020), logto would then be refused in'
        Write-Output '  BOTH legs, and the refusal after the suspension would prove nothing.'
        Write-Output '  Add the account to sdusers first, or run this as a user who is in it.'
        exit 2
    }

    $tcp = Test-NetConnection -ComputerName 127.0.0.1 -Port $Port -WarningAction SilentlyContinue -InformationLevel Quiet
    if (-not $tcp) {
        Write-Output ("  WARNING: nothing is listening on 127.0.0.1:{0}, so the API door will" -f $Port)
        Write-Output '  be recorded SKIP rather than measured.  APIPORT in sd.conf turns it on;'
        Write-Output '  this script deliberately does not, because a verifier that restarts SD'
        Write-Output '  to measure a refusal has changed the thing it is measuring.'
        Write-Output ''
    }

    # ***THE ALPHABET IS NOT A STYLE CHOICE, AND THIS COST A Create PHASE.***
    # 28 Aug 2026: the first version used GeneratePassword(24, 6), copied from
    # verify-tiers.ps1 and verify-acctmsgs.ps1 - neither of which sends a
    # password through ssh.  This one does, and SSH_ASKPASS is a cmd.exe batch
    # doing "echo %SDPROBEPW%".  ***cmd EXPANDS THE VARIABLE AND THEN PARSES THE
    # RESULT***, so a "^" in the value is cmd's escape character and is EATEN.
    #
    # MEASURED, not reasoned: 'a);uoYHY90^;w%kkm[K}q]co' went in at 24
    # characters and came out at 23, as 'a);uoYHY90;w%kkm[K}q]co'.  ssh would
    # then be handed a password that is not the account's, the LOGIN door would
    # be refused in the CONTROL leg, and the run would stop having measured
    # nothing - for a reason with no connection to suspension at all.
    #
    # ***AND THE ANSWER WAS ALREADY IN THE TREE.***  verify-createaccount.ps1:403
    # carries this exact alphabet with the comment "nothing cmd.exe treats
    # specially, because it passes through the askpass helper", and
    # verify-sshonly.ps1 uses the same one.  Kept identical to theirs on purpose:
    # three files now depend on the same property and should fail together if it
    # is ever wrong.  The '-Aa9' suffix guarantees the character classes a
    # complexity policy asks for, whatever the random draw gives.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    if ($Password -ne '') {
        # 28 Aug 2026 - THE ORCHESTRATOR SUPPLIES IT so nothing has to be parsed
        # back out of an elevated child's stdout.  verify-doors-suite.ps1 runs
        # this phase as an elevated child and then needs the same password in
        # the UNELEVATED parent for the Control and Refused legs; scraping it
        # from the child's output would mean redirecting that output to a file,
        # which is the one copy nobody deletes.  Passing it IN keeps the value
        # in the parent, where it was made.
        #
        # THE ALPHABET CHECK BELOW STILL RUNS ON IT.  A supplied password is
        # checked against the askpass mechanism exactly as a generated one is -
        # it is the caller's alphabet that would be wrong, and the whole point
        # of that check is that it measures rather than trusts.
        $pw = $Password
    } else {
        $bytes = New-Object byte[] 20
        ([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
        $pw = (-join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })) + '-Aa9'
    }

    # ***AND THE ALPHABET IS CHECKED RATHER THAN TRUSTED, BEFORE ANYTHING IS
    # CREATED.***  The comment above explains why the safe alphabet is used; this
    # measures that it worked, against the very mechanism that mangles it.  A
    # rule nothing tests is how the first version passed review in my head and
    # then ate a character.  It runs BEFORE CREATE.ACCOUNT so a failure costs
    # nothing and leaves no account behind.
    $probeDir = Join-Path $env:TEMP 'sd-doors-pwcheck'
    if (-not (Test-Path -LiteralPath $probeDir)) { New-Item -ItemType Directory -Path $probeDir | Out-Null }
    $probeCmd = Join-Path $probeDir 'askpass.cmd'
    Set-Content -Path $probeCmd -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
    $env:SDPROBEPW = $pw
    $echoed = ''
    try { $echoed = ((& cmd.exe /c $probeCmd) -join '') } finally {
        Remove-Item Env:\SDPROBEPW -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    Note 'the password survives the askpass batch byte for byte' $true ($echoed -ceq $pw) $true
    if ($echoed -cne $pw) {
        Write-Output ''
        Write-Output ("  The generated password is {0} characters and cmd.exe echoed back {1}." -f
                      $pw.Length, $echoed.Length)
        Write-Output '  ssh would be handed a password that is not the account''s, the LOGIN door'
        Write-Output '  would be refused in the CONTROL leg, and the run would stop having'
        Write-Output '  measured nothing.  Nothing has been created.  This is a defect in the'
        Write-Output '  alphabet above, not on the machine - see verify-createaccount.ps1:403.'
        Write-Verdict 'verify-doors-admin'
        exit 2
    }

    Show-SD 'create the account' @(
        ('CREATE.ACCOUNT USER ' + $acct + ' PROGRAMMER BOTH'), $pw, $pw) @($pw)

    Note 'the ACCOUNTS record exists' $true (Test-Path -LiteralPath (Join-Path $accts $acctU)) $true
    if (-not (Test-Path -LiteralPath (Join-Path $accts $acctU))) {
        Write-Output '  Nothing was created, so there is no fixture.  That is "could not be run".'
        Write-Verdict 'verify-doors-admin'
        exit 2
    }
    Note 'ACC$TIER is PROGRAMMER' 'PROGRAMMER' (Get-AccountTier $acct) $true
    Note 'the Windows account exists' $true (Test-WinUser $acct) $true

    # ***THE API DOOR NEEDS AN SD PASSWORD AND CREATE.ACCOUNT DOES NOT SET ONE.***
    # Measured 28 Aug 2026, the FIRST run of this pair: the CONTROL leg admitted
    # ssh and logto and sd-connect answered "Invalid username or password", with
    # sddr1a already in sdapi, sdssh and sdusers - so APISRVR:1362's group door
    # was open and the refusal was a credential, not a route.  The two doors
    # authenticate against DIFFERENT stores: CREATE.ACCOUNT prompts for the
    # WINDOWS password, which is what sshd checks, while the API does SCRAM
    # against a PBKDF2 verifier in sdsys\$cred that ONLY MODIFY.PASSWORD writes.
    # verify-apiidentity.ps1:446 has always done this and is why it could reach
    # the API at all; this file was written without it and could never have
    # passed its own Control leg.  The product side is PRE_RELEASE 42.
    #
    # ONE STRING FOR BOTH so the measuring half keeps a single -Password.  They
    # remain separate credentials - this sets them to the same value, it does
    # not merge them.
    Show-SD 'set the SD password the API authenticates against' @(
        ('MODIFY.PASSWORD ' + $acctU), $pw, $pw) @($pw)
    # ANCHOR ON THE SUCCESS WORDING, CASE-SENSITIVELY.  SET_ACC_PASSWORD:252
    # prints "Password set for account X"; :153 prints "has no password set" on
    # a path that has NOT set one, so a match on "Password set" alone would be
    # the false positive this project keeps paying for.
    Note 'MODIFY.PASSWORD set the SD password' $true `
         (Test-Say $lastSD 'Password set for account') $true
    # THE DISQUALIFIERS, from the same file: :167/:226/:241 "Password not
    # changed.", :238 "Passwords do not match.", :255 "Unable to set password".
    Note 'MODIFY.PASSWORD was not refused' $false `
         (Test-Say $lastSD 'Password not changed|Passwords do not match|Unable to set password') $true
    if (-not (Test-Say $lastSD 'Password set for account')) {
        Write-Output '  The account exists but has no SD password, so the API door can never be'
        Write-Output '  ADMITTED in the Control leg and the pair would measure nothing.  Take the'
        Write-Output '  fixture away with -Phase Remove before trying again.'
        Write-Verdict 'verify-doors-admin'
        exit 2
    }

    Show-SD 'permit the caller into it' @(('MODIFY.ACCOUNT ' + $acctU + ' ADD ' + $me)) @()
    Note ('10018: ' + $me + ' added to the group') $true `
         (Test-Say $lastSD ([regex]::Escape($me) + ' added to group')) $true
    Note 'it did NOT refuse for sdusers membership (10020)' $false `
         (Test-Say $lastSD 'is not a member of sdusers') $true

    Write-Output ''
    Write-Output '==========================================================================='
    Write-Output ('  ACCOUNT : ' + $acct)
    if ($Password -ne '') {
        # ***THE PASSWORD IS NOT PRINTED WHEN IT WAS SUPPLIED, AND THAT IS THE
        # POINT OF THE BRANCH.***  verify-doors-suite.ps1 runs this phase as an
        # elevated child and CAPTURES its output to a transcript so the run can
        # be read afterwards - and a transcript is a file.  Printing the
        # password here would put it on disk, which is exactly what the
        # hand-run path below refuses to do.  The caller already has it.
        Write-Output '  PASSWORD: supplied by the caller - not printed, because a caller that'
        Write-Output '            passes one is capturing this output to a transcript.'
        Write-Output ''
        Write-Output '  The orchestrator drives the remaining phases; no command is printed.'
    } else {
        Write-Output ('  PASSWORD: ' + $pw)
        Write-Output '  It is a throwaway on an account -Phase Remove deletes.  It is printed'
        Write-Output '  here and written nowhere: the measuring half needs it for the ssh and'
        Write-Output '  API doors, and putting it in a file would be the one copy nobody deletes.'
        Write-Output ''
        Write-Output '  NEXT - in an ORDINARY, UNELEVATED PowerShell:'
        Write-Output ''
        Write-Output ('    ' + $measure + ' -Prefix ' + $Prefix + " -Password '" + $pw + "' -Phase Control")
        Write-Output ''
        Write-Output '  It must report all three doors ADMITTED.  If any is refused, stop - the'
        Write-Output '  refusals after the suspension would prove nothing.'
    }
    Write-Output '==========================================================================='
}

# ===========================================================================
if ($Phase -eq 'Suspend') {

    if (-not (Test-Path -LiteralPath (Join-Path $accts $acctU))) {
        Write-Output ("verify-doors-admin: no ACCOUNTS record for {0} - run -Phase Create first." -f $acctU)
        exit 2
    }
    Note 'before: ACC$TIER is PROGRAMMER' 'PROGRAMMER' (Get-AccountTier $acct) $true

    Show-SD 'suspend' @(('MODIFY.ACCOUNT ' + $acctU + ' SUSPENDED')) @()

    Note 'suspend says 10109 "Account X is now SUSPENDED"' 'said' `
         (Get-Said $lastSD ('Account\s+' + [regex]::Escape($acctU) + '\s+is now\s+SUSPENDED')) $true
    Note 'after: ACC$TIER is SUSPENDED' 'SUSPENDED' (Get-AccountTier $acct) $true
    # Field 6 is what makes the round trip lossless, and it is also the proof
    # that the suspension went through tier.set rather than being typed in.
    Note 'ACC$PRIOR.TIER kept the tier it displaced' 'PROGRAMMER' (Get-AccountPriorTier $acct) $true

    # ***THE WINDOWS SIDE MUST NOT HAVE MOVED.***  MODIFYA:98 - "SUSPENDED
    # denies access and changes nothing else".  If the account had been dropped
    # from sdssh, the ssh door would refuse for a reason that is not the one
    # under test, and step 4 would score a false pass.
    $inSsh = $false
    try {
        $inSsh = @(Get-LocalGroupMember -Group 'sdssh' -ErrorAction Stop |
                   Where-Object { $_.Name -match ('\\' + [regex]::Escape($acct) + '$') }).Count -gt 0
    } catch { }
    Note 'still in sdssh - the suspension changed no group' $true $inSsh $true

    Write-Output ''
    Write-Output '==========================================================================='
    Write-Output '  NEXT - in an ORDINARY, UNELEVATED PowerShell, same password as before:'
    Write-Output ''
    Write-Output ('    ' + $measure + ' -Prefix ' + $Prefix + " -Password '<the one printed at Create>' -Phase Refused")
    Write-Output ''
    Write-Output '  It must report all three doors REFUSED, and ssh and logto must say so in'
    Write-Output "  SD's own words - 10107, 'is suspended'."
    Write-Output '==========================================================================='
}

# ===========================================================================
if ($Phase -eq 'Remove') {

    if (-not (Test-Path -LiteralPath (Join-Path $accts $acctU))) {
        Write-Output ("  no ACCOUNTS record for {0} - nothing to remove." -f $acctU)
    } else {
        Show-SD 'delete the account' @(('DELETE.ACCOUNT ' + $acct), 'Y') @()
    }

    Note 'the Windows account is gone' $false (Test-WinUser $acct) $true
    Note 'the ACCOUNTS record is gone' $false `
         (Test-Path -LiteralPath (Join-Path $accts $acctU)) $true

    # Read from disk, not from what DELETE.ACCOUNT said - PRE_RELEASE 41.
    $litter = @()
    $d = Join-Path $env:SystemDrive ('Users\' + $acct)
    if (Test-Path -LiteralPath $d) { $litter += $d }
    foreach ($g in @('sdu_' + $acct)) {
        if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { $litter += ('group ' + $g) }
    }
    if ($litter.Count -gt 0) {
        Write-Output '  *** LEFT BEHIND - read from disk, not from what the delete reported:'
        $litter | ForEach-Object { Write-Output ('      ' + $_) }
        Write-Output '  This account DID sign in over ssh, so a profile directory here is'
        Write-Output '  PRE_RELEASE 35/36 and expected until that is built.'
    } else {
        Write-Output ('  nothing left behind for ' + $acct)
    }
}

Write-Output ''
$results | Format-Table -AutoSize -Wrap | Out-String | Write-Output
Write-Verdict 'verify-doors-admin'

if ($fatal) { exit 1 }
exit 0
