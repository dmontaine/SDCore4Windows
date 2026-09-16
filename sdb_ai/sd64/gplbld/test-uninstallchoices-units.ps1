# test-uninstallchoices-units.ps1 - drive verify-uninstallchoices.ps1's two
# decisions off disk, with no install, no elevation and no uninstall.
#
# 16 Sep 26 Windows port, RELEASE_1.1 38 and 50.
#
# ***IT EXISTS FOR THE ONE THING NOTHING ELSE CAN REACH.***  Every row that
# verifier judges is reachable only by UNINSTALLING SD, interactively, with a
# person pressing a particular pair of buttons - and each case then costs a
# reinstall to get back to where the next one starts.  So the decision itself
# is the one part that can be exercised cheaply, and it is also the part that
# can be silently wrong: a verdict that scored a vacuous pass would report a
# defect fixed on the strength of a measurement that could not have seen it,
# which is exactly what RELEASE_1.1 50 was - a sweep reporting success on a set
# it had never enumerated.
#
# THE TWO FUNCTIONS ARE LIFTED BY AST, NOT COPIED.  A second copy of the
# decision passes for ever while the shipped one drifts; this tree has paid for
# that shape more than once.
#
# ***AND IT ASSERTS THE PARTITION.***  The -Case/-Check parameters carry a
# ValidateSet, and every name in it must be answered by BOTH functions - a
# sixth case cannot be added without somebody giving it a precondition and a
# verdict, rather than silently falling through to a one-row pass.

$ErrorActionPreference = 'Stop'
$gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$target = "$gplbld/verify-uninstallchoices.ps1"
Write-Host "test-uninstallchoices-units: target $target"

$script:pass = 0
$script:fail = 0
function Check($name, $ok, $detail) {
    if ($ok) { $script:pass++; Write-Host ("  [PASS] {0}" -f $name) }
    else     { $script:fail++; Write-Host ("  [FAIL] {0}{1}" -f $name, $(if ($detail) { " -- $detail" } else { '' })) }
}

# A state object shaped like Get-SdState's, with the fields each case reads.
function New-State($h) {
    $d = @{
        TreePresent = $true; TreeEntries = @('sdsys', 'sd.conf'); ConfPresent = $true
        SdsysPresent = $true; ProgramPresent = $false; UninsPresent = $true
        SdusersPresent = $true; SdusersMembers = @('Don', 'sdw50a')
        RouteGroups = @('sdapi', 'sdssh', 'sdsshonly'); LocalUsers = @('Don', 'sdw50a'); Taken = 'fixture'
    }
    foreach ($k in $h.Keys) { $d[$k] = $h[$k] }
    return [pscustomobject]$d
}
function Failed($rows, $needle) {
    return (@($rows | Where-Object { -not $_.Pass -and $_.Check -like "*$needle*" }).Count -ge 1)
}
function AllPass($rows) { return (@($rows | Where-Object { -not $_.Pass }).Count -eq 0) }

Write-Host ''
Write-Host '=== 0. the null case is refused: the functions are really there ==='

if (-not (Test-Path -LiteralPath $target)) {
    Check 'verify-uninstallchoices.ps1 exists' $false "not found: $target"
    Write-Host ''
    Write-Host 'test-uninstallchoices-units: FAILED - the script under test is missing.'
    exit 1
}

$tok = $null; $err = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($target, [ref]$tok, [ref]$err)
Check ("verify-uninstallchoices.ps1 parses ({0} error(s))" -f $err.Count) ($err.Count -eq 0) `
      (($err | ForEach-Object { $_.Message }) -join '; ')

function Lift($ast, $name) {
    return $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }, $true)
}

$fnV = Lift $ast 'Get-UninstallVerdict'
$fnP = Lift $ast 'Get-CasePrecondition'
Check ("Get-UninstallVerdict was found in the shipped script ({0})" -f $fnV.Count) ($fnV.Count -eq 1) `
      'renamed or inlined - this test would then be measuring nothing'
Check ("Get-CasePrecondition was found in the shipped script ({0})" -f $fnP.Count) ($fnP.Count -eq 1) `
      'renamed or inlined - this test would then be measuring nothing'

if ($fnV.Count -ne 1 -or $fnP.Count -ne 1) {
    Write-Host ''
    Write-Host 'test-uninstallchoices-units: FAILED - nothing to drive.'
    exit 1
}

. ([scriptblock]::Create($fnV[0].Extent.Text))
. ([scriptblock]::Create($fnP[0].Extent.Text))
Check 'both are callable after the lift' `
      ((Get-Command Get-UninstallVerdict -ErrorAction SilentlyContinue) -and
       (Get-Command Get-CasePrecondition -ErrorAction SilentlyContinue)) $null

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 1. the partition: every case the parameters accept is answered ==='

# Read the case names from the script's OWN ValidateSet rather than repeating
# them here, so a sixth case cannot be added without this test seeing it.
$sets = $ast.FindAll({
        param($n)
        $n -is [System.Management.Automation.Language.AttributeAst] -and
        $n.TypeName.Name -eq 'ValidateSet'
     }, $true)
$cases = @()
foreach ($s in $sets) {
    $vals = @($s.PositionalArguments | ForEach-Object { $_.Value })
    if ($vals -contains 'treeabsent') { $cases = @($vals | Where-Object { $_ -ne '' }) ; break }
}
Check ("the case ValidateSet was read from the script ({0} cases)" -f $cases.Count) ($cases.Count -eq 5) `
      ("expected 5, got: " + ($cases -join ', '))

foreach ($c in $cases) {
    # A case with no precondition branch falls through to "unknown case".
    $r = Get-CasePrecondition $c (New-State @{}) 'sdw50a'
    Check ("$c has a precondition branch") ($r -notlike 'unknown case*') $r
    # A case with no verdict branch yields only the shared "the uninstall ran" row.
    $rows = Get-UninstallVerdict $c (New-State @{}) (New-State @{}) 'yes' 'sdw50a'
    Check ("$c has verdict rows of its own ({0})" -f $rows.Count) ($rows.Count -gt 1) `
          'only the shared row came back, so this case decides nothing'
}

Write-Host ''
Write-Host '=== 2. every case asserts the uninstall actually ran ==='
foreach ($c in $cases) {
    # ProgramPresent still $true = the uninstaller never ran.  Without this row
    # a case scores whatever the before state happened to be.
    $rows = Get-UninstallVerdict $c (New-State @{}) (New-State @{ ProgramPresent = $true }) 'yes' 'sdw50a'
    Check ("$c fails when the program directory is still there") (Failed $rows 'the uninstall ran') $null
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 3. silentkeep - /VERYSILENT must remove neither ==='
$before = New-State @{ ProgramPresent = $true }
$good   = New-State @{}
Check 'a run that kept everything passes' (AllPass (Get-UninstallVerdict 'silentkeep' $before $good 'yes' '')) $null
Check 'it fails if sd.conf went' `
      (Failed (Get-UninstallVerdict 'silentkeep' $before (New-State @{ ConfPresent = $false }) 'yes' '') 'sd.conf survives') $null
Check 'it fails if the tree went' `
      (Failed (Get-UninstallVerdict 'silentkeep' $before (New-State @{ TreePresent = $false }) 'yes' '') 'data tree survives') $null
Check 'it fails if sdusers went' `
      (Failed (Get-UninstallVerdict 'silentkeep' $before (New-State @{ SdusersPresent = $false }) 'yes' '') 'sdusers survives') $null
# ***THE ROW THIS TEST HAD BACKWARDS UNTIL IT WAS RUN FOR REAL.***  The three
# route groups SURVIVE a silent uninstall by the owner's ruling of 2 Sep 2026:
# RemoveSdGroups is called above the UninstallSilent guard but carries its own,
# because removing sdsshonly gives kept accounts the console back and that
# disclosure only renders interactively.  Both directions are pinned here.
Check 'silentkeep fails if the route groups were removed silently' `
      (Failed (Get-UninstallVerdict 'silentkeep' $before (New-State @{ RouteGroups = @() }) 'yes' '') 'route groups SURVIVE') $null
Check 'silentkeep fails if only some of them survived' `
      (Failed (Get-UninstallVerdict 'silentkeep' $before (New-State @{ RouteGroups = @('sdsshonly') }) 'yes' '') 'route groups SURVIVE') $null
Check 'an INTERACTIVE case fails if the route groups survived' `
      (Failed (Get-UninstallVerdict 'keepdb-delconf' $before (New-State @{ ConfPresent = $false }) 'yes' '') 'route groups removed') $null
Check 'a snapshot with no route groups at all is refused' `
      ((Get-CasePrecondition 'silentkeep' (New-State @{ RouteGroups = @() }) '') -like '*route groups*') $null

Write-Host ''
Write-Host '=== 4. the two 38 combinations are each others control ==='
$kdc = New-State @{ ConfPresent = $false; TreeEntries = @('sdsys'); RouteGroups = @() }
Check 'keepdb-delconf passes when only sd.conf went' (AllPass (Get-UninstallVerdict 'keepdb-delconf' $before $kdc 'yes' '')) $null
Check 'keepdb-delconf fails if sdsys went too' `
      (Failed (Get-UninstallVerdict 'keepdb-delconf' $before (New-State @{ ConfPresent = $false; SdsysPresent = $false }) 'yes' '') 'sdsys survives') $null
Check 'keepdb-delconf fails if sdusers went (the database was kept)' `
      (Failed (Get-UninstallVerdict 'keepdb-delconf' $before (New-State @{ ConfPresent = $false; SdusersPresent = $false }) 'yes' '') 'sdusers survives') $null

$dkc = New-State @{ SdsysPresent = $false; TreeEntries = @('sd.conf'); SdusersPresent = $false; RouteGroups = @() }
Check 'deldb-keepconf passes when the folder holds sd.conf alone' (AllPass (Get-UninstallVerdict 'deldb-keepconf' $before $dkc 'yes' '')) $null
# THE ROW THAT MATTERS: "sd.conf is still there" is true of a tree that was
# never touched, so the folder's WHOLE contents are asserted, not just the file.
Check 'deldb-keepconf fails if the rest of the tree survived' `
      (Failed (Get-UninstallVerdict 'deldb-keepconf' $before (New-State @{ SdsysPresent = $false; TreeEntries = @('sdsys', 'sd.conf'); SdusersPresent = $false }) 'yes' '') 'sd.conf ALONE') $null
Check 'deldb-keepconf fails if sd.conf went with the database' `
      (Failed (Get-UninstallVerdict 'deldb-keepconf' $before (New-State @{ ConfPresent = $false; SdsysPresent = $false; TreeEntries = @(); SdusersPresent = $false }) 'yes' '') 'sd.conf survives') $null

Write-Host ''
Write-Host '=== 5. deldb-delacct - the sweep removes the account AND keeps the installer ==='
$oldUser = $env:USERNAME
try {
    $env:USERNAME = 'Don'
    $swept = New-State @{ TreePresent = $false; TreeEntries = @(); ConfPresent = $false
                          SdsysPresent = $false; SdusersPresent = $false; LocalUsers = @('Don')
                          RouteGroups = @() }
    Check 'a real sweep passes' (AllPass (Get-UninstallVerdict 'deldb-delacct' $before $swept 'yes' 'sdw50a')) $null
    # RELEASE_1.1 50 ITSELF: the sweep reported success having enumerated
    # nothing, so the account survived.
    $notSwept = New-State @{ TreePresent = $false; TreeEntries = @(); ConfPresent = $false
                             SdsysPresent = $false; SdusersPresent = $false; LocalUsers = @('Don', 'sdw50a') }
    Check 'the defect itself fails: the account is still a Windows user' `
          (Failed (Get-UninstallVerdict 'deldb-delacct' $before $notSwept 'yes' 'sdw50a') 'removed from Windows') $null
    # THE CONTROL IN THE OTHER DIRECTION: a sweep that took everything would
    # pass the row above, and is the harm -Keep exists to prevent.
    $overSwept = New-State @{ TreePresent = $false; TreeEntries = @(); ConfPresent = $false
                              SdsysPresent = $false; SdusersPresent = $false; LocalUsers = @() }
    Check 'an over-broad sweep fails: the installing user was taken too' `
          (Failed (Get-UninstallVerdict 'deldb-delacct' $before $overSwept 'yes' 'sdw50a') 'KEPT') $null
} finally { $env:USERNAME = $oldUser }

Write-Host ''
Write-Host '=== 6. treeabsent - the operators observation decides it, and is required ==='
$taBefore = New-State @{ TreePresent = $false; TreeEntries = @(); ConfPresent = $false
                         SdsysPresent = $false; ProgramPresent = $true }
$taAfter  = New-State @{ TreePresent = $false; TreeEntries = @(); ConfPresent = $false
                         SdsysPresent = $false; SdusersPresent = $false; RouteGroups = @() }
Check 'it passes when the question was seen' (AllPass (Get-UninstallVerdict 'treeabsent' $taBefore $taAfter 'yes' '')) $null
# ***THE WHOLE POINT.***  Before the fix this branch showed NO dialog, and the
# state afterwards is identical either way - sdusers goes in both worlds.  So a
# verdict drawn from state alone would have passed on the unfixed build.
Check 'it FAILS when the question was not offered, on identical state' `
      (Failed (Get-UninstallVerdict 'treeabsent' $taBefore $taAfter 'no' '') 'OFFERED') $null
Check 'an unanswered observation is not read as yes' `
      (Failed (Get-UninstallVerdict 'treeabsent' $taBefore $taAfter '' '') 'OFFERED') $null
Check 'it fails if sdusers survived (the branch did not reach the end)' `
      (Failed (Get-UninstallVerdict 'treeabsent' $taBefore (New-State @{ TreePresent = $false; SdusersPresent = $true }) 'yes' '') 'sdusers removed') $null

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 7. the preconditions refuse the vacuous measurements ==='
Check 'no snapshot at all is refused' ((Get-CasePrecondition 'treeabsent' $null '') -ne '') $null
Check 'a snapshot with no uninstaller is refused' `
      ((Get-CasePrecondition 'silentkeep' (New-State @{ UninsPresent = $false }) '') -like '*unins000*') $null
Check 'silentkeep with no sd.conf to keep is refused' `
      ((Get-CasePrecondition 'silentkeep' (New-State @{ ConfPresent = $false }) '') -ne '') $null
Check 'keepdb-delconf with sd.conf already absent is refused' `
      ((Get-CasePrecondition 'keepdb-delconf' (New-State @{ ConfPresent = $false }) '') -ne '') $null
Check 'deldb-keepconf with sdsys already absent is refused' `
      ((Get-CasePrecondition 'deldb-keepconf' (New-State @{ SdsysPresent = $false }) '') -ne '') $null
# THE ONE THIS MACHINE ACTUALLY HITS: sdusers holding only the installing user,
# whom -Keep excludes by construction, so nothing could ever be removed.
Check 'deldb-delacct with only the installing user in sdusers is refused' `
      ((Get-CasePrecondition 'deldb-delacct' (New-State @{ SdusersMembers = @('Don'); LocalUsers = @('Don') }) 'sdw50a') -ne '') $null
Check 'deldb-delacct without -Prefix is refused' `
      ((Get-CasePrecondition 'deldb-delacct' (New-State @{}) '') -like '*-Prefix*') $null
Check 'deldb-delacct whose account is not in sdusers is refused' `
      ((Get-CasePrecondition 'deldb-delacct' (New-State @{ SdusersMembers = @('Don', 'other') }) 'sdw50a') -ne '') $null
Check 'treeabsent with the tree still present is refused' `
      ((Get-CasePrecondition 'treeabsent' (New-State @{ TreePresent = $true }) '') -ne '') $null
Check 'treeabsent with sdusers already gone is refused' `
      ((Get-CasePrecondition 'treeabsent' (New-State @{ TreePresent = $false; SdusersPresent = $false; ProgramPresent = $true }) '') -ne '') $null
# AND THE POSITIVE CONTROL: the preconditions must actually say YES to the
# states these cases are meant to run in, or every row above passes trivially.
Check 'silentkeep says yes to a healthy tree'  ((Get-CasePrecondition 'silentkeep' (New-State @{}) '') -eq '') $null
Check 'deldb-delacct says yes to a machine with an SD account' `
      ((Get-CasePrecondition 'deldb-delacct' (New-State @{}) 'sdw50a') -eq '') $null
Check 'treeabsent says yes to a deleted tree with SD still installed' `
      ((Get-CasePrecondition 'treeabsent' $taBefore '') -eq '') $null

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== 8. mutant control, on a COPY - the live file is never touched ==='
$sandbox = Join-Path ([IO.Path]::GetTempPath()) ("uc-mutant-" + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $sandbox -Force
try {
    $copy = Join-Path $sandbox 'verify-uninstallchoices.ps1'
    $text = Get-Content -LiteralPath $target -Raw
    # Remove the operator's observation row from treeabsent - the exact
    # regression that would make this whole witness vacuous again.
    $mutated = $text -replace "Row \`$rows 'accounts question was OFFERED' 'yes' \`$saw", ''
    Check 'the mutation changed the text' ($mutated -ne $text) 'the row was not found by its own wording'
    Set-Content -LiteralPath $copy -Value $mutated -Encoding UTF8 -NoNewline

    $mtok = $null; $merr = $null
    $mast = [System.Management.Automation.Language.Parser]::ParseFile($copy, [ref]$mtok, [ref]$merr)
    $mfn  = Lift $mast 'Get-UninstallVerdict'
    if ($mfn.Count -eq 1) {
        $sb = [scriptblock]::Create(($mfn[0].Extent.Text -replace 'Get-UninstallVerdict', 'Get-MutantVerdict'))
        . $sb
        $rows = Get-MutantVerdict 'treeabsent' $taBefore $taAfter 'no' ''
        Check 'the mutant no longer fails on -Saw no (so the row was load-bearing)' `
              (-not (Failed $rows 'OFFERED')) 'the row survived the mutation - the control proves nothing'
    } else {
        Check 'the mutant still parses and lifts' $false "found $($mfn.Count) definitions"
    }
    # AND THE LIVE FILE IS UNCHANGED, byte for byte.
    Check 'the live script is untouched' ((Get-Content -LiteralPath $target -Raw) -eq $text) $null
} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("test-uninstallchoices-units: PASSED - {0} of {0} checks passed." -f $script:pass)
    exit 0
}
Write-Host ("test-uninstallchoices-units: FAILED - {0} of {1} checks failed." -f $script:fail, ($script:pass + $script:fail))
exit 1
