# check-install.ps1 - tell the person who just installed SD whether it worked.
#
#   powershell -File check-install.ps1            run the checks
#   powershell -File check-install.ps1 -Brief     one line per check, no preamble
#
# Exit 0 nothing is wrong, 1 something is.  A check that cannot be answered YET
# is not something being wrong - see THREE OUTCOMES below.
#
# THIS IS NOT THE DEVELOPMENT SUITE AND CANNOT BECOME IT.  VerifyInstall1.ps1
# and its sixteen verifiers answer "does every behaviour still hold, on a tree
# that still matches the source it was built from".  Two things stop that
# question being asked on a user's machine, and neither is a packaging problem:
#
#   1. assert-current.ps1 compares the install against the SOURCE TREE, which a
#      user does not have, and 21 of the 24 verifiers refuse to run without it.
#   2. The suite is DESTRUCTIVE.  It creates and deletes Windows accounts,
#      rewrites user-rights policy, restarts the SD service and edits
#      sshd_config.  None of that belongs on somebody's working install.
#
# So this asks a smaller and different question - DID THIS INSTALL, ON THIS
# MACHINE, PRODUCE A WORKING SD - and it asks it by READING ONLY.  It creates
# nothing, deletes nothing, starts and stops nothing, and changes no setting.
# Run it as often as you like.
#
# THE ONE FAILURE IT EXISTS TO CATCH, because it has happened: on 16 Aug 2026 an
# install shipped with an EMPTY CATALOGUE.  Every file was present, the service
# ran, and nothing worked, because the bootstrap had not compiled the BASIC
# programs into gcat.  cycle.ps1 steps 3 and 8 count that tree for developers.
# Nothing counted it on a user's machine until this file.
#
# THREE OUTCOMES, AND THE THIRD IS WHY THIS SCRIPT IS SHAPED THE WAY IT IS.
#
#   [ok]      the check passed.
#   [PROBLEM] something is actually wrong.  Exit code 1.
#   [not yet] the check could not be answered on THIS logon, and that is
#             expected and harmless.
#
# The third exists because of a real Windows behaviour the installer already
# warns about twice: the installer adds you to the "sdusers" group, and WINDOWS
# FIXES GROUP MEMBERSHIP IN YOUR ACCESS TOKEN WHEN YOU SIGN IN.  A membership
# granted after that point is invisible until you sign out and back in.  The
# data tree grants SYSTEM, Administrators and sdusers, so on the logon that ran
# the installer this script CANNOT READ THE DATABASE, however healthy it is.
#
# A CHECK THAT REPORTED THAT AS A FAILURE WOULD BE WORSE THAN NO CHECK AT ALL.
# It would tell somebody their brand new install was broken, at the exact moment
# they have least reason to doubt it, for a reason that fixes itself.  So the
# membership is read TWO WAYS - from the group itself, and from this process's
# token - and the two together say which case it is:
#
#   in the group, not in the token  ->  [not yet], sign out and back in
#   not in the group at all         ->  [PROBLEM], the installer did not add you
#
# Inno runs a "postinstall" entry as "Run as: Original user", so the token this
# sees is the ordinary one and the case above is the NORMAL one at install time,
# not the exception.
#
# IT IS ALSO WHY THIS DOES NOT ELEVATE.  Elevating would let it read the tree
# and answer everything at once - and it would then be answering as
# Administrators rather than as the user, so a genuine "this user cannot reach
# their own database" would pass.  The whole question is whether THIS PERSON can
# use SD.  Asking it with somebody else's token is not a shortcut, it is a
# different question.  Same reasoning as verify-credacl.ps1 refusing elevation.

[CmdletBinding()]
param(
    # One line per check and no explanation.  For somebody re-running it who has
    # already read the preamble once.
    [switch] $Brief,

    # 22 Aug 26 - SKIP THE "shall I?" PROMPT.  Anything that is not a person
    # needs this: Read-Host in a non-interactive host does not wait, it THROWS,
    # so the absence of somebody to answer is caught and named rather than left
    # as a stack trace.  Same reasoning and same switch name as VerifyInstall1.
    [switch] $Yes,

    # 22 Aug 26 - do not wait for a keypress at the end.  For anything that
    # is not a person sitting in front of the window.
    [switch] $NoPause
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# WHERE THINGS ARE.  These are constants and not guesses: the install location
# stopped being a choice on 22 Aug 2026 (sd.iss, DisableDirPage/UsePreviousAppDir)
# and the data tree never was one - DataDir is #defined as {commonappdata}\SD.
$AppDir  = Join-Path $env:ProgramFiles 'SD'
$DataDir = Join-Path $env:ProgramData  'SD'
$SdExe   = Join-Path $AppDir 'usr\bin\sd.exe'
$SysDir  = Join-Path $DataDir 'sdsys'
$GcatDir = Join-Path $SysDir  'gcat'

$script:problems = 0
$script:notyet   = 0

# ---------------------------------------------------------------------------
# IS THIS AN ELEVATED WINDOW?  It changes what the answers MEAN, so it has to be
# known before any of them are printed.
#
# The data tree grants SYSTEM, Administrators and sdusers.  An elevated token
# carries Administrators, so it can read the database WHETHER OR NOT the person
# is in sdusers - and this script would then report the database healthy for
# somebody whose ordinary sign-in cannot open it at all.  THAT IS A FALSE PASS
# ON THE ONLY QUESTION THIS SCRIPT ASKS.
#
# IT DOES NOT REFUSE, THOUGH, AND THE DIFFERENCE FROM verify-credacl.ps1 IS
# DELIBERATE.  That is a developer's verifier and refusing is right for it: a
# wrong answer there corrupts a measurement.  This is a tool a worried user
# runs, and somebody who right-clicks "Run as administrator" - which is exactly
# what a worried person does - must not be met with a blank refusal that
# teaches them nothing.  So it runs, and it says what the answer is worth.
$script:elevated = ([Security.Principal.WindowsPrincipal] `
    [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

function Ok      ($m) { Write-Host ('  [ok]      ' + $m) -ForegroundColor Green }
function Problem ($m) { $script:problems++; Write-Host ('  [PROBLEM] ' + $m) -ForegroundColor Red }
function NotYet  ($m) { $script:notyet++;   Write-Host ('  [not yet] ' + $m) -ForegroundColor Yellow }
function Info    ($m) { if (-not $Brief) { Write-Host ('            ' + $m) -ForegroundColor DarkGray } }
function Section ($m) { Write-Host ''; Write-Host $m -ForegroundColor Cyan }

# 22 Aug 26 - SAY WHEN IT IS OVER, AND CLOSE ON A KEYPRESS.  Owner's
# instruction, twice.  The window has to outlive the checks - a check nobody
# can read is not a check, which is the third fault that killed the old SDSYS
# password step - but the first way of doing that, -NoExit, left a LIVE
# POWERSHELL PROMPT with nothing saying the work was over and no way out but
# typing "exit" at a prompt nobody had asked for.
#
# ON EVERY ENDING, not only the good one, because "is it finished?" is the same
# question whichever answer it reached - and it is loudest on the path that
# found a problem, where a reader is most likely to sit and wait for something
# more to happen.
#
# DEFINED HERE, WITH THE OTHER HELPERS, rather than beside the summary it is
# used by.  PowerShell binds a function when execution reaches it, and the
# refusal path exits long before the summary - so a definition further down
# would have been an unrecognised command on the one path a user takes by
# choosing not to run anything.
# $Ran is false on the one path where nothing was checked, because the user said
# no.  "Test completed" would not be true there, and a closing line that
# overstates what happened is the same class of thing as the summary that told
# somebody to sign out when that could not help them.
# 22 Aug 26 - WHERE TO FIND IT, IN ONE PLACE.  Owner: the elevated banner said
# to "run this again ... from an ordinary window" and named neither what "this"
# is nor where to get it.  That banner is now the MOST READ text in the file -
# the install-time run is launched by the finishing step, which must be
# elevated, so it fires on every fresh install.
#
# FOUR PLACES SAID SOME OF THIS AND NO TWO SAID THE SAME AMOUNT, which is how
# one of them ended up saying none of it.  They all call this now, so the
# Start Menu wording and the path cannot drift apart again.
#
# THE PATH IS BUILT FROM $AppDir rather than written out, so it stays true if
# this is ever run from somewhere other than the install.
function Rerun {
    Write-Host '    Start Menu  ->  SD  ->  Check the SD installation'
    Write-Host '  or:'
    Write-Host ('    powershell -File "' + (Join-Path $AppDir 'check-install.ps1') + '"')
}

function Finish([bool] $Ran = $true) {
    Write-Host ''
    if ($Ran) {
        Write-Host '  Test completed.' -ForegroundColor Cyan
    } else {
        Write-Host '  Nothing was checked.' -ForegroundColor Cyan
    }

    # 22 Aug 26 - A KEYPRESS CLOSES IT, rather than a prompt the user must type
    # "exit" at.  Owner's instruction.  The window used to be held open with
    # -NoExit, which leaves a LIVE POWERSHELL PROMPT sitting there - so the
    # window stayed, which was the point, but getting rid of it meant knowing to
    # type a command at a prompt nobody asked for.  Waiting for a key does the
    # same job and ends by itself.
    #
    # -NoExit IS GONE FROM BOTH LAUNCH SITES to match: the installer's finishing
    # step and the Start Menu shortcut.  If either kept it, this pause would be
    # followed by the very prompt it exists to avoid.
    #
    # IT MUST NOT HANG SOMETHING THAT IS NOT A PERSON.  ReadKey throws in a host
    # with no console - which is what -Yes callers generally are - so the throw
    # is caught and skipped rather than left to become a stack trace at the end
    # of an otherwise successful run.  -NoPause is the explicit way to ask for
    # the same thing.
    if ((-not $NoPause) -and (-not [Console]::IsInputRedirected)) {
    # THE GUARD IS IsInputRedirected, NOT A try/catch - MEASURED 22 Aug 2026.
    # The first version wrapped ReadKey in try/catch on the assumption it would
    # THROW in a host with no console, the way Read-Host does.  IT DOES NOT: it
    # BLOCKS, for ever.  A background job left to run with no -NoPause hung until
    # it was killed, which is the unbounded-wait fault PROJECT_STATUS section 8
    # records costing three runs.
    # [Console]::IsInputRedirected is false only for a REAL console, which is
    # exactly when a keypress can arrive.  The try/catch stays as a backstop for
    # a host that refuses the call outright, but it is no longer the guard.
        Write-Host '  Press any key to close this window.' -ForegroundColor Cyan
        try   { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') }
        catch { }
    }
    Write-Host ''
}

# ---------------------------------------------------------------------------
# IS THIS USER IN sdusers, AND DOES THIS TOKEN KNOW IT?  Two questions, and the
# whole [not yet] path depends on telling them apart.
function Get-SdUsersState {
    $inGroup = $null      # $true, $false, or $null meaning "could not read"
    try {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $members = @(Get-LocalGroupMember -Group 'sdusers' -ErrorAction Stop)
        $inGroup = [bool](@($members | Where-Object { $_.SID.Value -eq $me }).Count)
    } catch {
        # Get-LocalGroupMember can fail on a machine where the group does not
        # exist, and it can fail for reasons of its own.  Not knowing is a third
        # answer and is reported as such rather than guessed either way.
        $inGroup = $null
    }

    # THE TOKEN, which is the half that lags.  Translate() is wrapped because a
    # token can carry SIDs that no longer resolve to a name, and one of those
    # must not take the whole check down.
    $inToken = $false
    foreach ($g in [Security.Principal.WindowsIdentity]::GetCurrent().Groups) {
        try {
            if ($g.Translate([Security.Principal.NTAccount]).Value -match '\\sdusers$') { $inToken = $true }
        } catch { }
    }
    return [pscustomobject]@{ InGroup = $inGroup; InToken = $inToken }
}

# ---------------------------------------------------------------------------
if (-not $Brief) {
    Write-Host ''
    Write-Host '  Checking your SD installation' -ForegroundColor White
    Write-Host '  ============================='
    Write-Host ''
    # 22 Aug 26 - IT NO LONGER CLAIMS THE INSTALL HAS FINISHED.  Owner: "the
    # install doesn't actually finish until you close the post install script
    # window, so ... 'The install has finished' is not correct."  Right, and it
    # was wrong twice over: this window is reached THROUGH the installer's own
    # finishing step, and the password step that ran a moment ago in this same
    # window is part of setting SD up, not something after it.
    #
    # WHAT IS TRUE IS THE REASSURING HALF ANYWAY - the files are on disk and
    # nothing here writes - so saying that instead costs nothing and does not
    # have to be taken back.
    Write-Host '  SD is installed, and this is the last step of setting it up.'
    Write-Host '  Nothing here changes anything - it only reads - so it is safe to'
    Write-Host '  run again whenever you like.'
    Write-Host ''
    Write-Host '  What it will do, and it is all reading:'
    Write-Host ''
    Write-Host '    * look for the SD program files and the SD service'
    Write-Host '    * check that you can reach the database'
    Write-Host '    * count the programs SD built during the install'
    Write-Host '    * check the network options, if you turned any on'
    Write-Host ''
    Write-Host '  It creates nothing, deletes nothing, and starts and stops nothing.'
    Write-Host '  It takes a few seconds, and you can run it again whenever you like'
    Write-Host '  from the Start Menu: SD  ->  Check the SD installation.'
    Write-Host ''
}

# 22 Aug 26 - AND IT ASKS, EVEN THOUGH THE TICKBOX ALREADY DID.  Owner, 22 Aug:
# "there was no explanation of the post install validation process and no option
# for the user to refuse it."  The installer's tickbox is a refusal, but it is
# one line on a page somebody is clicking Finish on, so in practice it is not a
# decision anybody makes.  This is the one that is hard to miss, and it costs a
# keystroke to say no.
if (-not $Yes) {
    $answer = $null
    try   { $answer = Read-Host '  Run the checks now? (y/n)' }
    catch {
        Write-Host ''
        Write-Host '  Nothing is available to answer that question, so nothing was run.'
        Write-Host '  Pass -Yes to run the checks without asking.'
        Write-Host ''
        exit 2
    }
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host ''
        Write-Host '  Nothing was checked.  The installation is unaffected either way.'
        Write-Host '  You can run it whenever you want it:'
        Rerun
        Finish $false
        exit 0
    }
}

if ($script:elevated) {
    Write-Host ''
    Write-Host '  NOTE: this window has administrator rights, which changes what the' -ForegroundColor Yellow
    Write-Host '  database answers below are worth.  Administrators can open the SD' -ForegroundColor Yellow
    Write-Host '  database whatever groups you are in, so a pass here does NOT show' -ForegroundColor Yellow
    Write-Host '  that your ordinary sign-in can use SD.' -ForegroundColor Yellow
    Write-Host ''
    Write-Host '  For that answer, run this same check again from an ORDINARY window' -ForegroundColor Yellow
    Write-Host '  - not "Run as administrator":' -ForegroundColor Yellow
    Rerun
}

$sdUsers = Get-SdUsersState

# --- 1. the programs -------------------------------------------------------
Section '  The program files'

if (Test-Path -LiteralPath $SdExe) {
    Ok ('SD is installed in ' + $AppDir)
} else {
    Problem ('SD is not where it should be - expected ' + $SdExe)
    Info 'Nothing else below will mean much.  Try installing again.'
}

# --- 2. the service --------------------------------------------------------
Section '  The SD service'

$svc = Get-Service -Name 'SD' -ErrorAction SilentlyContinue
if ($null -eq $svc) {
    Problem 'The SD service was not installed.'
    Info 'SD runs as a Windows service.  Without it nobody can connect.'
} elseif ($svc.Status -eq 'Running') {
    Ok 'The SD service is running.'
} else {
    Problem ('The SD service is installed but is ' + $svc.Status + '.')
    Info 'Start it from Services, or restart the machine.'
}

# --- 3. your access to the database ----------------------------------------
Section '  Your access to the database'

if ($sdUsers.InGroup -eq $false) {
    Problem 'You are not a member of the "sdusers" group.'
    Info 'That membership is what lets you open the database.  An administrator'
    Info 'can add you with:   net localgroup sdusers "<your user name>" /add'
} elseif ($null -eq $sdUsers.InGroup) {
    NotYet 'Could not read the "sdusers" group to check your membership.'
} elseif (-not $sdUsers.InToken) {
    NotYet 'You are in the "sdusers" group, but this sign-in does not have it yet.'
    Info 'This is normal and it is not a fault.  Windows decides what groups you'
    Info 'are in when you sign in, so a membership added during the install does'
    Info 'not apply until you SIGN OUT AND BACK IN.  Do that, then run this again.'
} else {
    Ok 'You are in the "sdusers" group and this sign-in has it.'
}

# --- 4. the database itself ------------------------------------------------
# THE CHECK THIS FILE EXISTS FOR.  A tree that is present but has an empty
# catalogue is the 16 Aug 2026 failure, and it looks completely healthy from
# the outside.
Section '  The database'

if (-not (Test-Path -LiteralPath $SysDir)) {
    Problem ('The database is missing - expected ' + $SysDir)
} else {
    Ok ('The database is in ' + $DataDir)

    # Reading gcat needs the tree ACL, which needs sdusers IN THE TOKEN.  So a
    # failure here is only meaningful once section 3 said the token has it;
    # before that, "cannot read" is the expected answer and not a fault.
    $count = $null
    try {
        $count = @(Get-ChildItem -LiteralPath $GcatDir -File -ErrorAction Stop).Count
    } catch {
        $count = $null
    }

    if ($null -ne $count) {
        # The number is a floor, not the exact shipped count: the catalogue
        # grows as accounts compile their own programs, and a check that
        # demanded an exact figure would start failing on a machine that was
        # simply being used.  What distinguishes a good install from the broken
        # one is 100-odd entries against nearly none.
        if ($count -ge 100) {
            Ok ("SD's program catalogue is present (" + $count + ' entries).')
            # SAY WHOSE RIGHTS ANSWERED IT.  Read under elevation this line is
            # about the ADMINISTRATOR token, and the reader has every reason to
            # take it as being about themselves.  The banner at the top says so
            # once; this says it where the misreading would actually happen.
            if ($script:elevated -and -not $sdUsers.InToken) {
                Info 'Read using administrator rights - this does not show that your'
                Info 'ordinary sign-in can open the database.'
            }
        } else {
            Problem ("SD's program catalogue has only " + $count + ' entries and should have over 100.')
            Info 'The install did not finish building SD. Almost nothing will work.'
            Info 'Please report this - it is a fault in the installer, not in anything you did.'
        }
    } elseif ($sdUsers.InToken) {
        Problem 'Could not read the program catalogue, and this sign-in should be able to.'
        Info ('Expected to read ' + $GcatDir)
    } elseif ($sdUsers.InGroup -eq $false) {
        # 22 Aug 26 - ATTRIBUTE THIS TO THE RIGHT CAUSE.  The first version sent
        # everyone who could not read the tree down the "sign out and back in"
        # path, INCLUDING somebody who is not in sdusers at all.  Signing out
        # and back in would not help them and they would do it, find nothing
        # changed, and have been told the wrong thing by the tool that was
        # supposed to explain their install.  The membership check above has
        # already reported their real problem; this only says why the catalogue
        # went unchecked, and does not offer a remedy that cannot work.
        NotYet 'The program catalogue was not checked, because of the membership problem above.'
    } else {
        NotYet 'Cannot check the program catalogue until you sign out and back in.'
        Info 'See the note above - this is the same group membership, not a second problem.'
    }
}

# --- 5. remote access, only where it was asked for -------------------------
# EVERY CHECK HERE IS CONDITIONAL ON THE FEATURE BEING WANTED.  Reporting "the
# API port is closed" to somebody who never asked for the API would be noise
# that reads like a fault.
Section '  Remote access'

$apiPort = $null
$conf = Join-Path $DataDir 'sd.conf'
if (Test-Path -LiteralPath $conf) {
    try {
        $line = Select-String -LiteralPath $conf -Pattern '^\s*APIPORT\s*=\s*(\d+)' -ErrorAction Stop |
                    Select-Object -First 1
        if ($line) { $apiPort = [int]$line.Matches[0].Groups[1].Value }
    } catch { }
}

if ($null -eq $apiPort -or $apiPort -le 0) {
    Ok 'The network API is switched off, so nothing is listening for it.'
} else {
    $listening = $false
    try {
        $listening = [bool](@(Get-NetTCPConnection -State Listen -LocalPort $apiPort -ErrorAction Stop).Count)
    } catch {
        # Get-NetTCPConnection is absent on some editions; netstat is the
        # fallback and is present everywhere.
        $ns = & "$env:SystemRoot\System32\netstat.exe" -an
        $listening = [bool](@($ns | Where-Object { $_ -match ('LISTENING') -and $_ -match (':' + $apiPort + '\s') }).Count)
    }
    if ($listening) {
        Ok ('The network API is listening on port ' + $apiPort + '.')
    } elseif ($null -ne $svc -and $svc.Status -ne 'Running') {
        NotYet ('Nothing is listening on port ' + $apiPort + ' because the service is not running.')
    } else {
        Problem ('The network API is switched on but nothing is listening on port ' + $apiPort + '.')
    }
}

$sshSvc = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
if ($null -eq $sshSvc) {
    Info 'The ssh server is not installed, so ssh access was not set up.'
} elseif ($sshSvc.Status -eq 'Running') {
    Ok 'The ssh server is running.'
} else {
    NotYet ('The ssh server is installed but is ' + $sshSvc.Status + '.')
    Info 'OpenSSH often needs a restart after being installed.'
}

Write-Host ''
Write-Host '  ============================='
if ($script:problems -gt 0) {
    Write-Host ('  Found ' + $script:problems + ' problem(s).') -ForegroundColor Red
    if ($script:notyet -gt 0) {
        # 22 Aug 26 - NEUTRAL WORDING ON THIS PATH, DELIBERATELY.  It used to
        # say these checks "need you to sign out and back in", which is only
        # true when the token is the reason.  When a PROBLEM is what blocked
        # them - not being in sdusers at all - that sentence sends the reader
        # off to do something that cannot help, and away from the fault that is
        # printed six lines above.  Each [not yet] line has already said why it
        # was skipped; the summary only counts them.
        Write-Host ('  ' + $script:notyet + ' other check(s) could not be made - see above.') -ForegroundColor Yellow
    }
    Finish
    exit 1
}

if ($script:notyet -gt 0) {
    Write-Host '  Nothing is wrong.' -ForegroundColor Green
    Write-Host ('  ' + $script:notyet + ' check(s) need you to SIGN OUT AND BACK IN before they can be made.') -ForegroundColor Yellow
    Write-Host '  That is expected straight after installing.' -ForegroundColor Yellow
    Write-Host ''
    # 22 Aug 26 - SAY HOW, NOT JUST WHEN.  This used to end with "run this again
    # afterwards" and never said how to, which on a fresh install is advice
    # nobody can act on: the first run is ALWAYS the incomplete one - the
    # installing user's token cannot carry sdusers yet - so the re-run is not an
    # optional extra, it is how the check ever gets finished.  Being told to
    # repeat something unfindable is the same fault as being told to sign out
    # when that cannot help, which this file already had once.
    Write-Host '  Afterwards, run it again from:'
    Rerun
    Finish
    exit 0
}

Write-Host '  Everything checks out.  SD is installed and working.' -ForegroundColor Green
Finish
exit 0
