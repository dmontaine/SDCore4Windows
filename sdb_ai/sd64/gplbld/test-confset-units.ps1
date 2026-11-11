# test-confset-units.ps1 - drive sd-confset.ps1, the Windows half of SET.CONFIG (RELEASE_1.1 218).
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-confset-units.ps1
#
# ORDINARY UNELEVATED PROMPT.  No install, no SD, no elevation.  Exit 0 all passed, 1 something
# failed, 2 could not set up.  Everything it makes is under %TEMP%\test-confset-<id> and is removed
# at the end; no real sd.conf is read or written (every run passes -ConfPath).
#
# WHY IT EXISTS.  The script edits THE FILE THAT DECIDES WHETHER SD STARTS.  What must be proved is
# what would fail silently: that only the one line changes (comments, other sections and line ends
# byte for byte), that a KEY= line outside [sd] is not taken for the setting, that duplicates are
# folded to one, that a refusal and a no-op write nothing, that the old file is kept as .bak, and
# that the helper's list of 14 and their ranges and effects are the ones sdsys\config.table states.
# The Windows carry of Linux's test-confset-elevate-units.py (10 Nov 2026), in the shape of
# test-backupdir-units.ps1: the pure functions are lifted from the file by AST, and the end-to-end
# rows run the real script as a child process, which is how SD runs it.
#
# NOT SHIPPED - assert-current exempts test-* scripts by name.

$ErrorActionPreference = 'Stop'

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $here 'sd-confset.ps1'
$table   = Join-Path (Split-Path -Parent $here) 'sdsys\config.table'
Write-Host "test-confset-units: subject $subject"
Write-Host "test-confset-units: table   $table"
if (-not (Test-Path -LiteralPath $subject)) { Write-Host 'test-confset-units: subject not found.'; exit 2 }
if (-not (Test-Path -LiteralPath $table)) { Write-Host 'test-confset-units: config.table not found.'; exit 2 }

$tok = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($subject, [ref]$tok, [ref]$errs)
if ($errs.Count -gt 0) { Write-Host "test-confset-units: subject has $($errs.Count) parse error(s)."; exit 2 }

$srcText = @{}
foreach ($name in @('Test-Setting', 'Get-Scan')) {
    $fn = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true))
    if ($fn.Count -ne 1) { Write-Host "test-confset-units: expected exactly one $name, found $($fn.Count)."; exit 2 }
    $srcText[$name] = $fn[0].Extent.Text
    . ([scriptblock]::Create($fn[0].Extent.Text))
}
foreach ($var in @('Writable', 'Fixed')) {
    $as = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$' + $var)
    }, $false))
    if ($as.Count -ne 1) { Write-Host "test-confset-units: expected one assignment to `$$var, found $($as.Count)."; exit 2 }
    . ([scriptblock]::Create($as[0].Extent.Text))
}
Write-Host "  lifted Test-Setting, Get-Scan, `$Writable ($($Writable.Count) names), `$Fixed ($($Fixed.Count) names)"

$script:pass = 0
$script:fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $what" }
    else     { $script:fail++; Write-Host "  [FAIL] $what $detail" }
}
function Bytes([string]$p) { return [System.IO.File]::ReadAllBytes($p) }
function Hex([byte[]]$b) { return [System.BitConverter]::ToString($b) }

$work = Join-Path $env:TEMP ('test-confset-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($work)
$ascii = [System.Text.Encoding]::ASCII

function Run-Script([string[]]$a) {
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $subject @a 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o.Trim() }
}
function New-Conf([string]$name, [string[]]$lines, [string]$nl) {
    $p = Join-Path $work $name
    [System.IO.File]::WriteAllBytes($p, $ascii.GetBytes(($lines -join $nl) + $nl))
    return $p
}
function Text([string]$p) { return $ascii.GetString((Bytes $p)) }

$minimum = 45
try {
    # --- 1. the helper agrees with config.table --------------------------------
    Write-Host ''
    Write-Host '1. the helper and sdsys\config.table'
    $rows = @(Get-Content -LiteralPath $table | Where-Object { $_ -ne '' -and -not $_.StartsWith('#') })
    $yes = @{}; $no = @()
    foreach ($r in $rows) {
        $f = $r -split '\|'
        if ($f[8] -eq 'yes') { $yes[$f[0]] = @([int]$f[3], [int]$f[4], $f[5]) } else { $no += $f[0] }
    }
    Write-Host "  table: $($rows.Count) rows, $($yes.Count) write=yes, $($no.Count) write=no"
    Check 'the table has rows (refuses the null case)' ($rows.Count -gt 40)
    Check 'the 14 write=yes rows are the helper''s 14 names' (((@($yes.Keys) | Sort-Object) -join ',') -ceq ((@($Writable.Keys) | Sort-Object) -join ','))
    $same = $true
    foreach ($k in $yes.Keys) {
        if (-not $Writable.ContainsKey($k)) { $same = $false; continue }
        $w = $Writable[$k]; $t = $yes[$k]
        if ($w[0] -ne $t[0] -or $w[1] -ne $t[1] -or $w[2] -cne $t[2]) { $same = $false; Write-Host "    differs: $k helper $($w -join '/') table $($t -join '/')" }
    }
    Check 'each one''s range and effect are the table''s' $same
    Check 'the write=no rows are the helper''s known-but-fixed names' ((($no | Sort-Object) -join ',') -ceq (($Fixed | Sort-Object) -join ','))

    # --- 2. what may be written -------------------------------------------------
    Write-Host ''
    Write-Host '2. Test-Setting'
    foreach ($ok in @(@('CLEANUP', '600'), @('CLEANUP', '30'), @('CLEANUP', '3600'), @('USPLIT', '0'), @('MAXCALL', '1000000'), @('GRPSIZE', '8'))) {
        Check "accepted: $($ok[0])=$($ok[1])" ((Test-Setting $ok[0] $ok[1]) -eq '')
    }
    $bad = @(
        @('', '1', 'no parameter name'), @('cleanup', '600', 'capital letter'), @('CLEAN-UP', '600', 'capital letter'),
        @('ABCDEFGHIJKLM', '1', 'longer than any'), @('FROBNICATE', '1', 'not a parameter SD knows'),
        @('SH', '1', 'SD knows, and set.config does not change'), @('APIPORT', '0', 'SD knows, and set.config does not change'),
        @('NETDIRS', '1', 'SD knows, and set.config does not change'), @('STARTUP', '1', 'not a parameter SD knows'),
        @('CLEANUP', '', 'no value'), @('CLEANUP', '-1', 'digits only'), @('CLEANUP', '6 00', 'digits only'),
        @('CLEANUP', '60.5', 'digits only'), @('CLEANUP', '12345678', 'more than 7'), @('CLEANUP', '0600', 'start with a zero'),
        @('CLEANUP', '29', 'outside the range 30 to 3600'), @('CLEANUP', '3601', 'outside the range'), @('USPLIT', '2', 'outside the range 0 to 1')
    )
    foreach ($b in $bad) {
        $w = Test-Setting $b[0] $b[1]
        Check "refused: '$($b[0])' '$($b[1])' ($($b[2]))" ($w -ne '' -and $w.Contains($b[2])) "got: $w"
    }

    # --- 3. the scan, as config.c reads the file ---------------------------------
    Write-Host ''
    Write-Host '3. Get-Scan'
    $L = @('# head', '[sd]', 'SDSYS=C:\x', '# CLEANUP=1', 'CLEANUP=100', 'cleanup=7', '', '[other]', 'CLEANUP=200', '[SD]', 'NUMUSERS=2', 'CLEANUP=300', '# tail')
    $s = Get-Scan $L 'CLEANUP'
    Check 'the first CLEANUP= in [sd] is line 4' ($s.First -eq 4) "got $($s.First)"
    Check 'the one in the second [SD] section is a duplicate to drop' (($s.Drops -join ',') -eq '11') "got $($s.Drops -join ',')"
    Check 'the [other] section, a comment and a lower-case key do not count' ($s.Count -eq 2)
    Check 'the add point is the last setting of the last [sd] section' ($s.After -eq 11) "got $($s.After)"
    $s = Get-Scan @('[sd]', 'A=1', '# c', '[x]', 'B=2') 'CLEANUP'
    Check 'no CLEANUP: the add point is A=1, not the comment or [x]' ($s.First -eq -1 -and $s.After -eq 1)
    $s = Get-Scan @('[x]', 'CLEANUP=5') 'CLEANUP'
    Check 'no [sd] section: no add point' ($s.After -eq -1 -and $s.Count -eq 0)
    $s = Get-Scan @('[Sd]', 'CLEANUPX=5', 'CLEANUP=6') 'CLEANUP'
    Check 'the section name is compared in capitals; CLEANUPX is another name' ($s.First -eq 2 -and $s.Count -eq 1)

    $m1 = $srcText['Get-Scan'].Replace('if (-not $insd) { continue }', '')
    . ([scriptblock]::Create($m1))
    $s = Get-Scan @('[sd]', 'A=1', '[other]', 'CLEANUP=200') 'CLEANUP'
    Check 'MUTANT: a scan that ignores the section takes [other]''s line and is caught' ($m1 -ne $srcText['Get-Scan'] -and $s.First -ne -1)
    . ([scriptblock]::Create($srcText['Get-Scan']))
    $m2 = $srcText['Test-Setting'].Replace('-cnotmatch ''^[A-Z][A-Z0-9]*$''', '-notmatch ''^[A-Z][A-Z0-9]*$''')
    . ([scriptblock]::Create($m2))
    Check 'MUTANT: a case-blind name check lets "cleanup" through and is caught' ($m2 -ne $srcText['Test-Setting'] -and (Test-Setting 'cleanup' '600') -notlike '*capital letter*')
    . ([scriptblock]::Create($srcText['Test-Setting']))
    Check 'CONTROL: the real functions are back' ((Test-Setting 'cleanup' '600') -like '*capital letter*' -and (Get-Scan @('[sd]', '[o]', 'CLEANUP=1') 'CLEANUP').First -eq -1)

    # --- 4. the real script, as SD runs it -------------------------------------
    Write-Host ''
    Write-Host '4. the script, end to end (scratch sd.conf, real child process)'
    $lines = @('[sd]', 'SDSYS=C:\ProgramData\SD\sdsys', '# a comment inside [sd]', 'CLEANUP=300', 'GRPSIZE=2', '', '[other]', 'CLEANUP=999', '[sd]', 'CLEANUP=301', 'ERRLOG=50', '# the end')
    $conf = New-Conf 'sd.conf' $lines "`r`n"
    $before = Bytes $conf
    $r = Run-Script @('-Name', 'CLEANUP', '-Value', '600', '-ConfPath', $conf)
    Write-Host "    output: $($r.Out -replace "`r?`n", ' / ')"
    Check 'the first line echoes the real inputs' ($r.Out -match [regex]::Escape("SD-CONFSET name=CLEANUP value=600 conf=$conf"))
    Check 'exit 0 and the success line with the effect' ($r.Code -eq 0 -and $r.Out -match 'SD-CONFSET OK CLEANUP 600 restart$')
    $want = @('[sd]', 'SDSYS=C:\ProgramData\SD\sdsys', '# a comment inside [sd]', 'CLEANUP=600', 'GRPSIZE=2', '', '[other]', 'CLEANUP=999', '[sd]', 'ERRLOG=50', '# the end')
    Check 'the file: first line replaced, the duplicate in the second [sd] dropped, [other] and comments kept, CRLF kept' ((Text $conf) -ceq (($want -join "`r`n") + "`r`n")) (Text $conf)
    Check 'the old file is kept as sd.conf.bak, byte for byte' ((Hex (Bytes ($conf + '.bak'))) -eq (Hex $before))
    Check 'no temporary file is left beside it' (@(Get-ChildItem -LiteralPath $work -Filter '*.new').Count -eq 0)

    $mid = Bytes $conf
    $bakMid = Bytes ($conf + '.bak')
    $r = Run-Script @('-Name', 'CLEANUP', '-Value', '600', '-ConfPath', $conf)
    Check 'the same value again: OK ... unchanged, exit 0' ($r.Code -eq 0 -and $r.Out -match 'SD-CONFSET OK CLEANUP 600 restart unchanged$') $r.Out
    Check '... and neither the file nor .bak was touched' ((Hex (Bytes $conf)) -eq (Hex $mid) -and (Hex (Bytes ($conf + '.bak'))) -eq (Hex $bakMid))

    $r = Run-Script @('-Name', 'NETWAIT', '-Value', '20', '-ConfPath', $conf)
    $t = Text $conf
    Check 'a parameter the file lacks is added after the last setting of the last [sd] section' ($r.Code -eq 0 -and $t.Contains("ERRLOG=50`r`nNETWAIT=20`r`n# the end") -and $r.Out -match 'OK NETWAIT 20 session$') $t

    $mid = Bytes $conf
    foreach ($b in @(@('CLEANUP', '29'), @('SH', '1'), @('cleanup', '600'), @('CLEANUP', '0600'), @('BOGUS', '1'))) {
        $r = Run-Script @('-Name', $b[0], '-Value', $b[1], '-ConfPath', $conf)
        Check "refused end to end: $($b[0]) $($b[1]) (exit 1, ERROR, no OK)" ($r.Code -eq 1 -and $r.Out -match 'SD-CONFSET ERROR' -and $r.Out -notmatch 'SD-CONFSET OK') $r.Out
    }
    Check '... and the refusals left the file as it was' ((Hex (Bytes $conf)) -eq (Hex $mid))

    $lf = New-Conf 'lf.conf' @('[sd]', 'GRPSIZE=2') "`n"
    $r = Run-Script @('-Name', 'GRPSIZE', '-Value', '4', '-ConfPath', $lf)
    Check 'an LF file stays LF' ($r.Code -eq 0 -and (Text $lf) -ceq "[sd]`nGRPSIZE=4`n") (Text $lf)

    $nosd = New-Conf 'nosd.conf' @('[other]', 'GRPSIZE=2') "`r`n"
    $nb = Bytes $nosd
    $r = Run-Script @('-Name', 'GRPSIZE', '-Value', '4', '-ConfPath', $nosd)
    Check 'a file with no [sd] section is refused and untouched' ($r.Code -eq 1 -and $r.Out -match 'no \[sd\] section' -and (Hex (Bytes $nosd)) -eq (Hex $nb)) $r.Out

    $hi = Join-Path $work 'hi.conf'
    [System.IO.File]::WriteAllBytes($hi, [byte[]](@(91, 115, 100, 93, 13, 10) + $ascii.GetBytes('SH=caf') + @(0xE9, 13, 10)))
    $hb = Bytes $hi
    $r = Run-Script @('-Name', 'GRPSIZE', '-Value', '4', '-ConfPath', $hi)
    Check 'a file with a byte outside plain ASCII is refused and untouched' ($r.Code -eq 1 -and $r.Out -match 'not plain ASCII' -and (Hex (Bytes $hi)) -eq (Hex $hb)) $r.Out

    $r = Run-Script @('-Name', 'GRPSIZE', '-Value', '4', '-ConfPath', (Join-Path $work 'missing.conf'))
    Check 'a missing sd.conf is refused by name' ($r.Code -eq 1 -and $r.Out -match 'is not a regular file') $r.Out
}
catch {
    Write-Host "test-confset-units: STOPPED - $($_.Exception.Message)"
    if ($script:fail -gt 0) { Write-Host "test-confset-units: FAILED - $($script:fail) failed before it stopped."; exit 1 }
    exit 2
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

if ($script:pass -eq 0) { Write-Host 'test-confset-units: VOID - no check ran.'; exit 2 }
if (($script:pass + $script:fail) -lt $minimum) { Write-Host "test-confset-units: REFUSED - only $($script:pass + $script:fail) checks ran, expected at least $minimum."; exit 1 }
if ($script:fail -gt 0) { Write-Host "test-confset-units: FAILED - $($script:pass) passed, $($script:fail) failed."; exit 1 }
Write-Host "test-confset-units: PASSED - $($script:pass) of $($script:pass) checks passed."
exit 0
