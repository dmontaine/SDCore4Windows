# test-reconcile-units.ps1 - unit test for reconcile-accounts.ps1's decision
# table.  Needs NO install, NO elevation, NO register and NO account, so it
# costs nothing to run and can run before the sweep is handed to sdsvc.exe.
#
#   powershell -File test-reconcile-units.ps1
#
# Exit 0 every row passed, 1 a row failed, 2 the subject could not be read.
#
# START-HISTORY:
# 03 Sep 26 Windows port - written with the sweep, PRE_RELEASE_FIXES.md 93 and
#           65.  The sweep runs as LocalSystem at every service start and
#           deletes account directories named in a register file, so its
#           decision table is the security boundary of the whole feature - and
#           it is the part that cannot be exercised by running the thing,
#           because every path through it ends in "and then nothing happened".
# END-HISTORY
#
# WHAT IT GUARDS, AND WHY EACH ROW IS WORTH A TEST.
#
# TWO OF THESE ROWS ARE WHOLE ENTRIES IN THEIR OWN RIGHT.
#
#   THE TYPE ROW.  CREATE.ACCOUNT has three types and only USER has a Windows
#   login (CREATEA:1042, grant.os.access at :1171).  A sweep that reads "no
#   Windows account of this name" as "stale" deletes every GROUP and OTHER
#   account and SDSYS with them.  PRE_RELEASE 93 records that the check written
#   for that entry did exactly this on its first run, which is why the type is
#   read out of ACC$GROUP rather than guessed from the name.
#
#   THE COULD-NOT-TELL ROW IS PRE_RELEASE 96 IN ITS EXPENSIVE FORM.  That entry
#   is about predicates answering "no" and "I could not tell" with the same
#   FALSE; here the same collapse would delete the entire register the first
#   time a domain controller was unreachable at boot.  So $lookupOk is a
#   separate input and the table refuses on it BEFORE it looks at anything
#   else, and this file drives that ordering rather than trusting it.
#
# THE FUNCTIONS ARE LIFTED OUT OF THE SHIPPED FILE BY THE PowerShell PARSER,
# NOT COPIED - the technique test-reclaim-units.ps1 and test-apiidentity-units
# .ps1 both use, and for the reason they both give: a test carrying its own
# copy of the table passes for ever while the shipped one rots.

param(
    # The subject.  Overridable so a candidate file can be driven before it
    # replaces the shipped one.
    [string] $Sweep = ''
)

$ErrorActionPreference = 'Stop'

$pass = 0
$fail = 0

function Note([bool]$ok, [string]$what, [string]$detail = '') {
    if ($ok) {
        $script:pass++
        Write-Host ("  PASS  " + $what)
    } else {
        $script:fail++
        Write-Host ("  FAIL  " + $what + $(if ($detail -ne '') { "  <- " + $detail } else { '' }))
    }
}

# --- lift the functions out of the shipped file ----------------------------

if ($Sweep -eq '') { $Sweep = Join-Path $PSScriptRoot 'reconcile-accounts.ps1' }
$Sweep = [System.IO.Path]::GetFullPath($Sweep)

Write-Host ''
Write-Host ('test-reconcile-units: subject ' + $Sweep)

if (-not (Test-Path -LiteralPath $Sweep)) {
    Write-Host ('  FAIL  no such file: ' + $Sweep)
    Write-Host ''
    Write-Host 'test-reconcile-units: 0 passed, 1 failed'
    exit 2
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Sweep, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host ('  FAIL  ' + $Sweep + ' does not parse: ' + $errors.Count + ' error(s)')
    $errors | ForEach-Object { Write-Host ('        line ' + $_.Extent.StartLineNumber + ': ' + $_.Message) }
    Write-Host ''
    Write-Host 'test-reconcile-units: 0 passed, 1 failed'
    exit 2
}

$funcs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
Write-Host ('test-reconcile-units: parsed, ' + $tokens.Count + ' tokens, ' +
            $funcs.Count + ' function(s): ' + (($funcs | ForEach-Object { $_.Name }) -join ', '))

# REFUSE THE NULL CASE OUT LOUD.  A file whose functions the parser cannot find
# parses with zero errors - that is exactly how an embedded BOM scored a false
# green as step 17 of b18 - so the names are asserted, not assumed.
$wanted = @('Norm', 'Get-RecordLogin', 'Get-ReconcileRefusal', 'Get-Verdict',
            'Resolve-WindowsAccount', 'Get-Records')
foreach ($w in $wanted) {
    $d = @($funcs | Where-Object { $_.Name -eq $w })
    if ($d.Count -ne 1) {
        Write-Host ('  FAIL  ' + $Sweep + ' defines ' + $d.Count + ' function(s) called ' + $w + ', expected exactly 1')
        Write-Host ''
        Write-Host 'test-reconcile-units: 0 passed, 1 failed'
        exit 2
    }
    . ([scriptblock]::Create($d[0].Extent.Text))
}

foreach ($w in $wanted) {
    if (-not (Get-Command $w -ErrorAction SilentlyContinue)) {
        Write-Host ('  FAIL  ' + $w + ' did not define itself after being lifted')
        Write-Host ''
        Write-Host 'test-reconcile-units: 0 passed, 1 failed'
        exit 2
    }
}

# --- the fixtures ----------------------------------------------------------
#
# Invented throughout.  Nothing here touches the machine, and the root below is
# deliberately NOT this machine's account root: a test that happened to name
# the real one could pass by accident on a machine where the real one is what
# the code looked at.

$ROOT = 'D:\TestAccounts'

function Acc($recordId, $group, $dir, $winUser, $live, $ok) {
    return (Get-ReconcileRefusal 'accounts' $recordId $group $dir $ROOT $winUser $live $ok)
}
function Osu($recordId, $winUser, $live, $ok) {
    return (Get-ReconcileRefusal 'os.users' $recordId '' '' $ROOT $winUser $live $ok)
}

Write-Host ''
Write-Host '--- Get-RecordLogin: the account TYPE is read, not guessed'

Note ((Get-RecordLogin 'sdu_bob')  -eq 'bob')  'sdu_bob is a USER account whose login is bob' (Get-RecordLogin 'sdu_bob')
Note ((Get-RecordLogin 'SDU_Bob')  -eq 'Bob')  'the sdu_ prefix is matched case-insensitively' (Get-RecordLogin 'SDU_Bob')
Note ((Get-RecordLogin 'sdu_a.b-c') -eq 'a.b-c') 'a login with punctuation survives' (Get-RecordLogin 'sdu_a.b-c')
Note ((Get-RecordLogin 'payroll')  -eq '')     'a GROUP account has no login'
Note ((Get-RecordLogin '')         -eq '')     'an OTHER account has no login'
Note ((Get-RecordLogin 'sdsys')    -eq '')     'sdsys has no login'
Note ((Get-RecordLogin 'sdu_')     -eq '')     'a bare sdu_ names nobody'
Note ((Get-RecordLogin 'xsdu_bob') -eq '')     'sdu_ must be the START of the field, not anywhere in it'

Write-Host ''
Write-Host '--- accounts: the case the sweep exists for'

# THE CONTROL FOR EVERYTHING BELOW.  If this row ever stops returning '', the
# refusals that follow are passing because the fixture is wrong rather than
# because the table works.
Note ((Acc 'bob' 'sdu_bob' "$ROOT\bob" 'bob' '' $true) -eq '') `
     'a stale USER account is cleared for removal' (Acc 'bob' 'sdu_bob' "$ROOT\bob" 'bob' '' $true)

Note ((Acc 'bob' 'sdu_bob' "$ROOT\BOB" 'bob' '' $true) -eq '') `
     'the directory leaf matches case-insensitively' (Acc 'bob' 'sdu_bob' "$ROOT\BOB" 'bob' '' $true)

Note ((Acc 'bob' 'sdu_bob' "$ROOT\bob\" 'bob' '' $true) -eq '') `
     'a trailing separator does not defeat the leaf test' (Acc 'bob' 'sdu_bob' "$ROOT\bob\" 'bob' '' $true)

Write-Host ''
Write-Host '--- accounts: an account with no Windows user is EXEMPT, not stale'

$r = Acc 'sdsys' 'sdsys' 'C:\ProgramData\SD\sdsys' '' '' $true
Note ($r.StartsWith('exempt: ')) 'sdsys is exempt' $r
$r = Acc 'SDSYS' 'sdsys' 'C:\ProgramData\SD\sdsys' '' '' $true
Note ($r.StartsWith('exempt: ')) 'SDSYS in upper case is exempt too' $r
$r = Acc 'payroll' 'payroll' "$ROOT\payroll" '' '' $true
Note ($r.StartsWith('exempt: ')) 'a GROUP account is exempt' $r
$r = Acc 'legacy' '' "$ROOT\legacy" '' '' $true
Note ($r.StartsWith('exempt: ')) 'an OTHER account, with no ACC$GROUP at all, is exempt' $r

# AND A TRUNCATED RECORD IS NOT ONE OF THEM.  An empty file reads back as
# ACC$GROUP="" exactly like an OTHER account does, so without a pathname row a
# corrupt record would be scored healthy and left in the register for ever.
$r = Acc 'stump' '' '' '' '' $true
Note ($r -ne '' -and -not $r.StartsWith('exempt: ')) `
     'a record with no ACC$PATH is REFUSED, not exempted as an OTHER account' $r
Note ($r -like '*truncated*') 'and it says truncated, so the reason is actionable' $r

# AND EXEMPT IS NOT THE SAME ANSWER AS PROCEED.  The caller counts them
# differently and one of them deletes.
Note ((Acc 'payroll' 'payroll' "$ROOT\payroll" '' '' $true) -ne '') `
     'exempt is never the empty string, which is what authorises a removal'

Write-Host ''
Write-Host '--- accounts: I COULD NOT TELL is not NO (PRE_RELEASE 96)'

$r = Acc 'bob' 'sdu_bob' "$ROOT\bob" 'bob' '' $false
Note ($r -ne '' -and -not $r.StartsWith('exempt: ')) `
     'a lookup that did not complete REFUSES rather than removing' $r
Note ($r -like '*did not complete*') 'and it says so in those words' $r

# THE ORDERING MATTERS AND IS TESTED, NOT ASSUMED.  A record that would
# otherwise be exempt must still refuse on the lookup, or "could not tell"
# would be quietly reclassified as a benign skip on some records and acted on
# for others.
$r = Acc 'sdsys' 'sdsys' 'C:\ProgramData\SD\sdsys' '' '' $false
Note ($r -ne '' -and -not $r.StartsWith('exempt: ')) `
     'the lookup row is reached BEFORE the exemption rows' $r

Write-Host ''
Write-Host '--- accounts: the refusals'

$r = Acc 'bob' 'sdu_bob' 'D:\Somewhere\bob' 'bob' '' $true
Note ($r -ne '') 'a directory outside the account root is refused' $r

$r = Acc 'bob' 'sdu_bob' $ROOT 'bob' '' $true
Note ($r -ne '') 'a record naming the account root ITSELF is refused' $r

$r = Acc 'bob' 'sdu_bob' "$ROOT\alice" 'bob' '' $true
Note ($r -ne '') 'a record whose directory leaf is another account is refused' $r

$r = Acc 'bob' 'sdu_bob' "$ROOT\sub\bob" 'bob' '' $true
Note ($r -ne '') 'a directory two levels down is refused' $r

$r = Acc 'bob' 'sdu_bob' '' 'bob' '' $true
Note ($r -ne '') 'a record with no directory at all is refused' $r

$r = Get-ReconcileRefusal 'accounts' 'bob' 'sdu_bob' "$ROOT\bob" '' 'bob' '' $true
Note ($r -ne '') 'an unresolvable account root refuses every record' $r

$r = Acc '%E' 'sdu_%E' "$ROOT\%E" '%E' '' $true
Note ($r -ne '') 'an escaped record id is refused rather than decoded here' $r

$r = Acc '' 'sdu_bob' "$ROOT\bob" 'bob' '' $true
Note ($r -ne '') 'a record with no id is refused' $r

Write-Host ''
Write-Host '--- os.users: the record alone, and no directory test'

Note ((Osu 'bob' 'bob' '' $true) -eq '') 'a stale os.users record is cleared for removal' (Osu 'bob' 'bob' '' $true)

$r = Osu 'bob' 'bob' '' $false
Note ($r -ne '' -and $r -like '*did not complete*') 'a lookup that did not complete is refused' $r

$r = Osu '%G' '%G' '' $true
Note ($r -ne '') 'an escaped record id is refused' $r

$r = Osu 'bob' '' '' $true
Note ($r -ne '' -and -not $r.StartsWith('exempt: ')) `
     'os.users never takes the exemption path - it has no account type' $r

# AND THE DIRECTORY ROWS MUST NOT FIRE HERE.  An os.users record carries no
# path, so a table that fell through to the directory tests would refuse every
# one of them and the file would never be reconciled at all.
Note ((Osu 'carol' 'carol' '' $true) -eq '') 'no directory row fires on an os.users record'

Write-Host ''
Write-Host '--- Get-Verdict: A LIVE ACCOUNT IS NOT A REFUSAL'
#
# The first version of the sweep had no such category, so every valid record
# counted as a refusal and a healthy register exited 1 saying "2 refused".
# Witnessed on the live install before it was fixed, which is why these rows
# exist: the table was right and the READING of it was not.

Note ((Get-Verdict '') -eq 'act')                            'an empty reason authorises the removal'
Note ((Get-Verdict 'valid: bob still resolves') -eq 'valid') 'a live account is valid, not refused'
Note ((Get-Verdict 'exempt: sdsys ...') -eq 'exempt')        'an exemption is its own category'
Note ((Get-Verdict 'the lookup did not complete') -eq 'refused') 'anything unmarked is a refusal'
Note ((Get-Verdict 'validation went wrong') -eq 'refused')   'the prefix is "valid: " with its colon, so a reason merely STARTING with those letters still refuses'

# AND THE TWO HEALTHY CATEGORIES MUST NOT BE THE ACTIONABLE ONE.  Only '' may
# ever mean "delete this account directory".
foreach ($m in @('valid: x', 'exempt: x', 'anything else')) {
    Note ((Get-Verdict $m) -ne 'act') ('"' + $m + '" does not authorise a removal')
}

# THE TWO TABLES ARE DRIVEN TOGETHER, because the bug was in the JOIN between
# them rather than in either one.
$r = Acc 'bob' 'sdu_bob' "$ROOT\bob" 'bob' 'local account bob' $true
Note ((Get-Verdict $r) -eq 'valid') 'a live Windows account scores valid end to end' $r
Note ($r -like '*still resolves*')  'and the reason names what it found' $r

$r = Osu 'bob' 'bob' 'local account bob' $true
Note ((Get-Verdict $r) -eq 'valid') 'a live os.users login scores valid end to end' $r

$r = Acc 'sdsys' 'sdsys' 'C:\ProgramData\SD\sdsys' '' '' $true
Note ((Get-Verdict $r) -eq 'exempt') 'sdsys scores exempt end to end' $r

$r = Acc 'bob' 'sdu_bob' "$ROOT\bob" 'bob' '' $true
Note ((Get-Verdict $r) -eq 'act') 'and only the stale record scores act' $r

Write-Host ''
Write-Host '--- Resolve-WindowsAccount: three answers, not two'

$set = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
[void]$set.Add('bob')

$a = Resolve-WindowsAccount 'bob' $set
Note ($a.ok -and $a.live -ne '') 'a name in the local set resolves without asking Windows' ($a.live)

$a = Resolve-WindowsAccount 'BOB' $set
Note ($a.ok -and $a.live -ne '') 'the local set is matched case-insensitively' ($a.live)

$a = Resolve-WindowsAccount '' $set
Note ($a.ok -and $a.live -eq '') 'an empty name is answered, not looked up'

# THIS ONE DOES ASK WINDOWS, and it is the row that proves ABSENT and COULD NOT
# TELL are different values.  The name cannot exist: it is not a legal Windows
# account name and nothing will ever map it.
$a = Resolve-WindowsAccount 'zz-no-such-account-3f9c1a7e' $set
Note ($a.ok -and $a.live -eq '') 'a name Windows does not know is ABSENT with ok still true' `
     ('ok=' + $a.ok + ' live=' + $a.live)

Write-Host ''
Write-Host '--- Get-Records: EMPTY and UNREADABLE are different answers'
#
# ***THIS COST A CYCLE AND IT WAS FOUND BY THE SERVICE, NOT BY A TEST.***  3 Sep
# 2026, the first run sdsvc.exe ever made: the sweep runs BEFORE "sd -start", so
# on a fresh install os.users is still empty, and a PowerShell function that
# returns @() hands its caller $null.  The caller read that as "could not be
# read", counted it towards the exit code, and the service logged "register
# reconcile: exited with 1" on a perfectly healthy machine WITH NO LINE SAYING
# WHY.  These rows use real directories because the trap is in PowerShell's
# return semantics rather than in any logic - a fixture that passed an array
# around would not reproduce it.

$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('reconcile-units-' + [System.Guid]::NewGuid().ToString('N'))
$dirEmpty    = Join-Path $tmp 'empty'
$dirOne      = Join-Path $tmp 'one'
$dirTwo      = Join-Path $tmp 'two'
$dirAbsent   = Join-Path $tmp 'never-created'
New-Item -ItemType Directory -Path $dirEmpty -Force | Out-Null
New-Item -ItemType Directory -Path $dirOne   -Force | Out-Null
New-Item -ItemType Directory -Path $dirTwo   -Force | Out-Null
Set-Content -LiteralPath (Join-Path $dirOne 'alice') -Value 'x'
Set-Content -LiteralPath (Join-Path $dirTwo 'alice') -Value 'x'
Set-Content -LiteralPath (Join-Path $dirTwo 'bob')   -Value 'x'

$r = Get-Records $dirEmpty
Note ($null -ne $r)            'an EMPTY directory does not come back as null'
Note ($r.ok -and -not $r.absent) 'it is readable and present' ('ok=' + $r.ok + ' absent=' + $r.absent)
Note ((@($r.items)).Count -eq 0) 'and it holds no records' ((@($r.items)).Count)

$r = Get-Records $dirAbsent
Note ($null -ne $r)      'a MISSING directory does not come back as null'
Note ($r.ok)             'and it is not reported as unreadable - it is simply not there'
Note ($r.absent)         'absent says so on its own'

# THE ONE-RECORD CASE IS THE OTHER HALF OF THE SAME TRAP: a single-element
# array returns as a bare FileInfo, so anything doing .Count on the result was
# relying on PowerShell adding Count to scalars.
$r = Get-Records $dirOne
Note ((@($r.items)).Count -eq 1) 'a ONE-record directory holds exactly one' ((@($r.items)).Count)
$r = Get-Records $dirTwo
Note ((@($r.items)).Count -eq 2) 'a two-record directory holds exactly two' ((@($r.items)).Count)

# AND THE THREE STATES MUST NOT COLLAPSE INTO EACH OTHER.
$e = Get-Records $dirEmpty
$a = Get-Records $dirAbsent
Note (($e.absent -ne $a.absent)) 'empty and absent are distinguishable'

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Write-Host ('test-reconcile-units: ' + $pass + ' passed, ' + $fail + ' failed')

# REFUSE THE NULL CASE.  A run that asserted nothing must not exit 0.
if ($pass -eq 0) {
    Write-Host 'test-reconcile-units: NOTHING WAS ASSERTED - that is a failure, not a pass.'
    exit 1
}
if ($fail -gt 0) { exit 1 }
exit 0
