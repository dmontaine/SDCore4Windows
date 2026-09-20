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
Section '4. the generated script, EXECUTED, against a fake sd.exe'
$fakeSd = Join-Path $tmp 'fake-sd.cmd'
Set-Content -LiteralPath $fakeSd -Value @('@echo off', '@findstr "^"') -Encoding ASCII
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
$after = (Get-FileHash -LiteralPath $modPath -Algorithm SHA256).Hash
Check 'the live module is byte-identical after the mutants (SHA-256)' ($after -eq $liveHash) "before=$liveHash after=$after"

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
