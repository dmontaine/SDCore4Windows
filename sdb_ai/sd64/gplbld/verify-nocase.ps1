# verify-nocase.ps1 - prove case insensitive comparison is switched on,
# PROJECT_STATUS.md 7 step 8.  Two halves, both of which were correct code that
# had never been reached: DHF_NOCASE on directory files (the C layer, dh_open.c)
# and SYSTEM(91) answering Windows (the BASIC layer, which is what lets QPROC
# treat a directory file's ids as case insensitive).
#
#   VerifyInstall1.ps1 -Run <token>           the only supported way to run it
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# ***IT RUNS AS A THROWAWAY NON-ADMINISTRATOR ACCOUNT SINCE 29 Aug 2026, AND
# THAT IS PRE_RELEASE 59.***  It used to drive sd.exe down a pipe as the
# invoking user, whose probe landed in their own account's BP.  PRE_RELEASE 56
# ended that: an administrator is elevated at LOGIN and lands in SDSYS, so on
# -Run b59 this found SDSYS's BP where it expected the account's and said so -
# "the probe did not run - no DIRFILE line", a refusal rather than a false
# pass.  The account it needs is not the invoking user's any more, because
# under 56 an administrator has none.
#
# ***THE OBVIOUS SHORTCUT IS A TRAP.***  Adding "LOGTO DON" here would pass
# today and break the moment adopt-account goes, which is ruled and pending
# (56's last piece).  A test standing on an account that exists only because
# the installer adopted the installing user is a test with a countdown on it.
#
# WHAT IT NEEDS, AND WHERE IT COMES FROM.  VerifyInstall1.ps1 creates ONE
# non-administrator account for the whole unelevated half before its step list
# and removes it after, and passes it here as -TestUser / -TestPassword.  This
# script does not make it, does not remove it, and REFUSES WITHOUT IT rather
# than falling back to the invoking user - the fallback is the false pass.
#
# NO ELEVATION.  Reaching the account is ssh, and the probe is planted through
# the file system into a directory the runner had an ACE added to at create
# time.  Nothing here depends on this process's token.
#
# WHAT IT MEASURES.  dh_open.c:529 sets DHF_NOCASE on directory files, which
# this tree now does unconditionally - it used to sit under
# CASE_INSENSITIVE_FILE_SYSTEM, a macro neither this tree nor sdb64 defines.
# A directory file's record ids ARE file names, and NTFS resolves SUE and sue
# to one file, so without the flag SD takes two record locks (op_lock.c) and
# two transaction cache entries (txn.c) on what is one file.
#
# THE DYNAMIC FILE IS THE CONTROL AND IS THE POINT OF THE TEST.  FILEINFO
# answering 1 for a directory file proves nothing on its own - a constant
# would do the same.  VOC is a dynamic file and takes its flags from its own
# header (dh_open.c:549), which this change did not touch, so it must still
# answer 0.  One moved, one did not, and only then is the flag being read
# rather than invented.
#
# THE LOCK COLLISION IS THE CONSEQUENCE, NOT THE CHANGE, and is not tested
# here.  Whether a READU on sue blocks a READU on SUE is downstream of this
# flag through op_lock.c, which has honoured DHF_NOCASE since long before this
# port.  What this port changed is whether the flag is SET, and that is what
# this measures.  A two-session lock test is still worth having one day; it is
# not what proves this change.
#
# IF THIS SCRIPT EVER BREAKS, the measurement underneath it is four lines and
# was done by hand first.  Write this into <account>\BP\SDNOCASE:
#
#       OPEN 'BP' TO F.DIR ELSE STOP 'cannot open BP'
#       OPEN 'VOC' TO F.DH ELSE STOP 'cannot open VOC'
#       CRT 'DIRFILE=':FILEINFO(F.DIR, 1008)
#       CRT 'DHFILE=':FILEINFO(F.DH, 1008)
#       CRT 'ISWIN=':SYSTEM(91)
#
# then send "BASIC BP SDNOCASE", "RUN BP SDNOCASE", "OFF" into an ssh session
# as that account.  ***NOT A LOCAL PIPE INTO sd.exe, WHICH IS WHAT THIS LINE
# SAID UNTIL 29 Aug 2026*** - a local pipe runs as the invoking user, and if
# that user is an administrator PRE_RELEASE 56 puts them in SDSYS, so the two
# FILEINFO answers would be about SDSYS's BP and VOC.  1008 is FL$NOCASE
# (SYSCOM KEYS.H), written as a literal so the probe does not depend on the
# include path from a user account.  pterm() CANNOT be used from a user account
# - it is internal-only and compiles as an undimensioned array - which is why
# SYSTEM() is the route to these.
#
# MEASURED BEFORE THE CHANGES, both by hand: DIRFILE=0 and DHFILE=0 on the
# 17:36:21 install, ISWIN=0 on the 20:10:31 one.  Those are the readings this
# script exists to see move - and DHFILE is the one that must NOT.

[CmdletBinding()]
param(
    # NOT Mandatory, DELIBERATELY, and the reason is the one written into
    # sdtestuser.ps1's Invoke-SdAsTestUser: Mandatory makes PowerShell's
    # parameter BINDER handle the empty case before this script's body runs -
    # and inside a runner a Mandatory parameter with nothing to bind PROMPTS,
    # which is a hang rather than an error.  That trap cost a run on 28 Aug
    # 2026 (VerifyInstall1.ps1's door-step comment).  The refusal below is the
    # guard; it must be reachable.
    [string] $TestUser = '',
    [string] $TestPassword = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

# ***REFUSE WITHOUT THE TEST ACCOUNT, OUT LOUD, AND BEFORE assert-current.***
# The line further down used to be "$account = $env:USERNAME.ToLower()" and
# falling back to it would be the worst available outcome: under PRE_RELEASE 56
# the invoking user is an administrator, LOGIN elevates them into SDSYS, and
# the probe would measure SDSYS's BP while the report said it had measured an
# ordinary account's.  A refusal that names what is missing beats a number that
# is about something else.
#
# IT COMES BEFORE assert-current DELIBERATELY, AND THAT IS NOT A RELAXATION OF
# THE RULE.  assert-current guards MEASUREMENTS - "compiling is not running" -
# and a missing argument measures nothing.  Putting it first also means the
# refusal can be driven by a unit test with NO INSTALL AT ALL, which is the
# only way this branch will ever be exercised regularly.
if ($TestUser -eq '' -or $TestPassword -eq '') {
    Write-Output 'verify-nocase: refusing - no test account was supplied.'
    Write-Output ("  -TestUser '{0}', -TestPassword {1}" -f
                  $TestUser, $(if ($TestPassword -eq '') { '(empty)' } else { '(given)' }))
    Write-Output ''
    Write-Output '  Since PRE_RELEASE 56 an administrator is elevated at LOGIN and lands in'
    Write-Output '  SDSYS, so there is no ordinary account for this to run as any more.  It'
    Write-Output '  needs a real non-administrator one, which VerifyInstall1 makes once for'
    Write-Output '  the whole unelevated half and passes in.  Run it that way:'
    Write-Output ''
    Write-Output '      C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\VerifyInstall1.ps1 -Run <token>'
    Write-Output ''
    Write-Output '  ORDINARY, UNELEVATED PowerShell.  The token is single-use.'
    exit 2
}

# A CURRENT INSTALL NEXT.  This measures a C change (gplsrc/dh_open.c), so a
# stale install answers for the binary that change replaced - which is exactly
# the reading being tested against.  CLAUDE.md: compiling is not running.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-nocase: refusing - see above'
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

$account = $TestUser.ToLower()
$acctDir = Get-SdTestUserHome -Name $account

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $step; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
}

# ---------------------------------------------------------------- preconditions

# A PRESENCE CHECK, NOT THE DRIVER.  Nothing here runs sd.exe any more - the
# session is ssh's, and sshd's ForceCommand starts SD at the far end.  The path
# is still worth asserting because "SD is not installed" and "the flag reads 0"
# should not look alike.
if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output "verify-nocase: refusing - no $sdExe"
    exit 2
}
if (-not (Test-Path -LiteralPath $acctDir)) {
    Write-Output "verify-nocase: refusing - $account has no SD account at $acctDir"
    Write-Output '  VerifyInstall1 said it created it; CREATE.ACCOUNT made no directory.'
    exit 2
}

# ***AND CAN THIS PROCESS ACTUALLY WRITE THERE.***  Measured 29 Aug 2026 and it
# is not a formality: an account directory is PROTECTED and grants Modify to
# SYSTEM, Administrators and its own sdu_<account> group ONLY - an unelevated
# token has none of the three, and a plain "ls" of one answered "Permission
# denied".  sdtestuser-admin.ps1 -Action Create adds an ACE for the invoking
# user; this is where a grant that did not land stops being four verifiers
# failing on four different wordings for one cause.
try {
    $null = Assert-SdTestUserHomeWritable -Name $account
} catch {
    Write-Output ('verify-nocase: refusing - ' + $_.Exception.Message)
    exit 2
}

$bp = Join-Path $acctDir 'BP'
if (-not (Test-Path -LiteralPath $bp)) {
    Write-Output "verify-nocase: refusing - $account has no BP file at $bp"
    exit 2
}

Write-Output "verify-nocase: probing as SD account $account (a throwaway non-administrator)"
Write-Output ("  account directory: " + $acctDir)
Write-Output ''

# ------------------------------------------------------------------- the probe

# WRITTEN STRAIGHT INTO THE FILE SYSTEM, WHICH IS THE WHOLE TRICK.  BP is a
# DIRECTORY file, so each record is a file on disk and a probe can be placed
# without driving ED through a pipe.  latin-1 and LF to match the BASIC sources
# this tree ships.
$probeSrc = Join-Path $bp 'SDNOCASE'
$probeObj = Join-Path $acctDir 'bp.out\SDNOCASE'

$src = @(
    "* SDNOCASE - written by gplbld/verify-nocase.ps1.  Safe to delete."
    "* 1008 is FL`$NOCASE (SYSCOM KEYS.H), literal to avoid an include path."
    "      OPEN 'BP' TO F.DIR ELSE STOP 'cannot open BP'"
    "      OPEN 'VOC' TO F.DH ELSE STOP 'cannot open VOC'"
    "      CRT 'DIRFILE=':FILEINFO(F.DIR, 1008)"
    "      CRT 'DHFILE=':FILEINFO(F.DH, 1008)"
    "      CRT 'ISWIN=':SYSTEM(91)"
) -join "`n"

[System.IO.File]::WriteAllText($probeSrc, $src + "`n",
                               [System.Text.Encoding]::GetEncoding('iso-8859-1'))

function Remove-Probe {
    foreach ($f in @($probeSrc, $probeObj)) {
        if (Test-Path -LiteralPath $f) {
            try { Remove-Item -LiteralPath $f -Force } catch {
                Write-Output "verify-nocase: WARNING - could not remove $f"
            }
        }
    }
}

# ***DRIVEN OVER ssh AS THE TEST ACCOUNT, NOT DOWN A LOCAL PIPE.***  A local
# pipe runs sd.exe as the INVOKING user, and under PRE_RELEASE 56 that is an
# administrator who is elevated at LOGIN into SDSYS - the wrong BP, which is
# exactly the failure this conversion repairs.
#
# ssh IS THE ROUTE BECAUSE runas CANNOT BE.  Accounts SD creates are in
# sdsshonly, which carries SeDenyInteractiveLogonRight (5.6.2), so an
# interactive logon as one is refused BY WINDOWS - and that refusal is the
# product working correctly, not an obstacle to route around.
#
# Invoke-SdAsTestUser sends TERM 200,9999 first and appends OFF, so nothing
# wraps (PRE_RELEASE 40, which cost a wrong verdict by counting a wrapped line
# twice) and the session ends rather than waiting on stdin.  The BOM sink the
# old local pipe needed is gone with the pipe: ssh's stdin is a file written
# with WriteAllText and carries no BOM.
try {
    $r = Invoke-SdAsTestUser -Name $account -Password $TestPassword `
             -Commands @('BASIC BP SDNOCASE', 'RUN BP SDNOCASE')
    $out = $r.Out
}
catch {
    Write-Output "verify-nocase: could not drive SD as $account : $($_.Exception.Message)"
    Remove-Probe
    exit 2
}

$text = ($out | Out-String)

# PRINT WHAT THE INSTRUMENT ACTUALLY DID, NOT ONLY WHAT IT CONCLUDED.  The ssh
# leg has three ways to come back empty that look alike from the numbers - a
# refused password, sshd not running, ForceCommand not starting SD - and none
# of them is "the flag reads 0".
Write-Output ("  ssh exit {0}, {1} characters of output" -f $r.ExitCode, $text.Length)
if ($r.Err -ne '') {
    Write-Output '  --- ssh stderr ---'
    foreach ($l in ($r.Err -split "`n")) { if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) } }
}

# A COMPILE FAILURE MUST NOT READ AS A MEASUREMENT.  If the probe did not
# build there is no FILEINFO line to find, and a missing line would otherwise
# be scored as "not 1" - a FAIL that blames the C change for a broken probe.
if ($text -notmatch 'DIRFILE=') {
    Write-Output 'verify-nocase: the probe did not run - no DIRFILE line in the output.'
    # 29 Aug 26 - AND SAY WHICH OF THE THREE IT WAS.  Over ssh the same silence
    # has causes that are nothing to do with the probe, and this used to print
    # the raw output and leave the reader to tell them apart.  Each of these is
    # a fact about the run, not a guess about it.
    Write-Output ("  ssh exit {0}; the account is {1}" -f $r.ExitCode, $account)
    if ($r.ExitCode -ne 0) {
        Write-Output '  A NON-ZERO ssh EXIT MEANS THE SESSION, NOT THE PROBE.  Check that sshd is'
        Write-Output ("  running, that {0} is in sdsshonly and sdssh, and that the password" -f $account)
        Write-Output '  VerifyInstall1 generated is the one CREATE.ACCOUNT was given.'
    } elseif ($text.Trim() -eq '') {
        Write-Output '  ssh SUCCEEDED AND SD PRINTED NOTHING, which points at ForceCommand not'
        Write-Output '  starting SD rather than at the probe failing to compile.'
    } else {
        Write-Output '  SD answered and did not reach the CRT lines, so read the compile below.'
    }
    Write-Output '  Raw output follows.'
    Write-Output $text
    Remove-Probe
    exit 2
}

$dirVal = if ($text -match 'DIRFILE=(\d+)') { $Matches[1] } else { '(none)' }
$dhVal  = if ($text -match 'DHFILE=(\d+)')  { $Matches[1] } else { '(none)' }
$winVal = if ($text -match 'ISWIN=(\d+)')   { $Matches[1] } else { '(none)' }

Remove-Probe

# ---------------------------------------------------------------------- report

Note 'directory file (BP) reports FL$NOCASE' '1' $dirVal $true
Note 'dynamic file (VOC) reports FL$NOCASE'  '0' $dhVal  $true

# SYSTEM(91) IS WHAT UNBLOCKS QPROC, and it is decisive for the same reason the
# rows above are: QPROC:499 is the only route by which the query processor
# treats a directory file's ids as case insensitive, because FL$FLAGS cannot
# answer for a directory file at all (op_dio2.c:439 gates it on dynamic).
# It read 0 before the change - on Windows.
Note 'SYSTEM(91) answers Windows'            '1' $winVal $true

$results | Format-Table -AutoSize | Out-String | Write-Output

if ($fatal) {
    Write-Output 'verify-nocase: FAILED.'
    Write-Output ''
    if ($dirVal -eq '0' -and $dhVal -eq '0') {
        Write-Output '  Both read 0, which is the reading from BEFORE the change - so the'
        Write-Output '  installed sd.exe predates dh_open.c:529. assert-current passed, so'
        Write-Output '  check that the cycle actually rebuilt and reinstalled the binary.'
    } elseif ($dhVal -ne '0') {
        Write-Output '  The DYNAMIC file moved, which this change should not have touched.'
        Write-Output '  Dynamic files take their flags from their own header (dh_open.c:549);'
        Write-Output '  if that moved, something wider than step 8 has changed.'
    }
    exit 1
}

Write-Output 'verify-nocase: PASSED - directory files are case insensitive, dynamic files unchanged.'
exit 0
