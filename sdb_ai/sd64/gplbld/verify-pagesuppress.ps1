<#
.SYNOPSIS
    "Suppress pagination" at a query report's page prompt must behave like
    NO.PAGE.  ***AN ORDINARY UNELEVATED PROMPT.***

.DESCRIPTION
    RELEASE_1.1_FIXES.md 28, UPSTREAM_FIXES.md 39.  QDISP's page prompt offers
    "Action (Abort/Quit/Next/Suppress pagination)".  Answering S cleared
    qd.paginate, which stops the prompt, but not qd.no.page, which is what
    emit.line tests before clearing the screen and re-emitting the heading at
    each new page.  So the report stopped asking and went on clearing the
    screen every page, and a terminal showed only the last page.

    MEASURED BEFORE THE FIX, 13 Sep 2026, on the 10:23:02 install, LIST ONLY
    VOC at TERM 80,12 (421 records):

        NO.PAGE            1 clear-screen, 1 heading, 0 prompts
        page prompt, S    48 clear-screens, 47 headings, 1 prompt -
                          46 of each AFTER the prompt

    The totals cannot be compared with the control: the sign-on banner clears
    the screen in both legs, and a paginated LIST also clears before page 1
    where NO.PAGE does not.  So the decisive rows count only what follows the
    prompt, and the control fixes that one heading is what NO.PAGE draws.

    ***TWO LEGS, AND THE FIRST IS THE CONTROL.***  Leg A lists with NO.PAGE,
    which is the behaviour S is meant to reproduce, and fixes the expected
    counts from the install itself rather than from a number typed here.  Leg B
    lists without it and answers the first prompt with S.  A leg B that never
    reached a prompt would pass every "no more headings" row by default, so
    the prompt being reached exactly once is a decisive row of its own.

    A small terminal (TERM 80,12) makes the report span many pages.  The input
    is piped and bounded by a job; any sd.exe the job leaves behind is killed
    by PID diff, never by name - the SD service runs sd.exe too.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 the test could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-pagesuppress.ps1
#>

[CmdletBinding()]
param(
    [int]$TimeoutSeconds = 40
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$ESC    = [char]27
$Clear  = "$ESC[H$ESC[J"
$Prompt = 'Action ('

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}
function Bail([int]$code, [string]$why) {
    Write-Host ''
    if ($code -eq 0) { Write-Host "verify-pagesuppress: PASSED - $why" }
    elseif ($code -eq 1) { Write-Host "verify-pagesuppress: FAILED - $why" }
    else { Write-Host "verify-pagesuppress: COULD NOT RUN - $why" }
    exit $code
}

# The pipe shape and the bounding are verify-promptenter.ps1's.  No TERM line is
# prepended here: the page size under test is set by the leg itself.
function Invoke-SD([string[]]$lines) {
    $body = "`n" + (($lines + @('OFF')) -join "`n") + "`n"
    $before = @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue |
                ForEach-Object { $_.Id })

    $job = Start-Job -ScriptBlock {
        param($exe, $text)
        $text | & $exe 2>&1
    } -ArgumentList $sdExe, $body

    $killed = $false
    if (-not (Wait-Job $job -Timeout $TimeoutSeconds)) {
        $killed = $true
        Stop-Job $job -ErrorAction SilentlyContinue
        foreach ($p in @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue)) {
            if ($before -notcontains $p.Id) {
                try { $p.Kill() } catch { }
            }
        }
    }
    $out = @(Receive-Job $job -ErrorAction SilentlyContinue)
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    return [pscustomobject]@{ Text = ($out | Out-String); Killed = $killed }
}

function Measure-Report([string]$label, [string[]]$lines) {
    Write-Host "--- $label -------------------------------------------------------"
    Write-Host ('  input: ' + (($lines + @('OFF')) | ForEach-Object { "[$_]" }) -join ' ')
    $r = Invoke-SD $lines
    $t = $r.Text
    $m = [regex]::Match($t, '(\d+) record\(s\) listed')
    # Split at the first prompt.  Everything before it is page 1 and the sign-on,
    # which clear the screen whatever S does - the banner's own clear is in both
    # legs, and a paginated LIST clears before page 1 where NO.PAGE does not.
    # Measured 13 Sep 2026, which is why the decisive rows count only what comes
    # AFTER the prompt rather than comparing totals with the control.
    #
    # THE HEADING PATTERN.  A page heading repeats the whole sentence, so the
    # control's reads "LIST ONLY VOC NO.PAGE ... Page 1" - the first version of
    # this pattern had no room for the keyword and counted 0 there.  The gap
    # before "Page" is spaces only, so the echoed command line, which ends at a
    # newline, cannot match.
    $Heading = 'LIST ONLY VOC(?: NO\.PAGE)? {2,}Page +\d+'
    $pi = $t.IndexOf($Prompt)
    $tail = if ($pi -ge 0) { $t.Substring($pi) } else { '' }
    $o = [pscustomobject]@{
        Killed        = $r.Killed
        Bytes         = $t.Length
        Clears        = [regex]::Matches($t, [regex]::Escape($Clear)).Count
        Headings      = [regex]::Matches($t, $Heading).Count
        Prompts       = [regex]::Matches($t, [regex]::Escape($Prompt)).Count
        ClearsAfter   = [regex]::Matches($tail, [regex]::Escape($Clear)).Count
        HeadingsAfter = [regex]::Matches($tail, $Heading).Count
        Listed        = if ($m.Success) { [int]$m.Groups[1].Value } else { -1 }
        Text          = $t
    }
    Write-Host ("  killed {0}, bytes {1}, clear-screens {2} ({3} after the first prompt), headings {4} ({5} after), prompts {6}, listed {7}" -f `
        $o.Killed, $o.Bytes, $o.Clears, $o.ClearsAfter, $o.Headings, $o.HeadingsAfter, $o.Prompts, $o.Listed)
    return $o
}

# --- refusals ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $sdExe)) { Bail 2 "no sd.exe at $sdExe" }

$elevated = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
                [Security.Principal.WindowsBuiltInRole]::Administrator)
Write-Host "verify-pagesuppress: sd.exe   $sdExe"
Write-Host "verify-pagesuppress: elevated $elevated"
Write-Host ''
Write-Host '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
Write-Host ''

# --- leg A: the control, NO.PAGE -----------------------------------------------
$a = Measure-Report 'leg A (control): LIST ONLY VOC NO.PAGE' @('TERM 80,12', 'LIST ONLY VOC NO.PAGE')
if ($a.Killed -or $a.Listed -le 0) {
    Bail 2 "the control did not complete a listing - nothing to compare against.`n$($a.Text)"
}
# The report must be long enough to span pages at this size, or leg B could not
# reach a prompt and the whole test would measure nothing.
if ($a.Listed -lt 40) {
    Bail 2 "only $($a.Listed) records - too few to span several pages at TERM 80,12."
}
if ($a.Prompts -ne 0) {
    Bail 2 "the NO.PAGE control itself prompted $($a.Prompts) time(s) - it is not a control."
}
Write-Host ''

# --- leg B: page prompt answered S ----------------------------------------------
# keycode() reads one byte, so the S is taken from the pipe at the first prompt;
# the newline after it reaches TCL as an empty command, which is harmless.
$b = Measure-Report 'leg B: LIST ONLY VOC, first page prompt answered S' @('TERM 80,12', 'LIST ONLY VOC', 'S')
Write-Host ''

Row 'leg B terminated (no hang at a later prompt)' (-not $b.Killed) `
    "killed after ${TimeoutSeconds}s - a prompt came back after S and waited on the pipe"
Row 'leg B reached the page prompt exactly once' ($b.Prompts -eq 1) `
    "$($b.Prompts) prompt(s): 0 means S was never offered (nothing measured); more than 1 means S did not stop the prompts"
Row 'leg B listed every record the control listed' ($b.Listed -eq $a.Listed) `
    "leg B listed $($b.Listed), the control $($a.Listed)"

# THE DECISIVE ROWS, COUNTED AFTER THE PROMPT.  Before the fix: 46 and 46.
# The control is what says a heading should appear once: NO.PAGE's whole listing
# carries exactly the one heading page 1 has.
Row 'the control: NO.PAGE draws the heading once' ($a.Headings -eq 1) `
    "NO.PAGE drew $($a.Headings) headings - the behaviour S is compared against is not what this test assumes"
Row 'leg B drew page 1 (its heading precedes the prompt)' (($b.Headings - $b.HeadingsAfter) -eq 1) `
    "$($b.Headings - $b.HeadingsAfter) heading(s) before the prompt"
Row 'after S, no further page headings' ($b.HeadingsAfter -eq 0) `
    "$($b.HeadingsAfter) heading(s) after S - each later page still re-drew its heading"
Row 'after S, no further clear-screens' ($b.ClearsAfter -eq 0) `
    "$($b.ClearsAfter) clear-screen(s) after S - a terminal would show only the last page"

Write-Host ''
Write-Host "verify-pagesuppress: $pass passed, $fail failed"
if ($fail -gt 0) { Bail 1 "$fail check(s) failed." }
Bail 0 "S at the page prompt ran the rest of the report on, exactly as NO.PAGE does."
