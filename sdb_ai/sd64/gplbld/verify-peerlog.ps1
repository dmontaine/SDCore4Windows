<#
.SYNOPSIS
    Prove sdwind identifies the process at the other end of an API connection,
    and that the error log it now writes per connection stays inside ERRLOG.

.DESCRIPTION
    ONE ELEVATED COMMAND for the peer-authentication work.  Two things landed
    together and this measures both, because neither is safe without the other:

      * sdwind.c logs WHO connected - the peer's Windows pid and account,
        from GetExtendedTcpTable (gplsrc/win32peer.c).  Owner's decision,
        20 Aug 2026: LOG ONLY.  Nothing is refused.
      * sdwind.c's log_message() gained the errlog trim the sd side has always
        had.  Without it, a per-connection writer ignores ERRLOG and grows the
        file without bound.

    WHAT MAKES THIS A TEST RATHER THAN A DEMONSTRATION, and it is the same
    trick the peer probe uses: THE ANSWER IS KNOWN INDEPENDENTLY.  The
    connections are opened by processes whose pids this script was told by
    Windows, not ones it deduced - $PID for its own, and Start-Process's
    reported pid for the second.  A lookup that returned any constant would
    pass a one-peer test and fails this one.

    AND THE CROSS-ACCOUNT CASE IS THE POINT, not an extra.  sdwind runs as
    LocalSystem and every peer it looks at belongs to somebody else, so
    OpenProcess across accounts is exercised here for the first time - the
    probe ran both halves as the same user.

    THE TRIM'S CONTROL IS THE OLD/NEW MARKER PAIR.  "The file got smaller"
    would also be true if the trim threw the whole thing away, which would be
    silent data loss.  So a planted log carries a marker in its FIRST record
    and another in its LAST, and the assertion is that the first is gone AND
    the second survives.

    NOTHING IS MEASURED BY DIFFING TWO READS, deliberately.  A trim can fire
    between any two reads and make the second SHORTER than the first, so
    "what appeared since last time" is not a safe question to ask of this
    file.  Every assertion below searches the whole log for a pid this script
    already knows, which a trim cannot invalidate - it discards the oldest
    records, and the ones being looked for are the newest.

    IT CHANGES THE INSTALLED SYSTEM AND PUTS IT BACK.  sd.conf gains ERRLOG
    and APIPORT lines and is restored from a backup in a finally block; SD is
    restarted twice.  THE ERROR LOG IS DELIBERATELY OVERWRITTEN and is not put
    back - it is planted with synthetic records, which is how the trim is made
    to fire without opening a thousand connections.  Say so before running
    this on a machine whose SD error log matters.

.PARAMETER Port
    Loopback port the API listener uses.  4243 is the shipped default.

.PARAMETER MaxConnections
    Give up looking for the trim after this many connections.  The default is
    generous; the plant leaves only a few hundred bytes of headroom, so the
    trim normally fires within a handful.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-peerlog.ps1
#>

[CmdletBinding()]
param(
    [int] $Port = 4243,
    [int] $MaxConnections = 40
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$SvcName = 'SD'
$conf    = Join-Path $env:ProgramData 'SD\sd.conf'
$backup  = $conf + '.before-peerlog'
$errlog  = Join-Path $env:ProgramData 'SD\sdsys\errlog'

# ERRLOG's floor.  config.c:401 raises anything smaller to this "for file trim
# to work in log_message()", so asking for less would measure a number the
# server had silently replaced.
$ErrlogKb    = 10
$ErrlogBytes = $ErrlogKb * 1024

# NOT UNDER C:\ProgramData\SD, for the reason cycle.ps1 gives: LOCALAPPDATA is
# the same directory elevated or not, so an unelevated session afterwards can
# read what this wrote.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-peerlog-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results  = New-Object System.Collections.ArrayList
$failed   = $false
$peakSeen = 0

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

function Fail($msg) {
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

function Stop-SD {
    if (Get-Service -Name $SvcName -ErrorAction SilentlyContinue) {
        & "$env:SystemRoot\System32\sc.exe" stop $SvcName | Out-Null
    }
    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    return -not [bool](Get-Process -Name sdwind, sd -ErrorAction SilentlyContinue)
}

function Start-SD {
    & "$env:SystemRoot\System32\sc.exe" start $SvcName | Out-Null
    $deadline = (Get-Date).AddSeconds(45)
    while (-not (Get-Process -Name sdwind -ErrorAction SilentlyContinue) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 500
    }
    return [bool](Get-Process -Name sdwind -ErrorAction SilentlyContinue)
}

# EVERY SIZE READING GOES THROUGH HERE so the high-water mark is kept as we
# go.  "The log reached the cap" has to be true of the whole run, not of the
# step that happened to be looking when it did - a trim in an earlier step
# would otherwise hide the evidence that there was anything to trim.
function Get-ErrlogSize {
    if (-not (Test-Path -LiteralPath $errlog)) { return 0 }
    $n = (Get-Item -LiteralPath $errlog).Length
    if ($n -gt $script:peakSeen) { $script:peakSeen = $n }
    return $n
}

# Read it with FileShare::ReadWrite - the daemon holds it open across its own
# write, and a plain Get-Content intermittently answers "in use by another
# process" rather than the contents.
function Get-ErrlogText {
    if (-not (Test-Path -LiteralPath $errlog)) { return '' }
    $fs = [System.IO.File]::Open($errlog, [System.IO.FileMode]::Open,
                                 [System.IO.FileAccess]::Read,
                                 [System.IO.FileShare]::ReadWrite)
    try {
        $sr = New-Object System.IO.StreamReader($fs)
        try { return $sr.ReadToEnd() } finally { $sr.Dispose() }
    } finally { $fs.Dispose() }
}

# The API connection lines currently in the log, newest last.
function Get-PeerLines {
    return @((Get-ErrlogText) -split "`n" | Where-Object { $_ -match 'API connection from' })
}

# One connection to the API port, opened and dropped.  The far end forks an
# "sd -n -q" that sees EOF and exits; nothing is sent, because the peer is
# identified at accept() and this test has no business reaching SCRAM.
#
# A SESSION THAT FAILS TO START DOES NOT AFFECT THIS TEST, which is worth
# saying because opening a few dozen connections could reach NUMUSERS.  The
# log line is written BEFORE the fork (sdwind.c, accept_api_session), so it
# is there whether or not the child ever ran.
function Connect-Once {
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $c.Connect('127.0.0.1', $Port)
        Start-Sleep -Milliseconds 250   # let sdwind accept and log before we go
    } finally { $c.Close() }
}

# ---------------------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'Run this from an ELEVATED PowerShell - it edits the installed sd.conf, overwrites the SD error log and restarts SD.'
}

# THE CYCLE RULE, and it is a gate rather than a reminder.  CLAUDE.md: anything
# that tests the install calls this first, or the result describes a tree that
# no longer exists.
Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'assert-current refuses - run gplbld/cycle.ps1 first.' }

if (-not (Test-Path -LiteralPath $conf)) { Fail "No installed sd.conf at $conf." }

$restoreNeeded = $false
$oldest = 'PEERLOGMARKER-OLDEST'
$newest = 'PEERLOGMARKER-NEWEST'

try {
    # -----------------------------------------------------------------------
    Step 1 "Setting ERRLOG=$ErrlogKb and APIPORT=$Port in the installed sd.conf"

    Copy-Item -LiteralPath $conf -Destination $backup -Force
    $restoreNeeded = $true

    # FILTER BOTH KEYS OUT FIRST.  APIPORT ships active now, so appending
    # without removing would leave two APIPORT lines and read_config() would
    # take whichever it met last - verify-apiport.ps1 carries the same guard
    # for the same reason.
    $lines = @(Get-Content -LiteralPath $conf) |
             Where-Object { $_ -notmatch '^\s*APIPORT\s*=' -and $_ -notmatch '^\s*ERRLOG\s*=' }
    $lines += ('ERRLOG=' + $ErrlogKb)
    $lines += ('APIPORT=' + $Port)
    Set-Content -LiteralPath $conf -Value $lines -Encoding Ascii

    # -----------------------------------------------------------------------
    Step 2 'Stopping SD and planting a log just under the cap'

    if (-not (Stop-SD)) { Fail 'SD would not stop - close any open session and try again.' }

    # WRITTEN IN PLACE, NEVER DELETED AND RECREATED.  A recreated file inherits
    # the data tree's ACL afresh, which is the quiet downgrade win32audit.h
    # describes; overwriting keeps whatever the installer put on it.
    #
    # PLANTED JUST UNDER THE CAP so the trim is a few connections away rather
    # than a few hundred.  The records are the shape sdwind writes - a header
    # line and an indented message line - because the trim restarts the file
    # at the first newline past the halfway mark, and a file of one enormous
    # line would exercise the guard rather than the path.
    $filler = ('.' * 60)
    $plant  = New-Object System.Text.StringBuilder
    $null = $plant.Append("20 Aug 26 00:00:00 [$oldest]:`n   planted first record $filler`n")
    while ($plant.Length -lt ($ErrlogBytes - 400)) {
        $null = $plant.Append("20 Aug 26 00:00:00 [sdwind]:`n   planted filler $filler`n")
    }
    $null = $plant.Append("20 Aug 26 00:00:00 [$newest]:`n   planted last record $filler`n")
    [System.IO.File]::WriteAllText($errlog, $plant.ToString(),
                                   (New-Object System.Text.ASCIIEncoding))

    $planted      = Get-ErrlogSize
    $plantedText  = Get-ErrlogText
    # THE LINES AS PLANTED, for the whole-line assertion at the end.
    $plantedLines = @($plantedText -split "`n")
    Write-Host ("   planted $planted bytes, cap is $ErrlogBytes")

    # Control on the plant itself: a test that cannot see its own setup is
    # measuring nothing afterwards.
    Note 'planted log is under the cap' $true ($planted -lt $ErrlogBytes)
    Note 'planted log carries the OLDEST marker' $true ($plantedText -match [regex]::Escape($oldest))
    Note 'planted log carries the NEWEST marker' $true ($plantedText -match [regex]::Escape($newest))
    Note 'planted log has no API connection lines yet' 0 (Get-PeerLines).Count

    # -----------------------------------------------------------------------
    Step 3 'Starting SD'

    # IT HAS TO BE A RESTART, not a reload.  read_config() runs only when the
    # shared segment is CREATED (sysseg.c:150-157); an attaching session takes
    # pcfg from the segment instead, so a running system never sees the change.
    if (-not (Start-SD)) { Fail 'SD would not start again.  Read the SD error log.' }
    Start-Sleep -Seconds 2

    $sdwind    = Get-Process -Name sdwind -ErrorAction SilentlyContinue
    $sdwindPid = if ($sdwind) { $sdwind.Id } else { 0 }
    Write-Host "   sdwind pid $sdwindPid"

    $listen = @(netstat -an | Select-String 'LISTENING' |
                Where-Object { $_ -match ('127\.0\.0\.1:' + $Port + '\s') })
    Note 'listener on 127.0.0.1' $true ($listen.Count -gt 0)
    if ($listen.Count -eq 0) { Fail "Nothing is listening on 127.0.0.1:$Port - the rest cannot be measured." }

    # -----------------------------------------------------------------------
    Step 4 "Connecting from THIS process (pid $PID)"

    Connect-Once
    $peers = Get-PeerLines
    Note 'a connection was logged' $true ($peers.Count -gt 0)
    foreach ($l in $peers) { Write-Host ('   ' + $l.Trim()) }

    $mineLine = ''
    foreach ($l in $peers) { if ($l -match ('pid\s+' + $PID + '\b')) { $mineLine = $l } }

    # THE PID ASSERTION, and it is the whole test: $PID came from Windows, not
    # from anything this script or SD worked out.
    Note "logged pid is this process ($PID)" $true ($mineLine -ne '')

    # THE ACCOUNT ASSERTION.  sdwind is LocalSystem and this process is not, so
    # this is the cross-account OpenProcess the probe never reached.
    $me = $env:USERDOMAIN + '\' + $env:USERNAME
    Note "logged account is $me" $true ($mineLine -match [regex]::Escape($me))
    Note 'the owner was resolved, not "unknown"' $false ($mineLine -match 'owner unknown')

    # AND THE FIRST CONTROL AGAINST A CONSTANT: it cannot be sdwind's own pid,
    # which is what a lookup reporting the asking process would return.
    Note 'logged pid is not sdwind itself' $false ($mineLine -match ('pid\s+' + $sdwindPid + '\b'))

    # -----------------------------------------------------------------------
    Step 5 'Connecting from a DIFFERENT process, which must be named instead'

    # THE SECOND PEER IS WHAT KILLS "it reports a constant" OUTRIGHT.  One peer
    # proves a number was produced; two different peers producing two different
    # numbers proves the number was looked up.
    $childScript = @"
`$c = New-Object System.Net.Sockets.TcpClient
`$c.Connect('127.0.0.1', $Port)
Start-Sleep -Milliseconds 600
`$c.Close()
"@
    $childFile = Join-Path $env:TEMP ('sd-peerlog-child-' + $PID + '.ps1')
    Set-Content -LiteralPath $childFile -Value $childScript -Encoding Ascii

    $child = Start-Process -FilePath 'powershell.exe' `
                -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $childFile) `
                -PassThru -WindowStyle Hidden
    $childPid = $child.Id
    Write-Host "   child powershell pid $childPid"
    try { $null = $child.WaitForExit(20000) } catch { }
    Start-Sleep -Milliseconds 500

    $peers2 = Get-PeerLines
    foreach ($l in $peers2) { Write-Host ('   ' + $l.Trim()) }

    $theirLine = ''
    foreach ($l in $peers2) { if ($l -match ('pid\s+' + $childPid + '\b')) { $theirLine = $l } }

    Note 'the two peers really are different processes' $true ($childPid -ne $PID)
    Note "the child ($childPid) was logged"  $true ($theirLine -ne '')
    Note 'and its line is not this process'  $false ($theirLine -match ('pid\s+' + $PID + '\b'))
    # BOTH must be present at once.  A lookup that returned "whoever asked
    # last" would satisfy either assertion alone and neither together.
    Note 'both pids are in the log together' $true (($mineLine -ne '') -and ($theirLine -ne ''))

    Remove-Item -LiteralPath $childFile -Force -ErrorAction SilentlyContinue

    # -----------------------------------------------------------------------
    Step 6 'Connecting until the trim fires'

    $prev  = Get-ErrlogSize
    $fired = 0
    $sizes = New-Object System.Collections.ArrayList
    $null  = $sizes.Add($prev)

    for ($i = 1; $i -le $MaxConnections; $i++) {
        Connect-Once
        $now = Get-ErrlogSize
        $null = $sizes.Add($now)
        # A DROP is the trim, and nothing else here can shrink the file.
        if ($now -lt $prev) { $fired = $i; break }
        $prev = $now
    }

    Write-Host ('   sizes: ' + (($sizes | Select-Object -First 60) -join ' '))
    Note 'the trim fired' $true ($fired -gt 0)
    if ($fired -gt 0) { Write-Host "   fired on connection $fired" }

    $final     = Get-ErrlogSize
    $finalText = Get-ErrlogText

    # THE MEASUREMENT IS NOT VACUOUS: the log must actually have reached the
    # cap, or "it is under the cap" says nothing at all.
    Note 'the log did reach the cap' $true ($peakSeen -ge $ErrlogBytes)
    Note 'and is under it afterwards' $true ($final -lt $ErrlogBytes)
    Write-Host "   peak $peakSeen, final $final, cap $ErrlogBytes"

    # -----------------------------------------------------------------------
    Step 7 'What the trim kept, and what it threw away'

    # THE PAIR IS THE CONTROL.  "Smaller" would also be true of a file the
    # trim had emptied, which is silent data loss wearing the right number.
    Note 'the OLDEST record is gone'  $false ($finalText -match [regex]::Escape($oldest))
    Note 'the NEWEST record survived' $true  ($finalText -match [regex]::Escape($newest))

    # AND IT STARTS ON A LINE BOUNDARY, asserted without assuming the log's
    # format: the first line of the trimmed file must be one of the lines that
    # was in it beforehand, WHOLE.  An off-by-one leaves a suffix instead, and
    # a suffix matches nothing.
    $firstLine = (($finalText -split "`n")[0])
    $whole = @($plantedLines | Where-Object { $_ -eq $firstLine }).Count -gt 0
    Note 'the file starts on a whole line' $true $whole
    Write-Host ('   first line now: ' + $firstLine.Trim())

    # The connections made AFTER the trim must still be there - the newest data
    # is the data a log exists for.
    Note 'connections are still logged after the trim' $true ($finalText -match 'API connection from')
}
finally {
    Write-Host ''
    Write-Host '== [restore] Putting sd.conf back and restarting SD' -ForegroundColor Cyan
    if ($restoreNeeded -and (Test-Path -LiteralPath $backup)) {
        Copy-Item -LiteralPath $backup -Destination $conf -Force
        Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue
        Write-Host '   sd.conf restored'
    }
    if (Stop-SD) { $null = Start-SD }
    Write-Host '   THE ERROR LOG IS NOT RESTORED - it holds this run''s planted records.'
}

Write-Host ''
$results | Format-Table -AutoSize
$pass  = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
$total = $results.Count
Write-Host ("verify-peerlog: {0}/{1}" -f $pass, $total) -ForegroundColor $(if ($failed) { 'Red' } else { 'Green' })
try { Stop-Transcript | Out-Null } catch { }
exit $(if ($failed) { 1 } else { 0 })
