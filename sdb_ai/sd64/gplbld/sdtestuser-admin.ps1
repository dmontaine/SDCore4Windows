# sdtestuser-admin.ps1 - the ELEVATED half: make or remove the test account
#
# PRE_RELEASE_FIXES 59.  Raised by VerifyInstall1.ps1 through
# Start-Process -Verb RunAs, which is where the UAC prompt appears.
#
# WHY A SEPARATE FILE.  CREATE.ACCOUNT and DELETE.ACCOUNT are gated on
# K$ADMINISTRATOR, and VerifyInstall1 MUST STAY UNELEVATED - several of its
# measurements are only valid there, and an elevated parent cannot make an
# ordinary child, because "runas /trustlevel" yields a RESTRICTED token rather
# than this user's own (S4.0.1).  So the parent stays ordinary and raises this.
# The same shape as verify-doors-admin.ps1, which is green.
#
# ***THE PASSWORD ARRIVES AS AN ARGUMENT, AND THAT IS THE REVIEWED CHOICE
# RATHER THAN THE LAZY ONE.***  verify-doors-suite.ps1 does the same, for the
# reason recorded there: the UNELEVATED parent needs the same password
# afterwards to drive ssh, and scraping it out of an elevated child's stdout
# would mean redirecting that output to a file - the one copy nobody deletes.
# Passing it in keeps the value in the parent, where it was made.  A command
# line is visible to this user's own processes; a file on disk outlives them.
#
# IT PRINTS WHAT IT DID.  The instrument rule applies to setup as much as to a
# test: the account name, the verb, and SD's own answer, so a run that created
# nothing cannot be read as a run that created something.  THE PASSWORD IS
# NEVER PRINTED and never logged.
#
# ***AND SINCE 29 Aug 2026 Create DOES A SECOND THING: IT GRANTS THE INVOKING
# USER MODIFY ON THE ACCOUNT DIRECTORY.***  Not tidiness - without it the
# unelevated parent cannot reach the account at all, and all four verifiers
# this exists for plant their probes through the file system.  Measured, and
# the reasoning is at the grant itself.  It is on a throwaway account, it
# reaches nothing else, and -Action Remove takes the directory with it.

param(
    [Parameter(Mandatory = $true)][ValidateSet('Create', 'Remove')][string]$Action,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Password = '',
    [string]$LogFile = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

function Say([string]$m) {
    Write-Output $m
    if ($LogFile -ne '') {
        try { Add-Content -LiteralPath $LogFile -Value $m } catch { }
    }
}

$elevated = ([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# REFUSE THE NULL CASE.  Unelevated, CREATE.ACCOUNT is refused and this would
# report a failure that looks like SD saying no rather than like the child
# never having been elevated.  The two need telling apart.
if (-not $elevated) {
    Say 'sdtestuser-admin: NOT ELEVATED - refusing. CREATE.ACCOUNT needs K$ADMINISTRATOR.'
    exit 2
}

if ($Action -eq 'Create' -and $Password -eq '') {
    Say 'sdtestuser-admin: Create needs -Password; CREATE.ACCOUNT prompts for it twice.'
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path -LiteralPath $sdExe)) {
    Say ('sdtestuser-admin: no sd.exe at ' + $sdExe)
    exit 2
}

if ($Action -eq 'Create') {
    $lines = New-SdTestUserScript -Name $Name -Password $Password
} else {
    $lines = Remove-SdTestUserScript -Name $Name
}

# ***THE BEFORE HALF, TAKEN BEFORE ANYTHING RUNS.***  Without it the check
# after cannot tell "Create made this" from "this was already here", and a
# stale account from an earlier run would score a confident pass while the
# password in the parent's hand did not match it - every ssh leg would then
# fail for a reason nobody would look for here.
$acctRecPre = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Name.ToUpper())
$recBefore  = Test-Path -LiteralPath $acctRecPre
$winBefore  = $false
try { $null = Get-LocalUser -Name $Name -ErrorAction Stop; $winBefore = $true } catch { $winBefore = $false }

# THE NAME IS SINGLE-USE, and this is where that is enforced rather than
# assumed.  An ssh sign-in leaves a profile directory DELETE.ACCOUNT cannot
# remove while its hive is mounted, and Windows then gives a rebuilt account a
# SUFFIXED home - PRE_RELEASE 35/36.  So a Create onto an existing name is
# refused outright instead of being made to work.
if ($Action -eq 'Create' -and ($recBefore -or $winBefore)) {
    Say ('sdtestuser-admin: ' + $Name + ' ALREADY EXISTS (record=' + $recBefore +
         ', windows=' + $winBefore + ').')
    Say '  The name is single-use - an ssh sign-in leaves a profile Windows will not'
    Say '  reuse, so a rebuilt account gets a suffixed home.  Use a fresh -Run token.'
    exit 2
}

Say ('sdtestuser-admin: ' + $Action + ' ' + $Name)
Say ('  sd.exe: ' + $sdExe)
foreach ($l in $lines) {
    if ($Password -ne '' -and $l -ceq $Password) { Say '    <password, redacted>' }
    else { Say ('    ' + $l) }
}

# ***INPUT TO sd.exe MUST BE PIPED. A FILE HANDLE IS REFUSED, AND THE FIRST
# VERSION OF THIS FILE USED ONE.***  Measured on -Run b60, 29 Aug 2026: SD
# printed its banner, then ":Process terminated", and created nothing.  That is
# sysmsg 5020 at CPROC:473, the K$LOGOUT arm - a forced logout, not a refusal of
# the command, which is why nothing said "CREATE.ACCOUNT" at all.
#
# ***IT WAS ALREADY WRITTEN DOWN, DATED 14 Aug 2026***, in
# verify-createaccount.ps1's header and PROJECT_STATUS.md section 6:
# "Input must be PIPED.  Start-Process -RedirectStandardInput hands SD a file
# handle and SD answers 'Process terminated' and exits, the same way the '<'
# redirect does."  A run was spent rediscovering it.
#
# NOTE THE DISTINCTION, because sdtestuser.ps1 still uses the file form and is
# RIGHT to: Invoke-SdTestNative drives ssh.exe, which takes a file handle
# happily, and SD is at the FAR END of the connection where it sees the ssh
# channel rather than a file.  The rule is about handing sd.exe its own stdin.
#
# LOGTO SDSYS FIRST, matching verify-doors-admin.ps1, verify-tiers.ps1 and
# verify-createaccount.ps1 - every elevated script here that has ever created an
# account carries it, and all of them were green on b59, which is post-56.
# Under PRE_RELEASE 56 an administrator should already land in SDSYS at LOGIN, so this
# ought to be a no-op re-entry; it stays because this is SETUP, and setup that
# quietly depends on a product change is a hidden test of it.
#
# TERM after it, so nothing wraps: a wrapped line is counted twice by anything
# grepping the transcript, which is PRE_RELEASE 40 and cost a wrong verdict.
#
# AND THE LEADING BLANK LINE IS A BOM SINK, not a stray newline.  The pipe
# prepends a BOM to the first line whatever $OutputEncoding says, and SD answers
# that it is not in your VOC; landing it on a line that was empty anyway costs
# one harmless complaint instead of eating a real command.
$body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"

# ***AND A TIMEOUT, WHICH MATTERS MORE HERE THAN IN THE SCRIPT THIS IS COPIED
# FROM.***  This runs in an ELEVATED window raised by Start-Process -Verb RunAs,
# and the unelevated parent is sitting on -Wait.  A prompt nobody answers would
# hang BOTH, with the reason on a console the parent cannot read.  The job form
# turns that into a message.  PRE_RELEASE 14 is the case: a piped answer missing
# its prompt ate the following commands and hung, costing a session and an
# elevated "sd -cleanup".
$timeoutSec = 120
try {
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $timeoutSec) {
        $raw = Receive-Job $job
    } else {
        Stop-Job $job
        $raw = Receive-Job $job
        $raw += ''
        $raw += ("*** SD DID NOT FINISH IN {0}s - it is waiting for input." -f $timeoutSec)
        $raw += '*** Nothing below this line was answered.  Check for a stray sd.exe.'
    }
    Remove-Job $job -Force
    $out = (($raw -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")

    Say '  --- SD said ---'
    foreach ($l in ($out -split "`n")) {
        $t = $l.TrimEnd()
        if ($t -ne '') { Say ('  | ' + $t) }
    }

    # ***CHECK THE ARTEFACT, NOT THE WORDING.***  This first matched SD's output
    # for words like "created", and that was wrong twice over.  Message 6011 is
    # "Account NOT created", so a bare "created" matches the FAILURE; and the
    # success wording guessed at (6055/6056, "User %1 created") is not printed
    # by CREATEA at all - it was invented, which is worse than no anchor.
    #
    # verify-doors-admin.ps1 is the reviewed precedent and it parses nothing:
    # it asks whether the ACCOUNTS record and the Windows user EXIST.  That is
    # also what the instrument rule actually wants - "the state it compared,
    # BEFORE and AFTER" - and it cannot be fooled by an echoed command line.
    $acctRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Name.ToUpper())
    $recNow  = Test-Path -LiteralPath $acctRec
    $winNow  = $false
    try { $null = Get-LocalUser -Name $Name -ErrorAction Stop; $winNow = $true } catch { $winNow = $false }

    Say ('  ACCOUNTS record ' + $acctRec)
    Say ('    before=' + $recBefore + '  after=' + $recNow)
    Say ('  Windows user ' + $Name)
    Say ('    before=' + $winBefore + '  after=' + $winNow)

    if ($Action -eq 'Create') {
        # BOTH halves, because either alone is a broken account: a record with
        # no Windows user cannot sign in over ssh, and a Windows user with no
        # record cannot be reached or removed by SD (PRE_RELEASE 39).
        if (-not ($recNow -and $winNow)) {
            Say 'sdtestuser-admin: Create did NOT succeed - read SD''s lines above.'
            exit 1
        }

        # ---------------------------------------------------------------
        # ***AND NOW MAKE THE DIRECTORY REACHABLE BY THE PARENT, WHICH IT IS
        # NOT BY DEFAULT.***  Measured 29 Aug 2026, and it is the fault that
        # would have stopped every converted verifier dead:
        #
        #   C:\ProgramData\SD\user_accounts\SDACCTB59
        #     NT AUTHORITY\SYSTEM        FullControl
        #     BUILTIN\Administrators     FullControl
        #     GITORLI\sdu_sdacctb59      Modify
        #
        # and nothing else.  The unelevated runner is in none of the three -
        # Administrators is present but DENY-ONLY in a UAC-filtered token - so
        # an "ls" of that directory answered "Permission denied" and so did a
        # touch.  All four verifiers plant their probes through the FILE
        # SYSTEM, so they need the parent to be able to write there.
        #
        # ***A GROUP MEMBERSHIP WOULD NOT WORK AND THAT IS WHY THIS IS AN ACE
        # ON THE USER.***  Adding the parent to sdu_<account> changes the
        # machine, not the parent's TOKEN - group membership is fixed at logon.
        # That is PRE_RELEASE 44 exactly: "don is in sdu_sddrb50a ON THE
        # MACHINE and NOT IN HIS TOKEN", which cost a wrong verdict on 28 Aug
        # and is why the door pair had to grow a helper account with a fresh
        # ssh logon.  An ACE naming the USER's SID needs no new token: the user
        # SID is present and enabled in a filtered token.
        #
        # THE GRANT IS ON THE THROWAWAY ACCOUNT ONLY, and it dies with it -
        # -Action Remove deletes the directory, so there is nothing to revoke.
        # It does not touch SDSYS, the system files or any real account, so no
        # measurement about what an ordinary user may reach is affected.
        $me    = [Security.Principal.WindowsIdentity]::GetCurrent()
        $meSid = $me.User
        $acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $Name.ToLower())

        Say ('  account directory ' + $acctDir)
        if (-not (Test-Path -LiteralPath $acctDir)) {
            Say '  BUT IT IS NOT THERE - the record and the Windows user exist and the'
            Say '  directory does not.  Nothing can plant a probe in it.'
            exit 1
        }

        $aclBefore = (Get-Acl -LiteralPath $acctDir).Access |
                     ForEach-Object { $_.IdentityReference.Value + ' ' + $_.FileSystemRights }
        Say '  ACL before:'
        foreach ($a in $aclBefore) { Say ('    ' + $a) }

        # (OI)(CI) so it reaches BP, bp.out, VOC and $hold - the account
        # directory's own three ACEs are inheritable and its children inherit
        # them, measured on user_accounts\don\bp, so this one propagates the
        # same way.
        try {
            $acl = Get-Acl -LiteralPath $acctDir
            $ace = New-Object System.Security.AccessControl.FileSystemAccessRule(
                       $meSid, 'Modify',
                       'ContainerInherit, ObjectInherit', 'None', 'Allow')
            $acl.AddAccessRule($ace)
            Set-Acl -LiteralPath $acctDir -AclObject $acl
        } catch {
            Say ('  GRANT FAILED: ' + $_.Exception.Message)
            exit 1
        }

        $aclAfter = (Get-Acl -LiteralPath $acctDir).Access |
                    ForEach-Object { $_.IdentityReference.Value + ' ' + $_.FileSystemRights }
        Say ('  granted Modify to ' + $me.Name + ' (' + $meSid.Value + ')')
        Say '  ACL after:'
        foreach ($a in $aclAfter) { Say ('    ' + $a) }

        # ***THE CHECK HERE IS THAT THE ACE IS ON THE DIRECTORY, AND THAT IS
        # DELIBERATELY NOT A WRITE.***  A write probe was written here first
        # and taken out again: THIS PROCESS IS ELEVATED, so it writes through
        # BUILTIN\Administrators\FullControl whether the grant landed or not.
        # It would have passed on the failure path - the exact shape 0's
        # "anchor on the success wording" rule forbids, in ACL form - and it
        # would have read like proof.
        #
        # So this asserts the mechanical thing it CAN assert, and the decisive
        # check is the UNELEVATED parent's Assert-SdTestUserHomeWritable, which
        # is the only token that can answer the question being asked.
        # COMPARE SIDs, NOT NAMES, AND TRANSLATE ONE AT A TIME.  Get-Acl
        # TRANSLATES an IdentityReference back to "DOMAIN\name" on read even
        # when the rule was added as a SID, so "-eq $meSid.Value" would compare
        # S-1-5-21-... against GITORLI\don and answer False on the SUCCESS path
        # - a Create that worked, refused.  And Translate THROWS on a SID with
        # no account behind it, which these directories really do carry: the
        # SDACCTB59 measurement above found an orphaned sdu_ SID whose group
        # had been deleted with the account.  Under ErrorActionPreference Stop
        # that would kill the script, so each one is tried on its own.
        $granted = @()
        foreach ($ace in (Get-Acl -LiteralPath $acctDir).Access) {
            if ($ace.AccessControlType -ne 'Allow') { continue }
            try {
                $s = $ace.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value
            } catch { continue }
            if ($s -eq $meSid.Value) { $granted += $ace }
        }
        if ($granted.Count -eq 0) {
            Say ('  THE ACE IS NOT THERE after Set-Acl - nothing on ' + $acctDir +
                 ' names ' + $meSid.Value + '.')
            exit 1
        }
        Say ('  ACE present for ' + $meSid.Value + ': ' + $granted[0].FileSystemRights)
        Say '  (an elevated write here would prove nothing - the parent''s own write is the check)'

        Say 'sdtestuser-admin: Create succeeded - record, Windows user and the parent''s ACE.'
        exit 0
    } else {
        if ((-not $recNow) -and (-not $winNow)) {
            Say 'sdtestuser-admin: Remove succeeded - record and Windows user both gone.'
            exit 0
        }
        Say 'sdtestuser-admin: Remove did NOT fully succeed - something is left behind.'
        exit 1
    }
} finally {
    # ***NOTHING TO CLEAN UP ANY MORE, AND THAT IS THE POINT OF SAYING SO.***
    # This removed a %TEMP% work directory holding in/out/err files - the stdin
    # file being the one that carried the PASSWORD to disk.  The pipe form above
    # keeps the whole body in memory, so there is no file to leak and none to
    # delete.  PRE_RELEASE 47 is the case for not simply deleting this block:
    # every refused run there leaked a temp directory, because the directory was
    # created above the check that refused.
    #
    # THE JOB IS THE THING THAT CAN SURVIVE NOW.  Remove-Job -Force runs on the
    # normal path; this catches a run that died between Start-Job and it.
    Get-Job -ErrorAction SilentlyContinue |
        Where-Object { $_.State -ne 'Completed' } |
        ForEach-Object {
            try { Stop-Job $_ -ErrorAction Stop } catch { }
            try { Remove-Job $_ -Force -ErrorAction Stop } catch { }
        }
}
