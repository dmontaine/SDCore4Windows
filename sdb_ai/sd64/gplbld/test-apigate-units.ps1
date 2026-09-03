# test-apigate-units.ps1 - PRE_RELEASE_FIXES 146.
#
# Free: no install, no elevation, no run token.  It reads gplbld/sd.iss and
# asserts the shape of the API firewall gate.
#
# ===========================================================================
# WHAT IT GUARDS, AND WHY A COMMENT WOULD NOT HAVE DONE
# ===========================================================================
#
# 146: ApiConfAbsent was a LIVE FileExists on sd.conf, and the installer writes
# sd.conf itself.  So one function answered TRUE at the tasks page (box offered)
# and FALSE at ssPostInstall (firewall gated on it) - and because the other arm
# of that gate is "not TrueUpgrade", the two were unsatisfiable together and
# ApplyApiFirewall never ran on ANY path.  "Let other computers on your network
# reach it" was inert on every install.
#
# ***THE ONE-LINE CAUSE WAS ONE CALL.  THE CLASS IS "A TEST WHOSE ANSWER THE
# INSTALLER CHANGES MID-RUN", AND THIS FILE IS WHAT CATCHES THE CLASS.***  The
# same lesson was already written down twice in sd.iss - SdWasInstalled and
# SshWasAbsent both say "sample it in InitializeSetup, before anything is
# written" - and ApiConfAbsent was still built the other way.  Prose in the file
# did not stop it; a check does.
#
# THE STRIPPER IS SHARED, NOT COPIED (PRE_RELEASE 143).  This tree's habit is to
# quote the defect beside the fix, so an unstripped scan would trip on the very
# comment explaining 146 - which is exactly how 131 and 143 were paid for.
#
# NO Set-StrictMode AT FILE SCOPE: it would bind whatever dot-sources this.

$ErrorActionPreference = 'Stop'

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $here 'strip-comments.ps1')
$iss = Join-Path $here 'sd.iss'

$script:pass = 0
$script:fail = 0
$script:ran  = 0

function Check {
    param([string] $Name, $Expected, $Actual)
    $script:ran++
    if ($Expected -ceq $Actual) {
        $script:pass++
        Write-Host ("  [PASS] {0}" -f $Name)
    } else {
        $script:fail++
        Write-Host ("  [FAIL] {0}`n         expected <{1}>`n         actual   <{2}>" -f $Name, $Expected, $Actual) -ForegroundColor Red
    }
}

Write-Host ''
Write-Host 'test-apigate-units - the API firewall gate in sd.iss (PRE_RELEASE 146)'
Write-Host ("  sd.iss : {0}" -f $iss)

# --- null cases, refused out loud ------------------------------------------
if (-not (Test-Path -LiteralPath $iss)) {
    Write-Host '  REFUSED: sd.iss not found - nothing was checked.' -ForegroundColor Red
    exit 2
}
$lines = @(Get-StrippedLines -Path $iss -Kind 'iss')
Write-Host ("  stripped lines : {0}" -f $lines.Count)
if ($lines.Count -lt 100) {
    Write-Host '  REFUSED: the strip produced almost nothing - the parse is wrong, not the file.' -ForegroundColor Red
    exit 2
}

# CANARY.  If the stripper ever eats real code, every test below would pass by
# finding nothing.  A name that is certainly in sd.iss's [Code] must survive.
$canary = @($lines | Where-Object { $_.Text -match 'function\s+ApplyApiFirewall' })
if ($canary.Count -eq 0) {
    Write-Host '  REFUSED: canary "function ApplyApiFirewall" not found after stripping.' -ForegroundColor Red
    Write-Host '  The scan is broken; no verdict is available.' -ForegroundColor Red
    exit 2
}
Write-Host ("  canary : ApplyApiFirewall found at line {0}" -f $canary[0].Line)
Write-Host ''

# --------------------------------------------------------------------------
# 1. ApiConfAbsent MUST NOT READ THE FILE SYSTEM.  This is 146 in one line.
# --------------------------------------------------------------------------
$fnStart = @($lines | Where-Object { $_.Text -match '^\s*function\s+ApiConfAbsent\s*:' })
Check 'ApiConfAbsent is defined exactly once' 1 $fnStart.Count

$body = ''
if ($fnStart.Count -eq 1) {
    $from = $fnStart[0].Line
    # Body is short; take until the first "end;" after the header.
    foreach ($e in $lines) {
        if ($e.Line -lt $from) { continue }
        $body += $e.Text + "`n"
        if ($e.Line -gt $from -and $e.Text -match '^\s*end\s*;') { break }
    }
}
Check 'ApiConfAbsent body was captured'      $true  ($body.Length -gt 0)
Check 'ApiConfAbsent does NOT call FileExists' $false ($body -match 'FileExists')
Check 'ApiConfAbsent does NOT expand sd.conf'  $false ($body -match 'sd\.conf')
Check 'ApiConfAbsent returns the sampled var'  $true  ($body -match 'Result\s*:=\s*ApiConfWasAbsent')

# --------------------------------------------------------------------------
# 2. THE SAMPLE IS TAKEN ONCE, IN InitializeSetup, BEFORE ANYTHING IS WRITTEN.
# --------------------------------------------------------------------------
$assign = @($lines | Where-Object { $_.Text -match '^\s*ApiConfWasAbsent\s*:=' })
Check 'ApiConfWasAbsent is assigned exactly once' 1 $assign.Count

$declared = @($lines | Where-Object { $_.Text -match '^\s*ApiConfWasAbsent\s*:\s*Boolean\s*;' })
Check 'ApiConfWasAbsent is declared once'         1 $declared.Count

$initStart = @($lines | Where-Object { $_.Text -match '^\s*function\s+InitializeSetup\s*:' })
Check 'InitializeSetup is defined exactly once'   1 $initStart.Count

# The assignment must sit between InitializeSetup's header and the NEXT
# top-level routine - that is what "sampled in InitializeSetup" means, and a
# line moved out of it is the way 146 comes back.
$inInit = $false
if ($assign.Count -eq 1 -and $initStart.Count -eq 1) {
    $nextRoutine = @($lines | Where-Object {
        $_.Line -gt $initStart[0].Line -and $_.Text -match '^\s*(function|procedure)\s+\w+' })
    $endOfInit = if ($nextRoutine.Count -gt 0) { $nextRoutine[0].Line } else { [int]::MaxValue }
    $inInit = ($assign[0].Line -gt $initStart[0].Line) -and ($assign[0].Line -lt $endOfInit)
    Write-Host ("         (InitializeSetup {0}..{1}, assignment at {2})" -f $initStart[0].Line, $endOfInit, $assign[0].Line)
}
Check 'the sample is taken inside InitializeSetup' $true $inInit

# --------------------------------------------------------------------------
# 3. THE GATE ITSELF IS STILL WIRED.  Removing it would make the box inert
#    again by a different route, and nothing else would notice.
# --------------------------------------------------------------------------
$gate = @($lines | Where-Object { $_.Text -match 'ApiConfAbsent\s+then' -and $_.Text -match 'TrueUpgrade' })
Check 'the firewall gate still tests both arms' 1 $gate.Count

$call = @($lines | Where-Object { $_.Text -match ':=\s*ApplyApiFirewall' })
Check 'ApplyApiFirewall still has exactly one call site' 1 $call.Count

$taskCheck = @($lines | Where-Object { $_.Text -match 'Check:\s*ApiConfAbsent' })
Check 'the apiremote task still carries Check: ApiConfAbsent' 1 $taskCheck.Count

# --------------------------------------------------------------------------
# 4. THE sd.conf [Files] PAIR IS STILL onlyifdoesntexist ON BOTH ARMS.
#    That is WHY the live test could not work, and if it ever stops being true
#    the reasoning in the comments above stops being true with it.
# --------------------------------------------------------------------------
$confFiles = @($lines | Where-Object { $_.Text -match 'DestName:\s*"sd\.conf"' -or $_.Text -match 'Stage.\\ProgramData\\sd\.conf' })
Check 'both sd.conf [Files] arms are present' 2 $confFiles.Count

# --------------------------------------------------------------------------
# 5. PRE_RELEASE_FIXES 147 - THE SCOPE IS MEASURED, AND MEASURED LATE.
#
# ***THIS IS 146's LESSON POINTING THE OTHER WAY, AND THAT IS WHY IT IS HERE
# RATHER THAN IN A FILE OF ITS OWN.***  ApiConfAbsent must be sampled EARLY,
# before the installer writes the file it tests for.  The firewall SCOPE must be
# sampled LATE, after the one call that creates the rule - sample it first and
# the closing box reports the state this install was about to change.  Two
# opposite rules, one question ("which side of the write is this asking
# about?"), and a reader who has just learned the first one is exactly who would
# move the second.
# --------------------------------------------------------------------------
$scopeFn = @($lines | Where-Object { $_.Text -match '^\s*function\s+GetApiRuleScope\s*:' })
Check 'GetApiRuleScope is defined exactly once' 1 $scopeFn.Count

$scopeCall = @($lines | Where-Object { $_.Text -match 'ApiScope\s*:=\s*GetApiRuleScope' })
Check 'the API scope is sampled exactly once'   1 $scopeCall.Count

$afterApply = $false
if ($scopeCall.Count -eq 1 -and $call.Count -eq 1) {
    $afterApply = ($scopeCall[0].Line -gt $call[0].Line)
    Write-Host ("         (ApplyApiFirewall at {0}, scope sampled at {1})" -f $call[0].Line, $scopeCall[0].Line)
}
Check 'the scope is sampled AFTER the firewall step' $true $afterApply

# THE MESSAGE SPEAKS ONLY FROM A MEASUREMENT.  'none' is the measured absence of
# a rule; anything else - including the empty string GetApiRuleScope returns when
# it could not read one - must leave the paragraph out.
$scopeGate = @($lines | Where-Object { $_.Text -match "ApiScope\s*=\s*'none'" })
Check "the paragraph is gated on a measured 'none'" 1 $scopeGate.Count

$gateText = ''
if ($scopeGate.Count -eq 1) { $gateText = $scopeGate[0].Text }
Check 'that gate also requires a preserved sd.conf' $true ($gateText -match 'not\s+ApiConfAbsent')
Check 'that gate also requires a listener'          $true ($gateText -match 'ApiListenerAfterwards')

# --------------------------------------------------------------------------
# 6. THE TWO PARAGRAPHS ARE INITIALISED EMPTY AND THEN GATED, IN THAT ORDER.
#
# PRE_RELEASE_FIXES 135 and 147.  Each is a sentence about something that did
# NOT come back, and each is true only under its gate: 135's on "SD Core was not
# installed when Setup started" (an in-place upgrade loses no membership), 147's
# on the measured scope.  Ungating either turns a true sentence into a false one
# on the path it does not apply to, which is the direction 77 and 133 were both
# filed for.  So the assignment must be followed IMMEDIATELY by its own "if".
# --------------------------------------------------------------------------
function Next-Statement([int] $after) {
    foreach ($e in $lines) {
        if ($e.Line -le $after) { continue }
        if ($e.Text.Trim() -eq '') { continue }
        return $e.Text.Trim()
    }
    return ''
}

$accessInit = @($lines | Where-Object { $_.Text -match "^\s*AccessMsg\s*:=\s*'';" })
Check 'AccessMsg is initialised empty exactly once' 1 $accessInit.Count
$accessNext = ''
if ($accessInit.Count -eq 1) { $accessNext = Next-Statement $accessInit[0].Line }
Check 'AccessMsg is then gated on not TrueUpgrade' $true ($accessNext -match '^if\s+not\s+TrueUpgrade\s+then')

$apiInit = @($lines | Where-Object { $_.Text -match "^\s*ApiRuleMsg\s*:=\s*'';" })
Check 'ApiRuleMsg is initialised empty exactly once' 1 $apiInit.Count
$apiNext = ''
if ($apiInit.Count -eq 1) { $apiNext = Next-Statement $apiInit[0].Line }
Check 'ApiRuleMsg is then gated on the measured scope' $true ($apiNext -match "ApiScope\s*=\s*'none'")

# --------------------------------------------------------------------------
# 7. AND THE SCRIPT ON THE OTHER END STILL TAKES -ScopeFile.
#
# TWO FILES DESCRIBING ONE FACT, KEPT IN STEP BY HAND - the shape
# test-stemcoverage and test-dirscoverage exist for.  sd.iss passes -ScopeFile
# and reads three words back; api-firewall.ps1 has to accept the switch and
# write one of them.  A rename on either side leaves the installer taking the
# "could not read it" path silently, and the box then says nothing at all -
# which looks exactly like a machine whose rule is fine.
# --------------------------------------------------------------------------
$fw = Join-Path $here 'api-firewall.ps1'
if (-not (Test-Path -LiteralPath $fw)) {
    Write-Host '  REFUSED: api-firewall.ps1 not found beside sd.iss.' -ForegroundColor Red
    exit 2
}
$fwLines = @(Get-StrippedLines -Path $fw -Kind 'hash')
Check 'api-firewall.ps1 declares -ScopeFile' 1 @($fwLines | Where-Object { $_.Text -match '\[string\]\$ScopeFile' }).Count
Check 'it writes the file'                   1 @($fwLines | Where-Object { $_.Text -match 'WriteAllText\(\$ScopeFile' }).Count

$verdicts = @($fwLines | Where-Object { $_.Text -match "\`$verdict\s*=\s*'(open|restricted|none)'" })
Check 'it can write all three verdicts' 3 $verdicts.Count

$issWords = @($lines | Where-Object { $_.Text -match "Scope\s*=\s*'open'" -and $_.Text -match "'restricted'" -and $_.Text -match "'none'" })
Check 'sd.iss accepts exactly those three words' 1 $issWords.Count

Write-Host ''
Write-Host ("  ran {0}, passed {1}, failed {2}" -f $script:ran, $script:pass, $script:fail)

# The number of Check calls above.  It is here so that a check DELETED during a
# refactor fails loudly instead of leaving a smaller suite reporting green.
$minimum = 27
if ($script:ran -lt $minimum) {
    Write-Host ("  REFUSED: only {0} checks ran, expected at least {1}" -f $script:ran, $minimum) -ForegroundColor Red
    exit 2
}
if ($script:fail -gt 0) { exit 1 }
Write-Host '  the API firewall gate is sampled once and still wired.'
exit 0
