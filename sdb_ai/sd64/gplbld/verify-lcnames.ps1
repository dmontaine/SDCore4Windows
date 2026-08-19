# verify-lcnames.ps1 - the first of section 5.12 (a)'s renames: the per-account
# file names on disk are lower case.  PROJECT_STATUS.md 5.12, section 7 step 8.
#
#   powershell -File verify-lcnames.ps1            check, clean up after itself
#   powershell -File verify-lcnames.ps1 -Keep      leave the two probe records
#   powershell -File verify-lcnames.ps1 -Cleanup   remove ones left by -Keep
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# WHAT CHANGED.  CREATEA's create.dir.file is given a VOC id (fn) and a name on
# disk (os.name); the second is now lower case, so a new account holds $hold,
# $hold.dic, $svlists and bp instead of $HOLD, $HOLD.DIC, $SVLISTS and BP.  The
# VOC ids are untouched - that is the other half of 5.12 and a later step.
# to_file.c's three hold-file paths moved with it.
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
# THE CONTROLS ARE THE POINT, and there are two.  The account's VOC is still
# upper case on disk, deliberately - it is a later rename - so a change that
# lower-cased everything would fail here rather than pass.  And cat has been
# lower case since before the port, so it shows the listing can report either.
#
# COPYP RIDES ALONG because it shipped in the same cycle.  See section 5.
#
# DRIVING SD FROM POWERSHELL: input must be PIPED, not redirected, and the pipe
# prepends a BOM to the first line, so a blank sacrificial line absorbs it.
# PROJECT_STATUS.md section 6.  Every call is bounded - section 8 records three
# runs lost to an unbounded prompt loop on 18 Aug 2026.

param(
    [string]$Account = $env:USERNAME,
    [string]$Tag     = 'lc1',
    [switch]$Keep,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

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
    $body = "`n" + ((@('TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
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

function Remove-Probes {
    foreach ($p in @((Join-Path $acctDir ('$hold\'    + $holdRec)),
                     (Join-Path $acctDir ('$svlists\' + $listName)))) {
        if (Test-Path -LiteralPath $p) {
            Remove-Item -LiteralPath $p -Force
            Write-Output ("  removed " + $p)
        }
    }
}

if ($Cleanup) {
    Write-Output ''
    Write-Output '=== cleanup only ========================================================'
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

    foreach ($n in @('$hold', '$hold.dic', '$svlists', 'bp')) {
        Note ($n + ' present, exact case') 1 @($onDisk | Where-Object { $_ -ceq $n }).Count
    }
    # The old spellings must be absent, which Test-Path could never have shown.
    foreach ($n in @('$HOLD', '$HOLD.DIC', '$SVLISTS', 'BP')) {
        Note ($n + ' absent') 0 @($onDisk | Where-Object { $_ -ceq $n }).Count
    }
    # THE CONTROLS.  VOC is a later rename and must still be upper case; cat was
    # lower case before this change and shows the listing reports both.
    Note 'control: VOC still upper case' 1 @($onDisk | Where-Object { $_ -ceq 'VOC' }).Count
    Note 'control: cat still lower case' 1 @($onDisk | Where-Object { $_ -ceq 'cat' }).Count

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 3. the VOC records name the lower-case paths ========================='
    Write-Output '  The VOC id is unchanged; fields 2 and 3 hold the path, and that is what'
    Write-Output '  LISTF and CT VOC show a user.'

    $ct = Invoke-SD @('CT VOC $HOLD', 'CT VOC $SAVEDLISTS', 'CT VOC BP')
    Note 'CT VOC $HOLD names $hold'          $true ($ct -cmatch '(?m)^\s*2:\s*\$hold\s*$')
    Note 'CT VOC $HOLD names $hold.dic'      $true ($ct -cmatch '(?m)^\s*3:\s*\$hold\.dic\s*$')
    Note 'CT VOC $SAVEDLISTS names $svlists' $true ($ct -cmatch '(?m)^\s*2:\s*\$svlists\s*$')
    Note 'CT VOC BP names bp'                $true ($ct -cmatch '(?m)^\s*2:\s*bp\s*$')
    Write-Output '  --- CT VOC said: ---'
    Write-Output $ct

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

    # $hold, reached the way a print goes there rather than through the VOC:
    # SETPTR mode 3 with AS <name> makes SD build the path itself - SETPTR:329
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
    Write-Output '=== 5. COPYP, which rides this cycle and is unrelated ===================='
    Write-Output '  VOC_TEMPLATE/COPYP field 1 held the description where the type code'
    Write-Output '  belongs.  IT WAS NOT BROKEN BY IT - measured on the pre-change 18:54:10'
    Write-Output '  install, COPYP already answered "File name required", because CPROC:1436'
    Write-Output '  tests only voc.entry.type[1,1] and "Verb..." starts with V.  So the'
    Write-Output '  behaviour checks below are CONTROLS against regression, not a repair.'
    Write-Output '  LOGTO SDSYS, because VOC_TEMPLATE becomes SDSYS s own VOC.'

    $ctc = Invoke-SD @('LOGTO SDSYS', 'CT VOC COPYP')
    Note 'CT VOC COPYP shows a bare V type code' $true ($ctc -match '(?m)^\s*1:\s*V\s*$')
    Note 'and no longer the description text'    $false ($ctc -match 'Verb for Pick style COPY')
    Write-Output '  --- CT VOC COPYP said: ---'
    Write-Output $ctc

    # Relative, not against a hardcoded message: COPYP must not answer the way an
    # unknown verb does, and must answer the way it did before the change.
    $unknown = Invoke-SD @('LOGTO SDSYS', 'ZZNOSUCHVERB')
    $copyp   = Invoke-SD @('LOGTO SDSYS', 'COPYP')
    Note 'COPYP answers differently from an unknown verb' $false ($copyp -eq $unknown)
    Note 'COPYP still reaches $COPYP itself' $true ($copyp -match 'File name required')

    # -----------------------------------------------------------------------
    Write-Output ''
    Write-Output '=== 6. WHY COPYP WAS NEVER BROKEN, measured rather than argued ==========='
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
        Note 'section 6 could run (bp directory found)' $true $false
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
