<#
.SYNOPSIS
    Does !valid_os_name on the API login path refuse a name a real client could
    legitimately present?  PROJECT_STATUS.md section 2.

.DESCRIPTION
    THE QUESTION THIS SETTLES, owed since 15 Aug 2026.  APISRVR:1180 applies
    !valid_os_name to the SCRAM username BEFORE the credential is read, and that
    function allows letters, digits, dot, underscore and hyphen only - no
    backslash and no space.  So a domain-qualified name, DOMAIN\user, is refused
    before authentication.  Section 2 recorded this as "not yet measured:
    whether a real API login presents a domain-qualified name", and said that
    measurement decides whether it is a defect or only a smell.

    WHAT IS ALREADY SETTLED FROM SOURCE, so this script measures the rest:

      - The client sends what the APPLICATION passed.  SDConnect()'s username
        argument goes to scram_login() and straight into "n=%s"
        (sdclilib.c:1049).  Nothing derives it from Windows - there is no
        GetUserName anywhere in the client.
      - The client's only check is LENGTH, 1..32 (sdclilib.c:1218).  Charset is
        entirely the server's business, so a qualified name does reach the wire.
      - SD can never REGISTER an account whose name would fail the check:
        CREATE_USER:79, CREATEA:537 and CREATEA:1406 (the ADOPT path) all apply
        !valid_os_name first.
      - And SD cannot see a domain account at all.  IS_USER:62 says so in its
        own comment - "LOCAL ACCOUNTS ONLY.  Get-LocalUser does not see domain
        accounts" - and CREATE_USER uses New-LocalUser.

    THE CONTROL IS THE WHOLE POINT.  A refusal proves nothing on its own here,
    because an account that does not exist is refused too, by the very next
    line.  So every treatment below is the SAME account with the SAME password
    that step 3 has just seen admitted; the only thing that changes is how the
    name is spelled.  Without step 3 this file would pass on a build where the
    API refused everything.

    WHAT IT CANNOT MEASURE, AND NOR CAN THIS MACHINE.  GITORLI is in WORKGROUP,
    not a domain, so there is no real domain account to present.  Section 4's
    RDP entry is the same shape: the reasoning is sound, the rig is absent.
    What is measured here is the SPELLING being refused, which is the half that
    decides the question - a name SD could never register cannot be a login it
    owes anybody.

.PARAMETER Prefix
    Single-use account name, as every verifier here takes.  Section 6 has the
    list of spent ones.

.PARAMETER Keep
    Leave the account in place.  Off by default; the account is removed in a
    finally so a failure part way does not litter.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-apiname.ps1 -Prefix sdapin1
#>
param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [int]    $Port = 4243,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$Sd64   = Split-Path -Parent $Gplbld
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$sdBin  = Join-Path $env:ProgramFiles 'SD\usr\bin'
$probe  = Join-Path $Sd64 'gplsrc\sdclilib\localtest\remote-connect-test.exe'
$audit  = Join-Path $env:ProgramData 'SD\sdsys\audit'
$ESC    = [char]27

# LOCALAPPDATA, not under ProgramData\SD: it is the same directory elevated or
# not, so an unelevated session afterwards can read what this wrote.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-apiname-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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

function Invoke-SD([string[]]$commands) {
    # LOGIN re-inits terminal geometry on every account switch (LOGIN:201-209),
    # so the initial TERM below is wiped by any LOGTO in $commands.  Full
    # write-up in verify-tiers.ps1's Invoke-SD.
    $expanded = New-Object System.Collections.ArrayList
    foreach ($c in $commands) {
        $null = $expanded.Add($c)
        if ($c -match '^\s*LOGTO\b') { $null = $expanded.Add('TERM 200,9999') }
    }
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $expanded + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ($ESC + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

# SECTION 6: never redirect a native exe's stderr inline in PowerShell 5.1 -
# under $ErrorActionPreference = 'Stop' every stderr LINE becomes a terminating
# error, and a refusal is exactly the output this script exists to read.
function Invoke-Probe([string]$user, [string]$pass, [string]$account) {
    $o = [IO.Path]::GetTempFileName()
    $e = [IO.Path]::GetTempFileName()
    try {
        $saved = $env:PATH
        $env:PATH = $sdBin + ';' + $env:PATH
        $p = Start-Process -FilePath $probe `
                -ArgumentList @('127.0.0.1', "$Port", $user, $pass, $account) `
                -NoNewWindow -Wait -PassThru `
                -RedirectStandardOutput $o -RedirectStandardError $e
        $env:PATH = $saved
        $text = ((Get-Content -LiteralPath $o -Raw -ErrorAction SilentlyContinue) + "`n" +
                 (Get-Content -LiteralPath $e -Raw -ErrorAction SilentlyContinue))
        return [pscustomobject]@{ Code = $p.ExitCode; Text = $text }
    } finally {
        Remove-Item -LiteralPath $o, $e -Force -ErrorAction SilentlyContinue
    }
}

# CASE SENSITIVE, AND THAT IS NOT FUSSINESS.  remote_connect_test.c prints
# "  admitted" when the first connect succeeds (:116) and "  ADMITTED" on the
# FAILURE paths of its wrong-password and SDSYS checks (:139, :154).  PowerShell's
# -match is case-INSENSITIVE by default, so a plain -match 'admitted' reads
# either one as success.  -ceq on the trimmed line cannot.
function Was-Admitted($r) {
    foreach ($l in ($r.Text -split "`r?`n")) {
        if ($l.Trim() -ceq 'admitted') { return $true }
    }
    return $false
}

# Returns the one line the client printed for the first connect attempt, so two
# refusals can be compared as strings rather than by eye.
function First-Verdict($r) {
    foreach ($l in ($r.Text -split "`r?`n")) {
        if ($l -cmatch 'REFUSED:' -or $l.Trim() -ceq 'admitted') { return $l.Trim() }
    }
    return '(no verdict line)'
}

# ---------------------------------------------------------------------------
$id = [Security.Principal.WindowsIdentity]::GetCurrent()
if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'Run this from an ELEVATED PowerShell - it creates and deletes an account.'
}

Step 0 'Checking the installed tree matches source'
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'assert-current says the install is not current. Cycle first.' }

$restoreNeeded = $false
try {
    # -----------------------------------------------------------------------
    Step 1 'Making an account the API can reach'

    if (-not (Get-Process -Name sdwind -ErrorAction SilentlyContinue)) {
        Fail 'sdwind is not running - start SD before running this.'
    }
    $listening = [bool](netstat -an | Select-String (':' + $Port) | Select-String 'LISTENING')
    Note 'API port is listening' $true $listening
    if (-not $listening) { Fail "Nothing is listening on $Port." }

    # Two passwords, and they are not the same thing - verify-apiport.ps1 has
    # the reasoning. The Windows one may hold punctuation; the SD one stays
    # alphanumeric because it is passed as an argument.
    Add-Type -AssemblyName System.Web
    $winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6)
    $bytes = New-Object byte[] 18
    ([Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $pw = ([Convert]::ToBase64String($bytes) -replace '[^A-Za-z0-9]', '') + 'aA1'

    $out = Invoke-SD @("CREATE.ACCOUNT USER $Prefix PROGRAMMER NONE", $winPw, $winPw)
    $accRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper())
    $made = Test-Path -LiteralPath $accRec
    Note 'accounts record created' $true $made
    if (-not $made) { Write-Host $out; Fail 'CREATE.ACCOUNT did not register the account.' }
    $restoreNeeded = $true

    $out = Invoke-SD @(("MODIFY.PASSWORD " + $Prefix.ToUpper()), $pw, $pw)
    $set = ($out -match 'Password set for account')
    Note 'password set' $true $set
    if (-not $set) { Write-Host $out; Fail 'MODIFY.PASSWORD did not report success.' }

    $out = Invoke-SD @("MODIFY.ACCOUNT $Prefix API")
    $inApi = [bool](Get-LocalGroupMember -Group 'sdapi' -Member $Prefix -ErrorAction SilentlyContinue)
    Note 'granted API access (in sdapi)' $true $inApi
    if (-not $inApi) { Write-Host $out; Fail 'MODIFY.ACCOUNT ... API did not put the account in sdapi.' }

    # -----------------------------------------------------------------------
    Step 2 'Building the probe'

    # sdclilib\tests\ and localtest\ are both excluded from assert-current, so
    # building here cannot make the install report stale - section 6.
    $bash = 'C:\msys64\usr\bin\bash.exe'
    if (-not (Test-Path -LiteralPath $bash)) { Fail "MSYS2 bash not found at $bash." }
    $sd64posix = '/' + ($Sd64 -replace '\\', '/' -replace '^([A-Za-z]):', '$1')
    $cmd = "cd '$sd64posix/gplsrc/sdclilib' && PATH=/c/msys64/ucrt64/bin:`$PATH " +
           "make CC=/c/msys64/ucrt64/bin/gcc.exe localtest/remote-connect-test.exe 2>/dev/null || " +
           "( mkdir -p localtest && /c/msys64/ucrt64/bin/gcc.exe -std=c11 -Wall -Wextra -Wpedantic " +
           "-o localtest/remote-connect-test.exe tests/remote_connect_test.c -I. -L. -lsdclilib )"
    & $bash -lc $cmd | Out-Null
    $built = Test-Path -LiteralPath $probe
    Note 'probe built' $true $built
    if (-not $built) { Fail 'Could not build remote-connect-test.exe.' }

    # -----------------------------------------------------------------------
    Step 3 'THE CONTROL: the bare name, admitted'

    # Without this every check below passes on a build where the API refuses
    # everything, which is the failure shape this project has paid for.
    $bare = Invoke-Probe $Prefix $pw $Prefix.ToUpper()
    $bareOk = Was-Admitted $bare
    Note 'bare name admitted' $true $bareOk
    if (-not $bareOk) {
        Write-Host $bare.Text
        Fail 'The control failed: the account cannot log in at all, so no refusal below means anything.'
    }
    $bareVerdict = First-Verdict $bare

    # -----------------------------------------------------------------------
    Step 4 'THE TREATMENT: the same account, spelled four other ways'

    $machine = $env:COMPUTERNAME
    $auditBefore = ''
    if (Test-Path -LiteralPath $audit) { $auditBefore = Get-Content -LiteralPath $audit -Raw }

    $cases = @(
        @{ Name = "$machine\$Prefix";              Label = 'COMPUTER\name' },
        @{ Name = ($machine.ToLower() + '\' + $Prefix); Label = 'computer\name (lower)' },
        @{ Name = "$Prefix $Prefix";               Label = 'name with a space' },
        @{ Name = "$Prefix@$machine";              Label = 'name@computer (UPN shape)' }
    )
    $verdicts = @{}
    foreach ($c in $cases) {
        $r = Invoke-Probe $c.Name $pw $Prefix.ToUpper()
        $refused = -not (Was-Admitted $r)
        Note ("refused: " + $c.Label) $true $refused
        $verdicts[$c.Label] = First-Verdict $r
    }

    # -----------------------------------------------------------------------
    Step 5 'THE DISCRIMINATOR: a refused spelling is indistinguishable from a wrong password'

    # This is the finding that costs a user time, and it is why the question was
    # worth asking even though the answer is "not a defect".  APISRVR sends both
    # to scram.bad.cred, so the client cannot tell "this name can never be an
    # account" from "you typed the wrong password".
    $wrong = Invoke-Probe $Prefix ($pw + 'X') $Prefix.ToUpper()
    $wrongVerdict = First-Verdict $wrong
    Write-Host "     bare + right password : $bareVerdict"
    Write-Host "     bare + WRONG password : $wrongVerdict"
    foreach ($k in $verdicts.Keys) { Write-Host ("     {0,-22}: {1}" -f $k, $verdicts[$k]) }

    $same = $true
    foreach ($k in $verdicts.Keys) { if ($verdicts[$k] -ne $wrongVerdict) { $same = $false } }
    Note 'every refused spelling reads exactly like a wrong password' $true $same

    # -----------------------------------------------------------------------
    Step 6 'AND EVERY REFUSAL IS AUDITED'

    # THIS EXPECTATION IS THE OPPOSITE OF WHAT IT WAS ON 21 Aug 2026, and the
    # inversion is the fix.  APISRVR used to audit one reason only - "not in
    # sdapi" - and that fires AFTER the proof succeeds, so everything reaching
    # scram.bad.cred wrote nothing at all.  This script measured that (the file
    # did not grow across five refusals) and section 8 carried it as an open
    # question.  There is now one writer at exit.vb.scram.fail, driven by
    # scram.refuse.reason, and every path out of both handlers passes it.
    $auditAfter = ''
    if (Test-Path -LiteralPath $audit) { $auditAfter = Get-Content -LiteralPath $audit -Raw }
    Note 'audit grew across the refusals' $true ($auditAfter.Length -gt $auditBefore.Length)

    $new = $auditAfter.Substring([Math]::Min($auditBefore.Length, $auditAfter.Length))

    # THE REASON, NOT JUST A RECORD.  "something was written" would pass on a
    # writer that logged the wrong thing for every refusal alike; these two say
    # the right branch named itself, and they differ from each other.
    Note 'records reason=name rejected by valid_os_name' $true `
         ($new -cmatch 'reason=name rejected by valid_os_name')
    Note 'records reason=wrong password'                 $true `
         ($new -cmatch 'reason=wrong password')

    # THE SANITISER, AND THIS IS THE LOG-INJECTION CONTROL.  audit_message()
    # (k_error.c) writes the text verbatim and ends the record with a newline,
    # and these names have NOT passed valid_os_name - that is why they are being
    # recorded.  scram.clean.name maps anything outside valid_os_name's own set
    # to '?', so the backslash form must appear ONLY in its sanitised spelling.
    $sanitised = $machine + '?' + $Prefix
    $raw       = $machine + '\' + $Prefix
    Note 'the name is recorded sanitised'  $true  ($new -cmatch [regex]::Escape($sanitised))
    Note 'the raw backslash never appears' $false ($new -cmatch [regex]::Escape($raw))

    Write-Host '     --- what the trail gained ---'
    foreach ($l in ($new -split "`r?`n")) { if ($l.Trim()) { Write-Host ("     " + $l.Trim()) } }

    # -----------------------------------------------------------------------
    Step 7 'THE CLIENT CAP IS A DIFFERENT CHECK, and says so'

    # sdclilib.c:1218 refuses 0 or >32 before anything reaches the wire, with
    # its own text.  Distinguishing it from the server refusal is what shows the
    # two limits are independent rather than one check seen twice.
    $long = Invoke-Probe ('z' * 33) $pw $Prefix.ToUpper()
    $clientSide = ($long.Text -match 'Invalid user name')
    Note 'a 33-character name is refused CLIENT-side, different text' $true $clientSide
    Write-Host ("     33 chars: " + (First-Verdict $long))
}
finally {
    if ($restoreNeeded -and -not $Keep) {
        Step 9 'Cleaning up'
        try {
            if (Get-LocalGroupMember -Group 'sdapi' -Member $Prefix -ErrorAction SilentlyContinue) {
                Remove-LocalGroupMember -Group 'sdapi' -Member $Prefix -ErrorAction Stop
                Write-Host "   took $Prefix out of sdapi"
            }
        } catch { Write-Host "   could not remove from sdapi: $($_.Exception.Message)" }
        try { $null = Invoke-SD @("DELETE.ACCOUNT $Prefix", 'Y', 'Y') } catch { }
        if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
            try { Remove-LocalUser -Name $Prefix -ErrorAction Stop } catch { }
        }
        Write-Host "   $Prefix removed"
    } elseif ($restoreNeeded) {
        Write-Host ''
        Write-Host "-Keep: $Prefix still exists and is still in sdapi." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host
$pass = ($results | Where-Object { $_.Expected -eq $_.Observed }).Count
Write-Host ("verify-apiname: {0} of {1} checks passed" -f $pass, $results.Count)
try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 }
exit 0
