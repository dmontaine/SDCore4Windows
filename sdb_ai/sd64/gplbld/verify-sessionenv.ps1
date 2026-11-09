<#
.SYNOPSIS
    Does an ssh session and an API session see ITS OWN USER'S environment?  (RELEASE_1.1 196, OpenQM 574.)  ***ELEVATED, SDSYS signed in.***

.DESCRIPTION
    QM's Windows service gave sessions SYSTEM's environment.  SD's service runs as LocalSystem too, so the same question
    is asked here: a throwaway non-administrator account, with both routes, runs one BASIC program over ssh and over the
    API, and the program prints USERNAME, USERPROFILE and TEMP as that session sees them.

    The program is compiled over ssh as the account (its own bp.edit).  Every value is printed.  An answer that never
    arrived is a failed row, not a pass.  The account is removed afterwards; its Windows profile stays until a restart,
    so -Prefix takes a new name each run.

.PARAMETER Prefix
    The throwaway account's name, lower case, not used before.

.OUTPUTS
    Exit 0 every check passed, 1 a check failed, 2 it could not run.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\verify-sessionenv.ps1 -Prefix sdenvb322
#>

[CmdletBinding()]
param(
    [string]$Prefix = '',
    [int]$Port = 4247
)

$ErrorActionPreference = 'Stop'
$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sd64   = Split-Path -Parent $Gplbld
$bash   = 'C:\msys64\usr\bin\bash.exe'

$script:pass = 0
$script:fail = 0
function Row([string]$name, [bool]$ok, [string]$detail) {
    if ($ok) { $script:pass++; Write-Output "  [PASS] $name" }
    else     { $script:fail++; Write-Output "  [FAIL] $name"; Write-Output "         $detail" }
}
function Bail([int]$code, [string]$why) {
    Write-Output ''
    Write-Output ("verify-sessionenv: " + @('PASSED', 'FAILED', 'COULD NOT RUN')[$code] + " - $why")
    exit $code
}

if ($Prefix -notmatch '^[a-z][a-z0-9]{2,15}$') { Bail 2 "-Prefix '$Prefix' must be a new lower-case account name." }
$account = $Prefix
Write-Output "verify-sessionenv: account $account, API port $Port"

& (Join-Path $Gplbld 'assert-current.ps1') | Select-Object -Last 1
if ($LASTEXITCODE -ne 0) { Bail 2 'assert-current refuses - the installed tree does not match source.' }

. (Join-Path $Gplbld 'sdsys-seat.ps1')
. (Join-Path $Gplbld 'sdtestuser.ps1')
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 180) { return (Invoke-SdSeatText -Commands $commands -TimeoutSec $TimeoutSec) }
Assert-SdSeat -Label 'verify-sessionenv'
if (Get-LocalUser -Name $account -ErrorAction SilentlyContinue) { Bail 2 "a Windows account named $account already exists; use a new -Prefix." }

$msys = '/' + $sd64.Substring(0, 1).ToLower() + ($sd64.Substring(2) -replace '\\', '/')
function Invoke-Api([string]$User, [string]$Pw, [string]$Acct, [string]$ApiCmd) {
    $cmd = "cd '$msys' && make check-api-admin APIHOST=127.0.0.1 APIPORT=$Port APIUSER=$User APIPASS='$Pw' APIACCT=$Acct APICMD='$ApiCmd'"
    $prev = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $t = (& $bash -lc $cmd 2>&1 | Out-String); $rc = $LASTEXITCODE } finally { $ErrorActionPreference = $prev }
    return [pscustomobject]@{ Text = ($t -replace '[\xFC-\xFF]', "`n"); Rc = $rc }
}
function Get-Env([string]$text, [string]$name) {
    # Printable ASCII only: the API hands the three lines back joined by a mark, whatever the console's code page makes of it.
    $m = [regex]::Match($text, "ENV:$name=([\x20-\x7E]*)")
    if ($m.Success) { return $m.Groups[1].Value.Trim() }
    return $null
}
function Judge([string]$route, [string]$text) {
    foreach ($v in 'USERNAME', 'USERPROFILE', 'TEMP') { Write-Output ("  {0}: {1} = [{2}]" -f $route, $v, (Get-Env $text $v)) }
    $u = Get-Env $text 'USERNAME'; $p = Get-Env $text 'USERPROFILE'; $t = Get-Env $text 'TEMP'
    Row "$route`: the program answered" ($null -ne $u) 'no ENV: line came back, so nothing was measured'
    Row "$route`: USERNAME is the account's own" ($u -ieq $account) "got [$u]"
    Row "$route`: USERPROFILE is the account's, not SYSTEM's" (($p -match [regex]::Escape($account)) -and ($p -notmatch '(?i)systemprofile')) "got [$p]"
    Row "$route`: TEMP is not the system's" (($null -ne $t) -and ($t -ne '') -and ($t -notmatch '(?i)\\Windows\\(Temp|System32)')) "got [$t]"
}

$password = New-SdTestPassword
$created = $false
try {
    Write-Output '=== 1. a throwaway account with both routes ==='
    $mk = @(New-SdTestUserScript -Name $account -Password $password -Gates 'bp-on')
    $mk[0] = $mk[0] -replace ' SSH', ' BOTH'
    Write-Output ("  " + $mk[0])
    $o = Invoke-SD $mk
    $created = ($null -ne (Get-LocalUser -Name $account -ErrorAction SilentlyContinue))
    if (-not $created) { Write-Output $o; Bail 2 'the account was not created.' }
    $admins = @(Get-LocalGroupMember -Group 'Administrators' | ForEach-Object { ($_.Name -split '\\')[-1].ToLower() })
    Row 'the account is not an administrator' ($admins -notcontains $account) 'it is in Administrators, so the test means nothing'
    $home0 = Get-SdTestUserHome -Name $account
    $bp = Join-Path $home0 'bp'
    if (-not (Test-Path -LiteralPath $bp)) { Bail 2 "no bp at $bp" }

    $src = "program zzenv34`ncrt 'ENV:USERNAME=' : env('USERNAME')`ncrt 'ENV:USERPROFILE=' : env('USERPROFILE')`ncrt 'ENV:TEMP=' : env('TEMP')`nend`n"
    [IO.File]::WriteAllText((Join-Path $bp 'ZZENV34'), $src, [Text.Encoding]::GetEncoding('iso-8859-1'))

    Write-Output ''
    Write-Output '=== 2. over ssh ==='
    $r = Invoke-SdAsTestUser -Name $account -Password $password -Commands @('BASIC bp ZZENV34', 'RUN bp ZZENV34')
    Write-Output ("  ssh exit {0}" -f $r.ExitCode)
    if ($r.Err -ne '') { Write-Output ("  stderr: " + ($r.Err -replace "`r?`n", ' | ')) }
    Write-Output ($r.Out -split "`n" | Where-Object { $_ -match 'ENV:|error|Compiled' })
    Judge 'ssh' $r.Out

    Write-Output ''
    Write-Output '=== 3. over the API ==='
    $a = Invoke-Api $account $password $account.ToUpper() 'RUN bp ZZENV34'
    Write-Output ("  client exit {0}" -f $a.Rc)
    Write-Output ($a.Text -split "`r?`n" | Where-Object { $_ -match 'ENV:|rror|refus|denied' } | ForEach-Object { '  | ' + $_ })
    Judge 'API' $a.Text
} finally {
    if ($created) {
        Write-Output ''
        Write-Output '--- removing the account ---'
        try {
            $null = Invoke-SD @(Remove-SdTestUserScript -Name $account)
            Row 'cleanup: the Windows account is gone' ($null -eq (Get-LocalUser -Name $account -ErrorAction SilentlyContinue)) "$account is still there"
        } catch { Write-Output ("  cleanup failed: " + $_.Exception.Message) }
    }
}

Write-Output ''
Write-Output "verify-sessionenv: $script:pass passed, $script:fail failed"
if ($script:fail -gt 0) { Bail 1 "$script:fail check(s) failed." }
if ($script:pass -eq 0) { Bail 2 'no check ran.' }
Bail 0 'an ssh session and an API session each see their own user''s environment.'
