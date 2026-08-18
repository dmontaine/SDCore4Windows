# verify-osusers.ps1 - prove @SDSYS/OS.USERS PERMITS a shell, and not merely
# that it refuses one.  PROJECT_STATUS.md 7 step 7.
#
#   powershell -File verify-osusers.ps1        run the whole test
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# THE ADMIT PATH IS THE HALF THAT WAS NEVER SEEN.  OS.USERS shipped empty, so
# every observation of it up to 17 Aug 2026 was a REFUSAL - and a gate that
# refuses everybody is indistinguishable from one that is simply broken.  The
# question this answers is the other one: put a name on the list, and does that
# name get a shell it did not have a moment earlier?
#
# RUN IT UNELEVATED, AND THAT IS THE SUBJECT, NOT A CONVENIENCE.  CPROC admits
# K$ADMINISTRATOR whatever the list says (CPROC:3448), deliberately, so an
# elevated run is admitted BY ELEVATION and proves nothing about OS.USERS at
# all.  The script refuses to run elevated for the same reason
# verify-credacl.ps1 does.
#
# IT WILL ASK FOR ELEVATION TWICE, and cannot avoid it.  Writing the record and
# removing it again need an administrator - that ACL is the entire protection
# (gplbld/secure-osusers.ps1) - while the measurement must not have one.  The
# two halves cannot share a token, so the unelevated half drives and elevates
# for the two writes.  Elevating is easy; de-elevating faithfully is not.
#
# WHAT IS DECISIVE IS THE MARKER FILE, NOT THE MESSAGE.  Each SH probe runs a
# command whose only job is to create a file, and the file is what is scored:
# it cannot be produced by SD echoing the command back, and it cannot be
# missing on a run that really happened.  The messages are read too, and they
# are what tells the two refusals apart - 10053 the gate, 5240 the
# metacharacter ban - which is the same discrimination the API test rests on,
# sysmsg(5017) against sysmsg(10003).
#
# THE PROBES CARRY NO SHELL METACHARACTER BY ACCIDENT.  !valid_shell_cmd bans
# ; | & $ ` < > so the plain probes may use none of them - no $env:, no
# redirection - and the piped probes exist precisely to carry the one banned
# character that matters.  The marker directory is checked for all eight before
# anything runs, because a path with a $ in it would refuse the plain probe and
# read as a failure of the gate.
#
# THE CONTROLS, and none of the admits mean anything without them:
#
#   unelevated, unlisted   SH refused 10053, no marker    <- before
#   ELEVATED,   unlisted   SH admitted                    <- elevation still
#                                                            passes on its own
#   ELEVATED,   unlisted   SH with a pipe refused 5240    <- the ban is intact
#                                                            for the unlisted
#   unelevated, LISTED     SH admitted                    <- THE OWED TEST
#   unelevated, LISTED     SH with a pipe admitted        <- the ban is lifted
#   unelevated, unlisted   SH refused 10053 again         <- and it was the
#                                                            record that did it
#
# The last row is what stops a pass being read into an install that admits
# everybody: the permission has to go away again when the record does.
#
# IF THE ADMIT FAILS, READ THE PROBE'S OPEN= LINE FIRST.  CPROC reads the list
# from the user's OWN process and secure-osusers.ps1 grants sdusers (RX), so
# whether an unelevated OPENPATH of a read-only directory file succeeds is the
# first thing that could make this design not work at all.  The probe answers
# that from inside SD, which no icacls listing can.

[CmdletBinding()]
param(
    # Internal.  The two elevated halves re-enter this script through
    # Start-Process -Verb RunAs; nobody types these.
    [ValidateSet('', 'Grant', 'Revoke')] [string] $Phase = '',
    [string] $LogName = '',
    [string] $ResultFile = '',
    [string] $MarkerDir = ''
)

$ErrorActionPreference = 'Stop'

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$osUsers = Join-Path $env:ProgramData 'SD\sdsys\OS.USERS'

# DRIVING SD FROM POWERSHELL has two traps, both in PROJECT_STATUS.md 6: input
# must be PIPED rather than redirected, and the pipe prepends a BOM to the first
# line, so a blank sacrificial line absorbs it.  TERM 200,9999 keeps SD from
# wrapping the messages this script matches on.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"

    # EAP IS LOWERED ACROSS THE CALL.  Under Stop, 2>&1 on a native command
    # turns each stderr line into a terminating NativeCommandError - the trap
    # written up in secure-cred.ps1 and met again in verify-credacl.ps1.
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $raw = $body | & $sdExe 2>&1
    $ErrorActionPreference = $prev

    # [char]27 AND NOT `e.  Windows PowerShell 5.1 has no `e escape - it is
    # PowerShell 6 and later - so "`e\[..." is the literal letter e and the
    # strip silently does nothing.  verify-nocase.ps1 and verify-tiers.ps1 both
    # carry that line and neither has ever stripped an escape sequence; it has
    # not cost them anything because they match on substrings, as this does.
    # Measured 18 Aug 2026: TERM 200,9999 came back as "TERM<ESC>[7G200,9999".
    $esc = [char]27
    return (($raw -replace ($esc + '\[[0-9]*[A-Za-z]'), '') | Out-String)
}

# The whole SD command line a probe types, SH INCLUDED.  Its job is to create
# one file; New-Item -Force truncates an existing one, which is wanted, since a
# stale marker from an interrupted run must never be able to read as a pass.
#
# THE SH PREFIX BELONGS HERE AND WAS ONCE LEFT TO THE CALLER, which cost a run
# on 18 Aug 2026: every probe went in as a bare "New-Item ...", SD answered
# "New-Item is not in your VOC", no marker appeared, and six decisive checks
# FAILED without the gate under test ever being reached.  Assert-ProbeRan below
# is what stops that reading as a refusal a second time.
function New-ProbeCmd([string]$marker, [bool]$piped) {
    if ($piped) { return "SH New-Item -ItemType File -Path $marker -Force | Out-Null" }
    return "SH New-Item -ItemType File -Path $marker -Force"
}

# A PROBE THAT NEVER REACHED THE GATE IS NOT A REFUSAL BY IT.  "not in your VOC"
# is message 5051 and means CPROC never got as far as os.command:, so no marker
# is the absence of a test rather than the presence of a boundary.  Returns
# $true if the probe was really typed at the gate.
function Test-ProbeRan([string]$text) {
    return (-not ($text -match 'New-Item is not in your VOC'))
}

function Remove-Marker([string]$marker) {
    if (Test-Path -LiteralPath $marker) {
        try { Remove-Item -LiteralPath $marker -Force } catch { }
    }
}

# ===========================================================================
# The elevated halves.  Each is a separate process behind its own UAC prompt,
# writes what it saw to -ResultFile as RESULT: lines, and says the rest for the
# transcript the unelevated parent prints.
# ===========================================================================

if ($Phase -ne '') {
    $out = New-Object System.Collections.ArrayList
    function Say($t) { $null = $out.Add($t); Write-Output $t }

    # NO BOM.  Set-Content -Encoding UTF8 writes one on Windows PowerShell 5.1,
    # and it lands on the FIRST line - so the parent's "^RESULT: ..." would fail
    # to match line 1 and silently lose whichever key happened to be there.
    function Write-ResultFile {
        [System.IO.File]::WriteAllLines($ResultFile, [string[]]$out,
                                        (New-Object System.Text.UTF8Encoding($false)))
    }

    $record = Join-Path $osUsers $LogName

    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Say 'RESULT: elevated=no'
        Write-ResultFile
        exit 2
    }
    Say 'RESULT: elevated=yes'

    if ($Phase -eq 'Grant') {
        # THE TWO ELEVATED CONTROLS, TAKEN WHILE THE LIST IS STILL EMPTY.  They
        # have to be taken here and now: once the record exists this session is
        # listed as well, and neither question can be asked again.
        $mc = Join-Path $MarkerDir 'elev-plain'
        $md = Join-Path $MarkerDir 'elev-piped'
        Remove-Marker $mc
        Remove-Marker $md

        $t = Invoke-SD @((New-ProbeCmd $mc $false), (New-ProbeCmd $md $true))
        Say '--- elevated, unlisted, SD output ---'
        Say $t.TrimEnd()

        Say ('RESULT: elev_reached=' + $(if (Test-ProbeRan $t) { 'yes' } else { 'no' }))
        Say ('RESULT: elev_plain=' + $(if (Test-Path -LiteralPath $mc) { 'ran' } else { 'refused' }))
        Say ('RESULT: elev_piped=' + $(if (Test-Path -LiteralPath $md) { 'ran' } else { 'refused' }))
        Say ('RESULT: elev_msg10053=' + $(if ($t -match 'not permitted to use the operating system shell') { 'yes' } else { 'no' }))
        Say ('RESULT: elev_msg5240=' + $(if ($t -match 'executing operating system command') { 'yes' } else { 'no' }))

        Remove-Marker $mc
        Remove-Marker $md

        # THE RECORD.  OS.USERS is a DIRECTORY file, so a record is a file and a
        # field mark is a newline - the same route verify-nocase.ps1 uses to
        # place a BP program without driving ED through a pipe.  Field 1 is SH
        # and field 2 is OS.EX; OS.EX is stored, dictionaried and READ BY NOBODY
        # (step 7), so "no" here documents intent and enforces nothing.
        if (Test-Path -LiteralPath $record) {
            Say 'RESULT: granted=already-there'
        } else {
            [System.IO.File]::WriteAllText($record, "yes`nno`n",
                                           [System.Text.Encoding]::GetEncoding('iso-8859-1'))
            Say ('RESULT: granted=' + $(if (Test-Path -LiteralPath $record) { 'yes' } else { 'no' }))
        }
        Say "RESULT: record=$record"
    }

    if ($Phase -eq 'Revoke') {
        if (Test-Path -LiteralPath $record) { Remove-Item -LiteralPath $record -Force }
        Say ('RESULT: revoked=' + $(if (Test-Path -LiteralPath $record) { 'no' } else { 'yes' }))
    }

    Write-ResultFile
    exit 0
}

# ===========================================================================
# The unelevated test.
# ===========================================================================

# IT WRITES A TRANSCRIPT, for the reason verify-tiers.ps1 gives: in this project
# the person who ran an elevated step does not paste its output back, so a
# verifier whose result lives only in a console window has reported nothing.
# Not under C:\ProgramData\SD - cycle.ps1 deletes that tree.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-osusers-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ('transcript: ' + $logPath)

# A CURRENT INSTALL FIRST.  This measures a BASIC change (GPL.BP/CPROC) and an
# installer step (secure-osusers.ps1), so a stale install answers for the tree
# that change replaced.  CLAUDE.md: compiling is not running.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-osusers: refusing - see above'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-osusers: refusing - this window is ELEVATED.'
    Write-Output ''
    Write-Output '  CPROC admits K$ADMINISTRATOR whatever OS.USERS says, so an'
    Write-Output '  elevated run is admitted by elevation and says nothing about'
    Write-Output '  the list. Run it from an ordinary window, as the account'
    Write-Output '  holder whose shell is in question. It will prompt for the'
    Write-Output '  elevation it needs, twice.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

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
    Write-Output ('  [{0}] {1}: expected {2}, got {3}' -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $step, $expected, $got)
}

function Stop-Here([int]$code, [string]$why) {
    Write-Output ''
    Write-Output "verify-osusers: $why"
    try { Stop-Transcript | Out-Null } catch { }
    exit $code
}

# ---------------------------------------------------------------- preconditions

if (-not (Test-Path -LiteralPath $sdExe))   { Stop-Here 2 "refusing - no $sdExe" }
if (-not (Test-Path -LiteralPath $osUsers)) { Stop-Here 2 "refusing - no $osUsers; the bootstrap did not run" }

# THE ACCOUNT DIRECTORY IS THE WINDOWS NAME, and its CASE is not to be assumed:
# CREATE_USER upcases it, the adopted account on this machine is lower case, and
# NTFS resolves either - so look for the real one rather than carrying a guess.
$acctRoot = Join-Path $env:ProgramData 'SD\user_accounts'
$acctDir  = $null
foreach ($n in @($env:USERNAME.ToUpper(), $env:USERNAME)) {
    $p = Join-Path $acctRoot $n
    if (Test-Path -LiteralPath $p) { $acctDir = $p; break }
}
if ($null -eq $acctDir) {
    Stop-Here 2 "refusing - $env:USERNAME has no SD account under $acctRoot. Only an account holder can run this."
}
$bp = Join-Path $acctDir 'BP'
if (-not (Test-Path -LiteralPath $bp)) {
    Stop-Here 2 "refusing - no BP in $acctDir; the diagnostic probe has nowhere to live."
}

# THE MARKER DIRECTORY MUST BE SAFE TO NAME IN AN SH COMMAND.  A space would
# break the PowerShell command line the probe becomes, and any of the eight
# banned metacharacters would be refused by !valid_shell_cmd - which would read
# as the gate refusing, and be nothing of the kind.
$markerDir = Join-Path $logDir 'osusers'
if ($markerDir -match '[ ;|&$`<>]') { $markerDir = Join-Path $env:ProgramData 'SD\verify-osusers' }
if ($markerDir -match '[ ;|&$`<>]') {
    Stop-Here 2 "refusing - no marker directory can be named without a space or a shell metacharacter (tried $markerDir)."
}
if (-not (Test-Path -LiteralPath $markerDir)) { $null = New-Item -ItemType Directory -Path $markerDir -Force }

Write-Output "verify-osusers: testing $osUsers"
Write-Output "  as $($id.Name), unelevated; SD account directory $acctDir"
Write-Output "  markers in $markerDir"
Write-Output ''

# --------------------------------------------------- 0. what CPROC will look up

Write-Output '=== 0. The record key, and whether the list can be read at all ============'

# @LOGNAME IS THE KEY, AND IS NOT $env:USERNAME BY ASSUMPTION.  CPROC reads
# OS.USERS by @logname (CPROC:3443) - the person, not the account - so the probe
# asks SD what that string is rather than this script deciding.  It also answers
# the OPENPATH question, which is the first thing that could make the whole
# design not work: the file is (RX) to sdusers and CPROC opens it from the
# user's own process.
$probeSrc = Join-Path $bp 'SDOSUSER'
$probeObj = Join-Path $acctDir 'BP.OUT\SDOSUSER'
$src = @(
    "* SDOSUSER - written by gplbld/verify-osusers.ps1.  Safe to delete."
    "      CRT 'LOGNAME=':@LOGNAME"
    "      OPENPATH @SDSYS:@DS:'OS.USERS' TO F.OSU THEN"
    "         CRT 'OPEN=1'"
    "         READ OSU.REC FROM F.OSU, @LOGNAME THEN"
    "            CRT 'REC=':OSU.REC<1>"
    "         END ELSE"
    "            CRT 'REC=(none)'"
    "         END"
    "      END ELSE"
    "         CRT 'OPEN=0'"
    "      END"
    "   END"
) -join "`n"
[System.IO.File]::WriteAllText($probeSrc, $src + "`n",
                               [System.Text.Encoding]::GetEncoding('iso-8859-1'))

function Remove-Probe {
    foreach ($f in @($probeSrc, $probeObj)) {
        if (Test-Path -LiteralPath $f) {
            try { Remove-Item -LiteralPath $f -Force } catch {
                Write-Output "verify-osusers: WARNING - could not remove $f"
            }
        }
    }
}

function Invoke-Probe {
    return (Invoke-SD @('BASIC BP SDOSUSER', 'RUN BP SDOSUSER'))
}

$probeText = Invoke-Probe

# A PROBE THAT DID NOT RUN MUST NOT READ AS A MEASUREMENT.  Without a LOGNAME
# line this script would be guessing the record key, and a guess that is wrong
# fails the admit for a reason that has nothing to do with the gate.
if ($probeText -notmatch 'LOGNAME=') {
    Write-Output $probeText
    Remove-Probe
    Stop-Here 2 'the probe did not run - no LOGNAME line above. The test cannot name the record.'
}

$logNameValue = ([regex]::Match($probeText, 'LOGNAME=(\S+)')).Groups[1].Value
$openedOk     = ($probeText -match 'OPEN=1')
$recBefore    = if ($probeText -match 'REC=(\S*)') { $Matches[1] } else { '(no line)' }

Write-Output "  @LOGNAME is $logNameValue"
Note 'unelevated OPENPATH of OS.USERS succeeds' 'yes' $(if ($openedOk) { 'yes' } else { 'no' }) $true
Note 'record present before the test'           '(none)' $recBefore $false

$record = Join-Path $osUsers $logNameValue

# ASKED TWICE, AND THE SECOND ONE IS NOT REDUNDANT.  This script REMOVES the
# record when it finishes, so a record that was already there would be
# destroyed - somebody's real shell permission, taken away by a test.  SD
# answering "(none)" is one witness; if its READ failed for any reason other
# than absence it would say the same thing.  OS.USERS is (RX) to sdusers, so
# the filesystem can be asked directly, and it is.
if ($recBefore -ne '(none)' -or (Test-Path -LiteralPath $record)) {
    Remove-Probe
    Stop-Here 2 ("refusing - $logNameValue is ALREADY on the list. This measures the transition, " +
                 "so it has to start with the name absent - and it would remove $record " +
                 'when it finished, which is not this test''s to do. Take it off from an ' +
                 'elevated prompt and run this again.')
}

# ------------------------------------------------------ 1. the ACL, decisively

Write-Output ''
Write-Output '=== 1. Can an ordinary user put their own name on the list? ==============='

# THE $CRED LESSON, ASKED OF THIS FILE.  The data tree grants sdusers Modify and
# OS.USERS sits inside it, so without secure-osusers.ps1 the permission list is
# writable by exactly the people it restrains, and every check below it is
# decoration.  Nothing checked the $CRED ACL either, and it shipped open for a
# whole session.  The question is asked the way an attacker would ask it - by
# writing - not by reading a listing.
$aclProbe = Join-Path $osUsers 'verify-osusers-probe'
$wrote = $false
try {
    $fs = [System.IO.File]::Open($aclProbe, [System.IO.FileMode]::CreateNew,
                                 [System.IO.FileAccess]::Write)
    $fs.Close()
    $wrote = $true
}
catch [System.UnauthorizedAccessException] { $wrote = $false }
catch {
    Write-Output "verify-osusers: the ACL probe could not be run: $($_.Exception.Message)"
    Remove-Probe
    Stop-Here 2 'the ACL question was not answered, so nothing below it can be trusted.'
}
if ($wrote) { try { Remove-Item -LiteralPath $aclProbe -Force } catch { } }

Note 'ordinary user can add a record to OS.USERS' 'no' $(if ($wrote) { 'yes' } else { 'no' }) $true

# ------------------------------------------------- 2. unelevated, unlisted: no

Write-Output ''
Write-Output '=== 2. Unelevated and unlisted - the before reading ======================='

$mBeforePlain = Join-Path $markerDir 'before-plain'
$mBeforePiped = Join-Path $markerDir 'before-piped'
Remove-Marker $mBeforePlain
Remove-Marker $mBeforePiped

$before = Invoke-SD @((New-ProbeCmd $mBeforePlain $false), (New-ProbeCmd $mBeforePiped $true))
Write-Output '--- SD output ---'
Write-Output $before.TrimEnd()
Write-Output '-----------------'

# "SH is not in your VOC" IS NOT A REFUSAL BY THE GATE.  A standard-tier account
# has neither SH nor BASIC (NEWVOC/TIER.OMIT.STANDARD), so say so rather than
# scoring an absent verb as a working gate.
# SD does NOT quote the name in message 5051 - measured 18 Aug 2026, where a
# BOM came back as "<BOM> is not in your VOC" - so this matches it unquoted.
if ($before -match 'SH is not in your VOC') {
    Remove-Probe
    Stop-Here 2 ("refusing - SH is not in $logNameValue's VOC. Only a PROGRAMMER or " +
                 'ADMINISTRATOR account has the verb at all, so there is no gate to measure here.')
}
if (-not (Test-ProbeRan $before)) {
    Remove-Probe
    Stop-Here 2 ('the probe never reached the gate - SD answered "not in your VOC" for the ' +
                 'probe command itself, so no marker means no test rather than a refusal.')
}

Note 'unlisted: plain SH creates its marker' 'no' $(if (Test-Path -LiteralPath $mBeforePlain) { 'yes' } else { 'no' }) $true
Note 'unlisted: piped SH creates its marker' 'no' $(if (Test-Path -LiteralPath $mBeforePiped) { 'yes' } else { 'no' }) $true
Note 'unlisted: refused with message 10053'  'yes' $(if ($before -match 'not permitted to use the operating system shell') { 'yes' } else { 'no' }) $true

# THE MESSAGE CARRIES @logname AND IS THE SECOND WITNESS TO THE KEY.  CPROC
# prints the same string it looked the record up with, so if this disagrees with
# the probe, the record about to be written is named wrong.
$msgName = if ($before -match '(\S+) is not permitted to use the operating system shell') { $Matches[1] } else { '(not printed)' }
Note 'the refusal names the same @logname the probe reported' $logNameValue $msgName $false

Remove-Marker $mBeforePlain
Remove-Marker $mBeforePiped

# ------------------------------------------------------------------ 3. grant it

Write-Output ''
Write-Output '=== 3. Elevating to put the name on the list =============================='
Write-Output '  UAC will prompt. The elevated half also takes the two controls that can'
Write-Output '  only be taken while the list is still empty.'

# NEITHER OF THESE RETURNS A VALUE, AND THAT IS DELIBERATE.  A PowerShell
# function returns EVERYTHING it writes, so a helper that both prints and
# returns hands its caller an array with the printed lines in front of the
# answer - $rc would be a string array and "$rc -ne 0" would be a comparison
# nobody meant.  Both of these print, so both report through a script-scope
# variable instead and have no return value at all.
$script:elevExit    = -1
$script:elevResults = @{}

function Invoke-ElevatedPhase([string]$phase, [string]$resultPath) {
    $script:elevExit = -1
    $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass',
           '-File',       ('"' + $PSCommandPath + '"'),
           '-Phase',      $phase,
           '-LogName',    $logNameValue,
           '-ResultFile', ('"' + $resultPath + '"'),
           '-MarkerDir',  ('"' + $markerDir + '"'))
    try {
        $p = Start-Process -FilePath 'powershell.exe' -ArgumentList $a -Verb RunAs -Wait -PassThru
        $script:elevExit = $p.ExitCode
    }
    catch {
        # A declined or unavailable UAC prompt.  Over ssh there is no interactive
        # desktop to draw one on at all - sd-elevate.ps1 says why.
        Write-Output "verify-osusers: elevation for $phase did not happen: $($_.Exception.Message)"
    }
}

function Read-ElevResults([string]$resultPath) {
    $h = @{}
    if (-not (Test-Path -LiteralPath $resultPath)) {
        Write-Output '  (the elevated half wrote no result file)'
        $script:elevResults = $h
        return
    }
    $text = Get-Content -LiteralPath $resultPath
    Write-Output '--- from the elevated half ---'
    $text | ForEach-Object { Write-Output ('  ' + $_) }
    Write-Output '------------------------------'
    foreach ($line in $text) {
        if ($line -match '^RESULT: (\w+)=(.*)$') { $h[$Matches[1]] = $Matches[2] }
    }
    $script:elevResults = $h
}

$stamp      = Get-Date -Format 'yyyyMMdd-HHmmss'
$resultFile = Join-Path $logDir ('verify-osusers-grant-' + $stamp + '.txt')
$granted    = $false

try {
    Invoke-ElevatedPhase 'Grant' $resultFile
    $rc = $script:elevExit
    Read-ElevResults $resultFile
    $elev = $script:elevResults

    if ($rc -ne 0 -or $null -eq $elev['granted']) {
        Remove-Probe
        Stop-Here 2 "the elevated half did not complete (exit $rc). Nothing was measured and nothing was left behind."
    }
    $granted = ($elev['granted'] -eq 'yes' -or $elev['granted'] -eq 'already-there')

    Note 'the record was written' 'yes' $(if ($granted) { 'yes' } else { 'no' }) $true

    if ($elev['elev_reached'] -ne 'yes') {
        Remove-Probe
        Stop-Here 2 ('the elevated probe never reached the gate - SD answered "not in your VOC" ' +
                     'for the probe command itself. Its two controls measured nothing.')
    }

    # The two controls that had to be taken while the list was still empty.
    Note 'ELEVATED and unlisted: plain SH still runs' 'ran'     $elev['elev_plain'] $true
    Note 'ELEVATED and unlisted: piped SH is refused' 'refused' $elev['elev_piped'] $true
    Note 'ELEVATED refusal is the ban (5240), not the gate (10053)' 'yes' `
         $(if ($elev['elev_msg5240'] -eq 'yes' -and $elev['elev_msg10053'] -eq 'no') { 'yes' } else { 'no' }) $true

    if (-not $granted) {
        Remove-Probe
        Stop-Here 1 'the record could not be written, so the admit path cannot be measured.'
    }

    # ---------------------------------------------- 4. unelevated, LISTED: yes

    Write-Output ''
    Write-Output '=== 4. Unelevated and LISTED - the reading this whole step is for ========'

    $mAfterPlain = Join-Path $markerDir 'after-plain'
    $mAfterPiped = Join-Path $markerDir 'after-piped'
    Remove-Marker $mAfterPlain
    Remove-Marker $mAfterPiped

    $after = Invoke-SD @((New-ProbeCmd $mAfterPlain $false), (New-ProbeCmd $mAfterPiped $true))
    Write-Output '--- SD output ---'
    Write-Output $after.TrimEnd()
    Write-Output '-----------------'

    if (-not (Test-ProbeRan $after)) {
        Remove-Probe
        Stop-Here 2 ('the listed probe never reached the gate - SD answered "not in your VOC" ' +
                     'for the probe command itself. Nothing about the admit path was measured.')
    }

    Note 'LISTED: plain SH creates its marker' 'yes' $(if (Test-Path -LiteralPath $mAfterPlain) { 'yes' } else { 'no' }) $true
    Note 'LISTED: piped SH creates its marker' 'yes' $(if (Test-Path -LiteralPath $mAfterPiped) { 'yes' } else { 'no' }) $true
    Note 'LISTED: no 10053 refusal'            'no'  $(if ($after -match 'not permitted to use the operating system shell') { 'yes' } else { 'no' }) $true

    $probeAfter = Invoke-Probe
    $recAfter = if ($probeAfter -match 'REC=(\S*)') { $Matches[1] } else { '(no line)' }
    Note 'SD reads the record back as yes' 'yes' $recAfter $false

    Remove-Marker $mAfterPlain
    Remove-Marker $mAfterPiped
}
finally {
    # ---------------------------------------------------- 5. take it away again

    if ($granted) {
        Write-Output ''
        Write-Output '=== 5. Elevating to take the name off again =============================='
        Write-Output '  UAC will prompt a second time. The tree is left as it was found.'

        $revokeFile = Join-Path $logDir ('verify-osusers-revoke-' + $stamp + '.txt')
        Invoke-ElevatedPhase 'Revoke' $revokeFile
        $rc2 = $script:elevExit
        Read-ElevResults $revokeFile
        $rev = $script:elevResults

        if ($rc2 -ne 0 -or $rev['revoked'] -ne 'yes') {
            Write-Output ''
            Write-Output 'verify-osusers: WARNING - THE RECORD IS STILL THERE. Remove it from an elevated prompt:'
            Write-Output "    del `"$record`""
            $script:fatal = $true
        }
        else {
            Note 'the record was removed again' 'yes' 'yes' $false

            # THE LOOP CLOSES HERE.  Everything above is equally consistent with
            # an install that admits everybody; what rules that out is the shell
            # going away again with the record.
            $mEnd = Join-Path $markerDir 'end-plain'
            Remove-Marker $mEnd
            $end = Invoke-SD @((New-ProbeCmd $mEnd $false))
            Write-Output '--- SD output ---'
            Write-Output $end.TrimEnd()
            Write-Output '-----------------'
            Note 'record gone: SH is refused again'   'no'  $(if (Test-Path -LiteralPath $mEnd) { 'yes' } else { 'no' }) $true
            Note 'record gone: message 10053 is back' 'yes' $(if ($end -match 'not permitted to use the operating system shell') { 'yes' } else { 'no' }) $true
            Remove-Marker $mEnd
        }
    }

    Remove-Probe
}

# ---------------------------------------------------------------------- report

Write-Output ''
$results | Format-Table -AutoSize | Out-String | Write-Output

if ($fatal) {
    Write-Output 'verify-osusers: FAILED.'
    Write-Output ''
    if (-not $openedOk) {
        Write-Output '  OPENPATH of OS.USERS failed for an unelevated user, which is the first'
        Write-Output '  thing to rule out: CPROC reads the list from the user''s own process and'
        Write-Output '  secure-osusers.ps1 grants sdusers (RX) only. If a directory file cannot'
        Write-Output '  be opened read-only, the design needs a different route to the list, not'
        Write-Output '  a different ACL.'
    }
    Write-Output "  Transcript: $logPath"
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

Write-Output 'verify-osusers: PASSED - OS.USERS grants a shell, and takes it away again.'
Write-Output "  Transcript: $logPath"
try { Stop-Transcript | Out-Null } catch { }
exit 0
