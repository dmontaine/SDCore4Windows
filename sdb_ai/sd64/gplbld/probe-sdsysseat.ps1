<#
.SYNOPSIS
    ONE RUN THAT SETTLES HOW THE ELEVATED SUITE GETS ITS SEAT.  RELEASE_1.1 76.

.DESCRIPTION
    RELEASE_1.1 64 left every elevated verifier driving SD through a
    "LOGTO SDSYS" prefix that cproc:2789 now refuses with 10002, and made
    CREATE.ACCOUNT reachable only from the Windows SDSYS account's own elevated
    session.  The owner ruled on 19 Sep 2026 that the suite is to be GIVEN
    SDSYS's password once per run and spawn its own SDSYS sessions, rather than
    being run from an SDSYS sign-in.

    ***THAT RULING RESTS ON ONE THING NOBODY HAS MEASURED: WHETHER A SPAWNED
    SDSYS SESSION IS ELEVATED.***  LOGIN's landing case is

        case upcase(@logname) = 'SDSYS' and kernel(K$ADMINISTRATOR, -1)

    (gpl.bp/login) - the identity AND an elevated token, with no K$INTERACTIVE
    term since 64 deleted the administrator peer gate.  So a spawn that yields
    a UAC-FILTERED token lands nowhere: it falls past the case and is refused
    with 10002, exactly as the LOGTO prefix is today, and seventeen rewritten
    verifiers would fail for a reason invisible in their own output.
    PROJECT_STATUS.md:7334 already records that a local account logging on over
    the NETWORK gets a filtered token on this machine
    (LocalAccountTokenFilterPolicy is not set), which is why this is a question
    and not an assumption.

    ***SO IT MEASURES BOTH SPAWN ROUTES AND THEN ASKS SD.***

      Route A  Start-Process -Credential (CreateProcessWithLogonW).  The cheap
               one.  ***MEASURED ON THE OWNER'S RUN, 19 Sep 2026, AND IT IS
               FILTERED, WHICH IS WHAT THIS FILE PREDICTED IN WRITING***:
               identity=ace\SDSYS, isadmin=False, BUILTIN\Administrators
               "Group used for deny only", Mandatory Label\Medium Mandatory
               Level.  So the spawn WORKS and the token is Medium - LOGIN's
               landing case cannot match through it, and route A is not the
               seat.  The row is kept because it is the control: it proves the
               credential and the work directory are right, so a failure in
               route B is route B's.
      Route B  a scheduled task registered with RunLevel Highest, which is the
               documented way to ask for the full token explicitly.  ***ITS
               FIRST ATTEMPT NEVER RAN***: the principal was '.\SDSYS' and
               Register-ScheduledTask answered "No mapping between account
               names and security IDs was done" (0x80070534).  ".\" is a shell
               convention, not an LSA one, and Start-Process -Credential
               accepts the same string happily - two APIs disagreeing about a
               name, with only one of them saying so.  It is
               "<COMPUTER>\<ACCOUNT>" now, and a registration failure is
               REPORTED rather than thrown, because the first run ended
               mid-sentence with route B unmeasured and no summary at all.

    Each route reports its INTEGRITY LEVEL and whether BUILTIN\Administrators is
    enabled or "deny only" - the distinction PROJECT_STATUS.md:7187 records -
    from whoami /groups, which shares no code with the .NET check beside it.
    Whichever route comes back elevated then drives the real sd.exe with WHO.

    ***ANCHORED ON THE SUCCESS WORDING, WITH THE FAILURE WORDING AS A
    DISQUALIFIER.***  WHO prints "<n> SDSYS" on the positive path; 10002 says
    "restricted to privileged users" on the negative one, and the account name
    appears on BOTH - so a row matching the name alone would be the false
    positive CLAUDE.md names.

    ***IT REFUSES THE NULL CASE.***  A route that produced no output at all is a
    FAIL with its own row: "the spawn printed nothing" and "the spawn said no"
    are different answers and this says which.

    THE PASSWORD IS TYPED, NEVER PASSED.  Read-Host -AsSecureString into a
    PSCredential; not echoed, not written to any file, and never on a command
    line (the owner's rule, 14 Aug 2026, PROJECT_STATUS.md:7345).  Every task is
    unregistered in a finally, so no stored credential outlives the run.

    IT CREATES NO SD ACCOUNT AND CHANGES NO SD STATE.  WHO is a read.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File C:\Users\Don\SDCoreProject\sd4windows\sdb_ai\sd64\gplbld\probe-sdsysseat.ps1

    ELEVATED PowerShell, as yourself.  It asks for the Windows SDSYS password
    once, at the keyboard.
#>

[CmdletBinding()]
param(
    # The Windows account to spawn as.  SDSYS is the one the decision is about;
    # the parameter exists so the ROUTES can be measured against another admin
    # account without touching SDSYS's password.
    [string] $Account = 'SDSYS',

    # Where the spawned processes write.  Both seats must reach it.
    [string] $WorkDir = (Join-Path $env:ProgramData 'SD-verify\sdsysseat')
)

$ErrorActionPreference = 'Stop'

$pass = 0
$fail = 0
function Note([string]$what, $expected, $got) {
    $ok = ($expected -eq $got)
    if ($ok) { $script:pass++ } else { $script:fail++ }
    Write-Output ("[{0}] {1}: expected {2}, got {3}" -f `
                  $(if ($ok) { 'PASS' } else { 'FAIL' }), $what, $expected, $got)
}
function Say([string]$t)  { Write-Output ('  ' + $t) }
function Head([string]$t) { Write-Output ''; Write-Output ('== ' + $t) }

Write-Output 'probe-sdsysseat: RELEASE_1.1 76 - can a spawned SDSYS session reach SDSYS?'
Write-Output ('  script        : ' + $PSCommandPath)
Write-Output ('  account       : ' + $Account)
Write-Output ('  work directory: ' + $WorkDir)

# --------------------------------------------------------------- preconditions
Head 'preconditions'

$me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
$pr = New-Object Security.Principal.WindowsPrincipal(
          [Security.Principal.WindowsIdentity]::GetCurrent())
$elevated = $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
Say ("this session   : {0}, elevated={1}" -f $me, $elevated)
if (-not $elevated) {
    Write-Output 'probe-sdsysseat: this needs an ELEVATED PowerShell - registering a scheduled'
    Write-Output '  task for another account needs it, and so does the comparison this makes.'
    exit 2
}

if (-not (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue)) {
    Write-Output ("probe-sdsysseat: there is no Windows {0} account.  The installer makes it" -f $Account)
    Write-Output '  (gplbld/install-sdsys.ps1); run a cycle first.'
    exit 2
}
Say ("{0} exists as a Windows account" -f $Account)

$sdExe = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
if (-not (Test-Path -LiteralPath $sdExe)) {
    Write-Output ("probe-sdsysseat: no {0}, so the SD half cannot be measured." -f $sdExe)
    exit 2
}
Say ('sd.exe         : ' + $sdExe)

if (-not (Test-Path -LiteralPath $WorkDir)) {
    $null = New-Item -ItemType Directory -Path $WorkDir -Force
}
$acl  = Get-Acl -LiteralPath $WorkDir
$rule = New-Object Security.AccessControl.FileSystemAccessRule(
            $Account, 'Modify', 'ContainerInherit,ObjectInherit', 'None', 'Allow')
$acl.AddAccessRule($rule)
Set-Acl -LiteralPath $WorkDir -AclObject $acl
Say ("{0} granted Modify on the work directory" -f $Account)

Write-Output ''
Write-Output ("Type the Windows {0} password.  It is not echoed, not written to any" -f $Account)
Write-Output '  file, and never put on a command line.'
$secret = Read-Host -Prompt ("{0} password" -f $Account) -AsSecureString
if ($null -eq $secret -or $secret.Length -eq 0) {
    Write-Output 'probe-sdsysseat: no password given - nothing was measured.'
    exit 2
}
$cred = New-Object System.Management.Automation.PSCredential(('.\' + $Account), $secret)

# ***A TRANSCRIPT, BECAUSE THE 19 Sep RUN'S ANSWER SCROLLED OFF.***  Route C
# failed and printed its Win32 error to a console the owner had already
# scrolled past, so the one fact the run existed to produce could not be read
# back.  VerifyInstall1 has kept a transcript since 22 Aug for exactly this;
# a probe whose whole output is the result has no less need of one.  The
# password cannot reach it: Read-Host -AsSecureString above echoes nothing,
# and it is read before this starts.
$logPath = Join-Path $WorkDir ('probe-sdsysseat-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
$transcribing = $false
try {
    Start-Transcript -LiteralPath $logPath -ErrorAction Stop | Out-Null
    $transcribing = $true
    Write-Output ('  transcript    : ' + $logPath)
} catch {
    Write-Output ('  transcript    : COULD NOT START - ' + $_.Exception.Message)
    Write-Output '    (the run continues; read the console, and say so if a line is missing)'
}

# The report a spawned process writes.  whoami is deliberately beside the .NET
# check: they share no code, so agreement is evidence and disagreement is a
# finding.
$tokenScript = @'
$out = @()
$out += 'identity=' + [Security.Principal.WindowsIdentity]::GetCurrent().Name
$p = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$out += 'isadmin=' + $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$out += ((& "$env:SystemRoot\System32\whoami.exe" /groups) -join "`n")
$out += 'ENDOFREPORT'
Set-Content -LiteralPath '@@OUT@@' -Value ($out -join "`n") -Encoding utf8
'@

# .Replace() rather than -replace: the replacement is a PATH, and a regex
# replacement string is not a literal one.  (CLAUDE.md's backslash rule, met
# by building the file rather than by escaping.)
function Write-SpawnScript([string]$path, [string]$body, [string]$outFile) {
    Set-Content -LiteralPath $path -Value ($body.Replace('@@OUT@@', $outFile)) -Encoding utf8
}

function Wait-For([string]$path, [int]$seconds) {
    $deadline = (Get-Date).AddSeconds($seconds)
    while (-not (Test-Path -LiteralPath $path) -and (Get-Date) -lt $deadline) {
        Start-Sleep -Milliseconds 400
    }
    return (Test-Path -LiteralPath $path)
}

# ***A FUNCTION THAT RETURNS A VALUE PRINTS NOTHING, AND THAT IS A RULE HERE
# RATHER THAN A STYLE.***  Measured on the owner's 19 Sep run: the first
# version of this file had Read-Report and Show-Token call Say(), which writes
# to the OUTPUT stream - so every one of those lines was captured into the
# caller's variable instead of reaching the screen.  The token report was read
# correctly and NOBODY SAW IT, $a came back as a three-element array rather
# than the hashtable, and the elevated test below would have read $a.IsAdmin as
# null on a good measurement.  An instrument that hides what it measured is the
# thing CLAUDE.md's rule 1 exists to stop, and this is that defect arriving
# through PowerShell's plumbing rather than through a missing Write-Output.
# So: value in, value out, and the CALLER prints.
function Read-Report([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    return (Get-Content -LiteralPath $path -Raw)
}

function Get-TokenFacts($text) {
    if ($null -eq $text) { return $null }
    $who = ''
    if ($text -match 'identity=(.+)') { $who = $Matches[1].Trim() }
    $mand = '<not reported>'
    foreach ($l in ($text -split "`r?`n")) {
        if ($l -match 'Mandatory Label\\(\S+)') { $mand = $Matches[1] }
    }
    return @{
        Who       = $who
        IsAdmin   = [bool]($text -match 'isadmin=True')
        Mand      = $mand
        DenyOnly  = [bool]($text -match '(?m)^BUILTIN\\Administrators.*deny only')
        Whole     = [bool]($text -match 'ENDOFREPORT')
        # ***THE SECOND HALF OF kernel.c:299'S CONJUNCTION, AND IT IS WHY THE
        # 19 Sep RUN WAS REFUSED.***  USR_ADMIN is set only when IsElevated()
        # AND IsInteractive() are both true, and IsInteractive() looks for
        # S-1-5-4 (SD_INTERACTIVE_GID 4, sddefs.h:271) in the very group list
        # IsElevated() reads for 544.  A BATCH logon carries S-1-5-3 instead,
        # so a scheduled task is elevated and NOT interactive - which is
        # PROJECT_STATUS.md 5.25 working exactly as it was ruled: "a session
        # whose origin cannot be established stays refused, which is what keeps
        # an unattended scheduled task out".
        Interactive = [bool]($text -match '(?m)^NT AUTHORITY\\INTERACTIVE\b')
        Batch       = [bool]($text -match '(?m)^NT AUTHORITY\\BATCH\b')
    }
}

# The product's own test, in one place, so a reader does not have to go to the
# C to learn why a route was refused.  connection_type is CN_CONSOLE for a
# locally-run sd.exe, so the middle term of kernel.c:299 is satisfied and the
# two that can fail are these.
function Test-Seat($facts) {
    if ($null -eq $facts) { return $false }
    return ($facts.IsAdmin -and -not $facts.DenyOnly -and $facts.Interactive)
}

function Write-TokenFacts($facts, [string]$label) {
    if ($null -eq $facts) {
        Say ("{0}: NO REPORT - the spawn wrote nothing at all" -f $label)
        return
    }
    if (-not $facts.Whole) {
        Say ("{0}: the report is TRUNCATED - the spawn died part way through" -f $label)
    }
    Say ("{0}: identity={1}" -f $label, $facts.Who)
    Say ("{0}: integrity={1}  isadmin={2}  Administrators-deny-only={3}" -f `
         $label, $facts.Mand, $facts.IsAdmin, $facts.DenyOnly)
    Say ("{0}: INTERACTIVE(S-1-5-4)={1}  BATCH(S-1-5-3)={2}" -f `
         $label, $facts.Interactive, $facts.Batch)
    Say ("{0}: SD's own test (IsElevated AND IsInteractive, kernel.c:299) = {1}" -f `
         $label, (Test-Seat $facts))
}

# Registers a task, runs it, waits for its output file, and unregisters it.  A
# task is registered per call rather than edited: changing the action of a task
# that carries a stored password re-registers its principal, and re-registering
# is the thing being measured.
$tasksMade = New-Object System.Collections.ArrayList

# ***THE PRINCIPAL IS "<COMPUTER>\<ACCOUNT>", NOT ".\<ACCOUNT>" - MEASURED ON
# THE OWNER'S 19 Sep RUN, WHERE THIS COST THE WHOLE ROUTE.***  Register-
# ScheduledTask answered "No mapping between account names and security IDs was
# done" (HRESULT 0x80070534) for '.\SDSYS'.  ".\" is a SHELL convention for
# "this machine"; the Task Scheduler service hands the string to LSA, which has
# never heard of it.  Start-Process -Credential accepts the same string
# happily, which is what makes this worth a paragraph: the two APIs disagree
# about a name, and only one of them says so.
function Get-Principal { return ($env:COMPUTERNAME + '\' + $Account) }

# It REPORTS a registration failure instead of dying on it.  The first version
# let the exception out and the run stopped with route B unmeasured and no
# summary at all - the owner's run ended mid-sentence.
function Invoke-ViaTask([string]$ps1, [string]$outFile, [int]$seconds) {
    $name = 'SDVerifySdsysSeat_' + [Guid]::NewGuid().ToString('N').Substring(0, 8)
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
                  -Argument ('-ExecutionPolicy Bypass -File "{0}"' -f $ps1)
    try {
        Register-ScheduledTask -TaskName $name -Action $action `
            -User (Get-Principal) -Password $cred.GetNetworkCredential().Password `
            -RunLevel Highest -Force | Out-Null
    } catch {
        return @{ Ok = $false; Task = $name; Why = ('Register-ScheduledTask refused: ' + $_.Exception.Message) }
    }
    $null = $tasksMade.Add($name)
    try {
        Start-ScheduledTask -TaskName $name
    } catch {
        return @{ Ok = $false; Task = $name; Why = ('Start-ScheduledTask refused: ' + $_.Exception.Message) }
    }
    $got = Wait-For $outFile $seconds
    return @{ Ok = $got; Task = $name
              Why = $(if ($got) { '' } else { 'the task produced no output within ' + $seconds + 's' }) }
}

# ===========================================================================
# ROUTE C - THE INTERACTIVE LOGON'S OWN LINKED TOKEN.
#
# ***THIS IS NOT A TRICK PLAYED ON THE GATE, AND THE DISTINCTION IS THE WHOLE
# REASON IT IS ALLOWED TO EXIST.***  Route A already performs a real
# INTERACTIVE logon as the account - its token carries S-1-5-4, measured - and
# UAC hands that logon a FILTERED token.  TokenLinkedToken returns the other
# half of that same pair: the token UAC would give if a person clicked Yes.  So
# this starts the process with the elevated token OF AN INTERACTIVE LOGON,
# which is exactly what clicking Yes does.  The consent is real and it is the
# owner's: an elevated administrator, at the keyboard, typing the account's
# password into this probe.
#
# ***AND THE PROPERTY IT DEPENDS ON IS ALREADY MEASURED IN THIS TREE.***
# HISTORY.md:48615, 5 Sep 2026: "ELEVATION KEEPS S-1-5-4... INTERACTIVE true in
# both legs, with BUILTIN\Administrators moving FALSE -> TRUE between them."
# That was read from one ordinary session's own linked token, with the
# Administrators move as the control that stops the two legs being one token
# read twice.  If it holds for another account's logon, route C satisfies BOTH
# terms of kernel.c:299 with no change to the product and no door to ship.
#
# CreateProcessWithTokenW, NOT CreateProcessAsUser: the first needs
# SeImpersonatePrivilege, which an elevated administrator HAS; the second needs
# SeAssignPrimaryTokenPrivilege, which it does not.  Every failure below
# reports its Win32 error rather than returning a bare false.
Add-Type -ErrorAction Stop -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class SdSeat {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out IntPtr token);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool GetTokenInformation(IntPtr token, int infoClass,
        IntPtr buffer, int length, out int returned);

    [DllImport("advapi32.dll", SetLastError=true)]
    public static extern bool DuplicateTokenEx(IntPtr existing, uint access,
        IntPtr attrs, int impLevel, int tokenType, out IntPtr dup);

    [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Unicode)]
    public struct STARTUPINFO {
        public int cb; public string res1; public string desktop; public string title;
        public int x, y, xSize, ySize, xCount, yCount, fill, flags;
        public short showWindow, res2; public IntPtr res3, stdIn, stdOut, stdErr;
    }
    [StructLayout(LayoutKind.Sequential)]
    public struct PROCESS_INFORMATION { public IntPtr process, thread; public int pid, tid; }

    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern bool CreateProcessWithTokenW(IntPtr token, int logonFlags,
        string appName, string cmdLine, int creationFlags, IntPtr env, string curDir,
        ref STARTUPINFO si, out PROCESS_INFORMATION pi);

    [DllImport("kernel32.dll", SetLastError=true)]
    public static extern bool CloseHandle(IntPtr h);

    // Returns "" on success, or the step that failed with its Win32 error.
    public static string Spawn(string user, string domain, string pass,
                               string appName, string cmdLine, string curDir, out int pid) {
        pid = 0;
        IntPtr filtered = IntPtr.Zero, linked = IntPtr.Zero, primary = IntPtr.Zero;
        try {
            // 2 = LOGON32_LOGON_INTERACTIVE, 0 = LOGON32_PROVIDER_DEFAULT
            if (!LogonUser(user, domain, pass, 2, 0, out filtered))
                return "LogonUser (interactive) failed, Win32 " + Marshal.GetLastWin32Error();

            // 19 = TokenLinkedToken
            int need = 0;
            GetTokenInformation(filtered, 19, IntPtr.Zero, 0, out need);
            if (need <= 0)
                return "GetTokenInformation(TokenLinkedToken) sized nothing, Win32 "
                       + Marshal.GetLastWin32Error()
                       + " - this logon may have NO linked token (not a split-token account)";
            IntPtr buf = Marshal.AllocHGlobal(need);
            try {
                if (!GetTokenInformation(filtered, 19, buf, need, out need))
                    return "GetTokenInformation(TokenLinkedToken) failed, Win32 "
                           + Marshal.GetLastWin32Error();
                linked = Marshal.ReadIntPtr(buf);
            } finally { Marshal.FreeHGlobal(buf); }

            // The linked token is an IMPERSONATION token; CreateProcessWithTokenW
            // needs a PRIMARY one.  0xF01FF = TOKEN_ALL_ACCESS, 2 = SecurityImpersonation,
            // 1 = TokenPrimary.
            if (!DuplicateTokenEx(linked, 0xF01FF, IntPtr.Zero, 2, 1, out primary))
                return "DuplicateTokenEx failed, Win32 " + Marshal.GetLastWin32Error();

            STARTUPINFO si = new STARTUPINFO();
            si.cb = Marshal.SizeOf(typeof(STARTUPINFO));
            PROCESS_INFORMATION pi;
            // 0x08000000 = CREATE_NO_WINDOW
            if (!CreateProcessWithTokenW(primary, 0, appName, cmdLine, 0x08000000,
                                         IntPtr.Zero, curDir, ref si, out pi))
                return "CreateProcessWithTokenW failed, Win32 " + Marshal.GetLastWin32Error();
            pid = pi.pid;
            CloseHandle(pi.thread); CloseHandle(pi.process);
            return "";
        } finally {
            if (primary  != IntPtr.Zero) CloseHandle(primary);
            if (linked   != IntPtr.Zero) CloseHandle(linked);
            if (filtered != IntPtr.Zero) CloseHandle(filtered);
        }
    }
}
'@

function Invoke-ViaLinkedToken([string]$ps1, [string]$outFile, [int]$seconds) {
    $pid2 = 0
    $cmd = ('"' + (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') +
            '" -ExecutionPolicy Bypass -File "' + $ps1 + '"')
    $why = [SdSeat]::Spawn($Account, $env:COMPUTERNAME,
                           $cred.GetNetworkCredential().Password,
                           (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'),
                           $cmd, $WorkDir, [ref]$pid2)
    if ($why -ne '') { return @{ Ok = $false; Task = ''; Why = $why } }

    # ***"IT STARTED AND WROTE NOTHING" AND "IT NEVER STARTED" ARE DIFFERENT
    # ANSWERS, AND THE 19 Sep RUN COULD NOT TELL THEM APART.***  The child's
    # exit code is the thing that separates them: a PowerShell that could not
    # find its script, or threw writing the report, exits non-zero and says so
    # here rather than leaving an absent file to be read as a failed spawn.
    $exitCode = '<still running>'
    $p = Get-Process -Id $pid2 -ErrorAction SilentlyContinue
    if ($null -ne $p) {
        if ($p.WaitForExit($seconds * 1000)) { $exitCode = $p.ExitCode }
    } else {
        $exitCode = '<gone before it could be read>'
    }

    $got = Wait-For $outFile $seconds
    return @{ Ok = $got; Task = ('pid ' + $pid2 + ', child exit code ' + $exitCode)
              Why = $(if ($got) { '' } else {
                        'the spawn produced no output within ' + $seconds +
                        's (child exit code ' + $exitCode + ')' }) }
}

function Invoke-ViaStartProcess([string]$ps1, [string]$outFile, [int]$seconds) {
    try {
        Start-Process -FilePath 'powershell.exe' `
            -ArgumentList @('-ExecutionPolicy', 'Bypass', '-File', $ps1) `
            -Credential $cred -WorkingDirectory $WorkDir -WindowStyle Hidden
    } catch {
        return @{ Ok = $false; Task = ''; Why = ('Start-Process refused: ' + $_.Exception.Message) }
    }
    $got = Wait-For $outFile $seconds
    return @{ Ok = $got; Task = ''
              Why = $(if ($got) { '' } else { 'the spawn produced no output within ' + $seconds + 's' }) }
}

try {
    # ------------------------------------------------------------------ route A
    Head 'route A - Start-Process -Credential (CreateProcessWithLogonW)'
    Say 'MEASURED FILTERED on 19 Sep 2026 - Medium integrity, Administrators deny'
    Say 'only.  It is re-run as the CONTROL: it proves the credential and the work'
    Say 'directory are right, so a failure in route B belongs to route B.'

    $aOut = Join-Path $WorkDir 'routeA.txt'
    $aPs1 = Join-Path $WorkDir 'routeA.ps1'
    Remove-Item -LiteralPath $aOut -ErrorAction SilentlyContinue
    Write-SpawnScript $aPs1 $tokenScript $aOut
    Say ('command: powershell -ExecutionPolicy Bypass -File "' + $aPs1 + '"  (as ' + $Account + ')')
    $aRun = Invoke-ViaStartProcess $aPs1 $aOut 30
    if (-not $aRun.Ok) { Say $aRun.Why }
    $a = Get-TokenFacts (Read-Report $aOut)
    Write-TokenFacts $a 'route A'
    Note 'route A produced a report at all' $true ($null -ne $a)

    # ------------------------------------------------------------------ route B
    Head 'route B - a scheduled task registered with RunLevel Highest'

    $bOut = Join-Path $WorkDir 'routeB.txt'
    $bPs1 = Join-Path $WorkDir 'routeB.ps1'
    Remove-Item -LiteralPath $bOut -ErrorAction SilentlyContinue
    Write-SpawnScript $bPs1 $tokenScript $bOut
    Say ('principal: ' + (Get-Principal))
    Say ('task runs: powershell -ExecutionPolicy Bypass -File "' + $bPs1 + '"')
    $bRun = Invoke-ViaTask $bPs1 $bOut 60
    Say ('task name: ' + $bRun.Task)
    if (-not $bRun.Ok) { Say $bRun.Why }
    $b = Get-TokenFacts (Read-Report $bOut)
    Write-TokenFacts $b 'route B'
    Note 'route B produced a report at all' $true ($null -ne $b)

    # ------------------------------------------------------------------ route C
    Head 'route C - the interactive logon''s OWN linked token'
    Say 'LogonUser(INTERACTIVE) -> TokenLinkedToken -> CreateProcessWithTokenW.'
    Say 'This is what UAC does when a person clicks Yes, so it should carry S-1-5-4'
    Say 'from the logon AND the full token from the link.  HISTORY.md:48615 measured'
    Say 'that elevation keeps S-1-5-4 on this machine; this asks it of another'
    Say 'account''s logon.'

    $cOut = Join-Path $WorkDir 'routeC.txt'
    $cPs1 = Join-Path $WorkDir 'routeC.ps1'
    Remove-Item -LiteralPath $cOut -ErrorAction SilentlyContinue
    Write-SpawnScript $cPs1 $tokenScript $cOut
    Say ('command: powershell -ExecutionPolicy Bypass -File "' + $cPs1 + '"  (as ' + $Account + ')')
    $cRun = Invoke-ViaLinkedToken $cPs1 $cOut 30
    if ($cRun.Task -ne '') { Say ('spawned: ' + $cRun.Task) }
    if (-not $cRun.Ok) { Say $cRun.Why }
    $c = Get-TokenFacts (Read-Report $cOut)
    Write-TokenFacts $c 'route C'
    Note 'route C produced a report at all' $true ($null -ne $c)

    # ------------------------------------------------------- the decisive rows
    Head 'what the three routes answered'

    $aElev = ($null -ne $a -and $a.IsAdmin -and -not $a.DenyOnly)
    $bElev = ($null -ne $b -and $b.IsAdmin -and -not $b.DenyOnly)
    $cElev = ($null -ne $c -and $c.IsAdmin -and -not $c.DenyOnly)
    $aSeat = Test-Seat $a
    $bSeat = Test-Seat $b
    $cSeat = Test-Seat $c
    Say ("route A: elevated={0}  interactive={1}  SEAT={2}" -f `
         $aElev, $(if ($null -ne $a) { $a.Interactive } else { '<none>' }), $aSeat)
    Say ("route B: elevated={0}  interactive={1}  SEAT={2}" -f `
         $bElev, $(if ($null -ne $b) { $b.Interactive } else { '<none>' }), $bSeat)
    Say ("route C: elevated={0}  interactive={1}  SEAT={2}" -f `
         $cElev, $(if ($null -ne $c) { $c.Interactive } else { '<none>' }), $cSeat)
    Note 'a route gave an ELEVATED session as the account'    $true ($aElev -or $bElev -or $cElev)
    Note 'a route satisfied BOTH terms SD tests (the seat)'   $true ($aSeat -or $bSeat -or $cSeat)

    if (-not ($aElev -or $bElev -or $cElev)) {
        Write-Output ''
        Write-Output 'probe-sdsysseat: NEITHER ROUTE IS ELEVATED, so LOGIN''s landing case cannot'
        Write-Output '  match and the suite cannot be given its seat this way.  THAT IS AN ANSWER,'
        Write-Output '  not a failure of the probe: it means the 19 Sep ruling needs the other'
        Write-Output '  option - the suite run from an SDSYS sign-in - or a deliberate decision'
        Write-Output '  about LocalAccountTokenFilterPolicy, which is a machine-wide UAC change'
        Write-Output '  and is the owner''s to make.'
        exit 1   # the counts and the transcript are closed by the finally
    }

    # ***MEASURED 19 Sep 2026 AND THE TWO ROUTES FAIL OPPOSITE HALVES.***  Route
    # A is INTERACTIVE and Medium; route B is High and BATCH.  Neither is a
    # seat, so SD below is EXPECTED to refuse, and a refusal it predicted is a
    # confirmed prediction rather than a product failure - scoring it as a FAIL
    # would blame SD for obeying 5.25.  The SD leg still runs, because the
    # refusal is the evidence.
    $expectRefusal = -not ($aSeat -or $bSeat -or $cSeat)
    if ($expectRefusal) {
        Write-Output ''
        Write-Output '  NO ROUTE IS A SEAT.  A AND B FAIL OPPOSITE HALVES OF ONE CONJUNCTION:'
        Write-Output '  kernel.c:299 sets USR_ADMIN only for IsElevated() AND IsInteractive(), and'
        Write-Output '  IsInteractive() looks for S-1-5-4 in the same group list IsElevated() reads'
        Write-Output '  for 544 (sddefs.h:240, :271).  CreateProcessWithLogonW gives an INTERACTIVE'
        Write-Output '  logon with a UAC-FILTERED token; a scheduled task gives a full token with a'
        Write-Output '  BATCH logon.  SD is expected to refuse below with 10002, and that refusal is'
        Write-Output '  PROJECT_STATUS.md 5.25 working as ruled - "a session whose origin cannot be'
        Write-Output '  established stays refused, which is what keeps an unattended scheduled task'
        Write-Output '  out".  The run continues so the refusal is on the record.'
    }

    # ------------------------------------------------------------------- SD
    Head 'and what SD says when that seat runs it'

    # Prefer a route that IS a seat; failing that, the elevated one, because a
    # refusal from the closest route is the most informative one to capture.
    $route = $(if ($cSeat) { 'C' } elseif ($bSeat) { 'B' } elseif ($aSeat) { 'A' }
               elseif ($cElev) { 'C' } elseif ($bElev) { 'B' } else { 'A' })
    Say ("driving sd.exe through route {0}" -f $route)
    if ($expectRefusal) { Say 'PREDICTION: SD refuses with 10002, because no route is a seat.' }

    $sdOut = Join-Path $WorkDir 'sdwho.txt'
    $sdPs1 = Join-Path $WorkDir 'sdwho.ps1'
    Remove-Item -LiteralPath $sdOut -ErrorAction SilentlyContinue
    $sdScript = @'
$sd  = '@@SD@@'
$in  = "`nWHO`nOFF`n"
$out = $in | & $sd 2>&1
Set-Content -LiteralPath '@@OUT@@' -Value (($out -join "`n") + "`nENDOFREPORT") -Encoding utf8
'@
    Write-SpawnScript $sdPs1 ($sdScript.Replace('@@SD@@', $sdExe)) $sdOut

    switch ($route) {
        'B' {
            Say ('principal: ' + (Get-Principal))
            $sdRun = Invoke-ViaTask $sdPs1 $sdOut 90
            Say ('task name: ' + $sdRun.Task)
        }
        'C' {
            $sdRun = Invoke-ViaLinkedToken $sdPs1 $sdOut 90
            if ($sdRun.Task -ne '') { Say ('spawned: ' + $sdRun.Task) }
        }
        default { $sdRun = Invoke-ViaStartProcess $sdPs1 $sdOut 90 }
    }
    if (-not $sdRun.Ok) { Say $sdRun.Why }

    $sdText = Read-Report $sdOut
    if ($null -ne $sdText -and $sdText -notmatch 'ENDOFREPORT') {
        Say 'the SD report is TRUNCATED - the spawn died part way through'
    }
    Note 'the spawned seat produced SD output at all' $true ($null -ne $sdText)
    if ($null -ne $sdText) {
        Write-Output '  --- raw sd output ---'
        foreach ($l in ($sdText -split "`r?`n")) { Write-Output ('  | ' + $l) }

        # SUCCESS WORDING.  WHO answers "<n> SDSYS"; the account NAME alone is
        # not a check - 10002's refusal names SDSYS too.
        $landed  = ($sdText -match '(?m)^\s*\d+\s+SDSYS\b')
        $refused = ($sdText -match 'restricted to privileged users')
        if ($expectRefusal) {
            # The prediction is the check.  A route that is not a seat MUST be
            # refused; landing anyway would mean SD's gate does not hold, which
            # is a finding in the other direction and is scored as one.
            Note 'SD refused with 10002, as predicted for a non-seat route' $true $refused
            Note 'and it did NOT land in SDSYS'                             $true (-not $landed)
        } else {
            Note 'WHO answered "<n> SDSYS" (the landing case matched)' $true $landed
            Note 'no 10002 refusal in the same output'                 $true (-not $refused)
        }
    }
} finally {
    foreach ($n in $tasksMade) {
        Unregister-ScheduledTask -TaskName $n -Confirm:$false -ErrorAction SilentlyContinue
    }
    if ($tasksMade.Count -gt 0) {
        Write-Output ''
        Write-Output ("  {0} scheduled task(s) unregistered - no stored credential outlives this run" -f $tasksMade.Count)
    }
    # THE SUMMARY IS WRITTEN HERE, INSIDE THE finally, so that it reaches the
    # transcript on EVERY path - including the two "exit 1" arms above, which
    # are the paths a reader most needs the counts from.  Stopping the
    # transcript first and summarising after would have left the log ending
    # mid-run, which is the defect this whole block is here to fix.
    Write-Output ''
    Write-Output ("probe-sdsysseat: {0} passed, {1} failed" -f $pass, $fail)
    Write-Output ("  work directory left in place for reading: {0}" -f $WorkDir)
    if ($transcribing) {
        Write-Output ("  transcript    : " + $logPath)
        Stop-Transcript | Out-Null
    }
}

if ($fail -gt 0) { exit 1 }
exit 0
