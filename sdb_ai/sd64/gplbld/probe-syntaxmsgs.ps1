# probe-syntaxmsgs.ps1 - what do SD Core's syntax and usage messages PRINT, in lower case?
#
# RUN IT ELEVATED, with SDSYS signed in (the seat, sdsys-seat.ps1).  PAL-24 stage 2 (8 Oct 2026) lowered the
# command words in messages 13006 and 13016 (BACKUP.ACCOUNT and RESTORE.ACCOUNT syntax) and in the usage
# lines of CREATE.ACCOUNT and MODIFY.ACCOUNT.  This runs each of those verbs once, in a way that only
# PRINTS its syntax (nothing is created, backed up, restored or changed), and judges what came out.
#
# WHAT IT SENDS, each as its own seat call (the raw output is printed and logged):
#   BACKUP.ACCOUNT ALL zzsyntax    -> message 13006 ("ALL" and a name together are refused)
#   RESTORE.ACCOUNT                -> message 13016 (no archive given)
#   CREATE.ACCOUNT                 -> createa's "Command Syntax:" block
#   MODIFY.ACCOUNT                 -> modifya's "Command Syntax:" block (no account named)
#   MODIFY.ACCOUNT SDSYS ZZBADWORD -> modifya's "Action Must Be ..." line (SDSYS is named, nothing is changed)
#
# THE JUDGEMENT is CASE-SENSITIVE on purpose: each expected line must exist in lower case, and no printed
# line may still show the old capitals.  The echo of what was typed starts with ':' and is not judged.
# EXIT: 0 every row found and no capitals; 1 a row missing or a capital seen; 2 it could not run (not
# elevated, no seat, a call that printed nothing).  The transcript is the evidence:
# %LOCALAPPDATA%\SD-verify\probe-syntaxmsgs-<time>.log.

$ErrorActionPreference = 'Stop'

$here  = Split-Path -Parent $MyInvocation.MyCommand.Path
$seat  = Join-Path $here 'sdsys-seat.ps1'
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ('probe-syntaxmsgs-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -LiteralPath $logFile | Out-Null

function Exit-Probe([int]$code) {
    try { Stop-Transcript | Out-Null } catch { }
    exit $code
}

$script:seatFailed = 0
$script:texts = @{}

# Prints; returns nothing (a function that prints AND returns folds its lines into the return value).
function Step([string]$Key, [string]$Cmd) {
    Write-Output ''
    Write-Output ('=== ' + $Key + '    command sent: ' + $Cmd)
    $r = Invoke-SdViaSeat -Commands @($Cmd) -TimeoutSec 120
    Write-Output ('    seat Ok = ' + $r.Ok)
    if (-not $r.Ok) {
        $script:seatFailed++
        Write-Output ('    seat Why = ' + $r.Why)
        $script:texts[$Key] = ''
        return
    }
    $script:texts[$Key] = [string]$r.Text
    ($r.Text -split "`r?`n" | Where-Object { $_ -match '\S' }) | ForEach-Object { Write-Output ('    | ' + $_.TrimEnd()) }
}

try {
    Write-Output ('probe-syntaxmsgs  now   : ' + (Get-Date -Format 's'))
    Write-Output ('                  script: ' + $MyInvocation.MyCommand.Path)
    Write-Output ('                  seat  : ' + $seat + '  exists: ' + (Test-Path -LiteralPath $seat))
    Write-Output ('                  log   : ' + $logFile)
    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Output ('                  elevated: ' + $elevated)
    if (-not $elevated) { Write-Output 'REFUSED: not elevated - the seat needs an elevated token.'; Exit-Probe 2 }
    if (-not (Test-Path -LiteralPath $seat)) { Write-Output ('REFUSED: missing ' + $seat); Exit-Probe 2 }

    . (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
    $who = Invoke-SdViaSeat -Commands @('WHO')
    Write-Output ('seat proof: Ok=' + $who.Ok + '  ' + $who.Detail)
    if (-not $who.Ok -or $who.Text -match 'restricted to privileged users' -or $who.Text -notmatch '(?m)^\s*\d+\s+SDSYS\b') {
        Write-Output 'REFUSED: SD did not answer WHO as SDSYS, so nothing below would be an SDSYS verb.'
        Exit-Probe 2
    }

    Step 'backup' 'BACKUP.ACCOUNT ALL zzsyntax'
    Step 'restore' 'RESTORE.ACCOUNT'
    Step 'create' 'CREATE.ACCOUNT'
    Step 'modify' 'MODIFY.ACCOUNT'
    Step 'modifybad' 'MODIFY.ACCOUNT SDSYS ZZBADWORD'

    Write-Output ''
    Write-Output '=== judging (case-sensitive; echoed commands start with ":" and are skipped)'
    if ($script:seatFailed -gt 0) { Write-Output ('REFUSED: ' + $script:seatFailed + ' seat call(s) did not run'); Exit-Probe 2 }

    $rows = @(
        @{ K = 'backup';    N = '13006 syntax line 1';          Rx = '^Syntax: backup\.account name \[name \.\.\.\] \[to directory\]$' },
        @{ K = 'backup';    N = '13006 syntax line 2';          Rx = '^backup\.account all \[to directory\]$' },
        @{ K = 'backup';    N = '13006 the directory sentence'; Rx = '^Without to, the directory saved by set\.backup\.directory is used\.$' },
        @{ K = 'restore';   N = '13016 archive name form';      Rx = '^Syntax: restore\.account archive name \[name \.\.\.\] \{no\.query\}$' },
        @{ K = 'restore';   N = '13016 archive all form';       Rx = '^restore\.account archive all \{no\.query\}$' },
        @{ K = 'restore';   N = '13016 latest name form';       Rx = '^restore\.account latest name \[name \.\.\.\] \{no\.query\}$' },
        @{ K = 'restore';   N = '13016 latest all form';        Rx = '^restore\.account latest all \{no\.query\}$' },
        @{ K = 'restore';   N = '13016 the latest sentence';    Rx = '^latest uses the newest backup made on this computer that holds the account\.$' },
        @{ K = 'create';    N = 'createa user line';            Rx = '^Command Syntax: create\.account user <user name> \{ssh \| api \| both \| none\}$' },
        @{ K = 'create';    N = 'createa group line';           Rx = '^create\.account group <group name> \{no\.query\}$' },
        @{ K = 'create';    N = 'createa other line';           Rx = '^create\.account other <account name> <pathname> \{no\.query\}$' },
        @{ K = 'modify';    N = 'modifya add|delete line';      Rx = '^Command Syntax:\s+modify\.account <account> add \| delete <username>$' },
        @{ K = 'modify';    N = 'modifya route line';           Rx = '^modify\.account <account> ssh \| api \| both \| none$' },
        @{ K = 'modify';    N = 'modifya sh-on line';           Rx = '^modify\.account <account> sh-on \| sh-off$' },
        @{ K = 'modify';    N = 'modifya os-on line';           Rx = '^modify\.account <account> os-on \| os-off$' },
        @{ K = 'modify';    N = 'modifya suspended line';       Rx = '^modify\.account <account> suspended \| unsuspended$' },
        @{ K = 'modifybad'; N = 'modifya "Action Must Be" line'; Rx = '^modify\.account Action Must Be add, delete, ssh, api, both, none,$' },
        @{ K = 'modifybad'; N = 'modifya its second line';      Rx = '^sh-on, sh-off, os-on, os-off, suspended or unsuspended$' }
    )
    $bad = 0
    foreach ($row in $rows) {
        $lines = @($script:texts[$row.K] -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' -and -not $_.StartsWith(':') })
        $n = @($lines | Where-Object { $_ -cmatch $row.Rx }).Count
        $v = if ($n -eq 1) { 'ok' } else { 'MISSING' }
        if ($n -ne 1) { $bad++ }
        Write-Output ('    {0,-34} found {1} (need 1)  {2}' -f ($row.K + ': ' + $row.N), $n, $v)
    }
    $upper = @()
    foreach ($k in $script:texts.Keys) {
        foreach ($l in ($script:texts[$k] -split "`r?`n")) {
            $s = $l.Trim()
            if ($s -eq '' -or $s.StartsWith(':')) { continue }
            if ($s -cmatch '^(Command Syntax:\s+|Syntax:\s+)?(CREATE|MODIFY|BACKUP|RESTORE|UPDATE)\.ACCOUNTS?\b' -or $s -cmatch '^(LATEST uses|Without TO)' -or $s -cmatch '^\{NO\.QUERY\}') { $upper += ($k + ': ' + $s) }
        }
    }
    Write-Output ('    printed lines that still quote a command in capitals: {0} (need 0)' -f $upper.Count)
    $upper | ForEach-Object { Write-Output ('      UPPER: ' + $_) }
    if ($upper.Count -gt 0) { $bad++ }

    Write-Output ''
    if ($bad -eq 0) { Write-Output 'VERDICT: every syntax and usage line prints in lower case.'; Exit-Probe 0 }
    Write-Output ('VERDICT: ' + $bad + ' problem(s) above - the raw output is printed in full.')
    Exit-Probe 1
}
catch {
    Write-Output ('probe-syntaxmsgs: DIED - ' + $_.Exception.Message)
    Write-Output ($_.ScriptStackTrace)
    Exit-Probe 2
}
