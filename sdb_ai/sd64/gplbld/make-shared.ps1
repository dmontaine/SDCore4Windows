# make-shared.ps1 - make the SHARED ACCOUNT at install time, or refuse the install because the name is taken.
#
#   powershell -ExecutionPolicy Bypass -File make-shared.ps1 -Preflight -ReasonFile <file>       (before anything is changed)
#   powershell -ExecutionPolicy Bypass -File make-shared.ps1 -AppDir <app> -DataDir <data>       (after the files are in place)
#
# 25 Oct 2026, RELEASE_1.1 170: the Windows half of Linux S.66 (fc4030a, Linux installsdcore.sh shared_preflight and
# SHARED-CREATE).  A group account named shared whose files every account with the shared.read gate opens by NAME.  The kernel,
# the BASIC and the gates are in the tree; this is the installer's part, and it is the same behaviour as Linux's with three
# differences the operating system forces (mailed 25 Oct, no objection from Linux 24 Oct 23:50):
#   1. The register group sdg_shared is a LOCAL WINDOWS GROUP WITH NO MEMBERS.  Linux has root and sdsys in it; on Windows SDSYS is an
#      elevated sign-on and not a group member, and Administrators / SYSTEM already hold full control of every account directory.
#   2. The directory's ACL is SYSTEM and Administrators Full, sdusers Modify, both (OI)(CI), inheritance broken - the same people as
#      Linux's sdsys:sdusers 2775 / 664.  CREATE.ACCOUNT stamps it at create time (create_account secure.account.dir) and
#      secure-account-dirs.ps1 re-stamps it at every install: BOTH know the name shared, which is why there is no second script.
#   3. THE DOOR IS A MARKER, AS IN LINUX: sdsys\$shared.make, written immediately before 'CREATE.ACCOUNT GROUP shared' and removed
#      again whatever happens, so a failed create cannot leave the name open.  Without it the verb refuses the name (12521).
#
# PREFLIGHT (-Preflight).  An account named shared that the administrator made BEFORE this release cannot become SD's: its group, its
# members and its files were not chosen for this, and every account would be able to read it by file name.  So the install stops,
# before one file is written, naming the register record to look at.  An account is OURS only when its record says what this script
# makes: line 1 the group_accounts\shared directory and line 3 sdg_shared.  Exit 0 go on, 4 a foreign account (reason in -ReasonFile).
#
# CREATE.  Exit codes, and sd.iss reports each one differently:
#   0  made, and the register, the directory's ACL and the group all say what they should
#   2  already there and ours - the reinstall / kept-accounts case, nothing to do
#   3  SD would not start, so the verb was never run
#   1  anything else: the verb refused, or the result is not what it should be (each difference is printed)
#
# THE VERDICT IS DRAWN FROM WHAT THE SYSTEM NOW HOLDS, NOT FROM ANY EXIT CODE (the instrument rule): the register record's lines 1 and 3,
# the directory's ACL entry by entry, and the members of sdg_shared.

[CmdletBinding()]
param(
    [switch] $Preflight,
    [string] $ReasonFile = '',
    [string] $AppDir = '',
    [string] $DataDir = 'C:\ProgramData\SD',
    # Test seams: the two names the verdict looks for.  The installer never passes them.
    [string] $ExpectedGroup = 'sdg_shared',
    [string] $UsersGroup = 'sdusers'
)

$ErrorActionPreference = 'Stop'

# A person who types "powershell -ExecutionPolicy Bypass -File <script>" into a PowerShell 7 window starts a 5.1 that inherits PowerShell 7's module
# folders, where the first Security cmdlet (Get-Acl below) fails to load (RELEASE_1.1 110, 111).  Set to Windows PowerShell's own folders, as
# gpl.bp/ps_scripto does for SD's scripts; before any cmdlet, so early enough.  test-psmodulepath-units.ps1 holds every such script to it.
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"

function Get-SharedPaths([string] $Data) {
    return [pscustomobject]@{
        Record = Join-Path $Data 'sdsys\accounts\shared'
        Dir    = Join-Path $Data 'group_accounts\shared'
        Marker = Join-Path $Data 'sdsys\$shared.make'
    }
}

function ConvertTo-CompareForm([string] $p) {
    # Windows paths in a register record may carry either separator and any case.
    if ($null -eq $p) { return '' }
    return (($p.Trim() -replace '/', '\').TrimEnd('\')).ToLowerInvariant()
}

function Get-SharedRecordVerdict {
    <#
      Is the register record of the account called shared SD's own?  Returns 'absent' (no record), 'ours' (line 1 is the group_accounts\shared
      directory and line 3 is sdg_shared) or 'foreign' (anything else, with the two lines in Lines).  PURE: it reads one file.
    #>
    param([string] $Record, [string] $Dir, [string] $Group = 'sdg_shared')
    if (-not (Test-Path -LiteralPath $Record)) {
        return [pscustomobject]@{ Verdict = 'absent'; Line1 = ''; Line3 = '' }
    }
    $lines = @(Get-Content -LiteralPath $Record -ErrorAction Stop)
    $l1 = ''; $l3 = ''
    if ($lines.Count -ge 1) { $l1 = [string]$lines[0] }
    if ($lines.Count -ge 3) { $l3 = [string]$lines[2] }
    $ours = ((ConvertTo-CompareForm $l1) -eq (ConvertTo-CompareForm $Dir)) -and ($l3.Trim().ToLowerInvariant() -eq $Group.ToLowerInvariant())
    return [pscustomobject]@{ Verdict = $(if ($ours) { 'ours' } else { 'foreign' }); Line1 = $l1; Line3 = $l3 }
}

function Get-SharedAclProblems {
    <#
      The directory's ACL against what the design says, ENTRY BY ENTRY.  Returns the list of differences (empty = right):
        inheritance broken; exactly SYSTEM (S-1-5-18) Full, Administrators (S-1-5-32-544) Full and the users group Modify; every
        entry Allow and inherited by containers and objects.
      By SID, because the two built-ins are renamed on a localised Windows.
    #>
    param([string] $Dir, [string] $UsersGroup = 'sdusers')
    $problems = @()
    if (-not (Test-Path -LiteralPath $Dir)) { return @("no directory $Dir") }
    $acl = Get-Acl -LiteralPath $Dir
    if (-not $acl.AreAccessRulesProtected) { $problems += 'inheritance is not broken (the data tree''s grants are still inherited)' }
    try {
        $usersSid = ([System.Security.Principal.NTAccount]$UsersGroup).Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        return @($problems + "the group $UsersGroup does not exist")
    }
    $want = @{
        'S-1-5-18'     = [System.Security.AccessControl.FileSystemRights]::FullControl
        'S-1-5-32-544' = [System.Security.AccessControl.FileSystemRights]::FullControl
    }
    $want[$usersSid] = [System.Security.AccessControl.FileSystemRights]::Modify -bor [System.Security.AccessControl.FileSystemRights]::Synchronize
    $seen = @{}
    foreach ($r in $acl.Access) {
        $sid = $r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if (-not $want.ContainsKey($sid)) { $problems += "unexpected entry for $($r.IdentityReference) ($($r.FileSystemRights))"; continue }
        if ($r.AccessControlType -ne 'Allow') { $problems += "entry for $($r.IdentityReference) is $($r.AccessControlType)" }
        if ($r.InheritanceFlags -ne 'ContainerInherit, ObjectInherit') { $problems += "entry for $($r.IdentityReference) is not (OI)(CI): $($r.InheritanceFlags)" }
        $rights = [int]$r.FileSystemRights
        $needed = [int]$want[$sid]
        if (($rights -band $needed) -ne $needed) { $problems += "entry for $($r.IdentityReference) is $($r.FileSystemRights), expected $($want[$sid])" }
        if ($sid -eq $usersSid -and ($rights -band [int][System.Security.AccessControl.FileSystemRights]::FullControl) -eq [int][System.Security.AccessControl.FileSystemRights]::FullControl) {
            $problems += "entry for $($r.IdentityReference) is Full control, expected Modify"
        }
        $seen[$sid] = $true
    }
    foreach ($sid in $want.Keys) { if (-not $seen.ContainsKey($sid)) { $problems += "no entry for $sid" } }
    return $problems
}

function Get-SharedGroupMembers([string] $Group) {
    <# The members of the local group, or $null when the group does not exist.  net.exe, with the error preference lowered for the call. #>
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $out = & net.exe localgroup $Group 2>&1
    $rc = $LASTEXITCODE
    $ErrorActionPreference = $prev
    if ($rc -ne 0) { return $null }
    $members = @()
    $in = $false
    foreach ($l in $out) {
        $s = [string]$l
        if ($s -match '^-{5,}') { $in = -not $in; continue }
        if ($in -and $s.Trim() -ne '' -and $s -notmatch 'command completed') { $members += $s.Trim() }
    }
    return ,$members
}

function Get-SharedVerdict {
    <# Everything the install judges by.  Returns the list of differences; empty means the shared account is as designed. #>
    param([string] $Data, [string] $UsersGroup = 'sdusers', [string] $Group = 'sdg_shared')
    $p = Get-SharedPaths $Data
    $diff = @()
    $rec = Get-SharedRecordVerdict -Record $p.Record -Dir $p.Dir -Group $Group
    if ($rec.Verdict -eq 'absent') { return @("the register record $($p.Record) does not exist") }
    if ($rec.Verdict -eq 'foreign') {
        $diff += "register line 1 is '$($rec.Line1)' (expected $($p.Dir)) and line 3 is '$($rec.Line3)' (expected $Group)"
    }
    $diff += @(Get-SharedAclProblems -Dir $p.Dir -UsersGroup $UsersGroup)
    $m = Get-SharedGroupMembers $Group
    if ($null -eq $m) { $diff += "the group $Group does not exist" }
    elseif (@($m).Count -gt 0) { $diff += "the group $Group has members ($(@($m) -join ', ')); it should have none" }
    return $diff
}

# --- dot-sourcing for tests ($SkipRun set first): define the functions and stop ------------------------------------------------------
if ($SkipRun) { return }

# --- preflight ---------------------------------------------------------------------------------------------------------------------------
if ($Preflight) {
    $p = Get-SharedPaths $DataDir
    $rec = Get-SharedRecordVerdict -Record $p.Record -Dir $p.Dir -Group $ExpectedGroup
    if ($rec.Verdict -eq 'foreign') {
        $reason = @(
            "An SD account named shared already exists, and it is not SD's own.",
            "Its register record is $($p.Record)",
            "  line 1 is '$(if ($rec.Line1) { $rec.Line1 } else { '<empty>' })' (SD's own is $($p.Dir))",
            "  line 3 is '$(if ($rec.Line3) { $rec.Line3 } else { '<empty>' })' (SD's own is $ExpectedGroup)") -join "`r`n"
        Write-Output $reason
        if ($ReasonFile) { try { Set-Content -LiteralPath $ReasonFile -Value $reason -Encoding ascii } catch { } }
        exit 4
    }
    Write-Output "make-shared: preflight ok ($($rec.Verdict))"
    exit 0
}

# --- create ------------------------------------------------------------------------------------------------------------------------------
$LogFile = Join-Path $DataDir 'make-shared.log'
function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }
Say "=== make-shared AppDir=$AppDir, DataDir=$DataDir"
$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) { Say "make-shared: no sd.exe at $sd"; exit 1 }

$paths = Get-SharedPaths $DataDir
$rec = Get-SharedRecordVerdict -Record $paths.Record -Dir $paths.Dir -Group $ExpectedGroup
if ($rec.Verdict -eq 'foreign') {
    Say "make-shared: an account named shared exists and is not SD's own (line 1 '$($rec.Line1)', line 3 '$($rec.Line3)'); it was left alone"
    exit 1
}
if ($rec.Verdict -eq 'ours') {
    $diff = @(Get-SharedVerdict -Data $DataDir -UsersGroup $UsersGroup -Group $ExpectedGroup)
    if ($diff.Count -eq 0) { Say 'make-shared: the shared account is already there and as designed; nothing to do'; exit 2 }
    Say 'make-shared: the shared account is already registered but differs from the design (secure-account-dirs.ps1 re-stamps the directory):'
    foreach ($d in $diff) { Say "  $d" }
    exit 1
}
if (Test-Path -LiteralPath $paths.Dir) {
    Say "make-shared: $($paths.Dir) exists but the shared account is not registered; it was left exactly as it is and the account was NOT made. Move or remove that directory, then install again."
    exit 1
}

. (Join-Path $PSScriptRoot 'internal-marker.ps1')

function Invoke-Sd {
    param([string[]] $SdArgs)
    $out = Join-Path $env:TEMP ("sd-shared-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-shared-err-$PID.txt")
    $marked = $false
    if (@($SdArgs).Count -gt 0 -and $SdArgs[0] -ieq '-internal') {
        $marked = Set-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') -Writer 'make-shared'
    }
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru -RedirectStandardOutput $out -RedirectStandardError $err
    $null = $p.Handle
    $exited = $p.WaitForExit(120000)
    if ($marked) { $null = Remove-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') }
    $text = ''
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) { $text += (Get-Content $f -Raw); Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
    if (-not $exited) { return [pscustomobject]@{ Code = 1; Text = "sd $SdArgs did not finish within two minutes" } }
    return [pscustomobject]@{ Code = $p.ExitCode; Text = $text.Trim() }
}

function Test-SdRunning {
    # Same test as attach-account.ps1: an sdwind that sits beside sd-solo.exe is Solo's server, not this product's.
    return $null -ne ((Get-Process sdwind -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'sdwind' -or -not ($_.Path -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $_.Path) 'sd-solo.exe'))) }))
}

$weStartedIt = $false
if (-not (Test-SdRunning)) {
    $r = Invoke-Sd @('-start')
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not (Test-SdRunning)) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-SdRunning)) {
        Say 'make-shared: SD would not start, so the shared account was not made'
        Say ('  sd -start exited {0}: {1}' -f $r.Code, $r.Text)
        exit 3
    }
    $weStartedIt = $true
}

$result = 1
try {
    $markerOk = $true
    try {
        Set-Content -LiteralPath $paths.Marker -Encoding utf8 -Value @(
            "Written by make-shared.ps1 at $(Get-Date -Format 's').",
            "It permits ONE 'CREATE.ACCOUNT GROUP shared' from an -internal session and is deleted on use.",
            'If this file is still here, the install did not finish - delete it.')
    } catch {
        $markerOk = $false
        Say "make-shared: could not write $($paths.Marker) - $($_.Exception.Message)"
    }
    if ($markerOk) {
        $r = Invoke-Sd @('-internal', 'CREATE.ACCOUNT', 'GROUP', 'shared')
        if ($r.Text) { Say $r.Text }
        $diff = @(Get-SharedVerdict -Data $DataDir -UsersGroup $UsersGroup -Group $ExpectedGroup)
        if ($diff.Count -eq 0) {
            Say "make-shared: the shared account is registered with group $ExpectedGroup, its directory is stamped, the group has no members"
            $result = 0
        } else {
            Say 'make-shared: the shared account is NOT as designed:'
            foreach ($d in $diff) { Say "  $d" }
            $result = 1
        }
    }
}
finally {
    # SHUT THE DOOR whatever happened: a marker left behind is the one failure that nothing later would notice.
    if (Test-Path -LiteralPath $paths.Marker) {
        try { Remove-Item -LiteralPath $paths.Marker -Force -ErrorAction Stop; Say 'make-shared: removed the one-shot marker' }
        catch { Say "make-shared: COULD NOT REMOVE $($paths.Marker) - delete it by hand" }
    }
    if ($weStartedIt) { $null = Invoke-Sd @('-stop') }
}
exit $result
