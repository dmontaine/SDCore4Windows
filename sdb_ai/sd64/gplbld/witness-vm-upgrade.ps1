# witness-vm-upgrade.ps1 - group B of the Core VM witness sitting (13 Nov 2026): an upgrade from the last release, W1.1-3,
# to the new build.  Rows (RELEASE_1.1): 256 (the four PY_* samples refreshed into the preserved sdsys\bp), 266 (SDSYS's VOC
# refreshed at its next sign-in), 260 (an account the old release made, whose $cred an old release stored, still signs in),
# 277 (an install over an existing sdssh keeps an administrator's removal).  verify-upgrade.ps1 -Snapshot / -Compare runs
# beside it (the probe pair, voc_template replaced, $upgrade-probe kept); the sheet orders the two.
#
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-upgrade.ps1 -Phase Before   (on W1.1-3)
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-upgrade.ps1 -Phase After    (on the new build)
#
# ELEVATED PowerShell in the VM, SDSYS signed in (the seat).  assert-current is NOT called: between the phases the install
# is meant to be the OLD build (verify-upgrade.ps1's header).  Before makes two accounts with the OLD release's CREATE.ACCOUNT
# (zzwitold: API, zzwitold2: SSH; passwords generated, kept in C:\SD-witness\fixtures.json), takes zzwitold2 out of sdssh by
# hand, and writes C:\SD-witness\upgrade-before.json.  After reads the same things again and judges.  Exit 0 passed, 1 FAIL,
# 2 could not run.
#
# START-HISTORY:
# 13 Nov 26  New, for the Core VM witness sitting.  Parse-checked; not run (it needs the VM).
# END-HISTORY

param([Parameter(Mandatory = $true)][ValidateSet('Before', 'After')][string]$Phase)

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

Start-Wit ('witness-vm-upgrade-' + $Phase.ToLower()) @($Phase)
if (-not (Test-WitElevated)) { Write-Wit 'CANNOT RUN: not elevated.'; exit 2 }
if (-not (Test-Path -LiteralPath $script:WitSdExe)) { Write-Wit 'CANNOT RUN: SD is not installed.'; exit 2 }
$statePath = Join-Path $script:WitRoot 'upgrade-before.json'
$srcBp = Join-Path (Split-Path -Parent $PSScriptRoot) 'sdsys\bp'
$insBp = Join-Path $script:WitSdsys 'bp'
$credDir = Join-Path $script:WitSdsys '$cred'
$py = @('PY_JSON', 'PY_TERM', 'PY_TEST', 'PY_TEST2')
$newVerbs = @('remote.sdsys', 'set.job', 'tool.remote', 'tool.ai')

$w = Invoke-WitSd -Commands @('WHO') -Label 'the seat' -TimeoutSec 90
if (-not $w.Ok -or $w.Text -notmatch '(?m)^\s*\d+\s+SDSYS\b') { Write-Wit 'CANNOT RUN: the SDSYS seat did not answer WHO as SDSYS (sign in as SDSYS once, switch back).'; exit 2 }

function Get-UpFacts {
    $f = [ordered]@{}
    $f.SdExe = (Get-FileHash -LiteralPath $script:WitSdExe -Algorithm SHA256).Hash
    $f.Version = ''
    foreach ($k in @(Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'SD*' })) { $f.Version += ($k.DisplayName + ' ' + $k.DisplayVersion + '; ') }
    $f.Py = @($py | ForEach-Object { $p = Join-Path $insBp $_; if (Test-Path -LiteralPath $p) { $_ + '=' + (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash } else { $_ + '=absent' } })
    $f.Cred = @(Get-ChildItem -LiteralPath $credDir -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    $f.Sdssh = @(Get-WitGroupMembers 'sdssh' | Sort-Object)
    $f.Probe = Test-Path -LiteralPath (Join-Path $insBp '$upgrade-probe')
    return $f
}
# Each verb in its own seat call, anchored on the record's program name (V / CA / $set_job ...), which only a printed record
# carries: the command line "CT VOC set.job" does not.  The first call is SDSYS's sign-in, which refreshes its VOC.
$progOf = @{ 'remote.sdsys' = '$remotesdsys'; 'set.job' = '$set_job'; 'tool.remote' = '$tool_remote'; 'tool.ai' = '$tool_ai' }
function Get-VocVerbs {
    $h = @{}
    foreach ($v in $newVerbs) {
        $r = Invoke-WitSd -Commands @(('CT VOC ' + $v)) -Label ('is ' + $v + ' in SDSYS''s VOC?')
        if (-not $r.Ok) { return $null }
        $h[$v] = ([string]$r.Text).Contains($progOf[$v])
    }
    return $h
}

if ($Phase -eq 'Before') {
    $f = Get-UpFacts
    $fix = Read-WitFixtures
    if ($null -eq $fix) { $fix = @{} }
    foreach ($a in @(@('zzwitold', 'API'), @('zzwitold2', 'SSH'))) {
        $n = $a[0]
        if (Test-Path -LiteralPath (Join-Path (Join-Path $script:WitSdsys 'accounts') $n)) { Write-Wit ('  ' + $n + ' exists already: kept'); continue }
        $pw = New-SdTestPassword
        $null = Invoke-WitSd -Commands @(('CREATE.ACCOUNT USER ' + $n + ' ' + $a[1]), $pw, $pw) -Label ('the OLD release makes ' + $n) -Secrets @($pw) -TimeoutSec 180
        if (Test-Path -LiteralPath (Join-Path (Join-Path $script:WitSdsys 'accounts') $n)) { $fix[$n] = $pw }
    }
    Save-WitFixtures $fix ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value)
    $f.Cred = @(Get-ChildItem -LiteralPath $credDir -Force -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Write-Wit ('  $cred holds (the case the old release wrote): ' + ($f.Cred -join ', '))
    $removed = ''
    if (@(Get-WitGroupMembers 'sdssh') -contains 'zzwitold2') { Remove-LocalGroupMember -Group sdssh -Member 'zzwitold2' -ErrorAction SilentlyContinue; $removed = 'zzwitold2' }
    $f.Sdssh = @(Get-WitGroupMembers 'sdssh' | Sort-Object)
    $f.Removed = $removed
    $vv = Get-VocVerbs
    $f.Voc = @()
    if ($null -ne $vv) { $f.Voc = @($newVerbs | ForEach-Object { $_ + '=' + $vv[$_] }) }
    foreach ($k in $f.Keys) { Write-Wit ('  ' + $k + ' = ' + (@($f[$k]) -join ', ')) }
    ($f | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath $statePath -Encoding ASCII
    Add-WitResult 'context' ('the old install recorded: ' + $f.Version) 'INFO' $statePath
    if ($removed -eq '') { Add-WitResult '277' 'zzwitold2 taken out of sdssh by hand before the upgrade' 'NOT-MEASURED' 'it was not in sdssh after CREATE.ACCOUNT ... SSH' }
    Write-Wit '  Next (sheet): verify-upgrade.ps1 -Snapshot, then the new installer over this install, then -Compare and this script -Phase After.'
}

if ($Phase -eq 'After') {
    if (-not (Test-Path -LiteralPath $statePath)) { Write-Wit ('CANNOT RUN: no ' + $statePath + ' (run -Phase Before on the old install first).'); exit 2 }
    $b = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $f = Get-UpFacts
    foreach ($k in $f.Keys) { Write-Wit ('  now ' + $k + ' = ' + (@($f[$k]) -join ', ')) }
    if ($b.SdExe -eq $f.SdExe) { Add-WitResult 'context' 'the upgrade replaced sd.exe' 'FAIL' 'the hash did not move: the new installer did not run, or is the old one' }
    else { Add-WitResult 'context' ('upgraded: ' + $b.Version + ' -> ' + $f.Version) 'INFO' ('sd.exe ' + $b.SdExe.Substring(0, 12) + ' -> ' + $f.SdExe.Substring(0, 12)) }

    foreach ($n in $py) {
        $src = Join-Path $srcBp $n
        $ins = Join-Path $insBp $n
        if (-not (Test-Path -LiteralPath $src)) { Add-WitResult '256' ($n + ' refreshed into sdsys\bp') 'NOT-MEASURED' ('no source copy at ' + $src); continue }
        $hs = (Get-FileHash -LiteralPath $src -Algorithm SHA256).Hash
        $hi = ''
        if (Test-Path -LiteralPath $ins) { $hi = (Get-FileHash -LiteralPath $ins -Algorithm SHA256).Hash }
        $was = @($b.Py | Where-Object { $_ -like ($n + '=*') }) -join ''
        Set-WitCompare '256' ($n + ' in the preserved sdsys\bp is the new build''s, byte for byte') $hs $hi -Evidence ('before the upgrade: ' + $was)
    }
    Set-WitCompare '256' '$upgrade-probe in sdsys\bp was kept (bp is preserved)' ([string]$b.Probe) ([string]$f.Probe) -Evidence 'planted by verify-upgrade.ps1 -Snapshot; False on both sides means -Snapshot was not run'

    $vv = Get-VocVerbs
    if ($null -eq $vv) { Add-WitResult '266' 'SDSYS''s VOC refreshed at its sign-in after the upgrade' 'NOT-MEASURED' 'the seat did not run' }
    else {
        $miss = @($newVerbs | Where-Object { -not $vv[$_] })
        $wasMissing = @($b.Voc | Where-Object { $_ -like '*=False' })
        if ($miss.Count -eq 0) { Add-WitResult '266' 'SDSYS''s VOC has the new build''s verbs after its first sign-in on the upgraded install' 'PASS' ('before: ' + (@($b.Voc) -join ', ') + '; after: all four present') }
        else { Add-WitResult '266' 'SDSYS''s VOC has the new build''s verbs after its first sign-in' 'FAIL' ('missing: ' + ($miss -join ',') + '; before: ' + (@($b.Voc) -join ', ')) }
        if ($wasMissing.Count -eq 0) { Add-WitResult '266' 'the control: the old release lacked at least one of them' 'NOT-MEASURED' 'the old VOC already had all four, so "refreshed" is not shown by them' }
    }

    $removed = [string]$b.Removed
    $added = @(@($f.Sdssh) | Where-Object { @($b.Sdssh) -notcontains $_ })
    if ($removed -eq '') { Add-WitResult '277' 'the upgrade keeps an administrator''s removal from sdssh' 'NOT-MEASURED' 'Before removed no member' }
    elseif (@($f.Sdssh) -contains $removed) { Add-WitResult '277' 'the upgrade keeps an administrator''s removal from sdssh' 'FAIL' ($removed + ' is in sdssh again; added: ' + ($added -join ',')) }
    else { Add-WitResult '277' 'the upgrade keeps an administrator''s removal from sdssh' 'PASS' ('before ' + (@($b.Sdssh) -join ',') + '; after ' + (@($f.Sdssh) -join ',') + '; added: ' + $(if ($added.Count) { $added -join ',' } else { 'none' })) }

    # 260: the old account signs in over the API after the upgrade (its $cred record is the old release's).
    Write-Wit ('  $cred before: ' + (@($b.Cred) -join ', ') + '   now: ' + (@($f.Cred) -join ', '))
    $fix = Read-WitFixtures
    $pw = ''
    if ($null -ne $fix -and $fix.ContainsKey('zzwitold')) { $pw = $fix['zzwitold'] }
    $null = Invoke-WitSd -Commands @('remote.api local', 'N') -Label 'the API to LOCAL (answer N; SD is restarted next)' -TimeoutSec 180
    $rs = & $script:WitSdExe -restart 2>&1 | ForEach-Object { [string]$_ }
    Write-WitRaw 'sd -restart' ($rs -join "`n")
    Start-Sleep -Seconds 3
    $port = 0
    try { $m = [regex]::Match([IO.File]::ReadAllText((Join-Path $script:WitDataDir 'sd.conf')), '(?m)^\s*APIPORT\s*=\s*(\d+)'); if ($m.Success) { $port = [int]$m.Groups[1].Value } } catch { }
    $pyExe = Get-Command python.exe -ErrorAction SilentlyContinue
    if ($pw -eq '' -or $port -eq 0 -or $null -eq $pyExe) { Add-WitResult '260' 'an account the old release made signs in after the upgrade' 'NOT-MEASURED' ('password ' + ($pw -ne '') + ', APIPORT ' + $port + ', python ' + ($null -ne $pyExe)) }
    else {
        $env:SD_SCRAM_PASSWORD = $pw
        if (Test-Path -LiteralPath 'C:\sdtools\bin\libssl-3-x64.dll') { $env:SD_PROBE_LIBSSL = 'C:\sdtools\bin\libssl-3-x64.dll' }
        $po = & $pyExe.Source (Join-Path $PSScriptRoot 'scram-probe.py') --user zzwitold --port $port -- WHO 2>&1 | ForEach-Object { [string]$_ }
        Remove-Item Env:\SD_SCRAM_PASSWORD -ErrorAction SilentlyContinue
        $pt = $po -join "`n"
        Write-WitRaw 'scram-probe as zzwitold' $pt
        Set-WitVerdict '260' 'an account the old release made (its $cred record stored by W1.1-3) signs in over the API after the upgrade' $pt 'SCRAM: server signature VERIFIED' @('login REFUSED', 'MISMATCH')
    }
    # verify-upgrade.ps1 writes its transcripts under this user's LOCALAPPDATA; copy them beside these logs so step 14 sends one folder.
    foreach ($vl in @(Get-ChildItem -LiteralPath (Join-Path $env:LOCALAPPDATA 'SD-verify') -Filter 'verify-upgrade-*.log' -ErrorAction SilentlyContinue)) {
        Copy-Item -LiteralPath $vl.FullName -Destination (Join-Path (Join-Path $script:WitRoot 'logs') $vl.Name) -Force -ErrorAction SilentlyContinue
        Write-Wit ('  copied ' + $vl.FullName + ' into C:\SD-witness\logs')
    }
    $r = Invoke-WitSd -Commands @('DELETE.ACCOUNT zzwitold', 'Y', 'DELETE.ACCOUNT zzwitold2', 'Y') -Label 'remove the two accounts' -TimeoutSec 240
    Add-WitResult 'cleanup' 'zzwitold and zzwitold2 removed' 'INFO' ('register records left: ' + @(@('zzwitold', 'zzwitold2') | Where-Object { Test-Path -LiteralPath (Join-Path (Join-Path $script:WitSdsys 'accounts') $_) }).Count)
}

$code = Complete-Wit
exit $code
