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
# Section 5 (6 Oct 2026, owner: "ssh.server ... use bundled MSI"; and message 10148 was measured FALSE for an MSI
# removal): RUNS install-ssh.ps1's own discovery of the MSI the installer keeps in <install folder>\ssh-server,
# checks remove-ssh.ps1's MSI branch exits 3, that message 12011 and SSHSRVR agree with it, and that sd.iss keeps the
# copy.  Two mutants prove the discovery and the exit code are really being judged.
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

    # --- 5. 6 Oct 2026, owner: "ssh.server ... use bundled MSI", and 10148 was false for an MSI removal ----
    Write-Host ''; Write-Host '5. install-ssh.ps1 finds the MSI the installer kept; an MSI removal is not announced as staged'

    # 5a. THE REAL DISCOVERY STATEMENT, extracted from install-ssh.ps1 and run against a scratch folder.
    $ins     = Join-Path $here 'install-ssh.ps1'
    $insText = [System.IO.File]::ReadAllText($ins)
    function Get-DiscoveryText([string]$scriptPath) {
        $tk = $null; $er = $null
        $a = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tk, [ref]$er)
        $n = @($a.FindAll({ param($x) $x -is [System.Management.Automation.Language.IfStatementAst] -and $x.Extent.Text -match "'ssh-server'" }, $true))
        if ($n.Count -ne 1) { return '' }
        return $n[0].Extent.Text
    }
    function Invoke-Discovery([string]$stmt, [string]$root, [string]$msiIn) {
        $s = $stmt.Replace('$PSScriptRoot', "'" + $root.Replace("'", "''") + "'")
        $Msi = $msiIn
        $null = Invoke-Expression $s
        return $Msi
    }
    $disc = Get-DiscoveryText $ins
    Check 'found the ssh-server discovery statement in install-ssh.ps1' ($disc -ne '')
    $inst = Join-Path $work 'installed'
    $ssd  = Join-Path $inst 'ssh-server'
    New-Item -ItemType Directory -Path $ssd -Force | Out-Null
    $m9  = Join-Path $ssd 'OpenSSH-Win64-v9.5.0.0.msi'
    $m10 = Join-Path $ssd 'OpenSSH-Win64-v10.0.0.0.msi'
    [System.IO.File]::WriteAllText($m9, 'x'); [System.IO.File]::WriteAllText($m10, 'x')
    $other = Join-Path $work 'given.msi'; [System.IO.File]::WriteAllText($other, 'x')
    $emptyRoot = Join-Path $work 'noinstall'; New-Item -ItemType Directory -Path $emptyRoot -Force | Out-Null
    Check 'no -Msi: the kept copy is used, and v10.0 beats v9.5 (version, not text, order)' ((Invoke-Discovery $disc $inst '') -eq $m10)
    Check 'a -Msi that exists wins over the kept copy'                                         ((Invoke-Discovery $disc $inst $other) -eq $other)
    Check 'a -Msi that is not there falls back to the kept copy'                               ((Invoke-Discovery $disc $inst (Join-Path $work 'gone.msi')) -eq $m10)
    Check 'nothing kept and no -Msi: stays empty (the Windows capability, as before)'          ((Invoke-Discovery $disc $emptyRoot '') -eq '')
    $mutDisc = $disc.Replace('-Descending', '')
    Check 'MUTANT: ascending order picks the older MSI and is caught'                          ((Invoke-Discovery $mutDisc $inst '') -ne $m10)

    # 5b. remove-ssh.ps1: the branch for the MSI's server ends in `exit 3`, never `exit 0` (0 is the staged-removal message).
    function Test-MsiRemovalExit([string]$text) {
        $tk = $null; $er = $null
        $a = [System.Management.Automation.Language.Parser]::ParseInput($text, [ref]$tk, [ref]$er)
        $n = @($a.FindAll({ param($x) $x -is [System.Management.Automation.Language.IfStatementAst] -and $x.Clauses[0].Item1.Extent.Text -match '\$MsiSshd' }, $true))
        if ($n.Count -ne 1) { return $false }
        $last = $n[0].Clauses[0].Item2.Statements | Select-Object -Last 1
        return ($last.Extent.Text -eq 'exit 3')
    }
    $rmText = [System.IO.File]::ReadAllText((Join-Path $here 'remove-ssh.ps1'))
    Check 'remove-ssh.ps1: the MSI branch ends in exit 3'                                     (Test-MsiRemovalExit $rmText)
    $rmMut = $rmText.Replace("    exit 3`r`n}", "    exit 0`r`n}").Replace("    exit 3`n}", "    exit 0`n}")
    Check 'CONTROL: the mutation really changed remove-ssh.ps1'                                ($rmMut -ne $rmText)
    Check 'MUTANT: exit 0 at the end of that branch is caught'                                 (-not (Test-MsiRemovalExit $rmMut))

    # 5c. message 12011, and SSHSRVR wired to it and to -Show.
    $msgPath = Join-Path (Join-Path (Split-Path -Parent $here) 'sdsys\messages') '12011'
    $msgOk = Test-Path -LiteralPath $msgPath
    Check 'message 12011 exists' $msgOk
    if ($msgOk) {
        $msg = [System.IO.File]::ReadAllText($msgPath)
        Check '12011 says it is gone now and no restart is needed'          (($msg -match 'gone now') -and ($msg -match 'no restart is needed'))
        Check '12011 does NOT say the server is still running (10148''s claim)' (-not ($msg -match '(?i)still here|still running|next restarts'))
        Check '12011 is one line with no CR'                                  (($msg.TrimEnd("`n") -notmatch "[\r\n]") -and ($msg -notmatch "`r"))
    }
    $sshsrvr = [System.IO.File]::ReadAllText((Join-Path (Split-Path -Parent $here) 'sdsys\gpl.bp\sshsrvr'))
    Check 'SSHSRVR prints 12011 only for rc = 3 on REMOVE'                  ($sshsrvr -match "(?s)if rc = 3 and action = 'REMOVE' then\s*\r?\n\s*crt sysmsg\(12011\)")
    Check 'SSHSRVR asks install-ssh.ps1 -Show and skips the warning on rc = 10' (($sshsrvr -match "arg = ' -Show'") -and ($sshsrvr -match 'if rc = 10 then dl = @false') -and ($sshsrvr -match "if action = 'INSTALL' and dl then"))
    Check 'install-ssh.ps1 has -Show and exits 10 for "no download"'       (($insText -match '\[switch\]\$Show') -and ($insText -match 'exit 10'))

    # 5d. sd.iss keeps the MSI in the install folder, from the file found beside the installer.
    $iss = [System.IO.File]::ReadAllText((Join-Path $here 'sd.iss'))
    Check 'sd.iss: [Files] copies the beside-the-installer MSI to {app}\ssh-server' ($iss -match '(?s)Source: "\{code:SshMsiSource\}"; DestDir: "\{app\}\\ssh-server";[^\r\n]*\\\s*\r?\n\s*Flags: external ignoreversion skipifsourcedoesntexist; Check: SshMsiFound')
    Check 'sd.iss: SshMsiSource exists and returns SshMsiPath' ($iss -match '(?s)function SshMsiSource\(Param: String\): String;\s*\r?\n\s*begin\s*\r?\n\s*Result := SshMsiPath;')
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
