# finish-install.ps1 - the one thing that happens after the installer closes.
#
#   powershell -ExecutionPolicy Bypass -File finish-install.ps1 -AppDir "C:\Program Files\SD"
#
# ONE WINDOW, ONE STEP.  Owner's instruction, 22 Aug 2026: "put them both in one
# script, call sd for the password and then move on to the post validation".
#
#   18 Sep 26 - HALF OF THAT WENT, RELEASE_1.1 64, AND THIS FILE IS THE HALF.  It
#   used to do two things and now does one: the installation check.  Step 1
#   opened SD at the end of an install so somebody could give their account a
#   password, and it existed for the account the installer had just adopted out
#   of the installing Windows administrator.  Nobody is adopted now; the one
#   account is SDSYS, and it authenticates with its WINDOWS password, which
#   install-sdsys.ps1 generates and prints into install-sdsys.log BEFORE the
#   wizard closes.  There is nothing for SD to ask for on the way in, so no
#   session is opened and no password is collected here.
#
#   THE STEP'S HISTORY STAYS WHERE IT IS USED - sd.iss, at the call site, and
#   PRE_RELEASE_FIXES 138 and 155: 138 is why it ran TWICE (an administrator had
#   two SD accounts and the install set one), 155 is the page's formatting.
#
#   THE CHECK runs in this same window, and a keypress closes the window at the
#   end.
#
# WHY ONE SCRIPT RATHER THAN TWO THINGS SETUP LAUNCHES.  Setup had been opening
# the password session from ssPostInstall - while the wizard was still on screen
# - and offering the check as a tickbox on the Finished page.  That produced two
# faults the owner met on a real install: the wizard sat open behind the SD
# window, and the check asked "shall I?" TWICE, once as the tickbox and once in
# the script.  Sequencing them here removes both: Setup launches this and exits,
# the tickbox is gone, and the only question left is the one the check asks.
#
# WHY IT IS ELEVATED, AND WHAT THAT COSTS.  The check runs on SETUP's token, and
# that is the only reason this script is elevated: the password step needed the
# same token and its reasoning is a gravestone in sd.iss - an unelevated token
# does not carry sdusers until the user signs out and back in, so it cannot open
# the data tree, and SecureCredStore had locked $cred to SYSTEM and
# Administrators.
#
# THAT IS A REAL TRADE rather than a free one: an administrator token reads the
# data tree through the Administrators ACE, so "you can reach the database" is
# answered about the wrong token.  check-install.ps1 detects this and says so,
# twice - in a banner and again beside the answer it affects - and the Start Menu
# shortcut is the run that answers it properly, once the user has signed out and
# back in.
#
# IT IS A NET GAIN AT INSTALL TIME, which is why this is acceptable rather than
# merely tolerable.  Unelevated, the catalogue check - the one thing this whole
# check exists for, after the 16 Aug 2026 install that shipped an empty
# catalogue - CANNOT RUN AT ALL on the installing user's token, because the tree
# is unreadable until they sign out.  Elevated, it runs.  A labelled answer
# beats a deferred one.

[CmdletBinding()]
param(
    # Where SD is installed.  PASSED BY SETUP, not defaulted from $PSScriptRoot:
    # that default comes out EMPTY in an advanced script's param block, which is
    # the fault adopt-account.ps1 records costing a real install.
    [string] $AppDir = '',

    # 18 Sep 26 - -WithPassword AND -User ARE BOTH GONE, RELEASE_1.1 64.  The
    # switch chose between collecting a credential and not; nothing collects one
    # here any more.  -User named WHOSE credential and was then the account name
    # looked for in $cred - which is why its default from $env:USERNAME was
    # called out as dangerous: a wrong value sets the password on the wrong
    # account.  Nothing reads either name now, so Setup passes neither, and a
    # future step that needs to know who is installing should be handed it
    # explicitly rather than defaulting it.

    # WHAT SETUP DID WITH THE SDSYS ACCOUNT - install-sdsys.ps1's own exit code,
    # passed through by RunFinishingStep: 0 it MADE the account, 2 it was already
    # there, 1 or 3 it could not.  -1 is the default and means NOBODY TOLD US - a
    # hand run of this script - and the prompt below is then skipped rather than
    # guessed at, because offering to set the password of an account this run
    # knows nothing about is how you overwrite a working one.
    [int] $SdsysCode = -1,

    # Passed straight through to check-install.ps1.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'

if ($AppDir -eq '') { $AppDir = Join-Path $env:ProgramFiles 'SD' }
$Check = Join-Path $AppDir 'check-install.ps1'

# 18 Sep 26 - $SdExe AND $SysDir WENT WITH THE PASSWORD STEP, RELEASE_1.1 64.
# $SdExe was the sd.exe that step started; $SysDir was the data tree, read for
# one question only - did a credential appear in $cred.  Nothing left here reads
# either, and the 42-line block that stood below this point went with them: it
# was PRE_RELEASE_FIXES 138's reasoning for a step that ran twice, over an
# account model (an administrator has TWO SD accounts) that RELEASE_1.1 64
# deleted.  It is in that entry, and in sd.iss's gravestone at the call site.

# 4 Sep 26 - PRE_RELEASE_FIXES 155.  ONE WRAP WIDTH FOR EVERYTHING THIS SCRIPT
# SAYS, because it had three.  The banner below is hand-wrapped at about 72; the
# $Purpose strings were handed to Write-Host as ONE LINE EACH and wrapped at
# whatever the console happened to be, which on the owner's screen broke "its"
# across two lines mid-word.
#
# 74 IS CHOSEN AGAINST THE SMALL SCREEN, NOT THE BIG ONE.  Entry 150 is the
# neighbouring lesson - a dialog sized to the machine that built it and clipped
# on 1024x768 - and a console here is 80 columns until somebody widens it.
function Write-Wrapped {
    param(
        [string] $Text,
        [string] $Indent = '',
        [int]    $Width  = 74,
        [System.ConsoleColor] $Color
    )
    # ***IT KEEPS THE GAPS, AND THE FIRST VERSION DID NOT.***  This file writes
    # two spaces after a full stop, and "Change it with  modify.password sdsys
    # from inside SD." sets its command off with two on each side.  A wrapper
    # built on -split '\s+' collapses every one of those to a single space -
    # a formatting regression introduced by the fix for a formatting complaint.
    # So each word carries the whitespace that FOLLOWED it, that gap is used
    # when the next word lands on the same line, and it is discarded at a line
    # break, which is where a gap should disappear anyway.
    $limit   = $Width - $Indent.Length
    $line    = ''
    $pending = ''
    $out     = @()
    foreach ($m in [regex]::Matches($Text, '\S+[ \t]*')) {
        $word = $m.Value.TrimEnd(" `t")
        $gap  = $m.Value.Substring($word.Length)
        if ($line -eq '') {
            $line = $word
        } elseif (($line.Length + $pending.Length + $word.Length) -le $limit) {
            $line = $line + $pending + $word
        } else {
            $out += $line
            $line = $word
        }
        $pending = $gap
    }
    if ($line -ne '') { $out += $line }
    # ***A CALLER THAT PASSED NOTHING MUST NOT SILENTLY PRINT NOTHING.***  An
    # empty $Purpose would leave the step with no explanation and look
    # deliberate; say so instead.
    if ($out.Count -eq 0) { $out = @('(no text supplied)') }
    foreach ($l in $out) {
        if ($PSBoundParameters.ContainsKey('Color')) {
            Write-Host ($Indent + $l) -ForegroundColor $Color
        } else {
            Write-Host ($Indent + $l)
        }
    }
}

# 18 Sep 26 - Invoke-PasswordStep STOOD HERE, AND SO DID ITS CALLER BELOW.  It
# started one sd.exe per account with '-QUIET MODIFY.PASSWORD <account>' - that
# is how an install collected a password for the account it had just adopted -
# and then read $cred to prove one had actually been written, because a prompt
# that never appeared would otherwise have been indistinguishable from a
# success.  RELEASE_1.1 64 removed the adopted account, and this window now asks
# for the SDSYS WINDOWS password instead - Set-SdsysPassword below is what
# replaced it.  PRE_RELEASE_FIXES 138 and 155 are where the old step's reasoning
# lives.

function Set-SdsysPassword {
    # ASKS FOR IT, BECAUSE A GENERATED PASSWORD IN A LOG IS NOT A WAY IN.
    # Owner's ruling, 18 Sep 2026, after the first install to use the generated
    # one: "the password for the SDSYS account was never asked for or printed so
    # no way to get in".  install-sdsys.ps1 still generates one - the account
    # needs a password the moment it exists, and that is the path a hand run
    # takes - but it does it in a HIDDEN window (sd.iss's Exec, SW_HIDE), so this
    # is the first place in the whole install where a person can be asked.
    #
    # ***HERE RATHER THAN IN install-sdsys.ps1, AND THAT IS MEASURED RATHER THAN
    # PREFERRED.***  That step runs at ssPostInstall, WHILE THE WIZARD IS STILL
    # ON SCREEN, and a console prompt there is the fault the owner met on 22 Aug
    # 2026 - the wizard sitting open behind a window of ours.  This script runs
    # from DeinitializeSetup, after the wizard has gone, in a window the install
    # already opens.
    #
    # AND IT CANNOT HANG AN INSTALL.  Redirected stdin means nobody is at a
    # console - the same guard check-install.ps1 uses - so the prompt is skipped
    # and the generated password is printed instead.
    param([string] $LogFile)

    Write-Host '  SET THE PASSWORD FOR SDSYS' -ForegroundColor White
    Write-Host ''
    Write-Wrapped -Text ('You sign in to Windows as SDSYS and start SD Core from an elevated ' +
        'prompt, and this account is the only way into SD.  Type the password you want for it.  ' +
        'It is not shown as you type, and you are asked twice.')
    Write-Host ''

    if ([Console]::IsInputRedirected) {
        Write-Wrapped -Text ('Nobody is at this console, so nothing is asked and the generated ' +
            'password stands.')
        Write-Host ''
        Show-GeneratedPassword -LogFile $LogFile
        return
    }

    $tries = 0
    while ($tries -lt 3) {
        $tries++
        $a = Read-Host '  New SDSYS password' -AsSecureString
        if ($a.Length -eq 0) {
            # AN EMPTY LINE IS A DELIBERATE ANSWER rather than a mistake: SD's own
            # credential prompt ends the session on one (130's ruling), and here
            # it means "keep the generated one" - which is then printed, so it is
            # shown rather than hunted for in a file.
            Write-Host ''
            Write-Wrapped -Text ('No password typed, so the one the install generated stands.')
            Write-Host ''
            Show-GeneratedPassword -LogFile $LogFile
            return
        }
        $b = Read-Host '  Type it again' -AsSecureString
        # ***THE TWO ARE COMPARED AS PLAIN TEXT, WHICH IS THE ONLY WAY TWO
        # SecureStrings CAN BE COMPARED AT ALL.***  It is a deliberate, bounded
        # exception: the strings exist in this process for the length of the
        # comparison and are dropped on the next line.  Everything else here
        # keeps them as SecureStrings, including the call that sets the account's
        # password - so nothing is passed as an argument, which is the exposure
        # sd-elevate.ps1 measured (Win32_Process.CommandLine shows it verbatim).
        $pa = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($a))
        $pb = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($b))
        $same = ($pa -ceq $pb)
        $pa = $null; $pb = $null
        if (-not $same) {
            Write-Host '  They did not match.  Try again.' -ForegroundColor Yellow
            Write-Host ''
            continue
        }
        try {
            Set-LocalUser -Name 'SDSYS' -Password $a -ErrorAction Stop
        } catch {
            # A REFUSAL BY THE PASSWORD POLICY IS NOT A FAILED INSTALL.  Windows
            # says why, and saying it here is the difference between a retry and
            # a lockout.
            Write-Host ('  Windows refused that password: ' + $_.Exception.Message) -ForegroundColor Yellow
            Write-Host ''
            continue
        }
        Write-Host '  The SDSYS password is set.' -ForegroundColor Green
        Write-Host ''
        # THE LOG IS THE RECORD OF THIS MACHINE'S WAY IN, so the password it
        # printed a minute ago is not left standing as though it still worked.
        try {
            Add-Content -Path $LogFile -ErrorAction Stop -Value (
                (Get-Date -Format 's') + '  the password printed above was REPLACED by one set in ' +
                'the finishing window.  No copy of it is kept here.')
        } catch {
            Write-Host ('  (Could not note that in ' + $LogFile + ': ' + $_.Exception.Message + ')') -ForegroundColor Yellow
        }
        return
    }

    Write-Host '  Three attempts.  The generated password stands.' -ForegroundColor Yellow
    Write-Host ''
    Show-GeneratedPassword -LogFile $LogFile
}

function Show-GeneratedPassword {
    # READS THE PASSWORD BACK OUT OF THE LOG install-sdsys.ps1 WROTE, and refuses
    # out loud when it cannot find it: an empty answer here would read as "no
    # password exists", which is the one reading worse than none.
    param([string] $LogFile)
    $shown = ''
    try {
        $hit = Select-String -LiteralPath $LogFile -Pattern 'SDSYS WINDOWS PASSWORD' -Context 0, 1 -ErrorAction Stop
        if ($hit) { $shown = (($hit[-1].Context.PostContext) -join ' ').Trim() }
    } catch { }
    if ($shown -eq '') {
        Write-Wrapped -Text ('The generated password could not be read back from ' + $LogFile +
            '.  Open that file yourself: the line after "SDSYS WINDOWS PASSWORD" is the password.')
        Write-Host ''
        return
    }
    Write-Host ('  SDSYS password: ' + $shown) -ForegroundColor Cyan
    Write-Host ''
    Write-Wrapped -Text ('That is the password the install generated.  Change it whenever you ' +
        'wish, from the SDSYS account or from an elevated prompt.')
}

Write-Host ''
Write-Host '  SD is installed.' -ForegroundColor White
Write-Host '  ================'
Write-Host ''

# 18 Sep 26 - WHAT THIS WINDOW SAYS NOW, AND WHY IT SAYS LESS THAN IT DID.  It
# used to describe the account and send the reader to install-sdsys.log for the
# password.  Now it either ASKS for that password or says which case this is.
# Write-Wrapped is used for the text deliberately: these are the page's own
# words, and gplbld/test-wraptext-units.ps1 lifts the function out of this file.
Write-Wrapped -Text ('SD Core is installed.  Its one account is SDSYS, and that is the account ' +
    'that can create the others: sign in as SDSYS and start SD Core from an ELEVATED prompt.')
Write-Host ''

$SdsysLog = Join-Path (Join-Path $env:ProgramData 'SD') 'install-sdsys.log'
switch ($SdsysCode) {
    0 {
        Set-SdsysPassword -LogFile $SdsysLog
    }
    2 {
        Write-Wrapped -Text ('The SDSYS account was already on this machine, so this install left ' +
            'it alone - including its password, which is the one set before.')
        Write-Host ''
    }
    default {
        Write-Wrapped -Text ('No password is set here.  Either the install reported that it could ' +
            'not make the SDSYS account - install-sdsys.log beside the data tree says what ' +
            'happened - or this window is being run by hand, where nothing can be known about ' +
            'that account.  To set one, from an elevated prompt:  Set-LocalUser -Name SDSYS ' +
            '-Password (Read-Host -AsSecureString)')
        Write-Host ''
    }
}

# ---------------------------------------------------------------------------
# AND ON TO THE CHECK.  Called rather than launched: same window, same console,
# and its exit code becomes this script's, so anything reading the result of the
# finishing step gets the check's verdict rather than "the launcher started".
if (-not (Test-Path -LiteralPath $Check)) {
    Write-Host ("  The installation check is missing - expected " + $Check) -ForegroundColor Red
    Write-Host ''
    # PAUSE HERE TOO.  Every other ending is check-install's, which waits for a
    # key of its own; this one returns without ever reaching it.  Since -NoExit
    # went, an unpaused exit closes the window instantly - so the one message
    # that reports a broken install would be the only one nobody could read.
    if (-not [Console]::IsInputRedirected) {
        # ReadKey BLOCKS rather than throwing when there is no console - see the
        # note in check-install.ps1's Finish().  IsInputRedirected is the guard.
        Write-Host '  Press any key to close this window.' -ForegroundColor Cyan
        try   { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
        catch { }
    }
    Write-Host ''
    exit 2
}

& $Check -Yes:$Yes
exit $LASTEXITCODE
