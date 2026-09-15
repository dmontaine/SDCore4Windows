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

    ***15 Sep 2026 - LEGS 1 AND 2 ARE RETIRED, AND 6131 WITH THEM.***
    RELEASE_1.1 5 D2 made every hashed file case insensitive, so DELETEF's
    exact read finds the upper-case record by its lower name and never reaches
    6131.  Leg 1 now asserts that: deleted, no 6130, no prompt.  The paragraphs
    below about 6131 are history.

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

    ***LEGS 4 AND 5 PRESS ENTER AT FOUR MORE PROMPTS - 13 Sep 2026, RELEASE_1.1
    6.***  That entry had 6135, 6140, 3033, 3034 and 3035 reached by no
    verifier.  Leg 4 is DELETEF's 6135 and 6140: a second VOC pointer made with
    COPY (zzpromptx -> zzpromptd) is a file whose stored paths differ from its
    own name, which is the branch that asks - a plain DELETE.FILE asks nothing.
    Leg 5 is CATALOG's 3033 and 3034: a program catalogued LOCAL then private
    meets 3033, and LOCAL again meets 3034.  Every leg has its Y control, and
    every behaviour was captured from a real session before these were written.
    3035 is NOT here and cannot be: it needs a matching GLOBAL catalogue entry,
    every gcat name carries a $ ! * prefix (152 of 152, measured) that a private
    or local name cannot, and writing gcat is administrator-only.

    ***LEGS 6, 7 AND 8 - 13 Sep 2026.***  Leg 6 is CPROC's .D prompt 5040, the
    last of RELEASE_1.1 6's seven.  Legs 7 and 8 are RELEASE_1.1 33, the owner's
    ruling on the two prompts 6 left alone: message 2050 ("Use active select
    list") now defaults to N in its six verbs, driven here through CT; and
    DELETEF's 6133 on a multifile gains C to cancel, which Enter now means -
    driven on a two-component multifile, with N (dictionary only) as the control.

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
$FileD  = 'zzpromptd'   # leg 4: the real file
$FileX  = 'zzpromptx'   # leg 4: a second VOC pointer to it, so its paths differ from its name
$ProgP  = 'ZZPROMPTP'   # leg 5: a program catalogued LOCAL and private in turn
$SentV  = 'zzpromptv'   # leg 6: a sentence saved with .S, for CPROC's .D prompt 5040
$MultiM = 'zzpromptm'   # leg 8: a two-component multifile, for DELETEF's 6133

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
Write-Host "verify-promptenter: file    $Probe  (leg 1, made with OPTION CREATE.FILE.UPCASE)"
Write-Host "verify-promptenter: file    $ProbeL  (leg 3, made the ordinary way)"
Write-Host "verify-promptenter: prompts 6135 6140 3033 3034 5040 2050 6133 (6131 unreachable under D2)"
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

    # 15 Sep 26 - LEGS 1 AND 2 RETIRED, OWNER'S RULING ("retire and replace").
    # They pressed Enter at 6131, which DELETEF asks only when its exact read of
    # the typed name MISSES and the upcase read hits.  RELEASE_1.1 5 D2 made VOC
    # case insensitive, so the exact read of 'zzprompte' hits ZZPROMPTE itself:
    # 6131 is unreachable on a D2 install, and b161's premise check (CT echoed
    # the spelling typed, not the one stored) refused for exactly that reason.
    # ***6131's ENTER DEFAULT IS THEREFORE WITNESSED NOWHERE NOW.***
    #
    # THE REPLACEMENT is what D2 means for the same fixture: the lower-case name
    # deletes the upper-case record with no 6130 and no prompt.  No answer line
    # is supplied, so a prompt that did appear would take its default N and the
    # file would survive - which the last row catches.
    #
    # THE PREMISE IS READ FROM THE DISK, NOT FROM CT: CT echoes the spelling
    # typed on a NOCASE VOC, while CREATE.FILE names the directory as it stores
    # the id, and OPTION CREATE.FILE.UPCASE keeps both as typed.
    $acct0 = Join-Path $Root $Account
    $upDir = @(Get-ChildItem -LiteralPath $acct0 -Directory | Where-Object { $_.Name -ceq $Probe })
    if ($upDir.Count -ne 1) {
        Bail 2 "no directory named exactly $Probe - OPTION CREATE.FILE.UPCASE did not keep the case, so leg 1 would not start from an upper-case record."
    }
    Write-Host "  setup: $Probe created, listed, and its directory is upper case"
    Write-Host ''

    # --- LEG 1: a lower-case name deletes the upper-case record, no prompt ---
    $lower = $Probe.ToLower()
    Write-Host "--- leg 1: DELETE.FILE $lower on the upper-case $Probe - no prompt (D2) ----"
    $r = Invoke-SD @("DELETE.FILE $lower")
    Write-Host $r.Text
    Row 'leg 1: the run terminated (no runaway loop)' (-not $r.Killed) `
        "the child had to be killed after ${TimeoutSeconds}s - this is the hang entry 6 is about"
    Row 'leg 1: no 6130 - the record was found as typed' `
        ($r.Text -notmatch 'No VOC record found') 'DELETEF printed 6130 - VOC did not find the upper-case id by its lower name'
    Row 'leg 1: no 6131 prompt' ($r.Text -notmatch 'Use file') 'DELETEF asked 6131 - the exact read missed on a case-insensitive VOC'
    # SUCCESS WORDING: 6144.  Case-blind, because it may name the id as typed.
    Row "leg 1: SD reported VOC entry '$lower' deleted (any case)" `
        ($r.Text -match "VOC entry '$lower' deleted") 'no 6144 success line'
    $after = Invoke-SD @("LISTF $Probe")
    Row "leg 1: $Probe is gone - VOC and directory" `
        (($after.Text -notmatch '1 record\(s\) listed') -and -not (Test-Path -LiteralPath (Join-Path $acct0 $Probe))) `
        "LISTF still lists $Probe, or its directory is still on disk"
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
    Write-Host $mk3.Text
    # Precondition, and the reason it is decisive: if the id were stored upper
    # this leg would say nothing about the lower-case tier.  15 Sep 26 - read
    # from the DIRECTORY name, not CT's echo, which under D2 repeats the
    # spelling typed (see the leg 1 note).  CREATE.FILE names it as it stores the id.
    $isLower = ($mk3.Text -match "Created DATA part as $lowerL") -and
               (@(Get-ChildItem -LiteralPath (Join-Path $Root $Account) -Directory | Where-Object { $_.Name -ceq $lowerL }).Count -eq 1)
    Row "leg 3 precondition: $ProbeL was created and stored as $lowerL" $isLower `
        "no directory named exactly $lowerL - phase (a) is not on this install or the create failed.`n$($mk3.Text)"
    if ($isLower) {
        $d3 = Invoke-SD @("DELETE.FILE $ProbeL")
        Write-Host $d3.Text
        Row 'leg 3: the run terminated' (-not $d3.Killed) "killed after ${TimeoutSeconds}s"
        Row 'leg 3: no 6130 - the lower-case tier found the record' `
            ($d3.Text -notmatch 'No VOC record found') 'DELETEF printed 6130, so it did not try lower case'
        Row 'leg 3: no 6131 prompt' ($d3.Text -notmatch 'Use file') 'DELETEF asked - the lower tier is meant to be silent'
        # SUCCESS WORDING, NOT THE ABSENCE OF AN ERROR: 6144 with the stored id.
        # 15 Sep 26 - case-blind: under D2 6144 may name the id as typed.
        Row "leg 3: SD reported VOC entry '$lowerL' deleted (any case)" `
            ($d3.Text -match "VOC entry '$lowerL' deleted") 'no 6144 success line'
        $after3 = Invoke-SD @("CT VOC $lowerL")
        Row "leg 3: the VOC record is gone" ($after3.Text -match 'not found') `
            "CT VOC $lowerL still finds the record"
    }
    Write-Host ''

    # --- LEG 4: RELEASE_1.1 6, DELETEF 6135 and 6140 ----------------------------
    #
    # DELETEF asks 6135/6140 only when the stored DATA/DICT path differs from
    # the name typed.  COPY FROM VOC makes exactly that: zzpromptx whose field 2
    # is zzpromptd.  Enter at both must delete nothing; the control, Y at both,
    # deletes both portions of zzpromptd (captured 13 Sep 2026: "DATA portion
    # 'zzpromptd' deleted" / "DICT portion 'zzpromptd.DIC' deleted").
    Write-Host "--- leg 4: DELETEF 6135 + 6140 via a second VOC pointer ($FileX -> $FileD) ---"
    $acctDir = Join-Path $Root $Account
    $dDir    = Join-Path $acctDir $FileD
    $dDic    = Join-Path $acctDir ($FileD + '.DIC')
    $null = Invoke-SD @("DELETE VOC $FileX")                             # leftovers of an earlier run
    $null = Invoke-SD @("DELETE.FILE $FileD", 'Y', 'Y', 'Y')
    $mk4 = Invoke-SD @("CREATE.FILE $FileD", "COPY FROM VOC $FileD,$FileX", "CT VOC $FileX")
    Write-Host $mk4.Text
    # PRECONDITION: the pointer exists and names the other file.  Without it
    # DELETEF would ask nothing and every "nothing deleted" row would pass.
    $ptrOk = ($mk4.Text -match '1 record\(s\) copied') -and ($mk4.Text -cmatch "(?m)^\s*2: $FileD\s*$")
    Row "leg 4 precondition: $FileX is a VOC pointer to $FileD" $ptrOk `
        'COPY did not make the pointer, so DELETEF would not ask - nothing below could be measured'
    if ($ptrOk) {
        $e4 = Invoke-SD @("DELETE.FILE $FileX", '', '')
        Write-Host $e4.Text
        Row 'leg 4: the run terminated (no runaway loop)' (-not $e4.Killed) "killed after ${TimeoutSeconds}s"
        Row 'leg 4: the transcript is a sane size' ($e4.Text.Length -lt 200000) "$($e4.Text.Length) bytes"
        Row 'leg 4: prompt 6135 was reached, showing (y/<n>)' `
            ($e4.Text -match "OK to delete DATA portion '$FileD' \(y/<n>\)\?") 'no 6135 prompt for the DATA portion'
        Row 'leg 4: prompt 6140 was reached, showing (y/<n>)' `
            ($e4.Text -match "OK to delete DICT portion '$FileD\.DIC' \(y/<n>\)\?") 'no 6140 prompt for the DICT portion'
        Row 'leg 4: ENTER at both deleted nothing' `
            (($e4.Text -notmatch "portion '[^']*' deleted") -and ($e4.Text -notmatch "VOC entry '[^']*' deleted")) `
            'a deletion was reported - Enter was taken as YES'
        Row 'leg 4: both portions survive on disk' ((Test-Path -LiteralPath $dDir) -and (Test-Path -LiteralPath $dDic)) `
            "$dDir or its .DIC is gone after Enter"

        # CONTROL: Y at both must delete, or "survived" above measured nothing.
        $y4 = Invoke-SD @("DELETE.FILE $FileX", 'Y', 'Y')
        Write-Host $y4.Text
        Row "CONTROL leg 4: Y deletes DATA portion '$FileD'" ($y4.Text -match "DATA portion '$FileD' deleted") `
            'no 6136 - the prompt is not driving a deletion'
        Row "CONTROL leg 4: Y deletes DICT portion '$FileD.DIC'" ($y4.Text -match "DICT portion '$FileD\.DIC' deleted") `
            'no 6141'
        Row 'CONTROL leg 4: both portions are gone from disk' `
            (-not (Test-Path -LiteralPath $dDir) -and -not (Test-Path -LiteralPath $dDic)) 'a portion survived an explicit Y'
    }
    Write-Host ''

    # --- LEG 5: RELEASE_1.1 6, CATALOG 3033 and 3034 ----------------------------
    #
    # LOCAL then private meets 3033 ("also in local catalogue"); LOCAL again
    # meets 3034 ("also in private catalogue").  Enter keeps each entry; Y
    # removes it.  Local is a VOC record (V / CS); private is a record in the
    # account's cat directory.  Captured 13 Sep 2026 before writing this.
    Write-Host "--- leg 5: CATALOG 3033 + 3034 on $ProgP ------------------------------"
    $catRec = Join-Path (Join-Path $acctDir 'cat') $ProgP
    $srcRec = Join-Path $bpDir $ProgP
    [System.IO.File]::WriteAllText($srcRec,
        ("* $ProgP - written by verify-promptenter.ps1.  Safe to delete.`n   crt '$ProgP-RAN'`nend`n"),
        [System.Text.Encoding]::GetEncoding('iso-8859-1'))
    $mk5 = Invoke-SD @("BASIC BP $ProgP", "CATALOG BP $ProgP LOCAL", "CT VOC $ProgP")
    Write-Host $mk5.Text
    $localOk = ($mk5.Text -match "$ProgP added to local catalogue") -and ($mk5.Text -cmatch '(?m)^\s*2: CS\s*$')
    Row "leg 5 precondition: $ProgP compiled and is in the LOCAL catalogue (V / CS)" $localOk `
        'the program is not locally catalogued, so 3033 could not be reached'
    if ($localOk) {
        # 3033: catalogue privately while the local entry exists; Enter.
        $e33 = Invoke-SD @("CATALOG BP $ProgP", '', "CT VOC $ProgP")
        Write-Host $e33.Text
        Row 'leg 5: the 3033 run terminated' (-not $e33.Killed) "killed after ${TimeoutSeconds}s"
        Row 'leg 5: prompt 3033 was reached, showing (y/<n>)' `
            ($e33.Text -match 'Program is also in local catalogue\. Remove \(y/<n>\)\?') 'no 3033 prompt'
        Row 'leg 5: ENTER at 3033 kept the LOCAL entry (V / CS still there)' `
            ($e33.Text -cmatch '(?m)^\s*2: CS\s*$') 'the VOC V/CS record is gone after Enter'
        Row "leg 5: and the private entry was written ($catRec)" (Test-Path -LiteralPath $catRec) `
            'no private catalogue record, so 3034 below could not be reached'

        # 3034: catalogue LOCAL while the private entry exists; Enter.
        $e34 = Invoke-SD @("CATALOG BP $ProgP LOCAL", '')
        Write-Host $e34.Text
        Row 'leg 5: the 3034 run terminated' (-not $e34.Killed) "killed after ${TimeoutSeconds}s"
        Row 'leg 5: prompt 3034 was reached, showing (y/<n>)' `
            ($e34.Text -match 'Program is also in private catalogue\. Remove \(y/<n>\)\?') 'no 3034 prompt'
        Row 'leg 5: ENTER at 3034 kept the private entry' (Test-Path -LiteralPath $catRec) `
            'the private catalogue record is gone after Enter'

        # CONTROLS: Y removes each.
        $y34 = Invoke-SD @("CATALOG BP $ProgP LOCAL", 'Y')
        Row 'CONTROL leg 5: Y at 3034 removes the private entry' `
            (($y34.Text -match 'Program is also in private catalogue') -and -not (Test-Path -LiteralPath $catRec)) `
            'the private record survived an explicit Y, or the prompt did not appear'
        $y33 = Invoke-SD @("CATALOG BP $ProgP", 'Y', "CT VOC $ProgP")
        Row 'CONTROL leg 5: Y at 3033 removes the LOCAL entry' `
            (($y33.Text -match 'Program is also in local catalogue') -and ($y33.Text -match "Record '$ProgP' not found")) `
            'the VOC V/CS record survived an explicit Y, or the prompt did not appear'
    }
    Write-Host ''

    # --- LEG 6: RELEASE_1.1 6, CPROC's .D prompt 5040 --------------------------
    #
    # The seventh prompt, and the only one of the seven b152 had not pressed
    # Enter at: b136 answered it with a real Y inside verify-vocverbs entry 5.
    # ".S <name> 1" saves the previous command as an S-type VOC record - the
    # shape verify-vocverbs proved ("001  S" in the listing; a record that is
    # neither S nor PA takes 5041 and never asks).  CPROC:1202 asks 5040; Enter
    # now means N, which releases the record and leaves without deleting.
    Write-Host "--- leg 6: CPROC .D prompt 5040 on the sentence $SentV ----------------"
    $null = Invoke-SD @("DELETE VOC $SentV")                              # leftover of an earlier run
    $mk6 = Invoke-SD @(".S $SentV 1", ".L $SentV")
    Write-Host $mk6.Text
    $sentOk = $mk6.Text -match '(?m)^[ \t]*001[ \t]+S[ \t]*\r?$'
    Row "leg 6 precondition: .S wrote $SentV as an S-type record" $sentOk `
        'no "001  S" line, so .D would take 5041 and never ask 5040'
    if ($sentOk) {
        $e6 = Invoke-SD @(".D $SentV", '', ".L $SentV")
        Write-Host $e6.Text
        Row 'leg 6: the run terminated (no runaway loop)' (-not $e6.Killed) "killed after ${TimeoutSeconds}s"
        Row 'leg 6: the transcript is a sane size' ($e6.Text.Length -lt 200000) "$($e6.Text.Length) bytes"
        Row 'leg 6: prompt 5040 was reached, showing (y/<n>)' `
            ($e6.Text -match "Delete VOC record '$SentV' \(y/<n>\)\?") 'no 5040 prompt'
        Row 'leg 6: ENTER kept the sentence (001  S still listed)' `
            (($e6.Text -match '(?m)^[ \t]*001[ \t]+S[ \t]*\r?$') -and ($e6.Text -notmatch "'$SentV' not found in VOC")) `
            'the sentence is gone after Enter - Enter was taken as YES'

        # CONTROL: Y must delete, or "still listed" above measured nothing.
        $y6 = Invoke-SD @(".D $SentV", 'Y', ".L $SentV")
        Write-Host $y6.Text
        Row 'CONTROL leg 6: the prompt was reached again' ($y6.Text -match "Delete VOC record '$SentV'") `
            'the control did not reach 5040'
        Row 'CONTROL leg 6: Y deleted the sentence' ($y6.Text -match "'$SentV' not found in VOC") `
            '.L still lists the sentence after an explicit Y'
    }
    Write-Host ''

    # --- LEG 7: RELEASE_1.1 33, message 2050 (select list), owner's ruling -----
    #
    # "Use active select list (First item 'x') (y/<n>)?", asked by six verbs; CT is
    # the harmless one to drive - it only displays.  Captured 13 Sep 2026 before
    # the change: SSELECT VOC SAMPLE 1 then CT VOC asks 2050 naming the first id;
    # N stops, Y prints "VOC <id>" and the record.  Enter must now mean N.
    Write-Host '--- leg 7: message 2050 - an active select list, then CT VOC ------------'
    $e7 = Invoke-SD @('SSELECT VOC SAMPLE 1', 'CT VOC', '', 'WHO')
    Write-Host $e7.Text
    $first7 = [regex]::Match($e7.Text, "First item '([^']+)'")
    Row 'leg 7: the run terminated (no runaway loop)' (-not $e7.Killed) "killed after ${TimeoutSeconds}s"
    Row 'leg 7: prompt 2050 was reached, showing (y/<n>)' `
        ($e7.Text -match "Use active select list \(First item '[^']+'\) \(y/<n>\)\?") 'no 2050 prompt carrying (y/<n>)'
    if ($first7.Success) {
        $id7 = $first7.Groups[1].Value
        Row "leg 7: ENTER displayed nothing (no 'VOC $id7' record)" `
            ($e7.Text -notmatch ('(?m)^VOC ' + [regex]::Escape($id7) + '\s*$')) 'the record was displayed - Enter was taken as YES'
        # The line after the Enter ran as a command, so the prompt ended rather
        # than eating it: WHO answers with the account name.
        Row 'leg 7: the session went on to the next command (WHO answered)' `
            ($e7.Text -match "(?m)^\s*\d+\s+$([regex]::Escape($Account))\b") 'WHO did not answer - the prompt swallowed it'
        $y7 = Invoke-SD @('SSELECT VOC SAMPLE 1', 'CT VOC', 'Y')
        Row "CONTROL leg 7: Y displays the record 'VOC $id7'" `
            ($y7.Text -match ('(?m)^VOC ' + [regex]::Escape($id7) + '\s*$')) 'Y did not display it - the prompt is not driving anything'
    }
    Write-Host ''

    # --- LEG 8: RELEASE_1.1 33, DELETEF 6133 gains C to cancel, owner's ruling --
    #
    # A multifile with two data components reaches 6133.  Captured 13 Sep 2026
    # before the change: CREATE.FILE ZZPROMPTM,C1 then ,C2 makes it (field 4
    # "c1<vm>c2"); N at 6133 deletes the DICTIONARY only; Y goes on to ask 6135
    # for each component.  Now: Enter means C, and C deletes nothing.
    Write-Host "--- leg 8: DELETEF 6133 on the multifile $MultiM ---------------------"
    $mDir = Join-Path $acctDir $MultiM
    $mDic = Join-Path $acctDir ($MultiM + '.DIC')
    $null = Invoke-SD @("DELETE VOC $MultiM")
    foreach ($p in @($mDir, $mDic)) { if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue } }
    $mk8 = Invoke-SD @("CREATE.FILE $($MultiM.ToUpper()),C1", "CREATE.FILE $($MultiM.ToUpper()),C2", "CT VOC $MultiM")
    Write-Host $mk8.Text
    $multiOk = ($mk8.Text -match "Created DATA part as $MultiM/c2") -and (Test-Path -LiteralPath (Join-Path $mDir 'c1')) -and
               (Test-Path -LiteralPath (Join-Path $mDir 'c2')) -and (Test-Path -LiteralPath $mDic)
    Row "leg 8 precondition: $MultiM is a multifile with components c1 and c2 and a dictionary" $multiOk `
        'the multifile was not built, so 6133 could not be reached'
    if ($multiOk) {
        foreach ($ans in @(@{ Label = 'ENTER'; Line = '' }, @{ Label = 'an explicit C'; Line = 'C' })) {
            $r8 = Invoke-SD @("DELETE.FILE $MultiM", $ans.Line, 'WHO')
            Write-Host $r8.Text
            Row "leg 8 ($($ans.Label)): the run terminated" (-not $r8.Killed) "killed after ${TimeoutSeconds}s"
            Row "leg 8 ($($ans.Label)): prompt 6133 was reached, showing (y/n/<c>)" `
                ($r8.Text -match 'Delete all data components of multifile.*\(y/n/<c>\)\?') 'no 6133 prompt carrying (y/n/<c>)'
            Row "leg 8 ($($ans.Label)): nothing was deleted" `
                (($r8.Text -notmatch "portion '[^']*' deleted") -and ($r8.Text -notmatch "VOC entry '[^']*' deleted")) `
                'a deletion was reported - cancel did not cancel'
            Row "leg 8 ($($ans.Label)): both components and the dictionary survive on disk" `
                ((Test-Path -LiteralPath (Join-Path $mDir 'c1')) -and (Test-Path -LiteralPath (Join-Path $mDir 'c2')) -and (Test-Path -LiteralPath $mDic)) `
                'a part of the multifile is gone'
            Row "leg 8 ($($ans.Label)): the session went on (WHO answered)" `
                ($r8.Text -match "(?m)^\s*\d+\s+$([regex]::Escape($Account))\b") 'WHO did not answer - the prompt swallowed it'
        }
        # CONTROL: N keeps its old meaning - the dictionary goes, the data stays.
        $n8 = Invoke-SD @("DELETE.FILE $MultiM", 'N')
        Write-Host $n8.Text
        Row "CONTROL leg 8: N deletes the dictionary only ('$MultiM.DIC' deleted)" `
            (($n8.Text -match "DICT portion '$MultiM\.DIC' deleted") -and (-not (Test-Path -LiteralPath $mDic)) -and
             (Test-Path -LiteralPath (Join-Path $mDir 'c1'))) 'N did not delete exactly the dictionary - the prompt is not driving the branch'
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

    # Legs 4 and 5.  DELETE VOC for the pointer and any dead record; DELETE.FILE
    # for a file that survived; DELETE.CATALOG for the private entry, and DELETE
    # VOC for a local one; then the source and object by file.  Checked, not
    # assumed: a VOC record left by a green run is RELEASE_1.1 26 and 31.
    $null = Invoke-SD @("DELETE VOC $FileX")
    $null = Invoke-SD @("DELETE.FILE $FileD", 'Y', 'Y', 'Y')
    $null = Invoke-SD @("DELETE VOC $FileD")
    $null = Invoke-SD @("DELETE.CATALOG $ProgP", "DELETE VOC $ProgP", "DELETE VOC $SentV")
    # Leg 8's multifile: every answer given explicitly - Y at 6133, then Y at
    # each component's 6135 (a component's path never equals the file name, so
    # DELETEF always asks; captured) - then the VOC record and a file fallback.
    $null = Invoke-SD @("DELETE.FILE $MultiM", 'Y', 'Y', 'Y')
    $null = Invoke-SD @("DELETE VOC $MultiM")
    foreach ($p in @((Join-Path (Join-Path $Root $Account) $MultiM), (Join-Path (Join-Path $Root $Account) ($MultiM + '.DIC')))) {
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
    }
    foreach ($f in @((Join-Path $bpDir $ProgP), (Join-Path (Join-Path (Join-Path $Root $Account) 'bp.out') $ProgP))) {
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
    }
    $gone = Invoke-SD @("CT VOC $FileX", "CT VOC $FileD", "CT VOC $ProgP", "CT VOC $SentV", "CT VOC $MultiM")
    foreach ($n in @($FileX, $FileD, $ProgP, $SentV, $MultiM)) {
        Row "cleanup: no VOC record '$n' is left" ($gone.Text -match "Record '$n' not found") "CT VOC $n still finds it"
    }
    $acctForClean = Join-Path $Root $Account
    $leftFiles = @((Join-Path $acctForClean $FileD), (Join-Path $acctForClean ($FileD + '.DIC')),
                   (Join-Path (Join-Path $acctForClean 'cat') $ProgP), (Join-Path $bpDir $ProgP),
                   (Join-Path $acctForClean $MultiM), (Join-Path $acctForClean ($MultiM + '.DIC'))) |
                 Where-Object { Test-Path -LiteralPath $_ }
    Row 'cleanup: no leg 4/5/8 file, catalogue record or source is left' ($leftFiles.Count -eq 0) ($leftFiles -join ', ')
}

Write-Host ''
Write-Host "verify-promptenter: $pass passed, $fail failed"
if ($fail -gt 0) { Bail 1 "$fail check(s) failed." }
Bail 0 "Enter took the default at 6135, 6140, 3033, 3034, 5040, 2050 and 6133 (cancel), each control proves its prompt was live, and a file was deleted by its name in the other case with no prompt, both ways."
