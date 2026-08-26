# verify-standalone.ps1 - measure a STAND-ALONE SD installation.
# PROJECT_STATUS.md "START HERE" item 5.
#
#   powershell -File verify-standalone.ps1            run the checks, clean up
#   powershell -File verify-standalone.ps1 -Keep      leave the group account behind
#
# Exit 0 every check passed, 1 a check failed, 2 the test could not be run.
#
# WHY THIS EXISTS.  Item 5 was built end to end and every part of it was
# "proven as far as it can be without an install" - ISPP lint, a [Code] section
# compiled in a harness, controls that fail on an injected fault.  None of that
# touches a machine.  The suite has no step that CHOOSES the stand-alone
# option, so all 31 of its steps run the full installation and nothing in it
# has ever looked at a stand-alone system.  This is that step.
#
# ============================================================================
# IT REFUSES ON A FULL INSTALL, AND THAT REFUSAL IS THE POINT
# ============================================================================
#
# Every check below asks whether something is ABSENT - no APIPORT, no open
# port, no firewall rule, no ssh server.  On a FULL install most of those
# answers would be wrong, but a few would be accidentally right, and on a
# machine with no SD at all EVERY ONE of them would be "absent" and this would
# report a clean pass having measured nothing whatsoever.
#
# That is the failure CLAUDE.md's instrument rule is about: a test that passes
# because it did nothing must FAIL, not pass.  So section 0 establishes that
# this IS a stand-alone install before any absence is allowed to count, and
# exits 2 - "could not be run" - when it is not.  It is deliberately not exit 1:
# nothing has failed, the test simply does not apply here.
#
# ============================================================================
# EVERY ABSENCE IS PAIRED WITH A CONTROL
# ============================================================================
#
# "Get-NetFirewallRule found no SD rule" and "Get-NetFirewallRule is broken and
# found nothing at all" produce the same answer.  So does "nothing is listening
# on 4243" versus "the listener query returned an empty set".  Each of those
# checks therefore also asserts that the same call, made the same way, DOES see
# the things that are genuinely there.  A control that comes back empty fails
# the run.
#
# ============================================================================
# THE TWO SD CHECKS ANCHOR ON THE WORDING ONLY THE REAL OUTCOME PRINTS
# ============================================================================
#
# Section 6 asserts that CREATE.ACCOUNT USER is refused.  The obvious guard -
# "the account name appears in the output" - is exactly the trap that made
# verify-apiidentity report a refused step as confirmed: the name is echoed by
# the command line, by the refusal, and by any error about it.  So the anchor is
# sysmsg 10100's own first line, which is printed on the refusal path and
# nowhere else, and it is paired with two disqualifiers: sysmsg 10007's "Created"
# must be ABSENT, and no Windows user of that name may exist afterwards.
#
# Section 7 is the other half of the ruling and it is not decoration.  The
# decision was that the USER form is refused and the GROUP form is untouched,
# because a group account is how a learner still separates their work.  A run
# that only proved the refusal would be consistent with CREATEA refusing
# everything, which would break the education case the option exists for.

[CmdletBinding()]
param(
    # Created and removed within one run.  A fixed name is fine; section 6
    # refuses to proceed if either name already exists, because that would be
    # somebody's real account.
    [string] $UserAccount  = 'sdsauser',
    [string] $GroupAccount = 'sdsagroup',

    # Leave the group account behind for inspection.
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-standalone-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

# CLAUDE.md: call assert-current first from anything new that tests the install.
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-standalone: refusing - see above'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

# SECTIONS 6 AND 7 DRIVE SD WITH LOGTO SDSYS, AND THAT NEEDS AN ELEVATED
# TOKEN.  Checked here rather than at section 6, because reaching section 6 and
# failing there is the worse outcome: LOGTO would fail, sysmsg 10100 would be
# absent from the output, and the rows would score FAIL - a FALSE NEGATIVE that
# reads as "the installer did not wire the refusal" when the truth is "this
# shell was not elevated".  A test that cannot run must say so, not fail.
$principal = New-Object Security.Principal.WindowsPrincipal(
                 [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output ''
    Write-Output 'verify-standalone: CANNOT RUN - not elevated.'
    Write-Output '  Sections 6 and 7 drive SD with LOGTO SDSYS, which needs an elevated'
    Write-Output '  token.  Unelevated they would fail and read as a broken installer.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
Write-Output ('elevated as: ' + [Security.Principal.WindowsIdentity]::GetCurrent().Name)

$dataDir  = Join-Path $env:ProgramData 'SD'
$sdsys    = Join-Path $dataDir 'sdsys'
$marker   = Join-Path $sdsys '$standalone'
$sdConf   = Join-Path $dataDir 'sd.conf'
$sdExe    = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$grpDir   = Join-Path $dataDir ('group_accounts\' + $GroupAccount)

# RULE 1 OF THE INSTRUMENT SECTION: print the real inputs, not the intent.
Write-Output ''
Write-Output '=== what this run is measuring ==================================='
Write-Output ("  data tree : " + $dataDir)
Write-Output ("  marker    : " + $marker)
Write-Output ("  sd.conf   : " + $sdConf)
Write-Output ("  sd.exe    : " + $sdExe)
Write-Output ("  user acct : " + $UserAccount + "   group acct: " + $GroupAccount)

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{
        Check = $check; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
    })
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

# BOUNDED, and the bound is not caution.  SD prompts from places a script cannot
# predict, each in an unbounded "until yn = 'Y' or 'N'" loop; a hung pipe
# returns nothing at all, so the cause is invisible, and the stuck sdwind then
# refuses the next cycle.  verify-fold.ps1 carries the full note.  The leading
# "`n" is the BOM sink.
#
# Write-Host, not Write-Output, for anything that is not the return value: a
# PowerShell function returns everything on the output stream, so a stray
# Write-Output makes the caller's string an ARRAY.
function Invoke-SD([string[]]$commands, [int]$TimeoutSec = 60) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    Write-Host ('    sd <<< ' + (($commands) -join ' ; '))
    $job = Start-Job -ScriptBlock { param($exe, $text) $text | & $exe } `
                     -ArgumentList $sdExe, $body
    if (Wait-Job $job -Timeout $TimeoutSec) {
        $out = Receive-Job $job
    } else {
        Stop-Job $job
        $out = Receive-Job $job
        $out += ''
        $out += "*** SD did not finish in $TimeoutSec s - it is waiting for input."
        $out += "*** It leaves the session's user-table slot and locks behind, so"
        $out += "*** sdwind will not shut down and cycle.ps1 will refuse to start."
        $out += "*** Stop-Process the sdwind PID it names."
    }
    Remove-Job $job -Force
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

function Remove-GroupAccount {
    if (Test-Path -LiteralPath $grpDir) {
        Remove-Item -LiteralPath $grpDir -Recurse -Force -ErrorAction SilentlyContinue
        Write-Host ('  cleanup: removed ' + $grpDir)
    } else {
        Write-Host ('  cleanup: no ' + $grpDir)
    }
}

try {

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== [0] Is this a stand-alone installation at all? ================'
# THE NULL-CASE GUARD.  Read the header: without this, a machine with no SD
# would answer "absent" to every check below and score a clean pass.

if (-not (Test-Path -LiteralPath $sdsys)) {
    Write-Output ("  there is no data tree at " + $sdsys)
    Write-Output ''
    Write-Output 'verify-standalone: CANNOT RUN - SD is not installed here.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

if (-not (Test-Path -LiteralPath $marker)) {
    Write-Output ("  no marker at " + $marker)
    Write-Output '  the data tree IS present, so SD is installed - as a FULL installation.'
    Write-Output ''
    Write-Output 'verify-standalone: CANNOT RUN - this is not a stand-alone installation.'
    Write-Output '  Every check in this file asks whether something is ABSENT, and on a full'
    Write-Output '  install those answers would be meaningless.  DO NOT READ THIS AS A PASS.'
    Write-Output '  Run cycle.ps1 and choose "Stand-alone installation" on the mode page.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}
Write-Output ("  marker present: " + $marker)

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== [1] The marker, and what it says ============================='
# It is written for a human who finds an unfamiliar file in SDSYS.  CREATEA
# reads only whether it exists, so the content is not load-bearing - but an
# empty or truncated marker means SaveStringToFile half-succeeded, which is
# worth knowing.
$markerText = ''
$raw = Get-Content -LiteralPath $marker -Raw -ErrorAction SilentlyContinue
# An empty file comes back as $null, and a [string] cast does not make it '',
# so .Trim() on it throws on the success path.
if ($null -ne $raw) { $markerText = [string]$raw }

Note 'marker is not empty' $true ($markerText.Length -gt 0)
Note 'marker says it marks a stand-alone install' $true `
     ($markerText -match [regex]::Escape('marks a STAND-ALONE SD installation'))
Note 'marker names the group-account way out' $true `
     ($markerText -match [regex]::Escape('create.account group'))
# CONTROL for the file test itself: a name that is not there must read absent.
Note 'CONTROL: a name that is not there reads absent' $false `
     (Test-Path -LiteralPath ($marker + '.notthere'))

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== [2] sd.conf sets no APIPORT =================================='
# LINE-WISE, matching stage.py _active_apiport() exactly.  Testing whether the
# text CONTAINS 'APIPORT=4243' is the trap stage.py records: the commented-out
# replacement contains that substring, so the guard fires on its own success.
$confLines = @(Get-Content -LiteralPath $sdConf -ErrorAction SilentlyContinue)
Write-Output ("  read " + $confLines.Count + " lines from " + $sdConf)
$activeApi = @($confLines | Where-Object { $_.Trim() -eq 'APIPORT=4243' })
$commented = @($confLines | Where-Object { $_.Trim() -eq '# APIPORT=4243' })

Note 'no ACTIVE APIPORT line' 0 $activeApi.Count
# CONTROL: the commented line IS there.  Without this, an sd.conf that failed to
# read at all - or the wrong file - would also show zero active lines.
Note 'CONTROL: the commented-out APIPORT line is present' 1 $commented.Count
# CONTROL: this is a real sd.conf and not an empty read.
$liveSettings = @($confLines | Where-Object { $_ -match '^\s*[A-Z][A-Z0-9_]*\s*=' })
Note 'CONTROL: sd.conf holds other live settings' $true ($liveSettings.Count -gt 0)

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== [3] Nothing is listening on the API port ====================='
# APIPORT unset means SD opens NO socket - sdwind.c:351, "APIPORT not set - the
# default, and not a failure".  So this is a real state to measure, not just an
# absent firewall rule.
$listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue)
$on4243    = @($listeners | Where-Object { $_.LocalPort -eq 4243 })
Write-Output ("  the machine has " + $listeners.Count + " listening TCP ports")

Note 'nothing listening on 4243' 0 $on4243.Count
# CONTROL: the query sees listeners at all.  Every Windows machine has some; an
# empty set means the cmdlet failed, not that the machine is quiet.
Note 'CONTROL: the listener query returns rows' $true ($listeners.Count -gt 0)

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== [4] No firewall rule was written ============================='
# The mode page tells the reader there is "no rule to open", and that has to
# stay true.  A rule naming a port nothing listens on describes a service that
# does not exist - which is why ApplyApiFirewall exits rather than writing a
# -Restrict rule.
$allRules = @(Get-NetFirewallRule -ErrorAction SilentlyContinue)
$sdRules  = @($allRules | Where-Object { $_.DisplayName -match '^SD ' -or $_.Name -match '^SD-' })
Write-Output ("  the machine has " + $allRules.Count + " firewall rules in total")
if ($sdRules.Count -gt 0) {
    Write-Output '  SD-named rules found:'
    foreach ($r in $sdRules) { Write-Output ('    ' + $r.Name + '  |  ' + $r.DisplayName) }
}

Note 'no SD firewall rule' 0 $sdRules.Count
# CONTROL: the cmdlet returns the machine's rules.  Zero of everything would
# make the line above pass while measuring nothing.
Note 'CONTROL: the firewall query returns rules' $true ($allRules.Count -gt 0)

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== [5] No ssh server was installed or started ==================='
# The stand-alone promise is specifically that no ssh server was installed and
# no ssh configuration was changed.  sshd absent is the strong form; sshd
# present but stopped would mean the [Run] gate leaked.
$sshd = Get-Service -Name 'sshd' -ErrorAction SilentlyContinue
$sshdState = 'absent'
if ($null -ne $sshd) { $sshdState = [string]$sshd.Status }
Write-Output ("  sshd service: " + $sshdState)

Note 'sshd is not running' $false ($sshdState -eq 'Running')
# CONTROL: Get-Service can find a service that is certainly there.  Without it,
# a broken call returns $null and "absent" for everything.
$control = Get-Service -Name 'Winmgmt' -ErrorAction SilentlyContinue
Note 'CONTROL: Get-Service finds a service that exists' $true ($null -ne $control)

# sshd_config must not have been given SD's AllowGroups block.  Absent file is
# the expected state; a present one that names sdssh would mean ApplyAllowGroups
# ran when it should have exited.
$sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
$allowGroups = 0
if (Test-Path -LiteralPath $sshdConfig) {
    $allowGroups = @(Get-Content -LiteralPath $sshdConfig -ErrorAction SilentlyContinue |
                     Where-Object { $_ -match '^\s*AllowGroups\b' }).Count
    Write-Output ("  sshd_config present at " + $sshdConfig + ", AllowGroups lines: " + $allowGroups)
} else {
    Write-Output ("  no sshd_config at " + $sshdConfig)
}
Note 'sshd_config carries no AllowGroups' 0 $allowGroups

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== [6] create.account USER is refused, and says why ============='
# THE ANCHOR IS sysmsg 10100's OWN WORDING, not the account name.  The name is
# echoed by the command line, by the refusal and by any error about it, so
# matching on it would report success on all three failure paths - which is
# exactly how a refused step came to be reported as confirmed once already.

if (Get-LocalUser -Name $UserAccount -ErrorAction SilentlyContinue) {
    Write-Output ("  REFUSING - a Windows user named " + $UserAccount + " already exists;")
    Write-Output '  it is not this script''s to touch.  Re-run with -UserAccount <other>.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$outUser = Invoke-SD @("CREATE.ACCOUNT USER $UserAccount")
Write-Output '  --- raw output, printed every run ---'
Write-Output $outUser
Write-Output '  --- end raw output ---'

Note 'refusal prints sysmsg 10100' $true `
     ($outUser -match [regex]::Escape('is not available on a stand-alone SD system'))
Note 'refusal names the group alternative' $true `
     ($outUser -match [regex]::Escape('create.account group'))
# DISQUALIFIER: sysmsg 10007's success wording must be absent.  A step where the
# positive pattern matches AND a disqualifier matches is not a pass either.
Note 'DISQUALIFIER: no "Created" success message' $false `
     ($outUser -match 'User\s+\S+\s+Created')
# And the outcome itself, which no wording can fake.
Note 'no Windows user was made' $false `
     ($null -ne (Get-LocalUser -Name $UserAccount -ErrorAction SilentlyContinue))

# ---------------------------------------------------------------------------
Write-Output ''
Write-Output '=== [7] create.account GROUP still works ========================='
# The other half of the ruling.  Without this the run would be consistent with
# CREATEA refusing everything, which would break the education case the
# stand-alone option exists for.

if (Test-Path -LiteralPath $grpDir) {
    Write-Output ("  a directory already exists at " + $grpDir + " - removing this script's leftover")
    Remove-GroupAccount
}

$outGroup = Invoke-SD @("CREATE.ACCOUNT GROUP $GroupAccount NO.QUERY")
Write-Output '  --- raw output, printed every run ---'
Write-Output $outGroup
Write-Output '  --- end raw output ---'

# sysmsg 10014 is "Group:  %1 created" - the wording of the positive path.
Note 'group account reports created (sysmsg 10014)' $true `
     ($outGroup -match 'Group:\s+\S+\s+created')
# DISQUALIFIER: the stand-alone refusal must NOT have fired on this arm.
Note 'DISQUALIFIER: 10100 did not fire on the GROUP arm' $false `
     ($outGroup -match [regex]::Escape('is not available on a stand-alone SD system'))
# And the outcome, which is what the wording is a claim about.
Note 'the group account directory exists' $true (Test-Path -LiteralPath $grpDir)

}
catch {
    Write-Output ''
    Write-Output ('verify-standalone: unexpected error - ' + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    $failed = $true
}
finally {
    Write-Output ''
    if ($Keep) {
        Write-Output ("-Keep: leaving " + $grpDir + " behind.")
    } else {
        Remove-GroupAccount
    }
}

Write-Output ''
Write-Output '=== summary ========================================================='
$results | Format-Table -AutoSize | Out-String | Write-Output
$passCount = @($results | Where-Object { $_.Result -eq 'PASS' }).Count
Write-Output ("{0}/{1} checks passed" -f $passCount, $results.Count)
Write-Output ''
if ($failed) {
    Write-Output 'verify-standalone: FAILED - read the rows above.'
} else {
    Write-Output 'verify-standalone: PASSED - this stand-alone install opened no port,'
    Write-Output '  wrote no firewall rule, installed no ssh server, refuses'
    Write-Output '  create.account user with sysmsg 10100, and still makes group accounts.'
}

try { Stop-Transcript | Out-Null } catch { }
if ($failed) { exit 1 } else { exit 0 }
