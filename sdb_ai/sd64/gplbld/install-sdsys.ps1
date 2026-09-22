# install-sdsys.ps1 - create the ONE Windows account that may administer SD
#
#   powershell -ExecutionPolicy Bypass -File install-sdsys.ps1 -DataDir "C:\ProgramData\SD"
#
# Called by sd.iss from ssPostInstall, elevated, where adopt-account.ps1 used to
# be called.  Project 7 step 1f, and RELEASE_1.1 64.
#
# ***RELEASE_1.1 64, OWNER'S DECISION 18 SEP 2026.***  "There will be one and
# only one administrator account SDSYS, which will also be tied to a Windows
# account administrator account of the same name ... Only the Windows SDSYS
# account will have access to SD as an administrator from an elevated session,
# all other windows administrators will be refused."
#
# WHY THIS REPLACES adopt-account.ps1 RATHER THAN JOINING IT.  That script gave
# the INSTALLING Windows administrator an SD account, and CREATEA minted it an
# administrator - the arrangement 64 forbids and deletes.  What is left is this
# account, and it is the only door: LOGIN's landing case is
# `upcase(@logname) = 'SDSYS' and kernel(K$ADMINISTRATOR, -1)`, so an elevated
# session of the Windows account named SDSYS lands in SDSYS and nothing else
# does.  IF THIS STEP DOES NOT RUN, THE INSTALL HAS NO WAY IN AT ALL - measured
# on the 15:07:23 install of 18 Sep 2026, when the adopt step failed and left
# `sdsys/accounts` holding sdsys alone, `user_accounts/` empty, and `sd.exe`
# answering "Account DON not in register" / "Connection terminated".
#
# THE NAME IS FIXED AND IS NOT A PARAMETER.  The Windows account name IS the SD
# account name (login:747), so a parameter here would be a second place for the
# model to live and a way to install a machine nobody can administer.
#
# WHAT IT JOINS, AND WHAT IT DOES NOT:
#   Administrators   REQUIRED.  The landing case needs an ELEVATED session, and
#                    elevation is a Windows token; membership is what lets the
#                    owner start SD with "Run as administrator" and get one.
#   sdusers          REQUIRED.  That group carries the data tree's ACL.  Without
#                    it SDSYS is an administrator who cannot open SD's files.
#   sdapi            NOT JOINED BY DEFAULT (RELEASE_1.1 101, owner 22 Sep 2026).
#                    SDSYS has the API route like every other account, off until
#                    MODIFY.ACCOUNT SDSYS API.  This script never removes it, so
#                    a grant survives an upgrade.
#   sdssh            NOT JOINED, AND NOT OFFERED.  Owner, 22 Sep 2026: ssh is no
#                    use to SDSYS, which must already be signed in to be an
#                    administrator.  MODIFY.ACCOUNT refuses SDSYS SSH.  Only the
#                    old removal is gone; nothing here adds it.
#   sdsshonly        NEVER.  Its SeDenyInteractiveLogonRight would lock SDSYS
#                    out of its own console.
#
# THE PASSWORD IS GENERATED, PRINTED AND LOGGED, AND SOMEBODY ASKS FOR A BETTER
# ONE A MOMENT LATER.  The generated one exists because the account needs a
# password the instant it is created, and because a hand run of this script has
# nobody to ask - but this script runs in a HIDDEN window (sd.iss's Exec,
# SW_HIDE), so nobody ever SEES it.  Owner's ruling, 18 Sep 2026, after the first
# install to use it: "the password for the SDSYS account was never asked for or
# printed so no way to get in".  finish-install.ps1 therefore ASKS for that
# password in its window - which opens after the wizard, on Setup's elevated
# token - and when it sets one it appends a line to this log saying the printed
# password was replaced, so the log never stands as a working credential after
# it has stopped being one.  SD's own credential register is empty at install
# (the cycle prints "NO ACCOUNT HAS A PASSWORD") and a console login is by
# Windows identity, so SD needs no password of SDSYS's - this one is Windows'.
#
# EXIT CODES, and sd.iss reports each one differently:
#   0  the account was created or brought back into shape
#   2  it was already right - the reinstall case, not a failure
#   1  something failed, and the log says what
#
# NO SD SERVER IS STARTED OR STOPPED HERE, unlike adopt-account.ps1: this step
# writes Windows state only, and it has no verb to run.

[CmdletBinding()]
param(
    # Where SD's data tree is.  The installer passes {#DataDir}; the default is
    # the same literal the other shipped scripts use.  -AppDir is NOT a
    # parameter: nothing here reads a program file, so taking one would be a
    # parameter nobody can use.
    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Stop'

# THE NAME, IN ONE PLACE.  login:747 tests this name; CREATEA writes the register
# record under it; sd.iss's closing text names it to the reader.
$AccountName = 'SDSYS'

# New-LocalUser caps -Description at 48 CHARACTERS and refuses a longer one at
# parameter binding - install-service.ps1 records an install that completed with
# no account and no API because of exactly that, and test-installservice-units
# measures its literal.  This one is 28 characters.
$SdsysDescription = 'SD Core administrator account'

# EVERYTHING SAID HERE IS ALSO WRITTEN TO A FILE, for adopt-account.ps1's reason:
# sd.iss calls this through Exec with SW_HIDE, and the password below has to
# survive on disk because it is shown once.  C:\ProgramData\SD is locked to
# SYSTEM and Administrators by secure-log.ps1 at install time, so this log is
# not readable by the accounts it describes.
$LogFile = Join-Path $DataDir 'install-sdsys.log'

function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

function New-RandomPassword {
    # 32 characters from a CSPRNG, on install-service.ps1's alphabet and for its
    # reason: it has to satisfy New-LocalUser and the password policy at once,
    # and be unguessable.  Unlike the relay's, this one is USED by a person.
    #
    # 19 Sep 26 - AND IT NOW HAS TO SATISFY SD'S OWN RULE TOO, RELEASE_1.1 75.
    # ***THIS IS NOT A THEORETICAL TIDY-UP.***  The password this generates is
    # the one a person is shown and types, and from this release SD refuses a
    # password with no digit in it - so a draw that happened to contain none
    # would hand the operator a password that SD itself would not accept if
    # they tried to set it by hand.  32 characters make that vanishingly
    # unlikely and "vanishingly unlikely" is not a guarantee; drawing again is.
    #
    # THE LOOP IS BOUNDED AND SAYS SO IF IT EVER RUNS OUT.  An unbounded retry
    # over a CSPRNG cannot hang in practice, but a bounded one cannot hang in
    # principle either, and a silent infinite loop inside a HIDDEN install step
    # is the worst shape this script could take.
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%+=?'
    for ($draw = 1; $draw -le 20; $draw++) {
        $bytes = New-Object byte[] 32
        [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $s = ''
        foreach ($b in $bytes) { $s += $chars[$b % $chars.Length] }
        if (Test-GeneratedPasswordComplex -Password $s) { return $s }
    }
    Say 'WARNING: 20 generated passwords in a row failed SD password rule - using the last.'
    return $s
}

# THE RULE, AGAIN, AND THE THIRD COPY IS DELIBERATE RATHER THAN CARELESS.
# gpl.bp/pw_complex holds it for everything inside SD; finish-install.ps1 holds
# it for the prompt that sets the SDSYS password; this one exists because this
# script runs BEFORE either is reachable - at ssPostInstall, in a hidden window,
# with no SD session and nothing dot-sourced.  test-pwcomplex-units.py drives
# all three against one table so they cannot drift apart.
function Test-GeneratedPasswordComplex {
    param([string] $Password)
    if ($Password.Length -lt 8) { return $false }
    $lower = $false; $upper = $false; $digit = $false; $symbol = $false
    foreach ($ch in $Password.ToCharArray()) {
        $c = [int][char]$ch
        # The symbol arm names its own range and the catch-all fails closed -
        # gpl.bp/pw_complex's shape.  See the note there for why it is not the
        # other way round.
        if     ($c -ge 97 -and $c -le 122) { $lower  = $true }
        elseif ($c -ge 65 -and $c -le 90)  { $upper  = $true }
        elseif ($c -ge 48 -and $c -le 57)  { $digit  = $true }
        elseif ($c -ge 32 -and $c -le 126) { $symbol = $true }
        else                               { return $false }
    }
    return ($lower -and $upper -and $digit -and $symbol)
}

function Test-SdsysMembership([string] $Group) {
    return [bool](Get-LocalGroupMember -Group $Group -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -like ('*\' + $AccountName) })
}

Say ("=== install-sdsys " + (Get-Date -Format 's') + " DataDir=$DataDir")

$account = Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue
$created = $false
$password = ''
$failed = $false

if ($null -eq $account) {
    $password = New-RandomPassword
    $sec = ConvertTo-SecureString $password -AsPlainText -Force
    try {
        $account = New-LocalUser -Name $AccountName -Password $sec -PasswordNeverExpires `
            -AccountNeverExpires -Description $SdsysDescription -ErrorAction Stop
    } catch {
        Say ("could not create the " + $AccountName + " account: " + $_.Exception.Message)
        Say 'NO SD ADMINISTRATOR EXISTS ON THIS MACHINE. SD cannot be administered from a console.'
        exit 1
    }
    $created = $true
    Say ("created the Windows account " + $AccountName)
} else {
    Say ("" + $AccountName + " already exists")
    if (-not $account.Enabled) {
        Enable-LocalUser -Name $AccountName
        Say '  it was disabled; enabled'
    }
}

# GROUPS.  Added where they are required, removed where they would be a lie.
foreach ($g in @('Administrators', 'sdusers')) {
    if (-not (Test-SdsysMembership $g)) {
        try {
            Add-LocalGroupMember -Group $g -Member $AccountName -ErrorAction Stop
            Say ("  joined " + $AccountName + " to " + $g)
        } catch {
            Say ("  COULD NOT join " + $g + ": " + $_.Exception.Message)
            $failed = $true
        }
    } else {
        Say ("  already in " + $g)
    }
}
# RELEASE_1.1 101, owner 22 Sep 2026: SDSYS has the API route like every other
# account - off until "MODIFY.ACCOUNT SDSYS API" turns it on.  So sdapi is NOT
# touched here: this script runs on every install, an upgrade included, and
# stripping it would undo an administrator's grant each time.  sdssh is not
# offered to SDSYS at all.  Off after a fresh install holds without any removal -
# the two groups are deleted at uninstall, and sync-route-groups.ps1 leaves SDSYS
# out of the sdssh seed.
# sdsshonly stays removed: its deny-logon rights would lock SDSYS out of its own
# console.
foreach ($g in @('sdssh', 'sdsshonly')) {
    if (Test-SdsysMembership $g) {
        Remove-LocalGroupMember -Group $g -Member $AccountName -ErrorAction SilentlyContinue
        Say ("  removed " + $AccountName + " from " + $g + " - it has no ssh route and must keep its console")
    }
}

# THE VERDICT IS TAKEN FROM WINDOWS, NOT FROM WHAT THIS SCRIPT DID.  Every step
# above can fail in a way that leaves the account in place and unusable, and the
# one failure that matters - an administrator who cannot open SD - is invisible
# until somebody tries to sign in.
$ok = (Get-LocalUser -Name $AccountName -ErrorAction SilentlyContinue) -and
      (Test-SdsysMembership 'Administrators') -and
      (Test-SdsysMembership 'sdusers')
if (-not $ok) { $failed = $true }

if ($failed) {
    Say ''
    Say 'THE SDSYS ACCOUNT IS NOT USABLE. Check the lines above.'
    Say 'Without it this machine has no SD administrator and no way into SD.'
    exit 1
}

if ($created) {
    Say ''
    Say 'SDSYS WINDOWS PASSWORD - shown once, and in this log:'
    Say ('    ' + $password)
    Say ''
    Say 'Sign in as SDSYS, start SD from an ELEVATED console ("Run as administrator"),'
    Say 'and you are the SD administrator. No SD password is needed for that: the'
    Say 'session is the Windows account.'
}

Say ''
Say ("OK: " + $AccountName + " is in Administrators and sdusers, and not in sdsshonly. the API is its to turn on: MODIFY.ACCOUNT SDSYS API.")
Say ("     log: " + $LogFile)
if ($created) { exit 0 } else { exit 2 }
