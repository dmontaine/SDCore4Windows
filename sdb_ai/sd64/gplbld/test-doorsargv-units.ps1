# test-doorsargv-units.ps1 - unit test for verify-doors-suite.ps1's elevation
# argument list.  Needs NO install, NO elevation and NO account, so it costs
# nothing to run and can run before the suite is handed to anybody.
#
# START-HISTORY:
# 28 Aug 2026  Written after the -Run b50 suite run.  Create elevated and
#              passed 8/8; Suspend and Remove died before the UAC prompt with
#              "Cannot validate argument on parameter 'ArgumentList'.  The
#              argument is null or empty", leaving the account unsuspended so
#              the Refused leg could not run at all.
# END-HISTORY
#
# ***WHAT IT GUARDS.***  Start-Process's -ArgumentList carries
# [ValidateNotNullOrEmpty()], and on a COLLECTION that attribute validates
# every ELEMENT as well as the collection itself.  One '' therefore rejects
# the WHOLE list and nothing is launched.  verify-doors-suite.ps1 passed
# '-Password', $Password unconditionally, and Suspend and Remove take no
# password (verify-doors-admin.ps1:58 defaults it to ''), so those two legs
# could never elevate.
#
# ***THE REJECTION WAS MEASURED ON THE LIVE CMDLET, NOT REASONED.***  On
# 28 Aug 2026, PowerShell 5.1.26100.9168:
#
#     Start-Process powershell.exe -ArgumentList @('-NoProfile','-Command','exit 0') -WhatIf
#         -> "A parameter cannot be found that matches parameter name 'WhatIf'"
#            i.e. -ArgumentList BOUND; the error is about a later parameter
#     Start-Process powershell.exe -ArgumentList @('-NoProfile','-Password','') -WhatIf
#         -> "Cannot validate argument on parameter 'ArgumentList'..."
#            i.e. -ArgumentList REFUSED, and the only difference is the ''
#
# Launching nothing is the point of a unit test, so the rows below check
# acceptance through Test-ArgvAcceptance, a proxy carrying the SAME attribute
# on the SAME type.  The control row proves the proxy can still tell the
# defect from the fix.
#
# ***IT TESTS THE SHIPPED FUNCTION, NOT A COPY OF IT.***  Invoke-ElevatedPhase
# is lifted out of verify-doors-suite.ps1 by the PowerShell PARSER and defined
# here verbatim; there is no second copy of the argument list to drift.  If
# the function cannot be found the test FAILS - a run that measured nothing
# must not score green.

[CmdletBinding()]
param(
    # ***-Suite EXISTS SO THE FIX CAN HAVE A POSITIVE CONTROL.***  Point it at
    # a copy carrying the OLD unconditional '-Password', $Password and this
    # file must go RED; a test that cannot fail on the defect is not measuring
    # the fix.  RUN AND OBSERVED FAILING that way on 28 Aug 2026: 27 passed,
    # 8 failed - four rows each for Suspend and Remove (element count 15 not
    # 13, -Password present, one empty element, and the list refused).  The
    # fixed file scores 35 of 35.  Default is the real file beside this one.
    [string] $Suite = ''
)

$ErrorActionPreference = 'Stop'

$pass = 0
$fail = 0

function Note([bool]$ok, [string]$what, [string]$detail = '') {
    if ($ok) { $script:pass++ } else { $script:fail++ }
    $line = "  [{0}] {1}" -f $(if ($ok) { 'PASS' } else { 'FAIL' }), $what
    if ($detail -ne '') { $line += " -- $detail" }
    Write-Output $line
}

# The proxy: same attribute, same parameter type as Start-Process -ArgumentList.
function Test-ArgvAcceptance {
    param([ValidateNotNullOrEmpty()] [string[]] $ArgumentList)
    return $true
}

function Would-Accept($argv) {
    try { $null = Test-ArgvAcceptance -ArgumentList $argv; return $true }
    catch { return $false }
}

Write-Output ''
Write-Output 'test-doorsargv-units: verify-doors-suite.ps1 elevation argv'
Write-Output ("  shell     {0}, elevated={1}" -f $PSVersionTable.PSVersion,
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
     ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator))

# --- 0. THE CONTROL: the proxy must still reject the defect -----------------
# Without this the whole file could pass by accepting everything.
$defectArgv = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', 'x.ps1',
                '-Prefix', 'sddrb99', '-Phase', 'Suspend', '-Password', '',
                '-Out', 'y.log')
Note (-not (Would-Accept $defectArgv)) 'CONTROL: the old unconditional -Password form is REJECTED' `
     'one empty element, 13 in all'
Note (Would-Accept @('-NoProfile', '-Phase', 'Suspend')) 'CONTROL: a list with no empty element is ACCEPTED'

# --- 1. Lift the real function out of the real file -------------------------
$suitePath = $(if ($Suite -ne '') { $Suite } else { Join-Path $PSScriptRoot 'verify-doors-suite.ps1' })
if (-not (Test-Path -LiteralPath $suitePath)) {
    Write-Output ''
    Write-Output ("REFUSING - no such file: {0}" -f $suitePath)
    exit 2
}
# Forward slashes: the parser call then carries no backslash of its own.
$forParser = $suitePath -replace '\\', '/'
Write-Output ''
Write-Output ("  parsing   {0}" -f $forParser)

$tokens = $null; $perrs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($forParser, [ref]$tokens, [ref]$perrs)
Note ($perrs.Count -eq 0) 'verify-doors-suite.ps1 parses' ("{0} parse error(s)" -f $perrs.Count)
if ($perrs.Count -gt 0) { $perrs | ForEach-Object { Write-Output ('      ' + $_) } }

$fn = $ast.FindAll({ param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $n.Name -eq 'Invoke-ElevatedPhase' }, $true) | Select-Object -First 1

Note ($null -ne $fn) 'Invoke-ElevatedPhase found in the file'
if ($null -eq $fn) {
    Write-Output ''
    Write-Output 'REFUSING - the function under test is not there, so nothing below measured anything.'
    exit 2
}
Invoke-Expression $fn.Extent.Text

# --- 2. The stub, and the script-scope state the function reads --------------
$script:capturedArgv = $null
function Start-Process {
    param([string] $FilePath, [string] $Verb, [switch] $Wait, [switch] $PassThru,
          [object] $ArgumentList)
    $script:capturedArgv = @($ArgumentList)
    return [pscustomobject]@{ ExitCode = 0 }
}

# ***SET EXPLICITLY, BECAUSE THE LIFT DOES NOT BRING THE INITIALISER.***  Only
# the FUNCTION is parsed out of the suite, so the script-scope state it reads
# has to be built here.  An unset $helperPipe is $null, and the suite's guard
# is IsNullOrEmpty precisely so that a run in that state does not take the
# helper branch - this file is what found that.  Empty means "no helper is
# serving", which is the route the argv rows below are about.
$script:helperPipe = ''
$stamp  = 'unittest'
$admin  = Join-Path $PSScriptRoot 'verify-doors-admin.ps1'
$Prefix = 'sddrunit'
$logDir = Join-Path $env:TEMP ('sd-doors-argv-log-' + [guid]::NewGuid().ToString('N'))
$work   = Join-Path $env:TEMP ('sd-doors-argv-'     + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $logDir | Out-Null
New-Item -ItemType Directory -Path $work   | Out-Null

function Argv-For([string]$Phase, [string]$Password) {
    $script:capturedArgv = $null
    $script:phaseExit    = 2
    Invoke-ElevatedPhase $Phase $Password | Out-Null
    return $script:capturedArgv
}

try {
    # --- 3. Create CARRIES a password ---------------------------------------
    $pw   = 'Doors!Unit9'
    $argv = Argv-For 'Create' $pw
    Note ($null -ne $argv) 'Create: Start-Process was reached'
    if ($null -ne $argv) {
        Note ($argv.Count -eq 15) 'Create: argv has 15 elements' ("got {0}" -f $argv.Count)
        Note ($argv -contains '-Password') 'Create: -Password is present'
        $i = [array]::IndexOf($argv, '-Password')
        Note ($i -ge 0 -and $argv[$i + 1] -eq $pw) 'Create: the password follows its switch'
        Note (Would-Accept $argv) 'Create: Start-Process would accept the list'
        Note ($script:phaseExit -eq 0) 'Create: the child exit code is read back' ("phaseExit={0}" -f $script:phaseExit)
    }

    # --- 4. Suspend and Remove OMIT it, and this is the regression -----------
    foreach ($ph in @('Suspend', 'Remove')) {
        $argv = Argv-For $ph ''
        Note ($null -ne $argv) ("{0}: Start-Process was reached" -f $ph) `
             'the b50 defect never got here'
        if ($null -ne $argv) {
            Note ($argv.Count -eq 13) ("{0}: argv has 13 elements" -f $ph) ("got {0}" -f $argv.Count)
            Note (-not ($argv -contains '-Password')) ("{0}: -Password is omitted, not empty" -f $ph)
            $empty = @($argv | Where-Object { [string]::IsNullOrEmpty($_) })
            Note ($empty.Count -eq 0) ("{0}: no empty element" -f $ph) ("{0} empty" -f $empty.Count)
            Note (Would-Accept $argv) ("{0}: Start-Process would accept the list" -f $ph)
            Note ($script:phaseExit -eq 0) ("{0}: the child exit code is read back" -f $ph) `
                 ("phaseExit={0}" -f $script:phaseExit)
        }
    }

    # --- 5. Every leg still names its own -Phase and -Out --------------------
    foreach ($ph in @('Create', 'Suspend', 'Remove')) {
        $argv = Argv-For $ph $(if ($ph -eq 'Create') { $pw } else { '' })
        $i = [array]::IndexOf($argv, '-Phase')
        Note ($i -ge 0 -and $argv[$i + 1] -eq $ph) ("{0}: -Phase carries its own name" -f $ph)
        $j = [array]::IndexOf($argv, '-Out')
        Note ($j -ge 0 -and $argv[$j + 1] -like ("*{0}*" -f $ph.ToLower())) `
             ("{0}: -Out names this phase's log" -f $ph) $(if ($j -ge 0) { $argv[$j + 1] } else { 'absent' })
    }

    # --- 5b. THE HELPER ROUTE'S LAUNCHER ------------------------------------
    # 28 Aug 2026.  The default route sends a SELF-CONTAINED launcher to a
    # resident elevated helper, because that helper passes no arguments.  The
    # argv rows above stop covering the default path the moment it changes, so
    # the generator gets its own rows: the secret must be present (it cannot be
    # passed any other way), the -Password switch must be ABSENT for the two
    # phases that take none, and the apostrophe guard must refuse rather than
    # emit a broken script.
    $genFn = $ast.FindAll({ param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $n.Name -eq 'New-SelfContainedLauncher' }, $true) | Select-Object -First 1
    Note ($null -ne $genFn) 'New-SelfContainedLauncher found in the file'
    if ($null -ne $genFn) {
        Invoke-Expression $genFn.Extent.Text

        $outC = Join-Path $logDir 'create.log'
        $lC   = New-SelfContainedLauncher 'Create' $pw $outC
        Note ($lC -ne '') 'helper/Create: a launcher was written'
        if ($lC -ne '') {
            $body = (Get-Content -LiteralPath $lC -Raw)
            Note ($body -like "*$pw*") 'helper/Create: the password IS in the launcher' `
                 'it cannot be an argument - the helper passes none'
            Note ($body -like '*-Password*') 'helper/Create: -Password is named'
            Note ($body -like "*$outC*")     'helper/Create: output is redirected to this phase''s log'
            $t2 = $null; $e2 = $null
            $null = [System.Management.Automation.Language.Parser]::ParseFile(
                        ($lC -replace '\\', '/'), [ref]$t2, [ref]$e2)
            Note ($e2.Count -eq 0) 'helper/Create: the launcher parses' ("{0} error(s)" -f $e2.Count)
        }

        foreach ($ph in @('Suspend', 'Remove')) {
            $outX = Join-Path $logDir ($ph + '.log')
            $lX   = New-SelfContainedLauncher $ph '' $outX
            Note ($lX -ne '') ("helper/{0}: a launcher was written" -f $ph)
            if ($lX -ne '') {
                $b = (Get-Content -LiteralPath $lX -Raw)
                Note (-not ($b -like '*-Password*')) ("helper/{0}: -Password is omitted entirely" -f $ph)
                Note ($b -like "*-Phase '$ph'*")     ("helper/{0}: -Phase carries its own name" -f $ph)
                $t3 = $null; $e3 = $null
                $null = [System.Management.Automation.Language.Parser]::ParseFile(
                            ($lX -replace '\\', '/'), [ref]$t3, [ref]$e3)
                Note ($e3.Count -eq 0) ("helper/{0}: the launcher parses" -f $ph) ("{0} error(s)" -f $e3.Count)
            }
        }

        # THE GUARD, EXERCISED.  A refusal that has never been triggered is a
        # branch nobody has run - and this file exists because two checks in a
        # row were shipped without being watched fail.
        $bad = New-SelfContainedLauncher 'Create' "pw'with'quote" (Join-Path $logDir 'bad.log')
        # [string]::IsNullOrEmpty, not "-eq ''", and the FIRST version of this
        # row is why: the function printed its refusal AND returned, so $bad
        # came back as an ARRAY and would not bind to Note's [bool].  That is
        # the trap the suite's own header warns about, and this row found it.
        Note ([string]::IsNullOrEmpty($bad)) 'helper: an apostrophe in a value is REFUSED, not quoted badly'
        Note ($script:launcherError -ne '') 'helper: the refusal says WHY, in a variable rather than the return' `
             $script:launcherError
    }

    # --- 6. The launcher it wrote is a loadable script -----------------------
    $launchers = @(Get-ChildItem -LiteralPath $work -Filter 'launch-*.ps1')
    Note ($launchers.Count -eq 3) 'three -NoHelper launchers were written' ("got {0}" -f $launchers.Count)
    foreach ($l in $launchers) {
        $lt = $null; $le = $null
        $null = [System.Management.Automation.Language.Parser]::ParseFile(
                    ($l.FullName -replace '\\', '/'), [ref]$lt, [ref]$le)
        Note ($le.Count -eq 0) ("launcher {0} parses" -f $l.Name) ("{0} error(s)" -f $le.Count)
        $bytes = [System.IO.File]::ReadAllBytes($l.FullName)
        $bom = $false
        for ($k = 1; $k -lt $bytes.Length - 2; $k++) {
            if ($bytes[$k] -eq 0xEF -and $bytes[$k+1] -eq 0xBB -and $bytes[$k+2] -eq 0xBF) { $bom = $true; break }
        }
        Note (-not $bom) ("launcher {0} carries no embedded BOM" -f $l.Name)
    }
}
finally {
    Remove-Item -LiteralPath $work   -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $logDir -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
if ($fail -eq 0 -and $pass -gt 0) {
    Write-Output ("test-doorsargv-units: PASSED - {0} of {0} checks passed." -f $pass)
    exit 0
}
Write-Output ("test-doorsargv-units: FAILED - {0} passed, {1} failed." -f $pass, $fail)
exit 1
