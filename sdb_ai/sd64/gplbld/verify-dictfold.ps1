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

    THE FIXTURE: DICT VOC's f1 and f3 are copied as they are shipped, and xtype
    is VOC's TYPE I-type as it shipped BEFORE stage 2b - its expression naming
    F1 and F3 in UPPER case - written into the account's bp and copied from
    there.  (14 Sep 26: stage 2b lowered the shipped expression's tokens, and
    COPY does not fold - measured, "COPY FROM DICT VOC ... f1" answered "Record
    'f1' not found" while F1 was stored - so copying TYPE would no longer test
    the upper-case tokens, and copying F1 would find nothing.)  The data record
    is VOC's who verb (field 1 "Verb to show...", field 3 "16"), so xtype must
    evaluate to V.

    ***AND STAGE 2b's OWN ROWS*** (legs 4 and 5, and two setup rows): the
    shipped ids are stored lower case - LIST DICT VOC's rows read -cmatch, type
    / f1 / @id / data.name present and their upper-case spellings absent - and
    CREATE.FILE writes @id, saying so in 6129.  Every one of those was upper
    case on the b157 install (measured the same day by scratch probe: sixteen
    upper-case ids, "Added default '@ID' record to dictionary").  Leg 5, a query
    naming TYPE and one naming type, is a regression control: 2a already made
    both work.

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
$XRec    = $File + 'xt'      # the pre-2b TYPE I-type, as a record in bp
# VOC's TYPE expression exactly as FILES_DICTS shipped it before stage 2b.
$XExpr   = 'IF F1[1,1]=''P'' THEN F1[1,2] ELSE F1[1,1];IF @ = ''K'' AND F3 # '''' THEN @:@VM:(IF F3[1,1]=''P'' THEN F3[1,2] ELSE F3[1,1]) ELSE @'

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
    foreach ($f in @(Get-ChildItem -LiteralPath (Join-Path $AcctDir 'bp') -File -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '(?i)^zzdf[0-9]{6}xt$' })) {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
        Write-Host "    swept bp record $($f.Name)"
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
    # The record is written with LF field marks and no BOM, the form a directory
    # file's record takes on disk (gplbld\FILES_DICTS is the same shape).
    $xPath = Join-Path (Join-Path $AcctDir 'bp') $XRec
    $xBody = (@('I', $XExpr, '', 'Type', '2L', 'S') -join "`n") + "`n"
    [System.IO.File]::WriteAllText($xPath, $xBody, (New-Object System.Text.ASCIIEncoding))
    Write-Host "  wrote $xPath"
    Write-Host "  expression: $XExpr"
    $mk = Invoke-SD @(
        "CREATE.FILE $File",
        "COPY FROM DICT VOC TO DICT $File f1,f1",
        "COPY FROM DICT VOC TO DICT $File f3,f3",
        "COPY FROM bp TO DICT $File $XRec,xtype",
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

    # --- stage 2b: CREATE.FILE's default record is @id ------------------------
    Row "2b: CREATE.FILE said it added '@id' (6129)" ($mk.Text -cmatch "(?m)^Added default '@id' record to dictionary") "no 6129 line naming '@id'"
    Row "2b: the new dictionary stores '@id' and no '@ID'" (($mk.Text -cmatch '(?m)^@id\s{2,}D\s') -and ($mk.Text -cnotmatch '(?m)^@ID\s{2,}D\s')) 'LIST DICT shows the default record under @ID, or not at all'

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
    # 14 Sep 26 - RELEASE_1.1 5 D2: every hashed file is case insensitive, so
    # CD's read of XTYPE hits xtype directly and CD echoes 'Compiling XTYPE'
    # as typed (b161).  AND CD WRITES THE COMPILED RECORD BACK UNDER THE NAME
    # TYPED (CD:302, :316), which re-stores the id as XTYPE - b162's LIST DICT
    # showed one record, XTYPE, and 4 records in all.  Cosmetic: no twin, no
    # loss.  So the rows are the D2 ones: exactly one row that folds to xtype,
    # and the record count unchanged.
    $cd = Invoke-SD @("CD $File XTYPE", "LIST DICT $File")
    Show "CD $File XTYPE, LIST DICT $File" $cd
    Row 'leg 2b: CD found the item typed in upper case (no "not found")' ($cd.Text -notmatch "Source record 'XTYPE' not found") 'CD did not fold the name'
    Row "leg 2b: CD compiled it ('Compiling xtype' in any case, no error)" `
        (($cd.Text -match '(?m)^Compiling xtype\s*$') -and ($cd.Text -notmatch 'is not defined|Compilation error')) 'no clean Compiling line naming xtype'
    $xRows = [regex]::Matches($cd.Text, '(?m)^(?i:xtype)\s{2,}I\s').Count
    Row "leg 2b: exactly one row for xtype, in either case - no twin, nothing lost" `
        (($xRows -eq 1) -and ($cd.Text -match '(?m)^4 record\(s\) listed')) "xtype rows: $xRows; LIST DICT should list @id, f1, f3 and xtype - 4 records"

    # --- leg 3: the compiled I-type evaluates ---------------------------------
    Write-Host ''
    Write-Host '--- leg 3: LIST xtype evaluates the compiled I-type --------------------'
    $ev = Invoke-SD @("LIST $File xtype")
    Show "LIST $File xtype" $ev
    Row 'leg 3: no compile error at query time' ($ev.Text -notmatch 'is not defined|Compilation error') 'the query recompiled and failed'
    Row "leg 3: r1's type evaluates to V (who is a verb)" ($ev.Text -match '(?m)^r1\s+V\s*$') 'no "r1  V" row'

    # --- leg 4: stage 2b - the shipped ids are stored lower case --------------
    # DICT VOC is SDSYS's voc.dic from any account.  A row is the id at the
    # start of a line, two or more spaces, then the type column; the heading
    # ("@ID.......") and the echoed command (":LIST ...") cannot match.
    Write-Host ''
    Write-Host '--- leg 4: LIST DICT VOC - the shipped ids as stored ----------------------'
    $dv = Invoke-SD @('LIST DICT VOC')
    Show 'LIST DICT VOC' $dv
    $dvCount = [regex]::Match($dv.Text, '(?m)^(\d+) record\(s\) listed')
    Write-Host ("  records listed: " + $(if ($dvCount.Success) { $dvCount.Groups[1].Value } else { '(no count line)' }))
    Row 'CONTROL leg 4: LIST DICT VOC listed its records' ($dvCount.Success -and ([int]$dvCount.Groups[1].Value -gt 0)) 'no "n record(s) listed" line - dict.dic''s own phrase or ids may not resolve'
    foreach ($pair in @(@('type', 'TYPE', 'I'), @('f1', 'F1', 'D'), @('@id', '@ID', 'D'), @('data.name', 'DATA.NAME', 'D'))) {
        $lo = [regex]::Escape($pair[0]); $up = [regex]::Escape($pair[1]); $t = $pair[2]
        Row ("leg 4: '" + $pair[0] + "' is stored, '" + $pair[1] + "' is not") `
            (($dv.Text -cmatch ('(?m)^' + $lo + '\s{2,}' + $t + '\s')) -and ($dv.Text -cnotmatch ('(?m)^' + $up + '\s{2,}' + $t + '\s'))) 'the stored id is not lower case, or both spellings are stored'
    }

    # --- leg 5: a query names the renamed field in either case ----------------
    Write-Host ''
    Write-Host '--- leg 5: LIST VOC WITH TYPE / type - regression control ----------------'
    $qv = Invoke-SD @('LIST VOC WITH TYPE = "V" AND @ID = "who"', 'LIST VOC WITH type = "V" AND @id = "who"')
    Show 'LIST VOC WITH TYPE, WITH type' $qv
    $one = [regex]::Matches($qv.Text, '(?m)^1 record\(s\) listed').Count
    Row 'leg 5: both queries found who (1 record listed, twice)' (($one -eq 2) -and ($qv.Text -notmatch 'not defined|Compilation error')) "1-record lines: $one of 2"
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
