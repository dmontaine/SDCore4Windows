# probe-txnlock.ps1 - does a commit that FAILS HALF WAY still hold its record
# locks?  PRE_RELEASE 102, the lock half.
#
# THIS ONE INDUCES THE FAULT, WHICH NOTHING IN THIS FAMILY HAS DONE BEFORE.
# 101 established that a directory-file delete at commit is inducible on
# Windows - "a read-only file, an ACL denial, or a file held open by a scanner
# is enough" - so this holds the victim record's file open with a share mode
# that denies delete, and the remove() inside op_txncmt() then fails for real.
#
# WHAT HAPPENS ON THE FAULT PATH, and why the lock is the question:
#   op_txncmt() saves process.txn_id into commit_txn_id and zeroes txn_id, then
#   the delete fails, k_error(1423) is raised, and K_ERROR DOES NOT RETURN - it
#   longjmps to K_ABORT.  unlock_txn(commit_txn_id) after the loop is skipped,
#   and txn_abort() (which the abort DOES reach) tested only process.txn_id,
#   which is 0.  So nothing released the lock and it was held for the life of
#   the process.
#
# RED/GREEN.  Run it against the INSTALLED binary before the cycle - that is
# still the pre-fix build - and the RU lock must SURVIVE.  Run it after the
# cycle and it must be GONE.  A probe that reports "no lock" against a binary
# that cannot pass is measuring nothing, so -Expect makes the direction
# explicit and the run fails if it gets the other answer.

[CmdletBinding()]
param(
    [ValidateSet('leak','released')]
    [string]$Expect = 'released',   # 'leak' = pre-fix binary, 'released' = post-fix
    [string]$Tag    = 'TXL',
    [int]$Timeout   = 120
)

$ErrorActionPreference = 'Stop'

$sdExe   = 'C:\Program Files\SD\usr\bin\sd.exe'
$acctDir = 'C:\ProgramData\SD\user_accounts\don'
$dirFile = $Tag + 'DIR'
$prog    = $Tag + 'K'
$victim  = 'VICTIM'

$fails = 0
$rows  = @()

function Note {
    param([string]$What, $Expected, $Got)
    $ok = ([string]$Expected -ceq [string]$Got)
    if (-not $ok) { $script:fails++ }
    $script:rows += [pscustomobject]@{ Check=$What; Expected=$Expected; Got=$Got
                                       Result=$(if($ok){'PASS'}else{'FAIL'}) }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
                  $(if($ok){'PASS'}else{'FAIL'}), $What, $Expected, $Got)
}

function Invoke-SDText {
    param([string[]]$Commands, [int]$TimeoutSec = 120)
    # TERM 200,9999 FIRST, ALWAYS.  Omitting it cost this probe a 120-second
    # timeout on "BASIC BP TXLK": the default terminal is 24 lines, the compiler
    # filled a page, and SD sat waiting for a keypress that a pipe can never
    # send.  Every house verifier sets it before doing anything and this did
    # not.  A timed-out session also leaves its user-table slot behind, which
    # is why it matters beyond the lost run.
    $body = "`n" + ((@('TERM 200,9999') + $Commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe,$text) $text | & $exe } -ArgumentList $sdExe,$body
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else { Stop-Job $job; $out = Receive-Job $job; $out += "*** SD DID NOT FINISH IN $TimeoutSec s" }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'),'') -join "`n")
}

function Show-SD {
    param([string]$Label,[string[]]$Commands,[int]$TimeoutSec = 120)
    Write-Output ("  --- SD session: " + $Label + " ---")
    $Commands | ForEach-Object { Write-Output ("    > " + $_) }
    $o = Invoke-SDText -Commands $Commands -TimeoutSec $TimeoutSec
    $o -split "`n" |
        Where-Object { $_ -notmatch 'Ladybridge|free software|WARRANTY|redistribute|CONFIG GPL' -and $_.Trim() -ne '' } |
        ForEach-Object { Write-Output ("    | " + $_) }
    $script:lastSD = $o
}

Write-Output '=== 0. preconditions, printed rather than assumed ==='
Write-Output ("  sd.exe   : " + $sdExe)
if (-not (Test-Path -LiteralPath $sdExe)) { Write-Output '  ABORT: no sd.exe'; exit 2 }
$hash = (Get-FileHash $sdExe -Algorithm SHA256).Hash.Substring(0,16)
Write-Output ("  sha256   : " + $hash)
Write-Output ("  expecting: " + $Expect + "   (leak = pre-fix binary, released = post-fix)")
if (-not (Test-Path -LiteralPath $acctDir)) { Write-Output '  ABORT: no DON account'; exit 2 }

$dirPath = Join-Path $acctDir $dirFile
$bpPath  = Join-Path $acctDir 'bp'
$victimPath = Join-Path $dirPath $victim
foreach ($p in @($dirPath, (Join-Path $bpPath $prog))) {
    if (Test-Path -LiteralPath $p) { Write-Output ("  ABORT: leftover " + $p); exit 2 }
}
if (-not (Test-Path -LiteralPath $bpPath)) { Write-Output '  ABORT: no bp in DON'; exit 2 }

# ------------------------------------------------------------------ fixture
Write-Output ''
Write-Output '=== 1. fixture: a DIRECTORY file with one record to delete ==='
Show-SD 'create the file' @(('CREATE.FILE ' + $dirFile + ' DIRECTORY'))
Note 'the directory file exists' $true (Test-Path -LiteralPath $dirPath)
if ($fails) { Write-Output '  ABORT: fixture'; exit 2 }
Set-Content -LiteralPath $victimPath -Value 'this record is about to be deleted' -Encoding Ascii -NoNewline
Note 'the victim record exists' $true (Test-Path -LiteralPath $victimPath)

# The BASIC program.  bp is a DIRECTORY file, so a record IS a file.
# COMMIT is the statement op_txncmt() implements; BEGIN TRANSACTION opens it.
# THE BLOCK MUST BE CLOSED WITH "END TRANSACTION" AND THE PROGRAM WITH "END".
# Measured, not guessed: COMMIT alone leaves the block open and BCOMP reports
# "Expected TRANSACTION after END"; and with no final END at all THE COMPILER
# HANGS INDEFINITELY rather than reporting anything - 41s to a timeout against
# 0.5s for the same source with one END added.  That cost this probe two runs
# and left orphaned sessions in the user table.  See PRE_RELEASE 114.
$src = @(
    "      OPEN '$dirFile' TO F ELSE STOP",
    "      BEGIN TRANSACTION",
    "         READU R FROM F, '$victim' ELSE R = ''",
    "         DELETE F, '$victim'",
    "         COMMIT",
    "      END TRANSACTION",
    "      CRT 'ZZCOMMITRETURNED'",
    "      END"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $bpPath $prog) -Value $src -Encoding Ascii
Note 'the BASIC source is in bp' $true (Test-Path -LiteralPath (Join-Path $bpPath $prog))

Write-Output ''
Write-Output '=== 2. compile it ==='
Show-SD 'compile' @(('BASIC BP ' + $prog))
Note 'it compiled with no errors' $true `
     ([bool]($lastSD -match '0 error\(s\)|Compilation complete'))
Note 'and no error wording appeared' $false `
     ([bool]($lastSD -match '[1-9][0-9]* error\(s\)|not found|syntax error'))
if ($fails) { Write-Output '  ABORT: the program did not compile.'; exit 2 }

# ------------------------------------------------------ induce the failure
Write-Output ''
Write-Output '=== 3. hold the victim open, denying DELETE, so remove() really fails ==='
$fs = $null
try {
    $fs = [IO.File]::Open($victimPath, [IO.FileMode]::Open,
                          [IO.FileAccess]::Read, [IO.FileShare]::Read)
    Write-Output ('  handle open on ' + $victimPath + ' with FileShare.Read (delete denied)')
} catch {
    Write-Output ('  ABORT: could not open the victim: ' + $_.Exception.Message); exit 2
}

# CONTROL: prove Windows really refuses the delete while the handle is open.
# Without this the whole probe could be measuring a delete that would have
# failed anyway, or one that would have succeeded.
$delBlocked = $false
try { Remove-Item -LiteralPath $victimPath -Force -ErrorAction Stop }
catch { $delBlocked = $true }
Note 'CONTROL: Windows refuses to delete it while held' $true $delBlocked

Write-Output ''
Write-Output '=== 4. run the transaction - the COMMIT must fail ==='
try {
    Show-SD 'begin transaction, delete, commit' @(
        ('RUN BP ' + $prog),
        'WHO',
        'LIST.READU') -TimeoutSec $Timeout
} finally {
    if ($fs) { $fs.Close(); $fs.Dispose(); Write-Output '  handle released' }
}
$out = $lastSD

# SUCCESS/FAILURE ANCHORS.  ZZCOMMITRETURNED prints only if COMMIT came back
# normally, so its ABSENCE is what says the fault fired; and 1423's text is the
# positive marker of the refusal.  Both are checked, because either alone could
# be satisfied by the program never running.
Note 'the program ran (its file was reached)' $false `
     ([bool]($out -match 'Program .* not found|not catalogued'))
Note 'COMMIT did NOT return normally (no ZZCOMMITRETURNED)' $false `
     ([bool]($out -match 'ZZCOMMITRETURNED'))
# THE TOOL'S OWN SUCCESS WORDING, read off a real run.  An earlier draft looked
# for 'Error deleting record|1423|Unable to delete', none of which SD prints;
# the real text of 1423 on this path is "Delete error in transaction commit".
Note 'the commit reported a delete failure (1423 text)' $true `
     ([bool]($out -match 'Delete error in transaction commit'))
Note 'the session survived the abort (WHO answered)' $true `
     ([bool]($out -match '(?m)^\s*\d+\s+DON'))

# ------------------------------------------------------------ the verdict
Write-Output ''
Write-Output '=== 5. LIST.READU - is the record lock still held? ==='
# THE "NOTHING HELD" WORDING IS THE TOOL'S OWN, READ OFF A REAL RUN RATHER THAN
# INVENTED: "There are no active file, read or update locks held by any user".
# An earlier draft guessed 'No records locked', which appears nowhere, so the
# control would have been silently false on every run.
$lockHeld = [bool]($out -match [regex]::Escape($victim))
$noLocks  = [bool]($out -match 'no active file, read or update locks')
Write-Output ("  victim named in LIST.READU output : " + $lockHeld)
Write-Output ("  'nothing held' wording present    : " + $noLocks)
Note 'LIST.READU answered at all (one wording or the other)' $true ($lockHeld -or $noLocks)

# ***THIS IS AN OBSERVATION AND NOT A VERDICT, AND THE REASON IS MEASURED.***
# LIST.READU run in the SAME session after the program has ended CANNOT SEE A
# LOCK EVEN WHEN ONE IS DEFINITELY HELD.  Positive control, 1 Sep 2026, three
# programs in DON: READU then fall off the end; READU then STOP; READU then
# RELEASE.  All three printed their marker, so all three ran - and ALL THREE
# reported "no active file, read or update locks held by any user", including
# the one that never released anything.
#
# So "no lock after the failed commit" says NOTHING about whether the lock
# leaked; it is the null case, and asserting on it would be a green light from
# an instrument that cannot fail.  The direction is printed and deliberately
# not scored.  Observing the leak needs a SECOND, CONCURRENT session looking at
# the first while it is still alive, which this one-session shape cannot do.
Write-Output ''
Write-Output '  *** NOT MEASURED: the lock state is UNKNOWN, not "released". ***'
Write-Output '      LIST.READU cannot see a held lock from the same session after'
Write-Output '      the program ends - proved by a positive control that also came'
Write-Output '      back empty.  PRE_RELEASE 102 records this; it needs two sessions.'
if ($Expect -eq 'leak') {
    Write-Output ('      (-Expect leak was asked for; observed lockHeld = ' + $lockHeld + ', unscored.)')
}

# ---------------------------------------------------------------- clean up
Write-Output ''
Write-Output '=== 6. clean up ==='
Show-SD 'delete the fixture' @(('DELETE.FILE ' + $dirFile + ' no.query'))
foreach ($p in @($dirPath, (Join-Path $bpPath $prog), (Join-Path $bpPath ($prog + '.OUT')))) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
}
$left = @(@($dirPath, (Join-Path $bpPath $prog)) | Where-Object { Test-Path -LiteralPath $_ })
Note 'no fixture left behind' 0 $left.Count
Note 'no stray sd.exe session' 0 @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue).Count

Write-Output ''
$rows | Format-Table -AutoSize | Out-String | Write-Output
if (@($rows).Count -eq 0) { Write-Output 'probe-txnlock: FAILED - no checks ran.'; exit 1 }
if ($fails -gt 0) {
    Write-Output ("probe-txnlock: FAILED - {0} of {1} check(s) failed." -f $fails, @($rows).Count)
    exit 1
}
Write-Output ("probe-txnlock: PASSED - {0} of {0} checks passed, expecting '{1}' on {2}." -f
              @($rows).Count, $Expect, $hash)
exit 0
