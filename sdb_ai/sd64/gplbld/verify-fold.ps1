# verify-fold.ps1 - prove the name fold is "as typed, then lower, then upper",
# and that nothing that worked before stopped working.  PROJECT_STATUS.md 5.12.
#
#   powershell -File verify-fold.ps1            create, check, clean up
#   powershell -File verify-fold.ps1 -Keep      leave the two files behind
#   powershell -File verify-fold.ps1 -Cleanup   remove ones left by -Keep
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# -Cleanup EXISTS BECAUSE -Keep WITHOUT IT IS A TRAP.  The first version had no
# such switch, so the only way to clear what -Keep left was to run the test
# again - which refused, correctly, with "DATA part of file already exists" and
# left the files exactly where they were.  Same shape as verify-catgate.ps1's.
#
# WHAT THE DEFECT WAS.  CREATE.FILE writes the VOC entry under the name AS TYPED
# and upper-cases the name on disk (UPSTREAM_FIXES.md 6), so "CREATE.FILE testlc"
# registers "testlc", reports "Created DATA part as TESTLC", and every lookup
# then tried "TESTLC" and, failing that, upcase("TESTLC") - the same string
# twice.  COUNT TESTLC answered "File not found" for a file the same command had
# just said it created.  The fold now tries lower case in between.
#
# THE CONTROL IS THE SECOND FILE.  A fold that resolved everything to lower case
# would pass every check on the first file and break every existing system, so
# an upper-case file is created too and must still answer to both cases.
#
# WHY COUNT AND NOT SOMETHING SMALLER.  It goes through the parser's VOC lookup
# (PARSER:151) and then opens the file, which is the pair of sites this change
# exists for.  "File not found" and "0 record(s) counted" are unambiguous.
#
# SECTION 4 IS A SECOND LOOKUP, ADDED 18 Aug 2026, AND COUNT CANNOT REACH IT.
# The 74 folded sites all try the name in three cases themselves and hand each
# one to _VOC_REF, which matched EXACTLY and had no fold of its own - it was not
# among the 36 files the fold commit changed.  So every verb passed while every
# hard-coded open "$SAVEDLISTS" in GPL.BP would have broken the moment a VOC id
# was renamed.  Only a BASIC program with a literal in it can show the
# difference, which is why section 4 compiles one.
#
# DRIVING SD FROM POWERSHELL: input must be PIPED, not redirected, and the pipe
# prepends a BOM to the first line, so a blank sacrificial line absorbs it.
# PROJECT_STATUS.md section 6, and verify-catgate.ps1's header for the prompt
# trap that ended a run dead - DELETE.FILE below is answered explicitly.

param(
    [string]$Tag = 'fold1',
    [switch]$Keep,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-fold-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys = Join-Path $env:ProgramData 'SD\sdsys'

# Per-run names, for the reason verify-catgate.ps1 records: reusing a name an
# earlier run created and deleted is a variable this test does not need.
$lc = 'zzlc' + $Tag        # created in lower case
$uc = ('zzuc' + $Tag).ToUpper()

# Fixed, not per-run like $lc/$uc: it is a program, not a file, so a leftover
# from an earlier run is overwritten rather than refused.
$probeName = 'ZZFOLDOPEN'

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

# BOUNDED, BECAUSE A TEST HARNESS THAT CAN HANG IS A BAD HARNESS.  SD prompts
# from places a script cannot predict - CATALOG's "also in private catalogue.
# Remove?", DELETEF's per-part confirmations, and DELETEF:152's "Use file 'xx'?"
# which FORCE does NOT suppress - and every one of them sits in an unbounded
# "until yn = 'Y' or 'N'" loop.  Piped input runs out, the loop keeps reading,
# and the window is dead with no output at all, because this function only
# returns when SD exits.  Three runs were lost that way on 18 Aug 2026.
#
# The job is killed at the timeout and WHATEVER SD PRINTED IS RETURNED, so the
# prompt that caused it is visible instead of being trapped in a hung pipe.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 45) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** The last line above is the prompt that stopped it."
        $out += "*** AND IT LEFT DEBRIS: killing the job kills the session without"
        $out += "*** letting it deregister, so its user-table slot and any record"
        $out += "*** locks it held stay behind.  A later DELETE.FILE on the same"
        $out += "*** name then blocks SILENTLY, and cycle.ps1 will refuse to start"
        $out += "*** with 'SD is still running: sdwind(N)' because sdwind will not"
        $out += "*** shut down while it thinks a session is attached.  Both were"
        $out += "*** seen on 18 Aug 2026.  Stop-Process the sdwind PID it names."
    }
    Remove-Job $job -Force
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

# "0 record(s) counted" is success; "File not found" is the defect.  Both are
# checked rather than just the absence of the error, so a COUNT that failed some
# other way cannot read as a pass.
function Test-Count($name) {
    $out = Invoke-SD @("COUNT $name")
    if ($out -match 'record\(s\) counted') { return 'counted' }
    if ($out -match 'not found')           { return 'not found' }
    return 'unclear'
}

# FORCE, NOT AN ANSWER PIPED AFTER IT.  DELETEF prompts SEPARATELY for the DATA
# and DICT parts (DELETEF:222, :296), each in an unbounded
# "loop ... until yn = 'Y' or 'N' repeat", and each prompt appears only when the
# stored path differs from the default name.  For zzlcfold1 it does differ -
# CREATE.FILE upper-cases the name on disk while the VOC id keeps the case typed
# (UPSTREAM_FIXES.md 6), which is the very defect this script tests around.  So
# a single "Y" answered the DATA prompt, "OFF" fell into the DICT loop, was
# neither Y nor N, and the pipe hung on the 16:35:38 run.  FORCE skips both
# (DELETEF:220, :294) and needs no input at all.
function Remove-Made {
    foreach ($n in @($lc, $uc)) {
        $out = Invoke-SD @("DELETE.FILE $n FORCE")
        if ($out -match 'waiting for input') {
            Write-Output ("  SD would not delete " + $n + " unattended:")
            Write-Output $out
            Write-Output '  falling back to removing the directories only - the VOC entry stays'
        }
    }
    foreach ($n in @($lc, $lc.ToUpper(), $uc, $uc.ToLower())) {
        foreach ($sfx in @('', '.DIC')) {
            $p = Join-Path $sdsys ($n + $sfx)
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
    }
    # Section 4's probe: the source record in BP and the object in BP.OUT.  Both
    # are plain files - BP and BP.OUT are directory files.
    foreach ($p in @((Join-Path (Join-Path $sdsys 'BP') $probeName),
                     (Join-Path (Join-Path $sdsys 'BP.OUT') $probeName))) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue }
    }
}

# BEFORE THE assert-current GATE.  Clearing up after an earlier run must not
# depend on the install still being current - the usual reason the files are in
# the way is that a cycle has just replaced the tree around them.
if ($Cleanup) {
    # ELEVATION IS CHECKED HERE TOO, not only on the test path below.  Remove-Made
    # deletes through SD (DELETE.FILE, so the VOC entry goes with the directory)
    # and that needs LOGTO SDSYS.  Unelevated it would fall through to the
    # Remove-Item sweep and leave SDSYS's VOC naming files that are not there -
    # a half-clean that looks like a clean.
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
            ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output 'verify-fold: -Cleanup needs an ELEVATED PowerShell - it deletes through SD.'
        exit 2
    }
    Write-Output ("removing " + $lc + " and " + $uc)
    Remove-Made
    exit 0
}

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-fold: refusing - see above'
    exit 2
}

if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-fold: this needs an ELEVATED PowerShell - it works in SDSYS.'
    exit 2
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 1. A file created with a LOWER case name ==============================='

$out = Invoke-SD @("CREATE.FILE $lc")
if ($out -notmatch 'Created DATA part as') {
    Write-Output '  --- SD said: ---'; Write-Output $out
    Write-Output "  CREATE.FILE $lc did not report making a file"
    exit 2
}
Write-Output ("  created " + $lc)

# As typed: this worked before the change and must still work.
Note "COUNT $lc (as typed)"           'counted' (Test-Count $lc)
# THE DEFECT: the name CREATE.FILE reported back.  Was 'not found'.
Note "COUNT $($lc.ToUpper()) (upper)" 'counted' (Test-Count $lc.ToUpper())

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 2. THE CONTROL: an UPPER case file still answers to both =============='

$out = Invoke-SD @("CREATE.FILE $uc")
if ($out -notmatch 'Created DATA part as') {
    Write-Output '  --- SD said: ---'; Write-Output $out
    Write-Output "  CREATE.FILE $uc did not report making a file"
    exit 2
}
Write-Output ("  created " + $uc)

Note "COUNT $uc (as typed)"           'counted' (Test-Count $uc)
Note "COUNT $($uc.ToLower()) (lower)" 'counted' (Test-Count $uc.ToLower())

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 3. A name that is in no case at all is still refused =================='

# Without this the suite would pass on a fold that answered "counted" to
# everything, which is the failure mode that matters most here.
Note 'COUNT zznosuchfile' 'not found' (Test-Count 'zznosuchfile')

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== 4. THE BASIC "OPEN" STATEMENT, which is a different lookup ============'
Write-Output '  COUNT above goes through the parser.  OPEN goes through _VOC_REF, which'
Write-Output '  the 74-site fold never touched.  MEASURED on the 18:54:10 install, before'
Write-Output '  the change: A and D were FAIL, while COUNT found both files.'

# BP is a directory file, so a record is just a file on disk.  That is what makes
# this cheap - no editor driven down a pipe, and section 7 step 8 records the
# same trick.  LF endings and no BOM, like every other record in GPL.BP.
$probeSrc = @"
* $probeName - written by verify-fold.ps1.  Safe to delete.
   open '$($lc.ToUpper())' to f1 then
      print 'A=OK'
   end else
      print 'A=FAIL'
   end
   open '$lc' to f2 then
      print 'B=OK'
   end else
      print 'B=FAIL'
   end
   open '$uc' to f3 then
      print 'C=OK'
   end else
      print 'C=FAIL'
   end
   open '$($uc.ToLower())' to f4 then
      print 'D=OK'
   end else
      print 'D=FAIL'
   end
   open 'zznosuchfileatall' to f5 then
      print 'E=OK'
   end else
      print 'E=FAIL'
   end
end
"@
[IO.File]::WriteAllText((Join-Path (Join-Path $sdsys 'BP') $probeName),
                        ($probeSrc -replace "`r`n", "`n"),
                        (New-Object Text.UTF8Encoding $false))

function Get-Probe($out, $tag) {
    if ($out -match ('(?m)^' + $tag + '=(OK|FAIL)\s*$')) { return $matches[1] }
    return 'unclear'
}

$run = Invoke-SD @("BASIC BP $probeName", "RUN BP $probeName")
if ($run -notmatch '0 error\(s\)') {
    Write-Output '  --- SD said: ---'
    Write-Output $run
    Write-Output "  $probeName did not compile - section 4 could not be read"
    $failed = $true
} else {
    # A and D are the change.  B and C are the regression guard: they worked
    # before and an exact-match read is still what serves them.
    Note 'OPEN a lower-case id typed UPPER' 'OK'   (Get-Probe $run 'A')
    Note 'OPEN a lower-case id as typed'    'OK'   (Get-Probe $run 'B')
    Note 'OPEN an upper-case id as typed'   'OK'   (Get-Probe $run 'C')
    Note 'OPEN an upper-case id typed LOWER' 'OK'  (Get-Probe $run 'D')
    # Without this the section would pass on a fold that opened anything at all.
    Note 'OPEN a name in no case at all'    'FAIL' (Get-Probe $run 'E')
    Write-Output '  --- RUN said: ---'
    Write-Output $run
}

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== Summary =============================================================='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
Write-Output ("  {0} of {1} checks passed" -f $passed, $results.Count)

if (-not $Keep) {
    Write-Output ''
    Write-Output 'Cleaning up (use -Keep to leave the files for inspection)'
    Remove-Made
} else {
    Write-Output ''
    Write-Output ("Left behind: " + $lc + " and " + $uc + " in SDSYS")
}

try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 } else { exit 0 }
