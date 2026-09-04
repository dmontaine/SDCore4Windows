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
#      04 Sep 26 - IT RUNS TWICE, PRE_RELEASE_FIXES 138.  An administrator has
#      TWO SD accounts: their own, which an unelevated "sd" lands in, and
#      SDSYS, which every ELEVATED session lands in (LOGIN:627).  This step set
#      only the first, so the next elevated "sd" asked for a password and the
#      one just given looked ignored.  The owner ruled "set both", and the
#      screen now says there are two accounts before it asks twice.  See the
#      block above Invoke-PasswordStep for the whole of why - including why no
#      verifier can ever exercise the second prompt.
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

# ===========================================================================
# 04 Sep 26 - PRE_RELEASE_FIXES 138.  THE PASSWORD STEP RUNS TWICE, BECAUSE AN
# ADMINISTRATOR HAS TWO ACCOUNTS.
#
# ***WHAT WAS WRONG.***  This step set a credential for the adopted person's
# own account and nothing else, and LOGIN:627 puts every ELEVATED administrator
# into SDSYS - "case kernel(K$ADMINISTRATOR,-1) and kernel(K$OS.ADMINISTRATOR,0)
# and sd_admin_tier(@logname)".  require.credential (LOGIN:1065) then reads
# $cred keyed on initial.account, finds SDSYS has none, and asks.  So the first
# bare "sd" after an install asked for a password again and THE ANSWER JUST
# GIVEN LOOKED IGNORED.  Neither half was broken; they were written eight days
# apart and the second moved where a login lands.  Measured in $cred on the
# guest: DON 18:12:28 (this step) and SDSYS 18:14:31 (the owner, at a prompt he
# should not have needed).
#
# ***THE OWNER RULED SHAPE (b), 2 Sep 2026: SET BOTH.***  (a) set SDSYS's
# instead - rejected, it leaves the unelevated door unset and revives the SDSYS
# password step adopt-account.ps1:46 records was killed by three faults.  (c)
# reword 10089 to name SDSYS as a different account - rejected as fixing the
# confusion and not the missing credential.  (b) is the only option consistent
# with 130's ruling that a password is required.
#
# ***SO THE SCREEN HAS TO SAY THERE ARE TWO ACCOUNTS.***  That is what makes (b)
# honest rather than merely correct: a step that asks twice without saying why
# replaces "the answer was ignored" with "why is it asking again", which is the
# same fault wearing a different hat.
#
# ***NO VERIFIER CAN EVER EXERCISE THIS, AND THAT IS STRUCTURAL.***
# LOGIN:955 guards the credential block on kernel(K$TTY,0) # '', and kernel.c:251
# sets that from ttyname(fileno(stdin)) - so any session whose stdin is a PIPE
# has no tty and skips it.  Every automated route in this project pipes stdin,
# which is what Invoke-SD's script-ending-in-OFF is.  The prompt requires the one
# condition the whole suite is built not to have, so THE SECOND PROMPT MUST BE
# WITNESSED BY A PERSON AT A KEYBOARD.  Do not go looking for the verifier.
#
# ONE FUNCTION, RUN TWICE, rather than two copies of the block: a second copy is
# a second place for the next defect to be fixed in only one, which is the
# argument gpl.bp/EDIT makes for not being two programs.
# ===========================================================================

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

function Invoke-PasswordStep {
    param(
        [string] $Account,   # the SD account to set a password for
        [string] $Which,     # "1 of 2" - so the user can see how far along they are
        [string] $Purpose,   # one line: when this account is the one you reach
        [string] $IfDeclined # what is true if they press Enter and set none
    )

    # 4 Sep 26 - PRE_RELEASE_FIXES 155.  COLUMN 0, AND WRAPPED.
    #
    # THE PAGE HAD TWO LEFT MARGINS AND NEITHER WAS WRONG ON ITS OWN: this
    # script indents what it says by two, and sd.exe's own output - "Account
    # DON has no password set", "New password:" - starts at column 0 and cannot
    # be indented from here.  Inside a step the two are interleaved, so the
    # step's own header now sits at column 0 with the output it introduces.
    # The banner keeps its indent: that is this script narrating, and the
    # distinction is now a rule rather than an accident.
    Write-Host ("Password $Which - $Account") -ForegroundColor White
    Write-Wrapped -Text $Purpose
    Write-Host ''

    # THE ACCOUNT IS PASSED AS ITS OWN ARGUMENT, not glued into a string.
    # sd.c joins argv from the first non-switch onward into single_command
    # (sd.c:681-695), so three elements arrive as "MODIFY.PASSWORD <account>".
    # Case does not matter - SET_ACC_PASSWORD:80 does account = upcase(token).
    #
    # IT NEEDS THE ELEVATED TOKEN, and has it twice over: sd.c calls
    # check_admin() before accepting a command line at all, and
    # SET_ACC_PASSWORD:113 refuses an account other than your own without
    # K$ADMINISTRATOR.  This runs on Setup's token.  Note that under
    # PRE_RELEASE 56's model the elevated session lands in SDSYS, so it is the
    # PERSON'S account that is "other than your own" here - both are permitted
    # either way, and neither depends on which is which.
    try {
        $p = Start-Process -FilePath $SdExe `
                -ArgumentList '-QUIET','MODIFY.PASSWORD',$Account `
                -NoNewWindow -Wait -PassThru -ErrorAction Stop
        $null = $p
        Write-Host ''
    } catch {
        Write-Host ''
        Write-Host ('  SD could not be started: ' + $_.Exception.Message) -ForegroundColor Red
        Write-Host '  You can set the password later by typing  sd  at a command prompt.' -ForegroundColor Red
        Write-Host ''
        return $false
    }

    # DID A PASSWORD ACTUALLY GET SET?  ***KEEP THIS CHECK. IT IS THE ONE THAT
    # CAUGHT THE 24 Aug 2026 REGRESSION*** - and the comment that used to sit
    # here had PREDICTED that regression in as many words, while this step still
    # passed "off": "if the prompt never appears... off runs immediately, SD
    # exits, and the user is never asked".  That is exactly what happened when
    # LOGIN stopped prompting for a command line, and without this check the
    # user would have found out weeks later.
    #
    # The failure mode is narrower now - MODIFY.PASSWORD asks for itself, so it
    # cannot be silently skipped by a login-path change - but the check costs
    # nothing and covers the whole class: a verb that was refused, a session
    # that never started, a $cred that was not writable.
    #
    # IT IS ALSO THE DECLINE CASE, and one sentence serves both: pressing Enter
    # on an empty password is a legitimate answer that leaves no credential.
    # Neither is an error, so this is a note and not a failure.
    #
    # THE STORE IS READABLE HERE AND NOWHERE ELSE.  SecureCredStore has locked
    # $cred to SYSTEM and Administrators, so this test works only because this
    # script is elevated - the same token the password step needs.  A missing
    # directory means the ACL or the install is wrong, which is
    # check-install.ps1's business below, not this one's; silence is the right
    # answer here.
    $credDir = Join-Path $SysDir '$cred'
    if ((Test-Path -LiteralPath $credDir) -and
        (-not (Test-Path -LiteralPath (Join-Path $credDir $Account)))) {
        # 4 Sep 26 - PRE_RELEASE_FIXES 155: column 0 and wrapped, like the
        # header above it.  $IfDeclined is a long single line too.
        Write-Host ("No password was set for $Account.") -ForegroundColor Yellow
        Write-Wrapped -Text $IfDeclined -Color Yellow
        Write-Host ''
        return $false
    }
    return $true
}

Write-Host ''
Write-Host '  SD is installed.' -ForegroundColor White
Write-Host '  ================'
Write-Host ''

if ($WithPassword) {
    # PRE_RELEASE_FIXES 138 - SAY THERE ARE TWO ACCOUNTS BEFORE ASKING TWICE.
    # The whole reason the owner chose "set both" over "set SDSYS instead" is
    # that it is honest about there being two; asking twice without saying so
    # would replace "the answer I gave was ignored" with "why is it asking
    # again", which is the same fault in a different coat.
    Write-Host '  Two things are left, and this window does both.'
    Write-Host ''
    Write-Host '    1. SD opens so you can set a password.  IT ASKS TWICE, and that is'
    Write-Host '       not a fault: as an administrator you have TWO SD accounts.'
    Write-Host ''
    Write-Host ("         {0,-10} where you land when you open SD normally" -f $User)
    Write-Host  '         SDSYS      where you land when you run SD as administrator'
    Write-Host ''
    Write-Host '       They are separate accounts and each needs its own password.'
    Write-Host '       You may give them the same one; SD does not mind either way.'
    Write-Host ''
    Write-Host '    2. This window then checks that the installation is sound.'
    Write-Host ''
    # 4 Sep 26 - PRE_RELEASE_FIXES 155.  SAID HERE, ONCE, FOR BOTH ACCOUNTS.
    #
    # SET_ACC_PASSWORD used to print this itself, which meant twice, because the
    # installer runs it once per account in a separate sd.exe.  It now stays
    # quiet under -QUIET - which this script already passes - so this is the
    # only copy on the page.  It is ABOVE both prompts on purpose: it is the
    # thing you need before you are asked, not after.
    #
    # KEEP THE PHRASE "A password is required".  test-retired-wording-units.ps1
    # registers it as the REPLACEMENT for entry 130's retired claim, so it has
    # to keep appearing somewhere the lint can find it.
    Write-Wrapped -Indent '  ' -Text ('A password is required.  Pressing Enter on an empty line does not ' +
        'give you an account without one - it leaves that account unusable until a password ' +
        'is set: not here at the keyboard, not over ssh, and not through the SD API.  SD asks ' +
        'again the first time you open the account.  This is true of both accounts below.')
    Write-Host ''
    Write-Host '  Starting SD now.  It closes by itself once each password is set,'
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
        # (How the account is passed, and why the elevated token is needed, are
        # in Invoke-PasswordStep above - they belong with the call, not here.)
        #
        # DECLINING STILL WORKS, and now says so itself: an empty password makes
        # SET_ACC_PASSWORD:227 print "Password not changed." and stop.  The
        # message stays readable because this is OUR console, not one that
        # vanishes with the process.
        #
        # 26 Aug 26 - AND MISTYPING IT NO LONGER ENDS THE INSTALL WITH NO
        # PASSWORD.  SET_ACC_PASSWORD gave one attempt at the pair and stopped
        # on a mismatch; this window then moved straight on to the check with
        # the account still passwordless.  It allows three now, and says which
        # one you are on.  An empty entry still leaves at once and is not
        # counted - that is a decision, not a mistake.
        #
        # A FRESH ACCOUNT IS THE EXPECTED CASE AND IS HANDLED: :152 prints
        # "has no password set.  Setting the first one", and :159 skips the
        # current-password prompt when there is no credential to check against.
        # 1 OF 2 - THE PERSON'S OWN ACCOUNT.  First because it is the one the
        # wizard's last page has just told them about, and the one an
        # UNELEVATED "sd" lands in.
        $null = Invoke-PasswordStep -Account $User -Which '1 of 2' `
            -Purpose 'This is where SD puts you when you open it normally, and the password you use over ssh and through the SD API.' `
            -IfDeclined 'That is fine at this machine - Windows has already authenticated you - but the account cannot be reached over ssh or the API until one is set.  SD asks again the first time you open the account.'

        # 2 OF 2 - SDSYS.  PRE_RELEASE_FIXES 138: LOGIN:627 puts every ELEVATED
        # administrator here, and require.credential reads $cred keyed on
        # initial.account, so without this the first elevated "sd" asks for a
        # password and the one just given looks ignored.
        #
        # ***SKIPPED IF SDSYS ALREADY HAS ONE, AND THAT IS NOT SYMMETRY WITH THE
        # STEP ABOVE - IT IS THE KEEP-THE-DATABASE CASE.***  PasswordStepWanted
        # is (AdoptCode = 0), so this runs whenever the installer MADE the
        # person's account - which can happen over a data tree that was kept,
        # and a kept tree keeps $cred.  SET_ACC_PASSWORD:159 skips the
        # current-password prompt only when there is no credential to check
        # against, so asking here would demand the OLD SDSYS password from
        # somebody who came to set a new one.  The step above is deliberately
        # left alone: its behaviour is not this entry's, and changing it would
        # be an unrequested second change riding in on this one.
        $sdsysCred = Join-Path (Join-Path $SysDir '$cred') 'SDSYS'
        if (Test-Path -LiteralPath $sdsysCred) {
            # 4 Sep 26 - PRE_RELEASE_FIXES 155: this branch is a step header
            # like the one Invoke-PasswordStep writes, so it takes the same
            # margin.  It was the only other place printing "Password N of 2".
            Write-Host 'Password 2 of 2 - SDSYS' -ForegroundColor White
            Write-Wrapped -Text ('SDSYS already has a password from a previous install, so it has ' +
                'been left alone.  Change it with  modify.password sdsys  from inside SD.')
            Write-Host ''
        } else {
            $null = Invoke-PasswordStep -Account 'SDSYS' -Which '2 of 2' `
                -Purpose 'This is where SD puts you when you run it as administrator.  It is a different account from the one above and needs its own password.' `
                -IfDeclined 'SD will ask again the first time you run it as administrator, and until then that account cannot be used.'
        }
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
