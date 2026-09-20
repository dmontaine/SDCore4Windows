<#
.SYNOPSIS
    Speak the SCRAM exchange at the API port directly and check what the
    server does with it.  docs/SCRAM_AUTH.md phases 3 and 5.

.DESCRIPTION
    ONE ELEVATED COMMAND for request types 47 and 48.  It is the only thing
    that exercises vb.scram.first and vb.scram.final's refusals; until it
    passes they are written and unproven.

    THE CLIENT IS NOT sdclilib, and that is the point.  A test that went
    through the client library would be the library agreeing with itself.

    15 Sep 26 - RELEASE_1.1 42.  THE CLIENT IS NOW gplbld/scram-probe.py, NOT
    .NET CODE IN THIS FILE.  RELEASE_1.1 41 made every API connection TLS 1.3
    with the login bound to it (RFC 9266 tls-exporter), and .NET's SslStream
    cannot export that binding, so the TcpClient this file carried could no
    longer reach the server at all.  The probe is SCRAM from Python's standard
    library over libssl by ctypes, with no SD code in it - still a second
    implementation against the same RFC.  Each refusal below is one probe run
    in a mode that makes the message wrong in exactly one way, and every run's
    command line and full output is printed.  The Linux port split its
    verifiers the same way (mailbox 15 Sep 12:15): positives over TLS, the raw
    plaintext socket kept only as a refusal control.

    IT CHANGES THE INSTALLED SYSTEM AND PUTS IT BACK, exactly as
    verify-apiport.ps1 does and for the same reasons: a throwaway account,
    APIPORT added to the installed sd.conf and removed again, SD restarted
    twice.  The restore runs in a finally block.

    WHAT IT IS TRYING TO CATCH.  A login path that says "yes" is easy; the
    checks that matter are the ones that must say "no", and the two controls:

      - the password does not appear in the bytes sent (and the SAME test
        finds it in a request 24 login, so the test can detect one)
      - two exchanges for one account get different server nonces
      - a captured client-final replayed against a fresh exchange is refused
      - a client-final with no client-first before it is refused
      - a client-final carrying the wrong channel binding is refused, and so
        is an unbound 'n,,' header over TLS (41's downgrade)
      - a connection that does not start TLS gets no ACK
      - every refusal carries the message the handler meant to send, not
        merely a non-zero status
      - request 24 is REFUSED, and says why.

.PARAMETER Prefix
    Name for the throwaway Windows and SD account.  Use one nobody has used -
    CREATE.ACCOUNT refuses a name it has seen, which is the right way round.

.PARAMETER Port
    Loopback port to use.  4243 is the number the Linux build uses.

.PARAMETER Keep
    Leave APIPORT set and the account in place when the run finishes, for
    poking at by hand.  The account still has to be removed with
    DELETE.ACCOUNT afterwards.

.PARAMETER SelfTest
    The client alone, no server: runs test-scramprobe-units.py, which checks
    the probe's SCRAM against the RFC 7677 vector and its packets byte for byte.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-scramlogin.ps1 -Prefix sdscram1
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# 03 Sep 26 - THAT SENTENCE IS NEW HERE, AND THE THIRD CODE HAD NEVER BEEN
# USED.  PRE_RELEASE_FIXES.md 151.  Twelve other verifiers state this
# convention in their own headers; the six API ones stated nothing and left
# every precondition refusal through Fail() at exit 1 - which in a suite
# summary is indistinguishable from a check that ran and failed.  See Refuse().

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [int]    $Port = 4243,
    [switch] $Keep,
    [switch] $SelfTest
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$SvcName = 'SD'
$conf    = Join-Path $env:ProgramData 'SD\sd.conf'
$backup  = $conf + '.before-scramlogin'

# SCRAM$ITERATIONS in gpl.bp/int$keys.h.  Asserted rather than read, so a
# change to the cost has to be made deliberately in both places.
$ExpectedIterations = 600000

# NOT UNDER C:\ProgramData\SD - the tree the cycle deletes.  LOCALAPPDATA is
# the same directory elevated or not, so an unelevated session can read it.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-scramlogin-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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

function Fail($msg) {
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

# 03 Sep 26 - PRE_RELEASE_FIXES.md 151.  A PRECONDITION REFUSAL IS NOT A FAILED
# CHECK, and until now both left through Fail() at exit 1.  Run b106 showed six
# API verifiers "exit 1" in a block, which reads as "the API is broken" - and
# NOT ONE OF THEM HAD MEASURED ANYTHING.  All six had refused on
# assert-current because a source file was written while the run was in flight.
#
# IT DOWNGRADES TO 1 IF A DECISIVE CHECK HAS ALREADY FAILED, and that is the
# half that is easy to get wrong.  Several stop-sites below sit immediately
# after a Note() that has already recorded a [FAIL] - there the fixture step IS
# a decisive check - and exiting 2 there would file a real failure under "could
# not run", which is the more dangerous direction of the two.  Step 5's
# server-first is exactly that case.  So the helper asks the run's own state
# rather than trusting the call site to be a precondition.
function Refuse($msg) {
    if ($script:failed) {
        Fail ($msg + '  (a decisive check had already FAILED, so this is exit 1, not 2)')
    }
    Write-Host ''
    Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# The text the server will have sent for sysmsg(N), read from the INSTALLED
# tree.
#
# WHY THE MESSAGE AND NOT JUST "SERVER.ERROR WAS NON-ZERO".  A refusal that
# lands on the wrong branch refuses just as firmly and reads identically from
# outside, so "it said no" cannot tell a nonce mismatch from a bad password
# from an unopenable $cred.  Naming the message is what makes each refusal a
# statement about WHICH check fired.
#
# Reading the installed file rather than hard-coding the words is deliberate:
# assert-current has already established the install matches source, so this
# is source's text, and a handler that quoted the wrong number still fails.
function Get-SysMsg([int]$n) {
    $f = Join-Path $env:ProgramData ('SD\sdsys\messages\' + $n)
    if (-not (Test-Path -LiteralPath $f)) { return "<message $n is not installed>" }
    return ((Get-Content -LiteralPath $f -Raw)).Trim()
}

# Drives an SD session from SDSYS.  Same shape as verify-apiport.ps1: a blank
# first line absorbs the BOM, TERM stops it paginating, OFF ends it.
# 20 Sep 26 - RELEASE_1.1 76, THE SDSYS SEAT (sdsys-seat.ps1; verify-createaccount
# was the pilot, witnessed 18/18 on 19 Sep).  THE "LOGTO SDSYS" PREFIX THIS USED
# TO SEND IS REFUSED (10002) FROM ANY SESSION THAT DID NOT START AS THE OS SDSYS
# ACCOUNT with an elevated, interactive token, and an elevated Don is not one.  So
# the commands go to a task inside SDSYS's own live session and the text comes back
# through a file.  The TERM handling this function carried - first line, and again
# after every LOGTO, because LOGIN resets the terminal geometry on each account
# switch (LOGIN:201-209) - lives in the helper now (Expand-SeatCommands) with its
# own guard.  A seat that did not run THROWS rather than returning '' (see
# Invoke-SdSeatText).  SDSYS must be signed in: `query session` shows its row.
#
# THE TIMEOUT IS 300 s, NOT 180 LIKE THE OTHERS: one call below compiles and RUNS a
# BASIC client (BASIC BP TESTSDCLI, RUN BP TESTSDCLI) that connects to the API, and
# the in-process pipe this replaces was unbounded, so a bound has to be generous
# enough not to turn a slow connect into a false failure.
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
function Invoke-SD([string[]]$commands) {
    return (Invoke-SdSeatText -Commands $commands -TimeoutSec 300)
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

# ===========================================================================
# THE CLIENT: gplbld/scram-probe.py.  15 Sep 26 - RELEASE_1.1 42.
#
# The wire format, the SCRAM arithmetic and the TLS session are all in the
# probe; its header documents each mode and the one verdict line each prints.
# What stays here is running it so that the result can be disagreed with:
# the exact command line, the password's LENGTH (never the password - it goes
# in the environment, which does not reach the process list), every line the
# probe printed, and its exit code.  CLAUDE.md's instrument rule.
#
# EVERY MATCH BELOW IS CASE-SENSITIVE AND ANCHORED ON A WHOLE LINE the probe
# prints only on that path.  The probe echoes its own arguments, so a loose
# match on a name or a mode would find the echo - the verify-apiidentity
# Step 3 trap.
# ===========================================================================

$Probe      = Join-Path $Gplbld 'scram-probe.py'
$ProbeUnits = Join-Path $Gplbld 'test-scramprobe-units.py'
$Python     = $null

# Resolves the python the probe runs under, then runs the probe's own unit
# test with it: the RFC 7677 vector, libssl loading, and the request packets
# byte for byte.  THE INSTRUMENT IS PROVED BEFORE IT IS BELIEVED - if these
# come out wrong, nothing this script says about the server means anything.
# Returns the unit test's exit code.
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
    try {
        $u  = & $script:Python $ProbeUnits 2>&1
        $uc = $LASTEXITCODE
    } finally { $ErrorActionPreference = $saved }
    foreach ($l in @($u)) { Write-Host ('   | ' + ("$l".TrimEnd("`r"))) }
    Write-Host "   test-scramprobe-units exit $uc"
    return $uc
}

# One probe run.  $probeArgs, NOT $args - that is PowerShell's automatic
# variable, and a parameter of that name reaches the call empty (CLAUDE.md,
# 23 Aug 2026).  An empty list is refused rather than run.
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
    try {
        $raw  = & $script:Python $Probe @probeArgs 2>&1
        $code = $LASTEXITCODE
    } finally {
        Remove-Item -Path 'Env:SD_SCRAM_PASSWORD' -ErrorAction SilentlyContinue
        $ErrorActionPreference = $saved
    }
    $lines = @($raw | ForEach-Object { "$_".TrimEnd("`r") })
    foreach ($l in $lines) { Write-Host ('   | ' + $l) }
    Write-Host "   probe exit $code"
    return [pscustomobject]@{ Label = $label; Code = $code; Lines = $lines }
}

# The first group of the first line matching $pattern, case-sensitively;
# $null if no line matches.
function Get-ProbeMatch($r, [string]$pattern) {
    foreach ($l in $r.Lines) {
        if ($l -cmatch $pattern) { return $Matches[1] }
    }
    return $null
}

# The wire line's verdict: 'absent from', 'FOUND IN' or 'NOT CHECKED'.
function Get-ProbeWire($r) {
    $w = Get-ProbeMatch $r '^  wire     : password (absent from|FOUND IN|NOT CHECKED)'
    if ($null -eq $w) { return '<no wire line>' }
    return $w
}

# A login the server must refuse at $request with sysmsg($msg).  Two rows, as
# before 42: that it refused, and that the refusal is the one the handler
# meant.  $pattern's group is the server's text; the default is the probe's
# ordinary refusal line.
function Assert-Refusal($r, [string]$what, [int]$request, [int]$msg, [string]$pattern = '') {
    if ($pattern -eq '') { $pattern = '^SCRAM: login REFUSED at request ' + $request + ': (.*)$' }
    $t = Get-ProbeMatch $r $pattern
    Note "$what refused at request $request" $true (($r.Code -eq 1) -and ($null -ne $t))
    if ($null -eq $t) { $t = "<the probe printed no refusal at request $request>" }
    Note "  and it is $msg" (Get-SysMsg $msg) $t.Trim()
}

# ---------------------------------------------------------------------------
# -SelfTest: the client alone, against the published vector and its own
# packet layouts.  NO ELEVATION, NO SERVER, NO INSTALL - so it can be run at
# any time, including while a cycle is owed, and it is the first thing to run
# when the exchange fails and it is not obvious which side is wrong.
if ($SelfTest) {
    Step 0 'test-scramprobe-units.py - the client only, no server involved'
    Note 'test-scramprobe-units exits 0' 0 (Test-ProbeInstrument)

    Write-Host ''
    Write-Host '=== Summary ============================================================='
    $results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host
    $passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
    Write-Host ("{0} / {1} checks passed" -f $passed, $results.Count)
    try { Stop-Transcript | Out-Null } catch { }
    if ($failed) { exit 1 }
    exit 0
}

if (-not $Prefix) {
    Refuse 'Give -Prefix a name nobody has used, or run with -SelfTest for the offline vector check.'
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Refuse 'Run this from an ELEVATED PowerShell - it creates an account, edits the installed sd.conf and restarts SD.'
}

# THE CYCLE RULE, and it is a gate rather than a reminder.  CLAUDE.md: anything
# that tests the install calls this first, or the result describes a tree that
# no longer exists.
Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current refuses - run gplbld/cycle.ps1 first.' }

# BEFORE ANY ACCOUNT IS MADE: a probe that cannot run would otherwise be
# discovered after the system had been changed, and every row below would be
# a statement about python rather than about the server.
Step '0b' 'Proving the client before using it'
if ((Test-ProbeInstrument) -ne 0) {
    Refuse 'test-scramprobe-units did not pass - the probe cannot be trusted, so nothing it reports about the server would mean anything.'
}

if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
    Refuse "$Prefix already exists as a Windows account.  Use a -Prefix that does not."
}
if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper()))) {
    Refuse ($Prefix.ToUpper() + " is still in the ACCOUNTS register from an earlier run." +
          "  Remove it with DELETE.ACCOUNT, or use a fresh -Prefix.")
}

$restoreNeeded = $false
$pw = ''

# $cred is moved aside for one check and put straight back; these two let the
# outer finally have a second go if the inner one could not.  A run that ended
# with the credential store renamed would refuse every login on the machine.
$credDir   = Join-Path $env:ProgramData 'SD\sdsys\$cred'
$credAside = $credDir + '.moved-for-5274'
$movedCred = $false

# TESTSDCLI IS DROPPED INTO PLACE FOR STEP 9b AND REMOVED IN FINALLY.  Init
# here so the finally can rely on it even if we fail before step 9b.  See
# the copy at step 9b for the reasoning.
$installedTestSdcli = Join-Path $env:ProgramData 'SD\sdsys\bp\TESTSDCLI'
$droppedTestSdcli   = $false

try {
    # -----------------------------------------------------------------------
    Step 1 "Creating the throwaway account $Prefix"

    # NO NO.QUERY: CREATE.ACCOUNT USER creates a Windows account too and
    # refuses outright without a prompt.  Two passwords, deliberately not the
    # same thing - $winPw is Windows', $pw is the SD credential and the only
    # one this test ever uses.  verify-apiport.ps1 has the long version.
    Add-Type -AssemblyName System.Web
    # 20 Sep 26 - RELEASE_1.1 83: SD's pw_complex (RELEASE_1.1 75) needs lower, upper,
    # digit AND symbol, and a bare GeneratePassword(24, 6) lacks a digit 5.7 % of the
    # time (measured, 20,000 samples) - SD then re-prompts, eats the next piped line
    # and spins at EOF: the run HANGS.  'aA1!' guarantees all four classes.
    $winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6) + 'aA1!'

    # 19 Sep 26 - RELEASE_1.1 64: PROGRAMMER is REFUSED at create time now
    # (createa's keyword case, sysmsg 2018 - the whole command stops and no
    # account is made), so the access keyword is the whole of the line.
    # 20 Sep 26 - RELEASE_1.1 76: PROVE THE SDSYS SEAT BEFORE CREATING ANYTHING, so a
    # missing SDSYS session is exit 2 ("could not run") and not a thrown error at the
    # first SD call that reads as a product failure.  See sdsys-seat.ps1.
    Assert-SdSeat -Label 'verify-scramlogin'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $Prefix API", $winPw, $winPw)
    $accRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper())
    $made = Test-Path -LiteralPath $accRec
    Note 'accounts record created' $true $made
    if (-not $made) { Write-Host $out; Refuse 'CREATE.ACCOUNT did not register the account.' }
    $restoreNeeded = $true

    # -----------------------------------------------------------------------
    Step 2 'Setting its password'

    # GENERATED, NEVER HARDCODED, AND NEVER ON A COMMAND LINE - it goes to SD
    # on stdin.  Alphanumeric so it cannot be confused by any quoting on the
    # way, and so the "is it on the wire" search is unambiguous.
    $bytes = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    # 20 Sep 26 - RELEASE_1.1 83: base64 alphanumerics + 'aA1' has NO SYMBOL, which SD's
    # pw_complex (RELEASE_1.1 75) refuses EVERY time - MODIFY.PASSWORD re-prompts, eats
    # the next piped line and spins at EOF: the run HANGS.  '-' is the one symbol safe
    # through bash -lc, cmd and the askpass helper, and it is not first.
    $pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + '-aA1'

    $out = Invoke-SD @(("MODIFY.PASSWORD " + $Prefix.ToUpper()), $pw, $pw)
    $set = ($out -match 'Password set for account')
    Note 'password set' $true $set
    if (-not $set) { Write-Host $out; Refuse 'MODIFY.PASSWORD did not report success.' }

    # THE CREDENTIAL IS VERSION 2, checked before anything tries to use it.  A
    # version 1 record would make every check below fail for a reason that has
    # nothing to do with the exchange.
    $credRec = Join-Path $env:ProgramData ('SD\sdsys\$cred\' + $Prefix.ToUpper())
    if (Test-Path -LiteralPath $credRec) {
        # READ IT AS BYTES, NOT AS TEXT.  Whether a field mark reaches the disk
        # as 0xFE or as a newline is a property of the file type, not something
        # this check should depend on - and 0xFE alone is not valid UTF-8, so a
        # text read would turn it into a replacement character.  Latin-1 maps
        # every byte to itself, which is all that is wanted here.
        $raw = [Text.Encoding]::GetEncoding('iso-8859-1').GetString(
                   [IO.File]::ReadAllBytes($credRec))
        $credVer = ($raw -split '\r?\n|\xFE')[0].Trim()
        Note '$cred record is version 2' '2' $credVer
    } else {
        Note '$cred record exists' $true $false
    }

    # -----------------------------------------------------------------------
    Step 3 "Enabling APIPORT=$Port in the installed sd.conf"

    Copy-Item -LiteralPath $conf -Destination $backup -Force
    $lines = @(Get-Content -LiteralPath $conf) | Where-Object { $_ -notmatch '^\s*APIPORT\s*=' }
    $lines += ('APIPORT=' + $Port)
    Set-Content -LiteralPath $conf -Value $lines -Encoding Ascii

    # -----------------------------------------------------------------------
    Step 4 'Restarting SD so read_config() runs'

    # IT HAS TO BE A RESTART, not a reload.  read_config() runs only when the
    # shared segment is CREATED (sysseg.c), so a running system never sees it.
    if (-not (Stop-SD))  { Refuse 'SD would not stop - close any open session and try again.' }
    if (-not (Start-SD)) { Refuse 'SD would not start again.  Read the SD error log.' }
    Start-Sleep -Seconds 2

    $listen = @(netstat -an | Select-String 'LISTENING' |
                Where-Object { $_ -match (':' + $Port + '\s') })
    Note 'a listener on the port' $true ($listen.Count -gt 0)
    if ($listen.Count -eq 0) { Refuse 'Nothing is listening - the rest of this script has nothing to talk to.' }

    $upper = $Prefix.ToUpper()
    $at    = @('--user', $Prefix, '--port', "$Port")

    # -----------------------------------------------------------------------
    Step 5 'The exchange, end to end, over TLS'

    $r5 = Invoke-ScramProbe 'a correct login, then the account' $pw ($at + @('--account', $upper))

    $cNonce = Get-ProbeMatch $r5 '^  client-first: p=tls-exporter,,n=[^,]*,r=([^,]+)$'
    $sFirst = Get-ProbeMatch $r5 '^  server-first: (r=[^,]+,s=[^,]+,i=\d+)$'
    Note '47 sent with the bound header, and accepted' $true (($null -ne $cNonce) -and ($null -ne $sFirst))
    if ($null -eq $sFirst) { Refuse 'Without a server-first there is nothing further to check.' }

    $sParts = $sFirst -split ','
    $sNonce = $sParts[0].Substring(2)

    # THE CLIENT-SIDE CHECK THE DESIGN NAMES, made HERE from the two lines the
    # probe printed rather than taken from the probe's own refusal to go on.
    # A combined nonce that does not start with the nonce we sent is a reply
    # to somebody else's exchange.
    Note 'combined nonce extends ours'   $true ($null -ne $cNonce -and $sNonce.StartsWith($cNonce))
    Note 'server added nonce of its own' $true ($null -ne $cNonce -and $sNonce.Length -gt $cNonce.Length)
    Note 'iterations'                    $ExpectedIterations ([int]$sParts[2].Substring(2))

    # MUTUAL AUTHENTICATION, AND IT IS THE HALF EASIEST TO LET SLIDE.  The
    # probe computes the signature from ServerKey and compares it; VERIFIED is
    # printed only when they agree, and MISMATCH exits 3.
    Note '48 accepted and the server signature verifies' $true (
        ($r5.Code -eq 0) -and ($null -ne (Get-ProbeMatch $r5 '^(SCRAM: server signature VERIFIED)$')))

    # NOT JUST "48 RETURNED 0".  logged.in has to have been set, and the
    # only way to see that from outside is to issue a request the main loop
    # refuses to an unauthenticated session - the probe's request 3.
    Note 'session is authenticated (request 3 entered the account)' $true (
        $null -ne (Get-ProbeMatch $r5 ('^(account ' + [regex]::Escape($upper) + ': entered)$')))

    # THE CENTRAL CLAIM, MEASURED.  The probe searched every plaintext byte it
    # handed to TLS.  The control is in step 9.
    Note 'password absent from the bytes sent' 'absent from' (Get-ProbeWire $r5)

    # -----------------------------------------------------------------------
    Step 6 'Freshness: a second exchange for the same account'

    $r6 = Invoke-ScramProbe 'a second login for the same account' $pw $at
    $s6 = Get-ProbeMatch $r6 '^  server-first: r=([^,]+),s=[^,]+,i=\d+$'
    Note '47 accepted again' $true ($null -ne $s6)
    # If this ever fails, the server nonce is not random and every replay
    # defence below is decoration.
    Note 'server nonce differs from the first exchange' $true (($null -ne $s6) -and ($s6 -ne $sNonce))

    # -----------------------------------------------------------------------
    Step 7 'The refusals'

    # Each is its own probe run on its own connection: a refused exchange sets
    # done and the server drops the link, which is itself part of the
    # behaviour.  Each message is wrong in EXACTLY ONE WAY.

    # Wrong password.  Everything else about the message is correct, so this
    # isolates the proof.
    $r = Invoke-ScramProbe 'wrong password' ($pw + 'x') $at
    Assert-Refusal $r 'wrong password' 48 5017

    # Replay.  A client-final captured from an exchange that SUCCEEDED, sent
    # against a fresh client-first on a new connection.  The probe rewrites
    # c= to the new connection's binding, so the nonce - which belongs to an
    # exchange that no longer exists - is the only stale part.
    #
    # 5272, not 5017: the proof is never reached.  A stale nonce is a bad
    # MESSAGE, and if this ever reads 5017 the server has run a signature
    # check against an exchange that had already been closed.
    $r = Invoke-ScramProbe 'replay a captured client-final' $pw ($at + @('--replay'))
    Assert-Refusal $r 'replayed client-final' 48 5272 '^REPLAY: the captured client-final was REFUSED at request 48: (.*)$'

    # A client-final answering a nonce nobody issued.
    $r = Invoke-ScramProbe 'tampered nonce' $pw ($at + @('--tamper-nonce'))
    Assert-Refusal $r 'tampered nonce' 48 5272

    # 15 Sep 26 - RELEASE_1.1 42.  THE BINDING, the check 41 added.  The
    # correct nonce and a proof computed over what was sent, but c= carries
    # this session's binding with one bit flipped: a login relayed by a man in
    # the middle, who holds a different TLS session and so a different binding.
    $r = Invoke-ScramProbe 'client-final with the wrong channel binding' $pw ($at + @('--bad-cbind'))
    Assert-Refusal $r 'wrong channel binding' 48 5272

    # 48 with no 47 before it.  This is the one that would pass silently if the
    # handler compared against empty values instead of refusing.
    # 5273 and not 5272: the sequence is what is wrong, not the message.
    $r = Invoke-ScramProbe 'client-final without client-first' $pw ($at + @('--final-only'))
    Assert-Refusal $r 'client-final without client-first' 48 5273

    # An account that does not exist.
    # THE SAME WORDS AS A WRONG PASSWORD, which is the point - the reply
    # must not distinguish an account that exists from one that does not.
    # The round trip still does; docs/SCRAM_AUTH.md, "Still open".
    $r = Invoke-ScramProbe 'unknown account' $pw @('--user', ($Prefix + 'nosuch'), '--port', "$Port")
    Assert-Refusal $r 'unknown account' 47 5017

    # The downgrade signal.  'y,,' says "the server does not support channel
    # binding"; accepting it would let a man in the middle strip a binding.
    $r = Invoke-ScramProbe "the 'y,,' downgrade header" $pw ($at + @('--gs2', 'y,,'))
    Assert-Refusal $r "'y,,' downgrade" 47 5272

    # 15 Sep 26 - RELEASE_1.1 42.  'n,,' OVER TLS: the header that was correct
    # before 41 is now a downgrade, because the transport has a binding to
    # offer.  apisrvr picks the header from the transport, not the client.
    $r = Invoke-ScramProbe "the unbound 'n,,' header over TLS" $pw ($at + @('--no-binding'))
    Assert-Refusal $r "unbound 'n,,' over TLS" 47 5272

    # A mandatory extension the server does not understand.  RFC 5802 requires
    # a failure, not a shrug.
    $r = Invoke-ScramProbe 'an m= mandatory extension' $pw ($at + @('--gs2', 'p=tls-exporter,,m=whatever,'))
    Assert-Refusal $r 'm= mandatory extension' 47 5272

    # 15 Sep 26 - RELEASE_1.1 42.  THE TRANSPORT REFUSAL, and the one row where
    # the raw socket survives: a client that does not start TLS must never be
    # spoken to in clear.  The relay waits out its handshake deadline
    # (SD_TLS_HANDSHAKE_MS) and closes without the ACK.
    $r = Invoke-ScramProbe 'a plaintext connection' $pw ($at + @('--no-tls'))
    Note 'a plaintext connection gets no ACK' $true (
        ($r.Code -eq 1) -and ($null -ne (Get-ProbeMatch $r '^(PLAINTEXT: no ACK) - connection closed')))

    # -----------------------------------------------------------------------
    Step '7b' 'The server-fault path: an unopenable $cred is 5274, not 5017'

    # THE ONE REFUSAL THAT IS NOT A SECURITY ANSWER, and the last one in the
    # handler that nothing had ever exercised.  A primitive that fails or a
    # credential store that will not open is a fault in this server; saying so
    # tells an attacker only that SDEXT or the file is broken, which no
    # credential depends on.  Reporting it as "invalid username or password"
    # instead would send an administrator hunting a password that is correct.
    #
    # IT IS MEASURED BY BREAKING THE SERVER ON PURPOSE, briefly.  $cred is
    # renamed, one client-first is sent, and it is renamed back in a finally -
    # and again in the outer finally if that failed.  APISRVR opens $cred per
    # request and closes it again, and each connection is its own process, so
    # nothing holds a handle across the rename.
    try {
        Rename-Item -LiteralPath $credDir -NewName (Split-Path -Leaf $credAside) -ErrorAction Stop
        $movedCred = $true
    } catch {
        Write-Host ('   could not move $cred aside: ' + $_.Exception.Message) -ForegroundColor Yellow
        Write-Host '   5274 stays unexercised for this run - say so rather than assuming it.' -ForegroundColor Yellow
    }

    if ($movedCred) {
        try {
            $r = Invoke-ScramProbe 'a login while $cred cannot be opened' $pw $at
            Assert-Refusal $r 'unopenable $cred' 47 5274
        } finally {
            try {
                Rename-Item -LiteralPath $credAside -NewName (Split-Path -Leaf $credDir) -ErrorAction Stop
                $movedCred = $false
                Write-Host '   $cred put back'
            } catch {
                Write-Host ('   COULD NOT PUT $cred BACK: ' + $_.Exception.Message) -ForegroundColor Red
            }
        }
    }

    # -----------------------------------------------------------------------
    Step 8 'Phase 5: request 24 is retired, and refuses'

    # THE CREDENTIALS ARE CORRECT.  That is what makes this a test of the
    # retirement rather than of the password: the old path is refused for a
    # login that would have succeeded before phase 5.
    #
    # AND IT IS 5275, NOT 5017 OR 5270.  A retired request that answered
    # "invalid username or password" would send everyone looking for a
    # credential fault; "not logged in" would read as a client bug.
    $r8 = Invoke-ScramProbe 'request 24, the retired cleartext login' $pw ($at + @('--legacy'))
    Assert-Refusal $r8 'request 24' 24 5275 '^LEGACY: login REFUSED at request 24: (.*)$'

    # -----------------------------------------------------------------------
    Step 9 'The control for the wire check'

    # WITHOUT THIS, "the password is not in the bytes" MEANS NOTHING - a
    # search that can never find anything passes just as well.  Request 24
    # carries the password in clear, and the same search finds it.
    #
    # STILL VALID AFTER PHASE 5, and worth being clear why: the probe searches
    # what IT sent, not what the server accepted.  The packet above still puts
    # the password in the stream; the server throws it away instead of reading
    # it.  So the control measures the detector, as it always did.
    Note 'same search finds the password in a request 24 login' 'FOUND IN' (Get-ProbeWire $r8)

    # -----------------------------------------------------------------------
    Step '9b' 'The OTHER client: the !sdclient class module'

    # SDCLIENT IS THE THIRD THING THAT SPEAKS THIS PROTOCOL, and it is the one
    # nothing had ever tested.  sdclilib.dll is the client for applications
    # outside SD; !sdclient is the client for BASIC programs inside it, and it
    # sent the cleartext request 24 until phase 5 gave it a SCRAM exchange.
    # Retiring 24 without changing it would have broken it silently - it has no
    # test of its own and no caller in this tree to notice.
    #
    # EVERYTHING ABOVE SPEAKS SCRAM FROM THE PROBE.  This step is the only one
    # that exercises the BASIC implementation - which since 41 opens the socket
    # with SKT$TLS and binds its login too - and it runs against the same
    # server, which is what stops the two agreeing with each other and both
    # being wrong.
    #
    # THE PASSWORD GOES ON STDIN, NEVER ON THE COMMAND LINE - TESTSDCLI reads
    # it with echo off.  A command line reaches the process list.
    #
    # TESTSDCLI IS DROPPED INTO PLACE HERE AND REMOVED IN THE OUTER FINALLY,
    # 24 Aug 2026 - it used to ship at sdsys/bp/TESTSDCLI alongside the rest
    # of SDSYS's BP, but that put a developer test file on every end user's
    # machine.  It now lives beside this script as gplbld/testsdcli.bp and is
    # copied in for the duration of the run.  BASIC still finds it as
    # "BP TESTSDCLI" because that IS the on-disk path SDSYS's BP resolves to.
    # sdsys/bp is locked to sdusers:(RX) by secure-sysdirs (step 15), but
    # VerifyInstall2 runs elevated, so the Administrators:(F) grant applies.
    # $installedTestSdcli was set at the top so the outer finally can rely on
    # it even if we fail before this point.
    $testSdcliSource = Join-Path $PSScriptRoot 'testsdcli.bp'
    if (-not (Test-Path -LiteralPath $testSdcliSource)) {
        Refuse ("verify-scramlogin: cannot find " + $testSdcliSource +
              " - it is what BASIC BP TESTSDCLI resolves to.")
    }
    Copy-Item -LiteralPath $testSdcliSource -Destination $installedTestSdcli -Force
    $droppedTestSdcli = $true

    $cliOut = Invoke-SD @(
        'BASIC BP TESTSDCLI',
        'RUN BP TESTSDCLI',
        $upper,
        $pw,
        "$Port")

    $compiled = ($cliOut -notmatch 'error\(s\)' ) -or ($cliOut -match '0 error\(s\)')
    Note 'TESTSDCLI compiles'          $true $compiled
    # THE ERRGEN TRAP.  A $define that does not resolve becomes an ordinary
    # unassigned variable, so the call compiles, the compiler says 0 errors
    # and the program misbehaves at run time.  docs/SCRAM_HANDOFF.md.
    Note 'no unassigned variables'     $false ($cliOut -match 'is not assigned a value')
    if (-not $compiled) { Write-Host $cliOut }

    Note '!sdclient connected over SCRAM' $true ($cliOut -match 'PASS  connect')
    Note '!sdclient ran a command'        $true ($cliOut -match 'PASS  execute')
    # The control inside TESTSDCLI: without it, "connect worked" says nothing
    # about whether the proof was checked.
    Note '!sdclient refused a wrong password' $true ($cliOut -match 'PASS  wrong password refused')
    Note 'TESTSDCLI overall'              $true ($cliOut -match 'TESTSDCLI PASSED')
    if ($cliOut -notmatch 'TESTSDCLI PASSED') { Write-Host $cliOut }
}
finally {
    # BEFORE ANYTHING ELSE, AND REGARDLESS OF -Keep.  A $cred left renamed
    # refuses every login on the machine, so this runs even on the paths that
    # deliberately leave the rest of the system alone.
    if ($movedCred -and (Test-Path -LiteralPath $credAside)) {
        try {
            Rename-Item -LiteralPath $credAside -NewName (Split-Path -Leaf $credDir) -ErrorAction Stop
            Write-Host '   $cred put back (outer)'
        } catch {
            Write-Host ('   $cred IS STILL RENAMED - put it back by hand: ' +
                        $credAside + ' -> ' + $credDir) -ForegroundColor Red
        }
    }

    # TESTSDCLI cleanup - REGARDLESS OF -Keep, because a leftover in
    # sdsys/bp is exactly the sdusers-visible file the 24 Aug drop removed.
    # The .OUT part comes and goes with cycles anyway (bp.out ships empty,
    # stage.py:148), but the source is what nothing on the install path
    # would put back, so leaving it here is a silent revival of what was
    # deliberately removed.
    if ($droppedTestSdcli) {
        foreach ($p in @($installedTestSdcli,
                         (Join-Path $env:ProgramData 'SD\sdsys\bp.OUT\TESTSDCLI'))) {
            if (Test-Path -LiteralPath $p) {
                Remove-Item -LiteralPath $p -Force -ErrorAction SilentlyContinue
            }
        }
        Write-Host '   TESTSDCLI removed from sdsys/bp (source lives in gplbld/testsdcli.bp)'
    }

    if (-not $Keep) {
        Step 10 'Putting the system back'

        if (Test-Path -LiteralPath $backup) {
            Copy-Item -LiteralPath $backup -Destination $conf -Force
            Remove-Item -LiteralPath $backup -Force
            Write-Host '   sd.conf restored'
        }

        if ($restoreNeeded) {
            if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name $Prefix
                Write-Host "   removed Windows account $Prefix"
            }
            $d = Join-Path $env:ProgramData ('SD\user_accounts\' + $Prefix)
            if (Test-Path -LiteralPath $d) {
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
            }
            $g = 'sdu_' + $Prefix
            if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $g }
            # The SD half is left deliberately, as verify-apiport.ps1 leaves
            # its own: removing the register record here would hide a
            # CREATE.ACCOUNT that had half failed.  $CRED keeps its record too.
            Write-Host '   ACCOUNTS and $CRED records left in place - remove with DELETE.ACCOUNT'
        }

        if (Stop-SD) { $null = Start-SD }
        Write-Host '   SD restarted with the port closed'
    } else {
        Write-Host ''
        Write-Host "-Keep: APIPORT=$Port is STILL SET and $Prefix still exists." -ForegroundColor Yellow
        Write-Host "  password: $pw"
        Write-Host "  put it back with: Copy-Item '$backup' '$conf' -Force, then restart SD"
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host

$passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("{0} / {1} checks passed" -f $passed, $results.Count)

try { Stop-Transcript | Out-Null } catch { }

if ($failed) { exit 1 }
exit 0
