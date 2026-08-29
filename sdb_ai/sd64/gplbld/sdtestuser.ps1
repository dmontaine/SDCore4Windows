# sdtestuser.ps1 - a throwaway NON-ADMINISTRATOR account, and a way to run SD as it
#
# Dot-sourced, not run.  PRE_RELEASE_FIXES 59.
#
# WHY THIS EXISTS.  Five unelevated verifiers - lcnames, osusers, nocase,
# lineendings, batchjob - meant "run sd as an ordinary user", and that only
# ever worked because the owner is an administrator WITH an ordinary account.
# PRE_RELEASE 56 abolished that combination: an administrator is elevated at
# LOGIN and lands in SDSYS, so those verifiers found SDSYS's BP where they
# expected the account's and every one of them refused the null case rather
# than scoring a false pass (-Run b59, 29 Aug 2026).
#
# ***THE FIX IS NOT A PATH CHANGE, AND THE OBVIOUS SHORTCUT IS A TRAP.***
# Adding "LOGTO DON" to each verifier would make them pass today and break
# again the moment adopt-account goes - which is ruled and pending, 56's last
# piece.  An account that exists only because the installer adopted the
# installing user is not something to build five tests on.
#
# WHY ssh AND NOT runas / Start-Process -Credential.  Accounts SD creates are
# in sdsshonly, which carries SeDenyInteractiveLogonRight (5.6.2) - so an
# interactive logon as one is refused BY WINDOWS, and that refusal is the
# product working.  ssh is the door these accounts have, and sshd's
# ForceCommand starts SD, so the remote "command" is decoration and stdin
# carries the SD lines.  Copied in shape from verify-doors.ps1, which is green.
#
# ***ONE ACCOUNT FOR THE WHOLE UNELEVATED HALF, AND THAT IS THE POINT.***
# Creating it needs elevation, so it costs a UAC prompt; five verifiers each
# making their own would cost five.  VerifyInstall1 makes it once before the
# step list and removes it after - CLAUDE.md's rule, "pursue it by removing the
# need for a prompt, not by skipping the step".
#
# THE ACCOUNT IS STANDARD TIER, DELIBERATELY, and the create line says so by
# SAYING NOTHING: 'STANDARD' is not a keyword, it is the default (CREATEA:272),
# and only PROGRAMMER and ADMINISTRATOR are keywords.  Naming it would pass an
# unrecognised token.  Standard is also the tier these verifiers want - the
# least-privileged thing that can hold an account.

Set-StrictMode -Version Latest

# The safe alphabet, and the reason is not aesthetic: SSH_ASKPASS is a cmd.exe
# batch file, and cmd eats %, &, ^, | and friends.  Kept identical to
# verify-doors-admin.ps1 so the two fail together if it is ever wrong.  The
# '-Aa9' suffix guarantees the character classes a complexity policy asks for
# whatever the random draw gives.
$script:SdTestAlphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'

function New-SdTestPassword {
    <#  Generate one, then MEASURE that it survives the mechanism that would
        mangle it, before anything is created.  A rule nothing tests is how
        verify-doors-admin's first version passed review and then ate a
        character; this runs before CREATE.ACCOUNT so a failure costs nothing
        and leaves no account behind.  #>
    $bytes = New-Object byte[] 20
    ([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $pw = (-join ($bytes | ForEach-Object { $script:SdTestAlphabet[$_ % $script:SdTestAlphabet.Length] })) + '-Aa9'

    $probeDir = Join-Path $env:TEMP ('sd-testuser-pwcheck-' + $PID)
    if (-not (Test-Path -LiteralPath $probeDir)) {
        New-Item -ItemType Directory -Path $probeDir | Out-Null
    }
    $probeCmd = Join-Path $probeDir 'askpass.cmd'
    Set-Content -Path $probeCmd -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
    $env:SDPROBEPW = $pw
    $echoed = ''
    try {
        $echoed = ((& cmd.exe /c $probeCmd) -join '')
    } finally {
        Remove-Item Env:\SDPROBEPW -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $probeDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    # -cne, case SENSITIVE.  A password differing only in case would pass -ne.
    if ($echoed -cne $pw) {
        throw ("sdtestuser: the generated password does not survive the askpass batch " +
               "(generated $($pw.Length) characters, cmd echoed back $($echoed.Length)). " +
               "ssh would be handed a password that is not the account's.")
    }
    return $pw
}

# Start-Process keeps stdout and stderr in separate files and hands back a real
# exit code.  Under ErrorActionPreference Stop an ErrorRecord from a native exe
# is TERMINATING, and ssh writes "Warning: Permanently added ..." to stderr ON
# SUCCESS - so a naive call dies on a successful connection.  Stdin comes from
# a file so anything that prompts gets EOF rather than hanging.
function Invoke-SdTestNative {
    param([string]$Exe, [string[]]$CmdArgs, [string]$StdIn = '', [string]$WorkDir)
    $so = Join-Path $WorkDir 'native.out'
    $se = Join-Path $WorkDir 'native.err'
    $si = Join-Path $WorkDir 'native.in'
    if ($StdIn -eq '') { Set-Content -Path $si -Value $null -Encoding ascii }
    else { [IO.File]::WriteAllText($si, $StdIn) }
    $p = Start-Process -FilePath $Exe -ArgumentList $CmdArgs -NoNewWindow -Wait -PassThru `
             -RedirectStandardOutput $so -RedirectStandardError $se -RedirectStandardInput $si
    # An empty Get-Content is $null, and a [string] cast does not make it '' -
    # .Trim() on it throws, ON THE SUCCESS PATH, which is the worst place.
    $outTxt = ''
    $errTxt = ''
    if (Test-Path $so) { $o = (Get-Content $so); if ($null -ne $o) { $outTxt = (($o) -join "`n").Trim() } }
    if (Test-Path $se) { $e = (Get-Content $se); if ($null -ne $e) { $errTxt = (($e) -join "`n").Trim() } }
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $outTxt; Err = $errTxt }
}

function Invoke-SdAsTestUser {
    <#  Run SD commands as the test account, over ssh.  $Commands are SD lines;
        'OFF' is appended so the session ends rather than waiting on stdin.

        THE ARGUMENT IS 'whoami' AND THAT IS NOT A MISTAKE.  sshd's
        ForceCommand starts SD whatever is asked for, so the remote command is
        decoration and stdin is the real input.  #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Password,
        # NOT Mandatory, DELIBERATELY, and this is not laxity.  Mandatory makes
        # PowerShell's parameter BINDER reject an empty array before this body
        # runs, so the refusal below would be dead code and the caller would get
        # "Cannot bind argument ... because it is an empty array" - which says
        # nothing about why an empty list is wrong.  Caught 29 Aug 2026 by the
        # unit test passing for the binder's reason instead of this one, which
        # is the "test that passes because it did nothing" the instrument rule
        # forbids.  The guard below is the refusal; it must be reachable.
        [string[]]$Commands = @(),
        [string]$WorkDir = ''
    )

    # REFUSE THE NULL CASE, OUT LOUD.  An empty command list would open a
    # session, send nothing and come back "successful" - a measurement of
    # nothing that reads like a pass.
    if ($null -eq $Commands -or $Commands.Count -eq 0) {
        throw 'Invoke-SdAsTestUser: no SD commands given; that would open a session, measure nothing and look like a pass.'
    }

    $sshExe = Get-Command ssh.exe -ErrorAction SilentlyContinue
    if ($null -eq $sshExe) {
        throw 'Invoke-SdAsTestUser: no ssh.exe on PATH; the test account can only be reached over ssh.'
    }

    if ($WorkDir -eq '') { $WorkDir = Join-Path $env:TEMP ('sd-testuser-' + $PID) }
    if (-not (Test-Path -LiteralPath $WorkDir)) {
        New-Item -ItemType Directory -Path $WorkDir | Out-Null
    }
    $askpass = Join-Path $WorkDir 'askpass.cmd'

    # TERM first: without it the session negotiates a size that wraps output,
    # and a wrapped line is counted twice by anything grepping for it -
    # PRE_RELEASE 40, which cost a wrong verdict.
    $body = "`n" + ((@('TERM 200,9999') + $Commands + @('OFF')) -join "`n") + "`n"

    $sshCommon = @('-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=NUL',
                   '-o', 'ConnectTimeout=20', '-o', 'LogLevel=ERROR',
                   '-o', 'PreferredAuthentications=password',
                   '-o', 'NumberOfPasswordPrompts=1')

    # The password lives in an environment variable of THIS process only, and
    # the askpass file is written and deleted around the call.
    $env:SDPROBEPW = $Password
    Set-Content -Path $askpass -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
    $env:SSH_ASKPASS = $askpass
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $env:DISPLAY = 'localhost:0'
    try {
        $r = Invoke-SdTestNative $sshExe.Source ($sshCommon + @(($Name + '@localhost'), 'whoami')) `
                 -StdIn $body -WorkDir $WorkDir
        # Strip the ANSI the terminal emits, the way every other verifier does.
        $r.Out = ($r.Out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '')
        return $r
    } finally {
        Remove-Item Env:\SSH_ASKPASS, Env:\SSH_ASKPASS_REQUIRE, Env:\DISPLAY, Env:\SDPROBEPW `
                    -ErrorAction SilentlyContinue
        Remove-Item $askpass -ErrorAction SilentlyContinue
    }
}

function Get-SdTestUserHome {
    <#  Where the account's files are, for the verifiers that work on the
        filesystem side rather than through SD.  Derived, not guessed: the
        installer's DataDir is {commonappdata}\SD and CREATE.ACCOUNT puts user
        accounts under user_accounts\<name>, lower case (5.12).  #>
    param([Parameter(Mandatory = $true)][string]$Name)
    return (Join-Path $env:ProgramData ('SD\user_accounts\' + $Name.ToLower()))
}

function New-SdTestUserScript {
    <#  The SD lines an ELEVATED session runs to create the account.  Returned
        rather than executed, so the caller can hand them to whatever elevated
        child it already has and so a unit test can check them without an
        install, an elevation or an account.

        CREATE.ACCOUNT PROMPTS FOR THE WINDOWS PASSWORD TWICE and takes it from
        stdin, which is why the password appears as two bare lines after the
        command rather than as an argument.

        NO TIER KEYWORD: 'STANDARD' is the default and is NOT a keyword
        (CREATEA:272), so naming it would pass an unrecognised token.
        SSH is the route - the account needs no API access to be driven here. #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Password
    )
    return @(('CREATE.ACCOUNT USER ' + $Name + ' SSH'), $Password, $Password)
}

function Remove-SdTestUserScript {
    <#  The SD lines an ELEVATED session runs to take it away again.  Same
        reasoning as New-SdTestUserScript: returned, not executed.

        ***THERE IS NO NO.QUERY ON DELETE.ACCOUNT, AND ASSUMING ONE WOULD HANG
        THE SUITE.***  Checked in DELACC rather than guessed: the syntax is
        "DELETE.ACCOUNT account.name" and "one confirmation covers all of it".
        A NO.QUERY would be an unrecognised token AND the prompt would still
        fire - which is PRE_RELEASE 14 exactly, where "delete.file ... no.query"
        was issued down a pipe, hit a prompt, ATE THE FOLLOWING COMMANDS AS
        ANSWERS and hung, costing a session and an elevated sd -cleanup.

        The prompt is "input yn" in a loop "until yn = 'Y' or yn = 'N'"
        (DELACC:249), so a blank line does not escape it - it spins.  Y is
        therefore a required line, not a convenience. #>
    param([Parameter(Mandatory = $true)][string]$Name)
    return @(('DELETE.ACCOUNT ' + $Name), 'Y')
}
