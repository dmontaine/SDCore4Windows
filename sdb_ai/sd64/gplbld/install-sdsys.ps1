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
#   sdssh, sdapi,    NOT JOINED, DELIBERATELY.  SDSYS has no remote door: an ssh
#   sdsshonly        or API logon is not an elevated Windows session, so LOGIN's
#                    own guard refuses it (10002).  Joining would put an account
#                    that is always refused into the group that decides who may
#                    connect - a lie in the grant, which is what entry 63 was
#                    about.  It also keeps the account out of sdsshonly, whose
#                    SeDenyInteractiveLogonRight would lock SDSYS out of its own
#                    console.
#
# THE PASSWORD IS GENERATED, PRINTED AND LOGGED, FOR THE SAME REASON THE RELAY
# ACCOUNT'S IS.  Nobody types it but the owner, who has to sign in as SDSYS to
# administer SD at all, so it is shown at the end of the run and written to this
# script's log beside the tree.  SD's own credential register is empty at install
# (the cycle prints "NO ACCOUNT HAS A PASSWORD") and a console login is by
# Windows identity, so SD needs no password of SDSYS's - this one is Windows'.
# The account keeps it until somebody changes it, and `net user SDSYS *` does
# that at any time.
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
    $bytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
    $chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789!#%+=?'
    $s = ''
    foreach ($b in $bytes) { $s += $chars[$b % $chars.Length] }
    return $s
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
foreach ($g in @('sdssh', 'sdapi', 'sdsshonly')) {
    if (Test-SdsysMembership $g) {
        Remove-LocalGroupMember -Group $g -Member $AccountName -ErrorAction SilentlyContinue
        Say ("  removed " + $AccountName + " from " + $g + " - it has no remote door")
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
Say ("OK: " + $AccountName + " is in Administrators and sdusers, and in no ssh or API group.")
Say ("     log: " + $LogFile)
if ($created) { exit 0 } else { exit 2 }
