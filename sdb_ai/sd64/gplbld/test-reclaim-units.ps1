# test-reclaim-units.ps1 - unit test for reclaim-profiles.ps1's refusal table.
# Needs NO install, NO elevation, NO store and NO reboot, so it costs nothing to
# run and can run before the sweep is handed to sdsvc.exe.
#
# START-HISTORY:
# 28 Aug 2026  Written with the sweep, PRE_RELEASE_FIXES.md 36.  The sweep runs
#              as LocalSystem at every boot and deletes directories named in a
#              file, so its refusal table is the security boundary of the whole
#              feature - and it is the one part that cannot be exercised by
#              running the thing, because every path through it ends in "and
#              then nothing happened".
# 28 Aug 2026  PRE_RELEASE_FIXES.md 43, owner's ruling: the owner check is gone
#              from the sweep and the two OWNER rows are turned round.  This
#              file scored 39/39 against a sweep that could not reclaim a single
#              record, because every accepted case handed in SYSTEM or
#              Administrators and none handed in what DELETE_USER actually
#              writes - a file owned by the administrator who ran it.  The rows
#              that matter now are the ones asserting ACCEPTANCE; the control
#              for them is -Sweep at the pre-43 copy, where they go red 37/2.
# END-HISTORY
#
# ***WHAT IT GUARDS.***  reclaim-profiles.ps1 is started by sdsvc.exe as
# LocalSystem at every service start and removes the directory and the
# ProfileList entry named in each record under
# C:\ProgramData\SD\profile-reclaim.  secure-reclaim.ps1's ACL is what keeps
# other people out of that store; Get-RefusalReason is the backstop for the
# case where it is not, and every row below is one way a planted or stale
# record could do harm.
#
# ***IT TESTS THE SHIPPED FUNCTION, NOT A COPY OF IT.***  Get-RefusalReason and
# Norm are lifted out of reclaim-profiles.ps1 by the PowerShell PARSER and
# defined here verbatim, the idiom test-doorsargv-units.ps1 already uses.  If
# either cannot be found this file FAILS - a run that measured nothing must not
# score green.
#
# ***AND IT IS PURE, WHICH IS WHY IT CAN BE A UNIT TEST AT ALL.***
# Get-RefusalReason takes the owner SID, the parsed record, the profiles root,
# the live account name and the ProfileList path as ARGUMENTS.  The sweep makes
# those three live lookups and passes them in; this file makes them up.  So the
# table can be driven over invented SIDs and invented directories with nothing
# on the machine touched.
#
# ***THE CONTROL ROW IS THE POINT.***  A refusal table that refuses everything
# passes every negative row and is useless, so the first row is a record that
# must be ACCEPTED.  If it is refused this file goes red.

[CmdletBinding()]
param(
    # ***-Sweep EXISTS SO THE TEST CAN HAVE A POSITIVE CONTROL.***  Point it at
    # a copy with a check removed and the matching row must go RED.  Default is
    # the real file beside this one.
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

# --- lift the two functions out of the shipped file ------------------------

if ($Sweep -eq '') { $Sweep = Join-Path $PSScriptRoot 'reclaim-profiles.ps1' }
$Sweep = [System.IO.Path]::GetFullPath($Sweep)

Write-Host ''
Write-Host ('test-reclaim-units: subject ' + $Sweep)

if (-not (Test-Path -LiteralPath $Sweep)) {
    Write-Host ('  FAIL  no such file: ' + $Sweep)
    Write-Host ''
    Write-Host 'test-reclaim-units: 0 passed, 1 failed'
    exit 1
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($Sweep, [ref]$tokens, [ref]$errors)
if ($errors.Count -gt 0) {
    Write-Host ('  FAIL  ' + $Sweep + ' does not parse: ' + $errors.Count + ' error(s)')
    $errors | ForEach-Object { Write-Host ('        line ' + $_.Extent.StartLineNumber + ': ' + $_.Message) }
    Write-Host ''
    Write-Host 'test-reclaim-units: 0 passed, 1 failed'
    exit 1
}

$funcs = @($ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
Write-Host ('test-reclaim-units: parsed, ' + $tokens.Count + ' tokens, ' +
            $funcs.Count + ' function(s): ' + (($funcs | ForEach-Object { $_.Name }) -join ', '))

# REFUSE THE NULL CASE OUT LOUD.  A file whose functions the parser cannot find
# parses with zero errors - that is exactly how an embedded BOM scored a false
# green as step 17 of b18 - so the names are asserted, not assumed.
$wanted = @('Get-RefusalReason', 'Norm')
foreach ($w in $wanted) {
    $d = @($funcs | Where-Object { $_.Name -eq $w })
    if ($d.Count -ne 1) {
        Write-Host ('  FAIL  ' + $Sweep + ' defines ' + $d.Count + ' function(s) called ' + $w + ', expected exactly 1')
        Write-Host ''
        Write-Host 'test-reclaim-units: 0 passed, 1 failed'
        exit 1
    }
    . ([scriptblock]::Create($d[0].Extent.Text))
}

if (-not (Get-Command Get-RefusalReason -ErrorAction SilentlyContinue)) {
    Write-Host '  FAIL  Get-RefusalReason did not define itself after being lifted'
    Write-Host ''
    Write-Host 'test-reclaim-units: 0 passed, 1 failed'
    exit 1
}

# --- the fixtures ----------------------------------------------------------
#
# Invented throughout.  None of these SIDs or paths is real and nothing here
# touches the machine; the root below is not this machine's profiles root
# either, which is deliberate - a test that happened to name the real one could
# pass by accident on a machine where the real one is what the code looked at.

$SYSTEM = 'S-1-5-18'
$ADMINS = 'S-1-5-32-544'
$ROOT   = 'D:\TestUsers'
$SID    = 'S-1-5-21-1111111111-2222222222-3333333333-1007'

function Rec($sid, $account, $directory) {
    return @{ 'sid' = $sid; 'account' = $account; 'directory' = $directory }
}

# Every call names its arguments in the same order the sweep used to take them.
# GET-REFUSALREASON NO LONGER TAKES THE OWNER - PRE_RELEASE 43 - so this wrapper
# accepts it and does not forward it.  The parameter is kept HERE, and only
# here, so that every call site below still reads as "this record, owned by
# this identity", which is what each row is about; the sweep still reads and
# logs the owner, it just no longer refuses on it.
#   fileName, ownerSid, rec, rootNorm, liveAccount, entryPath
function Why($fileName, $ownerSid, $rec, $root, $live, $entry) {
    return (Get-RefusalReason $fileName $rec $root $live $entry)
}

Write-Host ''
Write-Host 'THE CONTROL: a record that MUST be accepted'

$good = Rec $SID 'sdacct1' 'D:\TestUsers\sdacct1'
$r = Why $SID $SYSTEM $good $ROOT '' ''
Note ($r -eq '') 'a well-formed orphan record with no ProfileList entry is accepted' $r

$r = Why $SID $ADMINS $good $ROOT '' 'D:\TestUsers\sdacct1'
Note ($r -eq '') 'the same, owned by Administrators, with a MATCHING entry' $r

# The paths must compare after normalisation, not as written, or a trailing
# separator or a doubled one would refuse a record that is perfectly good.
$r = Why $SID $SYSTEM (Rec $SID 'sdacct1' 'D:\TestUsers\sdacct1\') $ROOT '' 'D:\TestUsers\\sdacct1'
Note ($r -eq '') 'a trailing separator and a doubled one still compare equal' $r

Write-Host ''
Write-Host 'THE OWNER: evidence, not a gate - the rows PRE_RELEASE 43 turned round'

# ***THIS IS THE ROW WHOSE ABSENCE MADE 39/39 MEAN NOTHING.***  Every accepted
# case above hands in SYSTEM or Administrators.  Not one row ever handed in what
# DELETE_USER ACTUALLY PRODUCES - a file owned by the administrator who ran
# DELETE.ACCOUNT, because on Windows an elevated process owns what it creates by
# its own SID.  The suite drove every way the guard said no and never the one
# path where it had to say yes, so it scored 39/39 against a sweep that could
# not reclaim anything.  Measured 28 Aug 2026: five genuine records, five
# refusals.  A test that only exercises the refusals passes when the feature
# does nothing.
$adminOwn = 'S-1-5-21-1111111111-2222222222-3333333333-1001'
$r = Why $SID $adminOwn $good $ROOT '' ''
Note ($r -eq '') 'a record owned by the ADMINISTRATOR who ran DELETE.ACCOUNT is ACCEPTED' $r

# The containment is the store's ACL - SYSTEM and Administrators only,
# re-asserted by the sweep at every boot before a record is read - so an
# unreadable owner is not by itself a reason to leave an orphan on the disk.
$r = Why $SID '' $good $ROOT '' ''
Note ($r -eq '') 'a record whose owner cannot be read is accepted - the ACL is the gate' $r

# AND THE REST OF THE TABLE MUST STILL BITE ON A RECORD OWNED THAT WAY, or this
# ruling would have quietly disabled the other six rules along with the owner
# one.  Same ordinary-user owner, one broken field.
$r = Why 'S-1-5-21-9-9-9-1007' $adminOwn $good $ROOT '' ''
Note ($r -ne '') '  and a renamed record owned the same way is still refused' 'accepted'

Write-Host ''
Write-Host 'THE RECORD ITSELF'

$r = Why $SID $SYSTEM $null $ROOT '' ''
Note ($r -ne '') 'a record that could not be parsed is refused' 'accepted'

$r = Why 'S-1-5-21-9-9-9-1007' $SYSTEM $good $ROOT '' ''
Note ($r -ne '') 'a record whose FILE NAME is not the SID inside it is refused' 'accepted'

$r = Why '' $SYSTEM (Rec '' 'sdacct1' 'D:\TestUsers\sdacct1') $ROOT '' ''
Note ($r -ne '') 'a record with no SID at all is refused' 'accepted'

Write-Host ''
Write-Host 'THE SID: a local account, and an orphaned one'

foreach ($bad in @('S-1-5-18', 'S-1-5-32-544', 'S-1-1-0', 'S-1-5-21-1-2-3',
                   'not-a-sid', 'S-1-5-21-1111111111-2222222222-3333333333-1007-1')) {
    $r = Why $bad $SYSTEM (Rec $bad 'x' 'D:\TestUsers\x') $ROOT '' ''
    Note ($r -ne '') ("refused: " + $bad) 'accepted'
}

$lowRid = 'S-1-5-21-1111111111-2222222222-3333333333-500'
$r = Why $lowRid $SYSTEM (Rec $lowRid 'admin' 'D:\TestUsers\admin') $ROOT '' ''
Note ($r -ne '') 'refused: RID 500, the built-in Administrator' 'accepted'
Note ($r -like '*below 1000*') '  and it says which rule fired' $r

$r = Why $SID $SYSTEM $good $ROOT 'sdacct1' ''
Note ($r -ne '') 'a SID that still has a LIVE local account is refused' 'accepted'
Note ($r -like '*live local account*') '  and it says so' $r

Write-Host ''
Write-Host 'THE DIRECTORY: under the profiles root, and not a standard profile'

$r = Why $SID $SYSTEM (Rec $SID 'sdacct1' '') $ROOT '' ''
Note ($r -ne '') 'a record naming no directory is refused' 'accepted'

$r = Why $SID $SYSTEM (Rec $SID 'sdacct1' $ROOT) $ROOT '' ''
Note ($r -ne '') 'a record naming the profiles ROOT itself is refused' 'accepted'

$r = Why $SID $SYSTEM (Rec $SID 'sdacct1' 'D:\TestUsers\') $ROOT '' ''
Note ($r -ne '') 'the same with a trailing separator is refused' 'accepted'

foreach ($elsewhere in @('C:\Windows\System32', 'D:\TestUsers\sdacct1\Documents',
                         'D:\Elsewhere\sdacct1', 'D:\TestUsersOther\sdacct1')) {
    $r = Why $SID $SYSTEM (Rec $SID 'sdacct1' $elsewhere) $ROOT '' ''
    Note ($r -ne '') ("refused, not directly under the root: " + $elsewhere) 'accepted'
}

# ..\ IS THE ONE THAT LOOKS LIKE IT WOULD SLIP THROUGH, and the reason the
# comparison is made on the NORMALISED path rather than the written one:
# "D:\TestUsers\..\Windows" has the root as a prefix as a string and is not
# under it at all.
$r = Why $SID $SYSTEM (Rec $SID 'sdacct1' 'D:\TestUsers\..\Windows\System32') $ROOT '' ''
Note ($r -ne '') 'refused: a path that escapes the root with ..\' 'accepted'

# CONCATENATED, NOT Join-Path.  Join-Path resolves the drive and throws
# "A drive with the name 'D' does not exist" on a machine that has no D: -
# which would make this test's result depend on the machine's drive letters.
# The subject compares paths with [System.IO.Path], which is string arithmetic
# and asks the filesystem nothing.
foreach ($std in @('Default', 'Default User', 'Public', 'All Users',
                   'defaultuser0', 'systemprofile', 'LocalService', 'NetworkService')) {
    $r = Why $SID $SYSTEM (Rec $SID $std ($ROOT + '\' + $std)) $ROOT '' ''
    Note ($r -ne '') ("refused, a standard Windows profile: " + $std) 'accepted'
}

# Case does not save a standard profile from being one.
$r = Why $SID $SYSTEM (Rec $SID 'public' 'D:\TestUsers\public') $ROOT '' ''
Note ($r -ne '') 'refused: "public" in lower case is still the Public profile' 'accepted'

Write-Host ''
Write-Host 'WINDOWS'' OWN OPINION, WHERE IT STILL HAS ONE'

$r = Why $SID $SYSTEM $good $ROOT '' 'D:\TestUsers\somebody-else'
Note ($r -ne '') 'a ProfileList entry naming a DIFFERENT directory is refused' 'accepted'
Note ($r -like '*ProfileList entry names*') '  and it says both paths' $r

$r = Why $SID $SYSTEM $good '' '' ''
Note ($r -ne '') 'a profiles root that could not be resolved refuses everything' 'accepted'

Write-Host ''
Write-Host ('test-reclaim-units: ' + $pass + ' passed, ' + $fail + ' failed')
Write-Host ''

if ($fail -gt 0) { exit 1 }
exit 0
