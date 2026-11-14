# witness-vm-user.ps1 - the ORDINARY (unelevated) script of the Core VM witness sitting (13 Nov 2026): what an ordinary
# account sees.
#
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-user.ps1 -Only <section[,section]>
#
# An ORDINARY UNELEVATED PowerShell in the VM.  Prerequisite, printed and refused if missing: witness-vm-admin.ps1 -Only
# fixtures has run (elevated) and made the fixture accounts zzwitoff (OS switch OFF) and zzwiton (OS and SH on), their probe
# programs, and C:\SD-witness\fixtures.json.  Everything SD-side goes over ssh into this VM's own sshd, as those accounts.
#
# Sections, by row (RELEASE_1.1):
#   ospath     241 (OSPATH keys G2, G5, G13, G18 and a junction refused with ER$PERM for the OFF account, allowed for the ON
#              control), 251 (OPENTEMP T1, T2, T5: ELSE with ER$PERM, nothing made), 263 (DIGEST of a file outside the account)
#   cim        242: CIM cmdlets (Get-NetTCPConnection, Get-NetFirewallProfile, Get-ScheduledTask) in an ssh session of Core
#   pipes      what an unelevated non-administrator token gets from the service pipes (247 sd-audit, 253 sd-runin, 246 sd-ai,
#              202 sd-radmin), and 253(b) F4: sd.exe -RUNIN refused
#   audit      247: a forged uid-0 record sent by zzwiton (a sdusers member) through SH, and an ssh session's own audit line;
#              both are judged by witness-vm-admin.ps1 -Only afterconsole (the trail is not readable unelevated)
#
# Output: every ssh command, SD's raw answer, the disk state before and after, one [VERDICT] line per check; a summary and
# CSV in C:\SD-witness\logs.  Exit 0 passed, 1 a FAIL or FINDING, 2 could not run or nothing measured.  It never ends an SD
# process: every ssh session ends with OFF.
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting.  Parse-checked; not run (it needs the VM).
# END-HISTORY

param([string[]]$Only = @(), [switch]$List)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')
. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

$known = @('ospath', 'cim', 'pipes', 'audit')
if ($List) { Write-Host ('sections: ' + ($known -join ',')); exit 0 }
$sections = Resolve-WitSections $Only $known
if ($null -eq $sections) { exit 2 }
Start-Wit 'witness-vm-user' $sections

if (Test-WitElevated) {
    Write-Wit 'CANNOT RUN: this PowerShell is ELEVATED.  These checks are what an ordinary token sees; open an ordinary PowerShell (not "Run as administrator").'
    exit 2
}
$fix = Read-WitFixtures
if ($null -eq $fix -or -not $fix.ContainsKey('zzwitoff') -or -not $fix.ContainsKey('zzwiton')) {
    Write-Wit ('CANNOT RUN: no fixture passwords at ' + (Get-WitFixturePath) + ' readable by ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name + '.')
    Write-Wit '  First, in an ELEVATED PowerShell (SDSYS signed in once this boot):'
    Write-Wit ('  powershell -ExecutionPolicy Bypass -File ' + (Join-Path $PSScriptRoot 'witness-vm-admin.ps1') + ' -Only fixtures')
    exit 2
}
$vm = $env:COMPUTERNAME
$userDir = Join-Path $script:WitDataDir 'user_accounts'
$results = @{ SshNonce = ''; ForgeNonce = ''; ForgePid = ''; ForgeIdentity = '' }
$resultsPath = Join-Path $script:WitRoot 'user-results.json'
if (Test-Path -LiteralPath $resultsPath) {
    try { $old = Get-Content -LiteralPath $resultsPath -Raw | ConvertFrom-Json; foreach ($k in @($results.Keys)) { if ($old.$k) { $results[$k] = [string]$old.$k } } } catch { }
}

# ===================================================================================================== ospath (241, 251, 263)
if ($sections -contains 'ospath') {
    Write-Wit ''
    Write-Wit '=== ospath: OSPATH, OPENTEMP and DIGEST outside the account, OS switch OFF (zzwitoff) against ON (zzwiton)'
    $runs = @{}
    foreach ($pair in @(@('zzwiton', 'out-on'), @('zzwitoff', 'out-off'))) {
        $acct = Join-Path $userDir $pair[0]
        $out = Join-Path $script:WitRoot $pair[1]
        $probes = Get-WitDProbes $acct $out
        $state = @{}
        foreach ($f in @('o.txt', 'd5.txt', 'j5.txt', 'm13', 't5.tmp')) { $state[$f] = Test-Path -LiteralPath (Join-Path $out $f) }
        Write-Wit ('  ' + $pair[0] + ' before: ' + (($state.Keys | Sort-Object | ForEach-Object { $_ + '=' + $state[$_] }) -join ' '))
        $cmds = @()
        foreach ($p in $probes) { $cmds += ('BASIC bp ' + $p.Name); $cmds += ('RUN bp ' + $p.Name) }
        $r = Invoke-WitSsh -User $pair[0] -Password $fix[$pair[0]] -Commands $cmds -Label ($pair[0] + ': compile and run the ' + $probes.Count + ' probes (about 30 seconds)')
        $txt = ''
        if ($null -ne $r) { $txt = $r.Out }
        $after = @{}
        foreach ($f in @('o.txt', 'd5.txt', 'j5.txt', 'm13', 't5.tmp')) { $after[$f] = Test-Path -LiteralPath (Join-Path $out $f) }
        Write-Wit ('  ' + $pair[0] + ' after:  ' + (($after.Keys | Sort-Object | ForEach-Object { $_ + '=' + $after[$_] }) -join ' '))
        $compiled = [regex]::Matches($txt, 'Compiled 1 program\(s\) with no errors').Count
        Write-Wit ('  ' + $pair[0] + ': ' + $compiled + ' of ' + $probes.Count + ' probes compiled')
        $f = @{}
        foreach ($p in $probes) { $f[$p.Id] = Get-WitProbeFields $txt $p.Id }
        $runs[$pair[0]] = @{ F = $f; After = $after; Compiled = $compiled; Text = $txt }
    }

    $on = $runs['zzwiton']
    $off = $runs['zzwitoff']
    $v = { param($run, $id, $i) if ($null -eq $run.F[$id]) { return $null }; return $run.F[$id][$i] }
    $hex = '^[0-9a-fA-F]{64}$'

    # The controls first: what the ON account reaches shows the probes can see a success.
    $ctl = @{
        g2 = ((& $v $on 'g2' 0) -eq '1')
        g5 = ((& $v $on 'g5' 0) -eq '1' -and -not $on.After['d5.txt'])
        g13 = ((& $v $on 'g13' 0) -eq '1' -and $on.After['m13'])
        g18 = ($null -ne $on.F['g18'] -and (& $v $on 'g18' 2) -ne '1')
        dg = ([string](& $v $on 'dg' 0) -match $hex)
        t1 = ((& $v $on 't1' 0) -eq 'then')
        t5 = ((& $v $on 't5' 0) -eq 'then' -and -not $on.After['t5.tmp'])
        t2 = ((& $v $on 't2' 0) -eq 'then' -and (& $v $on 't2' 1) -eq 'then' -and (& $v $on 't2' 2) -ne (& $v $on 't2' 3))
    }
    foreach ($k in ($ctl.Keys | Sort-Object)) {
        $row = '241'
        if ($k -like 't*') { $row = '251' }
        if ($k -like 'd*') { $row = '263' }
        $vv = 'FAIL'
        if ($ctl[$k]) { $vv = 'PASS' }
        Add-WitResult $row ('control, OS switch ON (zzwiton): ' + $k + ' reaches outside the account') $vv ('R' + $k + '[' + (@($on.F[$k]) -join '|') + ']')
    }
    $judge = {
        param($row, $id, $what, $okNow, $ctlOk)
        $ev = 'R' + $id + '[' + (@($off.F[$id]) -join '|') + ']'
        if ($null -eq $off.F[$id]) { Add-WitResult $row $what 'NOT-MEASURED' ('the probe printed nothing (compiled ' + $off.Compiled + ')'); return }
        if (-not $ctlOk) { Add-WitResult $row $what 'NOT-MEASURED' ('the ON control for ' + $id + ' failed, so a refusal here proves nothing. ' + $ev); return }
        $vv = 'FAIL'
        if ($okNow) { $vv = 'PASS' }
        Add-WitResult $row $what $vv $ev
    }
    & $judge '241' 'g2' 'G2 outside, switch OFF: key 2 answers 0 with ER$PERM' (((& $v $off 'g2' 0) -eq '0') -and ((& $v $off 'g2' 2) -eq '1')) $ctl.g2
    & $judge '241' 'g5' 'G5 outside, switch OFF: ER$PERM and the file is NOT deleted' (((& $v $off 'g5' 2) -eq '1') -and $off.After['d5.txt']) $ctl.g5
    & $judge '241' 'g13' 'G13 outside, switch OFF: ER$PERM and no folder made' (((& $v $off 'g13' 2) -eq '1') -and -not $off.After['m13']) $ctl.g13
    & $judge '241' 'g18' 'G18 outside, switch OFF: the owner is null with ER$PERM' (((& $v $off 'g18' 0) -eq '') -and ((& $v $off 'g18' 2) -eq '1')) $ctl.g18
    & $judge '263' 'dg' 'DIGEST of a file outside the account, switch OFF: null with ER$PERM' (((& $v $off 'dg' 0) -eq '') -and ((& $v $off 'dg' 2) -eq '1')) $ctl.dg
    & $judge '251' 't1' 'T1 OPENTEMP with no path (TEMPDIR is outside), switch OFF: ELSE with ER$PERM' (((& $v $off 't1' 0) -eq 'else') -and ((& $v $off 't1' 2) -eq '1')) $ctl.t1
    & $judge '251' 't5' 'T5 OPENTEMP outside the account, switch OFF: ELSE with ER$PERM and nothing made' (((& $v $off 't5' 0) -eq 'else') -and ((& $v $off 't5' 2) -eq '1') -and -not $off.After['t5.tmp']) $ctl.t5
    & $judge '251' 't2' 'T2 two OPENTEMPs, switch OFF: both ELSE' (((& $v $off 't2' 0) -eq 'else') -and ((& $v $off 't2' 1) -eq 'else')) $ctl.t2
    # The inside control for DIGEST: an OFF account still digests its own file, so the refusal above is the OUTSIDE rule.
    $di = [string](& $v $off 'di' 0)
    Set-WitVerdict '263' 'DIGEST of a file INSIDE the account, switch OFF, is allowed (the refusal is the outside rule, not a broken probe)' $di $hex @()

    # The junction: inside the account by name, outside by where it leads.
    $j2 = $off.F['j2']; $j5 = $off.F['j5']; $dj = $off.F['dj']
    if ($null -eq $j2 -or $null -eq $j5 -or $null -eq $dj) { Add-WitResult '241' 'a junction inside the account that leads outside' 'NOT-MEASURED' 'a junction probe printed nothing' }
    else {
        $leak = @()
        if ($j2[2] -ne '1' -and $j2[0] -eq '1') { $leak += 'key 2 saw the outside file through the junction' }
        if (-not $off.After['j5.txt']) { $leak += 'key 5 DELETED the outside file through the junction' }
        if ([string]$dj[0] -match $hex) { $leak += 'DIGEST read the outside file through the junction' }
        $ev = 'Rj2[' + ($j2 -join '|') + '] Rj5[' + ($j5 -join '|') + '] Rdj[' + ($dj -join '|') + '] j5.txt still there: ' + $off.After['j5.txt']
        if ($leak.Count) { Add-WitResult '241' 'a junction inside the OFF account that leads outside is refused like the outside path' 'FINDING' (($leak -join '; ') + '. ' + $ev) }
        else { Add-WitResult '241' 'a junction inside the OFF account that leads outside is refused like the outside path' 'PASS' $ev }
    }
}

# ===================================================================================================== cim (242)
if ($sections -contains 'cim') {
    Write-Wit ''
    Write-Wit '=== cim: CIM cmdlets inside an ssh session of Core (row 242; zzwiton, SH on)'
    $cmds = @('SH Get-Date -Format yyyy', 'SH Get-NetTCPConnection -LocalPort 22 -State Listen', 'SH Get-NetFirewallProfile -Name Private', 'SH Get-ScheduledTask -TaskName ScheduledDefrag')
    $r = Invoke-WitSsh -User 'zzwiton' -Password $fix['zzwiton'] -Commands $cmds -Label 'one non-CIM control and three CIM cmdlets'
    # 14 Nov 26: the first run scored two of these PASS on SD's ECHO of the typed command (":SH Get-NetTCPConnection -LocalPort 22 -State
    # Listen" holds 22 and Listen; the echo of the third holds ScheduledDefrag) while all three cmdlets failed on stderr ("Cannot connect to
    # CIM server. Access denied").  So the anchors read the output with the echo lines (":...") taken out, each is a row only the cmdlet
    # prints, and the disqualifiers are looked for in stdout AND stderr.
    $t = ''
    if ($null -ne $r) { $t = (@(([string]$r.Out) -split "`r?`n") | Where-Object { $_ -notmatch '^\s*:' }) -join "`n" }
    if ($t -notmatch '(?m)^\s*20\d\d\s*$') { Add-WitResult '242' 'SH runs PowerShell in the ssh session (control: Get-Date)' 'NOT-MEASURED' 'Get-Date printed no year: SH did not run, so the CIM rows say nothing' }
    else {
        Add-WitResult '242' 'SH runs PowerShell in the ssh session (control: Get-Date)' 'PASS' ([regex]::Match($t, '(?m)^\s*20\d\d\s*$').Value.Trim())
        $err = if ($null -ne $r) { [string]$r.Err } else { '' }
        foreach ($c in @(
                @('Get-NetTCPConnection', 'Get-NetTCPConnection works in an ssh session (sshd''s port 22 Listen)', '(?m)^\S+\s+22\s+\S+\s+\d+\s+Listen\b'),
                @('Get-NetFirewallProfile', 'Get-NetFirewallProfile works in an ssh session', '(?m)^Name\s*:\s*Private\s*$'),
                @('Get-ScheduledTask', 'Get-ScheduledTask works in an ssh session', '(?m)^\\Microsoft\\Windows\\Defrag\\\s+ScheduledDefrag\b'))) {
            $mine = [regex]::Match($err, '(?m)^' + [regex]::Escape($c[0]) + '\s*:\s*(.*)$')
            if ($mine.Success) { Add-WitResult '242' $c[1] 'FAIL' ('stderr: ' + $c[0] + ' : ' + $mine.Groups[1].Value.Trim()) }
            elseif ($t -match $c[2]) { Add-WitResult '242' $c[1] 'PASS' ('its own output row: ' + [regex]::Match($t, $c[2]).Value.Trim()) }
            else { Add-WitResult '242' $c[1] 'FAIL' ('no output row /' + $c[2] + '/ and no error naming it; see the raw output above') }
        }
    }
}

# ===================================================================================================== pipes
if ($sections -contains 'pipes') {
    Write-Wit ''
    Write-Wit '=== pipes: the service pipes as an ordinary, unelevated token'
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sdu = Get-WitSid 'sdusers'
    $inSdusers = @($me.Groups | Where-Object { $_.Value -eq $sdu }).Count -gt 0
    Write-Wit ('  ' + $me.Name + ': sdusers in this token ' + $inSdusers + '; Administrators enabled ' + (Test-WitElevated))
    $client = 0x0001 -bor 0x0002 -bor 0x0080 -bor 0x00100000
    $e = [SdWit.Native]::PipeProbe('\\.\pipe\sd-runin', $client)
    Set-WitCompare '253' 'F4: an unelevated user cannot open the run.in request pipe (5 = access denied)' '5' ([string]$e)
    $e = [SdWit.Native]::PipeProbe('\\.\pipe\sd-radmin', $client)
    if ($e -eq 2) { Add-WitResult '202' 'an ordinary user cannot open the remote administration broker''s pipe' 'NOT-MEASURED' 'the broker is not running (remote administration is off): witness-vm-radmin.ps1 measures it while ON' }
    else { Set-WitCompare '202' 'an ordinary user cannot open the remote administration broker''s pipe' '5' ([string]$e) }
    foreach ($pn in @(@('sd-audit', '247'), @('sd-ai', '246'))) {
        $e = [SdWit.Native]::PipeProbe(('\\.\pipe\' + $pn[0]), $client)
        $want = '5'
        if ($inSdusers) { $want = '0' }
        Set-WitCompare $pn[1] ('an unelevated token ' + $(if ($inSdusers) { 'IN' } else { 'NOT in' }) + ' sdusers opens \\.\pipe\' + $pn[0] + ' as a client: ' + $(if ($inSdusers) { 'allowed' } else { 'refused' })) $want ([string]$e)
        $e2 = [SdWit.Native]::PipeProbe(('\\.\pipe\' + $pn[0]), 0x0004)
        Set-WitCompare $pn[1] ('nobody but the server may add an instance of \\.\pipe\' + $pn[0] + ' (FILE_CREATE_PIPE_INSTANCE refused)') '5' ([string]$e2)
    }
    # 253(b) F4: the child entry mode from an ordinary token.  Redirected, so no window of its own; never killed.
    $o = Join-Path $env:TEMP ('witness-runin-' + $PID + '.out')
    $er = Join-Path $env:TEMP ('witness-runin-' + $PID + '.err')
    $p = Start-Process -FilePath $script:WitSdExe -ArgumentList @('-RUNIN', 'zzrunin', '-QUIET', 'debug', 'bp', 'zzw253') -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $er
    if (-not $p.WaitForExit(20000)) { Add-WitResult '253' 'F4: sd.exe -RUNIN from an ordinary user is refused' 'NOT-MEASURED' ('sd.exe pid ' + $p.Id + ' still runs after 20 s: LEFT ALONE, not killed; close its window by hand') }
    else {
        $t = ((Get-Content -LiteralPath $o -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $er -Raw -ErrorAction SilentlyContinue))
        Write-WitRaw ('sd.exe -RUNIN (exit ' + $p.ExitCode + ')') $t
        Set-WitVerdict '253' 'F4: sd.exe -RUNIN from an ordinary user is refused' $t 'sd: -RUNIN (is only for run\.in''s debugged program|runs "debug|cannot be given)|This command needs an elevated session' @('zzw253 done', 'Compiled')
    }
    Remove-Item -LiteralPath $o, $er -Force -ErrorAction SilentlyContinue
}

# ===================================================================================================== audit (247)
if ($sections -contains 'audit') {
    Write-Wit ''
    Write-Wit '=== audit: records the admin script judges (row 247): an ssh session''s own line, and a forged record from a sdusers member'
    $n1 = 'zzw247s' + (Get-Random -Minimum 100000 -Maximum 999999)
    $r = Invoke-WitSsh -User 'zzwitoff' -Password $fix['zzwitoff'] -Commands @(('LOGTO ' + $n1)) -Label 'an ssh session LOGTOs to an account that does not exist (an audited refusal)'
    if ($null -ne $r -and $r.Out -match 'User not allowed in requested account') { $results.SshNonce = $n1; Add-WitResult '247' ('ssh session audit line sent (nonce ' + $n1 + '); judged by the admin script''s afterconsole') 'INFO' 'SD answered 10003' }
    else { Add-WitResult '247' 'ssh session audit line' 'NOT-MEASURED' 'SD did not answer 10003 to the LOGTO (see the raw output)' }
    $n2 = 'zzw247m' + (Get-Random -Minimum 100000 -Maximum 999999)
    $forge = Join-Path $PSScriptRoot 'witness-vm-forge.ps1'
    $r = Invoke-WitSsh -User 'zzwiton' -Password $fix['zzwiton'] -Commands @(('SH powershell -NoProfile -ExecutionPolicy Bypass -File ' + $forge + ' -Nonce ' + $n2)) -Label 'a forged uid-0 record from inside zzwiton''s session (about 15 seconds: C# is compiled once)'
    $m = $null
    if ($null -ne $r) { $m = [regex]::Match($r.Out, 'FORGE identity=(\S+) pid=(\d+) open=(\d+) write=(\d+) answer=(-?\d+)') }
    if ($null -eq $m -or -not $m.Success) { Add-WitResult '247' 'a forged record from a sdusers member' 'NOT-MEASURED' 'the forge script printed no FORGE line (SH or PowerShell did not run)' }
    else {
        $results.ForgeNonce = $n2; $results.ForgePid = $m.Groups[2].Value; $results.ForgeIdentity = $m.Groups[1].Value
        Set-WitCompare '247' 'a sdusers member may send a record to the writer (answer Y = 89)' '89' $m.Groups[5].Value -Evidence $m.Value
        Add-WitResult '247' 'the forger ran as zzwiton' $(if ($m.Groups[1].Value -ieq ($vm + '\zzwiton')) { 'PASS' } else { 'FAIL' }) ('wanted ' + $vm + '\zzwiton, got ' + $m.Groups[1].Value)
    }
    ($results | ConvertTo-Json) | Set-Content -LiteralPath $resultsPath -Encoding ASCII
    Write-Wit ('  nonces for the admin script: ' + $resultsPath)
}

$code = Complete-Wit
exit $code
