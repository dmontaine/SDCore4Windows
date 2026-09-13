<#
.SYNOPSIS
    Press ENTER at a prompt that has a default, and prove the default took
    effect.  ***AN ORDINARY UNELEVATED PROMPT.***

.DESCRIPTION
    RELEASE_1.1_FIXES.md 6.  Seven prompts were given `if x = '' then x = 'N'`
    and a `(y/<n>)?` marker on 11-12 Sep 2026, and the entry records the gap
    that matters: ***"The Enter-defaults are unwitnessed everywhere - every one
    of these was answered with a real Y or N, so no run has yet pressed Enter at
    one."***  This presses Enter.

    ***THE PROMPT IT DRIVES IS 6131***, `DELETEF:196` - "Use file '%1'
    (y/<n>)?" - reached by naming a file in LOWER CASE when its VOC record is
    UPPER CASE: DELETEF reports 6130, upcases, finds the record, and asks
    whether you meant that one.  It is the seventh prompt, the one whose
    WORDING was missing until 12 Sep 2026, so this witnesses the message and
    the default together.

    ***THE CONTROL IS THE POINT, NOT THE ENTER CASE.***  "The file still
    exists" is also what you get from a command that never ran, a prompt that
    never fired, and a typo in the file name.  So the same prompt is driven
    twice: Enter must LEAVE the file, and an explicit Y must DELETE it.  A run
    where both answers leave the file has measured nothing and says so.

    ***AND IT IS BOUNDED, BECAUSE THE DEFECT IT GUARDS IS A HANG.***  Before the
    fix an empty answer was neither Y nor N, so the loop re-asked for ever -
    measured on Linux at 98.9 MB of the question in 40 seconds.  The child is
    started with a redirected stdin and killed if it outstays its welcome, and
    an oversized transcript is itself a FAIL.  "echo WHO | sd" is in this
    project's record as a hang that cost an elevation to clear; nothing here is
    left to chance.

.PARAMETER Account
    The SD account to work in.  Defaults to the caller's own.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 the test could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-promptenter.ps1
#>

[CmdletBinding()]
param(
    [string]$Account = $env:USERNAME,
    [int]$TimeoutSeconds = 40
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$Root   = Join-Path $env:ProgramData 'SD\user_accounts'
$Probe  = 'ZZPROMPTE'

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}
function Bail([int]$code, [string]$why) {
    Write-Host ''
    if ($code -eq 0) { Write-Host "verify-promptenter: PASSED - $why" }
    elseif ($code -eq 1) { Write-Host "verify-promptenter: FAILED - $why" }
    else { Write-Host "verify-promptenter: COULD NOT RUN - $why" }
    exit $code
}

# ***IT MUST BE A PIPE, AND THAT IS MEASURED.***  The first version redirected
# stdin from a FILE, which is what lets Start-Process bound a child directly.
# SD answers that with "Process terminated" before it reads a single command -
# both LF and CRLF, so it is the handle and not the line endings.  The pipe
# shape is verify-basicfuncs.ps1's and it works, so the bounding is built
# around the pipe instead of replacing it.
#
# Bounded by a job, and any sd.exe the job leaves behind is killed BY PID DIFF -
# never by name, because the SD service runs sd.exe too and killing that would
# be a far worse outcome than the hang this is guarding against.
function Invoke-SD([string[]]$lines) {
    $body = "`n" + ((@('TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"
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

    $text = ($out | Out-String)
    return [pscustomobject]@{
        Text   = ($text -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '')
        Killed = $killed
        Bytes  = $text.Length
    }
}

# --- refusals ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $sdExe)) { Bail 2 "no sd.exe at $sdExe" }
$bpDir = Join-Path (Join-Path $Root $Account) 'bp'
if (-not (Test-Path -LiteralPath $bpDir)) {
    Bail 2 "no bp directory at $bpDir - pass -Account with an SD account name."
}

Write-Host "verify-promptenter: account $Account"
Write-Host "verify-promptenter: sd.exe  $sdExe"
Write-Host "verify-promptenter: file    $Probe"
Write-Host "verify-promptenter: prompt  6131, DELETEF:196"
Write-Host ''
Write-Host '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
Write-Host ''

try {
    # --- setup -------------------------------------------------------------
    $null = Invoke-SD @("DELETE.FILE $Probe", 'Y', 'Y', 'Y')   # any leftover
    $mk = Invoke-SD @("CREATE.FILE $Probe")
    if ($mk.Text -notmatch "Created DATA part as $Probe") {
        Bail 2 "could not create $Probe - the setup, not the measurement, failed.`n$($mk.Text)"
    }
    $ls = Invoke-SD @("LISTF $Probe")
    if ($ls.Text -notmatch '1 record\(s\) listed') {
        Bail 2 "$Probe was not listed after creation - nothing to measure."
    }
    Write-Host "  setup: $Probe created and listed"
    Write-Host ''

    # --- LEG 1: press ENTER -------------------------------------------------
    #
    # Lower case name, upper case VOC record - that is what reaches 6131.
    # The bare '' line IS the Enter.
    $lower = $Probe.ToLower()
    Write-Host "--- leg 1: DELETE.FILE $lower, answered with ENTER -------------------"
    $r = Invoke-SD @("DELETE.FILE $lower", '')
    Write-Host $r.Text

    Row 'the run terminated (no runaway loop)' (-not $r.Killed) `
        "the child had to be killed after ${TimeoutSeconds}s - this is the hang entry 6 is about"
    Row 'the transcript is a sane size' ($r.Bytes -lt 200000) `
        "$($r.Bytes) bytes - the runaway signature is megabytes of the same question"

    # The prompt must have been REACHED.  Without this row, every row below
    # passes on a run where DELETEF never asked anything.
    Row 'prompt 6131 was reached' ($r.Text -match 'Use file') `
        "no 'Use file' prompt in the transcript - the leg measured nothing"

    # THE WORDING FIXED ON 12 Sep 2026.
    Row 'prompt 6131 shows its default, (y/<n>)' ($r.Text -match 'Use file .*\(y/<n>\)') `
        'the prompt did not carry (y/<n>) - the 12 Sep message fix is not on this install'

    # THE DEFAULT ITSELF.  Nothing may have been deleted.
    $gone = ($r.Text -match "DATA portion '.*' deleted") -or
            ($r.Text -match "VOC entry '.*' deleted")
    Row 'ENTER did not delete anything' (-not $gone) `
        'the transcript reports a deletion - Enter was taken as YES'

    $after = Invoke-SD @("LISTF $Probe")
    Row 'the file survives an ENTER' ($after.Text -match '1 record\(s\) listed') `
        "LISTF no longer finds $Probe - it was deleted by an empty answer"
    Write-Host ''

    # --- LEG 2: the control, an explicit Y ---------------------------------
    #
    # WITHOUT THIS THE WHOLE TEST IS WORTHLESS.  "Still there" is equally what a
    # command that never ran produces.
    Write-Host "--- leg 2 (control): the same prompt answered Y ----------------------"
    $c = Invoke-SD @("DELETE.FILE $lower", 'Y')
    Write-Host $c.Text
    Row 'CONTROL: prompt 6131 was reached again' ($c.Text -match 'Use file') `
        'the control did not reach the prompt, so leg 1 proves nothing'
    $cGone = Invoke-SD @("LISTF $Probe")
    Row 'CONTROL: an explicit Y DOES delete the file' `
        ($cGone.Text -notmatch '1 record\(s\) listed') `
        "LISTF still finds $Probe after Y - the prompt is not driving a deletion at all, so leg 1's survival means nothing"
}
finally {
    $null = Invoke-SD @("DELETE.FILE $Probe", 'Y', 'Y', 'Y')
    $left = Invoke-SD @("LISTF $Probe")
    Write-Host ''
    Write-Host ("cleanup: $Probe left behind = " + ($left.Text -match '1 record\(s\) listed'))
}

Write-Host ''
Write-Host "verify-promptenter: $pass passed, $fail failed"
if ($fail -gt 0) { Bail 1 "$fail check(s) failed." }
Bail 0 "Enter took the default at prompt 6131, and the control proves the prompt was live."
