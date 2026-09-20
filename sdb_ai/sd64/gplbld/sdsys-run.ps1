<#
.SYNOPSIS
    Run SD commands AS SDSYS from your own elevated prompt, through the seat.

.DESCRIPTION
    A thin command-line front for sdsys-seat.ps1.  SD reaches SDSYS only from a process
    that IS the OS SDSYS account with an elevated, interactive token (kernel.c:299);
    "LOGTO SDSYS" and "sd -ASDSYS" from anywhere else are refused (10002).  So this
    hands the commands to a task inside SDSYS's own live session and prints what SD
    said.  It is for cleanup and for one-off development commands.

    Run it from an ELEVATED PowerShell as yourself - you do not switch to SDSYS - and
    SDSYS must be signed in (`query session` shows an SDSYS row).  It proves the seat
    first (Assert-SdSeat) and refuses with exit 2, before running anything, if it
    cannot.

    -Commands is ONE string, commands and their answers separated by ";".  A
    command that asks a question is answered by the NEXT item - "DELETE.ACCOUNT X;Y" -
    because the whole list is piped in, and a prompt with no answer waits until the
    timeout.  (Measured 20 Sep 2026: DELETE.FILE asks NOTHING for an ordinary file, so
    "DELETE.FILE ZZX;Y" only adds a harmless "Y is not in your VOC" - give an answer
    only to a command that really asks.)  A comma-separated list does NOT work through
    "powershell -File": it arrives as one string.  An SD command that itself contains a
    semicolon cannot be sent this way.

    -Internal runs "sd.exe -internal", the DEVELOPMENT door (RELEASE_1.1 82): it is
    what admits a LOGTO to a personal account, because the seat's OS user (SDSYS) is
    in no personal account's group.  Ask for it only when you need that.

    Exit 0 SD ran, 1 the seat ran but the call failed, 2 the seat could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\sdsys-run.ps1 -Commands "WHO"
#>

param(
    [Parameter(Mandatory = $true)] [string] $Commands,
    [switch] $Internal,
    [int]    $TimeoutSec = 120
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'sdsys-seat.ps1')

$list = @($Commands -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
if ($list.Count -eq 0) { Write-Output 'sdsys-run: -Commands held nothing to run.'; exit 2 }

Write-Output ('sdsys-run: {0} command(s){1}' -f $list.Count, $(if ($Internal) { ', through sd -internal' } else { '' }))
$list | ForEach-Object { Write-Output ('  > ' + $_) }
Write-Output ''

Assert-SdSeat -Label 'sdsys-run' -Internal:$Internal

$text = ''
try { $text = Invoke-SdSeatText -Commands $list -TimeoutSec $TimeoutSec -Internal:$Internal }
catch { Write-Output ''; Write-Output ('sdsys-run: ' + $_.Exception.Message); exit 1 }

Write-Output ''
Write-Output '  --- what SD said ---'
foreach ($l in @($text -split "`n")) { if ($l -match '\S') { Write-Output ('    ' + $l.Trim()) } }
exit 0
