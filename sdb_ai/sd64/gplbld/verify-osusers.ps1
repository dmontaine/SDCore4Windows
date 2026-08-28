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
# IT WILL ASK FOR ELEVATION TWICE - OR THREE TIMES if @LOGNAME starts on the
# list.  Writing the record and removing it again need an administrator - that
# ACL is the entire protection (gplbld/secure-osusers.ps1) - while the
# measurement must not have one.  The two halves cannot share a token, so the
# unelevated half drives and elevates for the writes.  Elevating is easy;
# de-elevating faithfully is not.
#
# @LOGNAME MAY ALREADY BE ON THE LIST, AND THAT IS NORMAL NOW.  CREATEA and
# adopt-account write an OS.USERS record ("yes","yes") for every
# ADMINISTRATOR-tier account as it is created (PRE_RELEASE 2, 27 Aug 2026), and
# the account the installer adopts - the one the person running this suite holds
# - is always ADMINISTRATOR.  So the "unlisted" baseline this test needs is not
# the state of a fresh install.  When it finds @LOGNAME already listed it SAVES
# the record's bytes, has the elevated half remove it for the baseline (the
# extra third prompt), runs the whole transition, and RESTORES the saved bytes
# at the end - so the tree is left exactly as found, automatic record included.
# The refuse-if-present guard this replaced was written when a pre-existing
# record could only be a person's manual decision; now it is the installer's,
# its content is known, and putting it back is safe.
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
#   (if @LOGNAME starts listed: save its bytes, elevate, remove it)
#   unelevated, unlisted   SH refused 10053, no marker    <- before
#   ELEVATED,   unlisted   SH admitted                    <- elevation still
#                                                            passes on its own
#   ELEVATED,   unlisted   SH with a pipe refused 5240    <- the ban is intact
#                                                            for the unlisted
#   unelevated, LISTED     SH admitted                    <- THE OWED TEST
#   unelevated, LISTED     SH with a pipe admitted        <- the ban is lifted
#   unelevated, unlisted   SH refused 10053 again         <- and it was the
#                                                            record that did it
#   (if a record was saved: elevate, write the saved bytes back)
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
    # Internal.  The elevated halves re-enter this script through
    # Start-Process -Verb RunAs; nobody types these.
    [ValidateSet('', 'Unlist', 'Grant', 'GrantOsx', 'Revoke')] [string] $Phase = '',
    [string] $LogName = '',
    [string] $ResultFile = '',
    [string] $MarkerDir = '',
    # Where the Unlist phase parks @LOGNAME's pre-existing record and the Revoke
    # phase reads it back from.  Empty when @LOGNAME started unlisted.
    [string] $SaveFile = ''
)

$ErrorActionPreference = 'Stop'

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$osUsers = Join-Path $env:ProgramData 'SD\sdsys\os.users'

# DRIVING SD FROM POWERSHELL has two traps, both in PROJECT_STATUS.md 6: input
# must be PIPED rather than redirected, and the pipe prepends a BOM to the first
# line, so a blank sacrificial line absorbs it.  TERM 200,9999 keeps SD from
# wrapping the messages this script matches on.
function Invoke-SD([string[]]$commands) {
    # LOGIN re-inits terminal geometry on every account switch (LOGIN:201-209),
    # so the initial TERM below is wiped by any LOGTO in $commands.  Full
    # write-up in verify-tiers.ps1's Invoke-SD.
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"

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

    # SAVE @LOGNAME's AUTOMATIC RECORD AND CLEAR IT FOR THE BASELINE.  Only runs
    # when step 0 found the account already listed (an ADMINISTRATOR - see the
    # header).  The bytes are copied verbatim, not reconstructed, so the Revoke
    # phase can put back exactly what was there - two "yes" fields, a hand-edited
    # third, whatever.  A missing $SaveFile target dir would strand the record,
    # so this refuses rather than proceed if the copy did not land.
    if ($Phase -eq 'Unlist') {
        if (-not (Test-Path -LiteralPath $record)) {
            Say 'RESULT: unlisted=already'
            Write-ResultFile
            exit 0
        }
        Copy-Item -LiteralPath $record -Destination $SaveFile -Force
        if (-not (Test-Path -LiteralPath $SaveFile)) {
            Say 'RESULT: unlisted=no'
            Say 'RESULT: saved=no'
            Write-ResultFile
            exit 2
        }
        Remove-Item -LiteralPath $record -Force
        Say ('RESULT: saved=' + $(if (Test-Path -LiteralPath $SaveFile) { 'yes' } else { 'no' }))
        Say ('RESULT: unlisted=' + $(if (Test-Path -LiteralPath $record) { 'no' } else { 'yes' }))
        Say "RESULT: savefile=$SaveFile"
        Write-ResultFile
        exit 0
    }

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

    # THE OTHER WAY ROUND, and it is the control the OS.EXECUTE gate needs.  The
    # Grant phase writes SH=yes OS.EX=no, which proves a refusal.  A gate that
    # refuses everything would pass that just as well, so this phase writes
    # SH=no OS.EX=yes and the caller checks the mirror image: OS.EXECUTE runs
    # and SH is refused, in one session, from one record.
    if ($Phase -eq 'GrantOsx') {
        [System.IO.File]::WriteAllText($record, "no`nyes`n",
                                       [System.Text.Encoding]::GetEncoding('iso-8859-1'))
        Say ('RESULT: osxgranted=' + $(if (Test-Path -LiteralPath $record) { 'yes' } else { 'no' }))
    }

    # REMOVE THE TEST RECORD, THEN PUT BACK WHATEVER WAS THERE BEFORE.  If the
    # Unlist phase saved a record, restoring it IS the end state this test
    # promises - "the tree is left as it was found".  If nothing was saved the
    # end state is no record, exactly as before.  revoked= reports the test
    # record is gone; restored= reports the original is back (or n/a).
    if ($Phase -eq 'Revoke') {
        if (Test-Path -LiteralPath $record) { Remove-Item -LiteralPath $record -Force }
        Say ('RESULT: revoked=' + $(if (Test-Path -LiteralPath $record) { 'no' } else { 'yes' }))

        if ($SaveFile -ne '' -and (Test-Path -LiteralPath $SaveFile)) {
            Copy-Item -LiteralPath $SaveFile -Destination $record -Force
            $ok = (Test-Path -LiteralPath $record)
            Say ('RESULT: restored=' + $(if ($ok) { 'yes' } else { 'no' }))
            if ($ok) { Remove-Item -LiteralPath $SaveFile -Force }
        } else {
            Say 'RESULT: restored=n/a'
        }
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
    Write-Output '  elevation it needs - twice, or three times if the account is'
    Write-Output '  already listed (an administrator always is).'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$results = New-Object System.Collections.ArrayList
$fatal   = $false

# Set by step 0a when @LOGNAME started listed and its record was parked.  Every
# early exit runs through Stop-Here, which restores it; a '' here means there is
# nothing to put back.  Declared now so a precondition Stop-Here sees a value.
$script:saveFile = ''

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

# PUT @LOGNAME's PARKED RECORD BACK.  A no-op unless step 0a saved one and it is
# not already back.  Called only from the finally block, which every path after
# step 0a runs through (Stop-Here's `exit` triggers it - measured, PS 5.1).
# Idempotent: a second call sees the save file gone and returns.
function Restore-SavedRecord {
    if (-not $script:saveFile -or -not (Test-Path -LiteralPath $script:saveFile)) { return }
    Write-Output ''
    Write-Output "verify-osusers: restoring $logNameValue's parked OS.USERS record"
    $rf = Join-Path $logDir ('verify-osusers-restore-' + $stamp + '.txt')
    Invoke-ElevatedPhase 'Revoke' $rf
    Read-ElevResults $rf
    if ($script:elevResults['restored'] -eq 'yes') {
        Write-Output "  restored - $record is back as it was found"
        $script:saveFile = ''
    } else {
        Write-Output ''
        Write-Output "verify-osusers: WARNING - could NOT restore $record automatically."
        Write-Output "  Its bytes are saved at:"
        Write-Output "      $script:saveFile"
        Write-Output "  Put them back from an ELEVATED prompt:"
        Write-Output "      Copy-Item `"$script:saveFile`" `"$record`""
        Write-Output "  or regenerate it: elevated 'sd', then  modify.account $logNameValue administrator"
        $script:fatal = $true
    }
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
$probeObj = Join-Path $acctDir 'bp.out\SDOSUSER'
$src = @(
    "* SDOSUSER - written by gplbld/verify-osusers.ps1.  Safe to delete."
    "      CRT 'LOGNAME=':@LOGNAME"
    "      OPENPATH @SDSYS:@DS:'os.users' TO F.OSU THEN"
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

# THE OS.EXECUTE PROBE, and it is the whole point of the C half of step 7.
# PROJECT_STATUS.md section 4: SH at the prompt is gated by CPROC, but
# OS.EXECUTE is its own BASIC statement and reached sh() with no gate at all,
# so any user with BASIC had the operating system from a program.  The gate now
# lives in C (op_sh.c, os_permitted) and reads OS.USERS field 2, "OS.EX".
#
# THE MARKER IS THE INSTRUMENT, not the message: the program asks the OS to
# create a file, so the file existing is the command having run.  A refusal
# raises a runtime error, which aborts the program - hence no marker.
$osxSrc = Join-Path $bp 'SDOSEXEC'
$osxObj = Join-Path $acctDir 'bp.out\SDOSEXEC'
$osxMarker = Join-Path $markerDir 'osexec'

function Write-OsxProbe {
    $t = @(
        "* SDOSEXEC - written by gplbld/verify-osusers.ps1.  Safe to delete."
        "      OS.EXECUTE 'cmd /c echo x > $osxMarker'"
        "      CRT 'OSEXEC=ran'"
        "   END"
    ) -join "`n"
    [System.IO.File]::WriteAllText($osxSrc, $t + "`n",
                                   [System.Text.Encoding]::GetEncoding('iso-8859-1'))
}

# Returns 'ran' | 'refused' | 'other', AND WRITES NOTHING, which is the whole
# reason it reports through a script-scope variable.  A PowerShell function
# returns EVERYTHING it writes, so a helper that both prints and returns hands
# its caller an array with the printed lines in front of the answer - the trap
# Invoke-ElevatedPhase already carries a comment about further down this file,
# and the first version of this walked straight into it: both checks compared
# 'refused' against System.Object[] and failed on a gate that was working.
#
# The marker is decisive - the program asks the OS to create a file, so the file
# existing is the command having run.  The message is corroboration, and both
# are recorded so a disagreement between them is visible.
$script:osxDetail = ''

function Test-OsExecute {
    Remove-Marker $osxMarker
    Write-OsxProbe
    $out = Invoke-SD @('BASIC BP SDOSEXEC', 'RUN BP SDOSEXEC')
    $made = Test-Path -LiteralPath $osxMarker
    $said = ($out -match 'not permitted to use OS.EXECUTE')
    $script:osxDetail = ("marker={0} refusal-message={1}" -f $made, $said)
    if (-not ($made -or $said)) {
        $script:osxDetail += "; neither - SD said: " + ($out.TrimEnd() -replace '\s+', ' ')
    }
    Remove-Marker $osxMarker
    if ($made) { return 'ran' }
    if ($said) { return 'refused' }
    return 'other'
}

function Remove-OsxProbe {
    foreach ($f in @($osxSrc, $osxObj)) {
        if (Test-Path -LiteralPath $f) { try { Remove-Item -LiteralPath $f -Force } catch { } }
    }
}

function Remove-Probe {
    Remove-OsxProbe
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

# NOT SCORED AS PASS/FAIL.  An empty result is the fresh-standalone case; a
# present one is the ADMINISTRATOR's automatic entry, handled at 0a.  Either is
# a legitimate starting point now, so this just records which one it was.
Write-Output "  record present before the test: $recBefore"

$record = Join-Path $osUsers $logNameValue

# --------------------------------------------------- the elevated-phase plumbing
# Defined here, not just before step 3, because step 0a below needs it too.
#
# NONE OF THESE RETURNS A VALUE, AND THAT IS DELIBERATE.  A PowerShell function
# returns EVERYTHING it writes, so a helper that both prints and returns hands
# its caller an array with the printed lines in front of the answer - $rc would
# be a string array and "$rc -ne 0" would be a comparison nobody meant.  Both of
# these print, so both report through a script-scope variable and return nothing.
$stamp              = Get-Date -Format 'yyyyMMdd-HHmmss'
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
    # Only the Unlist/Revoke phases need it, and only when a record was parked.
    if ($script:saveFile -ne '') { $a += @('-SaveFile', ('"' + $script:saveFile + '"')) }
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

# ===========================================================================
# ONE try FROM HERE, closed by the finally after step 5.  It is what guarantees
# the parked record (step 0a) and the test record (step 3) are cleaned up on
# EVERY exit, Stop-Here included - `exit` inside a try still runs finally in
# PS 5.1 (measured).  The body is left unindented: re-indenting ~200 lines to
# wrap them would be all risk and no behaviour.
# ===========================================================================
$granted = $false
try {

# --------------------------------- 0a. if @LOGNAME starts listed, park the record
# CREATEA/adopt-account list every ADMINISTRATOR account (PRE_RELEASE 2), and the
# adopted account is who runs this suite - so "already on the list" is the normal
# case now, not a person's manual grant.  Save the bytes, have the elevated half
# remove the record for the baseline, and step 5 writes them back.  Asked of both
# SD and the filesystem, as before: OS.USERS is (RX) to sdusers.
$startedListed = ($recBefore -ne '(none)' -or (Test-Path -LiteralPath $record))

if ($startedListed) {
    Write-Output ''
    Write-Output '=== 0a. Elevating to park the automatic record for the baseline =========='
    Write-Output "  $logNameValue is already listed - $record"
    Write-Output '  That is what CREATEA/adopt-account do for an ADMINISTRATOR account.'
    Write-Output '  Saving its bytes, removing it for the baseline, restoring it at step 5.'

    $script:saveFile = Join-Path $logDir ('verify-osusers-saved-' + $stamp + '.rec')
    $unlistFile      = Join-Path $logDir ('verify-osusers-unlist-' + $stamp + '.txt')
    Invoke-ElevatedPhase 'Unlist' $unlistFile
    $urc = $script:elevExit
    Read-ElevResults $unlistFile
    $ul = $script:elevResults

    if ($urc -ne 0 -or ($ul['unlisted'] -ne 'yes' -and $ul['unlisted'] -ne 'already')) {
        # Keep saveFile set IF the phase saved the bytes before it failed - the
        # finally then restores, which is safe whether or not the record went.
        # Only clear it when there is provably nothing to put back.
        if (-not (Test-Path -LiteralPath $script:saveFile)) { $script:saveFile = '' }
        Remove-Probe
        Stop-Here 2 ("could not park $logNameValue's automatic record for the baseline " +
                     "(exit $urc). The finally block will put it back if it moved.")
    }
    if ($ul['unlisted'] -eq 'already') {
        # Nothing was there after all - drop the save path so nothing restores.
        if (Test-Path -LiteralPath $script:saveFile) { Remove-Item -LiteralPath $script:saveFile -Force }
        $script:saveFile = ''
    }

    if ($script:saveFile -ne '') {
        $recheck = Invoke-Probe
        $recNow  = if ($recheck -match 'REC=(\S*)') { $Matches[1] } else { '(no line)' }
        Note 'baseline: the automatic record is now gone' '(none)' $recNow $true
        if ($recNow -ne '(none)') {
            Remove-Probe
            Stop-Here 2 "the record is still readable after the Unlist phase - the baseline is not clean."
        }
    }
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

# THE C HALF OF STEP 7, in the same session and with SH's refusal above as its
# control: one user, one session, and until 19 Aug 2026 one of these two routes
# was refused and the other was wide open.
$osxUnlisted = Test-OsExecute
Write-Output ('  OS.EXECUTE probe: ' + $script:osxDetail)
Note 'unlisted: OS.EXECUTE from a program is refused' 'refused' $osxUnlisted $true

# ------------------------------------------------------------------ 3. grant it

Write-Output ''
Write-Output '=== 3. Elevating to put the name on the list =============================='
Write-Output '  UAC will prompt (the second time, or third if step 0a ran). The elevated'
Write-Output '  half also takes the two controls that can only be taken while the list'
Write-Output '  is still empty.'

$resultFile = Join-Path $logDir ('verify-osusers-grant-' + $stamp + '.txt')

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

    # THE TWO FIELDS ARE INDEPENDENT, AND THIS IS WHERE THAT IS PROVED.  The
    # record granted above is "yes" then "no" - SH yes, OS.EX no - so in this
    # very session SH now works (checked above) and OS.EXECUTE must STILL be
    # refused.  If this passes only because everything is refused, the SH checks
    # above have already failed; if the gate read field 1 by mistake, this is
    # what catches it.
    $osxListed = Test-OsExecute
    Write-Output ('  OS.EXECUTE probe: ' + $script:osxDetail)
    Note 'LISTED for SH but not OS.EX: OS.EXECUTE is still refused' 'refused' $osxListed $true

    Remove-Marker $mAfterPlain
    Remove-Marker $mAfterPiped
}
finally {
    # ---------------------------------------------------- 5. take it away again

    if ($granted) {
        Write-Output ''
        Write-Output '=== 5. Elevating to take the name off again =============================='
        Write-Output '  UAC will prompt again. The tree is left exactly as it was found -'
        Write-Output '  the test record removed, and any record step 0a parked put back.'

        $revokeFile = Join-Path $logDir ('verify-osusers-revoke-' + $stamp + '.txt')
        # ---------------------------------------------------- 4a. the mirror
        Write-Output ''
        Write-Output '=== 4a. OS.EX=yes, SH=no - the control on the OS.EXECUTE gate ==========='
        Write-Output '  Everything above shows OS.EXECUTE being REFUSED, and a gate that'
        Write-Output '  refused everything would pass all of it.  This flips the record to'
        Write-Output '  SH=no OS.EX=yes and asks for the mirror image.'

        $osxFile = Join-Path $logDir 'osusers-grantosx.txt'
        Invoke-ElevatedPhase 'GrantOsx' $osxFile
        Read-ElevResults $osxFile
        $osxRes = $script:elevResults
        Note 'the OS.EX record was written' 'yes' `
             $(if ($osxRes['osxgranted']) { $osxRes['osxgranted'] } else { '(no line)' }) $false

        $osxOn = Test-OsExecute
        Write-Output ('  OS.EXECUTE probe: ' + $script:osxDetail)
        Note 'OS.EX=yes: OS.EXECUTE now runs' 'ran' $osxOn $true

        $mOsxSh = Join-Path $markerDir 'osx-sh'
        Remove-Marker $mOsxSh
        $shOff = Invoke-SD @((New-ProbeCmd $mOsxSh $false))
        Note 'and SH=no: the shell is still refused' 'no' `
             $(if (Test-Path -LiteralPath $mOsxSh) { 'yes' } else { 'no' }) $true
        Remove-Marker $mOsxSh

        # THE REVOKE PHASE REMOVES THE TEST RECORD AND, IF STEP 0a PARKED ONE,
        # WRITES THE SAVED BYTES BACK - so on this path the restore happens here,
        # not through Stop-Here.
        Invoke-ElevatedPhase 'Revoke' $revokeFile
        $rc2 = $script:elevExit
        Read-ElevResults $revokeFile
        $rev = $script:elevResults

        if ($rc2 -ne 0 -or $rev['revoked'] -ne 'yes') {
            Write-Output ''
            Write-Output 'verify-osusers: WARNING - THE TEST RECORD IS STILL THERE. Remove it from an elevated prompt:'
            Write-Output "    del `"$record`""
            $script:fatal = $true
        }
        elseif ($script:saveFile -ne '') {
            # @LOGNAME started listed: the end state is the SAVED record back,
            # not an empty list.  The loop closes a different way - the shell
            # tracked the TEST record's SH field at step 4a (yes->no, refused),
            # and now the account's own record is readable again.
            if ($rev['restored'] -eq 'yes') {
                Note 'the parked record was restored' 'yes' 'yes' $true
                if (Test-Path -LiteralPath $script:saveFile) { Remove-Item -LiteralPath $script:saveFile -Force }
                $script:saveFile = ''
                $probeEnd = Invoke-Probe
                $recEnd = if ($probeEnd -match 'REC=(\S*)') { $Matches[1] } else { '(no line)' }
                Note 'SD reads the restored record back' 'yes' $recEnd $false
            } else {
                Write-Output ''
                Write-Output "verify-osusers: WARNING - could NOT restore $record."
                Write-Output "  Bytes saved at:  $script:saveFile"
                Write-Output "  Elevated:  Copy-Item `"$script:saveFile`" `"$record`""
                $script:fatal = $true
            }
        }
        else {
            Note 'the record was removed again' 'yes' 'yes' $false

            # THE LOOP CLOSES HERE, when @LOGNAME started unlisted.  Everything
            # above is equally consistent with an install that admits everybody;
            # what rules that out is the shell going away again with the record.
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

    # EVERY OTHER PATH INTO finally: Grant never ran (so no test record to
    # revoke) but step 0a may have parked the account's record.  Put it back.
    if (-not $granted) { Restore-SavedRecord }

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
