# test-deletioncheck-units.ps1 - unit tests for assert-current.ps1's
# Find-InstalledDeletions, which cannot be exercised by running the guard
# itself: on a CURRENT tree it correctly finds nothing, so a run that had
# silently stopped working would look exactly like a run that passed.
#
# 25 Aug 26 Windows port.  The gap it closes was paid for twice - GPL.BP/OPGEN
# on 24 Aug and GPL.BP/MODIFY the same day, both deleted from source while the
# install kept them and this guard said the tree matched.  HISTORY.md,
# "assert-current cannot see a deletion", has both.
#
# THE FUNCTION IS LIFTED OUT OF assert-current.ps1 BY AST, NOT COPIED, for the
# reason test-apiidentity-units.ps1 gives: a test carrying its own copy passes
# for ever while the shipped one rots.
#
# ***THE POINT OF THE FIXTURES IS THE POSITIVE CASE.*** Every real run of this
# check on a healthy tree returns nothing, so "returned nothing" is the answer
# both from a working check and from a broken one.  The only way to tell them
# apart is to plant a deletion and require it to be found, by name.
#
# Unelevated, no SD, no install, no network.  It touches nothing but %TEMP%.
# NOT a verifier: it makes no claim about the installed tree, so it is not
# named verify-* and is in neither post-cycle runner.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# $PSScriptRoot so this works from any directory, and forward slashes so the
# path carries no backslash into ParseFile (CLAUDE.md's inline-script rule).
$src = ($PSScriptRoot -replace '\\', '/') + '/assert-current.ps1'
if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "assert-current.ps1 not found beside this script ($src)"
    exit 2
}

$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tok, [ref]$err)
if ($err.Count -gt 0) {
    Write-Host "assert-current.ps1 has $($err.Count) parse error(s) - fix those first:"
    $err | ForEach-Object { Write-Host ("  {0} line {1}" -f $_.Message, $_.Extent.StartLineNumber) }
    exit 2
}
foreach ($n in @('Find-InstalledDeletions', 'Find-UnshippedAppFiles')) {
    $fn = $ast.FindAll({ param($x)
        $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $x.Name -eq $n }, $true)
    if ($fn.Count -ne 1) {
        Write-Host "expected exactly 1 '$n' in assert-current.ps1, found $($fn.Count)"
        exit 2
    }
    . ([scriptblock]::Create($fn[0].Extent.Text))
}
Write-Host "lifted 2 functions from $src"
Write-Host ''

$script:fail = 0
function Check($name, $cond, $detail) {
    if ($cond) { Write-Host "  PASS  $name" }
    else { Write-Host "  FAIL  $name  $detail"; $script:fail++ }
}

# --- fixtures --------------------------------------------------------------
# Two trees with the shape sdb_ai\sd64\sdsys and C:\ProgramData\SD\sdsys have:
# a mirrored directory holding records, and a non-mirrored one that the
# install writes into.

function New-Fixture {
    param([string[]] $Mirrors = @('gpl.bp', 'messages'))
    $root = Join-Path $env:TEMP ('sddel-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $s = Join-Path $root 'src'
    $i = Join-Path $root 'inst'
    foreach ($m in $Mirrors) {
        New-Item -ItemType Directory -Path (Join-Path $s $m) -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $i $m) -Force | Out-Null
        foreach ($rec in @('ABORT', 'CREATEF', 'LOGIN')) {
            Set-Content -LiteralPath (Join-Path (Join-Path $s $m) $rec) -Value 'x' -Encoding ascii
            Set-Content -LiteralPath (Join-Path (Join-Path $i $m) $rec) -Value 'x' -Encoding ascii
        }
    }
    # accounts is NOT a mirror - the install grows it.  Present in both trees so
    # that a check which wrongly walked it would report the extra account.
    New-Item -ItemType Directory -Path (Join-Path $s 'accounts') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $i 'accounts') -Force | Out-Null
    Set-Content -LiteralPath (Join-Path (Join-Path $s 'accounts') 'sdsys') -Value 'x' -Encoding ascii
    Set-Content -LiteralPath (Join-Path (Join-Path $i 'accounts') 'sdsys') -Value 'x' -Encoding ascii
    Set-Content -LiteralPath (Join-Path (Join-Path $i 'accounts') 'don') -Value 'x' -Encoding ascii
    return [pscustomobject]@{ Root = $root; Src = $s; Inst = $i }
}

function Remove-Fixture($f) {
    Remove-Item -LiteralPath $f.Root -Recurse -Force -ErrorAction SilentlyContinue
}

# ===========================================================================
# 1. A CURRENT TREE IS SILENT - AND SAYS HOW MUCH IT LOOKED AT
# ===========================================================================
Write-Host '1. a tree with no deletions'
$f = New-Fixture
$r = Find-InstalledDeletions -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('gpl.bp', 'messages')
Check 'nothing reported' ($r.Deleted.Count -eq 0) "got: $($r.Deleted -join ', ')"
Check 'nothing skipped' ($r.Skipped.Count -eq 0) "got: $($r.Skipped -join ', ')"
Check 'it actually opened the files (Checked = 6)' ($r.Checked -eq 6) "Checked = $($r.Checked)"
Remove-Fixture $f

# ===========================================================================
# 2. THE POSITIVE CASE.  MODIFY, THE FILE THAT STARTED THIS
# ===========================================================================
Write-Host '2. source no longer has a record the install still holds'
$f = New-Fixture
Set-Content -LiteralPath (Join-Path (Join-Path $f.Inst 'gpl.bp') 'MODIFY') -Value 'x' -Encoding ascii
$r = Find-InstalledDeletions -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('gpl.bp', 'messages')
Check 'exactly one deletion found' ($r.Deleted.Count -eq 1) "got: $($r.Deleted -join ', ')"
Check 'it is named, with its directory' ($r.Deleted -contains 'gpl.bp\MODIFY') "got: $($r.Deleted -join ', ')"
Remove-Fixture $f

# ===========================================================================
# 3. A DELETION IN A SUBDIRECTORY IS STILL FOUND
# ===========================================================================
Write-Host '3. a deletion below the top level'
$f = New-Fixture
New-Item -ItemType Directory -Path (Join-Path (Join-Path $f.Inst 'messages') 'sub') -Force | Out-Null
Set-Content -LiteralPath (Join-Path (Join-Path (Join-Path $f.Inst 'messages') 'sub') 'GONE') -Value 'x' -Encoding ascii
$r = Find-InstalledDeletions -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('gpl.bp', 'messages')
Check 'the nested file is reported with its relative path' ($r.Deleted -contains 'messages\sub\GONE') "got: $($r.Deleted -join ', ')"
Remove-Fixture $f

# ===========================================================================
# 4. THE CRY-WOLF CASE.  accounts GROWS, AND IS NOT A MIRROR
# ===========================================================================
Write-Host '4. a directory the install writes into is not walked'
$f = New-Fixture
$r = Find-InstalledDeletions -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('gpl.bp', 'messages')
Check "the extra account is NOT reported" (-not ($r.Deleted -like '*don*')) "got: $($r.Deleted -join ', ')"
# ...and the control: if it WERE listed as a mirror, it would be reported.  A
# check that stayed silent here would be silent because it does nothing.
$r2 = Find-InstalledDeletions -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('accounts')
Check 'CONTROL: listing accounts as a mirror DOES report it' ($r2.Deleted -contains 'accounts\don') "got: $($r2.Deleted -join ', ')"
Remove-Fixture $f

# ===========================================================================
# 5. A CASE-ONLY RENAME IS B2'S, NOT THIS CHECK'S
# ===========================================================================
Write-Host '5. a case-only rename is not reported twice'
$f = New-Fixture
Remove-Item -LiteralPath (Join-Path (Join-Path $f.Inst 'gpl.bp') 'LOGIN')
Set-Content -LiteralPath (Join-Path (Join-Path $f.Inst 'gpl.bp') 'login') -Value 'x' -Encoding ascii
$r = Find-InstalledDeletions -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('gpl.bp', 'messages')
Check 'no deletion reported for a case-only difference' ($r.Deleted.Count -eq 0) "got: $($r.Deleted -join ', ')"
Remove-Fixture $f

# ===========================================================================
# 6. IT CANNOT REPORT CLEAN WHEN IT COULD NOT LOOK
# ===========================================================================
Write-Host '6. a mirror directory that is not there'
$f = New-Fixture
$r = Find-InstalledDeletions -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('gpl.bp', 'nosuchdir')
Check 'the missing directory is reported as skipped' ($r.Skipped -contains 'nosuchdir') "got: $($r.Skipped -join ', ')"
Check 'the directory that IS there was still walked' ($r.Checked -eq 3) "Checked = $($r.Checked)"

Remove-Item -LiteralPath (Join-Path $f.Inst 'messages') -Recurse -Force
$r = Find-InstalledDeletions -SourceSys $f.Src -InstallSys $f.Inst -Mirrors @('gpl.bp', 'messages')
Check 'a mirror missing from the INSTALL is skipped, not passed' ($r.Skipped -contains 'messages') "got: $($r.Skipped -join ', ')"
Remove-Fixture $f

# ===========================================================================
# 7. THE {app} HALF - Find-UnshippedAppFiles
#
# Inno's [Files] copies and overwrites but never removes a file that is absent
# from the new version, so a script dropped from stage.py stays in
# C:\Program Files\SD until somebody uninstalls.  This is what notices.
# ===========================================================================
Write-Host '7. leftover files in {app}'
$appDir = Join-Path $env:TEMP ('sdapp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $appDir -Force | Out-Null
foreach ($n in @('deny-logon.ps1', 'install-ssh.ps1', 'changelog',
                 'unins000.exe', 'unins000.dat')) {
    Set-Content -LiteralPath (Join-Path $appDir $n) -Value 'x' -Encoding ascii
}
New-Item -ItemType Directory -Path (Join-Path $appDir 'usr') -Force | Out-Null
Set-Content -LiteralPath (Join-Path (Join-Path $appDir 'usr') 'sd.exe') -Value 'x' -Encoding ascii

# The real valve is a scriptblock over the text of stage.py and sd.iss; these
# stand in for it so the test does not depend on what those files say today.
$shipsAll  = { param($n) $true }
$shipsSome = { param($n) $n -ne 'install-ssh.ps1' }

$a = Find-UnshippedAppFiles -AppRoot $appDir -ShipsAs $shipsAll
Check 'nothing reported when everything ships' ($a.Orphans.Count -eq 0) "got: $($a.Orphans -join ', ')"
Check "Inno's uninstaller is not counted (Checked = 3)" ($a.Checked -eq 3) "Checked = $($a.Checked)"
Check 'unins000.exe is not reported' (-not ($a.Orphans -contains 'unins000.exe')) "got: $($a.Orphans -join ', ')"
Check 'usr\sd.exe is not descended into' (-not ($a.Orphans -contains 'sd.exe')) "got: $($a.Orphans -join ', ')"

$b = Find-UnshippedAppFiles -AppRoot $appDir -ShipsAs $shipsSome
Check 'CONTROL: a retired script IS reported' ($b.Orphans -contains 'install-ssh.ps1') "got: $($b.Orphans -join ', ')"
Check 'and only that one' ($b.Orphans.Count -eq 1) "got: $($b.Orphans -join ', ')"

Remove-Item -LiteralPath $appDir -Recurse -Force -ErrorAction SilentlyContinue

$empty = Join-Path $env:TEMP ('sdapp-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $empty -Force | Out-Null
$c = Find-UnshippedAppFiles -AppRoot $empty -ShipsAs $shipsAll
Check 'an empty {app} reports Checked = 0, which the caller refuses' ($c.Checked -eq 0) "Checked = $($c.Checked)"
Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
if ($script:fail -gt 0) {
    Write-Host "$($script:fail) check(s) FAILED"
    exit 1
}
Write-Host 'all checks passed'
exit 0
