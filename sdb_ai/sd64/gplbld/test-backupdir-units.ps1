# test-backupdir-units.ps1 - drive sd-backupdir.ps1: the saved backup directory in sd.conf.
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4WindowsSolo\sdb_ai\sd64\gplbld\test-backupdir-units.ps1
#
# ORDINARY UNELEVATED PROMPT.  No install, no SD, no elevation.  Exit 0 all passed, 1 something
# failed, 2 could not set up.  Everything it makes is under %TEMP%\test-backupdir-<id> and is
# removed at the end; no real sd.conf is read or written (every run passes -ConfPath).
#
# WHY IT EXISTS.  Owner's ruling, 1 Oct 2026: SET.BACKUP.DIRECTORY saves the backup directory in
# the config file.  The script edits THE FILE THAT DECIDES WHETHER SD STARTS, so the things that
# must be proved are the ones whose failure is silent: that only the BACKUPDIR line changes
# (byte for byte), that CRLF and ASCII survive, that a refusal leaves the file untouched, and that
# the directory really is made and writable.  The pure functions are lifted from the file by AST
# (test-sdpath-units.ps1's technique) so this tests the shipped text; the end-to-end rows run the
# real script as a child process, which is how SD runs it.
#
# NOT SHIPPED - assert-current exempts test-* scripts by name.

$ErrorActionPreference = 'Stop'

$here    = Split-Path -Parent $MyInvocation.MyCommand.Path
$subject = Join-Path $here 'sd-backupdir.ps1'
Write-Host "test-backupdir-units: subject $subject"
if (-not (Test-Path -LiteralPath $subject)) { Write-Host 'test-backupdir-units: subject not found.'; exit 2 }

$tok = $null; $errs = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($subject, [ref]$tok, [ref]$errs)
if ($errs.Count -gt 0) { Write-Host "test-backupdir-units: subject has $($errs.Count) parse error(s)."; exit 2 }

$wanted = @('Test-BackupPath', 'Split-ConfText', 'Get-BackupDirLine', 'Set-BackupDirLine', 'Get-OtherLines')
$srcText = @{}
foreach ($name in $wanted) {
    $fn = @($ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true))
    if ($fn.Count -ne 1) { Write-Host "test-backupdir-units: expected exactly one $name, found $($fn.Count)."; exit 2 }
    $srcText[$name] = $fn[0].Extent.Text
    . ([scriptblock]::Create($fn[0].Extent.Text))
}
Write-Host "  lifted $($wanted.Count) functions"

# NOTE FOR WHOEVER EDITS THIS: Set-BackupDirLine and Get-OtherLines return ,@(...) - ONE object that is
# an array.  Call them as "$r = (f ...)" and the result is that array; wrapping the call in @( ) NESTS it
# (an array holding the array), and "-join" then joins one element.  That was this file's first draft.
$script:pass = 0
$script:fail = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Host "  [PASS] $what" }
    else     { $script:fail++; Write-Host "  [FAIL] $what $detail" }
}
function Bytes([string]$p) { return [System.IO.File]::ReadAllBytes($p) }
function Hex([byte[]]$b) { return [System.BitConverter]::ToString($b) }
function Count-Byte([byte[]]$b, [byte]$v) { return @($b | Where-Object { $_ -eq $v }).Count }

$work = Join-Path $env:TEMP ('test-backupdir-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
[void][System.IO.Directory]::CreateDirectory($work)
$ascii = [System.Text.Encoding]::ASCII

function Run-Script([string[]]$a) {
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $subject @a 2>&1 | Out-String
    return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $o.Trim() }
}
function New-Conf([string]$name, [string]$nl, [bool]$finalNl) {
    $lines = @('# sd.conf', 'SDSYS=C:\SD\sdsys', 'USRDIR=C:\SD\user_accounts', 'NUMUSERS=20', 'APIPORT=4249',
               '# BACKUPDIR=C:\a-comment-is-not-a-setting', 'backupdir=C:\lower-case-is-not-a-setting', 'ERRLOG=50')
    $p = Join-Path $work $name
    $t = ($lines -join $nl); if ($finalNl) { $t += $nl }
    [System.IO.File]::WriteAllBytes($p, $ascii.GetBytes($t))
    return $p
}

try {
    # --- 1. the path rules ---------------------------------------------------
    Write-Host ''
    Write-Host '1. Test-BackupPath'
    foreach ($ok in @('C:\Backups', 'C:/Backups', 'D:\My Backups\Sales', '\\server\share\backups', 'c:\a')) {
        Check "accepted: $ok" ((Test-BackupPath $ok) -eq '')
    }
    $long = 'C:\' + ('a' * 250)
    $bad = @(
        @{ P = '';                  Why = 'empty' },
        @{ P = 'backups';           Why = 'relative' },
        @{ P = 'C:backups';         Why = 'drive-relative' },
        @{ P = '/c/Backups';        Why = 'POSIX form' },
        @{ P = ' C:\Backups';       Why = 'leading space' },
        @{ P = 'C:\Backups ';       Why = 'trailing space' },
        @{ P = 'C:\Back*ups';       Why = 'wildcard' },
        @{ P = 'C:\Back"ups';       Why = 'quote' },
        @{ P = 'C:\Back|ups';       Why = 'pipe' },
        @{ P = ('C:\caf' + [char]0xE9); Why = 'non-ASCII' },
        @{ P = $long;               Why = 'over 240 characters' }
    )
    foreach ($b in $bad) { Check "refused ($($b.Why))" ((Test-BackupPath $b.P) -ne '') }

    # --- 2. reading and editing the lines ------------------------------------
    Write-Host ''
    Write-Host '2. the lines'
    $none = @('A=1', 'B=2', '')
    Check 'no BACKUPDIR line: nothing saved' ((Get-BackupDirLine $none) -eq '')
    Check 'a commented line is not a setting' ((Get-BackupDirLine @('# BACKUPDIR=C:\x')) -eq '')
    Check 'a lower-case key is not a setting (C compares case-sensitively)' ((Get-BackupDirLine @('backupdir=C:\x')) -eq '')
    Check 'the first active line wins' ((Get-BackupDirLine @('BACKUPDIR=C:\one', 'BACKUPDIR=C:\two')) -ceq 'C:\one')
    Check 'a value with spaces is read whole' ((Get-BackupDirLine @('BACKUPDIR=C:\My Backups')) -ceq 'C:\My Backups')

    $r = (Set-BackupDirLine $none 'C:\NewDir')
    Check 'added before the final empty element, so the file still ends with a newline' (($r -join '|') -ceq 'A=1|B=2|BACKUPDIR=C:\NewDir|')
    $r = (Set-BackupDirLine @('A=1', 'B=2') 'C:\NewDir')
    Check 'added at the end when the file had no final newline' (($r -join '|') -ceq 'A=1|B=2|BACKUPDIR=C:\NewDir')
    $r = (Set-BackupDirLine @('A=1', 'BACKUPDIR=C:\Old', 'B=2', '') 'C:\NewDir')
    Check 'an existing line is replaced in place' (($r -join '|') -ceq 'A=1|BACKUPDIR=C:\NewDir|B=2|')
    $r = (Set-BackupDirLine @('BACKUPDIR=C:\one', 'X=1', 'BACKUPDIR=C:\two') 'C:\NewDir')
    Check 'only the first of several is replaced' (($r -join '|') -ceq 'BACKUPDIR=C:\NewDir|X=1|BACKUPDIR=C:\two')
    $r = (Set-BackupDirLine @('# BACKUPDIR=C:\c', 'A=1', '') 'C:\NewDir')
    Check 'a comment is left alone and the setting is added' (($r -join '|') -ceq '# BACKUPDIR=C:\c|A=1|BACKUPDIR=C:\NewDir|')
    Check 'Get-OtherLines drops only the setting lines' (((Get-OtherLines @('A=1', 'BACKUPDIR=C:\x', '# BACKUPDIR=C:\y', 'B=2')) -join '|') -ceq 'A=1|# BACKUPDIR=C:\y|B=2')
    $sp = Split-ConfText "a`r`nb`r`n"
    Check 'CRLF is recognised and kept' ($sp.Nl -eq "`r`n" -and ($sp.Lines -join '|') -ceq 'a|b|')
    $sp = Split-ConfText "a`nb"
    Check 'LF is recognised and kept' ($sp.Nl -eq "`n" -and ($sp.Lines -join '|') -ceq 'a|b')

    # MUTANTS on synthetic text: the two edits most likely to be made by a tidy-up.
    $m1 = $srcText['Set-BackupDirLine'].Replace('if ((-not $done) -and ($l -clike ''BACKUPDIR=*''))', 'if ($false)')
    . ([scriptblock]::Create($m1))
    $r = (Set-BackupDirLine @('A=1', 'BACKUPDIR=C:\Old', '') 'C:\NewDir')
    Check 'MUTANT: never replacing (always appending) leaves two lines and is caught' ($m1 -ne $srcText['Set-BackupDirLine'] -and @($r | Where-Object { $_ -clike 'BACKUPDIR=*' }).Count -ne 1)
    . ([scriptblock]::Create($srcText['Set-BackupDirLine']))
    $m2 = $srcText['Get-BackupDirLine'].Replace('-clike', '-like')
    . ([scriptblock]::Create($m2))
    Check 'MUTANT: a case-insensitive match reads the lower-case line and is caught' ($m2 -ne $srcText['Get-BackupDirLine'] -and (Get-BackupDirLine @('backupdir=C:\x')) -ne '')
    . ([scriptblock]::Create($srcText['Get-BackupDirLine']))
    Check 'CONTROL: the real functions are back and behave' ((Get-BackupDirLine @('backupdir=C:\x')) -eq '' -and ((Set-BackupDirLine @('A=1', '') 'C:\z') -join '|') -ceq 'A=1|BACKUPDIR=C:\z|')

    # --- 3. the real script, as SD runs it -----------------------------------
    Write-Host ''
    Write-Host '3. the script, end to end (scratch sd.conf, real child process)'
    $conf = New-Conf 'sd.conf' "`r`n" $true
    $before = Bytes $conf
    $r = Run-Script @('-Mode', 'Get', '-ConfPath', $conf)
    Write-Host ("    " + ($r.Out -replace "`r?`n", "`n    "))
    Check 'Get with nothing saved: GET NONE, exit 0' ($r.Code -eq 0 -and $r.Out -match 'SD-BACKUPDIR GET NONE')
    Check 'Get changed nothing in the file' ((Hex (Bytes $conf)) -ceq (Hex $before))
    Check 'the run echoed its real inputs (mode, path, conf)' ($r.Out -match [regex]::Escape("conf=$conf"))

    $target = Join-Path $work 'bk one\nested\dir'
    $r = Run-Script @('-Mode', 'Set', '-Path', $target, '-ConfPath', $conf)
    Write-Host ("    " + ($r.Out -replace "`r?`n", "`n    "))
    Check 'Set: exit 0 and SET OK with the full path' ($r.Code -eq 0 -and $r.Out -match [regex]::Escape("SD-BACKUPDIR SET OK $target"))
    Check 'no ERROR line on the success path' ($r.Out -notmatch 'SD-BACKUPDIR ERROR')
    Check 'the nested directory was created' (Test-Path -LiteralPath $target -PathType Container)
    Check 'no probe file is left in it' (@(Get-ChildItem -LiteralPath $target -Force).Count -eq 0)
    $after = Bytes $conf
    $afterText = $ascii.GetString($after)
    $mine = @($afterText -split "`r`n" | Where-Object { $_ -clike 'BACKUPDIR=*' })
    Check 'exactly one BACKUPDIR line, holding the path' ($mine.Count -eq 1 -and $mine[0] -ceq "BACKUPDIR=$target")
    $otherBefore = (@($ascii.GetString($before) -split "`r`n") | Where-Object { -not ($_ -clike 'BACKUPDIR=*') }) -join "`r`n"
    $otherAfter  = (@($afterText -split "`r`n") | Where-Object { -not ($_ -clike 'BACKUPDIR=*') }) -join "`r`n"
    Check 'every other line is byte for byte what it was (the comment and lower-case lines too)' ($otherBefore -ceq $otherAfter)
    Check 'CRLF kept: a CR for every LF, no bare LF' ((Count-Byte $after 13) -eq (Count-Byte $after 10))
    Check 'plain ASCII, no byte order mark' (-not ($after | Where-Object { $_ -gt 127 }) -and -not ($after.Length -ge 3 -and $after[0] -eq 0xEF))
    Check 'the file still ends with a newline' ($after[$after.Length - 1] -eq 10)

    $r = Run-Script @('-Mode', 'Get', '-ConfPath', $conf)
    Check 'Get now returns the saved path' ($r.Code -eq 0 -and $r.Out -match [regex]::Escape("SD-BACKUPDIR GET OK $target"))

    $second = Join-Path $work 'second'
    $r = Run-Script @('-Mode', 'Set', '-Path', ($second.Replace('\', '/')), '-ConfPath', $conf)
    Check 'a forward-slash path is accepted and stored with Windows separators' ($r.Code -eq 0 -and $r.Out -match [regex]::Escape("SD-BACKUPDIR SET OK $second"))
    $lines = @($ascii.GetString((Bytes $conf)) -split "`r`n" | Where-Object { $_ -clike 'BACKUPDIR=*' })
    Check 'a second Set REPLACES the line (still exactly one)' ($lines.Count -eq 1 -and $lines[0] -ceq "BACKUPDIR=$second")

    # Refusals leave the file exactly as it was.
    $h = Hex (Bytes $conf)
    $rel = Run-Script @('-Mode', 'Set', '-Path', 'relative\dir', '-ConfPath', $conf)
    Check 'a relative path is refused with ERROR, exit 1' ($rel.Code -eq 1 -and $rel.Out -match 'SD-BACKUPDIR ERROR' -and $rel.Out -notmatch 'SET OK')
    $fileAsDir = Join-Path $work 'iamafile'
    [System.IO.File]::WriteAllText($fileAsDir, 'x')
    $r = Run-Script @('-Mode', 'Set', '-Path', $fileAsDir, '-ConfPath', $conf)
    Check 'an existing FILE is refused, exit 1' ($r.Code -eq 1 -and $r.Out -match 'is a file')
    $r = Run-Script @('-Mode', 'Set', '-Path', ('Q:\no\such\drive\' + [guid]::NewGuid().ToString('N')), '-ConfPath', $conf)
    Check 'a directory that cannot be created is refused, exit 1' ($r.Code -eq 1 -and $r.Out -match 'SD-BACKUPDIR ERROR' -and $r.Out -notmatch 'SET OK')
    Check 'none of the refusals touched the file' ((Hex (Bytes $conf)) -ceq $h)

    $r = Run-Script @('-Mode', 'Get', '-ConfPath', (Join-Path $work 'absent.conf'))
    Check 'a missing sd.conf is refused by name, exit 1' ($r.Code -eq 1 -and $r.Out -match 'does not exist')

    # LF-only file, and one with no final newline.
    $lf = New-Conf 'lf.conf' "`n" $true
    $r = Run-Script @('-Mode', 'Set', '-Path', (Join-Path $work 'lfdir'), '-ConfPath', $lf)
    $lfb = Bytes $lf
    Check 'an LF-only file stays LF-only (no CR introduced)' ($r.Code -eq 0 -and (Count-Byte $lfb 13) -eq 0)
    $nf = New-Conf 'nofinal.conf' "`r`n" $false
    $r = Run-Script @('-Mode', 'Set', '-Path', (Join-Path $work 'nfdir'), '-ConfPath', $nf)
    $nfb = Bytes $nf
    Check 'a file with no final newline gets the line on its own row and still has none' ($r.Code -eq 0 -and $nfb[$nfb.Length - 1] -ne 10 -and $ascii.GetString($nfb).EndsWith('BACKUPDIR=' + (Join-Path $work 'nfdir')))
}
catch {
    Write-Host "test-backupdir-units: STOPPED - $($_.Exception.Message)"
    Write-Host $_.ScriptStackTrace
    if ($script:fail -gt 0) { Write-Host "test-backupdir-units: FAILED - $($script:fail) failed before it stopped."; exit 1 }
    exit 2
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}

# The count of Check calls that must run, so a check DELETED in a refactor fails loudly.
$minimum = 45
Write-Host ''
if ($script:pass -eq 0) { Write-Host 'test-backupdir-units: VOID - no check ran.'; exit 2 }
if (($script:pass + $script:fail) -lt $minimum) { Write-Host "test-backupdir-units: REFUSED - only $($script:pass + $script:fail) checks ran, expected at least $minimum."; exit 1 }
if ($script:fail -gt 0) { Write-Host "test-backupdir-units: FAILED - $($script:pass) passed, $($script:fail) failed."; exit 1 }
Write-Host "test-backupdir-units: PASSED - $($script:pass) of $($script:pass) checks passed."
exit 0
