<#
.SYNOPSIS
    Drive sdpy.exe over a real pipe.  Free: no install, no elevation, no run
    token, no SD.

.DESCRIPTION
    PROJECT_STATUS.md section 5.27.  This speaks the protocol to the real
    binary rather than testing a model of it, because every interesting
    property of this helper is a property of the WIRE: whether a payload
    carrying marks survives, whether a print() corrupts the frame stream,
    whether a traceback comes back at all.

    ***THE THREE ROWS THAT ARE THE POINT.***

      * A VALUE CARRYING SD MARKS ROUND-TRIPS.  @fm/@vm/@sm are 0xFE/0xFD/0xFC
        and are not valid UTF-8.  The first version of sdpy.c used
        PyUnicode_FromString and would have rejected the first dynamic array
        anybody passed it.  Latin-1 is what the removed code's own error names
        said to use (SD_PyErr_EnLatin) and this is the row that holds it there.

      * print() DOES NOT CORRUPT THE STREAM.  stdout IS the protocol channel.
        If sys.stdout were not redirected, one print() would desynchronise
        every frame after it - and the failure would look like a protocol bug
        anywhere except where it was caused.

      * A FAILING SCRIPT RETURNS ITS TRACEBACK.  The removed surface returned
        an integer, so "it did not work" was the whole of the diagnosis.

.OUTPUTS
    Exit 0 every row passed, 1 a row failed, 2 the helper is not built.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$exe  = Join-Path $here 'sdpy.exe'

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}

if (-not (Test-Path -LiteralPath $exe)) {
    Write-Host "test-sdpy-units: COULD NOT RUN - no $exe"
    Write-Host '  Build it first: build-sdpy.ps1.  It is build output and is not tracked.'
    exit 2
}

# --- the wire ---------------------------------------------------------------
#
# BaseStream on both sides, never the StreamReader/Writer: the payloads are
# BYTES with explicit lengths, and a text reader would re-encode them and
# mis-count what it handed back.

$psi = New-Object System.Diagnostics.ProcessStartInfo
$psi.FileName = $exe
$psi.RedirectStandardInput = $true
$psi.RedirectStandardOutput = $true
$psi.RedirectStandardError = $true
$psi.UseShellExecute = $false
$psi.CreateNoWindow = $true
$proc = [System.Diagnostics.Process]::Start($psi)

$in  = $proc.StandardInput.BaseStream
$out = $proc.StandardOutput.BaseStream

function Send-Frame([string]$verb, [byte[]]$a1, [byte[]]$a2, [byte[]]$a3) {
    if ($null -eq $a1) { $a1 = @() }
    if ($null -eq $a2) { $a2 = @() }
    if ($null -eq $a3) { $a3 = @() }
    $hdr = [Text.Encoding]::ASCII.GetBytes(
               ('{0} {1} {2} {3}' -f $verb, $a1.Length, $a2.Length, $a3.Length) + "`n")
    $in.Write($hdr, 0, $hdr.Length)
    foreach ($a in @($a1, $a2, $a3)) { if ($a.Length) { $in.Write($a, 0, $a.Length) } }
    $in.Flush()
}

function Read-Frame() {
    # header: "<status> <len>\n", read a byte at a time so the payload that
    # follows is not swallowed by a buffer.
    $sb = New-Object Text.StringBuilder
    while ($true) {
        $b = $out.ReadByte()
        if ($b -lt 0) { return $null }
        if ($b -eq 10) { break }
        [void]$sb.Append([char]$b)
    }
    $parts = ($sb.ToString().Trim() -split '\s+')
    $status = [int]$parts[0]
    $len    = [int]$parts[1]
    $buf = New-Object byte[] $len
    $got = 0
    while ($got -lt $len) {
        $r = $out.Read($buf, $got, $len - $got)
        if ($r -le 0) { break }
        $got += $r
    }
    return [pscustomobject]@{ Status = $status; Bytes = $buf; Got = $got
                              Text = [Text.Encoding]::GetEncoding('iso-8859-1').GetString($buf) }
}

function Latin([string]$s) { return [Text.Encoding]::GetEncoding('iso-8859-1').GetBytes($s) }

Write-Host 'test-sdpy-units: driving the real sdpy.exe over a pipe'
Write-Host ("  binary : " + $exe)
Write-Host ''

try {
    # --- the handshake gates everything ------------------------------------
    Send-Frame 'PING' $null $null $null
    $r = Read-Frame
    Row 'a verb before HELLO is refused' ($r.Status -ne 0) `
        "status $($r.Status) '$($r.Text)' - the handshake is not gating"

    Send-Frame 'HELLO' (Latin 'SDPY1') $null $null
    $r = Read-Frame
    Row 'HELLO agrees on the protocol version' ($r.Status -eq 0 -and $r.Text -eq 'SDPY1') `
        "status $($r.Status) '$($r.Text)'"

    Send-Frame 'PING' $null $null $null
    $r = Read-Frame
    Row 'PING answers after HELLO' ($r.Status -eq 0 -and $r.Text -eq 'PONG') `
        "status $($r.Status) '$($r.Text)'"

    # --- lifecycle ----------------------------------------------------------
    Send-Frame 'ISINIT' $null $null $null
    $r = Read-Frame
    Row 'ISINIT says 0 before INIT' ($r.Text -eq '0') "got '$($r.Text)'"

    Send-Frame 'INIT' $null $null $null
    $r = Read-Frame
    $pyver = $r.Text
    Row 'INIT starts the interpreter' ($r.Status -eq 0 -and $r.Text -ne '') `
        "status $($r.Status) '$($r.Text)'"
    Write-Host ("         python: " + ($pyver -split "`n")[0])

    Send-Frame 'ISINIT' $null $null $null
    $r = Read-Frame
    Row 'ISINIT says 1 after INIT' ($r.Text -eq '1') "got '$($r.Text)'"

    # --- print() is captured, not leaked into the frame stream --------------
    Send-Frame 'RUNSTR' (Latin "print('hello from python')") $null $null
    $r = Read-Frame
    Row 'RUNSTR returns what the script printed' `
        ($r.Status -eq 0 -and $r.Text -match 'hello from python') `
        "status $($r.Status) '$($r.Text)'"

    # THE ROW THAT PROVES THE STREAM SURVIVED IT.  If print() had gone to the
    # real stdout, this next frame would be read out of step and PING would
    # come back as something else or not at all.
    Send-Frame 'PING' $null $null $null
    $r = Read-Frame
    Row 'the frame stream is still in step after a print()' `
        ($r.Status -eq 0 -and $r.Text -eq 'PONG') `
        "got status $($r.Status) '$($r.Text)' - a print() desynchronised the stream"

    # --- named objects, shared both ways -----------------------------------
    Send-Frame 'STRSET' (Latin 'hello') $null (Latin 'greeting')
    $r = Read-Frame
    Row 'STRSET stores a named string' ($r.Status -eq 0) "status $($r.Status) '$($r.Text)'"

    Send-Frame 'STRGET' $null $null (Latin 'greeting')
    $r = Read-Frame
    Row 'STRGET reads it back' ($r.Status -eq 0 -and $r.Text -eq 'hello') `
        "status $($r.Status) '$($r.Text)'"

    # The improvement over __main__: SD's names ARE the script globals.
    Send-Frame 'RUNSTR' (Latin "print(greeting.upper())") $null $null
    $r = Read-Frame
    Row 'a script sees SD''s named objects' ($r.Status -eq 0 -and $r.Text -match 'HELLO') `
        "status $($r.Status) '$($r.Text)'"

    Send-Frame 'RUNSTR' (Latin "from_python = 'made in python'") $null $null
    $r = Read-Frame | Out-Null
    Send-Frame 'STRGET' $null $null (Latin 'from_python')
    $r = Read-Frame
    Row 'SD sees what a script created' ($r.Status -eq 0 -and $r.Text -eq 'made in python') `
        "status $($r.Status) '$($r.Text)'"

    # --- ***MARKS AND NUL SURVIVE.  THIS IS THE ROW THAT CAUGHT A REAL BUG.***
    $marky = [byte[]](0x61, 0xFE, 0x62, 0xFD, 0x63, 0xFC, 0x64, 0x00, 0x65, 0x0A, 0x66)
    Send-Frame 'STRSET' $marky $null (Latin 'marks')
    $r = Read-Frame
    Row 'a value carrying @fm/@vm/@sm, NUL and a newline is accepted' ($r.Status -eq 0) `
        "status $($r.Status) '$($r.Text)'"

    Send-Frame 'STRGET' $null $null (Latin 'marks')
    $r = Read-Frame
    $same = ($r.Got -eq $marky.Length)
    if ($same) { for ($i = 0; $i -lt $marky.Length; $i++) { if ($r.Bytes[$i] -ne $marky[$i]) { $same = $false } } }
    Row 'it round-trips BYTE FOR BYTE' ($r.Status -eq 0 -and $same) `
        ("sent " + $marky.Length + " bytes, got " + $r.Got + ": " +
         (($r.Bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' '))

    Send-Frame 'OBJLEN' $null $null (Latin 'marks')
    $r = Read-Frame
    Row 'OBJLEN counts every byte of it' ($r.Text -eq [string]$marky.Length) `
        "expected $($marky.Length), got '$($r.Text)'"

    # --- type and delete ----------------------------------------------------
    Send-Frame 'OBJTYPE' $null $null (Latin 'greeting')
    $r = Read-Frame
    Row 'OBJTYPE names the Python type' ($r.Text -eq 'str') "got '$($r.Text)'"

    Send-Frame 'OBJTYPE' $null $null (Latin 'no_such_object')
    $r = Read-Frame
    Row 'an unknown object is -12014, not a crash' ($r.Status -eq -12014) `
        "status $($r.Status)"

    Send-Frame 'DELOBJ' $null $null (Latin 'greeting')
    $r = Read-Frame
    Row 'DELOBJ removes it' ($r.Status -eq 0) "status $($r.Status)"
    Send-Frame 'STRGET' $null $null (Latin 'greeting')
    $r = Read-Frame
    Row 'and it is gone afterwards' ($r.Status -eq -12014) "status $($r.Status)"

    # --- ***THE TRACEBACK.*** ----------------------------------------------
    Send-Frame 'RUNSTR' (Latin "raise ValueError('deliberate')") $null $null
    $r = Read-Frame
    Row 'a raising script returns -12004' ($r.Status -eq -12004) "status $($r.Status)"
    Row 'and the payload is the real traceback' `
        ($r.Text -match 'ValueError' -and $r.Text -match 'deliberate' -and $r.Text -match 'Traceback') `
        "payload was: '$($r.Text)'"

    # THE FIRST FIXTURE HERE WAS "this is not python" AND IT IS VALID PYTHON -
    # the "is not" operator applied to two names, so it compiled and raised
    # NameError at run time instead.  The helper was right and the test was
    # wrong; kept as a comment because it is a good trap.
    Send-Frame 'RUNSTR' (Latin "def broken(:") $null $null
    $r = Read-Frame
    Row 'a syntax error is reported as one, with its line' `
        ($r.Status -eq -12004 -and $r.Text -match 'SyntaxError' -and $r.Text -match 'line 1') `
        "status $($r.Status) '$($r.Text)'"

    # The stream is STILL in step after two failures.
    Send-Frame 'PING' $null $null $null
    $r = Read-Frame
    Row 'the stream is in step after two failures' ($r.Text -eq 'PONG') "got '$($r.Text)'"

    # --- shutdown -----------------------------------------------------------
    Send-Frame 'FIN' $null $null $null
    $r = Read-Frame
    Row 'FIN stops the interpreter' ($r.Status -eq 0) "status $($r.Status)"
    Send-Frame 'ISINIT' $null $null $null
    $r = Read-Frame
    Row 'ISINIT says 0 after FIN' ($r.Text -eq '0') "got '$($r.Text)'"

    Send-Frame 'RUNSTR' (Latin "print(1)") $null $null
    $r = Read-Frame
    Row 'running after FIN is -12001, not a crash' ($r.Status -eq -12001) "status $($r.Status)"

    Send-Frame 'QUIT' $null $null $null
    $r = Read-Frame | Out-Null
    $exited = $proc.WaitForExit(10000)
    Row 'QUIT exits cleanly' ($exited -and $proc.ExitCode -eq 0) `
        ("exited=$exited code=" + $(if ($exited) { $proc.ExitCode } else { 'still running' }))
}
finally {
    if (-not $proc.HasExited) {
        try { $proc.Kill(); Write-Host '  (the helper had to be killed)' } catch { }
    }
}

Write-Host ''
Write-Host "test-sdpy-units: $pass passed, $fail failed"
if ($fail -gt 0) { exit 1 }
exit 0
