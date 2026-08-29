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

Write-Output ''
Write-Output ("test-sdtestuser-units: {0} passed, {1} failed" -f $script:pass, $script:fail)
if ($script:fail -gt 0) { exit 1 }
exit 0
