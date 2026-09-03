# test-stripcomments-units.ps1 - drive gplbld/strip-comments.ps1, the comment
# stripper shared by assert-current.ps1 and test-retired-wording-units.ps1.
#
# 02 Sep 26 Windows port - PRE_RELEASE_FIXES 143.
#
# WHY THIS EXISTS SEPARATELY FROM THE WORDING LINT.  The stripper used to live
# inside test-retired-wording-units.ps1, where its only witness was that lint's
# own assertions - so it was tested for "does the lint still pass", never for
# what it does to a line.  assert-current.ps1 now reads the same functions and
# fails in the OPPOSITE direction (an over-strip there hides a Source line and
# lets a stale tree report CURRENT), so the stripper needs tests of its own.
#
# INSTRUMENT RULES (CLAUDE.md):
#   - it ECHOES the resolved paths and the real sd.iss line it reasons about;
#   - it REFUSES the null case out loud - a fixture that produced no lines, or
#     an sd.iss that cannot be read, is a FAIL rather than a quiet pass;
#   - the 143 case is proved RED BEFORE GREEN against the REAL sd.iss: the
#     unstripped text must match, and the stripped text must not.  A test that
#     only checked "stripped does not match" would pass just as well if the
#     stripper deleted the whole file.
#
# Unelevated, no SD, no install, no network, no run token.  It writes one
# fixture into the system temp directory and deletes it.

[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'

$gplbld = ($PSScriptRoot -replace '\\', '/')
Write-Host "test-stripcomments-units: gplbld $gplbld"

. (Join-Path $PSScriptRoot 'strip-comments.ps1')

$script:pass = 0
$script:fail = 0
function Check($label, $ok, $detail) {
    if ($ok) { $script:pass++; Write-Host ("  [PASS] " + $label) }
    else {
        $script:fail++
        Write-Host ("  [FAIL] " + $label) -ForegroundColor Red
        if ($detail) { Write-Host ("         " + $detail) -ForegroundColor Red }
    }
}
function Section($m) { Write-Host ''; Write-Host ("=== " + $m + " ===") }

# --------------------------------------------------------------------------
Section '0. dot-sourcing must not impose StrictMode on the caller'
# The suite-only.ps1 trap: a dot-sourced file's file-scope strict mode binds the
# CALLER.  This scope is deliberately lax, so reading an undefined variable must
# still be legal here after the dot-source above.
$leaked = $false
try { $null = $NoSuchVariableAnywhere } catch { $leaked = $true }
Check "strict mode did NOT leak into this scope: $leaked" (-not $leaked) `
      'strip-comments.ps1 has set strict mode at file scope and bound its callers'

Check 'Get-StrippedLines is defined' `
      ($null -ne (Get-Command Get-StrippedLines -ErrorAction SilentlyContinue)) $null
Check 'Get-StrippedText is defined' `
      ($null -ne (Get-Command Get-StrippedText -ErrorAction SilentlyContinue)) $null

# --------------------------------------------------------------------------
Section '1. THE 143 CASE, RED BEFORE GREEN, ON THE REAL sd.iss'
# assert-current's rule: a quote or a slash before the name is evidence of a
# ship line.  sd.iss:4577 quotes the rejected spelling inside the paragraph
# explaining that the spelling is wrong, which is what re-tripped it.
$issPath = Join-Path $PSScriptRoot 'sd.iss'
$name    = 'probe-taskdialog.iss'
$shipPat = "[""'\\/]" + [regex]::Escape($name)

if (-not (Test-Path -LiteralPath $issPath)) {
    Check 'sd.iss is readable' $false "not found: $issPath"
} else {
    $raw      = Get-Content -LiteralPath $issPath -Raw
    $stripped = Get-StrippedText -Path $issPath -Kind 'iss'

    Write-Host ("  sd.iss raw {0} chars, stripped {1} chars" -f $raw.Length, $stripped.Length)

    # THE NULL CASE.  A stripper that emptied the file would pass the green
    # check below for the wrong reason.
    #
    # THE FLOOR IS MEASURED, NOT GUESSED, AND THE FIRST GUESS WAS WRONG.  It was
    # written as 40% and failed at 28%, which looked like over-stripping and was
    # not: counted on 2 Sep 2026, sd.iss is ~73% comment CHARACTERS - 61,004 in
    # leading-";" lines, ~105,652 in braced prose and ~30,683 in (* *) blocks,
    # against 269,947 raw.  So 28% surviving is right.  The floor is kept loose
    # and deliberately weak; section 2's canaries are the real control, because
    # "how much survived" cannot tell shipped text from comment.
    Check ("the strip left a substantial file (>= 15%): {0}%" -f [int](100 * $stripped.Length / [Math]::Max(1, $raw.Length))) `
          ($stripped.Length -ge $raw.Length * 0.15) `
          'the stripper is eating shipped text, not just comments'

    $rawHits      = @([regex]::Matches($raw,      $shipPat))
    $strippedHits = @([regex]::Matches($stripped, $shipPat))

    Check ("RED: the UNstripped sd.iss matches the ship pattern ({0} hit(s))" -f $rawHits.Count) `
          ($rawHits.Count -ge 1) `
          'the 143 case is no longer present, so this test proves nothing - check sd.iss:4577'
    Check ("GREEN: the stripped sd.iss does NOT ({0} hit(s))" -f $strippedHits.Count) `
          ($strippedHits.Count -eq 0) `
          'the comment quoting "gplbld/probe-taskdialog.iss" is still in the scanned text'
}

# --------------------------------------------------------------------------
Section '2. THE OVER-STRIP CONTROL: real ship lines must survive'
# assert-current fails expensively if the strip eats a Source line, so the two
# canaries it uses are asserted here as well - one per file and per syntax.
$stageP = Join-Path $PSScriptRoot 'stage.py'
if (Test-Path -LiteralPath $issPath) {
    $s = Get-StrippedText -Path $issPath -Kind 'iss'
    $p = "[""'\\/]" + [regex]::Escape('adopt-account.ps1')
    Check 'sd.iss still ships adopt-account.ps1 after stripping' `
          ($s -match $p) 'an sd.iss [Files] Source line was stripped away'
}
if (Test-Path -LiteralPath $stageP) {
    $s = Get-StrippedText -Path $stageP -Kind 'hash'
    $p = "[""'\\/]" + [regex]::Escape('deny-logon.ps1')
    Check 'stage.py still ships deny-logon.ps1 after stripping' `
          ($s -match $p) 'a stage.py ship tuple was stripped away'
} else {
    Check 'stage.py is readable' $false "not found: $stageP"
}

# --------------------------------------------------------------------------
Section '3. the [Files] semicolon trap'
# Inno separates [Files] parameters with ";".  A mid-line ";" rule would eat
# every Source line in the installer, so ";" counts only at the start of a line.
$fx = Join-Path ([System.IO.Path]::GetTempPath()) ('stripfx-' + [Guid]::NewGuid().ToString('N') + '.iss')
$fixture = @(
    '[Files]',
    'Source: "{#Stage}\a\adopt-account.ps1"; DestDir: "{app}"; Flags: ignoreversion',
    '; a whole-line comment naming "gplbld/secret-one.ps1"',
    'Source: "{#Stage}\b\keep-me.ps1"; DestDir: "{app}"   // trailing naming "x/secret-two.ps1"',
    '[Code]',
    'procedure P;  { prose naming "gplbld/secret-three.ps1" }',
    'begin',
    '  S := ExpandConstant(''{app}'') + ''\usr\bin'';   { {app} is a constant, not prose }',
    '  T := ''{#AppName}'';',
    '(* a paren-star block naming',
    '   "gplbld/secret-four.ps1"',
    ' *)',
    '  U := ''kept-four'';',
    '  { an unterminated brace opens here and names "gplbld/secret-five.ps1"',
    '    and closes on this line }  V := ''kept-five'';',
    'end;'
)
Set-Content -LiteralPath $fx -Value $fixture -Encoding ASCII
try {
    $lines = @(Get-StrippedLines -Path $fx -Kind 'iss')
    $text  = Get-StrippedText  -Path $fx -Kind 'iss'

    Check ("the fixture produced lines: {0}" -f $lines.Count) ($lines.Count -eq $fixture.Count) `
          ("expected $($fixture.Count)")

    Check 'a [Files] Source line survives its mid-line semicolons' `
          ($text -match [regex]::Escape('adopt-account.ps1')) `
          'the ";" rule is matching mid-line and eating Source entries'
    Check 'the second Source line survives too' `
          ($text -match [regex]::Escape('keep-me.ps1')) $null

    Check 'a whole-line ";" comment is stripped'      ($text -notmatch 'secret-one')   $null
    Check 'a trailing "//" comment is stripped'       ($text -notmatch 'secret-two')   $null
    Check 'a { } prose comment is stripped'           ($text -notmatch 'secret-three') $null
    Check 'a (* *) block comment is stripped'         ($text -notmatch 'secret-four')  $null
    Check 'a multi-line { } comment is stripped'      ($text -notmatch 'secret-five')  $null

    Check 'the {app} constant is KEPT'                ($text -match [regex]::Escape('{app}'))      $null
    Check 'the {#AppName} directive is KEPT'          ($text -match [regex]::Escape('{#AppName}')) $null
    Check 'code after a closed (* *) block is kept'   ($text -match 'kept-four') $null
    Check 'code after a closed { } comment is kept'   ($text -match 'kept-five') $null
} finally {
    Remove-Item -LiteralPath $fx -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------
Section '4. the hash kind, shared by .ps1 and .py'
$fx2 = Join-Path ([System.IO.Path]::GetTempPath()) ('stripfx-' + [Guid]::NewGuid().ToString('N') + '.py')
Set-Content -LiteralPath $fx2 -Value @(
    "SHIPPED = ('deny-logon.ps1', 'x')   # names 'gplbld/secret-six.ps1'",
    '# a whole-line remark naming "gplbld/secret-seven.ps1"',
    "KEEP = 'tail-value'"
) -Encoding ASCII
try {
    $t2 = Get-StrippedText -Path $fx2 -Kind 'hash'
    Check 'a tuple before a trailing # survives'  ($t2 -match [regex]::Escape('deny-logon.ps1')) $null
    Check 'the trailing # remark is stripped'     ($t2 -notmatch 'secret-six')   $null
    Check 'a whole-line # remark is stripped'     ($t2 -notmatch 'secret-seven') $null
    Check 'a later plain line survives'           ($t2 -match 'tail-value')      $null
} finally {
    Remove-Item -LiteralPath $fx2 -Force -ErrorAction SilentlyContinue
}

# --------------------------------------------------------------------------
Section '5. refusals and edges'
$missing = @(Get-StrippedLines -Path (Join-Path ([System.IO.Path]::GetTempPath()) 'no-such-file-xyz.iss') -Kind 'iss')
Check ("a missing file yields no lines rather than throwing: {0}" -f $missing.Count) ($missing.Count -eq 0) $null

$threw = $false
try { $null = Get-StrippedLines -Path $issPath -Kind 'nonsense' } catch { $threw = $true }
Check 'an unknown Kind is refused rather than silently treated as one' $threw `
      'ValidateSet is missing, so a typo would scan with the wrong rules'

# --------------------------------------------------------------------------
Write-Host ''
if ($script:fail -eq 0) {
    Write-Host ("test-stripcomments-units: PASSED - {0} of {0} checks passed." -f $script:pass)
    exit 0
} else {
    Write-Host ("test-stripcomments-units: FAILED - {0} of {1} checks failed." -f $script:fail, ($script:pass + $script:fail)) -ForegroundColor Red
    exit 1
}
