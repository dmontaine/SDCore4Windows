# test-privundetermined-units.ps1 - guard verify-privundetermined.ps1's leg
# table against the C it claims to describe.
#
#   powershell -File test-privundetermined-units.ps1
#
# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.
#
# WHY IT EXISTS.  verify-privundetermined.ps1 is PRE_RELEASE_FIXES.md 96's
# witness, and it costs an install, an elevation, a run token, two SD restarts
# and about a minute of API round trips.  ITS LEG TABLE IS A SECOND DESCRIPTION
# OF FACTS THAT LIVE IN gplsrc - the PRIV_WHY enum, the exact reason strings
# priv_why_text() returns, and the sentence priv_log_undetermined() writes - and
# CLAUDE.md's own list of free guards is mostly made of exactly this shape:
# "two files that describe one fact and are kept in step by hand".
#
# WHAT DRIFT WOULD LOOK LIKE WITHOUT THIS.  Reword one string in
# priv_why_text() - "could not be read" to "was unreadable", say - and the
# verifier's leg still finds its ONE undetermined line, still counts 1, and
# still fails only on the row that names the reason.  That is a red suite step
# an hour into an elevated run, reported as a product regression, for a change
# that was neither.  Here it is a second.
#
# AND THE PART NOTHING ELSE COVERS: THE PARTITION.  Nine undetermined paths
# exist; the verifier exercises three and declares six unreachable.  A TENTH
# enum member added later belongs on one side or the other, and nothing would
# ask - the verifier would simply carry on measuring three of ten while its
# summary said three of nine.  This asserts that covered + unreachable +
# PRIV_ANSWERED is EXACTLY the enum, so a new member turns it red until
# somebody classifies it.
#
# IT NEEDS NO INSTALL, NO ELEVATION AND NO RUN TOKEN.  It reads two PowerShell
# files and four C files and writes nothing.
#
# NOT SHIPPED - it is on assert-current.ps1's $neverShipped list.

$ErrorActionPreference = 'Stop'

$sd64 = Split-Path $PSScriptRoot -Parent
$src  = Join-Path $PSScriptRoot 'verify-privundetermined.ps1'
$hdr  = Join-Path $sd64 'gplsrc\linuxlb.h'
$lib  = Join-Path $sd64 'gplsrc\linuxlb.c'
$sh   = Join-Path $sd64 'gplsrc\op_sh.c'
$kerr = Join-Path $sd64 'gplsrc\k_error.c'

$pass = 0
$fail = 0

function Note {
    param($What, $Expected, $Got)
    $ok = ($Expected -eq $Got)
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f
                  $(if ($ok) { 'PASS' } else { 'FAIL' }), $What, $Expected, $Got)
}

foreach ($p in @($src, $hdr, $lib, $sh, $kerr)) {
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Output ("test-privundetermined-units: {0} does not exist - nothing could be measured." -f $p)
        exit 2
    }
}

Write-Output 'test-privundetermined-units - PRE_RELEASE_FIXES.md 96, the verifier leg table'
Write-Output ("  subject: {0}" -f $src)
Write-Output ''

# ---------------------------------------------------------------- the lift
# PARSE FIRST, AND REFUSE ON AN ERROR RATHER THAN REPORTING ON THE WRECKAGE.
# CLAUDE.md's "verify a script loads before you submit it for execution" is
# satisfied for the verifier by this test being in the free set - so a broken
# verifier is found here, in a second, and not as a dead step 17 of an elevated
# run.
$t = $null; $e = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$t, [ref]$e)
if ($e.Count) {
    Write-Output "test-privundetermined-units: refusing - the verifier has $($e.Count) parse error(s)"
    $e | ForEach-Object { Write-Output ("  line " + $_.Extent.StartLineNumber + ": " + $_.Message) }
    exit 2
}
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$t, [ref]$e)

# LIFTED BY AST AND THE NULL CASE IS REFUSED OUT LOUD.  A FindAll that matched
# nothing would leave every check below comparing against $null, and a table of
# nothing passes any test that only looks for absences.
#
# THE DOT-SOURCE IS OUT HERE AND NOT INSIDE THE HELPER, WHICH IS THE WHOLE
# REASON THIS IS SPLIT IN TWO.  A "." inside a function defines the lifted
# function in THAT function's scope and it is gone the moment the helper
# returns - which fails loudly ("Get-PrivLegs is not recognized") rather than
# quietly, but only once somebody runs it.  foreach does not open a scope, so
# the loop below leaves all three at script scope.
#
# AND IT RETURNS A HASHTABLE RATHER THAN THE TEXT, so that a Write-Output for
# the reader cannot be JOINED onto the return value - the trap this project's
# memory file names in as many words.
function Get-Lifted([string]$name) {
    $f = @($ast.FindAll({ param($n)
              $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
              $n.Name -eq $name }, $true))
    if ($f.Count -ne 1) { return @{ Ok = $false; Count = $f.Count; Text = '' } }
    return @{ Ok = $true; Count = 1; Text = $f[0].Extent.Text }
}

foreach ($n in @('Get-PrivLegs', 'Get-PrivUnreachable', 'Get-PrivMarker', 'Get-ResultTally')) {
    $l = Get-Lifted $n
    if (-not $l.Ok) {
        Write-Output "test-privundetermined-units: refusing - expected 1 $n in the verifier, found $($l.Count)"
        exit 2
    }
    . ([scriptblock]::Create($l.Text))
    Write-Output ("  lifted {0} ({1} chars)" -f $n, $l.Text.Length)
}

$legs        = @((Get-PrivLegs).Legs)
$unreachable = @((Get-PrivUnreachable).Unreachable)
$marker      = Get-PrivMarker

if ($legs.Count -eq 0 -or $unreachable.Count -eq 0) {
    Write-Output "test-privundetermined-units: refusing - legs=$($legs.Count) unreachable=$($unreachable.Count); an empty table cannot be checked."
    exit 2
}
Write-Output ("  {0} leg(s), {1} declared unreachable" -f $legs.Count, $unreachable.Count)
Write-Output ''

$hdrText  = Get-Content -LiteralPath $hdr  -Raw
$libText  = Get-Content -LiteralPath $lib  -Raw
$shText   = Get-Content -LiteralPath $sh   -Raw
$kerrText = Get-Content -LiteralPath $kerr -Raw

# ------------------------------------------------------- 1. the table itself
Write-Output '=== the leg table stands on its own ==='

$names = @($legs | ForEach-Object { $_.Name })
Note 'every leg has a name' $legs.Count @($names | Where-Object { $_ }).Count
Note 'the leg names are unique' $legs.Count @($names | Select-Object -Unique).Count

# THE CONTROL IS A STRUCTURAL REQUIREMENT, NOT A CONVENTION.  Every other leg
# is a refusal, and a probe that could never succeed would score all of them.
Note 'exactly one leg GRANTS OS.EXECUTE' 1 @($legs | Where-Object { $_.Grants }).Count
Note 'at least two legs expect a refusal' $true (@($legs | Where-Object { -not $_.Grants }).Count -ge 2)

# A leg that expects a log line must say WHICH; a leg that expects none must
# name none.  Half-filled either way is a row that cannot be checked.
$halfFilled = @($legs | Where-Object {
                   [string]::IsNullOrEmpty($_.Why) -ne [string]::IsNullOrEmpty($_.WhyId) })
Note 'no leg names a reason without an id, or an id without a reason' 0 $halfFilled.Count

# AND A GRANTING LEG MUST EXPECT SILENCE.  os_permitted() sets *why =
# PRIV_ANSWERED on entry and only an exit that could not finish overwrites it,
# so a leg that grants and also expects a line describes a state the C cannot
# produce.
$grantingWithWhy = @($legs | Where-Object { $_.Grants -and $_.WhyId })
Note 'no granting leg expects an undetermined line' 0 $grantingWithWhy.Count

$covered = @($legs | Where-Object { $_.WhyId } | ForEach-Object { $_.WhyId })
Note 'the covered ids are unique' $covered.Count @($covered | Select-Object -Unique).Count
Write-Output ("       covered: {0}" -f ($covered -join ', '))

# --------------------------------------------------- 2. against the C enum
Write-Output ''
Write-Output '=== against the PRIV_WHY enum in linuxlb.h ==='

$enumBlock = [regex]::Match($hdrText, 'typedef enum \{(.*?)\} PRIV_WHY;', 'Singleline')
Note 'the PRIV_WHY enum is in linuxlb.h' $true $enumBlock.Success
if (-not $enumBlock.Success) {
    Write-Output 'test-privundetermined-units: no enum to check against - refusing to report on nothing.'
    exit 2
}
$members = @([regex]::Matches($enumBlock.Groups[1].Value, '\bPRIV_[A-Z_]+') |
             ForEach-Object { $_.Value } | Select-Object -Unique)
Write-Output ("       enum: {0} member(s)" -f $members.Count)

$declared = @($unreachable | ForEach-Object { $_.WhyId })
$claimed  = @(@('PRIV_ANSWERED') + $covered + $declared)

$notInEnum = @($claimed | Where-Object { $members -notcontains $_ })
Note 'every id the verifier names is a real enum member' 0 $notInEnum.Count
if ($notInEnum.Count) { Write-Output ("       not in the enum: {0}" -f ($notInEnum -join ', ')) }

$overlap = @($covered | Where-Object { $declared -contains $_ })
Note 'no id is both exercised and declared unreachable' 0 $overlap.Count

# ***THE PARTITION, AND IT IS THE ROW THIS FILE EXISTS FOR.***  A tenth enum
# member added later is neither exercised nor declared, and nothing else in the
# tree would ask which it is.
$unclassified = @($members | Where-Object { $claimed -notcontains $_ })
Note 'every enum member is exercised, declared unreachable, or ANSWERED' 0 $unclassified.Count
if ($unclassified.Count) {
    Write-Output ("       UNCLASSIFIED: {0}" -f ($unclassified -join ', '))
    Write-Output '       Add it to Get-PrivLegs with a fixture, or to Get-PrivUnreachable with a reason.'
}
Note 'the claim covers the whole enum and no more' $members.Count @($claimed | Select-Object -Unique).Count

# ------------------------------------------- 3. against priv_why_text()
Write-Output ''
Write-Output '=== the reason strings, verbatim, against priv_why_text() in linuxlb.c ==='

$textFn = [regex]::Match($libText, 'char\*\s*priv_why_text\(PRIV_WHY why\)\s*\{(.*?)\n\}', 'Singleline')
Note 'priv_why_text() is in linuxlb.c' $true $textFn.Success
if (-not $textFn.Success) {
    Write-Output 'test-privundetermined-units: no priv_why_text() to compare against - refusing.'
    exit 2
}

# case PRIV_X:\n  return "the text";   ->  a map from id to the exact string.
$map = @{}
foreach ($m in [regex]::Matches($textFn.Groups[1].Value,
                 'case\s+(PRIV_[A-Z_]+)\s*:\s*return\s+"([^"]*)"\s*;', 'Singleline')) {
    $map[$m.Groups[1].Value] = $m.Groups[2].Value
}
Note 'priv_why_text() maps every enum member' $members.Count $map.Keys.Count

foreach ($leg in @($legs | Where-Object { $_.WhyId })) {
    # ORDINAL AND CASE-SENSITIVE.  PowerShell's -eq compares strings
    # case-INSENSITIVELY, so "The os.users record could not be read" would pass
    # a -eq against the C's lower-case text and then never match the log line
    # the verifier reads with String.Contains(), which is ordinal.  That is the
    # exact shape of the -cne lesson in this project's memory.
    $want = $map[$leg.WhyId]
    $same = ($null -ne $want) -and [string]::Equals($want, $leg.Why, [System.StringComparison]::Ordinal)
    Note ("leg '" + $leg.Name + "' quotes " + $leg.WhyId + " exactly") $true $same
    if (-not $same) {
        Write-Output ("       C says : '{0}'" -f $want)
        Write-Output ("       leg says: '{0}'" -f $leg.Why)
    }
}

# ------------------------------------- 4. against priv_log_undetermined()
Write-Output ''
Write-Output '=== the marker, against priv_log_undetermined() in k_error.c ==='

$logFn = [regex]::Match($kerrText,
             'void priv_log_undetermined\(char\* what, PRIV_WHY why\) \{(.*?)\n\}', 'Singleline')
Note 'priv_log_undetermined() is in k_error.c' $true $logFn.Success
if ($logFn.Success) {
    $body = $logFn.Groups[1].Value
    # The format string is split across source lines by the formatter, so the
    # comparison is against the body with C string concatenation and newlines
    # squeezed out - otherwise "not a " / "denial" would never match.
    $flat = ($body -replace '"\s*\n\s*"', '') -replace '\s+', ' '
    Note 'the marker prefix is the wording the C writes' $true $flat.Contains($marker.Prefix)
    Note 'the tail is the wording the C writes'          $true $flat.Contains($marker.Tail)
    # sysseg IS TESTED THERE, AND THE VERIFIER DEPENDS ON IT NOT BEING TESTED
    # AWAY: without the guard the call from sd.c's pre-bind path would crash at
    # start-up, which is why that one site prints to stderr instead.  A change
    # that removed the guard would not break this verifier, but it is the one
    # line of that function a reader must not delete, so it is asserted here
    # where it costs nothing.
    Note 'it still refuses to log before sysseg is bound' $true ($body -match 'sysseg\s*==\s*NULL')
}

# THE "what" THE VERIFIER ANCHORS ON MUST BE THE LITERAL op_sh.c PASSES.
# Anchoring on a reason string alone would count a line written by
# kernel.c's "USR_ADMIN at session start" or op_kernel.c's "K$OS.ADMINISTRATOR"
# as this one, and those fire on the same run.
$callArg = [regex]::Match($shText, 'priv_log_undetermined\("([^"]*)"')
Note 'op_sh.c calls priv_log_undetermined()' $true $callArg.Success
if ($callArg.Success) {
    Note 'the verifier anchors on the "what" op_sh.c passes' `
         $true ([string]::Equals($callArg.Groups[1].Value, $marker.What, [System.StringComparison]::Ordinal))
    Write-Output ("       op_sh.c passes: '{0}'" -f $callArg.Groups[1].Value)
}

# ------------------------------------------- 5. the fixtures, modelled
Write-Output ''
Write-Output '=== the fixtures reach the exits they claim ==='

# THE MODEL IS ANCHORED TO THE SOURCE RATHER THAN TO MEMORY.  These three
# tests are os_permitted()'s decisive ones; if any is reworded the model below
# is describing code that no longer exists, and this row says so before the
# rows that use it.
$anchored = ($shText -match 'strchr\(buff,\s*.\\n.\)') -and
            ($shText -match 'if \(n <= 0\)') -and
            ($shText -match 'stricmp\(p, "yes"\)')
Note "op_sh.c still parses the record the way this model does" $true $anchored

# op_sh.c:191-224 in PowerShell.  Reads the same three decisions in the same
# order: read() gave nothing -> READ_FAILED; no newline -> MALFORMED;
# otherwise field 2, trimmed, compared to "yes" case-insensitively.
function Test-OsUsersRecord {
    param([string]$Content, [bool]$Present = $true, [bool]$Openable = $true)
    if (-not $Present)  { return @{ Grants = $false; WhyId = '' } }
    if (-not $Openable) { return @{ Grants = $false; WhyId = 'PRIV_OPEN_FAILED' } }
    if ($Content.Length -eq 0) { return @{ Grants = $false; WhyId = 'PRIV_READ_FAILED' } }
    $nl = $Content.IndexOf("`n")
    if ($nl -lt 0) { return @{ Grants = $false; WhyId = 'PRIV_MALFORMED' } }
    $rest = $Content.Substring($nl + 1)
    foreach ($stop in @("`n", "`r")) {
        $i = $rest.IndexOf($stop)
        if ($i -ge 0) { $rest = $rest.Substring(0, $i) }
    }
    $rest = $rest.Trim(' ')
    return @{ Grants = ($rest.ToLower() -eq 'yes'); WhyId = '' }
}

foreach ($leg in $legs) {
    $r = Test-OsUsersRecord -Content ([string]$leg.Content) `
                            -Present  ($leg.Fixture -ne 'none') `
                            -Openable ($leg.Fixture -ne 'denied')
    Note ("leg '" + $leg.Name + "' reaches the grant this table claims")  $leg.Grants $r.Grants
    Note ("leg '" + $leg.Name + "' reaches the exit this table claims")   ([string]$leg.WhyId) ([string]$r.WhyId)
}

# ***THE MUTANT CONTROL.***  Every row above is satisfied by a model that
# answered "no grant, no reason" to everything except the one granting leg -
# and the leg table has exactly one granting leg, so a model that simply echoed
# .Grants back would score full marks.  These four drive the model with inputs
# the table does not contain and require it to DISAGREE with what it was given.
Write-Output ''
Write-Output '=== the model can say something the table did not tell it ==='
Note 'a record whose second field is "no" does NOT grant' $false `
     (Test-OsUsersRecord -Content "yes`nno`n").Grants
Note 'a record whose second field is "YES" DOES grant (stricmp)' $true `
     (Test-OsUsersRecord -Content "no`nYES`n").Grants
Note 'a trailing-space second field still grants (the trim is real)' $true `
     (Test-OsUsersRecord -Content "no`nyes   `n").Grants
Note 'a one-field record is MALFORMED whatever it says' 'PRIV_MALFORMED' `
     (Test-OsUsersRecord -Content 'yes').WhyId

# ------------------------------------------- 6. the summary counter
# ***THIS SECTION IS A REGRESSION TEST FOR A FALSITY THAT REACHED THE OWNER'S
# SCREEN.***  PRE_RELEASE 156.  On verify-privundetermined's first real run
# (b112, 25 of 25, every leg green) the line under the table read "12 check(s)
# reported N/A - they were not measured", on a run where nothing was skipped.
#
# THE CAUSE: PowerShell's -eq coerces the RIGHT operand to the LEFT's type, so
# with Expected holding a boolean, "$true -eq 'n/a'" is TRUE.  There were
# exactly twelve rows expecting $true.  The fixture below reproduces that shape
# - booleans, integers and strings in Expected, and NO skipped rows - so it
# fails against the original one-liner and passes against the [string] form.
Write-Output ''
Write-Output '=== the summary counter, against the shape that broke it ==='

$rows = @(
    [pscustomobject]@{ Check = 'a'; Expected = $true;  Observed = $true  },
    [pscustomobject]@{ Check = 'b'; Expected = $true;  Observed = $true  },
    [pscustomobject]@{ Check = 'c'; Expected = $false; Observed = $false },
    [pscustomobject]@{ Check = 'd'; Expected = 1;      Observed = 1      },
    [pscustomobject]@{ Check = 'e'; Expected = 0;      Observed = 0      },
    [pscustomobject]@{ Check = 'f'; Expected = $true;  Observed = $false }
)
$t = Get-ResultTally $rows
# THE ROW THE BUG FAILS.  Under the original form this was 3, not 0.
Note 'a run with nothing skipped reports ZERO N/A' 0 $t.Na
Note 'it counts every row'                          6 $t.Total
Note 'it counts every row as asked'                 6 $t.Asked
Note 'it counts the passes'                         5 $t.Pass
Note 'and the one real failure'                     1 $t.Fail

# AND IT MUST STILL SEE A GENUINE SKIP, or the fix would be "call everything
# measured", which reports just as falsely in the other direction.
$rows2 = @(
    [pscustomobject]@{ Check = 'a'; Expected = $true;  Observed = $true },
    [pscustomobject]@{ Check = 'b'; Expected = 'n/a';  Observed = 'the probe never reached the attempt' }
)
$t2 = Get-ResultTally $rows2
Note 'a genuine N/A row is still counted as N/A' 1 $t2.Na
Note 'and it is NOT counted among the asked'     1 $t2.Asked
Note 'nor as a pass'                             1 $t2.Pass

# THE NULL CASE THE CLOSING LINE NOW REFUSES: a run where every row was skipped
# has asked nothing, and must not print a green summary.
$t3 = Get-ResultTally @([pscustomobject]@{ Check = 'a'; Expected = 'n/a'; Observed = 'why' })
Note 'a run that asked nothing reports Asked = 0' 0 $t3.Asked

# ------------------------------------------------------------- the verdict
Write-Output ''
Write-Output ("test-privundetermined-units: {0} passed, {1} failed" -f $pass, $fail)
if ($pass -eq 0) {
    Write-Output 'test-privundetermined-units: NOTHING PASSED - a run that asserted nothing is not a green run.'
    exit 2
}
exit $(if ($fail) { 1 } else { 0 })
