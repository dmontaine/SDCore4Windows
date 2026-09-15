<#
.SYNOPSIS
    SET.FILE, .S and CNAME store a NEW VOC id in lower case, find an EXISTING
    one in any case, and never make a second copy in another case.
    ***AN ORDINARY UNELEVATED PROMPT.***

.DESCRIPTION
    RELEASE_1.1_FIXES.md 5, the remainder after phase (a), and 34.  Owner's
    rulings: "lower case all the IDs in SD system files like VOC" (13 Sep 2026),
    and an existing id in another case is "the same id" (14 Sep 2026).

    ***EVERY DEFECT A LEG GUARDS WAS MEASURED ON THE b153 INSTALL FIRST***
    (14 Sep 2026, scratch probe, own account):
      - SET.FILE DON bp ZzVidPtr   stored "ZzVidPtr", exactly as typed
      - .S ZZVIDSEN 1 after .S ZzVidSen 1   made a SECOND record, no prompt
      - CNAME ZZVIDF TO ...        "ZZVIDF is not defined in your VOC" for an
                                   existing zzvidf (no downcase tier)
      - CNAME zzvidf TO ZzVidG     stored "ZzVidG" and left the dictionary
                                   directory as zzvidf.DIC (the .DIC test
                                   upcased one side only)
    VOC is a DYNAMIC file, so two casings are two records - which is what
    "LIST VOC WITH @ID = ..." showed (the typed case listed, the lower missed).

    ***THE DECISIVE READ IS THE STORED ID, CASE-SENSITIVELY.***  Each leg lists
    its fixture's whole family (every casing) with LIST VOC and compares the ids
    printed with -ceq.  "The command worked" is not measured by any row: a
    fold resolves every casing, so success at the command line cannot tell a
    lower id from an upper one or one record from two.

    ***LEGS 5 AND 6 ARE RELEASE_1.1 34***: .S onto an existing sentence asks
    5045, Enter must now keep the old sentence, and the Y control must replace
    it.  The two sentences differ (WHO against DATE), so "kept" and "replaced"
    are told apart by the record's own line 2, not by the absence of an error.

    ***LEG 9 GUARDS A DATA LOSS THE FIX ITSELF COULD HAVE INTRODUCED.***
    "CNAME zzx TO ZZX" downcases the new name to the old one; without the guard
    the write lands on the old record and the delete after it removes it.

    ***AND IT IS BOUNDED***, the shape verify-promptenter uses: every session
    is a job, killed after -TimeoutSeconds, and any sd.exe it leaves is killed
    BY PID DIFF, never by name (the service runs sd.exe too).  The probe that
    preceded this hung once - an unanswered DELETE.FILE prompt ate the rest of
    its script - which is why every DELETE.FILE here runs in its own session
    with its answers supplied.

.PARAMETER Account
    The SD account to work in.  Defaults to the caller's own.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 the test could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-vocidcase.ps1
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
$Reg     = $Account.ToUpper()                       # the ACCOUNTS register id
$st      = (Get-Date -Format 'HHmmss')

# Fixture names.  Typed MIXED case where the leg is about the stored case.
$P = "zzvidp$st"; $F = "zzvidf$st"; $Q = "zzvidq$st"; $S = "zzvids$st"
$C = "zzvidc$st"; $N = "zzvidn$st"; $T = "zzvidt$st"; $U = "zzvidu$st"

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}
function Bail([int]$code, [string]$why) {
    Write-Host ''
    if ($code -eq 0) { Write-Host "verify-vocidcase: PASSED - $why" }
    elseif ($code -eq 1) { Write-Host "verify-vocidcase: FAILED - $why" }
    else { Write-Host "verify-vocidcase: COULD NOT RUN - $why" }
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

# Echo a session's transcript, minus the sign-on banner, so every row below can
# be checked against what SD actually said (instrument rule 1).
function Show([string]$label, $r) {
    Write-Host "  --- $label ---"
    foreach ($l in ($r.Text -split "`r?`n")) {
        if ($l -match '^\s*$|Ladybridge|free software|welcome to modify|conditions\.  For|^SD Core for') { continue }
        Write-Host ("    " + $l)
    }
    if ($r.Killed) { Write-Host "    *** KILLED after $TimeoutSeconds s" }
}

# THE STORED IDS OF ONE FAMILY, EXACTLY AS VOC HOLDS THEM.  LIST asks for the
# whole zzvid family in the three casings every fixture here is typed in
# (zzvid, ZZVID, ZzVid - LIKE may be case-sensitive), then the rows are
# filtered to $stem without case, so a twin in any of them is returned.
# Captured format (b153 install):
#   "ZzVidSen               S"   one row per record, id at column 1
#   "2 record(s) listed"         or "0 record(s) listed"
# Returns $null if LIST never reported a count, or its rows do not add up to
# it - a session that did not run must not read as "no records".
function Get-Family([string]$stem) {
    $r = Invoke-SD @('LIST VOC WITH @ID LIKE "zzvid..." OR @ID LIKE "ZZVID..." OR @ID LIKE "ZzVid..."')
    if ($r.Killed -or ($r.Text -notmatch '(?m)^(\d+) record\(s\) listed')) {
        Show "LIST for $stem (no count)" $r
        return $null
    }
    $count = [int]$Matches[1]
    $all = @([regex]::Matches($r.Text, '(?m)^((?i:zzvid)\S*)\s+\S+\s*$') | ForEach-Object { $_.Groups[1].Value })
    if ($all.Count -ne $count) {
        Show "LIST for $stem (rows $($all.Count) against count $count)" $r
        return $null
    }
    $ids = @($all | Where-Object { $_ -match ('^(?i)' + [regex]::Escape($stem)) })
    return ,$ids
}
function Fmt($ids) { if ($null -eq $ids) { '(LIST did not run)' } elseif ($ids.Count -eq 0) { '(none)' } else { ($ids -join ', ') } }
function Is-Exactly($ids, [string]$want) { return ($null -ne $ids) -and ($ids.Count -eq 1) -and ($ids[0] -ceq $want) }

# Remove every VOC id and directory of the zzvid family, any stamp.  F records
# go through DELETE.FILE, one session each with answers supplied; the rest
# through DELETE VOC.  Then anything left on disk.
function Clear-Family {
    $r = Invoke-SD @('LIST VOC WITH @ID LIKE "zzvid..." OR @ID LIKE "ZZVID..." OR @ID LIKE "ZzVid..."')
    foreach ($m in [regex]::Matches($r.Text, '(?m)^((?i:zzvid)\S*)\s+(\S+)\s*$')) {
        $id = $m.Groups[1].Value; $type = $m.Groups[2].Value
        if ($type -ceq 'F') { $null = Invoke-SD @("DELETE.FILE $id", 'Y', 'Y', 'Y') }
        else                { $null = Invoke-SD @("DELETE VOC $id") }
        Write-Host "    swept VOC $id ($type)"
    }
    foreach ($d in @(Get-ChildItem -LiteralPath $AcctDir -Directory -ErrorAction SilentlyContinue |
                     Where-Object { $_.Name -match '(?i)^zzvid' })) {
        Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host "    swept directory $($d.Name)"
    }
}
function Get-Dirs([string]$stem) {
    return @(Get-ChildItem -LiteralPath $AcctDir -Directory -ErrorAction SilentlyContinue |
             Where-Object { $_.Name -match ('(?i)^' + [regex]::Escape($stem)) } | ForEach-Object { $_.Name })
}

# --- refusals ---------------------------------------------------------------
if (-not (Test-Path -LiteralPath $sdExe)) { Bail 2 "no sd.exe at $sdExe" }
if (-not (Test-Path -LiteralPath (Join-Path $AcctDir 'bp'))) {
    Bail 2 "no bp directory in $AcctDir - pass -Account with an SD account name."
}

Write-Host "verify-vocidcase: account  $Account  (register id $Reg)"
Write-Host "verify-vocidcase: dir      $AcctDir"
Write-Host "verify-vocidcase: sd.exe   $sdExe"
Write-Host "verify-vocidcase: fixtures $P $F $Q $S $C $N $T $U"
Write-Host ''
Write-Host '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
Write-Host ''

Write-Host '--- sweep leftovers of earlier runs ---------------------------------'
Clear-Family

try {
    # --- leg 1: SET.FILE, a new pointer ------------------------------------
    Write-Host ''
    Write-Host '--- leg 1: SET.FILE writes a new pointer lower case ----------------'
    $typedP = 'ZzVidP' + $st
    $r = Invoke-SD @("SET.FILE $Reg bp $typedP")
    Show "SET.FILE $Reg bp $typedP" $r
    $fam = Get-Family 'zzvidp'
    Write-Host "  stored ids: $(Fmt $fam)"
    Row "leg 1: the pointer typed '$typedP' is stored as '$P', and only that" (Is-Exactly $fam $P) "got $(Fmt $fam)"

    # --- leg 2: SET.FILE, the same id typed in upper case -------------------
    # 6876 is the existing-record path; it then offers 2060 (y/<n>/q), answered
    # Q so nothing is overwritten and no second pointer prompt is reached.
    Write-Host ''
    Write-Host '--- leg 2: SET.FILE onto the same id in upper case finds it ---------'
    $r = Invoke-SD @("SET.FILE $Reg bp $($P.ToUpper())", 'Q')
    Show "SET.FILE $Reg bp $($P.ToUpper())" $r
    $fam = Get-Family 'zzvidp'
    Write-Host "  stored ids: $(Fmt $fam)"
    Row 'leg 2: SET.FILE reported 6876 (Pointer name is already in VOC)' `
        ($r.Text -match 'Pointer name is already in VOC') 'no 6876 - the upper-case name was not matched to the lower id'
    Row "leg 2: still exactly one pointer, '$P' - no upper-case twin" (Is-Exactly $fam $P) "got $(Fmt $fam)"

    # --- leg 3: SET.FILE finds a lower-case target file typed upper ---------
    Write-Host ''
    Write-Host '--- leg 3: SET.FILE finds a lower-case target file typed in upper ---'
    $mk = Invoke-SD @("CREATE.FILE $F")
    if ($mk.Text -notmatch "Created DATA part as $F") { Show 'CREATE.FILE' $mk; Bail 2 "could not create $F - setup, not measurement, failed." }
    # 14 Sep 26 - RELEASE_1.1 5 D2: VOC is case insensitive, so SET.FILE's read
    # of the typed name hits the file directly and field 3 keeps the spelling
    # typed ('3: ZZVIDF...' on b161).  That is cosmetic - the pointer resolves in
    # any case - so the row reads the name without its case, and COUNT through
    # the pointer is the proof that it resolves.
    $r = Invoke-SD @("SET.FILE $Reg $($F.ToUpper()) $Q", "CT VOC $Q", "COUNT $Q")
    Show "SET.FILE $Reg $($F.ToUpper()) $Q" $r
    Row 'leg 3: no 6872 (File name is not in target VOC)' ($r.Text -notmatch 'File name is not in target VOC') '6872 - the downcase tier did not find the file'
    Row "leg 3: the pointer '$Q' names the file ('3: $F', any case)" `
        (($r.Text -match "(?m)^VOC $Q\s*$") -and ($r.Text -match "(?m)^3: $F\s*$")) 'no Q-pointer naming the file'
    Row "leg 3: COUNT $Q resolves through the pointer (0 records counted)" `
        (($r.Text -match '(?m)^0 record\(s\) counted') -and ($r.Text -notmatch 'not found|Cannot open')) 'COUNT through the pointer did not answer'

    # --- leg 4: .S, a new sentence ------------------------------------------
    Write-Host ''
    Write-Host '--- leg 4: .S saves a new sentence lower case -----------------------'
    $typedS = 'ZzVidS' + $st
    $r = Invoke-SD @('WHO', ".S $typedS 1", ".L $S")
    Show ".S $typedS 1" $r
    $fam = Get-Family 'zzvids'
    Write-Host "  stored ids: $(Fmt $fam)"
    Row "leg 4: the sentence typed '$typedS' is stored as '$S', and only that" (Is-Exactly $fam $S) "got $(Fmt $fam)"
    Row 'leg 4: it holds WHO' ($r.Text -match '(?m)^002\s+WHO\s*$') 'no "002  WHO" in .L'

    # --- leg 5: .S onto it in upper case, ENTER at 5045 ---------------------
    Write-Host ''
    Write-Host '--- leg 5: .S onto the same id in upper case - ENTER at 5045 --------'
    $r = Invoke-SD @('DATE', ".S $($S.ToUpper()) 1", '', ".L $S")
    Show ".S $($S.ToUpper()) 1, then ENTER" $r
    $fam = Get-Family 'zzvids'
    Write-Host "  stored ids: $(Fmt $fam)"
    Row 'leg 5: the session terminated (no runaway loop)' (-not $r.Killed) "killed after $TimeoutSeconds s"
    # 14 Sep 26 - D2: 5045 echoes the id as typed (b161); the one-record row
    # below is what proves it is the lower id, so this one is case-blind.
    Row "leg 5: 5045 was reached for the lower id, showing (y/<n>)" `
        ($r.Text -match "Overwrite VOC record '$S' \(y/<n>\)\?") "no 5045 naming '$S' with its default marker"
    Row 'leg 5: ENTER kept the old sentence (002 is still WHO)' `
        (($r.Text -match '(?m)^002\s+WHO\s*$') -and ($r.Text -notmatch '(?m)^002\s+DATE\s*$')) 'line 2 is not WHO'
    Row "leg 5: still exactly one sentence, '$S' - no upper-case twin" (Is-Exactly $fam $S) "got $(Fmt $fam)"

    # --- leg 6: CONTROL, Y at 5045 ------------------------------------------
    Write-Host ''
    Write-Host '--- leg 6: CONTROL - Y at 5045 replaces it ---------------------------'
    $r = Invoke-SD @('DATE', ".S $($S.ToUpper()) 1", 'Y', ".L $S")
    Show ".S $($S.ToUpper()) 1, then Y" $r
    $fam = Get-Family 'zzvids'
    Row 'CONTROL leg 6: 5045 was reached again' ($r.Text -match "Overwrite VOC record '$S'") 'no 5045'
    Row 'CONTROL leg 6: Y replaced the sentence (002 is now DATE)' ($r.Text -match '(?m)^002\s+DATE\s*$') 'line 2 is not DATE'
    Row "CONTROL leg 6: and it is still the one record '$S'" (Is-Exactly $fam $S) "got $(Fmt $fam)"

    # --- leg 7: CNAME, old name folds, new name lower, OS files follow ------
    Write-Host ''
    Write-Host '--- leg 7: CNAME - old name typed upper, new name stored lower -------'
    $mk = Invoke-SD @("CREATE.FILE $C")
    if ($mk.Text -notmatch "Created DATA part as $C") { Show 'CREATE.FILE' $mk; Bail 2 "could not create $C - setup, not measurement, failed." }
    $typedN = 'ZzVidN' + $st
    $r = Invoke-SD @("CNAME $($C.ToUpper()) TO $typedN")
    Show "CNAME $($C.ToUpper()) TO $typedN" $r
    $famN = Get-Family 'zzvidn'; $famC = Get-Family 'zzvidc'
    $dirsN = Get-Dirs 'zzvidn'; $dirsC = Get-Dirs 'zzvidc'
    Write-Host "  stored ids: new $(Fmt $famN); old $(Fmt $famC)"
    Write-Host "  on disk   : new $($dirsN -join ', '); old $($dirsC -join ', ')"
    # 14 Sep 26 - D2: 6158 names the OLD id as typed (b161: 'ZZVIDC...'); the
    # NEW id is still the stored lower one, and that half keeps its case.
    Row "leg 7: CNAME reported '$C' renamed to '$N'" ($r.Text -cmatch "'(?i:$C)' renamed to '$N'") 'no 6158 naming the new id lower'
    Row 'leg 7: the data directory was renamed (6153)' ($r.Text -match 'Renamed data file at operating system level') 'no 6153'
    Row 'leg 7: the dictionary directory was renamed (6155)' ($r.Text -match 'Renamed dictionary at operating system level') 'no 6155'
    Row "leg 7: VOC holds '$N' and only that" (Is-Exactly $famN $N) "got $(Fmt $famN)"
    Row 'leg 7: VOC holds nothing of the old name' (($null -ne $famC) -and ($famC.Count -eq 0)) "got $(Fmt $famC)"
    Row "leg 7: on disk exactly '$N' and '$N.DIC'" `
        ((@($dirsN | Where-Object { $_ -ceq $N }).Count -eq 1) -and (@($dirsN | Where-Object { $_ -ceq "$N.DIC" }).Count -eq 1) -and ($dirsC.Count -eq 0)) `
        "new: $($dirsN -join ', '); old: $($dirsC -join ', ')"

    # --- leg 8: CNAME onto an existing id in another case is refused --------
    Write-Host ''
    Write-Host '--- leg 8: CNAME onto the same id in upper case is refused ----------'
    $mk = Invoke-SD @("CREATE.FILE $T")
    if ($mk.Text -notmatch "Created DATA part as $T") { Show 'CREATE.FILE' $mk; Bail 2 "could not create $T - setup, not measurement, failed." }
    $r = Invoke-SD @("CNAME $T TO $($N.ToUpper())")
    Show "CNAME $T TO $($N.ToUpper())" $r
    $famN = Get-Family 'zzvidn'; $famT = Get-Family 'zzvidt'
    # 14 Sep 26 - D2: 6151 names the id as typed (b161); case-blind.
    Row 'leg 8: refused with 6151 naming the existing id' ($r.Text -match "(?m)^$N is already defined in your VOC") 'no 6151 naming the id'
    Row "leg 8: '$T' is untouched" (Is-Exactly $famT $T) "got $(Fmt $famT)"
    Row "leg 8: '$N' is still the only one of its name" (Is-Exactly $famN $N) "got $(Fmt $famN)"

    # --- leg 9: CNAME to its own name in another case must not lose it ------
    Write-Host ''
    Write-Host '--- leg 9: CNAME to its own name in upper case keeps the record -----'
    $r = Invoke-SD @("CNAME $N TO $($N.ToUpper())")
    Show "CNAME $N TO $($N.ToUpper())" $r
    $famN = Get-Family 'zzvidn'
    Row 'leg 9: refused with 6151' ($r.Text -cmatch "(?m)^$N is already defined in your VOC") 'no 6151'
    Row "leg 9: the record '$N' survives, and only it" (Is-Exactly $famN $N) "got $(Fmt $famN)"

    # --- leg 10: CNAME of an upper-case id to its own lower spelling ---------
    # OPTION CREATE.FILE.UPCASE keeps the case typed (verify-promptenter's
    # fixture route), so this is an old-style upper id with upper directories.
    # 14 Sep 26 - RETIRED AS A RENAME, OWNER'S RULING (retire and replace).  It
    # asserted the recase; on b161 CNAME refused it with 6151, because under D2
    # the new name's NOCASE read finds the old record itself - the leg 9 guard.
    # A recase could not be done by write-then-delete on a NOCASE VOC anyway:
    # measured 14 Sep, writing 'type' then deleting 'TYPE' deletes the one
    # record.  So the leg now asserts the refusal is SAFE - nothing is lost.
    Write-Host ''
    Write-Host '--- leg 10: CNAME an upper-case id to its own lower spelling is refused, nothing lost ---'
    $UU = $U.ToUpper()
    $mk = Invoke-SD @('OPTION CREATE.FILE.UPCASE', "CREATE.FILE $UU")
    $famU = Get-Family 'zzvidu'
    if (-not (Is-Exactly $famU $UU)) { Show 'CREATE.FILE (upper)' $mk; Bail 2 "could not make an upper-case id $UU (got $(Fmt $famU)) - setup failed." }
    Row "leg 10 precondition: '$UU' is stored upper case" $true ''
    $r = Invoke-SD @("CNAME $UU TO $U")
    Show "CNAME $UU TO $U" $r
    $famU = Get-Family 'zzvidu'; $dirsU = Get-Dirs 'zzvidu'
    Write-Host "  stored ids: $(Fmt $famU);  on disk: $($dirsU -join ', ')"
    Row 'leg 10: refused with 6151 (its own name in another case)' ($r.Text -match "(?m)^$U is already defined in your VOC") 'no 6151'
    Row "leg 10: the record survives, still exactly '$UU'" (Is-Exactly $famU $UU) "got $(Fmt $famU)"
    Row "leg 10: on disk still exactly '$UU' and '$UU.DIC'" `
        ((@($dirsU | Where-Object { $_ -ceq $UU }).Count -eq 1) -and (@($dirsU | Where-Object { $_ -ceq "$UU.DIC" }).Count -eq 1) -and ($dirsU.Count -eq 2)) `
        "on disk: $($dirsU -join ', ')"
}
finally {
    Write-Host ''
    Write-Host '--- cleanup ----------------------------------------------------------'
    Clear-Family
    $left = Invoke-SD @('LIST VOC WITH @ID LIKE "zzvid..." OR @ID LIKE "ZZVID..." OR @ID LIKE "ZzVid..."')
    $dirsLeft = Get-Dirs 'zzvid'
    Row 'cleanup: VOC holds no zzvid id in any case' ($left.Text -match '(?m)^0 record\(s\) listed') "LIST did not report 0: $($left.Text)"
    Row 'cleanup: no zzvid directory is left' ($dirsLeft.Count -eq 0) ($dirsLeft -join ', ')
}

Write-Host ''
Write-Host "verify-vocidcase: $pass passed, $fail failed"
if (($pass + $fail) -eq 0) { Bail 2 'no check ran - a broken test, not a pass.' }
if ($fail -gt 0) { Bail 1 "$fail check(s) failed." }
Bail 0 'SET.FILE, .S and CNAME store new VOC ids lower case, find existing ones in any case, and made no twin; Enter at 5045 kept the sentence; a refused recase lost nothing.'
