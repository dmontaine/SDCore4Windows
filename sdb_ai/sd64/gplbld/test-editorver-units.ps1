# test-editorver-units.ps1 - does install-editors.ps1's version probe answer
# for every file, and can it be made to hang?
#
#   powershell -ExecutionPolicy Bypass -File test-editorver-units.ps1
#
# Exit 0 all rows passed, 1 a row failed, 2 the check measured nothing.
# NO INSTALL, NO ELEVATION, NO RUN TOKEN.  One of the free tests CLAUDE.md says
# to run on every change.
#
# ===========================================================================
# WHY THIS EXISTS
# ===========================================================================
#
# PRE_RELEASE_FIXES 153.  install-editors.ps1 logged micro's version as blank -
# micro is a Go binary with no Win32 version resource - so the one place the
# machine recorded which micro is installed answered nothing, which is the whole
# of what entry 66 was for.  The fix asks the executable when the resource is
# empty, and falls back to size and SHA-256 so the field is never blank.
#
# ***ASKING AN EXECUTABLE IS THE PART THAT NEEDED A GUARD, NOT THE PART THAT
# NEEDED A COMMENT.***  install-editors.ps1 runs HIDDEN during the install, so a
# full-screen editor opened by a wrong flag would hang the install with nothing
# on screen to say why - and that is not a hypothetical class: this project has
# already lost a day to a hang whose output was going somewhere nobody read.
# The fix fences it with a five-second timeout and a Kill, and A TIMEOUT NOBODY
# HAS FIRED IS NOT A TIMEOUT.  Row 5 makes the probe hang on purpose.
#
# IT LIFTS THE FUNCTION OUT BY AST rather than copying it, so it cannot drift
# from what ships - the same idiom as test-verdict-units and
# test-apiidentity-units.  Say() is stubbed, and what it was asked to log is
# checked too: the timeout must be REPORTED, not swallowed.
#
# THE FIXTURES ARE .cmd FILES, which is what makes this runnable with no
# compiler: a .cmd carries no version resource, so it reaches the probe, and it
# can be made to print a version, print nothing, or loop for ever.
#
# NOT SHIPPED - must be on assert-current.ps1's $neverShipped list, added in
# the same commit that creates this file.

$ErrorActionPreference = 'Stop'

$pass = 0
$fail = 0
function Row($ok, $text) {
    if ($ok) { $script:pass++; Write-Output "[PASS] $text" }
    else     { $script:fail++; Write-Output "[FAIL] $text" }
}

$subject = Join-Path $PSScriptRoot 'install-editors.ps1'
Write-Output 'test-editorver-units: does the version probe answer, and can it hang?'
Write-Output ("  subject : " + $subject)

if (-not (Test-Path -LiteralPath $subject)) {
    Write-Output 'REFUSED: install-editors.ps1 is not beside this script.'
    exit 2
}

# --- lift Get-EditorVersion out of the shipped file ------------------------
$t = $null; $e = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($subject, [ref]$t, [ref]$e)
if ($e.Count -gt 0) {
    Write-Output ("REFUSED: install-editors.ps1 has {0} parse error(s)." -f $e.Count)
    exit 2
}
$fn = $ast.FindAll({
    param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
    $n.Name -eq 'Get-EditorVersion'
}, $true)
if ($fn.Count -ne 1) {
    Write-Output ("REFUSED: found {0} Get-EditorVersion definitions, want exactly 1." -f $fn.Count)
    Write-Output '  Either the fix for PRE_RELEASE 153 has been removed, or the function was renamed.'
    exit 2
}
Write-Output ("  lifted  : Get-EditorVersion, {0} line(s)" -f
              ($fn[0].Extent.EndLineNumber - $fn[0].Extent.StartLineNumber + 1))

# Say() is the shipped script's logger.  Stubbed, and CAPTURED - the timeout
# row below asserts the probe said so rather than failing silently.
$script:said = @()
function Say($m) { $script:said += $m }
. ([scriptblock]::Create($fn[0].Extent.Text))

$work = Join-Path $env:TEMP ('sd-editorver-units-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $work | Out-Null
Write-Output ("  fixtures: " + $work)
Write-Output ''

try {
    # --- 1. a real version resource is preferred over everything else ------
    $psh = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $v1  = Get-EditorVersion $psh ''
    Write-Output ("      powershell.exe -> '{0}'" -f $v1)
    Row ($v1 -ne '' -and -not $v1.StartsWith('unknown')) `
        'a file WITH a version resource answers from the resource'

    # --- 2. no resource, no flag: the size/SHA form, never a blank ---------
    $plain = Join-Path $work 'plain.bin'
    Set-Content -LiteralPath $plain -Value 'not an executable' -Encoding ascii
    $v2 = Get-EditorVersion $plain ''
    Write-Output ("      plain.bin -> '{0}'" -f $v2)
    Row ($v2 -ne '') 'a file with NO resource and NO flag still answers something'
    Row ($v2 -match '^unknown - [\d,]+ bytes, sha256 [0-9a-f]{64}$') `
        'and the answer carries the byte count and the full SHA-256'

    # --- 3. no resource, a flag that prints a labelled version -------------
    $good = Join-Path $work 'good.cmd'
    Set-Content -LiteralPath $good -Encoding ascii -Value @(
        '@echo off'
        'echo Version: 9.9.9'
        'echo Commit hash: deadbeef'
    )
    $v3 = Get-EditorVersion $good '-version'
    Write-Output ("      good.cmd -> '{0}'" -f $v3)
    Row ($v3 -eq '9.9.9') 'the labelled "Version:" line is taken, not the whole output'

    # --- 4. a flag that prints nothing falls back rather than blanking -----
    $quiet = Join-Path $work 'quiet.cmd'
    Set-Content -LiteralPath $quiet -Encoding ascii -Value @('@echo off', 'exit /b 0')
    $v4 = Get-EditorVersion $quiet '-version'
    Write-Output ("      quiet.cmd -> '{0}'" -f $v4)
    Row ($v4 -ne '') 'a probe that prints NOTHING still answers something'
    Row ($v4 -match '^unknown - ') 'and it falls back to the size/SHA form'

    # --- 5. THE ONE THAT MATTERS: a probe that never returns ---------------
    # This is the shape that would hang a hidden install step.  It must come
    # back inside the timeout, answer anyway, and SAY that it timed out.
    $hang = Join-Path $work 'hang.cmd'
    Set-Content -LiteralPath $hang -Encoding ascii -Value @(
        '@echo off'
        ':loop'
        'goto loop'
    )
    $script:said = @()
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $v5 = Get-EditorVersion $hang '-version'
    $sw.Stop()
    Write-Output ("      hang.cmd -> '{0}' in {1:n1}s" -f $v5, $sw.Elapsed.TotalSeconds)
    Row ($sw.Elapsed.TotalSeconds -lt 20) 'a probe that never returns is CUT OFF, not waited on'
    Row ($sw.Elapsed.TotalSeconds -ge 4.5) `
        'and it was really the timeout that ended it, not an instant failure'
    Row ($v5 -ne '') 'a timed-out probe still answers something'
    Row (@($script:said | Where-Object { $_ -match 'timed out' }).Count -ge 1) `
        'and the timeout is REPORTED to the log, not swallowed'
    # NO ASSERTION ON THE PROCESS LIST, deliberately: another cmd.exe on this
    # machine is none of this test's business, and a check that cannot tell
    # them apart would fail for the wrong reason.  The Kill is asserted by the
    # elapsed time above instead - a probe that was not killed does not return.

    # --- 6. a path that does not exist at all ------------------------------
    $v6 = Get-EditorVersion (Join-Path $work 'nosuchfile.exe') '-version'
    Write-Output ("      nosuchfile.exe -> '{0}'" -f $v6)
    Row ($v6 -ne '') 'a path that does not exist still answers something rather than blank'
}
finally {
    try { Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue } catch { }
}

Write-Output ''
Write-Output ("test-editorver-units: {0} passed, {1} failed" -f $pass, $fail)
if (($pass + $fail) -eq 0) { Write-Output 'VOID - nothing was checked.'; exit 2 }
if ($fail -gt 0) { exit 1 }
exit 0
