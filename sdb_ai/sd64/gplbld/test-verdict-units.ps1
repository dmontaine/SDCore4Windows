# Unit test for the Write-Verdict function added to verify-createaccount.ps1
# and verify-sshonly.ps1 on 24 Aug 2026.
#
# IT LIFTS THE FUNCTION OUT OF EACH SCRIPT BY AST, the way
# test-apiidentity-units.ps1 does, so it cannot drift from what it tests and
# needs no install, no SD and no account.
#
# THE POINT IS THAT THE CHECK CAN FAIL.  A verdict line that says PASSED
# whatever it is given is worse than none, because it would be believed.  So
# every case below asserts the wording AND the $fatal flag, and the null case -
# no decisive rows - must come back FAILED.

$ErrorActionPreference = 'Stop'

# $PSScriptRoot, NOT A HARDCODED PATH.  This lives beside what it tests, and a
# machine-specific path would make it a script only one clone can run - which
# is the sort of thing setup-devbox.ps1 exists to stop being true.
$gplbld  = $PSScriptRoot
# 28 Aug 26 - verify-vocverbs.ps1 and verify-acctmsgs.ps1 join the list in the
# commit that creates them.  Each carries the same "kept BYTE-FOR-BYTE
# IDENTICAL" comment as the other three, and a copy that claims that without
# anything checking it is a comment that rots on the first edit.
$targets = @('verify-createaccount.ps1', 'verify-sshonly.ps1', 'verify-cmdaudit.ps1',
             'verify-vocverbs.ps1', 'verify-acctmsgs.ps1', 'verify-tierchange.ps1')

# Collected so the two copies can be compared to each other, not just tested
# apart.  See the identical-copies assertion at the end.
$extents = @{}

$rows = @()
function Row($file, $case, $got, $want) {
    $ok = ($got -eq $want)
    $script:rows += [pscustomobject]@{
        File = $file; Case = $case; Got = $got; Want = $want
        Result = $(if ($ok) { 'PASS' } else { 'FAIL' })
    }
}

foreach ($name in $targets) {
    $path = Join-Path $gplbld $name
    Write-Host ("--- " + $path)
    if (-not (Test-Path -LiteralPath $path)) { Write-Host '    MISSING'; continue }

    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$t, [ref]$e)
    if ($e.Count -gt 0) { Write-Host ('    ' + $e.Count + ' parse errors'); continue }

    $fn = $ast.FindAll({ param($x)
        $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $x.Name -eq 'Write-Verdict' }, $true)

    # REFUSE THE NULL CASE: if the function is not there, this test must fail
    # rather than silently skip and report nothing.
    Row $name 'Write-Verdict is defined' ($fn.Count) 1
    if ($fn.Count -ne 1) { continue }

    # Lift it into this session.
    $extents[$name] = $fn[0].Extent.Text
    . ([scriptblock]::Create($fn[0].Extent.Text))
    Write-Host ('    lifted ' + $fn[0].Extent.Text.Length + ' chars')

    # --- case 1: all decisive checks passed -> PASSED, $fatal untouched
    $script:results = @(
        [pscustomobject]@{ Check='a'; Result='PASS'; Decisive='yes' },
        [pscustomobject]@{ Check='b'; Result='PASS'; Decisive='yes' },
        [pscustomobject]@{ Check='c'; Result='PASS'; Decisive='no'  })
    $script:fatal = $false
    $out = (Write-Verdict 'zz-test') | Out-String
    Row $name 'all pass -> says PASSED'      ([bool]($out -match 'zz-test: PASSED')) $true
    Row $name 'all pass -> counts decisive'  ([bool]($out -match '2 of 2 decisive'))  $true
    Row $name 'all pass -> reports all rows' ([bool]($out -match '3 row\(s\) in all')) $true
    Row $name 'all pass -> fatal stays false' $script:fatal $false

    # --- case 2: a decisive check failed -> FAILED, names it, sets fatal
    $script:results = @(
        [pscustomobject]@{ Check='alpha'; Result='PASS'; Decisive='yes' },
        [pscustomobject]@{ Check='beta';  Result='FAIL'; Decisive='yes' })
    $script:fatal = $false
    $out = (Write-Verdict 'zz-test') | Out-String
    Row $name 'a failure -> says FAILED'    ([bool]($out -match 'zz-test: FAILED')) $true
    Row $name 'a failure -> NOT PASSED'     ([bool]($out -match 'zz-test: PASSED')) $false
    Row $name 'a failure -> names the check' ([bool]($out -match 'beta'))           $true
    Row $name 'a failure -> sets fatal'      $script:fatal                          $true

    # --- case 3: THE NULL CASE.  Rows exist but none is decisive.
    $script:results = @(
        [pscustomobject]@{ Check='note only'; Result='PASS'; Decisive='no' })
    $script:fatal = $false
    $out = (Write-Verdict 'zz-test') | Out-String
    Row $name 'no decisive row -> FAILED'      ([bool]($out -match 'NO DECISIVE CHECK RAN')) $true
    Row $name 'no decisive row -> NOT PASSED'  ([bool]($out -match 'zz-test: PASSED'))       $false
    Row $name 'no decisive row -> sets fatal'  $script:fatal                                 $true

    # --- case 4: completely empty results.  The worst null case.
    $script:results = @()
    $script:fatal = $false
    $out = (Write-Verdict 'zz-test') | Out-String
    Row $name 'empty results -> FAILED'     ([bool]($out -match 'NO DECISIVE CHECK RAN')) $true
    Row $name 'empty results -> sets fatal'  $script:fatal                                $true
}

# ***THE TWO COPIES MUST BE IDENTICAL, AND THIS IS WHAT ENFORCES IT.***  Both
# scripts carry the same function and their comments say "if one changes,
# change both" - which is a hope, not a guard.  Session 51 paid for exactly
# that shape: the tier VOC counts lived in two files, one was re-derived, and
# NOTHING FAILED when the copies disagreed.  This fails.
if ($extents.Count -eq $targets.Count) {
    $texts  = @($targets | ForEach-Object { $extents[$_] })
    $allSame = $true
    for ($i = 1; $i -lt $texts.Count; $i++) {
        if ($texts[$i] -cne $texts[0]) { $allSame = $false }
    }
    Row '(all)' ('the ' + $texts.Count + ' Write-Verdict copies are identical') $allSame $true
    if (-not $allSame) {
        Write-Host '    they differ - diff the function across the files before doing anything else'
        for ($i = 0; $i -lt $texts.Count; $i++) {
            Write-Host ('      ' + $targets[$i] + '  ' + $texts[$i].Length + ' chars')
        }
    }
} else {
    Row '(all)' 'every copy was found' $extents.Count $targets.Count
}

# ---------------------------------------------------------------------------
# Get-LoginRecords, from verify-cmdaudit.ps1.  Same reasoning as above: it is a
# PURE function over text, so it can be driven with synthetic audit lines and
# needs no install, no SD and no elevation - which matters more here than
# usual, because the audit trail is readable only from an elevated session, so
# this is the ONLY part of that verifier testable without one.
$cmdaudit = Join-Path $gplbld 'verify-cmdaudit.ps1'
if (Test-Path -LiteralPath $cmdaudit) {
    Write-Host ('--- ' + $cmdaudit)
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($cmdaudit, [ref]$t, [ref]$e)
    $glr = $ast.FindAll({ param($x)
        $x -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $x.Name -eq 'Get-LoginRecords' }, $true)

    Row 'verify-cmdaudit.ps1' 'Get-LoginRecords is defined' ($glr.Count) 1
    if ($glr.Count -eq 1) {
        . ([scriptblock]::Create($glr[0].Extent.Text))
        Write-Host ('    lifted ' + $glr[0].Extent.Text.Length + ' chars')

        $n = 'verify-cmdaudit.ps1'

        # A command line and an interactive session, together, as LOGIN writes
        # them.  This is the shape the verifier asserts.
        $sample = @(
            '2026-08-24 18:30:00 LOGIN account=DON',
            '2026-08-24 18:30:05 LOGIN account=DON command=COUNT VOC',
            '2026-08-24 18:30:09 LOGIN REFUSED account=ZZ reason=something'
        ) -join "`n"
        $r = @(Get-LoginRecords $sample)
        Row $n 'parses both LOGIN forms'          $r.Count 2
        Row $n 'the bare form has no command'     (@($r | Where-Object { -not $_.HasCommand }).Count) 1
        Row $n 'the command form has one'         (@($r | Where-Object { $_.HasCommand }).Count)      1
        Row $n 'the command text survives spaces' (@($r | Where-Object { $_.Command -eq 'COUNT VOC' }).Count) 1
        Row $n 'the account is captured'          (@($r | Where-Object { $_.Account -eq 'DON' }).Count) 2

        # ***THE ORDERING TRAP.***  "LOGIN account=X command=Y" also matches a
        # pattern looking for "LOGIN account=X", so if the bare form were
        # tested first every command session would be classed as interactive -
        # which is the regression this verifier exists to catch, reported as a
        # pass.  This is the assertion that pins the order.
        $r2 = @(Get-LoginRecords '2026-08-24 18:30:05 LOGIN account=DON command=COUNT VOC')
        Row $n 'a command line is NOT read as bare' (@($r2 | Where-Object { $_.HasCommand }).Count) 1
        Row $n 'and yields exactly one record'      $r2.Count 1

        # Null cases: neither may invent a record.
        Row $n 'empty text yields nothing'   (@(Get-LoginRecords '').Count)   0
        Row $n 'null text yields nothing'    (@(Get-LoginRecords $null).Count) 0
        Row $n 'unrelated text yields none'  (@(Get-LoginRecords "nothing here`nnor here").Count) 0
    }
} else {
    Row 'verify-cmdaudit.ps1' 'the file exists' $false $true
}

Write-Host ''
$rows | Format-Table -AutoSize | Out-String | Write-Host

$bad = @($rows | Where-Object { $_.Result -ne 'PASS' })
if ($rows.Count -eq 0) {
    Write-Host 'NOTHING WAS TESTED - refusing to report a pass.'
    exit 2
}
if ($bad.Count -gt 0) {
    Write-Host ("FAILED - {0} of {1}" -f $bad.Count, $rows.Count)
    exit 1
}
Write-Host ("PASSED - {0} of {0} assertions" -f $rows.Count)
exit 0
