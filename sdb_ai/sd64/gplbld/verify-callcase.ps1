<#
.SYNOPSIS
    Program and catalogue names are LOWER case - what SD produces, read back
    case-sensitively.  ***AN ORDINARY UNELEVATED PROMPT.***

.DESCRIPTION
    RELEASE_1.1_FIXES.md 5, stage 3a (owner, 14 Sep 2026: the full conversion,
    lower case everywhere; CATALOG stores lower).  The runtime's canonical case
    for program names flipped from upper to lower: the C call sites, the
    compilers (BCOMP and bbcmp.py), CATALOG, DELETE.CATALOG, the kernel's own
    names and the pcode library.

    ***WHY THIS READS NAMES INSTEAD OF CHECKING THAT THINGS RUN.***  On NTFS a
    gcat file opens under any case (measured 14 Sep: openseq on
    gcat/!username found !USERNAME).  So a site that missed the flip still runs,
    and a suite that only checks behaviour stays green over it.  Every decisive
    row here reads a stored or printed NAME with -cmatch / -ceq:
      A. the gcat directory listing           - no entry with an upper-case letter
      B. the bin\pcode library's header names - every item lower
      C. the runtime's own error text         - "Unable to load '!zznosuchsub3a'"
      D. CATALOG into the private catalogue   - 3031 names zzcc3ap; cat\ holds it
      E. CATALOG LOCAL                        - 3029 names zzcl3a; VOC id lower
      F. the local entry, called and re-      - a call typed ZZCL3A finds it; a
         catalogued                              second CATALOG LOCAL leaves ONE
                                                 entry, stored zzcl3a
      G. DELETE.CATALOG                       - 3042 / 3040 name the lower id

    ***14 Sep 2026 - F's PLANT IS RETIRED*** (owner: "retire and replace").
    It planted an old-style ZZCL3A by writing that id and deleting zzcl3a.
    RELEASE_1.1 5 D2 made VOC case insensitive, so the delete removed the one
    record (b161).  Stored ids are read with "LIST VOC WITH @ID LIKE", which
    prints the id as STORED; "@ID =" is a keyed read and prints the spelling
    asked for (both measured 14 Sep 2026).

    ***RED ON THE b158 INSTALL, MEASURED BEFORE THE CYCLE*** by a scratch copy
    without the assert gate - see RELEASE_1.1 5 for the rows it failed.

    NOT COVERED: SET.TRIGGER's stored name (it needs a dynamic file and a
    catalogued trigger), and the kernel literals $debug/$pdbg and $proc, which
    only a debugger session or a PROC reaches.

    BOUNDED: every session is a job, killed after -TimeoutSeconds, any sd.exe
    left killed BY PID DIFF, never by name.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 the test could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\verify-callcase.ps1
#>

[CmdletBinding()]
param(
    [string]$Account = $env:USERNAME,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdsys   = Join-Path $env:ProgramData 'SD\sdsys'
$gcat    = Join-Path $sdsys 'gcat'
$pcodeF  = Join-Path $sdsys 'bin\pcode'
$AcctDir = Join-Path (Join-Path $env:ProgramData 'SD\user_accounts') $Account
$BpDir   = Join-Path $AcctDir 'bp'
$CatDir  = Join-Path $AcctDir 'cat'
$Progs   = @('zzcc3ap', 'zzrn3a', 'zzlc3a')   # zzmv3a retired 14 Sep 26; still swept below

$pass = 0
$fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $name" }
    else     { $script:fail++; Write-Host "  [FAIL] $name"; Write-Host "         $detail" }
}
function Bail([int]$code, [string]$why) {
    Write-Host ''
    if ($code -eq 0) { Write-Host "verify-callcase: PASSED - $why" }
    elseif ($code -eq 1) { Write-Host "verify-callcase: FAILED - $why" }
    else { Write-Host "verify-callcase: COULD NOT RUN - $why" }
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
# A directory-file record written with LF field marks and no BOM.
function Write-Record([string]$path, [string[]]$lines) {
    [System.IO.File]::WriteAllText($path, (($lines -join "`n") + "`n"), (New-Object System.Text.ASCIIEncoding))
    Write-Host "  wrote $path"
}
# Stored VOC ids for one name, read from LIST VOC's rows case-sensitively.  The
# selection folds upper and lower (PROJECT_STATUS.md trap), so the ROW is read.
# ***A ROW, NOT ANY LINE THAT STARTS WITH THE ID***: CATALOG's 3029 and
# DELETE.CATALOG's 3040 also begin "<id> added ..." / "<id> deleted ...", and the
# first draft counted them - the b158 red run reported "stored: ZZCL3A ZZCL3A".
# A LIST row pads the 20-wide id column, so the id is followed by two or more
# spaces or by the end of the line; a message has one space.  The control row
# in the fixtures section drives this on the message wording.
function Get-StoredVocIds([string]$text, [string]$name) {
    $ids = @()
    foreach ($m in [regex]::Matches($text, '(?im)^(' + [regex]::Escape($name) + ')(?:[ \t]{2,}|[ \t]*$)')) { $ids += $m.Groups[1].Value }
    return $ids
}
function Remove-Fixtures {
    $null = Invoke-SD @('DELETE.CATALOG zzcc3ap', 'DELETE.CATALOG zzcl3a LOCAL',
                       'DELETE VOC ZZCL3A', 'DELETE VOC zzcl3a',
                       ('DELETE bp ' + ($Progs -join ' ')), ('DELETE bp.out ' + ($Progs -join ' ')))
    foreach ($d in @($BpDir, (Join-Path $AcctDir 'bp.out'), $CatDir)) {
        foreach ($f in @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue |
                         Where-Object { $_.Name -match '(?i)^(zzcc3ap|zzrn3a|zzlc3a|zzmv3a|zzcl3a)$' })) {
            Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
            Write-Host "    swept $($f.FullName)"
        }
    }
}

# --- refusals and inputs -----------------------------------------------------
foreach ($p in @($sdExe, $gcat, $BpDir)) {
    if (-not (Test-Path -LiteralPath $p)) { Bail 2 "missing: $p" }
}
Write-Host "verify-callcase: account $Account"
Write-Host "verify-callcase: dir     $AcctDir"
Write-Host "verify-callcase: sd.exe  $sdExe"
Write-Host "verify-callcase: gcat    $gcat"
Write-Host "verify-callcase: pcode   $pcodeF"
Write-Host ''
Write-Host '--- assert-current -------------------------------------------------'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
Write-Host ''
Write-Host '--- sweep leftovers ---------------------------------------------------'
Remove-Fixtures

try {
    # --- A. the global catalogue listing -------------------------------------
    Write-Host ''
    Write-Host '--- A. gcat listing ----------------------------------------------------'
    $names = @(Get-ChildItem -LiteralPath $gcat -File | ForEach-Object { $_.Name })
    $upper = @($names | Where-Object { $_ -cmatch '[A-Z]' })
    Write-Host ("  entries: {0}; with an upper-case letter: {1}" -f $names.Count, $upper.Count)
    if ($upper.Count) { Write-Host ("  first upper-case entries: " + (($upper | Select-Object -First 10) -join ' ')) }
    Row 'CONTROL A: gcat holds a full catalogue (100 or more entries)' ($names.Count -ge 100) "entries: $($names.Count)"
    Row "A: gcat holds `$cproc under that exact name, non-empty" ((@($names | Where-Object { $_ -ceq '$cproc' }).Count -eq 1) -and ((Get-Item -LiteralPath (Join-Path $gcat '$cproc')).Length -gt 0)) 'no entry named exactly $cproc'
    Row 'A: no gcat entry name carries an upper-case letter' (($names.Count -gt 0) -and ($upper.Count -eq 0)) ("upper-case entries: " + (($upper | Select-Object -First 10) -join ' '))

    # --- B. the pcode library's header names ---------------------------------
    # OBJECT_HEADER (gplsrc/header.h): object_size int32 at 24, program_name at
    # 36, items padded to 4 bytes - sd.c load_pcode() walks it the same way.
    Write-Host ''
    Write-Host '--- B. bin\pcode header names ----------------------------------------'
    $pnames = @()
    try {
        $b = [System.IO.File]::ReadAllBytes($pcodeF)
        $i = 0
        while ($i -lt $b.Length) {
            if ($b[$i] -ne 0x64) { $pnames += "<bad magic at $i>"; break }
            $size = [BitConverter]::ToInt32($b, $i + 24)
            $end = $i + 36
            while ($end -lt $b.Length -and $b[$end] -ne 0) { $end++ }
            $pnames += [System.Text.Encoding]::ASCII.GetString($b, $i + 36, $end - ($i + 36))
            if ($size -le 0) { break }
            $i += ($size + 3) -band (-bnot 3)
        }
    } catch { $pnames += "<unreadable: $($_.Exception.Message)>" }
    $pupper = @($pnames | Where-Object { $_ -cmatch '[A-Z<]' })
    Write-Host ("  items: {0}; names: {1}" -f $pnames.Count, ($pnames -join ' '))
    Row 'CONTROL B: the pcode library parsed into 50 or more items' ($pnames.Count -ge 50) "items: $($pnames.Count)"
    Row "B: 'ak' and 'voc_cat' are there under exactly those names" ((($pnames -ceq 'ak').Count -eq 1) -and (($pnames -ceq 'voc_cat').Count -eq 1)) ($pnames -join ' ')
    Row 'B: no pcode header name carries an upper-case letter' (($pnames.Count -gt 0) -and ($pupper.Count -eq 0)) ($pupper -join ' ')

    # --- fixtures: four programs in bp -----------------------------------------
    Write-Host ''
    Write-Host '--- the stored-id matcher, on known text ---------------------------------'
    $probe = "zzcl3a added to local catalogue`nZZCL3A deleted from the local catalogue`n:LIST VOC WITH @ID = `"zzcl3a`"`nZZCL3A               `nzzcl3a"
    $hit = @(Get-StoredVocIds $probe 'zzcl3a')
    Write-Host ("  matched: " + ($hit -join ' '))
    Row 'CONTROL: the matcher takes LIST rows and ignores 3029/3040 message lines' (($hit.Count -eq 2) -and ($hit[0] -ceq 'ZZCL3A') -and ($hit[1] -ceq 'zzcl3a')) ("matched: " + ($hit -join ' '))

    Write-Host ''
    Write-Host '--- fixtures -----------------------------------------------------------'
    Write-Record (Join-Path $BpDir 'zzcc3ap') @('subroutine zzcc3ap(r)', "   r = 'ok3a'", '   return', 'end')
    Write-Record (Join-Path $BpDir 'zzrn3a') @(
        "   x = '!USERNAME'", '   r = ''''', '   call @x(r, @userno)', "   crt 'CTL3A [':r:']'",
        "   y = 'ZZCC3AP'", '   s = ''''', '   call @y(s)', "   crt 'PRIV3A [':s:']'",
        "   n = '!zzNoSuchSub3a'", '   call @n(t, @userno)', "   crt 'NOT REACHED3A'", 'end')
    Write-Record (Join-Path $BpDir 'zzlc3a') @("   y = 'ZZCL3A'", '   s = ''''', '   call @y(s)', "   crt 'LOCAL3A [':s:']'", 'end')
    $mk = Invoke-SD @(($Progs | ForEach-Object { "BASIC bp $_" }))
    Show 'BASIC' $mk
    $clean = [regex]::Matches($mk.Text, '(?m)^Compiled 1 program\(s\) with no errors').Count
    Row "setup: all $($Progs.Count) fixture programs compiled with no errors" ($clean -eq $Progs.Count) "clean compiles: $clean of $($Progs.Count)"
    if ($clean -ne $Progs.Count) { Bail 2 'the fixtures did not compile - nothing below would measure the names.' }

    # --- C, D. private catalogue and the runtime's own spelling -----------------
    Write-Host ''
    Write-Host '--- C, D. CATALOG into the private catalogue; the runtime error text --'
    $pv = Invoke-SD @('CATALOG bp ZZCC3AP', 'RUN bp zzrn3a')
    Show 'CATALOG bp ZZCC3AP / RUN bp zzrn3a' $pv
    $catNames = @(Get-ChildItem -LiteralPath $CatDir -File -ErrorAction SilentlyContinue | ForEach-Object { $_.Name })
    Write-Host ("  cat\ holds: " + ($catNames -join ' '))
    Row "D: CATALOG said 'zzcc3ap added to private catalogue' (3031, lower case)" ($pv.Text -cmatch '(?m)^zzcc3ap added to private catalogue') 'no 3031 line naming zzcc3ap in lower case'
    Row "D: the private catalogue file is named exactly 'zzcc3ap'" ((@($catNames | Where-Object { $_ -ceq 'zzcc3ap' }).Count -eq 1) -and (@($catNames | Where-Object { $_ -ieq 'zzcc3ap' }).Count -eq 1)) ("cat\ holds: " + ($catNames -join ' '))
    Row 'CONTROL C: !USERNAME (typed upper) still answers' ($pv.Text -match '(?m)^CTL3A \[\S+\]') 'no CTL3A line with a value'
    Row 'D: the private entry answers a call typed ZZCC3AP' ($pv.Text -match '(?m)^PRIV3A \[ok3a\]') 'no PRIV3A [ok3a] line'
    Row "C: the runtime names a missing call '!zznosuchsub3a' - lower case" ($pv.Text -cmatch "Unable to load '!zznosuchsub3a'") "no load error naming '!zznosuchsub3a' in lower case"

    # --- E, F. local catalogue: new entry, then one planted the old way ---------
    Write-Host ''
    Write-Host '--- E, F. CATALOG LOCAL, and an entry catalogued before stage 3a -------'
    $lc = Invoke-SD @('CATALOG bp zzcl3a zzcc3ap LOCAL', 'LIST VOC WITH @ID LIKE "zzcl..."')
    Show 'CATALOG LOCAL' $lc
    Row "E: CATALOG said 'zzcl3a added to local catalogue' (3029, lower case)" ($lc.Text -cmatch '(?m)^zzcl3a added to local catalogue') 'no 3029 line naming zzcl3a in lower case'
    # @() because PowerShell unrolls a one-element result to a bare string, and
    # $ids[0] would then be its first character.
    $ids = @(Get-StoredVocIds $lc.Text 'zzcl3a')
    Row "E: the VOC stores 'zzcl3a' and no other spelling" ((@($ids).Count -eq 1) -and ($ids[0] -ceq 'zzcl3a')) ("stored: " + ($ids -join ' '))

    # 14 Sep 26 - F's PLANT IS RETIRED (see the header).  zzmv3a wrote ZZCL3A
    # and deleted zzcl3a; under D2 that delete removed the one record (b161:
    # "PLANTED3A V CS", then "'zzcl3a' not found" and "Unable to load 'zzcl3a'").
    # F now calls the entry E made, typed upper, and re-catalogues over it.
    $pl = Invoke-SD @('RUN bp zzlc3a')
    Show 'call the local entry typed ZZCL3A' $pl
    Row 'F: a call typed ZZCL3A finds the local entry' ($pl.Text -match '(?m)^LOCAL3A \[ok3a\]') 'no LOCAL3A [ok3a] line'

    $rc = Invoke-SD @('CATALOG bp zzcl3a zzcc3ap LOCAL', 'LIST VOC WITH @ID LIKE "zzcl..."')
    Show 'CATALOG LOCAL over the existing entry' $rc
    $ids = @(Get-StoredVocIds $rc.Text 'zzcl3a')
    Row "F: re-cataloguing left exactly one entry, stored 'zzcl3a'" ((@($ids).Count -eq 1) -and ($ids[0] -ceq 'zzcl3a')) ("stored: " + ($ids -join ' '))

    # --- G. DELETE.CATALOG, both catalogues ---------------------------------
    Write-Host ''
    Write-Host '--- G. DELETE.CATALOG ---------------------------------------------------'
    $dc = Invoke-SD @('DELETE.CATALOG ZZCC3AP', 'DELETE.CATALOG ZZCL3A LOCAL', 'LIST VOC WITH @ID LIKE "zzcl..."')
    Show 'DELETE.CATALOG' $dc
    Row "G: 3042 names 'zzcc3ap' deleted from the private catalogue" ($dc.Text -cmatch '(?m)^zzcc3ap deleted from the private catalogue') 'no 3042 line naming zzcc3ap'
    Row "G: 3040 names 'zzcl3a' deleted from the local catalogue, typed ZZCL3A" ($dc.Text -cmatch '(?m)^zzcl3a deleted from the local catalogue') 'no 3040 line naming zzcl3a'
    Row 'G: no zzcl3a entry is stored in any case' (@(Get-StoredVocIds $dc.Text 'zzcl3a').Count -eq 0) 'a VOC entry remains'
    Row 'G: cat\ no longer holds zzcc3ap' (@(Get-ChildItem -LiteralPath $CatDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq 'zzcc3ap' }).Count -eq 0) 'the private catalogue file remains'
}
finally {
    Write-Host ''
    Write-Host '--- cleanup ----------------------------------------------------------'
    Remove-Fixtures
    $left = @()
    foreach ($d in @($BpDir, (Join-Path $AcctDir 'bp.out'), $CatDir)) {
        $left += @(Get-ChildItem -LiteralPath $d -File -ErrorAction SilentlyContinue |
                   Where-Object { $_.Name -match '(?i)^(zzcc3ap|zzrn3a|zzlc3a|zzmv3a|zzcl3a)$' } | ForEach-Object { $_.FullName })
    }
    Row 'cleanup: no fixture file is left in bp, bp.out or cat' ($left.Count -eq 0) ($left -join ' ')
}

Write-Host ''
Write-Host "verify-callcase: $pass passed, $fail failed"
if (($pass + $fail) -eq 0) { Bail 2 'no check ran - a broken test, not a pass.' }
if ($fail -gt 0) { Bail 1 "$fail check(s) failed." }
Bail 0 'program and catalogue names are produced and stored in lower case.'
