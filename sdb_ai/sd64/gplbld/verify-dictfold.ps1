<#
.SYNOPSIS
    A dictionary item stored in LOWER case is found when a query, CD or an
    I-type names it in UPPER case.  ***AN ORDINARY UNELEVATED PROMPT.***

.DESCRIPTION
    RELEASE_1.1_FIXES.md 5, stage 2a: every dictionary read folds - as given,
    then lower, then upper - as VOC reads already did.  It is the additive half
    that must be installed and witnessed BEFORE stage 2b renames the shipped
    dictionary ids (and @ID) to lower case, or every query, CD and I-type that
    names them in upper case would stop resolving.

    ***EVERY DECISIVE ROW WAS RED ON THE b155 INSTALL, MEASURED FIRST*** (scratch
    probe, 14 Sep 2026, own account, a file whose dictionary held f1 and xtype):
      - LIST zzdfprobe F1   did not use the dictionary's f1: the column heading
                            was 15 wide ("F1" plus 13 dots), f1's format is 5L
      - CD zzdfprobe xtype  "*** Field 'F1' is not defined" - ICOMP read the
                            upper-cased token twice and never the name as written
      - CD zzdfprobe XTYPE  "Source record 'XTYPE' not found"
      - LIST zzdfprobe xtype  "Compilation error in compiled dictionary item"
                            (after the failed CD; COPY had carried a compiled
                            object across, which LIST runs if no CD failed)

    THE FIXTURE is copied out of SDSYS's own shipped dictionary, so nothing here
    invents a dictionary record: DICT VOC's F1 and F3 become f1 and f3, and its
    TYPE I-type - whose expression names F1 and F3 in upper case - becomes
    xtype.  The data record is VOC's who verb (field 1 "Verb to show...", field
    3 "16"), so xtype must evaluate to V.

    BOUNDED like verify-promptenter: every session is a job, killed after
    -TimeoutSeconds, any sd.exe left killed BY PID DIFF, never by name.

.PARAMETER Account
    The SD account to work in.  Defaults to the caller's own.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 the test could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-dictfold.ps1
#>

[CmdletBinding()]
param(
    [string]$Account = $env:USERNAME,
    [int]$TimeoutSeconds = 40
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$AcctDir = Join-Path (Join-Path $env:ProgramData 'SD\user_accounts') $Account
$File    = 'zzdf' + (Get-Date -Format 'HHmmss')

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}
function Bail([int]$code, [string]$why) {
    Write-Host ''
    if ($code -eq 0) { Write-Host "verify-dictfold: PASSED - $why" }
    elseif ($code -eq 1) { Write-Host "verify-dictfold: FAILED - $why" }
    else { Write-Host "verify-dictfold: COULD NOT RUN - $why" }
    exit $code
}

function Invoke-SD([string[]]$lines) {
    $body = "`n" + ((@('TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"
    $before = @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue | ForEach-Object { $_.Id })
    $job = Start-Job -ScriptBlock {
        param($exe, $text)
        $text | & $exe 2>&1
    } -ArgumentList $sdExe, $body
    $killed = $false
    if (-not (Wait-Job $job -Timeout $TimeoutSeconds)) {
        $killed = $true
        Stop-Job $job -ErrorAction SilentlyContinue
        foreach ($p in @(Get-Process -Name 'sd' -ErrorAction SilentlyContinue)) {
            if ($before -notcontains $p.Id) { try { $p.Kill() } catch { } }
        }
    }
    $out = @(Receive-Job $job -ErrorAction SilentlyContinue)
    Remove-Job $job -Force -ErrorAction SilentlyContinue
    $text = ($out | Out-String) -replace ([char]27 + '\[[0-9]*[A-Za-z]'), ''
    return [pscustomobject]@{ Text = $text; Killed = $killed }
}
function Show([string]$label, $r) {
    Write-Host "  --- $label ---"
    foreach ($l in ($r.Text -split "`r?`n")) {
        if ($l -match '^\s*:?\s*$|Ladybridge|free software|welcome to modify|conditions\.  For|^SD Core for') { continue }
        Write-Host ("    " + $l)
    }
    if ($r.Killed) { Write-Host "    *** KILLED after $TimeoutSeconds s" }
}
function Remove-Fixtures {
    foreach ($d in @(Get-ChildItem -LiteralPath $AcctDir -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '(?i)^zzdf[0-9]{6}$' })) {
        $null = Invoke-SD @("DELETE.FILE $($d.Name.ToLower())", 'Y', 'Y', 'Y')
        foreach ($p in @($d.FullName, ($d.FullName + '.DIC'))) {
            if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Recurse -Force -ErrorAction SilentlyContinue }
        }
        Write-Host "    swept $($d.Name)"
    }
}

# --- refusals ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $sdExe)) { Bail 2 "no sd.exe at $sdExe" }
if (-not (Test-Path -LiteralPath (Join-Path $AcctDir 'bp'))) {
    Bail 2 "no bp directory in $AcctDir - pass -Account with an SD account name."
}
Write-Host "verify-dictfold: account $Account"
Write-Host "verify-dictfold: dir     $AcctDir"
Write-Host "verify-dictfold: sd.exe  $sdExe"
Write-Host "verify-dictfold: file    $File"
Write-Host ''
Write-Host '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
Write-Host ''
Write-Host '--- sweep leftovers ---------------------------------------------------'
Remove-Fixtures

try {
    # --- setup: a dictionary holding f1, f3 and xtype, a record r1 ----------
    Write-Host ''
    Write-Host '--- setup ------------------------------------------------------------'
    $mk = Invoke-SD @(
        "CREATE.FILE $File",
        "COPY FROM DICT VOC TO DICT $File F1,f1",
        "COPY FROM DICT VOC TO DICT $File F3,f3",
        "COPY FROM DICT VOC TO DICT $File TYPE,xtype",
        "COPY FROM VOC TO $File who,r1",
        "LIST DICT $File")
    Show 'setup' $mk
    if ($mk.Text -notmatch "Created DATA part as $File") { Bail 2 "could not create $File - setup, not measurement, failed." }
    $copied = [regex]::Matches($mk.Text, '(?m)^1 record\(s\) copied\.').Count
    Row 'setup: four COPY commands each copied one record' ($copied -eq 4) "copied lines: $copied"
    foreach ($id in @('f1', 'f3', 'xtype')) {
        Row "setup: the dictionary holds '$id', lower case" ($mk.Text -cmatch ('(?m)^' + [regex]::Escape($id) + '\s{2,}[DI]\s')) "no LIST DICT row for $id"
    }
    if ($fail -gt 0) { Bail 2 'the fixture is not what the legs assume - nothing below would measure the fold.' }

    # --- leg 1: a query names f1 as F1 ---------------------------------------
    # The column heading is the dictionary item's display name padded to its
    # format width with dots: f1 is "F1" at 5L, so "F1..." (three dots).  The
    # b155 install showed "F1" and thirteen dots - not f1 at all.
    Write-Host ''
    Write-Host '--- leg 1: LIST names the field in upper case ---------------------------'
    $q = Invoke-SD @("LIST $File F1", "LIST $File f1")
    Show 'LIST F1, LIST f1' $q
    $heads = @([regex]::Matches($q.Text, ('(?m)^' + [regex]::Escape($File) + '\.*\s+(F1\.*)\s*$')) | ForEach-Object { $_.Groups[1].Value })
    Write-Host ("  column headings, in order: " + ($heads -join ' | '))
    Row 'leg 1: both LISTs printed a column heading' ($heads.Count -eq 2) "got $($heads.Count)"
    Row "CONTROL leg 1: f1 typed lower uses the dictionary item (heading 'F1...')" (($heads.Count -eq 2) -and ($heads[1] -ceq 'F1...')) ($heads -join ' | ')
    Row "leg 1: F1 typed UPPER uses the same dictionary item (heading 'F1...')" (($heads.Count -eq 2) -and ($heads[0] -ceq 'F1...')) ($heads -join ' | ')

    # --- leg 2a: CD xtype (name typed as stored) - the EXPRESSION's F1 and F3 --
    # ***COPY CARRIED THE COMPILED OBJECT ACROSS*** (measured: on the pre-2a
    # install LIST xtype evaluated V with no compile at all), so a row that only
    # looks for the absence of an error passes when nothing was compiled.  Each
    # no-error row therefore REQUIRES the "Compiling xtype" line in the same
    # transcript.  Typed in lower case here so this leg isolates ICOMP's field
    # lookup from CD's own name lookup, which leg 2b takes.
    Write-Host ''
    Write-Host '--- leg 2a: CD xtype - the expression names F1 and F3 in upper case ----'
    $cda = Invoke-SD @("CD $File xtype")
    Show "CD $File xtype" $cda
    $compiledA = ($cda.Text -cmatch '(?m)^Compiling xtype\s*$')
    Row "leg 2a: CD reached the compiler ('Compiling xtype')" $compiledA 'no Compiling line - nothing below would be measured'
    Row 'leg 2a: the expression''s F1 and F3 resolved to f1 and f3 (compiled, no error)' `
        ($compiledA -and ($cda.Text -notmatch 'is not defined') -and ($cda.Text -notmatch 'Compilation error')) 'a field name in the expression did not fold'

    # --- leg 2b: CD XTYPE - CD's own lookup of the item name -----------------
    Write-Host ''
    Write-Host '--- leg 2b: CD XTYPE - the item name typed in upper case ----------------'
    $cd = Invoke-SD @("CD $File XTYPE")
    Show "CD $File XTYPE" $cd
    Row 'leg 2b: CD found the item typed in upper case (no "not found")' ($cd.Text -notmatch "Source record 'XTYPE' not found") 'CD did not fold the name'
    Row "leg 2b: CD compiled it under its own id ('Compiling xtype', no error)" `
        (($cd.Text -cmatch '(?m)^Compiling xtype\s*$') -and ($cd.Text -notmatch 'is not defined|Compilation error')) 'no clean Compiling line naming xtype'

    # --- leg 3: the compiled I-type evaluates ---------------------------------
    Write-Host ''
    Write-Host '--- leg 3: LIST xtype evaluates the compiled I-type --------------------'
    $ev = Invoke-SD @("LIST $File xtype")
    Show "LIST $File xtype" $ev
    Row 'leg 3: no compile error at query time' ($ev.Text -notmatch 'is not defined|Compilation error') 'the query recompiled and failed'
    Row "leg 3: r1's type evaluates to V (who is a verb)" ($ev.Text -match '(?m)^r1\s+V\s*$') 'no "r1  V" row'
}
finally {
    Write-Host ''
    Write-Host '--- cleanup ----------------------------------------------------------'
    Remove-Fixtures
    $left = Invoke-SD @("LISTF $File")
    Row 'cleanup: the file is gone from VOC' ($left.Text -match "'$File' not found") 'LISTF still lists it'
    Row 'cleanup: no zzdf directory is left' (@(Get-ChildItem -LiteralPath $AcctDir -Directory | Where-Object { $_.Name -match '(?i)^zzdf' }).Count -eq 0) 'a directory remains'
}

Write-Host ''
Write-Host "verify-dictfold: $pass passed, $fail failed"
if (($pass + $fail) -eq 0) { Bail 2 'no check ran - a broken test, not a pass.' }
if ($fail -gt 0) { Bail 1 "$fail check(s) failed." }
Bail 0 'a lower-case dictionary item is found when LIST, CD and an I-type name it in upper case.'
