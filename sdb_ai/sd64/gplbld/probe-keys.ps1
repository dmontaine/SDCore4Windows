# probe-keys.ps1 - what does this console actually SEND for each key?
#
#   powershell -File probe-keys.ps1        UNELEVATED, in a REAL console
#
# Exit 0 the probe ran, 2 it could not be set up.  There is nothing for it to
# pass or fail: it is an instrument, not a verifier.  What it prints is the
# measurement, and a person reads it.
#
# WHY THIS EXISTS, AND WHY IT IS THE ONLY SCRIPT HERE THAT NEEDS A HUMAN.
# Every other instrument in gplbld drives SD down a PIPE.  That is a real
# technique - keyin() reads stdin, so a piped byte reaches the command-line
# editor exactly as a keystroke does - and it is why verify-keys.ps1 needs no
# terminal.  But it measures what SD does with a byte, never what the console
# produces when a key is pressed.  The two are different questions and the gap
# has bitten twice:
#
#   * verify-keys.ps1 passed 6 of 6 on backspace, on the very install where the
#     owner was reporting backspace as doing nothing.
#   * PROJECT_STATUS.md 5.18's whole argument - that the ESC O spelling of an
#     arrow can never arrive, because SD never sends smkx to enter application
#     cursor mode - is reasoning from the protocol, not a measurement of this
#     console.  It is a strong argument and it predicted the fix correctly.  It
#     is still not the same thing as looking.
#
# So: this prints the bytes, one per line, as they arrive.  Press Left and read
# 27 91 68 off the screen.  There is no interpretation in between.
#
# WHY IT CANNOT RUN THE PROGRAM FOR YOU.  "sd <command>" is gated on elevation
# (sd.c:734, changelog 15 Aug 26), deliberately - "sd LISTF" used to run LISTF
# for anybody.  Elevating to dodge that would change the session under test, so
# the probe is started as a plain "sd" and you type one short command.  It is
# short on purpose: if the arrow keys are broken you cannot correct a typo.
#
# IT MUST BE A REAL CONSOLE, and the script refuses if standard input has been
# redirected - piping into it would measure the pipe and produce a confident
# answer to the wrong question, which is the exact failure this exists to stop.

param([switch]$Keep)

$ErrorActionPreference = 'Stop'

function Stop-Here([int]$code, [string]$msg) {
    Write-Output "probe-keys: $msg"
    exit $code
}

# ---------------------------------------------------------------------------
# 1. A real console, or nothing.

if ([Console]::IsInputRedirected) {
    Write-Output 'probe-keys: standard input is redirected, so this is not a console.'
    Write-Output '  Piping into this script would measure the pipe, not the keyboard,'
    Write-Output '  and every instrument in gplbld already does that.  Run it from a'
    Write-Output '  console window - cmd, PowerShell or Windows Terminal - by hand.'
    exit 2
}

# ---------------------------------------------------------------------------
# 2. The install must match source, or the bytes mean nothing.

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Stop-Here 2 'refusing - see above'
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path $sdExe)) { Stop-Here 2 "no $sdExe" }

# ---------------------------------------------------------------------------
# 3. Somewhere to put the program.  Same resolution verify-osusers.ps1 uses.

$acctRoot = Join-Path $env:ProgramData 'SD\user_accounts'
$acctDir  = $null
foreach ($n in @($env:USERNAME.ToUpper(), $env:USERNAME)) {
    $p = Join-Path $acctRoot $n
    if (Test-Path -LiteralPath $p) { $acctDir = $p; break }
}
if ($null -eq $acctDir) {
    Stop-Here 2 "$env:USERNAME has no SD account under $acctRoot. Only an account holder can run this."
}

# BP resolves to the lower-case bp on disk - NTFS is case insensitive, which is
# also why PROJECT_STATUS.md 5.12's verifier compares listings with -ceq rather
# than calling Test-Path.  Here the insensitivity is simply convenient.
$bp = Join-Path $acctDir 'BP'
if (-not (Test-Path -LiteralPath $bp)) { Stop-Here 2 "no BP in $acctDir - the probe has nowhere to live." }

$probeName = 'ZZKEYPROBE'

# ---------------------------------------------------------------------------
# 4. The program.
#
# BP is a directory file, so a record is a file on disk and no editor is needed
# - the same trick verify-fold.ps1 uses.  LF endings and no BOM, like every
# other record in the tree.
#
# THE ROLLING THREE BYTES ARE THE POINT.  An arrow arrives as ESC, then [ or O,
# then a letter, and which of those two middle bytes turns up is the entire
# question 5.18 turns on.  Naming it on screen means the reader does not have to
# hold the table in their head.

$probeSrc = @'
* ZZKEYPROBE - what the console sends for each key.
* Written by gplbld/probe-keys.ps1.  Safe to delete.
   print @(-1) :
* @(0,0) IS NOT A REDUNDANT CURSOR MOVE - it is what turns screen pagination
* off.  A cursor POSITIONING call does that; a special function like @(-1) does
* not, which is why clearing the screen above is not enough.  Without it a long
* probe session hits "Press RETURN to continue" part way through the byte
* listing, and the key pressed to dismiss it is itself a keystroke - so the
* instrument would start interfering with what it is measuring.  Measured 19 Aug
* 2026: the prompt appeared after 17 bytes in a PowerShell window.
   print @(0,0) :
   print 'ZZKEYPROBE - raw key bytes'
   print ''
   print '   terminal type  = ' : @term.type
   s = @(-1)
   t = ''
   for j = 1 to len(s)
      t := seq(s[j,1]) : ' '
   next j
   print '   terminfo clear = ' : t
   print ''
   print 'Press ONE key at a time and read the bytes it sends.'
   print 'Worth pressing: Left, Right, Up, Down, Backspace, Delete.'
   print ''
   print 'Press q when you have finished.'
   print ''
   n = 0
   b1 = 0 ; b2 = 0 ; b3 = 0
   loop
      c = keyin()
      b = seq(c)
   until b = 113 or n >= 300
      n = n + 1
      b1 = b2 ; b2 = b3 ; b3 = b
      if b >= 32 and b < 127 then p = c else p = ' '
      nm = ''
      if b = 27  then nm = 'ESC'
      if b = 8   then nm = 'Ctrl-H'
      if b = 13  then nm = 'CR'
      if b = 10  then nm = 'LF'
      if b = 9   then nm = 'TAB'
      if b = 127 then nm = 'DEL - the byte every Windows console sends for Backspace'
      print 'byte ' : n : ' = ' : b : '   ' : p : '   ' : nm
      gosub name.sequence
   repeat
   print ''
   print 'ZZKEYPROBE done, ' : n : ' bytes.'
   print 'Type OFF to leave SD.'
   stop

* Called after every byte.  Says nothing unless the last three bytes are an
* arrow, and then says which spelling it was - which is the whole measurement.
name.sequence:
   if b1 # 27 then return
   k = ''
   if b3 = 65 then k = 'UP'
   if b3 = 66 then k = 'DOWN'
   if b3 = 67 then k = 'RIGHT'
   if b3 = 68 then k = 'LEFT'
   if k = '' then return
   if b2 = 91 then
      print '        ^--- ' : k : ', normal cursor mode: ESC [ ' : char(b3)
      print '             This is the spelling the windows terminal type binds.'
   end
   if b2 = 79 then
      print '        ^--- ' : k : ', APPLICATION cursor mode: ESC O ' : char(b3)
      print '             SD does not bind this under the windows type, and'
      print '             nothing in SD sends smkx to ask for it.  Unexpected.'
   end
   return
end
'@

[IO.File]::WriteAllText((Join-Path $bp $probeName),
                        ($probeSrc -replace "`r`n", "`n"),
                        (New-Object Text.UTF8Encoding $false))

# ---------------------------------------------------------------------------
# 5. Compile it.  This half CAN be piped - it is a compile, not a keystroke.
#
# Bounded, for the reason PROJECT_STATUS.md section 8 records: three runs were
# lost to an unbounded prompt loop.  The leading blank line absorbs the pipe's
# BOM, which reaches the command line as a character and is answered with
# "is not in your VOC" by a session that is otherwise perfectly well.

Write-Output ''
Write-Output "probe-keys: compiling $probeName into $bp"

$body = "`n" + (@('TERM 200,9999', "BASIC BP $probeName", 'OFF') -join "`n") + "`n"
$job  = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } -ArgumentList $sdExe, $body
if (Wait-Job $job -Timeout 60) { $out = Receive-Job $job }
else { Stop-Job $job; $out = Receive-Job $job; $out += '<<TIMED OUT>>' }
Remove-Job $job -Force
$out = ($out -join "`n")

if ($out -notmatch '0 error\(s\)') {
    Write-Output '  --- SD said: ---'
    Write-Output $out
    Stop-Here 2 "$probeName did not compile"
}
Write-Output '  compiled.'

# ---------------------------------------------------------------------------
# 6. Hand over.

Write-Output ''
Write-Output '=========================================================================='
Write-Output '  SD is about to start IN THIS WINDOW.  At the ":" prompt, type:'
Write-Output ''
Write-Output "      RUN BP $probeName"
Write-Output ''
Write-Output '  Then press one key at a time.  Press q to stop the probe, and OFF to'
Write-Output '  leave SD - both of which bring you back here.'
Write-Output ''
Write-Output '  COPY THE OUTPUT OUT OF THE WINDOW WHEN YOU ARE DONE.  Nothing can'
Write-Output '  capture it from here: SD writes to the console directly, so there is'
Write-Output '  no transcript of it and no file to read afterwards.'
Write-Output '=========================================================================='
Write-Output ''

& $sdExe

# ---------------------------------------------------------------------------
# 7. Take it away again.

Write-Output ''
if ($Keep) {
    Write-Output "probe-keys: -Keep, so $probeName is left in $bp"
    Write-Output "  Re-run it any time with:  sd   then   RUN BP $probeName"
} else {
    foreach ($d in @($bp, (Join-Path $acctDir 'BP.OUT'))) {
        $p = Join-Path $d $probeName
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    Write-Output "probe-keys: removed $probeName and its object.  -Keep leaves them."
}

exit 0
