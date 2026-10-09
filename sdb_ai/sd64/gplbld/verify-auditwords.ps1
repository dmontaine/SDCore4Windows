# verify-auditwords.ps1 - is every word the audit trail wrote since this install lower case,
# and which of this release's audit events has the run actually produced?
#
#   powershell -ExecutionPolicy Bypass -File verify-auditwords.ps1 [-Since 'yyyy-MM-dd HH:mm:ss']
#
# ***ELEVATED POWERSHELL.***  C:\ProgramData\SD\sdsys\audit is locked to SYSTEM and Administrators
# (secure-audit.ps1), so an ordinary token is refused.  It reads and changes nothing.
#
# Exit 0 every line since -Since has no upper-case letter before its first "=", 1 at least one has,
# 2 the test could not be run (not elevated, no file, an empty file, a file in a shape this does not
# recognise).
#
# WHY IT EXISTS.  Owner's rule, 7 Oct 2026 via Linux T1830: every word an audit line writes before
# its first "=" is lower case, event names included.  The programs were changed on 8 Oct and the
# only witness was a one-off probe (probe-auditlower.ps1) plus a hand read of a five-line file; the
# lines the SUITE writes - login refused, api refused, account refused branch=N, elevation released,
# api handover failed, remote.api, remote.ssh - were never read, and nothing stops a later edit
# putting a capital back.  test-auditwords-units.py guards the SOURCE; this reads what an install
# WROTE.  It belongs LAST in VerifyInstall2, after the steps that make those lines.
#
# WHAT IS DECISIVE: (1) the file parsed to at least one audit line since -Since (the null case is
# refused, exit 2, never a pass), (2) the control - at least one "login" event - is present, so a
# reader that recognises nothing cannot pass, (3) ZERO lines carry an upper-case letter before the
# first "=" (checked CASE-SENSITIVELY: Regex -cmatch).  The table of events this release writes is
# printed with a count each and "NOT SEEN" where nothing in this run wrote one; that is information,
# not a failure, because a partial run (-Only) does not make every line.
#
# -Since defaults to the creation time of C:\ProgramData\SD, which assert-current.ps1 also treats as
# the install moment.  After a true UPGRADE the data tree is older than the install and still holds
# the previous build's lines, so pass -Since with the upgrade time.  The default is printed.

param(
    [string] $Since = ''
)

$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------- the pure part
# Kept as functions that print nothing and return a value, so test-auditwords-reader-units.ps1 can lift
# them out of this file by AST and drive them with synthetic text.

# One audit line is "<date> <time> user=<u> uid=<n> pid=<n> <event text>"; the event text is what the
# program wrote.  Returns one object per PARSED line at or after $SinceTime, plus a count of lines that
# did not parse, in the .Unparsed property of the FIRST element's sibling summary (see the caller).
function Get-AuditEvents([string] $Text, [datetime] $SinceTime) {
    $out = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrEmpty($Text)) { return @() }
    $n = 0
    foreach ($raw in ($Text -split "`r?`n")) {
        $n++
        if ($raw -notmatch '\S') { continue }
        if ($raw -match '^(\S+ \S+) user=(\S+) uid=(\d+) pid=(\d+) (.*)$') {
            $stamp = $Matches[1]; $ev = $Matches[5]
            $when = [datetime]::MinValue
            $okTime = [datetime]::TryParseExact($stamp, 'yyyy-MM-dd HH:mm:ss',
                          [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$when)
            if ($okTime -and $when -lt $SinceTime) { continue }
            $eq = $ev.IndexOf('=')
            $head = $(if ($eq -ge 0) { $ev.Substring(0, $eq) } else { $ev })
            $tok = @($head.Trim() -split '\s+' | Where-Object { $_ -ne '' })
            # the word before the "=" is a KEY (account, user, request ...), not part of the event name
            $word = $(if ($eq -ge 0 -and $tok.Count -gt 1) { ($tok[0..($tok.Count - 2)] -join ' ') } else { ($tok -join ' ') })
            $null = $out.Add([pscustomobject]@{ Line = $n; Stamp = $stamp; Text = $ev; Head = $head.Trim(); Word = $word; Parsed = $true })
        } else {
            $null = $out.Add([pscustomobject]@{ Line = $n; Stamp = ''; Text = $raw.Trim(); Head = ''; Word = ''; Parsed = $false })
        }
    }
    return @($out)
}

# The lines whose event text has an upper-case letter before its first "=" - CASE-SENSITIVE.
function Get-UpperHeadLines($Events) {
    return @(@($Events) | Where-Object { $_.Parsed -and ($_.Head -cmatch '[A-Z]') })
}

# How many parsed events match a regex on the whole head (case-sensitive: a pattern is written lower case).
function Measure-EventWord($Events, [string] $HeadPattern) {
    return @(@($Events) | Where-Object { $_.Parsed -and ($_.Head -cmatch $HeadPattern) }).Count
}

# The events this release writes, as head patterns (lower case).  Source: the K$AUDIT / audit.text
# literals in gpl.bp, op_kernel.c's "group.member could not tell", and the 8 Oct probe.
$script:ExpectedEvents = @(
    @{ Label = 'login';                         Rx = '^login account$' },
    @{ Label = 'login refused';                 Rx = '^login refused' },
    @{ Label = 'logto refused';                 Rx = '^logto refused' },
    @{ Label = 'elevation granted';             Rx = '^elevation granted' },
    @{ Label = 'elevation released';            Rx = '^elevation released' },
    @{ Label = 'internal session admitted';     Rx = '^internal session admitted' },
    @{ Label = 'api refused';                   Rx = '^api refused' },
    @{ Label = 'api handover failed';           Rx = '^api handover failed' },
    @{ Label = 'account refused (branch=N)';    Rx = '^account refused' },
    @{ Label = 'create.account';                Rx = '^create\.account' },
    @{ Label = 'delete.account';                Rx = '^delete\.account' },
    @{ Label = 'restore.account';               Rx = '^restore\.account' },
    @{ Label = 'modify.account add|delete';     Rx = '^modify\.account (add|delete)' },
    @{ Label = 'modify.account suspend';        Rx = '^modify\.account suspend' },
    @{ Label = 'modify.account unsuspended';    Rx = '^modify\.account unsuspended' },
    @{ Label = 'modify.account route';          Rx = '^modify\.account route' },
    @{ Label = 'modify.account os.users';       Rx = '^modify\.account os\.users' },
    @{ Label = 'remote.api';                    Rx = '^remote\.api' },
    @{ Label = 'remote.ssh';                    Rx = '^remote\.ssh' },
    @{ Label = 'group.member could not tell';   Rx = '^group\.member' }
)

# --------------------------------------------------------------------------- the run
# Dot-sourced for its functions by the unit test: stop here when told to.
if ($env:SD_VERIFYAUDITWORDS_LOAD_ONLY -eq '1') { return }

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-auditwords-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ('transcript: ' + $logPath)

$results = New-Object System.Collections.ArrayList
$failed  = $false
function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got; Result = $(if ($pass) { 'PASS' } else { 'FAIL' }) })
    Write-Output ('  [{0}] {1}: expected {2}, got {3}' -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-auditwords: refusing - see above'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

if (-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
        ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-auditwords: this needs an ELEVATED PowerShell - the audit file is locked to SYSTEM and Administrators.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$dataDir = Join-Path $env:ProgramData 'SD'
$audit   = Join-Path (Join-Path $dataDir 'sdsys') 'audit'
if (-not (Test-Path -LiteralPath $audit)) {
    Write-Output ('verify-auditwords: REFUSED - no audit file at ' + $audit)
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$sinceTime = [datetime]::MinValue
if ($Since -ne '') {
    if (-not [datetime]::TryParseExact($Since, 'yyyy-MM-dd HH:mm:ss', [Globalization.CultureInfo]::InvariantCulture,
                                       [Globalization.DateTimeStyles]::None, [ref]$sinceTime)) {
        Write-Output ("verify-auditwords: REFUSED - -Since '" + $Since + "' is not yyyy-MM-dd HH:mm:ss")
        try { Stop-Transcript | Out-Null } catch { }
        exit 2
    }
    $sinceWhy = 'given on the command line'
} else {
    $sinceTime = (Get-Item -LiteralPath $dataDir).CreationTime
    $sinceWhy = 'the creation time of ' + $dataDir + ' (the install moment, as assert-current.ps1 reads it)'
}

# Read with a shared handle: the kernel appends to this file while SD runs.
$text = ''
try {
    $fs = [IO.File]::Open($audit, 'Open', 'Read', 'ReadWrite')
    try { $text = (New-Object IO.StreamReader($fs, [Text.Encoding]::UTF8)).ReadToEnd() } finally { $fs.Close() }
} catch {
    Write-Output ('verify-auditwords: REFUSED - cannot read ' + $audit + ': ' + $_.Exception.Message)
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
$info = Get-Item -LiteralPath $audit
Write-Output ('audit file : {0}' -f $audit)
Write-Output ('size       : {0} bytes, last write {1}' -f $info.Length, $info.LastWriteTime)
Write-Output ('since      : {0}   ({1})' -f $sinceTime.ToString('yyyy-MM-dd HH:mm:ss'), $sinceWhy)

$events   = @(Get-AuditEvents $text $sinceTime)
$parsed   = @($events | Where-Object { $_.Parsed })
$unparsed = @($events | Where-Object { -not $_.Parsed })
Write-Output ('lines      : {0} parsed at or after -Since, {1} that did not parse' -f $parsed.Count, $unparsed.Count)
foreach ($u in ($unparsed | Select-Object -First 3)) { Write-Output ('    unparsed line ' + $u.Line + ': ' + $u.Text.Substring(0, [Math]::Min(120, $u.Text.Length))) }
if ($parsed.Count -eq 0) {
    Write-Output 'verify-auditwords: REFUSED - no audit line since -Since parsed, so a count over nothing would mean nothing.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

Write-Output ''
Write-Output '=== events this release writes, and how many of them this run produced =============='
foreach ($e in $script:ExpectedEvents) {
    $c = Measure-EventWord $parsed $e.Rx
    Write-Output ('  {0,-34} {1}' -f $e.Label, $(if ($c -eq 0) { 'NOT SEEN (nothing in this run wrote it)' } else { [string]$c + ' line(s)' }))
}
Write-Output ''
Write-Output '=== every distinct first word, with its count =========================================='
foreach ($g in ($parsed | Group-Object { ($_.Head -split '\s+')[0] } | Sort-Object Count -Descending)) {
    Write-Output ('  {0,-34} {1}' -f $g.Name, $g.Count)
}

Write-Output ''
Write-Output '=== decisive checks ====================================================================='
$login = Measure-EventWord $parsed '^login'
Note 'CONTROL: the reader recognises this file (at least one "login" event)' $true ($login -gt 0)
$upper = @(Get-UpperHeadLines $parsed)
Note 'no audit line carries an upper-case letter before its first "="' 0 $upper.Count
foreach ($u in ($upper | Select-Object -First 10)) {
    Write-Output ('    line {0}  {1}  {2}' -f $u.Line, $u.Stamp, $u.Text.Substring(0, [Math]::Min(160, $u.Text.Length)))
}

Write-Output ''
Write-Output '=== Summary =============================================================='
$results | Format-Table -AutoSize | Out-String -Width 200 | Write-Output
$passed = ($results | Where-Object { $_.Result -eq 'PASS' }).Count
Write-Output ('  {0} of {1} checks passed' -f $passed, $results.Count)
Write-Output $(if ($failed) { 'VERDICT: FAIL - an audit line carries an upper-case word before its first "="' }
               else { 'VERDICT: PASS - every audit line since the install is lower case before its first "="' })

try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 } else { exit 0 }
