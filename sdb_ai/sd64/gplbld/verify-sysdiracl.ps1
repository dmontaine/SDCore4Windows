# verify-sysdiracl.ps1 - prove the seven SDSYS system directories the owner
# ruled read-only on 24 Aug 2026 cannot be written by an ordinary SD user, AND
# that $ipc still can.  PROJECT_STATUS.md 7 step 15.
#
#   powershell -File verify-sysdiracl.ps1        run the checks
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# RUN IT UNELEVATED, AND THAT IS THE POINT, NOT A CONVENIENCE.  The question is
# what an ordinary SD user can do to these paths.  An elevated token holds
# BUILTIN\Administrators, which the ACL grants Full, so an elevated run would
# pass no matter how broken the ACL is - it would be measuring the wrong
# subject.  Same rule and same reason as verify-credacl.ps1 and
# verify-pcodeacl.ps1, both of which refuse elevation for exactly this.
#
# ***$ipc IS THE NEGATIVE CONTROL AND IT IS NOT OPTIONAL.***  Without a row
# that must come back WRITABLE, this script passes in two opposite worlds: one
# where secure-sysdirs.ps1 locked the seven, and one where something locked the
# whole data tree and broke every session.  It is also the row that is true for
# a reason rather than by luck - $ipc is the only one of the eight
# inherited-Modify targets an ordinary session was measured writing (every
# session modifies $ipc\%0; PHANTOM writes its command there, sd.c:55;
# APISRVR:214 opens it), which is why the ruling kept it Modify.
#
# THE DECISIVE CHECK IS THE WRITE, NOT THE ACL LISTING - verify-credacl.ps1's
# rule, and section 6 has the reason twice over: an ACL can be read wrong
# (inherited entries, deny ACEs, group nesting, token filtering), and an icacls
# that has itself been DENIED prints nothing and reads as "(none)", which
# scored a false clean on 24 Aug 2026.  So this asks the filesystem the
# question an attacker would ask, and the listing is reported only as
# diagnosis - labelled "not readable" rather than blank when icacls is refused.
#
# AND THE READ IS CHECKED TOO, WHICH IS NOT PADDING.  secure-sysdirs.ps1 grants
# sdusers (RX) rather than removing them, deliberately: sd.conf is read at
# start-up by every sd.exe, messages and $map are read by the interpreter,
# newvoc is read by CREATE.ACCOUNT, and a token that cannot even ENUMERATE a
# directory breaks scripts that merely stat it - check-install.ps1 aborted with
# "Access is denied" because Test-Path THROWS on an ACL denial.  So "cannot
# write" alone is not the pass condition; "can read, cannot write" is, and a
# run where BOTH fail is a failure with a different fix, reported apart.
#
# sd.conf IS A FILE, so its two questions are asked differently: opening it for
# WRITE rather than creating a file inside it.  The open is FileMode::Open with
# Write access and is closed immediately - it asks the access question without
# changing a byte.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$dataDir = 'C:\ProgramData\SD'
$sysDir  = Join-Path $dataDir 'sdsys'

# THE LIST IS DUPLICATED FROM sd.iss's SecureSysdirs AND MUST MOVE WITH IT.
# Said out loud because the same shape cost session 51 a suite failure: the
# tier VOC counts lived in verify-tiers.ps1 and verify-tierapi.ps1, one copy
# was re-derived, and NOTHING FAILS WHEN TWO COPIES DISAGREE - only when the
# install disagrees with the stale one.  Adding a path to sd.iss and not here
# leaves it locked and unverified; adding it here and not to sd.iss fails this
# script on the next install, which is the safer direction of the two.
$readOnly = @(
    (Join-Path $sysDir 'accounts'),
    (Join-Path $sysDir '$map'),
    (Join-Path $sysDir 'messages'),
    (Join-Path $sysDir 'newvoc'),
    (Join-Path $sysDir 'bp'),
    (Join-Path $sysDir 'cat'),
    (Join-Path $dataDir 'sd.conf')
)
$ipc = Join-Path $sysDir '$ipc'

$results     = @()
$fatal       = $false
$tooLittle   = $false   # something the ruling locked is still writable
$tooHard     = $false   # something is unreadable, or $ipc has stopped working

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
    Write-Output 'verify-sysdiracl: this is an ELEVATED session and the test would be meaningless.'
    Write-Output 'The ACL grants Administrators Full, so an elevated run passes however broken it is.'
    Write-Output 'Run it from an ORDINARY PowerShell window.'
    exit 2
}

# assert-current first, like every script that measures the installed tree.
& (Join-Path $PSScriptRoot 'assert-current.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-sysdiracl: the installed tree does not match source - run a cycle first.'
    exit 2
}

# THE USER MUST ACTUALLY BE AN SD USER, or "cannot write" proves nothing: a
# machine account outside sdusers is refused by the data tree above these and
# would pass a broken ACL.  Same shape as the controls in verify-batchjob.
$inSdusers = $false
try {
    $inSdusers = @(Get-LocalGroupMember -Group sdusers | ForEach-Object { $_.Name }) -contains $id.Name
} catch { }
if (-not $inSdusers) {
    Write-Output "verify-sysdiracl: $($id.Name) is not in sdusers, so a refusal here would prove nothing."
    exit 2
}

# REFUSE THE NULL CASE.  If the install is not there, or a path has been
# renamed, every write probe below fails for the wrong reason and the run reads
# as a clean lock.  Name what is missing and stop.
$absent = @(@($readOnly + $ipc) | Where-Object { -not (Test-Path -LiteralPath $_) })
if ($absent.Count -gt 0) {
    Write-Output 'verify-sysdiracl: these paths do not exist, so nothing could be measured:'
    $absent | ForEach-Object { Write-Output "    $_" }
    exit 2
}

Write-Output ("verify-sysdiracl: as {0}, unelevated, against {1}" -f $id.Name, $dataDir)
# SINGLE QUOTED, so $ipc is four characters and not the path in $ipc.  In
# PowerShell the escape character is a backtick and a backslash is literal, so
# "\$ipc" inside double quotes expands the variable and prepends a backslash.
Write-Output ('  {0} paths ruled read-only, plus $ipc as the negative control' -f $readOnly.Count)
Write-Output ''

# ------------------------------------------------------------------ the probes

# Can an ordinary token READ this path?  Enumeration for a directory, an open
# for a file - the two are different rights and the same question.
function Test-CanRead($p) {
    try {
        if ((Get-Item -LiteralPath $p -Force).PSIsContainer) {
            $null = Get-ChildItem -LiteralPath $p -Force -ErrorAction Stop
        } else {
            $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
            $fs.Close()
        }
        return $true
    } catch { return $false }
}

# Can an ordinary token WRITE this path?  A NEW FILE for a directory - the
# question is whether the directory accepts a write, and rewriting a real
# system file to find out would break the install this is checking.  For a
# file, an OPEN FOR WRITE that is closed at once, never written to.
function Test-CanWrite($p) {
    $item = Get-Item -LiteralPath $p -Force
    if ($item.PSIsContainer) {
        $probe = Join-Path $p 'zz-sysdiracl-probe.tmp'
        $made  = $false
        try {
            [IO.File]::WriteAllText($probe, 'probe')
            $made = $true
        } catch { }
        # Clean up whatever a failure left behind, or the next run inherits it.
        if ($made) { try { Remove-Item -LiteralPath $probe -Force } catch { } }
        return $made
    }
    try {
        $fs = [IO.File]::Open($p, [IO.FileMode]::Open, [IO.FileAccess]::Write, [IO.FileShare]::ReadWrite)
        $fs.Close()
        return $true
    } catch { return $false }
}

# ------------------------------------------------------------------ the checks

foreach ($p in $readOnly) {
    $leaf = Split-Path -Leaf $p

    $canRead = Test-CanRead $p
    if (-not $canRead) { $tooHard = $true }
    Note "sdusers can read $leaf" $canRead $true $true

    $canWrite = Test-CanWrite $p
    if ($canWrite) { $tooLittle = $true }
    Note "sdusers can WRITE $leaf" $canWrite $false $true
}

# THE NEGATIVE CONTROL.  $ipc must still be writable: every session modifies
# $ipc\%0 and a phantom is handed its command through it.  A failure here is
# not a tighter pass, it is a broken install.
$ipcRead = Test-CanRead $ipc
if (-not $ipcRead) { $tooHard = $true }
Note 'sdusers can read $ipc (CONTROL)' $ipcRead $true $true

$ipcWrite = Test-CanWrite $ipc
if (-not $ipcWrite) { $tooHard = $true }
Note 'sdusers can WRITE $ipc (CONTROL)' $ipcWrite $true $true

# Ownership, reported not asserted - an owner can always rewrite the DACL.
foreach ($p in @($readOnly[0], $ipc)) {
    $owner = '(not readable)'
    try { $owner = (Get-Acl -LiteralPath $p).Owner } catch { }
    Note ("owner of " + (Split-Path -Leaf $p)) $owner $owner $false
}

# ---------------------------------------------------------------------- report

# DIAGNOSIS ONLY, and it says "refused" rather than showing a blank.  An icacls
# that has itself been denied prints nothing, and a blank line read as "(none)"
# scored a false clean on 24 Aug 2026.
Write-Output '--- sdusers ACE as an ordinary user sees it ---'
foreach ($p in @($readOnly + $ipc)) {
    $line = '(icacls refused - the ACL could not be read at all)'
    try {
        $raw = @(& icacls.exe $p 2>&1 | ForEach-Object { $_.ToString().Trim() })
        $ace = @($raw | Where-Object { $_ -match 'sdusers' })
        if ($ace.Count -gt 0) { $line = ($ace -join ' | ') }
        elseif ($raw.Count -gt 0) { $line = '(no sdusers ACE) ' + ($raw[0]) }
    } catch { }
    Write-Output ("  {0,-10} {1}" -f (Split-Path -Leaf $p), $line)
}
Write-Output ''

$results | Format-Table -AutoSize | Out-String | Write-Output

if ($fatal) {
    if ($tooLittle) {
        Write-Output 'verify-sysdiracl: FAILED - SDSYS system directories are writable by ordinary SD users.'
        Write-Output ''
        Write-Output '  Any SD user can rewrite the account register, the message file, the'
        Write-Output '  system VOC or the configuration SD reads at start-up. Put it right'
        Write-Output '  from an ELEVATED PowerShell prompt, one call per path:'
        Write-Output ''
        foreach ($p in $readOnly) {
            Write-Output "      powershell -File `"$PSScriptRoot\secure-sysdirs.ps1`" -Path `"$p`""
        }
    }
    if ($tooHard) {
        Write-Output 'verify-sysdiracl: FAILED - and NOT because it is open.'
        Write-Output ''
        Write-Output '  Either a path an ordinary user must read is unreadable, or $ipc has'
        Write-Output '  stopped being writable. $ipc carries every session''s %0 and is how a'
        Write-Output '  PHANTOM is handed its command, so locking it breaks every session.'
        Write-Output '  The intended grants are sdusers:(OI)(CI)(RX) on the six directories,'
        Write-Output '  sdusers:(RX) on sd.conf, and $ipc LEFT ALONE at Modify.'
    }
    exit 1
}

Write-Output 'verify-sysdiracl: PASSED - the seven are readable and not writable, and $ipc still is.'
exit 0
