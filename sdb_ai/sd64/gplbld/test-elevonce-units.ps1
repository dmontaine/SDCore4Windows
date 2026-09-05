# test-elevonce-units.ps1 - drives elevate-once.ps1 without elevating anything
#
# 4 Sep 26 - PRE_RELEASE 165.  Free: no install, no elevation, no run token, no
# SD.  Runs in about a second.
#
# ***WHY A GUARD AT ALL, WHEN THE THING IT GUARDS ONLY RUNS INSIDE A SUITE.***
# Every route in elevate-once.ps1 is reached only during a ~20-minute run that
# a person has to sit through and that costs a -Run token, and the one that
# matters most - "an adopting step must never stop the helper" - fails SILENTLY:
# the helper exits, the next step asks for consent, and the run still goes
# green.  Nobody would read that as a defect; they would read it as "the helper
# thing does not seem to save many prompts".  A second here says it plainly.
#
# ***HOW IT DRIVES A FILE THAT SHELLS OUT TO A UAC PROMPT.***  elevate-once.ps1
# finds sd-elevate.ps1 with Join-Path $PSScriptRoot, and $PSScriptRoot in a
# DOT-SOURCED file is that file's OWN directory - measured, not assumed.  So the
# module is copied into a sandbox beside a FAKE sd-elevate.ps1 that records its
# argv and exits with a code this test chooses.  Nothing elevates; the decisions
# are real.
#
# ***WHAT IS NOT COVERED, SAID OUT LOUD.***  Two routes cannot be driven here
# because reaching them raises a real UAC prompt, and a test that prompts is one
# nobody can run unattended.  They are asserted STATICALLY over the AST instead,
# and the partition at the end requires every route to be one or the other, so a
# new route cannot appear without somebody classifying it.

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$pass = 0
$fail = 0
function Note([bool]$ok, [string]$what, [string]$got = '') {
    if ($ok) { $script:pass++; Write-Output ('  [PASS] ' + $what) }
    else {
        $script:fail++
        Write-Output ('  [FAIL] ' + $what + $(if ($got -ne '') { ' -- ' + $got } else { '' }))
    }
}

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$mod  = Join-Path $here 'elevate-once.ps1'

Write-Output '===== test-elevonce-units ====='
Write-Output ('  gplbld  : ' + $here)
Write-Output ('  subject : ' + $mod)

if (-not (Test-Path -LiteralPath $mod)) {
    Write-Output '  [FAIL] elevate-once.ps1 is not beside this test. Nothing was measured.'
    exit 1
}

# --------------------------------------------------------------- the sandbox
$sandbox = Join-Path $env:TEMP ('elevonce-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$null = New-Item -ItemType Directory -Path $sandbox
Write-Output ('  sandbox : ' + $sandbox)

$callLog  = Join-Path $sandbox 'calls.log'
$nextExit = Join-Path $sandbox 'nextexit.txt'

try {
    Copy-Item -LiteralPath $mod -Destination (Join-Path $sandbox 'elevate-once.ps1')

    # The stand-in for sd-elevate.ps1.  Same parameter surface, records what it
    # was asked to do, and exits with whatever nextexit.txt says.
    $fake = @'
param(
    [switch]$Start, [switch]$Run, [switch]$Stop,
    [string]$PipeName = '', [int]$OwnerPid = 0, [string]$Script = '', [string]$LogFile = ''
)
$mode = 'none'
if ($Start) { $mode = 'Start' }
if ($Run)   { $mode = 'Run' }
if ($Stop)  { $mode = 'Stop' }
$line = "{0}|pipe={1}|pid={2}|script={3}" -f $mode, $PipeName, $OwnerPid, $Script
Add-Content -LiteralPath (Join-Path $PSScriptRoot 'calls.log') -Value $line
$rcFile = Join-Path $PSScriptRoot 'nextexit.txt'
$rc = 0
if (Test-Path -LiteralPath $rcFile) { $rc = [int](Get-Content -LiteralPath $rcFile -Raw).Trim() }
exit $rc
'@
    [System.IO.File]::WriteAllText((Join-Path $sandbox 'sd-elevate.ps1'), $fake, [System.Text.Encoding]::ASCII)

    function Reset-Calls { if (Test-Path -LiteralPath $callLog) { Remove-Item -LiteralPath $callLog -Force } }
    function Get-Calls {
        if (-not (Test-Path -LiteralPath $callLog)) { return @() }
        return @(Get-Content -LiteralPath $callLog)
    }
    function Set-NextExit([int]$rc) { [System.IO.File]::WriteAllText($nextExit, [string]$rc, [System.Text.Encoding]::ASCII) }

    Set-NextExit 0
    . (Join-Path $sandbox 'elevate-once.ps1')

    # ------------------------------------------------------- the pipe name
    Write-Output ''
    Write-Output '--- the pipe name is SD''s own, and it is pinned to the BASIC ---'

    $expected = 'sd-elev-' + $env:USERNAME
    Note ((Get-SdElevPipeName) -ceq $expected) 'Get-SdElevPipeName is sd-elev-<username>' ("got " + (Get-SdElevPipeName))

    # ONE FACT IN TWO FILES, SO COMPARE THEM.  gpl.bp/ELEVATE builds the name SD
    # uses; if the prefix there ever changes, this helper stops being the one SD
    # finds and every LOGTO SDSYS starts prompting again - which presents as
    # "the helper does not work any more" and is a one-character edit elsewhere.
    $elevBp = Join-Path $here '..\sdsys\gpl.bp\ELEVATE'
    if (Test-Path -LiteralPath $elevBp) {
        $bpLine = @(Get-Content -LiteralPath $elevBp | Where-Object { $_ -match "pipe\s*=\s*'sd-elev-'" })
        Note ($bpLine.Count -eq 1) 'gpl.bp/ELEVATE builds the pipe name from the same prefix' ("matched " + $bpLine.Count + " line(s)")
    } else {
        Note $false 'gpl.bp/ELEVATE is readable for the prefix cross-check' ('not at ' + $elevBp)
    }

    # ------------------------------------------------------- -NoHelper
    Write-Output ''
    Write-Output '--- -NoHelper asks for nothing and starts nothing ---'
    Reset-Calls
    $st = Start-SdElevationHelper -NoHelper
    Note ($st -is [hashtable]) 'Start-SdElevationHelper returns a hashtable, not an array'
    Note ($st.Active -eq $false) '-NoHelper leaves no active pipe'
    Note (@(Get-Calls).Count -eq 0) '-NoHelper never invokes sd-elevate.ps1' ("calls: " + @(Get-Calls).Count)

    # ------------------------------------------------------- adoption
    Write-Output ''
    Write-Output '--- adopting a parent''s pipe costs no consent ---'
    Reset-Calls
    $st = Start-SdElevationHelper -Adopt 'sd-elev-parent'
    Note ($st.Pipe -ceq 'sd-elev-parent') 'the adopted pipe is the one that was passed' $st.Pipe
    Note ($st.Started -eq $false) 'an adopted helper is not recorded as started by us'
    Note ($st.Active -eq $true) 'an adopted helper is active'
    Note (@(Get-Calls).Count -eq 0) 'adoption never invokes sd-elevate.ps1 at all' ("calls: " + @(Get-Calls).Count)

    # ***THE ONE THAT MATTERS.***  Steps run in-process and share the runner's
    # pid, so a -Stop from an adopting step empties the helper's owner set and
    # kills the consent the rest of the run depends on.
    Write-Output ''
    Write-Output '--- AN ADOPTING STEP MUST NEVER STOP THE HELPER ---'
    Reset-Calls
    Stop-SdElevationHelper
    $calls = @(Get-Calls)
    Note ($calls.Count -eq 0) 'Stop after an adoption sends NOTHING to sd-elevate.ps1' ("calls: " + ($calls -join '; '))
    Note (@($calls | Where-Object { $_ -like 'Stop|*' }).Count -eq 0) 'no Stop reached sd-elevate.ps1'
    Note ((Get-SdElevationState).Active -eq $false) 'the adopted pipe is released locally'

    # ------------------------------------------------------- a real start
    Write-Output ''
    Write-Output '--- starting one for ourselves, and stopping it ---'
    Reset-Calls
    Set-NextExit 0
    $st = Start-SdElevationHelper -Purpose 'the unit test'
    Note ($st.Started -eq $true) 'a helper we started is recorded as ours'
    Note ($st.Pipe -ceq $expected) 'it is served on SD''s own pipe name' $st.Pipe
    $calls = @(Get-Calls)
    Note ($calls.Count -eq 1) 'exactly one call to sd-elevate.ps1' ("calls: " + $calls.Count)
    Note ($calls[0] -like ('Start|pipe=' + $expected + '|pid=' + $PID + '*')) 'it was -Start with this pipe and pid' $calls[0]

    Reset-Calls
    Stop-SdElevationHelper
    $calls = @(Get-Calls)
    Note ($calls.Count -eq 1 -and $calls[0] -like 'Stop|*') 'Stop on a helper we started DOES reach sd-elevate.ps1' ($calls -join '; ')
    Note ((Get-SdElevationState).Active -eq $false) 'state is cleared after a stop'

    # ------------------------------------------------------- refusals to start
    Write-Output ''
    Write-Output '--- a helper that will not start is a FALLBACK, said out loud ---'
    foreach ($pair in @(@{ rc = 5; word = 'consent' }, @{ rc = 9; word = 'no helper' }, @{ rc = 1; word = 'launch' })) {
        Reset-Calls
        Set-NextExit $pair.rc
        $st = Start-SdElevationHelper
        Note ($st.Active -eq $false) ("exit {0} leaves no active pipe" -f $pair.rc)
        Note ($st.Reason -match ("exit " + $pair.rc)) ("exit {0}'s reason names the code" -f $pair.rc) $st.Reason
    }
    Set-NextExit 0

    # ------------------------------------------------------- the null cases
    Write-Output ''
    Write-Output '--- Invoke-ElevatedScript REFUSES the null case out loud ---'
    Reset-Calls
    $r = Invoke-ElevatedScript -Launcher '' -Why 'nothing'
    Note ($r -is [hashtable]) 'Invoke-ElevatedScript returns a hashtable'
    Note ($r.Ok -eq $false -and $r.Route -ceq 'refused') 'an empty launcher path is refused' ($r.Route)
    Note (@(Get-Calls).Count -eq 0) 'nothing was run for an empty launcher'

    Reset-Calls
    $r = Invoke-ElevatedScript -Launcher (Join-Path $sandbox 'no-such-file.ps1') -Why 'nothing'
    Note ($r.Ok -eq $false -and $r.Route -ceq 'refused') 'a missing launcher is refused' ($r.Route)
    Note (@(Get-Calls).Count -eq 0) 'nothing was run for a missing launcher'

    # ------------------------------------------------------- the helper route
    Write-Output ''
    Write-Output '--- the helper route carries the child''s verdict back ---'
    $launcher = Join-Path $sandbox 'launcher.ps1'
    [System.IO.File]::WriteAllText($launcher, "exit 0`r`n", [System.Text.Encoding]::ASCII)

    $null = Start-SdElevationHelper -Adopt $expected
    Reset-Calls
    Set-NextExit 0
    $r = Invoke-ElevatedScript -Launcher $launcher -Why 'a fixture'
    Note ($r.Ok -eq $true -and $r.Route -ceq 'helper') 'it went through the helper' ($r.Route)
    Note ($r.ExitCode -eq 0) 'exit 0 comes back as 0'
    $calls = @(Get-Calls)
    Note ($calls.Count -eq 1 -and $calls[0] -like ('Run|*|script=' + $launcher)) 'the launcher path was sent verbatim' ($calls -join '; ')

    Reset-Calls
    Set-NextExit 7
    $r = Invoke-ElevatedScript -Launcher $launcher -Why 'a fixture that fails'
    Note ($r.ExitCode -eq 7) 'a non-zero child exit is passed through, not flattened' ("got " + $r.ExitCode)
    Note ($r.Ok -eq $true) 'a failing child still counts as HAVING RUN - Ok and ExitCode are different questions'

    # ------------------------------------------------------- -Visible
    Write-Output ''
    Write-Output '--- -Visible sends a wrapper that cannot prompt ---'
    Reset-Calls
    Set-NextExit 0
    $r = Invoke-ElevatedScript -Launcher $launcher -Why 'the handover' -Visible
    $calls = @(Get-Calls)
    Note ($calls.Count -eq 1) 'one call for a -Visible run' ($calls -join '; ')
    $sent = ''
    if ($calls.Count -eq 1 -and $calls[0] -match 'script=(.+)$') { $sent = $Matches[1] }
    Note ($sent -ne $launcher -and $sent -ne '') 'the WRAPPER was sent, not the launcher' $sent
    if (Test-Path -LiteralPath $sent) {
        $ws = Get-Content -LiteralPath $sent -Raw
        # THE WHOLE POINT OF -Visible: the wrapper is already elevated, so its
        # child needs no -Verb.  A -Verb RunAs in here would put the prompt back
        # and this test would still be green without these two rows.
        Note ($ws -notmatch 'RunAs') 'the wrapper contains no RunAs'
        Note ($ws -notmatch '-Verb') 'the wrapper contains no -Verb'
        Note ($ws -match 'Start-Process') 'the wrapper does Start-Process'
        Note ($ws -notmatch 'WindowStyle') 'the wrapper does not hide the window'
        Note ($ws -like ('*' + $launcher + '*')) 'the wrapper names the real launcher'
        Note ($ws -match 'exit \$p\.ExitCode') 'the wrapper returns the child''s exit code'
    } else {
        Note $false 'the wrapper file exists' ('not at ' + $sent)
    }

    # --------------------------------------- the wiring, in BOTH directions
    #
    # ***ONE FACT IN TWO PLACES, SO COMPARE THEM.***  VerifyInstall1's
    # $helperAware list decides which steps are HANDED the pipe; each script's
    # own param block decides whether it can RECEIVE one.  Drift either way is
    # silent and costs a whole run its prompts:
    #
    #   in the list, no parameter  -> the step dies on parameter binding, which
    #                                 reads as a broken runner
    #   parameter, not in the list -> the step quietly starts or prompts for its
    #                                 own, and the run asks again for no reason
    #
    # Neither shows up as a failing check; the suite still goes green.  That is
    # exactly the shape test-stemcoverage-units and test-dirscoverage-units
    # exist for, and this is a third instance of it.
    Write-Output ''
    Write-Output '--- $helperAware and the scripts agree, both ways ---'

    function Get-ParamNames([string]$Path) {
        $tt = $null; $ee = $null
        $a = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tt, [ref]$ee)
        if ($null -eq $a.ParamBlock) { return @() }
        return @($a.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
    }

    $vi1 = Join-Path $here 'VerifyInstall1.ps1'
    $declared = @()
    if (Test-Path -LiteralPath $vi1) {
        $tt = $null; $ee = $null
        $vast = [System.Management.Automation.Language.Parser]::ParseFile($vi1, [ref]$tt, [ref]$ee)
        $asg = @($vast.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $n.Left.Extent.Text -eq '$helperAware' }, $true))
        Note ($asg.Count -eq 1) 'VerifyInstall1.ps1 declares $helperAware exactly once' ("found " + $asg.Count)
        if ($asg.Count -eq 1) {
            $declared = @($asg[0].Right.FindAll({ param($n)
                            $n -is [System.Management.Automation.Language.StringConstantExpressionAst] }, $true) |
                          ForEach-Object { $_.Value } | Sort-Object -Unique)
        }
    } else {
        Note $false 'VerifyInstall1.ps1 is readable' ('not at ' + $vi1)
    }

    # REFUSE THE NULL CASE: an empty list would make both directions agree
    # trivially and score a confident pass on a scan that found nothing.
    Note ($declared.Count -gt 0) '$helperAware is not empty' ("count: " + $declared.Count)

    foreach ($name in $declared) {
        $sp = Join-Path $here $name
        if (Test-Path -LiteralPath $sp) {
            Note ((Get-ParamNames $sp) -contains 'HelperPipe') `
                 ($name + ' takes -HelperPipe, as $helperAware says it does')
        } else {
            Note $false ($name + ' exists') ('not at ' + $sp)
        }
    }

    # The other direction: anything in gplbld that TAKES -HelperPipe must be in
    # the list, or the runner will never hand it one.
    $takers = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $here -Filter '*.ps1' -File)) {
        if (@(Get-ParamNames $f.FullName) -contains 'HelperPipe') { $takers += $f.Name }
    }
    $takers = @($takers | Sort-Object -Unique)
    Note ($takers.Count -gt 0) 'at least one script takes -HelperPipe' ("count: " + $takers.Count)
    Note ((($takers -join ',') -ceq ($declared -join ','))) `
         'every -HelperPipe taker is in $helperAware and vice versa' `
         ("takers: " + ($takers -join ',') + " / declared: " + ($declared -join ','))

    # ------------------------------- $script:x colliding with a parameter $X
    #
    # ***THE DEFECT b119 ACTUALLY SHIPPED WITH, AND IT COST THREE CONSENTS
    # INSTEAD OF ONE WHILE PASSING EVERY CHECK.***  PowerShell variable names
    # are CASE-INSENSITIVE, so a parameter -HelperPipe and a variable written
    # $script:helperPipe are THE SAME VARIABLE.  verify-doors-suite.ps1 and
    # verify-sdsyswrite.ps1 each bound the runner's pipe and then assigned '' to
    # what looked like a private script variable, wiping the parameter they had
    # just been handed.  Both then started helpers of their own and stopped
    # them, killing the run's consent.
    #
    # ***IT FAILED THE QUIET WAY, WHICH IS WHY A LINT AND NOT A COMMENT.***
    # b119 was GREEN IN BOTH HALVES - 23 of 23 and 25 of 25 - and the only
    # symptom was that the run went on asking for consent.  Nothing in a
    # transcript says "your parameter was overwritten"; the two files that had
    # no such variable adopted correctly, so the split looked inexplicable until
    # the names were compared by hand.
    #
    # THE RULE IS GENERAL AND SWEEPS THE DIRECTORY, because this has nothing to
    # do with elevation: ANY script that assigns to $script:<name> while taking
    # a parameter of the same name (in any casing) is writing to its own
    # parameter and almost certainly does not mean to.  Assigning to the
    # parameter DIRECTLY ($Foo = 'x') is ordinary and is not flagged - it is the
    # scope prefix that creates the false belief that they are separate.
    Write-Output ''
    Write-Output '--- no script assigns $script:<name> over its own parameter $<Name> ---'

    function Get-ScopedParamCollisions([string]$Path) {
        $tt = $null; $ee = $null
        $a = [System.Management.Automation.Language.Parser]::ParseFile($Path, [ref]$tt, [ref]$ee)
        if ($null -eq $a.ParamBlock) { return @() }
        $names = @($a.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
        if ($names.Count -eq 0) { return @() }
        $hits = @()
        foreach ($asn in @($a.FindAll({ param($n)
                    $n -is [System.Management.Automation.Language.AssignmentStatementAst] }, $true))) {
            $lv = $asn.Left
            if ($lv -isnot [System.Management.Automation.Language.VariableExpressionAst]) { continue }
            $vp = $lv.VariablePath
            if (-not ($vp.IsScript -or $vp.IsGlobal)) { continue }
            $bare = $vp.UserPath -replace '^(script|global|local|private):', ''
            foreach ($p in $names) {
                # -eq is case-insensitive, which is the whole point: that is
                # exactly how PowerShell resolves the two to one variable.
                if ($bare -eq $p) {
                    $hits += ('line {0}: ${1} is the same variable as parameter ${2}' -f
                              $lv.Extent.StartLineNumber, $vp.UserPath, $p)
                }
            }
        }
        return @($hits | Sort-Object -Unique)
    }

    $scanned  = 0
    $collided = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $here -Filter '*.ps1' -File)) {
        $scanned++
        foreach ($h in @(Get-ScopedParamCollisions $f.FullName)) {
            $collided += ($f.Name + ' -- ' + $h)
        }
    }
    # REFUSE THE NULL CASE: a scan that parsed nothing would report clean.
    Note ($scanned -gt 20) 'the sweep actually read the directory' ("scanned: " + $scanned)
    Note ($collided.Count -eq 0) 'no gplbld script writes $script:<name> over its own parameter' `
         ($collided -join ' | ')

    # ------------------------------------------- what could not be driven here
    Write-Output ''
    Write-Output '--- the two routes that would raise a real prompt: STATIC ---'
    $t = $null; $e = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile(
               (Join-Path $sandbox 'elevate-once.ps1'), [ref]$t, [ref]$e)
    Note ($e.Count -eq 0) 'elevate-once.ps1 parses with no errors' ("errors: " + $e.Count)

    $fns = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
    Note ($fns.Count -eq 5) 'all five functions are present, so nothing swallowed a body' ("found " + $fns.Count)

    $inv = @($fns | Where-Object { $_.Name -eq 'Invoke-ElevatedScript' })
    $src = if ($inv.Count -eq 1) { $inv[0].Extent.Text } else { '' }
    Note ($src -match '-Verb RunAs') 'the fallback still asks for consent with -Verb RunAs'
    Note ($src -match '-ErrorAction Stop') 'the fallback uses -ErrorAction Stop, so a declined prompt THROWS rather than returning 0'
    Note ($src -match "Route = 'runas'") 'the fallback reports Route = runas'
    Note ($src -match '\$rc -eq 9') 'a helper that died mid-run (exit 9) is handled'
    Note ($src -match "sdElev\.Pipe\s*=\s*''") 'exit 9 clears the pipe so the next step does not retry a dead helper'

    # ***THE PARTITION.***  Every Route this function can return is either driven
    # above or declared unreachable-without-consent here.  A new one cannot
    # appear without failing this row, which is what stops the list rotting.
    $routes = @($src | Select-String -Pattern "Route\s*=\s*'([a-z]+)'" -AllMatches |
                ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
    $driven   = @('helper', 'refused')
    $declared = @('runas')
    $covered  = @($driven + $declared | Sort-Object -Unique)
    Note (($routes -join ',') -ceq ($covered -join ',')) `
         'every Route is either driven live or declared consent-bound' `
         ("routes: " + ($routes -join ',') + " / classified: " + ($covered -join ','))

} finally {
    Remove-Item -LiteralPath $sandbox -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Output ''
Write-Output ("test-elevonce-units: {0} passed, {1} failed" -f $pass, $fail)
if ($fail -gt 0) { exit 1 }
exit 0
