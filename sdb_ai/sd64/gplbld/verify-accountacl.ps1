<#
.SYNOPSIS
    Assert that the ACL CREATE.ACCOUNT puts on a new account directory is the
    SAME one gplbld/secure-account-dirs.ps1 puts on an existing one.
    PROJECT_STATUS.md section 8, "the B work".

.DESCRIPTION
    THE RULE IS DELIBERATELY IN TWO PLACES AND THIS IS THE ONLY GUARD ON IT.
    CREATEA's secure.account.dir builds the icacls line inline and runs it
    through !ps_script; secure-account-dirs.ps1 has the same rule in
    PowerShell.  They cannot share a file - the script installs to {app}, and
    SD exposes no system() key for the program directory (exe_directory()
    exists in C, config_path is the DATA tree) - so the intended guard was
    always a measurement.  CREATEA's own comment promises this file by name.

    WHAT IT MEASURES.  One account directory, three readings of its DACL:

      A  after CREATE.ACCOUNT USER <prefix>      the create-time half
      R  after icacls /reset                     the control
      S  after secure-account-dirs.ps1           the re-apply half

    and asserts A is byte-identical to S.  ONE directory rather than two, so
    the group name, the machine name and the SIDs are the same in both
    readings and equality can be exact instead of normalised.

    R IS WHY THIS TEST MEANS ANYTHING, AND WITHOUT IT THE RUN WOULD BE A LIE.
    Both halves are idempotent.  Running the script over a directory
    CREATE.ACCOUNT has just stamped leaves it exactly as it was - so "A equals
    S" would pass just as readily if the script had done NOTHING AT ALL, or
    were missing, or exited at its first guard.  Knocking the ACL back to
    inherited in between, and asserting that the knock actually landed
    (sdusers is back, inheritance is on again, R differs from A), is what
    makes S evidence of the script having applied the rule.

    AND THE SHAPE IS ASSERTED SEPARATELY, because A equals S would still pass
    if BOTH halves drifted the same way.  The three ACEs are checked against
    the rule as section 8 states it, by SID rather than by name - the scripts
    use SIDs precisely because BUILTIN\Administrators and NT AUTHORITY\SYSTEM
    are renamed on a localised Windows, and a test that compared names would
    be the one thing in this pair that could not run there.

    THE THIRD SUBJECT IS THE GUARD AGAINST A MASS-STAMP.  secure-account-dirs
    refuses to stamp a directory with no voc in it, and one whose sdu_ group
    does not exist; its header calls stamping every account on the machine to
    a group nobody can be in "the one failure this must not have".  Both
    refusals are exercised here with -WhatIf, which reaches them - the two
    guards run BEFORE the -WhatIf branch - while touching no ACL at all.

.PARAMETER Prefix
    Name for the throwaway Windows and SD account.  Use one nobody has used:
    CREATE.ACCOUNT refuses a name it has seen, which is the right way round.

.PARAMETER Keep
    Leave the account and its two scratch directories in place for poking at.
    They still have to be removed by hand afterwards.

.EXAMPLE
    C:\Users\dmont\Projects\sd4windows\sdb_ai\sd64\gplbld\verify-accountacl.ps1 -Prefix sdacl2
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)] [string] $Prefix,
    [switch] $Keep
)

$ErrorActionPreference = 'Stop'

$Gplbld = Split-Path -Parent $MyInvocation.MyCommand.Path
$sdExe  = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$Root   = Join-Path $env:ProgramData 'SD\user_accounts'

# icacls (F) and (M) as the masks they actually set.  Numeric rather than the
# FileSystemRights enum names, because (M) prints as "Modify, Synchronize" and
# the order of that list is not something to hang a test on.
$RIGHTS_F = 2032127   # 0x1F01FF  FullControl
$RIGHTS_M = 1245631   # 0x1301BF  Modify, Synchronize
$INHERIT_OICI = 3     # ContainerInherit + ObjectInherit

# NOT UNDER C:\ProgramData\SD - the tree cycle.ps1 deletes.  LOCALAPPDATA is
# the same directory elevated or not, so the unelevated session that asked for
# this run can read the transcript back.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$log = Join-Path $logDir ('verify-accountacl-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $log -Force | Out-Null } catch { }
Write-Host "transcript: $log"

$results = New-Object System.Collections.ArrayList
$failed  = $false

function Note($check, $expected, $got) {
    $pass = ($expected -eq $got)
    if (-not $pass) { $script:failed = $true }
    $null = $results.Add([pscustomobject]@{ Check = $check; Expected = $expected; Observed = $got })
    Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
        $(if ($pass) { 'PASS' } else { 'FAIL' }), $check, $expected, $got)
}

function Fail($msg) {
    Write-Host ''
    Write-Host "STOPPED: $msg" -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

function Step($n, $msg) { Write-Host ''; Write-Host "== [$n] $msg" -ForegroundColor Cyan }

# THE DACL ALONE, IN SDDL.  Owner and group are not what either half writes,
# and including them would make this fail on an unrelated difference.
function Get-Dacl([string]$path) {
    return (Get-Acl -LiteralPath $path).GetSecurityDescriptorSddlForm('Access')
}

# For the transcript.  SDDL is the assertion; this is what a person reads when
# the assertion fails, and without it a failure says only that two opaque
# strings differ.
function Show-Acl([string]$label, [string]$path) {
    Write-Host "   --- $label ---"
    $acl = Get-Acl -LiteralPath $path
    Write-Host ("   protected (inheritance off): " + $acl.AreAccessRulesProtected)
    foreach ($r in $acl.Access) {
        Write-Host ("   {0,-34} {1,-10} {2,-28} {3}" -f
            $r.IdentityReference, $r.AccessControlType, $r.FileSystemRights, $r.InheritanceFlags)
    }
}

# The installed sysmsg(N) as a REGEX, with each %1/%2 replaced by ".*" and
# every literal run escaped.  Read rather than hard-coded, because a check that
# quotes the words in this file goes blind the day somebody rewords the
# message, and goes blind in the passing direction.
#
# 20 Aug 26 - THIS TOOK THE TEXT BEFORE THE FIRST "%" UNTIL TODAY, AND IT ONLY
# EVER WORKED HERE BY ACCIDENT.  10055 is "Could not secure account directory
# %1 (%2)", which begins with literal text, so the head was usable.
# verify-rdpaccount.ps1 copied the function and reads six messages that all
# START with %1 - the head was the empty string for every one of them, and all
# six checks reported FAIL on a run where the feature worked perfectly.  Fixed
# here too rather than left as a working accident.  (That script went with
# RDPACCOUNT on 21 Aug 2026; verify-routes.ps1 replaced it and carries the
# fixed version of this function and the note.)
function Get-SysMsgPattern([int]$n) {
    $f = Join-Path $env:ProgramData ('SD\sdsys\messages\' + $n)
    if (-not (Test-Path -LiteralPath $f)) { return '' }
    $t = ((Get-Content -LiteralPath $f -Raw)).Trim()
    if ($t -eq '') { return '' }
    $parts = [regex]::Split($t, '%\d')
    return (($parts | ForEach-Object { [regex]::Escape($_) }) -join '.*')
}

# An identity that cannot be resolved to a SID must not abort the run - it is
# a finding, not a crash, and under $ErrorActionPreference = 'Stop' a throw
# inside Where-Object would take the whole verifier with it.
function Get-Sid($identityReference) {
    try { return $identityReference.Translate([Security.Principal.SecurityIdentifier]).Value }
    catch { return '<unresolvable>' }
}

# Drives an SD session from SDSYS.  Same shape as verify-scramlogin.ps1: a
# blank first line absorbs the BOM the pipe prepends, TERM stops it
# paginating, OFF ends it.  PROJECT_STATUS.md section 6 has both traps.
function Invoke-SD([string[]]$commands) {
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
}

# ---------------------------------------------------------------------------
# Refusals.  Everything here happens before anything is created.

if (-not $Prefix) {
    Write-Host 'verify-accountacl: -Prefix is required, and must be a name nobody has used.'
    Write-Host '  PROJECT_STATUS.md names the next free one.  Example: -Prefix sdacl2'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

# A caller that splats its arguments wrongly delivers "-Prefix sdacl2" as the
# VALUE of -Prefix, and the run then fails several steps later looking like
# something else entirely.  post-cycle-elevated.ps1's header has that
# measurement; this is the guard it earned.
if ($Prefix -notmatch '^[a-z][a-z0-9_]*$') {
    Fail ("-Prefix is '$Prefix'.  Lower case letters, digits and underscore only, " +
          'starting with a letter - CREATEA downcases the name and the directory ' +
          'takes it verbatim, so a mixed-case prefix would not match the group.')
}

$id = [Security.Principal.WindowsIdentity]::GetCurrent()
$pr = New-Object Security.Principal.WindowsPrincipal($id)
if (-not $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    # CREATE_USER needs an elevated token, and so does icacls on the data tree.
    # Unelevated, CREATE.ACCOUNT stops with "Create User Failed, OS Error: 5".
    Fail 'this needs an ELEVATED PowerShell.'
}

# REFUSE A STALE TREE BEFORE DOING ANYTHING.  CLAUDE.md requires a test cycle
# to begin with a fresh install; assert-current.ps1 is what makes that
# enforceable rather than remembered.
& (Join-Path $Gplbld 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) { Fail 'the installed tree does not match source - see above' }

if (-not (Test-Path -LiteralPath $sdExe))  { Fail "no $sdExe" }
if (-not (Test-Path -LiteralPath $Root))   { Fail "no $Root" }
$script  = Join-Path $Gplbld 'secure-account-dirs.ps1'
if (-not (Test-Path -LiteralPath $script)) { Fail "no $script" }

$acctDir = Join-Path $Root $Prefix
$noVoc   = Join-Path $Root ($Prefix + 'nv')     # a directory with no voc
$noGroup = Join-Path $Root ($Prefix + 'ng')     # a voc, but no sdu_ group
$accRec  = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Prefix.ToUpper())

if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
    Fail "$Prefix already exists as a Windows account - use a fresh -Prefix."
}
if (Test-Path -LiteralPath $acctDir) { Fail "$acctDir already exists - use a fresh -Prefix." }
if (Test-Path -LiteralPath $accRec)  {
    Fail ($Prefix.ToUpper() + ' is still in the ACCOUNTS register from an earlier run.' +
          '  Remove it with DELETE.ACCOUNT, or use a fresh -Prefix.')
}
foreach ($d in @($noVoc, $noGroup)) {
    if (Test-Path -LiteralPath $d) { Fail "$d is left over from an earlier run - remove it." }
}

$made = $false

try {
    # -----------------------------------------------------------------------
    Step 1 "Creating the throwaway account $Prefix"

    # NO NO.QUERY: CREATE.ACCOUNT USER makes a Windows account too and refuses
    # outright without a prompt.  The password is Windows' and is never used
    # again by this script - nothing here logs in.
    Add-Type -AssemblyName System.Web
    $winPw = [System.Web.Security.Membership]::GeneratePassword(24, 6)

    $out = Invoke-SD @("CREATE.ACCOUNT USER $Prefix BOTH", $winPw, $winPw)
    Note 'accounts record created' $true (Test-Path -LiteralPath $accRec)
    if (-not (Test-Path -LiteralPath $accRec)) { Write-Host $out; Fail 'CREATE.ACCOUNT did not register the account.' }
    $made = $true

    Note 'account directory created' $true (Test-Path -LiteralPath $acctDir)
    if (-not (Test-Path -LiteralPath $acctDir)) { Write-Host $out; Fail 'CREATE.ACCOUNT made no directory.' }

    # message 10055 is secure.account.dir's ONLY failure report.  Its absence
    # is the claim that the stamp went through; without this a !ps_script that
    # failed would show up only as a wrong ACL further down, and would read as
    # the two halves having drifted rather than as one of them refusing.
    $m10055 = Get-SysMsgPattern 10055
    if ($m10055 -eq '') {
        Note 'message 10055 is installed' $true $false
    } else {
        Note 'no message 10055 (could not secure)' $false ($out -match $m10055)
    }

    $group = 'sdu_' + $Prefix
    Note "group $group exists" $true ([bool](Get-LocalGroup -Name $group -ErrorAction SilentlyContinue))
    $groupSid = (Get-LocalGroup -Name $group -ErrorAction SilentlyContinue).SID.Value

    # -----------------------------------------------------------------------
    Step 2 'A - the ACL CREATE.ACCOUNT left'

    $A = Get-Dacl $acctDir
    Show-Acl 'A' $acctDir
    Write-Host "   SDDL: $A"

    $aclA = Get-Acl -LiteralPath $acctDir
    Note 'A: inheritance is off'    $true  $aclA.AreAccessRulesProtected
    Note 'A: three ACEs, no more'   3      @($aclA.Access).Count
    Note 'A: sdusers is gone'       $false ([bool](@($aclA.Access | Where-Object {
        $_.IdentityReference.Value -like '*\sdusers' }).Count))

    # BY SID, NOT BY NAME.  Both halves grant *S-1-5-18 and *S-1-5-32-544
    # rather than SYSTEM and BUILTIN\Administrators because those two are
    # renamed on a localised Windows; a test written against the names would
    # be the one part of this pair that could not run there.
    function Test-Ace($sid, $rights, $label) {
        $hit = @($aclA.Access | Where-Object {
            (Get-Sid $_.IdentityReference) -eq $sid -and
            [int]$_.FileSystemRights -eq $rights -and
            [int]$_.InheritanceFlags -eq $INHERIT_OICI -and
            [int]$_.PropagationFlags -eq 0 -and
            $_.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow
        }).Count
        Note ('A: ' + $label) 1 $hit
    }
    Test-Ace 'S-1-5-18'      $RIGHTS_F 'SYSTEM (OI)(CI)(F)'
    Test-Ace 'S-1-5-32-544'  $RIGHTS_F 'Administrators (OI)(CI)(F)'
    if ($groupSid) { Test-Ace $groupSid $RIGHTS_M ($group + ' (OI)(CI)(M)') }

    # (OI)(CI) is a claim about children, so read one.  voc is what
    # CREATE.ACCOUNT always makes and what secure-account-dirs uses as its
    # definition of an account directory.
    $vocPath = Join-Path $acctDir 'voc'
    if (Test-Path -LiteralPath $vocPath) {
        $vocAcl = Get-Acl -LiteralPath $vocPath
        Note 'A: voc inherits the group' $true ([bool](@($vocAcl.Access | Where-Object {
            $_.IsInherited -and $_.IdentityReference.Value -like ('*\' + $group) }).Count))
        Note 'A: voc does not inherit sdusers' $false ([bool](@($vocAcl.Access | Where-Object {
            $_.IdentityReference.Value -like '*\sdusers' }).Count))
    } else {
        Note 'A: voc exists to read' $true $false
    }

    # -----------------------------------------------------------------------
    Step 3 'R - the control: knock the ACL back to inherited'

    # WITHOUT THIS STEP THE WHOLE TEST PASSES VACUOUSLY.  Both halves are
    # idempotent, so running the script over a directory CREATE.ACCOUNT just
    # stamped leaves it identical whether the script did the work or did
    # nothing.  /reset drops the explicit ACEs and lets the container's
    # inheritable ACEs apply again.
    $null = & icacls.exe $acctDir /reset
    if ($LASTEXITCODE -ne 0) { Fail "icacls /reset exited $LASTEXITCODE - the control could not be set up" }

    $R = Get-Dacl $acctDir
    Show-Acl 'R' $acctDir
    $aclR = Get-Acl -LiteralPath $acctDir

    Note 'R: differs from A'          $true  ($R -cne $A)
    Note 'R: inheritance is back on'  $false $aclR.AreAccessRulesProtected

    # THE THIRD ASSERTION USED TO BE "sdusers is back" AND IT WAS WRONG - it
    # failed on the 15:09:33 install while the control was working perfectly.
    # Section 8's 18 Aug measurement of user_accounts predates
    # secure-accounts.ps1 being applied to the container, and that script
    # grants sdusers as (RD,AD,X,RA,S) with NO (OI)(CI) - deliberately not
    # inheritable - so sdusers CANNOT appear on a child directory and "back"
    # was never a state this could reach.  Measured after the reset: the
    # inherited set is CREATOR OWNER (materialised as the creating user),
    # BUILTIN\Administrators and NT AUTHORITY\SYSTEM.
    #
    # WHAT THE CONTROL ACTUALLY NEEDS TO SAY is that the thing the stamp ADDED
    # is gone, which is the account's own group.  That is what makes the third
    # reading evidence of the script's work rather than of nothing having
    # happened, and unlike sdusers it is true by construction.
    Note 'R: the account group is gone' $false ([bool](@($aclR.Access | Where-Object {
        $_.IdentityReference.Value -like ('*\' + $group) }).Count))

    # -----------------------------------------------------------------------
    Step 4 'S - what secure-account-dirs.ps1 makes of it'

    & $script -Root $Root -Account $Prefix
    $rc = $LASTEXITCODE
    Note 'secure-account-dirs exit code' 0 $rc

    $S = Get-Dacl $acctDir
    Show-Acl 'S' $acctDir
    Write-Host "   SDDL: $S"

    # -----------------------------------------------------------------------
    Step 5 'THE QUESTION: are the two halves the same rule?'

    Note 'S is byte-identical to A' $true ($S -ceq $A)
    if ($S -cne $A) {
        Write-Host ''
        Write-Host '   THE TWO HALVES HAVE DRIFTED.' -ForegroundColor Red
        Write-Host "   CREATE.ACCOUNT (CREATEA secure.account.dir):  $A"
        Write-Host "   secure-account-dirs.ps1:                      $S"
        Write-Host ''
        # Whether it is an ordering difference or a different set of ACEs is
        # the first thing the reader wants, and reading it out of two SDDL
        # strings by eye is exactly the sort of work that gets got wrong.
        $sortA = (($A -replace '^D:[A-Z]*', '') -split '(?<=\))(?=\()' | Sort-Object) -join ''
        $sortS = (($S -replace '^D:[A-Z]*', '') -split '(?<=\))(?=\()' | Sort-Object) -join ''
        if ($sortA -ceq $sortS) {
            Write-Host '   Same ACEs in a DIFFERENT ORDER - the two halves grant in different sequence.'
        } else {
            Write-Host '   DIFFERENT ACEs - this is a real difference in the rule, not an ordering one.'
        }
    }

    # -----------------------------------------------------------------------
    Step 6 'The guard against a mass-stamp'

    # secure-account-dirs.ps1's header: locking every account on the machine
    # to a group nobody can be in is "the one failure this must not have".
    # Two directories that must be REFUSED, and the real account beside them
    # as the control - without it "skipped everything" would pass this step.
    #
    # -WhatIf REACHES BOTH GUARDS AND CHANGES NOTHING.  Test-LooksLikeAccount
    # and the net localgroup check both run before the -WhatIf branch, so this
    # is a full exercise of them; and a sweep of the whole root with -WhatIf
    # cannot touch don's directory or anybody else's.
    $null = New-Item -ItemType Directory -Path $noVoc -Force
    $null = New-Item -ItemType Directory -Path $noGroup -Force
    Set-Content -LiteralPath (Join-Path $noGroup 'voc') -Value 'not a real voc' -Encoding ascii

    $sweep = & $script -Root $Root -WhatIf
    $sweepText = ($sweep | Out-String)
    Write-Host $sweepText

    Note 'no voc      -> skipped' $true ($sweepText -match ([regex]::Escape('skipped ' + $Prefix + 'nv') + '.*no voc'))
    Note 'no group    -> skipped' $true ($sweepText -match ([regex]::Escape('skipped ' + $Prefix + 'ng') + '.*does not exist'))
    Note 'real account-> stamped' $true ($sweepText -match ([regex]::Escape('would stamp ' + $Prefix) + '\s'))
    # And -WhatIf really did leave the ACL alone, which is what made the sweep
    # safe to run across every account on the machine.
    Note '-WhatIf changed nothing' $true ((Get-Dacl $acctDir) -ceq $S)
}
catch {
    # 20 Aug 26 - WITHOUT THIS THE FIRST RUN PRODUCED NO VERDICT AT ALL.  The
    # sweep in step 6 threw (secure-account-dirs.ps1's net.exe redirection,
    # fixed the same day), the finally cleaned up, and the exception then
    # propagated past the summary and the exit code - so the run ended with a
    # stack trace and no statement about any of the checks that HAD passed.
    # A verifier that cannot say what it measured is worth very little.
    $script:failed = $true
    Write-Host ''
    Write-Host ('verify-accountacl: THREW - ' + $_.Exception.Message) -ForegroundColor Red
    Write-Host $_.ScriptStackTrace
    $null = $results.Add([pscustomobject]@{
        Check = 'the run completed without throwing'; Expected = $true; Observed = $false })
}
finally {
    if (-not $Keep) {
        Step 7 'Putting the system back'

        foreach ($d in @($noVoc, $noGroup)) {
            if (Test-Path -LiteralPath $d) {
                Remove-Item -LiteralPath $d -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "   removed $d"
            }
        }

        if ($made) {
            if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
                Remove-LocalUser -Name $Prefix
                Write-Host "   removed Windows account $Prefix"
            }
            if (Test-Path -LiteralPath $acctDir) {
                Remove-Item -LiteralPath $acctDir -Recurse -Force -ErrorAction SilentlyContinue
                Write-Host "   removed $acctDir"
            }
            $g = 'sdu_' + $Prefix
            if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) {
                Remove-LocalGroup -Name $g
                Write-Host "   removed group $g"
            }
            if (Test-Path -LiteralPath (Join-Path $env:SystemDrive ('Users\' + $Prefix))) {
                Remove-Item -LiteralPath (Join-Path $env:SystemDrive ('Users\' + $Prefix)) `
                            -Recurse -Force -ErrorAction SilentlyContinue
            }
            # The SD half is left deliberately, as verify-scramlogin.ps1 and
            # verify-apiport.ps1 leave theirs: removing the register record
            # here would hide a CREATE.ACCOUNT that had half failed.
            Write-Host '   ACCOUNTS record left in place - remove with DELETE.ACCOUNT'
        }
    } else {
        Write-Host ''
        Write-Host "-Keep: $Prefix, $noVoc and $noGroup are all still there." -ForegroundColor Yellow
    }
}

# ---------------------------------------------------------------------------
Write-Host ''
Write-Host '=== Summary ============================================================='
$results | Format-Table Check, Expected, Observed -AutoSize | Out-String | Write-Host

$passed = @($results | Where-Object { $_.Expected -eq $_.Observed }).Count
$total  = @($results).Count
Write-Host ("$passed/$total checks passed")

if ($failed) {
    Write-Host ''
    Write-Host 'verify-accountacl: FAILED' -ForegroundColor Red
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

Write-Host ''
Write-Host 'verify-accountacl: the two halves of the rule agree.' -ForegroundColor Green
try { Stop-Transcript | Out-Null } catch { }
exit 0
