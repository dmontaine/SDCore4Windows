# sd-radmin-client.ps1 - the remote administration session's half of the broker's pipe
#
# 13 Nov 26 Windows port - written for RELEASE_1.1 202 (design .claude/design-remote-admin-20261113.md, section 5.1).
#
#   sd-radmin-client.ps1 -Request <file>
#
# Run by the remote administration session's commands (gpl.bp/radmin, through OS.EXECUTE from that $internal program) as the Windows account
# SDRADMIN, in its ssh session.  <file> is the request radmin wrote into SDSYS's pstmp (secure-psdir.ps1: each file is its writer's alone,
# CREATOR OWNER): "key=value" lines ending "end", the new password, when there is one, in hexadecimal.  THIS SCRIPT DELETES THE FILE AS SOON
# AS IT HAS READ IT, before it connects, so the password is on disk for the time between radmin's write and this read; it is never on a
# command line (the file's NAME is) and this script prints nothing of the request.
#
# IT CHECKS THE SERVER BEFORE IT SENDS ANYTHING: the pipe's owner must be SDSYS, Administrators or SYSTEM.  An elevated SDSYS (the broker)
# makes its pipe owned by one of those; a pipe made by anybody else, while the broker was not running, is owned by its maker, and gets
# nothing.  (Making a pipe owned by Administrators takes an administrator, who is above SD already.)
#
# WHAT IT PRINTS, for radmin to read: the broker's answer lines as they came ("nonce=", "out=", "exit=", "refused=", "timeout="), or one
# "noanswer=<why>" line of its own.  Exit 0 when an answer with this request's nonce came back, 2 when none did, 3 when the pipe was not
# the broker's, 4 when the request file was not usable.

param([string]$Request = '')

$ErrorActionPreference = 'Stop'

function Out-Line([string]$t) { [Console]::Out.WriteLine($t) }

$text = $null
try {
    if ($Request -eq '' -or -not (Test-Path -LiteralPath $Request -PathType Leaf)) { Out-Line 'noanswer=the request file is not there'; exit 4 }
    $bytes = [IO.File]::ReadAllBytes($Request)
    Remove-Item -LiteralPath $Request -Force
    if ($bytes.Length -gt 4096) { Out-Line 'noanswer=the request is longer than 4096 bytes'; exit 4 }
    $text = [Text.Encoding]::ASCII.GetString($bytes)
    [Array]::Clear($bytes, 0, $bytes.Length)
    # radmin writes field marks as line ends; a CR from either side is dropped, and the last line must be "end".
    $text = (($text -replace "`r", '') -split "`n" | Where-Object { $_ -ne '' }) -join "`n"
    if (-not $text.EndsWith("`nend")) { Out-Line 'noanswer=the request file does not end with "end"'; exit 4 }
    $text += "`n"
    $nonce = ''
    foreach ($l in ($text -split "`n")) { if ($l -cmatch '^nonce=([0-9a-f]{16})$') { $nonce = $Matches[1] } }
    if ($nonce -eq '') { Out-Line 'noanswer=the request has no nonce'; exit 4 }
} catch {
    if ($Request -ne '' -and (Test-Path -LiteralPath $Request)) { Remove-Item -LiteralPath $Request -Force -ErrorAction SilentlyContinue }
    Out-Line ('noanswer=the request file could not be read: ' + $_.Exception.Message)
    exit 4
}

$pipe = $null
try {
    $pipe = New-Object IO.Pipes.NamedPipeClientStream('.', 'sd-radmin', [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::None,
                                                      [Security.Principal.TokenImpersonationLevel]::Identification)
    try { $pipe.Connect(5000) } catch { Out-Line 'noanswer=the remote administration helper is not running'; exit 2 }

    $owner = ''
    try { $owner = $pipe.GetAccessControl().GetOwner([Security.Principal.SecurityIdentifier]).Value } catch { $owner = '' }
    $sdsys = ''
    try { $sdsys = (New-Object Security.Principal.NTAccount("$([Environment]::MachineName)\SDSYS")).Translate([Security.Principal.SecurityIdentifier]).Value } catch { }
    if (@('S-1-5-18', 'S-1-5-32-544', $sdsys) -notcontains $owner -or $owner -eq '') {
        Out-Line 'refused=the pipe sd-radmin is not the remote administration helper''s; nothing was sent'
        exit 3
    }

    $out = [Text.Encoding]::ASCII.GetBytes($text)
    $text = $null
    $pipe.Write($out, 0, $out.Length)
    $pipe.Flush()
    [Array]::Clear($out, 0, $out.Length)

    # The answer: everything until the line "end" or the pipe closes.  No timeout of its own: the broker answers within its 180 seconds.
    $latin1 = [Text.Encoding]::GetEncoding(28591)
    $reader = New-Object IO.StreamReader($pipe, $latin1)
    $seen = ''
    $any = $false
    while ($true) {
        $l = $reader.ReadLine()
        if ($null -eq $l -or $l -ceq 'end') { break }
        if ($l -cmatch '^nonce=(.*)$') { $seen = $Matches[1]; continue }
        Out-Line $l
        $any = $true
    }
    if (-not $any) { Out-Line 'noanswer=the helper closed the connection without an answer'; exit 2 }
    if ($seen -ne '' -and $seen -cne $nonce) { Out-Line 'noanswer=the answer was for another request'; exit 2 }
    exit 0
} catch {
    Out-Line ('noanswer=' + $_.Exception.Message)
    exit 2
} finally {
    if ($null -ne $pipe) { $pipe.Dispose() }
}
