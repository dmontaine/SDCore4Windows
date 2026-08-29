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
# ***THE ACCOUNT IS PROGRAMMER TIER, AND THAT IS MEASURED RATHER THAN CHOSEN.
# DO NOT "TIDY" IT BACK TO STANDARD ON LEAST-PRIVILEGE GROUNDS.***
#
# This said STANDARD until 29 Aug 2026, with the reasoning "standard is also the
# tier these verifiers want - the least-privileged thing that can hold an
# account".  That was wrong, and -Run b60 said so in SD's own words:
#
#     :BASIC BP SDNOCASE
#     BASIC is not in your VOC
#     :RUN BP SDNOCASE
#     RUN is not in your VOC
#
# sdsys/newvoc/TIER.OMIT.STANDARD lists the 42 verbs a standard account does not
# get, and 'basic' and 'run' are both on it - as are 'ed', 'edit', 'micro',
# 'create.file', 'copy', 'delete' and 'rename'.  ***ALL FOUR VERIFIERS THIS
# EXISTS FOR COMPILE AND RUN A BASIC PROBE***, so STANDARD cannot host any of
# them.  Read from the record itself, not inferred from the failure.
#
# ***IT IS STILL A REAL NON-ADMINISTRATOR, WHICH IS THE WHOLE POINT OF 59.***
# The tier that matters is ADMINISTRATOR: that is the one LOGIN elevates into
# SDSYS under PRE_RELEASE 56, and it is what these verifiers must not be.
# PROGRAMMER is not it - verify-doors creates its accounts PROGRAMMER for
# exactly this reason and its logto is subject to every ordinary gate.
#
# PROGRAMMER IS A KEYWORD; STANDARD IS NOT.  Only PROGRAMMER and ADMINISTRATOR
# are (CREATEA:272), standard being the default - so naming STANDARD would pass
# an unrecognised token, which is why the line below could not simply be
# corrected by swapping one word for another when it was written.

# ***NO Set-StrictMode HERE, AND THAT IS DELIBERATE - IT WAS HERE AND IT LEAKED.***
# Measured 29 Aug 2026, not assumed: Set-StrictMode applies to the CURRENT scope
# and its children, and dot-sourcing runs in the CALLER's scope - so this file
# was silently turning strict mode on inside VerifyInstall1.ps1 and
# verify-nocase.ps1, neither of which was written under it.  A probe that
# dot-sourced this file went from "undefined variable: allowed" to
# "THREW - RuntimeException" on the line after, and a missing property threw
# PropertyNotFoundException.
#
# THAT WAS NOT THEORETICAL.  VerifyInstall1.ps1's fallback for a missing sd.exe
# reads the uninstall keys with "$_.DisplayName -like 'SD *' -and
# $_.InstallLocation", and uninstall keys routinely carry neither - under strict
# mode that is a terminating error, in the branch whose whole job is to explain
# a broken install in one line rather than twenty-four.
#
# SO EACH FUNCTION SETS IT FOR ITSELF.  A function's scope is a CHILD of its
# caller's, so Set-StrictMode inside one binds that function and escapes
# nowhere.  The strictness is kept exactly where it was wanted - over this
# module's own code - and is not imposed on anything that dot-sources it.

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
    Set-StrictMode -Version Latest
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
    Set-StrictMode -Version Latest
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
    Set-StrictMode -Version Latest

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

    # ***THE WORK DIRECTORY IS REMOVED AGAIN WHEN THIS FUNCTION MADE IT.***
    # Measured 29 Aug 2026: it was not, and %TEMP%\sd-testuser-<pid> was found
    # holding native.in (the SD command lines), native.out (609 bytes of SD's
    # answer) and native.err after a run.  PRE_RELEASE 47 is the same shape.
    # The askpass file was always deleted, so no password was in it - but the
    # commands and the transcript were, once per verifier per run.
    #
    # ONLY WHEN THIS FUNCTION MADE IT.  A caller that passes -WorkDir owns the
    # directory and may want the files kept for a post-mortem; deleting a
    # caller's directory would be a surprise, and one that eats evidence.
    $ownWorkDir = ($WorkDir -eq '')
    if ($ownWorkDir) { $WorkDir = Join-Path $env:TEMP ('sd-testuser-' + $PID) }
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
        # The output has already been read into $r by Invoke-SdTestNative, so
        # there is nothing left in here the caller still needs.
        if ($ownWorkDir) {
            Remove-Item -LiteralPath $WorkDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Get-SdTestUserHome {
    <#  Where the account's files are, for the verifiers that work on the
        filesystem side rather than through SD.  Derived, not guessed: the
        installer's DataDir is {commonappdata}\SD and CREATE.ACCOUNT puts user
        accounts under user_accounts\<name>, lower case (5.12).

        ***THE PATH RESOLVING IS NOT THE SAME AS THE PATH BEING REACHABLE, AND
        WHEN THIS WAS WRITTEN IT WAS NOT.***  Measured 29 Aug 2026 against the
        10:35:46 install: each account directory is PROTECTED and grants Modify
        to SYSTEM, Administrators and ITS OWN sdu_<account> GROUP ONLY.  The
        unelevated parent is in none of those - Administrators is deny-only in
        a filtered token - so an "ls" of SDACCTB59 answered "Permission denied"
        and so did a touch.  All four of the verifiers this module exists for
        plant their probes THROUGH THE FILE SYSTEM (verify-lcnames alone does
        it in nine places), so without a grant this function names a directory
        none of them can use.

        sdtestuser-admin.ps1 -Action Create therefore adds one inheritable ACE
        for the invoking user, and Assert-SdTestUserHomeWritable below is what
        proves it landed rather than assuming it.  #>
    param([Parameter(Mandatory = $true)][string]$Name)
    Set-StrictMode -Version Latest
    return (Join-Path $env:ProgramData ('SD\user_accounts\' + $Name.ToLower()))
}

function Test-SdDirWritable {
    <#  Can THIS process write in $Path.  A real write, a real read-back and a
        real delete - not Get-Acl arithmetic.

        ***THE ACL IS NOT THE CLAIM AND THAT DISTINCTION IS THE WHOLE
        FUNCTION.***  An ACE that is present and an ACE that is effective are
        different things, and only the second is what four verifiers are about
        to rely on.  The read-back is there for the same reason: a write that
        lands somewhere else, or short, is not a write.

        SPLIT OUT FROM THE ASSERT BELOW SO IT CAN BE DRIVEN BOTH WAYS WITHOUT
        AN INSTALL.  The assert resolves a path under ProgramData that a unit
        test cannot create; this takes any directory, so the test can hand it
        one it can write (the positive control, which is the direction the
        reclaim suite got wrong on 28 Aug - "every accepted row handed in
        SYSTEM or Administrators and none handed in what the producer actually
        writes") and one it cannot.

        Returns $true or $false and THROWS NOTHING, so a caller can report.  #>
    param([Parameter(Mandatory = $true)][string]$Path)
    Set-StrictMode -Version Latest

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    $probe = Join-Path $Path ('ZZWRITE-' + $PID + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.tmp')
    $token = 'sdtestuser-writable-' + [guid]::NewGuid().ToString('N')
    $ok = $false
    try {
        [IO.File]::WriteAllText($probe, $token)
        $ok = ([IO.File]::ReadAllText($probe) -ceq $token)
    } catch {
        $ok = $false
    } finally {
        Remove-Item -LiteralPath $probe -Force -ErrorAction SilentlyContinue
    }
    return $ok
}

function Assert-SdTestUserHomeWritable {
    <#  REFUSE THE NULL CASE, ONCE AND LOUDLY.  The grant sdtestuser-admin.ps1
        makes is applied by an ELEVATED CHILD and used by an UNELEVATED PARENT,
        so nothing in the child's own process proves it worked - an elevated
        write goes through Administrators\FullControl either way.  If the grant
        silently did not land, every converted verifier would fail on its own
        probe with its own wording and four different-looking failures would
        have one cause.

        It names the ACL it found when it fails, because "could not write"
        without the ACL is a verdict with no evidence.  #>
    param([Parameter(Mandatory = $true)][string]$Name)
    Set-StrictMode -Version Latest

    $dir = Get-SdTestUserHome -Name $Name
    if (-not (Test-Path -LiteralPath $dir)) {
        throw ("Assert-SdTestUserHomeWritable: $dir does not exist. " +
               'CREATE.ACCOUNT did not make it, or the name is wrong.')
    }

    if (-not (Test-SdDirWritable -Path $dir)) {
        $acl = '      (could not be read either)'
        try {
            $acl = ((Get-Acl -LiteralPath $dir).Access |
                    ForEach-Object { '      ' + $_.IdentityReference + ' ' + $_.FileSystemRights }) -join "`n"
        } catch { }
        throw ("Assert-SdTestUserHomeWritable: cannot write inside $dir." +
               "`n  An account directory grants Modify to SYSTEM, Administrators and sdu_$Name" +
               "`n  ONLY, and an unelevated token has none of the three - Administrators is" +
               "`n  present but DENY-ONLY in a filtered token.  sdtestuser-admin.ps1 -Action" +
               "`n  Create adds an ACE for the invoking user; it did not land.  The ACL now:`n" + $acl)
    }
    return $dir
}

function New-SdTestUserScript {
    <#  The SD lines an ELEVATED session runs to create the account.  Returned
        rather than executed, so the caller can hand them to whatever elevated
        child it already has and so a unit test can check them without an
        install, an elevation or an account.

        CREATE.ACCOUNT PROMPTS FOR THE WINDOWS PASSWORD TWICE and takes it from
        stdin, which is why the password appears as two bare lines after the
        command rather than as an argument.

        PROGRAMMER, because STANDARD does not get 'basic' or 'run' and all four
        verifiers compile a probe - the header above has the measurement.  Never
        STANDARD, which is the default and is NOT a keyword (CREATEA:272), so
        naming it would pass an unrecognised token.

        SSH is the route - the account needs no API access to be driven here. #>
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Password
    )
    Set-StrictMode -Version Latest
    return @(('CREATE.ACCOUNT USER ' + $Name + ' PROGRAMMER SSH'), $Password, $Password)
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
    Set-StrictMode -Version Latest
    return @(('DELETE.ACCOUNT ' + $Name), 'Y')
}
