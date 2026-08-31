# reword-yn-prompts.ps1 - one-shot byte-level rewording of the Y/N prompts left
# open by PRE_RELEASE_FIXES.md 79, run once on 30 Aug 2026 and kept for the
# record.
#
# WHY A SCRIPT AND NOT THE EDITING TOOLS, which is CLAUDE.md's default and its
# rule: every one of these messages ends in a TRAILING SPACE before its newline
# - the gap between the prompt and the typed answer, because the caller uses
# "display ... :" - and the Edit and Write tools both strip a trailing space from
# the content given to them.  This is CLAUDE.md's own exemption for a transform
# the editing tools cannot do.  Entry 79 recorded the same thing the first time
# and said it would recur; it did.
#
# EVERY SUBSTITUTION IS CHECKED THREE WAYS, because a silent miss here changes a
# prompt's meaning without changing its behaviour:
#   1. the old text must appear EXACTLY ONCE - not zero (already done, or the
#      wording moved) and not twice (the wrong site would be hit);
#   2. the file must grow by EXACTLY the difference in length;
#   3. the last two bytes must still be space + newline afterwards (or, for the
#      one message that never had a trailing space, unchanged in that respect).
# Any failure leaves that file untouched and sets a non-zero exit.
#
#   powershell -File reword-yn-prompts.ps1 -WhatIf    show, change nothing
#   powershell -File reword-yn-prompts.ps1            apply
#
# Unelevated.  It writes only under sdsys/messages in the SOURCE tree.

[CmdletBinding()]
param([switch]$WhatIf)

$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot '..\sdsys\messages'
$dir = (Resolve-Path -LiteralPath $dir).Path
Write-Host "messages: $dir"

# old -> new.  The OLD text includes enough context to be unique in its file.
$edits = @(
    @{ N = '2060'; Old = 'Overwrite (Y/N/Q)? ';                      New = 'Overwrite (y/<n>/q)? ' },
    @{ N = '7143'; Old = 'OK to print (Y/N/Q/?)? ';                  New = 'OK to print (<y>/n/q/?)? ' },
    @{ N = '5049'; Old = 'Replace record(Y/N)? ';                    New = 'Replace record (y/<n>/a)? ' },
    @{ N = '6585'; Old = 'OK to overwrite (Y/N)? ';                  New = 'OK to overwrite (y/<n>)? ' },
    @{ N = '7211'; Old = 'Omit blank data lines (Y/N)';              New = 'Omit blank data lines (y/<n>)' },
    @{ N = '6554'; Old = 'to under line %3? ';                       New = 'to under line %3 (y/<n>)? ' },
    @{ N = '6555'; Old = 'delete the entire record? ';               New = 'delete the entire record (y/<n>)? ' },
    @{ N = '6556'; Old = 'to line %2? ';                             New = 'to line %2 (y/<n>)? ' },
    @{ N = '6558'; Old = 'delete the entire record? ';               New = 'delete the entire record (y/<n>)? ' },
    @{ N = '6577'; Old = 'to under line %3? ';                       New = 'to under line %3 (y/<n>)? ' }
)

# Latin-1 is a 1:1 byte mapping, so a round trip cannot alter a byte this script
# did not mean to alter.  Reading as UTF-8 and writing back is what
# double-encoded 272 em dashes on 28 Aug.
$enc  = [System.Text.Encoding]::GetEncoding(28591)
$bad  = 0
$done = 0

foreach ($e in $edits) {
    $p = Join-Path $dir $e.N
    if (-not (Test-Path -LiteralPath $p)) {
        Write-Host ("  [SKIP] {0} - no such message file" -f $e.N); $bad++; continue
    }

    $before = [System.IO.File]::ReadAllBytes($p)
    $text   = $enc.GetString($before)

    $hits = ([regex]::Matches($text, [regex]::Escape($e.Old))).Count
    if ($hits -ne 1) {
        Write-Host ("  [FAIL] {0} - '{1}' appears {2} time(s), expected exactly 1" -f $e.N, $e.Old, $hits)
        $bad++; continue
    }

    $newText = $text.Replace($e.Old, $e.New)
    $after   = $enc.GetBytes($newText)
    $want    = $before.Length + ($e.New.Length - $e.Old.Length)

    if ($after.Length -ne $want) {
        Write-Host ("  [FAIL] {0} - would be {1} bytes, expected {2}" -f $e.N, $after.Length, $want)
        $bad++; continue
    }

    # The tail: whatever it was before, it must be the same after.  For nine of
    # these that is "space, newline"; for 7211 it is "), newline".
    $tailBefore = ($before[-2..-1] | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    $tailAfter  = ($after[-2..-1]  | ForEach-Object { '{0:X2}' -f $_ }) -join ' '
    if ($tailBefore -cne $tailAfter) {
        Write-Host ("  [FAIL] {0} - tail changed {1} -> {2}" -f $e.N, $tailBefore, $tailAfter)
        $bad++; continue
    }

    if ($WhatIf) {
        Write-Host ("  [WHATIF] {0}  {1} -> {2} bytes  tail {3}  |{4}|" -f
                    $e.N, $before.Length, $after.Length, $tailAfter, $e.New)
    } else {
        [System.IO.File]::WriteAllBytes($p, $after)
        Write-Host ("  [OK]     {0}  {1} -> {2} bytes  tail {3}  |{4}|" -f
                    $e.N, $before.Length, $after.Length, $tailAfter, $e.New)
    }
    $done++
}

Write-Host ''
Write-Host ("reword-yn-prompts: {0} of {1} message(s) {2}, {3} refused." -f
            $done, $edits.Count, $(if ($WhatIf) { 'would change' } else { 'changed' }), $bad)
if ($bad -gt 0) { exit 1 }
if ($done -ne $edits.Count) { Write-Host 'refusing: not every edit was applied'; exit 1 }
exit 0
