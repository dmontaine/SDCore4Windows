# verify-keys.ps1 - the backspace key erases a character, whichever byte the
# terminal sends for it.  PROJECT_STATUS.md 5.17.
#
#   powershell -File verify-keys.ps1
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# WHAT IT MEASURES.  A terminal sends either Ctrl-H (8) or DEL (127) for its
# backspace key.  SD bound whichever one the terminal type's kbs capability
# named and ignored the other, so on a terminal that disagreed with its own
# terminfo entry the key did nothing at all.
#
# EVERY WINDOWS CONSOLE HOST SENDS DEL - cmd, PowerShell and Windows Terminal,
# measured 19 Aug 2026 - while LOGIN:116 defaults an unset TERM to vt100, whose
# kbs is ^H.  So backspace was dead out of the box on the platform this port is
# for.  _KEYCODE now binds both bytes as defaults, before the terminfo binds so
# a type that genuinely claims one of them still overrides it.
#
# IT NEEDS NO TERMINAL, AND THAT IS WHY IT IS CHEAP.  keyin() reads stdin, so a
# byte PIPED into SD reaches the command-line editor exactly as a keystroke
# does - which is the same property that makes the BOM trap in section 6 bite.
# So the erase can be driven from a pipe and this needs no interactive session,
# no elevation and no account of its own.
#
# THE INSTRUMENT IS WHAT SD EXECUTES, not what it echoes.  "COUNTX<erase> VOC"
# runs COUNT VOC and answers "422 record(s) counted" if the erase worked, and
# runs COUNTX VOC and answers "COUNTX is not in your VOC" if it did not.  Two
# different answers, so it cannot pass by accident - and the third case below
# sends no erase at all, which must produce the failing answer or the other two
# prove nothing.

param([switch]$Quiet)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-keys-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-keys: refusing - see above'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path $sdExe)) {
    Write-Output "verify-keys: no $sdExe"
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    if (-not $pass) { $script:failed = $true }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

# Every call is bounded - section 8 of PROJECT_STATUS records three runs lost to
# an unbounded prompt loop.  The leading blank line absorbs the pipe's BOM.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 45) {
    # LOGIN re-inits terminal geometry on every account switch (LOGIN:201-209),
    # so the initial TERM below is wiped by any LOGTO in $commands.  Full
    # write-up in verify-tiers.ps1's Invoke-SD.
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else {
        Stop-Job $job; $out = Receive-Job $job
        $out += ("<<TIMED OUT after {0}s>>" -f $TimeoutSec)
    }
    Remove-Job $job -Force
    return ($out -join "`n")
}

function Test-Erase([int]$code) {
    # COUNTX, then the erase byte, then " VOC".  If the byte erased the X, SD
    # runs COUNT VOC.
    return Invoke-SD @('COUNTX' + [char]$code + ' VOC')
}

try {
    Write-Output ''
    Write-Output '=== 1. the erase itself ==================================================='
    Write-Output '  The shipped default is the windows type, whose kbs is DEL.  Both'
    Write-Output '  bytes must work regardless of what the type says.'

    $del = Test-Erase 127
    Note 'DEL (0x7F) erases the character'   $true  ($del -match 'record\(s\) counted')
    Note 'and DEL did not survive into the verb' $false ($del -match 'is not in your VOC')

    $bs = Test-Erase 8
    Note 'Ctrl-H (0x08) erases the character' $true  ($bs -match 'record\(s\) counted')
    Note 'and Ctrl-H did not survive either'  $false ($bs -match 'is not in your VOC')

    Write-Output ''
    Write-Output '=== 2. the control ======================================================='
    Write-Output '  With no erase byte the SAME command must fail, or section 1 is measuring'
    Write-Output '  a COUNT that would have worked whatever was typed.'

    $none = Invoke-SD @('COUNTX VOC')
    Note 'control: with no erase, COUNTX is refused' $true  ($none -match 'is not in your VOC')
    Note 'control: and nothing was counted'          $false ($none -match 'record\(s\) counted')

    Write-Output ''
    Write-Output '=== 3. the arrow keys ===================================================='
    Write-Output '  PROJECT_STATUS.md 5.18.  A terminal spells an arrow one of two ways, and'
    Write-Output '  sends the ESC O form only in APPLICATION CURSOR MODE, which is entered by'
    Write-Output '  smkx - a string SD never sends, on any platform, from anywhere in the'
    Write-Output '  tree.  So the ordinary ESC [ form is the only one that can ever arrive,'
    Write-Output '  and the shipped default type must be one that binds it.  vt100 and xterm'
    Write-Output '  bind the other one, which is how all four arrows came to be dead.'
    Write-Output ''
    Write-Output '  THE INSTRUMENT NEEDS BOTH ARROWS AT ONCE, and the two ways of failing are'
    Write-Output '  told apart by the answer, not by a second run:  type COUNTVOC, LEFT four'
    Write-Output '  times, RIGHT once, then a space.'
    Write-Output '    both work    -> cursor at 5 -> COUNT VOC   -> "422 record(s) counted"'
    Write-Output '    LEFT only    -> cursor at 4 -> COUN TVOC   -> "COUN is not in your VOC"'
    Write-Output '    neither      -> cursor at 8 -> COUNTVOC    -> "COUNTVOC is not in..."'

    $esc = [char]27
    $arrowLine = { param($l, $r) 'COUNTVOC' + ($l * 4) + $r + ' ' }

    $normal = Invoke-SD @((& $arrowLine "$esc[D" "$esc[C"))
    Note 'LEFT and RIGHT (ESC [ D, ESC [ C) both move the cursor' $true `
         ($normal -match 'record\(s\) counted')
    Note 'and LEFT did not land it one short of the mark'         $false `
         ($normal -match 'COUN is not in your VOC')

    # WITHOUT THIS THE SECTION WOULD PASS ON A BUILD THAT ACCEPTED ANY ESCAPE
    # SEQUENCE AS AN ARROW.  Only the decisive half is asserted - whatever the
    # unbound bytes leave in the command line, they must not produce a COUNT.
    $appmode = Invoke-SD @((& $arrowLine ($esc + 'OD') ($esc + 'OC')))
    Note 'control: the application-mode spelling is NOT bound'    $false `
         ($appmode -match 'record\(s\) counted')

    $noarrow = Invoke-SD @('COUNTVOC ')
    Note 'control: with no arrows at all, COUNTVOC is refused'    $true `
         ($noarrow -match 'COUNTVOC is not in your VOC')

    if (-not $Quiet) {
        Write-Output ''
        Write-Output '  --- DEL run said: ---'
        Write-Output $del
    }

    Write-Output ''
    Write-Output '=== Summary =============================================================='
    $results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
    $passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
    Write-Output ("  {0} of {1} checks passed" -f $passed, $results.Count)
}
finally {
    try { Stop-Transcript | Out-Null } catch { }
}

if ($failed) { exit 1 } else { exit 0 }
