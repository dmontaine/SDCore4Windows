# probe-sshpreflight.ps1 - prove ssh-preflight.ps1 refuses when it should, and
# does NOT refuse when it should not.  PROJECT_STATUS.md 5.9, 7 step 3.
#
#   powershell -ExecutionPolicy Bypass -File <dir>\probe-sshpreflight.ps1
#
# ***RUN ONLY ON A THROWAWAY GUEST.***  It appends a directive to sshd_config
# and registers a bogus ssh service, then puts both back.  ELEVATED - creating
# a service needs it.  It does not ship: it is on assert-current's
# $neverShipped list.
#
# ssh-preflight.ps1 must be BESIDE this script.  Both are copied to a transient
# shared folder and run from there; neither hard-codes a drive letter, because
# a transient share does not get a stable one - two shares came up Y: and Z:,
# one share came up Z: alone, and a hard-coded Y: failed with "the argument to
# the -File parameter does not exist".
#
# A FALSE REFUSAL IS THE WORSE FAILURE - it turns away an install that should
# have worked - so the CLEAR cases are tested FIRST AND LAST.  The last case is
# not a formality: if the restore did not work, it fails and says so, rather
# than leaving a machine quietly mis-set and a result nobody can trust.
#
# MEASURED 25 Aug 2026 on VM Windows 11 - sshRemoteTest-A2, all four cases as
# expected: clear, refuse on a hand-configured sshd_config naming the added
# directive, refuse on a stopped third-party service naming it and its path,
# clear again after restore.

$ErrorActionPreference = 'Continue'

# FIND OUR OWN DIRECTORY RATHER THAN HARD-CODING A DRIVE LETTER.  A transient
# shared folder does NOT get a stable letter: with two shares mounted it came
# up Y: and Z:, with one share it came up Z: alone, and a hard-coded Y: then
# failed with "the argument to the -File parameter does not exist".
# $PSScriptRoot is empty in some hosts - adopt-account.ps1 records what that
# cost - so fall back to MyInvocation rather than trusting it.
$here = $PSScriptRoot
if (-not $here) { $here = Split-Path -Parent $MyInvocation.MyCommand.Path }

Start-Transcript -Path (Join-Path $here 'selftest-out.txt') -Force | Out-Null
Write-Host ('running from : ' + $here)

$probe = Join-Path $here 'ssh-preflight.ps1'
if (-not (Test-Path -LiteralPath $probe)) {
    Write-Host ('[FAIL] ssh-preflight.ps1 not found beside this script at ' + $probe)
    Stop-Transcript | Out-Null
    exit 1
}
$cfg   = Join-Path $env:ProgramData 'ssh\sshd_config'
$bak   = Join-Path $env:ProgramData 'ssh\sshd_config.selftest-backup'
$fails = 0

function Run-Case([string]$name, [int]$want) {
    Write-Host ''
    Write-Host ('================ CASE: ' + $name + '  (expect exit ' + $want + ') ================')
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $probe 2>&1 |
        ForEach-Object { Write-Host ('  | ' + $_) }
    $rc = $LASTEXITCODE
    Write-Host ('  exit code: ' + $rc)
    if ($rc -eq $want) { Write-Host ('  [ok]   as expected') }
    else               { Write-Host ('  [FAIL] wanted ' + $want + ', got ' + $rc); $script:fails++ }
    return $rc
}

Write-Host ('elevated : ' + ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))
Write-Host ('sshd_config present : ' + (Test-Path -LiteralPath $cfg))

# --- 1. baseline: SD is installed here, so this must be CLEAR ---------------
$null = Run-Case 'baseline, SD installed, stock config' 0

# --- 2. somebody has configured the Windows server -------------------------
if (Test-Path -LiteralPath $cfg) {
    Copy-Item -LiteralPath $cfg -Destination $bak -Force
    Add-Content -LiteralPath $cfg -Value 'PermitRootLogin no'
    Write-Host ''
    Write-Host 'added "PermitRootLogin no" to sshd_config'
    $null = Run-Case 'hand-configured Microsoft sshd_config' 1
    Copy-Item -LiteralPath $bak -Destination $cfg -Force
    Remove-Item -LiteralPath $bak -Force
    Write-Host 'sshd_config restored'
} else {
    Write-Host '[FAIL] no sshd_config to modify - case 2 could not run, which is not a pass'
    $fails++
}

# --- 3. a third-party ssh service, installed but not running ---------------
# Registered with a binary path that does not exist: the service never starts,
# and it does not need to - the point is whether the SCAN sees it.
$svc = 'SelfTestSshServer'
$bin = 'C:\NoSuchDir\BvSshServer.exe'
try {
    $null = & sc.exe create $svc binPath= $bin start= demand 2>&1
    Write-Host ''
    Write-Host ('registered bogus service ' + $svc + ' -> ' + $bin)
    $null = Run-Case 'third-party ssh service installed but stopped' 1
} finally {
    $null = & sc.exe delete $svc 2>&1
    Write-Host ('removed service ' + $svc)
}

# --- 4. everything restored: must be CLEAR again ---------------------------
$null = Run-Case 'after restore - must be clear again' 0

Write-Host ''
Write-Host '================ SELFTEST VERDICT ================'
if ($fails -eq 0) { Write-Host '  preflight-selftest: PASSED - refuses when it should, clears when it should.' }
else              { Write-Host ('  preflight-selftest: FAILED - ' + $fails + ' case(s) wrong.') }

Stop-Transcript | Out-Null
