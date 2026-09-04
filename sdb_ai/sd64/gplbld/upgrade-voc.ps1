#
# upgrade-voc.ps1 - bring an upgraded install's ACCOUNT VOCABULARIES up to the
# release.
#
# Run by the installer at ssPostInstall, on an UPGRADE only.
#
# WHY AN UPGRADE NEEDS THIS AND A FIRST INSTALL DOES NOT.  PRE_RELEASE_FIXES 70.
# An upgrade REPLACES the shipped vocabulary - newvoc and voc_template are on
# stage.py's replace list - and REBUILDS NOTHING.  Every account's live VOC,
# SDSYS's own included, is built FROM those templates by the bootstrap and by
# CREATEA, and is in neither the replace list nor the preserve list, so nothing
# an upgrade does can reach it.  The result is that a release which adds a verb
# ships the verb to newvoc and no existing account can type it.  A first install
# lays down the whole staged tree, whose VOC the build's own bootstrap already
# wrote, so there is nothing to do and this returns at once.
#
# ***IT CALLS THE EXISTING ALL-ACCOUNTS PATH, NOT A NEW ONE.***  That is the
# entry's ruling and it is the whole design.  LOGIN's UPDATE.VOC walk already
# reads sdsys/accounts and rewrites every registered account's VOC from
# NEWVOC, at each account's own tier, honouring [locked] on everything but a
# verb; UPDATE.ACCOUNTS answering Y is how a person reaches it.  All this does
# is ask for the same walk with the question already answered, which is what
# CPROC spells "UPDATE.ACCOUNTS ALL" (LOGIN mode 4).  A second implementation
# of "refresh every account" would drift from the first at the next tier change.
#
# ***WHY NOT JUST PIPE "Y" INTO THE INTERACTIVE FORM.***  Because a prompt read
# on a handle that answers nothing takes the default, and the default is N -
# so the step would report a clean upgrade over a tree it never touched.
# PROJECT_STATUS also records that piping into sd is how a session gets a hung
# sd.exe and an elevation to clear it.  The keyword removes the prompt instead
# of trying to answer it.
#
# THE THREE THINGS THAT KILLED EARLIER STEPS OF THIS SHAPE are all handled the
# way adopt-account.ps1's header records them, and its measurements are not
# repeated here: "sd -internal" NEEDS A RUNNING SERVER and the installer starts
# none; it NEEDS AN ELEVATED TOKEN, which is why sd.iss calls this from [Code]
# and not from a postinstall checkbox; and ITS OUTPUT HAS TO SURVIVE, so
# everything is captured and logged.
#
# ANCHORED ON THE WORDING SD PRINTS ON THE POSITIVE PATH, AND ON A COUNT.
# Message 10171, "N account(s) had their VOC updated", exists for this script:
# without it a walk that opened the register and visited NOTHING prints exactly
# what a walk that refreshed every account prints, and the exit code cannot tell
# them apart.  The per-account 5004 lines are counted separately as a second,
# independent reading - two numbers that must agree.
#
# EXIT CODES, and sd.iss reports each one differently:
#   0  every registered account's VOC was refreshed
#   3  SD would not start, so nothing was run
#   4  SDSYS has no update.accounts verb - a tree older than the mechanism
#   1  it ran and did not finish the job
#

[CmdletBinding()]
param(
    # Where SD's program files are.  The installer passes {app}.  NOT
    # "= $PSScriptRoot" in the default: in a script with [CmdletBinding()] that
    # evaluates to the empty string, which cost a whole install once -
    # adopt-account.ps1's -AppDir comment has the measurement.  Assigned in the
    # body instead.
    [string] $AppDir = '',

    [string] $DataDir = 'C:\ProgramData\SD'
)

$ErrorActionPreference = 'Stop'

$LogFile = Join-Path $DataDir 'upgrade-voc.log'

function Say([string] $Message) {
    Write-Output $Message
    try { Add-Content -Path $LogFile -Value $Message -ErrorAction Stop } catch { }
}

if (-not $AppDir) { $AppDir = $PSScriptRoot }

Say ("=== upgrade-voc {0}  AppDir={1}  DataDir={2}" -f
     (Get-Date -Format 's'), $AppDir, $DataDir)

if (-not $AppDir) {
    Say 'upgrade-voc: no -AppDir given and PSScriptRoot is empty; cannot find sd.exe'
    exit 1
}

$sd = Join-Path $AppDir 'usr\bin\sd.exe'
if (-not (Test-Path $sd)) { Say "upgrade-voc: no sd.exe at $sd"; exit 1 }

# THE NULL CASE, REFUSED BEFORE ANYTHING STARTS.  The walk reads this register;
# if it is not there, "0 accounts updated" would be the honest answer to a
# question that could not be asked, and it would look like a working step on an
# empty machine.  The count is taken here, from the register itself, and the
# run is measured against it.
$acctDir = Join-Path $DataDir 'sdsys\accounts'
if (-not (Test-Path -LiteralPath $acctDir)) {
    Say "upgrade-voc: no account register at $acctDir - nothing could be walked."
    exit 1
}
$registered = @(Get-ChildItem -LiteralPath $acctDir -File -ErrorAction SilentlyContinue)
Say ("upgrade-voc: {0} holds {1} account record(s)" -f $acctDir, $registered.Count)
if ($registered.Count -eq 0) {
    Say 'upgrade-voc: the account register is EMPTY, so a run would visit nothing'
    Say '  and still say it succeeded.'
    exit 1
}

function Invoke-Sd {
    # NEVER "Start-Process -Wait": sdwind inherits sd's handles and outlives it,
    # so waiting on the STREAMS waits for the daemon.  Wait on the PROCESS.
    # Measured twice on 15 Aug 2026 - adopt-account.ps1's Invoke-Sd has it.
    #
    # TEN MINUTES, not upgrade-dicts' five: this one is O(accounts) and copies
    # some 400 records into each, where that one is a single pass over a fixed
    # 76-record file.  A site with a few hundred accounts is the case where a
    # short timeout would kill a working upgrade half way through a VOC.
    param([string[]] $SdArgs, [int] $TimeoutMs = 600000)

    $out = Join-Path $env:TEMP ("sd-upvoc-out-$PID.txt")
    $err = Join-Path $env:TEMP ("sd-upvoc-err-$PID.txt")
    $p = Start-Process -FilePath $sd -ArgumentList $SdArgs -NoNewWindow -PassThru `
                       -RedirectStandardOutput $out -RedirectStandardError $err
    # TOUCH THE HANDLE OR ExitCode COMES BACK $null.  Start-Process -PassThru
    # returns a Process whose exit code is unreadable after WaitForExit unless
    # the handle was cached first, and the log then prints "exit " with nothing
    # after it.  upgrade-dicts.ps1's comment has the control that measured it.
    $null = $p.Handle
    $exited = $p.WaitForExit($TimeoutMs)
    $text = ''
    foreach ($f in @($out, $err)) {
        if (Test-Path $f) {
            $text += (Get-Content $f -Raw)
            Remove-Item $f -Force -ErrorAction SilentlyContinue
        }
    }
    if (-not $exited) {
        return [pscustomobject]@{ Code = 1; Text = "sd $SdArgs did not finish in $($TimeoutMs / 1000)s" }
    }
    return [pscustomobject]@{ Code = $p.ExitCode; Text = "$text".Trim() }
}

# THE WHOLE VERDICT, IN ONE PURE FUNCTION, so that it can be driven off disk.
# gplbld/test-upgradevoc-units.ps1 lifts this out BY AST and feeds it recorded
# SD output - the shape test-editorver-units and test-wraptext-units use - so
# the part of this script that can be wrong SILENTLY is exercised with no
# install, no elevation and no run token.  Everything above it is plumbing whose
# failure is loud.
#
# Returns a hashtable, never a bare value: PowerShell collapses a one-element
# array to a scalar and an empty one to $null on the way out of a function, so
# "no accounts" and "could not read" would arrive as the same thing.
#
# Code: 0 refreshed, 4 this tree predates the verb, 1 anything else.
function Get-VocVerdict {
    param(
        [string] $Text,
        [int]    $Registered
    )

    $t = "$Text"

    # THE SUCCESS ANCHOR IS SD's OWN POSITIVE WORDING (message 10171) AND THE
    # NUMBER INSIDE IT.  Not the verb name, not the account names, not the exit
    # code: all three appear on the failure paths as well.
    $total = -1
    $m = [regex]::Match($t, '(?m)^\s*(\d+)\s+account\(s\) had their VOC updated')
    if ($m.Success) { $total = [int] $m.Groups[1].Value }

    # The second, independent reading: message 5004, "Updating <path>", once per
    # account the walk opened.  Two numbers from two places that must agree - a
    # pattern that had drifted onto the wrong line shows up here as a
    # disagreement rather than as a confident wrong answer.
    #
    # ***THE PATH IS PART OF THE PATTERN, AND LEAVING IT OUT MADE EVERY REAL RUN
    # DISAGREE WITH ITSELF.***  5004's argument is always an account's VOC -
    # LOGIN builds it as "<account path>/voc" - so the line ends in voc.  Written
    # first as a bare "^Updating ", this also matched the release's own new
    # message 10170, whose first draft opened "Updating the VOC of every
    # registered account": the counts then came out 2 and 3 on a two-account
    # machine and the script refused a good upgrade.  Caught by
    # test-upgradevoc-units on its first run, off disk, before any guest saw it.
    # 10170 was reworded as well - one collision, both ends closed - but the
    # pattern is the half that stops the NEXT message from doing it again.
    $visited = @(($t -split "`r?`n") |
                 Where-Object { $_ -match '(?i)^\s*Updating\s+\S.*voc\s*$' }).Count

    # AND THE CONTROL: the wording SD prints when it REFUSES.  A run where the
    # positive pattern matches AND one of these appears is not a pass either.
    $bad = @()
    foreach ($pat in @('Cannot update every registered account from here',
                       'does not take',
                       'Cannot open accounts register',
                       'is not in your VOC',
                       'Command requires administrator privileges')) {
        if ($t -match [regex]::Escape($pat)) { $bad += $pat }
    }

    # A TREE OLDER THAN THE VERB IS ITS OWN ANSWER, not a generic failure: the
    # administrator has to run the walk by hand once, and no rerun of the
    # installer will ever help.  Tested FIRST because it is also a disqualifier,
    # and the specific answer is the more useful one.
    if ($t -match 'is not in your VOC') {
        return @{ Code = 4; Total = $total; Visited = $visited
                  Why = 'SDSYS has no update.accounts verb - this data tree predates it.' }
    }
    if ($bad.Count -gt 0) {
        return @{ Code = 1; Total = $total; Visited = $visited
                  Why = ('SD reported: ' + ($bad -join '; ')) }
    }
    if ($total -lt 0) {
        return @{ Code = 1; Total = $total; Visited = $visited
                  Why = 'SD never printed the count, so the walk did not finish.' }
    }
    if ($total -eq 0) {
        return @{ Code = 1; Total = $total; Visited = $visited
                  Why = 'the walk visited NO account, which is not a success on a machine whose register holds records.' }
    }
    if ($total -ne $visited) {
        return @{ Code = 1; Total = $total; Visited = $visited
                  Why = ("the count says {0} and there are {1} 'Updating' lines - one of the two readings is wrong, so neither is trusted." -f $total, $visited) }
    }
    return @{ Code = 0; Total = $total; Visited = $visited; Why = 'COMPLETE' }
}

function Test-SdRunning { return $null -ne (Get-Process sdwind -ErrorAction SilentlyContinue) }

function Wait-SdRunning {
    # "sd -start" forks and returns before sdwind appears, so looking once wins
    # the race on an idle machine and loses it on a busy one.  Measured
    # 15 Aug 2026; adopt-account.ps1's Wait-SdRunning has the whole story.
    param([int] $TimeoutSeconds = 20)
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-SdRunning) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return (Test-SdRunning)
}

# --- make sure there is a server ---------------------------------------------

$weStartedIt = $false
$result = 1
try {
    if (-not (Test-SdRunning)) {
        $r = Invoke-Sd @('-start')
        if (-not (Wait-SdRunning)) {
            Say 'upgrade-voc: SD would not start, so no account VOC was updated'
            Say ("  sd -start exited {0}: {1}" -f $r.Code, $r.Text)
            $result = 3
            throw 'no server'
        }
        $weStartedIt = $true
    }

    # --- UPDATE.ACCOUNTS ALL -------------------------------------------------
    #
    # "-internal" names SDSYS for itself in sd.c, which is what the walk needs:
    # LOGIN gates it on "@who = 'SDSYS' and kernel(K$ADMINISTRATOR,-1)" and
    # refuses out loud (message 10172) when either half is missing, so a session
    # that landed somewhere else cannot pass silently.
    Say 'upgrade-voc: sd -internal UPDATE.ACCOUNTS ALL'
    $w = Invoke-Sd @('-internal', 'UPDATE.ACCOUNTS', 'ALL')
    Say ("  exit {0}" -f $w.Code)
    Say '  --- output ---'
    foreach ($l in ("$($w.Text)" -split "`r?`n")) { if ($l.Trim()) { Say ("  | " + $l) } }
    Say '  --- end ---'

    $v = Get-VocVerdict -Text $w.Text -Registered $registered.Count
    Say ("upgrade-voc: {0} account(s) reported updated, {1} 'Updating' line(s), {2} registered" -f
         $v.Total, $v.Visited, $registered.Count)
    Say ("upgrade-voc: {0}" -f $v.Why)

    $result = $v.Code
    if ($result -ne 0) { throw $v.Why }
}
catch {
    Say ("upgrade-voc: {0}" -f $_.Exception.Message)
}
finally {
    # STOP ONLY WHAT WE STARTED.  The installer's other steps use the same rule,
    # so neither depends on the other having left a server behind.
    if ($weStartedIt) {
        Say 'upgrade-voc: stopping the server this script started'
        $s = Invoke-Sd @('-stop')
        Say ("  sd -stop exited {0}" -f $s.Code)
    }
}

Say ("upgrade-voc: exit {0}" -f $result)
exit $result
