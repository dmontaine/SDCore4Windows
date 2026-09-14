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

    ***AN UPPER-CASE VOC RECORD NO LONGER COMES FOR FREE - 13 Sep 2026.***
    RELEASE_1.1 5 phase (a) makes CREATE.FILE store a new id in lower case,
    so this script's plain "CREATE.FILE ZZPROMPTE" would now write
    zzprompte, leg 1 would find it as typed, never reach 6131 and delete it.
    The fixture is therefore made with OPTION CREATE.FILE.UPCASE set (option
    24, OPT.CREATE.FILE.CASE - despite its name it KEEPS the case typed), and
    a setup row proves the stored id is upper before any leg runs.

    ***LEG 3 WITNESSES RELEASE_1.1 27***: a file created the ordinary way
    (stored lower) and deleted by its name typed in UPPER case must go,
    without 6130 and without a prompt - DELETEF's lower-case tier.

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
$ProbeL = 'ZZPROMPTL'   # leg 3: created the ordinary way, so stored as zzpromptl

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
Write-Host "verify-promptenter: file    $Probe  (legs 1-2, made with OPTION CREATE.FILE.UPCASE)"
Write-Host "verify-promptenter: file    $ProbeL  (leg 3, made the ordinary way)"
Write-Host "verify-promptenter: prompt  6131, DELETEF"
Write-Host ''
Write-Host '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
Write-Host ''

try {
    # --- setup -------------------------------------------------------------
    $null = Invoke-SD @("DELETE.FILE $Probe", 'Y', 'Y', 'Y')   # any leftover
    $null = Invoke-SD @("DELETE.FILE $($ProbeL.ToLower())", 'Y', 'Y', 'Y')
    $mk = Invoke-SD @('OPTION CREATE.FILE.UPCASE', "CREATE.FILE $Probe")
    if ($mk.Text -notmatch "Created DATA part as $Probe") {
        Bail 2 "could not create $Probe - the setup, not the measurement, failed.`n$($mk.Text)"
    }
    $ls = Invoke-SD @("LISTF $Probe")
    if ($ls.Text -notmatch '1 record\(s\) listed') {
        Bail 2 "$Probe was not listed after creation - nothing to measure."
    }

    # THE PREMISE OF LEGS 1 AND 2, MEASURED.  CT prints the id it MATCHED, not
    # the one typed (CT:210), so asking for the lower name must echo the UPPER
    # id.  The echoed command carries only the lower spelling, and the refusal
    # (2108 "Record 'x' not found") carries the name as typed, so neither can
    # produce "VOC ZZPROMPTE" - hence -cmatch, and the disqualifier as well.
    $ct = Invoke-SD @("CT VOC $($Probe.ToLower())")
    $isUpper = ($ct.Text -cmatch "VOC $Probe\b") -and ($ct.Text -notmatch 'not found')
    Write-Host "  setup: CT VOC $($Probe.ToLower()) said:"
    Write-Host $ct.Text
    if (-not $isUpper) {
        Bail 2 "$Probe's VOC record is not stored in upper case - legs 1 and 2 could not reach 6131, so nothing would be measured."
    }
    Write-Host "  setup: $Probe created, listed, and its VOC id is upper case"
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
    Write-Host ''

    # --- LEG 3: RELEASE_1.1 27, a lower-case id deleted by its UPPER name ------
    #
    # CREATE.FILE stores this one lower (phase (a)).  Typed in upper case,
    # DELETEF must find it on its lower-case tier: no 6130, no 6131, deleted.
    # No answer lines are supplied, so a prompt that did appear would take its
    # default N and the file would survive - which the last row catches.
    $lowerL = $ProbeL.ToLower()
    Write-Host "--- leg 3: CREATE.FILE $ProbeL (stored lower), DELETE.FILE $ProbeL ----"
    $mk3 = Invoke-SD @("CREATE.FILE $ProbeL")
    $ct3 = Invoke-SD @("CT VOC $ProbeL")
    Write-Host $ct3.Text
    # Precondition, and the reason it is decisive: if the id were stored upper
    # this leg would pass on an exact match and say nothing about the fold.
    $isLower = ($ct3.Text -cmatch "VOC $lowerL\b") -and ($ct3.Text -notmatch 'not found')
    Row "leg 3 precondition: $ProbeL was created and stored as $lowerL" $isLower `
        "CT VOC $ProbeL did not echo 'VOC $lowerL' - phase (a) is not on this install or the create failed.`n$($mk3.Text)"
    if ($isLower) {
        $d3 = Invoke-SD @("DELETE.FILE $ProbeL")
        Write-Host $d3.Text
        Row 'leg 3: the run terminated' (-not $d3.Killed) "killed after ${TimeoutSeconds}s"
        Row 'leg 3: no 6130 - the lower-case tier found the record' `
            ($d3.Text -notmatch 'No VOC record found') 'DELETEF printed 6130, so it did not try lower case'
        Row 'leg 3: no 6131 prompt' ($d3.Text -notmatch 'Use file') 'DELETEF asked - the lower tier is meant to be silent'
        # SUCCESS WORDING, NOT THE ABSENCE OF AN ERROR: 6144 with the stored id.
        Row "leg 3: SD reported VOC entry '$lowerL' deleted" `
            ($d3.Text -cmatch "VOC entry '$lowerL' deleted") 'no 6144 success line naming the lower-case id'
        $after3 = Invoke-SD @("CT VOC $lowerL")
        Row "leg 3: the VOC record is gone" ($after3.Text -match 'not found') `
            "CT VOC $lowerL still finds the record"
    }
}
finally {
    $null = Invoke-SD @("DELETE.FILE $Probe", 'Y', 'Y', 'Y')
    $null = Invoke-SD @("DELETE.FILE $($ProbeL.ToLower())", 'Y', 'Y', 'Y')
    $left  = Invoke-SD @("LISTF $Probe")
    $leftL = Invoke-SD @("CT VOC $($ProbeL.ToLower())")
    Write-Host ''
    Write-Host ("cleanup: $Probe left behind = " + ($left.Text -match '1 record\(s\) listed'))
    Write-Host ("cleanup: $ProbeL left behind = " + ($leftL.Text -notmatch 'not found'))
}

Write-Host ''
Write-Host "verify-promptenter: $pass passed, $fail failed"
if ($fail -gt 0) { Bail 1 "$fail check(s) failed." }
Bail 0 "Enter took the default at prompt 6131, the control proves the prompt was live, and a lower-case id was deleted by its upper-case name."
