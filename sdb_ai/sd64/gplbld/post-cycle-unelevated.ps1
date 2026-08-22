# post-cycle-unelevated.ps1 - the verifiers that need NO elevation, in one command
#
#   Run from an ORDINARY PowerShell.  It REFUSES an elevated one - see below.
#
# WHY IT EXISTS, 22 Aug 2026.  post-cycle-elevated.ps1 runs nine verifiers and
# there are twenty-four in this directory.  Seven of the fifteen it leaves out
# need no elevation at all, which meant they could be run by anybody, at any
# time, for free - and so nobody ran them.  Between 21 Aug and 22 Aug not one of
# the seven appears in any transcript, and three of the twenty-four
# (verify-scramlogin, verify-setpw, verify-tierapi) were not named anywhere in
# PROJECT_STATUS.md at all.  That is the same failure verify-delaccount had:
# a verifier nobody runs is a guard that has already stopped guarding, and
# nothing reports its absence.
#
# IT MUST NOT BE RUN ELEVATED, AND THAT IS NOT TIDINESS.  verify-credacl.ps1
# asks whether an ORDINARY user can read or write sdsys\$cred.  secure-cred.ps1
# grants Administrators Full, so an elevated session can do both by design - it
# would pass every check while proving the opposite of what the file claims.  A
# test that passes for the wrong reason is worse than one that is not run,
# because it is believed.  The others are indifferent to the token; this one
# decides the rule, so the gate below is unconditional.
#
# IT SPENDS NO PREFIXES, which is the other reason to run it often.  Every step
# in post-cycle-elevated.ps1 burns a single-use account name, so re-running it
# to check something costs seven names and an argument list.  Nothing here
# creates a Windows account: the probes live inside the invoking user's own SD
# account, or in a temporary copy of a config file, and each step cleans up
# after itself.  Run it as many times as you like.
#
# WHAT IT DOES NOT COVER.  Eight verifiers need elevation and are still not in
# either runner - apiport, catgate, nonet, osusers, scramlogin, sshonly,
# tierapi, apiname.  PROJECT_STATUS.md carries the inventory and says which are
# deliberately out (sshonly and allowgroups test Windows rather than SD;
# apiname answered a question once).  Do not read this file's existence as
# "the rest are covered".

[CmdletBinding()]
param(
    # Keep going after a failing step.  Off by default: a failed check here
    # usually means the install is not what the last cycle left, and the next
    # step's result would be describing the same broken tree.
    [switch] $ContinueOnFailure
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# THE GATE.  Refuse elevation outright, for the verify-credacl reason above.
if (([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()
    ).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'post-cycle-unelevated: this is an ELEVATED PowerShell, and these checks need an ordinary one.'
    Write-Output ''
    Write-Output '  verify-credacl.ps1 asks whether an ORDINARY user can read or write sdsys\$cred.'
    Write-Output '  Administrators are granted Full by secure-cred.ps1, so an elevated run would pass'
    Write-Output '  every check and prove the opposite of what it claims.  Open a normal PowerShell.'
    exit 2
}

# ---------------------------------------------------------------------------
# 22 Aug 26 - IS SD ACTUALLY RUNNING?  The same guard as the elevated runner and
# for the same reason: assert-current compares hashes and mtimes, so a STOPPED
# server is perfectly "current" and every verifier prints a green
# "matches source" line immediately before failing on its first SD command.
#
# Five of the seven steps here drive real SD sessions (credacl is the exception,
# and allowgroups touches only a copy of sshd_config), so a stopped server fails
# most of this file one step at a time.
#
# IT REFUSES RATHER THAN STARTING IT - and here it could not start it anyway:
# this runner deliberately holds an UNELEVATED token, which cannot start a
# service.  Saying so plainly beats five identical failures.
$svc = Get-Service -Name 'SD' -ErrorAction SilentlyContinue
$sdwind = @(Get-Process -Name 'sdwind' -ErrorAction SilentlyContinue)
if ((-not $svc) -or ($svc.Status -ne 'Running') -or ($sdwind.Count -eq 0)) {
    Write-Output 'post-cycle-unelevated: REFUSING - SD is not running.'
    Write-Output ("  service: {0}    sdwind processes: {1}" -f
                  $(if ($svc) { $svc.Status } else { 'not installed' }), $sdwind.Count)
    Write-Output ''
    Write-Output '  Starting it needs elevation, which this runner does not have by design.'
    Write-Output '  From an ELEVATED shell:   C:\Windows\System32\sc.exe start SD'
    exit 2
}

# The same transcript reasoning as cycle.ps1 and the elevated runner: a run
# whose output is not kept is a run that has to be repeated to be quoted.  Not
# under C:\ProgramData\SD, which a cycle deletes.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$summary = Join-Path $logDir ('post-cycle-unelevated-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

# ---------------------------------------------------------------------------
# ORDER.  verify-credacl first, because it is the one that decides a security
# rule and the one the gate above exists for: if the session is somehow still
# privileged, it fails here rather than after six passing steps have suggested
# the tree is fine.  The rest are independent of each other - none creates an
# account, and each cleans up what it made - so the remaining order is only
# cheapest-first, to fail fast on a stale tree.
#
# Name => hashtable of parameters, splatted by NAME.  An empty hashtable means
# "no arguments", which splats correctly too.  See post-cycle-elevated.ps1's
# comment for why this is a hashtable and not an array: an array binds
# POSITIONALLY and silently gave verify-tiers.ps1 a $Prefix of "-Prefix".
$steps = @(
    @{ Name = 'verify-credacl.ps1';     P = @{} },
    @{ Name = 'verify-nocase.ps1';      P = @{} },
    @{ Name = 'verify-setpw.ps1';       P = @{} },
    @{ Name = 'verify-allowgroups.ps1'; P = @{} },
    @{ Name = 'verify-keys.ps1';        P = @{} },
    @{ Name = 'verify-editkeys.ps1';    P = @{} },
    @{ Name = 'verify-lcnames.ps1';     P = @{} }
)

$lines  = @()
$failed = 0
foreach ($s in $steps) {
    $path = Join-Path $PSScriptRoot $s.Name
    if (-not (Test-Path -LiteralPath $path)) {
        Write-Output ''
        Write-Output ('===== ' + $s.Name + ' - NOT FOUND, skipped =====')
        $lines += ('{0,-28} {1}' -f $s.Name, 'NOT FOUND')
        $failed++
        continue
    }
    Write-Output ''
    Write-Output ('===== ' + $s.Name + ' =====')
    $splat = $s.P
    & $path @splat
    $code = $LASTEXITCODE
    if ($code -ne 0) { $failed++ }
    $lines += ('{0,-28} exit {1}' -f $s.Name, $code)

    if ($code -ne 0 -and -not $ContinueOnFailure) {
        Write-Output ''
        Write-Output ("post-cycle-unelevated: STOPPING - {0} exited {1}." -f $s.Name, $code)
        Write-Output '  Re-run with -ContinueOnFailure to see the rest anyway.'
        break
    }
}

Write-Output ''
Write-Output '===== post-cycle-unelevated summary ====='
$lines | ForEach-Object { Write-Output $_ }
$lines | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ''
Write-Output ('summary written to: ' + $summary)

if ($failed -gt 0) {
    Write-Output ("post-cycle-unelevated: {0} step(s) did not exit 0." -f $failed)
    exit 1
}
Write-Output 'post-cycle-unelevated: every step exited 0.'
exit 0
