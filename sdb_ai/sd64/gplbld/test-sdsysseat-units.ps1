<#
.SYNOPSIS
    Free-tier guard for gplbld/sdsys-seat.ps1, RELEASE_1.1 76's shared helper that
    runs sd.exe AS the OS SDSYS account.  No install, no elevation, no run token.

.DESCRIPTION
    The helper's real runner registers a scheduled task for another account, which
    needs elevation and a live SDSYS session - so it is reached only inside a
    ~20-minute elevated run.  Everything that DECIDES is reachable without either,
    through the helper's $script:SeatTestHooks seam, and that is what this drives:

      1. the session finder, on qwinsta tables (Disc counts; SDSYS2 and xSDSYS do not)
      2. the report validator, on every way a report can be wrong
      3. the whole entry point with a fake runner - each refusal, and that a
         refusal never reaches the runner
      4. THE GENERATED TASK SCRIPT, EXECUTED FOR REAL against a fake sd.exe, so its
         header, its echo of the input, its end marker, and "input deleted before sd
         runs" are measured rather than read
      5. the real runner's SHAPE, from the AST (interactive + highest, battery
         settings, unregistered in a finally, no password path)
      6. MUTANT CONTROLS: each tagged check is removed from a copy and the fixture
         that should be refused must then be ACCEPTED - proof the fixtures can tell
         a broken helper from a good one.  The live file is asserted unchanged.

    ***THE REFUSALS ARE THE POINT.***  A seat that ran as the wrong account, or
    without an elevated interactive token, produces output that looks exactly like
    SD refusing a command.  If the validator ever passed such a report the harness
    would report a product failure that is really a seat failure.

    Exit 0 all checks passed, 1 a check failed, 2 it could not measure.
#>

$ErrorActionPreference = 'Stop'
$gplbld = Split-Path -Parent $PSCommandPath
$modPath = Join-Path $gplbld 'sdsys-seat.ps1'

$script:pass = 0
$script:fail = 0
$script:calls = 0
$script:sections = 0
$script:sectionChecks = @{}
$script:current = ''

function Section([string]$n) {
    $script:sections++
    $script:current = $n
    $script:sectionChecks[$n] = 0
    Write-Output ''
    Write-Output ('== ' + $n)
}
function Check([string]$label, [bool]$ok, [string]$detail = '') {
    $script:calls++
    $script:sectionChecks[$script:current]++
    if ($ok) { $script:pass++; Write-Output ('  [PASS] ' + $label) }
    else     { $script:fail++; Write-Output ('  [FAIL] ' + $label + '   <- ' + $detail) }
}

Write-Output 'test-sdsysseat-units: gplbld/sdsys-seat.ps1'
Write-Output ('  module : ' + $modPath)
if (-not (Test-Path -LiteralPath $modPath)) { Write-Output 'REFUSED: the module is not there.'; exit 2 }
$liveHash = (Get-FileHash -LiteralPath $modPath -Algorithm SHA256).Hash
Write-Output ('  sha256 : ' + $liveHash)

. $modPath
$script:SeatTestHooks = $null
foreach ($fn in 'Get-SeatSession', 'ConvertFrom-SeatReport', 'Invoke-SdViaSeat', 'New-SeatScript', 'Invoke-SeatTask') {
    if (-not (Get-Command $fn -ErrorAction SilentlyContinue)) { Write-Output ("REFUSED: $fn is not defined after dot-sourcing."); exit 2 }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ('seatfx-' + [Guid]::NewGuid().ToString('N').Substring(0, 10))
$null = New-Item -ItemType Directory -Path $tmp -Force
Write-Output ('  temp   : ' + $tmp)

$ESC = [string][char]27
function Report([string]$id, [string]$admin, [string]$inter, [string]$body, [bool]$marker = $true) {
    $t = 'SEAT identity=' + $id + ' admin=' + $admin + ' interactive=' + $inter + "`n" + $body
    if ($marker) { $t += "`nENDOFSEAT" }
    return $t
}

try {

# ---------------------------------------------------------------------------
Section '1. the session finder'
$qw = @(
    ' SESSIONNAME       USERNAME                 ID  STATE   TYPE        DEVICE ',
    ' services                                    0  Disc                        ',
    '>console           Don                       2  Active                      ',
    '                   SDSYS                    14  Disc                        ',
    ' rdp-tcp                                 65536  Listen                      ')
$s = Get-SeatSession -Account 'SDSYS' -Lines $qw
Check 'a DISCONNECTED session is found (a disconnected session is a seat - measured)' ($s.Ok -and $s.Id -eq 14 -and $s.State -eq 'Disc') ("Ok=$($s.Ok) Id=$($s.Id) State=$($s.State)")
$s = Get-SeatSession -Account 'SDSYS' -Lines @('>console   SDSYS   3  Active')
Check 'an Active session is found' ($s.Ok -and $s.Id -eq 3 -and $s.State -eq 'Active') "Ok=$($s.Ok)"
$s = Get-SeatSession -Account 'SDSYS' -Lines @('   sdsys   7  Disc')
Check 'the name is matched case-insensitively' ($s.Ok -and $s.Id -eq 7) "Ok=$($s.Ok)"
$s = Get-SeatSession -Account 'SDSYS' -Lines @('   SDSYS2   7  Disc')
Check 'SDSYS2 is another account and is NOT matched' (-not $s.Ok) 'a longer name matched'
$s = Get-SeatSession -Account 'SDSYS' -Lines @('   xSDSYS   7  Disc')
Check 'xSDSYS is another account and is NOT matched' (-not $s.Ok) 'a name with a prefix matched'
$s = Get-SeatSession -Account 'SDSYS' -Lines @('   SDSYS   7  Conn')
Check 'a session that is only connecting is NOT live' (-not $s.Ok) 'Conn matched'
$s = Get-SeatSession -Account 'SDSYS' -Lines @('>console   Don   2  Active', ' services  0  Disc')
Check 'no SDSYS row: refused' (-not $s.Ok) 'matched nothing and said yes'
Check 'and the refusal names the LOGIN NAME - 78 was a wrong login name' ($s.Why -match 'login name SDSYS') $s.Why
Check 'and says a task with no session never runs' ($s.Why -match 'never runs') $s.Why
$s = Get-SeatSession -Account 'SDSYS' -Lines @('', '   ')
Check 'an EMPTY table is "could not be read", not "no session"' (-not $s.Ok -and $s.Why -match 'could not be read') $s.Why

# ---------------------------------------------------------------------------
Section '2. the report validator'
$good = Report 'ace\SDSYS' 'True' 'True' ("${ESC}[H${ESC}[J:WHO`n44 SDSYS")
$r = ConvertFrom-SeatReport -Raw $good -Account 'SDSYS'
Check 'a good report is accepted' ($r.Ok) $r.Why
Check 'the SEAT header and the end marker are not in the text' ($r.Text -notmatch 'SEAT identity' -and $r.Text -notmatch 'ENDOFSEAT') $r.Text
Check 'ANSI escapes are stripped from the text' ($r.Text -notmatch [regex]::Escape($ESC) -and $r.Text -match '44 SDSYS') $r.Text
$r = ConvertFrom-SeatReport -Raw (Report 'ace\Don' 'True' 'True' 'x') -Account 'SDSYS'
Check 'WRONG IDENTITY (ace\Don) is refused' (-not $r.Ok -and $r.Why -match 'not SDSYS') $r.Why
$r = ConvertFrom-SeatReport -Raw (Report 'ace\XSDSYS' 'True' 'True' 'x') -Account 'SDSYS'
Check 'an identity that merely ENDS in SDSYS is refused' (-not $r.Ok) 'ace\XSDSYS was accepted as SDSYS'
$r = ConvertFrom-SeatReport -Raw (Report 'ace\SDSYS' 'False' 'True' 'x') -Account 'SDSYS'
Check 'SDSYS without an elevated token is refused (route A: filtered)' (-not $r.Ok -and $r.Why -match 'not elevated') $r.Why
$r = ConvertFrom-SeatReport -Raw (Report 'ace\SDSYS' 'True' 'False' 'x') -Account 'SDSYS'
Check 'SDSYS elevated but not interactive is refused (route B: batch)' (-not $r.Ok -and $r.Why -match 'not interactive') $r.Why
$r = ConvertFrom-SeatReport -Raw (Report 'ace\SDSYS' 'True' 'True' 'partial output' $false) -Account 'SDSYS'
Check 'a report with no end marker is refused' (-not $r.Ok -and $r.Why -match 'end marker') $r.Why
$r = ConvertFrom-SeatReport -Raw '' -Account 'SDSYS'
Check 'an empty report is refused' (-not $r.Ok) 'empty accepted'
$r = ConvertFrom-SeatReport -Raw "44 SDSYS`nENDOFSEAT" -Account 'SDSYS'
Check 'a report with no SEAT header is refused (it did not come from the task script)' (-not $r.Ok -and $r.Why -match 'no SEAT header') $r.Why
$r = ConvertFrom-SeatReport -Raw (Report 'ace\SDSYS' 'True' 'True' ('x' * 5000)) -Account 'SDSYS' -MaxBytes 1000
Check 'an oversized report is refused' (-not $r.Ok -and $r.Why -match 'larger than') $r.Why
$r = ConvertFrom-SeatReport -Raw (Report 'ace\Bob' 'True' 'True' 'x') -Account 'Bob'
Check 'the account is a parameter: Bob is accepted as Bob' ($r.Ok) $r.Why

# ---------------------------------------------------------------------------
Section '3. the entry point, with a fake runner'
$wd = Join-Path $tmp 'work'
$script:runnerCalls = 0
$script:seenScript = ''
$script:seenIn = ''
$script:behave = $null
$hooks = @{
    Elevated = $true
    Qwinsta  = $qw
    SdExe    = 'C:/fake/sd.exe'
    Runner   = { param($Ps1, $OutFile, $Seconds, $Account)
                 $script:runnerCalls++
                 $script:seenScript = [IO.File]::ReadAllText($Ps1)
                 $inF = [IO.Path]::ChangeExtension($Ps1, '.in')
                 if (Test-Path -LiteralPath $inF) { $script:seenIn = [IO.File]::ReadAllText($inF) }
                 & $script:behave $OutFile
               }
}
$script:SeatTestHooks = $hooks
$script:behave = { param($o) [IO.File]::WriteAllText($o, (Report 'ace\SDSYS' 'True' 'True' "`n:WHO`n44 SDSYS")); return @{ Ok = $true; Detail = 'fake'; Why = '' } }

$r = Invoke-SdViaSeat -Commands @('WHO') -WorkDir $wd
Check 'a good seat run is Ok' ($r.Ok) $r.Why
Check 'and returns the text SD printed' ($r.Text -match '44 SDSYS') $r.Text
Check 'the runner was called once' ($script:runnerCalls -eq 1) "calls=$($script:runnerCalls)"
Check 'the input starts with a newline (the BOM sink Invoke-SD always had)' ($script:seenIn.StartsWith("`n")) ([string]$script:seenIn.Length)
Check 'the input carries the command and ends OFF' ($script:seenIn -match '(?m)^WHO$' -and $script:seenIn -match "OFF`n$") $script:seenIn
Check 'THERE IS NO "LOGTO" ANYWHERE - the seat IS the account' ($script:seenScript -notmatch 'LOGTO' -and $script:seenIn -notmatch 'LOGTO') 'a LOGTO reached the seat'
Check 'the work directory is clean afterwards' (@(Get-ChildItem -LiteralPath $wd -Force).Count -eq 0) ((Get-ChildItem -LiteralPath $wd -Force | ForEach-Object Name) -join ',')

$perr = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($script:seenScript, [ref]$null, [ref]$perr)
Check 'the generated task script PARSES (0 errors)' (@($perr).Count -eq 0) (($perr | ForEach-Object Message) -join '; ')
$iRemove = $script:seenScript.IndexOf('Remove-Item')
$iRun    = $script:seenScript.IndexOf('& $sd')
Check 'the input is DELETED BEFORE sd.exe runs (it can hold a test password)' ($iRemove -ge 0 -and $iRun -gt $iRemove) "Remove-Item at $iRemove, run at $iRun"
Check 'the report is written to .tmp and RENAMED (no half report is ever visible)' ($script:seenScript -match "'\.tmp'" -and $script:seenScript -match 'Move-Item') 'a report can be seen half-written'

$before = $script:runnerCalls
$script:SeatTestHooks = @{ Elevated = $false; Qwinsta = $qw; SdExe = 'x'; Runner = $hooks.Runner }
$r = Invoke-SdViaSeat -Commands @('WHO') -WorkDir $wd
Check 'a NON-ELEVATED caller is refused' (-not $r.Ok -and $r.Why -match 'not elevated') $r.Why
Check '... and the runner was never reached' ($script:runnerCalls -eq $before) 'the runner ran anyway'
$script:SeatTestHooks = @{ Elevated = $true; Qwinsta = @('>console  Don  2  Active'); SdExe = 'x'; Runner = $hooks.Runner }
$r = Invoke-SdViaSeat -Commands @('WHO') -WorkDir $wd
Check 'NO SDSYS SESSION is refused' (-not $r.Ok -and $r.Why -match 'no live session') $r.Why
Check '... and the runner was never reached' ($script:runnerCalls -eq $before) 'the runner ran anyway'
$script:SeatTestHooks = $hooks
$r = Invoke-SdViaSeat -Commands @() -WorkDir $wd
Check 'NO COMMANDS is refused rather than run' (-not $r.Ok -and $r.Why -match 'no commands') $r.Why
$r = Invoke-SdViaSeat -Commands @('', '  ') -WorkDir $wd
Check 'commands that are only blank are refused too' (-not $r.Ok -and $r.Why -match 'no commands') $r.Why
Check '... and the runner was still never reached' ($script:runnerCalls -eq $before) 'the runner ran on nothing'

$script:behave = { param($o) return @{ Ok = $false; Detail = 'task X, LastTaskResult 267011'; Why = 'the task wrote no report within 90s' } }
$r = Invoke-SdViaSeat -Commands @('WHO') -WorkDir $wd
Check 'a runner failure is refused, with its reason' (-not $r.Ok -and $r.Why -match 'no report' -and $r.Text -eq '') $r.Why
Check '... and the detail (task id, LastTaskResult) is carried' ($r.Detail -match '267011') $r.Detail
$script:behave = { param($o) [IO.File]::WriteAllText($o, (Report 'ace\Don' 'True' 'True' 'x')); return @{ Ok = $true; Detail = 'fake'; Why = '' } }
$r = Invoke-SdViaSeat -Commands @('WHO') -WorkDir $wd
Check 'a run as the WRONG ACCOUNT is refused end to end' (-not $r.Ok -and $r.Text -eq '') $r.Why
Check '... and the work directory is still clean (cleanup runs on refusal)' (@(Get-ChildItem -LiteralPath $wd -Force).Count -eq 0) ((Get-ChildItem -LiteralPath $wd -Force | ForEach-Object Name) -join ',')
$script:behave = { param($o) return @{ Ok = $true; Detail = 'fake'; Why = '' } }
$r = Invoke-SdViaSeat -Commands @('WHO') -WorkDir $wd
Check 'a runner that says Ok but wrote NO FILE is refused (the null case)' (-not $r.Ok) 'no file, and it was accepted'

# ---------------------------------------------------------------------------
Section '3b. the shared TERM handling and the throwing wrapper (the mechanical group)'
$e = @(Expand-SeatCommands @('CT VOC X'))
Check 'TERM 200,9999 is the FIRST line, then the command' ($e.Count -eq 2 -and $e[0] -eq 'TERM 200,9999' -and $e[1] -eq 'CT VOC X') ($e -join ' / ')
$e = @(Expand-SeatCommands @('LOGTO ZZ', 'CT A', '  logto QQ', 'CT B'))
$want = @('TERM 200,9999', 'LOGTO ZZ', 'TERM 200,9999', 'CT A', '  logto QQ', 'TERM 200,9999', 'CT B')
Check 'TERM is re-issued after EVERY LOGTO (LOGIN resets the geometry on each switch)' (($e -join '|') -ceq ($want -join '|')) ($e -join ' / ')
Check 'the match is case-insensitive and tolerates leading space (both LOGTOs were followed)' ($e.Count -eq 7) "count=$($e.Count)"
$e = @(Expand-SeatCommands @('LOGTOX', 'DELETE.ACCOUNT LOGTOFOO'))
Check 'a word that merely STARTS with LOGTO is not a LOGTO (no extra TERM)' ($e.Count -eq 3) ($e -join ' / ')
$e = @(Expand-SeatCommands @('WHO'))
Check 'a single command still comes back as an array of two, not unrolled to a string' ($e.Count -eq 2) "count=$($e.Count)"

# --- -Internal: the flag reaches the script, only when asked, and only THAT flag --
$plain = New-SeatScript -SdExe 'C:/fake/sd.exe' -InFile 'C:/fake/in' -OutFile 'C:/fake/out'
$intl  = New-SeatScript -SdExe 'C:/fake/sd.exe' -InFile 'C:/fake/in' -OutFile 'C:/fake/out' -Internal $true
Check 'the DEFAULT script runs plain sd (no -internal anywhere) - nothing already witnessed changes' ($plain -match '& \$sd 2>&1' -and $plain -notmatch 'internal') $plain
Check 'the -Internal script runs sd.exe -internal' ($intl -match "& \`$sd '-internal' 2>&1") $intl
$perrI = $null
$null = [System.Management.Automation.Language.Parser]::ParseInput($intl, [ref]$null, [ref]$perrI)
Check 'the -Internal script PARSES (0 errors)' (@($perrI).Count -eq 0) (($perrI | ForEach-Object Message) -join '; ')
Check 'the two scripts differ ONLY by that argument (no other line changed)' (($intl.Replace("'-internal' ", '')) -ceq $plain) 'another line differs'
Check 'no @@ token is left in either script (a missed replacement would run a literal "@@ARGS@@")' ($plain -notmatch '@@' -and $intl -notmatch '@@') 'a placeholder survived'

$script:SeatTestHooks = $hooks
$script:behave = { param($o) [IO.File]::WriteAllText($o, (Report 'ace\SDSYS' 'True' 'True' "`n:WHO`n44 SDSYS")); return @{ Ok = $true; Detail = 'fake'; Why = '' } }
$null = Invoke-SdSeatText -Commands @('WHO') -WorkDir $wd -Internal
Check 'Invoke-SdSeatText -Internal puts "-internal" in the script the runner was handed' ($script:seenScript -match "'-internal'") 'the switch did not reach New-SeatScript'
$null = Invoke-SdSeatText -Commands @('WHO') -WorkDir $wd
Check 'and WITHOUT the switch the script has none' ($script:seenScript -notmatch 'internal') 'a default call asked for -internal'
$t = Invoke-SdSeatText -Commands @('WHO') -WorkDir $wd
Check 'Invoke-SdSeatText returns the TEXT, a string, not a result object' (($t -is [string]) -and $t -match '44 SDSYS') ("type=" + $t.GetType().Name)
Check 'and the input it sent starts with the newline sink, then TERM, then the command, then OFF' ($script:seenIn -ceq "`nTERM 200,9999`nWHO`nOFF`n") ($script:seenIn -replace "`n", '~')
$threw = ''
$script:behave = { param($o) return @{ Ok = $false; Detail = 'task X, LastTaskResult 267011'; Why = 'the task wrote no report within 90s' } }
try { $null = Invoke-SdSeatText -Commands @('WHO') -WorkDir $wd } catch { $threw = $_.Exception.Message }
Check 'a seat that did not run THROWS rather than returning an empty string' ($threw -match 'did not run') "threw='$threw'"
Check '... and the throw carries the seat''s reason and its detail' ($threw -match 'no report' -and $threw -match '267011') $threw
$threw = ''
try { $null = Invoke-SdSeatText -Commands @() -WorkDir $wd } catch { $threw = $_.Exception.Message }
Check 'no commands THROWS (the binder does not answer for it)' ($threw -match 'no commands') "threw='$threw'"
$threw = ''
try { $null = Invoke-SdSeatText -Commands @('', '  ') -WorkDir $wd } catch { $threw = $_.Exception.Message }
Check 'only-blank commands THROW too' ($threw -match 'no commands') "threw='$threw'"
$script:SeatTestHooks = $null

# Assert-SdSeat ENDS THE CALLING SCRIPT with exit 2, so it can only be observed
# from OUTSIDE one: each case is a tiny script run in a child process, with the
# hooks set inside it.  The exit code and the text are the whole assertion.
function Invoke-AssertChild([string]$name, [string]$hooksLiteral, [string]$extra = '') {
    $p = Join-Path $tmp ('assert-' + $name + '.ps1')
    $body = @(
        ('. ''' + $modPath + ''''),
        ('$script:SeatTestHooks = ' + $hooksLiteral),
        ('Assert-SdSeat -Label ''verify-fixture'' -WorkDir ''' + (Join-Path $tmp ('awork-' + $name)) + '''' + $extra),
        'Write-Output ''REACHED-AFTER-ASSERT''')
    Set-Content -LiteralPath $p -Value $body -Encoding UTF8
    $o = & powershell -NoProfile -ExecutionPolicy Bypass -File $p 2>&1 | ForEach-Object { [string]$_ }
    return @{ Code = $LASTEXITCODE; Text = ($o -join "`n") }
}
$goodRun = '{ param($Ps1,$OutFile,$Seconds,$Account) $t = ''SEAT identity=ace\SDSYS admin=True interactive=True'' + "`n" + ''__BODY__'' + "`nENDOFSEAT"; [IO.File]::WriteAllText($OutFile, $t); return @{ Ok = $true; Detail = ''fake''; Why = '''' } }'
$hk = { param($body, $elevated = '$true', $qw = '''   SDSYS   9  Disc''')
        '@{ Elevated = ' + $elevated + '; Qwinsta = @(' + $qw + '); SdExe = ''x''; Runner = ' + ($goodRun.Replace('__BODY__', $body)) + ' }' }

$c = Invoke-AssertChild 'good' (& $hk '44 SDSYS')
Check 'Assert-SdSeat on a good seat CONTINUES (exit 0, the script reaches the next line)' ($c.Code -eq 0 -and $c.Text -match 'REACHED-AFTER-ASSERT') "exit=$($c.Code) $($c.Text)"
Check '... and prints SD''s raw WHO answer (the rule: show the output every time)' ($c.Text -match '44 SDSYS' -and $c.Text -match 'what SD said to WHO') $c.Text
$c = Invoke-AssertChild 'good-internal' (& $hk '44 SDSYS') ' -Internal'
Check 'Assert-SdSeat -Internal on a good seat continues and SAYS it went through sd -internal' ($c.Code -eq 0 -and $c.Text -match 'through sd -internal' -and $c.Text -match 'REACHED-AFTER-ASSERT') "exit=$($c.Code) $($c.Text)"
$c = Invoke-AssertChild 'good-plain' (& $hk '44 SDSYS')
Check 'and WITHOUT -Internal it does not claim to' ($c.Text -notmatch 'through sd -internal') $c.Text
$c = Invoke-AssertChild 'nosess' (& $hk '44 SDSYS' '$true' '''>console  Don  2  Active''')
Check 'Assert-SdSeat with NO SDSYS session ends the script with EXIT 2, not 1' ($c.Code -eq 2 -and $c.Text -notmatch 'REACHED-AFTER-ASSERT') "exit=$($c.Code)"
Check '... and names the precondition and the login name' ($c.Text -match 'seat did not run' -and $c.Text -match 'login name SDSYS') $c.Text
$c = Invoke-AssertChild 'notelev' (& $hk '44 SDSYS' '$false')
Check 'Assert-SdSeat from a non-elevated caller is exit 2' ($c.Code -eq 2 -and $c.Text -match 'not elevated') "exit=$($c.Code) $($c.Text)"
$c = Invoke-AssertChild 'refused' (& $hk 'SDSYS Account access is restricted to privileged users')
Check 'a seat that ran but whose SD REFUSED (the refusal wording) is exit 2 - anchored on success, not on the name' ($c.Code -eq 2 -and $c.Text -match 'did not answer WHO as SDSYS') "exit=$($c.Code) $($c.Text)"
$c = Invoke-AssertChild 'nowho' (& $hk 'something else entirely')
Check 'a WHO answer with no "<n> SDSYS" is exit 2' ($c.Code -eq 2) "exit=$($c.Code)"

# ---------------------------------------------------------------------------
Section '4. the generated script, EXECUTED, against a fake sd.exe'
$fakeSd = Join-Path $tmp 'fake-sd.cmd'
Set-Content -LiteralPath $fakeSd -Value @('@echo off', '@echo ARGS=%*', '@findstr "^"') -Encoding ASCII
$wd2 = Join-Path $tmp 'work2'
$script:afterRun = @{}
$script:SeatTestHooks = @{
    Elevated = $true; Qwinsta = $qw; SdExe = $fakeSd
    Runner   = { param($Ps1, $OutFile, $Seconds, $Account)
                 $inF = [IO.Path]::ChangeExtension($Ps1, '.in')
                 $script:afterRun.InBefore = (Test-Path -LiteralPath $inF)
                 $null = & powershell -NoProfile -ExecutionPolicy Bypass -File $Ps1
                 $script:afterRun.InAfter  = (Test-Path -LiteralPath $inF)
                 $script:afterRun.TmpAfter = (Test-Path -LiteralPath ($OutFile + '.tmp'))
                 $script:afterRun.Raw = $(if (Test-Path -LiteralPath $OutFile) { [IO.File]::ReadAllText($OutFile) } else { '' })
                 return @{ Ok = (Test-Path -LiteralPath $OutFile); Detail = 'real script'; Why = 'the script wrote no report' }
               }
}
$me = $env:USERNAME
$r = Invoke-SdViaSeat -Commands @('WHO', 'LIST ACCOUNTS NO.PAGE') -Account $me -WorkDir $wd2 -TimeoutSec 60
$raw = [string]$script:afterRun.Raw
Check 'the real script wrote a report at all' ($raw.Length -gt 0) 'no output file'
Check 'the input file existed when the runner started, and the SCRIPT deleted it' ($script:afterRun.InBefore -and -not $script:afterRun.InAfter) ("before=$($script:afterRun.InBefore) after=$($script:afterRun.InAfter)")
Check 'no .tmp is left behind (the rename happened)' (-not $script:afterRun.TmpAfter) 'a .tmp remains'
$hdrOk = [bool]($raw -match '^SEAT identity=(\S+) admin=(True|False) interactive=(True|False)')
Check 'the header has the identity and both token facts' $hdrOk (($raw -split "`n")[0])
$hid = $(if ($hdrOk) { $Matches[1] } else { '' })
Check 'the identity is the account the script ACTUALLY ran as' ($hid -match ('(?i)\\' + [regex]::Escape($me) + '$')) "header identity=$hid, USERNAME=$me"
Check 'the fake sd received the piped input: the commands and OFF are echoed back' ($raw -match '(?m)^WHO\s*$' -and $raw -match 'LIST ACCOUNTS NO\.PAGE' -and $raw -match '(?m)^OFF\s*$') $raw
Check 'the end marker is the last thing in the report' ($raw -match 'ENDOFSEAT\s*$') $raw
$admin = [bool]($hdrOk -and $raw -match 'admin=True'); $inter = [bool]($hdrOk -and $raw -match 'interactive=True')
$expectOk = ($admin -and $inter)
Check ("the verdict AGREES with the token the script really had (admin=$admin interactive=$inter)") ($r.Ok -eq $expectOk) ("Ok=$($r.Ok) expected=$expectOk why=$($r.Why)")
Check 'and the work directory is clean afterwards' (@(Get-ChildItem -LiteralPath $wd2 -Force).Count -eq 0) ((Get-ChildItem -LiteralPath $wd2 -Force | ForEach-Object Name) -join ',')
if ($r.Ok) { Check 'an accepted run returns the echoed text without header or marker' ($r.Text -notmatch 'SEAT identity|ENDOFSEAT' -and $r.Text -match 'WHO') $r.Text }
else       { Check 'a refused run returns NO text' ($r.Text -eq '') $r.Text }
Check 'the default run passed sd NO arguments (the fake echoes %*)' ($raw -match '(?m)^ARGS=\s*$') $raw
$r2 = Invoke-SdViaSeat -Commands @('WHO') -Account $me -WorkDir $wd2 -TimeoutSec 60 -Internal
$raw2 = [string]$script:afterRun.Raw
Check 'the -Internal run REALLY handed "-internal" to the program (observed, not read)' ($raw2 -match '(?m)^ARGS=-internal\s*$') $raw2
# [ \t]+ AND NOT \s+: in multiline mode \s matches the NEWLINE after "ARGS=-internal",
# so \S then matched the first character of the NEXT line and this failed on a
# perfectly clean run - a check that could not pass.  Same-line whitespace only.
Check 'and it is the only argument (no smuggled extras)' (-not ($raw2 -match '(?m)^ARGS=-internal[ \t]+\S')) $raw2

# --- A HANG STILL SAYS WHERE IT STOPPED ---------------------------------------
# 20 Sep 2026: verify-accountrules sat at a password prompt for 180 s and the seat threw with
# NO text, so the cause had to be found by reading createa.  The generated script now appends
# each line to <report>.part as sd prints it, and the caller quotes the tail when it gives up.
# Observed here on the real generated script, against a fake sd that prints one line and hangs.
$wd3 = Join-Path $tmp 'work3'
$null = New-Item -ItemType Directory -Path $wd3 -Force
$hangSd = Join-Path $tmp 'hang-sd.cmd'
Set-Content -LiteralPath $hangSd -Value @('@echo off', '@echo FIRSTLINE-BEFORE-THE-HANG', '@ping -n 14 127.0.0.1 >nul') -Encoding ASCII
$inH = Join-Path $wd3 'h.in'; $ps1H = Join-Path $wd3 'h.ps1'; $outH = Join-Path $wd3 'h.out'
[IO.File]::WriteAllText($inH, "`nWHO`nOFF`n")
Set-Content -LiteralPath $ps1H -Encoding UTF8 -Value (New-SeatScript -SdExe $hangSd -InFile $inH -OutFile $outH)
$pp = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $ps1H) -PassThru -WindowStyle Hidden
$partText = ''
$until = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $until) {
    if (Test-Path -LiteralPath ($outH + '.part')) {
        try { $partText = [IO.File]::ReadAllText($outH + '.part') } catch { $partText = '' }
        if ($partText -match 'FIRSTLINE-BEFORE-THE-HANG') { break }
    }
    Start-Sleep -Milliseconds 300
}
$reportWhileHung = Test-Path -LiteralPath $outH
$null = & taskkill.exe /PID $pp.Id /T /F 2>&1
Start-Sleep -Milliseconds 500
Check 'WHILE sd is still running, the .part file holds the header and the line sd already printed' (($partText -match '^SEAT identity=') -and ($partText -match 'FIRSTLINE-BEFORE-THE-HANG')) $partText
Check 'and the final report does NOT exist yet (the hang was real, not a finished run)' (-not $reportWhileHung) 'the report appeared while sd was still hanging'

$script:SeatTestHooks = @{
    Elevated = $true; Qwinsta = $qw; SdExe = $fakeSd
    Runner   = { param($Ps1, $OutFile, $Seconds, $Account)
                 [IO.File]::WriteAllText($OutFile + '.part', "SEAT identity=x`nCreating account`nPassword: `n")
                 return @{ Ok = $false; Detail = 'fake hang'; Why = 'the task wrote no report within 3s' } }
}
$wd4 = Join-Path $tmp 'work4'
$rh = Invoke-SdViaSeat -Commands @('CREATE.ACCOUNT USER zz') -Account $me -WorkDir $wd4 -TimeoutSec 3
Check 'a timed-out call is still a refusal (Ok is false, no text)' ((-not $rh.Ok) -and $rh.Text -eq '') "Ok=$($rh.Ok)"
Check 'its Why quotes what SD had printed when it was stopped, ending at the prompt' (($rh.Why -match 'WHAT SD HAD PRINTED WHEN IT WAS STOPPED') -and ($rh.Why -match 'Password:')) $rh.Why
Check 'and it still carries the original timeout reason' ($rh.Why -match 'wrote no report within 3s') $rh.Why
Check 'the .part file is removed afterwards (work directory clean)' (@(Get-ChildItem -LiteralPath $wd4 -Force -ErrorAction SilentlyContinue).Count -eq 0) ((Get-ChildItem -LiteralPath $wd4 -Force | ForEach-Object Name) -join ',')
$script:SeatTestHooks = $null

# ---------------------------------------------------------------------------
Section '5. the real runner: shape, from the AST'
$tokens = $null; $perr2 = $null
$modAst = [System.Management.Automation.Language.Parser]::ParseFile($modPath, [ref]$tokens, [ref]$perr2)
$fnAst = $modAst.FindAll({ param($x) $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $x.Name -eq 'Invoke-SeatTask' }, $true) | Select-Object -First 1
Check 'Invoke-SeatTask was found in the module' ($null -ne $fnAst) 'not found'
$body = $(if ($null -ne $fnAst) { $fnAst.Body.Extent.Text } else { '' })
Check 'it registers an INTERACTIVE logon type' ($body -match '-LogonType Interactive') 'a batch task is elevated and refused (route B)'
Check 'it asks for RunLevel Highest' ($body -match '-RunLevel Highest') 'the token would be filtered'
Check 'it allows start on battery (a default-off task silently never runs)' ($body -match '-AllowStartIfOnBatteries' -and $body -match '-DontStopIfGoingOnBatteries') 'a laptop on battery would hang until timeout'
Check 'it has an execution time limit' ($body -match '-ExecutionTimeLimit') 'a wedged sd.exe would run for 72 hours'
$tryAst = $fnAst.Body.FindAll({ param($x) $x -is [System.Management.Automation.Language.TryStatementAst] }, $true) | Select-Object -First 1
$fin = $(if ($null -ne $tryAst -and $null -ne $tryAst.Finally) { $tryAst.Finally.Extent.Text } else { '' })
Check 'the task is UNREGISTERED in a finally (no task outlives the run)' ($fin -match 'Unregister-ScheduledTask') 'the unregister is not in a finally'
Check 'it has NO password path at all (no -Password, no credential)' ($body -notmatch '(?i)-Password|Credential|SecureString') 'a credential path exists'
Check 'it stops a task that never wrote a report' ($body -match 'Stop-ScheduledTask') 'a wedged task is left running'

# ---------------------------------------------------------------------------
Section '6. MUTANT CONTROLS - each check is removed from a COPY and its fixture must then be accepted'
$modText = [IO.File]::ReadAllText($modPath)
$mutants = @(
    @{ Tag = 'MUT-ID';          Raw = (Report 'ace\Don' 'True' 'True' 'x');     What = 'the identity check' },
    @{ Tag = 'MUT-ADMIN';       Raw = (Report 'ace\SDSYS' 'False' 'True' 'x');  What = 'the elevated check' },
    @{ Tag = 'MUT-INTERACTIVE'; Raw = (Report 'ace\SDSYS' 'True' 'False' 'x');  What = 'the interactive check' },
    @{ Tag = 'MUT-MARKER';      Raw = (Report 'ace\SDSYS' 'True' 'True' 'x' $false); What = 'the end-marker check' })
foreach ($m in $mutants) {
    $tagged = @([regex]::Matches($modText, '(?m)^.*#' + [regex]::Escape($m.Tag) + '\s*$'))
    Check ("{0} appears on exactly one line of the live module" -f $m.Tag) ($tagged.Count -eq 1) ("found $($tagged.Count)")
    if ($tagged.Count -ne 1) { continue }
    $mutText = $modText.Replace($tagged[0].Value, '')
    Check ("the mutant really differs from the live file ({0} removed)" -f $m.What) ($mutText -ne $modText) 'the mutation changed nothing'
    $live = ConvertFrom-SeatReport -Raw $m.Raw -Account 'SDSYS'
    $sb = [scriptblock]::Create($mutText)
    $mut = & { . $sb; ConvertFrom-SeatReport -Raw $m.Raw -Account 'SDSYS' }
    Check ("LIVE refuses the fixture for {0}" -f $m.What) (-not $live.Ok) 'the live file accepted it'
    Check ("the MUTANT (no {0}) ACCEPTS it - the fixture can tell them apart" -f $m.What) ($mut.Ok) 'the mutant refused too: this fixture proves nothing'
}
# A fifth mutant, of a different KIND: not a validator refusal but a line that
# must be present for the output to be right.  With the after-LOGTO TERM removed,
# a LOGTO's geometry reset is never undone and a long LIST after it paginates on
# a pipe that cannot answer - the hang this handling exists to prevent.
$tag = 'MUT-TERMAFTER'
$tagged = @([regex]::Matches($modText, '(?m)^.*#' + [regex]::Escape($tag) + '\s*$'))
Check ("{0} appears on exactly one line of the live module" -f $tag) ($tagged.Count -eq 1) ("found $($tagged.Count)")
if ($tagged.Count -eq 1) {
    $mutText = $modText.Replace($tagged[0].Value, '')
    Check 'the mutant really differs from the live file (the after-LOGTO TERM removed)' ($mutText -ne $modText) 'the mutation changed nothing'
    $liveN = @(Expand-SeatCommands @('LOGTO ZZ', 'CT A')).Count
    $sb = [scriptblock]::Create($mutText)
    $mutN = & { . $sb; @(Expand-SeatCommands @('LOGTO ZZ', 'CT A')).Count }
    Check 'LIVE re-issues TERM after the LOGTO (4 lines)' ($liveN -eq 4) "live=$liveN"
    Check 'the MUTANT does not (3 lines) - the fixture can tell them apart' ($mutN -eq 3) "mutant=$mutN"
}
$after = (Get-FileHash -LiteralPath $modPath -Algorithm SHA256).Hash
Check 'the live module is byte-identical after the mutants (SHA-256)' ($after -eq $liveHash) "before=$liveHash after=$after"

# ---------------------------------------------------------------------------
Section '7. every script that touches the seat loads it BEFORE it calls it (AST)'
# ***WHY THIS EXISTS - 20 Sep 2026, THE OWNER'S FIRST ELEVATED RUN OF THE TEN.***
# verify-createfilecase died with "Assert-SdSeat is not recognized": its Assert-SdSeat
# call sat at script scope ELEVEN LINES ABOVE the dot-source that defines it.  The
# unelevated dry-run I did first could not see it, because that script refuses at its
# elevation gate BEFORE reaching either line - the dry-run proves the load and the gate
# and nothing behind them, which is the sentence I had written about it the day before.
# Nothing in the tree checked the order, and it is one statement in a file that is only
# otherwise reached inside an elevated run.  A call inside a FUNCTION is not the risk (the
# function runs later, after the dot-source), so only script-scope calls are ordered.
$seatFns = @('Assert-SdSeat', 'Invoke-SdSeatText', 'Invoke-SdViaSeat', 'Expand-SeatCommands')
function Get-SeatOrderProblem([string]$Path) {
    # Returns @{ Touches = bool; Problem = string; DotLine = int; FirstTopLine = int }.
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) { return @{ Touches = $true; Problem = 'does not parse'; DotLine = -1; FirstTopLine = -1 } }
    $cmds = @($ast.FindAll({ param($x) $x -is [System.Management.Automation.Language.CommandAst] }, $true))
    $dots = @($cmds | Where-Object { $_.InvocationOperator -eq 'Dot' -and $_.Extent.Text -match 'sdsys-seat' })
    $uses = @($cmds | Where-Object { $seatFns -contains $_.GetCommandName() })
    if ($dots.Count -eq 0 -and $uses.Count -eq 0) { return @{ Touches = $false; Problem = ''; DotLine = -1; FirstTopLine = -1 } }
    $top = @($uses | Where-Object {
        $p = $_.Parent; $inFn = $false
        while ($null -ne $p) { if ($p -is [System.Management.Automation.Language.FunctionDefinitionAst]) { $inFn = $true; break }; $p = $p.Parent }
        -not $inFn })
    # Lines are read with ForEach-Object and a missing number is a FAILURE: "Measure-Object { }" is not
    # valid in 5.1, returns $null, and a verdict that reads $null as "in order" passes on nothing.
    $dl = -1; $fl = -1
    if ($dots.Count) { $dl = [int](($dots | ForEach-Object { $_.Extent.StartLineNumber } | Measure-Object -Minimum).Minimum) }
    if ($top.Count)  { $fl = [int](($top  | ForEach-Object { $_.Extent.StartLineNumber } | Measure-Object -Minimum).Minimum) }
    $why = ''
    if ($dots.Count -gt 0 -and $dl -lt 1) { $why = 'a dot-source was found but its line was not read' }
    elseif ($top.Count -gt 0 -and $fl -lt 1) { $why = 'a script-scope seat call was found but its line was not read' }
    elseif ($uses.Count -gt 0 -and $dots.Count -eq 0) { $why = 'calls a seat function and never dot-sources the helper' }
    elseif ($fl -ge 0 -and $dl -gt $fl) { $why = "the script-scope seat call at line $fl precedes the dot-source at line $dl" }
    return @{ Touches = $true; Problem = $why; DotLine = $dl; FirstTopLine = $fl }
}

$fxOk  = Join-Path $tmp 'order-ok.ps1'
$fxBad = Join-Path $tmp 'order-before.ps1'
$fxNo  = Join-Path $tmp 'order-nodot.ps1'
$fxFn  = Join-Path $tmp 'order-infunction.ps1'
Set-Content -LiteralPath $fxOk  -Encoding UTF8 -Value @('. (Join-Path $PSScriptRoot ''sdsys-seat.ps1'')', 'Assert-SdSeat -Label ''x''')
Set-Content -LiteralPath $fxBad -Encoding UTF8 -Value @('Assert-SdSeat -Label ''x''', '. (Join-Path $PSScriptRoot ''sdsys-seat.ps1'')')
Set-Content -LiteralPath $fxNo  -Encoding UTF8 -Value @('Assert-SdSeat -Label ''x''')
# A call inside a function that is only INVOKED later is fine: the function body runs after the dot-source.
Set-Content -LiteralPath $fxFn  -Encoding UTF8 -Value @('function Go { Invoke-SdSeatText -Commands @(''WHO'') }', '. (Join-Path $PSScriptRoot ''sdsys-seat.ps1'')', 'Go')
$rOk = Get-SeatOrderProblem $fxOk; $rBad = Get-SeatOrderProblem $fxBad; $rNo = Get-SeatOrderProblem $fxNo; $rFn = Get-SeatOrderProblem $fxFn
Check 'CONTROL: a script that loads the helper first is in order, with both lines read' (($rOk.Problem -eq '') -and $rOk.DotLine -eq 1 -and $rOk.FirstTopLine -eq 2) ("problem='$($rOk.Problem)' dot=$($rOk.DotLine) call=$($rOk.FirstTopLine)")
Check 'MUTANT: a script-scope Assert-SdSeat ABOVE the dot-source is flagged, naming both lines' (($rBad.Problem -match 'precedes the dot-source') -and $rBad.FirstTopLine -eq 1 -and $rBad.DotLine -eq 2) ("problem='$($rBad.Problem)'")
Check 'MUTANT: a seat call with no dot-source at all is flagged' ($rNo.Problem -match 'never dot-sources') ("problem='$($rNo.Problem)'")
Check 'a call inside a function defined before the dot-source is NOT flagged (it runs after)' ($rFn.Problem -eq '') ("problem='$($rFn.Problem)'")

$touching = 0; $problems = @()
foreach ($f in @(Get-ChildItem -LiteralPath $gplbld -Filter '*.ps1' | Where-Object { $_.Name -notmatch '^(sdsys-seat|test-)' })) {
    $r = Get-SeatOrderProblem $f.FullName
    if (-not $r.Touches) { continue }
    $touching++
    if ($r.Problem -ne '') { $problems += ($f.Name + ': ' + $r.Problem) }
}
# THE NULL CASE, refused out loud: a scan that found no script using the seat measured nothing.
Check ('the scan found the scripts that use the seat ({0}; more than 15)' -f $touching) ($touching -gt 15) "found $touching - the walk or the seat function names are wrong"
Check 'EVERY script that uses the seat loads it before its first script-scope call' ($problems.Count -eq 0) ($problems -join ' | ')

# ---------------------------------------------------------------------------
Section '8. a step that THROWS cannot end a suite run (both runners guard the step call)'
# ***MEASURED 20 Sep 2026***: the steps run in the runner's own process and most set
# $ErrorActionPreference = 'Stop', so a terminating error inside one propagated out of
# "& $path @splat" and ended the WHOLE suite - verify-createfilecase's "Assert-SdSeat is not
# recognized" did exactly that, and the steps after it never ran.  A one-loop reproduction gave
# "unguarded: LOOP ENDED BY ..." against "guarded: thrower.ps1=1 ; fine.ps1=0".  The seat adds a
# NEW way to throw (Invoke-SdSeatText throws when the seat does not run), so this matters more
# now than before.  Only a try/catch that sits INSIDE the step loop counts: VerifyInstall1 wraps
# the whole loop in a try/finally already, and that is exactly the shape that lets the throw
# end the run.
function Get-StepGuard([string]$Path) {
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) { return @{ Calls = 0; Unguarded = @('does not parse') } }
    $calls = @($ast.FindAll({ param($x)
        $x -is [System.Management.Automation.Language.CommandAst] -and
        $x.InvocationOperator -eq 'Ampersand' -and
        $x.CommandElements.Count -ge 2 -and
        $x.CommandElements[0].Extent.Text -eq '$path' -and
        $x.Extent.Text -match '@splat' }, $true))
    $bad = @()
    foreach ($c in $calls) {
        $p = $c.Parent; $try = $null; $loop = $null
        while ($null -ne $p) {
            if ($null -eq $try -and $p -is [System.Management.Automation.Language.TryStatementAst]) { $try = $p }
            if ($null -eq $loop -and $p -is [System.Management.Automation.Language.ForEachStatementAst]) { $loop = $p }
            $p = $p.Parent
        }
        $ok = ($null -ne $try -and $null -ne $loop -and $try.CatchClauses.Count -gt 0 -and
               $try.Extent.StartOffset -ge $loop.Extent.StartOffset)
        if (-not $ok) { $bad += ('line ' + $c.Extent.StartLineNumber) }
    }
    return @{ Calls = $calls.Count; Unguarded = $bad }
}
$gOk  = Join-Path $tmp 'runner-guarded.ps1'
$gBad = Join-Path $tmp 'runner-unguarded.ps1'
$gFin = Join-Path $tmp 'runner-tryfinally-only.ps1'
Set-Content -LiteralPath $gOk  -Encoding UTF8 -Value @('foreach ($s in $steps) {', '  $path = $s.Name; $splat = @{}', '  try { & $path @splat; $code = $LASTEXITCODE } catch { $code = 1 }', '}')
Set-Content -LiteralPath $gBad -Encoding UTF8 -Value @('foreach ($s in $steps) {', '  $path = $s.Name; $splat = @{}', '  & $path @splat', '  $code = $LASTEXITCODE', '}')
Set-Content -LiteralPath $gFin -Encoding UTF8 -Value @('try {', 'foreach ($s in $steps) {', '  $path = $s.Name; $splat = @{}', '  & $path @splat', '}', '} finally { }')
$sOk = Get-StepGuard $gOk; $sBad = Get-StepGuard $gBad; $sFin = Get-StepGuard $gFin
Check 'CONTROL: a step call inside a try/catch inside the loop is guarded (and was found)' (($sOk.Calls -eq 1) -and ($sOk.Unguarded.Count -eq 0)) "calls=$($sOk.Calls) unguarded=$($sOk.Unguarded -join ',')"
Check 'MUTANT: an unguarded step call is flagged' (($sBad.Calls -eq 1) -and ($sBad.Unguarded.Count -eq 1)) "calls=$($sBad.Calls) unguarded=$($sBad.Unguarded -join ',')"
Check 'MUTANT: a try/FINALLY around the whole loop (VerifyInstall1''s old shape) does not count as a guard' (($sFin.Calls -eq 1) -and ($sFin.Unguarded.Count -eq 1)) "calls=$($sFin.Calls) unguarded=$($sFin.Unguarded -join ',')"
foreach ($rn in 'VerifyInstall1.ps1', 'VerifyInstall2.ps1') {
    $g = Get-StepGuard (Join-Path $gplbld $rn)
    Check ("$rn calls its steps (the scan found $($g.Calls) call site(s), not zero)") ($g.Calls -ge 1) 'the walk found no "& $path @splat" - the shape changed and this guard is looking at nothing'
    Check ("$rn guards every step call with a try/catch inside the loop") ($g.Unguarded.Count -eq 0) ($g.Unguarded -join ',')
}

} finally {
    $script:SeatTestHooks = $null
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

# ---------------------------------------------------------------------------
Write-Output ''
$empty = @($script:sectionChecks.Keys | Where-Object { $script:sectionChecks[$_] -eq 0 })
if ($empty.Count -gt 0) { $script:fail++; Write-Output ('  [FAIL] a section ran no checks: ' + ($empty -join '; ')) }
if ($script:pass + $script:fail -lt $script:calls) {
    Write-Output ('REFUSED: the counters do not add up ({0} + {1} < {2} checks).' -f $script:pass, $script:fail, $script:calls)
    exit 2
}
Write-Output ('test-sdsysseat-units: {0} passed, {1} failed.' -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
