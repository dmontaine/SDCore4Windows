# test-shareddocs-units.ps1 - shared-docs.ps1's two judgements, on made-up input: which names a document may have, and whether the shared
# account's pdf directory is administrator-only.  Free: no SD, no install, no elevation (it stamps a folder of its own in %TEMP%).
#
#   powershell -ExecutionPolicy Bypass -File test-shareddocs-units.ps1
#
# 13 Nov 2026, RELEASE_1.1 252 (audit P-25) and 265.  WHY: the pdf directory is the one place under the shared account that must NOT inherit
# sdusers Modify (Linux: sdsys:sdusers 755), and the check that says so is what the installer believes.  So the check itself is tested:
# a directory stamped as designed passes, and one where the users group can write, or that inherits, fails BY NAME.  The users group is
# BUILTIN\Users here (the seam the installer never passes), so no SD group is needed.

$ErrorActionPreference = 'Stop'
$SkipRun = $true
. (Join-Path $PSScriptRoot 'shared-docs.ps1')

$fails = 0
$ran = 0
function Check([string] $Name, $Expected, $Actual) {
    $script:ran++
    if ($Expected -eq $Actual) { Write-Host "  [PASS] $Name" }
    else { Write-Host "  [FAIL] $Name`n         expected <$Expected>`n         actual   <$Actual>"; $script:fails++ }
}

Write-Host "test-shareddocs-units: shared-docs.ps1 at $(Join-Path $PSScriptRoot 'shared-docs.ps1')"

# --- names -------------------------------------------------------------------------------------------------------------------------------
Check 'a release changes document name is taken'        $true  (Test-DocName 'sd-core-for-windows-w2.0-0-changes.pdf')
Check 'a manual name is taken'                           $true  (Test-DocName 'user.pdf')
Check 'upper case is refused (DOCS.INSTALL would skip it)' $false (Test-DocName 'SD-Core-for-Windows-W2.0-0-User.pdf')
Check 'a leading dot is refused'                         $false (Test-DocName '.hidden.pdf')
Check 'a space is refused'                               $false (Test-DocName 'user guide.pdf')
Check 'a path separator is refused'                      $false (Test-DocName '..\x.pdf')
Check 'more than 80 characters is refused'               $false (Test-DocName (('a' * 81) + '.pdf'))

# --- the access list -----------------------------------------------------------------------------------------------------------------------
$root = Join-Path $env:TEMP ("shareddocs-test-$PID")
$null = New-Item -ItemType Directory -Path $root -Force
try {
    $users = 'Users'
    $good = Join-Path $root 'good'
    $null = New-Item -ItemType Directory -Path $good
    $a = Set-PdfDirAcl -Dir $good -Users $users
    Write-Host "         (icacls on $good exited $($a.Code))"
    $p = @(Get-PdfAclProblems -Dir $good -Users $users)
    Check 'CONTROL: a directory stamped by Set-PdfDirAcl passes (no problems)' 0 $p.Count
    if ($p.Count) { $p | ForEach-Object { Write-Host "         $_" } }

    $write = Join-Path $root 'write'
    $null = New-Item -ItemType Directory -Path $write
    $null = Set-PdfDirAcl -Dir $write -Users $users
    $null = & icacls.exe $write /grant ($users + ':(OI)(CI)(M)') 2>&1
    $p = @(Get-PdfAclProblems -Dir $write -Users $users)
    Check 'MUTANT: the users group given Modify is named as able to write' $true (@($p | Where-Object { $_ -match 'can write' }).Count -gt 0)

    $inh = Join-Path $root 'inherits'
    $null = New-Item -ItemType Directory -Path $inh
    $p = @(Get-PdfAclProblems -Dir $inh -Users $users)
    Check 'MUTANT: a directory that still inherits is named as not broken' $true (@($p | Where-Object { $_ -match 'inheritance is not broken' }).Count -gt 0)

    $p = @(Get-PdfAclProblems -Dir (Join-Path $root 'absent') -Users $users)
    Check 'NULL CASE: a directory that is not there is a problem, not a pass' $true (@($p | Where-Object { $_ -match 'no directory' }).Count -gt 0)
}
finally {
    $null = & icacls.exe $root /reset /T 2>&1
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "  ran $ran, passed $($ran - $fails), failed $fails"
if ($ran -lt 10) { Write-Host 'test-shareddocs-units: NULL CASE - fewer checks ran than written'; exit 1 }
exit $(if ($fails) { 1 } else { 0 })
