# witness-vm-xfer.ps1 - file transfer over the ssh login (RELEASE_1.1 299, Linux S.242) on a real Windows install.
#
#   powershell -ExecutionPolicy Bypass -File C:\sdrepo\sdb_ai\sd64\gplbld\witness-vm-xfer.ps1
#
# ELEVATED PowerShell in the VM, SDSYS signed in (the seat), the fixtures made (witness-vm-admin.ps1 -Only fixtures: zzwiton, a user
# account with the ssh route).  What it does, each step printed with SD's and the client's raw output and the audit lines it read:
#   1. sd.conf gets XFER=1 (a copy is kept and put back at the end), SD is restarted through its service.
#   2. NO SLOT: Windows' own sftp.exe connects as zzwiton.  PASS only when the audit has "xfer refused reason=no slot is open" for
#      zzwiton: that is SD's transfer server answering, i.e. Win32-OpenSSH passed "sftp-server.exe" as SSH_ORIGINAL_COMMAND and sd.exe
#      recognised it (sd_sftp.h, our OS deviation).  A "login" line for zzwiton instead, or no xfer line at all, is a FAIL.
#   3. modify.account zzwiton xfer-on (the seat).
#   4. RECEIVE: an ssh session of zzwiton types "receive"; sftp puts a plain-text file and a binary one; Enter closes the slot.
#      PASS: the text file is in zzwiton's xfer.in with the same SHA-256, the binary one is not, and the audit has xfer open, connect,
#      file (the text one), refused (the binary one, not plain text) and close.
#   5. Put back: xfer-off, the original sd.conf, SD restarted.
# It never ends an SD process.  WinSCP's .filepart is NOT measured here (no WinSCP in the VM).  Exit 0 passed, 1 FAIL, 2 could not run.
#
# START-HISTORY:
# 15 Nov 26  New (RELEASE_1.1 299).  Parse-checked; first run is the VM round of 15 Nov.
# END-HISTORY

$ErrorActionPreference = 'Continue'
. (Join-Path $PSScriptRoot 'witness-vm-lib.ps1')
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')

Start-Wit 'witness-vm-xfer' @('xfer')
if (-not (Test-WitElevated)) { Write-Wit 'CANNOT RUN: not elevated.'; exit 2 }
$fix = Read-WitFixtures
$pw = ''
if ($null -ne $fix -and $fix.ContainsKey('zzwiton')) { $pw = $fix['zzwiton'] }
if ($pw -eq '') { Write-Wit 'CANNOT RUN: no zzwiton password on file (run witness-vm-admin.ps1 -Only fixtures).'; exit 2 }
$sftpExe = Get-Command sftp.exe -ErrorAction SilentlyContinue
$sshExe = Get-Command ssh.exe -ErrorAction SilentlyContinue
if ($null -eq $sftpExe -or $null -eq $sshExe) { Write-Wit 'CANNOT RUN: no ssh.exe or sftp.exe (OpenSSH client) on PATH.'; exit 2 }
Write-Wit ('  sftp: ' + $sftpExe.Source + '   ssh: ' + $sshExe.Source)

$conf = Join-Path $script:WitDataDir 'sd.conf'
$confBak = Join-Path $script:WitRoot 'sd.conf.before-xfer'
$acctDir = Join-Path $script:WitDataDir 'user_accounts\zzwiton'
$inDir = Join-Path $acctDir 'xfer.in'
$work = Join-Path $script:WitRoot 'xfer-test'
$null = New-Item -ItemType Directory -Path $work -Force
$opts = @('-o', 'StrictHostKeyChecking=no', '-o', 'UserKnownHostsFile=NUL', '-o', 'ConnectTimeout=20', '-o', 'LogLevel=ERROR',
          '-o', 'PreferredAuthentications=password', '-o', 'NumberOfPasswordPrompts=1')
$ask = Join-Path $work 'askpass.cmd'
Set-Content -Path $ask -Encoding ascii -Value @('@echo off', 'echo %SDPROBEPW%')

function Start-Client([string]$Exe, [string[]]$ArgList) {
    $psi = New-Object Diagnostics.ProcessStartInfo
    $psi.FileName = $Exe
    $psi.Arguments = ($ArgList -join ' ')
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $psi.EnvironmentVariables['SDPROBEPW'] = $pw
    $psi.EnvironmentVariables['SSH_ASKPASS'] = $ask
    $psi.EnvironmentVariables['SSH_ASKPASS_REQUIRE'] = 'force'
    $psi.EnvironmentVariables['DISPLAY'] = 'localhost:0'
    Write-Wit ('  > ' + $Exe + ' ' + $psi.Arguments)
    $p = [Diagnostics.Process]::Start($psi)
    return @{ P = $p; Out = $p.StandardOutput.ReadToEndAsync(); Err = $p.StandardError.ReadToEndAsync() }
}
function Run-Sftp([string[]]$Lines, [int]$Wait = 60) {
    $c = Start-Client $sftpExe.Source ($opts + @('zzwiton@localhost'))
    foreach ($l in $Lines) { Write-Wit ('    sftp> ' + $l); $c.P.StandardInput.WriteLine($l) }
    $c.P.StandardInput.Close()
    $done = $c.P.WaitForExit($Wait * 1000)
    if (-not $done) { Write-Wit ('  sftp did not end within ' + $Wait + ' s (pid ' + $c.P.Id + ', left alone)'); return '' }
    $t = $c.Out.Result + "`n" + $c.Err.Result
    Write-WitRaw ('sftp (exit ' + $c.P.ExitCode + ')') $t
    return $t
}
function Restart-Sd { try { Restart-Service -Name SD -ErrorAction Stop; Start-Sleep -Seconds 4; Write-Wit ('  service SD: ' + (Get-Service SD).Status) } catch { Write-Wit ('  Restart-Service SD failed: ' + $_.Exception.Message) } }

# ---------------------------------------------------------------------------------------------------- 1. XFER=1
Write-Wit ''
Write-Wit '=== 1. XFER=1 in sd.conf (a copy is kept), SD restarted'
Copy-Item -LiteralPath $conf -Destination $confBak -Force
$lines = @(Get-Content -LiteralPath $conf)
$had = @($lines | Where-Object { $_ -match '^\s*XFER\s*=' })
Write-Wit ('  sd.conf XFER lines before: ' + $(if ($had.Count) { $had -join ' | ' } else { '(none)' }))
$new = @($lines | Where-Object { $_ -notmatch '^\s*XFER\s*=' }) + 'XFER=1'
Set-Content -LiteralPath $conf -Value $new -Encoding ascii
Write-Wit ('  sd.conf XFER lines after : ' + (@(Get-Content -LiteralPath $conf | Where-Object { $_ -match '^\s*XFER\s*=' }) -join ' | '))
Restart-Sd

try {
    # ------------------------------------------------------------------------------------------------ 2. no slot
    Write-Wit ''
    Write-Wit '=== 2. an sftp request with no transfer open: does it reach SD''s transfer server?'
    $mark = Get-WitAuditMark
    $t = Run-Sftp @('ls', 'quit')
    Start-Sleep -Seconds 2
    $a = @(Get-WitAuditSince $mark)
    Write-WitRaw 'audit since the mark' ($a -join "`n")
    $xferNoSlot = @($a | Where-Object { $_ -match 'xfer refused' -and $_ -match 'no slot is open' })
    $loginLine = @($a | Where-Object { $_ -match '\blogin\b' -and $_ -match 'zzwiton' })
    if ($xferNoSlot.Count -gt 0 -and $loginLine.Count -eq 0) { Add-WitResult '299' 'an sftp request reaches SD''s transfer server (Win32-OpenSSH passes sftp-server.exe; sd.exe recognises it) and is refused: no slot is open' 'PASS' $xferNoSlot[0] }
    elseif ($loginLine.Count -gt 0) { Add-WitResult '299' 'an sftp request reaches SD''s transfer server' 'FAIL' ('SD ran a LOGIN for it instead: ' + $loginLine[0] + ' (SSH_ORIGINAL_COMMAND did not match sd_sftp.h)') }
    else { Add-WitResult '299' 'an sftp request reaches SD''s transfer server' 'FAIL' 'no "xfer refused ... no slot is open" line; see the client output and the audit above' }

    # ------------------------------------------------------------------------------------------------ 3. xfer-on
    Write-Wit ''
    Write-Wit '=== 3. modify.account zzwiton xfer-on'
    $r = Invoke-WitSd -Commands @('MODIFY.ACCOUNT zzwiton xfer-on') -Label 'zzwiton: xfer-on' -TimeoutSec 120
    Set-WitVerdict '299' 'modify.account zzwiton xfer-on says the account may move files' $r.Text 'Account zzwiton may move files over its ssh login \(receive / send\): yes' @('not a user account', 'not in your VOC', 'already had')

    # ------------------------------------------------------------------------------------------------ 4. receive
    Write-Wit ''
    Write-Wit '=== 4. receive in an ssh session of zzwiton; sftp puts a text file and a binary file; Enter closes'
    $txt = Join-Path $work 'orders.csv'
    Set-Content -LiteralPath $txt -Value @('id,qty,price', '1,4,9.95', '2,1,120.00', 'witness 299 15 Nov 26') -Encoding ascii
    $bin = Join-Path $work 'logo.bin'
    [IO.File]::WriteAllBytes($bin, [byte[]](0, 1, 2, 3, 255, 254, 10))
    $txtHash = (Get-FileHash -LiteralPath $txt -Algorithm SHA256).Hash
    Write-Wit ('  orders.csv sha256 ' + $txtHash)
    if (Test-Path -LiteralPath (Join-Path $inDir 'orders.csv')) { Remove-Item -LiteralPath (Join-Path $inDir 'orders.csv') -Force }
    $mark = Get-WitAuditMark
    $h = Start-Client $sshExe.Source ($opts + @('zzwiton@localhost', 'session'))
    $h.P.StandardInput.WriteLine(''); $h.P.StandardInput.WriteLine('TERM 200,9999'); $h.P.StandardInput.WriteLine('receive'); $h.P.StandardInput.Flush()
    Start-Sleep -Seconds 10
    $t2 = Run-Sftp @(('put "' + $txt + '"'), ('put "' + $bin + '"'), 'quit')
    Start-Sleep -Seconds 3
    $h.P.StandardInput.WriteLine(''); $h.P.StandardInput.Flush()
    Start-Sleep -Seconds 6
    try { $h.P.StandardInput.WriteLine('OFF'); $h.P.StandardInput.Close() } catch { }
    $ended = $h.P.WaitForExit(30000)
    if ($ended) { Write-WitRaw 'the ssh session of zzwiton (receive)' ($h.Out.Result + "`n" + $h.Err.Result) }
    else { Write-Wit ('  the ssh client (pid ' + $h.P.Id + ') is still running; its output is not read (left alone)') }
    Start-Sleep -Seconds 2
    $a = @(Get-WitAuditSince $mark)
    Write-WitRaw 'audit since the mark' ($a -join "`n")
    $got = Join-Path $inDir 'orders.csv'
    $gotHash = if (Test-Path -LiteralPath $got) { (Get-FileHash -LiteralPath $got -Algorithm SHA256).Hash } else { '' }
    Write-Wit ('  xfer.in\orders.csv: ' + $(if ($gotHash) { 'sha256 ' + $gotHash } else { 'ABSENT' }))
    Set-WitCompare '299' 'the text file arrived in xfer.in byte for byte (same SHA-256)' $txtHash $gotHash
    Set-WitCompare '299' 'the binary file was not kept' 'False' ([string](Test-Path -LiteralPath (Join-Path $inDir 'logo.bin')))
    foreach ($w in @(@('xfer open dir=in', 'the audit has the opening'), @('xfer connect dir=in', 'the audit has the connection'),
                     @('xfer file dir=in', 'the audit has the text file with its size and SHA-256'), @('name=orders.csv', 'the file line names orders.csv'),
                     @('reason=not plain text', 'the audit has the binary file refused as not plain text'), @('xfer close dir=in', 'the audit has the closing'))) {
        $hit = @($a | Where-Object { $_ -match [regex]::Escape($w[0]) })
        Add-WitResult '299' $w[1] $(if ($hit.Count) { 'PASS' } else { 'FAIL' }) $(if ($hit.Count) { $hit[0] } else { 'no line with "' + $w[0] + '"' })
    }
    $fileLine = @($a | Where-Object { $_ -match 'xfer file dir=in' -and $_ -match 'name=orders\.csv' })
    if ($fileLine.Count -and $gotHash) {
        Set-WitVerdict '299' 'the audit''s SHA-256 for orders.csv is the file''s (its first 8 hex digits)' ($fileLine[0].ToLower()) ('sha256=' + $gotHash.Substring(0, 8).ToLower()) @()
    }
    Add-WitResult '299' 'WinSCP (resume, .filepart): Linux asked' 'NOT-MEASURED' 'no WinSCP in the VM'
}
finally {
    # ------------------------------------------------------------------------------------------------ 5. put back
    Write-Wit ''
    Write-Wit '=== 5. put back: xfer-off, the original sd.conf, SD restarted'
    $null = Invoke-WitSd -Commands @('MODIFY.ACCOUNT zzwiton xfer-off') -Label 'zzwiton: xfer-off' -TimeoutSec 120
    Copy-Item -LiteralPath $confBak -Destination $conf -Force
    Write-Wit ('  sd.conf XFER lines now: ' + $(if (@(Get-Content -LiteralPath $conf | Where-Object { $_ -match '^\s*XFER\s*=' }).Count) { 'some' } else { '(none, as before)' }))
    Restart-Sd
}

$code = Complete-Wit
exit $code
