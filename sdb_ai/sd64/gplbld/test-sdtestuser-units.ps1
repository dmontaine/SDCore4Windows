# test-sdtestuser-units.ps1 - drive sdtestuser.ps1's script builders
#
# NO INSTALL, NO ELEVATION, NO ACCOUNT, NO ssh.  PRE_RELEASE_FIXES 59.
#
# WHAT IT IS FOR.  sdtestuser.ps1 builds the SD command lines that an elevated
# child runs to create and delete a throwaway account.  Those lines are fed
# down a pipe to a program that PROMPTS, so a wrong one does not fail - it
# HANGS, eats the following lines as answers, and leaves an account behind.
# That is PRE_RELEASE 14 exactly, and it cost a session plus an elevated
# "sd -cleanup" the day it happened.  Checking them costs nothing here.
#
# BOTH TRAPS BELOW WERE REAL, AND BOTH WERE WRITTEN WRONG FIRST TIME:
#
#   * "CREATE.ACCOUNT USER x STANDARD SSH" - STANDARD is NOT a keyword, it is
#     the default (CREATEA:272).  Naming it passes an unrecognised token.
#   * "DELETE.ACCOUNT x NO.QUERY" - there is no NO.QUERY on that verb.  The
#     confirmation is "input yn" looping "until yn = 'Y' or 'N'" (DELACC:249),
#     so a blank line does not escape it, it SPINS.
#
# ***AND IT CARRIES ITS OWN POSITIVE CONTROL.***  A suite that only ever sees
# correct input cannot tell "the check works" from "the check is vacuous", so
# each rule is also run against a deliberately wrong line and must reject it.
# That is the shape test-reclaim-units.ps1 uses, and the reason it exists is
# PRE_RELEASE 43 - 39 rows that all passed and none of which drove the one
# path that mattered.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'sdtestuser.ps1')

$script:pass = 0
$script:fail = 0

function Note([string]$what, $expected, $actual) {
    $ok = ($expected -ceq $actual)
    if ($ok) {
        $script:pass++
        Write-Output ("  [PASS] {0}: expected '{1}', got '{2}'" -f $what, $expected, $actual)
    } else {
        $script:fail++
        Write-Output ("  [FAIL] {0}: expected '{1}', got '{2}'" -f $what, $expected, $actual)
    }
}

function NoteTrue([string]$what, $actual) { Note $what $true ([bool]$actual) }

Write-Output 'test-sdtestuser-units: driving sdtestuser.ps1 script builders'
Write-Output ("  module: " + (Join-Path $here 'sdtestuser.ps1'))
Write-Output ''

# ---------------------------------------------------------------- create
Write-Output '== 1. New-SdTestUserScript'
$mk = New-SdTestUserScript -Name 'sdtub60' -Password 'PwPwPw-Aa9'
Write-Output ('  lines produced: ' + $mk.Count)
foreach ($l in $mk) {
    if ($l -eq 'PwPwPw-Aa9') { Write-Output '    <password, redacted>' } else { Write-Output ('    ' + $l) }
}

# THREE lines exactly - the command and the password TWICE.  Asserting the
# count is not padding: PowerShell's "+" on an array folds or splits an element
# depending on which side the literal is, so a builder can silently return two
# lines where three were meant and the password prompt then eats the next
# command.
Note 'create: line count' 3 $mk.Count
Note 'create: the command' 'CREATE.ACCOUNT USER sdtub60 SSH' $mk[0]
Note 'create: password supplied twice' $true (($mk[1] -ceq 'PwPwPw-Aa9') -and ($mk[2] -ceq 'PwPwPw-Aa9'))
NoteTrue 'create: does NOT name the STANDARD tier (it is the default, not a keyword)' `
         ($mk[0] -notmatch '\bSTANDARD\b')
NoteTrue 'create: names the SSH route' ($mk[0] -match '\bSSH\b')
NoteTrue 'create: does NOT grant ADMINISTRATOR or PROGRAMMER' `
         ($mk[0] -notmatch '\b(ADMINISTRATOR|PROGRAMMER)\b')

# ---------------------------------------------------------------- delete
Write-Output ''
Write-Output '== 2. Remove-SdTestUserScript'
$rm = Remove-SdTestUserScript -Name 'sdtub60'
Write-Output ('  lines produced: ' + $rm.Count)
foreach ($l in $rm) { Write-Output ('    ' + $l) }

Note 'delete: line count' 2 $rm.Count
Note 'delete: the command' 'DELETE.ACCOUNT sdtub60' $rm[0]
Note 'delete: answers the confirmation' 'Y' $rm[1]
NoteTrue 'delete: does NOT say NO.QUERY (the verb has none; it would hang)' `
         ($rm[0] -notmatch 'NO\.QUERY')

# ---------------------------------------------------------------- home
Write-Output ''
Write-Output '== 3. Get-SdTestUserHome'
$home1 = Get-SdTestUserHome -Name 'SDTUB60'
Write-Output ('  ' + $home1)
NoteTrue 'home: lower-cased (5.12)' ($home1 -cmatch 'sdtub60$')
NoteTrue 'home: under user_accounts' ($home1 -match 'user_accounts')

# ---------------------------------------------------------------- null case
Write-Output ''
Write-Output '== 4. Invoke-SdAsTestUser REFUSES an empty command list'
# ***MATCH THE REFUSAL'S OWN WORDING, NOT MERELY "IT THREW".***  This assertion
# passed on 29 Aug 2026 against PowerShell's PARAMETER BINDER - "Cannot bind
# argument ... because it is an empty array" - while the module's own guard was
# unreachable dead code.  A check that cannot tell those two apart is not a
# check; it is the "test that passes because it did nothing" in miniature, and
# it was found in this very file.  So anchor on wording only the guard emits.
$threw = $false
$msg = ''
try {
    Invoke-SdAsTestUser -Name 'x' -Password 'y' -Commands @() | Out-Null
} catch {
    $threw = $true
    $msg = $_.Exception.Message
    Write-Output ('  refused: ' + $msg)
}
NoteTrue 'null case: an empty command list is refused, not run' $threw
NoteTrue 'null case: refused by the MODULE and not by the parameter binder' `
         ($msg -match 'measure nothing')
NoteTrue 'control: the binder''s own wording would NOT satisfy that check' `
         (-not ('Cannot bind argument to parameter ''Commands'' because it is an empty array.' -match 'measure nothing'))

# ---------------------------------------------------------------- password
Write-Output ''
Write-Output '== 5. New-SdTestPassword survives the askpass batch'
$pw = New-SdTestPassword
Write-Output ('  generated ' + $pw.Length + ' characters (value not printed)')
NoteTrue 'password: 24 characters (20 drawn + the -Aa9 suffix)' ($pw.Length -eq 24)
NoteTrue 'password: ends -Aa9, so the class policy is satisfied' ($pw -cmatch '\-Aa9$')
NoteTrue 'password: carries no cmd.exe metacharacter' ($pw -notmatch '[%&^|<>"]')

# ---------------------------------------------------------------- controls
Write-Output ''
Write-Output '== 6. POSITIVE CONTROLS - the rules above must REJECT a wrong line'
Write-Output '   (each is the mistake actually made while writing the module)'

$badCreate = 'CREATE.ACCOUNT USER sdtub60 STANDARD SSH'
$badDelete = 'DELETE.ACCOUNT sdtub60 NO.QUERY'
$badDeleteLines = @($badDelete)

NoteTrue 'control: the STANDARD rule REJECTS the line that names it' `
         (-not ($badCreate -notmatch '\bSTANDARD\b'))
NoteTrue 'control: the NO.QUERY rule REJECTS the line that says it' `
         (-not ($badDelete -notmatch 'NO\.QUERY'))
NoteTrue 'control: the delete line-count rule REJECTS a script with no Y' `
         (-not ($badDeleteLines.Count -eq 2))

# ------------------------------------------------------- the writability gate
Write-Output ''
Write-Output '== 7. Test-SdDirWritable - BOTH DIRECTIONS, with real directories'
Write-Output '   (29 Aug 2026: the account directory is NOT reachable by the unelevated'
Write-Output '    parent by default, which is what this gate exists to catch)'

# THE POSITIVE CONTROL FIRST, AND IT IS THE ONE THAT MATTERS.  A gate that only
# ever says no passes every negative row and is still useless - PRE_RELEASE 43,
# where 39 accepted rows all drove the refusal and none drove the one path that
# had to succeed.  So: a directory this process really can write.
$okDir = Join-Path $env:TEMP ('sdtu-units-ok-' + $PID)
if (-not (Test-Path -LiteralPath $okDir)) { $null = New-Item -ItemType Directory -Path $okDir }
Write-Output ('  writable fixture:  ' + $okDir)
NoteTrue 'Test-SdDirWritable says YES to a directory this process can write' `
         (Test-SdDirWritable -Path $okDir)

# AND IT MUST LEAVE NOTHING BEHIND.  A probe file that survives would be
# planted inside a real account directory on every run.
$leftovers = @(Get-ChildItem -LiteralPath $okDir -Force -ErrorAction SilentlyContinue)
Note 'Test-SdDirWritable leaves no probe file behind' 0 $leftovers.Count

# THE NEGATIVE, WITH A DIRECTORY THAT DENIES THIS USER.  Built by DENYING the
# current user rather than by naming one that does not exist, so it fails the
# way a real account directory fails - on the ACL, not on Test-Path.
$noDir = Join-Path $env:TEMP ('sdtu-units-deny-' + $PID)
if (-not (Test-Path -LiteralPath $noDir)) { $null = New-Item -ItemType Directory -Path $noDir }
$denied = $false
try {
    $acl = Get-Acl -LiteralPath $noDir
    $acl.SetAccessRuleProtection($true, $false)
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().User
    # Read, so the directory can still be removed by its owner afterwards, and
    # an explicit DENY on write, which beats the owner's implicit rights.
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $me, 'ReadAndExecute', 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    $acl.AddAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule(
        $me, 'CreateFiles, Write', 'ContainerInherit, ObjectInherit', 'None', 'Deny')))
    Set-Acl -LiteralPath $noDir -AclObject $acl
    $denied = $true
} catch {
    Write-Output ('  could not build the denied fixture: ' + $_.Exception.Message)
}
Write-Output ('  denied fixture:    ' + $noDir)

# ***REFUSE THE NULL CASE: IF THE FIXTURE WAS NOT BUILT, FAIL - DO NOT SKIP.***
# A negative row that passes because nothing denied anything is the "test that
# passes because it did nothing" the instrument rule forbids.
NoteTrue 'the denied fixture was actually built (a row that cannot fail is not a test)' $denied
if ($denied) {
    NoteTrue 'Test-SdDirWritable says NO to a directory this process is denied' `
             (-not (Test-SdDirWritable -Path $noDir))
}

# AND A PATH THAT IS NOT THERE AT ALL IS ALSO NO, NOT AN EXCEPTION.
NoteTrue 'Test-SdDirWritable says NO to a path that does not exist' `
         (-not (Test-SdDirWritable -Path (Join-Path $env:TEMP ('sdtu-units-absent-' + $PID))))

foreach ($d in @($okDir, $noDir)) {
    if (Test-Path -LiteralPath $d) {
        try {
            $a = Get-Acl -LiteralPath $d
            $a.SetAccessRuleProtection($false, $true)
            $a.Access | Where-Object { $_.AccessControlType -eq 'Deny' } |
                ForEach-Object { $null = $a.RemoveAccessRule($_) }
            Set-Acl -LiteralPath $d -AclObject $a
        } catch { }
        Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# --------------------------------------------- the verifier's own refusal path
Write-Output ''
Write-Output '== 8. verify-nocase.ps1 REFUSES with no test account'
Write-Output '   (the shortcut it must never take is falling back to the invoking user,'
Write-Output '    who under PRE_RELEASE 56 is elevated at LOGIN and lands in SDSYS)'

# RUN THE REAL SCRIPT.  It reaches this branch BEFORE assert-current, so it
# needs no install - which is the whole reason that check was put first.
$nocase = Join-Path $here 'verify-nocase.ps1'
if (-not (Test-Path -LiteralPath $nocase)) {
    Note 'verify-nocase.ps1 is beside this test' $true $false
} else {
    $refusal = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $nocase 2>&1 |
                Out-String)
    $rc = $LASTEXITCODE
    Write-Output ('  exit ' + $rc + ', ' + $refusal.Length + ' characters')
    foreach ($l in ($refusal -split "`n")) {
        if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) }
    }
    Note 'verify-nocase with no -TestUser exits 2 (could not run), not 0 or 1' 2 $rc

    # ANCHOR ON WORDING ONLY THE REFUSAL EMITS.  "test account" appears in the
    # help text too; "no test account was supplied" is printed on this path and
    # nowhere else.
    NoteTrue 'it names what is missing, in its own words' `
             ($refusal -match 'no test account was supplied')

    # AND THE DISQUALIFIERS: it must NOT have gone on to measure anything.
    NoteTrue 'it did not reach the probe (no DIRFILE/PASSED/FAILED in the output)' `
             ($refusal -notmatch 'DIRFILE|verify-nocase: PASSED|verify-nocase: FAILED')
}

# ------------------------------------------------- strict mode must not leak
Write-Output ''
Write-Output '== 9. dot-sourcing sdtestuser.ps1 must NOT turn strict mode on in the caller'
Write-Output '   (it did until 29 Aug 2026, and VerifyInstall1.ps1 dot-sources it)'

# ***THE CALLER IS A SEPARATE PROCESS, BECAUSE THIS ONE IS ALREADY STRICT.***
# test-sdtestuser-units.ps1 sets Set-StrictMode -Version Latest at the top, so
# a check made here would pass whatever the module does - the "test that passes
# because it did nothing" in its exact form.  The probe below starts lax.
$leakProbe = Join-Path $env:TEMP ('sdtu-units-leak-' + $PID + '.ps1')
$mod = (Join-Path $here 'sdtestuser.ps1') -replace '\\', '/'
Set-Content -LiteralPath $leakProbe -Encoding ascii -Value @(
    '$ErrorActionPreference = ''Continue''',
    'try { $a = $NoSuchVariable; Write-Output "BEFORE=lax" } catch { Write-Output "BEFORE=strict" }',
    (". '" + $mod + "'"),
    'try { $b = $StillNoSuchVariable; Write-Output "AFTER=lax" } catch { Write-Output "AFTER=strict" }',
    '$o = [pscustomobject]@{ DisplayName = ''SD 1.0'' }',
    'try { $null = $o.InstallLocation; Write-Output "PROP=lax" } catch { Write-Output "PROP=strict" }'
)
$leakOut = (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $leakProbe 2>&1 | Out-String)
Remove-Item -LiteralPath $leakProbe -Force -ErrorAction SilentlyContinue
foreach ($l in ($leakOut -split "`n")) { if ($l.Trim() -ne '') { Write-Output ('  | ' + $l.TrimEnd()) } }

# THE NULL CASE FIRST: if the probe did not start, BEFORE is missing and every
# row below would pass on an empty string.
NoteTrue 'the leak probe actually ran (BEFORE line present)' ($leakOut -match 'BEFORE=')
NoteTrue 'the probe starts lax, so the AFTER rows can mean something' ($leakOut -match 'BEFORE=lax')
NoteTrue 'an undefined variable is still allowed after dot-sourcing' ($leakOut -match 'AFTER=lax')
NoteTrue 'a missing property is still allowed after dot-sourcing' ($leakOut -match 'PROP=lax')

# AND THE STRICTNESS IS STILL THERE WHERE IT WAS WANTED: the functions set it
# for themselves, so a bad reference inside one is still caught.  Driven
# through the real function rather than asserted about the source.
$strictKept = $false
try   { $null = Invoke-SdTestNative -Exe 'x' -CmdArgs @() -WorkDir '' }
catch { $strictKept = $true }
NoteTrue 'the module''s own functions still fail loudly on a bad call' $strictKept

Write-Output ''
Write-Output ("test-sdtestuser-units: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
