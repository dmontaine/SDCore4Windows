<#
.SYNOPSIS
    Does SETPTR mode 1 print to a Windows printer - the one named with AT, and
    the user's default when none is named - and say so when it cannot?
    RELEASE_1.1 54.  ELEVATED (it creates two local printers).

.DESCRIPTION
    Until 17 Sep 2026 a mode-1 print job was written to sdsys\prt and handed to
    "lp" through system(); the install has no shell and no lp, so every job
    vanished with no message.  spool_print_job() now hands the file to
    PowerShell's Out-Printer (linuxprt.c).  This is the witness, and it has to
    print to something whose output can be READ BACK - the box's real default
    printer may be paper, or "Microsoft Print to PDF" on a PORTPROMPT: port that
    raises a Save dialog no unattended session can answer.  So it makes its own:

      two printers on the "Generic / Text Only" driver, each on a LOCAL PORT
      WHOSE NAME IS A FILE PATH, which Windows spools straight into that file.
      <Prefix>a is the printer SETPTR names with AT; <Prefix>d is made the
      running user's DEFAULT for the run (the previous default is recorded and
      put back).  Neither touches paper.

    Legs, each an SD session driven through sd.exe:
      1. named   SETPTR 0,...,1,AT <Prefix>a,BRIEF then LIST ... LPTR: the
                 text arrives in <Prefix>a's file.
      2. default SETPTR 0,...,1,BRIEF (no AT): the text arrives in <Prefix>d's
                 file - the default-printer path, which is the one that reads
                 "prints to the default Windows printer".
      3. refusal SETPTR ... AT zz-no-such-printer: the session prints
                 "Print job not sent: Windows refused it for printer ..." and
                 NEITHER file gains a job (the null case: a job going to the
                 wrong printer would be worse than none).
    Before any leg, both files are asserted ABSENT, so a stale file cannot
    score.  The job text carries the run's own prefix, so a file from another
    run cannot either.

    NO ACCOUNT AND NO PROFILE: the prefix names two printers and two files,
    nothing in Windows' account database - so it is declared in
    clean-test-profiles.ps1's $notProfiles, not $stems.

.OUTPUTS
    Exit 0 every decisive check passed, 1 a check failed, 2 could not run.
#>

param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$ESC     = [char]27
$Driver  = 'Generic / Text Only'
$Stage   = Join-Path $env:ProgramData ('sdprint-' + $Prefix)
$PrnA    = $Prefix + 'a'          # named with AT
$PrnD    = $Prefix + 'd'          # the default for the run
$FileA   = Join-Path $Stage ($PrnA + '.prn')
$FileD   = Join-Path $Stage ($PrnD + '.prn')
$Marker  = 'ZZPRINT' + $Prefix.ToUpper()

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-print-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results = New-Object System.Collections.ArrayList
$failed  = $false
$prevDefault = $null
$madeA = $false; $madeD = $false; $madePortA = $false; $madePortD = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}
function Fail($msg) { Write-Host ''; Write-Host "STOPPED: $msg" -ForegroundColor Red; try { Stop-Transcript | Out-Null } catch { }; exit 1 }
function Refuse($msg) {
    if ($script:failed) { Fail ($msg + '  (a decisive check had already FAILED, so this is exit 1, not 2)') }
    Write-Host ''; Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow; try { Stop-Transcript | Out-Null } catch { }; exit 2
}
function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 90) {
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) { $out = Receive-Job $job }
    else { Stop-Job $job; $out = Receive-Job $job; $out += "<<TIMED OUT after $TimeoutSec s>>" }
    Remove-Job $job -Force
    return (($out -join "`n") -replace ($ESC + '\[[0-9]*[A-Za-z]'), '')
}

# A file port's output lands when the spooler has finished, not when SD's
# session returns; give it a moment, but never score an absent file as present.
function Wait-Job-File([string]$path, [int]$seconds = 20) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while ((Get-Date) -lt $deadline) {
        if ((Test-Path -LiteralPath $path) -and ((Get-Item -LiteralPath $path).Length -gt 0)) { Start-Sleep -Milliseconds 500; return $true }
        Start-Sleep -Milliseconds 500
    }
    return (Test-Path -LiteralPath $path)
}

function Show($label, $text) {
    Write-Host "  --- $label ---"
    ($text -split "`n") | Where-Object { $_.Trim() -ne '' } | ForEach-Object { Write-Host ('  | ' + $_) }
}

# ---------------------------------------------------------------------------
$me = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $me.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { Refuse 'Run this from an ELEVATED PowerShell - it creates two local printers.' }
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Refuse 'assert-current says the install is not current. Cycle first.' }
if (-not (Get-PrinterDriver -Name $Driver -ErrorAction SilentlyContinue)) { Refuse "the '$Driver' printer driver is not on this machine; it ships with Windows, so something is off." }
if (-not (Get-Service Spooler -ErrorAction SilentlyContinue) -or (Get-Service Spooler).Status -ne 'Running') { Refuse 'the Print Spooler service is not running.' }
if (Get-Printer -Name $PrnA -ErrorAction SilentlyContinue) { Refuse "a printer named $PrnA already exists - a stale run? remove it first." }
if (Get-Printer -Name $PrnD -ErrorAction SilentlyContinue) { Refuse "a printer named $PrnD already exists - a stale run? remove it first." }

try {
    # -----------------------------------------------------------------------
    Step 1 'Two printers on file ports, one of them the default for this run'
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
    $null = New-Item -ItemType Directory -Path $Stage -Force
    # The spooler (SYSTEM) writes the port file; make sure it may.
    $null = & icacls.exe $Stage /grant '*S-1-5-18:(OI)(CI)F' /T
    Add-PrinterPort -Name $FileA; $madePortA = $true
    Add-PrinterPort -Name $FileD; $madePortD = $true
    Add-Printer -Name $PrnA -DriverName $Driver -PortName $FileA; $madeA = $true
    Add-Printer -Name $PrnD -DriverName $Driver -PortName $FileD; $madeD = $true
    Write-Host "  $PrnA -> $FileA"
    Write-Host "  $PrnD -> $FileD"
    $prevDefault = (Get-CimInstance Win32_Printer | Where-Object { $_.Default } | Select-Object -First 1).Name
    Write-Host ("  previous default printer: " + $(if ($prevDefault) { $prevDefault } else { '(none)' }))
    $net = New-Object -ComObject WScript.Network
    $net.SetDefaultPrinter($PrnD)
    $nowDefault = (Get-CimInstance Win32_Printer | Where-Object { $_.Default } | Select-Object -First 1).Name
    Note 'the run''s default printer is the file-port printer' $PrnD $nowDefault
    Note 'control: neither port file exists before any job' $false ((Test-Path -LiteralPath $FileA) -or (Test-Path -LiteralPath $FileD))

    # -----------------------------------------------------------------------
    Step 2 "named: SETPTR ... AT $PrnA, then a LIST to the printer"
    $out = Invoke-SD @(("SETPTR 0,80,60,0,0,1,AT $PrnA,BRIEF"), "LIST VOC WITH @ID = ""$Marker"" OR @ID = ""WHO"" @ID LPTR")
    Show 'session' $out
    Note 'named: the session reported no refusal' $false ($out -match 'Print job not sent')
    $arrived = Wait-Job-File $FileA
    Note "named: a job arrived in $PrnA's file" $true $arrived
    $textA = $(if ($arrived) { Get-Content -LiteralPath $FileA -Raw } else { '' })
    Show "$PrnA file" $textA
    Note 'named: the job carries the listing (WHO)' $true ($textA -match '\bWHO\b')
    Note 'named: nothing arrived at the default printer''s file' $false (Test-Path -LiteralPath $FileD)

    # -----------------------------------------------------------------------
    Step 3 'default: SETPTR ... with no AT - the default Windows printer'
    $out = Invoke-SD @('SETPTR 0,80,60,0,0,1,BRIEF', "LIST VOC WITH @ID = ""$Marker"" OR @ID = ""WHO"" @ID LPTR")
    Show 'session' $out
    Note 'default: the session reported no refusal' $false ($out -match 'Print job not sent')
    $arrived = Wait-Job-File $FileD
    Note "default: a job arrived in $PrnD's file" $true $arrived
    $textD = $(if ($arrived) { Get-Content -LiteralPath $FileD -Raw } else { '' })
    Show "$PrnD file" $textD
    Note 'default: the job carries the listing (WHO)' $true ($textD -match '\bWHO\b')

    # -----------------------------------------------------------------------
    Step 4 'refusal: a printer that does not exist'
    $sizeA = (Get-Item -LiteralPath $FileA).Length
    $sizeD = (Get-Item -LiteralPath $FileD).Length
    $out = Invoke-SD @('SETPTR 0,80,60,0,0,1,AT zz-no-such-printer,BRIEF', "LIST VOC WITH @ID = ""WHO"" @ID LPTR")
    Show 'session' $out
    Note 'refusal: the session said the job was not sent, naming the printer' $true ($out -match 'Print job not sent: Windows refused it for printer zz-no-such-printer')
    Start-Sleep -Seconds 3
    Note 'refusal: no job went to the named file instead' $sizeA (Get-Item -LiteralPath $FileA).Length
    Note 'refusal: no job went to the default file instead' $sizeD (Get-Item -LiteralPath $FileD).Length
}
catch {
    Write-Host ("verify-print: " + $_.Exception.Message) -ForegroundColor Red
    $failed = $true
}
finally {
    Write-Host ''
    Write-Host '=== cleanup ==='
    try { if ($prevDefault) { (New-Object -ComObject WScript.Network).SetDefaultPrinter($prevDefault); Write-Host "  default printer put back: $prevDefault" } } catch { Write-Host "  could not restore the default printer: $($_.Exception.Message)" }
    if (-not $Keep) {
        foreach ($p in @($PrnA, $PrnD)) { try { if (Get-Printer -Name $p -ErrorAction SilentlyContinue) { Remove-Printer -Name $p } } catch { Write-Host "  could not remove printer ${p}: $($_.Exception.Message)" } }
        foreach ($f in @($FileA, $FileD)) { try { if (Get-PrinterPort -Name $f -ErrorAction SilentlyContinue) { Remove-PrinterPort -Name $f } } catch { Write-Host "  could not remove port ${f}: $($_.Exception.Message)" } }
        try { if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force } } catch { }
        Note 'cleanup: both printers gone' $false ([bool](Get-Printer -Name $PrnA -ErrorAction SilentlyContinue) -or [bool](Get-Printer -Name $PrnD -ErrorAction SilentlyContinue))
    } else {
        Write-Host "  -Keep: $PrnA, $PrnD and $Stage left in place"
    }
}

Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = ($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("verify-print: {0} of {1} checks passed" -f $pass, $results.Count)
try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 }
exit 0
