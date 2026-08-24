# probe-impfork.ps1 - build and run probe-impfork.c as LocalSystem.
#
# 24 Aug 26 Windows port.  PROJECT_STATUS.md section 7 step 14, after run b28.
#
# TWO QUESTIONS, and probe-impfork.c's header carries the reasoning:
#   Q1  does ImpersonateLoggedOnUser still govern the MSYS2 runtime's open()
#       in a fork()ed and exec()d Cygwin child - the shape an API session
#       actually has (sdwind.c:491)?  probe-impersonate measured a STANDALONE
#       program started by schtasks, which is not that shape.
#   Q2  when a file is CREATED while impersonating, whose name goes on it?
#       b28 read Get-Acl.Owner on a record written by the API session and
#       concluded the switch has no effect.  That reading is equally consistent
#       with the runtime stamping a new file from its own cached user, which
#       the thread token does not touch - and b28's control could not have
#       separated the two.
#
# IT MUST RUN AS LocalSystem, and that is not a convenience:
# LsaRegisterLogonProcess needs SeTcbPrivilege, which no interactive account
# has - probe-s4u measured that, and probe-impfork refuses with
# NTSTATUS 0xC0000041 when run as anyone else.  Reached the way probe-s4u.ps1
# and probe-impersonate.ps1 reach it, and for the same reason (nothing binary
# may be downloaded into this project): schtasks /RU SYSTEM.
#
# THREE THINGS INHERITED FROM probe-s4u.ps1, ALL PAID FOR THERE:
#
# 1. Every schtasks and icacls call goes through a wrapper.  A native command
#    writing to stderr under $ErrorActionPreference = 'Stop' becomes a
#    TERMINATING error in PowerShell 5.1, and the tidy-up /Delete for a task
#    that is not there does exactly that.
# 2. The probe's output is redirected BY cmd.exe into a file which this script
#    then prints.  Reading a native program's stdout through PowerShell lost
#    about ten lines there, including the verdict.
# 3. The output file lives in C:\Windows\Temp, which SYSTEM can write.
#
# AND ONE PAID FOR BY verify-apiidentity's b25: icacls can exit 0 having said
# "Access is denied".  Assert-Icacls reads the OUTPUT, not just the code.
#
# THE FIXTURES ARE THE MEASUREMENT, so they are built here, ASSERTED here, and
# printed in the transcript rather than assumed:
#   allowed    the target may read           (OI)(CI)(RX)
#   forbidden  ACL'd exactly like sdsys\$cred - SYSTEM and Administrators only
#   writable   the target may create files   (OI)(CI)(M)   <- Q2 needs this
# ACLs are set on the DIRECTORIES BEFORE the files are made, so each file
# inherits the ACL it is supposed to have rather than being fixed up
# afterwards - b26's lesson was that the assertion belongs on the FILE.
#
# NOT SHIPPED.  probe-impfork.c, .exe and .ps1 are on assert-current.ps1's
# $neverShipped list, added in the commit that creates them, or the tree reads
# stale because they exist.

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
        $out = & schtasks.exe @Arguments 2>&1
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

# b25: icacls exits 0 having failed. Read what it SAID, not just the code.
#
# AND THE FIRST VERSION OF THIS FUNCTION WAS ITSELF THE TRAP CLAUDE.md NAMES -
# 24 Aug 2026, caught on the first elevated run.  It disqualified on the
# substring 'Failed processing', which icacls prints on EVERY SUCCESS as
# "Successfully processed 1 files; Failed processing 0 files".  So it refused a
# perfectly good fixture.  A pattern shared by the success and failure outputs
# is not a check.  The counts are parsed, and the SUCCESS wording is what is
# anchored on - with the null case (0 files processed) refused out loud.
function Assert-Icacls {
    param([string]$What, $Result)
    $text = ($Result.Output | Out-String)
    $why  = @()

    if ($Result.Code -ne 0)              { $why += "exit code $($Result.Code)" }
    if ($text -match 'Access is denied') { $why += 'it said "Access is denied"' }

    if ($text -match 'Failed processing\s+(\d+)\s+file') {
        if ([int]$Matches[1] -gt 0) { $why += "it failed $($Matches[1]) file(s)" }
    } else {
        $why += 'it printed no "Failed processing N files" line at all'
    }

    # THE POSITIVE ANCHOR, and the null case with it: a run that processed
    # nothing must not pass merely because nothing failed.
    if ($text -match 'Successfully processed\s+(\d+)\s+file') {
        if ([int]$Matches[1] -lt 1) { $why += 'it processed 0 files - it did nothing' }
    } else {
        $why += 'it printed no "Successfully processed N files" line'
    }

    if ($why.Count -gt 0) {
        Write-Host "  icacls FAILED: $What"
        $why | ForEach-Object { Write-Host "      because $_" }
        $Result.Output | ForEach-Object { Write-Host "      | $_" }
        # A refusal here used to leave the fixtures behind, and /inheritance:r
        # on a fresh directory leaves an EMPTY DACL - so the leftovers could not
        # be removed without elevation.  Cleaned up if the caller has defined
        # the cleanup yet; the guard is what lets this function be unit-tested
        # on its own, where Remove-Fixtures does not exist.
        if (Get-Command Remove-Fixtures -ErrorAction SilentlyContinue) { Remove-Fixtures }
        exit 2
    }
}

# ---------------------------------------------------------------------------
# Preconditions, each refused loudly rather than allowed to spoil the result.
# ---------------------------------------------------------------------------
$pr = New-Object Security.Principal.WindowsPrincipal(
          [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host 'probe-impfork: this needs an ELEVATED window.'
    Write-Host '  It registers a scheduled task as SYSTEM and sets ACLs.'
    exit 2
}

$acct = Get-LocalUser -Name $Account -ErrorAction SilentlyContinue
if ($null -eq $acct) {
    Write-Host "probe-impfork: local account '$Account' does not exist."
    Write-Host '  Pass -Account with one that does.  probe-impersonate used test1.'
    exit 2
}

# IF THE TARGET IS AN ADMINISTRATOR THE FORBIDDEN FILE IS NOT FORBIDDEN TO
# THEM, and the measurement would read as "impersonation does nothing" when in
# fact the ACL never excluded them.  probe-impersonate.ps1 calls this the
# control that is easiest to leave out and hardest to notice missing.
$admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name })
if ($admins -match "\\$Account$") {
    Write-Host "probe-impfork: '$Account' is an Administrator."
    Write-Host '  The forbidden fixture grants Administrators, so nothing would be'
    Write-Host '  refused and the run would read as a negative result. Pick another.'
    exit 2
}

Write-Host 'probe-impfork - section 7 step 14, after b28'
Write-Host ''
Write-Host "  target account : $Account"
Write-Host "  running as     : $($env:USERNAME), elevated"

# ---------------------------------------------------------------------------
# Build, with the MSYS2 gcc - the runtime is the subject of the test.
# ---------------------------------------------------------------------------
$gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$src    = Join-Path $gplbld 'probe-impfork.c'
$exe    = Join-Path $gplbld 'probe-impfork.exe'
$cc     = 'C:\msys64\usr\bin\gcc.exe'

if (-not (Test-Path -LiteralPath $cc)) {
    Write-Host "probe-impfork: no MSYS2 gcc at $cc"; exit 2
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
# Fixtures.  ACLs on the directories FIRST, then the files, so each file
# inherits what it is meant to have.
# ---------------------------------------------------------------------------
$base      = Join-Path $env:SystemRoot ('Temp\sdprobe-impf-{0}' -f $PID)
$allowDir  = Join-Path $base 'allowed'
$denyDir   = Join-Path $base 'forbidden'
$writeDir  = Join-Path $base 'writable'
$allowFile = Join-Path $allowDir 'readable'
$denyFile  = Join-Path $denyDir  'secret'

# ONE cleanup, used by every exit path.  icacls /reset FIRST: a directory whose
# DACL was emptied by /inheritance:r cannot be removed on its own rights.
function Remove-Fixtures {
    if ($script:cmdFile -and (Test-Path -LiteralPath $script:cmdFile)) {
        Remove-Item -LiteralPath $script:cmdFile -Force -ErrorAction SilentlyContinue
    }
    if (-not $script:base) { return }
    if (-not (Test-Path -LiteralPath $script:base)) { return }
    $null = Invoke-Icacls $script:base /reset /T /C /Q
    Remove-Item -LiteralPath $script:base -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  fixtures removed: $script:base"
}

# Leftovers from an earlier run that died before its cleanup.  Same reason:
# they may carry an empty DACL, and this is the elevated context that can
# still reset them.
Get-ChildItem -Path (Join-Path $env:SystemRoot 'Temp') -Filter 'sdprobe-impf-*' `
              -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  clearing an earlier run's leftovers: $($_.FullName)"
    $null = Invoke-Icacls $_.FullName /reset /T /C /Q
    Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}
Get-ChildItem -Path (Join-Path $env:SystemRoot 'Temp') -Filter 'probe-impf-*' `
              -File -ErrorAction SilentlyContinue | ForEach-Object {
    Remove-Item -LiteralPath $_.FullName -Force -ErrorAction SilentlyContinue
}

Write-Host ''
Write-Host '=== fixtures ==='
New-Item -ItemType Directory -Force -Path $allowDir | Out-Null
New-Item -ItemType Directory -Force -Path $denyDir  | Out-Null
New-Item -ItemType Directory -Force -Path $writeDir | Out-Null

# /inheritance:r FIRST on the forbidden one, or the inherited Users ACE grants
# read and the "forbidden" file is not forbidden at all.  No /T anywhere: b25
# was an /inheritance:r /T walk that emptied the parent and then could not
# descend into it.
Assert-Icacls 'forbidden /inheritance:r' (Invoke-Icacls $denyDir /inheritance:r)
Assert-Icacls 'forbidden /grant' (Invoke-Icacls $denyDir /grant `
    'SYSTEM:(OI)(CI)(F)' 'Administrators:(OI)(CI)(F)')

Assert-Icacls 'allowed /inheritance:r' (Invoke-Icacls $allowDir /inheritance:r)
Assert-Icacls 'allowed /grant' (Invoke-Icacls $allowDir /grant `
    'SYSTEM:(OI)(CI)(F)' 'Administrators:(OI)(CI)(F)' `
    ("{0}:(OI)(CI)(RX)" -f $Account))

Assert-Icacls 'writable /inheritance:r' (Invoke-Icacls $writeDir /inheritance:r)
Assert-Icacls 'writable /grant' (Invoke-Icacls $writeDir /grant `
    'SYSTEM:(OI)(CI)(F)' 'Administrators:(OI)(CI)(F)' `
    ("{0}:(OI)(CI)(M)" -f $Account))

Set-Content -LiteralPath $allowFile -Value 'readable by the target' -Encoding utf8
Set-Content -LiteralPath $denyFile  -Value 'not readable by the target' -Encoding utf8

# THE FIXTURES ARE ASSERTED, NOT JUST PRINTED.  A forbidden file that happens
# to name the target, or a writable directory that does not, would make the
# whole run meaningless in a way no later step could detect.
$denyAcl  = (Invoke-Icacls $denyFile).Output  | Out-String
$allowAcl = (Invoke-Icacls $allowFile).Output | Out-String
$writeAcl = (Invoke-Icacls $writeDir).Output  | Out-String

Write-Host "  allowed   : $allowFile"
$allowAcl -split "`r?`n" | Where-Object { $_ -ne '' } | ForEach-Object { Write-Host "      $_" }
Write-Host "  forbidden : $denyFile"
$denyAcl  -split "`r?`n" | Where-Object { $_ -ne '' } | ForEach-Object { Write-Host "      $_" }
Write-Host "  writable  : $writeDir"
$writeAcl -split "`r?`n" | Where-Object { $_ -ne '' } | ForEach-Object { Write-Host "      $_" }

$bad = @()
if ($denyAcl  -match [regex]::Escape($Account)) { $bad += "the FORBIDDEN file names $Account" }
if ($allowAcl -notmatch [regex]::Escape($Account)) { $bad += "the ALLOWED file does not name $Account" }
if ($writeAcl -notmatch [regex]::Escape($Account)) { $bad += "the WRITABLE directory does not name $Account" }
if ($bad.Count -gt 0) {
    Write-Host ''
    Write-Host '*** the fixtures are wrong, so nothing measured with them would mean anything:'
    $bad | ForEach-Object { Write-Host "      $_" }
    if (-not $KeepFixtures) { Remove-Fixtures }
    exit 2
}
Write-Host '  fixtures assert correctly.'

# ---------------------------------------------------------------------------
# Run as LocalSystem.
# ---------------------------------------------------------------------------
$taskName = 'SDProbeImpFork'
$outFile  = Join-Path $env:SystemRoot ('Temp\probe-impf-{0}.txt' -f $PID)
$cmdFile  = Join-Path $env:SystemRoot ('Temp\probe-impf-{0}.cmd' -f $PID)

# THE COMMAND GOES IN A BATCH FILE, NOT IN /TR.  schtasks refuses a /TR longer
# than 261 characters - measured 24 Aug 2026, "Value for '/TR' option cannot be
# more than 261 character(s)" - and this probe takes four paths where
# probe-impersonate took two, which is enough to cross it.  /TR then carries
# only the short path to the batch file.
#
# ASCII, NOT utf8: Set-Content -Encoding utf8 writes a BOM in PowerShell 5.1,
# and a BOM at the top of a .cmd is fed to the command interpreter as part of
# the first line.  That is the embedded-BOM trap CLAUDE.md records, in the one
# file type where it would be silent.
$inner = '"{0}" {1} "{2}" "{3}" "{4}" > "{5}" 2>&1' -f `
             $exe, $Account, $allowFile, $denyFile, $writeDir, $outFile
Set-Content -LiteralPath $cmdFile -Encoding ascii -Value @(
    '@echo off'
    $inner
)
$tr = $cmdFile

if (Test-Path -LiteralPath $outFile) { Remove-Item -LiteralPath $outFile -Force }

Write-Host ''
Write-Host '==========================================================='
Write-Host ' AS LocalSystem - the identity sdwind runs as.'
Write-Host ' THIS IS THE MEASUREMENT.'
Write-Host '==========================================================='
# CLAUDE.md rule 1: show the REAL command line, not the intended one.  That
# now means the batch file's CONTENTS, read back off disk - printing $inner
# would show what was meant to be written rather than what was.
Write-Host "  task /TR      : $tr   ($($tr.Length) chars, limit 261)"
Write-Host '  batch file as written back off disk:'
Get-Content -LiteralPath $cmdFile | ForEach-Object { Write-Host "      | $_" }
if ($tr.Length -gt 261) {
    Write-Host '  /TR is still over the limit - schtasks would refuse it.'
    if (-not $KeepFixtures) { Remove-Fixtures }
    exit 2
}

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
# This probe forks, so it writes in two bursts with a pause between them -
# the settle window is longer than probe-impersonate's for that reason.
$deadline = (Get-Date).AddSeconds(90)
$lastLen  = -1
$stable   = 0
while ((Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 750
    if (Test-Path -LiteralPath $outFile) {
        $len = (Get-Item -LiteralPath $outFile).Length
        if ($len -gt 0 -and $len -eq $lastLen) {
            $stable++
            if ($stable -ge 4) { break }   # 3s unchanged, not 0.75s
        } else { $stable = 0 }
        $lastLen = $len
    }
}
Invoke-Schtasks /Delete /TN $taskName /F | Out-Null

Write-Host ''
if (Test-Path -LiteralPath $outFile) {
    Get-Content -LiteralPath $outFile | ForEach-Object { Write-Host $_ }
    $keep = Join-Path $env:LOCALAPPDATA 'SD-verify\probe-impfork.txt'
    Copy-Item -LiteralPath $outFile -Destination $keep -Force -ErrorAction SilentlyContinue
    Write-Host ''
    Write-Host "transcript kept at: $keep"
    Remove-Item -LiteralPath $outFile -Force -ErrorAction SilentlyContinue
} else {
    Write-Host 'THE PROBE PRODUCED NO OUTPUT FILE - it did not run, or SYSTEM could not'
    Write-Host 'write it.  Nothing here is a result.'
}

Write-Host ''
if (-not $KeepFixtures) {
    Remove-Fixtures
} else {
    Write-Host "fixtures KEPT: $base"
}
