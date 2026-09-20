<#
.SYNOPSIS
    RELEASE_1.1 46's witness: a non-administrator account, over the API, can
    write its OWN VOC and a DATA file the administrator created for it - the
    write that was refused ER_RDONLY (3018) before fix (a) in dh_open.c.

.DESCRIPTION
    THE BUG.  Every hashed file (`%0`) CREATE.ACCOUNT makes in a new account is
    created by CREATEA under the elevated administrator, and since 15 Aug 2026
    the Windows port transfers no ownership.  dh_open.c decided read-only from
    `access(pathname, W_OK)`, and under the MSYS2 `noacl` mount `access()` does
    not read the DACL - it grants write to the file's OWNER only.  So the
    account's own user (the API session's euid, via S4U) was refused every write
    to its own VOC, over the API and ssh alike, while a DIRECTORY file - which
    SD opens without asking `access()` - wrote fine on the identical ACL.

    THE FIX (a).  dh_open.c now opens the subfile for update and drops to
    read-only only if that open fails, honouring the real DACL, which grants the
    account's group Modify.

    WHAT THIS MEASURES, as the account's own user over a real API session:
      - a write to the account's OWN VOC is WRITTEN, and the record reads back
        with its content (so it really landed, not a spurious ack);
      - a write to a DATA file the ADMINISTRATOR created in the account is
        WRITTEN and reads back;
      - CONTROL: neither record existed before the write (the null case), and
        neither WRITE line carries status 3018.
    The `%0` owners are printed so the log shows the write succeeded DESPITE the
    file being owned by the administrator - which is the whole point of fix (a).

    BEFORE THE FIX (or on a stale tree) the two writes come back REFUSED 3018
    and the run FAILS (exit 1); after the cycle they are WRITTEN.  assert-current
    refuses a stale tree first, so this cannot pass by measuring the old binary.

    ELEVATED, and it refuses otherwise: CREATE.ACCOUNT and the APIPORT restart
    need it.  APIPORT is added to sd.conf and removed again, SD restarted twice;
    the restore runs in a finally.  NOT SHIPPED - on assert-current's
    $neverShipped.

.PARAMETER Prefix
    Throwaway account name.  Use one nobody has used; CREATE.ACCOUNT refuses a
    name it has seen.

.PARAMETER Port
    API port, default 4243.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File verify-vocwrite.ps1 -Prefix sdvocw1
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [int] $Port = 4243
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$SvcName = 'SD'
$conf    = Join-Path $env:ProgramData 'SD\sd.conf'
$backup  = $conf + '.before-vocwrite'
$accts   = Join-Path $env:ProgramData 'SD\sdsys\accounts'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-vocwrite-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}
function Refuse($msg) { Write-Host ''; Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch { }; exit 2 }
function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# Drives an SD session from SDSYS; TERM re-issued after every LOGTO because
# LOGIN resets terminal geometry (verify-scramlogin's Invoke-SD).
# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT (sdsys-seat.ps1; verify-createaccount
# was the pilot, witnessed 18/18 on 19 Sep).  THE "LOGTO SDSYS" PREFIX THIS USED
# TO SEND IS REFUSED (10002) FROM ANY SESSION THAT DID NOT START AS THE OS SDSYS
# ACCOUNT with an elevated, interactive token, and an elevated Don is not one.  So
# the commands go to a task inside SDSYS's own live session and the text comes back
# through a file.  The TERM handling this function carried - first line, and again
# after every LOGTO - lives in the helper now (Expand-SeatCommands) with its own
# guard.  THE "LOGTO $upper" CALLS BELOW STILL WORK: SDSYS -> a personal account is
# allowed; only the way BACK (LOGTO SDSYS) is refused, and nothing here goes back.
# A seat that did not run THROWS rather than returning '' (Invoke-SdSeatText).
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
function Invoke-SD([string[]]$commands) {
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec 180)
}

function Stop-SD {
    if (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) {
        & "$env:SystemRoot\System32\sc.exe" stop $SvcName | Out-Null
    }
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    return -not [bool](Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue)
}

function Start-SD {
    & "$env:SystemRoot\System32\sc.exe" start $SvcName | Out-Null
    $deadline = (Get-Date).AddSeconds(45)
    while (-not (Get-Process -Name sdwind -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    return [bool](Get-Process -Name sdwind -ErrorAction SilentlyContinue)
}

# The API client, proved by its own units first (verify-scramlogin's shape).
$Probe      = Join-Path $Gplbld 'scram-probe.py'
$ProbeUnits = Join-Path $Gplbld 'test-scramprobe-units.py'
$Python     = $null

function Test-ProbeInstrument {
    foreach ($f in @($Probe, $ProbeUnits)) {
        if (-not (Test-Path -LiteralPath $f)) { Refuse "$f is missing - it is the API client this verifier drives." }
    }
    $cmd = Get-Command python -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { Refuse 'python is not on PATH - scram-probe.py is the API client this verifier drives.' }
    $script:Python = $cmd.Source
    Write-Host "   python : $script:Python"
    Write-Host "   probe  : $Probe"
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $u = & $script:Python $ProbeUnits 2>&1; $uc = $LASTEXITCODE } finally { $ErrorActionPreference = $saved }
    foreach ($l in @($u)) { Write-Host ('   | ' + ("$l".TrimEnd("`r"))) }
    Write-Host "   test-scramprobe-units exit $uc"
    return $uc
}

# $probeArgs, NOT $args (the automatic variable - CLAUDE.md, 23 Aug 2026).
function Invoke-ScramProbe([string]$label, [string]$password, [string[]]$probeArgs) {
    if ($null -eq $probeArgs -or $probeArgs.Count -eq 0) {
        Refuse "Invoke-ScramProbe '$label' was handed no arguments - it would measure nothing."
    }
    Write-Host ''
    Write-Host "   -- scram-probe: $label"
    Write-Host ('   command : ' + $script:Python + ' ' + $Probe + ' ' + ($probeArgs -join ' '))
    Write-Host ('   password: in SD_SCRAM_PASSWORD, {0} characters' -f $password.Length)
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    $env:SD_SCRAM_PASSWORD = $password
    try { $raw = & $script:Python $Probe @probeArgs 2>&1; $code = $LASTEXITCODE }
    finally {
        Remove-Item -Path 'Env:SD_SCRAM_PASSWORD' -ErrorAction SilentlyContinue
        $ErrorActionPreference = $saved
    }
    $lines = @($raw | ForEach-Object { "$_".TrimEnd("`r") })
    foreach ($l in $lines) { Write-Host ('   | ' + $l) }
    Write-Host "   probe exit $code"
    return [pscustomobject]@{ Label = $label; Code = $code; Lines = $lines }
}

function Test-ProbeLine($r, [string]$pattern) {
    foreach ($l in $r.Lines) { if ($l -cmatch $pattern) { return $true } }
    return $false
}

function New-Marker([string]$tag) {
    $bytes = New-Object byte[] 12
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    return $tag + '-' + (([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '').ToUpper())
}

# ---------------------------------------------------------------------------
if (-not $Prefix) { Refuse 'pass -Prefix, e.g. -Prefix sdvocw1.  It names the throwaway account.' }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Refuse 'Run this from an ELEVATED PowerShell - it creates and deletes an account.'
}

Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current refuses - run gplbld/cycle.ps1 first (this needs the dh_open.c fix installed).' }

Step '0b' 'Proving the client before using it'
if ((Test-ProbeInstrument) -ne 0) { Refuse 'test-scramprobe-units failed - the client is not trusted, so nothing it says about the server would be.' }

$upper = $Prefix.ToUpper()
if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) { Refuse "$Prefix already exists as a Windows account.  Use a fresh -Prefix." }
if (Test-Path -LiteralPath (Join-Path $accts $upper))        { Refuse "$upper is still in the ACCOUNTS register.  Use a fresh -Prefix." }

$madeAcct  = $false
$confMoved = $false
$pw        = ''

try {
    Add-Type -AssemblyName System.Web

    # -----------------------------------------------------------------------
    Step 1 "Creating the throwaway non-administrator account $Prefix (PROGRAMMER, reach API)"
    $winPw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    # 19 Sep 26 - RELEASE_1.1 64: PROGRAMMER is REFUSED at create time now
    # (createa's keyword case, sysmsg 2018 - the whole command stops and no
    # account is made), so the access keyword is the whole of the line.
    # 20 Sep 26 - RELEASE_1.1 76: PROVE THE SDSYS SEAT BEFORE CREATING ANYTHING, so a
    # missing SDSYS session is exit 2 ("could not run") and not a thrown error at the
    # first SD call that reads as a product failure.  See sdsys-seat.ps1.
    Assert-SdSeat -Label 'verify-vocwrite'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $Prefix API", $winPw, $winPw)
    if (-not (Test-Path -LiteralPath (Join-Path $accts $upper))) { Write-Host $out; Refuse "CREATE.ACCOUNT did not register $Prefix." }
    $madeAcct = $true
    if (Get-LocalGroupMember -Group 'Administrators' -Member $Prefix -ErrorAction SilentlyContinue) {
        Refuse "$Prefix is an Administrator - it would OWN its files and the test would pass vacuously.  Use a non-admin tier."
    }
    Write-Host "   $Prefix created and is NOT an administrator"

    # -----------------------------------------------------------------------
    Step 2 'Setting its API password'
    $bytes = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + 'aA1'
    $out = Invoke-SD @(("MODIFY.PASSWORD " + $upper), $pw, $pw)
    if ($out -notmatch 'Password set for account') { Write-Host $out; Refuse 'MODIFY.PASSWORD did not report success.' }
    Write-Host '   password set'

    # -----------------------------------------------------------------------
    Step 3 "Creating a DATA file ZZVOCW in $upper, as the administrator"
    # A hashed DATA file the account did NOT create - so its %0 is owned by the
    # administrator, the same shape as the account's own VOC.  Both are the
    # files fix (a) is about.
    $out = Invoke-SD @("LOGTO $upper", 'CREATE.FILE ZZVOCW DYNAMIC NO.QUERY')
    if ($out -notmatch 'Created DATA part as zzvocw\b') { Write-Host $out; Refuse 'CREATE.FILE ZZVOCW did not report the DATA part created.' }
    $acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $upper)
    foreach ($p in @('voc\%0', 'zzvocw\%0')) {
        $full = Join-Path $acctDir $p
        $own  = if (Test-Path -LiteralPath $full) { (Get-Acl -LiteralPath $full).Owner } else { '<missing>' }
        Write-Host ("   {0,-12} owner: {1}   (the API session runs as {2}; fix (a) makes the write succeed anyway)" -f $p, $own, $Prefix)
    }

    # -----------------------------------------------------------------------
    Step 4 "Enabling APIPORT=$Port in the installed sd.conf and restarting SD"
    Copy-Item -LiteralPath $conf -Destination $backup -Force
    $confMoved = $true
    $lines = @(Get-Content -LiteralPath $conf) | Where-Object { $_ -notmatch '^\s*APIPORT\s*=' }
    $lines += ('APIPORT=' + $Port)
    Set-Content -LiteralPath $conf -Value $lines -Encoding Ascii
    if (-not (Stop-SD))  { Refuse 'SD would not stop - close any open session and try again.' }
    if (-not (Start-SD)) { Refuse 'SD would not start again.  Read the SD error log.' }
    Start-Sleep -Seconds 2
    $listen = @(netstat -an | Select-String 'LISTENING' | Where-Object { $_ -match (':' + $Port + '\s') })
    if ($listen.Count -eq 0) { Refuse 'Nothing is listening on the port - there is nothing to talk to.' }
    Write-Host "   listener on $Port"

    # -----------------------------------------------------------------------
    Step 5 'CONTROL: neither record exists yet (so a later "written" is not measuring a pre-existing one)'
    $vocMark  = New-Marker 'ZZVOCW-VOCVAL'
    $dataMark = New-Marker 'ZZVOCW-DATVAL'
    $before = Invoke-SD @("LOGTO $upper", 'CT VOC ZZVOCTEST', 'CT ZZVOCW ZZREC')
    Note 'the VOC record is absent before the write'  $false ($before.Contains($vocMark))
    Note 'the DATA record is absent before the write' $false ($before.Contains($dataMark))

    # -----------------------------------------------------------------------
    Step 6 "The account writes its OWN VOC and the DATA file, over the API, as $Prefix"
    $r = Invoke-ScramProbe "write VOC and DATA as $Prefix" $pw @(
        '--user', $Prefix, '--account', $upper, '--port', "$Port",
        '--write', 'VOC',    'ZZVOCTEST', ('VOC value ' + $vocMark),
        '--write', 'ZZVOCW', 'ZZREC',     ('DATA value ' + $dataMark))
    if (-not (Test-ProbeLine $r '^SCRAM: server signature VERIFIED$')) {
        Refuse 'the probe did not complete a verified login - the writes below would say nothing about the fix.'
    }
    # THE DECISIVE ROWS.  Anchor on the probe's success wording ('WRITTEN' on the
    # positive path), and refuse the failure wording (3018) as a control.
    Note 'VOC write over the API is WRITTEN'  $true (Test-ProbeLine $r '^WRITE VOC ZZVOCTEST: WRITTEN$')
    Note 'DATA write over the API is WRITTEN' $true (Test-ProbeLine $r '^WRITE ZZVOCW ZZREC: WRITTEN$')
    Note 'no write was refused 3018 (ER_RDONLY)' $false (Test-ProbeLine $r 'status 3018')

    # -----------------------------------------------------------------------
    Step 7 'The writes really landed: read both records back on the server'
    $after = Invoke-SD @("LOGTO $upper", 'CT VOC ZZVOCTEST', 'CT ZZVOCW ZZREC')
    ($after -split "`r?`n") | Where-Object { $_ -match 'ZZVOCW-|ZZVOCTEST|ZZREC' } | ForEach-Object { Write-Host ('   | ' + $_) }
    Note 'the VOC record reads back with its content'  $true ($after.Contains($vocMark))
    Note 'the DATA record reads back with its content' $true ($after.Contains($dataMark))
}
finally {
    Step 9 'Putting the system back'
    $removed = @()
    if ($confMoved -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $conf -Force
        Remove-Item -LiteralPath $backup -Force
        $removed += 'APIPORT'
    }
    if ($madeAcct) {
        $null = Invoke-SD @("DELETE.ACCOUNT $upper", 'Y')
        if (-not (Test-Path -LiteralPath (Join-Path $accts $upper))) { $removed += "SD:$upper" }
        else { Write-Host "   $upper IS STILL IN THE REGISTER - DELETE.ACCOUNT did not remove it" -ForegroundColor Red }
        if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) { Remove-LocalUser -Name $Prefix -ErrorAction SilentlyContinue; $removed += "user:$Prefix" }
        $d = Join-Path $env:ProgramData ('SD\user_accounts\' + $Prefix)
        if (Test-Path -LiteralPath $d) { Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue; $removed += "dir:$Prefix" }
        $g = 'sdu_' + $Prefix
        if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $g -ErrorAction SilentlyContinue; $removed += "group:$g" }
    }
    if ($confMoved) { if (Stop-SD) { $null = Start-SD }; $removed += 'SD restarted with the port closed' }
    if ($removed.Count) { Write-Host ('   ' + ($removed -join ', ')) } else { Write-Host '   nothing to put back' }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host
$passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("{0} / {1} checks passed" -f $passed, $results.Count)
try { Stop-Transcript | Out-Null } catch { }
if ($results.Count -eq 0) { Write-Host 'NO CHECK RAN'; exit 2 }
if ($failed) { exit 1 }
exit 0
