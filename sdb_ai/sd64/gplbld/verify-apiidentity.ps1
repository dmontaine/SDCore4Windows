# verify-apiidentity.ps1 - does an API session actually run as the user?
#
# 23 Aug 26 Windows port.  PROJECT_STATUS.md section 7 step 14, shape (b).
#
# WHAT IT IS FOR, AND WHY THE SUITE PASSING WITHOUT IT PROVED LESS THAN IT
# LOOKED.  b17 was green with the identity change in, and because APISRVR's
# hook FAILS CLOSED that did prove something real: message 5277 never fired, so
# kernel(K$ASSUME.USER) returned 1 on every live API login and the S4U logon and
# ImpersonateLoggedOnUser both worked.
#
# IT PROVED NOTHING ABOUT THE EFFECT.  No check asked whether the session is now
# CONFINED to what the user may read - and a green suite would look exactly the
# same if the token changed and the file layer ignored it.  That was a live
# possibility until gplbld/probe-impersonate.c measured otherwise, and
# probe-impersonate measured a bare process, not a session reached over the API.
# This closes the gap end to end.
#
# HOW IT WORKS.  Two fixture directories, built here and destroyed afterwards:
#
#     allow    the throwaway user is granted (RX)          open must SUCCEED
#     deny     SYSTEM and Administrators only, inheritance
#              broken - exactly sdsys\$cred's shape        open must be REFUSED
#
# Each gets a VOC F-pointer in the throwaway account, planted with SET.FILE from
# a local elevated session.  Then a LIVE API SESSION logs in with SCRAM and
# sends request 4 - vb.open - for each pointer.  One request, one answer, no
# command parsing in the way.
#
# THE ALLOW FIXTURE IS THE CONTROL AND IT CARRIES THE WHOLE TEST.  A refusal on
# "deny" means nothing on its own: a wrong path, a mistyped VOC pointer or a
# file that was never created all look identical to an ACL denial.  If "allow"
# does not open, this script reports VOID and refuses to call "deny" a pass -
# CLAUDE.md, a test that passes because it did nothing must fail.
#
# AND THE THROWAWAY USER MUST NOT BE AN ADMINISTRATOR, or the deny fixture is
# not denied to them and a false negative reads as a real one.  CREATE.ACCOUNT
# does not make administrators, but it is checked rather than assumed.
#
# WHAT A FAILURE MEANS.  If "deny" OPENS, the session is still reaching files
# with the service's rights and step 14 is not doing what it was built for -
# the login half works and the containment half does not.  That is a product
# finding, not a test fault, and it should be treated as one.
#
# THE SCRAM CLIENT BELOW IS COPIED VERBATIM FROM verify-scramlogin.ps1, extracted
# with the PowerShell AST rather than retyped.  Duplicated rather than shared
# because factoring it out would mean editing a verifier that passes, and the
# copy cannot drift into being subtly wrong the way a retyped one can.  If the
# protocol ever changes, both change.
#
# NOT SHIPPED - it must be on assert-current.ps1's $neverShipped list.
#
# NOT YET RUN BY ANYBODY.  Written 23 Aug 2026 at the end of a long session and
# handed over UNRUN, deliberately: PROJECT_STATUS's START HERE says so.

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [int]    $Port = 4243,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

# Request types.  APISRVR's dispatch table is the authority.
$SrvrOpen   = 4
$SrvrQuit   = 1
$ScramFirst = 47
$ScramFinal = 48

$script:checks = @()
$script:void   = $false

function Note($check, $expected, $got, $decisive = $true) {
    $pass = ($expected -eq $got)
    $script:checks += [pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' }); Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    }
    $tag = $(if ($pass) { '[PASS]' } else { '[FAIL]' })
    Write-Host "  $tag $check`: expected $expected, got $got"
}
function Fail($msg) { Write-Host ''; Write-Host "verify-apiidentity: $msg" -ForegroundColor Red; exit 1 }
function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

function Invoke-Icacls {
    param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Arguments)
    $saved = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    try { $o = & icacls.exe @Arguments 2>&1; return [pscustomobject]@{ Code = $LASTEXITCODE; Output = $o } }
    finally { $ErrorActionPreference = $saved }
}

# A local elevated SD session, for the setup only.  $null | so a console cannot
# be handed to sd as stdin - verify-batchjob.ps1:85 has why that matters.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + (($commands + 'OFF') -join "`n") + "`n"
    $job = Start-Job -ScriptBlock {
        param($exe, $text) $text | & $exe
    } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout 90) { $out = Receive-Job $job }
    else { Stop-Job $job; $out = Receive-Job $job; $out += '*** TIMED OUT' }
    Remove-Job $job -Force
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') | Out-String)
}

# ---------------------------------------------------------------------------
# THE SCRAM CLIENT, COPIED VERBATIM FROM verify-scramlogin.ps1 - see the header.
# Extracted with the PowerShell AST, not retyped.
# ---------------------------------------------------------------------------

﻿function New-SdConnection([int]$port) {
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

# ---------------------------------------------------------------------------
# Open a file by VOC name over the API and say plainly what came back.
# Request 4 is vb.open; a non-zero server error means it did not open.
# ---------------------------------------------------------------------------
function Test-ApiOpen($conn, [string]$vocName) {
    $payload = [Text.Encoding]::ASCII.GetBytes($vocName)
    Send-SdPacket $conn $SrvrOpen $payload
    $reply = Receive-SdPacket $conn
    # SERVER.ERROR IS THE FIELD, NOT STATUS.  vb.open sets server.error to
    # SV$ON.ERROR or SV$ELSE when the open fails; Status is SD's STATUS() and is
    # not what says whether the file opened.  verify-scramlogin judges every one
    # of its checks the same way.  Getting this wrong would have called every
    # refusal a success.
    return [pscustomobject]@{
        Opened      = ($reply.ServerError -eq 0)
        ServerError = $reply.ServerError
        Status      = $reply.Status
        Text        = $reply.Text
    }
}

# ---------------------------------------------------------------------------
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
Write-Host 'verify-apiidentity - does an API session run as the user? (7 step 14)'
Write-Host ''

& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'assert-current refuses - the install does not match source.' }

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'this needs an ELEVATED window: it creates an account and sets ACLs.'
}

if (-not $Prefix) { Fail 'pass -Prefix, e.g. -Prefix sdapiidb18.  It names the throwaway account.' }
if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
    Fail "$Prefix already exists as a Windows account.  Use a -Prefix that does not."
}
if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper()))) {
    Fail ($Prefix.ToUpper() + ' is still in the ACCOUNTS register from an earlier run.')
}

$base    = Join-Path $env:ProgramData ('SD\zzapiid-' + $stamp)
$allowDir = Join-Path $base 'allow'
$denyDir  = Join-Path $base 'deny'
$made     = $false

try {
    # ---------------------------------------------------------------- 1
    Step 1 "Creating the throwaway account $Prefix"
    $winPw = 'Zz!' + [Guid]::NewGuid().ToString('N').Substring(0, 12) + 'aA9'
    $apiPw = 'Qq!' + [Guid]::NewGuid().ToString('N').Substring(0, 12) + 'bB8'
    $out = Invoke-SD @("CREATE.ACCOUNT USER $Prefix PROGRAMMER API", $winPw, $winPw)
    $accRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper())
    if (-not (Test-Path -LiteralPath $accRec)) { Write-Host $out; Fail 'CREATE.ACCOUNT did not register the account.' }
    $made = $true
    Write-Host "   account $Prefix created"

    $out = Invoke-SD @(("MODIFY.PASSWORD " + $Prefix.ToUpper()), $apiPw, $apiPw)
    if ($out -notmatch 'Password set') { Write-Host $out; Fail 'MODIFY.PASSWORD did not report success.' }
    Write-Host '   API password set'

    # THE CONTROL ON THE CONTROL.  If CREATE.ACCOUNT ever started making
    # administrators, the deny fixture would not deny and this whole run would
    # read as "impersonation does nothing".
    $admins = @(Get-LocalGroupMember -Group 'Administrators' -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    if ($admins -match "\\$Prefix$") { Fail "$Prefix is an Administrator - the deny fixture would not deny it." }
    Write-Host "   $Prefix is not an Administrator, so the deny fixture really denies"

    # ---------------------------------------------------------------- 2
    Step 2 'Building the two fixtures'
    New-Item -ItemType Directory -Force -Path $allowDir | Out-Null
    New-Item -ItemType Directory -Force -Path $denyDir  | Out-Null
    Set-Content -LiteralPath (Join-Path $allowDir 'REC1') -Value 'readable' -Encoding ascii
    Set-Content -LiteralPath (Join-Path $denyDir  'REC1') -Value 'secret'   -Encoding ascii

    # /inheritance:r FIRST, or the inherited ACEs grant read and "deny" is not
    # denied.  This is sdsys\$cred's shape.
    $null = Invoke-Icacls $denyDir  /inheritance:r
    $null = Invoke-Icacls $denyDir  /grant 'SYSTEM:(OI)(CI)(F)' 'Administrators:(OI)(CI)(F)'
    $null = Invoke-Icacls $allowDir /inheritance:r
    $null = Invoke-Icacls $allowDir /grant 'SYSTEM:(OI)(CI)(F)' 'Administrators:(OI)(CI)(F)' ("{0}:(OI)(CI)(RX)" -f $Prefix)
    Write-Host "   allow: $allowDir"
    Write-Host "   deny : $denyDir"

    # ---------------------------------------------------------------- 3
    Step 3 'Pointing the account VOC at both, with SET.FILE'
    $out = Invoke-SD @("LOGTO " + $Prefix.ToUpper(),
                       "SET.FILE $allowDir ZZIDALLOW",
                       "SET.FILE $denyDir ZZIDDENY",
                       'CT VOC ZZIDALLOW', 'CT VOC ZZIDDENY')
    if ($out -notmatch 'ZZIDALLOW' -or $out -notmatch 'ZZIDDENY') {
        Write-Host $out; Fail 'SET.FILE did not plant both VOC pointers.'
    }
    Write-Host '   ZZIDALLOW and ZZIDDENY are in the account VOC'

    # ---------------------------------------------------------------- 4
    Step 4 'Opening both through a LIVE API session'
    $conn = $null
    try {
        $conn  = New-SdConnection $Port
        $first = Invoke-ScramFirst $conn $Prefix
        if ($first.Response.ServerError -ne 0 -or -not $first.Parsed) {
            Write-Host ('   server said: ' + $first.Response.Text)
            Fail 'the SCRAM client-first was refused - no session to measure.'
        }
        $final = Invoke-ScramFinal $conn $first $apiPw
        if ($final.Response.ServerError -ne 0) {
            Write-Host ('   server said: ' + $final.Response.Text)
            Fail ('SCRAM login failed, so nothing below can be measured.  IF THAT TEXT IS ' +
                  'MESSAGE 5277 - "could not take your Windows identity" - then ' +
                  'K$ASSUME.USER refused and THAT IS THE FINDING, not a broken test.')
        }
        Write-Host "   logged in over the API as $Prefix"

        $allow = Test-ApiOpen $conn 'ZZIDALLOW'
        $deny  = Test-ApiOpen $conn 'ZZIDDENY'
        Write-Host "   ZZIDALLOW opened=$($allow.Opened)  serverError=$($allow.ServerError)  status=$($allow.Status)"
        Write-Host "   ZZIDDENY  opened=$($deny.Opened)  serverError=$($deny.ServerError)  status=$($deny.Status)"
        if ($deny.Text) { Write-Host ("   deny reply: " + $deny.Text.Trim()) }

        # THE NULL-CASE GUARD.  Without the allow fixture opening, a refusal on
        # deny says nothing at all.
        if (-not $allow.Opened) {
            $script:void = $true
            Write-Host ''
            Write-Host '*** VOID: the ALLOW fixture did not open either. ***' -ForegroundColor Yellow
            Write-Host '    The VOC pointer, the path or the fixture is wrong, so the refusal'
            Write-Host '    on DENY proves nothing.  Nothing here is a result.'
        } else {
            Note 'ALLOW fixture opens over the API'      $true  $allow.Opened
            Note 'DENY fixture is REFUSED over the API'  $false $deny.Opened
        }
    } finally {
        if ($conn) { try { Send-SdPacket $conn $SrvrQuit @() } catch { }; Close-SdConnection $conn }
    }
}
finally {
    if (-not $Keep) {
        Step 9 'Cleaning up'
        if ($made) {
            $out = Invoke-SD @("DELETE.ACCOUNT " + $Prefix.ToUpper() + ' USER', 'Y')
            Write-Host "   account $Prefix removed"
        }
        if (Test-Path -LiteralPath $base) {
            $null = Invoke-Icacls $base /reset /T /C
            Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "   fixtures removed"
        }
    } else {
        Write-Host ''
        Write-Host "-Keep: account $Prefix and $base are still there."
    }
}

Write-Host ''
if ($script:void) {
    Write-Host 'verify-apiidentity: VOID - a control did not hold, nothing was measured.' -ForegroundColor Yellow
    exit 2
}
$script:checks | Format-Table -AutoSize | Out-String | Write-Host
$failed = @($script:checks | Where-Object { $_.Result -eq 'FAIL' })
if ($failed.Count -gt 0) {
    Write-Host "verify-apiidentity: FAILED - $($failed.Count) check(s)." -ForegroundColor Red
    Write-Host '  If DENY opened, the API session is still reaching files with the'
    Write-Host '  service rights: step 14 logs in as the user and does not CONTAIN'
    Write-Host '  the user.  That is a product finding, not a test fault.'
    exit 1
}
Write-Host 'verify-apiidentity: PASSED - an API session opens what the user may and is refused what it may not.'
exit 0
