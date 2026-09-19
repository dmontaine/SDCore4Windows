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
# success.  RELEASE_1.1 64 removed the adopted account: the one account is
# SDSYS, whose password install-sdsys.ps1 generates and prints into its own log
# before the wizard closes.  No session is opened here any more, so nothing sets
# a password and nothing has one to verify.  PRE_RELEASE_FIXES 138 (why it ran
# twice, and why no verifier can exercise a credential prompt) and 155 (the
# page's margins and wrap width) are where that reasoning lives.

Write-Host ''
Write-Host '  SD is installed.' -ForegroundColor White
Write-Host '  ================'
Write-Host ''

# 18 Sep 26 - WHAT THIS WINDOW SAYS NOW THAT THE PASSWORD STEP HAS GONE.  It is
# the same news the installer's closing dialog carries, at the point where the
# person is still looking at an install window rather than at a wizard.
#
# IT DOES NOT PRINT THE PASSWORD AND MUST NOT.  install-sdsys.ps1 prints it once,
# into a log only SYSTEM and Administrators can read, and the log is the record.
#
# AND IT IS WRITTEN FOR BOTH CASES WITHOUT KNOWING WHICH ONE THIS IS.
# install-sdsys.ps1 prints the password only when it MADE the account - on a
# machine that already had SDSYS it leaves the account alone and prints nothing -
# so "if this install made that account" is the honest qualifier rather than a
# hedge.  Write-Wrapped is used for it deliberately: this is the page's own text,
# and gplbld/test-wraptext-units.ps1 lifts the function out of this file.
Write-Wrapped -Text ('SD Core is installed.  Its one account is SDSYS, and that is the account ' +
    'that can create the others: sign in as SDSYS and start SD Core from an ELEVATED prompt.  ' +
    'If this install made that account, its Windows password is printed at the end of ' +
    'install-sdsys.log in the SD data directory.')
Write-Host ''

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
