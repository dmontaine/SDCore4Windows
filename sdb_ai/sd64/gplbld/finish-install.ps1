# finish-install.ps1 - the two things that happen after the installer closes.
#
#   powershell -File finish-install.ps1 -AppDir "C:\Program Files\SD" -WithPassword
#
# ONE WINDOW, TWO STEPS, IN ORDER.  Owner's instruction, 22 Aug 2026: "put them
# both in one script, call sd for the password and then move on to the post
# validation".
#
#   1. SD opens so you can give your account a password.  You type OFF to leave.
#   2. The installation check runs, in this same window.
#
# WHY ONE SCRIPT RATHER THAN TWO THINGS SETUP LAUNCHES.  Setup had been opening
# the password session from ssPostInstall - while the wizard was still on screen
# - and offering the check as a tickbox on the Finished page.  That produced two
# faults the owner met on a real install: the wizard sat open behind the SD
# window, and the check asked "shall I?" TWICE, once as the tickbox and once in
# the script.  Sequencing them here removes both: Setup launches this and exits,
# the tickbox is gone, and the only question left is the one the check asks.
#
# WHY IT IS ELEVATED, AND WHAT THAT COSTS.  The password step NEEDS elevation and
# the reasoning is a gravestone in sd.iss: an unelevated token does not carry
# sdusers until the user signs out and back in, so it cannot open the data tree,
# and SecureCredStore has just locked $cred to SYSTEM and Administrators, so
# !CRED_SET could not write the credential either.  Setup's own token carries
# Administrators and both ACLs grant it.
#
# So the check runs elevated too, and THAT IS A REAL TRADE rather than a free
# one: an administrator token reads the data tree through the Administrators
# ACE, so "you can reach the database" is answered about the wrong token.
# check-install.ps1 detects this and says so, twice - in a banner and again
# beside the answer it affects - and the Start Menu shortcut is the run that
# answers it properly, once the user has signed out and back in.
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

    # Only when the installer has just MADE the account.  On a reinstall the
    # account was left alone and keeps whatever password it had, so there is
    # nothing to ask for and SD is not opened at all.
    [switch] $WithPassword,

    # Passed straight through to check-install.ps1.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'

if ($AppDir -eq '') { $AppDir = Join-Path $env:ProgramFiles 'SD' }
$SdExe = Join-Path $AppDir 'usr\bin\sd.exe'
$Check = Join-Path $AppDir 'check-install.ps1'

Write-Host ''
Write-Host '  SD is installed.' -ForegroundColor White
Write-Host '  ================'
Write-Host ''

if ($WithPassword) {
    Write-Host '  Two things are left, and this window does both.'
    Write-Host ''
    Write-Host '    1. SD opens so you can give your account a password.'
    Write-Host '    2. This window then checks that the installation is sound.'
    Write-Host ''
    Write-Host '  Starting SD now.  Type  off  when you have set the password,'
    Write-Host '  and the check will follow automatically.' -ForegroundColor Cyan
    Write-Host ''

    if (-not (Test-Path -LiteralPath $SdExe)) {
        Write-Host ("  SD is not where it should be - expected " + $SdExe) -ForegroundColor Red
        Write-Host '  Skipping the password step.' -ForegroundColor Red
        Write-Host ''
    } else {
        # -NoNewWindow, SO IT IS THIS WINDOW.  The point of one script is one
        # window; a second console would put the two steps side by side and
        # leave the same "which one wants me?" question the tickbox created.
        #
        # -Wait, AND IT IS SAFE HERE IN A WAY IT WAS NOT IN SETUP.  Setup could
        # not wait on this - it would have held the wizard open behind a prompt
        # the user has to know to type OFF at, which is the fault being fixed.
        # Nothing is holding this script open but the user, so waiting is
        # exactly what sequences the two steps.
        #
        # -QUIET suppresses the version and licence banner (CMD_QUIET, sd.c:347,
        # tested at LOGIN:234).  This window has already said what is happening.
        try {
            $p = Start-Process -FilePath $SdExe -ArgumentList '-QUIET' `
                    -NoNewWindow -Wait -PassThru -ErrorAction Stop
            Write-Host ''
            Write-Host ('  SD closed (exit ' + $p.ExitCode + ').') -ForegroundColor DarkGray
        } catch {
            Write-Host ''
            Write-Host ('  SD could not be started: ' + $_.Exception.Message) -ForegroundColor Red
            Write-Host '  You can set the password later by typing  sd  at a command prompt.' -ForegroundColor Red
        }
        Write-Host ''
    }
} else {
    # THE REINSTALL CASE.  Say why there was no password step rather than
    # leaving a reader to wonder what happened to step 1 they were promised.
    Write-Host '  Your SD account was already there and has been left alone, so there'
    Write-Host '  is no password to set.  Checking the installation.'
    Write-Host ''
}

# ---------------------------------------------------------------------------
# AND ON TO THE CHECK.  Called rather than launched: same window, same console,
# and its exit code becomes this script's, so anything reading the result of the
# finishing step gets the check's verdict rather than "the launcher started".
if (-not (Test-Path -LiteralPath $Check)) {
    Write-Host ("  The installation check is missing - expected " + $Check) -ForegroundColor Red
    Write-Host ''
    exit 2
}

& $Check -Yes:$Yes
exit $LASTEXITCODE
