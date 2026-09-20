# probe-osex.ps1 - THE DISCRIMINATOR for verify-pyapi's -12040.
#
# -12040 has three causes and the reason is never surfaced (sdpy_session_error
# has no caller).  So ask the SAME QUESTION THE PYTHON GATE ASKS, by the same
# route: os_permitted() via OS.USERS field 2, which is what an "os.execute"
# from a compiled, NON-internal program goes through.
#
#   os.execute works  -> the session IS permitted -> the Python gate should
#                        have passed, and -12040 is a defect.
#   os.execute refused-> the session is NOT permitted -> -12040 is the gate
#                        working as designed, and the probe needs a permitted
#                        session.
#
# ***CONVERTED TO THE SDSYS SEAT 20 Sep 2026 - IT NOW RUNS ELEVATED, AS SDSYS.***  It used to be
# "unelevated, on purpose: that is the session verify-pyapi used", and the seat cannot ask that
# question: see the note above Invoke-SD below.

$ErrorActionPreference = 'Stop'

$sdsys   = Join-Path (Join-Path $env:ProgramData 'SD') 'sdsys'
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$ctlFile = 'PROBEOSXBP' + $stamp.Substring(9)
$ctlDir  = Join-Path $sdsys $ctlFile
$ctlName = 'OSXPRB' + $stamp.Substring(9)

Write-Output ("  sd.exe    : " + $sdExe)
Write-Output ("  fixture   : " + $ctlFile + " / " + $ctlName)
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
Write-Output ("  running as: " + $id.Name)
Write-Output ("  elevated  : " + ([Security.Principal.WindowsPrincipal]$id).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator))

# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT (sdsys-seat.ps1), CONVERTED ON THE OWNER'S RULING
# ("convert").  THE "LOGTO SDSYS" PREFIX THIS USED TO SEND IS REFUSED (10002) FROM ANY SESSION
# THAT DID NOT START AS THE OS SDSYS ACCOUNT with an elevated, interactive token, so the
# commands go to a task inside SDSYS's own live session.
#
# ***WHAT THIS CHANGES ABOUT THE QUESTION, SAID PLAINLY.***  The header asks whether an UNELEVATED
# session is permitted to reach the OS from a non-internal program, and says "unelevated, on
# purpose: that is the session verify-pyapi used".  The seat's token is ELEVATED (that is what
# reaches SDSYS at all), so USR_ADMIN is set and os_permitted() takes its administrator branch:
# this now answers the ELEVATED-SDSYS case only, and cannot ask the unelevated one.  That
# question is what VerifyInstall1's throwaway test user exists for.  The probe still works and
# still discriminates "the plumbing runs" from "the gate refused", which is what -12040's three
# causes needed separated.  SDSYS must be signed in, and this needs an ELEVATED PowerShell.
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 180) {
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec)
}
Assert-SdSeat -Label 'probe-osex'

foreach ($p in @($ctlDir, ($ctlDir + '.DIC'), ($ctlDir + '.OUT'))) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}

$out = Invoke-SD @("CREATE.FILE $ctlFile DIRECTORY")
if ($out -notmatch 'Created DATA part as') {
    Write-Output $out; Write-Output '  fixture failed'; exit 2
}

# NOT $internal - that is the whole point.  An $internal program short-circuits
# os_permitted() and would pass for every user, measuring nothing.
$src = @(
    '* Created by probe-osex.ps1 - safe to delete'
    "   cap = ''"
    "   os.execute 'cmd /c echo OSEX-RAN' capturing cap"
    "   crt 'OSXPRB-CAP=':cap"
    "   crt 'OSXPRB-DONE'"
) -join "`r`n"
Set-Content -LiteralPath (Join-Path $ctlDir $ctlName) -Value $src -Encoding Ascii

$out = Invoke-SD @("BASIC $ctlFile $ctlName")
if (-not (Test-Path -LiteralPath (Join-Path ($ctlDir + '.OUT') $ctlName))) {
    Write-Output $out; Write-Output '  no object'; exit 2
}

$run = Invoke-SD @("RUN $ctlFile $ctlName")
Write-Output ''
Write-Output '--- SD said, in full: ---'
Write-Output $run
Write-Output '--- end ---'

foreach ($p in @($ctlDir, ($ctlDir + '.DIC'), ($ctlDir + '.OUT'))) {
    if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force }
}

Write-Output ''
$ran     = $run -match 'OSXPRB-DONE'
$worked  = $run -match 'OSEX-RAN'
$refused = $run -match 'not permitted to use the operating system'

Write-Output ("  program reached the end : " + $ran)
Write-Output ("  os.execute PRODUCED ITS OUTPUT (OSEX-RAN captured) : " + $worked)
Write-Output ("  SD printed a refusal    : " + $refused)
Write-Output ''
if (-not $ran) { Write-Output '  VERDICT: inconclusive - the program did not finish.'; exit 2 }
if ($worked -and -not $refused) {
    Write-Output '  VERDICT: THIS SESSION IS PERMITTED to reach the OS.'
    Write-Output '  So the Python gate had no permission reason to refuse, and'
    Write-Output '  verify-pyapi''s -12040 points at the helper not STARTING.'
    exit 0
}
if ($refused -and -not $worked) {
    Write-Output '  VERDICT: THIS SESSION IS NOT PERMITTED to reach the OS.'
    Write-Output '  -12040 is then the gate working as designed, and verify-pyapi'
    Write-Output '  needs a session that is permitted (elevated, or OS.USERS).'
    exit 0
}
Write-Output '  VERDICT: ambiguous - both or neither matched.  Read the raw output.'
exit 1
