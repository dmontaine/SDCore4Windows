# verify-vocverbs.ps1 - exercise the five PRE_RELEASE fixes that need no
# account: 5 (.D folds case), 13 (QSELECT names its list), 14 (NO.QUERY does
# not prompt on an @SDSYS part), 15 (DELETE.INDEX folds case), 26 (DELETE.FILE
# does not prompt on a lower-case name).
#
#   powershell -File verify-vocverbs.ps1                 run the checks
#   powershell -File verify-vocverbs.ps1 -Prefix zzprfb  use a different name set
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# WHY IT EXISTS.  All five shipped into the install of 28 Aug 2026 00:53:34 and
# NOTHING HAS RUN ANY OF THEM.  They compiled and they installed; that is not
# the same as working, and PRE_RELEASE_FIXES.md marks each of them "COMPILED
# AND INSTALLED - UNTESTED" on purpose.  This is the witness.
#
# RUN IT ELEVATED, AND THAT IS NOT A PREFERENCE.  Every session here starts
# with LOGTO SDSYS, which is administrator-only, and the fixtures are created
# in the SDSYS account directory, which the step 15 ACL lock closes to an
# ordinary token.
#
# ***THE ONE CHECK THAT SEPARATES A FIX FROM AN ACCIDENT, PER ENTRY.***  Each
# entry anchors on wording the tool prints ONLY on the path under test, and
# names a disqualifier - the wording the refusal prints - which fails the row
# if it appears too.  CLAUDE.md, "a check must anchor on the SUCCESS wording":
#
#   5   ".D <UPPER>" must print 5040 naming the record in LOWER case.  The
#       failure path cannot print that line at all - it prints 5043 - so the
#       prompt itself is the evidence, and the COUNT of 5040 lines is what
#       proves the second half (a name matching nothing must not reach it).
#   13  3261 must end in a list NUMBER.  The defect printed the same message
#       with one argument, so the text was identical up to the dangling
#       "select list ".  Matching "select list" would have passed on the defect.
#   14  10117's own sentence, which only check.sdsys.file's NO.QUERY branch
#       prints, AND the absence of 6146, the prompt it replaced.  Answering
#       6146 with N reaches the same skip.part, so 10117 alone does not
#       separate fix from defect - the disqualifier is the whole check.
#   15  2627 "Deleted index F1" - the UPPER-case real name, from a verb typed
#       in lower case.  Disqualifier 2604 "Unrecognised index name (f1)".
#   26  6136/6141/6144, and the ABSENCE of 6135 and 6140.
#
# ***ENTRY 26 IS NOT TESTED THE WAY START HERE SUGGESTS.***  That box says
# "delete.file zzwork force".  ***THAT TEST CANNOT FAIL***: DELETEF guards both
# prompts with "if not(force)" (:250 and :319), so force suppresses them
# whether or not the fix is present, and the run would score a pass having
# measured nothing.  The reproduction entry 26 itself describes is the NO.QUERY
# form, which does NOT suppress them - only the path comparison does.  That is
# what runs here.
#
# ***MATCHING IS CASE-SENSITIVE, AND THAT IS THE POINT.***  Three of the five
# fixes ARE case behaviour, so IgnoreCase would make the disqualifiers match
# their own success wording - "'ZZPRFD' not found" would match the lower-case
# line the fix DOES print, and the run would fail a working build.  Test-Say
# passes Multiline only.  Every pattern below is therefore written in the exact
# case the message file uses.
#
# ***A VERB WHOSE ARGUMENT IS OPTIONAL PROMPTS FOR IT, AND DOWN A PIPE THE
# PROMPT EATS THE NEXT LINE.***  Measured 28 Aug 2026, first run: "LIST.INDEX
# zzprfak" with no index name reached LISTI:117's "Index name:", swallowed the
# OFF that followed, answered its own question with it, and the session sat
# until the 60-second timeout.  It cost the run at the entry 15 fixture, with
# entries 5, 13 and 14 already passed.
#
# THE CLASS IS WIDER THAN THIS ONE VERB.  LISTI:117 and DELETEI:101 hold the
# same block, DELETEF:117 prompts when no file name is given, DELACC:96 when no
# account is.  ***THE RULE FOR ANYTHING DRIVEN DOWN A PIPE IS TO NAME EVERY
# OPTIONAL ARGUMENT*** - "ALL" or an explicit name - rather than to rely on the
# form a person would type interactively.  The tell is a transcript in which
# SD's last line is a prompt and the command after it never appears.
#
# WHAT IT TOUCHES.  Five names under one prefix, all created and removed by
# this script, all inside SDSYS.  Entry 14 needs a VOC record whose part is in
# the system account: it COPIES the "messages" pointer to a name of its own
# rather than going near a real system file, and the run asserts sdsys\messages
# is still on disk afterwards.

[CmdletBinding()]
param([string]$Prefix = 'zzprf')

$ErrorActionPreference = 'Stop'

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys   = Join-Path $env:ProgramData  'SD\sdsys'
$sysFile = Join-Path $sdsys 'messages'      # the real file entry 14 must NOT delete

$results = New-Object System.Collections.ArrayList
$fatal   = $false
$lastSD  = ''

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check    = $step
        Expected = $expected
        Observed = $got
        Result   = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $step, $expected, $got)
}

# 24 Aug 26 - THE VERDICT LINE.  Kept BYTE-FOR-BYTE IDENTICAL to the copies in
# verify-createaccount.ps1, verify-cmdaudit.ps1 and verify-sshonly.ps1, and
# test-verdict-units.ps1 asserts that across all of them.  If one changes,
# change all of them.
function Write-Verdict($name) {
    $all      = @($script:results)
    $decisive = @($all | Where-Object { $_.Decisive -eq 'yes' })
    $failed   = @($decisive | Where-Object { $_.Result -ne 'PASS' })

    Write-Output ""
    if ($decisive.Count -eq 0) {
        Write-Output ("{0}: FAILED - NO DECISIVE CHECK RAN, so this run proves nothing." -f $name)
        Write-Output ("  {0} row(s) recorded, none of them decisive." -f $all.Count)
        $script:fatal = $true
        return
    }
    if ($failed.Count -gt 0) {
        Write-Output ("{0}: FAILED - {1} of {2} decisive checks failed:" -f $name, $failed.Count, $decisive.Count)
        $failed | ForEach-Object { Write-Output ("    " + $_.Check) }
        $script:fatal = $true
        return
    }
    Write-Output ("{0}: PASSED - {1} of {1} decisive checks passed, {2} row(s) in all." -f
                  $name, $decisive.Count, $all.Count)
}

# --------------------------------------------------------------- text helpers
#
# PURE, and separate from everything that touches the machine.  Both take a
# REGULAR EXPRESSION, never a bare string: PROJECT_STATUS.md section 6 records a
# check that used -SimpleMatch with an interpolated variable and reported a
# string that was present as absent.  Callers escape their own literals.
#
# NEITHER WRITES ANYTHING.  A function that both prints and returns hands the
# caller its printed lines JOINED to the return value, which is how a check on
# "the output" quietly becomes a check on the narration.
function Test-Say([string]$text, [string]$pattern) {
    if ([string]::IsNullOrEmpty($text)) { return $false }
    return ([regex]::IsMatch($text, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline))
}
function Get-SayCount([string]$text, [string]$pattern) {
    if ([string]::IsNullOrEmpty($text)) { return 0 }
    return ([regex]::Matches($text, $pattern, [Text.RegularExpressions.RegexOptions]::Multiline)).Count
}

# ------------------------------------------------------------------ Invoke-SD
#
# COPIED FROM probe-catprivate.ps1:144 UNCHANGED, which is the shape
# PROJECT_STATUS.md section 6 says works: ONE STRING with LF separators (an
# ARRAY down the pipe puts a phantom empty line after every command, and an
# "input" statement eats it), a leading newline as the BOM sink, TERM to stop
# pagination, OFF to end it, and a TIMEOUT that says so out loud rather than
# returning empty.
#
# THE TIMEOUT IS NOT DECORATION HERE.  Three of the five sessions below run a
# verb that PROMPTS if its fix is absent, and a prompt down a pipe eats the
# following lines - including OFF.  A regressed build therefore hangs, and this
# branch is what turns that into a legible failure instead of a stray sd.exe
# nobody accounts for.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** It also leaves the session's user-table slot and locks behind,"
        $out += "*** so sdwind will not shut down and cycle.ps1 will refuse to"
        $out += "*** start.  Stop-Process the sdwind PID it names."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# EVERY SESSION'S RAW OUTPUT IS PRINTED, unconditionally.  CLAUDE.md, "an
# instrument shows what it DID": a conditional print cannot catch a subtle
# refusal, because the condition is the thing that was wrong.  The commands are
# echoed from the ARRAY THAT WAS PASSED, not from SD's echo of them - section 6
# records a transcript in which SD's own [K erase-line sequences rendered
# "CREATE.ACCOUNT USER sdacct1" as "CREATE.ACCOUSER sdacct1" on a line that
# executed correctly.
#
# IT RETURNS NOTHING AND LEAVES THE OUTPUT IN $script:lastSD.  Returning it
# would hand the caller these Write-Output lines joined to SD's, and every
# pattern below would then be matching this function's own narration.
function Show-SD([string]$title, [string[]]$commands) {
    Write-Output ("  --- SD session: " + $title + " ---")
    foreach ($c in $commands) { Write-Output ("    > " + $c) }
    $out = Invoke-SD $commands
    Write-Output '    --- SD said: ---'
    foreach ($line in ($out -split "`n")) { Write-Output ("    | " + $line.TrimEnd()) }
    Write-Output ''
    $script:lastSD = $out
}

# ------------------------------------------------------------- preconditions

if ($Prefix -cnotmatch '^[a-z][a-z0-9]{1,6}$') {
    Write-Output "verify-vocverbs: -Prefix is '$Prefix'."
    Write-Output '  Lower case letters and digits only, starting with a letter, 2 to 7 characters.'
    Write-Output '  CREATE.FILE upper-cases the name for the PATH and leaves the VOC id as typed,'
    Write-Output '  and entries 15 and 26 are ABOUT that difference - a mixed-case prefix would'
    Write-Output '  make the two sides of the comparison disagree for a reason that is not the'
    Write-Output '  one under test.'
    exit 2
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-vocverbs: this needs an ELEVATED PowerShell and this one is not.'
    Write-Output '  Every session here starts with LOGTO SDSYS, which is administrator-only,'
    Write-Output '  and the fixtures are written inside the SDSYS account directory, which the'
    Write-Output '  step 15 ACL lock closes to an ordinary token.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1') -Quiet | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-vocverbs: the installed tree does not match source - run a cycle first.'
    Write-Output '  A result from a stale tree is worse than no result: it looks like evidence.'
    exit 2
}

foreach ($p in @($sdExe, $sdsys, $sysFile)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("verify-vocverbs: {0} does not exist - nothing could be measured." -f $p)
        exit 2
    }
}

# ------------------------------------------------------------------ the names
#
# ***THE CASE OF EACH NAME IS DELIBERATE AND IS NOT COSMETIC.***  Where the fix
# under test is about case, the name is LOWER and the verb that must fold it is
# typed in the other case.  Where it is not - the entry 14 pointer and the
# entry 15 dictionary source - the name is UPPER, so that every read of it hits
# DELETEF's exact-match path.  A name whose case does not match its VOC id
# reaches 6130 and then the "Use file 'x'?" prompt at :161, which down a pipe
# eats the following line; that is a hang this script has no reason to risk in
# a step that is only clearing up.
$vocSent = $Prefix + 'd'                   # entry 5   saved lower, deleted UPPER
$sysPtr  = ($Prefix + 'f').ToUpper()       # entry 14  copy of the messages pointer
$akFile  = $Prefix + 'ak'                  # entry 15  lower: the fold is the test
$srcFile = ($Prefix + 'src').ToUpper()     # entry 15  the dictionary source
$wFile   = $Prefix + 'w'                   # entry 26  lower: the fold is the test

$srcDir  = Join-Path $sdsys $srcFile
$akDir   = Join-Path $sdsys $akFile.ToUpper()
$wDir    = Join-Path $sdsys $wFile.ToUpper()
$allDirs = @($srcDir, ($srcDir + '.DIC'),
             $akDir,  ($akDir  + '.DIC'),
             $wDir,   ($wDir   + '.DIC'))
$allNames = @($vocSent, $sysPtr, $akFile, $srcFile, $wFile)

Write-Output ("verify-vocverbs: as {0}, ELEVATED" -f $id.Name)
Write-Output ("  sd      {0}" -f $sdExe)
Write-Output ("  sdsys   {0}" -f $sdsys)
Write-Output ("  prefix  {0}" -f $Prefix)
Write-Output ("  names   {0}" -f ($allNames -join ', '))
Write-Output ''

# ------------------------------------------------------- 0. clear the ground
#
# ***AND THEN REFUSE IF IT IS NOT CLEAR.***  Every fixture below is created by
# this run; if one of these names survives the sweep it belongs to something
# else, and every measurement after it would describe a record this script did
# not write.  CLAUDE.md: a test that passes because it did nothing must fail.

Write-Output '=== 0. clear the ground ==================================================='

Show-SD 'pre-clean' @(
    ('DELETE VOC ' + $vocSent),
    ('DELETE.FILE ' + $sysPtr  + ' NO.QUERY'),
    ('delete.file ' + $akFile  + ' no.query'),
    ('DELETE.FILE ' + $srcFile + ' NO.QUERY'),
    ('delete.file ' + $wFile   + ' no.query'))

foreach ($p in $allDirs) {
    if (Test-Path -LiteralPath $p) {
        Write-Output ("  removing stale " + $p)
        Remove-Item -LiteralPath $p -Recurse -Force
    }
}

# .L folds case itself, so one spelling finds the record whatever case it is
# in, and prints 5043 naming it exactly as typed when it is absent.
Show-SD 'confirm the ground is clear' ($allNames | ForEach-Object { '.L ' + $_ })
$clear = $lastSD
foreach ($n in $allNames) {
    Note ("ground is clear: " + $n) $true `
         (Test-Say $clear ("'" + [regex]::Escape($n) + "' not found in VOC")) $true
}
if ($fatal) {
    Write-Output ''
    Write-Output 'verify-vocverbs: one of the fixture names already exists and could not be'
    Write-Output '  removed.  Nothing below would be measuring a record this run created.'
    Write-Output ('  Re-run with a fresh name set, e.g. -Prefix ' + $Prefix + '2')
    Write-Verdict 'verify-vocverbs'
    exit 1
}

# ------------------------------------------------ 5. .D folds the record name

Write-Output ''
Write-Output '=== PRE_RELEASE 5: ".D name" finds a lower-case record typed in upper ====='

# THE FIXTURE IS MADE WITH .S, which writes the name EXACTLY AS TYPED - so the
# record is lower case and the ".D" below is upper case, which is the case under
# test.  "001  S" in the listing is what proves .S wrote a record of the type .D
# requires: a record that exists but is neither S nor PA takes a different
# branch (5041) and would never reach the prompt this section anchors on.
Show-SD 'entry 5' @(
    'WHO',
    ('.S ' + $vocSent + ' 1'),
    ('.L ' + $vocSent),
    ('.D ' + $vocSent.ToUpper()),
    'Y',
    ('.L ' + $vocSent),
    ('.D ' + $Prefix + 'nosuch'))
$e5 = $lastSD

Note 'entry 5 fixture: .S wrote an S-type record' $true `
     (Test-Say $e5 '^[ \t]*001[ \t]+S[ \t]*\r?$') $true

# DECISIVE, AND SUCCESS-ONLY.  5040 names $vocSent in LOWER case after ".D" was
# typed in UPPER: the only way at.command holds the lower-case name at that
# point is the downcase read the fix added.  The old code failed both reads and
# printed nothing here at all.
Note 'entry 5: .D UPPER reached the delete prompt for the lower-case record' $true `
     (Test-Say $e5 ("Delete VOC record '" + [regex]::Escape($vocSent) + "'")) $true

# Disqualifier: the refusal wording for the name as typed.
Note 'entry 5: .D UPPER did NOT report the name as not found' $false `
     (Test-Say $e5 ("'" + [regex]::Escape($vocSent.ToUpper()) + "' not found in VOC")) $true

# AFTER state.  The fixture row above is the BEFORE state, so this pair is a
# state comparison and not a single reading.
Note 'entry 5: the record is gone afterwards' $true `
     (Test-Say $e5 ("'" + [regex]::Escape($vocSent) + "' not found in VOC")) $true

# THE SECOND HALF OF THE FIX - the fall-through.  A name that matches nothing
# must report 5043 and leave, NOT act on whatever voc.rec was last read.  The
# evidence is arithmetic: exactly ONE delete prompt in the whole session.
Note 'entry 5: an unknown name says not found' $true `
     (Test-Say $e5 ("'" + [regex]::Escape($Prefix + 'nosuch') + "' not found in VOC")) $true
Note 'entry 5: only ONE delete prompt fired in the session' 1 `
     (Get-SayCount $e5 'Delete VOC record') $true

# ------------------------------------------ 13. QSELECT names its select list

Write-Output ''
Write-Output '=== PRE_RELEASE 13: QSELECT ends with the list number ====================='

# "*" RATHER THAN THE BARE FORM THE ENTRY QUOTES.  "QSELECT VOC SAVING 3" with
# no source needs an ACTIVE select list and otherwise stops at 3290 (QSELECT:196),
# and a preceding SELECT would print a "selected to select list" line of its own
# - which is the wording under test.  The "*" form is self-contained and leaves
# exactly one such line in the transcript.
Show-SD 'entry 13' @('QSELECT VOC * SAVING 3', 'CLEARSELECT')
$e13 = $lastSD

Note 'entry 13: the message ends with a list NUMBER' $true `
     (Test-Say $e13 '\d+ record\(s\) selected to select list \d+') $true

# Disqualifier: the defect printed the same sentence with nothing after it.
Note 'entry 13: no dangling "select list" with no number' $false `
     (Test-Say $e13 'selected to select list[ \t]*\r?$') $true

# NULL CASE.  "0 record(s) selected to select list 0" is a well-formed message
# and would pass the row above while proving QSELECT read nothing.
Note 'entry 13: it did NOT select zero records' $false `
     (Test-Say $e13 '(^|[ \t])0 record\(s\) selected') $true

# --------------------------- 14. NO.QUERY does not prompt on an @SDSYS part

Write-Output ''
Write-Output '=== PRE_RELEASE 14: DELETE.FILE NO.QUERY on a part in SDSYS =============='

# THE FIXTURE IS A COPY OF THE "messages" POINTER, NOT THE POINTER ITSELF.  The
# branch under test fires on any VOC F record whose path starts @SDSYS, and
# copying one gives a record this run owns while still pointing at a real system
# file - which is what makes the "the file itself is left where it is" half
# measurable at all.
Note 'entry 14 fixture: sdsys\messages exists before' $true `
     (Test-Path -LiteralPath $sysFile) $true

# The trailing N,N are REGRESSION ANSWERS, not part of the test: on a build
# without the fix 6146 prompts and eats the following lines, and its loop only
# leaves on a Y or an N.  They cannot score a pass - the disqualifier below
# requires 6146 to be ABSENT, and answering it is exactly what that forbids.
# They also answer 6131 if COPY ever stores the target id in a case that makes
# DELETEF miss it, which would otherwise hang this session for 60 seconds.
Show-SD 'entry 14' @(
    ('COPY FROM VOC messages,' + $sysPtr),
    ('.L ' + $sysPtr),
    ('DELETE.FILE ' + $sysPtr + ' NO.QUERY'),
    'N',
    'N',
    ('.L ' + $sysPtr))
$e14 = $lastSD

Note 'entry 14 fixture: the copied pointer names an @SDSYS path' $true `
     (Test-Say $e14 '^[ \t]*002[ \t]+@SDSYS/messages[ \t]*\r?$') $true

Note 'entry 14: NO.QUERY said what it did instead of asking' $true `
     (Test-Say $e14 'NO\.QUERY was given and the data part of this file is in the system account') $true

# THE DISQUALIFIER IS THE WHOLE CHECK.  Answering 6146 with N reaches the same
# skip.part the fix does, so 10117 alone does not separate them - only the
# absence of the question does.
Note 'entry 14: the system-account question was NOT asked' $false `
     (Test-Say $e14 'Delete the file from the system account') $true

Note 'entry 14: the VOC reference was deleted' $true `
     (Test-Say $e14 ("VOC entry '" + [regex]::Escape($sysPtr) + "' deleted")) $true
Note 'entry 14: the pointer is gone from VOC afterwards' $true `
     (Test-Say $e14 ("'" + [regex]::Escape($sysPtr) + "' not found in VOC")) $true

# AND THE HALF THAT MATTERS MOST: the real file is still there.  Read from disk,
# not from what SD said about it.
Note 'entry 14: sdsys\messages is still on disk afterwards' $true `
     (Test-Path -LiteralPath $sysFile) $true

# ------------------------------------- 15. DELETE.INDEX folds the index name

Write-Output ''
Write-Output '=== PRE_RELEASE 15: DELETE.INDEX matches a lower-case index name ========='

Show-SD 'entry 15 fixture: the dictionary source' @(('CREATE.FILE ' + $srcFile + ' DIRECTORY'))
$e15a = $lastSD

if ((-not (Test-Say $e15a 'Created DATA part as')) -or -not (Test-Path -LiteralPath $srcDir)) {
    Write-Output ('  ' + $srcFile + ' was not created - entry 15 cannot be set up.')
    Write-Output '  That is "could not be run", not a failure of the fix.'
    Write-Verdict 'verify-vocverbs'
    exit 2
}

# A D-type dictionary item, written as a directory-file record and copied in.
# CREATE.INDEX refuses a field that is not in the dictionary (2608), so this is
# the cheapest way to give the file something indexable without an interactive
# editor.  Fields: type, location, conversion, name, format, S/M.
$dictRec = @('D', '1', '', 'F1', '10L', 'S') -join "`r`n"
Set-Content -LiteralPath (Join-Path $srcDir 'F1') -Value $dictRec -Encoding Ascii

# ***"LIST.INDEX <file>" WITH NO INDEX NAME PROMPTS - "ALL" IS NOT OPTIONAL
# HERE.***  Measured 28 Aug 2026: the bare form reached LISTI:117's "Index
# name:" and ate the OFF that followed it, and the session then sat until the
# timeout.  The prompt block sits BEFORE the "File has no indices" test, so it
# fires whatever the file holds.  DELETEI:101 has the identical block, which is
# why every delete.index below names something.
Show-SD 'entry 15 fixture: the file and its index' @(
    ('create.file ' + $akFile),
    ('COPY FROM ' + $srcFile + ' TO DICT ' + $akFile + ' F1'),
    ('CREATE.INDEX ' + $akFile + ' F1'),
    ('LIST.INDEX ' + $akFile + ' ALL'))
$e15b = $lastSD

# TWO INDEPENDENT INSTRUMENTS, because the fixture failing quietly is what
# would make the rows below meaningless.  2617 is CREATE.INDEX's own success
# wording; 2620 is the file read back afterwards and counted.
Note 'entry 15 fixture: the dictionary record was copied in' $true `
     (Test-Say $e15b '1 record\(s\) copied\.') $true
Note 'entry 15 fixture: CREATE.INDEX said it added the index' $true `
     (Test-Say $e15b 'Added index for F1') $true
Note 'entry 15 fixture: the file reads back with exactly one index' $true `
     (Test-Say $e15b 'Number of indices = 1') $true
if (-not (Test-Say $e15b 'Number of indices = 1')) {
    Write-Output '  The index was not created, so nothing below would be measuring the fold.'
    Write-Verdict 'verify-vocverbs'
    exit 2
}

# A SEPARATE SESSION.  DELETE.INDEX needs exclusive access to the file, and the
# session that just created and listed it is the likeliest thing holding it
# open.  The control runs FIRST: once F1 is deleted the file has no indices and
# DELETEI stops at 2603 before it ever reaches the report.
Show-SD 'entry 15' @(
    ('delete.index ' + $akFile + ' ' + $Prefix + 'nope'),
    ('delete.index ' + $akFile + ' f1'),
    ('LIST.INDEX ' + $akFile + ' ALL'))
$e15c = $lastSD

# CONTROL: a name that really is unknown is reported AS TYPED, not upcased.  The
# fold must correct names that match something, and only those.
Note 'entry 15 control: an unknown name is echoed as typed' $true `
     (Test-Say $e15c ('Unrecognised index name \(' + [regex]::Escape($Prefix + 'nope') + '\)')) $true
Note 'entry 15 control: it was NOT upcased on the way out' $false `
     (Test-Say $e15c ('Unrecognised index name \(' + [regex]::Escape(($Prefix + 'nope').ToUpper()) + '\)')) $true

# DECISIVE: lower case in, the real UPPER-case name back out of 2627.
Note 'entry 15: "delete.index ... f1" deleted index F1' $true `
     (Test-Say $e15c 'Deleted index F1') $true
Note 'entry 15: f1 was NOT reported unrecognised' $false `
     (Test-Say $e15c 'Unrecognised index name \(f1\)') $true
Note 'entry 15: the file has no indices afterwards' $true `
     (Test-Say $e15c 'File has no indices') $true

# ---------------------- 26. DELETE.FILE does not prompt on a lower-case name

Write-Output ''
Write-Output '=== PRE_RELEASE 26: DELETE.FILE NO.QUERY on a lower-case name ============'

# NO.QUERY, NOT FORCE.  See the header: force suppresses both prompts on its own,
# so the force form passes on the defect as readily as on the fix.
Show-SD 'entry 26' @(
    ('create.file ' + $wFile),
    ('delete.file ' + $wFile + ' no.query'),
    'N',
    'N',
    ('.L ' + $wFile))
$e26 = $lastSD

Note 'entry 26 fixture: the file was created' $true `
     (Test-Say $e26 'Created DATA part as') $true

Note 'entry 26: the DATA prompt did NOT fire' $false `
     (Test-Say $e26 'OK to delete DATA portion') $true
Note 'entry 26: the DICT prompt did NOT fire' $false `
     (Test-Say $e26 'OK to delete DICT portion') $true

Note 'entry 26: the DATA portion was deleted' $true `
     (Test-Say $e26 ("DATA portion '" + [regex]::Escape($wFile.ToUpper()) + "' deleted")) $true
Note 'entry 26: the DICT portion was deleted' $true `
     (Test-Say $e26 ("DICT portion '" + [regex]::Escape($wFile.ToUpper() + '.DIC') + "' deleted")) $true
Note 'entry 26: the VOC entry was deleted' $true `
     (Test-Say $e26 ("VOC entry '" + [regex]::Escape($wFile) + "' deleted")) $true

# -------------------------------------------------------------- 9. clean up

Write-Output ''
Write-Output '=== clean up =============================================================='

Show-SD 'clean up' @(
    ('delete.file ' + $akFile + ' no.query'),
    'N',
    'N',
    ('DELETE.FILE ' + $srcFile + ' NO.QUERY'),
    ('DELETE VOC ' + $vocSent),
    ('DELETE VOC ' + $sysPtr))

foreach ($p in $allDirs) {
    if (Test-Path -LiteralPath $p) {
        Write-Output ("  removing " + $p)
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$left = @($allDirs | Where-Object { Test-Path -LiteralPath $_ })
if ($left.Count -gt 0) {
    Write-Output '  NOT FULLY CLEANED UP - these are still on disk:'
    $left | ForEach-Object { Write-Output ('    ' + $_) }
    Write-Output '  Reported, not failed: the fixes above were already measured.'
}

# AND THE CONTROL ON THE CLEAN-UP ITSELF.  sdsys\messages must still be there;
# if this run removed it, that is a far bigger finding than any row above.
Note 'clean-up control: sdsys\messages survived the whole run' $true `
     (Test-Path -LiteralPath $sysFile) $true

# ---------------------------------------------------------------------- report

Write-Output ''
$results | Format-Table -AutoSize -Wrap | Out-String | Write-Output

Write-Verdict 'verify-vocverbs'

if ($fatal) { exit 1 }
exit 0
