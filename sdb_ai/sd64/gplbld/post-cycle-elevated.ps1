# post-cycle-elevated.ps1 - the ELEVATED verifiers, in one command
#
#   Run from an ELEVATED PowerShell.  Nothing else here needs elevation.
#
# WHY IT EXISTS.  19 Aug 2026: an agent shell cannot raise a UAC prompt -
# Start-Process -Verb RunAs returns "The operation was canceled by the user"
# without ever showing one, because a detached process has no desktop to
# display consent on.  So every elevated step has to be started by a human,
# and a handful of separate hand-run commands is exactly the shape cycle.ps1
# was written to get rid of (CLAUDE.md, "Do not hand-run the steps").
#
# It runs each verifier WITHOUT -Keep, so each removes what it made and the
# tree is left clean.  -Keep is the stronger run - it leaves the accounts to be
# read back independently - but it then owes a -Cleanup and one interactive
# DELETE.ACCOUNT per account it left, and verify-createaccount.ps1 already
# reads its account's directory back case-exactly before removing it.
#
# The summary is written to a file as well as the screen, because an elevated
# window does not paste its output back into the session that asked for it.
#
# ---------------------------------------------------------------------------
# ARGUMENTS ARE SPLATTED FROM A HASHTABLE, AND THE FIRST VERSION OF THIS FILE
# GOT IT WRONG IN A WAY THAT LOOKED LIKE AN SD BUG.  19 Aug 2026.  It held
# Args = @('-Prefix', $TierPrefix) and invoked "& $path @($s.Args)".
#
#   @(...) IS AN ARRAY SUBEXPRESSION, NOT SPLATTING.  Splatting is @name on a
#   VARIABLE.  So the whole array was passed as ONE positional argument and
#   stringified: verify-tiers.ps1 ran with $Prefix = "-Prefix sdtierg", and
#   tried to create SD accounts called "-Prefix sdtierg1".
#
#   AND ARRAY SPLATTING WOULD NOT HAVE FIXED IT EITHER.  "& $path @a" on an
#   array passes the elements POSITIONALLY - "-Prefix" binds to $Prefix as a
#   positional value, not as a parameter name, giving $Prefix = "-Prefix".
#   Only a HASHTABLE splat binds by name.  Measured, all three forms:
#       & $p @($a)               ->  Prefix = [-Prefix sdtierg]
#       & $p @a   (array)        ->  Prefix = [-Prefix]
#       & $p @h   (hashtable)    ->  Prefix = [sdtierg]      <- the correct one
#
# WHAT IT COST, and it is the reason this comment is long: verify-tiers.ps1
# reported all three tiers holding 429 VOC records with none of the 18
# capabilities withheld and all 10 administration verbs present - which reads
# exactly like the silent tier-filter failure PROJECT_STATUS.md 5.12 warns
# about, the one where a STANDARD account quietly gets the full VOC.  It was
# nothing of the sort.  CREATE.ACCOUNT had refused the malformed name, LOGTO
# had left the session in SDSYS, and 429 is simply how many records
# voc_template holds.  THE PARAMETER NAMES ARE VALIDATED BELOW so that a
# repeat stops here instead of three sections later wearing a disguise.

param(
    [string]$TierPrefix = 'sdtierg',   # MUST be one nobody has used - see PROJECT_STATUS.md
    [string]$Account    = 'sdacct14',  # likewise; sdacct1..13 are spent
    # 20 Aug 26 - verify-accountacl.ps1's throwaway account.  LOWER CASE ONLY,
    # unlike the two above: CREATEA downcases the user name and the directory
    # takes it verbatim, so a mixed-case prefix would name a directory the
    # sdu_ group derivation could not match.  Validated separately below.
    [string]$AclPrefix  = 'sdacl2',
    # 20 Aug 26 - verify-apiadmin.ps1's throwaway account.  Lower case only,
    # for the same reason as $AclPrefix, and validated with it below.
    [string]$ApiPrefix  = 'sdapia2',
    # 21 Aug 26 - verify-routes.ps1's three throwaway accounts, and
    # verify-accountrules.ps1's four.  Both derive Windows account names from
    # the prefix, so lower case only, validated with the two above.
    [string]$RoutePrefix = 'sdrt5',
    [string]$RulesPrefix = 'sdar1',
    # 21 Aug 26 - verify-delaccount.ps1's two throwaway accounts, <prefix>s and
    # <prefix>b.  Lower case only, same derivation as the two above.
    #
    # WIRED IN ON THE OWNER'S INSTRUCTION, 21 Aug 2026, AND THE REASON IS THE
    # ONE FAILURE THIS FILE CANNOT OTHERWISE CATCH.  It was the only verifier
    # left that had to be REMEMBERED: it is on assert-current's $neverShipped
    # list, so it never reports the tree stale, and nothing else reported its
    # absence either.  It went a whole phase without running, which is how
    # Phase 3's $adopt marker assertion reached the end of the plan unmeasured
    # (HISTORY, 21 Aug, "the verifier nobody runs").  A step that is only run
    # when somebody thinks of it is not in the suite.
    [string]$DelPrefix   = 'sddel5'
)

$ErrorActionPreference = 'Continue'

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'post-cycle-elevated: this needs an ELEVATED PowerShell.'
    exit 2
}

# An account name is an OS user name.  Anything with a space or a leading dash
# is a mangled argument, not a name - see the header.
foreach ($p in @(@{ N = 'TierPrefix'; V = $TierPrefix }, @{ N = 'Account'; V = $Account })) {
    if ($p.V -notmatch '^[A-Za-z][A-Za-z0-9_.]*$') {
        Write-Output ("post-cycle-elevated: -{0} is '{1}', which is not a usable account name." -f $p.N, $p.V)
        Write-Output '  Letters, digits, dot and underscore only, starting with a letter.'
        exit 2
    }
}

# STRICTER, AND NOT AN OVERSIGHT ABOVE.  verify-accountacl.ps1 derives the
# sdu_ group from the DIRECTORY name, which CREATEA writes downcased, so an
# upper-case prefix here would send it looking for a group that is not there.
if ($AclPrefix -notmatch '^[a-z][a-z0-9_]*$') {
    Write-Output ("post-cycle-elevated: -AclPrefix is '{0}'." -f $AclPrefix)
    Write-Output '  Lower case letters, digits and underscore only, starting with a letter.'
    exit 2
}
if ($ApiPrefix -notmatch '^[a-z][a-z0-9_]*$') {
    Write-Output ("post-cycle-elevated: -ApiPrefix is '{0}'." -f $ApiPrefix)
    Write-Output '  Lower case letters, digits and underscore only, starting with a letter.'
    exit 2
}
foreach ($p in @(@{ N = 'RoutePrefix'; V = $RoutePrefix }, @{ N = 'RulesPrefix'; V = $RulesPrefix },
                 @{ N = 'DelPrefix';   V = $DelPrefix })) {
    if ($p.V -notmatch '^[a-z][a-z0-9_]*$') {
        Write-Output ("post-cycle-elevated: -{0} is '{1}'." -f $p.N, $p.V)
        Write-Output '  Lower case letters, digits and underscore only, starting with a letter.'
        exit 2
    }
}

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$summary = Join-Path $logDir ('post-cycle-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.txt')

# Name => hashtable of parameters, splatted by NAME.  An empty hashtable means
# "no arguments", which splats correctly too.
$steps = @(
    @{ Name = 'verify-fold.ps1';          P = @{} },
    @{ Name = 'verify-createaccount.ps1'; P = @{ Account = $Account } },
    @{ Name = 'verify-tiers.ps1';         P = @{ Prefix  = $TierPrefix } },
    # 20 Aug 26 - section 8's per-account ACLs.  It is the only step that
    # deliberately breaks an ACL (icacls /reset) before putting it back.
    #
    # 21 Aug 26 - THIS COMMENT USED TO SAY "LAST, because ... a run that died
    # mid-way should not leave the steps after it measuring a directory in
    # that state", AND BOTH HALVES WERE WRONG.  It is not last - five steps
    # follow it - and it was not last when that was written either, since
    # peerlog and apiadmin already came after.  The reasoning did not
    # generalise: the ACL it breaks is on its OWN throwaway account directory,
    # user_accounts\<AclPrefix> (verify-accountacl.ps1:207), which no other
    # step reads, and the prefix is single-use so the next cycle will not meet
    # it either.  POSITION IS NOT LOAD-BEARING FOR THIS STEP.  It is for
    # verify-peerlog (overwrites the error log) and verify-apiadmin (restarts
    # SD twice), which is why those two are where they are and this one is
    # simply where it landed.
    @{ Name = 'verify-accountacl.ps1';    P = @{ Prefix  = $AclPrefix } },
    # 21 Aug 26 - the two route/rule verifiers, added when phase 4 rewrote the
    # first and wrote the second.  Both were run by hand until now, which is
    # exactly the shape this file exists to remove.
    #
    # BEFORE verify-peerlog.ps1, WHICH IS THE ORDERING THAT MATTERS.  That step
    # overwrites the SD error log with synthetic records, so anything that could
    # leave a diagnosis there has to have run already.  Both of these drive
    # CREATE.ACCOUNT and MODIFY.ACCOUNT, which are exactly the verbs that would.
    @{ Name = 'verify-routes.ps1';        P = @{ Prefix  = $RoutePrefix } },
    # AND THIS ONE PLACES THE ADOPT MARKER, briefly, to measure the gate.  It
    # removes it in a finally and again at the top of its own step 4, but a run
    # killed between those two points leaves the install-only gate open until
    # somebody deletes C:\ProgramData\SD\sdsys\$adopt by hand.
    @{ Name = 'verify-accountrules.ps1';  P = @{ Prefix  = $RulesPrefix } },
    # 21 Aug 26 - DELETE.ACCOUNT both directions, and the second step that
    # places the ADOPT marker, so the caveat above covers this one too.
    #
    # HERE, AND NOT LATER, FOR THE SAME REASON AS THE TWO ABOVE: it drives
    # CREATE.ACCOUNT, ADOPT and DELETE.ACCOUNT, so a failure leaves its
    # diagnosis in the SD error log that verify-peerlog.ps1 then overwrites.
    # It does not restart SD - its Start-SD returns early if sdwind is already
    # up - so it does not disturb the server the earlier steps measured.
    #
    # IT MAKES WINDOWS PROFILES AND DELETES THEM, which no other step does.
    # A run killed inside it can leave C:\Users\<prefix>s or <prefix>b and a
    # ProfileList entry behind; both subjects are named from -DelPrefix, so
    # the next cycle needs a fresh one either way.
    @{ Name = 'verify-delaccount.ps1';    P = @{ Prefix  = $DelPrefix } },
    # 20 Aug 26 - peer identification and the errlog trim.  AFTER EVERYTHING
    # ELSE, and for a blunter reason than the note above: it OVERWRITES the SD
    # error log with synthetic records, which is how the trim is made to fire
    # without opening a thousand connections.  Any step that failed earlier
    # leaves its diagnosis in that log, so this must not run before them.
    # It also restarts SD twice, so nothing after it would be talking to the
    # same server the earlier steps measured.
    @{ Name = 'verify-peerlog.ps1';       P = @{} },
    # 20 Aug 26 - THE API-PRIVILEGE VERIFIER, AND IT FAILS TODAY ON PURPOSE.
    # A remote API session runs as LocalSystem and can write $cred (measured;
    # PROJECT_STATUS.md's opening section).  Nothing is fixed yet, so this step
    # is expected to report 13/15 with the two verdict checks FAILING - that is
    # the finding standing, not the suite rotting.  When the fix lands it goes
    # green, which is the whole reason it is here rather than run by hand.
    #
    # LAST, because it creates and deletes a throwaway account and restarts SD
    # twice - the same reasoning as the two steps above it.
    @{ Name = 'verify-apiadmin.ps1';      P = @{ Prefix = $ApiPrefix } }
)

$lines = @()
foreach ($s in $steps) {
    $path = Join-Path $PSScriptRoot $s.Name
    $shown = ($s.P.GetEnumerator() | ForEach-Object { '-' + $_.Key + ' ' + $_.Value }) -join ' '
    Write-Output ''
    Write-Output ('===== ' + $s.Name + ' ' + $shown + ' =====')
    $splat = $s.P
    & $path @splat
    $code = $LASTEXITCODE
    $lines += ('{0,-28} {1,-22} exit {2}' -f $s.Name, $shown, $code)
}

Write-Output ''
Write-Output '===== post-cycle summary ====='
$lines | ForEach-Object { Write-Output $_ }
$lines | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ''
Write-Output ("summary written to: " + $summary)
