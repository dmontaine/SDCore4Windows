# probe-impersonate.ps1 - build and run probe-impersonate.c as LocalSystem.
#
# 23 Aug 26 Windows port.  PROJECT_STATUS.md section 7 step 14, shape (b).
#
# THE QUESTION: does ImpersonateLoggedOnUser change what the MSYS2 runtime's
# open() can open?  SD opens every data file that way - dh_file.c:815 - so if
# the runtime ignores the thread token, shape (b) buys nothing and the choice
# collapses to shape (a).  probe-impersonate.c's header has the reasoning.
#
# IT MUST RUN AS LocalSystem, and that is not a convenience: LsaRegisterLogonProcess
# needs SeTcbPrivilege, which no interactive account has - probe-s4u.c measured
# that.  Reached the same way probe-s4u.ps1 does it, and for the same reason
# (nothing binary may be downloaded into this project): schtasks /RU SYSTEM.
#
# THREE THINGS INHERITED FROM probe-s4u.ps1, ALL PAID FOR THERE:
#
# 1. Every schtasks call goes through Invoke-Schtasks.  A native command
#    writing to stderr under $ErrorActionPreference = 'Stop' becomes a
#    TERMINATING error in PowerShell 5.1, and the tidy-up /Delete for a task
#    that is not there does exactly that.
# 2. The probe's output is redirected BY cmd.exe into a file which this script
#    then prints.  Reading a native program's stdout through PowerShell lost
#    about ten lines there, including the verdict.
# 3. The output file lives in C:\Windows\Temp, which SYSTEM can write.
#
# THE FIXTURES ARE THE MEASUREMENT, so they are built here rather than assumed:
# two directories, one the target may read and one ACL'd exactly like
# sdsys\$cred - SYSTEM and Administrators, inheritance broken, target absent.
# Both are removed afterwards.
#
# NOT SHIPPED.  probe-impersonate.c, .exe and .ps1 must be on
# assert-current.ps1's $neverShipped list or the tree reads stale because they
# exist.

param(
    [string]$Account = 'test1',
    [switch]$KeepFixtures
)

$ErrorActionPreference = 'Stop'

function Invoke-Schtasks {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out  = & schtasks.exe @Arguments 2>&1
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
    } finally { $ErrorActionPreference = $saved }
}

function Invoke-Icacls {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $out = & icacls.exe @Arguments 2>&1
        return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $out }
    } finally { $ErrorActionPreference = $saved }
}

# ---------------------------------------------------------------------------
# Preconditions, each refused loudly rather than allowed to spoil the result.
# ---------------------------------------------------------------------------
$pr = New-Object Security.Principal.WindowsPrincipal(
          [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'probe-impersonate: this needs an ELEVATED window.'
    Write-Host '  It registers a scheduled task as SYSTEM and sets ACLs.'
    exit 2
}

$acct = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
if ($null -eq $acct) {
    Write-Host "probe-impersonate: local account '$Account' does not exist."
    Write-Host '  Pass -Account with one that does.  probe-s4u used test1.'
    exit 2
}

# IF THE TARGET IS AN ADMINISTRATOR THE FORBIDDEN FILE IS NOT FORBIDDEN TO
# THEM, and the measurement would read as "impersonation does nothing" when in
# fact the ACL never excluded them.  This is the control that would be easiest
# to leave out and hardest to notice missing.
$admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name })
if ($admins -match "\\$Account$") {
    Write-Host "probe-impersonate: '$Account' is an Administrator."
    Write-Host '  The forbidden fixture grants Administrators, so nothing would be'
    Write-Host '  refused and the run would read as a negative result. Pick another.'
    exit 2
}

Write-Host 'probe-impersonate - section 7 step 14, shape (b)'
Write-Host ''
Write-Host "  target account : $Account"
Write-Host "  running as     : $($env:USERNAME), elevated"

# ---------------------------------------------------------------------------
# Build, with the MSYS2 gcc - the runtime is the subject of the test.
# ---------------------------------------------------------------------------
$gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$src    = Join-Path $gplbld 'probe-impersonate.c'
$exe    = Join-Path $gplbld 'probe-impersonate.exe'
$cc     = 'C:\msys64\usr\bin\gcc.exe'

if (-not (Test-Path -LiteralPath $cc)) {
    Write-Host "probe-impersonate: no MSYS2 gcc at $cc"; exit 2
}

# gcc finds its own DLLs through PATH - probe-s4u.ps1 records the same.
$savedPath = $env:PATH
$env:PATH  = 'C:\msys64\usr\bin;' + $env:PATH
try {
    Write-Host ''
    Write-Host '=== building with the MSYS2 gcc (the server toolchain) ==='
    $build = & $cc -O2 -Wall -o $exe $src -lsecur32 -ladvapi32 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host 'BUILD FAILED:'
        $build | ForEach-Object { Write-Host "  $_" }
        exit 2
    }
    Write-Host "  built: $exe"
} finally { $env:PATH = $savedPath }

# ---------------------------------------------------------------------------
# Fixtures.  The forbidden one is ACL'd like sdsys\$cred.
# ---------------------------------------------------------------------------
$base      = Join-Path $env:SystemRoot ('Temp\sdprobe-imp-{0}' -f $PID)
$allowDir  = Join-Path $base 'allowed'
$denyDir   = Join-Path $base 'forbidden'
$allowFile = Join-Path $allowDir 'readable'
$denyFile  = Join-Path $denyDir  'secret'

Write-Host ''
Write-Host '=== fixtures ==='
New-Item -ItemType Directory -Force -Path $allowDir | Out-Null
New-Item -ItemType Directory -Force -Path $denyDir  | Out-Null
Set-Content -LiteralPath $allowFile -Value 'readable by the target' -Encoding utf8
Set-Content -LiteralPath $denyFile  -Value 'not readable by the target' -Encoding utf8

# /inheritance:r FIRST, or the inherited Users ACE grants read and the
# "forbidden" file is not forbidden at all.
$null = Invoke-Icacls $denyDir /inheritance:r
$null = Invoke-Icacls $denyDir /grant 'SYSTEM:(OI)(CI)(F)' 'Administrators:(OI)(CI)(F)'
$null = Invoke-Icacls $allowDir /inheritance:r
$null = Invoke-Icacls $allowDir /grant 'SYSTEM:(OI)(CI)(F)' 'Administrators:(OI)(CI)(F)' `
                                       ("{0}:(OI)(CI)(RX)" -f $Account)

Write-Host "  allowed   : $allowFile"
(Invoke-Icacls $allowFile).Output | ForEach-Object { Write-Host "      $_" }
Write-Host "  forbidden : $denyFile"
(Invoke-Icacls $denyFile).Output | ForEach-Object { Write-Host "      $_" }

# ---------------------------------------------------------------------------
# Run as LocalSystem.
# ---------------------------------------------------------------------------
$taskName = 'SDProbeImpersonate'
$outFile  = Join-Path $env:SystemRoot ('Temp\probe-imp-{0}.txt' -f $PID)
$inner    = '"{0}" {1} "{2}" "{3}" > "{4}" 2>&1' -f $exe, $Account, $allowFile, $denyFile, $outFile
$tr       = 'cmd.exe /c {0}' -f $inner

if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force }

Write-Host ''
Write-Host '==========================================================='
Write-Host ' AS LocalSystem - the identity sdwind runs as.'
Write-Host ' THIS IS THE MEASUREMENT.'
Write-Host '==========================================================='

Invoke-Schtasks /Delete /TN $taskName /F | Out-Null
$created = Invoke-Schtasks /Create /TN $taskName /TR $tr /SC ONCE /ST 00:00 `
                           /RU SYSTEM /RL HIGHEST /F
if ($created.Code -ne 0) {
    Write-Host 'could not register the SYSTEM task:'
    $created.Output | ForEach-Object { Write-Host "  $_" }
    exit 2
}
$started = Invoke-Schtasks /Run /TN $taskName
if ($started.Code -ne 0) {
    Write-Host 'the SYSTEM task would not start:'
    $started.Output | ForEach-Object { Write-Host "  $_" }
    Invoke-Schtasks /Delete /TN $taskName /F | Out-Null
    exit 2
}

# The task is fire-and-forget; wait for the output file to stop growing.
$deadline = (Get-Date).AddSeconds(60)
$lastLen  = -1
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 750
    if (Test-Path -LiteralPath $outFile) {
        $len = (Get-Item -LiteralPath $outFile).Length
        if ($len -gt 0 -and $len -eq $lastLen) { break }
        $lastLen = $len
    }
}
Invoke-Schtasks /Delete /TN $taskName /F | Out-Null

Write-Host ''
if (Test-Path -LiteralPath $outFile) {
    Get-Content -LiteralPath $outFile | ForEach-Object { Write-Host $_ }
    Copy-Item -LiteralPath $outFile -Destination (Join-Path $env:LOCALAPPDATA 'SD-verify\probe-impersonate.txt') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Host 'THE PROBE PRODUCED NO OUTPUT FILE - it did not run, or SYSTEM could not write it.'
    Write-Host 'Nothing here is a result.'
}

if (-not $KeepFixtures) {
    # icacls first: a directory whose ACL excludes this token cannot be removed.
    $null = Invoke-Icacls $base /reset /T /C
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host "fixtures removed: $base"
} else {
    Write-Host ''
    Write-Host "fixtures KEPT: $base"
}
