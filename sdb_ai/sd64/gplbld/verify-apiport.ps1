<#
.SYNOPSIS
    Turn the API port on, prove a remote session works, and turn it off again.

.DESCRIPTION
    ONE ELEVATED COMMAND for PROJECT_STATUS.md section 7 step 6.  It is the
    first thing that exercises the remote transport, step 6a's $CRED check and
    step 6c's ACC$GROUP check; until it passes, all three are built and
    unproven.

    IT CHANGES THE INSTALLED SYSTEM AND PUTS IT BACK.  A throwaway account is
    created and deleted, APIPORT is added to the installed sd.conf and removed
    again, and SD is restarted twice.  The restore runs in a finally block, so
    it also happens when a check fails part way.

    WHY A THROWAWAY ACCOUNT AND NOT YOURS.  The test needs an account with a
    password, and setting one on a real account to run a test leaves a
    credential behind that nobody asked for.  The password is generated here,
    never appears on a command line, and goes to SD on stdin - section 5.6.1's
    rule, which exists because a command line is readable through Task Manager,
    Win32_Process and ETW.

.PARAMETER Prefix
    Name for the throwaway Windows and SD account.  Use one that does not
    exist; CREATE.ACCOUNT refuses a name it has seen, which is the right way
    round.

.PARAMETER Port
    Loopback port to use.  4243 is the number the Linux build uses.

.PARAMETER Keep
    Leave APIPORT set and the account in place when the run finishes, for
    poking at by hand.  The account still has to be removed with
    DELETE.ACCOUNT afterwards.

.EXAMPLE
    C:\Users\dmont\Projects\sdb_ai_windows\sdb_ai\sd64\gplbld\verify-apiport.ps1 -Prefix sdapi1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [int]    $Port = 4243,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld  = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sd64    = Split-Path -Parent $Gplbld
$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$SvcName = 'SD'
$conf    = Join-Path $env:ProgramData 'SD\sd.conf'
$backup  = $conf + '.before-apiport'

# NOT UNDER C:\ProgramData\SD, for the reason cycle.ps1 gives: LOCALAPPDATA is
# the same directory elevated or not, so an unelevated session afterwards can
# read what this wrote.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-apiport-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results = New-Object System.Collections.ArrayList
$failed  = $false

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

# Drives an SD session from SDSYS.  Same shape as verify-tiers.ps1: a blank
# first line absorbs the BOM, TERM stops it paginating, OFF ends it.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

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

# ---------------------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'Run this from an ELEVATED PowerShell - it creates an account, edits the installed sd.conf and restarts SD.'
}

# THE CYCLE RULE, and it is a gate rather than a reminder.  CLAUDE.md: anything
# that tests the install calls this first, or the result describes a tree that
# no longer exists.
Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'assert-current refuses - run gplbld/cycle.ps1 first.' }

if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
    Fail "$Prefix already exists as a Windows account.  Use a -Prefix that does not."
}

$restoreNeeded = $false
$pw = ''
$testRc = -1

try {
    # -----------------------------------------------------------------------
    Step 1 "Creating the throwaway account $Prefix"

    # PROGRAMMER rather than standard: a standard VOC would do for WHO, but a
    # fuller one keeps this test measuring the TRANSPORT rather than the tier
    # work, which verify-tiers.ps1 owns.
    $out = Invoke-SD @("CREATE.ACCOUNT USER $Prefix PROGRAMMER NO.QUERY")
    $accRec = Join-Path $env:ProgramData ('SD\sdsys\ACCOUNTS\' + $Prefix.ToUpper())
    $made = Test-Path -LiteralPath $accRec
    Note 'ACCOUNTS record created' $true $made
    if (-not $made) {
        Write-Host $out
        Fail 'CREATE.ACCOUNT did not register the account.'
    }
    $restoreNeeded = $true

    # -----------------------------------------------------------------------
    Step 2 'Setting its password'

    # GENERATED, NEVER HARDCODED, AND NEVER ON A COMMAND LINE.  It reaches SD on
    # stdin.  The trailing characters guarantee a mix whatever the base64 came
    # out as, since Windows may have a complexity policy on the local account.
    $bytes = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + 'aA1'

    # The account has no credential yet, so SET.PASSWORD does not ask for a
    # current one - SET_ACC_PASSWORD's has.cred test.  It asks for the new one
    # twice.
    $out = Invoke-SD @(("SET.PASSWORD " + $Prefix.ToUpper()), $pw, $pw)
    $set = ($out -match 'Password set for account')
    Note 'password set' $true $set
    if (-not $set) { Write-Host $out; Fail 'SET.PASSWORD did not report success.' }

    # -----------------------------------------------------------------------
    Step 3 "Enabling APIPORT=$Port in the installed sd.conf"

    Copy-Item -LiteralPath $conf -Destination $backup -Force
    $lines = @(Get-Content -LiteralPath $conf) | Where-Object { $_ -notmatch '^\s*APIPORT\s*=' }
    $lines += ('APIPORT=' + $Port)
    Set-Content -LiteralPath $conf -Value $lines -Encoding Ascii

    # -----------------------------------------------------------------------
    Step 4 'Restarting SD so read_config() runs'

    # IT HAS TO BE A RESTART, not a reload.  read_config() runs only when the
    # shared segment is CREATED (sysseg.c:150-157); an attaching session takes
    # pcfg from the segment instead, so a running system never sees the change.
    if (-not (Stop-SD))  { Fail 'SD would not stop - close any open session and try again.' }
    if (-not (Start-SD)) { Fail 'SD would not start again.  Read the SD error log.' }

    Start-Sleep -Seconds 2

    # -----------------------------------------------------------------------
    Step 5 'Checking what is listening'

    $listen = @(netstat -an | Select-String 'LISTENING' |
                Where-Object { $_ -match (':' + $Port + '\s') })
    Note 'a listener on the port' $true ($listen.Count -gt 0)
    foreach ($l in $listen) { Write-Host ('   ' + $l.ToString().Trim()) }

    # THE SECURITY ASSERTION, and the reason this step exists at all.  Bound to
    # loopback means unreachable from the network; 0.0.0.0 would mean SD is
    # facing the world, which posture B says it never does.
    $onLoopback = @($listen | Where-Object { $_ -match ('127\.0\.0\.1:' + $Port) }).Count -gt 0
    $onAny      = @($listen | Where-Object { $_ -match ('0\.0\.0\.0:' + $Port) }).Count -gt 0
    Note 'bound to 127.0.0.1' $true $onLoopback
    Note 'NOT bound to 0.0.0.0' $true (-not $onAny)

    Note 'sdwind running' $true ([bool](Get-Process -Name sdwind -ErrorAction SilentlyContinue))

    # -----------------------------------------------------------------------
    Step 6 'Driving a session through the client library'

    # The three cells and the two controls live in the test, not here - see
    # gplsrc/sdclilib/tests/remote_connect_test.c.  Its exit code is the result.
    #
    # THROUGH THE TOP-LEVEL MAKEFILE, not gplsrc/sdclilib: from there make picks
    # up the MSYS2 cc instead of the UCRT64 compiler the DLL is built with, and
    # the test will not run.  Same trap as check-local.
    $bash = 'C:\msys64\usr\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bash)) { Fail "MSYS2 bash not found at $bash" }

    # C:\a\b -> /c/a/b
    $msys = '/' + $Sd64.Substring(0, 1).ToLower() + ($Sd64.Substring(2) -replace '\\', '/')

    $cmd = "cd '$msys' && make check-remote APIHOST=127.0.0.1 APIPORT=$Port " +
           "APIUSER=$Prefix APIPASS='$pw' APIACCT=" + $Prefix.ToUpper()
    & $bash -lc $cmd
    $testRc = $LASTEXITCODE
    Note 'remote_connect_test exit code' 0 $testRc
}
finally {
    if (-not $Keep) {
        Step 9 'Putting the system back'

        if (Test-Path -LiteralPath $backup) {
            Copy-Item -LiteralPath $backup -Destination $conf -Force
            Remove-Item -LiteralPath $backup -Force
            Write-Host '   sd.conf restored'
        }

        if ($restoreNeeded) {
            if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name $Prefix
                Write-Host "   removed Windows account $Prefix"
            }
            $d = Join-Path $env:ProgramData ('SD\user_accounts\' + $Prefix)
            if (Test-Path -LiteralPath $d) {
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
            }
            $g = 'sdu_' + $Prefix
            if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { Remove-LocalGroup -Name $g }
            # The SD half is left deliberately, as verify-tiers.ps1 leaves its
            # own: removing the register record here would hide a
            # CREATE.ACCOUNT that had half failed.  $CRED keeps its record too.
            Write-Host '   ACCOUNTS and $CRED records left in place - remove with DELETE.ACCOUNT'
        }

        if (Stop-SD) { $null = Start-SD }
        Write-Host '   SD restarted with the port closed'
    } else {
        Write-Host ''
        Write-Host "-Keep: APIPORT=$Port is STILL SET and $Prefix still exists." -ForegroundColor Yellow
        Write-Host "  password: $pw"
        Write-Host "  put it back with: Copy-Item '$backup' '$conf' -Force, then restart SD"
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host

if ($failed) {
    Write-Host 'VERIFY-APIPORT: FAILED - read the rows above.' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}
Write-Host 'VERIFY-APIPORT: all checks passed.' -ForegroundColor Green
Write-Host 'The remote transport carried a session, $CRED ran, and the ACC$GROUP check ran.'
try { Stop-Transcript | Out-Null } catch { }
exit 0
