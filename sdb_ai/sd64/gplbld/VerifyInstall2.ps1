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
    # 21 Aug 26 - verify-delaccount.ps1's throwaway accounts, <prefix>s and
    # <prefix>b.  Lower case only, same derivation as the two above.
    # 30 Aug 26 - THREE NOW: <prefix>h joins them, PRE_RELEASE_FIXES.md 65.
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
    # 29 Aug 26 - verify-sdsysgate.ps1, PRE_RELEASE 62.  One throwaway
    # non-administrator account, created and removed inside the step.  Lower
    # case only, same derivation as the rest: it becomes a Windows account name.
    [string]$GatePrefix  = '',   # verify-sdsysgate.ps1 - one account
    # 02 Sep 26 - verify-vocverbs.ps1, PRE_RELEASE_FIXES 112, owner's ruling.
    # It was in NEITHER runner, so the checks it carries for entries 5, 13, 14
    # and 15 had never fired since the day it was written - the same shape as
    # verify-profiledir below, and as 82 and 107.
    #
    # NO ACCOUNT: unlike every other prefix here it names FILES in SDSYS, not
    # Windows accounts, so it carries no lower-case-only constraint of its own.
    # It is still derived from -Run, because a fixed prefix passes once and
    # fails every run after (54).
    [string]$VocPrefix   = '',   # verify-vocverbs.ps1  - files, no account
    # 30 Aug 26 - verify-profiledir.ps1, PRE_RELEASE_FIXES 54.  It was in
    # NEITHER runner, so 36's last leg had never fired since the day it was
    # written.  VerifyInstall2 is the right runner and VerifyInstall1 is not,
    # and its cost is lower than verify-doors-suite, already a suite step: one
    # control account, created and deleted, and it never logs in - so it leaves
    # no profile directory, which is the thing that makes the doors fixture
    # single-use and expensive.
    [string]$ProfPrefix  = '',   # verify-profiledir.ps1 - one account
    # 31 Aug 26 - verify-tierchange.ps1, PRE_RELEASE_FIXES 107, on the owner's
    # ruling.  SAME STORY AS $ProfPrefix DIRECTLY ABOVE and found the same way:
    # it was in NEITHER runner, so the three rows of PRE_RELEASE 19 it covers
    # had never fired since the day it was written.
    #
    # THIS USED TO ADD "and because it RAISES verify-acctmsgs.ps1 and
    # verify-vocverbs.ps1, three verifiers went unrun together rather than
    # one."  ***THAT WAS FALSE - IT RAISES NEITHER, AND BOTH ARE STILL RUN BY
    # NOTHING.***  Corrected 1 Sep 2026, PRE_RELEASE_FIXES 112; the measurement
    # is in the longer note beside the step itself, below.
    #
    # THIS RUNNER AND NOT THE OTHER: its own header says the middle three rows
    # need "an elevated piped session", and it takes a -Prefix for a throwaway
    # account.  Lower case only, like the prefixes above, because CREATEA
    # downcases the name and the directory takes it verbatim.
    [string]$TcPrefix    = '',   # verify-tierchange.ps1 - one account
    # 04 Sep 26 - verify-privundetermined.ps1, PRE_RELEASE_FIXES 96's witness.
    # One throwaway PROGRAMMER account reached over the API, because a socket
    # session is the only one on this machine that does NOT get USR_ADMIN and so
    # is the only one whose OS.EXECUTE decision reaches the os.users record at
    # all (kernel.c:253).  Lower case only, same derivation as the rest: it
    # becomes a Windows account name AND the name of the record the run writes
    # into sdsys\os.users, which op_sh.c looks up verbatim.
    [string]$PrivPrefix  = '',   # verify-privundetermined.ps1 - one account

    # 22 Aug 26 - Send each step's FULL output to its own file and show only a
    # progress line per step, plus every failing check, on the screen.  The file
    # is unfiltered; only the screen is selected.  See the loop for why that
    # distinction is load-bearing, and for what -Quiet costs.
    # 30 Aug 26 - RUN ONLY THE NAMED STEP(S).  Owner's ruling, 30 Aug 2026:
    # "add -Only, and drop the full run to milestones".  The elevated half is
    # 15 of the suite's ~20 minutes, and the one step that decides a change is
    # usually 30 to 90 seconds of it.
    #
    #     VerifyInstall2.ps1 -Run b76 -Only verify-delaccount
    #     VerifyInstall2.ps1 -Run b76 -Only verify-tiers,verify-tierapi
    #
    # Comma or semicolon separated, with or without .ps1, case-insensitive.
    # The filter is shared with VerifyInstall1 (suite-only.ps1); its header
    # records why it is one file and what it refuses.
    #
    # ***-Run IS STILL REQUIRED AND STILL DERIVES EVERY PREFIX.***  That is the
    # whole reason to run a single step THROUGH the runner rather than by hand:
    # a fixed prefix passes once and fails every later run, which reads like a
    # product fault (PRE_RELEASE 54).
    #
    # ***A PARTIAL RUN SAYS SO WHEREVER IT REPORTS***, and the closing line never
    # reads "all N steps exited 0" on one.
    #
    # 31 Aug 26 - [string[]] SO BOTH SHELL FORMS BIND, the same change and the
    # same reason as VerifyInstall1.ps1, which carries the full write-up:
    # PowerShell parses "a,b" in argument position as an ARRAY before binding,
    # so as [string] this refused the documented multi-name form with "Cannot
    # process argument transformation on parameter 'Only'".  Changed here in the
    # same commit BECAUSE THE TWO RUNNERS MUST NOT DISAGREE ABOUT HOW A
    # DOCUMENTED FLAG IS TYPED - a form that works on one and not the other is
    # worse than one that works on neither, since it teaches the wrong habit.
    # The filter is untouched: the array is joined at the call site and
    # suite-only.ps1 still splits a string on [,;].
    [string[]]$Only = @(),

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
    if (-not $GatePrefix)  { $GatePrefix  = "sdgate$Run" }
    # 02 Sep 26 - PRE_RELEASE_FIXES 112.  Derived from -Run like the rest: a
    # FIXED prefix passes once and fails every later run, which is 54's lesson
    # and the reason to go through the runner rather than call the verifier by
    # hand.  verify-vocverbs makes files, not accounts, so this is shorter than
    # the account prefixes and needs no Windows-name constraint.
    if (-not $VocPrefix)   { $VocPrefix   = "sdvv$Run" }
    # THE PREFIX MUST COME FROM THE -Run TOKEN, as sdacctb48/sdtiertb48 already
    # do and as 54 says in as many words.  verify-profiledir.ps1 refuses a spent
    # stem by design, so a FIXED prefix would pass once and fail on every later
    # run on the same machine - which reads like a product fault and is not one.
    if (-not $ProfPrefix)  { $ProfPrefix  = "sdprof$Run" }
    # 31 Aug 26 - and verify-tierchange.ps1's, for the reason directly above:
    # it creates a throwaway account, so a FIXED prefix would pass once and
    # collide on every later run on the same machine.
    if (-not $TcPrefix)    { $TcPrefix    = "sdtc$Run" }
    # 04 Sep 26 - PRE_RELEASE 96's verifier.  Derived from -Run for 54's reason,
    # and with one of its own: the run WRITES a record named after this prefix
    # into sdsys\os.users, and refuses to start if one is already there.  A
    # fixed prefix would therefore not merely collide on the account, it would
    # refuse on litter from its own last run.
    if (-not $PrivPrefix)  { $PrivPrefix  = "sdpw$Run" }
}

# WITHOUT -Run THE SIX NEW ONES HAVE NO DEFAULT, and that is deliberate: the
# seven older parameters carry literal defaults from before this token existed,
# and those defaults are all SPENT names that would fail anyway.  Inventing
# fresh literals here would just add six more to that pile.
foreach ($p in @(@{ N = 'CatPrefix'; V = $CatPrefix }, @{ N = 'SshPrefix'; V = $SshPrefix },
                 @{ N = 'NamePrefix'; V = $NamePrefix }, @{ N = 'PortPrefix'; V = $PortPrefix },
                 @{ N = 'ScramPrefix'; V = $ScramPrefix }, @{ N = 'TierApiPrefix'; V = $TierApiPrefix },
                 # 31 Aug 26 - verify-tierchange.ps1's, added with the step.
                 # It is listed HERE and not only above because a prefix that
                 # is empty at this point reaches CREATE.ACCOUNT as a bare
                 # "sd" name; refusing by name costs nothing and the step
                 # cannot then fail several minutes later looking like a
                 # product fault.
                 @{ N = 'TcPrefix'; V = $TcPrefix })) {
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
    # <p>a, verify-delaccount <p>s, <p>b and <p>h, verify-tiers <p>1..3.
    #
    # 30 Aug 26 - <p>h is the third one, PRE_RELEASE_FIXES.md 65 and 36.  It is
    # the subject whose profile is pinned open, so DELETE.ACCOUNT reaches
    # DELETE_USER's keep-both arm - and it therefore LEAVES C:\Users\<p>h and a
    # ProfileList entry on purpose.  The wildcard already covered it; naming it
    # here is so the next reader of a "<p>h already exists" refusal knows which
    # verifier to look at.
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
    # 31 Aug 26 - PRE_RELEASE_FIXES 107, on the owner's ruling.  DIRECTLY AFTER
    # verify-tiers BECAUSE IT IS THE REST OF THE SAME QUESTION: PRE_RELEASE 19
    # lists seven things the tier change needs proved, verify-tiers section 6
    # covers four and SAYS IN ITS OWN OUTPUT that it does not cover the rest.
    # This is the middle three - the required access keyword, what leaves with
    # ADMINISTRATOR, and the "left alone" count.  (The three DOORS are still
    # covered by neither; they need an unelevated session, an ssh login and an
    # API pair, which is PRE_RELEASE 38.)
    #
    # IT WAS IN NEITHER RUNNER UNTIL TODAY, found by re-deriving
    # VerifyInstall1's header counts from the directory rather than adjusting
    # them by one - the check that file's header demands after the same
    # invariant broke on 24 Aug 2026.
    #
    # ***IT IS THE PARENT OF NOTHING, AND THIS COMMENT USED TO SAY IT WAS THE
    # PARENT OF TWO.  WIRING IT IN PUT ONE VERIFIER BACK, NOT THREE.***
    # Corrected 1 Sep 2026, PRE_RELEASE_FIXES 112.  The claim was that it
    # "raises verify-acctmsgs.ps1 and verify-vocverbs.ps1".  Measured rather
    # than re-read: verify-tierchange.ps1 names those two ONLY in comments
    # (:94, :120), and the one external script it actually invokes is
    # assert-current.ps1 (:261).
    #
    # ***SO BOTH OF THEM ARE STILL RUN BY NOTHING***: neither appears as a
    # Name = '...' step in EITHER runner.  Their only other mentions are
    # assert-current.ps1's roster, which checks that they exist rather than
    # running them, and test-acctmsgs-units / test-vocverbs-units, which lift
    # functions out of them without driving an install.
    #
    # THE COST OF THE OLD WORDING IS ON THE RECORD: -Only verify-tierchange was
    # handed over as PRE_RELEASE 100's deciding step BECAUSE of this comment,
    # ran green at 28 of 28, and drove no index at all.  A comment naming what
    # a step covers gets read as evidence, and nobody re-derives a signpost.
    @{ Name = 'verify-tierchange.ps1';    P = @{ Prefix  = $TcPrefix } },
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
    # 29 Aug 26 - PRE_RELEASE 62's verifier, and it is in THIS runner rather
    # than the other for verify-cmdaudit's reason exactly: the decisive reading
    # is the AUDIT REASON, and the trail is locked to SYSTEM and Administrators.
    #
    # ***sysmsg 10002 IS NOT A USABLE ANCHOR HERE AND THAT IS WHY THE STEP
    # EXISTS AT ALL.***  CPROC prints it on BOTH refusal paths - the identity
    # gate at :2637 and the failed elevation at :2651 - and the session is
    # reached over ssh, which has no desktop, so elevate('START') would fail
    # there anyway.  A check anchored on 10002 would pass with the gate DELETED.
    # Only 'reason=not an administrator' in the audit tells them apart.
    #
    # It makes and removes its own account: VerifyInstall1's test account
    # belongs to the unelevated half and is gone before this runner starts.
    @{ Name = 'verify-sdsysgate.ps1';     P = @{ Prefix  = $GatePrefix } },
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
    # 30 Aug 26 - PRE_RELEASE_FIXES 54.  Placed after verify-delaccount because
    # both make and remove one account, so a failure here reads next to the
    # other account-lifecycle rows rather than among the ACL ones.
    @{ Name = 'verify-profiledir.ps1';    P = @{ Prefix  = $ProfPrefix } },
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
    # 04 Sep 26 - PRE_RELEASE_FIXES 96's witness, and the thing it measures has
    # never been executed by anything: the tri-state was BUILT on 3 Sep, the
    # suite went green on b108 with ZERO undetermined lines in errlog, and a
    # zero is what a green run looks like whether the logging works or has never
    # been reached.  This makes it non-zero on purpose, three times, and then
    # requires it back to zero on a check that COMPLETED.
    #
    # IMMEDIATELY AFTER verify-apiadmin AND FOR ITS REASONS, NOT BY HABIT.  It
    # is an API step, so it belongs with them: it edits APIPORT in the installed
    # sd.conf and restarts SD, and it writes connection records to the error log
    # that verify-peerlog has finished with.  Running it before peerlog would
    # break peerlog's arithmetic, which is the ordering constraint that put the
    # API block here in the first place.
    #
    # AND IT SHARES verify-apiadmin's FIXTURE SHAPE DELIBERATELY - same probe
    # (apiosexecprobe.sb), same throwaway PROGRAMMER tier, same make target -
    # so the two read as one pair: apiadmin asks whether OS.EXECUTE is CONTAINED
    # for a remote session, this one asks whether the refusal can SAY WHY.
    #
    # IT WRITES ONE RECORD INTO sdsys\os.users AND REMOVES IT.  That is the one
    # piece of shared state it touches, it is named after its own -Prefix, and
    # it refuses to start if a record of that name is already there rather than
    # overwriting somebody's decision on the list that grants shells.
    @{ Name = 'verify-privundetermined.ps1'; P = @{ Prefix = $PrivPrefix } },
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
    # 02 Sep 26 - PRE_RELEASE_FIXES 112, owner's ruling: "add verifiers to
    # VerifyInstall2".  It was in NEITHER runner, so its checks for entries 5,
    # 13, 14 and 15 have never run since the day it was written.
    #
    # HERE RATHER THAN LAST, because verify-tierapi below is last for a stated
    # reason - it is the only step needing a binary from outside this
    # repository - and taking that place would cost that reason.
    #
    # LATE RATHER THAN EARLY, because it is the one step that creates and
    # deletes FILES IN SDSYS.  Nothing after it counts SDSYS state, so its churn
    # cannot perturb another step's arithmetic.  Checked rather than assumed:
    # verify-tiers' COUNT VOC rows are taken after LOGTO <tier account>, so they
    # count the ACCOUNT's VOC and not SDSYS's, and this could in fact have gone
    # anywhere - the placement is belt to that braces.
    #
    # IT CLEANS UP AFTER ITSELF AND PROVES IT: its section 9 deletes both
    # fixtures and then asserts sdsys\messages survived the run, so a cleanup
    # that took too much would show as a red row rather than as a puzzle later.
    #
    # WHAT IT DOES NOT COVER, SO NOBODY READS MORE INTO A GREEN THAN IS THERE:
    # the AK write path.  Its fixture indexes a file whose DATA part is empty
    # and uses CREATE.INDEX, which defines an index without building one, so
    # get_ak_node is called zero times.  probe-akwrite.ps1 in VerifyInstall1 is
    # what covers that.
    @{ Name = 'verify-vocverbs.ps1';      P = @{ Prefix = $VocPrefix } },
    # 22 Aug 26 - all three tiers reachable over the API, and one that should
    # not be reachable refused.
    #
    # 04 Sep 26 - THE REASON IT WAS PUT LAST IS GONE, AND THE ORDER STAYS.
    # PRE_RELEASE_FIXES 161.  This used to be "the only step that needs a binary
    # from OUTSIDE this repository - sd-connect.exe from the sdclilib32 tree",
    # placed last so that its absence cost nothing before it.  "make sd" now
    # builds sd-connect.exe into bin\client32, so nothing here reaches outside
    # the tree.  ***AND "THE ONLY STEP" WAS WRONG WHEN IT WAS WRITTEN***:
    # verify-doors.ps1 carried the same default, and it SKIPS its API door
    # rather than refusing - so on b116, with the tree deleted, this step
    # exited 2 while doors passed with a door untested.  Last is still a fine
    # place for it; it is no longer a mitigation for anything.
    @{ Name = 'verify-tierapi.ps1';       P = @{ Prefix = $TierApiPrefix } },

    # 03 Sep 26 - LAST, AND IT HAS TO BE LAST.  PRE_RELEASE 93 and 65, owner's
    # instruction after the b107 witness.  It measures the residue THIS run
    # leaves, restarts the SD service so reconcile-accounts.ps1 sweeps it, and
    # checks the right records went and the valid ones stayed.
    #
    # ***IT IS NOT verify-register RUN AGAIN, AND IT CANNOT BE.***
    # verify-tierapi above leaves its register records behind ON PURPOSE, so a
    # plain verify-register placed here would find them and go red on EVERY
    # run - and a permanently red guard is what teaches people to ignore
    # guards.  The owner ruled sweep-then-verify; the file's header has the
    # reasoning and the five things it proves that neither half proves alone.
    #
    # verify-register in VerifyInstall1 stays where it is: running FIRST, it
    # catches what a PREVIOUS run left uncleaned, which is the b100 state (14
    # dead records in 15).  This one catches residue seconds old.  They are
    # different questions and both are worth asking.
    #
    # NO PREFIX AND NO ACCOUNT: it creates nothing.  It DOES restart SD, which
    # this runner already does more than once.
    @{ Name = 'verify-registersweep.ps1'; P = @{} }
)

# 30 Aug 26 - -Only.  Shared filter, see suite-only.ps1.  It runs AFTER the
# whole list is built, so a name is checked against the steps this run would
# actually have made.
. (Join-Path $PSScriptRoot 'suite-only.ps1')
$sel = Select-SuiteSteps -Steps $steps -Only ($Only -join ',') -Runner 'VerifyInstall2'
if ($sel.Error -ne '') { Write-Output $sel.Error; exit 2 }
$partial   = $sel.Partial
$fullCount = @($steps).Count
$steps     = @($sel.Steps)
if ($partial) {
    Write-Output ''
    Write-Output ('***** PARTIAL RUN - {0} of {1} step(s), because -Only was given *****' -f
                  @($steps).Count, $fullCount)
    Write-Output ('      ' + (($steps | ForEach-Object { $_.Name }) -join ', '))
    Write-Output '      This run says NOTHING about the steps it did not run.'
}

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
# 28 Aug 26 - CLOSE WHAT A STEP LEFT OPEN, AND SAY SO.  PRE_RELEASE 40.
#
# A verifier that calls Start-Transcript and exits without stopping it leaves it
# open ON THIS PROCESS - the steps run in the runner's own session - so it goes
# on recording every verifier that follows.  Measured 27 Aug 2026:
# verify-sshonly-20260827-232336.log carried verify-apiadmin's two [FAIL] rows
# and the whole suite's summary from six verifiers later, and a wrong
# per-verifier count was issued and withdrawn on exactly that.
#
# ***FIXED HERE RATHER THAN IN FIFTEEN VERIFIERS, ON PURPOSE.***  The entry
# proposed a try/finally around each verifier's body; this is one place, it
# cannot be forgotten by the next verifier somebody writes, and it also covers
# the case a try/finally does not - a step that dies outright.
#
# ***THIS RUNNER HAS NO TRANSCRIPT OF ITS OWN***, so every one closed here is a
# leak and there is nothing to restore.  (VerifyInstall1 does have one, and its
# copy of this restores it with -Append.)  Checked, not assumed: the only two
# mentions of Start-Transcript in this file are in the comment above.
#
# AND IT REPORTS RATHER THAN TIDYING SILENTLY.  A leak is a defect in the step
# that leaked, and a fix that hides it would leave nobody any way to find out
# which one.  Write-Host, not Write-Output, so the note reaches the screen in
# both branches and is not captured into the step's own redirected file.
function Close-LeakedTranscripts([string]$stepName) {
    $leaked = 0
    while ($true) {
        try { Stop-Transcript -ErrorAction Stop | Out-Null; $leaked++ } catch { break }
    }
    if ($leaked -gt 0) {
        Write-Host ("  NOTE: {0} left {1} transcript(s) open - PRE_RELEASE 40. Closed." -f
                    $stepName, $leaked)
    }
}

$lines  = @()
$failed = 0
# 03 Sep 26 - PRE_RELEASE_FIXES.md 152.  COUNTED SEPARATELY, NOT COUNTED
# DIFFERENTLY.  $failed keeps its meaning exactly - every step that did not
# exit 0, refusals included - so the exit logic at the foot of this file is
# untouched and a step that COULD NOT RUN still never reads as a pass.  This is
# the extra count beside it, so the closing line can say which kind of red a
# red suite is.  b106 showed six API verifiers "exit 1" in a block and it read
# as "the API is broken"; not one of them had measured anything.
#
# A STEP THAT EXITED 2 BUT LEFT [FAIL] MARKERS IS COUNTED AS FAILED, NOT
# REFUSED.  Entry 151's Refuse() downgrades itself to exit 1 when a decisive
# check has already failed, so this should not arise in the six - but the rule
# here does not depend on that, and it errs towards reporting a failure.
$refused = 0
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
        Close-LeakedTranscripts $s.Name
        $lines += ('{0,-28} {1,-22} exit {2}{3}' -f $s.Name, $shown, $code,
                   $(if ($code -eq 2) { '  COULD NOT RUN' } else { '' }))
        if ($code -ne 0) { $failed++ }
        if ($code -eq 2) { $refused++ }   # 03 Sep 26 - PRE_RELEASE 152
        continue
    }

    $stepLog = Join-Path $logDir ('{0}-{1:d2}-{2}.log' -f $stamp, $i, $short)
    Write-Host ('[{0,2}/{1}] {2,-22} {3,-24}' -f $i, $steps.Count, $short, $shown) -NoNewline

    # *> captures ALL streams - output, error, warning, verbose, debug and
    # information.  Write-Host goes to the INFORMATION stream in PowerShell 5+,
    # which is why it is caught here and would not have been in 2.0.
    & $path @splat *> $stepLog
    $code = $LASTEXITCODE
    Close-LeakedTranscripts $s.Name

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
    } elseif ($code -eq 2 -and $fails.Count -eq 0) {
        # 03 Sep 26 - PRE_RELEASE_FIXES.md 152.  STILL COUNTED IN $failed, and
        # still not a pass - it is coloured and worded differently because it
        # sends the reader somewhere else: to the environment, not the product.
        $failed++
        $refused++
        Write-Host ' COULD NOT RUN  exit 2' -ForegroundColor Yellow
        Get-Content -LiteralPath $stepLog -Tail 4 -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host ('         ' + $_) -ForegroundColor DarkYellow }
        Write-Host ('         full output: ' + $stepLog) -ForegroundColor Yellow
        $lines += ('{0,-28} {1,-22} exit {2}  COULD NOT RUN  {3}' -f $s.Name, $shown, $code, $stepLog)
        continue
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

# 03 Sep 26 - THE HEADING GOES INTO THE FILE, NOT ONLY THE CONSOLE.
# PRE_RELEASE_FIXES 149.  Until now the PARTIAL banner was Write-Output only
# while the file received $lines alone, so the one artifact that outlives the
# run could not say whether it was a full run - and a reader grepping it for
# PARTIAL found nothing on a partial run exactly as on a whole one, the
# dangerous direction.  VerifyInstall1 escaped this only because it has a
# transcript; this runner has none of its own (see the note near the top).
# Build the heading once, print it AND write it at the head of the file.
#
# @() ON BOTH SIDES OF THE '+' DELIBERATELY.  A bare "$heading + $lines" folds
# the string and the array's first element into one when $lines happens to be a
# scalar, which is the array-literal trap this file has paid for elsewhere;
# wrapping both operands makes the result heading-then-rows whatever $lines is.
if ($partial) {
    $heading = ('===== post-cycle summary - PARTIAL, {0} of {1} step(s) =====' -f
                @($steps).Count, $fullCount)
} else {
    $heading = '===== post-cycle summary ====='
}
Write-Output ''
Write-Output $heading
$lines | ForEach-Object { Write-Output $_ }
(@($heading) + @($lines)) | Set-Content -LiteralPath $summary -Encoding utf8
Write-Output ''
Write-Output ("summary written to: " + $summary)
if ($Quiet) {
    Write-Output ("per-step output:    " + (Join-Path $logDir ($stamp + '-NN-verify-*.log')))
}
if ($failed -gt 0) {
    if ($partial) {
        Write-Output ("VerifyInstall2: PARTIAL - {0} of {1} step(s) run, {2} did not exit 0." -f
                      $steps.Count, $fullCount, $failed)
    } else {
        Write-Output ("VerifyInstall2: {0} of {1} step(s) did not exit 0." -f $failed, $steps.Count)
    }
    # 03 Sep 26 - PRE_RELEASE_FIXES.md 152.  SAY WHICH KIND OF RED, ON ITS OWN
    # LINE SO THE SENTENCE ABOVE KEEPS THE WORDING READERS AND GREPS EXPECT.
    if ($refused -gt 0) {
        Write-Output ("  of those, {0} FAILED a check and {1} COULD NOT RUN (exit 2)." -f
                      ($failed - $refused), $refused)
        Write-Output '  A step that could not run measured nothing: it is not a product finding.'
        Write-Output '  Read those first - a stale tree or a missing tool refuses every one of them.'
    }
    exit 1
}
# 30 Aug 26 - NEVER "all N steps exited 0" ON A PARTIAL RUN.  On a -Only run that
# sentence would be a claim about the whole half, and the last line is how these
# logs get read.
if ($partial) {
    Write-Output ("VerifyInstall2: PARTIAL - {0} of {1} step(s) run, all exited 0." -f
                  $steps.Count, $fullCount)
    Write-Output '  The other steps were NOT run and this says nothing about them.'
} else {
    Write-Output ("VerifyInstall2: all {0} steps exited 0." -f $steps.Count)
}
