<#
.SYNOPSIS
    Free guard: the exact, checked scope of RELEASE_1.1 76's "driver re-aim" -
    every gplbld script that still hands SD a live "LOGTO SDSYS" line, sorted
    into what it actually is.

.DESCRIPTION
    WHY THIS EXISTS.  76's own entry has quoted "~17 rigs" and "NINETEEN
    HARNESS SITES" at different points, and neither number was ever derived
    from the tree - both were counted by eye from a grep, on a night when the
    same session's FIRST attempt at this exact survey scored 39 files as
    "comment-only" because it read the shared stripper's return keys wrong
    (.Number/.Line instead of the real .Line/.Text) and silently compared
    $null against every pattern.  That is CLAUDE.md's own instrument rule
    failing in the one place a session was relying on it to say "nothing left
    to do" - a confident zero from a check that never measured anything.  This
    file is the corrected version, kept as a STANDING GUARD rather than a
    one-off script, so the same mistake cannot recur unnoticed and the count
    stays true as files change.

    ***IT USES THE SHARED STRIPPER, NOT A COPY.***  gplbld/strip-comments.ps1
    is dot-sourced directly - Get-StrippedLines's 'hashblock' kind, the same
    function assert-current.ps1 and the wording lint already trust - so this
    guard can never disagree with them about what counts as a comment.
    ***'hashblock' RATHER THAN 'hash' SINCE 20 Sep 2026, RELEASE_1.1 81***:
    'hash' knows only "#" to end of line, and building this guard is what found
    that PowerShell's block-comment form was invisible to it.  'hash' is now
    REFUSED on a .ps1 outright, so this call site cannot quietly drift back.

    (That form is not spelled out here, and the reason is worth the line: the
    first draft of this paragraph WROTE it, the closing delimiter ended this
    very help block forty lines early, and the file stopped parsing.  The same
    shape the fix is about, one level up.)

    ***A LIVE "LOGTO SDSYS" IS NOT ONE THING, AND SORTING THEM MATTERS.***
    Reading every hit by hand (20 Sep 2026) found four different roles wearing
    the same three words:

      DRIVER            A script that bakes an unconditional "LOGTO SDSYS"
                         into its own Invoke-SD / Invoke-Bounded so its pipe
                         lands in the SDSYS account.  RELEASE_1.1 64 slices 1-2
                         refuse that prefix outright (cproc:2789, 10002) from
                         any session that did not already start elevated as
                         SDSYS, so every one of these is currently BROKEN and
                         is what 76's re-aim has to fix.  ***RELEASE_1.1 78
                         WAS THE BLOCKER AND IS CLOSED (20 Sep 2026): NOT A
                         DEFECT, SDSYS SIGNS IN AT THE CONSOLE.***  Route D
                         (76) then measured a working seat: a task in SDSYS's
                         own live session.  So the fix is NOT "stop sending
                         LOGTO SDSYS" - it is a shared helper that hands each
                         sd.exe call to that task and reads the output back,
                         adopted here 34 times.  Written in the conditional
                         because nothing here is built.

      CALLER_SUPPLIED   Same defect, different shape: Invoke-SD itself sends
                         no prefix, and the CALLING code passes 'LOGTO SDSYS'
                         as the first literal command, assuming an elevated
                         administrator's own session could still reach SDSYS
                         with it.  It cannot, for the same reason.  One file.

      GATE              The refusal (or the elevated round-trip) IS the
                         subject under test - this is what verify-elevdoor.ps1
                         and part of verify-sdsysgate.ps1 measure on purpose,
                         and 64 did not break it: an unelevated LOGTO SDSYS
                         SHOULD be refused, and that is exactly what these
                         assert.  Not broken, not this entry's to fix - listed
                         so a future sweep does not "fix" a passing test.

      FIXTURE           No live invocation at all: synthetic test data or an
                         assertion about ANOTHER script's own source text.
                         test-sdtestuser-units.ps1 in particular must be
                         updated IN LOCKSTEP with sdtestuser-admin.ps1 the day
                         that driver is actually re-aimed, or it will assert a
                         prefix the product no longer sends.

    ***EVERY FILE IS HAND-DECLARED, NOT AUTO-SORTED, AND THAT IS A DELIBERATE
    CHOICE.***  A structural heuristic (which variable the array is assigned
    to, whether 'WHO' brackets it) could tell a DRIVER from a GATE most of the
    time and be silently wrong on the one file that matters -
    verify-sdsysgate.ps1 carries BOTH shapes forty lines apart in the same
    file.  So this guard does what test-acctkeywords-units.py's PENDING table
    already does: every live hit is READ and DECLARED with why, and an
    UNDECLARED file is a FAIL, not a guess - the same demand PENDING makes of
    itself, and the reason a stale declaration is a FAIL rather than a quiet
    pass (a file re-aimed and left declared DRIVER would otherwise sit here
    claiming work already done).

    Exit 0 all checks passed, 1 a check failed, 2 it could not measure.
#>

$ErrorActionPreference = 'Stop'
$gplbld = Split-Path -Parent $PSCommandPath
. (Join-Path $gplbld 'strip-comments.ps1')

$pass = 0
$fail = 0
function Check([string]$label, [bool]$ok, [string]$detail = '') {
    if ($ok) { $script:pass++; Write-Output ("  [PASS] " + $label) }
    else     { $script:fail++; Write-Output ("  [FAIL] " + $label + $(if ($detail) { "  -> $detail" } else { '' })) }
}

$rx = 'logto\s+sdsys'

# --- the declaration --------------------------------------------------------
# Role -> reason, read from the file and written down 20 Sep 2026.  A file not
# in this table with a live hit is UNDECLARED and fails outright.
$DECLARED = [ordered]@{
    'clean-deadvoc.ps1'           = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'interop-account.ps1'         = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'probe-catprivate.ps1'        = @{ Role = 'DRIVER'; Why = 'unconditional prefix, plus its own elevation message' }
    'probe-osex.ps1'              = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'probe-tasklock.ps1'          = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'sdtestuser-admin.ps1'        = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-accountacl.ps1'       = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-accountrules.ps1'     = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-acctmsgs.ps1'         = @{ Role = 'DRIVER'; Why = 'unconditional prefix, plus its own explanatory line' }
    'verify-apiname.ps1'          = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-apiport.ps1'          = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-apiremote.ps1'        = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-apiwire.ps1'          = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-catgate.ps1'          = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-createaccount.ps1'    = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-createfilecase.ps1'   = @{ Role = 'DRIVER'; Why = 'unconditional prefix, plus its own explanatory lines' }
    'verify-delaccount.ps1'       = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-delacc-xref.ps1'      = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-dictrename.ps1'       = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-doors-admin.ps1'      = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-fold.ps1'             = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-nonet.ps1'            = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-nocaseupgrade.ps1'    = @{ Role = 'DRIVER'; Why = 'prefix sent unless -internal; the -internal leg is the one escape already in the tree' }
    'verify-profiledir.ps1'       = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-pyapi.ps1'            = @{ Role = 'DRIVER'; Why = 'unconditional prefix, plus its own explanatory line' }
    'verify-pygate.ps1'           = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-scramlogin.ps1'       = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-sshadmin.ps1'         = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder (also PENDING in test-acctkeywords-units.py for the ADMINISTRATOR keyword - two separate defects in one file)' }
    'verify-twins.ps1'            = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-uninstallchoices.ps1' = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }
    'verify-vocverbs.ps1'         = @{ Role = 'DRIVER'; Why = 'unconditional prefix, plus its own explanatory line' }
    'verify-vocwrite.ps1'         = @{ Role = 'DRIVER'; Why = 'unconditional prefix in its own body builder' }

    'verify-lcnames.ps1'          = @{ Role = 'CALLER_SUPPLIED'; Why = "Invoke-SD sends no prefix itself; the CALLERS' own command arrays open with the literal 'LOGTO SDSYS'" }

    # verify-sdsysgate.ps1 is the one file that is genuinely both: its own
    # Invoke-SD (used for setup/teardown around the real test) carries the
    # broken unconditional prefix, DRIVER-shaped; forty lines further down,
    # -Commands @('WHO', 'LOGTO SDSYS', 'WHO') is the file's actual SUBJECT -
    # "a non-administrator tries LOGTO SDSYS and is refused" - which is a GATE
    # line and must not be touched by the re-aim.  Declared once, as both,
    # because the guard partitions by FILE and a file cannot be asked to pick.
    'verify-sdsysgate.ps1'        = @{ Role = 'DRIVER+GATE'; Why = 'its own Invoke-SD carries the broken prefix (setup/teardown); a separate line 40 further on is the deliberate gate test and must survive the re-aim untouched' }

    'verify-elevdoor.ps1'         = @{ Role = 'GATE'; Why = 'the unelevated refusal and the elevated round-trip ARE the thing under test; not broken by 64, not this entry to fix' }

    'test-lcnameslegs-units.ps1'  = @{ Role = 'FIXTURE'; Why = 'embeds a synthetic script as test data; no live invocation of its own' }
    'test-sdtestuser-units.ps1'   = @{ Role = 'FIXTURE'; Why = "asserts sdtestuser-admin.ps1's OWN source contains the prefix - must be edited in lockstep the day that driver is re-aimed, or it will fail asserting a prefix the product no longer sends" }

    # ***THERE IS NO "COMMENT" ROLE ANY MORE, AND ITS DISAPPEARANCE IS THE
    # POINT.***  20 Sep 26, RELEASE_1.1 81.  This table used to carry two -
    # probe-sdsysseat.ps1 and verify-routes.ps1 - whose "LOGTO SDSYS" sat
    # inside a <# .SYNOPSIS #> help block that the stripper's 'hash' Kind could
    # not see, so they arrived here looking live and had to be declared away by
    # hand.  81 gave the stripper a 'hashblock' Kind that reads the block, and
    # the two rows stopped being reachable: they are comments now, to the
    # instrument as well as to a reader, so the guard never sees them.
    #
    # ***A DECLARATION THAT EXISTS ONLY TO EXCUSE AN INSTRUMENT'S BLIND SPOT IS
    # A BUG WEARING A TABLE ROW.***  Deleting these two is what fixing the
    # stripper LOOKS like from here, and it is why the partition check that
    # fails a stale declaration is the row that matters: it is what forced the
    # deletion in the same commit rather than leaving two dead excuses behind.
    #
    # The gap was also predicted to affect assert-current.ps1's ship-detection.
    # ***CHECKED, 20 Sep 2026: IT DOES NOT.***  That script strips only
    # stage.py ('hash') and sd.iss ('iss'), and stage.py contains no "<#" at
    # all - Python has no such form.  The wording lint WAS affected: 655 lines
    # across 19 files.  Measured, not assumed, and recorded in 81.
}

$ROLES_NEEDING_REAIM = @('DRIVER', 'CALLER_SUPPLIED', 'DRIVER+GATE')

Write-Output 'test-logtoreaim-units: the checked scope of RELEASE_1.1 76''s driver re-aim.'
Write-Output ("  gplbld : " + $gplbld)
Write-Output ''

# --- control: the stripper must find a KNOWN-LIVE line ---------------------
# This is the exact mistake this file exists to stop recurring: an earlier
# pass this same night read the wrong hashtable keys, got $null for every
# comparison, and reported "0 live" everywhere - a confident, wrong all-clear.
# If this control ever fails, nothing below can be trusted.
$controlFile = Join-Path $gplbld 'verify-createaccount.ps1'
$controlLines = @(Get-StrippedLines -Path $controlFile -Kind hashblock)
$controlHit = @($controlLines | Where-Object { $_.Text -match $rx })
Check 'CONTROL: the stripper finds a known-live LOGTO SDSYS line (verify-createaccount.ps1)' `
      ($controlHit.Count -ge 1) ("found " + $controlHit.Count + " - the stripper or its key names are wrong")
if ($controlHit.Count -eq 0) {
    Write-Output ''
    Write-Output 'test-logtoreaim-units: REFUSING to report a scope with a dead instrument.'
    exit 2
}

# --- the scan ----------------------------------------------------------------
# EXCLUDES ITS OWN FILE.  $DECLARED's Why-strings quote the very phrase this
# scans for, in double-quoted PowerShell strings no stripper can tell from
# code - so without this a guard would fail naming itself.  'hashblock' does
# not help here and is not meant to: those strings ARE live script text.
$selfName = Split-Path -Leaf $PSCommandPath
$scripts = @(Get-ChildItem -LiteralPath $gplbld -Filter *.ps1 -File | Where-Object { $_.Name -ne $selfName })
Check 'CONTROL: the gplbld directory has a full set of scripts (150+)' `
      ($scripts.Count -ge 150) ("found " + $scripts.Count + " - is the path right?")

$found = [ordered]@{}
foreach ($f in ($scripts | Sort-Object Name)) {
    $stripped = @(Get-StrippedLines -Path $f.FullName -Kind hashblock)
    $hit = @($stripped | Where-Object { $_.Text -match $rx })
    if ($hit.Count -gt 0) { $found[$f.Name] = $hit }
}
Check 'the scan found files to judge' ($found.psbase.Count -gt 0) ("found " + $found.psbase.Count)

# --- the partition: every live file is declared, no leftovers --------------
$undeclared = @($found.Keys | Where-Object { -not $DECLARED.Contains($_) })
Check ("no undeclared file carries a live LOGTO SDSYS ({0} live file(s), {1} declared)" -f $found.psbase.Count, $DECLARED.Count) `
      ($undeclared.Count -eq 0) `
      ("undeclared: " + ($undeclared -join ', ') + " - read it and add it to `$DECLARED, or the re-aim's scope is wrong")

# A stale declaration is a FAIL, matching test-acctkeywords-units.py's own
# rule for PENDING: a file re-aimed (or its gate/fixture removed) must leave
# this table in the SAME commit, or the count below overstates what is left.
$stale = @($DECLARED.Keys | Where-Object { -not $found.Contains($_) })
Check ("no declaration is stale ({0} declared)" -f $DECLARED.Count) `
      ($stale.Count -eq 0) `
      ("declared but no longer live: " + ($stale -join ', ') + " - remove it from `$DECLARED, the work is done")

Write-Output ''
Write-Output 'BY ROLE:'
$byRole = @{}
foreach ($k in $DECLARED.Keys) {
    $r = $DECLARED[$k].Role
    if (-not $byRole.ContainsKey($r)) { $byRole[$r] = New-Object System.Collections.ArrayList }
    [void]$byRole[$r].Add($k)
}
foreach ($r in ($byRole.Keys | Sort-Object)) {
    Write-Output ("  {0,-16} {1,3}  {2}" -f $r, $byRole[$r].Count, (($byRole[$r] | Sort-Object) -join ', '))
}

$reaimCount = @($DECLARED.Keys | Where-Object { $ROLES_NEEDING_REAIM -contains $DECLARED[$_].Role }).Count
Write-Output ''
Write-Output ("*** RELEASE_1.1 76's DRIVER RE-AIM, CHECKED SCOPE: {0} file(s) still send a live LOGTO SDSYS prefix that RELEASE_1.1 64 slices 1-2 refuse (10002). ***" -f $reaimCount)
Write-Output '    78 is closed (not a defect: SDSYS signs in) and route D is a measured seat, so what'
Write-Output '    the re-aim needs is a shared helper, not a prefix deletion - see RELEASE_1.1 76.'

# --- mutant control, on a COPY of the directory, never the live files ------
Write-Output ''
Write-Output 'MUTANT CONTROL (--gplbld points this run at a copy):'
if ($MyInvocation.UnboundArguments -contains '--gplbld') {
    Write-Output '  (skipped - this IS the mutant run)'
} else {
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('logtoreaim-mutant-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $tmp | Out-Null
    try {
        Copy-Item -LiteralPath (Join-Path $gplbld 'strip-comments.ps1') -Destination $tmp
        # The control check needs its known-live file too, or the mutant run
        # refuses on a dead instrument before it ever reaches the partition -
        # which is correct behaviour, but not what THIS control is testing.
        Copy-Item -LiteralPath (Join-Path $gplbld 'verify-createaccount.ps1') -Destination $tmp
        # Plant an UNDECLARED live occurrence: a file with the phrase and no
        # entry in $DECLARED must fail the partition check.
        Set-Content -LiteralPath (Join-Path $tmp 'zz-planted.ps1') -Value @(
            '# a planted, undeclared driver',
            "`$body = `"LOGTO SDSYS`""
        )
        $mutantSelf = (Join-Path $tmp (Split-Path -Leaf $PSCommandPath))
        Copy-Item -LiteralPath $PSCommandPath -Destination $mutantSelf
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $mutantSelf --gplbld 2>&1
        $mutantFailed = ($LASTEXITCODE -ne 0) -and ($out -match [regex]::Escape('zz-planted.ps1'))
        Check 'MUTANT: an undeclared planted driver is caught by name' $mutantFailed `
              'the partition check did not name the planted file'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output ''
Write-Output ("test-logtoreaim-units: {0} passed, {1} failed." -f $pass, $fail)
exit $(if ($fail -gt 0) { 1 } else { 0 })
