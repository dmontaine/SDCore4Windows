# VerifyInstall2.ps1 - the ELEVATED verifiers, in one command
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
# *** 22 Aug 26 - THE PARAGRAPH ABOVE IS NO LONGER TRUE ON THIS MACHINE, AND IT
# IS THE PREMISE THE WHOLE SPLIT RESTS ON. ***  Measured, twice, from an
# UNELEVATED agent shell:
#
#     Start-Process powershell -ArgumentList ... -Verb RunAs -Wait -PassThru
#
# returned exit 0, and the child reported "user=GITORLI\don elevated=True"
# while the parent reported elevated=False.  No "operation was canceled".  So
# an agent shell CAN get an elevated child here, and the reason this file must
# be started by a human has gone.
#
# WHAT IS NOT ESTABLISHED, and matters before anyone builds on it: WHY.  Either
# UAC on this machine is configured not to prompt for this account, or
# something changed since 19 Aug.  Those have very different consequences - the
# first is a local setting that another machine will not share, and the second
# would mean the 19 Aug observation was wrong or has been overtaken.  NOBODY HAS
# LOOKED.  Treat "an agent can elevate" as true HERE and unproven anywhere else,
# and do not delete the split until it is understood.
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
    # 22 Aug 26 - ONE TOKEN THAT DERIVES ALL THIRTEEN.  The eight verifiers that
    # were in neither runner were wired in on this date, which took the prefix
    # count from seven to thirteen.  Thirteen single-use names, invented by hand
    # and all distinct from every name spent since 13 Aug, is not a thing anybody
    # types correctly at the end of a cycle - and the failure mode is not a clean
    # refusal but a verifier three sections in, wearing a disguise, which is the
    # fault this file's header already records costing an install.
    #
    # So: -Run <token> derives every prefix below that was not given explicitly.
    # Use a token nobody has used - the check further down refuses one whose
    # accounts already exist, which is the half that actually protects you,
    # because A WINDOWS LOCAL USER SURVIVES AN UNINSTALL and a fresh install is
    # therefore NOT a fresh set of names.
    #
    #   VerifyInstall2.ps1 -Run b1
    #
    # Every individual prefix still overrides, so an interrupted cycle can re-run
    # one step with a fresh name without spending a whole new token.
    [string]$Run = '',

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
    [string]$DelPrefix   = 'sddel5',

    # 22 Aug 26 - THE SIX THAT WERE IN NEITHER RUNNER AND NEEDED A NAME.
    # verify-nonet and verify-osusers were wired in on the same date and take no
    # prefix at all, so they are not here.  Lower case only, all of them: each
    # derives Windows account names from the prefix, the same reason $AclPrefix
    # carries.
    [string]$CatPrefix   = '',   # verify-catgate.ps1   - one account
    [string]$SshPrefix   = '',   # verify-sshonly.ps1   - one account
    [string]$NamePrefix  = '',   # verify-apiname.ps1   - one account
    [string]$PortPrefix  = '',   # verify-apiport.ps1   - one account
    [string]$ScramPrefix = '',   # verify-scramlogin.ps1 - one account
    [string]$TierApiPrefix = '', # verify-tierapi.ps1   - one account per tier
    [string]$ApiIdPrefix = '',   # verify-apiidentity.ps1 - one account

    # 22 Aug 26 - Send each step's FULL output to its own file and show only a
    # progress line per step, plus every failing check, on the screen.  The file
    # is unfiltered; only the screen is selected.  See the loop for why that
    # distinction is load-bearing, and for what -Quiet costs.
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

# ---------------------------------------------------------------------------
# 22 Aug 26 - DERIVE FROM -Run.  Only fills what was not given explicitly, so
# an override always wins.  The stems are the ones each verifier's own history
# already used, so a -Run token reads like the names it produces.
if ($Run) {
    if ($Run -notmatch '^[a-z0-9]+$') {
        Write-Output ("VerifyInstall2: -Run is '{0}'." -f $Run)
        Write-Output '  Lower case letters and digits only - it becomes part of a Windows account name.'
        exit 2
    }
    if (-not $PSBoundParameters.ContainsKey('TierPrefix'))    { $TierPrefix    = "sdtiert$Run" }
    if (-not $PSBoundParameters.ContainsKey('Account'))       { $Account       = "sdacct$Run"  }
    if (-not $PSBoundParameters.ContainsKey('AclPrefix'))     { $AclPrefix     = "sdacl$Run"   }
    if (-not $PSBoundParameters.ContainsKey('ApiPrefix'))     { $ApiPrefix     = "sdapia$Run"  }
    if (-not $PSBoundParameters.ContainsKey('RoutePrefix'))   { $RoutePrefix   = "sdrt$Run"    }
    if (-not $PSBoundParameters.ContainsKey('RulesPrefix'))   { $RulesPrefix   = "sdar$Run"    }
    if (-not $PSBoundParameters.ContainsKey('DelPrefix'))     { $DelPrefix     = "sddel$Run"   }
    if (-not $CatPrefix)     { $CatPrefix     = "sdcatg$Run" }
    if (-not $SshPrefix)     { $SshPrefix     = "sdssh$Run"  }
    if (-not $NamePrefix)    { $NamePrefix    = "sdapin$Run" }
    if (-not $PortPrefix)    { $PortPrefix    = "sdapi$Run"  }
    if (-not $ScramPrefix)   { $ScramPrefix   = "sdscram$Run" }
    if (-not $TierApiPrefix) { $TierApiPrefix = "sdtapi$Run" }
    if (-not $ApiIdPrefix) { $ApiIdPrefix = "sdapiid$Run" }
}

# WITHOUT -Run THE SIX NEW ONES HAVE NO DEFAULT, and that is deliberate: the
# seven older parameters carry literal defaults from before this token existed,
# and those defaults are all SPENT names that would fail anyway.  Inventing
# fresh literals here would just add six more to that pile.
foreach ($p in @(@{ N = 'CatPrefix'; V = $CatPrefix }, @{ N = 'SshPrefix'; V = $SshPrefix },
                 @{ N = 'NamePrefix'; V = $NamePrefix }, @{ N = 'PortPrefix'; V = $PortPrefix },
                 @{ N = 'ScramPrefix'; V = $ScramPrefix }, @{ N = 'TierApiPrefix'; V = $TierApiPrefix })) {
    if (-not $p.V) {
        Write-Output ("VerifyInstall2: -{0} was not given and -Run was not either." -f $p.N)
        Write-Output '  Simplest: VerifyInstall2.ps1 -Run <token nobody has used>'
        exit 2
    }
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Output 'VerifyInstall2: this needs an ELEVATED PowerShell.'
    exit 2
}

# An account name is an OS user name.  Anything with a space or a leading dash
# is a mangled argument, not a name - see the header.
foreach ($p in @(@{ N = 'TierPrefix'; V = $TierPrefix }, @{ N = 'Account'; V = $Account })) {
    if ($p.V -notmatch '^[A-Za-z][A-Za-z0-9_.]*$') {
        Write-Output ("VerifyInstall2: -{0} is '{1}', which is not a usable account name." -f $p.N, $p.V)
        Write-Output '  Letters, digits, dot and underscore only, starting with a letter.'
        exit 2
    }
}

# STRICTER, AND NOT AN OVERSIGHT ABOVE.  verify-accountacl.ps1 derives the
# sdu_ group from the DIRECTORY name, which CREATEA writes downcased, so an
# upper-case prefix here would send it looking for a group that is not there.
if ($AclPrefix -notmatch '^[a-z][a-z0-9_]*$') {
    Write-Output ("VerifyInstall2: -AclPrefix is '{0}'." -f $AclPrefix)
    Write-Output '  Lower case letters, digits and underscore only, starting with a letter.'
    exit 2
}
if ($ApiPrefix -notmatch '^[a-z][a-z0-9_]*$') {
    Write-Output ("VerifyInstall2: -ApiPrefix is '{0}'." -f $ApiPrefix)
    Write-Output '  Lower case letters, digits and underscore only, starting with a letter.'
    exit 2
}
foreach ($p in @(@{ N = 'RoutePrefix'; V = $RoutePrefix }, @{ N = 'RulesPrefix'; V = $RulesPrefix },
                 @{ N = 'DelPrefix';   V = $DelPrefix },
                 # 22 Aug 26 - the six new ones, same rule and the same reason.
                 @{ N = 'CatPrefix';   V = $CatPrefix },  @{ N = 'SshPrefix';     V = $SshPrefix },
                 @{ N = 'NamePrefix';  V = $NamePrefix }, @{ N = 'PortPrefix';    V = $PortPrefix },
                 @{ N = 'ScramPrefix'; V = $ScramPrefix },@{ N = 'TierApiPrefix'; V = $TierApiPrefix })) {
    if ($p.V -notmatch '^[a-z][a-z0-9_]*$') {
        Write-Output ("VerifyInstall2: -{0} is '{1}'." -f $p.N, $p.V)
        Write-Output '  Lower case letters, digits and underscore only, starting with a letter.'
        exit 2
    }
}

# ---------------------------------------------------------------------------
# 22 Aug 26 - REFUSE A SPENT NAME BEFORE ANYTHING RUNS, not four verifiers in.
#
# A WINDOWS LOCAL USER SURVIVES AN UNINSTALL.  cycle.ps1 deletes both trees, so
# the SD side of a spent name goes - but the Windows account and its sdu_ group
# do not, and CREATE.ACCOUNT refuses a name whose Windows account already exists
# (message 10038).  A fresh install is therefore NOT a fresh set of names, which
# is exactly the assumption a tired reader makes at the end of a cycle.
#
# Each verifier does check its own name, but it checks it when it gets there:
# on 22 Aug the eight-step run would have gone six deep before a collision
# surfaced, and every account made before it would still need removing by hand.
# This asks all thirteen up front and names every clash at once.
$claimed = @()
foreach ($p in @(@{ N = 'TierPrefix'; V = $TierPrefix }, @{ N = 'Account';     V = $Account },
                 @{ N = 'AclPrefix';  V = $AclPrefix },  @{ N = 'ApiPrefix';   V = $ApiPrefix },
                 @{ N = 'RoutePrefix';V = $RoutePrefix },@{ N = 'RulesPrefix'; V = $RulesPrefix },
                 @{ N = 'DelPrefix';  V = $DelPrefix },  @{ N = 'CatPrefix';   V = $CatPrefix },
                 @{ N = 'SshPrefix';  V = $SshPrefix },  @{ N = 'NamePrefix';  V = $NamePrefix },
                 @{ N = 'PortPrefix'; V = $PortPrefix }, @{ N = 'ScramPrefix'; V = $ScramPrefix },
                 @{ N = 'TierApiPrefix'; V = $TierApiPrefix })) {
    # -Name "<p>*" catches the derived forms too: verify-routes makes <p>s and
    # <p>a, verify-delaccount <p>s and <p>b, verify-tiers <p>1..3.
    $u = @(Get-LocalUser  -Name ($p.V + '*')        -ErrorAction SilentlyContinue)
    $g = @(Get-LocalGroup -Name ('sdu_' + $p.V + '*') -ErrorAction SilentlyContinue)
    if ($u.Count -or $g.Count) {
        $claimed += ('  -{0,-14} {1,-12} already exists: {2}' -f $p.N, $p.V,
                     ((@($u | ForEach-Object Name) + @($g | ForEach-Object Name)) -join ', '))
    }
}
if ($claimed.Count -gt 0) {
    Write-Output 'VerifyInstall2: REFUSING - these names are already taken on this machine:'
    $claimed | ForEach-Object { Write-Output $_ }
    Write-Output ''
    Write-Output '  A Windows local user survives an uninstall, so a fresh install is not a'
    Write-Output '  fresh set of names.  Pick a -Run token nobody has used, or override the'
    Write-Output '  individual prefixes that clash.'
    exit 2
}

# ---------------------------------------------------------------------------
# 22 Aug 26 - IS SD ACTUALLY RUNNING?  assert-current DOES NOT ANSWER THIS, and
# the difference cost a run on the day this was written.
#
# WHAT HAPPENED.  The service had been stopped to clear a stale user table and
# was never started again.  verify-fold.ps1 called assert-current, which PASSED
# - it compares hashes and mtimes, so a stopped server is entirely current -
# printed "the installed tree matches source", and then died on its first SD
# command with "SD has not been started".  A green line immediately above a
# failure is the worst possible reading order.
#
# WHY IT IS WORTH A GUARD NOW AND WAS NOT BEFORE: this file had nine steps and
# has seventeen.  Every one of them would discover a stopped server separately,
# and the ones that create accounts would leave them behind on the way.
#
# IT REFUSES RATHER THAN STARTING IT.  Auto-starting would hide the state, and
# the state is diagnostic: a stopped SD after a cycle means either the cycle did
# not finish or something stopped it, and both are worth knowing before
# measuring anything.  cycle.ps1 owns starting SD; this file only measures.
$svc = Get-Service -Name 'SD' -ErrorAction SilentlyContinue
$sdwind = @(Get-Process -Name 'sdwind' -ErrorAction SilentlyContinue)
if ((-not $svc) -or ($svc.Status -ne 'Running') -or ($sdwind.Count -eq 0)) {
    Write-Output 'VerifyInstall2: REFUSING - SD is not running.'
    Write-Output ("  service: {0}    sdwind processes: {1}" -f
                  $(if ($svc) { $svc.Status } else { 'not installed' }), $sdwind.Count)
    Write-Output ''
    Write-Output '  assert-current would still pass: it compares hashes and mtimes, so a'
    Write-Output '  stopped server is perfectly "current".  Nothing here can measure one.'
    Write-Output ''
    Write-Output '      C:\Windows\System32\sc.exe start SD'
    Write-Output ''
    Write-Output '  If it was stopped to clear a stale user table, check C:\ProgramData\SD\shm'
    Write-Output '  is empty first - that is what proves the old table went.'
    exit 2
}

# BOTH ARE CHECKED, not just the service.  sdsvc.log records the service
# reporting RUNNING while it waits five seconds to see whether sdwind stays up,
# so the SCM's answer alone can be true while the daemon is already gone - the
# same gap cycle.ps1 step 1 waits on the process for.
#
# THE -join IS ON ITS OWN LINE DELIBERATELY.  Written inline as
#     "... {0} ... {1}" -f ($sdwind | ForEach-Object Id) -join ',', $Run
# it does not do what it reads as: -f and -join are the SAME PRECEDENCE and bind
# LEFT TO RIGHT, so PowerShell parses it as ("..." -f $ids) -join (',', $Run).
# -f then has one argument, {1} has nothing to fill it, and the whole line dies
# with "Index (zero based) must be greater than or equal to zero and less than
# the size of the argument list".  Measured 22 Aug 2026, on the first run after
# the guard above was added - non-fatal, but it printed a red block immediately
# before step 1, which is precisely where a reader is deciding whether to trust
# the run.
$sdwindPids = ($sdwind | ForEach-Object Id) -join ','
Write-Output ("VerifyInstall2: SD is running (sdwind {0}), -Run '{1}'" -f $sdwindPids, $Run)

$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$stamp   = Get-Date -Format 'yyyyMMdd-HHmmss'
$summary = Join-Path $logDir ('post-cycle-' + $stamp + '.txt')

# Name => hashtable of parameters, splatted by NAME.  An empty hashtable means
# "no arguments", which splats correctly too.
$steps = @(
    @{ Name = 'verify-fold.ps1';          P = @{} },
    # 22 Aug 26 - SDNet is gone and its neighbours are not.  FIRST BECAUSE IT IS
    # CHEAP AND STATIC: it creates no account, needs no prefix and reads the
    # installed tree, so if the tree is not what the cycle left it says so
    # before twelve throwaway accounts have been made.
    @{ Name = 'verify-nonet.ps1';         P = @{} },
    # 22 Aug 26 - check-install's [not yet] path, 13/13 on the 21:34:25 tree.
    # PLACED EARLY AND NEEDING NO PREFIX: it creates ONE Windows account under a
    # fixed name and removes it in the same run, so there is no prefix to spend
    # and nothing for a later step to collide with.  It also tests a SHIPPED
    # script rather than SD itself, and it found that script aborting with
    # "Access is denied" on the one token it exists to reassure - so it earns
    # its place ahead of the twelve throwaway accounts below.
    @{ Name = 'verify-notyet.ps1';        P = @{} },
    # 24 Aug 26 - section 7 step 9's guard, and it sits here for verify-notyet's
    # reason directly above: it spends NO PREFIX, creates no account and leaves
    # nothing behind but two ordinary sessions' worth of audit records, so it is
    # free to run ahead of the twelve throwaway accounts below.
    #
    # IT IS THE AUTOMATABLE HALF OF STEP 9 AND ONLY THAT HALF.  It proves LOGIN
    # computed a non-empty batch.command for a command line and an empty one for
    # an interactive session - the GATE'S INPUT.  It cannot prove the password
    # prompt was skipped; that needs an elevated session at a REAL console on an
    # account with no credential, which cannot be had non-interactively.  The
    # script's header and section 7 step 9 both say so.
    #
    # ELEVATED IS REQUIRED, WHICH IS WHY IT IS IN THIS RUNNER AND NOT THE OTHER:
    # the audit trail is locked to SYSTEM and Administrators, and an unelevated
    # "sd <command>" is refused unless the command is on the account batch.jobs
    # list.
    @{ Name = 'verify-cmdaudit.ps1';      P = @{} },
    @{ Name = 'verify-createaccount.ps1'; P = @{ Account = $Account } },
    @{ Name = 'verify-tiers.ps1';         P = @{ Prefix  = $TierPrefix } },
    # 22 Aug 26 - the global catalogue gate (UPSTREAM_FIXES 7).  It drives
    # CREATE.ACCOUNT, so it belongs BEFORE verify-peerlog for the error-log
    # reason the routes/rules comment below spells out.
    #
    # *** verify-osusers.ps1 WAS PUT HERE ON 22 Aug AND DOES NOT BELONG. ***
    # It REFUSES an elevated window - "CPROC admits K$ADMINISTRATOR whatever
    # OS.USERS says, so an elevated run is admitted by elevation and says
    # nothing about the list" (verify-osusers.ps1:243) - so it exited 2 without
    # measuring anything.  It is in VerifyInstall1.ps1 now, beside
    # verify-credacl, which refuses elevation for the same class of reason: a
    # test that passes because of the token is worse than one nobody runs.
    #
    # HOW IT GOT HERE, because the mistake is repeatable: the file was
    # classified by grepping for WindowsBuiltInRole, which it does mention -
    # in a gate that refuses rather than requires.  Grep found the role and
    # assumed the sign.  Read the branch, not the symbol.
    @{ Name = 'verify-catgate.ps1';       P = @{ Account = $CatPrefix } },
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
    # 22 Aug 26 - the ssh-only account model (section 5.6.2).  LAST OF THE
    # ACCOUNT STEPS and still before verify-peerlog, same error-log reason.
    #
    # IT IS THE ONE STEP THAT DOES NOT CALL assert-current, and that is
    # deliberate rather than an omission - CLAUDE.md exempts it and
    # verify-allowgroups because they test WINDOWS behaviour rather than SD's.
    # So it proves nothing about whether the tree is current; the steps around
    # it do that.
    #
    # IT DOES A REAL ssh LOGIN, so it is the slowest step here and the only one
    # that can fail for a reason outside SD entirely - sshd not running, a host
    # key prompt, a firewall.  Read a failure here against verify-routes'
    # sshd_config checks before suspecting SD.
    @{ Name = 'verify-sshonly.ps1';       P = @{ Account = $SshPrefix } },
    # 20 Aug 26 - peer identification and the errlog trim.  AFTER EVERYTHING
    # ELSE, and for a blunter reason than the note above: it OVERWRITES the SD
    # error log with synthetic records, which is how the trim is made to fire
    # without opening a thousand connections.  Any step that failed earlier
    # leaves its diagnosis in that log, so this must not run before them.
    # It also restarts SD twice, so nothing after it would be talking to the
    # same server the earlier steps measured.
    @{ Name = 'verify-peerlog.ps1';       P = @{} },
    # 20 Aug 26 - THE API-PRIVILEGE VERIFIER.
    #
    # *** 22 Aug 26 - THIS COMMENT SAID IT "FAILS TODAY ON PURPOSE" AND WAS
    # EXPECTED TO REPORT "13/15 with the two verdict checks FAILING". BOTH
    # HALVES ARE NOW WRONG. *** The containment gate landed on 21 Aug
    # (op_dio2.c, and the USR_ADMIN fix in kernel.c), so on the 22 Aug 08:32:03
    # install it reports 22/23 with BOTH verdict checks PASSING - the API
    # session can neither open nor write $cred - and the 23rd a standing N/A
    # (the whoami probe cannot run, because OS.EXECUTE is refused, which is
    # itself the right answer).  What is NOT fixed is the session's TOKEN, which
    # is still LocalSystem; that is PROJECT_STATUS.md's opening section and it
    # is not what this step measures.  A FAILURE HERE IS NOW A REGRESSION.
    #
    # FIRST OF THE API STEPS, all of which come after verify-peerlog: each
    # edits APIPORT in the installed sd.conf and restarts SD, so none of them
    # is talking to the server the earlier steps measured, and all of them
    # write API connection records to the error log peerlog has finished with.
    @{ Name = 'verify-apiadmin.ps1';      P = @{ Prefix = $ApiPrefix } },
    # 22 Aug 26 - !valid_os_name on the API login path, and the audit trail.
    # SECOND of the API steps and deliberately before the three that rewrite
    # sd.conf: it is the only one that does NOT touch the file, so it measures
    # the port in the state the install ships it (APIPORT=4243, active since
    # Phase 1).  It writes refusal records to the audit file on purpose.
    @{ Name = 'verify-apiname.ps1';       P = @{ Prefix = $NamePrefix } },
    # 22 Aug 26 - the two API gates answering DIFFERENTLY: a wrong password
    # refused by !CRED_VERIFY, and SDSYS refused by the ACC$GROUP test.  That
    # pair is what makes the admitted case mean anything, and no other verifier
    # makes it - verify-apiadmin measures containment, not the gates.
    @{ Name = 'verify-apiport.ps1';       P = @{ Prefix = $PortPrefix } },
    # 22 Aug 26 - the SCRAM exchange spoken directly at the port, against the
    # RFC rather than against sdclilib: replay refused, client-final with no
    # client-first refused, two exchanges get different nonces, the password
    # never appears in the bytes, and request 24 (cleartext) REFUSED.
    @{ Name = 'verify-scramlogin.ps1';    P = @{ Prefix = $ScramPrefix } },
    # 23 Aug 26 - section 7 step 14, shape (b): an API session must be CONFINED
    # to what the user may read, not merely logged in as them.  It opens two
    # fixtures over a live API session - one the user may read, one ACL'd like
    # sdsys\$cred - and the second must be refused.  AFTER verify-scramlogin,
    # because it needs the SCRAM login to work before its answer means anything;
    # a failure here with scramlogin green is the identity change, not the login.
    @{ Name = 'verify-apiidentity.ps1';   P = @{ Prefix = $ApiIdPrefix } },
    # 22 Aug 26 - all three tiers reachable over the API, and one that should
    # not be reachable refused.  LAST because it is the only step that needs a
    # binary from OUTSIDE this repository - sd-connect.exe from the sdclilib32
    # tree (its -SdConnect default).  If that tree is absent this step is the
    # one that fails, and nothing before it is lost.
    @{ Name = 'verify-tierapi.ps1';       P = @{ Prefix = $TierApiPrefix } }
)

# ---------------------------------------------------------------------------
# 22 Aug 26 - -Quiet: FULL OUTPUT TO A FILE PER STEP, PROGRESS AND FAILURES ON
# THE SCREEN.  Seventeen verbose steps is several thousand lines, and the
# console scrollback is not where any of it should be read from anyway.
#
# THE FILE IS NEVER FILTERED, and that is the whole design.  §8 of
# PROJECT_STATUS.md records the intermittent 138/142 being LOST TWICE because
# "the run went through Select-String, so Start-Transcript recorded the command
# and not the answers".  So the per-step file gets EVERYTHING - all six streams,
# via *> - and only what is echoed to the SCREEN is selected.  A filter that
# can lose evidence must never be the only copy.
#
# WHAT -Quiet COSTS, and it is worth knowing before using it: several verifiers
# call Start-Transcript themselves, and a transcript records what reaches the
# HOST.  Under -Quiet their output goes to a file instead, so THEIR OWN
# transcripts will be thin or empty.  Nothing is lost - the runner's per-step
# file is the fuller record - but do not go looking in the verifier's own
# transcript afterwards and conclude the step printed nothing.
#
# IT IS OPT-IN, NOT THE DEFAULT.  Changing what a suite prints in the middle of
# an investigation is how evidence goes missing, and today has already cost
# three runs to changes made around this file rather than in it.
$lines  = @()
$failed = 0
$i      = 0
foreach ($s in $steps) {
    $i++
    $path = Join-Path $PSScriptRoot $s.Name
    $shown = ($s.P.GetEnumerator() | ForEach-Object { '-' + $_.Key + ' ' + $_.Value }) -join ' '
    $splat = $s.P
    $short = $s.Name -replace '\.ps1$', ''

    if (-not $Quiet) {
        Write-Output ''
        Write-Output ('===== ' + $s.Name + ' ' + $shown + ' =====')
        & $path @splat
        $code = $LASTEXITCODE
        $lines += ('{0,-28} {1,-22} exit {2}' -f $s.Name, $shown, $code)
        if ($code -ne 0) { $failed++ }
        continue
    }

    $stepLog = Join-Path $logDir ('{0}-{1:d2}-{2}.log' -f $stamp, $i, $short)
    Write-Host ('[{0,2}/{1}] {2,-22} {3,-24}' -f $i, $steps.Count, $short, $shown) -NoNewline

    # *> captures ALL streams - output, error, warning, verbose, debug and
    # information.  Write-Host goes to the INFORMATION stream in PowerShell 5+,
    # which is why it is caught here and would not have been in 2.0.
    & $path @splat *> $stepLog
    $code = $LASTEXITCODE

    # Surfaced from the file, never from a pipe the file did not also get.
    # '[FAIL]' is the marker most verifiers use per check; the summary tables
    # also end rows with FAIL, but those are the same checks counted twice, so
    # only the marker is surfaced and the count points at the file.
    $fails = @()
    if (Test-Path -LiteralPath $stepLog) {
        # 22 Aug 26 - THE PATTERN IS THE LITERAL MARKER, NOT A REGEX FOR IT.
        # -SimpleMatch takes the pattern LITERALLY, so '\[FAIL\]' looked for
        # eight characters INCLUDING THE BACKSLASHES and no verifier has ever
        # written those.  It matched nothing, every run, since the day -Quiet
        # was added: the b2 run reported "FAILED  exit 1, 0 failing check(s)"
        # for verify-sshonly while its own step file held five [FAIL] lines.
        #
        # Measured three ways on that file rather than reasoned about:
        #   -SimpleMatch '\[FAIL\]'  ->  0     (what this line used to be)
        #   '\[FAIL\]' as a regex    ->  5
        #   -SimpleMatch '[FAIL]'    ->  5     (this line now)
        #
        # Either of the last two is correct; the literal is kept because a
        # SIMPLE match on a FIXED marker is what was meant, and it cannot be
        # broken again by regex metacharacters in a marker somebody changes.
        $fails = @(Select-String -LiteralPath $stepLog -Pattern '[FAIL]' -SimpleMatch -ErrorAction SilentlyContinue)
    }

    if ($code -eq 0 -and $fails.Count -eq 0) {
        Write-Host ' OK' -ForegroundColor Green
    } else {
        $failed++
        Write-Host (' FAILED  exit {0}, {1} failing check(s)' -f $code, $fails.Count) -ForegroundColor Red
        $fails | Select-Object -First 15 | ForEach-Object {
            Write-Host ('         ' + $_.Line.Trim()) -ForegroundColor Red
        }
        if ($fails.Count -gt 15) {
            Write-Host ('         ... and {0} more, all in the file below' -f ($fails.Count - 15)) -ForegroundColor Red
        }
        # A step can exit non-zero with no [FAIL] marker at all - it refused to
        # start, or died.  Then the last few lines are the only clue there is.
        if ($fails.Count -eq 0) {
            Get-Content -LiteralPath $stepLog -Tail 8 -ErrorAction SilentlyContinue |
                ForEach-Object { Write-Host ('         ' + $_) -ForegroundColor DarkYellow }
        }
        Write-Host ('         full output: ' + $stepLog) -ForegroundColor Yellow
    }
    $lines += ('{0,-28} {1,-22} exit {2}  {3}' -f $s.Name, $shown, $code, $stepLog)
}

Write-Output ''
Write-Output '===== post-cycle summary ====='
$lines | ForEach-Object { Write-Output $_ }
$lines | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ''
Write-Output ("summary written to: " + $summary)
if ($Quiet) {
    Write-Output ("per-step output:    " + (Join-Path $logDir ($stamp + '-NN-verify-*.log')))
}
if ($failed -gt 0) {
    Write-Output ("VerifyInstall2: {0} of {1} step(s) did not exit 0." -f $failed, $steps.Count)
    exit 1
}
Write-Output ("VerifyInstall2: all {0} steps exited 0." -f $steps.Count)
