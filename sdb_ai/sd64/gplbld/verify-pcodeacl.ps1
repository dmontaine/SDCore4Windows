# verify-pcodeacl.ps1 - prove the pcode library cannot be rewritten by an
# ordinary SD user, PROJECT_STATUS.md 7 step 15.
#
#   powershell -File verify-pcodeacl.ps1        run the checks
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# RUN IT UNELEVATED, AND THAT IS THE POINT, NOT A CONVENIENCE.  The question is
# what an ordinary SD user can do to <sysdir>\bin.  An elevated token holds
# BUILTIN\Administrators, which the ACL grants Full, so an elevated run would
# pass no matter how broken the ACL is - it would be measuring the wrong
# subject.  Same rule and same reason as verify-credacl.ps1, which refuses
# elevation for exactly this.
#
# WHY THIS EXISTS.  sysseg.c:189 builds <sysdir>/bin/pcode, :193 opens it and
# :279 reads it WHOLE into the shared segment at start-up; every session then
# executes it through load_pcode() (sd.c:847).  So an SD user who can write
# that file runs their own code in EVERY session - SDSYS's and an
# administrator's included - from the next SD start.  It measured
# sdusers:(I)(OI)(CI)(M) on the 10:01:45 install, 23 Aug 2026, and the write was
# proved from an unelevated token before secure-pcode.ps1 existed.
#
# IT IS THE SAME CONTROL AS verify-catgate AT ONE LEVEL DOWN.  gcat decides
# WHICH catalogued program runs; this decides what the interpreter running it
# IS.  Locking one and leaving the other is most of a control.
#
# THE DECISIVE CHECK IS THE WRITE, NOT THE ACL LISTING - verify-credacl.ps1's
# rule, and it is the one that caught this in the first place.  An ACL can be
# read wrong: inherited entries, deny ACEs, group nesting and token filtering
# all change what a listing means.  So this asks the filesystem the question an
# attacker would ask, and the listing is reported only as diagnosis.
#
# AND THE READ IS CHECKED TOO, WHICH IS NOT PADDING.  secure-pcode.ps1 grants
# sdusers (RX) rather than removing them, deliberately: a token that cannot even
# ENUMERATE the directory breaks scripts that merely stat it, and this project
# has already paid for that once - check-install.ps1 aborted with "Access is
# denied" because Test-Path THROWS on an ACL denial.  So "cannot write" alone is
# not the pass condition; "can read, cannot write" is.  A run where BOTH fail
# means the lock was applied too hard, and that is a failure with a different
# fix, so the two are reported apart.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$binDir = 'C:\ProgramData\SD\sdsys\bin'
$pcode  = Join-Path $binDir 'pcode'

$results = @()
$fatal   = $false

function Note($what, $got, $want, $decisive) {
    $ok = ($got -eq $want)
    if ($decisive -and -not $ok) { $script:fatal = $true }
    $script:results += [pscustomobject]@{
        Check    = $what
        Got      = $got
        Expected = $want
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
        Result   = $(if ($ok) { 'PASS' } else { $(if ($decisive) { 'FAIL' } else { 'note' }) })
    }
}

# ------------------------------------------------------------------ preconditions

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-pcodeacl: this is an ELEVATED session and the test would be meaningless.'
    Write-Output 'The ACL grants Administrators Full, so an elevated run passes however broken it is.'
    Write-Output 'Run it from an ORDINARY PowerShell window.'
    exit 2
}

# assert-current first, like every script that measures the installed tree.
& (Join-Path $PSScriptRoot 'assert-current.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-pcodeacl: the installed tree does not match source - run a cycle first.'
    exit 2
}

if (-not (Test-Path -LiteralPath $binDir)) {
    Write-Output "verify-pcodeacl: $binDir does not exist - nothing to measure."
    exit 2
}

# THE USER MUST ACTUALLY BE AN SD USER, or "cannot write" proves nothing: a
# machine account outside sdusers is refused by the data tree above this and
# would pass a broken ACL.  Same shape as the controls in verify-batchjob.
$inSdusers = $false
try {
    $inSdusers = @(Get-LocalGroupMember -Group sdusers | ForEach-Object { $_.Name }) -contains $id.Name
} catch { }
if (-not $inSdusers) {
    Write-Output "verify-pcodeacl: $($id.Name) is not in sdusers, so a refusal here would prove nothing."
    exit 2
}

# ------------------------------------------------------------------ the checks

# 1. THE READ.  An ordinary session must be able to enumerate this directory.
$canRead = $false
try {
    $null = Get-ChildItem -LiteralPath $binDir -Force -ErrorAction Stop
    $canRead = $true
} catch { }
Note 'sdusers can enumerate <sysdir>\bin' $canRead $true $true

# 2. THE WRITE - the decisive one.  A NEW FILE, not a modification of pcode:
#    the question is whether the directory accepts a write, and rewriting the
#    real pcode to find out would break the install this is checking.
$probe   = Join-Path $binDir 'zz-pcodeacl-probe.tmp'
$canMake = $false
try {
    [IO.File]::WriteAllText($probe, 'probe')
    $canMake = $true
} catch { }
if ($canMake) {
    # Clean up whatever the failure left behind, or the next run inherits it.
    try { Remove-Item -LiteralPath $probe -Force } catch { }
}
Note 'sdusers can create a file in <sysdir>\bin' $canMake $false $true

# 3. THE WRITE THAT MATTERS: opening the real pcode for writing.  Kept separate
#    from check 2 because a directory can refuse new files while an existing
#    file still carries a writable ACE of its own.  OPENED AND CLOSED, never
#    written to - FileMode::Open with Write access asks the access question
#    without changing a byte.
$canOpenPcode = $false
if (Test-Path -LiteralPath $pcode) {
    try {
        $fs = [IO.File]::Open($pcode, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
        $fs.Close()
        $canOpenPcode = $true
    } catch { }
    Note 'sdusers can open pcode for WRITING' $canOpenPcode $false $true
} else {
    Note 'pcode file present' $false $true $true
}

# 4. Ownership, reported not asserted - an owner can always rewrite the DACL.
$owner = '(not readable)'
try { $owner = (Get-Acl -LiteralPath $binDir).Owner } catch { }
Note 'owner' $owner $owner $false

# ---------------------------------------------------------------------- report

Write-Output '--- ACL as an ordinary user sees it ---'
try { (& icacls.exe $binDir 2>&1 | Select-Object -First 6) | Write-Output }
catch { Write-Output '  (could not be listed)' }
Write-Output ''

$results | Format-Table -AutoSize | Out-String | Write-Output

if ($fatal) {
    if ($canMake -or $canOpenPcode) {
        Write-Output 'verify-pcodeacl: FAILED - the pcode library is writable by ordinary SD users.'
        Write-Output ''
        Write-Output '  Any SD user can replace the interpreter every session runs, including'
        Write-Output '  SDSYS''s and an administrator''s, from the next SD start. Put it right'
        Write-Output '  from an ELEVATED prompt:'
        Write-Output ''
        Write-Output "      powershell -File `"$PSScriptRoot\secure-pcode.ps1`" -Path `"$binDir`""
    } else {
        Write-Output 'verify-pcodeacl: FAILED - and NOT because it is open.'
        Write-Output ''
        Write-Output '  An ordinary user cannot even read this directory. That is tighter than'
        Write-Output '  secure-pcode.ps1 applies, and it breaks anything that merely stats the'
        Write-Output '  path - Test-Path THROWS on an ACL denial. Check what else has been'
        Write-Output '  applied to it; the intended grant is sdusers:(OI)(CI)(RX).'
    }
    exit 1
}

Write-Output 'verify-pcodeacl: PASSED - pcode is readable by SD users and writable only by administrators.'
exit 0
