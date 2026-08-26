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
$SrvrOpen    = 4
$SrvrQuit    = 1
$SrvrAccount = 3
$SrvrWrite   = 16   # APISRVR dispatch table line 336
$ScramFirst  = 47
$ScramFinal  = 48

$script:checks = @()
$script:void   = $false
# 26 Aug 26 - set by the teardown when the throwaway account did not fully go.
# It does not gate the exit code; it stops the closing sentence claiming a run
# that left nothing behind.  See the teardown for what that cost.
$script:leftLitter = ''

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

# Apply a grant and REFUSE TO BELIEVE THE EXIT CODE ON ITS OWN.
#
# icacls exits 0 having failed on some of the items it was given: measured
# 24 Aug 2026, "<path>\*: Access is denied." on stderr with exit 0, because
# the item named on the command line succeeded and only the recursion did
# not.  b25 and b26 were both scored on that silence.  The two honest
# signals are the denial text and the "Failed processing N files" tail, so
# both are read, and anything unexpected stops the run rather than leaving a
# half-applied ACL for Step 5 to misinterpret as a product finding.
function Assert-Icacls([string[]]$arguments, [string]$what) {
    # SPLATTED, NOT PASSED.  Invoke-Icacls collects ValueFromRemainingArguments,
    # so handing it an array as one positional argument NESTS it and icacls
    # receives the whole command line as a single path - "The filename,
    # directory name, or volume label syntax is incorrect", exit 123.
    $r = Invoke-Icacls @arguments
    $text = ($r.Output | Out-String)
    if ($r.Code -ne 0) {
        Write-Host $text
        Fail "$what exited $($r.Code)."
    }
    if ($text -match 'Access is denied|Failed processing [1-9]') {
        Write-Host $text
        Fail ("$what reported a failure while exiting 0.  " +
              'Some object did not get the ACL, so the fixture cannot be trusted.')
    }
}

# TWO CALLS, NOT A LOOP OVER A LIST OF ARGUMENT LISTS.  The loop form was
# written as @(@('/grant') + $grants, @('/inheritance:r')) and PowerShell binds
# "," TIGHTER than "+", so that parses as @('/grant') + ($grants, @(...)) and
# yields THREE passes - "/grant" with no principals, the principals with no
# verb, then the strip.  Measured before it ran.  Two plain calls cannot
# express that mistake.
function Set-FixtureAcl([string]$path, [string[]]$grants, [bool]$recurse, [string]$label) {
    $tail = @('/C') + $(if ($recurse) { @('/T') } else { @() })
    Assert-Icacls (@($path, '/grant') + $grants + $tail) "icacls /grant on $label"
    Assert-Icacls (@($path, '/inheritance:r') + $tail)   "icacls /inheritance:r on $label"
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
    # BACKTICK-e IS NOT AN ESCAPE IN WINDOWS POWERSHELL 5.1 - it arrived in
    # PowerShell 6, so "`e[..." is the literal letter e and this strip was dead
    # code (PROJECT_STATUS.md section 6 records the same dead line in
    # verify-nocase.ps1 and verify-tiers.ps1).  It matters here and not there:
    # the Step 3 checks below anchor on ^ at line start, and an unstripped
    # [K erase-line sequence sits between the newline and the text.
    $esc = [char]27
    return (($out -replace "$esc\[[0-9]*[A-Za-z]", '') | Out-String)
}

# WHO prints "<session> <ACCOUNT>" or "<session> <ACCOUNT> from <ACCOUNT>".
#
# THE OBVIOUS PATTERN FOR THAT IS WRONG AND COST RUN b24.  '^\s*\d+\s+(\S+)'
# also matches COPY's own success line, "1 record(s) copied." - digit, space,
# token - so a step containing two COPYs parsed as five WHO reports:
# "DON, SDAPIIDB24, record(s), record(s), SDAPIIDB24".  The account check then
# read index 2 as "record(s)" and failed a step that had entirely succeeded.
#
# So the account is matched as an ACCOUNT-SHAPED token to end of line, which
# "record(s) copied." cannot be: it has a parenthesis and trailing prose.
#
# AND THE PATTERN IS DELIBERATELY NOT CASE-INSENSITIVE.  [A-Z] under (?i)
# matches the "r" of "record(s)" and puts the bug straight back - the same
# trap PROJECT_STATUS.md section 6 records as "-match IS CASE INSENSITIVE, so
# a success test can match the failure line".  WHO upcases the account name
# (measured on b24: "47 SDAPIIDB24 from DON"), so (?m) alone is correct.
function Get-WhoAccounts([string]$text) {
    $pattern = '(?m)^\s*\d+\s+([A-Z][A-Z0-9_.$-]*)(?:\s+from\s+[A-Z][A-Z0-9_.$-]*)?\s*$'
    return @([regex]::Matches($text, $pattern) | ForEach-Object { $_.Groups[1].Value })
}

# ---------------------------------------------------------------------------
# THE SCRAM CLIENT, COPIED VERBATIM FROM verify-scramlogin.ps1 - see the header.
# Extracted with the PowerShell AST, not retyped.
# ---------------------------------------------------------------------------

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
    # Data is the payload as RAW BYTES.  vb.open answers with the file number
    # as iconv(i,'ISL') - a two-byte little-endian short (APISRVR:668) - which
    # is not text and does not survive an ASCII decode.
    $data = New-Object byte[] ($body.Length - 6)
    if ($data.Length -gt 0) { [Array]::Copy($body, 6, $data, 0, $data.Length) }
    return [pscustomobject]@{
        ServerError = [BitConverter]::ToInt16($body, 0)
        Status      = [BitConverter]::ToInt32($body, 2)
        Text        = [Text.Encoding]::ASCII.GetString($body, 6, $body.Length - 6)
        Data        = $data
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
    # FileNo is what vb.write needs; vb.open returns it as a 2-byte LE short.
    $fno = -1
    if ($reply.ServerError -eq 0 -and $reply.Data.Length -ge 2) {
        $fno = [BitConverter]::ToInt16($reply.Data, 0)
    }
    return [pscustomobject]@{
        Opened      = ($reply.ServerError -eq 0)
        ServerError = $reply.ServerError
        Status      = $reply.Status
        Text        = $reply.Text
        FileNo      = $fno
    }
}

# vb.write, request 16 (APISRVR:900).  Payload is
#   fileno (2, LE) | id_len (2, LE) | id | data
# which is what APISRVR's oconv(cmnd[1,2],'ISL') / cmnd[3,2] / cmnd[5,id.len]
# read back off the wire.
function Invoke-ApiWrite($conn, [int]$fileNo, [string]$id, [string]$data) {
    $idBytes   = [Text.Encoding]::ASCII.GetBytes($id)
    $dataBytes = [Text.Encoding]::ASCII.GetBytes($data)
    $payload   = New-Object System.Collections.Generic.List[byte]
    $payload.AddRange([BitConverter]::GetBytes([int16]$fileNo))
    $payload.AddRange([BitConverter]::GetBytes([int16]$idBytes.Length))
    $payload.AddRange($idBytes)
    $payload.AddRange($dataBytes)
    Send-SdPacket $conn $SrvrWrite $payload.ToArray()
    $reply = Receive-SdPacket $conn
    return [pscustomobject]@{
        Written     = ($reply.ServerError -eq 0)
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
$userDir  = Join-Path $base 'useronly'
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
    # HOW THE FIXTURES GET INTO VOC, AND WHY IT IS THIS WAY ROUND.  Two
    # earlier routes are dead and are recorded so neither is tried again:
    #   b21  SET.FILE is a CROSS-ACCOUNT verb (SETFILE.b:29 = "SET.FILE
    #        account file.name pointer.name"), so it read ZZIDALLOW as an
    #        account name and refused with sysmsg 2201, every call.
    #   b23  CREATE.FILE ... DYNAMIC PATHNAME <path> half-succeeds.  CREATEF
    #        prints 6127, writes the VOC entry, THEN opens the new dictionary
    #        and stops on 6128 before adding @ID (CREATEF:471-486).  The VOC
    #        entry survives pointing at a structurally incomplete file, so
    #        vb.open answered ER_FNF.  That is a product bug, still open.
    #
    # The route used now needs neither verb.  A VOC F-pointer is just a
    # three-field record, and a DIRECTORY-type file stores each record as a
    # plain text file with NEWLINE field marks (C:\ProgramData\SD\sdsys\bp is
    # the shipped example).  So: make a scratch directory file, write the
    # pointer into it as text, and let COPY carry it into VOC - COPY maps
    # newlines to field marks whenever exactly one side is a directory file
    # (COPY:220-229; the BINARY keyword is what SUPPRESSES that, and is
    # implied only when BOTH sides are directory files).
    #
    # THE FIXTURE MUST BE A DYNAMIC FILE, NOT A DIRECTORY FILE, AND THAT IS
    # THE WHOLE VALIDITY OF THE TEST.  op_dio1.c:734 stats the path, then
    # :767 tests for a %0 subfile: with %0 it calls dh_open() and really
    # OPENS the bucket files, which is what an ACL can refuse; without %0 it
    # becomes a DIRECTORY_FILE and op_dio1.c:866 opens NOTHING - the stat
    # alone succeeds through the parent's traverse right even when the DACL
    # grants the user nothing.  A directory-file fixture would therefore
    # report "deny opened" on a working build and read as impersonation
    # doing nothing.
    # UserMayRead is what Step 4 asserts of every object in the tree and what
    # Step 5 expects of the API open.  Grants are passed to icacls verbatim.
    # ZZIDUSER names NEITHER SYSTEM NOR Administrators, deliberately:
    # LocalSystem holds both, so a fixture carrying either cannot tell a
    # contained session from an uncontained one.
    #
    # DEFINED BEFORE STEP 2, WHICH USES IT.  foreach over an undefined
    # variable iterates ZERO times in PowerShell rather than erroring, so
    # declaring this later made Step 2 create nothing, print nothing, and hand
    # a missing directory to the move in Step 3.
    # DIRECTORIES AND FILES ARE GRANTED SEPARATELY, AND THAT IS NOT TIDINESS.
    # dh_open() only stat()s the fixture DIRECTORY (op_dio1.c:734) and then
    # OPENS the %N subfiles, so the files are what an ACL has to gate.  The
    # directories therefore keep Administrators throughout - which is what
    # lets this script walk and read them, and what lets cleanup delete them -
    # while ZZIDUSER's FILES grant the account alone.  A LocalSystem session
    # holds SYSTEM and Administrators, so it stats the directory happily and
    # is refused at %0, which is the discrimination this fixture is for.
    $sysAdmin  = @('SYSTEM:(OI)(CI)(F)', 'Administrators:(OI)(CI)(F)')
    $userRxDir = '{0}:(OI)(CI)(RX)' -f $Prefix
    $userRxFile = '{0}:(RX)' -f $Prefix
    $fixtures = @(
        [pscustomobject]@{ Name = 'ZZIDALLOW'; Dest = $allowDir; UserMayRead = $true
                           DirGrants  = $sysAdmin + @($userRxDir)
                           FileGrants = @('SYSTEM:(F)', 'Administrators:(F)', $userRxFile) },
        [pscustomobject]@{ Name = 'ZZIDDENY';  Dest = $denyDir;  UserMayRead = $false
                           DirGrants  = $sysAdmin
                           FileGrants = @('SYSTEM:(F)', 'Administrators:(F)') },
        [pscustomobject]@{ Name = 'ZZIDUSER';  Dest = $userDir;  UserMayRead = $true
                           DirGrants  = $sysAdmin + @($userRxDir)
                           FileGrants = @($userRxFile) })

    Step 2 'Building the three fixture directories (ACLs applied later)'
    foreach ($f in $fixtures) {
        New-Item -ItemType Directory -Force -Path $f.Dest | Out-Null
        Write-Host ("   $($f.Name): $($f.Dest)")
    }
    if (@(Get-ChildItem -LiteralPath $base -Directory).Count -ne $fixtures.Count) {
        Fail "expected $($fixtures.Count) fixture directories under $base - the fixture table was empty or did not apply."
    }

    # ---------------------------------------------------------------- 3
    Step 3 'Creating the fixtures, moving them out, and planting VOC pointers'
    $acct = $Prefix.ToUpper()

    # THE ACCOUNT DIRECTORY IS READ FROM THE REGISTER, NOT BUILT FROM $Prefix.
    # accounts/<name> is itself a directory-file record - LF-delimited text
    # whose field 1 is the account path, stored with FORWARD slashes and a
    # LOWER-CASE leaf (measured: "C:/ProgramData/SD/user_accounts/don").
    # Composing it by hand would bake in both a separator and a case guess,
    # and section 7 step 8 moved that case once already.
    $accPath = ((Get-Content -LiteralPath $accRec -TotalCount 1) -replace '/', '\').Trim()
    if (-not $accPath) { Fail "ACCOUNTS record $accRec has no field 1 - cannot locate the account directory." }
    if (-not (Test-Path -LiteralPath $accPath -PathType Container)) {
        Fail "ACCOUNTS field 1 names '$accPath', which is not a directory on disk."
    }
    Write-Host "   account directory, from the register: $accPath"

    # (a) Create all three PLAINLY - no PATHNAME keyword.  That is the b23
    # route and CREATEF stops on 6128 before adding @ID.  This is the code
    # path every fresh account already uses.  WHO brackets LOGTO so the raw
    # output says which account each command ran under.
    # Built from $fixtures so the command list cannot drift from the table.
    # ZZIDOWN IS THE OWNERSHIP PROBE AND IT IS A DIRECTORY FILE ON PURPOSE:
    # a directory file stores every record as a real file on disk, so the
    # OWNER of that file is the OS identity of whoever wrote it.  It stays in
    # the account directory - no move, no pointer - because the account
    # directory already grants sdu_<acct>, Administrators and SYSTEM, so the
    # write succeeds whichever identity the session turns out to have.  That
    # is deliberate: this probe must not test access at all.
    $wanted = $fixtures.Count + 2   # fixtures + ZZIDSRC scratch + ZZIDOWN probe
    $out = Invoke-SD (@('WHO', "LOGTO $acct", 'WHO') +
                      @($fixtures | ForEach-Object { "CREATE.FILE $($_.Name) DYNAMIC NO.QUERY" }) +
                      @('CREATE.FILE ZZIDSRC DIRECTORY NO.QUERY',
                        'CREATE.FILE ZZIDOWN DIRECTORY NO.QUERY', 'WHO'))
    Write-Host '   --- raw Invoke-SD output for Step 3a (create) ---'
    ($out -split "`r?`n") | ForEach-Object { Write-Host ('   | ' + $_) }
    Write-Host '   --- end raw output ---'

    $whos = Get-WhoAccounts $out
    Write-Host ('   accounts WHO reported (in order): ' + ($whos -join ', '))
    if ($whos.Count -lt 3) {
        Fail "Step 3a expected three WHO reports; got $($whos.Count).  Session state cannot be trusted."
    }
    if ($whos[1] -ne $acct -or $whos[2] -ne $acct) {
        Fail ("LOGTO $acct was not honoured.  WHO after LOGTO said '$($whos[1])', WHO after the creates said '$($whos[2])'.  " +
              'CREATE.FILE therefore wrote into the WRONG account.')
    }

    # SUCCESS ANCHOR IS 6129, NOT 6127, AND THAT IS THE b23 LESSON.  CREATEF
    # prints 6127 ("Created DATA part as") and writes the VOC entry BEFORE it
    # opens the new dictionary, so b23 saw 6127 twice on files that were
    # structurally broken and scored it a pass.  6129 ("Added default '@ID'
    # record to dictionary") is the LAST message on the happy path and is
    # reached only after the dictionary opened and @ID was written
    # (CREATEF:471-486).  Three files, so three of them.
    $ok = @([regex]::Matches($out, "(?im)^\s*Added default '@ID' record to dictionary")).Count
    if ($ok -lt $wanted) {
        Fail ("CREATE.FILE finished $ok of $wanted files (anchor: sysmsg 6129, the LAST message on the happy path).  " +
              'A file that printed 6127 but not 6129 stopped at 6128 and is structurally incomplete.')
    }
    # DISQUALIFIER control.  "Unable to" is here because 6128 is "Unable to
    # open newly created dictionary" - a STOP that lands AFTER the success
    # text, which is exactly what the count above would otherwise miss.
    $disqualifiers = @('Unable to', 'already exists', 'not in register', 'not found',
                       'does not exist', 'is not defined', 'not an F-type',
                       'Unexpected token')
    $hit = @($disqualifiers | Where-Object { $out -match [regex]::Escape($_) })
    if ($hit.Count -gt 0) {
        Fail ('Failure text appeared in Step 3a output: ' + ($hit -join ', ') + '.')
    }
    Write-Host "   confirmed: $wanted files created complete under $acct (6129 seen $wanted times, no stop text)"

    # (b) Move the two DH files out to the fixture directories.  A DH file
    # records no path of its own - the only pathname in DH_HEADER is akpath
    # (dh_fmt.h:146), the alternate-key directory, and CREATE.FILE builds no
    # indexes, so ak_map is 0 and akpath is empty.  The VOC pointer is
    # therefore the only thing that has to learn where the file went.
    foreach ($f in $fixtures) {
        foreach ($part in @($f.Name, ($f.Name + '.DIC'))) {
            $src = Join-Path $accPath $part
            if (-not (Test-Path -LiteralPath $src -PathType Container)) {
                Fail "CREATE.FILE reported success but '$src' is not on disk."
            }
            Move-Item -LiteralPath $src -Destination (Join-Path $f.Dest $part) -Force
        }
        # %0 IS WHAT MAKES IT A DH FILE AT OPEN TIME (op_dio1.c:767).  Assert
        # it survived the move: without it the fixture silently opens as a
        # DIRECTORY file, nothing is opened at all, and the deny half loses
        # its ability to deny - a false "impersonation does nothing".
        $bucket = Join-Path (Join-Path $f.Dest $f.Name) '%0'
        if (-not (Test-Path -LiteralPath $bucket)) {
            Fail ("$($f.Name) has no %0 subfile after the move.  It would open as a DIRECTORY file, " +
                  'which opens no file at all, so the ACL could never refuse it.')
        }
        Write-Host ("   moved $($f.Name) + .DIC to $($f.Dest), %0 present")
    }

    # (c) Write the VOC pointers into the scratch directory file as text.
    # LF ONLY, AND THIS IS THE TRAP.  op_dio3.c:1180 maps \n to a field mark
    # and never touches \r, and the record is opened O_BINARY
    # (dh_file.c:230), so a CRLF file gives field 1 "F\r" and field 2
    # "<path>\r" - a trailing CR on the pathname that fails later as "not
    # found" while CT VOC looks perfectly correct.  SD writes these files the
    # same way it reads them: sddefs.h:65 defines Newline as "\n".
    # Set-Content and Out-File both emit CRLF, so neither may be used, and
    # WriteAllBytes over ASCII is used rather than WriteAllText so no
    # encoding default can introduce a BOM either.
    $srcDir = Join-Path $accPath 'ZZIDSRC'
    if (-not (Test-Path -LiteralPath $srcDir -PathType Container)) {
        Fail "CREATE.FILE ZZIDSRC reported success but '$srcDir' is not on disk."
    }
    foreach ($f in $fixtures) {
        $recPath = Join-Path $srcDir $f.Name
        $rec = "F`n" + (Join-Path $f.Dest $f.Name) + "`n" + (Join-Path $f.Dest ($f.Name + '.DIC')) + "`n"
        [System.IO.File]::WriteAllBytes($recPath, [System.Text.Encoding]::ASCII.GetBytes($rec))

        # READ THE BYTES BACK.  A stray 13 is the CRLF trap above; a first
        # byte that is not 'F' (70) means a BOM or an encoding default got in
        # front of the type code.  Both would produce a VOC record that reads
        # correctly to the eye and does not work.
        $bytes = [System.IO.File]::ReadAllBytes($recPath)
        if ($bytes -contains 13) {
            Fail "$recPath contains a CR (13).  Field marks would carry a trailing CR - see the comment above."
        }
        if ($bytes[0] -ne 70) {
            Fail "$recPath starts with byte $($bytes[0]), not 'F' (70).  Something prefixed the type code."
        }
        Write-Host ("   wrote $($f.Name) pointer, $($bytes.Length) bytes, LF-only, first byte 'F'")
    }

    # (d) COPY carries them into VOC, mapping newlines to field marks because
    # exactly one side is a directory file (COPY:220-229).  OVERWRITING is
    # required, not optional: CREATE.FILE already put a ZZIDALLOW/ZZIDDENY
    # record in this VOC pointing at the pre-move location, and without the
    # keyword COPY reports 6193 and leaves the stale pointer in place.
    # The last COPY is the OWNERSHIP CONTROL: it writes a record into ZZIDOWN
    # from THIS session, which is the local elevated one.  Step 5 then writes
    # another from the API session.  Comparing the two owners is what turns
    # "the API record is owned by X" into evidence - if both come back the
    # same, ownership is not tracking the writer and the probe is void.
    $out2 = Invoke-SD (@('WHO', "LOGTO $acct", 'WHO') +
                       @($fixtures | ForEach-Object { "COPY FROM ZZIDSRC TO VOC $($_.Name) OVERWRITING" }) +
                       @($fixtures | ForEach-Object { "CT VOC $($_.Name)" }) +
                       @('COPY FROM ZZIDSRC TO ZZIDOWN ZZIDALLOW,ZZLOCAL OVERWRITING', 'WHO'))
    Write-Host '   --- raw Invoke-SD output for Step 3d (copy) ---'
    ($out2 -split "`r?`n") | ForEach-Object { Write-Host ('   | ' + $_) }
    Write-Host '   --- end raw output ---'

    $whos2 = Get-WhoAccounts $out2
    Write-Host ('   accounts WHO reported (in order): ' + ($whos2 -join ', '))
    if ($whos2.Count -lt 3) {
        Fail "Step 3d expected three WHO reports; got $($whos2.Count) ($($whos2 -join ', ')).  Session state cannot be trusted."
    }
    if ($whos2[1] -ne $acct -or $whos2[2] -ne $acct) {
        Fail ("LOGTO $acct was not honoured in Step 3d.  WHO after LOGTO said '$($whos2[1])', WHO after the copies said '$($whos2[2])'.  " +
              'COPY would have written into the wrong VOC.')
    }

    # SUCCESS anchor: sysmsg 6189 is "%1 record(s) copied." and COPY prints it
    # once per command WITH THE COUNT, so a copy that did nothing says
    # "0 record(s) copied." and cannot match this.
    $copied = @([regex]::Matches($out2, '(?im)^\s*1 record\(s\) copied')).Count
    if ($copied -lt ($fixtures.Count + 1)) {
        Fail ("COPY reported '1 record(s) copied' $copied time(s), expected $($fixtures.Count + 1) " +
              '(one per VOC pointer, plus the ZZLOCAL ownership control).  ' +
              'A "0 record(s) copied" line means the source record was not found in ZZIDSRC.')
    }
    $hit2 = @(@('Null source', 'Null target', 'not copied', 'Error ', 'Unable to') |
              Where-Object { $out2 -match [regex]::Escape($_) })
    if ($hit2.Count -gt 0) {
        Fail ('Failure text appeared in Step 3d output: ' + ($hit2 -join ', ') + '.')
    }

    # AND THE POINTER MUST NAME THE NEW LOCATION.  CT echoes only "CT VOC
    # ZZIDALLOW", which does not contain the fixture path, so the path
    # appearing at all means CT printed the RECORD - it cannot be the echo.
    # Newlines are collapsed first because CT wraps a long field.
    $flat = ($out2 -replace "`r?`n", '')
    foreach ($f in $fixtures) {
        $want = Join-Path $f.Dest $f.Name
        if ($flat -notmatch [regex]::Escape($want)) {
            Fail ("CT VOC $($f.Name) does not show '$want'.  The VOC pointer still names the pre-move " +
                  'location, so the API session would open the wrong file or none at all.')
        }
    }
    Write-Host '   confirmed: both VOC pointers copied and naming the fixture directories'

    # ---------------------------------------------------------------- 4
    # THE THIRD FIXTURE IS WHAT MAKES THIS A DIAGNOSIS AND NOT JUST A VERDICT.
    # LocalSystem's token carries BUILTIN\Administrators as well as SYSTEM, so
    # ALLOW and DENY between them cannot say WHO the session is - both grant
    # SYSTEM, so both open for a session that never left LocalSystem.  ZZIDUSER
    # grants the account and NOTHING ELSE - no SYSTEM, no Administrators - so
    # it is the one fixture only the real user can open:
    #
    #   fixture    grants                          user   LocalSystem
    #   ZZIDALLOW  SYSTEM, Administrators, user    opens  opens
    #   ZZIDDENY   SYSTEM, Administrators          REFUSED  opens
    #   ZZIDUSER   user only                       opens  REFUSED
    #
    # So DENY answers "is the session contained?" and USER answers "is the
    # session the user?", and the pair separates "impersonation never took"
    # from "impersonation took but the open ignores it".
    #
    # ACLs come AFTER the move so they reach the bucket files, and /T is what
    # carries them there.  /inheritance:r FIRST, or the inherited sdusers:(M)
    # from C:\ProgramData\SD grants read and DENY does not deny.
    Step 4 'Setting the fixture ACLs and reading every one of them back'

    # GRANT FIRST, STRIP INHERITANCE SECOND.  THE OTHER ORDER SILENTLY LEAVES
    # THE CHILDREN UNTOUCHED, AND IT IS WHAT MADE RUN b25 LOOK LIKE A PRODUCT
    # FINDING.  /inheritance:r removes every inherited ACE, and these fixture
    # directories had nothing else - so it left an EMPTY DACL, and icacls then
    # could not walk into the directory it had just emptied.  It reported
    # "<path>\*: Access is denied" and carried on with exit 0 for the item it
    # HAD done, so the failure was invisible.  The children kept their stale
    # inherited ACEs from C:\ProgramData\SD - including sdusers:(OI)(CI)(M),
    # which the API account is a member of - while the DIRECTORY read back
    # perfectly clean.  Measured 24 Aug 2026 with two scratch probes:
    # owner-implicit rights DO cover READ_CONTROL on such an object, but they
    # do NOT cover FILE_TRAVERSE through it, which is the whole mechanism.
    #
    # Granting first means the explicit ACE is already in place when
    # /inheritance:r drops the inherited ones, so access is never lost and the
    # walk completes.
    foreach ($f in $fixtures) {
        $root  = Join-Path $f.Dest $f.Name
        $files = @(Get-ChildItem -LiteralPath $root -Recurse -Force -File |
                   ForEach-Object { $_.FullName })
        $f | Add-Member -NotePropertyName Files -NotePropertyValue $files -Force
        if ($files.Count -eq 0) {
            Fail "$($f.Name) has no files under '$root' - there is nothing for an ACL to gate."
        }

        Set-FixtureAcl $f.Dest ($f.DirGrants) $true  "$($f.Name) directories"
        foreach ($file in $files) {
            Set-FixtureAcl $file ($f.FileGrants) $false "$($f.Name) $(Split-Path -Leaf $file)"
        }
        Write-Host ("   $($f.Name): dirs [" + ($f.DirGrants -join ' ') +
                    "]  files [" + ($f.FileGrants -join ' ') + "]")
    }

    # READ THE DACLs BACK, BECAUSE OTHERWISE STEP 5 CONFLATES TWO FAULTS.
    # If DENY opens, that is either impersonation doing nothing (the finding
    # this verifier exists to report) or the deny ACL never having applied (a
    # fixture fault).  Those must not be indistinguishable, and icacls exit
    # codes do not separate them - it reports success for a /grant whose
    # effect is then undone by an inherited ACE.
    #
    # MOVING A DIRECTORY WITHIN ONE VOLUME CARRIES ITS OLD ACEs, so this is
    # not a formality: the fixtures were created inside the account tree,
    # under sdu_<acct>:(M), and Windows does not re-evaluate inheritance on a
    # rename.  /inheritance:r is what removes them and this is what proves it.
    # CHECK %0, NOT JUST THE DIRECTORY, AND THAT DISTINCTION IS THE WHOLE
    # POINT.  op_dio1.c:767 stats the directory but dh_open() opens the
    # SUBFILES, so %0 is the object whose DACL decides the answer.  These
    # fixtures were created inside the account tree, under sdu_<acct>:(M),
    # and MOVING WITHIN ONE VOLUME CARRIES THE OLD ACEs - so a stale grant
    # surviving on %0 while the directory looks clean would let DENY open on
    # a build where impersonation works perfectly, and be reported as a
    # product finding.  Every object in the tree is checked.
    foreach ($f in $fixtures) {
        # THE FILES ARE WHAT IS ASSERTED, because the files are what dh_open()
        # opens.  b25 asserted the DIRECTORY and passed while %0 - the object
        # that decides the answer - still carried an inherited sdusers grant.
        $bucketSeen = $false
        # Derived, not declared, so it cannot drift from the grants above.
        $svcDenied = -not (@($f.FileGrants) -match 'SYSTEM|Administrators')

        foreach ($o in $f.Files) {
            if ((Split-Path -Leaf $o) -eq '%0') { $bucketSeen = $true }

            # NAME THE OBJECT BEFORE READING IT.  b26 died here with a bare
            # "Get-Acl : Access is denied" that did not say which of nine
            # objects it was on, which is what made the cause guesswork.
            $names = $null
            try { $names = @((Get-Acl -LiteralPath $o).Access |
                             ForEach-Object { $_.IdentityReference.Value }) }
            catch {
                Fail ("could not read the DACL of '$o' ($($_.Exception.GetType().Name)).  " +
                      'The fixture ACLs are not what this script intended, so nothing below is measurable.')
            }
            Write-Host ("   $(Split-Path -Leaf $o) [$($f.Name)]: " + ($names -join '; '))

            $userGrant = @($names | Where-Object {
                $_ -match "\\$Prefix$" -or $_ -match '\\sdusers$' -or $_ -match "\\sdu_$Prefix$" })
            $svcGrant  = @($names | Where-Object {
                $_ -match 'NT AUTHORITY\\SYSTEM$' -or $_ -match '\\Administrators$' })

            if ($f.UserMayRead -and $userGrant.Count -eq 0) {
                Fail ("$($f.Name) must be readable by $Prefix, but '$o' grants it nothing.  " +
                      'Step 5 would report a refusal that means nothing.')
            }
            if (-not $f.UserMayRead -and $userGrant.Count -gt 0) {
                Fail ("$($f.Name) must grant $Prefix nothing, but '$o' carries $($userGrant -join ', ').  " +
                      'It would open for a legitimate reason and be misread as impersonation failing.')
            }
            if ($svcDenied -and $svcGrant.Count -gt 0) {
                Fail ("$($f.Name) is the identity probe and must grant no service principal, but '$o' " +
                      "carries $($svcGrant -join ', ').  A LocalSystem session holds both, so it would " +
                      'open and the probe would prove nothing.')
            }
        }

        # REFUSE THE NULL CASE OUT LOUD.  A tree with no %0 would pass every
        # assertion above by having nothing to assert on.
        if (-not $bucketSeen) {
            Fail "$($f.Name) has no %0 among the $($f.Files.Count) file(s) checked - the assertions above checked nothing that gets opened."
        }
        Write-Host ("   $($f.Name): $($f.Files.Count) file(s) incl. %0 - " +
                    $(if ($f.UserMayRead) { "$Prefix granted" } else { "$Prefix granted nothing" }) +
                    $(if ($svcDenied) { ', no service principal' } else { '' }))
    }

    # ---------------------------------------------------------------- 5
    Step 5 'Opening the fixtures, then asking the session who it is'
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

        # SCRAM authenticates the user; ATTACHING to an account is a separate,
        # required step.  sdclilib.c:1241 does exactly this after login:
        #     message_pair(SrvrAccount, account, strlen(account))
        # verify-scramlogin never opens a file, so it does not attach; copying
        # only its login left the session with NO account VOC, and every
        # vb.open of ZZID* came back ER_NVR (3007) - the b19 VOID.  Without
        # this attach the whole run measures nothing.
        $acctName = $Prefix.ToUpper()
        $acctPayload = [Text.Encoding]::ASCII.GetBytes($acctName)
        Send-SdPacket $conn $SrvrAccount $acctPayload
        $acctReply = Receive-SdPacket $conn
        if ($acctReply.ServerError -ne 0) {
            Write-Host ('   server said: ' + $acctReply.Text)
            Fail ("SrvrAccount attach to $acctName failed - server error " +
                  "$($acctReply.ServerError), status $($acctReply.Status).  " +
                  'Without the attach the session has no account VOC and no ' +
                  'open below could succeed - so nothing here is a result.')
        }
        Write-Host "   attached to account $acctName"

        $opened = @{}
        foreach ($f in $fixtures) {
            $r = Test-ApiOpen $conn $f.Name
            $opened[$f.Name] = $r
            Write-Host ("   {0,-9} opened={1}  serverError={2}  status={3}" -f
                        $f.Name, $r.Opened, $r.ServerError, $r.Status)
            if ($r.Text -and -not $r.Opened) { Write-Host ("     reply: " + $r.Text.Trim()) }
        }

        # THE NULL-CASE GUARD.  Without the allow fixture opening, a refusal on
        # deny says nothing at all.
        if (-not $opened['ZZIDALLOW'].Opened) {
            $script:void = $true
            Write-Host ''
            Write-Host '*** VOID: the ALLOW fixture did not open either. ***' -ForegroundColor Yellow
            Write-Host '    The VOC pointer, the path or the fixture is wrong, so the refusal'
            Write-Host '    on DENY proves nothing.  Nothing here is a result.'
        } else {
            # NOT DECISIVE, AND RUN b27 IS WHY.  All three of these opened on
            # a run whose fixture ACLs were verified correct at %0 - which no
            # single token can do, since ZZIDDENY grants the account nothing
            # and ZZIDUSER grants nothing else.  So the DACL was not what
            # gated them: a LocalSystem session holds SeBackupPrivilege, which
            # bypasses DACLs outright.  These rows are kept because they are
            # real readings and their pattern is diagnostic, but the identity
            # question is settled by ownership below, not here.
            Note 'ALLOW fixture opens over the API'      $true  $opened['ZZIDALLOW'].Opened $false
            Note 'DENY fixture is REFUSED over the API'  $false $opened['ZZIDDENY'].Opened  $false
            Note 'USER-ONLY fixture opens over the API'  $true  $opened['ZZIDUSER'].Opened  $false
        }

        # ------------------------------------------------------------- 5b
        # THE OWNERSHIP PROBE - THE MEASUREMENT THIS VERIFIER IS ACTUALLY FOR.
        #
        # Every ACL fixture above asks "what may this session READ", and that
        # question cannot be answered while the session may hold a privilege
        # that bypasses the answer.  Ownership is not bypassable in the same
        # way: SeBackupPrivilege lets a token open a file it has no ACE on, it
        # does not change whose name goes on a file the token CREATES.  A
        # directory-type file stores each record as a real file, so writing
        # one and reading its owner asks the session, directly, who it is.
        Write-Host ''
        Write-Host '   -- ownership probe --'
        $ownDir   = Join-Path $accPath 'ZZIDOWN'
        $localRec = Join-Path $ownDir 'ZZLOCAL'
        $apiRec   = Join-Path $ownDir 'ZZAPI'

        if (-not (Test-Path -LiteralPath $localRec)) {
            $script:void = $true
            Write-Host "*** VOID: the local control record '$localRec' is absent." -ForegroundColor Yellow
            Write-Host '    The Step 3d COPY did not produce a file, so there is nothing to compare against.'
        } else {
            $own = Test-ApiOpen $conn 'ZZIDOWN'
            if (-not $own.Opened) {
                $script:void = $true
                Write-Host "*** VOID: the API session could not open ZZIDOWN (serverError $($own.ServerError))." -ForegroundColor Yellow
            } else {
                $w = Invoke-ApiWrite $conn $own.FileNo 'ZZAPI' 'written by the API session'
                if (-not $w.Written) {
                    $script:void = $true
                    Write-Host "*** VOID: vb.write was refused (serverError $($w.ServerError), status $($w.Status))." -ForegroundColor Yellow
                    if ($w.Text) { Write-Host ('    server said: ' + $w.Text.Trim()) }
                } elseif (-not (Test-Path -LiteralPath $apiRec)) {
                    # REFUSE THE NULL CASE.  vb.write reporting success without
                    # a file on disk would make every owner reading below a
                    # statement about a file that does not exist.
                    $script:void = $true
                    Write-Host "*** VOID: vb.write reported success but '$apiRec' is not on disk." -ForegroundColor Yellow
                } else {
                    $localOwner = (Get-Acl -LiteralPath $localRec).Owner
                    $apiOwner   = (Get-Acl -LiteralPath $apiRec).Owner
                    Write-Host "   ZZLOCAL (written by the local elevated session): $localOwner"
                    Write-Host "   ZZAPI   (written by the API session)           : $apiOwner"

                    # THE CONTROL.  If both records carry the same owner then
                    # ownership is not tracking the writing session at all -
                    # every SD-created file might simply be owned by whoever
                    # owns the tree - and the API reading proves nothing.
                    if ($localOwner -eq $apiOwner) {
                        $script:void = $true
                        Write-Host '*** VOID: both records have the SAME owner, so ownership does not' -ForegroundColor Yellow
                        Write-Host '    track the writing session and the API reading is not evidence.'
                    } else {
                        Note 'the API session writes as the authenticated user' `
                             $true ($apiOwner -match "\\$Prefix$")
                    }
                }
            }
        }
    } finally {
        if ($conn) { try { Send-SdPacket $conn $SrvrQuit @() } catch { }; Close-SdConnection $conn }
    }
}
finally {
    if (-not $Keep) {
        Step 9 'Cleaning up'
        if ($made) {
            # 24 Aug 26 - TWO FAULTS IN TWO LINES, AND THE SECOND HID THE FIRST.
            #
            # DELETE.ACCOUNT TAKES THE ACCOUNT NAME AND NOTHING ELSE.  This
            # passed "<name> USER", mirroring CREATE.ACCOUNT's leading type
            # keyword onto a verb that has none, and DELACC:103 rejects it as
            # an unexpected token (sysmsg 2018) BEFORE deleting anything.
            #
            # And the announcement below was unconditional - it read neither
            # $out nor the resulting state - so every run from b18 to b32 said
            # "account removed" and left its Windows account, its SD account
            # record and its user profile behind.  That is the backlog
            # clean-test-profiles.ps1 keeps being asked to clear.
            #
            # ANCHOR ON THE STATE, NOT ON THE VERB'S OUTPUT.  "Removed" is a
            # claim about what is gone, so it is answered by looking, and the
            # raw output is printed whenever the claim fails.
            # 26 Aug 26 - THE 24 Aug FIX MADE THIS TELL THE TRUTH AND DID NOT
            # STOP THE LEAK.  THE WARNING WAS PRINTED EVERY RUN AND NOBODY READ
            # IT.  Run b43's transcript, section [9]:
            #
            #     :DELETE.ACCOUNT SDAPIIDB43 Y
            #     Unexpected token (Y)
            #
            # THE CONFIRMATION WAS ON THE COMMAND LINE, and DELACC:104 rejects
            # a further token with sysmsg 2018 before deleting anything - the
            # SAME sysmsg, and the same "an extra word became an argument"
            # shape, that the 24 Aug note above describes for "USER".  The verb
            # did nothing: SD account record, Windows user, sdu_ group and
            # profile all survived, every run from b33 to b43.
            #
            # THE CAUSE IS POWERSHELL PRECEDENCE, NOT SD.  This read
            #
            #     Invoke-SD @("DELETE.ACCOUNT " + $Prefix.ToUpper(), 'Y')
            #
            # and "A + B, C" parses as "A + (B, C)".  So the 'Y' never was a
            # second element: it joined the ARRAY $Prefix.ToUpper(), 'Y', which
            # a string + array then flattened with $OFS - one space - into the
            # single line "DELETE.ACCOUNT SDAPIIDB43 Y".  Measured, not
            # inferred: the expression as written returns .Count = 1.
            #
            # THE INTERPOLATED FORM HAS NO + AND NO PRECEDENCE TO GET WRONG,
            # and it is what verify-apiadmin.ps1:682 has always used - which is
            # why sdapia accounts leave nothing behind and sdapiid left EIGHT.
            # b43's apiadmin transcript is the control: "Delete account
            # SDAPIAB43, its directory and its Windows account sdapiab43
            # (Y/N)? Y" then "Group: sdu_sdapiab43 Deleted", "OS User:
            # sdapiab43 Deleted".  DELETE.ACCOUNT removes the Windows account
            # and its profile (DELACC:46, :308-345) - it was never the verb.
            $cmd = "DELETE.ACCOUNT " + $Prefix.ToUpper()
            $lines = @($cmd, 'Y')
            # REFUSE TO SEND WHAT WE DID NOT MEAN TO SEND.  This is the guard
            # the fault itself asks for: the bug was a two-line sequence that
            # silently became one, so assert the count before it goes anywhere.
            # Cheap, and it fails loudly instead of leaving an account behind.
            if ($lines.Count -ne 2) {
                Write-Host ("   INTERNAL: the DELETE.ACCOUNT sequence collapsed to {0} line(s) - not sent." -f $lines.Count) -ForegroundColor Red
                $out = '*** not sent - the command sequence was malformed'
            } else {
                Write-Host ("   sending: [0] <{0}>  [1] <{1}>" -f $lines[0], $lines[1])
                $out = Invoke-SD $lines
            }

            # A NET UNDER THE VERB, NOT A REPLACEMENT FOR IT.  On the happy path
            # DELETE.ACCOUNT has already taken the Windows user, its sdu_ group
            # and its profile, and both blocks below find nothing and say
            # nothing.  They exist because this teardown runs in a finally: it
            # has to cope with the run that got here after SD became
            # unreachable, or after DELETE.ACCOUNT refused for a reason nobody
            # has met yet.  EIGHT accounts accumulated the last time the only
            # cleanup path was one SD command that had quietly stopped working.
            #
            # Guarded rather than blind: Remove-LocalUser on a name that is not
            # there is an error, and an error thrown in a finally would replace
            # the verdict with a stack trace.
            if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
                try {
                    Remove-LocalUser -Name $Prefix -ErrorAction Stop
                    Write-Host "   cleanup: removed Windows user $Prefix"
                } catch {
                    Write-Host ("   cleanup: could NOT remove Windows user {0} - {1}" -f $Prefix, $_.Exception.Message) -ForegroundColor Yellow
                }
            }
            $sdu = 'sdu_' + $Prefix
            if (Get-LocalGroup -Name $sdu -ErrorAction SilentlyContinue) {
                try {
                    Remove-LocalGroup -Name $sdu -ErrorAction Stop
                    Write-Host "   cleanup: removed group $sdu"
                } catch {
                    Write-Host ("   cleanup: could NOT remove group {0} - {1}" -f $sdu, $_.Exception.Message) -ForegroundColor Yellow
                }
            }

            $rec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper())
            $stillReg = Test-Path -LiteralPath $rec
            $stillWin = $null -ne (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue)
            $stillGrp = $null -ne (Get-LocalGroup -Name $sdu -ErrorAction SilentlyContinue)
            if ($stillReg -or $stillWin -or $stillGrp) {
                # 26 Aug 26 - AND THE VERDICT HAS TO CARRY IT.  This warning was
                # printed on every run from b33 to b43 and read by nobody,
                # because the closing line underneath it said PASSED and the
                # exit code was 0.  A cleanup failure is not a product failure
                # and must not gate the exit code - but the closing sentence
                # can stop claiming a clean run, which is item 5's SKIP rule
                # applied to litter instead of to a skipped check.
                $script:leftLitter = "$Prefix (register:$stillReg user:$stillWin group:$stillGrp)"
                Write-Host "   WARNING: $Prefix was NOT fully removed." -ForegroundColor Yellow
                Write-Host ("     SD account record present: {0}    Windows user present: {1}    group {2} present: {3}" -f $stillReg, $stillWin, $sdu, $stillGrp)
                Write-Host '     --- what DELETE.ACCOUNT actually said ---'
                @($out) | ForEach-Object { Write-Host "     | $_" }
                Write-Host '     Remove the Windows user by hand; clean-test-profiles.ps1 REFUSES'
                Write-Host '     a profile whose account still exists, so it cannot clear this for you.'
            } else {
                Write-Host "   account $Prefix removed - SD record, Windows user and $sdu all gone"
            }
        }
        if (Test-Path -LiteralPath $base) {
            # The fixture DIRECTORIES keep Administrators, so the tree walks;
            # ZZIDUSER's FILES do not, and deleting those relies on
            # FILE_DELETE_CHILD from the parent.  Administrators is put back on
            # each file by name first so the removal does not depend on that.
            # Guarded: a failure before Step 4 leaves no file list.
            foreach ($f in @($fixtures | Where-Object { $_ -and $_.Files })) {
                foreach ($o in $f.Files) {
                    $null = Invoke-Icacls $o /grant 'Administrators:(F)' /C
                }
            }
            $null = Invoke-Icacls $base /reset /T /C
            Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
            if (Test-Path -LiteralPath $base) {
                Write-Host "   WARNING: $base could not be fully removed - remove it by hand." -ForegroundColor Yellow
            } else {
                Write-Host "   fixtures removed"
            }
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

# ONLY DECISIVE ROWS DECIDE THE EXIT CODE.  The three ACL fixture rows are
# marked non-decisive since run b27: all three opened against ACLs verified
# correct at %0, which no single token can do, so the DACL was not what gated
# them - a LocalSystem session holds SeBackupPrivilege and bypasses DACLs.
# Letting those rows set the exit code would report a failure whose cause is
# the instrument.  They are still printed, because their pattern is a reading.
$softFailed = @($script:checks | Where-Object { $_.Result -eq 'FAIL' -and $_.Decisive -eq 'no' })
$failed     = @($script:checks | Where-Object { $_.Result -eq 'FAIL' -and $_.Decisive -eq 'yes' })

if ($softFailed.Count -gt 0) {
    Write-Host "  note: $($softFailed.Count) non-decisive check(s) did not hold - see the Decisive column."
    Write-Host '  Those are ACL-based and cannot gate a token holding SeBackupPrivilege;'
    Write-Host '  the ownership probe is what answers the identity question.'
}
if ($failed.Count -gt 0) {
    Write-Host "verify-apiidentity: FAILED - $($failed.Count) decisive check(s)." -ForegroundColor Red
    Write-Host '  The API session wrote a record owned by somebody other than the'
    Write-Host '  authenticated user: step 14 logs in as the user and does not BECOME'
    Write-Host '  the user.  That is a product finding, not a test fault.'
    exit 1
}
if ($script:leftLitter) {
    Write-Host 'verify-apiidentity: PASSED - the API session writes as the authenticated user.'
    Write-Host ("  BUT IT LEFT LITTER: {0}" -f $script:leftLitter) -ForegroundColor Yellow
    Write-Host '  The measurement stands; the cleanup did not finish.  Read section [9]'
    Write-Host '  above for what DELETE.ACCOUNT said, and clear it before reusing the prefix.'
    exit 0
}
Write-Host 'verify-apiidentity: PASSED - the API session writes as the authenticated user, and cleaned up after itself.'
exit 0
