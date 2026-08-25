# finish-install.ps1 - the two things that happen after the installer closes.
#
#   powershell -File finish-install.ps1 -AppDir "C:\Program Files\SD" -WithPassword
#
# ONE WINDOW, TWO STEPS, IN ORDER.  Owner's instruction, 22 Aug 2026: "put them
# both in one script, call sd for the password and then move on to the post
# validation".
#
#   1. SD opens so you can give your account a password.  It closes ITSELF once
#      the password is set - MODIFY.PASSWORD is passed as a single command, so
#      SD runs it and exits without the user doing anything.
#
#      CHANGED 24 Aug 2026, AND THE OLD FORM IS WHY.  It used to pass "off" and
#      rely on LOGIN's require.credential prompting on the way IN, with "off"
#      then ending the session.  That made the password a SIDE EFFECT of
#      logging in, and step 9's ruling - a command line is batch, so it must
#      not prompt - removed the prompt and this step silently stopped asking.
#      Asking is now what the command DOES, so nothing about logging in can
#      take it away again.
#   2. The installation check runs, in this same window, and a keypress closes
#      the window at the end.
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

    # Whose account.  Passed by Setup as {username}; the default is for a hand
    # run.  24 Aug 2026 - IT IS NOW ALSO THE ARGUMENT TO MODIFY.PASSWORD, not
    # only the name looked for in $cred afterwards, so a wrong value no longer
    # just weakens a check: it would set the password on the wrong account, or
    # be refused with "Account %1 not in register" (SET_ACC_PASSWORD:124).
    [string] $User = $env:USERNAME,

    # Passed straight through to check-install.ps1.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'

if ($AppDir -eq '') { $AppDir = Join-Path $env:ProgramFiles 'SD' }
$SdExe = Join-Path $AppDir 'usr\bin\sd.exe'
$Check = Join-Path $AppDir 'check-install.ps1'

# The data tree is not a choice - DataDir is #defined as {commonappdata}\SD in
# sd.iss, with no wizard page - so this is a constant rather than a guess.
$SysDir = Join-Path (Join-Path $env:ProgramData 'SD') 'sdsys'

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
    Write-Host '  Starting SD now.  It closes by itself once the password is set,'
    Write-Host '  and the check follows automatically.' -ForegroundColor Cyan
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
        #
        # MODIFY.PASSWORD IS THE COMMAND, AND ASKING IS WHAT IT DOES.  Owner's
        # decision, 24 Aug 2026.  SD runs a single command and exits when one is
        # given (sd.c:645), so the session still ends without the user - owner,
        # 22 Aug 2026: "the paragraph that runs the password entry should be
        # able to log out without the user having to do it."
        #
        # ***IT REPLACED "off", AND THE REASON IS A REGRESSION THIS STEP
        # ACTUALLY SUFFERED.***  Passing "off" relied on LOGIN's
        # require.credential prompting on the way IN, with "off" then ending the
        # session - so the password was a SIDE EFFECT of logging in.  Section 7
        # step 9's ruling (a command line is batch, so it must not prompt) took
        # that prompt away, and this step stopped asking with no error at all.
        # The wizard completed and the account had no password.  Asking is now
        # the command's own job, so no future change to how LOGIN treats a
        # command line can remove it again.
        #
        # WHY NOT -INTERNAL, which was the first idea: sd.c:589-594 forces
        # -INTERNAL to the SDSYS account and refuses any other, so it would set
        # SDSYS's password rather than this user's, silently.
        #
        # THE ACCOUNT IS PASSED AS ITS OWN ARGUMENT, not glued into a string.
        # sd.c joins argv from the first non-switch onward into single_command
        # (sd.c:681-695), so three elements arrive as "MODIFY.PASSWORD <user>".
        # Case does not matter - SET_ACC_PASSWORD:80 does account = upcase(token).
        #
        # IT NEEDS THE ELEVATED TOKEN, and has it, twice over: sd.c calls
        # check_admin() before accepting a command line at all, and
        # SET_ACC_PASSWORD:113 refuses an account other than your own without
        # K$ADMINISTRATOR.  This runs on Setup's token.
        #
        # DECLINING STILL WORKS, and now says so itself: an empty password makes
        # SET_ACC_PASSWORD:176 print "Password not changed." and stop.  The
        # message stays readable because this is OUR console, not one that
        # vanishes with the process.
        #
        # A FRESH ACCOUNT IS THE EXPECTED CASE AND IS HANDLED: :152 prints
        # "has no password set.  Setting the first one", and :159 skips the
        # current-password prompt when there is no credential to check against.
        try {
            $p = Start-Process -FilePath $SdExe `
                    -ArgumentList '-QUIET','MODIFY.PASSWORD',$User `
                    -NoNewWindow -Wait -PassThru -ErrorAction Stop
            Write-Host ''

            # DID A PASSWORD ACTUALLY GET SET?  ***KEEP THIS CHECK. IT IS THE
            # ONE THAT CAUGHT THE 24 Aug 2026 REGRESSION*** - and the comment
            # that used to sit here had PREDICTED that regression in as many
            # words, while this step still passed "off": "if the prompt never
            # appears... off runs immediately, SD exits, and the user is never
            # asked".  That is exactly what happened when LOGIN stopped
            # prompting for a command line, and without this check the user
            # would have found out weeks later, the first time they tried to
            # reach the account from another machine.
            #
            # The failure mode is narrower now - MODIFY.PASSWORD asks for
            # itself, so it cannot be silently skipped by a login-path change -
            # but the check costs nothing and covers the whole class: a verb
            # that was refused, a session that never started, a $cred that was
            # not writable.
            #
            # IT IS ALSO THE DECLINE CASE, and the same sentence serves both:
            # pressing Enter on an empty password is a legitimate answer that
            # leaves no credential.  Neither is an error, so this is a note and
            # not a failure - it says what is true and how to put it right.
            #
            # THE STORE IS READABLE HERE AND NOWHERE ELSE.  SecureCredStore has
            # locked $cred to SYSTEM and Administrators, so this test works only
            # because this script is elevated - the same token the password step
            # needs.  A missing directory means the ACL or the install is wrong,
            # which is check-install's business below, not this one's; silence
            # is the right answer here.
            $credRec = Join-Path (Join-Path $SysDir '$cred') $User
            if ((Test-Path -LiteralPath (Join-Path $SysDir '$cred')) -and
                (-not (Test-Path -LiteralPath $credRec))) {
                Write-Host '  No password was set for your SD account.' -ForegroundColor Yellow
                Write-Host '  That is fine at this machine - Windows has already authenticated' -ForegroundColor Yellow
                Write-Host '  you - but the account cannot be reached over ssh or the API until' -ForegroundColor Yellow
                Write-Host '  one is set.  SD asks again the first time you open the account.' -ForegroundColor Yellow
                Write-Host ''
            }
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
