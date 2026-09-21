# verify-lcnames.ps1 - the first of section 5.12 (a)'s renames: the per-account
# file names on disk are lower case.  PROJECT_STATUS.md 5.12, section 7 step 8.
#
#   powershell -ExecutionPolicy Bypass -File verify-lcnames.ps1            check, clean up after itself
#   powershell -ExecutionPolicy Bypass -File verify-lcnames.ps1 -Keep      leave the two probe records
#   powershell -ExecutionPolicy Bypass -File verify-lcnames.ps1 -Cleanup   remove ones left by -Keep
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# WHAT CHANGED.  CREATEA's create.dir.file is given a VOC id (fn) and a name on
# disk (os.name); the second is now lower case, so a new account holds $hold,
# $hold.dic, $svlists and bp instead of $HOLD, $HOLD.DIC, $SVLISTS and BP.
# to_file.c's three hold-file paths moved with it.  That is 5.12 (a).
#
# AND 5.12 (b) HAS STARTED, TWO FILES IN.  The VOC ids $SAVEDLISTS and $HOLD are
# now $savedlists and $hold.  BP and $COMMAND.STACK are NOT, deliberately, and
# are what is left of the controls in section 3: a change that lower-cased every
# id would fail there rather than pass.  SECTION 5 IS THE HALF THAT COULD BREAK
# EVERY EXISTING ACCOUNT - GPL.BP opens both names as hard-coded literals,
# nothing migrates an account created before a rename, and what makes those
# accounts keep working is _VOC_REF folding the id UP as well as down.
#
# IT NEEDS NO ACCOUNT OF ITS OWN, AND THAT IS WHY IT IS UNELEVATED.  The
# installer creates one through adopt-account.ps1 at every install, so after a
# cycle the installing user's account directory has just been built by the
# CREATEA under test.  Creating another would need CREATE.ACCOUNT, a Windows
# account and an elevated window - verify-createaccount.ps1's job, which now
# makes the same assertion case-exactly for an account it creates itself.
#
# Test-Path CANNOT MAKE THIS ASSERTION.  NTFS matches $HOLD against $hold, so a
# Test-Path check passes whichever case CREATEA wrote and proves nothing.  Every
# name check below compares against the real directory listing with -ceq.
#
# AND 5.12 (a)'s WIDE HALF WENT ON 19 Aug 2026: the SHIPPED SDSYS files are
# lower case on disk too, and so is the per-account voc.  Section 2a is the new
# one and it reads the installed sdsys directly.  NOTHING MIGRATES - an account
# or an sdsys built before this keeps the upper-case spellings and NTFS matches
# either, which is why the rename could be made a directory at a time.
#
# THE CONTROLS MOVED WITH IT, and that is worth reading before adding a check
# here.  The account's VOC used to be the on-disk control; it is lower case now,
# so the controls that remain are the VOC IDS - section 3 types BP and
# $COMMAND.STACK in lower case and requires an UPPER-case answer, so a change
# that lower-cased every id would fail there rather than pass.  cat has been
# lower case since before the port and shows the listing can report either.
#
# COPYP RIDES ALONG because it shipped in the same cycle.  See section 5.
#
# 14 Sep 2026 - RELEASE_1.1 5 D2 MADE VOC CASE INSENSITIVE, AND THREE OF THIS
# FILE'S INSTRUMENTS DIED WITH IT (b161).  CT now echoes the spelling TYPED, an
# exact-match read of VOC now finds any spelling, and sections 5/5a/5b's rename
# toggles ("write UPPER, delete lower") DELETED THE ONLY RECORD - $savedlists,
# $hold and $command.stack vanished from the account this runs in.  Stored ids
# are now read from "LIST VOC WITH @ID LIKE", which prints them as stored; the
# toggles are gone.  NEVER write one spelling and delete another on a hashed file.
#
# DRIVING SD FROM POWERSHELL: input must be PIPED, not redirected, and the pipe
# prepends a BOM to the first line, so a blank sacrificial line absorbs it.
# PROJECT_STATUS.md section 6.  Every call is bounded - section 8 records three
# runs lost to an unbounded prompt loop on 18 Aug 2026.

param(
    [string]$Account = $env:USERNAME,
    [string]$Tag     = 'lc1',
    [switch]$Keep,
    [switch]$Cleanup,

    # 16 Sep 26 - RELEASE_1.1 45 closed LOGTO SDSYS to a session that did not
    # start elevated, and this script has five legs that LOGTO SDSYS to read
    # voc_template's own records (sections 3 and 6).  They ran unelevated and
    # so were refused - ten rows red on b171, the first full run since 45 -
    # measuring the door rather than the names.  Those legs now run in an
    # ELEVATED re-entry of this same file: the parent writes the SD command
    # lists to -RequestFile, the child runs each through the same Invoke-SD and
    # writes the raw output to -ResultFile, the parent reads it back and judges
    # exactly as before.  Internal; nobody types these.
    [ValidateSet('', 'RunLegs')] [string]$Phase = '',
    [string]$RequestFile = '',
    [string]$ResultFile = '',
    # The runner's helper pipe (PRE_RELEASE 165), so the elevated re-entry costs
    # no consent of its own.  ADOPT ONLY - never started here (verify-osusers
    # says why).  Not passed down to the re-entry, which is already elevated.
    [string]$HelperPipe = ''
)

$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot 'elevate-once.ps1')
# 21 Sep 26 - RELEASE_1.1 76, the owner's ruling "convert": the SDSYS legs run
# through the SDSYS seat inside the elevated re-entry below.  Dot-sourced BEFORE
# the first script-scope call, which test-sdsysseat-units section 7 checks.
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
if ($HelperPipe -ne '') {
    $null = Start-SdElevationHelper -Adopt $HelperPipe -Purpose 'this step'
}

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-lcnames-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

# CLAUDE.md's rule, made enforceable rather than remembered: a result read off a
# tree that does not match source says nothing about the change.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-lcnames: refusing - see above'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$sdExe    = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$acctRoot = Join-Path $env:ProgramData 'SD\user_accounts'
$sdsysDir = Join-Path $env:ProgramData 'SD\sdsys'
$holdRec  = ('ZZ' + $Tag).ToUpper()      # a record in $hold
$listName = ('ZZL' + $Tag).ToUpper()     # a saved select list in $svlists

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

# The job is killed at the timeout and WHATEVER SD PRINTED IS RETURNED, so a
# prompt that caused a hang is visible instead of trapped in a dead pipe.
#
# NO LOGTO in the default body.  Sections 2 to 4 must run IN the account, because
# the files under test are the account's; SDSYS's own $HOLD, BP and VOC are
# shipped system files and are not part of this rename.  An unelevated sd for the
# installing user lands in that account already (section 7 step 1f), and section
# 1 asserts it did.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 45) {
    # LOGIN re-inits terminal geometry on every account switch (LOGIN:201-209),
    # so the initial TERM below is wiped by any LOGTO in $commands.  Full
    # write-up was in verify-tiers.ps1's Invoke-SD (deleted 18 Sep 2026,
    # RELEASE_1.1 64, with the tiers).  ITS TERM-AFTER-LOGTO TRAP STILL APPLIES
    # and is now written down nowhere, which one of these slices has to fix.  AND
    # THE LOGTO SDSYS PREFIX EVERY DRIVER HERE USED IS REFUSED NOW (cproc:2789,
    # 10002); 64's FIFTH PASS has the measurement.  THIS function never sent it -
    # it drives the invoking user's own account - and the SDSYS legs that did go
    # through the SDSYS seat since 21 Sep 2026 (the RunLegs block below).
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ("<<TIMED OUT after {0}s - SD is probably at a prompt>>" -f $TimeoutSec)
    }
    Remove-Job $job -Force
    return ($out -join "`n")
}

# ---------------------------------------------------------------------------
# THE ELEVATED RE-ENTRY (see -Phase above).  The request file is sections of
#   ### <name>
#   <one SD command per line>
# and the result file is the same sections holding Invoke-SD's raw output for
# each, closed by "### END".  Nothing is judged here: the parent applies the
# same Test-Reached / Test-StoredAs / -match rows it always did, so the ONLY
# thing that moved is which token ran the SD session.  The child refuses the
# null case out loud - no request, no legs, not elevated - with exit 2.
if ($Phase -eq 'RunLegs') {
    $lines = New-Object System.Collections.ArrayList
    function Emit($t) { $null = $lines.Add($t) }
    function Write-ResultFile {
        [System.IO.File]::WriteAllLines($ResultFile, [string[]]$lines,
                                        (New-Object System.Text.UTF8Encoding($false)))
    }
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Emit 'RESULT: elevated=no'; Write-ResultFile
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }
    Emit 'RESULT: elevated=yes'
    if ($RequestFile -eq '' -or -not (Test-Path -LiteralPath $RequestFile)) {
        Emit 'RESULT: legs=0'; Emit 'RESULT: error=no request file'; Write-ResultFile
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }
    $legs = [ordered]@{}
    $cur = $null
    foreach ($l in @(Get-Content -LiteralPath $RequestFile)) {
        if ($l -match '^### (\S+)$') { $cur = $Matches[1]; $legs[$cur] = New-Object System.Collections.ArrayList }
        elseif ($null -ne $cur -and $l -ne '') { $null = $legs[$cur].Add($l) }
    }
    Emit ('RESULT: legs=' + $legs.Count)
    if ($legs.Count -eq 0) { Write-ResultFile; try { Stop-Transcript | Out-Null } catch { }; exit 2 }
    foreach ($name in @($legs.Keys)) {
        $cmds = [string[]]$legs[$name]
        Write-Output ("  elevated leg {0}: {1}" -f $name, ($cmds -join ' ; '))
        Emit ('### ' + $name)
        # 21 Sep 26 - THROUGH THE SDSYS SEAT, NOT THIS PROCESS'S OWN sd.exe.
        # RELEASE_1.1 76, the owner's ruling.  64 refuses a LOGTO to SDSYS
        # (10002) and an elevated session of the invoking user lands in that
        # user's own account, so the legs no longer open with "LOGTO SDSYS": the
        # seat's session IS SDSYS.  This process is elevated, which the seat needs
        # to register its task.  A seat that did not run THROWS; the leg's answer
        # then stays EMPTY - the failing direction for every row that reads it -
        # and the reason travels as a RESULT line, which the parent prints.
        try {
            foreach ($o in ((Invoke-SdSeatText -Commands $cmds -TimeoutSec 180) -split "`n")) { Emit $o }
        } catch {
            Emit ('RESULT: seat did not run for leg ' + $name + ' - ' + ($_.Exception.Message -replace '\r?\n', ' '))
        }
        Emit '### END'
    }
    Write-ResultFile
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

# The parent's side.  Takes an ordered table name -> string[] of SD commands,
# runs ONE elevated re-entry for the lot, and leaves name -> raw output in
# $script:sdsysOut.  A leg the child did not answer is '' there and reads as
# "nothing matched", which is the failing direction for every row that
# consumes it.  A SCRIPT VARIABLE, NOT A RETURN VALUE: this function writes
# progress lines with Write-Output, and a return value would travel in the same
# pipeline as those lines - the caller would index an array of strings.
# test-lcnameslegs-units.ps1 caught exactly that on the first draft.
function Invoke-SDElevatedLegs([System.Collections.Specialized.OrderedDictionary]$legs) {
    $answers = @{}
    foreach ($k in @($legs.Keys)) { $answers[$k] = '' }
    $script:sdsysOut = $answers
    $work = Join-Path $env:TEMP ('vlc-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $null = New-Item -ItemType Directory -Path $work
    try {
        $req = Join-Path $work 'request.txt'
        $res = Join-Path $work 'result.txt'
        $body = New-Object System.Collections.ArrayList
        foreach ($k in @($legs.Keys)) {
            $null = $body.Add('### ' + $k)
            foreach ($c in @($legs[$k])) { $null = $body.Add($c) }
        }
        [System.IO.File]::WriteAllLines($req, [string[]]$body, (New-Object System.Text.UTF8Encoding($false)))

        # SINGLE-QUOTED, so backslashes are literal; an apostrophe is refused.
        if (@(@($PSCommandPath, $req, $res) | Where-Object { $_ -match "'" }).Count -gt 0) {
            Write-Output 'verify-lcnames: a path contains an apostrophe; the elevated launcher cannot be built safely.'
            return
        }
        $call = "& '$PSCommandPath' -Phase 'RunLegs' -RequestFile '$req' -ResultFile '$res'"
        $launcher = Join-Path $work 'phase.ps1'
        [System.IO.File]::WriteAllText($launcher, (@($call, 'exit $LASTEXITCODE') -join "`r`n") + "`r`n",
                                       [System.Text.Encoding]::ASCII)
        # RULE 1: the real call, echoed before it runs.
        Write-Output ('  elevated legs argv: ' + $call)
        Write-Output ('  legs: ' + (@($legs.Keys) -join ', '))
        $r = Invoke-ElevatedScript -Launcher $launcher -Why 'verify-lcnames SDSYS legs'
        if (-not $r.Ok) {
            Write-Output ('verify-lcnames: the elevated legs did not run: ' + $r.Reason)
            return
        }
        if (-not (Test-Path -LiteralPath $res)) {
            Write-Output '  (the elevated half wrote no result file)'
            return
        }
        $cur = $null
        $buf = New-Object System.Collections.ArrayList
        foreach ($l in @(Get-Content -LiteralPath $res)) {
            if ($l -match '^RESULT: (.*)$') { Write-Output ('  elevated half: ' + $Matches[1]); continue }
            if ($l -eq '### END') { if ($null -ne $cur) { $answers[$cur] = ($buf -join "`n") }; $cur = $null; $buf.Clear(); continue }
            if ($l -match '^### (\S+)$') { $cur = $Matches[1]; $buf.Clear(); continue }
            if ($null -ne $cur) { $null = $buf.Add($l) }
        }
        $answered = @($answers.Keys | Where-Object { $answers[$_] -ne '' }).Count
        Write-Output ("  elevated legs answered: {0} of {1}" -f $answered, $legs.Count)
    } finally {
        Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# The account DIRECTORY is lower case already (CREATEA downcases it), while the
# SD account NAME is upper case.  Resolve the directory from the listing rather
# than assuming either.
$acctDir = $null
if (Test-Path -LiteralPath $acctRoot) {
    $hit = @(Get-ChildItem -LiteralPath $acctRoot -Directory |
             Where-Object { $_.Name -ieq $Account })
    if ($hit.Count -eq 1) { $acctDir = $hit[0].FullName }
}
if ($null -eq $acctDir) {
    Write-Output ("verify-lcnames: no account directory for '{0}' under {1}" -f $Account, $acctRoot)
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
Write-Output ("account directory: " + $acctDir)

$script:hadObjDir = @(Get-ChildItem -LiteralPath $acctDir -Directory -ErrorAction SilentlyContinue |
                      Where-Object { $_.Name -ieq 'BP.OUT' }).Count -eq 1

# AND THE OBJECT FILE, WHICH IS NOT OPTIONAL TIDINESS.  The probes below are
# compiled with "BASIC bp <name>", and BASIC:132 builds the object file name
# from the name AS TYPED - so it creates bp.OUT, and CREATE.FILE then stores the
# VOC id as typed (bp.OUT) while upper-casing the directory (BP.OUT).  That is
# UPSTREAM_FIXES.md 6.  The three-case fold cannot reach a MIXED-case id, so a
# later "BASIC BP <probe>" finds no VOC entry, tries to create BP.OUT, and stops
# with "Data pathname 'BP.OUT' already exists".  Measured 18 Aug 2026: leaving it
# behind made verify-nocase.ps1 and verify-osusers.ps1 exit 2 on a good install.
# DELETE.FILE takes the VOC entry and the directory together, and FORCE
# suppresses the two prompts DELETEF asks when a stored path differs from the
# default name.
function Remove-Probes {
    foreach ($p in @((Join-Path $acctDir ('$hold\'    + $holdRec)),
                     (Join-Path $acctDir ('$svlists\' + $listName)))) {
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force
            Write-Output ("  removed " + $p)
        }
    }

    $objDir = @(Get-ChildItem -LiteralPath $acctDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ieq 'BP.OUT' })
    # ONLY IF THIS RUN MADE IT.  An account has no BP.OUT until something
    # compiles in it, but verify-nocase.ps1 and verify-osusers.ps1 make one too
    # and it is not this script's to remove.  -Cleanup clears the flag, because
    # then removing it IS the job.
    # 19 Aug 26 - bp.out, NOT bp.OUT.  BASIC names the object file from the VOC
    # record that answered and the suffix follows its case, so the id it creates
    # is now bp.out.  The old mixed-case spelling here left the file behind and
    # printed the warning below on a perfectly good install: measured on the
    # 09:10:45 install, "DELETE.FILE bp.OUT FORCE" removed nothing while
    # "DELETE.FILE bp.out FORCE" answered "DATA portion 'BP.OUT' deleted /
    # VOC entry 'bp.out' deleted".  WHY THE MIXED SPELLING IS NOT FOLDED TO THE
    # LOWER ONE IS NOT ESTABLISHED - see PROJECT_STATUS.md 8, open questions.
    if ($objDir.Count -eq 1 -and -not $script:hadObjDir) {
        $null = Invoke-SD @('DELETE.FILE bp.out FORCE')
        $still = @(Get-ChildItem -LiteralPath $acctDir -Directory -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -ieq 'BP.OUT' })
        if ($still.Count -eq 0) {
            Write-Output '  removed the bp.out object file this script created'
        } else {
            # NOT the old "a later BASIC BP <x> will fail" - that failure was the
            # mixed-case id, and it is fixed.  A left-behind object file is now
            # just an object file, and section 9 clears it as its first act.
            Write-Output '  note: the bp.out object file is still there; section 9 clears it next run'
        }
    }
}

if ($Cleanup) {
    Write-Output ''
    Write-Output '=== cleanup only ========================================================'
    $script:hadObjDir = $false
    Remove-Probes
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

try {
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 1. the session is in the account, not SDSYS =========================='

    $who = Invoke-SD @('WHO')
    Note 'WHO names the account' $true ($who -match ('(?i)\b' + [regex]::Escape($Account) + '\b'))
    Write-Output '  --- WHO said: ---'
    Write-Output $who

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 2. the names on disk, exact case ====================================='

    $onDisk = @(Get-ChildItem -LiteralPath $acctDir -Force | Select-Object -ExpandProperty Name)
    Write-Output ('  listing: ' + ($onDisk -join '  '))

    # voc joined this list on 19 Aug 2026 - CREATEA:581 creates it as 'voc' now.
    foreach ($n in @('$hold', '$hold.dic', '$svlists', 'bp', 'voc')) {
        Note ($n + ' present, exact case') 1 @($onDisk | Where-Object { $_ -ceq $n }).Count
    }
    # The old spellings must be absent, which Test-Path could never have shown.
    foreach ($n in @('$HOLD', '$HOLD.DIC', '$SVLISTS', 'BP', 'VOC')) {
        Note ($n + ' absent') 0 @($onDisk | Where-Object { $_ -ceq $n }).Count
    }
    # THE CONTROL.  cat was lower case before any of this and shows the listing
    # reports the real case rather than folding it - without which every check
    # above would pass on an account that had never been renamed at all.  The
    # controls that show this is a rename and not a sweep are the VOC IDS, and
    # they are in section 3: BP and $COMMAND.STACK are still upper case.
    Note 'control: cat still lower case' 1 @($onDisk | Where-Object { $_ -ceq 'cat' }).Count

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 2a. THE SHIPPED SDSYS NAMES ON DISK, 5.12 (a) WIDE HALF =============='
    Write-Output '  These are the ones the owner asked about: bp and voc in SDSYS itself.'
    Write-Output '  Some ship from the repository, some are made by BBPROC at bootstrap and'
    Write-Output '  some by stage.py, so a miss here says which half was left behind.'

    $sysDisk = @(Get-ChildItem -LiteralPath $sdsysDir -Force |
                 Select-Object -ExpandProperty Name)
    Write-Output ('  listing: ' + (($sysDisk | Sort-Object) -join '  '))

    # SHIPPED FROM THE REPOSITORY (gplbld/stage.py SDSYS_SHIP and SDSYS_EMPTY).
    $shipped = @('gpl.bp', 'syscom', 'newvoc', 'voc_template', 'messages',
                 'sd.voclib', 'accounts', 'bp', 'gpl.bp.out', 'bp.out',
                 'pcode.out', '$hold', '$cred', 'os.users', 'os.users.dic')
    # MADE BY THE BOOTSTRAP: BBPROC's FILES_LIST, plus voc at BBPROC:158.
    $made    = @('voc', 'voc.dic', 'dict.dic', 'dir_dict', 'accounts.dic',
                 '$hold.dic', '$map', '$map.dic', '$ipc')
    # MADE BY THE INSTALLER: sd.iss hands secure-psdir.ps1 the path to create.
    $byInst  = @('pstmp')

    foreach ($n in ($shipped + $made + $byInst)) {
        Note ('sdsys ' + $n + ' present, exact case') 1 `
             @($sysDisk | Where-Object { $_ -ceq $n }).Count
    }
    foreach ($n in @('GPL.BP', 'SYSCOM', 'NEWVOC', 'VOC_TEMPLATE', 'MESSAGES',
                     'SD.VOCLIB', 'ACCOUNTS', 'BP', 'GPL.BP.OUT', 'BP.OUT',
                     'PCODE.OUT', '$HOLD', '$CRED', 'OS.USERS', 'OS.USERS.DIC',
                     'VOC', 'VOC.DIC', 'DICT.DIC', 'DIR_DICT', 'ACCOUNTS.DIC',
                     '$HOLD.DIC', '$MAP', '$MAP.DIC', '$IPC', 'PSTMP')) {
        Note ('sdsys ' + $n + ' absent') 0 @($sysDisk | Where-Object { $_ -ceq $n }).Count
    }
    # THE CONTROLS FOR THIS SECTION.  gcat, cat, prt, bin and terminfo were
    # lower case before any of it, so they show the listing is not folding case.
    foreach ($n in @('gcat', 'cat', 'prt', 'bin')) {
        Note ('control: sdsys ' + $n + ' unchanged') 1 `
             @($sysDisk | Where-Object { $_ -ceq $n }).Count
    }

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 3. the VOC records name the lower-case paths ========================='
    Write-Output '  Fields 2 and 3 hold the path, and that is what LISTF and CT VOC show.'
    Write-Output '  This is 5.12 (a) and is independent of the id, which the next block tests.'

    $ct = Invoke-SD @('CT VOC $hold', 'CT VOC $savedlists', 'CT VOC BP',
                      'CT VOC VOC', 'CT VOC SYSCOM')
    Note 'CT VOC $hold names $hold'          $true ($ct -cmatch '(?m)^\s*2:\s*\$hold\s*$')
    Note 'CT VOC $hold names $hold.dic'      $true ($ct -cmatch '(?m)^\s*3:\s*\$hold\.dic\s*$')
    Note 'CT VOC $savedlists names $svlists' $true ($ct -cmatch '(?m)^\s*2:\s*\$svlists\s*$')
    Note 'CT VOC BP names bp'                $true ($ct -cmatch '(?m)^\s*2:\s*bp\s*$')
    # 19 Aug 26 - THE WIDE HALF.  The account's own VOC pointer and one that
    # reaches into SDSYS, so a miss says whether it was newvoc's F records or
    # the on-disk rename that was left behind.  Field 3 of VOC is @SDSYS/voc.dic.
    Note 'CT VOC VOC names voc'              $true ($ct -cmatch '(?m)^\s*2:\s*voc\s*$')
    Note 'CT VOC VOC names @SDSYS/voc.dic'   $true ($ct -cmatch '(?m)^\s*3:\s*@SDSYS/voc\.dic\s*$')
    Note 'CT VOC SYSCOM names @SDSYS/syscom' $true ($ct -cmatch '(?m)^\s*2:\s*@SDSYS/syscom\s*$')
    Write-Output '  --- CT VOC said: ---'
    Write-Output $ct

    # THE ID ITSELF, 5.12 (b), AND "NOT FOUND" CANNOT MEASURE IT.  An earlier
    # version of these two checks asserted that CT VOC $SAVEDLISTS now answers
    # "Record not found".  IT DOES NOT, and both checks failed on the 20:21:53
    # install: CT folds the RECORD id as well as the file name (CT:202, one of
    # the 74 sites), so it finds the record whichever case is typed.
    #
    # WHICH GAVE A BETTER INSTRUMENT THAN THE ONE INTENDED, UNTIL D2.  CT:215
    # printed the id it MATCHED, not the one typed, so the echo said which
    # spelling was stored.
    #
    # 14 Sep 26 - NOT ANY MORE.  RELEASE_1.1 5 D2 made VOC case insensitive, so
    # CT's read of the typed name hits the record directly and echoes the
    # spelling TYPED: every "typing X is answered as x" row failed on b161, a
    # correct install.  Each id is now two rows: typing the old name REACHES the
    # record (CT prints it, no 2108), and the id is STORED lower, read from
    # "LIST VOC WITH @ID LIKE" - which scans and prints the id as stored
    # (measured 14 Sep 2026: LIKE "$HOLD" listed $hold, @ID = "$HOLD" listed
    # $HOLD).  -cmatch on the row is the assertion.
    function Test-Reached([string]$text, [string]$typed) {
        return (($text -match ('(?m)^VOC ' + [regex]::Escape($typed) + '\s*$')) -and
                ($text -notmatch ("Record '" + [regex]::Escape($typed) + "' not found")))
    }
    function Test-StoredAs([string]$text, [string]$stored, [string]$other) {
        return (($text -cmatch ('(?m)^' + [regex]::Escape($stored) + '\s{2,}')) -and
                ($text -cnotmatch ('(?m)^' + [regex]::Escape($other) + '\s{2,}')))
    }
    function Get-LikeQuery([string[]]$ids) {
        return ('LIST VOC WITH ' + (($ids | ForEach-Object { '@ID LIKE "' + $_ + '"' }) -join ' OR '))
    }
    function Note-Pairs($text, $pairs, [string]$prefix) {
        foreach ($p in $pairs) {
            Note ("{0}typing {1} reaches the record" -f $prefix, $p.U) $true (Test-Reached $text $p.U)
            Note ("{0}{1} is stored as {2}" -f $prefix, $p.U, $p.L) $true (Test-StoredAs $text $p.L $p.U)
        }
    }
    # 19 Aug 26 - BP MOVED THIS CYCLE AND TOOK ITS CONTROL WITH IT.  It is an
    # assertion now, not a control.
    $ucPairs = @(@{U='$SAVEDLISTS'; L='$savedlists'}, @{U='$HOLD'; L='$hold'}, @{U='BP'; L='bp'})
    $ctUc = Invoke-SD (@($ucPairs | ForEach-Object { 'CT VOC ' + $_.U }) + @(Get-LikeQuery @($ucPairs | ForEach-Object { $_.L })))
    Note-Pairs $ctUc $ucPairs ''
    # 19 Aug 26 - THE TEN F/Q FILE POINTERS MOVED, 5.12 (b).  Same instrument:
    # type the OLD upper-case id and read which spelling CT says it matched.
    # VOC is the one worth naming - DELETEF bans it, CNAME, CREATEF, SHOW and
    # SED name it as a literal, and CPROC reads $VOC.PARSER out of it.
    #
    # THE TEN SPLIT ACROSS TWO VOCs AND THE FIRST VERSION OF THIS TESTED THEM
    # ALL IN ONE, which failed four checks on a rename that was perfectly good.
    # An account's VOC is built from newvoc; voc_template becomes SDSYS's own.
    # ACCOUNTS, MESSAGES, QFILE and OS.USERS are in voc_template ONLY, so in
    # DON's account they do not exist and never did - "Record not found" is the
    # right answer there, not evidence of anything.  Ask each one where it lives.
    $fqPairs = @(@{U='VOC';         L='voc'},
                 @{U='NEWVOC';      L='newvoc'},
                 @{U='SYSCOM';      L='syscom'},
                 @{U='DICT.DICT';   L='dict.dict'},
                 @{U='MD';          L='md'},
                 @{U='SD.ACCOUNTS'; L='sd.accounts'})
    $ctFq = Invoke-SD (@($fqPairs | ForEach-Object { 'CT VOC ' + $_.U }) + @(Get-LikeQuery @($fqPairs | ForEach-Object { $_.L })))
    Note-Pairs $ctFq $fqPairs ''

    $sysPairs = @(@{U='ACCOUNTS'; L='accounts'},
                  @{U='MESSAGES'; L='messages'},
                  @{U='QFILE';    L='qfile'},
                  @{U='OS.USERS'; L='os.users'})
    # 16 Sep 26 - EVERY LOGTO SDSYS LEG IN THIS SCRIPT RUNS HERE, ONCE, ELEVATED
    # (RELEASE_1.1 45 refuses LOGTO SDSYS to a session that did not start
    # elevated - measured red on b171).  The command lists are unchanged; section
    # 6's three legs are gathered into the same request so a standalone run
    # costs one consent rather than four.  The judging stays where it was.
    # 21 Sep 26 - AND THE LEGS NO LONGER OPEN WITH LOGTO SDSYS, RELEASE_1.1 76:
    # the re-entry runs them through the SDSYS seat, whose session already IS
    # SDSYS, and 64 refuses the LOGTO outright (10002).  The rest of each list is
    # unchanged, so the judging below reads the same commands' output.
    $sdsysLegs = [ordered]@{
        sysct   = @($sysPairs | ForEach-Object { 'CT VOC ' + $_.U }) + @(Get-LikeQuery @($sysPairs | ForEach-Object { $_.L }))
        copypct = @('CT VOC COPYP')
        unknown = @('ZZNOSUCHVERB')
        copyp   = @('COPYP')
    }
    Invoke-SDElevatedLegs $sdsysLegs          # fills $script:sdsysOut
    $ctSys = $script:sdsysOut['sysct']
    # THE DOOR ITSELF IS THE CONTROL: had the leg run unelevated, SD would say so.
    Note 'SDSYS: the elevated leg was not refused at the door' $false ($ctSys -match 'restricted to privileged users|did not start elevated')
    Note 'SDSYS: the elevated leg answered at all (null case refused)' $true ($ctSys -ne '')
    Note-Pairs $ctSys $sysPairs 'SDSYS: '
    # AND THE OTHER HALF OF THAT SPLIT IS ITSELF AN ASSERTION: those four are
    # administrative and must NOT have arrived in an ordinary account's VOC.
    Note 'ACCOUNTS is absent from the account VOC, as it always was' $true `
         ($ctFq -match "Record 'ACCOUNTS' not found" -or $ctFq -notmatch '(?m)^VOC accounts')

    # THE TWO Q-POINTERS NAME ANOTHER ID IN FIELD 3, and that field had to move
    # with them.  SD.ACCOUNTS field 2 is an ACCOUNT name and stays upper - that
    # is the wide half of 5.12 and is out of scope, so it doubles as a control
    # on this pair: a sweep would have taken SDSYS down with it.
    $ctQ = Invoke-SD @('CT VOC MD', 'CT VOC SD.ACCOUNTS')
    Note 'MD field 3 names voc'              $true ($ctQ -cmatch '(?m)^\s*3:\s*voc\s*$')
    Note 'SD.ACCOUNTS field 3 names accounts' $true ($ctQ -cmatch '(?m)^\s*3:\s*accounts\s*$')
    Note 'control: SD.ACCOUNTS field 2 is still SDSYS' $true ($ctQ -cmatch '(?m)^\s*2:\s*SDSYS\s*$')

    # $COMMAND.STACK MOVED ON 19 AUG, so it is an assertion now, not the control.
    $csPairs = @(@{U='$COMMAND.STACK'; L='$command.stack'})
    $ctCs = Invoke-SD @('CT VOC $COMMAND.STACK', (Get-LikeQuery @('$command.stack')))
    Note-Pairs $ctCs $csPairs ''

    # THE CONTROL, AND IT IS NO LONGER A SHIPPED ID - it is a record this test
    # makes for itself.  $HOLD was the control until 18 Aug, BP until 19 Aug and
    # $COMMAND.STACK until later the same day; each rename ate the one before it,
    # and the section's whole point is to tell a rename from a SWEEP - if
    # everything in the VOC were lower-cased by accident, every assertion above
    # would still pass.  A record the test writes in UPPER case and reads back in
    # UPPER case cannot be eaten by the next rename, because nothing ships it.
    $ctlBp = @(Get-ChildItem -LiteralPath $acctDir -Directory |
               Where-Object { $_.Name -ieq 'bp' } | Select-Object -First 1)
    if ($ctlBp.Count -ne 1) {
        Note 'control: bp directory found so the control could be written' $true $false
    } else {
        $ctlName = ('ZZCTL' + $Tag).ToUpper()
        $ctlProg = ('ZZCTLP' + $Tag).ToUpper()
        $ctlSrc = @"
* $ctlProg - writes section 3's control record.  Safe to delete.
   open 'voc' to vf then
      write 'X' to vf,'$ctlName'
      print 'CTL=OK'
   end else
      print 'CTL=FAIL'
   end
end
"@
        [IO.File]::WriteAllText((Join-Path $ctlBp[0].FullName $ctlProg),
                                ($ctlSrc -replace "`r`n", "`n"),
                                (New-Object Text.UTF8Encoding $false))
        $ctlRun = Invoke-SD @("BASIC bp $ctlProg", "RUN bp $ctlProg")
        Note 'control: the test wrote its own UPPER-case VOC record' $true ($ctlRun -match 'CTL=OK')

    # Typed in LOWER case it is reached, and the stored id is untouched.  A
    # sweep would have taken this with it.  14 Sep 26 - the stored id is read
    # from LIKE's row, not CT's echo (see the note on the rows above).
        $ctCtl = Invoke-SD @("CT VOC $($ctlName.ToLower())", (Get-LikeQuery @($ctlName.ToLower())))
        Note 'control: an UPPER-case id the test wrote is reached typed lower' $true `
             (Test-Reached $ctCtl $ctlName.ToLower())
        Note 'control: and it is still stored UPPER - nothing lower-cased it' $true `
             (Test-StoredAs $ctCtl $ctlName $ctlName.ToLower())
        $null = Invoke-SD @("DELETE VOC $ctlName")
        foreach ($d in @($ctlBp[0].FullName, (Join-Path $acctDir 'BP.OUT'))) {
            $q = Join-Path $d $ctlProg
            if (Test-Path -LiteralPath $q) { Remove-Item -LiteralPath $q -Force }
        }
    }

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 4. behaviour, not just names ========================================='
    Write-Output '  A name that is only cosmetically right would pass sections 2 and 3 and'
    Write-Output '  still have broken every file the account owns.'

    Note 'COUNT BP opens the renamed file' $false ((Invoke-SD @('COUNT BP')) -match 'File not found')

    # $svlists, through the verbs that use it.  SELECT VOC then SAVE.LIST writes
    # a record into the account's saved-list file; GET.LIST reads it back.
    $lst = Invoke-SD @('SELECT VOC', ('SAVE.LIST ' + $listName), ('GET.LIST ' + $listName))
    Note 'SAVE.LIST wrote into $svlists' $true `
         (Test-Path -LiteralPath (Join-Path $acctDir ('$svlists\' + $listName)))
    Note 'GET.LIST read it back' $false ($lst -match 'not found')
    Write-Output '  --- SAVE.LIST/GET.LIST said: ---'
    Write-Output $lst

    # THE PROMISE MADE TO USERS IN THE CHANGELOG: the old spelling still works
    # when it is TYPED, even though the id has moved.  That is the downward half
    # of the fold, and it is what keeps ED $SAVEDLISTS and COPY.LIST ... FROM
    # $SAVEDLISTS working.  Section 5 is the upward half.
    Note 'COUNT $SAVEDLISTS still finds the file' $false `
         ((Invoke-SD @('COUNT $SAVEDLISTS')) -match 'File not found')
    Note 'COUNT $savedlists finds it as typed'    $false `
         ((Invoke-SD @('COUNT $savedlists')) -match 'File not found')
    Note 'COUNT $HOLD still finds the file'       $false `
         ((Invoke-SD @('COUNT $HOLD')) -match 'File not found')
    Note 'COUNT $hold finds it as typed'          $false `
         ((Invoke-SD @('COUNT $hold')) -match 'File not found')

    # AND LIST, WHICH NAMES THE RECORD ID RATHER THAN THE FILE.  THIS SECTION
    # SHIPPED WITHOUT IT AND THE RENAME HAD ALREADY BROKEN IT: measured on the
    # 22:26:18 install, LIST VOC $hold listed 1 record and LIST VOC $HOLD
    # answered "'$HOLD' not found" - on the same record that CT VOC $HOLD
    # echoed back as $hold.  QPROC's check.record read the id exactly and had
    # no fold at all, so CT and LIST disagreed about the same name.  COUNT and
    # CT alone could never have shown it, which is why they did not.
    $lstLc = Invoke-SD @('LIST VOC $hold NO.PAGE')
    $lstUc = Invoke-SD @('LIST VOC $HOLD NO.PAGE')
    Note 'LIST VOC $hold lists the record' $true ($lstLc -match '1 record')
    Note 'LIST VOC $HOLD lists it too'     $true ($lstUc -match '1 record')
    Note 'and no longer says not found'    $false ($lstUc -match "HOLD' not found")
    # THE CONTROL: a name in no case at all must still be reported missing, or
    # the fold above would be indistinguishable from a lookup that matches
    # anything.  verify-fold.ps1 section 3 makes the same argument for files.
    $lstNo = Invoke-SD @('LIST VOC ZZNOSUCHVOCID NO.PAGE')
    Note 'control: an absent id is still not found' $true ($lstNo -match 'not found')

    # $hold, reached the way a print goes there rather than through the VOC:
    # SETPTR mode 3 with AS <name> makes SD build the path itself - SETPTR:334
    # prefixes "$HOLD " and start_file() turns that into a relative path.
    #
    # 18 Aug 26 - AND IT CANNOT TELL YOU WHETHER to_file.c WAS REBUILT.  An
    # earlier version of this comment claimed the record appearing under $hold
    # measured the C literal.  It does not, and cannot on Windows: the literal is
    # a RELATIVE path resolved against the account directory, and NTFS matches
    # $HOLD against $hold, so the old binary and the new one both write into the
    # same place.  This check passed on a cycle where to_file.c had never been
    # compiled at all - see assert-current.ps1 check A2, which now refuses that
    # tree instead.  What this check IS good for is CREATEA's rename: if the
    # directory were still $HOLD and the VOC said $hold, or either were missing,
    # nothing would arrive.
    $spool = Invoke-SD @(('SETPTR 1,132,60,0,0,3,AS ' + $holdRec + ',BRIEF'),
                         'LIST VOC COPYP LPTR 1 NO.PAGE',
                         'SP.CLOSE 1')
    Note 'printing to the hold file wrote into $hold' $true `
         (Test-Path -LiteralPath (Join-Path $acctDir ('$hold\' + $holdRec)))
    Write-Output '  --- SETPTR/LIST/SP.CLOSE said: ---'
    Write-Output $spool

    Write-Output '  --- LISTF, for the record: ---'
    Write-Output (Invoke-SD @('LISTF NO.PAGE'))

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 5. RETIRED 14 Sep 2026: AN ACCOUNT CREATED BEFORE THE RENAME ========='
    Write-Output '  Sections 5, 5a and 5b renamed a shipped VOC id back to its old upper'
    Write-Output '  spelling with "write UPPER, delete lower", measured through it, and'
    Write-Output '  renamed it back.  RELEASE_1.1 5 D2 made VOC case insensitive, so the'
    Write-Output '  delete removed the ONLY record: b161 left $savedlists, $hold and'
    Write-Output '  $command.stack missing from the account this runs in (put back by'
    Write-Output '  hand 14 Sep 2026).  A lower/upper pair cannot exist under D2, and'
    Write-Output '  section 4 already reaches the one record typed either way.  What is'
    Write-Output '  kept is behaviour on the SHIPPED ids: _NEXTPTR (5a), the stack (5b).'
    # ***DO NOT BRING A TOGGLE BACK.***  Writing one spelling and deleting another
    # on a case-insensitive file deletes the record - measured 14 Sep 2026 on a
    # scratch file (write TYPE, write type, delete TYPE: 0 records).  This test
    # runs in the owner's own account.  Owner's ruling: retire and replace.

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 5a. _NEXTPTR REACHES DICT $hold THROUGH THE SHIPPED VOC RECORD ======'
    Write-Output '  GPL.BP opens the literal "$hold" in CLEANAC, SPVIEW, MICRO, _PRFILE and'
    Write-Output '  _NEXTPTR.  NOT the SETPTR check in section 4 - to_file.c builds a RELATIVE'
    Write-Output '  path and reaches $hold whatever the VOC says.  AS NEXT goes through'
    Write-Output '  _NEXTPTR, which opens DICT "$hold" - field 3 of the VOC record.'
    Write-Output '  14 Sep 2026: the rename toggle this section had is retired (see 5).'

    $nextRec = ('ZZN' + $Tag).ToUpper()
    $holdDir = @(Get-ChildItem -LiteralPath $acctDir -Directory |
                 Where-Object { $_.Name -ieq '$hold' } | Select-Object -First 1)
    if ($holdDir.Count -ne 1) {
        Note 'section 5a could run ($hold directory found)' $true $false
    } else {
        # THE FAILURE IS SILENT, AND THAT IS WHY THE SUFFIX IS THE INSTRUMENT:
        # _NEXTPTR presets seqno to '0' and only a successful open replaces it
        # with a four-digit number, so a lookup that missed writes ZZN..._0 and a
        # lookup that hit writes ZZN..._0001.
        Get-ChildItem -LiteralPath $holdDir[0].FullName -Force |
            Where-Object { $_.Name -like ($nextRec + '_*') } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        $nxt = Invoke-SD @(('SETPTR 1,132,60,0,0,3,AS NEXT ' + $nextRec + ',BRIEF'),
                           'LIST VOC COPYP LPTR 1 NO.PAGE',
                           'SP.CLOSE 1')

        $suffixed = @(Get-ChildItem -LiteralPath $holdDir[0].FullName -Force |
                      Where-Object { $_.Name -like ($nextRec + '_*') } |
                      Select-Object -ExpandProperty Name)
        Write-Output ('  hold file now holds: ' + ($suffixed -join '  '))
        # FOUR DIGITS, NOT THE LITERAL _0001.  $NEXT persists in $hold.dic, so
        # the second run on one install would legitimately get _0002 and an exact
        # match would fail on a change that is working.  The discriminator is the
        # WIDTH: fmt(...,"4'0'R") can only produce four digits, and the preset can
        # only produce _0.
        $rxOk = '^' + [regex]::Escape($nextRec) + '_[0-9]{4}$'
        Note '_NEXTPTR reached DICT $hold' 1 `
             @($suffixed | Where-Object { $_ -match $rxOk }).Count
        Note 'and did not fall back to the unnumbered suffix' 0 `
             @($suffixed | Where-Object { $_ -ceq ($nextRec + '_0') }).Count
        Write-Output '  --- SETPTR/LIST/SP.CLOSE said: ---'
        Write-Output $nxt

        Get-ChildItem -LiteralPath $holdDir[0].FullName -Force |
            Where-Object { $_.Name -like ($nextRec + '_*') } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------------
    Write-Output ''
    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 5b. THE COMMAND STACK IS SAVED THROUGH THE SHIPPED VOC RECORD ========'
    Write-Output '  CPROC and LOGIN reach $command.stack by RECORD read.  THE INSTRUMENT IS'
    Write-Output '  THE stacks FILE, not the VOC: CPROC writes it only when it found the'
    Write-Output '  record AND the record is X type, so the file appearing is the read having'
    Write-Output '  succeeded.  14 Sep 2026: the rename toggle this section had is retired (see 5).'

    $stkDir = Join-Path $acctDir 'stacks'
    if (Test-Path -LiteralPath $stkDir) { Remove-Item -LiteralPath $stkDir -Recurse -Force }
    $null = Invoke-SD @('COUNT VOC')
    Note 'the stack is saved with the shipped lower-case id' $true (Test-Path -LiteralPath $stkDir)

    Write-Output '=== 6. COPYP, which rides this cycle and is unrelated ===================='
    Write-Output '  VOC_TEMPLATE/COPYP field 1 held the description where the type code'
    Write-Output '  belongs.  IT WAS NOT BROKEN BY IT - measured on the pre-change 18:54:10'
    Write-Output '  install, COPYP already answered "File name required", because CPROC:1436'
    Write-Output '  tests only voc.entry.type[1,1] and "Verb..." starts with V.  So the'
    Write-Output '  behaviour checks below are CONTROLS against regression, not a repair.'
    Write-Output '  They run as SDSYS, because VOC_TEMPLATE becomes SDSYS s own VOC - so these'
    Write-Output '  three legs ran in section 3 s elevated re-entry, through the SDSYS seat.'

    $ctc = $script:sdsysOut['copypct']
    Note 'CT VOC COPYP shows a bare V type code' $true ($ctc -match '(?m)^\s*1:\s*V\s*$')
    Note 'and no longer the description text'    $false ($ctc -match 'Verb for Pick style COPY')
    Write-Output '  --- CT VOC COPYP said: ---'
    Write-Output $ctc

    # Relative, not against a hardcoded message: COPYP must not answer the way an
    # unknown verb does, and must answer the way it did before the change.
    $unknown = $script:sdsysOut['unknown']
    $copyp   = $script:sdsysOut['copyp']
    # Two empty answers would be "equal" and score the row below as a PASS
    # having measured nothing; refuse that first.
    Note 'COPYP and the unknown-verb control both answered' $true ($copyp -ne '' -and $unknown -ne '')
    Note 'COPYP answers differently from an unknown verb' $false ($copyp -eq $unknown)
    Note 'COPYP still reaches $COPYP itself' $true ($copyp -match 'File name required')

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 7. WHY COPYP WAS NEVER BROKEN, measured rather than argued ==========='
    Write-Output '  CPROC:1410 says a type code MAY be followed by comment text with no'
    Write-Output '  space - the PI / PI-open / UniVerse rule - and CPROC:1433 tests only'
    Write-Output '  voc.entry.type[1,1].  So "Verb for Pick style COPY" is a V with a'
    Write-Output '  comment.  This builds such a record from scratch and dispatches it.'
    Write-Output '  It is what corrects the changelog entry that said UNLOCK never worked.'

    # A PROGRAM, because no verb writes an arbitrary VOC record.  It goes in the
    # account VOC rather than the SDSYS one, so this stays unelevated like the
    # rest of the script.
    $mk = 'ZZMKDESCV'
    $bpDir = @(Get-ChildItem -LiteralPath $acctDir -Directory |
               Where-Object { $_.Name -ieq 'bp' } | Select-Object -First 1)
    if ($bpDir.Count -ne 1) {
        Note 'section 7 could run (bp directory found)' $true $false
    } else {
        $mkSrc = @"
* $mk - written by verify-lcnames.ps1.  Safe to delete.
   open 'VOC' to voc.f else stop
   rec = 'Verb with a description where the bare code usually goes'
   rec<2> = 'CA'
   rec<3> = '`$COPYP'
   write rec to voc.f, 'ZZDESCV'
   print 'WROTE=OK'
end
"@
        [IO.File]::WriteAllText((Join-Path $bpDir[0].FullName $mk),
                                ($mkSrc -replace "`r`n", "`n"),
                                (New-Object Text.UTF8Encoding $false))

        $mkOut = Invoke-SD @("BASIC bp $mk", "RUN bp $mk")
        if ($mkOut -notmatch 'WROTE=OK') {
            Write-Output '  --- SD said: ---'
            Write-Output $mkOut
            Note 'the descriptive VOC record was written' $true $false
        } else {
            Note 'the descriptive VOC record was written' $true $true

            # THE MEASUREMENT.  If a descriptive type code did NOT dispatch, this
            # would answer the way an unknown verb does.  $COPYP with no argument
            # says "File name required", which only a dispatched verb can produce.
            $descOut    = Invoke-SD @('ZZDESCV')
            $unknownOut = Invoke-SD @('ZZNOSUCHVERBATALL')
            Note 'a descriptive type code still dispatches' $true `
                 ($descOut -match 'File name required')
            Note 'and does not answer like an unknown verb' $false `
                 (($descOut -replace 'ZZDESCV', '') -eq ($unknownOut -replace 'ZZNOSUCHVERBATALL', ''))
            Write-Output '  --- ZZDESCV said: ---'
            Write-Output $descOut
        }

        # Both halves go, whether or not the checks passed.
        $null = Invoke-SD @('DELETE VOC ZZDESCV')
        Remove-Item -LiteralPath (Join-Path $bpDir[0].FullName $mk) -Force -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 8. A LOWER-CASE VOC ID, REACHED BY TYPING IT IN UPPER CASE ==========='
    Write-Output '  Nothing SD ships is lower case yet, so the DOWNWARD half of the fold has'
    Write-Output '  never fired for a verb or a keyword - only the upward half has, which is'
    Write-Output '  what sections 3 to 5a measure.  This makes two records with lower-case'
    Write-Output '  ids and reaches them by typing the names in UPPER case.'
    Write-Output '  IT FOUND A REAL BLOCKER on 18 Aug 2026.  CPROC:1401 resolved a typed verb'
    Write-Output '  as entered, then UPPER, then upper-with-hyphens-as-dots, with no'
    Write-Output '  lower-case attempt at all - so lower-casing the command ids would have'
    Write-Output '  made every verb typed in upper case answer "is not in your VOC", for'
    Write-Output '  every user.  Reading the code said otherwise; only this said so.'

    $mkp = 'ZZMKPROBE'
    $bp8 = @(Get-ChildItem -LiteralPath $acctDir -Directory |
             Where-Object { $_.Name -ieq 'bp' } | Select-Object -First 1)
    if ($bp8.Count -ne 1) {
        Note 'section 8 could run (bp directory found)' $true $false
    } else {
        # Single-quoted here-string: every $ in it is SD source, not PowerShell.
        # The COUNT.SUP read folds both ways so this section keeps working after
        # the command ids move - it is the thing being tested, so it must not
        # assume the answer.
        $mkpSrc = @'
* ZZMKPROBE - written by verify-lcnames.ps1.  Safe to delete.
* Writes two VOC records whose ids are LOWER CASE: a verb and a keyword.
   open 'VOC' to voc.f else stop
   rec = 'V'
   rec<2> = 'CA'
   rec<3> = '$COPYP'
   write rec to voc.f, 'zzprobev'

   k = ''
   read k from voc.f, 'COUNT.SUP' else
      read k from voc.f, 'count.sup' else k = ''
   end

   if k # '' then
      write k to voc.f, 'zzprobek'
      print 'WROTE=OK'
   end else
      print 'WROTE=NOKEYWORD'
   end
end
'@
        [IO.File]::WriteAllText((Join-Path $bp8[0].FullName $mkp),
                                ($mkpSrc -replace "`r`n", "`n"),
                                (New-Object Text.UTF8Encoding $false))

        $mk8 = Invoke-SD @("BASIC bp $mkp", "RUN bp $mkp")
        if ($mk8 -notmatch 'WROTE=OK') {
            Write-Output '  --- SD said: ---'
            Write-Output $mk8
            Note 'the two lower-case probe records were written' $true $false
        } else {
            Note 'the two lower-case probe records were written' $true $true

            # THE VERB.  $COPYP with no argument says "File name required", which
            # only a dispatched verb can produce, and an unknown verb says "is
            # not in your VOC" - two different answers, so this cannot pass by
            # accident.  The id is zzprobev and the name typed is ZZPROBEV.
            $v8 = Invoke-SD @('ZZPROBEV')
            Note 'a lower-case VERB id dispatches typed UPPER' $true `
                 ($v8 -match 'File name required')
            Note 'and does not answer "not in your VOC"'      $false `
                 ($v8 -match 'is not in your VOC')
            Write-Output '  --- ZZPROBEV said: ---'
            Write-Output $v8

            # THE CONTROL for it: a name that is in the VOC in NO case must still
            # be refused, or the fold above would be indistinguishable from a
            # lookup that matches anything.
            $vc8 = Invoke-SD @('ZZPROBEVNOSUCH')
            Note 'control: an unknown verb is still refused' $true `
                 ($vc8 -match 'is not in your VOC')

            # THE KEYWORD, and the instrument is a VISIBLE DIFFERENCE rather than
            # an absence of error.  zzprobek is a copy of COUNT.SUP, which
            # suppresses the "n record(s) listed" line.  Typed as ZZPROBEK it can
            # only take effect if the keyword read folded downwards; if it did
            # not, QPROC treats the token as a RECORD ID instead and says so.
            $kOn  = Invoke-SD @('LIST VOC COPYP NO.PAGE')
            $kOff = Invoke-SD @('LIST VOC COPYP ZZPROBEK NO.PAGE')
            Note 'without the keyword, the count line is printed' $true `
                 ($kOn  -match 'record\(s\) listed')
            Note 'a lower-case KEYWORD id works typed UPPER'      $false `
                 ($kOff -match 'record\(s\) listed')
            Note 'and was not taken for a record id'              $false `
                 ($kOff -match 'ZZPROBEK. not found')
            Write-Output '  --- LIST ... ZZPROBEK said: ---'
            Write-Output $kOff
        }

        # Both records and the program go, whether or not the checks passed.
        $null = Invoke-SD @('DELETE VOC zzprobev', 'DELETE VOC zzprobek')
        Remove-Item -LiteralPath (Join-Path $bp8[0].FullName $mkp) -Force -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 9. THE OBJECT FILE NAME, WHICH IS WHAT BP HAD TO MOVE BEHIND =========='
    Write-Output '  BASIC used to build the object file name from the TOKEN, so "BASIC bp X"'
    Write-Output '  asked for bp.OUT - and CREATE.FILE writes the VOC id as typed while upper'
    Write-Output '  casing the directory.  No case of the three-case fold reaches a MIXED-case'
    Write-Output '  id, so the next "BASIC BP Y" could never open it and never will again.'
    Write-Output '  BASIC now names it from the VOC record that answered, suffix and all.'

    # THIS SECTION HAS TO START FROM NO OBJECT FILE AT ALL.  With one already
    # there, BASIC's open succeeds and the create branch - the only place the
    # name is built - is never reached, so the section would pass without
    # measuring anything.  Removing it is safe: it holds compiled objects that
    # any BASIC re-creates, and Remove-Probes tidies the new one afterwards.
    $null = Invoke-SD @('DELETE.FILE bp.out FORCE', 'DELETE.FILE bp.OUT FORCE',
                        'DELETE.FILE BP.OUT FORCE')
    $leftover = @(Get-ChildItem -LiteralPath $acctDir -Directory -ErrorAction SilentlyContinue |
                  Where-Object { $_.Name -ieq 'bp.out' })
    foreach ($l in $leftover) { Remove-Item -LiteralPath $l.FullName -Recurse -Force -ErrorAction SilentlyContinue }
    $script:hadObjDir = $false
    Note 'the object file was cleared, so the create branch is reached' 0 `
         @(Get-ChildItem -LiteralPath $acctDir -Directory -ErrorAction SilentlyContinue |
           Where-Object { $_.Name -ieq 'bp.out' }).Count

    $bp9 = @(Get-ChildItem -LiteralPath $acctDir -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -ceq 'bp' })
    if ($bp9.Count -ne 1) {
        Note 'section 9: the account has a lower-case bp to compile into' $true $false
    } else {
        $rd9 = ('ZZR' + $Tag).ToUpper()
        $up9 = ('ZZU' + $Tag).ToUpper()

        # THE READER USED EXACT-MATCH READS until 14 Sep 2026.  RELEASE_1.1 5 D2
        # made a read of VOC case insensitive, so 'bp.OUT' and 'BP.OUT' both found
        # bp.out (b161: MIXED=YES and UPPER=YES on a correct install).  The stored
        # id is now read from "LIST VOC WITH @ID LIKE", which prints it as stored
        # (measured the same day: LIKE "bp.OUT" listed bp.out).
        $rd9Src = @'
program zzreadout
   print 'RAN=OK'
end
'@
        [IO.File]::WriteAllText((Join-Path $bp9[0].FullName $rd9),
                                ($rd9Src -replace "`r`n", "`n"),
                                (New-Object Text.UTF8Encoding $false))

        # Compiling it IS the measurement: this is the compile that goes through
        # the create branch, typed in LOWER case against a VOC id that is now bp.
        $mk9 = Invoke-SD @("BASIC bp $rd9", "RUN bp $rd9", 'LIST VOC WITH @ID LIKE "bp.out"')
        Write-Output '  --- BASIC bp / RUN bp / LIST VOC WITH @ID LIKE said: ---'
        Write-Output $mk9

        Note 'the probe compiled and ran' $true ($mk9 -match 'RAN=OK')
        Note 'BASIC bp <x> created the object file as bp.out' $true `
             ($mk9 -cmatch '(?m)^bp\.out\s{2,}')
        Note 'and NOT as the mixed-case bp.OUT'               $false `
             ($mk9 -cmatch '(?m)^bp\.OUT\s{2,}')
        Note 'and not as BP.OUT either'                       $false `
             ($mk9 -cmatch '(?m)^BP\.OUT\s{2,}')

        # THE REGRESSION ITSELF, and it is a different assertion from the one
        # above: the failure was never in the compile that made the file, it was
        # in the NEXT one, typed the other way.  "Data pathname 'BP.OUT' already
        # exists" is the exact message it used to stop with.
        $upSrc = @'
program zzupperout
   print 'UPPERCOMPILE=OK'
end
'@
        [IO.File]::WriteAllText((Join-Path $bp9[0].FullName $up9),
                                ($upSrc -replace "`r`n", "`n"),
                                (New-Object Text.UTF8Encoding $false))

        $u9 = Invoke-SD @("BASIC BP $up9", "RUN BP $up9")
        Write-Output '  --- BASIC BP / RUN BP said: ---'
        Write-Output $u9

        Note 'BASIC BP <y> afterwards does not hit "already exists"' $false `
             ($u9 -match 'already exists')
        Note 'and it compiles and runs'                              $true `
             ($u9 -match 'UPPERCOMPILE=OK')

        Remove-Item -LiteralPath (Join-Path $bp9[0].FullName $rd9) -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $bp9[0].FullName $up9) -Force -ErrorAction SilentlyContinue
    }

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 10. RELEASE_1.1 5 STAGE 1, 14 Sep 2026 ================================='

    # 10a. THE LAST FOUR UPPER-CASE VOC IDS NEWVOC SHIPPED - $ACC, $MAP, $RELEASE,
    # SD.VOCLIB - are $acc, $map, $release, sd.voclib.  Section 3's instrument,
    # as it is since 14 Sep 2026: typing the old name reaches the record, and
    # LIKE's row shows it stored lower.  (An account made BEFORE the rename is
    # verify-tiers.ps1 section 5b's job, which needs an account of its own.)
    $p10 = @(@{U='$ACC'; L='$acc'}, @{U='$MAP'; L='$map'},
             @{U='$RELEASE'; L='$release'}, @{U='SD.VOCLIB'; L='sd.voclib'})
    $ct10 = Invoke-SD (@($p10 | ForEach-Object { 'CT VOC ' + $_.U }) + @(Get-LikeQuery @($p10 | ForEach-Object { $_.L })))
    Note-Pairs $ct10 $p10 ''
    Write-Output '  --- CT VOC said: ---'
    Write-Output $ct10

    # 10b. CASE INVERSION - A CONTROL HERE, NOT THE WITNESS.  LOGIN turned it on
    # at every login and linuxio.c at session start; the owner ruled both off.
    # ***NOTHING CAN TELL THE OLD CODE FROM THE NEW***: measured 14 Sep 2026 on
    # the install that still had both, inversion read Off piped, under
    # sd -internal, and interactively (the owner) - on Windows it was already not
    # in effect, cause untraced.  verify-createfilecase.ps1 holds the -internal
    # reading as a regression guard.  What this section can still hold is that PTERM itself reports and
    # sets the flag: Off, then On after PTERM CASE INVERT (sysmsg 6833 / 6832),
    # then NOINVERT so the session ends as it began.
    $pt10 = Invoke-SD @('PTERM DISPLAY', 'PTERM CASE INVERT', 'PTERM DISPLAY', 'PTERM CASE NOINVERT')
    $readings = @([regex]::Matches($pt10, 'Case inversion: (On|Off)') | ForEach-Object { $_.Groups[1].Value })
    Write-Output ('  PTERM DISPLAY readings, in order: ' + ($readings -join ', '))
    Note 'PTERM DISPLAY was read twice'                          2     $readings.Count
    Note 'control: a piped session reads case inversion Off'     'Off' $(if ($readings.Count -ge 1) { $readings[0] } else { '(none)' })
    Note 'control: PTERM CASE INVERT then reads On'              'On'  $(if ($readings.Count -ge 2) { $readings[1] } else { '(none)' })

    # 10c. THE SYSCOM INCLUDE RECORDS ARE LOWER CASE ON DISK.  Exact-case listing,
    # the section 2 instrument (Test-Path would match either).  Every shipped name
    # in syscom, not a sample, so a file that missed the rename is named.
    $syscomDir = Join-Path $sdsysDir 'syscom'
    $sysc = @(Get-ChildItem -LiteralPath $syscomDir -File -Force | Select-Object -ExpandProperty Name)
    Write-Output ('  syscom listing: ' + (($sysc | Sort-Object) -join '  '))
    Note 'syscom listing is not empty' $true ($sysc.Count -gt 0)
    foreach ($n in @('err.h', 'keys.h', 'parser.h', '$pcldata', 'sdclient.bas')) {
        Note ('syscom ' + $n + ' present, exact case') 1 @($sysc | Where-Object { $_ -ceq $n }).Count
    }
    Note 'syscom holds no name with an upper-case letter' '' `
         (($sysc | Where-Object { $_ -cmatch '[A-Z]' }) -join ' ')

    # -----------------------------------------------------------------------
    if (-not $Keep) {
        Write-Output ''
        Write-Output '=== cleanup =============================================================='
        Remove-Probes
    } else {
        Write-Output ''
        Write-Output '  -Keep: probe records left behind.  Remove them with -Cleanup.'
    }

    Write-Output ''
    Write-Output '=== Summary =============================================================='
    $results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
    $passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
    Write-Output ("  {0} of {1} checks passed" -f $passed, $results.Count)
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}

if ($failed) { exit 1 } else { exit 0 }
