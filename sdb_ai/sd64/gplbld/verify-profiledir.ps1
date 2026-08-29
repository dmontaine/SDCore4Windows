<#
.SYNOPSIS
    CREATE.ACCOUNT must refuse a name whose Windows profile directory is still
    on the disk.  PRE_RELEASE_FIXES.md 36, the one leg of it never exercised.

.DESCRIPTION
    ***WHAT IT GUARDS, AND WHY THE ANSWER CANNOT BE PUT RIGHT AFTERWARDS.***
    Windows will not put a new profile where one already sits.  Asked for an
    account whose directory survives, it creates the account with a SUFFIXED
    home - the name with the computer name appended - and says nothing.
    Anything the old directory held, ssh keys included, is then simply not
    where the account looks.  CREATEA:511-520 refuses instead: !profile_dir
    tests for the directory, sysmsg 10124 names it, and status() is read
    separately so a check that could not RUN (10125) also stops the creation
    rather than scoring as a clear path.

    ***THIS LEG SHIPPED UNMEASURED AND THAT IS WHY THE SCRIPT EXISTS.***  b56
    and b57 both ran the whole suite against the finished build and neither
    log mentions 10124 or 10125 - nothing creates an account over a leftover
    directory, because every other verifier is careful to use a fresh name.
    The check that has never fired is the one that cannot be trusted.

    ***THE FIXTURE IS A BARE DIRECTORY, DELIBERATELY.***  !profile_dir is a
    Test-Path on <ProfilesDirectory>\<name> (PROFILE_DIR:99-100) - no account,
    no registry entry, no hive.  So the subject is made with New-Item and
    removed with Remove-Item, and the test needs no deleted account, no
    reboot and no reclaim store.  It also means this measures exactly what the
    BASIC measures, rather than a richer state that might pass for other
    reasons.

    ***AND IT CARRIES ITS OWN CONTROL.***  A refusal proves nothing on its own:
    CREATE.ACCOUNT refuses names for a dozen reasons and SD might simply be
    broken.  So the same command is run for a second name with NO leftover
    directory, and that one must SUCCEED - Windows account, sdu_ group and
    ACCOUNTS record all present, and 10124 absent from its output.  One
    difference between the two runs, opposite outcomes.

.PARAMETER Prefix
    Stem for two throwaway names: <prefix>x, which gets a leftover directory
    and must be REFUSED, and <prefix>y, the control, which must be CREATED.
    Use a stem nobody has used - the spent list is in PROJECT_STATUS.md.

.PARAMETER Keep
    Leave the fixture directory and the control account behind for poking at.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-profiledir.ps1 -Prefix sdpdb58
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)] [string] $Prefix,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-profiledir-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
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
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# The installed sysmsg(N) as a REGEX - copied from verify-delaccount.ps1, whose
# header records why it is read from the install rather than hard-coded: a
# reworded message must fail the check that names it instead of going blind.
# A LITERAL RUN OF THE MESSAGE, MADE TOLERANT OF HOW SD RENDERS IT.
#
# ***THE MESSAGE FILE HOLDS LITERAL BACKSLASH-n, NOT NEWLINES*** - sixteen of
# them in 10124, fourteen in 10075, sixteen in 10123 - and SD turns each into a
# line break when it prints.  Escaping the file text as it stands produces a
# pattern containing "\\n", which matches a literal backslash followed by n:
# something the rendered output never contains.  The check could not match
# however right the product was.  Found 28 Aug 2026 by this script reporting
# FAIL on a refusal whose message was sitting in its own transcript, correct
# and complete.
#
# So every run of whitespace - literal \n, a real newline, spaces - becomes
# \s+.  That survives the rendering AND any wrapping, and it cannot loosen a
# check into a false positive: the words and their order still have to be
# there, and -match is already case-insensitive.
function Esc-Loose([string]$s) {
    $runs = [regex]::Split($s, '(?:\\n|\s)+')
    $out = ''
    for ($i = 0; $i -lt $runs.Count; $i++) {
        if ($i -gt 0) { $out += '\s+' }
        $out += [regex]::Escape($runs[$i])
    }
    return $out
}

function Get-SysMsgPattern([int]$n, [string[]]$vals) {
    $f = Join-Path $env:ProgramData ('SD\sdsys\messages\' + $n)
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $t = ((Get-Content -LiteralPath $f -Raw)).Trim()
    if ($t -eq '') { return '' }
    $parts = [regex]::Split($t, '%\d')
    $pat = Esc-Loose $parts[0]
    for ($i = 1; $i -lt $parts.Count; $i++) {
        if ($vals -and $vals.Count -ge $i -and $vals[$i - 1] -ne '') {
            $pat += [regex]::Escape($vals[$i - 1])
        } else {
            $pat += '.*'
        }
        $pat += Esc-Loose $parts[$i]
    }
    return $pat
}

function Shown($out, [int]$n, [string[]]$vals) {
    $p = Get-SysMsgPattern $n $vals
    return ($p -ne '' -and $out -match $p)
}

# Blank first line absorbs the pipe's BOM, TERM stops pagination, OFF ends it.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

function Test-SdRunning { return ((Get-Process sdwind -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) }

function Start-SD {
    if (Test-SdRunning) { return $true }
    $null = Start-Process -FilePath $sdExe -ArgumentList '-start' -NoNewWindow
    for ($i = 0; $i -lt 30; $i++) {
        if (Test-SdRunning) { Write-Host '  sdwind is up'; return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

# --- the preconditions -----------------------------------------------------

$pr = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Fail 'this needs an ELEVATED PowerShell - CREATE_USER makes a Windows account, and the fixture directory goes under C:\Users.'
}

& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'the installed tree does not match source - see above' }

if (-not (Test-Path -LiteralPath $sdExe)) { Fail "no $sdExe" }

$subject = ($Prefix + 'x')
$control = ($Prefix + 'y')
$pw      = 'Pd-' + [guid]::NewGuid().ToString('N').Substring(0, 12) + '!7'

# RULE 1 OF THE INSTRUMENT SECTION: the real inputs, before anything is done
# with them.  The profiles root is read the same way !profile_dir reads it, so
# the fixture lands where the BASIC will look rather than where this script
# assumes.
$profilesRoot = ''
try {
    $profilesRoot = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList' `
                        -Name ProfilesDirectory -ErrorAction Stop).ProfilesDirectory
} catch { }
if ($profilesRoot -eq '') { $profilesRoot = Join-Path $env:SystemDrive 'Users' }
$profilesRoot = [Environment]::ExpandEnvironmentVariables($profilesRoot)
$fixture = Join-Path $profilesRoot $subject

Write-Host ''
Write-Host "verify-profiledir: as $($env:USERDOMAIN)\$($env:USERNAME), ELEVATED"
Write-Host "  sd.exe         $sdExe"
Write-Host "  profiles root  $profilesRoot   (read from ProfileList, as !profile_dir does)"
Write-Host "  subject        $subject   - gets a leftover directory, must be REFUSED"
Write-Host "  control        $control   - no leftover directory, must be CREATED"
Write-Host "  fixture        $fixture"

# EVERY MESSAGE THIS RUN NAMES MUST BE THERE, checked before anything is made -
# an absent message file makes Get-SysMsgPattern return '', and Shown would then
# report "not shown" for a message that was printed perfectly.
foreach ($m in @(10124)) {
    if ((Get-SysMsgPattern $m @()) -eq '') { Fail "message $m is missing from the install - every check naming it would report a false negative" }
}

# REFUSE THE NULL CASE OUT LOUD.  If either name is already taken, the refusal
# this test is looking for could come from the name rather than the directory,
# and the run would pass while measuring the wrong rule.
foreach ($n in @($subject, $control)) {
    if (Get-LocalUser -Name $n -ErrorAction SilentlyContinue) { Fail "$n is already a Windows account - pick a fresh -Prefix" }
    if (Get-LocalGroup -Name ('sdu_' + $n) -ErrorAction SilentlyContinue) { Fail "sdu_$n already exists - pick a fresh -Prefix" }
    if (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $n.ToUpper()))) { Fail "$n already has an ACCOUNTS record - pick a fresh -Prefix" }
}
if (Test-Path -LiteralPath $fixture) { Fail "$fixture already exists - this test must make its own fixture, or it is not measuring what it thinks" }
if (Test-Path -LiteralPath (Join-Path $profilesRoot $control)) { Fail "the CONTROL name already has a directory - it would be refused for the same reason as the subject and prove nothing" }

if (-not (Start-SD)) { Fail 'sdwind did not start' }

# --- [1] the fixture -------------------------------------------------------

Step 1 'Make a leftover profile directory, with no account behind it'

$null = New-Item -ItemType Directory -Path $fixture -Force
Note 'fixture directory exists' $true (Test-Path -LiteralPath $fixture)
Note 'and no Windows account of that name' $false ([bool](Get-LocalUser -Name $subject -ErrorAction SilentlyContinue))
Write-Host "  before: $fixture present, $subject is not an account"

# --- [2] the refusal -------------------------------------------------------

Step 2 'CREATE.ACCOUNT over the leftover directory must be refused, naming it'

$out = Invoke-SD @("CREATE.ACCOUNT USER $subject BOTH", $pw, $pw)
Write-Host '  --- raw output ---------------------------------------------'
Write-Host $out
Write-Host '  ------------------------------------------------------------'

# ANCHORED ON 10124 WITH BOTH ITS PLACEHOLDERS FILLED - the account name AND
# the directory.  The name alone appears in the echoed command and in every
# other refusal CREATE.ACCOUNT can print, so matching it would be a check that
# the failure path also passes.
Note 'message 10124 shown, naming the account and the directory' $true `
     (Shown $out 10124 @($subject.ToUpper(), $fixture))

# --- [3] nothing was made --------------------------------------------------

Step 3 'The refusal must have created nothing at all'

Note 'no Windows account'  $false ([bool](Get-LocalUser -Name $subject -ErrorAction SilentlyContinue))
Note 'no sdu_ group'       $false ([bool](Get-LocalGroup -Name ('sdu_' + $subject) -ErrorAction SilentlyContinue))
Note 'no ACCOUNTS record'  $false (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $subject.ToUpper())))
Note 'the fixture directory is untouched' $true (Test-Path -LiteralPath $fixture)

$suffixed = @(Get-ChildItem -LiteralPath $profilesRoot -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -like ($subject + '.*') })
Note 'and Windows was never given the chance to make a SUFFIXED home' 0 $suffixed.Count

# --- [4] the control -------------------------------------------------------

Step 4 'CONTROL: the same command for a name with no leftover directory must SUCCEED'

$cout = Invoke-SD @("CREATE.ACCOUNT USER $control BOTH", $pw, $pw)
Write-Host '  --- raw output ---------------------------------------------'
Write-Host $cout
Write-Host '  ------------------------------------------------------------'

Note 'control: 10124 NOT shown' $false (Shown $cout 10124 @($control.ToUpper()))
Note 'control: Windows account made' $true ([bool](Get-LocalUser -Name $control -ErrorAction SilentlyContinue))
Note 'control: sdu_ group made'      $true ([bool](Get-LocalGroup -Name ('sdu_' + $control) -ErrorAction SilentlyContinue))
Note 'control: ACCOUNTS record made' $true (Test-Path -LiteralPath (Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $control.ToUpper())))

# --- [5] cleanup -----------------------------------------------------------

Step 5 'Cleanup'

if ($Keep) {
    Write-Host "  -Keep: leaving $fixture and the account $control"
} else {
    $dout = Invoke-SD @("DELETE.ACCOUNT $control", 'Y', 'Y', 'Y')
    Write-Host '  --- DELETE.ACCOUNT output ----------------------------------'
    Write-Host $dout
    Write-Host '  -----------------------------------------------------------'
    Note 'control account removed again' $false ([bool](Get-LocalUser -Name $control -ErrorAction SilentlyContinue))

    Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
    Note 'fixture directory removed'     $false (Test-Path -LiteralPath $fixture)
}

# --- the tally -------------------------------------------------------------

Write-Host ''
$results | Format-Table -AutoSize | Out-String | Write-Host

# [string] ON BOTH SIDES - PowerShell's -eq coerces the RIGHT operand to the
# LEFT's type, so "$true -eq 'n/a'" is TRUE.  verify-delaccount.ps1 caught this
# before its first run and the note is kept here for the same reason.
$na    = @($results | Where-Object { [string]$_.Expected -eq 'n/a' }).Count
$asked = @($results | Where-Object { [string]$_.Expected -ne 'n/a' })
$pass  = @($asked | Where-Object { $_.Expected -eq $_.Observed }).Count

# A RUN THAT ASKED NOTHING MUST NOT PASS.  If the steps above were skipped for
# any reason the tally would read 0 of 0 and the exit code would be 0.
if ($results.Count -lt 10) {
    Write-Host ''
    Write-Host ("verify-profiledir: only {0} check(s) were made - too few for this to have run.  Refusing to report a pass." -f $results.Count) -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

Write-Host ("verify-profiledir: {0} PASS + {1} N/A of {2}" -f $pass, $na, $results.Count)

if ($failed) {
    Write-Host ''
    Write-Host 'verify-profiledir: FAILED' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

Write-Host ''
Write-Host ('verify-profiledir: the leftover directory was refused and named, ' +
            'and the same command with no leftover directory created the account.') -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
