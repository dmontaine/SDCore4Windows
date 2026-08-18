# verify-nocase.ps1 - prove directory files open case insensitive,
# PROJECT_STATUS.md 7 step 8.
#
#   powershell -File verify-nocase.ps1        run the checks
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# RUN IT AS AN ORDINARY SD USER.  It needs no elevation: the probe opens two
# files in the invoking user's OWN account and asks SD about them.  Elevation
# is not refused either, because nothing here depends on the token.
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
#
# then pipe "BASIC BP SDNOCASE", "RUN BP SDNOCASE", "OFF" into sd.exe.  1008 is
# FL$NOCASE (SYSCOM KEYS.H), written as a literal so the probe does not depend
# on the include path from a user account.
#
# MEASURED BEFORE THE CHANGE, on the 17 Aug 2026 17:36:21 install: DIRFILE=0
# and DHFILE=0.  That is the reading this script exists to see move.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# A CURRENT INSTALL FIRST.  This measures a C change (gplsrc/dh_open.c), so a
# stale install answers for the binary that change replaced - which is exactly
# the reading being tested against.  CLAUDE.md: compiling is not running.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-nocase: refusing - see above'
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

# THE SD ACCOUNT IS THE WINDOWS NAME IN UPPER CASE.  CREATE_USER stamps the
# account that way and adopt-account.ps1 follows it, so DON is don's account.
# If step 8's wider half ever removes that upcasing, this line is one of the
# places that has to change with it.
$account = $env:USERNAME.ToUpper()
$acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $account)

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

if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output "verify-nocase: refusing - no $sdExe"
    exit 2
}
if (-not (Test-Path -LiteralPath $acctDir)) {
    Write-Output "verify-nocase: refusing - $account has no SD account at $acctDir"
    Write-Output '  Only an account holder can run this; the probe lives in their own BP.'
    exit 2
}

$bp = Join-Path $acctDir 'BP'
if (-not (Test-Path -LiteralPath $bp)) {
    Write-Output "verify-nocase: refusing - $account has no BP file at $bp"
    exit 2
}

Write-Output "verify-nocase: probing as SD account $account"
Write-Output ''

# ------------------------------------------------------------------- the probe

# WRITTEN STRAIGHT INTO THE FILE SYSTEM, WHICH IS THE WHOLE TRICK.  BP is a
# DIRECTORY file, so each record is a file on disk and a probe can be placed
# without driving ED through a pipe.  latin-1 and LF to match the BASIC sources
# this tree ships.
$probeSrc = Join-Path $bp 'SDNOCASE'
$probeObj = Join-Path $acctDir 'BP.OUT\SDNOCASE'

$src = @(
    "* SDNOCASE - written by gplbld/verify-nocase.ps1.  Safe to delete."
    "* 1008 is FL`$NOCASE (SYSCOM KEYS.H), literal to avoid an include path."
    "      OPEN 'BP' TO F.DIR ELSE STOP 'cannot open BP'"
    "      OPEN 'VOC' TO F.DH ELSE STOP 'cannot open VOC'"
    "      CRT 'DIRFILE=':FILEINFO(F.DIR, 1008)"
    "      CRT 'DHFILE=':FILEINFO(F.DH, 1008)"
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

# THE LEADING BLANK LINE IS A BOM SINK, not a stray newline.  The pipe prepends
# a BOM to the first line whatever $OutputEncoding says, and SD answers that it
# is not in your VOC; landing it on a line that was empty anyway costs one
# harmless complaint instead of eating a real command.  PROJECT_STATUS.md 6.
try {
    $body = "`n" + (@('BASIC BP SDNOCASE', 'RUN BP SDNOCASE', 'OFF') -join "`n") + "`n"
    $raw  = $body | & $sdExe 2>&1
    $out  = ($raw -replace "`e\[[0-9]*[A-Za-z]", '')
}
catch {
    Write-Output "verify-nocase: could not drive sd.exe: $($_.Exception.Message)"
    Remove-Probe
    exit 2
}

$text = ($out | Out-String)

# A COMPILE FAILURE MUST NOT READ AS A MEASUREMENT.  If the probe did not
# build there is no FILEINFO line to find, and a missing line would otherwise
# be scored as "not 1" - a FAIL that blames the C change for a broken probe.
if ($text -notmatch 'DIRFILE=') {
    Write-Output 'verify-nocase: the probe did not run - no DIRFILE line in the output.'
    Write-Output '  Raw output follows.'
    Write-Output $text
    Remove-Probe
    exit 2
}

$dirVal = if ($text -match 'DIRFILE=(\d+)') { $Matches[1] } else { '(none)' }
$dhVal  = if ($text -match 'DHFILE=(\d+)')  { $Matches[1] } else { '(none)' }

Remove-Probe

# ---------------------------------------------------------------------- report

Note 'directory file (BP) reports FL$NOCASE' '1' $dirVal $true
Note 'dynamic file (VOC) reports FL$NOCASE'  '0' $dhVal  $true

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
