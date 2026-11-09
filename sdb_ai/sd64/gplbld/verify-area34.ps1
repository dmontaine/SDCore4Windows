<#
.SYNOPSIS
    The behaviour carried from Linux in catch-up areas 3 and 4 and set.batch (RELEASE_1.1 197, 200), on the installed SD.

.DESCRIPTION
    TWO HALVES, BECAUSE ONE PROCESS CANNOT BE BOTH.
      -Half User    AN ORDINARY UNELEVATED PROMPT, in the caller's own account:
                    set.batch refused; ENCRYPT.KEY's 12-character floor; a bare SH; a
                    $ common in a hand-made object; DELETE.FILE over a planted junction.
      -Half Admin   ELEVATED, with SDSYS signed in (the seat, sdsys-seat.ps1):
                    GETLOCKS with user numbers nobody holds; set.batch's whole round;
                    a system program may still use a $ common.

    EVERY CHECK HAS ITS CONTROL OR ITS PRECONDITION, AND THE RAW OUTPUT IS PRINTED.
    Anchors are the words SD prints only on that path.  A setup that did not happen
    is exit 2, not a pass: the planted junction is proved reachable before the delete.

    NOT HERE: the API DELETE.FILE refusal (7c910a16) needs an API client session.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 it could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\verify-area34.ps1 -Half User
#>

[CmdletBinding()]
param(
    [ValidateSet('', 'User', 'Admin')] [string]$Half = '',
    [string]$Account = $env:USERNAME,
    [int]$TimeoutSeconds = 60
)

$ErrorActionPreference = 'Stop'
$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$Root   = Join-Path $env:ProgramData 'SD\user_accounts'
$SdSys  = Join-Path $env:ProgramData 'SD\sdsys'
$acct   = $Account.ToLower()
$acctDir = Join-Path $Root $acct

$script:pass = 0
$script:fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Output "  [PASS] $name" }
    else     { $script:fail++; Write-Output "  [FAIL] $name"; Write-Output "         $detail" }
}
function Bail([int]$code, [string]$why) {
    Write-Output ''
    Write-Output ("verify-area34: " + @('PASSED', 'FAILED', 'COULD NOT RUN')[$code] + " - $why")
    exit $code
}
function Show([string]$label, [string]$text) {
    Write-Output "  --- $label said: ---"
    foreach ($l in ($text -split "`r?`n")) { if ($l -match '\S') { Write-Output ("  | " + $l) } }
}
function Put-Source([string]$dir, [string]$name, [string]$src) {
    [IO.File]::WriteAllText((Join-Path $dir $name), ($src -replace "`r`n", "`n"), [Text.Encoding]::GetEncoding('iso-8859-1'))
}
function Remove-Named([string]$dir, [string[]]$names) {
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -File -ErrorAction SilentlyContinue | Where-Object { $names -icontains $_.Name })) {
        Remove-Item -LiteralPath $f.FullName -Force -ErrorAction SilentlyContinue
    }
}

if ($Half -eq '') { Write-Output 'verify-area34: refusing - say -Half User (unelevated) or -Half Admin (elevated, SDSYS signed in).'; exit 2 }

Write-Output "verify-area34: half $Half, account $acct"
Write-Output "verify-area34: sd.exe $sdExe"
Write-Output '--- assert-current ---'
& (Join-Path $Gplbld 'assert-current.ps1') | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }
if (-not (Test-Path -LiteralPath $sdExe)) { Bail 2 "no sd.exe at $sdExe" }
Write-Output ''

# ----------------------------------------------------------------------------------------------------------------
if ($Half -eq 'User') {

    # The session is bounded by a job.  A session that outstays it loses its stdin and ends; nothing is killed by name or pid.
    function Invoke-SD([string[]]$lines) {
        $body = "`n" + ((@('TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"
        $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe 2>&1 } -ArgumentList $sdExe, $body
        $late = $false
        if (-not (Wait-Job $job -Timeout $TimeoutSeconds)) { $late = $true; Stop-Job $job -ErrorAction SilentlyContinue }
        $out = @(Receive-Job $job -ErrorAction SilentlyContinue)
        Remove-Job $job -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Text = (($out | Out-String) -replace ([char]27 + '\[[0-9;?]*[A-Za-z]'), ''); Late = $late }
    }

    $bp = Join-Path $acctDir 'bp'
    $bpo = Join-Path $acctDir 'bp.out'
    if (-not (Test-Path -LiteralPath $bp)) { Bail 2 "no bp directory at $bp" }
    $who = Invoke-SD @('WHO')
    if ($who.Text -notmatch ('(?i)\b\d+\s+' + [regex]::Escape($acct) + '\b')) { Show 'WHO' $who.Text; Bail 2 "the session did not land in account $acct." }
    if ($who.Text -match '(?i)\bSDSYS\b') { Bail 2 'this half must run unelevated in an ordinary account.' }

    Write-Output '=== 1. set.batch is the administrator''s ==='
    $r = Invoke-SD @('SET.BATCH')
    Show 'SET.BATCH' $r.Text
    # The verb is in SDSYS's VOC only, so an ordinary account does not have it; 2001 is the second wall, for a VOC that did.
    Row 'an ordinary session cannot run it' ($r.Text -match 'SET\.BATCH is not in your VOC|Command requires administrator privileges') 'neither refusal was printed'
    Row 'and sees no list' ($r.Text -notmatch 'may run from the command line') 'it printed a list'
    Write-Output ''

    Write-Output '=== 2. ENCRYPT.KEY SET has a 12-character floor ==='
    $salt = 'AAAAAAAAAAAAAAAAAAAAAA=='        # 16 zero bytes in base64: the shape sdsalt() makes
    $r = Invoke-SD @("ENCRYPT.KEY SET zzk34 $salt", 'short12345', 'ENCRYPT.KEY LIST')
    Show 'a 10-character passphrase' $r.Text
    Row 'a 10-character passphrase is refused, naming 12' ($r.Text -match 'fewer than 12 characters') 'no 12999 wording'
    Row 'and no key was set' ($r.Text -notmatch 'Key zzk34 is set') 'it set the key'
    $r = Invoke-SD @("ENCRYPT.KEY SET zzk34 $salt", 'a-long-enough-passphrase', 'ENCRYPT.KEY LIST', 'ENCRYPT.KEY CLEAR zzk34')
    Show 'CONTROL, a long passphrase' $r.Text
    Row 'CONTROL: a long passphrase sets the key' ($r.Text -match 'Key zzk34 is set') 'no 12710 wording'
    Row 'CONTROL: and it is on the ring' ($r.Text -match 'zzk34\s+key id') 'LIST does not show it'
    Write-Output ''

    Write-Output '=== 3. SH with no command starts a shell ==='
    $r = Invoke-SD @('SH echo ZZSHCTL34', 'WHO')
    Show 'CONTROL, SH with a command' $r.Text
    $ctlOk = $r.Text -match '(?m)^\s*ZZSHCTL34\s*$'
    Row 'CONTROL: SH with a command runs (this account has the shell)' $ctlOk 'the shell gate or the command did not run, so a bare SH proves nothing'
    if ($ctlOk) {
        # Nothing follows exit: the shell reads ahead on the pipe and would swallow it.  The prompt coming back is the proof SD went on.
        $r = Invoke-SD @('SH', 'echo ZZSHBARE34', 'exit')
        Show 'a bare SH' $r.Text
        Row 'the session did not outstay its limit' (-not $r.Late) "over ${TimeoutSeconds}s"
        Row 'not refused as an empty command (5240)' ($r.Text -notmatch 'Error \d+ executing operating system command') 'the filter refused it'
        Row 'the shell ran what it was given' ($r.Text -match '(?m)^\s*ZZSHBARE34\s*$') 'the line was not run by a shell'
        Row 'SD''s prompt came back after the shell' ($r.Text -match '(?s)ZZSHBARE34.*exit.*(?m:^\s*:\s*$)') 'no : prompt after exit'
    }
    Write-Output ''

    Write-Output '=== 4. a $ common in an object that is not internal ==='
    # The hand-made object is one the ADMIN half compiled as $internal and copied here: run by an ordinary session, load_object gives it no internal status.
    $names = @('ZZCM34', 'ZZCT34', 'ZZHM34')
    try {
        Put-Source $bp 'ZZCT34' "program zzct34`ncommon /zzc34/ a`na = 1`ncrt 'CM34=CTL'`nend`n"
        Put-Source $bp 'ZZCM34' "`$internal`nprogram zzcm34`ncommon /`$zzc34/ a`na = 1`ncrt 'CM34=RAN'`nend`n"
        $c = Invoke-SD @('BASIC bp ZZCT34', 'RUN bp ZZCT34')
        Show 'CONTROL, an ordinary named common' $c.Text
        Row 'CONTROL: an ordinary named common is untouched' ($c.Text -match '(?m)^\s*CM34=CTL\s*$') 'the control did not run'
        $m = Invoke-SD @('BASIC bp ZZCM34')
        Show 'the same common compiled by this account' $m.Text
        Row 'the compiler refuses $internal here' ($m.Text -match 'Compiled 1 program\(s\) with errors') 'it compiled, so the compiler wall is gone'
        if (-not (Test-Path -LiteralPath (Join-Path $bpo 'ZZHM34'))) {
            Row 'the hand-made object is here (run -Half Admin first)' $false "no $bpo\ZZHM34"
        } else {
            $h = Invoke-SD @('RUN bp ZZHM34')
            Show 'the administrator-compiled object, run here' $h.Text
            Row 'the kernel refuses it (12603)' ($h.Text -match 'belongs to the system') 'no 12603 wording'
            Row 'and the program did not run' ($h.Text -notmatch '(?m)^\s*CM34=RAN\s*$') 'it ran'
        }
    } finally {
        Remove-Named $bp $names; Remove-Named $bpo $names
    }
    Write-Output ''

    Write-Output '=== 5. DELETE.FILE does not walk through a planted junction ==='
    $victim = Join-Path $env:LOCALAPPDATA 'SD-verify\dl34-victim'
    $dir = Join-Path $acctDir 'zzdl34'
    $lnk = Join-Path $dir 'lnk'
    $null = New-Item -ItemType Directory -Path $victim -Force
    $precious = Join-Path $victim 'precious.txt'
    [IO.File]::WriteAllText($precious, 'keep me')
    try {
        $mk = Invoke-SD @('CREATE.FILE ZZDL34')
        if (-not (Test-Path -LiteralPath $dir)) { Show 'CREATE.FILE' $mk.Text; Bail 2 "CREATE.FILE made no directory at $dir" }
        $o = & cmd /c mklink /J "$lnk" "$victim" 2>&1
        Write-Output ("  mklink: " + ($o -join ' '))
        if (-not (Test-Path -LiteralPath (Join-Path $lnk 'precious.txt'))) { Bail 2 'the junction does not reach the victim, so a delete would prove nothing.' }
        Write-Output '  setup: the victim is reachable through the junction inside the file'
        $d = Invoke-SD @('DELETE.FILE ZZDL34')
        Show 'DELETE.FILE' $d.Text
        Row 'the file was deleted' ($d.Text -match "VOC entry 'zzdl34' deleted") 'no 6144 wording'
        Row 'the directory is gone' (-not (Test-Path -LiteralPath $dir)) "$dir is still there"
        Row 'THE ROW: the file behind the junction survives' (Test-Path -LiteralPath $precious) "$precious was deleted through the link"
    } finally {
        if (Test-Path -LiteralPath $lnk) { & cmd /c rmdir "$lnk" 2>&1 | Out-Null }     # rmdir without /s takes the junction only
        $null = Invoke-SD @('DELETE.FILE zzdl34')
        Remove-Item -LiteralPath $precious -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $victim -Force -ErrorAction SilentlyContinue
    }
    Write-Output ''
}

# ----------------------------------------------------------------------------------------------------------------
if ($Half -eq 'Admin') {
    . (Join-Path $Gplbld 'sdsys-seat.ps1')
    function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 180) { return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec) }
    # $internal is honoured only in an internal-mode session, as well as SDSYS (bcomp, "INTERNAL").
    function Invoke-SDInternal([string[]]$commands, [int]$TimeoutSec = 180) { return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec -Internal) }
    Assert-SdSeat -Label 'verify-area34'
    Assert-SdSeat -Label 'verify-area34' -Internal

    $bp = Join-Path $SdSys 'bp'
    $bpo = Join-Path $SdSys 'bp.out'
    $names = @('ZZGU34', 'ZZPA34', 'ZZPD34', 'ZZCM34')
    $vocPath = (Join-Path $acctDir 'voc') -replace '\\', '/'
    if (-not (Test-Path -LiteralPath $bp)) { Bail 2 "no bp directory at $bp" }
    $jobRec = Join-Path (Join-Path $SdSys 'batch.jobs') $acct
    $saved = $null
    if (Test-Path -LiteralPath $jobRec) { $saved = [IO.File]::ReadAllBytes($jobRec) }

    try {
        Write-Output '=== 6. GETLOCKS with a user number nobody holds ==='
        Put-Source $bp 'ZZGU34' @'
$internal
program zzgu34
   hi = system(1053)
   nos = @userno:@fm:'12345':@fm:(hi + 1):@fm:'65537':@fm:'-5'
   for k = 1 to dcount(nos, @fm)
      l = getlocks('', nos<k>)
      crt 'ZZGU ' : k : ' n=' : dcount(l, @fm) : ' c=' : dcount(l<1>, @vm)
   next k
   crt 'ZZGU end'
end
'@
        $t = Invoke-SDInternal @('BASIC bp ZZGU34', 'RUN bp ZZGU34')
        Show 'ZZGU34' $t
        Row 'CONTROL: the session''s own number gives the three counters' ($t -match '(?m)^\s*ZZGU 1 n=\d+ c=3\s*$') 'no counters for the control'
        foreach ($k in 2..5) {
            Row "user number case $k answers with the counters and no lock line" ($t -match "(?m)^\s*ZZGU $k n=1 c=3\s*$") "no line ZZGU $k n=1 c=3"
        }
        Row 'the program reached its last line (no fault)' ($t -match '(?m)^\s*ZZGU end\s*$') 'it stopped early'
        Write-Output ''

        Write-Output '=== 7. a system program may still use a $ common ==='
        Put-Source $bp 'ZZCM34' "`$internal`nprogram zzcm34`ncommon /`$zzc34/ a`na = 1`ncrt 'CM34=RAN'`nend`n"
        $t = Invoke-SDInternal @('BASIC bp ZZCM34', 'RUN bp ZZCM34')
        Show 'ZZCM34 as the administrator' $t
        Row 'CONTROL: compiled by the administrator it runs' ($t -match '(?m)^\s*CM34=RAN\s*$') 'a system program was refused'
        $obj = @(Get-ChildItem -LiteralPath $bpo -File | Where-Object { $_.Name -ieq 'ZZCM34' })
        if ($obj.Count -ne 1) { Bail 2 'the administrator''s compile left no object to hand to the User half.' }
        Copy-Item -LiteralPath $obj[0].FullName -Destination (Join-Path (Join-Path $acctDir 'bp.out') 'ZZHM34') -Force
        Write-Output '  setup: object copied to the account as ZZHM34 for the User half'
        Write-Output ''

        Write-Output '=== 8. the set.batch round ==='
        Put-Source $bp 'ZZPA34' @"
`$internal
program zzpa34
   openpath '$vocPath' to f else stop 'PA=NOOPEN'
   write 'PA':@fm:'WHO' to f, 'zzpa34' on error stop 'PA=NOWRITE'
   crt 'PA=OK'
end
"@
        Put-Source $bp 'ZZPD34' @"
`$internal
program zzpd34
   openpath '$vocPath' to f else stop 'PD=NOOPEN'
   delete f, 'zzpa34'
   crt 'PD=OK'
end
"@
        $t = Invoke-SDInternal @('BASIC bp ZZPA34', 'RUN bp ZZPA34')
        if ($t -notmatch '(?m)^\s*PA=OK\s*$') { Show 'ZZPA34' $t; Bail 2 "the paragraph could not be planted in $vocPath" }
        Write-Output '  setup: paragraph zzpa34 is in the account''s VOC'

        $t = Invoke-SD @("SET.BATCH add $acct zzpa34")
        Show 'add' $t
        Row 'add says so (12492)' ($t -match "zzpa34 may now be run from the command line in account $acct") 'no 12492 wording'
        Row 'the record holds it' ((Test-Path -LiteralPath $jobRec) -and ([IO.File]::ReadAllText($jobRec) -match 'zzpa34')) "$jobRec has no zzpa34"
        $t = Invoke-SD @('SET.BATCH')
        Show 'list' $t
        Row 'the list shows it (12803)' ($t -match "Account $acct may run from the command line:.*zzpa34") 'no 12803 line'
        $t = Invoke-SD @("SET.BATCH add $acct zzpa34")
        Row 'adding it again changes nothing (12494)' ($t -match 'was already allowed') 'no 12494 wording'
        $t = Invoke-SD @("SET.BATCH add $acct zznosuch34")
        Row 'a name not in the VOC is refused (12491)' ($t -match 'is not a paragraph or a sentence') 'no 12491 wording'
        $t = Invoke-SD @('SET.BATCH add sdsys zzpa34')
        Row 'sdsys has no list (12490)' ($t -match 'it has no list') 'no 12490 wording'
        $t = Invoke-SD @("SET.BATCH remove $acct zzpa34")
        Row 'remove says so (12493)' ($t -match 'may no longer be run from the command line') 'no 12493 wording'
        $t = Invoke-SD @("SET.BATCH remove $acct zzpa34")
        Row 'removing it again changes nothing (12801)' ($t -match 'was not allowed') 'no 12801 wording'
        Write-Output ''
    } finally {
        try { $null = Invoke-SDInternal @('BASIC bp ZZPD34', 'RUN bp ZZPD34') } catch { Write-Output ("  cleanup: " + $_.Exception.Message) }
        if ($null -ne $saved) { [IO.File]::WriteAllBytes($jobRec, $saved) }
        elseif (Test-Path -LiteralPath $jobRec) { Remove-Item -LiteralPath $jobRec -Force -ErrorAction SilentlyContinue }
        Remove-Named $bp $names; Remove-Named $bpo $names
    }
}

Write-Output "verify-area34: $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { Bail 1 "$script:fail check(s) failed." }
if ($script:pass -eq 0) { Bail 2 'no check ran.' }
Bail 0 "all $script:pass checks of the $Half half passed."
