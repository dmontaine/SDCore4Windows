# probe-auditlower.ps1 - do the audited account verbs write their words in LOWER case?
#
# RUN IT ELEVATED, on a machine where SDSYS is signed in (the seat, sdsys-seat.ps1).
# READ-MOSTLY HARNESS FOR ONE QUESTION.  The owner ruled on 7 Oct 2026 that every word
# before the first '=' of an audit line is lower case.  The 8 Oct 13:05 cycle showed three
# real lines (internal session admitted, login, create.account); the verb lines had only
# ever been seen from the UPPER-case build.  This runs each audited verb once, on
# throwaway names, and judges the lines it caused.
#
# WHAT IT DOES, in order (every step prints the commands it sent and what SD said):
#   1. refuses unless elevated, the seat answers WHO as SDSYS, and neither throwaway
#      name exists (Windows user, group, account directory);
#   2. remembers: the audit line count, sd.conf byte for byte, the saved backup directory;
#   3. GROUP account ZZAUDG: create, backup, delete, restore, delete;
#   4. USER account ZZAUDU (BOTH): create, suspended, unsuspended, none, ssh, sh-on,
#      sh-off, os-on, os-off, delete;
#   5. puts back what it moved: removes any Windows user / group / os.users record /
#      backup file the run made, restores sd.conf byte for byte if it changed;
#   6. reads the NEW audit lines and judges them.
#
# WHAT IT DOES NOT TOUCH: DON, SDSYS, any other account, REMOTE.API, REMOTE.SSH, the
# firewall, services.  The word "judges" means: each expected line must exist with
# its words (everything before the first '=') exactly lower case, checked
# CASE-SENSITIVELY, and no new line may carry an upper-case letter before its first '='.
#
# EXIT: 0 every row found and no upper-case word; 1 a row missing or an upper-case word
# seen (the lines are printed either way); 2 it could not run (not elevated, no seat,
# a throwaway name already in use, no new audit lines at all - the null case).
#
# THE TRANSCRIPT IS THE EVIDENCE: %LOCALAPPDATA%\SD-verify\probe-auditlower-<time>.log.
# If a run dies half way: DELETE.ACCOUNT ZZAUDU and DELETE.ACCOUNT ZZAUDG from the SDSYS
# seat (or Remove-LocalUser ZZAUDU; Remove-LocalGroup sdu_ZZAUDU), then run it again.

$ErrorActionPreference = 'Stop'

$here   = Split-Path -Parent $MyInvocation.MyCommand.Path
$seat   = Join-Path $here 'sdsys-seat.ps1'
$bakCmd = Join-Path $here 'sd-backupdir.ps1'
$data   = Join-Path $env:ProgramData 'SD'
$audit  = Join-Path $data 'sdsys\audit'
$osu    = Join-Path $data 'sdsys\os.users'
$conf   = Join-Path $data 'sd.conf'
$gAcct  = 'ZZAUDG'
$uAcct  = 'ZZAUDU'
$ourBak = Join-Path $data 'probe-auditlower-bak'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
$logFile = Join-Path $logDir ('probe-auditlower-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
Start-Transcript -LiteralPath $logFile | Out-Null

$script:seatFailed = 0
$script:lastText   = ''
$script:pw         = ''

function Exit-Probe([int]$code) {
    try { Stop-Transcript | Out-Null } catch { }
    exit $code
}

# Prints; returns nothing (a function that prints AND returns folds its lines into the
# return value - ps-function-output-trap).  The text of the answer is left in $script:lastText.
function Step([string]$Title, [string[]]$Cmds, [int]$To = 300) {
    Write-Output ''
    Write-Output ('=== ' + $Title)
    $shown = ($Cmds | ForEach-Object { if ($script:pw -ne '' -and $_ -ceq $script:pw) { '<password>' } else { $_ } }) -join ' | '
    Write-Output ('    commands sent: ' + $shown)
    $script:lastText = ''
    $r = Invoke-SdViaSeat -Commands $Cmds -TimeoutSec $To
    Write-Output ('    seat Ok = ' + $r.Ok)
    if (-not $r.Ok) {
        $script:seatFailed++
        Write-Output ('    seat Why = ' + $r.Why)
        return
    }
    $t = [string]$r.Text
    if ($script:pw -ne '') { $t = $t.Replace($script:pw, '<password>') }
    $script:lastText = $t
    ($t -split "`r?`n" | Where-Object { $_ -match '\S' }) | ForEach-Object { Write-Output ('    | ' + $_.TrimEnd()) }
}

try {
    Write-Output ('probe-auditlower  now      : ' + (Get-Date -Format 's'))
    Write-Output ('                  script   : ' + $MyInvocation.MyCommand.Path)
    Write-Output ('                  transcript: ' + $logFile)
    Write-Output ('                  seat     : ' + $seat + '  exists: ' + (Test-Path -LiteralPath $seat))
    Write-Output ('                  audit    : ' + $audit + '  exists: ' + (Test-Path -LiteralPath $audit))
    Write-Output ('                  sd.conf  : ' + $conf + '  exists: ' + (Test-Path -LiteralPath $conf))
    Write-Output ('                  names    : group account ' + $gAcct + ', user account ' + $uAcct)

    $elevated = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    Write-Output ('                  elevated : ' + $elevated)
    if (-not $elevated) { Write-Output 'REFUSED: not elevated - the seat and the audit file both need an elevated token.'; Exit-Probe 2 }
    foreach ($f in $seat, $bakCmd, $audit, $conf) {
        if (-not (Test-Path -LiteralPath $f)) { Write-Output ('REFUSED: missing ' + $f); Exit-Probe 2 }
    }

    # The throwaway names must be free everywhere, or a "create" would be a refusal that
    # looks like a missing audit line.
    $busy = @()
    if (Get-LocalUser  -Name $uAcct -ErrorAction SilentlyContinue)            { $busy += ('Windows user ' + $uAcct) }
    if (Get-LocalGroup -Name ('sdu_' + $uAcct) -ErrorAction SilentlyContinue) { $busy += ('group sdu_' + $uAcct) }
    if (Get-LocalGroup -Name ('sdg_' + $gAcct) -ErrorAction SilentlyContinue) { $busy += ('group sdg_' + $gAcct) }
    foreach ($d in (Join-Path $data ('user_accounts\' + $uAcct)), (Join-Path $data ('group_accounts\' + $gAcct)), $ourBak) {
        if (Test-Path -LiteralPath $d) { $busy += $d }
    }
    if ($busy.Count -gt 0) { Write-Output ('REFUSED: already present - ' + ($busy -join '; ')); Exit-Probe 2 }

    . (Join-Path $PSScriptRoot 'sdsys-seat.ps1')
    $who =Invoke-SdViaSeat -Commands @('WHO')
    Write-Output ('seat proof        : Ok=' + $who.Ok + '  ' + $who.Detail)
    if ($who.Ok) { ($who.Text -split "`r?`n" | Where-Object { $_ -match '\S' }) | ForEach-Object { Write-Output ('    | ' + $_.Trim()) } }
    if (-not $who.Ok -or $who.Text -match 'restricted to privileged users' -or $who.Text -notmatch '(?m)^\s*\d+\s+SDSYS\b') {
        Write-Output 'REFUSED: SD did not answer WHO as SDSYS, so nothing below would be an SDSYS verb.'
        Exit-Probe 2
    }

    # ---- what to put back --------------------------------------------------
    $before    = @(Get-Content -LiteralPath $audit).Count
    $confBytes = [IO.File]::ReadAllBytes($conf)
    $confHash  = (Get-FileHash -LiteralPath $conf -Algorithm SHA256).Hash
    Write-Output ('audit lines before: ' + $before)
    Write-Output ('sd.conf sha256    : ' + $confHash + '  (' + $confBytes.Length + ' bytes)')

    $g = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bakCmd -Mode Get) -join "`n"
    Write-Output ('saved backup dir  : ' + (($g -split "`n" | Where-Object { $_ -match 'GET ' }) -join ' / '))
    $ours = $false
    if ($g -match 'GET NONE') {
        $s = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bakCmd -Mode Set -Path $ourBak) -join "`n"
        Write-Output ('set backup dir    : ' + (($s -split "`n" | Where-Object { $_ -match 'SET |ERROR' }) -join ' / '))
        if ($s -notmatch 'SET OK') { Write-Output 'REFUSED: could not save a backup directory.'; Exit-Probe 2 }
        $ours = $true; $bakDir = $ourBak
    } elseif ($g -match 'GET OK (.+)') {
        $bakDir = $Matches[1].Trim()
    } else {
        Write-Output 'REFUSED: could not read the saved backup directory.'; Exit-Probe 2
    }
    $bakBefore = @(Get-ChildItem -LiteralPath $bakDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })

    # ---- the verbs ---------------------------------------------------------
    Step 'GROUP account: create'  @("CREATE.ACCOUNT GROUP $gAcct")
    Step 'GROUP account: backup'  @("BACKUP.ACCOUNT $gAcct") 300
    Step 'GROUP account: delete'  @("DELETE.ACCOUNT $gAcct", 'Y', 'SDDELSENTINEL', 'Y', 'Y')
    Step 'GROUP account: restore' @("RESTORE.ACCOUNT LATEST $gAcct NO.QUERY") 300
    Step 'GROUP account: delete (cleanup)' @("DELETE.ACCOUNT $gAcct", 'Y', 'SDDELSENTINEL', 'Y', 'Y')

    # 20 random characters from the alphabet verify-createaccount uses, plus a suffix that
    # satisfies Windows' complexity rule.  It goes down a pipe and is shown as <password>.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 20
    ([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $script:pw = (-join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })) + '-Aa9'

    Step 'USER account: create'      @("CREATE.ACCOUNT USER $uAcct BOTH", $script:pw, $script:pw)
    Step 'USER account: suspended'   @("MODIFY.ACCOUNT $uAcct SUSPENDED")
    Step 'USER account: unsuspended' @("MODIFY.ACCOUNT $uAcct UNSUSPENDED")
    Step 'USER account: route none'  @("MODIFY.ACCOUNT $uAcct NONE")
    Step 'USER account: route ssh'   @("MODIFY.ACCOUNT $uAcct SSH")
    Step 'USER account: sh-on'       @("MODIFY.ACCOUNT $uAcct SH-ON")
    Step 'USER account: sh-off'      @("MODIFY.ACCOUNT $uAcct SH-OFF")
    Step 'USER account: os-on'       @("MODIFY.ACCOUNT $uAcct OS-ON")
    Step 'USER account: os-off'      @("MODIFY.ACCOUNT $uAcct OS-OFF")
    Step 'USER account: delete'      @("DELETE.ACCOUNT $uAcct", 'Y', 'SDDELSENTINEL', 'Y', 'Y')

    # ---- put back what this run moved -------------------------------------
    Write-Output ''
    Write-Output '=== putting back'
    if (Get-LocalUser -Name $uAcct -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $uAcct; Write-Output ('    WARNING: Windows user ' + $uAcct + ' was still there; removed')
    } else { Write-Output ('    Windows user ' + $uAcct + ': gone') }
    foreach ($gn in ('sdu_' + $uAcct), ('sdg_' + $gAcct)) {
        if (Get-LocalGroup -Name $gn -ErrorAction SilentlyContinue) {
            Remove-LocalGroup -Name $gn; Write-Output ('    WARNING: group ' + $gn + ' was still there; removed')
        } else { Write-Output ('    group ' + $gn + ': gone') }
    }
    foreach ($rec in @(Get-ChildItem -LiteralPath $osu -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ieq $uAcct })) {
        Remove-Item -LiteralPath $rec.FullName -Force; Write-Output ('    removed the os.users record this run made: ' + $rec.Name)
    }
    $bakAfter = @(Get-ChildItem -LiteralPath $bakDir -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object { $_.FullName })
    foreach ($nf in @($bakAfter | Where-Object { $bakBefore -notcontains $_ })) {
        Write-Output ('    backup file this run made: ' + $nf)
        if (-not $ours) { Remove-Item -LiteralPath $nf -Force; Write-Output '      removed (it was in a directory that was already saved)' }
    }
    if ($ours -and (Test-Path -LiteralPath $ourBak)) { Remove-Item -LiteralPath $ourBak -Recurse -Force; Write-Output ('    removed the backup directory this run made: ' + $ourBak) }
    $confNow = (Get-FileHash -LiteralPath $conf -Algorithm SHA256).Hash
    if ($confNow -ne $confHash) {
        [IO.File]::WriteAllBytes($conf, $confBytes)
        $confBack = (Get-FileHash -LiteralPath $conf -Algorithm SHA256).Hash
        Write-Output ('    sd.conf changed during the run; written back byte for byte, sha256 now ' + $confBack + '  (matches the start: ' + ($confBack -eq $confHash) + ')')
    } else { Write-Output '    sd.conf: unchanged' }

    # ---- judge the audit lines --------------------------------------------
    Write-Output ''
    Write-Output '=== the audit file'
    $all = @(Get-Content -LiteralPath $audit)
    $new = @($all | Select-Object -Skip $before)
    Write-Output ('audit lines after : ' + $all.Count + '   (' + $new.Count + ' new)')
    if ($new.Count -eq 0) { Write-Output 'REFUSED: NO NEW AUDIT LINES - nothing below can be judged.'; Exit-Probe 2 }
    if ($script:seatFailed -gt 0) { Write-Output ('NOTE: ' + $script:seatFailed + ' seat call(s) did not run; rows that depend on them will be missing.') }
    Write-Output '--- every new line, as written:'
    $new | ForEach-Object { Write-Output ('    ' + $_.Trim()) }

    # text after the "<date> <time> user=.. uid=.. pid=.. " prefix the kernel writes
    $texts = @($new | ForEach-Object { if ($_ -match '^\S+ \S+ user=\S+ uid=\d+ pid=\d+ (.*)$') { $Matches[1] } else { $_ } })

    $rows = @(
        @{ Name = 'create.account (group)';   Words = 'create\.account account';             Acct = $gAcct; Min = 1 },
        @{ Name = 'create.account (user)';    Words = 'create\.account account';             Acct = $uAcct; Min = 1 },
        @{ Name = 'restore.account';          Words = 'restore\.account account';            Acct = $gAcct; Min = 1 },
        @{ Name = 'delete.account (group x2)';Words = 'delete\.account account';             Acct = $gAcct; Min = 2 },
        @{ Name = 'delete.account (user)';    Words = 'delete\.account account';             Acct = $uAcct; Min = 1 },
        @{ Name = 'modify.account suspend';   Words = 'modify\.account suspend account';     Acct = $uAcct; Min = 1 },
        @{ Name = 'modify.account unsuspended';Words = 'modify\.account unsuspended account'; Acct = $uAcct; Min = 1 },
        @{ Name = 'modify.account route none';Words = 'modify\.account route none account';  Acct = $uAcct; Min = 1 },
        @{ Name = 'modify.account route ssh'; Words = 'modify\.account route ssh account';   Acct = $uAcct; Min = 1 },
        @{ Name = 'modify.account os.users (4)'; Words = 'modify\.account os\.users account'; Acct = $uAcct; Min = 4 }
    )
    Write-Output ''
    Write-Output '--- rows (words checked CASE-SENSITIVELY, account name without regard to case):'
    $bad = 0
    foreach ($row in $rows) {
        $n = @($texts | Where-Object { ($_ -cmatch ('^' + $row.Words + '=')) -and ($_ -match ('(?i)account=' + $row.Acct + '\b')) }).Count
        $verdict = if ($n -ge $row.Min) { 'ok' } else { 'MISSING'; }
        if ($n -lt $row.Min) { $bad++ }
        Write-Output ('    {0,-30} found {1} (need {2})  {3}' -f $row.Name, $n, $row.Min, $verdict)
    }
    $upper = @($texts | Where-Object { $_.Contains('=') -and ($_.Substring(0, $_.IndexOf('=')) -cmatch '[A-Z]') })
    Write-Output ('    new lines with an upper-case letter before the first "=": {0} (need 0)' -f $upper.Count)
    $upper | ForEach-Object { Write-Output ('      UPPER: ' + $_) }
    if ($upper.Count -gt 0) { $bad++ }

    Write-Output ''
    if ($bad -eq 0) { Write-Output 'VERDICT: every audited verb wrote its words in lower case.'; Exit-Probe 0 }
    Write-Output ('VERDICT: ' + $bad + ' problem(s) above - read the lines, they are printed in full.')
    Exit-Probe 1
}
catch {
    Write-Output ('probe-auditlower: DIED - ' + $_.Exception.Message)
    Write-Output ($_.ScriptStackTrace)
    Write-Output 'Leftovers, if any: DELETE.ACCOUNT ZZAUDU / ZZAUDG from the SDSYS seat; Remove-LocalUser ZZAUDU; sd.conf may hold a backup-dir line (see the sha256 above).'
    Exit-Probe 2
}
