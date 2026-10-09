# verify-failaudit.ps1 - is a REFUSED API login still audited when the client drops the connection
# during the server's three-second failed-login delay?  The suite step around probe-failaudit.ps1.
#
#   powershell -ExecutionPolicy Bypass -File verify-failaudit.ps1
#
# ***ELEVATED POWERSHELL.***  The full product's audit file (C:\ProgramData\SD\sdsys\audit) is locked to
# SYSTEM and Administrators, and the probe counts "api refused user=<name>" lines in it before and after
# every client it kills.  Changes nothing but the audit file's length (it adds the refusals it causes).
#
# Exit 0 every early drop was audited, or the API listener is off (SKIP, said out loud), 1 at least one
# early drop was NOT audited, 2 the test could not be run.
#
# WHY A WRAPPER.  RELEASE_1.1 122 reordered apisrvr so the audit record is written BEFORE the 3 s sleep,
# after Linux found 5 of 5 early drops wrote nothing there.  The full product's half was witnessed once
# (6 Oct, 5 of 5) and never again in a suite; the Solo half was witnessed 8 Oct 19:21 (probe-failaudit.ps1
# with its defaults, port 4249).  probe-failaudit.ps1 has the method, the controls and the null-case
# refusals, and is not a suite step because it takes -Port and -AuditFile and exits 2 when nothing
# listens.  This step supplies the full product's two values and turns "nothing listens because the API
# was not ticked" into a visible SKIP instead of a failed run.  The probe's own exit code is passed
# through otherwise, and its whole output is printed.
#
# THE SKIP IS NARROW ON PURPOSE: only when sd.conf has no active APIPORT line AND nothing listens on
# 4247.  An active APIPORT with no listener is exit 2 - the install says the API is on and it is not.

$ErrorActionPreference = 'Stop'

$Port  = 4247
$conf  = Join-Path $env:ProgramData 'SD\sd.conf'
$audit = Join-Path $env:ProgramData 'SD\sdsys\audit'
$probe = Join-Path $PSScriptRoot 'probe-failaudit.ps1'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-failaudit-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ('transcript: ' + $logPath)

function Stop-Here([int] $Code) { try { Stop-Transcript | Out-Null } catch { }; exit $Code }

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Write-Output ''; Write-Output 'verify-failaudit: refusing - see above'; Stop-Here 2 }

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-failaudit: this needs an ELEVATED PowerShell - the audit file is locked to SYSTEM and Administrators.'
    Stop-Here 2
}
foreach ($p in @($probe, $conf, $audit)) {
    if (-not (Test-Path -LiteralPath $p)) { Write-Output ('verify-failaudit: REFUSED - no ' + $p); Stop-Here 2 }
}

$apiOn = @(Get-Content -LiteralPath $conf | Where-Object { $_ -match '^\s*APIPORT\s*=\s*[1-9]' }).Count -gt 0
$listening = $null -ne (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1)
Write-Output ('sd.conf    : {0}   active APIPORT line: {1}' -f $conf, $apiOn)
Write-Output ('listener   : port {0} {1}' -f $Port, $(if ($listening) { 'LISTENING' } else { 'not listening' }))
Write-Output ('audit file : ' + $audit)
Write-Output ('probe      : ' + $probe)

if (-not $apiOn -and -not $listening) {
    Write-Output ''
    Write-Output 'SKIP: the API was not enabled at install (no active APIPORT line, nothing on 4247), so there is no refused login to audit.'
    Write-Output 'verify-failaudit: SKIPPED - this says NOTHING about the early-drop audit; install with the API box ticked to measure it.'
    Stop-Here 0
}
if ($apiOn -and -not $listening) {
    Write-Output ''
    Write-Output 'verify-failaudit: REFUSED - sd.conf has an active APIPORT line but nothing listens on 4247 (SD stopped, or the listener failed).'
    Stop-Here 2
}

# The probe in a child powershell so its exit code is its own and its output is shown whole.
$childOut = & powershell -NoProfile -ExecutionPolicy Bypass -File $probe -Port $Port -AuditFile $audit 2>&1 | Out-String -Width 220
$code = $LASTEXITCODE
Write-Output $childOut
Write-Output ('probe exit code: ' + $code)
switch ($code) {
    0 { Write-Output 'VERDICT: PASS - every early drop was audited (control added exactly one line, five drops five lines)' }
    1 { Write-Output 'VERDICT: FAIL - at least one early drop was NOT audited: the refusal is lost when the client leaves during the delay' }
    default { Write-Output 'VERDICT: COULD NOT RUN - the probe refused before it measured (read its output above)'; $code = 2 }
}
Stop-Here $code
