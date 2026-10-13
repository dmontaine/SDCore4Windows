<#
.SYNOPSIS
    SET.TRIGGER takes a lower-case trigger name (RELEASE_1.1 137), and an index
    holds the record ids AS THE FILE STORES THEM (RELEASE_1.1 138).
    ***AN ORDINARY UNELEVATED PROMPT.***

.DESCRIPTION
    TWO FAULTS, ONE STEP, BECAUSE BOTH WERE FOUND BY THE LINUX AGENT AND BOTH ARE
    A LOWER-CASE NAME MEETING CODE THAT STILL ASSUMED UPPER CASE.

    A. RELEASE_1.1 137 (Linux mail T0110).  Stage 3a lower-cased the trigger name
       in gpl.bp/settrig but left the character sets it is checked against in
       upper case, so SET.TRIGGER refused every name that starts with a letter
       with message 3002.  The BASIC SET.TRIGGER statement and triggers already
       stored were never affected, only the command.  The decisive rows:
         A1  SET.TRIGGER file zztrg137 PRE.WRITE prints 3005 and 3006, and not 3002
         A2  a SEPARATE session reads the trigger back from the file header
         A3  the same name typed in UPPER case is accepted, and is STORED lower
         A4  a name with an illegal character is still refused (3002)
         A5  a legal name nobody catalogued reaches the catalogue test (3003)

    B. RELEASE_1.1 138 (Linux mail T2330).  dh_write.c and dh_del.c gave the index
       routine the record id UPPER-cased on a NOCASE file, which is every hashed
       file since D2, while BUILD.INDEX stores the id as the file holds it.  After
       an index was built a new r4 was indexed as R4, a delete of r3 left r3, and
       a change of r1 left r1 and added R1.  This is the recipe of Linux's
       gplbld/sandbox-akcase.py (prog_steps()), run through SD's own BASIC: a file
       with a D-type item on field 1, three lower-case ids, CREATE.INDEX and
       BUILD.INDEX, then S1 a new record, S2 a delete, S3 a change, S4 a change
       under another spelling of the id in place, S5 the same after a size
       change, and the lists SELECTINDEX gives are printed after every step.
       Lists are compared as sorted sets and CASE SENSITIVELY.  Also read: the
       ids the file holds (the FIRST spelling stays), and the index after a
       BUILD.INDEX, which must equal the index the writes kept.

    ***THE INSTRUMENT IS WHAT THE PROGRAMS AND THE VERBS PRINTED.***  Every
    session's text is shown.  The control rows come first and a failing control
    ends the run with exit 2 and no verdict: S0 (an index BUILT from three
    lower-case ids must give exactly those), the fixture compiles, the trigger
    subroutine is catalogued, the file exists.

    NOT COVERED: a trigger actually FIRING on a write (this step only sets and
    reads the name), and a transaction commit through a real program (txn.c
    calls dh_write and dh_delete with the cached id; read, not run).

    BOUNDED: every session is a job, killed after -TimeoutSeconds, any sd.exe
    left killed BY PID DIFF, never by name.  Own account, no token, nothing
    outside it is touched, every fixture is swept first and removed again.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 the test could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\verify-trigak.ps1
#>

[CmdletBinding()]
param(
    [string]$Account = $env:USERNAME,
    [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$AcctDir = Join-Path (Join-Path $env:ProgramData 'SD\user_accounts') $Account
$BpDir   = Join-Path $AcctDir 'bp'
$CatDir  = Join-Path $AcctDir 'cat'

# Fixture names, all lower case, all swept before and after.
$TrgFile = 'zztf137'      # the file the trigger is set on
$TrgSub  = 'zztrg137'     # the catalogued subroutine named as its trigger
$AkFile  = 'zzak138'      # the file with the index
$PgmW    = 'zzak138w'     # writes the dictionary item and three records
$PgmS    = 'zzak138s'     # the steps S0..S5
$PgmR    = 'zzak138r'     # reads the index back after BUILD.INDEX
$Progs   = @($TrgSub, $PgmW, $PgmS, $PgmR)
$Cities  = @('Paris', 'Rome', 'Oslo', 'Copenhagen')

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}
function Bail([int]$code, [string]$why) {
    Write-Host ''
    if ($code -eq 0) { Write-Host "verify-trigak: PASSED - $why" }
    elseif ($code -eq 1) { Write-Host "verify-trigak: FAILED - $why" }
    else { Write-Host "verify-trigak: COULD NOT RUN - $why" }
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
# A BASIC source or any directory-file record, LF line ends and no BOM.
function Write-Source([string]$path, [string]$text) {
    $lines = @($text -split "`r?`n" | Where-Object { $_ -ne '' })
    [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), (New-Object System.Text.ASCIIEncoding))
    Write-Host "  wrote $path ($($lines.Count) lines)"
}

# The lists a steps program printed on one tagged line, as ONE canonical string:
#   Paris=r1,r3;Rome=r2;Oslo=;Copenhagen=
# ids sorted ordinally (the order inside an index entry is not the point),
# cities in the fixed order, CASE KEPT.  $null when the tagged line is not there.
function Get-Lists([string]$text, [string]$tag) {
    $m = [regex]::Match($text, '(?m)^' + [regex]::Escape($tag) + '\[(.*)\]\s*$')
    if (-not $m.Success) { return $null }
    $per = @{}
    foreach ($part in ($m.Groups[1].Value -split ';')) {
        $eq = $part.IndexOf('=')
        if ($eq -lt 1) { continue }
        $ids = @($part.Substring($eq + 1) -split ',' | Where-Object { $_ -ne '' })
        [Array]::Sort($ids, [StringComparer]::Ordinal)
        $per[$part.Substring(0, $eq)] = ($ids -join ',')
    }
    return (($Cities | ForEach-Object { $_ + '=' + $per[$_] }) -join ';')
}
function Want([string]$paris, [string]$rome, [string]$oslo, [string]$cph) {
    return "Paris=$paris;Rome=$rome;Oslo=$oslo;Copenhagen=$cph"
}
function Get-Ids([string]$text) {
    $m = [regex]::Match($text, '(?m)^IDS\[(.*)\]\s*$')
    if (-not $m.Success) { return $null }
    $ids = @($m.Groups[1].Value -split ',' | Where-Object { $_ -ne '' })
    [Array]::Sort($ids, [StringComparer]::Ordinal)
    return ($ids -join ',')
}

function Remove-Fixtures {
    $null = Invoke-SD @("SET.TRIGGER $TrgFile `"`"",
                       "DELETE.CATALOG $TrgSub",
                       "DELETE.FILE $TrgFile NO.QUERY", "DELETE.FILE $AkFile NO.QUERY",
                       ('DELETE bp ' + ($Progs -join ' ')), ('DELETE bp.out ' + ($Progs -join ' ')))
    foreach ($d in @($BpDir, (Join-Path $AcctDir 'bp.out'), $CatDir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue |
                         Where-Object { $Progs -contains $_.Name.ToLower() })) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "    swept $($f.FullName)"
        }
    }
}
function Get-Leftovers {
    $left = @()
    foreach ($d in @($BpDir, (Join-Path $AcctDir 'bp.out'), $CatDir)) {
        $left += @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue |
                   Where-Object { $Progs -contains $_.Name.ToLower() } | ForEach-Object { $_.FullName })
    }
    $left += @(Get-ChildItem -LiteralPath $AcctDir -Force -ErrorAction SilentlyContinue |
               Where-Object { $_.Name -match ('(?i)^(' + $TrgFile + '|' + $AkFile + ')(\.(dic|out))?$') } |
               ForEach-Object { $_.FullName })
    return $left
}

# --- refusals and inputs -----------------------------------------------------
foreach ($p in @($sdExe, $BpDir)) {
    if (-not (Test-Path -LiteralPath $p)) { Bail 2 "missing: $p" }
}
Write-Host "verify-trigak: account $Account"
Write-Host "verify-trigak: dir     $AcctDir"
Write-Host "verify-trigak: sd.exe  $sdExe"
Write-Host "verify-trigak: files   $TrgFile (trigger) and $AkFile (index); programs $($Progs -join ' ')"
Write-Host ''
Write-Host '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
Write-Host ''
Write-Host '--- sweep leftovers ---------------------------------------------------'
Remove-Fixtures

try {
    # =========================================================================
    # A. RELEASE_1.1 137 - SET.TRIGGER with a lower-case name
    # =========================================================================
    Write-Host ''
    Write-Host '--- A. fixture: a dynamic file and a catalogued subroutine -----------------'
    Write-Source (Join-Path $BpDir $TrgSub) @"
subroutine $TrgSub
   return
end
"@
    $mk = Invoke-SD @("CREATE.FILE $TrgFile", "BASIC bp $TrgSub", "CATALOG bp $TrgSub")
    Show "CREATE.FILE / BASIC / CATALOG" $mk
    $failBefore = $fail     # a setup is judged on ITS rows, not on earlier verdict rows
    Row "setup: the trigger subroutine compiled with no errors" ($mk.Text -cmatch '(?m)^Compiled 1 program\(s\) with no errors') 'no clean-compile line'
    Row "setup: CATALOG said '$TrgSub added to private catalogue' (3031)" ($mk.Text -cmatch ('(?m)^' + $TrgSub + ' added to private catalogue')) 'no 3031 line naming the subroutine'
    Row "setup: the file $TrgFile exists on disk" (Test-Path -LiteralPath (Join-Path $AcctDir $TrgFile)) 'no directory for the file'
    if ($fail -gt $failBefore) { Bail 2 'the A fixture did not build - nothing below would measure SET.TRIGGER.' }

    Write-Host ''
    Write-Host '--- A1, A2. lower case in, then read back from the file header -------------'
    $s1 = Invoke-SD @("SET.TRIGGER $TrgFile $TrgSub PRE.WRITE")
    Show "SET.TRIGGER $TrgFile $TrgSub PRE.WRITE" $s1
    $s2 = Invoke-SD @("SET.TRIGGER $TrgFile")
    Show "SET.TRIGGER $TrgFile  (read back, a new session)" $s2
    if ($s1.Text -match 'is not catalogued') { Bail 2 "SET.TRIGGER reached the catalogue test and did not find $TrgSub - the fixture, not the fix." }
    Row 'A1: 3002 "Illegal trigger function name" is NOT printed for a lower-case name' ($s1.Text -notmatch 'Illegal trigger function name') '3002 printed: SET.TRIGGER refuses a name that starts with a letter (RELEASE_1.1 137)'
    Row "A1: 3005 names the trigger '$TrgSub'" ($s1.Text -cmatch ('(?m)^Trigger function: ' + $TrgSub + '\s*$')) 'no 3005 line naming the trigger'
    Row 'A1: 3006 lists the mode PRE.WRITE' ($s1.Text -cmatch '(?m)^Modes: PRE\.WRITE\s*$') 'no 3006 line with PRE.WRITE'
    $m2 = [regex]::Match($s2.Text, '(?m)^Trigger function: (\S+)')
    Row "A2: a new session reads the trigger back from the file, stored as '$TrgSub'" ($m2.Success -and ($m2.Groups[1].Value -ceq $TrgSub)) ('read back: ' + $(if ($m2.Success) { $m2.Groups[1].Value } else { '(no 3005 line)' }))
    Row 'A2: it reads back the mode PRE.WRITE' ($s2.Text -cmatch '(?m)^Modes: PRE\.WRITE\s*$') 'no 3006 line with PRE.WRITE'
    Row 'A2: it does not say 3001 "File has no trigger function"' ($s2.Text -notmatch 'File has no trigger function') 'the file header holds no trigger'

    Write-Host ''
    Write-Host '--- A3. the same name typed in UPPER case --------------------------------'
    $up = $TrgSub.ToUpper()
    $s3 = Invoke-SD @("SET.TRIGGER $TrgFile $up POST.WRITE")
    Show "SET.TRIGGER $TrgFile $up POST.WRITE" $s3
    $s4 = Invoke-SD @("SET.TRIGGER $TrgFile")
    Show "SET.TRIGGER $TrgFile  (read back, a new session)" $s4
    $m3 = [regex]::Match($s3.Text, '(?m)^Trigger function: (\S+)')
    $m4 = [regex]::Match($s4.Text, '(?m)^Trigger function: (\S+)')
    Row "A3: $up is accepted and reported lower case" ($m3.Success -and ($m3.Groups[1].Value -ceq $TrgSub) -and ($s3.Text -notmatch 'Illegal trigger function name')) ('reported: ' + $(if ($m3.Success) { $m3.Groups[1].Value } else { '(no 3005 line)' }))
    Row 'A3: the mode changed to POST.WRITE' ($s3.Text -cmatch '(?m)^Modes: POST\.WRITE\s*$') 'no 3006 line with POST.WRITE'
    Row "A3: the file stores the lower-case name '$TrgSub', not the typed '$up'" ($m4.Success -and ($m4.Groups[1].Value -ceq $TrgSub)) ('stored: ' + $(if ($m4.Success) { $m4.Groups[1].Value } else { '(no 3005 line)' }))

    Write-Host ''
    Write-Host '--- A4, A5. the name checks are still there ------------------------------'
    $bad = 'zz^bad137'
    $nosuch = 'zznosuch137'
    $s5 = Invoke-SD @("SET.TRIGGER $TrgFile $bad PRE.WRITE")
    Show "SET.TRIGGER $TrgFile $bad PRE.WRITE" $s5
    $s6 = Invoke-SD @("SET.TRIGGER $TrgFile $nosuch PRE.WRITE")
    Show "SET.TRIGGER $TrgFile $nosuch PRE.WRITE" $s6
    Row 'A4 (control): a name with an illegal character is refused with 3002' ($s5.Text -cmatch 'Illegal trigger function name') 'no 3002 - the name check is gone, or the parser changed the token'
    Row 'A5: a legal name nobody catalogued is refused with 3003, past the name check' (($s6.Text -cmatch 'Trigger function is not catalogued') -and ($s6.Text -notmatch 'Illegal trigger function name')) 'no 3003, or 3002 printed first'

    # =========================================================================
    # B. RELEASE_1.1 138 - the index holds the ids as the file stores them
    # =========================================================================
    Write-Host ''
    Write-Host '--- B. fixture: a file, a D-type item on field 1, three records, an index ---'
    Write-Source (Join-Path $BpDir $PgmW) @"
   open '$AkFile' to f else stop 'no file'
   open 'DICT $AkFile' to d else stop 'no dict'
   write 'D':@fm:'1':@fm:'':@fm:'City':@fm:'12L':@fm:'S' on d, 'CITY'
   write 'Paris' on f, 'r1'
   write 'Rome' on f, 'r2'
   write 'Paris' on f, 'r3'
end
"@
    $showSub = @"
show:
   x = ''
   for i = 1 to 4
      v = vals<i>
      selectindex 'CITY', v from f to 5
      readlist l from 5 else l = ''
      x := v:'=':change(l, @fm, ','):';'
   next i
   return
"@
    $valsLine = "   vals = 'Paris':@fm:'Rome':@fm:'Oslo':@fm:'Copenhagen'"
    Write-Source (Join-Path $BpDir $PgmS) @"
   open '$AkFile' to f else stop 'no file'
$valsLine
   gosub show ; crt 'S0[':x:']'
   write 'Paris' on f, 'r4'
   gosub show ; crt 'S1[':x:']'
   delete f, 'r3'
   gosub show ; crt 'S2[':x:']'
   write 'Rome' on f, 'r1'
   gosub show ; crt 'S3[':x:']'
   write 'Oslo' on f, 'R2'
   gosub show ; crt 'S4[':x:']'
   write 'Copenhagen' on f, 'R2'
   gosub show ; crt 'S5[':x:']'
   select f to 6
   readlist ids from 6 else ids = ''
   crt 'IDS[':change(ids, @fm, ','):']'
   stop
$showSub
end
"@
    Write-Source (Join-Path $BpDir $PgmR) @"
   open '$AkFile' to f else stop 'no file'
$valsLine
   gosub show ; crt 'RB[':x:']'
   stop
$showSub
end
"@
    $mk = Invoke-SD @("CREATE.FILE $AkFile", "BASIC bp $PgmW", "BASIC bp $PgmS", "BASIC bp $PgmR")
    Show 'CREATE.FILE / BASIC x3' $mk
    $failBefore = $fail
    $clean = [regex]::Matches($mk.Text, '(?m)^Compiled 1 program\(s\) with no errors').Count
    Row 'setup: the three programs compiled with no errors' ($clean -eq 3) "clean compiles: $clean of 3"
    Row "setup: the file $AkFile exists on disk" (Test-Path -LiteralPath (Join-Path $AcctDir $AkFile)) 'no directory for the file'
    if ($fail -gt $failBefore) { Bail 2 'the B fixture did not build - nothing below would read an index.' }

    $fx = Invoke-SD @("RUN bp $PgmW", "CREATE.INDEX $AkFile CITY", "BUILD.INDEX $AkFile CITY", "LIST.INDEX $AkFile ALL")
    Show 'RUN setup / CREATE.INDEX / BUILD.INDEX / LIST.INDEX' $fx
    $failBefore = $fail
    Row 'setup: CREATE.INDEX said it added the index (2617)' ($fx.Text -cmatch 'Added index for CITY') 'no 2617 line for CITY'
    Row 'setup: the file reads back with exactly one index (2620)' ($fx.Text -cmatch 'Number of indices = 1') 'no "Number of indices = 1"'
    if ($fail -gt $failBefore) { Bail 2 'the index was not created - nothing below would read one.' }

    Write-Host ''
    Write-Host '--- B. the steps, each followed by what the index says -------------------'
    $st = Invoke-SD @("RUN bp $PgmS")
    Show "RUN bp $PgmS" $st
    $S = @{}
    foreach ($t in @('S0', 'S1', 'S2', 'S3', 'S4', 'S5')) { $S[$t] = Get-Lists $st.Text $t }
    $ids = Get-Ids $st.Text
    foreach ($t in @('S0', 'S1', 'S2', 'S3', 'S4', 'S5')) { Write-Host ("    {0}  {1}" -f $t, $(if ($null -eq $S[$t]) { '(not printed)' } else { $S[$t] })) }
    Write-Host ("    IDS  {0}" -f $(if ($null -eq $ids) { '(not printed)' } else { $ids }))
    $s0want = Want 'r1,r3' 'r2' '' ''
    if ($S['S0'] -cne $s0want) {
        Bail 2 ("the control step S0 is not what BUILD.INDEX of three lower-case ids must give - the fixture or the printing is wrong, so no verdict would mean anything. wanted [$s0want] got [" + $S['S0'] + ']')
    }
    Row 'S0 (control): an index BUILT from the file holds the ids as stored, lower case' $true ''

    Row 'S1: a new record r4 is indexed under r4 (not R4)'                                   ($S['S1'] -ceq (Want 'r1,r3,r4' 'r2' '' ''))   ("got [" + $S['S1'] + ']')
    Row 'S2: deleting r3 takes r3 out of the index'                                          ($S['S2'] -ceq (Want 'r1,r4' 'r2' '' ''))      ("got [" + $S['S2'] + ']')
    Row 'S3: changing r1 from Paris to Rome moves r1 (out of Paris, into Rome)'              ($S['S3'] -ceq (Want 'r4' 'r1,r2' '' ''))      ("got [" + $S['S3'] + ']')
    Row 'S4: writing r2 under the spelling R2, same size (in place), moves the stored r2'    ($S['S4'] -ceq (Want 'r4' 'r1' 'r2' ''))       ("got [" + $S['S4'] + ']')
    Row 'S5: writing it under R2 again, larger (deleted and added again), moves the stored r2' ($S['S5'] -ceq (Want 'r4' 'r1' '' 'r2'))    ("got [" + $S['S5'] + ']')
    Row 'the file holds r1, r2, r4: the FIRST spelling of an id stays through a rewrite under another' ($ids -ceq 'r1,r2,r4') ("got [$ids]")

    Write-Host ''
    Write-Host '--- B. the index after BUILD.INDEX must equal the index the writes kept --'
    $rb = Invoke-SD @("BUILD.INDEX $AkFile CITY", "RUN bp $PgmR")
    Show "BUILD.INDEX / RUN bp $PgmR" $rb
    $rebuilt = Get-Lists $rb.Text 'RB'
    Write-Host ("    RB   {0}" -f $(if ($null -eq $rebuilt) { '(not printed)' } else { $rebuilt }))
    Row 'an index kept up to date by the writes says what an index built from the file says' (($null -ne $rebuilt) -and ($rebuilt -ceq $S['S5'])) ("maintained [" + $S['S5'] + "], rebuilt [$rebuilt]")
}
finally {
    Write-Host ''
    Write-Host '--- cleanup ----------------------------------------------------------'
    Remove-Fixtures
    $left = @(Get-Leftovers)
    Row 'cleanup: no fixture file, directory or program is left in the account' ($left.Count -eq 0) ($left -join ' ')
}

Write-Host ''
Write-Host "verify-trigak: $pass passed, $fail failed"
if (($pass + $fail) -eq 0) { Bail 2 'no check ran - a broken test, not a pass.' }
if ($fail -gt 0) { Bail 1 "$fail check(s) failed." }
Bail 0 'SET.TRIGGER takes a lower-case name, and the index holds the ids as the file stores them.'
