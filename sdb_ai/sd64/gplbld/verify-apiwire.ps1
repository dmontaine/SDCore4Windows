<#
.SYNOPSIS
    RELEASE_1.1 41's last witness: WHAT CROSSES THE WIRE ON THE API PORT IS
    CIPHERTEXT.  A packet capture on the port during a real API write must not
    contain the record's content, the account name or the password.

.DESCRIPTION
    Row 41's falsified-if is "a packet capture on 4243 during an API read shows
    the record's content".  verify-apiport and verify-scramlogin both read the
    CLIENT's logical stream (the `wire` line is the plaintext the client handed
    TLS), so they prove SCRAM and the TLS path, not what a third party on the
    wire sees.  This file captures the wire itself with pktmon (ships with
    Windows 10 2004+; full packets with --pkt-size 0) and searches the raw
    capture bytes.

    THE CAPTURE IS PROVED BEFORE IT IS BELIEVED, both directions:

      CONTROL  - before the probe runs, a raw plaintext socket sends a marker
                 to the port.  That marker MUST be found in the capture.  If it
                 is not, pktmon cannot see this traffic (loopback is the
                 suspect) and the run REFUSES (exit 2) - an "absent" row from a
                 capture that saw nothing would be the vacuous pass CLAUDE.md
                 forbids.  -CaptureHost lets the run use the LAN address
                 instead of 127.0.0.1 if that is what it takes.
      LANDED   - after the probe, `CT` in the account must show the secret the
                 probe wrote.  The secret provably crossed the wire; only then
                 does "absent from the capture" mean encrypted.

    DECISIVE ROWS: the secret is absent, the account name is absent, the
    password is absent, and a TLS ClientHello was seen on the port.

    ELEVATED, and it refuses otherwise: pktmon needs it, so does the account
    creation.  APIPORT is added to sd.conf and removed again, SD restarted
    twice; the restore runs in a finally.  NOT SHIPPED - on assert-current's
    $neverShipped.  The .etl and .pcapng stay in SD-verify as evidence; they
    hold the plaintext CONTROL marker and ciphertext, nothing secret.

.PARAMETER Prefix
    Throwaway account name.  Use one nobody has used.

.PARAMETER CaptureHost
    Address the client connects to, default 127.0.0.1.  Pass this machine's
    LAN address if the loopback control refuses.

.PARAMETER Port
    API port, default 4243.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File verify-apiwire.ps1 -Prefix sdwire1
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [string] $CaptureHost = '127.0.0.1',
    [int]    $Port = 4243
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$SvcName = 'SD'
$conf    = Join-Path $env:ProgramData 'SD\sd.conf'
$backup  = $conf + '.before-apiwire'
$accts   = Join-Path $env:ProgramData 'SD\sdsys\accounts'
$pktmon  = Join-Path $env:SystemRoot 'System32\pktmon.exe'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$log   = Join-Path $logDir ('verify-apiwire-' + $stamp + '.log')
$etl   = Join-Path $logDir ('apiwire-' + $stamp + '.etl')
$pcap  = Join-Path $logDir ('apiwire-' + $stamp + '.pcapng')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results      = New-Object System.Collections.ArrayList
$failed       = $false
$observations = @()      # printed with the summary, never scored - see step 7

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}
function Refuse($msg) { Write-Host ''; Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch { }; exit 2 }
function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# Drives an SD session from SDSYS; verify-scramlogin's shape, with the TERM
# re-issued after every LOGTO because LOGIN resets terminal geometry.
function Invoke-SD([string[]]$commands) {
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
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

# pktmon, every call echoed with its output.  Exit codes are not trusted on
# their own: "stop" when nothing runs is an error that does not matter, and
# a "start" that failed says so in text.
function Invoke-Pktmon([string[]]$pmArgs) {
    if ($null -eq $pmArgs -or $pmArgs.Count -eq 0) { Refuse 'Invoke-Pktmon was handed no arguments.' }
    Write-Host ('   pktmon ' + ($pmArgs -join ' '))
    $saved = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $out = & $pktmon @pmArgs 2>&1; $code = $LASTEXITCODE } finally { $ErrorActionPreference = $saved }
    $lines = @($out | ForEach-Object { "$_".TrimEnd("`r") } | Where-Object { $_ -ne '' })
    foreach ($l in $lines) { Write-Host ('   | ' + $l) }
    return [pscustomobject]@{ Code = $code; Text = ($lines -join "`n") }
}

# The probe (verify-scramlogin's client), proved by its own units first.
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

# A random marker of the given shape - upper-case letters and digits only, so
# a byte search cannot be confused by encoding and cannot match by accident.
function New-Marker([string]$tag) {
    $bytes = New-Object byte[] 12
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    return $tag + '-' + (([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '').ToUpper())
}

# ---------------------------------------------------------------------------
if (-not $Prefix) { Refuse 'pass -Prefix, e.g. -Prefix sdwire1.  It names the throwaway account.' }

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Refuse 'Run this from an ELEVATED PowerShell - pktmon and CREATE.ACCOUNT both need it.'
}
if (-not (Test-Path -LiteralPath $pktmon)) { Refuse "$pktmon is not on this machine (Windows 10 2004+ ships it)." }

Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current refuses - run gplbld/cycle.ps1 first.' }

Step '0b' 'Proving the client before using it'
if ((Test-ProbeInstrument) -ne 0) { Refuse 'test-scramprobe-units failed - the client is not trusted, so nothing it says about the wire would be.' }

$upper = $Prefix.ToUpper()
if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) { Refuse "$Prefix already exists as a Windows account.  Use a fresh -Prefix." }
if (Test-Path -LiteralPath (Join-Path $accts $upper))        { Refuse "$upper is still in the ACCOUNTS register.  Use a fresh -Prefix." }

$madeAcct   = $false
$capturing  = $false
$confMoved  = $false
$pw         = ''

try {
    Add-Type -AssemblyName System.Web

    # -----------------------------------------------------------------------
    Step 1 "Creating the throwaway account $Prefix (reach: API)"
    $winPw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $Prefix PROGRAMMER API", $winPw, $winPw)
    if (-not (Test-Path -LiteralPath (Join-Path $accts $upper))) { Write-Host $out; Refuse "CREATE.ACCOUNT did not register $Prefix." }
    $madeAcct = $true
    Write-Host "   $Prefix created"

    # -----------------------------------------------------------------------
    Step 2 'Setting its API password'
    # Alphanumeric, generated, never on a command line (stdin to SD, the
    # environment to the probe) - and searchable in the capture unambiguously.
    $bytes = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + 'aA1'
    $out = Invoke-SD @(("MODIFY.PASSWORD " + $upper), $pw, $pw)
    if ($out -notmatch 'Password set for account') { Write-Host $out; Refuse 'MODIFY.PASSWORD did not report success.' }
    Write-Host '   password set'

    # -----------------------------------------------------------------------
    Step 3 "Creating the files the probe will write to, in $upper"
    # ZZWIRE IS A DIRECTORY FILE, NOT DYNAMIC, and the reason is a finding.
    # The 21:20 runs (15 Sep) made it DYNAMIC and the API session's write was
    # refused 3018 ER_RDONLY: dh_open.c:120 picks read-only from the MSYS2
    # runtime's access(W_OK), which on this noacl mount (msys64/etc/fstab) is a
    # POSIX emulation granting write to the file's OWNER only - and %0 was
    # created by the elevated session, so its owner is not the user, whatever
    # the inherited sdu_ ACE says.  A DIRECTORY-file write is a real CreateFile
    # against the real DACL and works (verify-apiidentity's ZZIDOWN).  The wire
    # witness only needs a known plaintext to cross, so it uses that shape;
    # the DYNAMIC case stays as an OBSERVATION row (step 7), not a verdict.
    $out = Invoke-SD @("LOGTO $upper", 'CREATE.FILE ZZWIRE DIRECTORY NO.QUERY',
                                       'CREATE.FILE ZZWIRED DYNAMIC NO.QUERY')
    if ($out -notmatch 'Created DATA part as zzwire\b')  { Write-Host $out; Refuse 'CREATE.FILE ZZWIRE did not report the DATA part created.' }
    if ($out -notmatch 'Created DATA part as zzwired\b') { Write-Host $out; Refuse 'CREATE.FILE ZZWIRED did not report the DATA part created.' }
    $acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $upper)
    foreach ($p in @('zzwire', 'zzwired\%0', 'voc\%0')) {
        $full = Join-Path $acctDir $p
        $own  = if (Test-Path -LiteralPath $full) { (Get-Acl -LiteralPath $full).Owner } else { '<missing>' }
        Write-Host ("   {0,-12} owner: {1}   (the API session runs as {2})" -f $p, $own, $Prefix)
    }
    Write-Host '   ZZWIRE (DIRECTORY) and ZZWIRED (DYNAMIC) created by the elevated session'

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
    if ($listen.Count -eq 0) { Refuse 'Nothing is listening on the port - there is nothing to capture.' }
    Write-Host "   listener on $Port"

    # -----------------------------------------------------------------------
    Step 5 "Starting the capture: every packet on port $Port, whole packets"
    $null = Invoke-Pktmon @('stop')                  # a leftover capture from a dead run
    $null = Invoke-Pktmon @('filter', 'remove')
    $r = Invoke-Pktmon @('filter', 'add', 'sdwire', '-p', "$Port")
    if ($r.Code -ne 0) { Refuse 'pktmon filter add failed.' }
    $r = Invoke-Pktmon @('start', '--capture', '--pkt-size', '0', '--file-name', $etl)
    # $capturing is set BEFORE the check: the first run (15 Sep 21:17) anchored
    # on 'Log file name:' where pktmon prints 'Log file:', refused, and left
    # the capture running because this flag was still false.  The anchor is
    # now the log line naming OUR file, which only a started capture prints.
    $capturing = ($r.Code -eq 0)
    if (-not $capturing -or $r.Text -notmatch ('Log file:\s+' + [regex]::Escape($etl))) {
        Refuse "pktmon start did not report logging to $etl - the capture is not running as intended."
    }
    $null = Invoke-Pktmon @('status')

    # -----------------------------------------------------------------------
    Step 6 'CONTROL: a plaintext marker sent to the port must be visible to the capture'
    $clear = New-Marker 'ZZWIRE-CLEAR'
    Write-Host "   marker: $clear"
    $tcp = New-Object System.Net.Sockets.TcpClient
    try {
        $tcp.Connect($CaptureHost, $Port)
        $ns = $tcp.GetStream()
        $b  = [Text.Encoding]::ASCII.GetBytes($clear + "`n")
        $ns.Write($b, 0, $b.Length); $ns.Flush()
        Start-Sleep -Milliseconds 500
    } finally { $tcp.Close() }
    Write-Host "   sent $($clear.Length + 1) plaintext byte(s) to ${CaptureHost}:$Port (the server will drop the connection - it is not a TLS ClientHello)"

    # -----------------------------------------------------------------------
    Step 7 'The real thing: log in over TLS and write a record whose content must not show'
    $secret = New-Marker 'ZZWIRE-SECRET'
    $obsDyn = New-Marker 'ZZWIRE-OBSDYN'
    $obsVoc = New-Marker 'ZZWIRE-OBSVOC'
    Write-Host "   secret : $secret  (written over the API into ZZWIRE ZZREC - the decisive write)"
    Write-Host "   also   : $obsDyn -> ZZWIRED ZZREC (DYNAMIC, elevated-created) and $obsVoc -> VOC ZZWIRETEST (the account's own VOC) - OBSERVED ONLY"
    $r = Invoke-ScramProbe 'login, attach, write the secret (and the two observation writes)' $pw @(
        '--user', $Prefix, '--account', $upper, '--host', $CaptureHost, '--port', "$Port",
        '--write', 'ZZWIRE',  'ZZREC',      ('the secret is ' + $secret + ' and nothing else'),
        '--write', 'ZZWIRED', 'ZZREC',      ('observation ' + $obsDyn),
        '--write', 'VOC',     'ZZWIRETEST', ('observation ' + $obsVoc))
    $verified = Test-ProbeLine $r '^SCRAM: server signature VERIFIED$'
    $written  = Test-ProbeLine $r '^WRITE ZZWIRE ZZREC: WRITTEN$'
    if ($r.Code -ne 0 -or -not $verified -or -not $written) {
        Refuse 'The probe did not complete a verified login and a WRITTEN record - there is no known plaintext to look for.'
    }
    # OBSERVATIONS, printed and carried to the summary but NOT scored: they
    # measure a different claim (can the account's user write files the
    # administrator made, and its own VOC, over the API) and belong to the
    # finding this file's step 3 comment describes, not to row 41.
    foreach ($o in @(@('ZZWIRED ZZREC', 'a DYNAMIC file the elevated session created'),
                     @('VOC ZZWIRETEST', "the account's own VOC"))) {
        $line = $r.Lines | Where-Object { $_ -cmatch ('^WRITE ' + [regex]::Escape($o[0]) + ': ') } | Select-Object -First 1
        if (-not $line) { $line = '<no WRITE line for ' + $o[0] + '>' }
        $script:observations += ('write to ' + $o[1] + ' -> ' + $line)
        Write-Host ('  [OBSERVED] ' + $o[1] + ': ' + $line)
    }
    Start-Sleep -Seconds 1

    # -----------------------------------------------------------------------
    Step 8 'Stopping the capture and converting it'
    $null = Invoke-Pktmon @('stop')
    $capturing = $false
    $null = Invoke-Pktmon @('filter', 'remove')
    if (-not (Test-Path -LiteralPath $etl)) { Refuse "pktmon left no $etl." }
    $r = Invoke-Pktmon @('etl2pcap', $etl, '--out', $pcap)
    if (-not (Test-Path -LiteralPath $pcap)) { Refuse 'etl2pcap produced no pcapng.' }
    $null = Invoke-Pktmon @('etl2txt', $etl, '--stats')
    $raw = [Text.Encoding]::GetEncoding('iso-8859-1').GetString([IO.File]::ReadAllBytes($pcap))
    Write-Host ("   capture: {0} bytes in {1}" -f $raw.Length, $pcap)

    # -----------------------------------------------------------------------
    Step 9 'Reading the capture'
    # The control decides whether anything below may be believed.
    $sawClear = $raw.Contains($clear)
    Note 'CONTROL: the plaintext marker is in the capture' $true $sawClear
    if (-not $sawClear) {
        # MEASURED 15 Sep 2026 (runs 2-4): on this box pktmon logs only DROP
        # events on a loopback connection (header-only RSTs, Packets total 0),
        # never the flow packets that carry payload - Windows loopback does not
        # traverse a filterable NDIS component.  A same-host LAN address
        # (192.168.0.2) is still loopback, so -CaptureHost does not help; the
        # traffic has to cross a real NIC, i.e. the peer must be another
        # machine (drive the probe from the Linux box to this server while this
        # capture runs).  Refusing is correct - an "absent" verdict from a
        # capture that saw no payload would be the vacuous pass CLAUDE.md forbids.
        Refuse ("pktmon saw no payload for ${CaptureHost}:$Port (loopback yields only drop events on this box). " +
                'A real capture needs a remote peer so the packets cross a NIC - run the probe from another machine.')
    }
    # TLS record header: content type 22 (handshake), version 3.1 or 3.3, two
    # length bytes, then handshake type 1 (ClientHello).
    Note 'a TLS ClientHello was seen on the port' $true ($raw -cmatch '\x16\x03[\x01\x03][\s\S]{2}\x01')

    Note 'the secret written over the API is ABSENT from the capture' $false ($raw.Contains($secret))
    Note 'the account name is ABSENT from the capture' $false ($raw.Contains($Prefix) -or $raw.Contains($upper))
    Note 'the password is ABSENT from the capture'    $false ($raw.Contains($pw))

    # -----------------------------------------------------------------------
    Step 10 'The secret really reached the server (else "absent" is vacuous)'
    $out = Invoke-SD @("LOGTO $upper", 'CT ZZWIRE ZZREC')
    ($out -split "`r?`n") | Where-Object { $_ -match 'ZZREC|ZZWIRE-SECRET' } | ForEach-Object { Write-Host ('   | ' + $_) }
    Note 'CT ZZWIRE ZZREC shows the secret on the server' $true ($out.Contains($secret))
    # A DIRECTORY-file record is a plain file: the same fact read a second way,
    # with nothing of SD's in the path, and its owner says who wrote it.
    $recFile = Join-Path $acctDir 'zzwire\ZZREC'
    if (Test-Path -LiteralPath $recFile) {
        $onDisk = [IO.File]::ReadAllText($recFile)
        Write-Host ("   on disk: {0} ({1} bytes, owner {2})" -f $recFile, $onDisk.Length, (Get-Acl -LiteralPath $recFile).Owner)
        Note 'the record file on disk holds the secret' $true ($onDisk.Contains($secret))
    } else {
        Note 'the record file exists on disk' $true $false
    }
}
finally {
    if ($capturing) {
        $null = Invoke-Pktmon @('stop')
        $null = Invoke-Pktmon @('filter', 'remove')
    }

    Step 11 'Putting the system back'
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
    $kept = @($etl, $pcap) | Where-Object { Test-Path -LiteralPath $_ }
    if ($kept.Count) { Write-Host ('   evidence kept: ' + ($kept -join ', ')) }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host
$passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("{0} / {1} checks passed" -f $passed, $results.Count)
if ($observations.Count) {
    Write-Host ''
    Write-Host 'Observed, not scored (a separate claim - see step 3 and step 7 comments):'
    foreach ($o in $observations) { Write-Host ('  ' + $o) }
}
try { Stop-Transcript | Out-Null } catch { }
if ($results.Count -eq 0) { Write-Host 'NO CHECK RAN'; exit 2 }
if ($failed) { exit 1 }
exit 0
