# shared-docs.ps1 - the shared account's documentation: its pdf directory, the changes document and the manuals, at install and at upgrade.
#
#   powershell -ExecutionPolicy Bypass -File shared-docs.ps1 -AppDir <app> -DataDir <data> -SourceDir <the installer's own folder>
#
# 13 Nov 2026, RELEASE_1.1 252 (audit P-25) with row 265: the Windows half of Linux installsdcore.sh's SHARED-CONTENT (the pdf directory),
# CHANGES-DOC (owner, 24 Oct 2026: the changes document "upon installation also copied into the 'shared' directory") and MANUALS-PDF
# (S.143, owner, 3 Nov 2026: "Yes, installer copies them").  The help box's line "More in the documentation: <page>.pdf, in the pdf
# directory of the shared account" (message 15046) is true only once this has run.
#
#   1. THE DIRECTORY.  <shared>\pdf, made if missing, with its OWN access list: inheritance broken, SYSTEM and Administrators Full,
#      sdusers Read & execute, all (OI)(CI) - Linux's sdsys:sdusers 755, so no SD user can add, change or remove a document.  The
#      shared directory itself gives sdusers Modify, which is why the subdirectory must not inherit it.  Stamped at every install.
#   2. THE CHANGES DOCUMENT.  sd-core-for-windows-<version>-changes.pdf / .html / .md beside the installer, copied into the directory.
#      A name that is not lower case letters, digits and . _ - is not copied and is named.
#   3. THE MANUALS.  The pdf folder beside the installer, handed to SD's own DOCS.INSTALL (an -internal session), which judges every
#      file: a lower case name ending .pdf, a file that starts with %PDF-.
#
# NEVER STOPS THE INSTALL.  Exit codes, and sd.iss says something only for 1:
#   0  done (the directory is as designed; whatever lay beside the installer was copied)
#   2  there is no shared account, so there is nowhere to put documents
#   1  anything else: the directory could not be made or stamped, a copy failed, DOCS.INSTALL did not report success
# A missing changes document or pdf folder is NOT a failure: an installer run from a build folder has neither.
#
# THE VERDICTS ARE DRAWN FROM WHAT THE SYSTEM NOW HOLDS (the instrument rule): the access list entry by entry after it is set, each
# copied file's presence, and DOCS.INSTALL's success line (message 12727), never its exit code (sd exits 0 when a verb refuses).

[CmdletBinding()]
param(
    [string] $AppDir = '',
    [string] $DataDir = 'C:\ProgramData\SD',
    [string] $SourceDir = '',
    # Test seam: the users group the directory is read by.  The installer never passes it.
    [string] $UsersGroup = 'sdusers'
)

$ErrorActionPreference = 'Continue'
$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"

function Test-DocName([string] $Name) {
    # The names DOCS.INSTALL takes (Linux's rule): a-z 0-9 . _ - only, not starting with a dot, at most 80 characters.
    return ($Name -cmatch '^[a-z0-9][a-z0-9._-]{0,79}$')
}

function Get-PdfAclProblems {
    <#
      The pdf directory's access list against the design, ENTRY BY ENTRY.  Returns the differences (empty = right): inheritance broken;
      exactly SYSTEM (S-1-5-18) Full, Administrators (S-1-5-32-544) Full and the users group Read & execute; every entry Allow and
      (OI)(CI); the users group with no write right.  By SID, because the built-ins are renamed on a localised Windows.
    #>
    param([string] $Dir, [string] $Users = 'sdusers')
    $problems = @()
    if (-not (Test-Path -LiteralPath $Dir)) { return @("no directory $Dir") }
    $acl = Get-Acl -LiteralPath $Dir
    if (-not $acl.AreAccessRulesProtected) { $problems += 'inheritance is not broken (the shared directory''s Modify for sdusers would be inherited)' }
    try {
        $usersSid = ([System.Security.Principal.NTAccount]$Users).Translate([System.Security.Principal.SecurityIdentifier]).Value
    } catch {
        return @($problems + "the group $Users does not exist")
    }
    $full = [System.Security.AccessControl.FileSystemRights]::FullControl
    $rx = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
    $writeBits = [int]([System.Security.AccessControl.FileSystemRights]::WriteData -bor [System.Security.AccessControl.FileSystemRights]::AppendData -bor
                       [System.Security.AccessControl.FileSystemRights]::Delete -bor [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
                       [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor [System.Security.AccessControl.FileSystemRights]::TakeOwnership)
    $want = @{ 'S-1-5-18' = $full; 'S-1-5-32-544' = $full }
    $want[$usersSid] = $rx
    $seen = @{}
    foreach ($r in $acl.Access) {
        $sid = $r.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        if (-not $want.ContainsKey($sid)) { $problems += "unexpected entry for $($r.IdentityReference) ($($r.FileSystemRights))"; continue }
        if ($r.AccessControlType -ne 'Allow') { $problems += "entry for $($r.IdentityReference) is $($r.AccessControlType)" }
        if ($r.InheritanceFlags -ne 'ContainerInherit, ObjectInherit') { $problems += "entry for $($r.IdentityReference) is not (OI)(CI): $($r.InheritanceFlags)" }
        $rights = [int]$r.FileSystemRights
        if (($rights -band [int]$want[$sid]) -ne [int]$want[$sid]) { $problems += "entry for $($r.IdentityReference) is $($r.FileSystemRights), expected $($want[$sid])" }
        if ($sid -eq $usersSid -and ($rights -band $writeBits) -ne 0) { $problems += "entry for $($r.IdentityReference) can write ($($r.FileSystemRights)); it must only read" }
        $seen[$sid] = $true
    }
    foreach ($sid in $want.Keys) { if (-not $seen.ContainsKey($sid)) { $problems += "no entry for $sid" } }
    return $problems
}

function Set-PdfDirAcl([string] $Dir, [string] $Users) {
    # /inheritance:r and every grant in ONE command (secure-account-dirs.ps1's form), so there is no moment with neither.
    $out = & icacls.exe $Dir /inheritance:r `
        /grant '*S-1-5-18:(OI)(CI)(F)' `
        /grant '*S-1-5-32-544:(OI)(CI)(F)' `
        /grant ($Users + ':(OI)(CI)(RX)') 2>&1
    return [pscustomobject]@{ Code = $LASTEXITCODE; Text = (($out | ForEach-Object { "$_" }) -join ' ').Trim() }
}

# --- dot-sourcing for tests ($SkipRun set first): define the functions and stop ------------------------------------------------------
if ($SkipRun) { return }

$LogFile = Join-Path $DataDir 'shared-docs.log'
function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }
Say "=== shared-docs AppDir=$AppDir, DataDir=$DataDir, SourceDir=$SourceDir  $(Get-Date -Format 's')"
$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) { Say "shared-docs: no sd.exe at $sd"; exit 1 }

$record = Join-Path $DataDir 'sdsys\accounts\shared'
$shared = Join-Path $DataDir 'group_accounts\shared'
if (-not (Test-Path -LiteralPath $record) -or -not (Test-Path -LiteralPath $shared)) {
    Say "shared-docs: there is no shared account ($record, $shared), so its documentation directory was not set up"
    exit 2
}

$result = 0

# 1. the directory and its access list
$pdf = Join-Path $shared 'pdf'
if (-not (Test-Path -LiteralPath $pdf)) {
    try { $null = New-Item -ItemType Directory -Path $pdf -ErrorAction Stop; Say "shared-docs: made $pdf" }
    catch { Say "shared-docs: could not make $pdf - $($_.Exception.Message)"; exit 1 }
}
$a = Set-PdfDirAcl -Dir $pdf -Users $UsersGroup
Say ("shared-docs: icacls {0} exited {1}: {2}" -f $pdf, $a.Code, $a.Text)
$problems = @(Get-PdfAclProblems -Dir $pdf -Users $UsersGroup)
if ($problems.Count -eq 0) {
    Say "shared-docs: $pdf is SYSTEM and Administrators Full, $UsersGroup Read & execute, inheritance broken"
} else {
    Say "shared-docs: $pdf is NOT as designed:"
    foreach ($p in $problems) { Say "  $p" }
    exit 1
}

# 2. the changes document beside the installer
if ($SourceDir -and (Test-Path -LiteralPath $SourceDir)) {
    $seen = 0; $copied = 0
    foreach ($pat in @('sd-core-for-windows-*-changes.pdf', 'sd-core-for-windows-*-changes.html', 'sd-core-for-windows-*-changes.md')) {
        foreach ($f in @(Get-ChildItem -LiteralPath $SourceDir -Filter $pat -File -ErrorAction SilentlyContinue)) {
            if ($f.Attributes -band [System.IO.FileAttributes]::ReparsePoint) { Say "shared-docs: $($f.Name) is a link and was not copied"; continue }
            $seen++
            if (-not (Test-DocName $f.Name)) { Say "shared-docs: $($f.Name) was not copied: the name must be lower case letters, digits and . _ -"; $result = 1; continue }
            $to = Join-Path $pdf $f.Name
            try { Copy-Item -LiteralPath $f.FullName -Destination $to -Force -ErrorAction Stop } catch { }
            if (Test-Path -LiteralPath $to) { $copied++; Say "shared-docs: copied $($f.Name)" }
            else { Say "shared-docs: $($f.Name) was NOT copied into $pdf"; $result = 1 }
        }
    }
    if ($seen -eq 0) { Say "shared-docs: no changes document beside the installer ($SourceDir), so none was copied" }
    else { Say "shared-docs: the changes document: $copied of $seen file(s) copied" }
} else {
    Say 'shared-docs: no installer folder was given, so no changes document was copied'
}

# 3. the manuals, through DOCS.INSTALL
$srcPdf = if ($SourceDir) { Join-Path $SourceDir 'pdf' } else { '' }
$nPdf = if ($srcPdf -and (Test-Path -LiteralPath $srcPdf)) { @(Get-ChildItem -LiteralPath $srcPdf -Filter '*.pdf' -File -ErrorAction SilentlyContinue).Count } else { 0 }
if ($nPdf -eq 0) {
    Say "shared-docs: no documentation PDFs beside the installer ($srcPdf); an administrator can add them later in SDSYS:  docs.install <folder of PDFs>"
    exit $result
}
Say "shared-docs: $nPdf PDF(s) in $srcPdf, handed to DOCS.INSTALL"

. (Join-Path $PSScriptRoot 'internal-marker.ps1')

function Invoke-Sd {
    param([string[]] $SdArgs)
    $out = Join-Path $env:TEMP ("sd-docs-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-docs-err-$PID.txt")
    $marked = $false
    if (@($SdArgs).Count -gt 0 -and $SdArgs[0] -ieq '-internal') {
        $marked = Set-SdInternalMarker -SdsysDir (Join-Path $DataDir 'sdsys') -Writer 'shared-docs'
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
    # Same test as make-shared.ps1: an sdwind beside sd-solo.exe is Solo's server, not this product's.
    return $null -ne ((Get-Process sdwind -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'sdwind' -or -not ($_.Path -and (Test-Path -LiteralPath (Join-Path (Split-Path -Parent $_.Path) 'sd-solo.exe'))) }))
}

$weStartedIt = $false
if (-not (Test-SdRunning)) {
    $r = Invoke-Sd @('-start')
    $deadline = (Get-Date).AddSeconds(20)
    while ((Get-Date) -lt $deadline -and -not (Test-SdRunning)) { Start-Sleep -Milliseconds 500 }
    if (-not (Test-SdRunning)) {
        Say 'shared-docs: SD would not start, so the manuals were not copied'
        Say ('  sd -start exited {0}: {1}' -f $r.Code, $r.Text)
        exit 1
    }
    $weStartedIt = $true
}
try {
    # One argument: DOCS.INSTALL takes the rest of the sentence as the directory, quotes allowed.
    $r = Invoke-Sd @('-internal', ('DOCS.INSTALL "' + $srcPdf + '"'))
    if ($r.Text) { Say $r.Text }
    if ($r.Text -match 'Copied \d+ document\(s\) into the shared account; skipped (\d+)') {
        if ([int]$Matches[1] -gt 0) { Say "shared-docs: DOCS.INSTALL skipped $($Matches[1]) file(s), named above"; $result = 1 }
        else { Say 'shared-docs: the manuals are in the shared account' }
    } else {
        Say ('shared-docs: DOCS.INSTALL did not report success (exit {0})' -f $r.Code)
        $result = 1
    }
}
finally {
    if ($weStartedIt) { $null = Invoke-Sd @('-stop') }
}
exit $result
