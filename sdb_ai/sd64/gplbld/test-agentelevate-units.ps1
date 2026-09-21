# test-agentelevate-units.ps1 - free guard over the DECISIONS of Claude Code's own elevation
# channel (.claude/tools/agent-elevate-lib.ps1): which script may be run elevated, which
# arguments are plain enough to pass, and how a request is encoded.
#
#   powershell -ExecutionPolicy Bypass -File test-agentelevate-units.ps1
#
# Exit 0 every check passed, 1 a check failed, 2 the library is not there (NO TREE).
#
# WHY IT EXISTS.  The channel runs whatever it admits with the owner's ADMINISTRATOR rights,
# and its helper cannot be exercised without a UAC click - so the ONE part that can be
# proved for free is the part that says no.  Everything here is pure: nothing is elevated,
# no pipe is opened, no helper is started.
#
# WHAT IT DOES NOT PROVE, said plainly so a green here is not over-read: that the pipe
# works, that the UAC prompt appears, that the helper serves, or that a real run's output
# files come back.  Those need the owner's first -Start.
#
# EVERY REFUSAL HAS A CONTROL.  A check that refuses must be shown to be the thing doing
# the refusing, so each safety check is removed in a COPY of the library and the same bad
# input must then be ACCEPTED (MUTANT rows).  The live library is asserted unchanged.

$ErrorActionPreference = 'Stop'

$repo    = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$libPath = Join-Path $repo '.claude\tools\agent-elevate-lib.ps1'
Write-Output 'test-agentelevate-units: the elevation channel''s allow-list and request decisions.'
Write-Output ("  repo : " + $repo)
Write-Output ("  lib  : " + $libPath)
if (-not (Test-Path -LiteralPath $libPath)) {
    Write-Output '  the library is not present on this checkout - nothing to test (exit 2, NO TREE).'
    exit 2
}
. $libPath

$pass = 0
$fail = 0
function Check([string]$label, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ("  [PASS] " + $label) }
    else     { $script:fail++; Write-Output ("  [FAIL] " + $label + $(if ($detail) { "  -> $detail" } else { '' })) }
}
function Refused($v, [string]$why) { return ((-not $v.Ok) -and ($v.Why -like ("*" + $why + "*"))) }

$libSha = (Get-FileHash -LiteralPath $libPath -Algorithm SHA256).Hash

# --- the real allowed directory -------------------------------------------------------------
$allow = Get-AgentAllowRoot $repo
Check 'CONTROL: the allowed directory resolves and exists (gplbld)' `
      ((Test-Path -LiteralPath $allow -PathType Container) -and ($allow -like '*\sdb_ai\sd64\gplbld')) $allow
$real = Join-Path $allow 'cycle.ps1'
Check 'CONTROL: a real gplbld script exists to be admitted' (Test-Path -LiteralPath $real) $real

$v = Test-AgentScriptAllowed $real $allow
Check 'a real script directly in gplbld is admitted' ($v.Ok -and $v.Full -eq $real) ("ok=" + $v.Ok + " why=" + $v.Why)
$v = Test-AgentScriptAllowed (Join-Path $allow 'CYCLE.PS1') $allow
Check 'the same script spelled in another case is admitted (Windows paths)' $v.Ok ("why=" + $v.Why)

# --- a sandbox, so refusals can be shown against files that really exist --------------------
$sb = Join-Path ([IO.Path]::GetTempPath()) ('agentelev-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sb
$null = New-Item -ItemType Directory -Path (Join-Path $sb 'sub')
Set-Content -LiteralPath (Join-Path $sb 'ok.ps1')        -Value 'exit 0'
Set-Content -LiteralPath (Join-Path $sb 'notes.txt')     -Value 'x'
Set-Content -LiteralPath (Join-Path $sb 'sub\deep.ps1')  -Value 'exit 0'
$outside = Join-Path ([IO.Path]::GetTempPath()) ('agentelev-outside-' + [guid]::NewGuid().ToString('N') + '.ps1')
Set-Content -LiteralPath $outside -Value 'exit 0'
$junctionRoot = Join-Path ([IO.Path]::GetTempPath()) ('agentelev-jr-' + [guid]::NewGuid().ToString('N'))
& cmd.exe /c mklink /J $junctionRoot $sb | Out-Null

try {
    $v = Test-AgentScriptAllowed (Join-Path $sb 'ok.ps1') $sb
    Check 'CONTROL: the sandbox admits its own .ps1 (so the refusals below are the rules, not a broken sandbox)' $v.Ok $v.Why

    Check 'REFUSED: an empty path'                        (Refused (Test-AgentScriptAllowed '' $sb) 'no script path')
    Check 'REFUSED: a path with a control character'      (Refused (Test-AgentScriptAllowed ((Join-Path $sb 'ok.ps1') + "`n") $sb) 'control characters')
    Check 'REFUSED: a .ps1 outside the allowed directory' (Refused (Test-AgentScriptAllowed $outside $sb) 'not directly inside')
    Check 'REFUSED: ..\ traversal that lands outside'     (Refused (Test-AgentScriptAllowed (Join-Path $sb ('..\' + (Split-Path -Leaf $outside))) $sb) 'not directly inside')
    Check 'REFUSED: a script in a SUBDIRECTORY'           (Refused (Test-AgentScriptAllowed (Join-Path $sb 'sub\deep.ps1') $sb) 'not directly inside')
    Check 'REFUSED: a file that is not .ps1'              (Refused (Test-AgentScriptAllowed (Join-Path $sb 'notes.txt') $sb) 'only .ps1')
    Check 'REFUSED: a .ps1 that does not exist'           (Refused (Test-AgentScriptAllowed (Join-Path $sb 'missing.ps1') $sb) 'no such file')
    Check 'REFUSED: an allowed directory that is a LINK'  (Refused (Test-AgentScriptAllowed (Join-Path $junctionRoot 'ok.ps1') $junctionRoot) 'link')
    Check 'NULL CASE: no allowed directory refuses everything (empty)'   (Refused (Test-AgentScriptAllowed (Join-Path $sb 'ok.ps1') '') 'allowed directory does not exist')
    Check 'NULL CASE: no allowed directory refuses everything (missing)' (Refused (Test-AgentScriptAllowed (Join-Path $sb 'ok.ps1') (Join-Path $sb 'nope')) 'allowed directory does not exist')

    # --- arguments -----------------------------------------------------------------------------
    Check 'args: none are fine'                           (Test-AgentArgsOk @()).Ok
    Check 'args: a typical verifier line is fine'         (Test-AgentArgsOk @('-Run', 'b210', '-Only', 'verify-lcnames,verify-fold')).Ok
    Check 'args: a Windows path is fine'                  (Test-AgentArgsOk @('C:\Users\Don\x.txt')).Ok
    foreach ($bad in @('a b', '; calc', 'x|y', 'x&y', '$(whoami)', '`x', "abc`n", 'say "hi"', "it's")) {
        $shown = ($bad -replace "`n", '\n')
        Check ("REFUSED arg: '" + $shown + "'") (-not (Test-AgentArgsOk @('-Run', $bad)).Ok)
    }
    Check 'REFUSED arg: an empty argument' (-not (Test-AgentArgsOk @('-Run', '')).Ok)

    # --- request round trip --------------------------------------------------------------------
    foreach ($case in @(@(), @('-Only'), @('-Run', 'b210', '-Only', 'verify-fold'))) {
        $line = ConvertTo-AgentRunRequest 'C:\x\y.ps1' $case
        $back = ConvertFrom-AgentRunRequest $line
        $same = ($null -ne $back) -and ($back.Script -eq 'C:\x\y.ps1') -and (@($back.ArgList).Count -eq @($case).Count) -and
                ((@($back.ArgList) -join '|') -eq (@($case) -join '|'))
        Check ("request round-trips with {0} argument(s)" -f @($case).Count) $same $line
    }
    foreach ($junk in @('', 'PING', 'C:\x\y.ps1', '{"nope":1}', '{bad', '[1,2]')) {
        Check ("not a run request: '" + $junk + "'") ($null -eq (ConvertFrom-AgentRunRequest $junk))
    }
    $la = Format-AgentLaunchArgs 'C:\x\y.ps1' @('-Run', 'b210')
    Write-Output ("  launch args: " + ($la -join ' '))
    Check 'launch args carry the switches, the quoted script and the arguments in order' `
          (($la[0] -eq '-NoProfile') -and ($la -contains '-ExecutionPolicy') -and ($la[5] -eq '"C:\x\y.ps1"') -and ($la[6] -eq '-Run') -and ($la[7] -eq 'b210'))

    # --- the reply: never an empty code (found on the FIRST real run, 21 Sep 2026) ---------------
    Check 'reply: a real code is passed through'      ((Format-AgentRunReply 0 'o' 'e') -eq '0|o|e')
    Check 'reply: a non-zero code is passed through'  ((Format-AgentRunReply 124 'o' 'e') -eq '124|o|e')
    Check 'reply: a NULL code becomes 1, never empty' ((Format-AgentRunReply $null 'o' 'e') -eq '1|o|e') (Format-AgentRunReply $null 'o' 'e')
    Check 'reply: an empty-string code becomes 1'     ((Format-AgentRunReply '' 'o' 'e') -eq '1|o|e')
    Check 'reply: a non-numeric code becomes 1'       ((Format-AgentRunReply 'ok' 'o' 'e') -eq '1|o|e')

    # --- MUTANTS: remove each check in a COPY, and the same bad input must be ACCEPTED ----------
    Write-Output ''
    Write-Output 'MUTANT CONTROL (each check removed in a copy of the library):'
    $libText = [IO.File]::ReadAllText($libPath)
    function Test-Mutant([string]$name, [string]$find, [string]$replace, [string]$driverBody) {
        $mut = $libText.Replace($find, $replace)
        if ($mut -eq $libText) { Check ("MUTANT " + $name + ": the mutation applied") $false 'the text to replace was not found'; return }
        # .ps1, NOT .txt: a dot-source of any other extension does not load the functions.
        $mutLib = Join-Path $sb ('mut-' + [guid]::NewGuid().ToString('N') + '-lib.ps1')
        $driver = Join-Path $sb ('mut-' + [guid]::NewGuid().ToString('N') + '.ps1')
        [IO.File]::WriteAllText($mutLib, $mut)
        [IO.File]::WriteAllText($driver, (". '" + $mutLib + "'`r`n" + $driverBody))
        # 'Continue' around the child: under Stop, Windows PowerShell 5.1 turns any native
        # stderr line into a terminating error and would end the whole guard.
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try   { $out = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $driver 2>&1 | Out-String) }
        finally { $ErrorActionPreference = $prevEap }
        Check ("MUTANT " + $name + ": the bad input is then ACCEPTED (the check was the thing refusing it)") ($out -match 'ACCEPTED') $out.Trim()
    }
    $sbq = $sb.Replace("'", "''"); $outq = $outside.Replace("'", "''"); $jrq = $junctionRoot.Replace("'", "''")
    Test-Mutant 'directory check removed' `
        'if ($null -eq $parent -or $parent.TrimEnd(''\'') -ne $root) {' 'if ($false) {' `
        ("`$v = Test-AgentScriptAllowed '$outq' '$sbq'`r`nif (`$v.Ok) { 'ACCEPTED' } else { 'REFUSED ' + `$v.Why }")
    Test-Mutant 'extension check removed' `
        'if ([IO.Path]::GetExtension($full) -ne ''.ps1'') {' 'if ($false) {' `
        ("`$v = Test-AgentScriptAllowed '" + (Join-Path $sb 'notes.txt').Replace("'", "''") + "' '$sbq'`r`nif (`$v.Ok) { 'ACCEPTED' } else { 'REFUSED ' + `$v.Why }")
    Test-Mutant 'link check removed' `
        '[IO.FileAttributes]::ReparsePoint' '[IO.FileAttributes]::Offline' `
        ("`$v = Test-AgentScriptAllowed '" + (Join-Path $junctionRoot 'ok.ps1').Replace("'", "''") + "' '$jrq'`r`nif (`$v.Ok) { 'ACCEPTED' } else { 'REFUSED ' + `$v.Why }")
    Test-Mutant 'argument check removed' `
        'if ($a -notmatch ''^[A-Za-z0-9_.,:=@\\/-]+\z'') {' 'if ($false) {' `
        ("`$r = Test-AgentArgsOk @('; calc')`r`nif (`$r.Ok) { 'ACCEPTED' } else { 'REFUSED ' + `$r.Why }")
    Test-Mutant 'reply guard removed' `
        'if ($null -ne $ExitCode -and ([string]$ExitCode) -match ''^-?\d+\z'') { $code = [int]$ExitCode }' '$code = $ExitCode' `
        ("`$r = Format-AgentRunReply `$null 'o' 'e'`r`nif (`$r.StartsWith('|')) { 'ACCEPTED an empty code: ' + `$r } else { 'REFUSED ' + `$r }")
    Test-Mutant 'argument anchor weakened back to $' `
        '^[A-Za-z0-9_.,:=@\\/-]+\z' '^[A-Za-z0-9_.,:=@\\/-]+$' `
        ("`$r = Test-AgentArgsOk @(""abc`n"")`r`nif (`$r.Ok) { 'ACCEPTED' } else { 'REFUSED ' + `$r.Why }")
}
finally {
    & cmd.exe /c rmdir $junctionRoot 2>$null | Out-Null
    Remove-Item -LiteralPath $sb -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $outside -Force -ErrorAction SilentlyContinue
}

Check 'the live library was not touched by any mutant (SHA-256)' ((Get-FileHash -LiteralPath $libPath -Algorithm SHA256).Hash -eq $libSha)

Write-Output ''
Write-Output ("test-agentelevate-units: {0} passed, {1} failed." -f $pass, $fail)
exit $(if ($fail -gt 0) { 1 } else { 0 })
