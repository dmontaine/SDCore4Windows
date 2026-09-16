<#
.SYNOPSIS
    Witnesses the five uninstall outcomes RELEASE_1.1 38 and 50 turn on.

.DESCRIPTION
    Every one of those witnesses is an INTERACTIVE uninstall - UninstallSilent
    is what suppresses the prompts, so the thing under test cannot be reached
    without a person pressing a button.  What a person cannot do reliably is
    say afterwards what the machine now looks like, which is this script's job:
    it snapshots the state BEFORE the uninstall, judges the state AFTER it
    against the combination that was chosen, and prints both.

    The five cases, and the entry each one closes:

      silentkeep       /VERYSILENT               38 - removes NEITHER
      keepdb-delconf   Keep db,  Delete config   38 - separable, one way
      deldb-keepconf   Delete db, Keep config    38 - separable, the other way
      deldb-delacct    Delete both, Delete accts 50 - the sweep really sweeps
      treeabsent       tree gone first           50 - second instance

    THE PRECONDITION IS CHECKED, NOT ASSUMED, AND IT IS WHERE THESE GO WRONG.
    Checking "sd.conf is absent afterwards" proves nothing if it was absent
    before, and "the accounts are gone" proves nothing on a machine whose
    sdusers holds only the installing user, whom -Keep excludes by
    construction.  Each case therefore declares what the BEFORE state must
    look like for the AFTER state to mean anything, and -Check exits 2 rather
    than scoring a vacuous pass when it does not hold.

    AND THE UNINSTALLER ITSELF IS DATED.  An uninstall run from a binary older
    than gplbld\sd.iss is a measurement of the previous build; -Snapshot
    refuses it.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File verify-uninstallchoices.ps1 -List
    powershell -ExecutionPolicy Bypass -File verify-uninstallchoices.ps1 -Snapshot -Case treeabsent
    powershell -ExecutionPolicy Bypass -File verify-uninstallchoices.ps1 -Check treeabsent -Saw yes
#>

# Exit 0 every decisive check passed, 1 a decisive check failed, 2 the test
# could not be run.

[CmdletBinding()]
param(
    [switch] $List,
    [switch] $Make,
    [switch] $Snapshot,
    [ValidateSet('silentkeep', 'keepdb-delconf', 'deldb-keepconf', 'deldb-delacct', 'treeabsent', '')]
    [string] $Case = '',
    [ValidateSet('silentkeep', 'keepdb-delconf', 'deldb-keepconf', 'deldb-delacct', 'treeabsent', '')]
    [string] $Check = '',
    [ValidateSet('yes', 'no', '')]
    [string] $Saw = '',
    [string] $Prefix = ''
)

$ErrorActionPreference = 'Stop'

$Gplbld   = Split-Path -Parent $MyInvocation.MyCommand.Path
$IssPath  = Join-Path $Gplbld 'sd.iss'
$SdExe    = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$AcctsDir = Join-Path $env:ProgramData 'SD\sdsys\accounts'
$DataPath = Join-Path $env:ProgramData 'SD'
$ProgPath = Join-Path $env:ProgramFiles 'SD'
$UninsExe = Join-Path $ProgPath 'unins000.exe'

$StateDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $StateDir)) { $null = New-Item -ItemType Directory -Path $StateDir -Force }

function Fail($msg)   { Write-Host ''; Write-Host "FAILED: $msg" -ForegroundColor Red;    exit 1 }
function Refuse($msg) { Write-Host ''; Write-Host "COULD NOT RUN: $msg" -ForegroundColor Yellow; exit 2 }
function Step($msg)   { Write-Host ''; Write-Host "== $msg" -ForegroundColor Cyan }

# ---------------------------------------------------------------------------
# THE STATE.  Everything the five cases judge, read in one place so that
# -Snapshot and -Check cannot drift apart in what they mean by "the state".
function Get-SdState {
    $treePresent = Test-Path -LiteralPath $DataPath -PathType Container
    $entries = @()
    if ($treePresent) {
        $entries = @(Get-ChildItem -LiteralPath $DataPath -Force |
                     ForEach-Object { $_.Name } | Sort-Object)
    }

    $sdusersMembers = @()
    $sdusersPresent = $false
    if (Get-LocalGroup -Name 'sdusers' -ErrorAction SilentlyContinue) {
        $sdusersPresent = $true
        try {
            $sdusersMembers = @(Get-LocalGroupMember -Group 'sdusers' -ErrorAction Stop |
                                ForEach-Object { ($_.Name -split '\\')[-1] } | Sort-Object)
        } catch { $sdusersMembers = @() }
    }

    $routeGroups = @()
    foreach ($g in @('sdapi', 'sdssh', 'sdsshonly')) {
        if (Get-LocalGroup -Name $g -ErrorAction SilentlyContinue) { $routeGroups += $g }
    }

    $uninsWrite = ''
    if (Test-Path -LiteralPath $UninsExe) {
        $uninsWrite = (Get-Item -LiteralPath $UninsExe).LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
    }

    return [pscustomobject]@{
        Taken          = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
        TreePresent    = $treePresent
        TreeEntries    = $entries
        ConfPresent    = (Test-Path -LiteralPath (Join-Path $DataPath 'sd.conf'))
        SdsysPresent   = (Test-Path -LiteralPath (Join-Path $DataPath 'sdsys') -PathType Container)
        ProgramPresent = (Test-Path -LiteralPath $ProgPath -PathType Container)
        UninsPresent   = (Test-Path -LiteralPath $UninsExe)
        UninsWrite     = $uninsWrite
        SdusersPresent = $sdusersPresent
        SdusersMembers = $sdusersMembers
        RouteGroups    = $routeGroups
        LocalUsers     = @(Get-LocalUser | ForEach-Object { $_.Name } | Sort-Object)
    }
}

function Show-State($label, $s) {
    Write-Host "  $label ($($s.Taken))"
    Write-Host "    data tree present : $($s.TreePresent)"
    Write-Host "    tree entries      : $(if ($s.TreeEntries.Count) { $s.TreeEntries -join ', ' } else { '<none>' })"
    Write-Host "    sd.conf present   : $($s.ConfPresent)"
    Write-Host "    sdsys present     : $($s.SdsysPresent)"
    Write-Host "    program dir       : $($s.ProgramPresent)   unins000.exe: $($s.UninsPresent) $($s.UninsWrite)"
    Write-Host "    sdusers           : $($s.SdusersPresent)   members: $(if ($s.SdusersMembers.Count) { $s.SdusersMembers -join ', ' } else { '<none>' })"
    Write-Host "    route groups      : $(if ($s.RouteGroups.Count) { $s.RouteGroups -join ', ' } else { '<none>' })"
}

# ---------------------------------------------------------------------------
# THE PRECONDITION.  Returns '' when the case can be measured from this BEFORE
# state, or the reason it cannot.  Separate from the verdict so that a test can
# drive both without a machine in either state.
function Get-CasePrecondition($case, $before, $prefix) {
    if (-not $before) { return 'there is no -Snapshot for this case; take one BEFORE the uninstall.' }
    if (-not $before.UninsPresent) {
        return 'the snapshot shows no unins000.exe, so no uninstall could have been run from it.'
    }
    # EVERY CASE NOW JUDGES THE THREE ROUTE GROUPS, so every case needs them
    # present beforehand - "they survived" and "they were removed" are both
    # unobservable against a machine that had none.
    if ($before.RouteGroups.Count -eq 0) {
        return 'the route groups (sdapi, sdssh, sdsshonly) were already absent, so neither their removal nor their survival could be observed.'
    }

    switch ($case) {
        'silentkeep' {
            if (-not $before.TreePresent) { return 'the data tree was already absent, so "it survives" could not distinguish anything.' }
            if (-not $before.ConfPresent) { return 'sd.conf was already absent, so "it survives" could not distinguish anything.' }
            return ''
        }
        'keepdb-delconf' {
            if (-not $before.TreePresent) { return 'the data tree was already absent - there was no database to keep.' }
            if (-not $before.ConfPresent) { return 'sd.conf was already absent, so its absence afterwards proves nothing.' }
            return ''
        }
        'deldb-keepconf' {
            if (-not $before.TreePresent) { return 'the data tree was already absent - there was no database to delete.' }
            if (-not $before.ConfPresent) { return 'sd.conf was already absent, so "it survived" could not be observed.' }
            if (-not $before.SdsysPresent) { return 'sdsys was already absent, so its removal could not be observed.' }
            return ''
        }
        'deldb-delacct' {
            if (-not $prefix) { return 'pass -Prefix <name>, naming the SD-created account this case must remove.' }
            if (-not $before.TreePresent) { return 'the data tree was already absent - this case is the tree-PRESENT path.' }
            if (-not $before.SdusersPresent) { return 'sdusers was already gone, so the sweep had no candidate set and 50 could not be reached.' }
            if ($before.LocalUsers -notcontains $prefix) { return "$prefix is not a local Windows account - run -Make first." }
            if ($before.SdusersMembers -notcontains $prefix) { return "$prefix is not in sdusers, so the sweep would never have considered it." }
            if ($before.SdusersMembers.Count -lt 2) {
                return 'sdusers holds one member only - the installing user is excluded by -Keep, so nothing could ever be removed and a pass would be vacuous.'
            }
            return ''
        }
        'treeabsent' {
            if ($before.TreePresent) { return 'the data tree was still present - this case needs it DELETED before the uninstall, or the tree-absent branch is never entered.' }
            if (-not $before.SdusersPresent) { return 'sdusers was already gone, so "the branch ran to the end" could not be observed.' }
            if (-not $before.ProgramPresent) { return 'SD was not installed, so there was no uninstaller to run.' }
            return ''
        }
    }
    return "unknown case '$case'."
}

# ---------------------------------------------------------------------------
# THE VERDICT.  Pure: a BEFORE state, an AFTER state and the operator's answer
# in, a list of rows out.  A test drives this on fixtures; nothing here reads
# the machine.
function Get-UninstallVerdict($case, $before, $after, $saw, $prefix) {
    $rows = New-Object System.Collections.ArrayList
    function Row($rows, $check, $expected, $got) {
        $null = $rows.Add([pscustomobject]@{
            Check = $check; Expected = "$expected"; Observed = "$got"; Pass = ("$expected" -eq "$got") })
    }

    # EVERY CASE ASSERTS THE UNINSTALL ACTUALLY RAN.  Without this row a script
    # that was never started scores whatever the before state happened to be.
    Row $rows 'the uninstall ran (program directory gone)' $false $after.ProgramPresent

    # THE THREE ROUTE GROUPS SPLIT ON SILENCE, AND THIS ROW HAD IT BACKWARDS
    # ON ITS FIRST RUN - 16 Sep 2026, silentkeep 5 of 6, the one red being the
    # instrument rather than the product.  RemoveSdGroups is CALLED above the
    # UninstallSilent guard in CurUninstallStepChanged, so the call site reads
    # as unconditional; the procedure carries ITS OWN guard (sd.iss:5158),
    # which is the owner's ruling of 2 Sep 2026 and states the cost out loud:
    # "a scripted unattended uninstall still leaves the three groups".  The
    # reason is that removing sdsshonly hands every KEPT account the console
    # and Remote Desktop back, and the removal is tied to the closing page
    # that discloses it - a page that only renders interactively.
    #
    # SO THE ROW STAYS AND IS INVERTED, because it now pins that ruling: a
    # change that starts removing them silently goes red here rather than
    # silently changing who can sign in to the machine.
    if ($case -eq 'silentkeep') {
        Row $rows 'route groups SURVIVE a silent uninstall' $before.RouteGroups.Count $after.RouteGroups.Count
    } else {
        Row $rows 'route groups removed (interactive)' 0 $after.RouteGroups.Count
    }

    switch ($case) {
        'silentkeep' {
            Row $rows 'data tree survives'          $true  $after.TreePresent
            Row $rows 'sd.conf survives'            $true  $after.ConfPresent
            Row $rows 'sdsys survives'              $true  $after.SdsysPresent
            Row $rows 'sdusers survives'            $true  $after.SdusersPresent
        }
        'keepdb-delconf' {
            Row $rows 'data tree survives'          $true  $after.TreePresent
            Row $rows 'sdsys survives'              $true  $after.SdsysPresent
            Row $rows 'sd.conf removed'             $false $after.ConfPresent
            Row $rows 'sdusers survives (db kept)'  $true  $after.SdusersPresent
        }
        'deldb-keepconf' {
            Row $rows 'data tree folder survives'   $true  $after.TreePresent
            Row $rows 'sd.conf survives'            $true  $after.ConfPresent
            Row $rows 'sdsys removed'               $false $after.SdsysPresent
            Row $rows 'folder holds sd.conf ALONE'  'sd.conf' ($after.TreeEntries -join ', ')
            Row $rows 'sdusers removed (db gone)'   $false $after.SdusersPresent
        }
        'deldb-delacct' {
            Row $rows 'data tree removed'           $false $after.TreePresent
            Row $rows 'sdusers removed'             $false $after.SdusersPresent
            Row $rows "$prefix removed from Windows" $false ($after.LocalUsers -contains $prefix)
            # THE CONTROL.  A sweep that removed everything would also pass the
            # row above, and that is the failure mode the -Keep rule exists to
            # prevent, so the installing user is asserted present.
            $installer = $env:USERNAME
            Row $rows "$installer KEPT (the -Keep control)" $true ($after.LocalUsers -contains $installer)
        }
        'treeabsent' {
            # THE OBSERVATION THAT DECIDES IT IS THE OPERATOR'S, and it is
            # required rather than inferred - before the fix this branch showed
            # no dialog at all, and no state afterwards distinguishes "asked and
            # answered Keep" from "never asked".
            Row $rows 'accounts question was OFFERED' 'yes' $saw
            Row $rows 'sdusers removed (branch ran to the end)' $false $after.SdusersPresent
        }
    }
    return $rows
}

function Get-StatePath($case) { Join-Path $StateDir ("uninstallchoices-" + $case + ".json") }

# ---------------------------------------------------------------------------
if ($List) {
    Write-Host ''
    Write-Host 'THE ORDER MATTERS AND IT IS NOT THE OBVIOUS ONE.' -ForegroundColor Cyan
    Write-Host 'Any uninstall that DELETES the database also deletes sdusers, and sdusers'
    Write-Host 'is the only candidate set the accounts sweep has - so deldb-delacct must'
    Write-Host 'come before deldb-keepconf, and the throwaway account must be made while'
    Write-Host 'a database still exists to make it in.'
    Write-Host ''
    Write-Host '  1  -Make -Prefix sdw50a     make the SD account (elevated, SD running)'
    Write-Host '  2  silentkeep               /VERYSILENT uninstall, nothing removed'
    Write-Host '  3  keepdb-delconf           interactive: Keep db, Delete config, Keep accounts'
    Write-Host '  4  deldb-delacct            interactive: Delete, Delete, Delete'
    Write-Host '  5  deldb-keepconf           interactive: Delete db, Keep config, Keep accounts'
    Write-Host '  6  treeabsent               delete the tree by hand, then uninstall'
    Write-Host ''
    Write-Host 'Each step is: -Snapshot -Case <name>, then the install/uninstall, then'
    Write-Host '-Check <name>.  A reinstall is needed between every pair.'
    exit 0
}

if ($Make) {
    if (-not $Prefix) { Refuse 'pass -Prefix <name>, e.g. -Prefix sdw50a.' }
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    if (-not (New-Object Security.Principal.WindowsPrincipal($id)).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Refuse 'Run -Make from an ELEVATED PowerShell - it creates a Windows account.'
    }
    if (-not (Test-Path -LiteralPath $SdExe)) { Refuse "no sd.exe at $SdExe - install SD first." }
    if (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue) {
        Refuse "$Prefix already exists as a Windows account.  Use a fresh -Prefix."
    }

    Step "Creating the SD account $Prefix (CREATE.ACCOUNT USER $Prefix PROGRAMMER NONE)"
    Add-Type -AssemblyName System.Web
    $pw = [System.Web.Security.Membership]::GeneratePassword(20, 4) + 'aA1!'
    # NONE: CREATE.ACCOUNT refuses (10082) unless told how the account is
    # reached, and this one needs no route - it exists to be swept away.
    $body = "`n" + ((@('LOGTO SDSYS', 'TERM 200,9999',
                       "CREATE.ACCOUNT USER $Prefix PROGRAMMER NONE", $pw, $pw, 'OFF')) -join "`n") + "`n"
    $out = $body | & $SdExe
    $out = (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
    Write-Host '   --- raw CREATE.ACCOUNT output ---'
    ($out -split "`r?`n") | ForEach-Object { Write-Host ('   | ' + $_) }
    Write-Host '   --- end raw output ---'

    if (-not (Test-Path -LiteralPath (Join-Path $AcctsDir $Prefix.ToUpper()))) {
        Refuse "CREATE.ACCOUNT did not register $Prefix - see the output above."
    }
    if (-not (Get-LocalUser -Name $Prefix -ErrorAction SilentlyContinue)) {
        Refuse "$Prefix was registered in SD but no Windows account was made, so the sweep would have nothing to remove."
    }
    $mem = @(Get-LocalGroupMember -Group 'sdusers' | ForEach-Object { ($_.Name -split '\\')[-1] })
    if ($mem -notcontains $Prefix) {
        Refuse "$Prefix is not in sdusers, so the sweep would never consider it - the case would be vacuous."
    }
    Write-Host ''
    Write-Host "$Prefix created: registered in SD, a Windows account, and in sdusers." -ForegroundColor Green
    Write-Host "sdusers now holds: $($mem -join ', ')"
    exit 0
}

if ($Snapshot) {
    if (-not $Case) { Refuse 'pass -Case <name> with -Snapshot.  Run -List for the order.' }
    $s = Get-SdState

    # THE UNINSTALLER MUST POST-DATE THE SOURCE IT IS BEING USED TO TEST.
    if ($s.UninsPresent -and (Test-Path -LiteralPath $IssPath)) {
        $issWrite = (Get-Item -LiteralPath $IssPath).LastWriteTime
        $binWrite = (Get-Item -LiteralPath $UninsExe).LastWriteTime
        Write-Host "  sd.iss       : $($issWrite.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-Host "  unins000.exe : $($binWrite.ToString('yyyy-MM-dd HH:mm:ss'))"
        if ($binWrite -lt $issWrite) {
            Refuse 'unins000.exe is OLDER than gplbld\sd.iss - it was built before the fix under test.  Run cycle.ps1.'
        }
    }

    Step "Snapshot BEFORE the '$Case' uninstall"
    Show-State 'before' $s
    $reason = Get-CasePrecondition $Case $s $Prefix
    if ($reason) { Refuse "the precondition for '$Case' does not hold: $reason" }

    $s | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Get-StatePath $Case) -Encoding UTF8
    Write-Host ''
    Write-Host "precondition holds; snapshot written to $(Get-StatePath $Case)" -ForegroundColor Green
    exit 0
}

if ($Check) {
    $path = Get-StatePath $Check
    if (-not (Test-Path -LiteralPath $path)) {
        Refuse "no snapshot at $path - run -Snapshot -Case $Check BEFORE the uninstall."
    }
    $before = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
    if ($Check -eq 'treeabsent' -and -not $Saw) {
        Refuse 'pass -Saw yes|no: whether the accounts question appeared.  No state afterwards can tell "asked and kept" from "never asked", so it is not inferred.'
    }
    $reason = Get-CasePrecondition $Check $before $Prefix
    if ($reason) { Refuse "the snapshot does not support this case: $reason" }

    $after = Get-SdState
    Step "Judging '$Check'"
    Show-State 'before' $before
    Write-Host ''
    Show-State 'after ' $after

    $rows = Get-UninstallVerdict $Check $before $after $Saw $Prefix
    Write-Host ''
    foreach ($r in $rows) {
        Write-Host ("  [{0}] {1}: expected {2}, got {3}" -f
            $(if ($r.Pass) { 'PASS' } else { 'FAIL' }), $r.Check, $r.Expected, $r.Observed)
    }
    $bad = @($rows | Where-Object { -not $_.Pass })
    Write-Host ''
    Write-Host ("$Check : $($rows.Count - $bad.Count) of $($rows.Count) checks passed")
    if ($bad.Count) { Fail "$($bad.Count) check(s) failed." }
    Write-Host "$Check WITNESSED" -ForegroundColor Green
    exit 0
}

Refuse 'nothing to do - pass -List, -Make, -Snapshot -Case <name>, or -Check <name>.'
