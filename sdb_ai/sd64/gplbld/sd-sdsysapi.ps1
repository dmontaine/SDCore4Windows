# sd-sdsysapi.ps1 - the Windows half of REMOTE.SDSYS API: may SDSYS use the API from other computers, and from where.
#
#   ... -Action on -Entries '192.168.1.0/24','10.0.0.5'     the listed addresses and ranges (at most 32)
#   ... -Action on -Entries 'any'                           every address (only alone)
#   ... -Action off                                         shut, as delivered
#   ... -Action status                                      what it is now; nothing changes
#   [-Dir <directory>] [-DryRun]                            for the unit test only (test-sdsysapi-units.py); REMOTESDSYS never passes them
#
# Run by SD through !ps_script_out, from gpl.bp REMOTESDSYS, as SDSYS's ELEVATED helper (the verb is the administrator's).  Carried
# 16 Nov 2026 from Linux's "sd-elevate sdsys-api" (S.256, Linux 3f8d2fa2; Windows RELEASE_1.1 331).  The rules are Linux's:
#
#   SHUT AS DELIVERED: no file.  "on" REPLACES the list.  Each entry is an IPv4 or IPv6 address or a range in CIDR form, checked and put in
#   standard form as Linux's python3 ipaddress.ip_network(entry, strict=False) does: the host bits cleared, an exact address /32 or /128, an
#   IPv4 mask given as a netmask (255.255.255.0) or a hostmask (0.0.0.255) turned into its length, IPv6 in its short form (RFC 5952, lower
#   case), a repeated entry kept once.  A /0 range is REFUSED: it is every address, and the owner chose listed ones; the word any, alone,
#   is the one way to admit every address (owner, 16 Nov 2026: "Yes, as an explicit word").  IPv4 is strict: four decimal parts, 0 to 255,
#   no leading zero (Python's rule since 3.9.5, so 010.0.0.1 is not read as octal or as 10.0.0.1).
#   THE FILE is <ProgramData>\SD\sd-tls\sdsys-api: "on", then one entry a line, ASCII, LF.  APISRVR reads it (OPENSEQ, as LocalSystem) for
#   every SCRAM login as sdsys and treats anything but a first line "on" as off.  The directory is the one the installer's secure-tls.ps1
#   makes SYSTEM and Administrators only, and the TLS relay refuses every API connection while it is in any other state (win32tls.c), so a
#   file there cannot have been put there by anyone but an administrator.  This script never makes the directory: its parent grants sdusers
#   Modify, so the install is the one moment it can be made with no window for an SD user to make it first.  Neither it nor the file may be
#   a link.  The write is a new file beside it (a fresh random name, created new), then File.Replace or Move: one step, never half a list.
#   "off" deletes the file.
#
# Windows deviations from Linux, both forced: PowerShell rather than bash and python3 (no Python on the target); and the place, which is
# Linux's /etc/sdcore/sdsys-api (root 0600) in the Windows form above.
#
# Output: Linux's lines, word for word - "sdsys over the API from other computers: on, from <entries>" or "...: off"; a refusal names the
# entry ("not an address or a range: X", "a /0 range is every address, and is refused: X") and ends "sdsys-api on: nothing was changed".
# Exit 0 done, 1 refused (an entry, the count), 2 could not run (not elevated, no directory, a link, a write that failed).
#
# START-HISTORY:
# 16 Nov 26 Windows port - written for RELEASE_1.1 331 (Linux S.256).
# END-HISTORY

param(
    [ValidateSet('on', 'off', 'status')]
    [string]$Action = 'status',
    [string[]]$Entries = @(),
    [string]$Dir = '',
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$Prog = 'sd-sdsysapi'

# REMOTESDSYS calls this in-process ("& '...\sd-sdsysapi.ps1' -Action on -Entries 'a','b'"), so -Entries is an array; through
# "powershell -File" the same list arrives as ONE string "a,b".  An address never holds a comma, so splitting on it reads both alike.
$Entries = @($Entries | ForEach-Object { $_ -split ',' } | Where-Object { $_ -ne '' })

# Straight to the process's standard output, not the pipeline: Refuse is called from inside ConvertTo-Network, whose pipeline output is its
# return value, so a Write-Output there would be folded into $n and never printed (the PowerShell function output trap, remote-admin.ps1's Out-Line).
function Say([string]$t) { [Console]::Out.WriteLine($t) }
function Refuse([string]$t) { Say $t; Say 'sdsys-api on: nothing was changed'; exit 1 }
function Fail([string]$t) { Say ("${Prog}: " + $t); exit 2 }

# ---------------------------------------------------------------- the address rules (Python's ipaddress, strict=False)

# A string of '0'/'1' for some bytes, eight a byte.
function Get-Bits([byte[]]$b) {
    $s = ''
    foreach ($x in $b) { $s += [Convert]::ToString([int]$x, 2).PadLeft(8, '0') }
    return $s
}

# The bytes for a string of bits whose length is a multiple of eight.
function Get-BytesFromBits([string]$s) {
    $n = $s.Length / 8
    $b = New-Object byte[] $n
    for ($i = 0; $i -lt $n; $i++) { $b[$i] = [Convert]::ToByte($s.Substring($i * 8, 8), 2) }
    return , $b
}

# Strict IPv4: four decimal parts of one to three digits, 0 to 255, no leading zero.  The bytes, or $null.
function ConvertFrom-V4([string]$s) {
    $p = $s.Split('.')
    if ($p.Count -ne 4) { return $null }
    $b = New-Object byte[] 4
    for ($i = 0; $i -lt 4; $i++) {
        $g = $p[$i]
        if ($g -notmatch '^[0-9]{1,3}$') { return $null }
        if ($g.Length -gt 1 -and $g[0] -eq '0') { return $null }
        $v = [int]$g
        if ($v -gt 255) { return $null }
        $b[$i] = [byte]$v
    }
    return , $b
}

# IPv6: what .NET reads as an IPv6 address, from hex digits, ':' and '.' only (no zone, no brackets).  The 16 bytes, or $null.
function ConvertFrom-V6([string]$s) {
    if ($s -notmatch '^[0-9a-fA-F:.]+$') { return $null }
    $ip = $null
    if (-not [System.Net.IPAddress]::TryParse($s, [ref]$ip)) { return $null }
    if ($ip.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetworkV6) { return $null }
    return , ($ip.GetAddressBytes())
}

# IPv6 text in RFC 5952's short form, as Python writes it: lower-case hex groups without leading zeros, the longest run of two or more zero
# groups (the first, if two are as long) written as '::'.
function Format-V6([byte[]]$b) {
    $h = @()
    for ($i = 0; $i -lt 8; $i++) { $h += ('{0:x}' -f ([int]$b[2 * $i] * 256 + [int]$b[2 * $i + 1])) }
    $bestAt = -1; $bestLen = 0; $at = -1; $len = 0
    for ($i = 0; $i -lt 8; $i++) {
        if ($h[$i] -eq '0') {
            if ($at -lt 0) { $at = $i; $len = 0 }
            $len++
            if ($len -gt $bestLen) { $bestAt = $at; $bestLen = $len }
        } else {
            $at = -1; $len = 0
        }
    }
    if ($bestLen -lt 2) { return ($h -join ':') }
    $left = ''
    $right = ''
    if ($bestAt -gt 0) { $left = ($h[0..($bestAt - 1)] -join ':') }
    if ($bestAt + $bestLen -lt 8) { $right = ($h[($bestAt + $bestLen)..7] -join ':') }
    return ($left + '::' + $right)
}

# One entry in standard form, or a refusal (exit 1).
function ConvertTo-Network([string]$e) {
    $parts = $e.Split('/')
    if ($parts.Count -gt 2 -or $parts[0] -eq '') { Refuse ('not an address or a range: ' + $e) }
    $v6 = $parts[0].Contains(':')
    if ($v6) { $addr = ConvertFrom-V6 $parts[0] } else { $addr = ConvertFrom-V4 $parts[0] }
    if ($null -eq $addr) { Refuse ('not an address or a range: ' + $e) }
    $width = $addr.Length * 8
    $plen = $width
    if ($parts.Count -eq 2) {
        $p = $parts[1]
        if ($p -match '^[0-9]+$') {
            $t = $p.TrimStart('0')
            if ($t -eq '') { $plen = 0 }
            elseif ($t.Length -gt 3) { Refuse ('not an address or a range: ' + $e) }
            else { $plen = [int]$t }
            if ($plen -gt $width) { Refuse ('not an address or a range: ' + $e) }
        } elseif (-not $v6) {
            # A mask, as Python reads one for IPv4: a netmask (ones, then zeros) first, then a hostmask (zeros, then ones).
            $m = ConvertFrom-V4 $p
            if ($null -eq $m) { Refuse ('not an address or a range: ' + $e) }
            $mb = Get-Bits $m
            if ($mb -match '^1*0*$') { $plen = ($mb -replace '0', '').Length }
            elseif ($mb -match '^0*1*$') { $plen = ($mb -replace '1', '').Length }
            else { Refuse ('not an address or a range: ' + $e) }
        } else {
            Refuse ('not an address or a range: ' + $e)
        }
    }
    if ($plen -eq 0) { Refuse ('a /0 range is every address, and is refused: ' + $e) }
    $bits = Get-Bits $addr
    $net = Get-BytesFromBits ($bits.Substring(0, $plen) + ('0' * ($width - $plen)))
    if ($v6) { $text = Format-V6 $net } else { $text = ($net -join '.') }
    return ($text + '/' + $plen)
}

# ---------------------------------------------------------------- the place

if ($Dir -ne '') {
    $SetDir = $Dir
} else {
    $SetDir = Join-Path (Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD') 'sd-tls'
    if (-not $DryRun) {
        $me = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
        if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
            Fail 'this needs an elevated administrator (SDSYS at its console); nothing was changed'
        }
    }
}
$SetFile = Join-Path $SetDir 'sdsys-api'

function Assert-Place {
    if (-not (Test-Path -LiteralPath $SetDir -PathType Container)) {
        Fail ("$SetDir is missing; the installer makes it (secure-tls.ps1).  Nothing was changed")
    }
    if ((Get-Item -LiteralPath $SetDir -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
        Fail ("$SetDir is a link: refused.  Nothing was changed")
    }
    if (Test-Path -LiteralPath $SetFile) {
        if ((Get-Item -LiteralPath $SetFile -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) {
            Fail ("$SetFile is a link: refused.  Nothing was changed")
        }
    }
}

# ---------------------------------------------------------------- the actions

switch ($Action) {
    'status' {
        if ($DryRun) { Say ("${Prog}: would report $SetFile"); exit 0 }
        Assert-Place
        $state = 'off'
        if (Test-Path -LiteralPath $SetFile -PathType Leaf) {
            try {
                $lines = @([IO.File]::ReadAllText($SetFile, [Text.Encoding]::ASCII) -split "`r?`n")
            } catch {
                Fail ("cannot read ${SetFile}: " + $_.Exception.Message)
            }
            if ($lines.Count -ge 1 -and $lines[0].Trim() -ceq 'on') {
                $list = @($lines | Select-Object -Skip 1 | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
                $state = 'on, from ' + ($list -join ' ')
            }
        }
        Say ('sdsys over the API from other computers: ' + $state)
        exit 0
    }
    'off' {
        if ($Entries.Count -ne 0) { Say 'sdsys-api off takes no address; nothing was changed'; exit 1 }
        if ($DryRun) { Say ("${Prog}: would remove $SetFile"); exit 0 }
        Assert-Place
        try {
            if (Test-Path -LiteralPath $SetFile) { Remove-Item -LiteralPath $SetFile -Force }
        } catch {
            Fail ("could not remove ${SetFile}: " + $_.Exception.Message)
        }
        Say 'sdsys over the API from other computers: off'
        exit 0
    }
    'on' {
        if ($Entries.Count -lt 1 -or $Entries.Count -gt 32) { Refuse 'sdsys-api on takes one to 32 addresses or ranges, or the word any alone' }
        $norm = @()
        if ($Entries[0] -ceq 'any') {
            if ($Entries.Count -ne 1) { Refuse 'sdsys-api on any takes no other address' }
            $norm = @('any')
        } else {
            foreach ($e in $Entries) {
                $n = ConvertTo-Network $e
                if ($norm -notcontains $n) { $norm += $n }
            }
        }
        if ($DryRun) { Say ("${Prog}: would write ${SetFile}: on, then " + ($norm -join ' ')); exit 0 }
        Assert-Place
        $tmp = Join-Path $SetDir ('.sdsys-api.' + [Guid]::NewGuid().ToString('N'))
        try {
            $bytes = [Text.Encoding]::ASCII.GetBytes(((@('on') + $norm) -join "`n") + "`n")
            $fs = New-Object IO.FileStream($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush() } finally { $fs.Close() }
            if (Test-Path -LiteralPath $SetFile) {
                [IO.File]::Replace($tmp, $SetFile, [NullString]::Value)
            } else {
                [IO.File]::Move($tmp, $SetFile)
            }
        } catch {
            if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
            Fail ("could not write ${SetFile}: " + $_.Exception.Message + '.  Nothing was changed')
        }
        Say ('sdsys over the API from other computers: on, from ' + ($norm -join ' '))
        exit 0
    }
}
