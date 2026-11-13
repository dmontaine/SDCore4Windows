# verify-carry-seat.ps1 - one administrator session for verify-carry-run.py's adm mode (RELEASE_1.1 254), run as SDSYS
# through the SDSYS seat, with the answer written to a file the launcher reads back.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File <this> -InFile <lines> -OutFile <report> [-TimeoutSec n] [-Internal]
#
# WHY IT EXISTS.  Linux's sandbox suites make an administrator session with SDTEST_ADMIN=1 (their adm()); on Windows the
# only SD administrator is the OS account SDSYS (RELEASE_1.1 64), reached through sdsys-seat.ps1's Invoke-SdViaSeat.  The
# launcher is Python and the seat is PowerShell, so this file is the one crossing: it takes the session's command lines
# (one per line, UTF-8, the launcher has already removed Linux's leading empty line and closing OFF, which the seat sends
# itself), runs them, and writes:
#
#   SEATBRIDGE ok=1|0
#   why=<the seat's refusal, one line; empty when ok>
#   detail=<task id and LastTaskResult>
#   ---
#   <what SD printed>
#   ENDOFBRIDGE
#
# The launcher refuses a report without the first or the last line (a report cut off is not an answer), and ok=0 stops the
# suite with exit 2: a seat that did not run is never read as "SD printed nothing".  Identity, elevation and the interactive
# token are checked by ConvertFrom-SeatReport inside Invoke-SdViaSeat, not here.
#
# -Internal is the seat's internal door (sd -internal, forced to SDSYS; a LOGTO into a fixture account needs it).  It prints
# nothing on the console; everything is in the report.  Exit 0 the seat ran, 2 it did not.  It needs an ELEVATED caller,
# which verify-carry-adm.ps1 is.
#
# START-HISTORY:
# 13 Nov 26 Written for RELEASE_1.1 254 (the adm() stand-in for the carried Linux sandbox suites).
# END-HISTORY

param(
    [Parameter(Mandatory = $true)] [string] $InFile,
    [Parameter(Mandatory = $true)] [string] $OutFile,
    [int] $TimeoutSec = 600,
    [switch] $Internal
)

$ErrorActionPreference = 'Stop'

function One-Line([string]$s) { return (($s -replace "[`r`n]+", ' | ').Trim()) }

function Write-Bridge([bool]$Ok, [string]$Why, [string]$Detail, [string]$Text) {
    $u8 = New-Object Text.UTF8Encoding($false)
    $body = ('SEATBRIDGE ok=' + $(if ($Ok) { '1' } else { '0' }) + "`n" +
             'why=' + (One-Line $Why) + "`n" +
             'detail=' + (One-Line $Detail) + "`n" +
             "---`n" + $Text + "`nENDOFBRIDGE`n")
    [IO.File]::WriteAllText($OutFile + '.tmp', $body, $u8)
    Move-Item -LiteralPath ($OutFile + '.tmp') -Destination $OutFile -Force
}

try {
    . (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
    $lines = @([IO.File]::ReadAllLines($InFile, (New-Object Text.UTF8Encoding($false))))
    if (@($lines | Where-Object { $_ -match '\S' }).Count -eq 0) {
        Write-Bridge $false 'the launcher sent no commands' '' ''
        exit 2
    }
    $r = Invoke-SdViaSeat -Commands $lines -TimeoutSec $TimeoutSec -Internal:$Internal
    if (-not $r.Ok) {
        Write-Bridge $false $r.Why $r.Detail ''
        exit 2
    }
    Write-Bridge $true '' $r.Detail ([string]$r.Text)
    exit 0
} catch {
    try { Write-Bridge $false ('the seat bridge failed: ' + $_.Exception.Message) '' '' } catch { }
    exit 2
}
