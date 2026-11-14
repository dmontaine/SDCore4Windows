# witness-vm-admin.ps1 - the ELEVATED script of the Core VM witness sitting (13 Nov 2026).
#
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-admin.ps1 -Only <section[,section]>
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-admin.ps1 -List
#
# ELEVATED PowerShell, in the VM, with the SDSYS Windows account signed in once this boot (switch user to SDSYS, sign in,
# switch back: the seat rule, sdsys-seat.ps1).  The sitting sheet .claude/vm-sitting-core-sheet-20261113.md names the
# sections for each step and the order.  -Only is required: a run with no section runs nothing and exits 2.
#
# Sections, by row (RELEASE_1.1):
#   context      the install under test (assert-current, sd.exe hash, services, sd.conf), and proves the SDSYS seat
#   fixtures     the fixture accounts (zzwitoff: OS off; zzwiton: OS and SH on; zzwitapi: API; zzwitsh: group, SH on, SDSYS a
#                member; zzrunin: group) and the group-D probe programs (241, 251, 263) - needed by most other sections
#   voc          227/262: which HOME tile verbs SDSYS's VOC holds (the console look is the sheet's)
#   api          243 (12950/12944), 278 (the restart question: local from off asks; on twice asks once), 266 (an API session's
#                @WHO lower case), 247 (an API session's line stamped with its own user)
#   runin201     201: compile.dict, a trigger, no.catalog (sitting 2's block 1, through the seat)
#   job222       222: a backup-all job run by Task Scheduler as SDSYS
#   print219     219: SPOOLER set to a "Microsoft Print To PDF" printer on a file port (never paper), and a refusal leg
#   audit247     247 (the writer's pipe, its DACL, remote clients refused, a forged claim stamped with the real user, an injected
#                line flattened, a foreign tree answered N, LOCK.TRACER through the service, timing, the rate bound) and 240
#                (a control character from a session reaches the trail as '?')
#   logto275     275 (SDSYS LOGTOs into a group account; SYSTEM reads that sd.exe's token while it waits: elevated / High or not) and 266 (LOGTO in, WHO
#                lower case, the logto and elevation-released audit lines)
#   gates266     266: update.accounts all, then the tool.gates verbs in SDSYS and in an account
#   shared260    260: delete.account shared refused (12522)
#   ai246        246: F10 delivered, F3 server owner, F5 remote refused, F6 the gate live, F4 squat, F1 DPAPI scope
#   runin253     253(b): sdrunin, its rights, the pipe, F4 (sd.exe -RUNIN refused), the debug probe compiled for the console
#   mark         writes the audit mark the console steps are read against (run it just before the SDSYS console steps)
#   runinchild   253(b) F1/F2/F3/F6: run from a second elevated window WHILE the console's run.in debug is stopped in the debugger
#   afterconsole 197 (the PDEBUG store's ACL), 253(b) (the probe's results and audit), 228/218/221/201 audit lines, 247 (the
#                user script's forged and ssh lines stamped with their real users)
#   cleanup      deletes the fixture accounts, the printer, and the passwords file
#
# What it prints: every SD command it sends (passwords never), SD's raw answer every time, the before/after state it
# compared, and one [VERDICT] line per check with its evidence; a summary and a results CSV beside the log in
# C:\SD-witness\logs.  Exit 0 measured and passed, 1 a FAIL or FINDING, 2 could not run or nothing measured.
#
# It never ends an SD process: a session it starts ends with OFF; a seat that times out is reported and left alone
# (memory never-stop-process-an-sd-session).  Printing goes to a PDF file printer only (memory
# check-tests-for-physical-side-effects).
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting.  Parse-checked; not run (it needs the VM).
# END-HISTORY

param(
    [string[]]$Only = @(),
    [switch]$List
)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

$known = @('context', 'fixtures', 'voc', 'api', 'runin201', 'job222', 'print219', 'audit247', 'logto275', 'gates266', 'shared260',
           'ai246', 'runin253', 'mark', 'runinchild', 'afterconsole', 'cleanup')
if ($List) { Write-Host ('sections: ' + ($known -join ',')); exit 0 }
$sections = Resolve-WitSections $Only $known
if ($null -eq $sections) { exit 2 }

Start-Wit 'witness-vm-admin' $sections
if (-not (Test-WitElevated)) {
    Write-Wit 'CANNOT RUN: this PowerShell is not elevated.  Open PowerShell with "Run as administrator" and run it again.'
    exit 2
}
if (-not (Test-Path -LiteralPath $script:WitSdExe)) { Write-Wit ('CANNOT RUN: there is no ' + $script:WitSdExe + ' - SD is not installed.'); exit 2 }

$me = [Security.Principal.WindowsIdentity]::GetCurrent()
$meSid = $me.User.Value
$vm = $env:COMPUTERNAME
$fixDir = $script:WitRoot
foreach ($d in @($fixDir, (Join-Path $fixDir 'logs'), (Join-Path $fixDir 'sys'))) { if (-not (Test-Path -LiteralPath $d)) { $null = New-Item -ItemType Directory -Path $d -Force } }
# The SYSTEM task's reports: SYSTEM and Administrators only.
try {
    $sa = New-Object Security.AccessControl.DirectorySecurity
    $sa.SetAccessRuleProtection($true, $false)
    foreach ($s in @('S-1-5-18', 'S-1-5-32-544')) { $sa.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($s)), 'FullControl', 'ContainerInherit,ObjectInherit', 'None', 'Allow'))) }
    Set-Acl -LiteralPath (Join-Path $fixDir 'sys') -AclObject $sa
} catch { Write-Wit ('  note: the sys folder ACL could not be set: ' + $_.Exception.Message) }

$userDir = Join-Path $script:WitDataDir 'user_accounts'
$groupDir = Join-Path $script:WitDataDir 'group_accounts'
$sdConf = Join-Path $script:WitDataDir 'sd.conf'
$systemScript = Join-Path $PSScriptRoot 'witness-vm-system.ps1'

# The fixture accounts and what each is for.
$FixUsers = @(
    @{ Name = 'zzwitoff'; Route = 'SSH'; Gates = 'bp-on'; Why = 'an ordinary account with its OS switch OFF (rows 241, 251, 263; the 246 gate)' }
    @{ Name = 'zzwiton'; Route = 'SSH'; Gates = 'bp-on os-on sh-on'; Why = 'the control with OS access and SH on (rows 241, 251, 263 controls; 242; 247 forge)' }
    @{ Name = 'zzwitapi'; Route = 'API'; Gates = ''; Why = 'an API account (rows 266, 247)' }
)

# --------------------------------------------------------------------------------------------- gates before any section

$seatSections = @('fixtures', 'voc', 'api', 'runin201', 'job222', 'print219', 'audit247', 'logto275', 'gates266', 'shared260', 'ai246', 'runin253', 'cleanup', 'context')
$needSeat = @($sections | Where-Object { $seatSections -contains $_ }).Count -gt 0
$needCurrent = @($sections | Where-Object { @('runinchild', 'afterconsole', 'mark', 'cleanup') -notcontains $_ }).Count -gt 0

if ($needCurrent) {
    Write-Wit ''
    Write-Wit 'assert-current: is the installed SD the build of this source copy?  (a few seconds)'
    $ac = Join-Path $PSScriptRoot 'assert-current.ps1'
    $acOut = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ac 2>&1 | ForEach-Object { [string]$_ }
    $acRc = $LASTEXITCODE
    Write-WitRaw ('assert-current.ps1 (exit ' + $acRc + ')') ($acOut -join "`n")
    if ($acRc -ne 0) {
        Write-Wit 'CANNOT RUN: assert-current did not say the install is current (exit 0).  A result from a stale install is void;'
        Write-Wit '  refresh the repo copy (sheet step 0) or install the installer built from it, then run this again.'
        exit 2
    }
}

if ($needSeat) {
    Write-Wit ''
    Write-Wit 'proving the SDSYS seat (a scheduled task inside SDSYS''s own session; about 5 seconds)'
    $w = Invoke-WitSd -Commands @('WHO') -Label 'WHO through the seat' -TimeoutSec 90
    if (-not $w.Ok -or $w.Text -notmatch '(?m)^\s*\d+\s+SDSYS\b' -or $w.Text -match 'restricted to privileged users') {
        Write-Wit 'CANNOT RUN: the seat did not answer WHO as SDSYS.  Sign in to Windows as SDSYS once (switch user), switch back, and run again.'
        exit 2
    }
}

function Get-SdConfText { try { return [IO.File]::ReadAllText($sdConf) } catch { return '' } }
function Get-ApiPort {
    $t = Get-SdConfText
    $m = [regex]::Match($t, '(?m)^\s*APIPORT\s*=\s*(\d+)')
    if ($m.Success) { return [int]$m.Groups[1].Value }
    return 0
}
function Get-Fix([string]$Name) {
    $f = Read-WitFixtures
    if ($null -eq $f -or -not $f.ContainsKey($Name)) { return '' }
    return $f[$Name]
}
function Get-AccountDir([string]$Name) {
    $u = Join-Path $userDir $Name
    if (Test-Path -LiteralPath $u) { return $u }
    return (Join-Path $groupDir $Name)
}
function Test-Registered([string]$Name) { return (Test-Path -LiteralPath (Join-Path (Join-Path $script:WitSdsys 'accounts') $Name)) }
function Test-WinUser([string]$Name) { try { $null = Get-LocalUser -Name $Name -ErrorAction Stop; return $true } catch { return $false } }

# ===================================================================================================== context
if ($sections -contains 'context') {
    Write-Wit ''
    Write-Wit '=== context: the install under test'
    $h = (Get-FileHash -LiteralPath $script:WitSdExe -Algorithm SHA256).Hash
    $fi = Get-Item -LiteralPath $script:WitSdExe
    Write-Wit ('  sd.exe ' + $script:WitSdExe + '  sha256 ' + $h + '  written ' + $fi.LastWriteTime.ToString('s'))
    foreach ($k in @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'SD*' })) {
        Write-Wit ('  installed: ' + $k.DisplayName + '  version ' + $k.DisplayVersion + '  at ' + $k.InstallLocation)
    }
    $head = ''
    try { $head = (Get-Content -LiteralPath '\\vboxsvr\repo\.git\HEAD' -ErrorAction Stop) -join '' } catch { $head = '(the repo share is not readable)' }
    Write-Wit ('  repo share HEAD: ' + $head)
    foreach ($s in @('SD', 'sd-ai', 'sshd')) {
        $c = Get-CimInstance Win32_Service -Filter ("Name='" + $s + "'") -ErrorAction SilentlyContinue
        if ($null -eq $c) { Write-Wit ('  service ' + $s + ': absent') } else { Write-Wit ('  service ' + $s + ': ' + $c.State + ' ' + $c.StartMode + ' as ' + $c.StartName + '  ' + $c.PathName) }
    }
    Write-WitRaw $sdConf (Get-SdConfText)
    Add-WitResult 'context' 'the SDSYS seat answers WHO as SDSYS and assert-current passed' 'INFO' 'see the raw WHO and assert-current output above'
}

# ===================================================================================================== fixtures
if ($sections -contains 'fixtures') {
    Write-Wit ''
    Write-Wit '=== fixtures: accounts and probes (CREATE.ACCOUNT through the seat; each takes about 10 seconds)'
    $fix = Read-WitFixtures
    if ($null -eq $fix) { $fix = @{} }
    foreach ($u in $FixUsers) {
        $n = $u.Name
        $recBefore = Test-Registered $n
        $winBefore = Test-WinUser $n
        if ($recBefore -or $winBefore) {
            if ($fix.ContainsKey($n)) { Write-Wit ('  ' + $n + ' is already there (register ' + $recBefore + ', Windows ' + $winBefore + ') and its password is on file: kept.'); continue }
            Add-WitResult 'fixtures' ($n + ' exists from an earlier run with no password on file') 'NOT-MEASURED' 'run -Only cleanup, then -Only fixtures again'
            continue
        }
        $pw = New-SdTestPassword
        $line = ('CREATE.ACCOUNT USER ' + $n + ' ' + $u.Route + ' ' + $u.Gates).Trim()
        $null = Invoke-WitSd -Commands @($line, $pw, $pw) -Label ('create ' + $n + ': ' + $u.Why) -Secrets @($pw) -TimeoutSec 180
        $recAfter = Test-Registered $n
        $winAfter = Test-WinUser $n
        $ok = ($recAfter -and $winAfter)
        $v = 'FAIL'
        if ($ok) { $v = 'PASS'; $fix[$n] = $pw }
        Add-WitResult 'fixtures' ('CREATE.ACCOUNT USER ' + $n) $v ('register record before=' + $recBefore + ' after=' + $recAfter + '; Windows user before=' + $winBefore + ' after=' + $winAfter)
    }
    foreach ($g in @('zzwitsh', 'zzrunin')) {
        if (-not (Test-Registered $g)) {
            $null = Invoke-WitSd -Commands @(('CREATE.ACCOUNT GROUP ' + $g + ' NO.QUERY')) -Label ('create group ' + $g)
        }
        Set-WitCompare 'fixtures' ('group account ' + $g + ' is registered') 'True' ([string](Test-Registered $g)) -Evidence (Join-Path (Join-Path $script:WitSdsys 'accounts') $g)
    }
    $r = Invoke-WitSd -Commands @('MODIFY.ACCOUNT zzwitsh sh-on', 'MODIFY.ACCOUNT zzwitsh ADD sdsys') -Label 'zzwitsh: SH on, and SDSYS a member (for 275 and 266)'
    # 13 Nov 26: a GROUP account's Windows group is sdg_<name> (createa; "sdsys added to group sdg_zzwitsh"), not sdu_.
    $mem = Get-WitGroupMembers 'sdg_zzwitsh'
    Set-WitCompare 'fixtures' 'SDSYS is a member of zzwitsh''s Windows group sdg_zzwitsh' 'True' ([string]($mem -contains 'sdsys')) -Evidence ('members: ' + ($mem -join ','))

    # Group D: the folders outside each account, the junction inside it pointing out, the inside file, and the probes.
    foreach ($pair in @(@('zzwitoff', 'out-off'), @('zzwiton', 'out-on'))) {
        $acct = Join-Path $userDir $pair[0]
        $out = Join-Path $fixDir $pair[1]
        if (-not (Test-Path -LiteralPath $acct)) { Add-WitResult 'fixtures' ('probes for ' + $pair[0]) 'NOT-MEASURED' ('no account directory ' + $acct); continue }
        if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force -ErrorAction SilentlyContinue }
        $null = New-Item -ItemType Directory -Path $out -Force
        foreach ($f in @('o.txt', 'd5.txt', 'j5.txt')) { Set-Content -LiteralPath (Join-Path $out $f) -Value 'zzwit outside file' -Encoding ASCII }
        Set-Content -LiteralPath (Join-Path $acct 'zzin.txt') -Value 'zzwit inside file' -Encoding ASCII
        $j = Join-Path $acct 'zzjunc'
        if (Test-Path -LiteralPath $j) { cmd.exe /c rmdir "$j" | Out-Null }
        $null = New-Item -ItemType Junction -Path $j -Target $out
        $written = 0
        foreach ($p in (Get-WitDProbes $acct $out)) {
            try { Write-WitBasic $acct $p.Name $p.Lines; $written++ } catch { Write-Wit ('  could not write ' + $p.Name + ': ' + $_.Exception.Message) }
        }
        $jt = ''
        try { $jt = [string](Get-Item -LiteralPath $j).Target } catch { }
        Add-WitResult 'fixtures' ($pair[0] + ': ' + $written + ' probe programs, the outside folder and the junction') 'INFO' ('outside ' + $out + '; junction ' + $j + ' -> ' + $jt)
    }
    if ($fix.Count -gt 0) {
        Save-WitFixtures $fix $meSid
        Write-Wit ('  passwords of the fixture accounts: ' + (Get-WitFixturePath) + ' (SYSTEM, Administrators and ' + $me.Name + ' only; -Only cleanup deletes it)')
    }
}

# ===================================================================================================== voc (227, 262)
if ($sections -contains 'voc') {
    Write-Wit ''
    Write-Wit '=== voc: the HOME tiles SDSYS should see (rows 227, 262)'
    $r = Invoke-WitSd -Commands @('CT VOC tool.ai', 'CT VOC tool.audit', 'CT VOC home') -Label 'the tile verbs in SDSYS''s VOC'
    if ($r.Ok) {
        $ai = ($r.Text -match '\$tool_ai\b')
        $au = ($r.Text -match '\$tool_audit\b')
        Add-WitResult '262' ('SDSYS''s VOC has tool.ai: ' + $ai + '; tool.audit: ' + $au + ' - so HOME should show the AI tile ' + $(if ($ai) { 'and' } else { 'but not' }) + ' ' + $(if ($au) { 'an' } else { 'no' }) + ' Audit trail tile') 'INFO' 'the console look (sheet C3) is the witness'
    } else { Add-WitResult '262' 'the tile verbs in SDSYS''s VOC' 'NOT-MEASURED' $r.Why }
}

# ===================================================================================================== api (243, 278, 266, 247)
if ($sections -contains 'api') {
    Write-Wit ''
    Write-Wit '=== api: remote.ssh / remote.api (243, 278), then an API session (266, 247)'
    $mark = Get-WitAuditMark
    $t0 = Get-Date
    $r = Invoke-WitSd -Commands @('remote.ssh') -Label 'remote.ssh, the report form' -TimeoutSec 120
    Set-WitVerdict '243' 'remote.ssh (report) prints 12950 "Reading the setting (a few seconds)..."' $r.Text 'Reading the setting \(a few seconds\)\.\.\.' @('is not in your VOC', 'Command requires administrator') ('seat ' + [int]((Get-Date) - $t0).TotalSeconds + ' s')
    $r = Invoke-WitSd -Commands @('remote.api') -Label 'remote.api, the report form' -TimeoutSec 120
    Set-WitVerdict '243' 'remote.api (report) prints 12950' $r.Text 'Reading the setting \(a few seconds\)\.\.\.' @('is not in your VOC', 'Command requires administrator')
    $t0 = Get-Date
    $r = Invoke-WitSd -Commands @('set.job') -Label 'set.job (the list form): does a line come before its PowerShell wait?' -TimeoutSec 120
    Add-WitResult '243' ('set.job took ' + [int]((Get-Date) - $t0).TotalSeconds + ' s through the seat (WHO takes about 5); the row''s second half (set.job, tool.jobs, settings_os) is not built: the source prints nothing before their waits') 'INFO' 'read the raw output above for a leading line'

    $portBefore = Get-ApiPort
    Write-Wit ('  sd.conf APIPORT before: ' + $portBefore + ' (0 = no active APIPORT line, the API off)')
    if ($portBefore -ne 0) {
        $null = Invoke-WitSd -Commands @('remote.api off', 'N') -Label 'put the API OFF first, answering N to any restart question' -TimeoutSec 180
    }
    $restartQ = 'Restart SD now\? Every SD session ends'
    $r1 = Invoke-WitSd -Commands @('remote.api local', 'N') -Label '278: remote.api local from OFF (answer N)' -TimeoutSec 180
    Set-WitVerdict '243' 'remote.api local prints 12944 "Making the change (a few seconds)..."' $r1.Text 'Making the change \(a few seconds\)\.\.\.' @('is not in your VOC')
    Set-WitVerdict '278' 'remote.api local from OFF offers SD''s restart (10135) and N leaves it written (10136)' $r1.Text "(?s)$restartQ.*SD was not restarted" @('did not succeed', 'is not in your VOC.*remote', 'Command requires administrator')
    $null = Invoke-WitSd -Commands @('remote.api off', 'N') -Label '278: back to OFF (answer N)' -TimeoutSec 180
    $r2 = Invoke-WitSd -Commands @('remote.api on', 'N') -Label '278: remote.api on, the first time (answer N)' -TimeoutSec 180
    $r3 = Invoke-WitSd -Commands @('remote.api on', 'N') -Label '278: remote.api on, the second time (answer N - a line nobody asked for is then a harmless TCL line)' -TimeoutSec 180
    $n2 = [regex]::Matches([string]$r2.Text, $restartQ).Count
    $n3 = [regex]::Matches([string]$r3.Text, $restartQ).Count
    $set3 = ([string]$r3.Text -match 'The SD API is now ON')
    if (-not $r2.Ok -or -not $r3.Ok) { Add-WitResult '278' 'remote.api on twice asks the restart once' 'NOT-MEASURED' 'a seat call did not run' }
    elseif ($n2 -eq 1 -and $n3 -eq 0 -and ([string]$r2.Text -match 'The SD API is now ON')) { Add-WitResult '278' 'remote.api on twice asks the restart once' 'PASS' ('restart question: first ON ' + $n2 + ' time(s), second ON ' + $n3 + '; second ON said "The SD API is now ON": ' + $set3) }
    else { Add-WitResult '278' 'remote.api on twice asks the restart once' 'FAIL' ('restart question: first ON ' + $n2 + ' time(s), second ON ' + $n3 + ' (wanted 1 and 0)') }

    # The API LOCAL and running, for the API session below.  on -> local moves no listener, so no question.
    $null = Invoke-WitSd -Commands @('remote.api local', 'N') -Label 'API to LOCAL for the API session (answer N)' -TimeoutSec 180
    $port = Get-ApiPort
    # 13 Nov 26: through the SD service, not "sd -restart" - that one restarts SD OUTSIDE the service and its daemon keeps a captured
    # pipe open for ever (Invoke-WitSdSwitch's note; measured in step 3 of this sitting).  The service is how the install runs SD.
    Write-Wit ('  sd.conf APIPORT now: ' + $port + '.  Restarting SD through its service so the listener opens (about 15 seconds)')
    try { Restart-Service -Name SD -ErrorAction Stop; Write-Wit ('  service SD: ' + (Get-Service SD).Status) } catch { Write-Wit ('  Restart-Service SD failed: ' + $_.Exception.Message) }
    Start-Sleep -Seconds 3
    $lis = @(Get-NetTCPConnection -State Listen -LocalPort $port -ErrorAction SilentlyContinue | ForEach-Object { $_.LocalAddress + ':' + $_.LocalPort + ' pid ' + $_.OwningProcess })
    Write-Wit ('  listening on ' + $port + ': ' + ($lis -join ', '))
    $apiPw = Get-Fix 'zzwitapi'
    $py = Get-Command python.exe -ErrorAction SilentlyContinue
    $probe = Join-Path $PSScriptRoot 'scram-probe.py'
    if ($apiPw -eq '' -or $null -eq $py -or $lis.Count -eq 0) {
        Add-WitResult '266' 'an API session''s @WHO is lower case' 'NOT-MEASURED' ('password on file: ' + ($apiPw -ne '') + '; python: ' + ($null -ne $py) + '; listener: ' + $lis.Count)
    } else {
        $env:SD_SCRAM_PASSWORD = $apiPw
        $ssl = 'C:\sdtools\bin\libssl-3-x64.dll'
        if (Test-Path -LiteralPath $ssl) { $env:SD_PROBE_LIBSSL = $ssl }
        $amark = Get-WitAuditMark
        # 13 Nov 26: commands need --account (step 3b: "CANNOT RUN - commands need --account"); the user's own account.
        Write-Wit ('  > python ' + $probe + ' --user zzwitapi --account zzwitapi --port ' + $port + ' -- WHO   (SD_PROBE_LIBSSL=' + $env:SD_PROBE_LIBSSL + ')')
        $po = & $py.Source $probe --user zzwitapi --account zzwitapi --port $port -- WHO 2>&1 | ForEach-Object { [string]$_ }
        Remove-Item Env:\SD_SCRAM_PASSWORD -ErrorAction SilentlyContinue
        $pt = $po -join "`n"
        Write-WitRaw 'scram-probe' $pt
        if ($pt -notmatch 'SCRAM: server signature VERIFIED') { Add-WitResult '266' 'an API session''s @WHO is lower case' 'NOT-MEASURED' 'the API login did not succeed (no "SCRAM: server signature VERIFIED")' }
        elseif ($pt -cmatch '(?m)^\s*\d+\s+zzwitapi\b') { Add-WitResult '266' 'an API session''s @WHO is lower case' 'PASS' ('WHO answered: ' + [regex]::Match($pt, '(?m)^\s*\d+\s+\S+').Value) }
        else { Add-WitResult '266' 'an API session''s @WHO is lower case' 'FAIL' ('no lower-case "<n> zzwitapi" line; WHO lines: ' + (([regex]::Matches($pt, '(?m)^\s*\d+\s+\S+') | ForEach-Object { $_.Value.Trim() }) -join ' / ')) }
        $al = @(Get-WitAuditSince $amark | Where-Object { $_ -match 'zzwitapi' })
        Write-WitRaw 'audit lines naming zzwitapi' ($al -join "`n")
        $stamped = @($al | Where-Object { $_ -match ('user=' + [regex]::Escape($vm) + '\\zzwitapi\s') })
        if ($al.Count -eq 0) { Add-WitResult '247' 'an API session''s audit lines carry its own Windows user' 'NOT-MEASURED' 'no audit line named zzwitapi' }
        elseif ($stamped.Count -eq $al.Count) { Add-WitResult '247' 'an API session''s audit lines carry its own Windows user' 'PASS' ($stamped.Count.ToString() + ' line(s) user=' + $vm + '\zzwitapi') }
        else { Add-WitResult '247' 'an API session''s audit lines carry its own Windows user' 'FAIL' (($al.Count - $stamped.Count).ToString() + ' of ' + $al.Count + ' lines name another user') }
    }
}

# ===================================================================================================== runin201
if ($sections -contains 'runin201') {
    Write-Wit ''
    Write-Wit '=== runin201: compile.dict, a trigger, no.catalog (row 201; sitting 2''s block 1 through the seat)'
    $fixSrc = @(
        '* zzfix - fixtures for the run.in witness (rows 201, 253); deleted by -Only cleanup',
        "acc = 'C:/ProgramData/SD/group_accounts/zzrunin'",
        "openpath acc : '/voc' to v else stop 'zzfix: cannot open the voc of zzrunin'",
        "act = downcase(field(trim(@sentence), ' ', 4))",
        'begin case',
        "   case act = 'setup'",
        "      openpath acc : '/bp' to b else stop 'zzfix: cannot open the bp of zzrunin'",
        "      write ""crt 'zzri ran'"" : @fm : 'end' to b, 'zzri'",
        "      src = ''",
        '      for i = 1 to 20000',
        "         src := 'x = ' : i : @fm",
        '      next i',
        "      src := 'end'",
        "      write src to b, 'zzbig'",
        "      create.file acc : '/zzcust' dynamic on error",
        "         stop 'zzfix: cannot create zzcust'",
        '      end',
        "      create.file acc : '/zzcust.dic' dynamic on error",
        "         stop 'zzfix: cannot create zzcust.dic'",
        '      end',
        "      write 'F' : @fm : 'zzcust' : @fm : 'zzcust.dic' to v, 'zzcust'",
        "      openpath acc : '/zzcust.dic' to d else stop 'zzfix: cannot open zzcust.dic'",
        "      write 'I' : @fm : 'len(@id)' : @fm : '' : @fm : 'Total' : @fm : '5R' : @fm : 'S' to d, 'total'",
        "      open 'voc' to sv else stop 'zzfix: cannot open the voc of this account'",
        "      write 'F' : @fm : acc : '/zzcust' : @fm : acc : '/zzcust.dic' to sv, 'zzcust.w'",
        "      crt 'zzfix setup: done'",
        "   case act = 'nocat'",
        "      delete v, 'no.catalog'",
        "      crt 'zzfix nocat: done'",
        "   case act = 'recat'",
        "      open 'newvoc' to n else stop 'zzfix: cannot open newvoc'",
        "      read r from n, 'no.catalog' else stop 'zzfix: newvoc has no no.catalog'",
        "      write r to v, 'no.catalog'",
        "      crt 'zzfix recat: done'",
        '   case 1',
        "      crt 'zzfix: setup, nocat or recat'",
        'end case',
        'end')
    if (-not (Test-Registered 'zzrunin')) { Add-WitResult '201' 'run.in fixtures' 'NOT-MEASURED' 'zzrunin is not registered: run -Only fixtures first' }
    else {
        Write-WitBasic $script:WitSdsys 'zzfix' $fixSrc
        # 13 Nov 26 (VM sitting): SET.TRIGGER is a RESTRICTED statement (bcomp: $internal programs only, which the seat cannot compile),
        # so the trigger is set with the SET.TRIGGER verb on a VOC pointer the setup writes (zzcust.w), and the verb wants the trigger
        # routine cataloged: zztrig, which does nothing (run.in must refuse BEFORE anything runs).
        Write-WitBasic $script:WitSdsys 'zztrig' @('subroutine zztrig(mode, id, rec, on.error, fvar)', '* zztrig - a trigger that does nothing, for the run.in witness (row 201)', 'return', 'end')
        $r = Invoke-WitSd -Commands @('basic bp zzfix', 'run bp zzfix setup', 'basic bp zztrig', 'catalog bp zztrig global') -Label 'compile and run the fixture program; the do-nothing trigger, cataloged'
        Set-WitVerdict '201' 'the fixture program compiled and set up zzcust and zzri' $r.Text '(?s)Compiled 1 program\(s\) with no errors.*zzfix setup: done' @('with errors in', 'zzfix: cannot')
        $r = Invoke-WitSd -Commands @('run.in zzrunin compile.dict zzcust total') -Label 'run.in compile.dict (no trigger)'
        Set-WitVerdict '201' 'run.in zzrunin compile.dict compiles an I-type' $r.Text 'Compiled \d+ .*with no errors' @('has a trigger function', 'is not a command run.in runs', 'with errors', 'not SD''s own entry', 'is not in your VOC')
        $r = Invoke-WitSd -Commands @('set.trigger zzcust.w zztrig', 'run.in zzrunin compile.dict zzcust total', 'set.trigger zzcust.w ""') -Label 'run.in compile.dict with a trigger on the file (SET.TRIGGER verb)'
        Set-WitVerdict '201' 'with a trigger on the file run.in refuses (12566) and runs nothing' $r.Text 'has a trigger function; run\.in did not run the command' @('zzfix: cannot', 'is not cataloged', 'File not found', 'Illegal trigger function name')
        $r = Invoke-WitSd -Commands @('run bp zzfix nocat', 'run.in zzrunin basic bp zzri no.query') -Label 'run.in basic with no.catalog removed from the account''s VOC'
        Set-WitVerdict '201' 'an account lacking SD''s no.catalog is refused (15070)' $r.Text 'no\.catalog is not SD''s own entry in the VOC of account' @('Compiled 1 program\(s\) with no errors')
        $r = Invoke-WitSd -Commands @('run bp zzfix recat', 'run.in zzrunin basic bp zzri no.query') -Label 'and with it put back'
        Set-WitVerdict '201' 'with no.catalog back, run.in basic compiles' $r.Text 'Compiled 1 program\(s\) with no errors' @('not SD''s own entry', 'with errors in')
    }
}

# ===================================================================================================== job222
if ($sections -contains 'job222') {
    Write-Wit ''
    Write-Wit '=== job222: a backup-all job, run by Task Scheduler as SDSYS (row 222)'
    $bdir = Join-Path $fixDir 'backup'
    if (-not (Test-Path -LiteralPath $bdir)) { $null = New-Item -ItemType Directory -Path $bdir -Force }
    $before = @(Get-ChildItem -LiteralPath $bdir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

    # 13 Nov 26 - RELEASE_1.1 281: the task folder \SD the install made, read elevated, before and after set.job; and a task planted under
    # the job's own name first (the squatter sd-taskfolder.ps1 guards against), which set.job must REPLACE - delete, then register - so the
    # registered task runs sd.exe as SDSYS and keeps nothing of the plant.
    $checkSdFolder = {
        param([string]$when)
        try {
            $svc = New-Object -ComObject Schedule.Service
            $svc.Connect()
            $sddl = $svc.GetFolder('\SD').GetSecurityDescriptor(0x5)
            $rsd = New-Object Security.AccessControl.RawSecurityDescriptor($sddl)
            $sids = @($rsd.DiscretionaryAcl | ForEach-Object { $_.SecurityIdentifier.Value } | Sort-Object -Unique)
            $prot = ($rsd.ControlFlags -band [Security.AccessControl.ControlFlags]::DiscretionaryAclProtected) -ne 0
            $ok = (@('S-1-5-32-544', 'S-1-5-18') -contains $rsd.Owner.Value) -and $prot -and (($sids -join ',') -ceq 'S-1-5-18,S-1-5-32-544')
            Add-WitResult '281' ('the task folder \SD is owned by SYSTEM or Administrators, protected, and open to them only (' + $when + ')') $(if ($ok) { 'PASS' } else { 'FAIL' }) $sddl
        } catch { Add-WitResult '281' ('the task folder \SD could be read (' + $when + ')') 'FAIL' $_.Exception.Message }
    }
    & $checkSdFolder 'as the install left it'
    $plantOk = $false
    try {
        $plantAct = New-ScheduledTaskAction -Execute (Join-Path $env:SystemRoot 'System32\cmd.exe') -Argument '/c exit 0'
        Register-ScheduledTask -TaskName 'sdcore-job-zzwb' -TaskPath '\SD\' -Action $plantAct -Description 'witness 281: a planted task' -Force -ErrorAction Stop | Out-Null
        $plantOk = $true
        Write-Wit '  planted \SD\sdcore-job-zzwb (cmd.exe /c exit 0, as this administrator) before set.job add zzwb'
    } catch { Add-WitResult '281' 'a task could be planted under the job''s name before set.job' 'NOT-MEASURED' $_.Exception.Message }

    $mark = Get-WitAuditMark
    $r = Invoke-WitSd -Commands @(('set.backup.directory ' + $bdir), 'set.job add zzwb backup-all daily 03:00') -Label 'the backup folder and the job' -TimeoutSec 180
    $task = @(Get-ScheduledTask -TaskPath '\SD\' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like '*zzwb*' })
    if ($plantOk -and $task.Count -eq 1) {
        $exe = [string]$task[0].Actions[0].Execute
        $ok = ($exe -like '*\sd.exe') -and ([string]$task[0].Principal.UserId -match 'SDSYS$') -and ([string]$task[0].Description -notmatch 'witness 281')
        Add-WitResult '281' 'set.job replaced the planted task: it runs sd.exe as SDSYS and keeps nothing of the plant' $(if ($ok) { 'PASS' } else { 'FAIL' }) ('action ' + $exe + '; principal ' + $task[0].Principal.UserId + '; description ' + $task[0].Description)
    }
    & $checkSdFolder 'after set.job add'
    if ($task.Count -ne 1) { Add-WitResult '222' 'set.job add makes the task under \SD\' 'FAIL' ('tasks under \SD\ naming zzwb: ' + $task.Count) }
    else {
        Add-WitResult '222' 'set.job add makes the task under \SD\' 'PASS' ($task[0].TaskPath + $task[0].TaskName + ' as ' + $task[0].Principal.UserId + ' ' + $task[0].Principal.LogonType + ' ' + $task[0].Principal.RunLevel)
        $others = @(Get-Process -Name sd -ErrorAction SilentlyContinue)
        Write-Wit ('  sd.exe processes now (the seat''s session has ended): ' + $others.Count + '.  Starting the task; waiting up to 180 seconds for the backup.')
        Start-ScheduledTask -TaskPath $task[0].TaskPath -TaskName $task[0].TaskName
        $deadline = (Get-Date).AddSeconds(180)
        $new = @()
        do {
            Start-Sleep -Seconds 5
            $new = @(Get-ChildItem -LiteralPath $bdir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.FullName })
            $st = (Get-ScheduledTask -TaskPath $task[0].TaskPath -TaskName $task[0].TaskName).State
        } while ($(Get-Date) -lt $deadline -and ($new.Count -eq 0 -or $st -eq 'Running'))
        $info = Get-ScheduledTaskInfo -TaskPath $task[0].TaskPath -TaskName $task[0].TaskName
        $jl = @(Get-WitAuditSince $mark | Where-Object { $_ -match 'job=zzwb' })
        Write-WitRaw 'audit lines with job=zzwb' ($jl -join "`n")
        $ev = ('task last run ' + $info.LastRunTime + ' result ' + $info.LastTaskResult + '; new files: ' + (($new | ForEach-Object { $_.FullName + ' (' + $_.Length + ' bytes)' }) -join ', '))
        if ($new.Count -gt 0 -and @($new | Where-Object { $_.Length -gt 0 }).Count -gt 0) { Add-WitResult '222' 'backup-all as SDSYS wrote a backup when no other session was signed on' 'PASS' $ev }
        else {
            Add-WitResult '222' 'backup-all as SDSYS wrote a backup when no other session was signed on' 'FAIL' $ev
            # 13 Nov 26: a scheduled job's output goes nowhere, so step 3b could not say why it wrote nothing.  The same command once
            # through the seat prints its refusal (the other sessions it saw, !acc_hold) or the zip it wrote (13008, with the path).
            $d = Invoke-WitSd -Commands @('BACKUP.ACCOUNT ALL') -Label 'why the job wrote nothing: BACKUP.ACCOUNT ALL once through the seat' -TimeoutSec 300
            $zips = @(Get-ChildItem -LiteralPath $bdir -Recurse -File -ErrorAction SilentlyContinue | Where-Object { $before -notcontains $_.FullName })
            Add-WitResult '222' 'BACKUP.ACCOUNT ALL through the seat (diagnosis for the job)' 'INFO' ('new files in ' + $bdir + ' now: ' + (($zips | ForEach-Object { $_.Name + ' (' + $_.Length + ')' }) -join ', ') + '; see the raw output above')
        }
        $sys = @($jl | Where-Object { $_ -match ('user=' + [regex]::Escape($vm) + '\\SDSYS\s') })
        if ($jl.Count -gt 0) { Set-WitCompare '247' 'a scheduled job''s audit lines carry user=<machine>\SDSYS (the job kind)' $jl.Count $sys.Count -Evidence 'lines with job=zzwb' }
    }
    $null = Invoke-WitSd -Commands @('set.job delete zzwb') -Label 'remove the job'
    $left = @(Get-ScheduledTask -TaskPath '\SD\' -ErrorAction SilentlyContinue | Where-Object { $_.TaskName -like '*zzwb*' }).Count
    Set-WitCompare '222' 'set.job delete removes the task' '0' ([string]$left)
}

# ===================================================================================================== print219
if ($sections -contains 'print219') {
    Write-Wit ''
    Write-Wit '=== print219: SPOOLER names the printer (row 219) - a PDF printer on a FILE port, never paper'
    $pdir = Join-Path $fixDir 'print'
    if (-not (Test-Path -LiteralPath $pdir)) { $null = New-Item -ItemType Directory -Path $pdir -Force }
    $port = Join-Path $pdir 'w219.pdf'
    $prn = 'SD Witness PDF'
    $drv = 'Microsoft Print To PDF'
    $confBefore = [IO.File]::ReadAllBytes($sdConf)
    $made = $false
    try {
        if (-not (Get-PrinterDriver -Name $drv -ErrorAction SilentlyContinue)) { throw ('the printer driver ''' + $drv + ''' is not installed') }
        Remove-Item -LiteralPath $port -Force -ErrorAction SilentlyContinue
        if (-not (Get-PrinterPort -Name $port -ErrorAction SilentlyContinue)) { Add-PrinterPort -Name $port }
        if (-not (Get-Printer -Name $prn -ErrorAction SilentlyContinue)) { Add-Printer -Name $prn -DriverName $drv -PortName $port; $made = $true }
        $pr = Get-Printer -Name $prn
        Write-Wit ('  printer ''' + $pr.Name + ''' driver ''' + $pr.DriverName + ''' port ''' + $pr.PortName + '''')
        $default = (Get-CimInstance Win32_Printer | Where-Object { $_.Default } | Select-Object -First 1).Name
        Write-Wit ('  the Windows default printer (SD must NOT use it): ' + $default)

        $text = [Text.Encoding]::ASCII.GetString($confBefore)
        $set = { param($name)
            $t = [regex]::Replace($text, '(?m)^\s*SPOOLER\s*=.*\r?\n', '')
            $t = [regex]::Replace($t, '(?mi)^\[sd\]\s*\r?\n', ("[sd]`r`nSPOOLER=" + $name + "`r`n"), 1)
            [IO.File]::WriteAllText($sdConf, $t, [Text.Encoding]::ASCII)
        }
        & $set $prn
        Write-WitRaw ('sd.conf with SPOOLER=' + $prn) (Get-SdConfText)
        $marker = 'ZZW219' + (Get-Random -Minimum 100000 -Maximum 999999)
        $r = Invoke-WitSd -Commands @('SETPTR 0,80,60,0,0,1,BRIEF', ('LIST VOC WITH @ID = "WHO" @ID "' + $marker + '" LPTR')) -Label 'one listing to the spooled printer (no AT)' -TimeoutSec 120
        $deadline = (Get-Date).AddSeconds(60)
        while (-not (Test-Path -LiteralPath $port) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
        Start-Sleep -Seconds 3
        $got = Test-Path -LiteralPath $port
        $len = 0; $head = ''
        if ($got) { $b = [IO.File]::ReadAllBytes($port); $len = $b.Length; if ($len -ge 5) { $head = [Text.Encoding]::ASCII.GetString($b, 0, 5) } }
        if ($r.Text -match 'Print job not sent') { Add-WitResult '219' 'a job with SPOOLER set reaches that printer' 'FAIL' ('SD said: ' + [regex]::Match($r.Text, 'Print job not sent[^\r\n]*').Value) }
        elseif ($got -and $head -eq '%PDF-' -and $len -gt 500) { Add-WitResult '219' 'a job with SPOOLER set reaches that printer (not the default printer)' 'PASS' ($port + ' ' + $len + ' bytes, starts %PDF-; marker ' + $marker + ' - open it to see the listing (sheet)') }
        else { Add-WitResult '219' 'a job with SPOOLER set reaches that printer' 'FAIL' ('port file exists ' + $got + ', ' + $len + ' bytes, head ' + $head) }

        & $set 'zz-no-such-printer'
        $r = Invoke-WitSd -Commands @('SETPTR 0,80,60,0,0,1,BRIEF', 'LIST VOC WITH @ID = "WHO" @ID LPTR') -Label 'SPOOLER naming a printer that does not exist' -TimeoutSec 120
        Set-WitVerdict '219' 'a refused SPOOLER job says so and names the SPOOLER printer' $r.Text 'Print job not sent: Windows refused it for printer ''?zz-no-such-printer''?' @('printer \(null\)') 'a "(null)" here is the defect suspected in linuxprt.c:231 (pu->printer_name, not the SPOOLER name)'
    } catch {
        Add-WitResult '219' 'SPOOLER printing' 'NOT-MEASURED' $_.Exception.Message
    } finally {
        [IO.File]::WriteAllBytes($sdConf, $confBefore)
        Write-Wit ('  sd.conf put back byte for byte: ' + ([Convert]::ToBase64String($confBefore) -eq [Convert]::ToBase64String([IO.File]::ReadAllBytes($sdConf))))
        if ($made) { try { Remove-Printer -Name $prn -ErrorAction Stop; Write-Wit '  the witness printer removed (the PDF file is kept)' } catch { Write-Wit ('  could not remove the printer: ' + $_.Exception.Message) } }
    }
}

# ===================================================================================================== audit247 (+240)
if ($sections -contains 'audit247') {
    Write-Wit ''
    Write-Wit '=== audit247: one writer for the audit trail (row 247) and a control character in a record (row 240)'
    $p = Get-WitPipe 'sd-audit'
    Write-Wit ('  \\.\pipe\sd-audit: ' + $p.Summary)
    if ($p.OpenError -ne 0) { Add-WitResult '247' 'the audit pipe is served' 'FAIL' ('open error ' + $p.OpenError) }
    else {
        $aces = @(Get-WitAces $p.Sddl)
        $owner = [regex]::Match($p.Sddl, '^O:([^D]+)D:').Groups[1].Value
        Set-WitCompare '247' 'the pipe''s owner is LocalSystem' 'SY' $owner -Evidence $p.Sddl
        Set-WitCompare '247' 'the pipe''s DACL is protected' 'True' ([string]($p.Sddl -match 'D:P')) -Evidence $p.Sddl
        $wide = @($aces | Where-Object { $_.Type -eq 'A' -and @('WD', 'AU', 'BU', 'IU', 'NU', 'AN') -contains $_.Sid })
        Set-WitCompare '247' 'no ACE for Everyone, Authenticated Users, Users, Interactive, Network or Anonymous' '0' ([string]$wide.Count) -Evidence (($aces | ForEach-Object { $_.Sid + ':' + $_.Rights }) -join ' ')
        $inst = @($aces | Where-Object { $_.Type -eq 'A' -and $_.Sid -ne 'SY' -and $_.Mask -ge 0 -and (($_.Mask -band 0x4) -ne 0 -or ($_.Mask -band 0x10000000) -ne 0 -or ($_.Mask -band 0x40000000) -ne 0) })
        Set-WitCompare '247' 'no ACE but SYSTEM''s carries FILE_CREATE_PIPE_INSTANCE (0x4) or a generic all/write' '0' ([string]$inst.Count) -Evidence (($inst | ForEach-Object { $_.Sid + ':' + $_.Rights }) -join ' ')
        $sdu = Get-WitSid 'sdusers'
        Set-WitCompare '247' 'sdusers may send (an ACE for its SID)' 'True' ([string](@($aces | Where-Object { $_.Sid -eq $sdu }).Count -gt 0)) -Evidence ('sdusers ' + $sdu)
        Set-WitVerdict '247' 'the pipe is served by the SD service (sdsvc.exe)' $p.Server 'sdsvc\.exe$' @()
        $rem = Test-WitPipeRemote 'sd-audit'
        if (-not $rem.Measured) { Add-WitResult '247' 'a remote client is refused (PIPE_REJECT_REMOTE_CLIENTS)' 'NOT-MEASURED' $rem.Why }
        elseif ($rem.Remote -ne 0) { Add-WitResult '247' 'a remote client is refused (\\localhost\pipe\sd-audit, through the SMB server)' 'PASS' ('local open ' + $rem.Local + ', loopback UNC open error ' + $rem.Remote) }
        else { Add-WitResult '247' 'a remote client is refused' 'FAIL' 'the loopback UNC open succeeded' }

        $log = Join-Path $script:WitDataDir 'sdsvc.log'
        $sl = @(Get-Content -LiteralPath $log -ErrorAction SilentlyContinue | Where-Object { $_ -match 'audit writer:' } | Select-Object -Last 3)
        Set-WitVerdict '247' 'sdsvc.log says the audit writer is serving' ($sl -join "`n") 'audit writer: serving' @('audit writer: not started')

        # A forged claim, an injected line, a foreign tree - sent by THIS process, an elevated administrator.
        $sysd = $script:WitSdsys
        $send = { param($text) [SdWit.Native]::PipeSend('\\.\pipe\sd-audit', [Text.Encoding]::ASCII.GetBytes($text), 5000) }
        $n1 = 'zzw247f' + (Get-Random -Minimum 100000 -Maximum 999999)
        $n2 = 'zzw247i' + (Get-Random -Minimum 100000 -Maximum 999999)
        $n3 = 'zzw247x' + (Get-Random -Minimum 100000 -Maximum 999999)
        $mark = Get-WitAuditMark
        $a1 = & $send ('SDAUDIT1 0' + "`t" + $sysd + "`t" + 'witness forged claim of user 0 ' + $n1)
        $a2 = & $send ('SDAUDIT1 0' + "`t" + $sysd + "`t" + 'witness injected ' + $n2 + "`r`n" + '2026-01-01 00:00:00 user=' + $vm + '\SDSYS uid=0 pid=1 forged ' + $n2)
        $a3 = & $send ('SDAUDIT1 0' + "`t" + 'C:\zz-not-a-tree\sdsys' + "`t" + 'witness foreign tree ' + $n3)
        Write-Wit ('  answers: forged ' + $a1.Answer + ' (open ' + $a1.OpenError + ', write ' + $a1.WriteError + ', timeout ' + $a1.TimedOut + '); injected ' + $a2.Answer + '; foreign ' + $a3.Answer + '   (89 = Y, 78 = N, 69 = E)')
        Start-Sleep -Seconds 2
        $new = @(Get-WitAuditSince $mark)
        Write-WitRaw 'audit lines written since' (($new | Where-Object { $_ -match 'zzw247' }) -join "`n")
        $l1 = @($new | Where-Object { $_ -match $n1 })
        $want1 = ('user=' + [regex]::Escape($me.Name) + ' uid=0 pid=' + $PID + ' ')
        if ($l1.Count -ne 1) { Add-WitResult '247' 'a forged claim (uid 0) is written with the sender''s real user and pid' 'FAIL' ('lines with ' + $n1 + ': ' + $l1.Count + ', answer ' + $a1.Answer) }
        elseif ($l1[0] -match $want1) { Add-WitResult '247' 'a forged claim (uid 0) is written with the sender''s real user and pid' 'PASS' $l1[0] }
        else { Add-WitResult '247' 'a forged claim (uid 0) is written with the sender''s real user and pid' 'FAIL' ('wanted /' + $want1 + '/ in: ' + $l1[0]) }
        $l2 = @($new | Where-Object { $_ -match $n2 })
        $bad = @($new | Where-Object { $_ -match ('^2026-01-01 00:00:00 user=' + [regex]::Escape($vm)) })
        if ($l2.Count -eq 1 -and $bad.Count -eq 0 -and $l2[0] -match ('injected ' + $n2 + '\?\?2026-01-01')) { Add-WitResult '247' 'an injected CR LF is written as ?? on the one line, and no forged line appears' 'PASS' $l2[0] }
        else { Add-WitResult '247' 'an injected CR LF is written as ?? on the one line' 'FAIL' ('lines with ' + $n2 + ': ' + $l2.Count + '; lines starting with the forged stamp: ' + $bad.Count + '; ' + ($l2 -join ' / ')) }
        $l3 = @($new | Where-Object { $_ -match $n3 })
        if ($a3.Answer -eq 78 -and $l3.Count -eq 0) { Add-WitResult '247' 'a record naming another tree is answered N and not written here' 'PASS' 'answer N' }
        else { Add-WitResult '247' 'a record naming another tree is answered N and not written here' 'FAIL' ('answer ' + $a3.Answer + ', lines ' + $l3.Count) }

        # Timing: 200 records through the pipe (no pass mark was set by the design).
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $ok = 0
        for ($i = 0; $i -lt 200; $i++) { $x = & $send ('SDAUDIT1 0' + "`t" + $sysd + "`t" + 'witness timing ' + $i); if ($x.Answer -eq 89) { $ok++ } }
        $sw.Stop()
        Add-WitResult '247' ('200 records through the pipe from one process: ' + $ok + ' taken, ' + [Math]::Round($sw.Elapsed.TotalMilliseconds / 200, 2) + ' ms each') 'INFO' 'the design set no pass mark; compare with the sign-on path if it ever feels slow'
    }

    # 240 and the console kind of 247: a session's own record with a control character in it.
    $nb = ('zz240b' + (Get-Random -Minimum 100000 -Maximum 999999))
    $nl = ('zz240n' + (Get-Random -Minimum 100000 -Maximum 999999))
    $prog = @(
        '* zzw240 - a LOGTO refusal whose account name holds a control character (row 240); deleted by -Only cleanup',
        ("   execute 'LOGTO " + $nb + "' : char(7) : 'bel'"),
        ("   execute 'LOGTO " + $nl + "' : char(10) : 'nl'"),
        'end')
    Write-WitBasic $script:WitSdsys 'zzw240' $prog
    $mark = Get-WitAuditMark
    $null = Invoke-WitSd -Commands @('basic bp zzw240', 'run bp zzw240') -Label '240: LOGTO with BEL and with LF in the name (both refused: not registered)'
    $new = @(Get-WitAuditSince $mark)
    Write-WitRaw 'audit lines naming zz240' (($new | Where-Object { $_ -match 'zz240' }) -join "`n")
    $lb = @($new | Where-Object { $_ -match $nb })
    if ($lb.Count -eq 0) { Add-WitResult '240' 'a BEL in a record reaches the trail as ?' 'NOT-MEASURED' 'no logto refused line named the probe (the program may not have run)' }
    elseif ($lb[0] -match ($nb + '\?bel')) { Add-WitResult '240' 'a BEL in a record reaches the trail as ?' 'PASS' $lb[0] }
    else { Add-WitResult '240' 'a BEL in a record reaches the trail as ?' 'FAIL' $lb[0] }
    $ln = @($new | Where-Object { $_ -match $nl })
    $broken = @($new | Where-Object { $_ -match '^nl\b' -or $_ -match '^nl reason=' })
    if ($broken.Count -gt 0) { Add-WitResult '240' 'a newline in a record does not break the trail into two lines' 'FAIL' ($broken -join ' / ') }
    elseif ($ln.Count -gt 0 -and $ln[0] -match ($nl + '\?nl')) { Add-WitResult '240' 'a newline in a record reaches the trail as ? on one line' 'PASS' $ln[0] }
    elseif ($ln.Count -gt 0) { Add-WitResult '240' 'a newline in a record reaches the trail as ?' 'NOT-MEASURED' ('the newline did not reach the trail (the TCL parser stopped the name at it): ' + $ln[0] + '; the writer''s own flattening of CR LF is the 247 injected-line check') }
    else { Add-WitResult '240' 'a newline in a record' 'NOT-MEASURED' 'no line named the probe' }
    $sys = @($lb + $ln | Where-Object { $_ -match ('user=' + [regex]::Escape($vm) + '\\SDSYS uid=\d+ pid=\d+ ') })
    if (($lb.Count + $ln.Count) -gt 0) { Set-WitCompare '247' 'a console (seat) session''s lines carry user=<machine>\SDSYS with its uid and pid' ([string]($lb.Count + $ln.Count)) ([string]$sys.Count) }

    # LOCK.TRACER through the service.
    $lt = Join-Path $script:WitSdsys 'locktrace'
    $rec = 'ZZW247LK' + (Get-Random -Minimum 1000 -Maximum 9999)
    Write-WitBasic $script:WitSdsys 'zzw247lk' @('* zzw247lk - one record lock for LOCK.TRACER (row 247); deleted by -Only cleanup', "   open 'VOC' to f else stop 'no voc'", ("   readu x from f, '" + $rec + "' else x = ''"), ("   release f, '" + $rec + "'"), 'end')
    $r = Invoke-WitSd -Commands @('LOCK.TRACER ON', 'basic bp zzw247lk', 'run bp zzw247lk', 'LOCK.TRACER OFF', 'LOCK.TRACER NO.PAGE') -Label 'LOCK.TRACER on, one lock taken and let go, off, the report'
    Set-WitVerdict '247' 'LOCK.TRACER ON answers 12364 "lock tracing is on"' $r.Text 'lock tracing is on' @('lock tracing could not be started', 'lock tracing is for the administrator')
    $ltText = ''
    if (Test-Path -LiteralPath $lt) { $ltText = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($lt)) }
    $sddl = ''
    try { $sddl = (Get-Acl -LiteralPath $lt).Sddl } catch { }
    Write-Wit ('  ' + $lt + ': ' + $ltText.Length + ' bytes; ACL ' + $sddl)
    if ($ltText -match $rec) { Add-WitResult '247' 'the lock trace has the probe''s record lock (written by the service)' 'PASS' ('locktrace holds ' + $rec) }
    else { Add-WitResult '247' 'the lock trace has the probe''s record lock' 'FAIL' ('locktrace (' + $ltText.Length + ' bytes) does not hold ' + $rec) }
    $ltAces = @(Get-WitAces $sddl | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.Sid } | Sort-Object -Unique)
    Set-WitCompare '247' 'locktrace is SYSTEM and Administrators only (D:P(A;;FA;;;SY)(A;;FA;;;BA))' 'BA,SY' ($ltAces -join ',') -Evidence $sddl
    try { Add-WitResult '247' ('the trail''s own ACL (secure-audit.ps1)') 'INFO' ((Get-Acl -LiteralPath (Get-WitAuditPath)).Sddl) } catch { }

    # The rate bound last: it is per Windows user, so it is sent from THIS user after everything else here.
    if ($p.OpenError -eq 0) {
        Write-Wit '  the rate bound: 610 records in a burst from this user, then 61 seconds of waiting for the window to end (about 75 seconds)'
        $taken = 0
        for ($i = 0; $i -lt 610; $i++) { $x = & $send ('SDAUDIT1 0' + "`t" + $script:WitSdsys + "`t" + 'witness rate ' + $i); if ($x.Answer -eq 89) { $taken++ } }
        $mark = Get-WitAuditMark
        Start-Sleep -Seconds 61
        $null = & $send ('SDAUDIT1 0' + "`t" + $script:WitSdsys + "`t" + 'witness rate after the window')
        Start-Sleep -Seconds 2
        $rl = @(Get-WitAuditSince $mark | Where-Object { $_ -match 'audit rate limit dropped=' })
        Set-WitVerdict '247' 'past 600 records a minute the writer drops and then says how many (Linux''s bound)' ($rl -join "`n") 'audit rate limit dropped=\d+ taken=\d+ limit=600 window=60' @() ('answered Y: ' + $taken + ' of 610 (a dropped record is still answered Y)')
    }
}

# ===================================================================================================== logto275 (+266)
if ($sections -contains 'logto275') {
    Write-Wit ''
    Write-Wit '=== logto275: an SDSYS session that LOGTOs into an account keeps its elevated token? (row 275, measure first; 266)'
    $mark = Get-WitAuditMark
    # No LOGTO back to SDSYS here: its refusal (10002) was witnessed on 22 Sep 2026, and a live one in a gplbld script must
    # be declared in test-logtoreaim-units.ps1, which this sitting does not edit.
    # 13 Nov 26: SH cannot measure it - SDSYS's own shell gate is closed as delivered, and SH asks the person's gate, so step 3b's
    # whoami never ran.  The token of the session's own sd.exe is read instead, as SYSTEM, while the session waits in zzwitsh
    # (SLEEP 30): the reader starts with the session and reads after 15 s, by which time LOGTO has been done.  The pid is the
    # one the audit's logto line names.
    $out = Join-Path (Join-Path $fixDir 'sys') 'token275.txt'
    $null = New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out)
    $ts = Invoke-WitAsSystem -Script $systemScript -Arguments '-Mode Token -UserName SDSYS -DelaySec 15' -OutFile $out -TimeoutSec 120 -While {
        Invoke-WitSd -Commands @('LOGTO zzwitsh', 'WHO', 'SLEEP 30', 'WHO') -Label 'LOGTO zzwitsh, WHO, then wait 30 s while SYSTEM reads the token' -TimeoutSec 180
    }
    $r = $ts.WhileOut
    $t = [string]$r.Text
    $al = @(Get-WitAuditSince $mark | Where-Object { $_ -match 'logto|elevation released' })
    $lpid = [regex]::Match(($al -join "`n"), 'pid=(\d+)\s+logto account=zzwitsh').Groups[1].Value
    Write-WitRaw 'the SYSTEM token report (row 275)' ([string]$ts.Text)
    $line = ''
    if ($lpid -ne '') { $line = [regex]::Match([string]$ts.Text, '(?m)^pid=' + $lpid + ' image=.*$').Value }
    if (-not $ts.Ok) { Add-WitResult '275' 'the token after LOGTO from SDSYS' 'NOT-MEASURED' $ts.Why }
    elseif ($null -eq $r -or -not $r.Ok) { Add-WitResult '275' 'the token after LOGTO from SDSYS' 'NOT-MEASURED' ('the seat did not run: ' + $(if ($r) { $r.Why } else { 'no result' })) }
    elseif ($lpid -eq '') { Add-WitResult '275' 'the token after LOGTO from SDSYS' 'NOT-MEASURED' 'the audit has no logto line with a pid' }
    elseif ($line -eq '') { Add-WitResult '275' 'the token after LOGTO from SDSYS' 'NOT-MEASURED' ('the SYSTEM report has no line for pid ' + $lpid + ' (the session had ended?)') }
    elseif ($line -match 'error=0 ' -and ($line -match 'elevated=1' -or $line -match 'integrity=S-1-16-12288')) { Add-WitResult '275' 'after LOGTO from SDSYS the session''s process is still elevated (High label): a program run in the account has administrator rights' 'FINDING' ($line + ' - the remedy is the owner''s decision (the row)') }
    elseif ($line -match 'error=0 ' -and $line -match 'elevated=0') { Add-WitResult '275' 'after LOGTO from SDSYS the session''s process is not elevated' 'PASS' $line }
    else { Add-WitResult '275' 'the token after LOGTO from SDSYS' 'NOT-MEASURED' ('the token could not be read: ' + $line) }
    Set-WitVerdict '266' 'WHO after LOGTO zzwitsh answers the account in lower case' $t '(?m)^\s*\d+\s+zzwitsh\b' @('User not allowed in requested account')
    if ($t -cmatch '(?m)^\s*\d+\s+ZZWITSH\b') { Add-WitResult '266' 'WHO after LOGTO is lower case' 'FAIL' 'WHO answered ZZWITSH' }
    $al = @(Get-WitAuditSince $mark | Where-Object { $_ -match 'logto|elevation released' })
    Write-WitRaw 'audit: logto lines' ($al -join "`n")
    Set-WitVerdict '266' 'the audit has logto account=zzwitsh and elevation released account=zzwitsh' ($al -join "`n") '(?s)elevation released account=zzwitsh.*logto account=zzwitsh|(?s)logto account=zzwitsh.*elevation released account=zzwitsh' @()
}

# ===================================================================================================== gates266
if ($sections -contains 'gates266') {
    Write-Wit ''
    Write-Wit '=== gates266: update.accounts all, then tool.gates in SDSYS and in an account (row 266)'
    $r = Invoke-WitSd -Commands @('UPDATE.ACCOUNTS ALL') -Label 'update.accounts all' -TimeoutSec 300
    Set-WitVerdict '266' 'update.accounts all updates every registered account (10171)' $r.Text 'account\(s\) had their VOC updated from the shipped vocabulary' @('NOTHING has been updated', 'does not take')
    $r = Invoke-WitSd -Commands @('CT VOC tool.gates', 'LOGTO zzwitsh', 'CT VOC tool.gates') -Label 'tool.gates in SDSYS, then in zzwitsh'
    $t = [string]$r.Text
    $i1 = $t.IndexOf('$tool_gates')
    $i2 = $t.IndexOf('$tool_mygates')
    if (-not $r.Ok) { Add-WitResult '266' 'tool.gates verbs' 'NOT-MEASURED' $r.Why }
    elseif ($i1 -ge 0 -and $i2 -gt $i1) { Add-WitResult '266' 'SDSYS''s tool.gates is $tool_gates (voc_template) and an account''s is $tool_mygates (newvoc)' 'PASS' ('offsets ' + $i1 + ' and ' + $i2) }
    else { Add-WitResult '266' 'SDSYS''s tool.gates is $tool_gates and an account''s is $tool_mygates' 'FAIL' ('$tool_gates at ' + $i1 + ', $tool_mygates at ' + $i2) }
}

# ===================================================================================================== shared260
if ($sections -contains 'shared260') {
    Write-Wit ''
    Write-Wit '=== shared260: delete.account shared is refused (row 260)'
    $rec = Join-Path (Join-Path $script:WitSdsys 'accounts') 'shared'
    $before = Test-Path -LiteralPath $rec
    $r = Invoke-WitSd -Commands @('DELETE.ACCOUNT shared', 'N') -Label 'DELETE.ACCOUNT shared (an N follows in case it asks)'
    Set-WitVerdict '260' 'DELETE.ACCOUNT shared is refused with 12522' $r.Text 'The shared account cannot be deleted' @() ('register record before ' + $before + ', after ' + (Test-Path -LiteralPath $rec))
    Set-WitCompare '260' 'the shared register record is still there' ([string]$before) ([string](Test-Path -LiteralPath $rec))
}

# ===================================================================================================== ai246
if ($sections -contains 'ai246') {
    Write-Wit ''
    Write-Wit '=== ai246: the AI helper - service, pipe, gate, squat, DPAPI (row 246; checks are against behavior, not the helper''s language)'
    $svc = Get-CimInstance Win32_Service -Filter "Name='sd-ai'" -ErrorAction SilentlyContinue
    if ($null -eq $svc) { Add-WitResult '246' 'the sd-ai service is installed' 'FAIL' 'no service sd-ai' }
    else {
        Add-WitResult '246' 'the sd-ai service' 'INFO' ($svc.State + ' ' + $svc.StartMode + ' as ' + $svc.StartName + ' : ' + $svc.PathName)
        Set-WitCompare '246' 'sd-ai runs (F10 delivered)' 'Running' $svc.State
        Set-WitCompare '246' 'sd-ai runs as the virtual account NT SERVICE\sd-ai' 'NT SERVICE\sd-ai' $svc.StartName
        Set-WitVerdict '246' 'the service runs the native helper (lib\sd-ai\sd-ai.exe --service, no Python)' ([string]$svc.PathName) 'lib\\sd-ai\\sd-ai\.exe"?\s+--service' @('python', '\.py\b', 'sd-ai-python')
        $sid = (& sc.exe qsidtype sd-ai 2>&1 | Out-String)
        Set-WitVerdict '246' 'its service SID type is RESTRICTED' $sid 'SERVICE_SID_TYPE:\s+RESTRICTED' @()
        $prv = (& sc.exe qprivs sd-ai 2>&1 | Out-String)
        $names = @([regex]::Matches($prv, 'Se\w+Privilege') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        Set-WitCompare '246' 'its only privilege is SeChangeNotifyPrivilege' 'SeChangeNotifyPrivilege' ($names -join ',') -Evidence ($prv -replace '\s+', ' ')
    }
    $svcSid = Get-WitSid 'NT SERVICE\sd-ai'
    $p = Get-WitPipe 'sd-ai'
    Write-Wit ('  \\.\pipe\sd-ai: ' + $p.Summary + '   (NT SERVICE\sd-ai is ' + $svcSid + ')')
    if ($p.OpenError -ne 0) { Add-WitResult '246' 'the AI pipe is served' 'FAIL' ('open error ' + $p.OpenError) }
    else {
        $owner = [regex]::Match($p.Sddl, '^O:([^D]+)D:').Groups[1].Value
        Set-WitCompare '246' 'F3: the pipe''s owner is the service''s own SID (what the kernel checks before sending)' $svcSid $owner -Evidence $p.Sddl
        Set-WitVerdict '246' 'the AI pipe is served by sd-ai.exe' $p.Server 'sd-ai\.exe$' @('python')
        $aces = @(Get-WitAces $p.Sddl)
        $inst = @($aces | Where-Object { $_.Type -eq 'A' -and @('SY', $svcSid) -notcontains $_.Sid -and $_.Mask -ge 0 -and (($_.Mask -band 0x4) -ne 0 -or ($_.Mask -band 0x10000000) -ne 0 -or ($_.Mask -band 0x40000000) -ne 0) })
        Set-WitCompare '246' 'no client ACE may create a pipe instance (0x4) or holds generic all/write' '0' ([string]$inst.Count) -Evidence (($aces | ForEach-Object { $_.Sid + ':' + $_.Rights }) -join ' ')
        $wide = @($aces | Where-Object { $_.Type -eq 'A' -and @('WD', 'AU', 'BU', 'IU', 'NU', 'AN') -contains $_.Sid })
        Set-WitCompare '246' 'no ACE for Everyone, Authenticated Users or Users' '0' ([string]$wide.Count)
        $rem = Test-WitPipeRemote 'sd-ai'
        if (-not $rem.Measured) { Add-WitResult '246' 'F5: a remote client is refused' 'NOT-MEASURED' $rem.Why }
        elseif ($rem.Remote -ne 0) { Add-WitResult '246' 'F5: a remote client is refused (\\localhost\pipe\sd-ai through the SMB server)' 'PASS' ('local ' + $rem.Local + ', loopback UNC error ' + $rem.Remote) }
        else { Add-WitResult '246' 'F5: a remote client is refused' 'FAIL' 'the loopback UNC open succeeded' }
    }
    $mem = Get-WitGroupMembers 'sdaiusers'
    Add-WitResult '246' ('F10: sdaiusers members: ' + $(if ($mem.Count) { $mem -join ',' } else { '(none)' })) 'INFO' 'empty as delivered unless the installer''s open-gates box was ticked (it gives the installing user ai-on)'
    $kd = Join-Path $script:WitDataDir 'ai\keys'
    $kerr = ''
    try { $null = Get-ChildItem -LiteralPath $kd -ErrorAction Stop; $kerr = 'listed by an administrator' } catch { $kerr = $_.Exception.GetType().Name + ': ' + $_.Exception.Message }
    Add-WitResult '246' ('the key folder ' + $kd + ' as an elevated administrator: ' + $kerr) 'INFO' 'designed SYSTEM and the service SID only, so an administrator listing it is refused'

    # F10: the AI off as delivered, asked by SDSYS (which the gate lets through).
    $mark = Get-WitAuditMark
    $r = Invoke-WitSd -Commands @('AI zzw246 delivered state') -Label 'F10: ai as SDSYS with no provider chosen'
    Set-WitVerdict '246' 'F10: ai answers 12629 "The AI is off" as delivered' $r.Text 'The AI is off: the administrator has not chosen a provider' @('could not be reached', 'may not use the AI', 'did not answer')
    $al = @(Get-WitAuditSince $mark | Where-Object { $_ -match 'ai request' })
    Add-WitResult '246' 'the ai request audit line (written before the connection)' 'INFO' ($al -join ' / ')

    # F6 and F2: the gate read live, from an ssh session that stays open across the change.
    $offPw = Get-Fix 'zzwitoff'
    if ($offPw -eq '') { Add-WitResult '246' 'F6: the gate is read at the next request' 'NOT-MEASURED' 'no zzwitoff password on file (run -Only fixtures)' }
    else {
        Write-Wit '  F6: one ssh session as zzwitoff asks twice, 40 seconds apart; the gate is opened between (about 60 seconds)'
        # 13 Nov 26: ai asks for a provider BEFORE the gate (gpl.bp/ai:78-85, as Linux ai:76-83), so with none chosen both asks said 12629 and the
        # gate was never reached.  A provider with no key is chosen for F6: the gate speaks first (12630), and an ask that passes it stops at 12631
        # (no key) before anything is sent.  PROVIDER none puts the delivered state back.
        $r = Invoke-WitSd -Commands @('SET.AI PROVIDER anthropic') -Label 'F6: a provider with no key, so the gate is reached'
        Write-WitRaw 'SET.AI PROVIDER anthropic' $r.Text
        $job = Start-Job -ScriptBlock {
            param($lib, $pw)
            . $lib
            $r = Invoke-SdAsTestUser -Name 'zzwitoff' -Password $pw -Commands @('AI zzw246 first', 'SLEEP 40', 'AI zzw246 second')
            return ($r.ExitCode.ToString() + "`n" + $r.Out)
        } -ArgumentList (Join-Path $PSScriptRoot 'sdtestuser.ps1'), $offPw
        Start-Sleep -Seconds 12
        $null = Invoke-WitSd -Commands @('MODIFY.ACCOUNT zzwitoff ai-on') -Label 'F6: open the ai gate of zzwitoff while its session waits'
        $jo = ''
        if (Wait-Job $job -Timeout 120) { $jo = [string](Receive-Job $job) } else { $jo = '' }
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        Write-WitRaw 'the zzwitoff session' $jo
        $i1 = $jo.IndexOf('may not use the AI')
        $i2 = $jo.IndexOf('The AI is not set up for')
        $i0 = $jo.IndexOf('The AI is off')
        if ($jo -eq '') { Add-WitResult '246' 'F6: the gate is read at the next request' 'NOT-MEASURED' 'the ssh session gave nothing back in 120 s' }
        elseif ($i0 -ge 0) { Add-WitResult '246' 'F6: the gate is read at the next request' 'NOT-MEASURED' ('no provider was chosen (12629 at ' + $i0 + '), so the gate was not reached') }
        elseif ($i1 -ge 0 -and $i2 -gt $i1) { Add-WitResult '246' 'F6/F2: the first ask is refused by the gate (12630), the second, after ai-on, passes it (12631, no key) - same session, no sign-out; the helper read the person, not SYSTEM' 'PASS' ('12630 at ' + $i1 + ', 12631 at ' + $i2) }
        else { Add-WitResult '246' 'F6: the gate is read at the next request' 'FAIL' ('12630 at ' + $i1 + ', 12631 at ' + $i2) }
        $null = Invoke-WitSd -Commands @('MODIFY.ACCOUNT zzwitoff ai-off', 'SET.AI PROVIDER none') -Label 'F6: close the gate again and choose no provider (as delivered)'
        $mem = Get-WitGroupMembers 'sdaiusers'
        Set-WitCompare '246' 'ai-off took zzwitoff out of sdaiusers' 'False' ([string]($mem -contains 'zzwitoff'))
    }

    # F4: the name squatted while the service is stopped.
    if ($null -ne $svc) {
        Write-Wit '  F4: stopping sd-ai, holding \\.\pipe\sd-ai in this process, asking as SDSYS (about 30 seconds)'
        $squat = $null
        try {
            Stop-Service -Name sd-ai -Force -ErrorAction Stop
            Start-Sleep -Seconds 2
            $squat = New-Object IO.Pipes.NamedPipeServerStream('sd-ai', [IO.Pipes.PipeDirection]::InOut, 1, [IO.Pipes.PipeTransmissionMode]::Byte, [IO.Pipes.PipeOptions]::Asynchronous)
            $wait = $squat.BeginWaitForConnection($null, $null)
            $r = Invoke-WitSd -Commands @('AI zzw246 squatted secret words') -Label 'F4: ai while the name is squatted'
            $got = 0
            $buf = New-Object byte[] 4096
            if ($wait.IsCompleted) {
                $squat.EndWaitForConnection($wait)
                $rd = $squat.BeginRead($buf, 0, $buf.Length, $null, $null)
                if ($rd.AsyncWaitHandle.WaitOne(3000)) { $got = $squat.EndRead($rd) }
            }
            Write-Wit ('  the squatter: client connected ' + $wait.IsCompleted + ', bytes received ' + $got)
            if ($got -eq 0 -and $r.Ok -and $r.Text -notmatch 'The AI is off|This will be sent to') { Add-WitResult '246' 'F4: with the name squatted nothing is sent and the ask is refused' 'PASS' ('bytes to the squatter 0; SD said: ' + (($r.Text -split "`n" | Where-Object { $_ -match 'AI' }) -join ' / ')) }
            elseif ($got -gt 0) { Add-WitResult '246' 'F4: with the name squatted nothing is sent' 'FAIL' ($got.ToString() + ' bytes reached the squatter: ' + [Text.Encoding]::ASCII.GetString($buf, 0, [Math]::Min($got, 200))) }
            else { Add-WitResult '246' 'F4: with the name squatted the ask is refused' 'NOT-MEASURED' 'the seat did not run, or SD''s answer was not a refusal' }
            Write-Wit '  F4: starting sd-ai while the name is still held (it must fail, not run quietly)'
            $startErr = ''
            try { Start-Service -Name sd-ai -ErrorAction Stop } catch { $startErr = $_.Exception.Message }
            Start-Sleep -Seconds 3
            $st = (Get-Service -Name sd-ai).Status
            $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'Application'; StartTime = (Get-Date).AddMinutes(-2) } -ErrorAction SilentlyContinue | Where-Object { $_.ProviderName -match 'sd-ai|SD' } | Select-Object -First 3 | ForEach-Object { $_.ProviderName + ': ' + ($_.Message -replace '\s+', ' ') })
            if ([string]$st -ne 'Running') { Add-WitResult '246' 'F4: the service will not start while its pipe name is taken' 'PASS' ('status ' + $st + '; ' + $startErr + '; events: ' + ($ev -join ' / ')) }
            else { Add-WitResult '246' 'F4: the service will not start while its pipe name is taken' 'FAIL' 'it is Running with the name held by another process' }
        } catch {
            Add-WitResult '246' 'F4: squat' 'NOT-MEASURED' $_.Exception.Message
        } finally {
            if ($null -ne $squat) { $squat.Dispose() }
            try { Start-Service -Name sd-ai -ErrorAction Stop } catch { }
            Start-Sleep -Seconds 2
            Write-Wit ('  sd-ai after the squat test: ' + (Get-Service -Name sd-ai).Status)
            Set-WitCompare '246' 'sd-ai runs again once the squatter is gone' 'Running' ([string](Get-Service -Name sd-ai).Status)
        }
    }

    # F1: DPAPI scope of a stored key.  The key goes in through the page's hand-over file (SET.AI KEY p HANDOVER), so
    # nothing waits on a keyboard; it is a dummy, never a real key.
    $hdir = Join-Path $script:WitSdsys '$aikey'
    $hf = Join-Path $hdir 'key'
    try {
        if (-not (Test-Path -LiteralPath $hdir)) { $null = New-Item -ItemType Directory -Path $hdir -Force }
        Set-Content -LiteralPath $hf -Value ('zzw246-not-a-real-key-' + (Get-Random)) -Encoding ASCII -NoNewline
        $r = Invoke-WitSd -Commands @('SET.AI PROVIDER anthropic', 'SET.AI KEY anthropic HANDOVER') -Label 'F1: a dummy key for the provider anthropic, through the hand-over file'
        Set-WitCompare '246' 'the hand-over file is gone after SET.AI KEY ... HANDOVER' 'False' ([string](Test-Path -LiteralPath $hf))
        $out = Join-Path (Join-Path $fixDir 'sys') 'keyprobe.txt'
        Write-Wit '  F1: reading the key folder as SYSTEM (a one-shot task; about 10 seconds)'
        $k = Invoke-WitAsSystem -Script $systemScript -Arguments ('-Mode KeyProbe -KeyDir "' + $kd + '" -CopyTo "' + (Join-Path $fixDir 'sys') + '"') -OutFile $out
        Write-WitRaw 'the SYSTEM key probe' $k.Text
        if (-not $k.Ok -or $k.Text -notmatch 'ENDOFREPORT') { Add-WitResult '246' 'F1: the key is sealed in the service account''s user scope' 'NOT-MEASURED' $k.Why }
        elseif ($k.Text -notmatch 'key=anthropic ') { Add-WitResult '246' 'F1: the key is sealed in the service account''s user scope' 'NOT-MEASURED' 'no key file anthropic was written (read SET.AI''s output above)' }
        else {
            $machine = ($k.Text -match 'key=anthropic dpapi-version=\S+ provider=\S+ masterkey=\S+ flags=\S+ machine-scope=True')
            $dec = ($k.Text -match 'key=anthropic unprotect-as-system [^\r\n]*result=DECRYPTED')
            $mkf = [regex]::Match($k.Text, 'key=anthropic masterkey-file=([^\r\n]*)').Groups[1].Value
            if (-not $machine -and -not $dec) { Add-WitResult '246' 'F1: the key is a user-scope DPAPI blob that SYSTEM cannot open' 'PASS' ('machine-scope flag clear; SYSTEM unprotect refused; master key file ' + $mkf) }
            else { Add-WitResult '246' 'F1: the key is a user-scope DPAPI blob' 'FAIL' ('machine-scope ' + $machine + ', decrypted by SYSTEM ' + $dec) }
            $copy = Join-Path (Join-Path $fixDir 'sys') 'copy-anthropic'
            if (Test-Path -LiteralPath $copy) {
                Add-Type -AssemblyName System.Security
                $res = 'refused'
                try { $null = [Security.Cryptography.ProtectedData]::Unprotect([IO.File]::ReadAllBytes($copy), [Text.Encoding]::ASCII.GetBytes('sd-ai key anthropic'), [Security.Cryptography.DataProtectionScope]::CurrentUser); $res = 'DECRYPTED' } catch { $res = 'refused: ' + $_.Exception.Message.Trim() }
                Add-WitResult '246' 'F1: a copied key blob cannot be opened by an elevated administrator either' $(if ($res -like 'refused*') { 'PASS' } else { 'FAIL' }) $res
                Remove-Item -LiteralPath $copy -Force -ErrorAction SilentlyContinue
            }
        }
    } catch { Add-WitResult '246' 'F1: DPAPI' 'NOT-MEASURED' $_.Exception.Message }
    finally {
        Remove-Item -LiteralPath $hf -Force -ErrorAction SilentlyContinue
        $null = Invoke-WitSd -Commands @('SET.AI KEY anthropic CLEAR', 'SET.AI PROVIDER none') -Label 'F1: the dummy key cleared and the provider back to none'
    }
    Add-WitResult '246' 'F7 (poll CPU through a slow answer), F8 (TLS: private CA, redirect, TLS 1.1) need fakemodel.py and a provider aimed at it' 'NOT-MEASURED' 'not part of this sitting: they need the helper''s test provider set up; F9 (typed key, echo off) and F11 (upgrade and uninstall) are the sheet''s and witness-vm-reinstall.ps1''s'
}

# ===================================================================================================== runin253
if ($sections -contains 'runin253') {
    Write-Wit ''
    Write-Wit '=== runin253: run.in WITH debug - the account, the pipe, F4, and the probe for the console step (row 253(b))'
    $u = $null
    try { $u = Get-LocalUser -Name sdrunin -ErrorAction Stop } catch { }
    if ($null -eq $u) { Add-WitResult '253' 'the bare account sdrunin exists' 'FAIL' 'no Windows user sdrunin' }
    else {
        Add-WitResult '253' 'the bare account sdrunin' 'INFO' ('enabled ' + $u.Enabled + '; ' + $u.Description + '; SID ' + $u.SID.Value)
        $in = @()
        foreach ($g in @(Get-LocalGroup)) { if (@(Get-LocalGroupMember -Group $g.Name -ErrorAction SilentlyContinue | Where-Object { $_.SID.Value -eq $u.SID.Value }).Count) { $in += $g.Name } }
        Set-WitCompare '253' 'sdrunin is in no local group (its groups are added per run, in the token)' '' ($in -join ',')
        $rights = Get-WitRights
        foreach ($rn in @('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight', 'SeDenyBatchLogonRight', 'SeDenyServiceLogonRight')) {
            $tr = Test-WitRight $rights $rn $u
            Write-Wit ('  ' + $tr.Listed)
            Set-WitCompare '253' ('sdrunin holds ' + $rn) 'True' $tr.Value
        }
    }
    $p = Get-WitPipe 'sd-runin'
    Write-Wit ('  \\.\pipe\sd-runin: ' + $p.Summary)
    if ($p.OpenError -ne 0) { Add-WitResult '253' 'the run.in pipe is served' 'FAIL' ('open error ' + $p.OpenError) }
    else {
        $aces = @(Get-WitAces $p.Sddl)
        $who = @($aces | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.Sid } | Sort-Object -Unique)
        Set-WitCompare '253' 'only SYSTEM and Administrators may open the run.in pipe' 'BA,SY' ($who -join ',') -Evidence $p.Sddl
        $inst = @($aces | Where-Object { $_.Type -eq 'A' -and $_.Sid -ne 'SY' -and $_.Mask -ge 0 -and (($_.Mask -band 0x4) -ne 0 -or ($_.Mask -band 0x10000000) -ne 0) })
        Set-WitCompare '253' 'Administrators may not create a pipe instance (0x4)' '0' ([string]$inst.Count)
        Set-WitVerdict '253' 'the pipe is served by sdsvc.exe' $p.Server 'sdsvc\.exe$' @()
        $rem = Test-WitPipeRemote 'sd-runin'
        if (-not $rem.Measured) { Add-WitResult '253' 'a remote client is refused' 'NOT-MEASURED' $rem.Why }
        else { Set-WitCompare '253' 'a remote client is refused (loopback UNC open fails)' 'True' ([string]($rem.Remote -ne 0)) -Evidence ('local ' + $rem.Local + ', remote ' + $rem.Remote) }
    }
    $sl = @(Get-Content -LiteralPath (Join-Path $script:WitDataDir 'sdsvc.log') -ErrorAction SilentlyContinue | Where-Object { $_ -match 'run\.in debug:' } | Select-Object -Last 3)
    Set-WitVerdict '253' 'sdsvc.log says run.in debug is serving' ($sl -join "`n") 'run\.in debug: serving' @()

    # F4, the elevated half: an administrator's sd.exe -RUNIN is refused (it is not the service's child).
    $o = Join-Path $fixDir 'runin-f4.out'
    $e = Join-Path $fixDir 'runin-f4.err'
    $pr = Start-Process -FilePath $script:WitSdExe -ArgumentList @('-RUNIN', 'zzrunin', '-QUIET', 'debug', 'bp', 'zzw253') -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
    if (-not $pr.WaitForExit(20000)) { Add-WitResult '253' 'F4: sd.exe -RUNIN from an administrator is refused' 'NOT-MEASURED' ('sd.exe pid ' + $pr.Id + ' is still running after 20 s - LEFT ALONE (never killed); close its window by hand') }
    else {
        $txt = ((Get-Content -LiteralPath $o -Raw -ErrorAction SilentlyContinue) + (Get-Content -LiteralPath $e -Raw -ErrorAction SilentlyContinue))
        Write-WitRaw ('sd.exe -RUNIN (exit ' + $pr.ExitCode + ')') $txt
        Set-WitVerdict '253' 'F4: sd.exe -RUNIN from an elevated administrator is refused (only the service''s child may use it)' $txt 'sd: -RUNIN (is only for run\.in''s debugged program|runs "debug <file> <program>" and nothing else|cannot be given with another entry mode)' @('Compiled', 'zzw253 ran')
    }

    # The probe the console step debugs: it records what the child could reach, in the account's own bp.
    $acct = Join-Path $groupDir 'zzrunin'
    if (-not (Test-Path -LiteralPath $acct)) { Add-WitResult '253' 'the debug probe' 'NOT-MEASURED' 'no zzrunin (run -Only fixtures)' }
    else {
        Remove-Item -LiteralPath (Join-Path $acct 'bp\zzw253.out') -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath (Join-Path $script:WitSdsys 'zzw253probe') -Force -ErrorAction SilentlyContinue
        Write-WitBasic $acct 'zzw253' @(
            '* zzw253 - run under run.in ... debug (row 253(b)): what the separate child can reach; results in this account''s bp',
            '$include err.h',
            "   res = 'logname=' : @logname : ' who=' : @who",
            '* 13 Nov 26 (VM sitting): THEN and ELSE as blocks - "then a ; b end else c" on one line ends the program at that end.',
            "   openpath 'C:/ProgramData/SD/user_accounts/zzwiton/bp' to f1 then",
            "      res<-1> = 'other-account=OPENED'",
            '      close f1',
            '   end else',
            "      res<-1> = 'other-account=refused status=' : status()",
            '   end',
            "   openpath 'C:/ProgramData/SD/sdsys/$cred' to f2 then",
            "      res<-1> = 'cred=OPENED'",
            '      close f2',
            '   end else',
            "      res<-1> = 'cred=refused status=' : status()",
            '   end',
            "   oswrite 'x' to 'C:/ProgramData/SD/sdsys/zzw253probe'",
            "   res<-1> = 'sdsys-write status=' : status()",
            "   open 'bp' to b else stop 'zzw253: no bp'",
            "   write res to b, 'zzw253.out'",
            "   crt 'zzw253 done'",
            'end')
        $r = Invoke-WitSd -Commands @('run.in zzrunin basic bp zzw253 debugging no.query') -Label 'compile the debug probe in zzrunin, with debugging'
        Set-WitVerdict '253' 'the debug probe compiled in zzrunin (for sheet step C8)' $r.Text 'Compiled 1 program\(s\) with no errors' @('with errors in', 'not SD''s own entry', 'is not a command run.in runs')
    }
}

# ===================================================================================================== mark
if ($sections -contains 'mark') {
    $m = Get-WitAuditMark
    Set-Content -LiteralPath (Join-Path $fixDir 'console-mark.txt') -Value ([string]$m + ' ' + (Get-Date).ToString('s')) -Encoding ASCII
    Add-WitResult 'mark' ('the audit trail is ' + $m + ' bytes; the console steps are read from here') 'INFO' (Join-Path $fixDir 'console-mark.txt')
}

# ===================================================================================================== runinchild
if ($sections -contains 'runinchild') {
    Write-Wit ''
    Write-Wit '=== runinchild: the run.in debug child, read WHILE the debugger is stopped in it (row 253(b) F1, F2, F3, F6)'
    $kids = @(Get-Process -Name sd -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -like '*\sdrunin' })
    if ($kids.Count -eq 0) { Add-WitResult '253' 'F1: a separate sd.exe runs as sdrunin while the debugger holds the program' 'NOT-MEASURED' 'no sd.exe runs as sdrunin now: start the console step (sheet C8) and run this while the debugger shows the program' }
    else {
        foreach ($k in $kids) {
            $par = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $k.Id)
            $pp = Get-CimInstance Win32_Process -Filter ('ProcessId=' + $par.ParentProcessId) -ErrorAction SilentlyContinue
            Write-Wit ('  child pid ' + $k.Id + ' ' + $k.UserName + ' parent ' + $par.ParentProcessId + ' ' + $(if ($pp) { $pp.Name } else { '?' }) + '; command line: ' + $par.CommandLine)
        }
        Add-WitResult '253' 'F1: a separate sd.exe runs as sdrunin (started by the service, not by the SDSYS session)' 'PASS' (($kids | ForEach-Object { 'pid ' + $_.Id + ' ' + $_.UserName }) -join ', ')
        $out = Join-Path (Join-Path $fixDir 'sys') 'token.txt'
        Write-Wit '  reading its token as SYSTEM (a one-shot task; about 10 seconds)'
        $t = Invoke-WitAsSystem -Script $systemScript -Arguments '-Mode Token -UserName sdrunin' -OutFile $out
        Write-WitRaw 'the SYSTEM token probe' $t.Text
        if (-not $t.Ok -or $t.Text -notmatch 'ENDOFREPORT') { Add-WitResult '253' 'the child''s token' 'NOT-MEASURED' $t.Why }
        else {
            $grp = Get-WitSid 'sdg_zzrunin'   # 13 Nov 26: zzrunin is a GROUP account, so its group is sdg_ (row 287: sdrunin.c wants sdu_)
            $sdu = Get-WitSid 'sdusers'
            $lines = @($t.Text -split "`r?`n")
            $g = ($lines | Where-Object { $_ -match ' groups=' } | Select-Object -First 1)
            $h = ($lines | Where-Object { $_ -match ' integrity=' } | Select-Object -First 1)
            $hasGrp = ($g -match ([regex]::Escape($grp) + '\|0x([0-9A-F]+);'))
            $grpEnabled = $hasGrp -and (([Convert]::ToInt32($Matches[1], 16) -band 4) -ne 0)
            $adm = [regex]::Match([string]$g, 'S-1-5-32-544\|0x([0-9A-F]+);')
            $admEnabled = $adm.Success -and (([Convert]::ToInt32($adm.Groups[1].Value, 16) -band 4) -ne 0)
            Set-WitCompare '253' ('F2: the child''s token has the account''s group sdg_zzrunin enabled (' + $grp + ')') 'True' ([string]$grpEnabled) -Evidence $g
            Set-WitCompare '253' ('F2: and sdusers (' + $sdu + ')') 'True' ([string]($g -match [regex]::Escape($sdu))) -Evidence $g
            Set-WitCompare '253' 'F3: no enabled Administrators in the child''s token' 'False' ([string]$admEnabled) -Evidence $g
            Set-WitVerdict '253' 'F3: the child is at Medium integrity (S-1-16-8192)' $h 'integrity=S-1-16-8192\b' @('integrity=S-1-16-12288', 'integrity=S-1-16-16384')
            Set-WitVerdict '253' 'F3: the child holds no privilege' $h 'privcount=0\b' @()
            Set-WitVerdict '253' 'F6: the child is in a job' $h 'injob=1\b' @()
        }
    }
}

# ===================================================================================================== afterconsole
if ($sections -contains 'afterconsole') {
    Write-Wit ''
    Write-Wit '=== afterconsole: read back what the SDSYS console steps did'
    $mk = 0
    try { $mk = [long]((Get-Content -LiteralPath (Join-Path $fixDir 'console-mark.txt') -ErrorAction Stop) -split ' ')[0] } catch { $mk = 0 }
    $lines = @(Get-WitAuditSince $mk)
    Write-Wit ('  ' + $lines.Count + ' audit lines since the console mark (' + $mk + ')')

    # 197: the PDEBUG store.
    $sdsysSid = Get-WitSid 'SDSYS'
    $prof = (Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue | Where-Object { $_.SID -eq $sdsysSid }).LocalPath
    $store = Join-Path ([string]$prof) 'AppData\Local\sd\pdebug'
    if ([string]::IsNullOrEmpty($prof) -or -not (Test-Path -LiteralPath $store)) { Add-WitResult '197' 'PDEBUG made SDSYS''s private store' 'NOT-MEASURED' ('no ' + $store + ' (sheet step C6 not done, or PDEBUG did not start)') }
    else {
        $sd = (Get-Acl -LiteralPath $store).Sddl
        $who = @(Get-WitAces $sd | Where-Object { $_.Type -eq 'A' } | ForEach-Object { $_.Sid } | Sort-Object -Unique)
        $extra = @($who | Where-Object { @('SY', 'BA', $sdsysSid) -notcontains $_ })
        Set-WitCompare '197' 'the PDEBUG store is protected (no inherited ACEs)' 'True' ([string]($sd -match 'D:P')) -Evidence ($store + ' ' + $sd)
        Set-WitCompare '197' 'the store grants only SDSYS, SYSTEM and Administrators' '' ($extra -join ',') -Evidence ($who -join ',')
        Set-WitCompare '197' 'SDSYS has full control of its store' 'True' ([string]($sd -match ('\(A;OICI;FA;;;' + [regex]::Escape($sdsysSid) + '\)'))) -Evidence $sd
    }

    # 253(b): the probe's own record, the sdsys write it must not have made, and the audit pair.
    $res = Join-Path $groupDir 'zzrunin\bp\zzw253.out'
    if (-not (Test-Path -LiteralPath $res)) { Add-WitResult '253' 'the debugged program ran in the child and wrote its results' 'NOT-MEASURED' ('no ' + $res + ' (sheet step C8: run it to its end with F9)') }
    else {
        $txt = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($res)) -replace [char]254, ' | '
        Add-WitResult '253' 'F1/F6: the debugged program ran to its end in the child (its record is written)' 'PASS' $txt
        Set-WitVerdict '253' 'F3: the child could not open another account' $txt 'other-account=refused' @('other-account=OPENED')
        Set-WitVerdict '253' 'F3: the child could not open sdsys\$cred' $txt 'cred=refused' @('cred=OPENED')
        Set-WitCompare '253' 'F3: the child wrote nothing into sdsys' 'False' ([string](Test-Path -LiteralPath (Join-Path $script:WitSdsys 'zzw253probe')))
        Set-WitVerdict '253' 'the program ran as sdrunin (@logname)' $txt 'logname=sdrunin' @()
    }
    $rl = @($lines | Where-Object { $_ -match 'run\.in (begin|end) account=zzrunin' })
    Write-WitRaw 'audit: run.in lines' ($rl -join "`n")
    Set-WitVerdict '253' 'the audit has run.in begin ... command=debug process=separate and run.in end ... command=debug with no reason' ($rl -join "`n") '(?s)run\.in begin account=zzrunin command=debug process=separate.*run\.in end account=zzrunin command=debug(?! reason)' @('command=debug reason=')

    # 201's abort (Ctrl-C on zzbig), 228's S and A, 218/221/227 page starts: the audit as evidence beside the sheet's answers.
    $ab = @($lines | Where-Object { $_ -match 'run\.in revert account=zzrunin reason=abort' })
    if ($ab.Count) { Add-WitResult '201' 'Ctrl-C then A during run.in basic aborts and reverts' 'PASS' $ab[0] } else { Add-WitResult '201' 'Ctrl-C then A during run.in basic aborts and reverts' 'NOT-MEASURED' 'no "run.in revert account=zzrunin reason=abort" line (the compile may have ended before Ctrl-C: the sheet''s answer decides)' }
    $ssh = @($lines | Where-Object { $_ -match 'remote\.ssh on' })
    $api = @($lines | Where-Object { $_ -match 'remote\.api (local|on)' } | ForEach-Object { [regex]::Match($_, 'remote\.api \w+').Value })
    if ($ssh.Count) { Add-WitResult '228' 'tool.remote S with on wrote remote.ssh on' 'PASS' $ssh[0] } else { Add-WitResult '228' 'tool.remote S with on' 'NOT-MEASURED' 'no remote.ssh on line since the mark' }
    if (($api -join ',') -match 'remote\.api local.*remote\.api on') { Add-WitResult '228' 'tool.remote A to LOCAL and back to ON' 'PASS' ($api -join ', ') } else { Add-WitResult '228' 'tool.remote A to LOCAL and back to ON' 'NOT-MEASURED' ('remote.api lines: ' + ($api -join ', ')) }
    $pages = @($lines | Where-Object { $_ -match 'tool start app=|command=home|modify\.account|create\.account|delete\.account' })
    Write-WitRaw 'audit: page starts and the account verbs the pages ran' ($pages -join "`n")
    Add-WitResult '221' ('the account verbs tool.accounts ran: ' + @($lines | Where-Object { $_ -match '(modify|create|delete)\.account' }).Count + ' audit lines') 'INFO' 'the sheet''s answers (C5) are the witness; the lines are above'

    # 247: the user script's lines, stamped with their real users.
    $ur = Join-Path $fixDir 'user-results.json'
    if (-not (Test-Path -LiteralPath $ur)) { Add-WitResult '247' 'the ordinary script''s audit lines (ssh session, forged claim from a sdusers member)' 'NOT-MEASURED' ('no ' + $ur + ' (run witness-vm-user.ps1 first)') }
    else {
        $u = Get-Content -LiteralPath $ur -Raw | ConvertFrom-Json
        $all = @(Get-WitAuditSince 0)
        foreach ($k in @(@('SshNonce', 'zzwitoff', 'an ssh session''s LOGTO refusal'), @('ForgeNonce', 'zzwiton', 'a forged uid-0 record sent by a sdusers member'))) {
            $n = [string]$u.($k[0])
            if ($n -eq '') { Add-WitResult '247' ($k[2] + ' is stamped with its real user') 'NOT-MEASURED' 'the user script recorded no nonce'; continue }
            $l = @($all | Where-Object { $_ -match $n })
            if ($l.Count -eq 0) { Add-WitResult '247' ($k[2] + ' is stamped with its real user') 'FAIL' ('no audit line holds ' + $n) ; continue }
            $want = 'user=' + [regex]::Escape($vm) + '\\' + $k[1] + ' '
            $ok = ($l[0] -match $want)
            if ($k[0] -eq 'ForgeNonce' -and [string]$u.ForgePid -ne '') { $ok = $ok -and ($l[0] -match ('pid=' + [string]$u.ForgePid + ' ')) }
            Add-WitResult '247' ($k[2] + ' is stamped with its real user' + $(if ($k[0] -eq 'ForgeNonce') { ' and pid' } else { '' })) $(if ($ok) { 'PASS' } else { 'FAIL' }) $l[0]
        }
    }
}

# ===================================================================================================== cleanup
if ($sections -contains 'cleanup') {
    Write-Wit ''
    Write-Wit '=== cleanup: the fixture accounts, programs, printer and the passwords file'
    foreach ($n in @('zzwitoff', 'zzwiton', 'zzwitapi', 'zzwitsh', 'zzrunin')) {
        if (-not (Test-Registered $n)) { continue }
        $null = Invoke-WitSd -Commands @(('DELETE.ACCOUNT ' + $n), 'Y') -Label ('delete ' + $n) -TimeoutSec 180
        Add-WitResult 'cleanup' ('DELETE.ACCOUNT ' + $n) $(if (Test-Registered $n) { 'FAIL' } else { 'PASS' }) ('register record now ' + (Test-Registered $n) + ', Windows user now ' + (Test-WinUser $n))
    }
    foreach ($f in @('zzfix', 'zzw240', 'zzw247lk')) { Remove-Item -LiteralPath (Join-Path $script:WitSdsys ('bp\' + $f)) -Force -ErrorAction SilentlyContinue }
    $null = Invoke-WitSd -Commands @('DELETE bp.out zzfix', 'DELETE bp.out zzw240', 'DELETE bp.out zzw247lk') -Label 'the compiled fixture programs'
    if (Get-Printer -Name 'SD Witness PDF' -ErrorAction SilentlyContinue) { Remove-Printer -Name 'SD Witness PDF' }
    Remove-Item -LiteralPath (Get-WitFixturePath) -Force -ErrorAction SilentlyContinue
    Set-WitCompare 'cleanup' 'the passwords file is gone' 'False' ([string](Test-Path -LiteralPath (Get-WitFixturePath)))
}

$code = Complete-Wit
exit $code
