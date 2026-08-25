# probe-catprivate.ps1 - PROJECT_STATUS.md 7 step 15's owed measurement:
# prove that CATALOG still writes sdsys\cat with the ACL lock in place.
#
#   powershell -File probe-catprivate.ps1
#
# WHY IT EXISTS, AND WHY IT IS ONE-SHOT.  Step 15 locks sdsys\cat to
# sdusers:(RX), leaving Administrators:(F) and SYSTEM:(F).  The design says
# CATALOG in SDSYS is elevated and therefore still writes through the
# administrator grant, and the row was REASONED rather than measured until
# this ran.  Once it has run green on the current install it will not be run
# again in the ordinary cycle - verify-sysdiracl already carries the ACLs -
# so this is a probe, not a verifier that joins the suite.
#
# THE SUCCESS ANCHOR IS THE WORDING CATALOG PRINTS ON THE POSITIVE PRIVATE
# PATH, "%1 added to private catalogue" (sysmsg 3031, CATALOG:426).  It does
# not appear on any failure path: the two "added to ..." siblings are 3029
# (local) and 3030 (global), the "cannot open" refusal is 3023, the admin
# gate is 2001, and CREATE.FILE / BASIC print their own separate wording if
# the fixtures could not be built.  Matching the argument or the call name
# is what verify-apiidentity paid for on 23 Aug 2026 - the same string
# appeared in the echoed command AND the refusal, and success was reported
# on a step that had been refused.  See CLAUDE.md's rule on anchor wording.
#
# THE FILESYSTEM CHECK RUNS TOO, so a false positive from a decorated error
# also fails.  cat.f is opened by openpath at CATALOG:238 and the record is
# written at CATALOG:424 as "write object.code to cat.f, call.name" - on
# disk that is sdsys\cat\<call.name>.  The name is unique per run (embedded
# timestamp), so a residue from an earlier run cannot make this pass
# trivially and the BEFORE snapshot proves it.
#
# NO $ PREFIX ON THE CALL NAME.  Anything starting with one of "*!_$" sets
# CAT_GLOBAL implicitly (CATALOG:161, :175, :186), which is administrator-
# gated in its own right and writes gcat, not cat.  Bare, mode stays 0 and
# the begin case at CATALOG:338 falls through to "case 1", the private
# branch.  A LOCAL keyword would write @voc instead and print sysmsg 3029,
# neither of which is the thing being measured; do not add it.
#
# NO.QUERY IS PASSED DEFENSIVELY.  check.local and check.global would prompt
# if the call name already existed in the other catalogue - and a piped SD
# session that hits an unexpected prompt hangs the pipe (see verify-fold.ps1
# and Invoke-SD's timeout note).  Our name is unique per run so nothing
# should trigger it, but the option is cheap insurance.
#
# gcat IS BACKED UP FIRST.  HISTORY 17 Aug 2026 records that a bad catalogue
# entry can lock a machine out of SD, because CPROC:315 calls $LOGIN out of
# gcat for every session.  This probe does not write gcat (no $ prefix), so
# the risk is theoretical rather than acute - but the recipe in
# PROJECT_STATUS.md 7 step 15 says to back it up and there is no reason to
# skip it.  The copy goes under %LOCALAPPDATA%\SD-verify, alongside the log.
#
# DRIVING SD FROM POWERSHELL: same two traps as verify-catgate.ps1's
# Invoke-SD - input must be PIPED (not redirected), and the pipe prepends a
# BOM which a leading blank line absorbs.  The Invoke-SD below is copied
# from verify-catgate.ps1 verbatim so the pipe shape does not drift.
#
# Exit 0 CATALOG wrote sdsys\cat, 1 it did not, 2 the probe could not run.

param(
    [switch]$SkipAssertCurrent
)

$ErrorActionPreference = 'Stop'

# Log alongside verify-catgate's, for the same reason: cycle.ps1 deletes
# C:\ProgramData\SD, and this probe wants a before/after transcript that
# survives a subsequent cycle.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$logPath = Join-Path $logDir ('probe-catprivate-' + $stamp + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

$dataDir = Join-Path $env:ProgramData 'SD'
$sdsys   = Join-Path $dataDir 'sdsys'
$cat     = Join-Path $sdsys 'cat'
$gcat    = Join-Path $sdsys 'gcat'
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

# Fixture names are per-run.  Same reasoning as verify-catgate: on the
# 11:42:41 run there, a fixed name reused after DELETE.FILE produced no
# object file and both controls failed with it.  ctlName does NOT start with
# any of "*!_$", so CATALOG stays in mode 0 (private) - see the header.
$ctlFile = 'PROBECATBP' + $stamp.Substring(9)     # PROBECATBP<HHMMSS>
$ctlDir  = Join-Path $sdsys $ctlFile
$ctlName = 'CATPRV' + $stamp.Substring(9)          # CATPRV<HHMMSS>

Write-Output ''
Write-Output '=== inputs, echoed before anything runs ==================================='
Write-Output ("  sd.exe       : " + $sdExe)
Write-Output ("  sdsys        : " + $sdsys)
Write-Output ("  cat          : " + $cat)
Write-Output ("  gcat         : " + $gcat)
Write-Output ("  ctlFile      : " + $ctlFile)
Write-Output ("  ctlName      : " + $ctlName)
Write-Output ("  writes to    : " + (Join-Path $cat $ctlName))

# --- guards ---------------------------------------------------------------
Write-Output ''
Write-Output '=== guards ================================================================'

if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output ("  no sd.exe at " + $sdExe + " - install first")
    exit 2
}
if (-not (Test-Path -LiteralPath $cat)) {
    Write-Output ("  no " + $cat + " - the tree is not one this probe can measure")
    exit 2
}
if (-not (Test-Path -LiteralPath $gcat)) {
    Write-Output ("  no " + $gcat + " - the tree is not one this probe can measure")
    exit 2
}

# assert-current, same rule as every other verifier here - a probe that runs
# against a stale tree can silently measure yesterday's ACLs.  -SkipAssertCurrent
# exists ONLY for the case where the caller has already run it in the same
# elevated session; leaving it off is the safer default.
if (-not $SkipAssertCurrent) {
    & (Join-Path $PSScriptRoot 'assert-current.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Output ''
        Write-Output 'probe-catprivate: refusing - see assert-current above'
        exit 2
    }
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'probe-catprivate: this needs an ELEVATED PowerShell - LOGTO SDSYS is administrator-only.'
    exit 2
}

# --- gcat backup ----------------------------------------------------------
# Per step 15's recipe.  Copy-Item -Recurse mirrors the directory; if the
# probe ever writes gcat by mistake (a wrong prefix, a typo in ctlName), the
# copy is the way back.  Not deleted on success: it is small, and its
# absence would be the first thing missed after a bad run.
$gcatBackup = Join-Path $logDir ('gcat-backup-' + $stamp)
Write-Output ("  backing gcat up to " + $gcatBackup)
Copy-Item -LiteralPath $gcat -Destination $gcatBackup -Recurse -Force

# --- Invoke-SD, copied from verify-catgate.ps1 unchanged ------------------
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 45) {
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
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

# --- fixtures: CREATE.FILE, source, BASIC ---------------------------------
Write-Output ''
Write-Output '=== fixtures (SDSYS scratch file and object code) =========================='

# EVERY FIXTURE STEP IS CHECKED AND SAYS WHAT SD SAID - verify-catgate's
# rule after two runs where a quiet fixture failure was reported as a
# CATALOG failure.  A fixture that cannot be built is "could not be run"
# (exit 2), never a FAIL.

# Belt-and-braces: if a previous crashed run left the scratch file behind,
# clear it out first.  Not through SD - the file may be inconsistent, and
# these are directories on disk that Remove-Item can delete outright.
foreach ($p in @($ctlDir, ($ctlDir + '.DIC'), ($ctlDir + '.OUT'))) {
    if (Test-Path -LiteralPath $p) {
        Write-Output ("  removing stale " + $p)
        Remove-Item -LiteralPath $p -Recurse -Force
    }
}

$cmd = "CREATE.FILE $ctlFile DIRECTORY"
Write-Output ("  SD: " + $cmd)
$out = Invoke-SD @($cmd)
if (($out -notmatch 'Created DATA part as') -or -not (Test-Path -LiteralPath $ctlDir)) {
    Write-Output '  --- SD said: ---'; Write-Output $out
    Write-Output ("  CREATE.FILE $ctlFile did not make the file - cannot build the fixture")
    exit 2
}

$src = @(
    '* Created by probe-catprivate.ps1 - safe to delete'
    "   crt 'CATPRV OK'"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $ctlDir $ctlName) -Value $src -Encoding Ascii

$cmd = "BASIC $ctlFile $ctlName"
Write-Output ("  SD: " + $cmd)
$out = Invoke-SD @($cmd)
if (-not (Test-Path -LiteralPath (Join-Path ($ctlDir + '.OUT') $ctlName))) {
    Write-Output '  --- SD said: ---'; Write-Output $out
    Write-Output ("  BASIC $ctlFile $ctlName produced no object - cannot build the fixture")
    exit 2
}

# --- the decisive step ----------------------------------------------------
Write-Output ''
Write-Output '=== decisive: CATALOG writes sdsys\cat under the ACL lock =================='

# BEFORE snapshot - "cat had this many records before, has one more after"
# is the strongest single check, because it also refuses the null case
# where a leftover file from an earlier run made the AFTER path look
# present.  Files, not directories: SD file records are one file each on
# disk under the SD data directory.
$targetFile = Join-Path $cat $ctlName
$before = @(Get-ChildItem -LiteralPath $cat -File -Force -ErrorAction SilentlyContinue).Count
$beforePresent = Test-Path -LiteralPath $targetFile
Write-Output ("  BEFORE: cat holds {0} files; {1} {2}" -f
              $before,
              $ctlName,
              $(if ($beforePresent) { 'already present (unexpected)' } else { 'absent' }))
if ($beforePresent) {
    Write-Output ("  refusing: " + $targetFile + " is present before CATALOG runs.")
    Write-Output ('  the after check would be trivially satisfied.')
    exit 2
}

# NO.QUERY defensively - see the header.  No $ prefix on ctlName, or
# CATALOG:161 would flip mode to CAT_GLOBAL and refuse under sysmsg 2001.
$cmd = "CATALOG $ctlFile $ctlName NO.QUERY"
Write-Output ("  SD: " + $cmd)
$out = Invoke-SD @($cmd)

# ALWAYS print what SD said for the decisive step - CLAUDE.md's rule after
# verify-apiidentity's Step 3 was reported as a pass on a refusal.  A print
# gated on the verdict is exactly the shape that hid it.
Write-Output '  --- SD said: ---'
Write-Output $out
Write-Output '  --- end SD ---'

# ANCHOR: sysmsg 3031's positive wording.  Substituting %1 gives "<name>
# added to private catalogue".  Match on the fixed tail to sidestep any
# case-folding of the call name.
$anchor = ($out -match 'added to private catalogue')

# DISQUALIFIERS: any of these appearing rules the run out, even if the
# anchor also matched (which should be impossible on the positive path).
$disqualifiers = @(
    'Cannot open private catalogue directory',
    'Cannot open global catalogue directory',
    'Command requires administrator privileges',
    'Permission denied',
    'Access is denied',
    'not found',
    'not in your VOC',
    'Illegal call name',
    'Incompatible cataloguing modes',
    'Unexpected token'
)
$hit = @()
foreach ($d in $disqualifiers) {
    if ($out -match [regex]::Escape($d)) { $hit += $d }
}

$after = @(Get-ChildItem -LiteralPath $cat -File -Force -ErrorAction SilentlyContinue).Count
$afterPresent = Test-Path -LiteralPath $targetFile
Write-Output ("  AFTER : cat holds {0} files; {1} {2}" -f
              $after, $ctlName,
              $(if ($afterPresent) { 'present' } else { 'absent' }))

# Decisive checks, three independent ones.  All three must agree; the
# verdict says which one refused if any did.
$countGrew   = ($after -eq ($before + 1))
$fileWritten = $afterPresent
$saidSuccess = ($anchor -and $hit.Count -eq 0)

Write-Output ''
Write-Output ('  countGrew    : ' + $countGrew   + " (before=$before after=$after)")
Write-Output ('  fileWritten  : ' + $fileWritten + " ($targetFile)")
Write-Output ('  saidSuccess  : ' + $saidSuccess +
              $(if ($hit.Count) { ' (disqualified by: ' + ($hit -join ', ') + ')' } else { '' }))

$pass = $countGrew -and $fileWritten -and $saidSuccess

# --- cleanup --------------------------------------------------------------
Write-Output ''
Write-Output '=== cleanup ==============================================================='

# DELETE.FILE FORCE (not a piped "Y") - DELETEF prompts separately for DATA
# and DICT when the stored path differs from the default, and only when it
# differs.  Our fixture names are upper case so today neither prompt fires;
# FORCE is the guarantee, and it is what verify-catgate learned to use.
$cmd = "DELETE.FILE $ctlFile FORCE"
Write-Output ("  SD: " + $cmd)
$out = Invoke-SD @($cmd)

# Belt-and-braces on disk too, since DELETE.FILE FORCE was seen leaving
# .OUT behind on at least one path in verify-catgate.  These are ours; the
# scratch name will never collide with anything shipped.
foreach ($p in @($ctlDir, ($ctlDir + '.DIC'), ($ctlDir + '.OUT'), $targetFile)) {
    if (Test-Path -LiteralPath $p) {
        Write-Output ('  removing ' + $p)
        Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --- verdict --------------------------------------------------------------
# LAST, and AFTER the cleanup prose - a tail of the log is how these are
# read (verify-createaccount and verify-sshonly on 24 Aug 2026 fixed the
# same trap: without a trailing verdict line, the prose was what a tail
# showed and a decisive failure hid).  Null case is refused out loud:
# if no decisive check ran (say the fixture step exited earlier), the
# script exited before this point and the verdict never printed.
Write-Output ''
if ($pass) {
    Write-Output ("probe-catprivate: PASS - CATALOG wrote " + $targetFile +
                  " under the sdsys\cat ACL lock. 3/3 checks agreed.")
    exit 0
} else {
    Write-Output ("probe-catprivate: FAIL - one or more decisive checks refused. " +
                  "countGrew=$countGrew fileWritten=$fileWritten saidSuccess=$saidSuccess")
    exit 1
}
