<#
.SYNOPSIS
    Speak the SCRAM exchange at the API port directly and check what the
    server does with it.  docs/SCRAM_AUTH.md phases 3 and 5.

.DESCRIPTION
    ONE ELEVATED COMMAND for request types 47 and 48.  It is the only thing
    that exercises vb.scram.first and vb.scram.final; until it passes they are
    written and unproven.

    THE CLIENT IS IN THIS FILE, and that is the point.  sdclilib.c does not
    speak SCRAM until phase 4, so a test that went through the client library
    would be testing nothing.  The exchange here is built from .NET primitives
    - PBKDF2, HMAC-SHA256, SHA-256 - against the same RFC as the server, so
    agreement between the two is agreement between two implementations rather
    than one implementation agreeing with itself.

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
      - every refusal carries the message the handler meant to send, not
        merely a non-zero status
      - request 24 is REFUSED, and says why.  This check was "request 24 is
        still accepted" until phase 5 retired the cleartext login; it was
        inverted rather than deleted, so it is now the proof the old path is
        gone rather than the proof it survived.

.PARAMETER Prefix
    Name for the throwaway Windows and SD account.  Use one nobody has used -
    CREATE.ACCOUNT refuses a name it has seen, which is the right way round.

.PARAMETER Port
    Loopback port to use.  4243 is the number the Linux build uses.

.PARAMETER Keep
    Leave APIPORT set and the account in place when the run finishes, for
    poking at by hand.  The account still has to be removed with
    DELETE.ACCOUNT afterwards.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-scramlogin.ps1 -Prefix sdscram1
#>

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

# Request types.  APISRVR's dispatch table is the authority; these three are
# the only ones this script sends.
$SrvrAccount = 3
$SrvrLogin   = 24
$ScramFirst  = 47
$ScramFinal  = 48

# SCRAM$ITERATIONS in gpl.bp/INT$KEYS.H.  Asserted rather than read, so a
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
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
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
# The wire.  op_tio.c op_readpkt/op_writepkt and sdclilib.c write_packet are
# the authority for all of this.
#
#   request   [4 byte length][2 byte type][payload]
#   response  [4 byte length][2 byte server error][4 byte status][text]
#
# Length counts itself.  Every number is low byte first regardless of the
# server platform, which is APISRVR's own START-DESCRIPTION.
# ===========================================================================

function New-SdConnection([int]$port) {
    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect('127.0.0.1', $port)
    $c.NoDelay = $true
    $s = $c.GetStream()
    $s.ReadTimeout  = 30000
    $s.WriteTimeout = 30000

    # WAIT FOR THE ACK, as OpenSocket() does.  The listener accepts before the
    # SD process behind it is running, so anything sent earlier is lost; 0x06
    # is that process announcing itself.
    $deadline = (Get-Date).AddSeconds(30)
    do {
        $b = $s.ReadByte()
        if ($b -lt 0) { throw 'connection closed before the ACK arrived' }
        if ((Get-Date) -gt $deadline) { throw 'no ACK within 30 seconds' }
    } while ($b -ne 6)

    return [pscustomobject]@{
        Client = $c
        Stream = $s
        Sent   = (New-Object System.Collections.Generic.List[byte])
    }
}

function Close-SdConnection($conn) {
    if ($null -eq $conn) { return }
    try { $conn.Stream.Close() } catch { }
    try { $conn.Client.Close() } catch { }
}

function Send-SdPacket($conn, [int]$type, [byte[]]$payload) {
    if ($null -eq $payload) { $payload = New-Object byte[] 0 }
    $pkt = New-Object byte[] (6 + $payload.Length)
    [BitConverter]::GetBytes([int32]($payload.Length + 6)).CopyTo($pkt, 0)
    [BitConverter]::GetBytes([int16]$type).CopyTo($pkt, 4)
    if ($payload.Length -gt 0) { $payload.CopyTo($pkt, 6) }
    $conn.Stream.Write($pkt, 0, $pkt.Length)
    $conn.Stream.Flush()
    # EVERY BYTE IS KEPT.  The "password never on the wire" check reads this
    # back, so it measures what was sent rather than what was meant.
    $conn.Sent.AddRange($pkt)
}

function Read-SdExact($conn, [int]$n) {
    $buf = New-Object byte[] $n
    $got = 0
    while ($got -lt $n) {
        $r = $conn.Stream.Read($buf, $got, $n - $got)
        if ($r -le 0) { throw 'connection closed part way through a packet' }
        $got += $r
    }
    return $buf
}

function Receive-SdPacket($conn) {
    $len = [BitConverter]::ToInt32((Read-SdExact $conn 4), 0)
    # 4 length + 2 server error + 4 status is the smallest legal reply.
    if ($len -lt 10) { throw "reply declared $len bytes, which is shorter than a header" }
    $body = Read-SdExact $conn ($len - 4)
    return [pscustomobject]@{
        ServerError = [BitConverter]::ToInt16($body, 0)
        Status      = [BitConverter]::ToInt32($body, 2)
        Text        = [Text.Encoding]::ASCII.GetString($body, 6, $body.Length - 6)
    }
}

# ===========================================================================
# SCRAM-SHA-256, client side.  RFC 5802 and RFC 7677.
# ===========================================================================

function Get-Pbkdf2([string]$password, [byte[]]$salt, [int]$iter, [int]$len) {
    $pw = [Text.Encoding]::UTF8.GetBytes($password)
    $k = New-Object System.Security.Cryptography.Rfc2898DeriveBytes -ArgumentList @(
             $pw, $salt, $iter, [System.Security.Cryptography.HashAlgorithmName]::SHA256)
    try { return $k.GetBytes($len) } finally { $k.Dispose() }
}

function Get-Hmac([byte[]]$key, [string]$msg) {
    $h = New-Object System.Security.Cryptography.HMACSHA256 -ArgumentList (, $key)
    try { return $h.ComputeHash([Text.Encoding]::UTF8.GetBytes($msg)) } finally { $h.Dispose() }
}

function Get-Sha256([byte[]]$data) {
    $h = [System.Security.Cryptography.SHA256]::Create()
    try { return $h.ComputeHash($data) } finally { $h.Dispose() }
}

function Get-Xor([byte[]]$a, [byte[]]$b) {
    if ($a.Length -ne $b.Length) { throw 'XOR operands differ in length' }
    $o = New-Object byte[] $a.Length
    for ($i = 0; $i -lt $a.Length; $i++) { $o[$i] = $a[$i] -bxor $b[$i] }
    return $o
}

function New-Nonce {
    # 18 bytes for the same reason the server uses 18: a multiple of three, so
    # base64 adds no '=' padding, and no character it emits is a comma.
    $b = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($b)
    return [Convert]::ToBase64String($b)
}

# Sends client-first and returns what came back, parsed if it was accepted.
function Invoke-ScramFirst($conn, [string]$user, [string]$gs2 = 'n,,', [string]$nonce = '') {
    if ($nonce -eq '') { $nonce = New-Nonce }
    $bare = "n=$user,r=$nonce"
    Send-SdPacket $conn $ScramFirst ([Text.Encoding]::UTF8.GetBytes($gs2 + $bare))
    $rsp = Receive-SdPacket $conn

    $out = [pscustomobject]@{
        Bare = $bare; CNonce = $nonce; Response = $rsp
        Combined = ''; Salt = $null; Iterations = 0; Parsed = $false
    }
    if ($rsp.ServerError -ne 0) { return $out }

    $parts = $rsp.Text.Split(',')
    if ($parts.Count -ne 3)      { return $out }
    if ($parts[0].Substring(0, 2) -ne 'r=') { return $out }
    if ($parts[1].Substring(0, 2) -ne 's=') { return $out }
    if ($parts[2].Substring(0, 2) -ne 'i=') { return $out }

    $out.Combined   = $parts[0].Substring(2)
    $out.Salt       = [Convert]::FromBase64String($parts[1].Substring(2))
    $out.Iterations = [int]$parts[2].Substring(2)
    $out.Parsed     = $true
    return $out
}

# THE WHOLE CLIENT-SIDE DERIVATION, WITH NO SOCKET IN IT.  Split out so
# -SelfTest can drive it with the RFC 7677 vectors and compare against
# published constants - which makes this the code the vectors prove, rather
# than a second copy written to agree with it.
function New-ScramProof([string]$bare, [string]$serverFirst, [byte[]]$salt,
                        [int]$iter, [string]$password, [string]$nonce) {
    $salted    = Get-Pbkdf2 $password $salt $iter 32
    $clientKey = Get-Hmac $salted 'Client Key'
    $storedKey = Get-Sha256 $clientKey
    $serverKey = Get-Hmac $salted 'Server Key'

    $cfinalBare = "c=biws,r=$nonce"
    $authMsg    = $bare + ',' + $serverFirst + ',' + $cfinalBare

    return [pscustomobject]@{
        SaltedPassword  = [Convert]::ToBase64String($salted)
        StoredKey       = [Convert]::ToBase64String($storedKey)
        ServerKey       = [Convert]::ToBase64String($serverKey)
        ClientProof     = [Convert]::ToBase64String((Get-Xor $clientKey (Get-Hmac $storedKey $authMsg)))
        ServerSignature = [Convert]::ToBase64String((Get-Hmac $serverKey $authMsg))
        FinalBare       = $cfinalBare
        AuthMessage     = $authMsg
    }
}

# Sends client-final.  The overrides exist so the negative checks can send a
# message that is wrong in exactly one way.
function Invoke-ScramFinal($conn, $first, [string]$password,
                           [string]$nonceOverride = '', [string]$proofOverride = '',
                           [string]$rawOverride = '') {
    if ($rawOverride -ne '') {
        Send-SdPacket $conn $ScramFinal ([Text.Encoding]::UTF8.GetBytes($rawOverride))
        return [pscustomobject]@{ Response = (Receive-SdPacket $conn); Sent = $rawOverride; ExpectedV = '' }
    }

    if ($nonceOverride -ne '') { $n = $nonceOverride } else { $n = $first.Combined }
    $s = New-ScramProof $first.Bare $first.Response.Text $first.Salt $first.Iterations $password $n

    if ($proofOverride -ne '') { $p = $proofOverride } else { $p = $s.ClientProof }

    $msg = $s.FinalBare + ',p=' + $p
    Send-SdPacket $conn $ScramFinal ([Text.Encoding]::UTF8.GetBytes($msg))
    return [pscustomobject]@{
        Response  = (Receive-SdPacket $conn)
        Sent      = $msg
        ExpectedV = 'v=' + $s.ServerSignature
    }
}

# The request 24 body: each field a 2 byte length then the text, padded to a
# 2 byte multiple with a NUL.  SDConnect() in sdclilib.c builds exactly this.
function New-SrvrLoginBody([string]$user, [string]$password) {
    $ms = New-Object System.IO.MemoryStream
    foreach ($s in @($user, $password)) {
        $b = [Text.Encoding]::ASCII.GetBytes($s)
        $ms.Write([BitConverter]::GetBytes([int16]$b.Length), 0, 2)
        $ms.Write($b, 0, $b.Length)
        if ($b.Length -band 1) { $ms.WriteByte(0) }
    }
    return $ms.ToArray()
}

# Is this byte sequence anywhere in what we sent?
function Test-SentContains($conn, [string]$needle) {
    $hay = $conn.Sent.ToArray()
    $ndl = [Text.Encoding]::ASCII.GetBytes($needle)
    if ($ndl.Length -eq 0 -or $hay.Length -lt $ndl.Length) { return $false }
    for ($i = 0; $i -le $hay.Length - $ndl.Length; $i++) {
        $hit = $true
        for ($j = 0; $j -lt $ndl.Length; $j++) {
            if ($hay[$i + $j] -ne $ndl[$j]) { $hit = $false; break }
        }
        if ($hit) { return $true }
    }
    return $false
}

# ---------------------------------------------------------------------------
# -SelfTest: the client half alone, against the published vectors.  NO
# ELEVATION, NO SERVER, NO INSTALL - so it can be run at any time, including
# while a cycle is owed, and it is the first thing to run when the exchange
# fails and it is not obvious which side is wrong.
#
# IT PROVES THE INSTRUMENT, NOT THE SERVER.  If these five constants come out
# right, a later disagreement with SD is SD's; if they come out wrong, nothing
# this script says about the server means anything.
if ($SelfTest) {
    Step 0 'RFC 7677 section 3 vectors - client side only, no server involved'

    $tSalt     = [Convert]::FromBase64String('W22ZaJ0SNY7soEsUEjb6gQ==')
    $tCombined = 'rOprNGfwEbeRWgbNEkqO%hvYDpWUa2RaTCAfuxFIlj)hNlF$k0'
    $tFirst    = 'r=' + $tCombined + ',s=W22ZaJ0SNY7soEsUEjb6gQ==,i=4096'
    $t = New-ScramProof 'n=user,r=rOprNGfwEbeRWgbNEkqO' $tFirst $tSalt 4096 'pencil' $tCombined

    Note 'SaltedPassword'  'xKSVEDI6tPlSysH6mUQZOeeOp01r6B3fcJbodRPcYV0=' $t.SaltedPassword
    Note 'StoredKey'       'WG5d8oPm3OtcPnkdi4Uo7BkeZkBFzpcXkuLmtbsT4qY=' $t.StoredKey
    Note 'ServerKey'       'wfPLwcE6nTWhTAmQ7tl2KeoiWGPlZqQxSrmfPwDl2dU=' $t.ServerKey
    Note 'ClientProof'     'dHzbZapWIk4jUhN+Ute9ytag9zjfMHgsqmmiz7AndVQ=' $t.ClientProof
    Note 'ServerSignature' '6rriTRBi23WpRR/wtup+mMhUZUn/dB5nLTJRsjl95G4=' $t.ServerSignature

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
    Fail 'Give -Prefix a name nobody has used, or run with -SelfTest for the offline vector check.'
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'Run this from an ELEVATED PowerShell - it creates an account, edits the installed sd.conf and restarts SD.'
}

if (-not [BitConverter]::IsLittleEndian) {
    Fail 'This script builds packets with BitConverter and assumes a little endian host.'
}

# THE CYCLE RULE, and it is a gate rather than a reminder.  CLAUDE.md: anything
# that tests the install calls this first, or the result describes a tree that
# no longer exists.
Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'assert-current refuses - run gplbld/cycle.ps1 first.' }

if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
    Fail "$Prefix already exists as a Windows account.  Use a -Prefix that does not."
}
if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper()))) {
    Fail ($Prefix.ToUpper() + " is still in the ACCOUNTS register from an earlier run." +
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

try {
    # -----------------------------------------------------------------------
    Step 1 "Creating the throwaway account $Prefix"

    # NO NO.QUERY: CREATE.ACCOUNT USER creates a Windows account too and
    # refuses outright without a prompt.  Two passwords, deliberately not the
    # same thing - $winPw is Windows', $pw is the SD credential and the only
    # one this test ever uses.  verify-apiport.ps1 has the long version.
    Add-Type -AssemblyName System.Web
    $winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6)

    $out = Invoke-SD @("CREATE.ACCOUNT USER $Prefix PROGRAMMER API", $winPw, $winPw)
    $accRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper())
    $made = Test-Path -LiteralPath $accRec
    Note 'accounts record created' $true $made
    if (-not $made) { Write-Host $out; Fail 'CREATE.ACCOUNT did not register the account.' }
    $restoreNeeded = $true

    # -----------------------------------------------------------------------
    Step 2 'Setting its password'

    # GENERATED, NEVER HARDCODED, AND NEVER ON A COMMAND LINE - it goes to SD
    # on stdin.  Alphanumeric so it cannot be confused by any quoting on the
    # way, and so the "is it on the wire" search is unambiguous.
    $bytes = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + 'aA1'

    $out = Invoke-SD @(("MODIFY.PASSWORD " + $Prefix.ToUpper()), $pw, $pw)
    $set = ($out -match 'Password set for account')
    Note 'password set' $true $set
    if (-not $set) { Write-Host $out; Fail 'MODIFY.PASSWORD did not report success.' }

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
    if (-not (Stop-SD))  { Fail 'SD would not stop - close any open session and try again.' }
    if (-not (Start-SD)) { Fail 'SD would not start again.  Read the SD error log.' }
    Start-Sleep -Seconds 2

    $listen = @(netstat -an | Select-String 'LISTENING' |
                Where-Object { $_ -match (':' + $Port + '\s') })
    Note 'a listener on the port' $true ($listen.Count -gt 0)
    if ($listen.Count -eq 0) { Fail 'Nothing is listening - the rest of this script has nothing to talk to.' }

    $upper = $Prefix.ToUpper()

    # -----------------------------------------------------------------------
    Step 5 'The exchange, end to end'

    $c1 = $null
    try {
        $c1 = New-SdConnection $Port
        $f1 = Invoke-ScramFirst $c1 $Prefix

        Note '47 accepted'                 0     ([int]$f1.Response.ServerError)
        if ($f1.Response.ServerError -ne 0) { Write-Host ('   server said: ' + $f1.Response.Text) }
        Note 'server-first parses'         $true $f1.Parsed
        if (-not $f1.Parsed) {
            Write-Host ('   server-first was: ' + $f1.Response.Text)
            Fail 'Without a server-first there is nothing further to check.'
        }

        # THE CLIENT-SIDE CHECK THE DESIGN NAMES.  A combined nonce that does
        # not start with the nonce we sent is a reply to somebody else's
        # exchange, and this is the test that notices.
        Note 'combined nonce extends ours' $true $f1.Combined.StartsWith($f1.CNonce)
        Note 'server added nonce of its own' $true ($f1.Combined.Length -gt $f1.CNonce.Length)
        Note 'iterations'                  $ExpectedIterations $f1.Iterations

        $r1 = Invoke-ScramFinal $c1 $f1 $pw
        Note '48 accepted'                 0     ([int]$r1.Response.ServerError)
        if ($r1.Response.ServerError -ne 0) { Write-Host ('   server said: ' + $r1.Response.Text) }

        # MUTUAL AUTHENTICATION, AND IT IS THE HALF EASIEST TO LET SLIDE.  The
        # signature is computed here from ServerKey and compared; a server that
        # answered anything else would be an impostor, and this is where that
        # is caught rather than in a comment.
        Note 'server signature verifies'   $r1.ExpectedV $r1.Response.Text

        # NOT JUST "48 RETURNED 0".  logged.in has to have been set, and the
        # only way to see that from outside is to issue a request the main loop
        # refuses to an unauthenticated session.
        Send-SdPacket $c1 $SrvrAccount ([Text.Encoding]::ASCII.GetBytes($upper))
        $acc = Receive-SdPacket $c1
        Note 'session is authenticated'    0     ([int]$acc.ServerError)
        if ($acc.ServerError -ne 0) { Write-Host ('   server said: ' + $acc.Text) }

        # THE CENTRAL CLAIM, MEASURED.  Everything this connection sent is in
        # $c1.Sent; the password is not in it.  The control is in step 9.
        Note 'password absent from the bytes sent' $false (Test-SentContains $c1 $pw)

        $capturedFinal = $r1.Sent
        $firstCombined = $f1.Combined
    } finally { Close-SdConnection $c1 }

    # -----------------------------------------------------------------------
    Step 6 'Freshness: a second exchange for the same account'

    $c2 = $null
    try {
        $c2 = New-SdConnection $Port
        $f2 = Invoke-ScramFirst $c2 $Prefix
        Note '47 accepted again'           0     ([int]$f2.Response.ServerError)
        # If this ever fails, the server nonce is not random and every replay
        # defence below is decoration.
        Note 'server nonce differs from the first exchange' $true ($f2.Combined -ne $firstCombined)
    } finally { Close-SdConnection $c2 }

    # -----------------------------------------------------------------------
    Step 7 'The refusals'

    # Each of these needs its own connection: a refused exchange sets done and
    # the server drops the link, which is itself part of the behaviour.

    # Wrong password.  Everything else about the message is correct, so this
    # isolates the proof.
    $c = $null
    try {
        $c = New-SdConnection $Port
        $f = Invoke-ScramFirst $c $Prefix
        $r = Invoke-ScramFinal $c $f ($pw + 'x')
        Note 'wrong password refused'      $true ([int]$r.Response.ServerError -ne 0)
        Note '  and it is 5017'            (Get-SysMsg 5017) $r.Response.Text.Trim()
    } finally { Close-SdConnection $c }

    # Replay.  A client-final captured from the exchange that SUCCEEDED, sent
    # against a fresh client-first.  Its nonce belongs to an exchange that no
    # longer exists, which is what makes the capture worthless.
    $c = $null
    try {
        $c = New-SdConnection $Port
        $null = Invoke-ScramFirst $c $Prefix
        $r = Invoke-ScramFinal $c $null $pw '' '' $capturedFinal
        Note 'replayed client-final refused' $true ([int]$r.Response.ServerError -ne 0)
        # 5272, not 5017: the proof is never reached.  A stale nonce is a bad
        # MESSAGE, and if this ever reads 5017 the server has run a signature
        # check against an exchange that had already been closed.
        Note '  and it is 5272'            (Get-SysMsg 5272) $r.Response.Text.Trim()
    } finally { Close-SdConnection $c }

    # A client-final answering a nonce nobody issued.
    $c = $null
    try {
        $c = New-SdConnection $Port
        $f = Invoke-ScramFirst $c $Prefix
        $r = Invoke-ScramFinal $c $f $pw (New-Nonce)
        Note 'tampered nonce refused'      $true ([int]$r.Response.ServerError -ne 0)
        Note '  and it is 5272'            (Get-SysMsg 5272) $r.Response.Text.Trim()
    } finally { Close-SdConnection $c }

    # 48 with no 47 before it.  This is the one that would pass silently if the
    # handler compared against empty values instead of refusing.
    $c = $null
    try {
        $c = New-SdConnection $Port
        $r = Invoke-ScramFinal $c $null $pw '' '' 'c=biws,r=nonsense,p=AAAA'
        Note 'client-final without client-first refused' $true ([int]$r.Response.ServerError -ne 0)
        # 5273 and not 5272: the sequence is what is wrong, not the message.
        Note '  and it is 5273'            (Get-SysMsg 5273) $r.Response.Text.Trim()
    } finally { Close-SdConnection $c }

    # An account that does not exist.
    $c = $null
    try {
        $c = New-SdConnection $Port
        $f = Invoke-ScramFirst $c ($Prefix + 'nosuch')
        Note 'unknown account refused'     $true ([int]$f.Response.ServerError -ne 0)
        # THE SAME WORDS AS A WRONG PASSWORD, which is the point - the reply
        # must not distinguish an account that exists from one that does not.
        # The round trip still does; docs/SCRAM_AUTH.md, "Still open".
        Note '  and it is 5017, as a wrong password is' (Get-SysMsg 5017) $f.Response.Text.Trim()
    } finally { Close-SdConnection $c }

    # The downgrade signal.  'y,,' says "the server does not support channel
    # binding"; accepting it would let a man in the middle strip a binding that
    # a later SCRAM-SHA-256-PLUS would rely on.
    $c = $null
    try {
        $c = New-SdConnection $Port
        $f = Invoke-ScramFirst $c $Prefix 'y,,'
        Note 'y,, downgrade refused'       $true ([int]$f.Response.ServerError -ne 0)
        Note '  and it is 5272'            (Get-SysMsg 5272) $f.Response.Text.Trim()
    } finally { Close-SdConnection $c }

    # A mandatory extension the server does not understand.  RFC 5802 requires
    # a failure, not a shrug.
    $c = $null
    try {
        $c = New-SdConnection $Port
        Send-SdPacket $c $ScramFirst ([Text.Encoding]::UTF8.GetBytes(
            'n,,m=whatever,n=' + $Prefix + ',r=' + (New-Nonce)))
        $r = Receive-SdPacket $c
        Note 'm= mandatory extension refused' $true ([int]$r.ServerError -ne 0)
        Note '  and it is 5272'            (Get-SysMsg 5272) $r.Text.Trim()
    } finally { Close-SdConnection $c }

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
        $c = $null
        try {
            $c = New-SdConnection $Port
            $f = Invoke-ScramFirst $c $Prefix
            Note 'unopenable $cred refused'  $true ([int]$f.Response.ServerError -ne 0)
            Note '  and it is 5274, not 5017' (Get-SysMsg 5274) $f.Response.Text.Trim()
        } finally {
            Close-SdConnection $c
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

    $c3 = $null
    try {
        $c3 = New-SdConnection $Port
        # THE CREDENTIALS ARE CORRECT.  That is what makes this a test of the
        # retirement rather than of the password: the old path is refused for
        # a login that would have succeeded before phase 5.
        Send-SdPacket $c3 $SrvrLogin (New-SrvrLoginBody $Prefix $pw)
        $r = Receive-SdPacket $c3
        Note 'request 24 refused'          $true ([int]$r.ServerError -ne 0)

        # AND IT IS 5275, NOT 5017 OR 5270.  A retired request that answered
        # "invalid username or password" would send everyone looking for a
        # credential fault; "not logged in" would read as a client bug.  This
        # is the check that keeps the reply diagnostic, and it is also what
        # distinguishes a handler that refuses from one that was never reached.
        Note '  and it is 5275'            (Get-SysMsg 5275) $r.Text.Trim()

        # -------------------------------------------------------------------
        Step 9 'The control for the wire check'

        # WITHOUT THIS, "the password is not in the bytes" MEANS NOTHING - a
        # search that can never find anything passes just as well.  Request 24
        # carries the password in clear, and the same function finds it.
        #
        # STILL VALID AFTER PHASE 5, and worth being clear why: Test-SentContains
        # reads what THIS SCRIPT sent, not what the server accepted.  The packet
        # above still puts the password on the wire; the server now throws it
        # away instead of reading it.  So the control measures the detector, as
        # it always did, and does not depend on request 24 working.
        Note 'same search finds the password in a request 24 login' $true (Test-SentContains $c3 $pw)
    } finally { Close-SdConnection $c3 }

    # -----------------------------------------------------------------------
    Step '9b' 'The OTHER client: the !sdclient class module'

    # SDCLIENT IS THE THIRD THING THAT SPEAKS THIS PROTOCOL, and it is the one
    # nothing had ever tested.  sdclilib.dll is the client for applications
    # outside SD; !sdclient is the client for BASIC programs inside it, and it
    # sent the cleartext request 24 until phase 5 gave it a SCRAM exchange.
    # Retiring 24 without changing it would have broken it silently - it has no
    # test of its own and no caller in this tree to notice.
    #
    # EVERYTHING ABOVE SPEAKS SCRAM FROM .NET.  This step is the only one that
    # exercises the BASIC implementation, and it runs against the same server,
    # which is what stops the two agreeing with each other and both being wrong.
    #
    # THE PASSWORD GOES ON STDIN, NEVER ON THE COMMAND LINE - sdsys/bp/TESTSDCLI
    # reads it with echo off.  A command line reaches the process list.
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
