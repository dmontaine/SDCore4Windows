# verify-credacl.ps1 - prove the credential store is closed to ordinary SD
# users, PROJECT_STATUS.md 7 step 6.
#
#   powershell -File verify-credacl.ps1        run the checks
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# RUN IT UNELEVATED, AND THAT IS THE POINT, NOT A CONVENIENCE.  The question is
# what an ordinary SD user can do to $CRED.  An elevated token holds
# BUILTIN\Administrators, which the ACL grants Full, so an elevated run passes
# no matter how broken the ACL is - it would be measuring the wrong subject.
# The script refuses to run elevated for that reason.
#
# WHY THIS EXISTS.  $CRED holds a per-account salt and an Argon2 verifier.
# Reading one is worth little; WRITING one is a straight privilege escalation -
# derive a verifier from a password you choose, overwrite another account's
# record, and authenticate through the API as them.  The data tree grants
# sdusers Modify and $CRED sits inside it, so the protection is entirely the
# ACL that secure-cred.ps1 applies, and nothing checked it until 17 Aug 2026.
#
# IT SHIPPED BROKEN AND STAYED BROKEN FOR A WHOLE SESSION, which is the reason
# this is a tracked script and not a remembered icacls line.  sd.iss single
# quoted the path and handed it to powershell -File, which strips nothing, so
# secure-cred.ps1 was asked to secure a path with quotes in its name, correctly
# answered "does not exist - nothing secured", and exited 2 into a Run entry
# that discarded the code.  Every visible sign said the install had worked.
#
# THE DECISIVE CHECK IS THE WRITE, NOT THE ACL LISTING.  An ACL can be read
# wrong - inherited entries, deny ACEs, group nesting and token filtering all
# change what a listing means - so this asks the filesystem the question the
# attacker would ask: create a file in $CRED as an unprivileged user.  The
# listing is reported too, but only as diagnosis.
#
# ONE THING IT CANNOT ANSWER: whether an ordinary user OWNS $CRED.  An owner
# can always rewrite the DACL, so ownership by anyone other than SYSTEM or
# Administrators would reopen this even with a correct ACL.  Ownership is
# reported below and is checked when it is readable, but on a healthy install
# the DACL denies the read that would confirm it - which is itself the pass.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# A CURRENT INSTALL FIRST.  What this measures is what the INSTALLER did, and
# the installer is source (gplbld/sd.iss, gplbld/secure-cred.ps1), so a stale
# install answers for an older one.  CLAUDE.md: a cycle begins with a fresh
# install; assert-current.ps1 is what makes that enforceable rather than
# remembered.  Exit 2 is this script's own "the test could not be run".
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-credacl: refusing - see above'
    exit 2
}

$store = Join-Path $env:ProgramData 'SD\sdsys\$cred'

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $step; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
}

# ---------------------------------------------------------------- preconditions

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if ($pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-credacl: refusing - this window is ELEVATED.'
    Write-Output ''
    Write-Output '  The ACL grants BUILTIN\Administrators Full, so an elevated'
    Write-Output '  run passes whatever the ACL says. Run it from an ordinary'
    Write-Output '  window, as the user whose access is in question.'
    exit 2
}

if (-not (Test-Path -LiteralPath $store)) {
    Write-Output "verify-credacl: refusing - $store does not exist."
    Write-Output '  Nothing has been installed here, or the bootstrap did not run.'
    exit 2
}

Write-Output "verify-credacl: testing $store"
Write-Output "  as $($id.Name), unelevated"
Write-Output ''

# ---------------------------------------------------------- 1. the decisive write

# THE PROBE IS DELETED IMMEDIATELY IF IT IS EVER CREATED.  On a healthy install
# this file is never made at all, because the create fails - which is the pass.
# $CRED is a directory file, so a stray file here would read as a record; the
# name is chosen to be unmistakable if a crash ever leaves one behind.
$probe = Join-Path $store 'verify-credacl-probe'
$wrote = $false
try {
    $fs = [System.IO.File]::Open($probe, [System.IO.FileMode]::CreateNew,
                                 [System.IO.FileAccess]::Write)
    $fs.Close()
    $wrote = $true
}
catch [System.UnauthorizedAccessException] {
    $wrote = $false
}
catch {
    # Anything else is not an answer to the question asked.  Report it rather
    # than scoring it, so a broken probe cannot read as a pass.
    Write-Output "verify-credacl: probe could not be run: $($_.Exception.Message)"
    exit 2
}

if ($wrote) {
    try { Remove-Item -LiteralPath $probe -Force } catch {
        Write-Output "verify-credacl: WARNING - could not remove probe file $probe"
    }
}

Note 'ordinary user can create a record in $CRED' 'no' $(if ($wrote) { 'yes' } else { 'no' }) $true

# ------------------------------------------------------- 2. the ACL, as diagnosis

# Access denied HERE IS THE HEALTHY ANSWER.  Reading a DACL needs READ_CONTROL,
# which a locked $CRED grants no ordinary user - so the three siblings
# (audit, sd-elevate.log, PSTMP) all refuse this read on a good install, and
# $CRED refusing it too is the shape being aimed at.
# EAP IS LOWERED ACROSS THIS CALL, and leaving it at Stop was a bug that made
# this script fail on exactly the installs it should pass.  Under Stop, 2>&1 on
# a native command turns each stderr line into a terminating NativeCommandError
# - and "Access is denied" on stderr IS the healthy answer here, so the script
# died at the moment it had proof the ACL was right.  Caught 17 Aug 2026 on the
# 17:36:21 install, one file over from the identical trap written up at the top
# of secure-cred.ps1.
$prevEap = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$acl = & icacls.exe $store 2>&1
$readable = ($LASTEXITCODE -eq 0)
$ErrorActionPreference = $prevEap
$aclText = ($acl | Out-String)

if ($readable) {
    # Readable means an ordinary token has READ_CONTROL. That is not by itself
    # the escalation - the write above is - but on a correctly locked store it
    # does not happen, so it is worth failing on rather than merely printing.
    Note 'DACL is readable by an ordinary user' 'no' 'yes' $false
    if ($aclText -match 'sdusers') {
        Note 'sdusers appears in the DACL' 'no' 'yes' $true
    } else {
        Note 'sdusers appears in the DACL' 'no' 'no' $true
    }
    if ($aclText -match '\(I\)') {
        # Inherited entries mean /inheritance:r did not run: this is the exact
        # signature the broken install left behind on 17 Aug 2026.
        Note 'DACL still has INHERITED entries' 'no' 'yes' $true
    } else {
        Note 'DACL still has INHERITED entries' 'no' 'no' $true
    }
} else {
    Note 'DACL is readable by an ordinary user' 'no' 'no' $false
}

# ------------------------------------------------------------------- 3. ownership

$owner = '(not readable)'
try { $owner = (Get-Acl -LiteralPath $store).Owner } catch { }
Note 'owner' $owner $owner $false

# ---------------------------------------------------------------------- report

Write-Output '--- ACL as an ordinary user sees it ---'
if ($readable) { Write-Output $aclText.TrimEnd() }
else { Write-Output '  Access is denied - which is the expected answer.' }
Write-Output ''

$results | Format-Table -AutoSize | Out-String | Write-Output

if ($fatal) {
    Write-Output 'verify-credacl: FAILED - the credential store is open.'
    Write-Output ''
    Write-Output '  Any SD user can overwrite another account''s verifier and then'
    Write-Output '  authenticate as them. Put it right from an ELEVATED prompt:'
    Write-Output ''
    Write-Output "      powershell -File `"$PSScriptRoot\secure-cred.ps1`" -Path `"$store`""
    exit 1
}

Write-Output 'verify-credacl: PASSED - the credential store is closed to ordinary users.'
exit 0
