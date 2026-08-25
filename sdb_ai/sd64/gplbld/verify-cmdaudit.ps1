# verify-cmdaudit.ps1 - prove LOGIN sees a COMMAND LINE as a command line, and
# an interactive session as an interactive one.  PROJECT_STATUS.md 7 step 9.
#
#   powershell -File verify-cmdaudit.ps1        run the checks
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# WHY THIS EXISTS.  The owner's ruling of 24 Aug 2026 - "sd <command> is batch,
# so it is not interactive" - is one conjunct at LOGIN:669, "and
# batch.command = ''", with batch.command HOISTED out of the batch gate below
# it so both tests can see it.  The hoist is the fragile part: move it back, or
# drop it, and batch.command is empty at the password test for every session,
# which silently restores the behaviour the ruling removed.
#
# ***WHAT IT PROVES, AND WHAT IT DOES NOT.***  It proves the GATE'S INPUT: that
# LOGIN computed a non-empty batch.command for "sd <command>" and an empty one
# for a plain session.  ***IT DOES NOT PROVE THE PROMPT WAS SKIPPED*** - that
# is the branch, not the input, and the branch cannot be tested automatically
# at all.  PROJECT_STATUS.md 7 step 9 has the scope and the four constraints
# that close that door; the short form is that the password prompt needs an
# elevated session, at a REAL console, on an account with NO credential, run AS
# that account - and an elevated token for another local user cannot be had
# non-interactively without weakening the machine.  So this is the automatable
# half, and saying which half it is matters more than the check itself.
#
# THE OBSERVABLE IS LOGIN'S OWN AUDIT RECORD, LOGIN:722-726:
#
#     if batch.command = '' then
#        void kernel(K$AUDIT, 'LOGIN account=' : audit.account)
#     end else
#        void kernel(K$AUDIT, 'LOGIN account=' : audit.account : ' command=' : batch.command)
#     end
#
# That branch reads the SAME variable the password gate reads, three lines
# apart, so it is not a proxy for the input - it IS the input.  A regression
# that emptied batch.command would stop the "command=" form appearing here.
#
# RUN IT ELEVATED, AND THAT IS NOT A PREFERENCE.  Two things need it: the audit
# trail is locked to SYSTEM and Administrators by secure-audit.ps1, so an
# ordinary token cannot read it at all - measured, "Permission denied" - and an
# unelevated "sd <command>" is refused unless the command is on the account's
# batch.jobs list (section 7 step 9's gate), which would make the command case
# untestable for a different reason.
#
# IT SPENDS NO PREFIX, CREATES NO ACCOUNT, AND WRITES NOTHING but two ordinary
# SD sessions' worth of audit records.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$audit  = Join-Path $env:ProgramData  'SD\sdsys\audit'

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check    = $step
        Expected = $expected
        Observed = $got
        Result   = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $step, $expected, $got)
}

# 24 Aug 26 - THE VERDICT LINE.  Kept BYTE-FOR-BYTE IDENTICAL to the copies in
# verify-createaccount.ps1 and verify-sshonly.ps1, and test-verdict-units.ps1
# asserts that across all three.  If one changes, change all of them.
function Write-Verdict($name) {
    $all      = @($script:results)
    $decisive = @($all | Where-Object { $_.Decisive -eq 'yes' })
    $failed   = @($decisive | Where-Object { $_.Result -ne 'PASS' })

    Write-Output ""
    if ($decisive.Count -eq 0) {
        Write-Output ("{0}: FAILED - NO DECISIVE CHECK RAN, so this run proves nothing." -f $name)
        Write-Output ("  {0} row(s) recorded, none of them decisive." -f $all.Count)
        $script:fatal = $true
        return
    }
    if ($failed.Count -gt 0) {
        Write-Output ("{0}: FAILED - {1} of {2} decisive checks failed:" -f $name, $failed.Count, $decisive.Count)
        $failed | ForEach-Object { Write-Output ("    " + $_.Check) }
        $script:fatal = $true
        return
    }
    Write-Output ("{0}: PASSED - {1} of {1} decisive checks passed, {2} row(s) in all." -f
                  $name, $decisive.Count, $all.Count)
}

# ---------------------------------------------------------------- the parser
#
# PURE, AND SEPARATE FROM EVERYTHING THAT TOUCHES THE MACHINE, so
# test-verdict-units.ps1 can lift it by AST and drive it with synthetic text.
# That is the whole of what can be tested without an install, so it is worth
# keeping the machine out of it.
#
# THE ORDER OF THE TWO PATTERNS MATTERS.  "LOGIN account=X command=Y" also
# matches a pattern looking for "LOGIN account=X", so the command form is
# tested FIRST and the bare form only where the command form did not match.
# Getting that backwards would report every command session as interactive -
# the exact regression this script exists to catch, reported as a pass.
function Get-LoginRecords([string] $text) {
    $out = New-Object System.Collections.ArrayList
    if ([string]::IsNullOrEmpty($text)) { return @() }
    foreach ($line in ($text -split "`n")) {
        $l = $line.Trim()
        if ($l -match 'LOGIN account=(\S+)\s+command=(.+?)\s*$') {
            $null = $out.Add([pscustomobject]@{
                Account = $Matches[1]; Command = $Matches[2].Trim(); HasCommand = $true })
        } elseif ($l -match 'LOGIN account=(\S+)\s*$') {
            $null = $out.Add([pscustomobject]@{
                Account = $Matches[1]; Command = ''; HasCommand = $false })
        }
    }
    return @($out)
}

# ------------------------------------------------------------- preconditions

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'verify-cmdaudit: this needs an ELEVATED session and this one is not.'
    Write-Output '  The audit trail is locked to SYSTEM and Administrators (secure-audit.ps1),'
    Write-Output '  and an unelevated "sd <command>" is refused unless the command is on the'
    Write-Output '  account batch.jobs list. Run it from an ELEVATED PowerShell.'
    exit 2
}

& (Join-Path $PSScriptRoot 'assert-current.ps1') | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Output 'verify-cmdaudit: the installed tree does not match source - run a cycle first.'
    exit 2
}

foreach ($p in @($sdExe, $audit)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("verify-cmdaudit: {0} does not exist - nothing could be measured." -f $p)
        exit 2
    }
}

Write-Output ("verify-cmdaudit: as {0}, ELEVATED" -f $id.Name)
Write-Output ("  sd    {0}" -f $sdExe)
Write-Output ("  audit {0}" -f $audit)

# ---------------------------------------------------------------- the probes

# BY LENGTH, like verify-apiname.ps1: only the bytes this run added are read,
# so a record left by an earlier session cannot score for it.
$before = ''
try { $before = [IO.File]::ReadAllText($audit) } catch {
    Write-Output ("verify-cmdaudit: the audit trail could not be read - " + $_.Exception.Message)
    exit 2
}
Write-Output ("  audit is {0} bytes before" -f $before.Length)
Write-Output ''

# --- 1. A COMMAND LINE.  stdin is fed $null rather than inherited: this script
#     may be run from a console, and a session that reached a prompt with a
#     console behind it would BLOCK for ever (section 7 step 9). Nothing here
#     depends on stdin, so closing it costs nothing and removes the hang.
Write-Output '  running: sd COUNT VOC   (a command line)'
$cmdOut = ''
try { $cmdOut = ($null | & $sdExe '-QUIET' 'COUNT' 'VOC' 2>&1 | Out-String) } catch {
    $cmdOut = "(threw: " + $_.Exception.Message + ")"
}
Write-Output ("    exit {0}" -f $LASTEXITCODE)

# --- 2. AN INTERACTIVE SESSION.  No command on the line; OFF is fed on stdin,
#     which is how every other verifier drives SD. batch.command comes from the
#     COMMAND LINE, so feeding OFF on stdin leaves it empty - which is the case
#     under test.
Write-Output '  running: sd            (no command, OFF piped)'
$intOut = ''
try { $intOut = (("`nOFF`n") | & $sdExe '-QUIET' 2>&1 | Out-String) } catch {
    $intOut = "(threw: " + $_.Exception.Message + ")"
}
Write-Output ("    exit {0}" -f $LASTEXITCODE)
Write-Output ''

$after = ''
try { $after = [IO.File]::ReadAllText($audit) } catch { }
$tail = ''
if ($after.Length -gt $before.Length) { $tail = $after.Substring($before.Length) }

Write-Output ("  audit is {0} bytes after, {1} new" -f $after.Length, $tail.Length)

# ---------------------------------------------------------------- the checks

# ***THE NULL CASE FIRST, AND IT IS THE ONE THAT MATTERS.***  If the audit did
# not grow, neither session reached LOGIN and every check below would pass by
# describing an empty string. Refuse out loud instead.
Note 'the audit trail grew' $true ($tail.Length -gt 0) $true
if ($tail.Length -eq 0) {
    Write-Output ''
    Write-Output 'verify-cmdaudit: FAILED - nothing was written to the audit trail, so'
    Write-Output '  neither session reached LOGIN and nothing was measured. Check that SD'
    Write-Output '  is running and that both commands above exited 0.'
    Write-Output ''
    Write-Output '--- what the two sessions printed ---'
    Write-Output $cmdOut
    Write-Output $intOut
    exit 1
}

$new = Get-LoginRecords $tail
Note 'LOGIN records were added by this run' $true ($new.Count -ge 2) $true

$withCmd = @($new | Where-Object { $_.HasCommand })
$bare    = @($new | Where-Object { -not $_.HasCommand })

# THE TWO DECISIVE ROWS.  Each is the presence of one FORM, and the two forms
# are written by the two branches of one if/else - so both appearing means
# LOGIN took both branches, which is the whole claim.
Note 'a COMMAND LINE was recorded with command=' $true ($withCmd.Count -ge 1) $true
Note 'an INTERACTIVE session was recorded without command=' $true ($bare.Count -ge 1) $true

# AND THE COMMAND ITSELF, because "command=" with the wrong text would mean
# batch.command held something other than the command line.
$sawCount = @($withCmd | Where-Object { $_.Command -match 'COUNT' })
Note 'the recorded command is the one that was run' $true ($sawCount.Count -ge 1) $true

# Reported, not asserted: the account each was recorded against.
foreach ($r in $new) {
    Note ("recorded: account={0} command='{1}'" -f $r.Account, $r.Command) $r.Account $r.Account $false
}

# ---------------------------------------------------------------------- report

Write-Output ''
Write-Output '--- the audit records this run added ---'
foreach ($line in ($tail -split "`n")) {
    if ($line.Trim() -ne '') { Write-Output ("  " + $line.Trim()) }
}
Write-Output ''

$results | Format-Table -AutoSize -Wrap | Out-String | Write-Output

if ($fatal) {
    Write-Output 'verify-cmdaudit: the two LOGIN forms did not both appear.'
    Write-Output ''
    Write-Output '  LOGIN:722-726 writes "command=" only when batch.command is non-empty,'
    Write-Output '  and batch.command is assigned at LOGIN:668, hoisted there so the password'
    Write-Output '  gate three lines below can read it. If the command form is MISSING, that'
    Write-Output '  assignment has moved or gone - which also silently restores the password'
    Write-Output '  prompt on a command line that section 7 step 9 removed.'
}

Write-Verdict 'verify-cmdaudit'

if ($fatal) { exit 1 }
exit 0
