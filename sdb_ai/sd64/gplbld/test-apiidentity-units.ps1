# test-apiidentity-units.ps1 - unit tests for verify-apiidentity.ps1's two
# helpers, neither of which can be exercised by running the verifier itself
# without spending a -Prefix token and a UAC click.
#
# 24 Aug 26 Windows port.  Both tests exist because the bug they cover was
# PAID FOR: Get-WhoAccounts' pattern cost run b24, and Set-FixtureAcl's
# ordering cost b25 and b26 and was written up as a product finding before
# being retracted.  PROJECT_STATUS.md section 6 has both traps.
#
# THE FUNCTIONS ARE LIFTED OUT OF THE VERIFIER BY AST, NOT COPIED.  A test
# carrying its own copy of the pattern passes for ever while the shipped one
# rots - the same reasoning verify-allowgroups.ps1 uses to parse the script it
# tests rather than restating its functions.
#
# Unelevated, no SD, no account, no network, no install.  It touches nothing
# but %TEMP%.  NOT a verifier: it makes no claim about the installed tree, so
# it is not named verify-* and is not in either post-cycle runner.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

# $PSScriptRoot so this works from any directory, and forward slashes so the
# path carries no backslash into ParseFile (CLAUDE.md's inline-script rule).
$src = ($PSScriptRoot -replace '\\', '/') + '/verify-apiidentity.ps1'
if (-not (Test-Path -LiteralPath $src)) {
    Write-Host "verify-apiidentity.ps1 not found beside this script ($src)"
    exit 2
}

$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$tok, [ref]$err)
if ($err.Count -gt 0) {
    Write-Host "verify-apiidentity.ps1 has $($err.Count) parse error(s) - fix those first:"
    $err | ForEach-Object { Write-Host ("  {0} line {1}" -f $_.Message, $_.Extent.StartLineNumber) }
    exit 2
}
foreach ($n in @('Fail', 'Invoke-Icacls', 'Assert-Icacls', 'Set-FixtureAcl', 'Get-WhoAccounts')) {
    $fn = $ast.FindAll({ param($x)
        $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq $n }, $true)
    if ($fn.Count -ne 1) {
        Write-Host "expected exactly 1 '$n' in verify-apiidentity.ps1, found $($fn.Count)"
        exit 2
    }
    . ([scriptblock]::Create($fn[0].Extent.Text))
}
Write-Host "lifted 5 functions from $src"
Write-Host ''

$script:fail = 0
function Check($name, $expected, $got) {
    $e = ($expected -join ','); $g = ($got -join ',')
    if ($e -eq $g) { Write-Host "  PASS  $name  -> [$g]" }
    else { Write-Host "  FAIL  $name  expected [$e] got [$g]"; $script:fail++ }
}

# ===========================================================================
# 1. Get-WhoAccounts
# ===========================================================================
Write-Host '-- Get-WhoAccounts --'

# The exact b24 Step 3d transcript.  The old pattern read the two COPY success
# lines as WHO reports and returned DON,SDAPIIDB24,record(s),record(s),...
$step3d = @"
:WHO
47 DON

:LOGTO SDAPIIDB24
:WHO
48 SDAPIIDB24 from DON

:COPY FROM ZZIDSRC TO VOC ZZIDALLOW OVERWRITING
1 record(s) copied.

:COPY FROM ZZIDSRC TO VOC ZZIDDENY OVERWRITING
1 record(s) copied.

:WHO
48 SDAPIIDB24 from DON
"@
Check 'b24 Step 3d transcript' @('DON','SDAPIIDB24','SDAPIIDB24') (Get-WhoAccounts $step3d)

$step3a = @"
:WHO
47 DON
:WHO
47 SDAPIIDB24 from DON
Created DATA part as ZZIDALLOW
Added default '@ID' record to dictionary
:WHO
47 SDAPIIDB24 from DON
"@
Check 'b24 Step 3a transcript' @('DON','SDAPIIDB24','SDAPIIDB24') (Get-WhoAccounts $step3a)

# NEGATIVE CONTROL - the lines that caused b24, alone.
Check 'COPY success lines alone' @() (Get-WhoAccounts "1 record(s) copied.`n0 record(s) copied.`n12 record(s) copied.")

# POSITIVE CONTROLS - a pattern matching NOTHING would pass the negative
# control and silently disable the account check the verifier relies on.
Check 'bare WHO'      @('DON')        (Get-WhoAccounts '47 DON')
Check 'WHO with from' @('SDAPIIDB24') (Get-WhoAccounts '48 SDAPIIDB24 from DON')

# CASE CONTROL - if (?i) ever creeps back, [A-Z] matches the "r" of record(s)
# and b24 returns.
Check 'lower-case token rejected' @() (Get-WhoAccounts '1 record(s) copied.')

# ===========================================================================
# 2. Set-FixtureAcl
# ===========================================================================
Write-Host ''
Write-Host '-- Set-FixtureAcl --'

$me   = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$base = Join-Path $env:TEMP ('sdfxacl-' + [Guid]::NewGuid().ToString('N').Substring(0,8))
$dest = Join-Path $base 'useronly'
$root = Join-Path $dest 'ZZIDUSER'
try {
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    New-Item -ItemType Directory -Force -Path (Join-Path $dest 'ZZIDUSER.DIC') | Out-Null
    foreach ($b in @('%0', '%1')) { Set-Content -LiteralPath (Join-Path $root $b) -Value 'x' }
    Set-Content -LiteralPath (Join-Path (Join-Path $dest 'ZZIDUSER.DIC') '%0') -Value 'x'

    # The stand-in for the inherited sdusers:(M) that leaked onto %0 in b25.
    # It is granted on the PARENT and must not survive on the children.
    $null = & icacls.exe $base /grant 'Users:(OI)(CI)(M)' /C 2>&1

    $files = @(Get-ChildItem -LiteralPath $dest -Recurse -Force -File | ForEach-Object { $_.FullName })
    if ($files.Count -ne 3) { Write-Host "  FAIL  expected 3 files, built $($files.Count)"; $script:fail++ }

    Set-FixtureAcl $dest @('SYSTEM:(OI)(CI)(F)', 'Administrators:(OI)(CI)(F)', "${me}:(OI)(CI)(RX)") $true 'dirs'
    foreach ($f in $files) { Set-FixtureAcl $f @("${me}:(RX)") $false (Split-Path -Leaf $f) }

    foreach ($f in $files) {
        $names = $null
        try { $names = @((Get-Acl -LiteralPath $f).Access | ForEach-Object { $_.IdentityReference.Value }) }
        catch { Write-Host "  FAIL  $f unreadable: $($_.Exception.GetType().Name)"; $script:fail++; continue }
        $leak = @($names | Where-Object {
            $_ -match '\\Users$' -or $_ -match 'NT AUTHORITY\\SYSTEM$' -or $_ -match '\\Administrators$' })
        if ($leak.Count -gt 0) {
            Write-Host ("  FAIL  {0} leaked: {1}" -f (Split-Path -Leaf $f), ($leak -join ', ')); $script:fail++
        } else {
            Write-Host ("  PASS  {0} [{1}]" -f (Split-Path -Leaf $f), ($names -join '; '))
        }
    }
} finally {
    if (Test-Path -LiteralPath $base) {
        foreach ($p in @(Get-ChildItem -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue |
                         ForEach-Object { $_.FullName })) {
            $null = & icacls.exe $p /grant "${me}:(F)" /C 2>&1
        }
        $null = & icacls.exe $base /reset /T /C 2>&1
        Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
    }
    Write-Host ("  cleanup removed the tree: " + (-not (Test-Path -LiteralPath $base)))
}

Write-Host ''
if ($script:fail -gt 0) {
    Write-Host "test-apiidentity-units: FAILED - $($script:fail) check(s)."
    exit 1
}
Write-Host 'test-apiidentity-units: all checks passed'
exit 0
