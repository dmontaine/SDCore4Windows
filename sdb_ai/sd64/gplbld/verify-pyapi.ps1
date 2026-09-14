# verify-pyapi.ps1 - does objective 2 work END TO END on an installed system?
#
#   powershell -ExecutionPolicy Bypass -File verify-pyapi.ps1
#
# UNELEVATED is fine and is how it was run.  Exit 0 the whole path works,
# 1 a step failed, 2 the fixture could not be built (never a FAIL).
#
# WHAT IT MEASURES.  BASIC -> !PY_* -> SDEXT/SDPYOBJ -> sdpy_client -> the pipe
# -> sdpy.exe -> CPython, and the answer back.  Nothing has ever driven that on
# an install: the C half was proved by driving binaries directly and the BASIC
# half had never been compiled until 12 Sep 2026 22:33.
#
# ***THE DECISIVE ROW ANCHORS ON A STRING ONLY PYTHON CAN PRODUCE.***  The probe
# asks Python to build 'SDPY-' + str(6*7) and reads it back through PY_GETATTR.
# "SDPY-42" cannot appear in a refusal, in an echoed command or in an error
# text - the arithmetic has to have happened in CPython for those bytes to
# exist.  Matching on the object name, or on "0", would have matched the
# failure path too.
#
# The fixture pattern is probe-catprivate.ps1's, including its Invoke-SD.

param(
    # ONLY for a caller that has already run assert-current in this same
    # session.  Leaving it off is the safer default.
    [switch]$SkipAssertCurrent
)

$ErrorActionPreference = 'Stop'

# assert-current, the same rule as every other probe here.  This one measures
# an INSTALL, so a stale tree makes every row below describe a system that no
# longer exists - and this probe's whole subject is a binary that reaches the
# install, so it is exactly the case the guard is for.
if (-not $SkipAssertCurrent) {
    & (Join-Path $PSScriptRoot 'assert-current.ps1')
    if ($LASTEXITCODE -ne 0) {
        Write-Output ''
        Write-Output 'verify-pyapi: refusing - see assert-current above'
        exit 2
    }
}

# ***THIS NEEDS AN ELEVATED SHELL, AND THE COMMENT HERE PREVIOUSLY SAID THE
# OPPOSITE.  CORRECTED 12 Sep 2026, MEASURED.***
#
# It said "UNELEVATED IS CORRECT AND IS NOT AN OVERSIGHT", on the strength of
# one unelevated run that worked.  THAT RUN WORKED BY ACCIDENT.  LOGTO SDSYS
# from an unelevated session reaches elevate('START'), which gates on
# Start-Process -Verb RunAs (CPROC:2687) - a UAC consent.  A session driven
# down a pipe has nobody to consent, so it HANGS at the LOGTO and the transcript
# ends with a prompt whose next command never appears.
#
# The one run that worked had a RESIDENT sd-elevate helper serving its pipe,
# left behind by an elevated cycle minutes earlier; with no helper the same
# command hung twice in a row.  Measured both ways: helper pipe present ->
# worked, no sd-elev-* pipe -> hung.
#
# ***WHAT THAT COSTS IN COVERAGE, SAID OUT LOUD.***  An elevated session sets
# USR_ADMIN, so may_start_helper() returns on its "an administrator always may"
# branch and the OS.USERS field 2 route is NOT exercised here.  This probe
# therefore measures the PLUMBING - BASIC to CPython and back - and not the
# gate.  probe-osex.ps1 asks the gate question separately, and exercising the
# OS.USERS branch properly needs a non-administrator account, which is what
# VerifyInstall1's throwaway test user exists for.

$dataDir = Join-Path $env:ProgramData 'SD'
$sdsys   = Join-Path $dataDir 'sdsys'
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdpyExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sdpy.exe'

# ***THE PROBES GO INTO SDSYS's OWN bp, AND NO FILE IS CREATED - 13 Sep 2026,
# owner: "they should not be stored in VOC".***  This script used to run
# CREATE.FILE PROBEPYBP<hhmmss> DIRECTORY, and BASIC then made its .OUT; both
# are VOC records in SDSYS, and the cleanup removed the DIRECTORIES with
# Remove-Item and never the records.  b141, b143 and b146 left six dead file
# pointers in SDSYS's VOC - PRE_RELEASE 60's defect in verify-catgate, copied.
# A record in bp is a file in a directory file and has no VOC entry, so there is
# nothing left to forget; verify-batchjob has planted into SDSYS's bp the same
# way since 29 Aug 2026.  (It also sidesteps RELEASE_1.1 5 phase (a): CREATE.FILE
# now stores a new id in lower case, which the old stale-fixture sweep's
# upper-case pattern would never have matched.)
$stamp    = Get-Date -Format 'yyyyMMdd-HHmmss'
$ctlFile  = 'bp'
$sysBp    = Join-Path $sdsys 'bp'
$sysBpOut = Join-Path $sdsys 'bp.out'
$ctlName  = 'PYPRB' + $stamp.Substring(9)
$incName  = 'PYINC' + $stamp.Substring(9)
$fixtures = @((Join-Path $sysBp $ctlName), (Join-Path $sysBpOut $ctlName),
              (Join-Path $sysBp $incName), (Join-Path $sysBpOut $incName))

Write-Output '=== inputs (rule 1: what it actually used) ================================'
Write-Output ("  sd.exe       : " + $sdExe)
Write-Output ("  sdpy.exe     : " + $sdpyExe)
Write-Output ("  sdsys        : " + $sdsys)
Write-Output ("  fixture file : " + $ctlFile + "  (" + $sysBp + ", objects in " + $sysBpOut + ")")
Write-Output ("  fixture progs: " + $ctlName + ", " + $incName)

if (-not (Test-Path -LiteralPath $sdExe))   { Write-Output "  no sd.exe at $sdExe";   exit 2 }
if (-not (Test-Path -LiteralPath $sdpyExe)) {
    Write-Output "  NO HELPER at $sdpyExe - this is the RELEASE_1.1 19 defect, not a"
    Write-Output "  Python fault.  Nothing below could pass."
    exit 2
}
Write-Output ("  helper size  : " + (Get-Item -LiteralPath $sdpyExe).Length + " bytes")

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
        $out += "*** Check for a stray sdwind before running a cycle."
    }
    Remove-Job $job -Force
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# --- fixture --------------------------------------------------------------
Write-Output ''
Write-Output '=== fixture ==============================================================='

# ***SWEEP THE WHOLE FAMILY, NOT THIS RUN'S NAME.***  The program names carry a
# timestamp, so a "remove stale" written against this run's names can NEVER
# fire - they do not exist yet by construction.  A run that dies between the
# plant and the cleanup leaves records in bp and bp.out that nothing else
# removes or reports.
$stale = @(foreach ($d in @($sysBp, $sysBpOut)) {
               Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '^(PYPRB|PYINC)[0-9]{6}$' }
           })
if ($stale.Count -gt 0) {
    Write-Output ("  sweeping " + $stale.Count + " leftover probe record(s) from an earlier run:")
    foreach ($f in $stale) {
        Write-Output ("    " + $f.FullName)
        Remove-Item -LiteralPath $f.FullName -Force
    }
}

if (-not (Test-Path -LiteralPath $sysBp -PathType Container)) {
    Write-Output "  no SDSYS bp at $sysBp - the probe has nowhere to go"
    exit 2
}

# The null case for the VOC row at the end: a scan that could not read the VOC
# would find no fixture name and "pass".  So it must first find a record every
# SDSYS VOC has.  Dynamic-file buckets are read as bytes; grep -a over the same
# files is how PRE_RELEASE 60's cleanup was checked.
function Get-VocText {
    $sb = New-Object System.Text.StringBuilder
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $sdsys 'voc') -File -ErrorAction SilentlyContinue)) {
        $null = $sb.Append([System.Text.Encoding]::GetEncoding('iso-8859-1').GetString(
                    [System.IO.File]::ReadAllBytes($f.FullName)))
    }
    return $sb.ToString()
}

# The deffuns are declared here rather than $include SDPYFUNC.H, so that the
# probe tests the CATALOGUED programs and not the include record's resolution
# from a scratch directory.
$src = @(
    '* Created by verify-pyapi.ps1 - safe to delete'
    "deffun PY_INITIALIZE() calling '!PY_INITIALIZE'"
    "deffun PY_IS_INITIALIZED() calling '!PY_IS_INITIALIZED'"
    "deffun PY_RUNSTRING(s) calling '!PY_RUNSTRING'"
    "deffun PY_GETATTR(o) calling '!PY_GETATTR'"
    "deffun PY_OBJTYPE(o) calling '!PY_OBJTYPE'"
    "deffun PY_FINALIZE() calling '!PY_FINALIZE'"
    ''
    '   st = PY_INITIALIZE()'
    "   crt 'PYPRB-INIT=':st"
    '   ii = PY_IS_INITIALIZED()'
    "   crt 'PYPRB-ISINIT=':ii"
    "   rs = PY_RUNSTRING(""zz_probe = 'SDPY-' + str(6*7)"")"
    "   crt 'PYPRB-RUN=':rs"
    "   vv = PY_GETATTR('zz_probe')"
    "   crt 'PYPRB-ATTR=':vv"
    "   ot = PY_OBJTYPE('zz_probe')"
    "   crt 'PYPRB-TYPE=':ot"
    '   fs = PY_FINALIZE()'
    "   crt 'PYPRB-FIN=':fs"
    "   crt 'PYPRB-DONE'"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $sysBp $ctlName) -Value $src -Encoding Ascii

$cmd = "BASIC $ctlFile $ctlName"
Write-Output ("  SD: " + $cmd)
$out = Invoke-SD @($cmd)
Write-Output '  --- BASIC said: ---'
Write-Output $out
if (-not (Test-Path -LiteralPath (Join-Path $sysBpOut $ctlName))) {
    # NAME THE REAL CAUSE RATHER THAN THE SYMPTOM.  "no object produced" sends a
    # reader looking at the compiler when the session never got past the LOGTO,
    # and the two look identical in the exit code.  This diagnosis sat on the
    # CREATE.FILE step until 13 Sep 2026; BASIC is the first SD call now.
    if ($out -match 'did not finish in' -and $out -notmatch 'error\(s\)') {
        Write-Output ''
        Write-Output '  IT HUNG BEFORE THE COMPILER ANSWERED, AND THE USUAL CAUSE IS ELEVATION.'
        Write-Output '  An unelevated LOGTO SDSYS reaches elevate(''START''), which raises a'
        Write-Output '  UAC consent (CPROC:2687).  Nothing driven down a pipe can answer'
        Write-Output '  one, so it waits until the timeout.'
        Write-Output ''
        Write-Output '  RUN THIS FROM AN ELEVATED PowerShell.  See the header for what'
        Write-Output '  that costs: USR_ADMIN takes the gate''s permissive branch, so this'
        Write-Output '  measures the plumbing and not the OS.USERS route.'
    }
    Write-Output '  no object produced - the probe cannot run'
    foreach ($p in $fixtures) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    exit 2
}

# --- the decisive run -----------------------------------------------------
Write-Output ''
Write-Output '=== decisive: BASIC -> !PY_* -> pipe -> CPython -> back ===================='

$cmd = "RUN $ctlFile $ctlName"
Write-Output ("  SD: " + $cmd)
$run = Invoke-SD @($cmd)
Write-Output '  --- SD said, in full (rule: print the raw output every time): ---'
Write-Output $run
Write-Output '  --- end ---'

# --- verdict --------------------------------------------------------------
Write-Output ''
Write-Output '=== rows =================================================================='

$fails = 0
$rows  = 0
function Row([bool]$ok, [string]$label, [string]$detail = '') {
    $script:rows++
    if (-not $ok) { $script:fails++ }
    $t = if ($ok) { 'PASS' } else { 'FAIL' }
    Write-Output ("  [$t] $label" + $(if ($detail) { "  - $detail" } else { '' }))
}

# REFUSE THE NULL CASE.  If the program never ran, every -match below is
# false and a naive reading calls that "no failures".
$ran = $run -match 'PYPRB-DONE'
Row $ran 'the probe program actually ran to the end (PYPRB-DONE)' `
    $(if ($ran) { '' } else { 'NOTHING BELOW IS MEANINGFUL - the program did not finish' })

if (-not $ran) {
    Write-Output ''
    Write-Output "  REFUSING a verdict: $rows row(s), and the decisive one says the"
    Write-Output '  program did not run.  This is not a pass and not a product FAIL.'
    foreach ($p in $fixtures) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    exit 2
}

Row ($run -match 'PYPRB-INIT=0')   'PY_INITIALIZE returned 0'
Row ($run -match 'PYPRB-ISINIT=1') 'PY_IS_INITIALIZED answered 1 after init'
Row ($run -match 'PYPRB-RUN=0')    'PY_RUNSTRING returned 0'

# THE DECISIVE ROW.  "SDPY-42" exists only if CPython evaluated 6*7.
Row ($run -match 'PYPRB-ATTR=SDPY-42') `
    'PY_GETATTR read back SDPY-42 - CPython evaluated 6*7 and the bytes came home'

Row ($run -match 'PYPRB-FIN=0')    'PY_FINALIZE returned 0'

# --- the DOCUMENTED route in ---------------------------------------------
# The program above declares its own deffuns, which tests the CATALOGUED
# programs without depending on how an include resolves.  The changelog tells
# a user to write "$include SDPYFUNC.H", so that claim is driven too: a
# shipped include record that does not resolve is a documentation defect
# nobody would find until a user tried it.
Write-Output ''
Write-Output '=== the documented route: $include SDPYFUNC.H ============================='

$incSrc  = @(
    '* Created by verify-pyapi.ps1 - safe to delete'
    '$include SDPYFUNC.H'
    '   st = PY_INITIALIZE()'
    "   crt 'PYINC-INIT=':st"
    '   fs = PY_FINALIZE()'
    "   crt 'PYINC-DONE'"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $sysBp $incName) -Value $incSrc -Encoding Ascii

$cmd = "BASIC $ctlFile $incName"
Write-Output ("  SD: " + $cmd)
$incOut = Invoke-SD @($cmd)
Write-Output '  --- BASIC said: ---'
Write-Output $incOut
$incBuilt = Test-Path -LiteralPath (Join-Path $sysBpOut $incName)
Row $incBuilt '$include SDPYFUNC.H compiles - the documented include resolves' `
    $(if ($incBuilt) { '' } else { 'no object produced' })

if ($incBuilt) {
    $incRun = Invoke-SD @("RUN $ctlFile $incName")
    Write-Output '  --- SD said: ---'
    Write-Output $incRun
    Row ($incRun -match 'PYINC-INIT=0') `
        'a program using the documented include runs and initialises'
}

# Disqualifiers: the helper-missing code and the not-initialised code must not
# appear anywhere.  -12040 is SD_PyErr_NoHelper.
Row (-not ($run -match '-12040')) 'no -12040 (helper would not start) anywhere in the transcript'
# 12 Sep 26 - RELEASE_1.1 21 split the two permission refusals out of -12040.
# On this step they are disqualifiers rather than expected answers: the suite
# runs elevated, so may_start_helper() takes its USR_ADMIN branch and neither
# can legitimately appear.  Seeing one here would mean the gate had started
# refusing an administrator, which is a product change nobody asked for.
Row (-not ($run -match '-12041')) 'no -12041 (session not permitted to use the OS) anywhere'
Row (-not ($run -match '-12042')) 'no -12042 (OS permission undetermined) anywhere'
Row (-not ($run -match '-12001')) 'no -12001 (interpreter not initialised) anywhere'

# --- cleanup --------------------------------------------------------------
Write-Output ''
Write-Output '=== cleanup ==============================================================='
foreach ($p in $fixtures) {
    if (Test-Path -LiteralPath $p) {
        Remove-Item -LiteralPath $p -Force
        Write-Output ("  removed " + $p)
    }
}
$left = @($fixtures | Where-Object { Test-Path -LiteralPath $_ })
Row ($left.Count -eq 0) 'the fixture left nothing behind in bp or bp.out' ($left -join ', ')

# ***THE OWNER'S RULE AS A ROW: THE RUN PUT NOTHING IN SDSYS's VOC.***  The
# control comes first and must be FOUND - "listf" is in every SDSYS VOC - or a
# scan that read nothing would pass.  Case-insensitive, because the fold means a
# record could be stored in either case.
$voc = Get-VocText
$vocControl = $voc.IndexOf('listf', [System.StringComparison]::OrdinalIgnoreCase) -ge 0
Write-Output ("  VOC scan: " + $voc.Length + " bytes read, control 'listf' found: " + $vocControl)
if (-not $vocControl) {
    Row $false 'SDSYS VOC scan could read the VOC (control listf found)' 'the scan below would measure nothing'
} else {
    $named = @(@($ctlName, $incName) | Where-Object {
                   $voc.IndexOf($_, [System.StringComparison]::OrdinalIgnoreCase) -ge 0 })
    Row ($named.Count -eq 0) 'SDSYS VOC names neither probe program - nothing was stored in VOC' ($named -join ', ')
}

$stray = @(Get-Process -Name 'sdwind', 'sd' -ErrorAction SilentlyContinue)
Write-Output ("  sd/sdwind processes now: " + $stray.Count)

Write-Output ''
if ($fails -gt 0) {
    Write-Output "verify-pyapi: $rows row(s), $fails FAILED"
    exit 1
}
Write-Output "verify-pyapi: $rows of $rows passed - objective 2 works end to end"
exit 0
