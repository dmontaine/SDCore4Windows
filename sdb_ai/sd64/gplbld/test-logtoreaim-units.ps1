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
                         sd.exe call to that task and reads the output back.
                         ***21 Sep 2026: THE HELPER IS BUILT (sdsys-seat.ps1),
                         WITNESSED ON A REAL MACHINE FOR THE PILOT AND THE
                         MECHANICAL GROUP.  NO DRIVER IS LEFT IN THE TABLE
                         BELOW: sdtestuser-admin, verify-lcnames,
                         verify-apiadmin AND verify-privundetermined WERE ALL
                         CONVERTED THAT DAY AND ARE UNWITNESSED.***

      CALLER_SUPPLIED   Same defect, different shape: Invoke-SD itself sends
                         no prefix, and the CALLING code passes 'LOGTO SDSYS'
                         as the first literal command, assuming an elevated
                         administrator's own session could still reach SDSYS
                         with it.  It cannot, for the same reason.  One file
                         (verify-lcnames.ps1), converted 21 Sep 2026.

      GATE              The refusal (or the elevated round-trip) IS the
                         subject under test - this is what verify-elevdoor.ps1
                         and part of verify-sdsysgate.ps1 measure on purpose,
                         and 64 did not break it: an unelevated LOGTO SDSYS
                         SHOULD be refused, and that is exactly what these
                         assert.  Not broken, not this entry's to fix - listed
                         so a future sweep does not "fix" a passing test.

      FIXTURE           No live invocation at all: synthetic test data or an
                         assertion about ANOTHER script's own source text.
                         test-sdtestuser-units.ps1 in particular had to be
                         updated IN LOCKSTEP with sdtestuser-admin.ps1 when that
                         driver was re-aimed (done, 21 Sep 2026): it now asserts
                         the admin half sends NO live prefix, so the phrase is
                         data in its rows.

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
# 21 Sep 26 - THE SECOND PATTERN, AND WHY THE FIRST WAS NOT ENOUGH.  RELEASE_1.1 76
# counted three scripts still sending the refused prefix; two MORE existed that this
# guard could not see: verify-apiadmin.ps1 and verify-privundetermined.ps1 build
# "LOGTO $account" inside Invoke-SDIn and are called as Invoke-SDIn 'SDSYS' ..., so
# the literal phrase is never in them.  This matches that call shape - the literal
# SDSYS handed to the helper as its account.  It is deliberately NARROW: a bare
# "LOGTO $var" is legitimate (verify-catgate and others move into a PERSONAL account
# through the seat's -Internal door), and no text scan can tell such a line from one
# whose variable happens to hold SDSYS.  Its two controls are below.
$rx2 = 'Invoke-SDIn\s+[''"]SDSYS[''"]'

# --- the declaration --------------------------------------------------------
# Role -> reason, read from the file and written down 20 Sep 2026.  A file not
# in this table with a live hit is UNDECLARED and fails outright.
$DECLARED = [ordered]@{
    # interop-account.ps1 IS NOT HERE: CONVERTED 20 Sep 2026 (the twenty-third pass) -
    # its Invoke-SD is a one-line call to Invoke-SdSeatText and it proves the seat with
    # Assert-SdSeat before it creates anything.  NOT WITNESSED: it makes a Windows
    # account and opens a firewall port, so its first run is the owner's, elevated.
    # probe-tasklock.ps1 IS NOT HERE: DELETED 21 Sep 2026 on the owner's ruling
    # ("remove probe-tasklock") - a one-shot probe for PRE_RELEASE 24, which is
    # closed, still sending the refused prefix.
    # ***ALL FOUR DRIVERS THE OWNER RULED "CONVERT" ON 21 Sep 2026 ARE DONE AND ARE NOT
    # HERE.  RELEASE_1.1 76.***  NONE OF THE FOUR IS WITNESSED; each needs one elevated
    # run with SDSYS signed in.
    #   sdtestuser-admin.ps1   CONVERTED: Invoke-SdAdmin is a call to Invoke-SdSeatText,
    #                          caught and turned back into text, and Assert-SdSeat runs
    #                          before anything is swept or made.
    #   verify-lcnames.ps1     CONVERTED: the RunLegs re-entry calls Invoke-SdSeatText per
    #                          leg and the four legs no longer open with the prefix.
    # verify-apiadmin.ps1 AND verify-privundetermined.ps1 ARE NOT HERE: CONVERTED 21 Sep
    # 2026 (RELEASE_1.1 76), THE LAST TWO.  They never matched the literal pattern - they
    # built "LOGTO $account" and passed 'SDSYS' in as the account - which is what the second
    # pattern ($rx2) exists to see, and each row had to leave this table in the commit that
    # converted the file.  Invoke-SDSys is now a plain seat call, Invoke-SDIn goes through
    # the seat's -Internal door and REFUSES 'SDSYS', and the local OS.EXECUTE control plants
    # a temporary os.users\SDSYS record (Set-SeatOsUsersRecord) and removes it.  NEITHER IS
    # WITNESSED: converted unattended, each needs one elevated run with SDSYS signed in.
    # 20 Sep 2026, THE TWENTY-THIRD PASS: acctmsgs, catgate, delaccount, doors-admin and
    # uninstallchoices ARE NOT HERE - CONVERTED, on the owner's "convert the remaining
    # verifiers" (probe-tasklock excepted, at his word).  NONE IS WITNESSED.  Four were plain
    # drivers (acctmsgs, delaccount, doors-admin, uninstallchoices: CREATE/MODIFY/DELETE
    # .ACCOUNT as SDSYS, and 76's row was wrong to group doors-admin and delaccount with the
    # privilege-subject ones - neither LOGTOs into a personal account).  ONE is the genuine
    # privilege-subject case: verify-catgate chooses its seat door PER CALL, -Internal only
    # where the call itself starts with LOGTO, and its header says to read the refusal rows
    # first.  verify-sdsysgate is re-declared below as a GATE: its driver is converted and
    # only the deliberate gate line remains.
    # verify-createaccount.ps1 IS NOT HERE: IT WAS CONVERTED (20 Sep 2026, the
    # PILOT for sdsys-seat.ps1) - its SD calls now run as a task inside SDSYS's
    # own session, so it sends no prefix.  Its row had to go in the same commit,
    # because a declaration for a file that no longer carries the phrase is a
    # STALE DECLARATION and fails the partition check below.  Each further
    # conversion deletes its row the same way, and the count printed at the end
    # falls by one.
    #
    # ***THE MECHANICAL GROUP IS NOT HERE EITHER - CONVERTED THE SAME DAY (20 Sep
    # 2026) AFTER THE PILOT PASSED 18/18 ON A REAL MACHINE:*** verify-accountacl,
    # verify-apiname, verify-apiport, verify-apiwire, verify-delacc-xref,
    # verify-profiledir, verify-scramlogin, verify-vocwrite.  Their Invoke-SD is a
    # one-line call to Invoke-SdSeatText and each proves the seat with
    # Assert-SdSeat before creating anything.  ALL EIGHT WITNESSED ON A REAL MACHINE,
    # 20 Sep 2026: profiledir, accountacl, apiname, apiport, scramlogin, delacc-xref
    # and vocwrite fully; apiwire through every step this machine can measure (its
    # packet capture is ruled a dead end here, 15 Sep).  apiwire and vocwrite FAILED
    # their first run - they LOGTO into a personal account, which the seat refuses -
    # and were re-built on the seat's -Internal switch, then passed.
    #
    # ***THE SUITE-STEP GROUP IS NOT HERE EITHER - CONVERTED 20 Sep 2026 (the
    # morning after the mechanical group).  WITNESSED THE SAME AFTERNOON, -Run b200
    # and b201: fold, nonet, vocverbs, createfilecase, dictrename, twins,
    # nocaseupgrade, pyapi and pygate pass through the seat; verify-accountrules
    # ran through it too but its SUBJECT is stale (RELEASE_1.1 68 withdrew the
    # refusal its step 1 expects, 64 abolished the ADOPT its step 4 tests) and it
    # needs a rewrite.***  The group: verify-twins,
    # verify-nonet, verify-dictrename, verify-fold, verify-createfilecase,
    # verify-accountrules, verify-vocverbs, and then verify-pygate, verify-pyapi and
    # verify-nocaseupgrade.  Same shape as the mechanical group: a
    # one-line Invoke-SD over Invoke-SdSeatText and an Assert-SdSeat before anything
    # is made.  verify-twins uses BOTH doors (plain, and -Internal for the one thing
    # only sd -internal can build, a case-sensitive file).  The sd -internal legs of
    # verify-createfilecase and verify-accountrules are NOT seat calls - they run
    # from the elevated shell on purpose and are the shipped scripts' shape (and
    # since RELEASE_1.1 82 each writes LOGIN's one-shot marker first).
    #
    # ***AND THE OWNER'S "REWRITE" AND "CONVERT" RULINGS, 20 Sep 2026 AFTERNOON:***
    # verify-sshadmin and verify-apiremote were REWRITTEN to what is left of their
    # subjects (the ssh door and the API door, end to end: the route keyword decides,
    # the address does not) and go through the seat; verify-accountrules was rewritten
    # (silence means BOTH, and the ATTACH refusal); and the three one-shots
    # clean-deadvoc, probe-catprivate and probe-osex were CONVERTED.  probe-osex's
    # question changes with the conversion - see the note above its Invoke-SD.  NONE
    # OF THESE IS WITNESSED YET.
    # (verify-lcnames.ps1 WAS THE ONE CALLER_SUPPLIED ROW, AND IS CONVERTED - see above.
    # The role is kept in the header because a future file can have that shape.)

    # verify-sdsysgate.ps1 is the one file that is genuinely both: its own
    # Invoke-SD (used for setup/teardown around the real test) carries the
    # broken unconditional prefix, DRIVER-shaped; forty lines further down,
    # -Commands @('WHO', 'LOGTO SDSYS', 'WHO') is the file's actual SUBJECT -
    # "a non-administrator tries LOGTO SDSYS and is refused" - which is a GATE
    # line and must not be touched by the re-aim.  Declared once, as both,
    # because the guard partitions by FILE and a file cannot be asked to pick.
    'verify-sdsysgate.ps1'        = @{ Role = 'GATE'; Why = "its setup/teardown Invoke-SD was CONVERTED to the seat (20 Sep 2026, unwitnessed); what is left is the deliberate -Commands @('WHO', 'LOGTO SDSYS', 'WHO') line, run over ssh as a real non-administrator, which MUST keep being refused" }

    'verify-elevdoor.ps1'         = @{ Role = 'GATE'; Why = 'the unelevated refusal and the elevated round-trip ARE the thing under test; not broken by 64, not this entry to fix' }

    # test-lcnameslegs-units.ps1 IS NOT HERE: its embedded synthetic legs dropped the
    # prefix in lockstep with verify-lcnames.ps1 (21 Sep 2026), so it carries the phrase
    # only in its help text now, and a declaration for that is a stale one.
    'test-sdtestuser-units.ps1'   = @{ Role = 'FIXTURE'; Why = "asserts about sdtestuser-admin.ps1's OWN source and about verify-elevdoor.ps1 as its control; since 21 Sep 2026 it asserts the admin half sends NO live prefix, so the phrase appears in its rows as data" }

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
# THE CONTROL FILE MUST BE ONE THAT WILL NEVER BE CONVERTED, and it has been
# three files that were, each of which made this check fail with "found 0" the day
# it was converted - the instrument saying its known-live example had stopped
# being live: verify-createaccount.ps1 (the pilot, 20 Sep 2026), verify-fold.ps1
# (20 Sep 2026), and sdtestuser-admin.ps1 (21 Sep 2026, the last DRIVER).
# THERE IS NO DRIVER LEFT TO CHOOSE, AND THE ANSWER IS A GATE: verify-elevdoor.ps1's
# refusal of LOGTO SDSYS is its whole subject (64 did not break it), so its live line
# is permanent by design and this control cannot be converted out from under itself.
$controlName = 'verify-elevdoor.ps1'
$controlFile = Join-Path $gplbld $controlName
$controlLines = @(Get-StrippedLines -Path $controlFile -Kind hashblock)
$controlHit = @($controlLines | Where-Object { $_.Text -match $rx })
Check ('CONTROL: the stripper finds a known-live LOGTO SDSYS line (' + $controlName + ')') `
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

# THE SECOND PATTERN'S CONTROLS, and both directions matter.  The positive line is
# the exact one that hid two scripts (verify-apiadmin.ps1:178 and
# verify-privundetermined.ps1:373 before 21 Sep 2026); the negative is the ordinary
# call into a personal account, which is legitimate and must never be flagged.  A
# pattern that matched both, or neither, would score a clean scan of nothing.
Check 'CONTROL: the second pattern matches the shape that hid two scripts' `
      ("    return (Invoke-SDIn 'SDSYS' `$commands)" -match $rx2) 'Invoke-SDIn ''SDSYS'' was not matched'
Check 'CONTROL: the second pattern does NOT match a call into a personal account' `
      ("    `$out = Invoke-SDIn `$Prefix.ToUpper() @('RUN BP APIADMINPROBE')" -notmatch $rx2) 'a personal-account call was matched'

$found = [ordered]@{}
foreach ($f in ($scripts | Sort-Object Name)) {
    $stripped = @(Get-StrippedLines -Path $f.FullName -Kind hashblock)
    $hit = @($stripped | Where-Object { $_.Text -match $rx -or $_.Text -match $rx2 })
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
Write-Output ("*** RELEASE_1.1 76's DRIVER RE-AIM, CHECKED SCOPE: {0} file(s) still send a live LOGTO SDSYS prefix (or hand the literal SDSYS to Invoke-SDIn) that RELEASE_1.1 64 slices 1-2 refuse (10002). ***" -f $reaimCount)
Write-Output '    The re-aim is the seat (sdsys-seat.ps1).  A count of 0 means nothing is left to CONVERT; it'
Write-Output '    does NOT mean the converted scripts are witnessed - each needs one elevated run with SDSYS'
Write-Output '    signed in, and RELEASE_1.1 76 says which have had one.'

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
        Copy-Item -LiteralPath (Join-Path $gplbld $controlName) -Destination $tmp
        # Plant an UNDECLARED live occurrence: a file with the phrase and no
        # entry in $DECLARED must fail the partition check.
        Set-Content -LiteralPath (Join-Path $tmp 'zz-planted.ps1') -Value @(
            '# a planted, undeclared driver',
            "`$body = `"LOGTO SDSYS`""
        )
        # 21 Sep 26 - AND THE SHAPE THE FIRST PATTERN COULD NOT SEE: a planted call
        # that hands the literal SDSYS to Invoke-SDIn, with no LOGTO in it at all.
        Set-Content -LiteralPath (Join-Path $tmp 'zz-planted2.ps1') -Value @(
            '# a planted, undeclared indirect driver',
            "`$out = Invoke-SDIn 'SDSYS' @('WHO')"
        )
        $mutantSelf = (Join-Path $tmp (Split-Path -Leaf $PSCommandPath))
        Copy-Item -LiteralPath $PSCommandPath -Destination $mutantSelf
        $out = & powershell -NoProfile -ExecutionPolicy Bypass -File $mutantSelf --gplbld 2>&1
        $mutantExit = $LASTEXITCODE
        Check 'MUTANT: an undeclared planted driver is caught by name' `
              (($mutantExit -ne 0) -and ($out -match [regex]::Escape('zz-planted.ps1'))) `
              'the partition check did not name the planted file'
        Check 'MUTANT: an undeclared Invoke-SDIn ''SDSYS'' (no LOGTO in it) is caught by name' `
              (($mutantExit -ne 0) -and ($out -match [regex]::Escape('zz-planted2.ps1'))) `
              'the second pattern did not name the planted file'
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Write-Output ''
Write-Output ("test-logtoreaim-units: {0} passed, {1} failed." -f $pass, $fail)
exit $(if ($fail -gt 0) { 1 } else { 0 })
