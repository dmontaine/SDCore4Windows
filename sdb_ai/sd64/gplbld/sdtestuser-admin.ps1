# sdtestuser-admin.ps1 - the ELEVATED half: make or remove the test account
#
# PRE_RELEASE_FIXES 59.  Raised by VerifyInstall1.ps1 through
# Start-Process -Verb RunAs, which is where the UAC prompt appears.
#
# WHY A SEPARATE FILE.  CREATE.ACCOUNT and DELETE.ACCOUNT are gated on
# K$ADMINISTRATOR, and VerifyInstall1 MUST STAY UNELEVATED - several of its
# measurements are only valid there, and an elevated parent cannot make an
# ordinary child, because "runas /trustlevel" yields a RESTRICTED token rather
# than this user's own (S4.0.1).  So the parent stays ordinary and raises this.
# The same shape as verify-doors-admin.ps1, which is green.
#
# ***THE PASSWORD ARRIVES AS AN ARGUMENT, AND THAT IS THE REVIEWED CHOICE
# RATHER THAN THE LAZY ONE.***  verify-doors-suite.ps1 does the same, for the
# reason recorded there: the UNELEVATED parent needs the same password
# afterwards to drive ssh, and scraping it out of an elevated child's stdout
# would mean redirecting that output to a file - the one copy nobody deletes.
# Passing it in keeps the value in the parent, where it was made.  A command
# line is visible to this user's own processes; a file on disk outlives them.
#
# IT PRINTS WHAT IT DID.  The instrument rule applies to setup as much as to a
# test: the account name, the verb, and SD's own answer, so a run that created
# nothing cannot be read as a run that created something.  THE PASSWORD IS
# NEVER PRINTED and never logged.

param(
    [Parameter(Mandatory = $true)][ValidateSet('Create', 'Remove')][string]$Action,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Password = '',
    [string]$LogFile = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. (Join-Path $PSScriptRoot 'sdtestuser.ps1')

function Say([string]$m) {
    Write-Output $m
    if ($LogFile -ne '') {
        try { Add-Content -LiteralPath $LogFile -Value $m } catch { }
    }
}

$elevated = ([Security.Principal.WindowsPrincipal](
    [Security.Principal.WindowsIdentity]::GetCurrent())).IsInRole(
    [Security.Principal.WindowsBuiltInRole]::Administrator)

# REFUSE THE NULL CASE.  Unelevated, CREATE.ACCOUNT is refused and this would
# report a failure that looks like SD saying no rather than like the child
# never having been elevated.  The two need telling apart.
if (-not $elevated) {
    Say 'sdtestuser-admin: NOT ELEVATED - refusing. CREATE.ACCOUNT needs K$ADMINISTRATOR.'
    exit 2
}

if ($Action -eq 'Create' -and $Password -eq '') {
    Say 'sdtestuser-admin: Create needs -Password; CREATE.ACCOUNT prompts for it twice.'
    exit 2
}

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path -LiteralPath $sdExe)) {
    Say ('sdtestuser-admin: no sd.exe at ' + $sdExe)
    exit 2
}

if ($Action -eq 'Create') {
    $lines = New-SdTestUserScript -Name $Name -Password $Password
} else {
    $lines = Remove-SdTestUserScript -Name $Name
}

# ***THE BEFORE HALF, TAKEN BEFORE ANYTHING RUNS.***  Without it the check
# after cannot tell "Create made this" from "this was already here", and a
# stale account from an earlier run would score a confident pass while the
# password in the parent's hand did not match it - every ssh leg would then
# fail for a reason nobody would look for here.
$acctRecPre = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Name.ToUpper())
$recBefore  = Test-Path -LiteralPath $acctRecPre
$winBefore  = $false
try { $null = Get-LocalUser -Name $Name -ErrorAction Stop; $winBefore = $true } catch { $winBefore = $false }

# THE NAME IS SINGLE-USE, and this is where that is enforced rather than
# assumed.  An ssh sign-in leaves a profile directory DELETE.ACCOUNT cannot
# remove while its hive is mounted, and Windows then gives a rebuilt account a
# SUFFIXED home - PRE_RELEASE 35/36.  So a Create onto an existing name is
# refused outright instead of being made to work.
if ($Action -eq 'Create' -and ($recBefore -or $winBefore)) {
    Say ('sdtestuser-admin: ' + $Name + ' ALREADY EXISTS (record=' + $recBefore +
         ', windows=' + $winBefore + ').')
    Say '  The name is single-use - an ssh sign-in leaves a profile Windows will not'
    Say '  reuse, so a rebuilt account gets a suffixed home.  Use a fresh -Run token.'
    exit 2
}

Say ('sdtestuser-admin: ' + $Action + ' ' + $Name)
Say ('  sd.exe: ' + $sdExe)
foreach ($l in $lines) {
    if ($Password -ne '' -and $l -ceq $Password) { Say '    <password, redacted>' }
    else { Say ('    ' + $l) }
}

# TERM first, so nothing wraps: a wrapped line is counted twice by anything
# grepping the transcript, which is PRE_RELEASE 40 and cost a wrong verdict.
$body = "`n" + ((@('TERM 200,9999') + $lines + @('OFF')) -join "`n") + "`n"

$work = Join-Path $env:TEMP ('sd-testuser-admin-' + $PID)
if (-not (Test-Path -LiteralPath $work)) { New-Item -ItemType Directory -Path $work | Out-Null }
$si = Join-Path $work 'in.txt'
$so = Join-Path $work 'out.txt'
$se = Join-Path $work 'err.txt'

try {
    [IO.File]::WriteAllText($si, $body)
    $p = Start-Process -FilePath $sdExe -NoNewWindow -Wait -PassThru `
             -RedirectStandardInput $si -RedirectStandardOutput $so -RedirectStandardError $se
    $out = ''
    if (Test-Path $so) { $o = Get-Content $so; if ($null -ne $o) { $out = ($o -join "`n") } }
    $out = ($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '')

    Say '  --- SD said ---'
    foreach ($l in ($out -split "`n")) {
        $t = $l.TrimEnd()
        if ($t -ne '') { Say ('  | ' + $t) }
    }

    # ***CHECK THE ARTEFACT, NOT THE WORDING.***  This first matched SD's output
    # for words like "created", and that was wrong twice over.  Message 6011 is
    # "Account NOT created", so a bare "created" matches the FAILURE; and the
    # success wording guessed at (6055/6056, "User %1 created") is not printed
    # by CREATEA at all - it was invented, which is worse than no anchor.
    #
    # verify-doors-admin.ps1 is the reviewed precedent and it parses nothing:
    # it asks whether the ACCOUNTS record and the Windows user EXIST.  That is
    # also what the instrument rule actually wants - "the state it compared,
    # BEFORE and AFTER" - and it cannot be fooled by an echoed command line.
    $acctRec = Join-Path $env:ProgramData ('SD\sdsys\accounts\' + $Name.ToUpper())
    $recNow  = Test-Path -LiteralPath $acctRec
    $winNow  = $false
    try { $null = Get-LocalUser -Name $Name -ErrorAction Stop; $winNow = $true } catch { $winNow = $false }

    Say ('  ACCOUNTS record ' + $acctRec)
    Say ('    before=' + $recBefore + '  after=' + $recNow)
    Say ('  Windows user ' + $Name)
    Say ('    before=' + $winBefore + '  after=' + $winNow)

    if ($Action -eq 'Create') {
        # BOTH halves, because either alone is a broken account: a record with
        # no Windows user cannot sign in over ssh, and a Windows user with no
        # record cannot be reached or removed by SD (PRE_RELEASE 39).
        if ($recNow -and $winNow) {
            Say 'sdtestuser-admin: Create succeeded - record and Windows user both present.'
            exit 0
        }
        Say 'sdtestuser-admin: Create did NOT succeed - read SD''s lines above.'
        exit 1
    } else {
        if ((-not $recNow) -and (-not $winNow)) {
            Say 'sdtestuser-admin: Remove succeeded - record and Windows user both gone.'
            exit 0
        }
        Say 'sdtestuser-admin: Remove did NOT fully succeed - something is left behind.'
        exit 1
    }
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
}
