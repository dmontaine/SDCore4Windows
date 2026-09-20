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

    # 19 Sep 26 - RELEASE_1.1 70.  WHO THE INSTALL ATTACHED, AND HOW IT WENT.
    #
    # -User CAME BACK, UNDER A NAME THAT SAYS WHERE IT COMES FROM.  The note
    # above records why the old one was dangerous - it defaulted from
    # $env:USERNAME, and a wrong value sets the password on the WRONG ACCOUNT -
    # and its own advice is followed here: Setup hands this over explicitly and
    # there is NO DEFAULT.  Empty means nobody said, and nothing is asked.
    [string] $AttachUser = '',

    # attach-account.ps1's exit code, passed through by RunFinishingStep: 0 it
    # MADE the account, 2 it was already there, 1 or 3 it could not.  -1 is the
    # default and means NOBODY TOLD US - a hand run - so the prompt is skipped
    # rather than guessed at, exactly as -SdsysCode is.
    [int] $AttachCode = -1,

    # Passed straight through to check-install.ps1.
    [switch] $Yes
)

$ErrorActionPreference = 'Stop'

if ($AppDir -eq '') { $AppDir = Join-Path $env:ProgramFiles 'SD' }
$Check = Join-Path $AppDir 'check-install.ps1'

# 19 Sep 26 - $SdExe AND $SysDir ARE BACK WITH THE STEP THAT NEEDED THEM,
# RELEASE_1.1 70.  The note below records them leaving with the -WithPassword
# half; they return for the same two jobs and no others - the sd.exe the
# password step starts, and the data tree, read for ONE question: did a
# credential appear in $cred.
$SdExe  = Join-Path $AppDir 'usr\bin\sd.exe'
$SysDir = Join-Path (Join-Path $env:ProgramData 'SD') 'sdsys'

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

# 19 Sep 26 - RELEASE_1.1 75.  SD'S OWN PASSWORD RULE, IN POWERSHELL, BECAUSE
# THIS ONE PROMPT CANNOT REACH THE BASIC THAT HOLDS IT.  Owner's ruling, taken
# on the SD Core for Linux side and binding in both ports: SD requires a complex
# password "even if the OS does not", for SDSYS and for every other account.
#
# ***THE OTHER THREE PROMPTS NEED NO POWERSHELL AT ALL***, which is worth saying
# because it is why this is the only copy: MODIFY.PASSWORD, CREATE.ACCOUNT and
# LOGIN's credential prompt all run through gpl.bp/pw_complex, and the install's
# own SD-password step is "sd -QUIET MODIFY.PASSWORD", so it inherits the check.
# This prompt sets a WINDOWS password with Set-LocalUser and never enters SD.
#
# ***A SECOND IMPLEMENTATION OF A RULE IS A THING THAT DRIFTS***, so it is not
# left to a reader's care: test-pwcomplex-units.py drives THIS function and the
# BASIC's ranges against the same table, and asserts that the sentence below and
# message 10920 say the same thing.
#
# IT IS A FLOOR, NOT A CEILING.  Set-LocalUser still applies the machine's own
# password policy afterwards, and the machine wins wherever it is stricter -
# which on a domain-managed box it may well be.
function Test-PasswordComplex {
    param([string] $Password)
    if ($Password.Length -lt 8) { return $false }
    $lower = $false; $upper = $false; $digit = $false; $symbol = $false
    foreach ($ch in $Password.ToCharArray()) {
        $c = [int][char]$ch
        # THE SYMBOL ARM NAMES ITS OWN RANGE AND THE CATCH-ALL FAILS CLOSED,
        # which is gpl.bp/pw_complex's shape and the Linux port's before that.
        # A character matching nothing is refused however these are ordered;
        # the earlier version tested out-of-range first and let the final else
        # mean "symbol", which fails OPEN the moment anybody reorders it.
        if     ($c -ge 97 -and $c -le 122) { $lower  = $true }
        elseif ($c -ge 65 -and $c -le 90)  { $upper  = $true }
        elseif ($c -ge 48 -and $c -le 57)  { $digit  = $true }
        elseif ($c -ge 32 -and $c -le 126) { $symbol = $true }
        else                               { return $false }
    }
    return ($lower -and $upper -and $digit -and $symbol)
}

# THE WORDING IS MESSAGE 10920's, WORD FOR WORD, and the units test asserts it.
# Two copies exist because this prompt runs outside SD; they must not differ.
$script:PwRuleText = 'A password needs at least 8 characters, with a lower-case letter, an upper-case letter, a digit and a symbol.'

function Set-SdsysPassword {
    # ASKS FOR IT, BECAUSE A GENERATED PASSWORD IN A LOG IS NOT A WAY IN.
    # Owner's ruling, 18 Sep 2026, after the first install to use the generated
    # one: "the password for the SDSYS account was never asked for or printed so
    # no way to get in".  install-sdsys.ps1 still generates one - the account
    # needs a password the moment it exists, and that is the path a hand run
    # takes - but it does it in a HIDDEN window (sd.iss's Exec, SW_HIDE), so this
    # is the first place in the whole install where a person can be asked.
    #
    # ***18 Sep 26, LATER STILL - AND IT ASKS ON "ALREADY THERE" TOO, WHICH IS
    # THE OWNER'S SECOND RULING AND IT REVERSES THIS STEP'S OWN PREMISE.***  The
    # twelfth pass prompted only when the install MADE the account, on the
    # reasoning "a reinstall cannot overwrite a working password" - and the
    # 21:28:44 run measured the hole in that word: install-sdsys.ps1 answered
    # "SDSYS already exists" (code 2) over an account whose generated password
    # was never known to anybody, and install-sdsys.log is OVERWRITTEN per run,
    # so the 17:55:27 password is not recoverable from anywhere.  An existing
    # password is not thereby a working one.  His words, verbatim, because the
    # model is load-bearing: "the only way to administer SD is to login to the
    # computer as the Windows user SDSYS ... Once connected the sdsys windows
    # user is in the sdsys sd account.  No other user has access to the SDSYS
    # account at all and the sdsys windows user only has access if logged in
    # locally, no remote access.  So without an sdsys password being entered at
    # install time there is no way to manage sd."
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
    param([string] $LogFile, [switch] $Existing)

    Write-Host '  SET THE PASSWORD FOR SDSYS' -ForegroundColor White
    Write-Host ''
    if ($Existing) {
        Write-Wrapped -Text ('The SDSYS account was already on this machine, and its password is ' +
            'whatever it already was - which nothing shows and nothing keeps a copy of.  This is ' +
            'the moment to set it: you sign in to Windows as SDSYS and start SD Core from an ' +
            'elevated prompt, and this account is the only way into SD.  Type the password you ' +
            'want for it.  It is not shown as you type, and you are asked twice.')
    } else {
        Write-Wrapped -Text ('You sign in to Windows as SDSYS and start SD Core from an elevated ' +
            'prompt, and this account is the only way into SD.  Type the password you want for it.  ' +
            'It is not shown as you type, and you are asked twice.')
    }
    Write-Host ''
    # THE RULE IS STATED BEFORE THE PROMPT, not only after a refusal - being
    # told the requirement once you have already failed it is how three
    # attempts get spent guessing.  RELEASE_1.1 75.
    Write-Wrapped -Text $script:PwRuleText
    Write-Host ''

    if ([Console]::IsInputRedirected) {
        if ($Existing) { Keep-ExistingPassword } else {
            Write-Wrapped -Text ('Nobody is at this console, so nothing is asked and the generated ' +
                'password stands.')
            Write-Host ''
            Show-GeneratedPassword -LogFile $LogFile
        }
        return
    }

    $tries = 0
    while ($tries -lt 3) {
        $tries++
        $a = Read-Host '  New SDSYS password' -AsSecureString
        if ($a.Length -eq 0) {
            # AN EMPTY LINE IS A DELIBERATE ANSWER rather than a mistake: SD's own
            # credential prompt ends the session on one (130's ruling).  On a
            # fresh account it means "keep the generated one" - which is then
            # printed, so it is shown rather than hunted for in a file.  On an
            # EXISTING account there is nothing generated this run and no copy
            # of the old one anywhere, so keeping is said plainly and with its
            # cure, because "kept a password nobody knows" is the state the
            # owner's ruling exists to end.
            Write-Host ''
            if ($Existing) { Keep-ExistingPassword } else {
                Write-Wrapped -Text ('No password typed, so the one the install generated stands.')
                Write-Host ''
                Show-GeneratedPassword -LogFile $LogFile
            }
            return
        }
        # 19 Sep 26 - RELEASE_1.1 75.  THE RULE IS CHECKED BEFORE THE REPEAT IS
        # ASKED FOR, and this is the one place the plain text is needed twice -
        # so the same bounded SecureString-to-BSTR exception the comparison
        # below documents applies, and the variable is cleared on the next line.
        # A weak entry counts as one of the three attempts, like a mismatch.
        $pw = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($a))
        $weak = -not (Test-PasswordComplex -Password $pw)
        $pw = $null
        if ($weak) {
            Write-Wrapped -Text $script:PwRuleText -Color Yellow
            Write-Host ('  That was attempt ' + $tries + ' of 3.') -ForegroundColor Yellow
            Write-Host ''
            continue
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
        # On -Existing nothing was printed from the log - nothing was generated
        # this run - so there is no line to kill, and the note would say a
        # replacement happened where none was shown.
        if (-not $Existing) {
            try {
                Add-Content -Path $LogFile -ErrorAction Stop -Value (
                    (Get-Date -Format 's') + '  the password printed above was REPLACED by one set in ' +
                    'the finishing window.  No copy of it is kept here.')
            } catch {
                Write-Host ('  (Could not note that in ' + $LogFile + ': ' + $_.Exception.Message + ')') -ForegroundColor Yellow
            }
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

function Keep-ExistingPassword {
    # THE -Existing KEEP PATH, IN ITS OWN FUNCTION BECAUSE TWO CALL SITES NEED
    # THE SAME WORDS: the redirected-stdin skip and a deliberate empty line.
    # Nothing was generated this run and install-sdsys.log keeps no copy of any
    # earlier one - it is OVERWRITTEN per run, measured 18 Sep 2026 - so there
    # is nothing to print and the honest sentence says so.  The cure rides with
    # it because "kept a password nobody knows" is exactly the state the
    # owner's ruling exists to end, and a reader who kept by mistake has one
    # line telling them the way out.
    Write-Wrapped -Text ('The password this account already has stays.  Nothing was generated this ' +
        'time and no copy of it exists anywhere, so it cannot be shown.  If it is not known, set ' +
        'one from any elevated PowerShell prompt:' + '  Set-LocalUser -Name SDSYS -Password ' +
        '(Read-Host -AsSecureString)')
    Write-Host ''
}

Write-Host ''
Write-Host '  SD is installed.' -ForegroundColor White
Write-Host '  ================'
Write-Host ''

# 18 Sep 26 - WHAT THIS WINDOW SAYS NOW, AND WHY IT SAYS LESS THAN IT DID.  It
# used to describe the account and send the reader to install-sdsys.log for the
# password.  Now it either ASKS for that password or says which case this is.
# Write-Wrapped is used for the text deliberately: these are the page's own
# 19 Sep 26 - RELEASE_1.1 70.  THE INSTALLING USER'S SD PASSWORD, ASKED HERE
# AND REQUIRED.
#
# WHY IT IS ASKED AT ALL, when the 18 Sep ruling was that the install asks for
# NO SD password.  That ruling's reason was "the installing user has already
# logged in to the OS with a password, and that login reaches their SD account"
# - TRUE, AND ONLY ABOUT THE CONSOLE.  RELEASE_1.1 68 then gave every account
# ssh and the API by DEFAULT, so the install was handing out routes the account
# could not authenticate on.  The owner's ruling, 19 Sep 2026: ask during the
# install and say it is only needed for remote access.
#
# ATTACH IS THE ONLY PATH THAT PRODUCES A CREDENTIAL-LESS ACCOUNT, which is why
# one prompt closes the whole hole.  An ordinary CREATE.ACCOUNT calls
# !set_passwd, which writes the Windows password AND $cred (createa:72, :844);
# ATTACH deliberately skips it, because the Windows account already exists and
# is not ours to touch.  So exactly one account per machine lands here.
#
# THE PASSWORD IS NEVER AN ARGUMENT.  SET_ACC_PASSWORD's own header states that
# as a rule and refuses a trailing token on purpose - "a second word is more
# likely a password than a keyword".  So MODIFY.PASSWORD is STARTED in this
# window and asks for itself, twice, hidden; nothing here ever holds the
# plaintext, and it cannot reach a command line, a log or the command stack.
#
# -QUIET SUPPRESSES THE VERB'S OWN EXPLANATORY PARAGRAPH, which this window has
# already given in its own words.  PRE_RELEASE_FIXES 155 added the switch for
# exactly this caller.
#
# REQUIRED MEANS ASKED AGAIN, NOT ENFORCED - and the difference is stated rather
# than hidden.  Nothing in an installer can stop somebody closing the window, so
# "required" here is: ask, verify a credential actually appeared, and ask again
# if it did not, up to $maxTries.  After that it prints the one command that
# puts it right rather than looping forever at somebody who has decided not to.
function Set-AttachedAccountPassword {
    param(
        [Parameter(Mandatory = $true)] [string] $Account,
        [int] $MaxTries = 3
    )

    $credDir  = Join-Path $SysDir '$cred'
    $credFile = Join-Path $credDir $Account.ToLowerInvariant()

    # THE STORE IS READABLE HERE AND NOWHERE ELSE: secure-cred.ps1 locks $cred
    # to SYSTEM and Administrators, so this test works only because this window
    # is elevated - the same token the password step itself needs.
    #
    # ALREADY SET IS NOT A FAILURE AND MUST NOT BE OVERWRITTEN.  On a reinstall
    # over a tree whose accounts were kept, the credential is the one the person
    # has been using; asking again would replace a working password with a
    # freshly invented one, which is the fault the sixteenth pass had to fix for
    # SDSYS.  Here it is CHECKABLE, so it is checked rather than reasoned about.
    if (Test-Path -LiteralPath $credFile) {
        Write-Wrapped -Text ("The account $Account already has an SD Core password, so it was " +
            'left alone.  Type  MODIFY.PASSWORD  in SD Core to change your own at any time.')
        Write-Host ''
        return $true
    }

    Write-Host ("SD Core password for $Account") -ForegroundColor White
    Write-Wrapped -Text ('This is NOT your Windows password and it does not replace it.  Signing ' +
        'in at this keyboard still uses Windows, and nothing about your Windows account has been ' +
        'changed.  This password is what lets you reach SD Core FROM ANOTHER COMPUTER - over ssh, ' +
        'or through the SD API - which this account is allowed to do.')
    Write-Host ''
    Write-Wrapped -Text ('You will be asked to type it twice.  What you type is not shown.')
    Write-Host ''

    for ($try = 1; $try -le $MaxTries; $try++) {
        try {
            # THE ACCOUNT IS ITS OWN ARGUMENT, not glued into a string: sd.c
            # joins argv from the first non-switch onward, so three elements
            # arrive as "MODIFY.PASSWORD <account>".
            #
            # IT NEEDS THE ELEVATED TOKEN AND HAS IT TWICE OVER - sd.c calls
            # check_admin() before accepting a command line at all, and
            # SET_ACC_PASSWORD refuses an account other than your own without
            # K$ADMINISTRATOR.  This runs on Setup's token.
            #
            # ***-internal IS WHAT MAKES THE VERB REACHABLE, AND LEAVING IT OUT
            # IS WHY THE FIRST BUILD OF THIS STEP FAILED ON A REAL INSTALL***
            # with "MODIFY.PASSWORD is not in your VOC", three times, exactly as
            # designed and to no purpose.  MODIFY.PASSWORD lives in
            # sdsys/voc_template, NOT in sdsys/newvoc - it is an SDSYS verb, and
            # an ordinary account's vocabulary does not contain it.  sd.c:607-612
            # sets forced_account = "SDSYS" for an internal session, which is the
            # whole reason attach-account.ps1 can call CREATE.ACCOUNT (also
            # voc_template-only) from the same installer.
            #
            # THE CODE THIS WAS RESTORED FROM DID NOT NEED IT, AND ITS OWN
            # COMMENT SAID WHY: under PRE_RELEASE 56's model an elevated session
            # LANDED IN SDSYS, so the verb was already in reach.  RELEASE_1.1 64
            # narrowed that landing to the Windows SDSYS account, so an elevated
            # session of the installing user now lands in their OWN account.  The
            # restored code carried a precondition 64 had removed.
            #
            # AND IT CHANGES WHAT IS ASKED, FOR THE BETTER: from SDSYS this is
            # setting SOMEBODY ELSE'S password, which SET_ACC_PASSWORD does NOT
            # require the current one for - "an administrator resetting a
            # forgotten password does not know it".  So the person types the new
            # password twice and is never asked for one they do not have.
            # RELEASE_1.1 82 (D2').  LOGIN admits an "sd -internal" session only
            # against a one-shot marker, which it deletes on admission; this writes
            # one immediately before the session and removes it afterwards in case
            # sd never consumed it.
            . (Join-Path $PSScriptRoot 'internal-marker.ps1')
            $marked = Set-SdInternalMarker -SdsysDir $SysDir -Writer 'finish-install'
            try {
                $p = Start-Process -FilePath $SdExe `
                        -ArgumentList '-internal', '-QUIET', 'MODIFY.PASSWORD', $Account `
                        -NoNewWindow -Wait -PassThru -ErrorAction Stop
            }
            finally {
                if ($marked) { $null = Remove-SdInternalMarker -SdsysDir $SysDir }
            }
            $null = $p
            Write-Host ''
        }
        catch {
            Write-Host ''
            Write-Host ('  SD Core could not be started: ' + $_.Exception.Message) -ForegroundColor Red
            break
        }

        # ***KEEP THIS CHECK.  IT IS THE ONE THAT CAUGHT THE 24 Aug 2026
        # REGRESSION***, when a login-path change meant the prompt never
        # appeared and the step passed anyway.  It covers the whole class: a
        # verb that was refused, a session that never started, a $cred that was
        # not writable, and an empty line typed at the prompt.
        if (Test-Path -LiteralPath $credFile) {
            Write-Wrapped -Text ("Password set.  $Account can now be reached over ssh and through " +
                'the SD API.')
            Write-Host ''
            return $true
        }

        if ($try -lt $MaxTries) {
            Write-Wrapped -Text ('No password was set, so nothing can reach this account from ' +
                'another computer yet.  A password is required - trying again.') -Color Yellow
            Write-Host ''
        }
    }

    # THE ESCAPE IS NAMED, NOT SILENT.  An account with no credential still
    # works at this keyboard, so the install is not broken - but it cannot be
    # reached remotely, and SD Core will ask again at the next ELEVATED sign-in.
    # 19 Sep 26 - THIS SENTENCE HAS BEEN WRONG IN BOTH DIRECTIONS IN ONE DAY,
    # WHICH IS WHY IT CARRIES A NOTE.  It first said "type MODIFY.PASSWORD",
    # which the reader could not do - the verb was in voc_template only.
    # RELEASE_1.1 71 then put it in newvoc on the owner's ruling, so they CAN,
    # but only for their OWN account: set_acc_password:123-126 refuses another
    # account without K$ADMINISTRATOR.  The qualifier is the whole point and
    # must not be dropped the next time this is tidied.
    Write-Wrapped -Text ("No SD Core password was set for $Account.  You can still use SD Core at " +
        'this keyboard, but nothing can reach the account from another computer until one is ' +
        'set.  Type  MODIFY.PASSWORD  in SD Core to set your own at any time, or start SD Core ' +
        'from an ELEVATED prompt and it asks you.') -Color Yellow
    Write-Host ''
    return $false
}

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
        # 18 Sep 26, later still - THE OWNER'S SECOND RULING: THE PROMPT IS OWED
        # HERE TOO.  "SDSYS already exists" is the case his machine is in, and
        # the twelfth pass's "a reinstall cannot overwrite a working password"
        # assumed the existing password was known to somebody - the 21:28:44 run
        # measured that it was not, and the log it was written to is overwritten
        # per run.  Without a password entered at install time there is no way
        # to manage SD at all, so the window asks on both codes that mean the
        # account EXISTS (0 made, 2 already there) and leaves the asking-out to
        # the empty line, which says what keeping means.
        Set-SdsysPassword -LogFile $SdsysLog -Existing
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
# 19 Sep 26 - AND THE INSTALLING USER'S OWN SD PASSWORD, RELEASE_1.1 70.
#
# AFTER SDSYS, because that is the order they matter in: SDSYS is how the
# machine is administered and this is how the person uses it from elsewhere.
#
# BOTH CODES THAT MEAN THE ACCOUNT EXISTS ARE ASKED - 0 made, 2 already there -
# and unlike the SDSYS block above, the "already there" case does not have to be
# reasoned about: the function READS $cred and leaves a credential that is
# already set alone.  A reinstall over kept accounts therefore cannot overwrite
# a working password, which is the fault the sixteenth pass had to fix for SDSYS
# precisely because a Windows password cannot be inspected that way.
switch ($AttachCode) {
    { $_ -in 0, 2 } {
        if ($AttachUser -ne '') {
            $null = Set-AttachedAccountPassword -Account $AttachUser
        }
        else {
            # THE NULL CASE, REFUSED OUT LOUD.  A code saying an account exists
            # with no name to go with it is a wiring fault in sd.iss, not a
            # normal path, and setting a password on a guessed name is the exact
            # danger the old -User default was condemned for.
            Write-Wrapped -Text ('Setup reported that an account was attached but did not say ' +
                'whose, so no password was asked for.  Start SD Core from an ELEVATED prompt and ' +
                'it will ask.') -Color Yellow
            Write-Host ''
        }
    }
    default {
        # 1, 3 or -1.  Nothing is said about a password for an account that was
        # not made - attach-account.log already carries why, and sd.iss's own
        # closing dialog names the recovery.  A hand run of this script lands
        # here too, which is why it is silence rather than a warning.
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
