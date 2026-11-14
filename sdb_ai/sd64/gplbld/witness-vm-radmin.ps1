# witness-vm-radmin.ps1 - remote administration over ssh (RELEASE_1.1 202), the VM falsifier checks F1-F10 and the
# assumptions A1-A6 of .claude/design-remote-admin-20261113.md, against the merged code (503e5952, 5b1aa5b8).
#
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-radmin.ps1 -Only <section[,section]>
#
# ELEVATED PowerShell in the VM, SDSYS signed in once this boot (the seat).  Run the sections IN THIS ORDER, in one run or
# several (each needs the ones before it):
#   delivered   F1  nothing exists as delivered: -Status absent, no SDRADMIN, no task, no sshd block, ssh refused
#   on          F2  remote.sdsys on (the console verb through the seat; its Windows password is generated here and kept in
#                   C:\SD-witness\fixtures.json): every wall open, groups, rights, sshd -T for both spellings, the broker task
#   ssh         F3  SDRADMIN over ssh lands in sdradmin; Windows refuses its interactive, batch and service logons (A3)
#   ops         F4  each listed op through the broker, read back on Windows and in SD (A1, A5, A6)
#   refuse      F5  bad and reserved targets, an administrator, an unstamped user; every verb not on the list; LOGTO
#   f6          F6  sftp, scp, a command line, a port forward, a key: all refused
#   f8          F8  SDRADMIN (and an ordinary SD user) cannot write SD's locked files; its own directory is the control
#   lockout     F10 Windows locks SDRADMIN after the policy's bad passwords (and this unlocks it again)
#   keep        remote.ssh off from the remote session keeps that session (row 202's owed "remote.ssh off keeps the remote
#               session"); then F7's live half: remote.sdsys off at the console ends a live SDRADMIN session
#   off         F7  every wall shut after OFF; ssh refused
#   offremote   F7  ON again (no new password), then remote.sdsys off FROM the remote session through the broker
# F9 (a replayed or stale job definition) and F11 (upgrade keeps the state; uninstall removes it) are not here: F9 needs a
# hand-made job definition run by an SDSYS batch logon, which no outside script can be (said in the summary); F11 is
# witness-vm-reinstall.ps1.
#
# Output as every witness-vm script: commands (passwords never), raw output, before/after, [VERDICT] lines with evidence,
# a summary and CSV in C:\SD-witness\logs.  Exit 0 passed, 1 FAIL or FINDING, 2 could not run or nothing measured.
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting.  Parse-checked; not run (it needs the VM).
# END-HISTORY

param([string[]]$Only = @(), [switch]$List)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

$known = @('delivered', 'on', 'ssh', 'ops', 'refuse', 'f6', 'f8', 'lockout', 'keep', 'off', 'offremote')
if ($List) { Write-Host ('sections: ' + ($known -join ',')); exit 0 }
$sections = Resolve-WitSections $Only $known
if ($null -eq $sections) { exit 2 }
Start-Wit 'witness-vm-radmin' $sections
if (-not (Test-WitElevated)) { Write-Wit 'CANNOT RUN: not elevated.  Open PowerShell with "Run as administrator".'; exit 2 }

$vm = $env:COMPUTERNAME
$app = Join-Path $env:ProgramFiles 'SD'
$ra = Join-Path $app 'remote-admin.ps1'
$stateFile = Join-Path $script:WitDataDir 'remote-admin\state'
$brokerLog = Join-Path $script:WitDataDir 'remote-admin\broker.log'
$cfg = Join-Path $env:ProgramData 'ssh\sshd_config'
$marker = '# --- BEGIN SD remote administration'
$sshdSvc = Get-CimInstance Win32_Service -Filter "Name='sshd'" -ErrorAction SilentlyContinue
$sshd = ''
if ($null -ne $sshdSvc) { $sshd = ($sshdSvc.PathName -replace '^"([^"]+)".*$', '$1') -replace '^(\S+\.exe).*$', '$1' }

$ac = Join-Path $PSScriptRoot 'assert-current.ps1'
Write-Wit 'assert-current (a few seconds)'
$acOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ac -Quiet 2>&1 | ForEach-Object { [string]$_ }
if ($LASTEXITCODE -ne 0) { Write-WitRaw 'assert-current' ($acOut -join "`n"); Write-Wit 'CANNOT RUN: the install is not the build of this source copy.'; exit 2 }
$w = Invoke-WitSd -Commands @('WHO') -Label 'the seat answers as SDSYS' -TimeoutSec 90
if (-not $w.Ok -or $w.Text -notmatch '(?m)^\s*\d+\s+SDSYS\b') { Write-Wit 'CANNOT RUN: the SDSYS seat did not answer (sign in as SDSYS once, switch back).'; exit 2 }

function Get-RaStatus {
    $o = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ra -Status 2>&1 | ForEach-Object { [string]$_ }
    return ($o -join "`n")
}
function Get-RadminPw { $f = Read-WitFixtures; if ($null -eq $f -or -not $f.ContainsKey('sdradmin')) { return '' }; return $f['sdradmin'] }
function Get-SshdT([string]$User) {
    if ($sshd -eq '') { return '' }
    $o = & $sshd -T -C ('user=' + $User + ',host=sdcheck,addr=192.0.2.1') 2>&1 | ForEach-Object { [string]$_ }
    return ($o -join "`n")
}
function Test-WinUser([string]$Name) { try { $null = Get-LocalUser -Name $Name -ErrorAction Stop; return $true } catch { return $false } }
function Test-Registered([string]$Name) { return (Test-Path -LiteralPath (Join-Path (Join-Path $script:WitSdsys 'accounts') $Name)) }
function Get-UserGroups([string]$Name) {
    $sid = Get-WitSid $Name
    $g = @()
    foreach ($lg in @(Get-LocalGroup)) { if (@(Get-LocalGroupMember -Group $lg.Name -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -eq $sid }).Count) { $g += $lg.Name } }
    return $g
}

# ssh, sftp or scp with a password from SSH_ASKPASS (sdtestuser.ps1's mechanism), any arguments; stdin from a file.  Returns
# Invoke-SdTestNative's object.  Prints nothing; the caller prints.
function Invoke-SshRaw([string]$Exe, [string[]]$CmdArgs, [string]$Password, [string]$StdIn = '') {
    $wd = Join-Path $env:TEMP ('witness-ssh-' + $PID)
    if (-not (Test-Path -LiteralPath $wd)) { $null = New-Item -ItemType Directory -Path $wd }
    $ask = Join-Path $wd 'askpass.cmd'
    $env:SDPROBEPW = $Password
    Set-Content -Path $ask -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
    $env:SSH_ASKPASS = $ask; $env:SSH_ASKPASS_REQUIRE = 'force'; $env:DISPLAY = 'localhost:0'
    try { return (Invoke-SdTestNative $Exe $CmdArgs -StdIn $StdIn -WorkDir $wd) }
    finally {
        Remove-Item Env:\SSH_ASKPASS, Env:\SSH_ASKPASS_REQUIRE, Env:\DISPLAY, Env:\SDPROBEPW -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $wd -Recurse -Force -ErrorAction SilentlyContinue
    }
}
$sshOpts = @('-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=NUL', '-o', 'ConnectTimeout=20', '-o', 'LogLevel=ERROR',
             '-o', 'PreferredAuthentications=password', '-o', 'NumberOfPasswordPrompts=1')

# One ssh session as SDRADMIN, held open: lines are written to it while it runs.  Returns the Process; its output is read
# with $p.StandardOutput.ReadToEndAsync() started here (kept on the object as .Tag is not available, so returned beside it).
function Start-HeldSsh([string]$User, [string]$Password) {
    $wd = Join-Path $env:TEMP ('witness-held-' + $PID)
    if (-not (Test-Path -LiteralPath $wd)) { $null = New-Item -ItemType Directory -Path $wd }
    $ask = Join-Path $wd 'askpass.cmd'
    Set-Content -Path $ask -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command ssh.exe).Source
    $psi.Arguments = (($sshOpts + @(($User + '@localhost'), 'whoami')) -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['SDPROBEPW'] = $Password
    $psi.EnvironmentVariables['SSH_ASKPASS'] = $ask
    $psi.EnvironmentVariables['SSH_ASKPASS_REQUIRE'] = 'force'
    $psi.EnvironmentVariables['DISPLAY'] = 'localhost:0'
    $p = [Diagnostics.Process]::Start($psi)
    $o = $p.StandardOutput.ReadToEndAsync()
    $e = $p.StandardError.ReadToEndAsync()
    return @{ P = $p; Out = $o; Err = $e; Dir = $wd }
}

$pw = Get-RadminPw

# ===================================================================================================== delivered (F1)
if ($sections -contains 'delivered') {
    Write-Wit ''
    Write-Wit '=== F1: delivered closed'
    if (-not (Test-Path -LiteralPath $ra)) { Add-WitResult '202' 'remote-admin.ps1 is installed' 'FAIL' ('no ' + $ra) }
    else {
        $s = Get-RaStatus
        Write-WitRaw 'remote-admin.ps1 -Status' $s
        Set-WitVerdict '202' 'F1: -Status says remote-admin=absent' $s '(?m)^remote-admin=absent\s*$' @('remote-admin=(open|inconsistent|closed)')
    }
    Set-WitCompare '202' 'F1: no Windows account SDRADMIN' 'False' ([string](Test-WinUser 'SDRADMIN'))
    Set-WitCompare '202' 'F1: no broker task \SD\sdcore-radmin' '0' ([string]@(Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction SilentlyContinue).Count)
    $c = ''
    try { $c = [IO.File]::ReadAllText($cfg) } catch { }
    Set-WitCompare '202' 'F1: sshd_config has no remote administration block' 'False' ([string]($c.Contains($marker))) -Evidence $cfg
    try { Copy-Item -LiteralPath $cfg -Destination (Join-Path $script:WitRoot 'sshd_config.before-radmin') -Force; Write-Wit '  sshd_config kept as C:\SD-witness\sshd_config.before-radmin (for F11)' } catch { }
    $r = Invoke-SshRaw (Get-Command ssh.exe).Source ($sshOpts + @('sdradmin@localhost', 'whoami')) ('zz-not-the-password-' + (Get-Random)) "OFF`n"
    Write-WitRaw ('ssh sdradmin@localhost (exit ' + $r.ExitCode + ')') ($r.Out + "`n" + $r.Err)
    Set-WitVerdict '202' 'F1: ssh sdradmin@localhost is refused' ($r.Err + ' exit=' + $r.ExitCode) 'Permission denied' @('exit=0\b')
}

# ===================================================================================================== on (F2)
if ($sections -contains 'on') {
    Write-Wit ''
    Write-Wit '=== F2: remote.sdsys on at the console (through the seat; the first ON makes SDRADMIN and asks its password twice)'
    if ($pw -eq '') {
        $pw = New-SdTestPassword
        $f = Read-WitFixtures
        if ($null -eq $f) { $f = @{} }
        $f['sdradmin'] = $pw
        Save-WitFixtures $f ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    }
    $mark = Get-WitAuditMark
    $r = Invoke-WitSd -Commands @('remote.sdsys on', $pw, $pw) -Label 'remote.sdsys on' -Secrets @($pw) -TimeoutSec 300
    Set-WitVerdict '202' 'F2: remote.sdsys on succeeds (12601 "ssh is open for SDRADMIN")' $r.Text 'ssh is open for SDRADMIN' @('did not succeed', 'Command requires administrator', 'not available in a remote administration session')
    $s = Get-RaStatus
    Write-WitRaw 'remote-admin.ps1 -Status' $s
    Set-WitVerdict '202' 'F2: -Status says remote-admin=open' $s '(?m)^remote-admin=open\s*$' @('remote-admin=(inconsistent|closed|absent)')
    foreach ($kv in @('account=enabled', 'sdssh=yes', 'sshd-arm=open', 'broker=running', 'state=on')) { Set-WitVerdict '202' ('F2: wall ' + $kv) $s ('(?m)^' + [regex]::Escape($kv) + '\s*$') @() }
    $u = $null
    try { $u = Get-LocalUser -Name SDRADMIN -ErrorAction Stop } catch { }
    if ($null -ne $u) {
        Add-WitResult '202' 'F2: SDRADMIN' 'INFO' ('enabled ' + $u.Enabled + '; ' + $u.Description + '; ' + $u.SID.Value)
        $g = @(Get-UserGroups 'SDRADMIN' | Sort-Object)
        $bad = @($g | Where-Object { @('Administrators', 'Remote Desktop Users', 'Remote Management Users', 'Backup Operators', 'sdapi', 'Hyper-V Administrators') -contains $_ })
        Set-WitCompare '202' 'F2: SDRADMIN is in no administrative group and not in sdapi' '' ($bad -join ',') -Evidence ('groups: ' + ($g -join ','))
        $need = @('sdusers', 'sdssh', 'sdsshonly' | Where-Object { $g -notcontains $_ })
        Set-WitCompare '202' 'F2: SDRADMIN is in sdusers, sdssh and sdsshonly' '' ($need -join ',') -Evidence ('groups: ' + ($g -join ','))
        $rights = Get-WitRights
        foreach ($rn in @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight', 'SeDenyBatchLogonRight', 'SeDenyServiceLogonRight')) {
            Set-WitCompare '202' ('F2: SDRADMIN holds ' + $rn) 'True' ([string](@($rights[$rn]) -contains $u.SID.Value))
        }
        Set-WitCompare '202' 'F2: SDRADMIN is NOT denied the network logon sshd needs' 'False' ([string](@($rights['SeDenyNetworkLogonRight']) -contains $u.SID.Value))
    } else { Add-WitResult '202' 'F2: the Windows account SDRADMIN was made' 'FAIL' 'Get-LocalUser SDRADMIN found nothing' }
    foreach ($spell in @('sdradmin', ($vm.ToLower() + '\sdradmin'))) {
        $t = Get-SshdT $spell
        Write-WitRaw ('sshd -T for ' + $spell + ' (the lines that matter)') (($t -split "`n" | Where-Object { $_ -match '^(authenticationmethods|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|hostbasedauthentication|authorizedkeysfile|maxauthtries|disableforwarding|allowtcpforwarding|permittunnel|permittty|permituserrc|forcecommand|denyusers|allowgroups) ' }) -join "`n")
        $miss = @()
        foreach ($want in @('passwordauthentication yes', 'pubkeyauthentication no', 'authenticationmethods password', 'disableforwarding yes', 'permittunnel no', 'maxauthtries 3', 'authorizedkeysfile none', 'permittty yes')) { if ($t -notmatch ('(?m)^' + [regex]::Escape($want) + '\s*$')) { $miss += $want } }
        if ($t -notmatch '(?m)^forcecommand .*sd\.exe') { $miss += 'forcecommand ...sd.exe' }
        if ($t -eq '') { Add-WitResult '202' ('F2/A2: sshd -T gives ' + $spell + ' the open keywords') 'NOT-MEASURED' 'sshd -T printed nothing (no sshd.exe found?)' }
        else { Set-WitCompare '202' ('F2/A2: sshd -T gives ' + $spell + ' the open keywords') '' ($miss -join '; ') }
    }
    $task = @(Get-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction SilentlyContinue)
    if ($task.Count -ne 1) { Add-WitResult '202' 'F2: the broker task runs' 'FAIL' 'no \SD\sdcore-radmin' }
    else {
        $t = $task[0]
        Add-WitResult '202' 'F2: the broker task' $(if ([string]$t.State -eq 'Running' -and $t.Principal.UserId -match 'SDSYS' -and [string]$t.Principal.LogonType -eq 'S4U') { 'PASS' } else { 'FAIL' }) ('state ' + $t.State + ', as ' + $t.Principal.UserId + ' ' + $t.Principal.LogonType + ' ' + $t.Principal.RunLevel)
    }
    $st = ''
    try { $st = ([IO.File]::ReadAllText($stateFile)).Trim() } catch { }
    Set-WitCompare '202' 'F2: the state file reads on' 'on' $st -Evidence $stateFile
    $e = [SdWit.Native]::PipeProbe('\\.\pipe\sd-radmin', (0x0001 -bor 0x0002 -bor 0x0080 -bor 0x00100000))
    Set-WitCompare '202' 'F5: the broker''s pipe refuses another user (this elevated administrator: 5 = access denied)' '5' ([string]$e)
    $al = @(Get-WitAuditSince $mark | Where-Object { $_ -match 'remote\.sdsys' })
    Write-WitRaw 'audit: remote.sdsys lines' ($al -join "`n")
    Set-WitVerdict '202' 'F2: the audit has remote.sdsys on made account=sdradmin and remote.sdsys on status=0' ($al -join "`n") '(?s)remote\.sdsys on made account=sdradmin.*remote\.sdsys on status=0' @()
}

# ===================================================================================================== ssh (F3, A3)
if ($sections -contains 'ssh') {
    Write-Wit ''
    Write-Wit '=== F3: SDRADMIN over ssh, and what Windows refuses it'
    if ($pw -eq '') { Add-WitResult '202' 'F3' 'NOT-MEASURED' 'no SDRADMIN password on file: run -Only on first' }
    else {
        $mark = Get-WitAuditMark
        $r = Invoke-WitSsh -User 'sdradmin' -Password $pw -Commands @('WHO', 'remote.sdsys') -Label 'F3: sign in, WHO, the status through the broker'
        $t = ''
        if ($null -ne $r) { $t = $r.Out }
        Set-WitVerdict '202' 'F3: SDRADMIN lands in sdradmin over ssh' $t '(?m)^\s*\d+\s+sdradmin\b' @('signs in only over ssh', 'Connection terminated', 'Permission denied')
        Set-WitVerdict '202' 'F3/A1: remote.sdsys (status) runs through the broker''s SDSYS job' $t '(?m)remote-admin=open' @('helper refused', 'gave no answer', 'not running')
        $al = @(Get-WitAuditSince $mark)
        Write-WitRaw 'audit since' (($al | Where-Object { $_ -match 'remote|radmin|sdradmin' }) -join "`n")
        Set-WitVerdict '202' 'F3: the audit has remote administration login from=<address>' ($al -join "`n") 'remote administration login from=\S+' @()
        $jl = @($al | Where-Object { $_ -match 'job=radmin-' })
        Add-WitResult '202' ('A1: the broker''s job lines carry job=radmin-<nonce>: ' + $jl.Count) $(if ($jl.Count) { 'PASS' } else { 'FAIL' }) (($jl | Select-Object -First 2) -join ' / ')
        foreach ($lt in @(@(2, 'interactive (console, runas)'), @(4, 'batch (a scheduled task)'), @(5, 'service'))) {
            $e = [SdWit.Native]::LogonTest('SDRADMIN', '.', $pw, $lt[0])
            Set-WitCompare '202' ('F3/A3: Windows refuses SDRADMIN a ' + $lt[1] + ' logon (1385 = logon type not granted)') '1385' ([string]$e)
        }
        $e = [SdWit.Native]::LogonTest('SDRADMIN', '.', $pw, 3)
        Set-WitCompare '202' 'F3/A3 control: the network logon sshd uses is allowed (0)' '0' ([string]$e)
    }
}

# ===================================================================================================== ops (F4, A5, A6)
if ($sections -contains 'ops') {
    Write-Wit ''
    Write-Wit '=== F4: each listed op from the remote session, read back on Windows and in SD (about 2 minutes)'
    if ($pw -eq '') { Add-WitResult '202' 'F4' 'NOT-MEASURED' 'no SDRADMIN password on file' }
    else {
        $pa = New-SdTestPassword
        $pb = New-SdTestPassword
        $ok = { param($r) if ($null -eq $r) { return '' }; return $r.Out }
        $r = Invoke-WitSsh 'sdradmin' $pw @('create.account user zzwitra ssh', $pa, $pa) 'F4: create.account user zzwitra ssh'
        Add-WitResult '202' 'F4/A6: create.account user through the broker makes the register record and the Windows user' $(if ((Test-Registered 'zzwitra') -and (Test-WinUser 'zzwitra')) { 'PASS' } else { 'FAIL' }) ('register ' + (Test-Registered 'zzwitra') + ', Windows ' + (Test-WinUser 'zzwitra') + ', groups ' + ((Get-UserGroups 'zzwitra') -join ','))
        $r2 = Invoke-WitSsh 'zzwitra' $pa @('WHO') 'F4: zzwitra signs in with the password the broker set'
        Set-WitVerdict '202' 'F4/A6: the new account signs in with the password sent as the secret' (& $ok $r2) '(?m)^\s*\d+\s+zzwitra\b' @('Permission denied')
        $r = Invoke-WitSsh 'sdradmin' $pw @('modify.password zzwitra', $pb, $pb) 'F4: modify.password zzwitra'
        $r2 = Invoke-WitSsh 'zzwitra' $pb @('WHO') 'F4: the new password works'
        Set-WitVerdict '202' 'F4: modify.password through the broker changes the password' (& $ok $r2) '(?m)^\s*\d+\s+zzwitra\b' @('Permission denied')
        $r = Invoke-WitSsh 'sdradmin' $pw @('modify.account zzwitra suspended') 'F4: suspend zzwitra'
        $r2 = Invoke-WitSsh 'zzwitra' $pb @('WHO') 'F4: a suspended account is refused at sign-on'
        $t2 = & $ok $r2
        if ($t2 -match '(?m)^\s*\d+\s+zzwitra\b') { Add-WitResult '202' 'F4: modify.account suspended through the broker takes effect' 'FAIL' 'zzwitra still answered WHO' } else { Add-WitResult '202' 'F4: modify.account suspended through the broker takes effect' 'PASS' 'no WHO answer after the suspension (raw output above)' }
        $null = Invoke-WitSsh 'sdradmin' $pw @('modify.account zzwitra unsuspended') 'F4: unsuspend zzwitra'
        $null = Invoke-WitSsh 'sdradmin' $pw @('create.account group zzwitrg') 'F4: create.account group zzwitrg'
        Set-WitCompare '202' 'F4: create.account group through the broker' 'True' ([string](Test-Registered 'zzwitrg'))
        $null = Invoke-WitSsh 'sdradmin' $pw @('modify.account zzwitrg add zzwitra') 'F4: modify.account zzwitrg add zzwitra'
        $m = Get-WitGroupMembers 'sdu_zzwitrg'
        Set-WitCompare '202' 'F4: modify.account add puts the user in the group''s Windows group' 'True' ([string]($m -contains 'zzwitra')) -Evidence ($m -join ',')
        $null = Invoke-WitSsh 'sdradmin' $pw @('modify.account zzwitrg delete zzwitra') 'F4: modify.account zzwitrg delete zzwitra'
        $m = Get-WitGroupMembers 'sdu_zzwitrg'
        Set-WitCompare '202' 'F4: modify.account delete takes the user out' 'False' ([string]($m -contains 'zzwitra')) -Evidence ($m -join ',')
        $r = Invoke-WitSsh 'sdradmin' $pw @('remote.sdsys accounts', 'remote.sdsys audit 20', 'remote.ssh', 'remote.api') 'F4: the reports'
        Set-WitVerdict '202' 'F4: the read-only reports answer through the broker' (& $ok $r) 'zzwitra' @('helper refused', 'gave no answer')
        $null = Invoke-WitSsh 'sdradmin' $pw @('delete.account zzwitra', 'zzwitra') 'F4: delete.account zzwitra (the name typed again)'
        Add-WitResult '202' 'F4: delete.account through the broker removes the record and the Windows user' $(if (-not (Test-Registered 'zzwitra') -and -not (Test-WinUser 'zzwitra')) { 'PASS' } else { 'FAIL' }) ('register ' + (Test-Registered 'zzwitra') + ', Windows ' + (Test-WinUser 'zzwitra'))
        $null = Invoke-WitSsh 'sdradmin' $pw @('delete.account zzwitrg', 'zzwitrg') 'F4: delete.account zzwitrg'
        Set-WitCompare '202' 'F4: delete.account of the group' 'False' ([string](Test-Registered 'zzwitrg'))
        $bl = @(Get-Content -LiteralPath $brokerLog -ErrorAction SilentlyContinue | Select-Object -Last 20)
        Write-WitRaw ('the broker''s log ' + $brokerLog + ' (last 20)') ($bl -join "`n")
        $sec = @($bl | Where-Object { $_ -match [regex]::Escape($pa) -or $_ -match [regex]::Escape($pb) })
        Set-WitCompare '202' 'the broker''s log never holds a password' '0' ([string]$sec.Count)
    }
}

# ===================================================================================================== refuse (F5)
if ($sections -contains 'refuse') {
    Write-Wit ''
    Write-Wit '=== F5: what the broker and the remote session must refuse (about 3 minutes; each in its own session)'
    if ($pw -eq '') { Add-WitResult '202' 'F5' 'NOT-MEASURED' 'no SDRADMIN password on file' }
    else {
        # Windows users the broker must refuse to touch: one without SD's stamp, one in Administrators.
        $plainPw = ConvertTo-SecureString (New-SdTestPassword) -AsPlainText -Force
        foreach ($n in @('zzwitplain', 'zzwitadm')) { if (-not (Test-WinUser $n)) { $null = New-LocalUser -Name $n -Password $plainPw -Description 'witness fixture, not made by SD' } }
        try { Add-LocalGroupMember -SID 'S-1-5-32-544' -Member 'zzwitadm' -ErrorAction Stop } catch { }
        $refusal = 'helper refused the command|is not available in a remote administration session|Command requires administrator privileges|is not in your VOC|User not allowed in requested account|SDSYS Account access is restricted|usage|not an account'
        foreach ($n in @('sdsys', 'sdradmin', 'shared', 'administrator', 'zzwitplain', 'zzwitadm', 'zz..x', 'zzabcdefghijklmnopqrs', 'ZZUPPER')) {
            $before = Test-Registered $n.ToLower()
            $r = Invoke-WitSsh 'sdradmin' $pw @(('create.account group ' + $n)) ('F5: create.account group ' + $n)
            $t = ''
            if ($null -ne $r) { $t = $r.Out }
            $made = (-not $before) -and (Test-Registered $n.ToLower())
            if ($made) { Add-WitResult '202' ('F5: the broker refuses the target ' + $n) 'FAIL' 'a register record was made' }
            else { Set-WitVerdict '202' ('F5: the broker refuses the target ' + $n) $t $refusal @('remote\.admin create\.account .*status=0') }
        }
        foreach ($c in @('set.config cleanup 600', 'set.job', 'backup.account all', 'update.accounts all', 'run.in zzrunin basic bp zzri no.query', 'catalog bp zzri global',
                         'logto zzwitoff', 'sh whoami', 'remote.sdsys on', 'create.file zzwitf dynamic', 'ed voc who')) {
            $r = Invoke-WitSsh 'sdradmin' $pw @($c, 'N', 'N') ('F5: ' + $c)
            $t = ''
            if ($null -ne $r) { $t = $r.Out }
            Set-WitVerdict '202' ('F5: the remote session refuses "' + $c + '"') $t $refusal @('status=ok', 'is scheduled', 'Backed up', 'had their VOC updated', 'Compiled 1 program', '\\sdradmin\s*$', 'ssh is open for', 'Created file')
        }
        foreach ($n in @('zzwitplain', 'zzwitadm')) { try { Remove-LocalUser -Name $n -ErrorAction Stop } catch { } }
        Add-WitResult '202' 'F5: hand-made requests (an extra key, oversize, a bad op) sent to the broker' 'NOT-MEASURED' 'only a process of SDRADMIN''s own may connect, and SDRADMIN has no shell: the free guard test-remoteadmin-units.ps1 drives the parser (139 rows, 50 mutants)'
        Add-WitResult '202' 'the broker''s built list lets modify.account set sh-on and os-on remotely (sd-radmin.ps1 $RadminModify)' 'INFO' 'the design proposed the tightening forms only (its Q3, the owner''s); not a refusal this sitting tests'
    }
}

# ===================================================================================================== f6
if ($sections -contains 'f6') {
    Write-Wit ''
    Write-Wit '=== F6: no file transfer, command line, forward or key'
    if ($pw -eq '') { Add-WitResult '202' 'F6' 'NOT-MEASURED' 'no SDRADMIN password on file' }
    else {
        $sftp = Get-Command sftp.exe -ErrorAction SilentlyContinue
        $bf = Join-Path $script:WitRoot 'sftp-batch.txt'
        Set-Content -LiteralPath $bf -Value 'ls' -Encoding ASCII
        if ($null -ne $sftp) {
            $r = Invoke-SshRaw $sftp.Source ($sshOpts + @('-b', $bf, 'sdradmin@localhost')) $pw ''
            Write-WitRaw ('sftp (exit ' + $r.ExitCode + ')') ($r.Out + "`n" + $r.Err)
            Set-WitCompare '202' 'F6: sftp fails (ForceCommand runs SD, not the sftp server)' 'True' ([string]($r.ExitCode -ne 0))
        }
        $dst = Join-Path $script:WitRoot 'scp-got.ini'
        Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
        $scp = Get-Command scp.exe -ErrorAction SilentlyContinue
        if ($null -ne $scp) {
            $r = Invoke-SshRaw $scp.Source ($sshOpts + @('sdradmin@localhost:C:/Windows/win.ini', $dst)) $pw ''
            Write-WitRaw ('scp (exit ' + $r.ExitCode + ')') ($r.Out + "`n" + $r.Err)
            Set-WitCompare '202' 'F6: scp copies nothing' 'False' ([string](Test-Path -LiteralPath $dst))
        }
        $r = Invoke-SshRaw (Get-Command ssh.exe).Source ($sshOpts + @('sdradmin@localhost', 'cmd', '/c', 'echo', 'zzw202cmdline')) $pw "OFF`n"
        Write-WitRaw ('ssh with a command line (exit ' + $r.ExitCode + ')') ($r.Out + "`n" + $r.Err)
        Set-WitCompare '202' 'F6: a command line on ssh is not run (ForceCommand)' 'False' ([string]($r.Out -match '(?m)^zzw202cmdline\s*$'))
        # A local forward: the listener is the client's own; the test is whether a connection through it reaches port 22.
        $fwdPort = 15555
        $wd = Join-Path $env:TEMP ('witness-fwd-' + $PID)
        if (-not (Test-Path -LiteralPath $wd)) { $null = New-Item -ItemType Directory -Path $wd }
        $ask = Join-Path $wd 'askpass.cmd'
        Set-Content -Path $ask -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = (Get-Command ssh.exe).Source
        $psi.Arguments = (($sshOpts + @('-N', '-L', ($fwdPort.ToString() + ':127.0.0.1:22'), 'sdradmin@localhost')) -join ' ')
        $psi.UseShellExecute = $false
        $psi.RedirectStandardError = $true
        $psi.EnvironmentVariables['SDPROBEPW'] = $pw
        $psi.EnvironmentVariables['SSH_ASKPASS'] = $ask
        $psi.EnvironmentVariables['SSH_ASKPASS_REQUIRE'] = 'force'
        $psi.EnvironmentVariables['DISPLAY'] = 'localhost:0'
        $fp = [Diagnostics.Process]::Start($psi)
        Start-Sleep -Seconds 8
        $banner = ''
        try {
            $tc = New-Object Net.Sockets.TcpClient('127.0.0.1', $fwdPort)
            $tc.ReceiveTimeout = 5000
            $buf = New-Object byte[] 64
            $n = 0
            try { $n = $tc.GetStream().Read($buf, 0, 64) } catch { }
            $banner = [Text.Encoding]::ASCII.GetString($buf, 0, $n)
            $tc.Close()
        } catch { $banner = '(no listener: ' + $_.Exception.Message + ')' }
        if (-not $fp.HasExited) { $fp.Kill() }
        Remove-Item -LiteralPath $wd -Recurse -Force -ErrorAction SilentlyContinue
        Add-WitResult '202' 'F6: a local forward through SDRADMIN''s session reaches nothing (no SSH banner from port 22 through it)' $(if ($banner -match 'SSH-2\.0') { 'FAIL' } else { 'PASS' }) ('read through the forward: ' + $banner.Trim())
        # A key in SDRADMIN's authorized_keys must not be used.
        $sid = Get-WitSid 'SDRADMIN'
        $prof = (Get-CimInstance Win32_UserProfile | Where-Object { $_.SID -eq $sid }).LocalPath
        if ([string]::IsNullOrEmpty($prof)) { Add-WitResult '202' 'F6: a key in SDRADMIN''s authorized_keys is refused' 'NOT-MEASURED' 'SDRADMIN has no profile yet (run -Only ssh first)' }
        else {
            $kd = Join-Path $env:TEMP ('witness-key-' + $PID)
            $null = New-Item -ItemType Directory -Path $kd -Force
            $kf = Join-Path $kd 'id'
            & ssh-keygen.exe -t ed25519 -f $kf -N '""' -q 2>&1 | Out-Null
            if (-not (Test-Path -LiteralPath $kf)) { & ssh-keygen.exe -t ed25519 -f $kf -N '' -q 2>&1 | Out-Null }
            $sshDir = Join-Path $prof '.ssh'
            $null = New-Item -ItemType Directory -Path $sshDir -Force
            $ak = Join-Path $sshDir 'authorized_keys'
            Copy-Item -LiteralPath ($kf + '.pub') -Destination $ak -Force
            $kr = Invoke-SdTestNative (Get-Command ssh.exe).Source @('-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=NUL', '-o', 'BatchMode=yes', '-o', 'PreferredAuthentications=publickey', '-i', $kf, 'sdradmin@localhost', 'whoami') -StdIn "OFF`n" -WorkDir $kd
            Write-WitRaw ('ssh with the key (exit ' + $kr.ExitCode + ')') ($kr.Out + "`n" + $kr.Err)
            Set-WitVerdict '202' 'F6: a key in SDRADMIN''s authorized_keys is refused' ($kr.Err + ' exit=' + $kr.ExitCode) 'Permission denied' @('exit=0\b')
            Remove-Item -LiteralPath $ak -Force -ErrorAction SilentlyContinue
            Remove-Item -LiteralPath $kd -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ===================================================================================================== f8
if ($sections -contains 'f8') {
    Write-Wit ''
    Write-Wit '=== F8: can SDRADMIN (or an ordinary SD user) write SD''s locked files?  Opened AS the user (network logon), for write'
    $who = @()
    if ($pw -ne '') { $who += , @('SDRADMIN', $pw) }
    $fx = Read-WitFixtures
    if ($null -ne $fx -and $fx.ContainsKey('zzwitoff')) { $who += , @('zzwitoff', $fx['zzwitoff']) }
    if ($who.Count -eq 0) { Add-WitResult '202' 'F8' 'NOT-MEASURED' 'no password on file for SDRADMIN or zzwitoff' }
    $sys = $script:WitSdsys
    $targets = @(
        @($sys, 0x2, $true), @((Join-Path $sys 'voc'), 0x2, $true), @((Join-Path $sys 'accounts'), 0x2, $true), @((Join-Path $sys '$cred'), 0x2, $true),
        @((Join-Path $sys 'gcat'), 0x2, $true), @((Join-Path $sys 'bp'), 0x2, $true), @((Join-Path $sys 'newvoc'), 0x2, $true), @((Join-Path $sys 'voc_template'), 0x2, $true),
        @((Join-Path $sys 'audit'), 0x2, $false), @((Join-Path $script:WitDataDir 'sd.conf'), 0x2, $false), @((Join-Path $script:WitDataDir 'sd-jobs'), 0x2, $true),
        @((Join-Path $script:WitDataDir 'remote-admin'), 0x2, $true), @((Join-Path $env:ProgramFiles 'SD'), 0x2, $true), @($script:WitSdExe, 0x2, $false))
    foreach ($w in $who) {
        foreach ($t in $targets) {
            if (-not (Test-Path -LiteralPath $t[0])) { continue }
            $e = [SdWit.Native]::OpenAs($w[0], '.', $w[1], $t[0], [uint32]$t[1], [bool]$t[2])
            if ($e -lt 0) { Add-WitResult '202' ('F8: ' + $w[0] + ' writes ' + $t[0]) 'NOT-MEASURED' ('the network logon failed: ' + (-$e)); continue }
            Set-WitCompare '202' ('F8: ' + $w[0] + ' may not write ' + $t[0] + ' (5 = access denied)') '5' ([string]$e)
        }
        $own = Join-Path (Join-Path $script:WitDataDir 'user_accounts') $w[0].ToLower()
        if (Test-Path -LiteralPath $own) {
            $e = [SdWit.Native]::OpenAs($w[0], '.', $w[1], $own, 0x2, $true)
            Set-WitCompare '202' ('F8 control: ' + $w[0] + ' may add a file in its own account directory (0 = allowed)') '0' ([string]$e) -Evidence $own
        }
    }
}

# ===================================================================================================== lockout (F10)
if ($sections -contains 'lockout') {
    Write-Wit ''
    Write-Wit '=== F10: Windows lockout of SDRADMIN'
    $na = (& net.exe accounts 2>&1 | Out-String)
    $th = [regex]::Match($na, 'Lockout threshold:\s*(\S+)').Groups[1].Value
    Write-Wit ('  net accounts: lockout threshold ' + $th)
    if ($pw -eq '') { Add-WitResult '202' 'F10' 'NOT-MEASURED' 'no SDRADMIN password on file' }
    elseif ($th -notmatch '^\d+$' -or [int]$th -eq 0) { Add-WitResult '202' 'F10: Windows locks SDRADMIN after bad passwords' 'NOT-MEASURED' ('this machine''s lockout policy is off (threshold ' + $th + '): Windows locks nobody; the docs should say so') }
    else {
        $n = [int]$th + 1
        $codes = @()
        for ($i = 0; $i -lt $n; $i++) { $codes += [SdWit.Native]::LogonTest('SDRADMIN', '.', ('zz-wrong-' + $i), 3) }
        $e = [SdWit.Native]::LogonTest('SDRADMIN', '.', $pw, 3)
        Set-WitCompare '202' ('F10: after ' + $n + ' bad passwords the right one is refused as locked out (1909)') '1909' ([string]$e) -Evidence ('bad attempts answered ' + (($codes | Sort-Object -Unique) -join ','))
        try { $u = [ADSI]('WinNT://./SDRADMIN,user'); $u.IsAccountLocked = $false; $u.SetInfo() } catch { Write-Wit ('  could not unlock: ' + $_.Exception.Message) }
        $e = [SdWit.Native]::LogonTest('SDRADMIN', '.', $pw, 3)
        Set-WitCompare '202' 'F10: unlocked again for the rest of the sitting' '0' ([string]$e)
    }
}

# ===================================================================================================== keep (and F7 live)
if ($sections -contains 'keep') {
    Write-Wit ''
    Write-Wit '=== remote.ssh off keeps the remote session; remote.sdsys off ends it (about 90 seconds)'
    if ($pw -eq '') { Add-WitResult '202' 'keep' 'NOT-MEASURED' 'no SDRADMIN password on file' }
    else {
        $h = Start-HeldSsh 'sdradmin' $pw
        $in = $h.P.StandardInput
        $in.WriteLine(''); $in.WriteLine('TERM 200,9999'); $in.WriteLine('WHO'); $in.Flush()
        Start-Sleep -Seconds 8
        $in.WriteLine('remote.ssh off'); $in.Flush()
        Start-Sleep -Seconds 25
        $in.WriteLine('WHO'); $in.Flush()
        Start-Sleep -Seconds 8
        $in.WriteLine('remote.ssh on'); $in.Flush()
        Start-Sleep -Seconds 25
        $aliveBefore = -not $h.P.HasExited
        Write-Wit ('  the session is ' + $(if ($aliveBefore) { 'still open' } else { 'GONE' }) + '; now remote.sdsys off at the console')
        $mark = Get-WitAuditMark
        $r = Invoke-WitSd -Commands @('remote.sdsys off') -Label 'F7: remote.sdsys off at the console while an SDRADMIN session is open' -TimeoutSec 300
        $ended = $h.P.WaitForExit(20000)
        if (-not $ended) { try { $in.WriteLine('WHO'); $in.Flush(); Start-Sleep -Seconds 5; $in.WriteLine('OFF'); $in.Close() } catch { } ; $null = $h.P.WaitForExit(15000) }
        else { try { $in.Close() } catch { } }
        $out = ''
        $err = ''
        if ($h.P.HasExited) { $out = $h.Out.Result; $err = $h.Err.Result }
        else { Write-Wit ('  the ssh client (pid ' + $h.P.Id + ') is still running after its stdin closed; its output is not read (left alone)') }
        Remove-Item -LiteralPath $h.Dir -Recurse -Force -ErrorAction SilentlyContinue
        Write-WitRaw 'the held SDRADMIN session' ($out + "`n" + $err)
        $whos = [regex]::Matches($out, '(?m)^\s*\d+\s+sdradmin\b').Count
        if ($whos -ge 2 -and $aliveBefore) { Add-WitResult '202' 'remote.ssh off from the remote session keeps that session (WHO answered after it)' 'PASS' ('WHO answers: ' + $whos) }
        else { Add-WitResult '202' 'remote.ssh off from the remote session keeps that session' 'FAIL' ('WHO answers: ' + $whos + '; open before OFF: ' + $aliveBefore) }
        Add-WitResult '202' 'F7: remote.sdsys off at the console ends a live SDRADMIN session at once' $(if ($ended -and $whos -lt 3) { 'PASS' } else { 'FAIL' }) ('the session ended within 20 s of OFF: ' + $ended + '; WHO answers in all: ' + $whos)
        Set-WitVerdict '202' 'F7: the console OFF printed no failure' $r.Text 'remote-admin: closed|the sshd arm shut' @('did not succeed', 'could not be shut')
    }
}

# ===================================================================================================== off (F7)
if ($sections -contains 'off') {
    Write-Wit ''
    Write-Wit '=== F7: every wall shut after OFF'
    $s = Get-RaStatus
    if ($s -match '(?m)^remote-admin=open') { $null = Invoke-WitSd -Commands @('remote.sdsys off') -Label 'remote.sdsys off' -TimeoutSec 300; $s = Get-RaStatus }
    Write-WitRaw 'remote-admin.ps1 -Status' $s
    Set-WitVerdict '202' 'F7: -Status says remote-admin=closed' $s '(?m)^remote-admin=closed\s*$' @('remote-admin=(open|inconsistent)')
    foreach ($kv in @('account=disabled', 'sdssh=no', 'sshd-arm=closed', 'state=off')) { Set-WitVerdict '202' ('F7: wall ' + $kv) $s ('(?m)^' + [regex]::Escape($kv) + '\s*$') @() }
    Set-WitVerdict '202' 'F7: the broker is not running' $s '(?m)^broker=(disabled|ready|absent)\s*$' @('(?m)^broker=running')
    $t = Get-SshdT 'sdradmin'
    Set-WitVerdict '202' 'F7: sshd -T for sdradmin gives denyusers *' $t '(?m)^denyusers \*\s*$' @()
    if ($pw -ne '') {
        $r = Invoke-SshRaw (Get-Command ssh.exe).Source ($sshOpts + @('sdradmin@localhost', 'whoami')) $pw "WHO`nOFF`n"
        Write-WitRaw ('ssh as SDRADMIN after OFF (exit ' + $r.ExitCode + ')') ($r.Out + "`n" + $r.Err)
        Set-WitVerdict '202' 'F7: ssh as SDRADMIN with its right password is refused after OFF' ($r.Err + ' exit=' + $r.ExitCode) 'Permission denied' @('exit=0\b')
    }
}

# ===================================================================================================== offremote (F7 remote)
if ($sections -contains 'offremote') {
    Write-Wit ''
    Write-Wit '=== F7: ON again (the password is kept: nothing asked), then OFF from the remote session'
    $mark = Get-WitAuditMark
    $r = Invoke-WitSd -Commands @('remote.sdsys on', 'N', 'N') -Label 'remote.sdsys on, the second time (two N lines in case it asks)' -TimeoutSec 300
    Set-WitVerdict '202' 'the second ON opens with no new account' $r.Text 'ssh is open for SDRADMIN' @('did not succeed')
    if ($pw -ne '') {
        $r = Invoke-WitSsh 'sdradmin' $pw @('remote.sdsys off', 'WHO') 'remote.sdsys off from the remote session'
        Start-Sleep -Seconds 10
        $s = Get-RaStatus
        Write-WitRaw 'remote-admin.ps1 -Status' $s
        Set-WitVerdict '202' 'F7: OFF from the remote session shuts every wall' $s '(?m)^remote-admin=closed\s*$' @('remote-admin=(open|inconsistent)')
        $al = @(Get-WitAuditSince $mark | Where-Object { $_ -match 'remote\.sdsys off' })
        Set-WitVerdict '202' 'F7: the audit says remote.sdsys off status=0 from=remote' ($al -join "`n") 'remote\.sdsys off status=0 from=remote' @()
    }
}

Add-WitResult '202' 'F9: a job definition older than 120 s, or used twice, is refused by K$JOB.MARK' 'NOT-MEASURED' 'needs a hand-made definition run by an SDSYS batch logon (the broker''s own route); covered by the free guard, not by this sitting'
$code = Complete-Wit
exit $code
