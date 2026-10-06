# test-sshroute-units.ps1 - the ssh server may be Windows' Feature on Demand OR the OpenSSH MSI.
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-sshroute-units.ps1
#
# ORDINARY UNELEVATED PROMPT.  No install, no SD, no elevation.  Exit 0 all passed, 1 something failed, 2 could
# not set up.  Everything it makes is under %TEMP%\test-sshroute-<pid> and is removed at the end.
#
# WHY IT EXISTS (RELEASE_1.1 121, 6 Oct 2026).  The SD installer now carries Microsoft's OpenSSH MSI beside itself
# and install-ssh.ps1 runs it when the ssh box is ticked.  The MSI puts sshd.exe in Program Files\OpenSSH; Windows'
# own capability puts it in System32\OpenSSH.  Every place that looks for the server had System32 only, and
# ssh-preflight.ps1 would have called an MSI-installed server "NOT part of Windows" and refused the next SD
# install.  This guard (1) fails when a script looks for the System32 sshd and not the Program Files one,
# (2) RUNS ssh-preflight's own classifier against both folders and a look-alike, and (3) proves the scan can fail.
#
# NOT SHIPPED - assert-current exempts test-* scripts by name.

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$work = Join-Path $env:TEMP ('test-sshroute-' + $PID)
$script:pass = 0; $script:fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $what" } else { $script:fail++; Write-Host "  [FAIL] $what $detail" }
}
Write-Host "test-sshroute-units: scripts in $here"

# A script "looks for the Microsoft server in System32" when it names System32\OpenSSH\sshd.exe or
# sshd_config_default; it is covered when it also names the Program Files location (ProgramW6432 or the folder).
function Test-Covered([string]$path) {
    $t = [System.IO.File]::ReadAllText($path)
    $sys = $t -match '(?i)System32\\OpenSSH'
    if (-not $sys) { return $true }
    return ($t -match '(?i)ProgramW6432') -or ($t -match '(?i)Program Files\\OpenSSH')
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    # --- 1. every script that looks in System32 also looks in Program Files ----------------------------
    Write-Host ''; Write-Host '1. no script looks only in System32'
    $files = @(Get-ChildItem -LiteralPath $here -Filter '*.ps1' | Where-Object { $_.Name -ne 'test-sshroute-units.ps1' })
    $withSys = @($files | Where-Object { (Get-Content -LiteralPath $_.FullName -Raw) -match '(?i)System32\\OpenSSH' })
    Check ("CONTROL: {0} scripts name the System32 server (the scan has something to judge)" -f $withSys.Count) ($withSys.Count -ge 6)
    $uncovered = @($files | Where-Object { -not (Test-Covered $_.FullName) })
    Check 'every one of them also names the Program Files server' ($uncovered.Count -eq 0) (($uncovered | ForEach-Object { $_.Name }) -join ', ')

    # --- 2. ssh-preflight's classifier, run on real strings -----------------------------------------------
    Write-Host ''; Write-Host '2. ssh-preflight: what ships with Windows'
    $pre = Join-Path $here 'ssh-preflight.ps1'
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($pre, [ref]$t, [ref]$e)
    Check 'ssh-preflight.ps1 parses' ($e.Count -eq 0) "($($e.Count) errors)"
    $fn = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'IsMicrosoftPath' }, $true))
    Check 'found IsMicrosoftPath' ($fn.Count -eq 1)
    . ([scriptblock]::Create($fn[0].Extent.Text))
    # the folders the script itself builds, read from the script rather than copied
    $src = [System.IO.File]::ReadAllText($pre)
    Check 'the script builds a list of both folders' (($src -match '\$MsSshDirs\s*=\s*@\(\$MsSshDirSys,\s*\$MsSshDirPf\)') -and ($src -match "System32\\OpenSSH") -and ($src -match "ProgramW6432"))
    $MsSshDirs = @('C:\WINDOWS\System32\OpenSSH', 'C:\Program Files\OpenSSH')
    Check 'System32\OpenSSH\sshd.exe ships with Windows'        (IsMicrosoftPath 'C:\WINDOWS\System32\OpenSSH\sshd.exe')
    Check 'Program Files\OpenSSH\sshd.exe ships with Windows'   (IsMicrosoftPath 'C:\Program Files\OpenSSH\sshd.exe')
    Check 'the folder itself counts'                              (IsMicrosoftPath 'C:\Program Files\OpenSSH')
    Check 'case does not matter'                                  (IsMicrosoftPath 'c:\program files\openssh\SSHD.EXE')
    Check 'a look-alike folder does NOT count'                    (-not (IsMicrosoftPath 'C:\Program Files\OpenSSH-evil\sshd.exe'))
    Check 'another vendor''s sshd does NOT count'                 (-not (IsMicrosoftPath 'C:\Program Files\Bitvise SSH Server\BssSvc.exe'))
    Check 'an empty path does NOT count'                          (-not (IsMicrosoftPath ''))

    # --- 3. install-ssh.ps1 and the others still parse, and param() is first ---------------------------
    Write-Host ''; Write-Host '3. the edited scripts parse; install-ssh.ps1 starts with its param block'
    foreach ($n in 'install-ssh.ps1', 'remove-ssh.ps1', 'ssh-preflight.ps1', 'allow-ssh-groups.ps1', 'capture-state.ps1', 'verify-routes.ps1', 'verify-allowgroups.ps1') {
        $a = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $here $n), [ref]$t, [ref]$e)
        Check "$n parses" ($e.Count -eq 0) "($($e.Count) errors)"
    }
    $ai = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $here 'install-ssh.ps1'), [ref]$t, [ref]$e)
    $pb = $ai.ParamBlock
    Check 'install-ssh.ps1 has a param block with -Msi' (($null -ne $pb) -and (@($pb.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Msi' }).Count -eq 1))
    $firstStmt = $ai.EndBlock.Statements | Select-Object -First 1
    Check 'the param block comes before any statement' ($pb.Extent.StartOffset -lt $firstStmt.Extent.StartOffset)

    # --- 4. the scan can fail ------------------------------------------------------------------------------
    Write-Host ''; Write-Host '4. mutant: a script that looks only in System32'
    $mut = Join-Path $work 'mutant.ps1'
    [System.IO.File]::WriteAllText($mut, '$sshd = Join-Path $env:SystemRoot ''System32\OpenSSH\sshd.exe''' + "`r`n" + 'Test-Path $sshd' + "`r`n")
    Check 'MUTANT: the scan flags a System32-only script' (-not (Test-Covered $mut))
    Check 'CONTROL: the live allow-ssh-groups.ps1 is covered' (Test-Covered (Join-Path $here 'allow-ssh-groups.ps1'))
}
catch {
    Write-Host "test-sshroute-units: STOPPED - $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($script:fail -gt 0) { exit 1 }
    exit 2
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host ''
if ($script:pass -eq 0) { Write-Host 'test-sshroute-units: VOID - no check ran.'; exit 2 }
if ($script:fail -gt 0) { Write-Host "test-sshroute-units: FAILED - $($script:pass) passed, $($script:fail) failed."; exit 1 }
Write-Host "test-sshroute-units: PASSED - $($script:pass) of $($script:pass) checks passed."
exit 0
