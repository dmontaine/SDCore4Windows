# verify-createaccount.ps1 - run CREATE.ACCOUNT USER against a throwaway name
# and check both halves of what it makes, including the ssh-only branch.
#
#   powershell -File verify-createaccount.ps1            create, check, clean up
#   powershell -File verify-createaccount.ps1 -Keep      leave the account behind
#   powershell -File verify-createaccount.ps1 -Cleanup   remove one left by -Keep
#   powershell -File verify-createaccount.ps1 -Keep -Password 'Sd-Test-1'
#                                                        a password you can type
#
# -Password is for the hand-driven case only.  The default is 24 random
# characters, which is right for an unattended run - nothing ever types it - and
# close to untypeable at an ssh prompt that does not echo.  It goes into shell
# history, so use it only for throwaway accounts on a development machine.
#
# Exit 0 all checks passed, 1 a check failed, 2 the test could not be run.
#
# WHY.  CREATE.ACCOUNT has been run once, on 14 Aug 2026, but the sdsshonly
# group did not exist then - so the ssh-only branch at CREATEA line 400 has
# never executed.  It is also the branch that can leave a mess: it `stop`s on
# failure AFTER the Windows account and the account directory have been made,
# so a failure there leaves a half-created account behind.
#
# This goes further than checking the verb returns.  It takes the account
# CREATE.ACCOUNT produced and puts it through the same three measurements
# verify-sshonly.ps1 uses, so what is proven is the whole chain: SD created the
# account, SD restricted it, and the restriction actually holds.
#
# THE HELPERS BELOW ARE COPIED FROM verify-sshonly.ps1 RATHER THAN SHARED.
# That script produced this project's ssh-only verification and is known to
# work; factoring its internals out into a module would mean re-verifying it
# through another elevated run to prove the refactor changed nothing, which is
# a poor trade for saving eighty lines.  If a third script wants them, that is
# the point to make a common file.
#
# DRIVING SD FROM POWERSHELL, which has two traps in it, both measured
# 14 Aug 2026 and both in PROJECT_STATUS.md section 6:
#
#   - Input must be PIPED.  Start-Process -RedirectStandardInput hands SD a
#     file handle and SD answers "Process terminated" and exits, the same way
#     the "<" redirect described in section 6 does.
#   - The pipe prepends a BOM to the FIRST line, whatever $OutputEncoding is
#     set to, and SD answers "COUNT is not in your VOC" for a perfectly good
#     COUNT VOC.  A blank sacrificial first line absorbs it: the BOM lands on
#     a line that was empty anyway, SD says it is not in the VOC, and the real
#     commands follow untouched.

param(
    [string]$Account  = 'sdacct1',
    [string]$Group    = 'sdsshonly',
    [string]$Password = '',
    # 03 Sep 26 - PRE_RELEASE_FIXES 136.  The tier keyword, which goes BETWEEN
    # the name and the access keyword: CREATE.ACCOUNT USER <name> <tier> <SSH>.
    # EMPTY IS THE DEFAULT AND MEANS "SAY NOTHING", which is what every run
    # before today did, so an existing caller gets the identical command line
    # and the identical STANDARD account.  136 needs one PROGRAMMER witness and
    # this is the whole of what it needed.
    [ValidateSet('', 'STANDARD', 'PROGRAMMER', 'ADMINISTRATOR')]
    [string]$Tier     = '',
    [switch]$Keep,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

# 19 Aug 26 - A TRANSCRIPT, AND IT WAS THE ONLY VERIFIER WITHOUT ONE.  This
# script is ELEVATED, and an elevated window does not paste its output back
# into the session that asked for it - which is the whole reason verify-tiers
# and verify-lcnames keep one.  On 19 Aug it exited 2 in under a second and
# there was NO RECORD AT ALL of why; the fault had to be reconstructed from
# verify-tiers' audit trail instead.  Outside the trees cycle.ps1 deletes.
$logDir = Join-Path $env:LOCALAPPDATA 'SD-verify'
if (-not (Test-Path -LiteralPath $logDir)) { $null = New-Item -ItemType Directory -Path $logDir -Force }
$logPath = Join-Path $logDir ('verify-createaccount-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.log')
try { Start-Transcript -Path $logPath -Force | Out-Null } catch { }
Write-Output ("transcript: " + $logPath)

# 19 Aug 26 - AND CHECK THE NAME IS A NAME.  A caller that splats its arguments
# wrongly delivers "-Account sdacct14" as the VALUE of -Account, and the run
# then fails several steps later looking like something else entirely.
# post-cycle-elevated.ps1's header has the measurement.
if ($Account -notmatch '^[A-Za-z][A-Za-z0-9_.]*$') {
    Write-Output ("verify-createaccount: -Account is '{0}', which is not a usable account name." -f $Account)
    Write-Output '  Letters, digits, dot and underscore only, starting with a letter.'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

# 15 Aug 26 - REFUSE A STALE TREE BEFORE DOING ANYTHING, and before -Cleanup
# too: cleaning up after a run whose results were void is fine, but starting a
# new one is not.  CLAUDE.md requires a test cycle to begin with a fresh
# install; assert-current.ps1 is what makes that enforceable rather than
# remembered, and its header records the two ways the rule alone was got round
# on 15 Aug 2026.  Exit 2 is this script's own "the test could not be run".
& (Join-Path $PSScriptRoot 'assert-current.ps1')
if ($LASTEXITCODE -ne 0) {
    Write-Output ''
    Write-Output 'verify-createaccount: refusing - see above'
    try { Stop-Transcript | Out-Null } catch { }
    exit 2
}

$sdExe   = Join-Path $env:ProgramFiles 'SD\usr\bin\sd.exe'
$acctDir = Join-Path $env:ProgramData ('SD\user_accounts\' + $Account)
$workdir = Join-Path $env:TEMP 'sd-createaccount-probe'
$askpass = Join-Path $workdir 'askpass.cmd'

$results = New-Object System.Collections.ArrayList
$fatal   = $false

function Note($step, $expected, $got, $decisive) {
    $pass = ($expected -eq $got)
    $null = $results.Add([pscustomobject]@{
        Check = $step; Expected = $expected; Observed = $got
        Result = $(if ($pass) { 'PASS' } else { 'FAIL' })
        Decisive = $(if ($decisive) { 'yes' } else { 'no' })
    })
    if ($decisive -and -not $pass) { $script:fatal = $true }
    Write-Output ("  [{0}] {1}: expected {2}, got {3}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }), $step, $expected, $got)
}

# 24 Aug 26 - THE VERDICT LINE. ADDED BECAUSE THIS SCRIPT PRINTED NONE.
#
# Found on the b36 suite run: every other verifier ends with wording of its own
# - "17 of 17 checks passed", "verify-pcodeacl: PASSED - ..." - and this one
# ended with eight lines of cleanup prose. The catch block below prints
# "verify-createaccount: FAILED", so FAILURE had wording and SUCCESS did not,
# which leaves a reader only the ABSENCE of failure to check.
#
# THAT ASYMMETRY IS THE THING SECTION 0 FORBIDS, and it had just cost a false
# reading: the elevated per-step logs are UTF-16LE, an ASCII grep for [FAIL]
# over them matches nothing, and "no FAIL rows" therefore looked identical to
# a clean run. A positive success string cannot be faked the same way - if it
# is absent, either the run did not finish or the pattern is wrong, and both
# are worth knowing.
#
# ***IT REFUSES THE NULL CASE OUT LOUD.*** A run that recorded no DECISIVE
# check has proved nothing, and without this it would have reached "exit 0" on
# an empty $results and scored as a pass. It sets $fatal rather than returning
# a code, so the existing "if ($fatal) { exit 1 }" carries it and no exit path
# has to change - and so nothing lands in the pipeline, which is what would
# happen if this returned a value while also writing output.
function Write-Verdict($name) {
    $all      = @($script:results)
    $decisive = @($all | Where-Object { $_.Decisive -eq 'yes' })
    $failed   = @($decisive | Where-Object { $_.Result -ne 'PASS' })

    Write-Output ""
    if ($decisive.Count -eq 0) {
        Write-Output ("{0}: FAILED - NO DECISIVE CHECK RAN, so this run proves nothing." -f $name)
        Write-Output ("  {0} row(s) recorded, none of them decisive." -f $all.Count)
        $script:fatal = $true
        return
    }
    if ($failed.Count -gt 0) {
        Write-Output ("{0}: FAILED - {1} of {2} decisive checks failed:" -f $name, $failed.Count, $decisive.Count)
        $failed | ForEach-Object { Write-Output ("    " + $_.Check) }
        $script:fatal = $true
        return
    }
    Write-Output ("{0}: PASSED - {1} of {1} decisive checks passed, {2} row(s) in all." -f
                  $name, $decisive.Count, $all.Count)
}

# STARTING SD IS NOT A JOB FOR Invoke-Native, AND THIS HUNG THE WHOLE SCRIPT.
#
# Measured 14 Aug 2026, fourth session: the script printed "SD is not running,
# starting it" and never came back.  sd -start had already succeeded - sdwind
# was up and the sd process had exited - but Invoke-Native was still waiting.
#
# sd -start spawns sdwind, which INHERITS the redirected stdout and stderr
# handles.  Start-Process -Wait with -RedirectStandardOutput does not return
# until those handles are released, so it waits for the DAEMON, which is meant
# to run for ever.  PROJECT_STATUS.md section 6 recorded the trap but gave
# "redirect to a file when starting from a script" as the remedy, which is what
# Invoke-Native does; redirecting to a file is not enough, because the wait is
# on the handle and not on the destination.  Corrected there and in HISTORY.md.
#
# So do what that trap's other sentence says: do not wait on the process at
# all, and look for sdwind instead.
function Start-SD {
    $null = Start-Process -FilePath $sdExe -ArgumentList '-start' -NoNewWindow
    for ($i = 0; $i -lt 30; $i++) {
        if ((Get-Process sdwind -ErrorAction SilentlyContinue | Measure-Object).Count -gt 0) {
            Write-Output "  sdwind is up"
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    Write-Output "  sdwind did not appear within 15 seconds"
    return $false
}

# See the header: no inline "2>&1" anywhere, because PowerShell 5.1 turns a
# native program's stderr into a terminating error under 'Stop'.
#
# DO NOT USE THIS FOR sd -start.  See Start-SD above.
# 15 Aug 26 - $StdIn EXISTS BECAUSE OF ForceCommand.  See the identical comment
# in verify-sshonly.ps1: with the ssh-only model's global ForceCommand applied,
# sshd discards "whoami" and runs SD, so ssh opens an interactive session and
# EOF at SD's ":" prompt makes SD spin (PROJECT_STATUS.md section 6).  This
# script is where that was found - it hung on 15 Aug 2026 having already passed
# everything else - and ConnectTimeout does not cover it.
function Invoke-Native {
    param([string]$Exe, [string[]]$CmdArgs, [string]$StdIn = '')
    $so = Join-Path $workdir 'native.out'
    $se = Join-Path $workdir 'native.err'
    $si = Join-Path $workdir 'native.in'
    if ($StdIn -eq '') { Set-Content -Path $si -Value $null -Encoding ascii }
    else { [IO.File]::WriteAllText($si, $StdIn) }
    $p = Start-Process -FilePath $Exe -ArgumentList $CmdArgs -NoNewWindow -Wait -PassThru `
             -RedirectStandardOutput $so -RedirectStandardError $se -RedirectStandardInput $si
    $o = ''; $e = ''
    if (Test-Path $so) { $o = ((Get-Content $so) -join "`n").Trim() }
    if (Test-Path $se) { $e = ((Get-Content $se) -join "`n").Trim() }
    return [pscustomobject]@{ ExitCode = $p.ExitCode; Out = $o; Err = $e }
}

$logonSig = @'
using System;
using System.Runtime.InteropServices;
public class SdLogon2 {
    [DllImport("advapi32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    static extern bool LogonUser(string user, string domain, string pass,
        int logonType, int logonProvider, out IntPtr token);
    [DllImport("kernel32.dll", SetLastError=true)]
    static extern bool CloseHandle(IntPtr handle);
    public static int Try(string user, string pass, int logonType) {
        IntPtr token = IntPtr.Zero;
        bool ok = LogonUser(user, ".", pass, logonType, 0, out token);
        if (!ok) return Marshal.GetLastWin32Error();
        CloseHandle(token);
        return 0;
    }
}
'@

function LogonResult($user, $pass, $type) {
    $rc = [SdLogon2]::Try($user, $pass, $type)
    if ($rc -eq 0) { return 'admitted' }
    if ($rc -eq 1385) { return 'refused 1385' }
    return ("refused " + $rc)
}

# ssh takes no password on the command line but honours SSH_ASKPASS with
# SSH_ASKPASS_REQUIRE=force.  The secret goes in an environment variable, never
# in the helper file, and is cleared in the finally block.
function SshPassword($pass) {
    Set-Content -Path $askpass -Encoding ascii -Value @('@echo off', 'echo %SDACCTPW%')
    $env:SDACCTPW = $pass
    $env:SSH_ASKPASS = $askpass
    $env:SSH_ASKPASS_REQUIRE = 'force'
    $env:DISPLAY = 'localhost:0'
    try {
        $r = Invoke-Native (Get-Command ssh).Source @(
            '-o','StrictHostKeyChecking=no','-o','UserKnownHostsFile=NUL',
            '-o','PreferredAuthentications=password','-o','NumberOfPasswordPrompts=1',
            '-o','ConnectTimeout=20','-o','LogLevel=ERROR',
            ($Account + '@localhost'), 'whoami') -StdIn "OFF`n"
    } finally {
        Remove-Item Env:\SDACCTPW, Env:\SSH_ASKPASS, Env:\SSH_ASKPASS_REQUIRE, Env:\DISPLAY -ErrorAction SilentlyContinue
        Remove-Item $askpass -ErrorAction SilentlyContinue
    }
    # 15 Aug 26 - TWO PROOFS OF ADMISSION.  Without ForceCommand, "whoami"
    # returns the account name.  With it, sshd runs SD instead and the name
    # never appears, so SD's own login banner is the proof.  Both mean admitted:
    # the question is whether the account got IN.  Keeping both lets this script
    # run either side of allow-ssh-groups.ps1, which is applied by hand.
    if ($r.ExitCode -eq 0 -and $r.Out -match [regex]::Escape($Account)) { return 'admitted' }
    if ($r.Out -match 'String Database') { return 'admitted' }
    $why = ($r.Out + ' ' + $r.Err).Trim() -replace '\s+', ' '
    if ($why -eq '') { $why = 'no output, exit ' + $r.ExitCode }
    return ('refused: ' + $why)
}

# ONE STRING WITH LF SEPARATORS, NOT AN ARRAY DOWN THE PIPELINE.
#
# PowerShell writes CRLF between pipeline objects, and SD treats CR and LF EACH
# as a line terminator - so an array of n commands arrives as n commands with a
# phantom EMPTY line after every one of them.  At the TCL prompt that is
# harmless and invisible: an empty command just reprints the prompt.  At an
# "input" statement it is not, and it silently destroyed this test:
#
#   input pw1 HIDDEN   <- the phantom after the CREATE.ACCOUNT line: EMPTY
#   input pw2 HIDDEN   <- the real password
#   input yn           <- the next phantom: EMPTY, so not "Y", so no retry
#
# pw1 # pw2, so SET_PASSWD returned "user created but password not set", the
# account was left disabled - Enable-LocalUser runs inside that same script -
# and all three logon measurements then failed for want of a password.  The
# second password fell through to the TCL prompt, where it produced a stray
# "Command not found" on stderr, which was the only visible trace.
#
# Measured 14 Aug 2026 rather than deduced, by piping AAA and BBB both ways and
# counting the prompts: the array form shows an empty command between each
# pair, the single-string form shows none.  PROJECT_STATUS.md section 6.
#
# The leading "`n" is the BOM sink - see the header.  It has to stay: the BOM
# still lands on the first line whichever form is used.
function Invoke-SD([string[]]$commands) {
    # 15 Aug 26 - "sd -ASDSYS" IS REFUSED NOW, and this is the whole change on
    # this side.  Nobody logs in to an account but their own (GPL.BP/LOGIN,
    # owner's rule 15 Aug 2026); an administrator arrives in their own account
    # and reaches SDSYS with LOGTO, which is where the elevated bypass lives.
    # The elevation this script already requires is what makes the LOGTO pass.
    $body = "`n" + ((@('LOGTO SDSYS') + $commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe
    return (($out -replace ([char]27 + '\[[0-9]*[A-Za-z]'), '') -join "`n")
}

function Test-Member($group, $name) {
    $m = Get-LocalGroupMember -Group $group -ErrorAction SilentlyContinue |
         Where-Object { $_.Name -like ("*\" + $name) }
    return ($null -ne $m)
}

function Remove-Made {
    # The WINDOWS half only.  See the summary for why the SD half is left.
    if (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue) {
        Remove-LocalUser -Name $Account
        Write-Output "cleanup: removed Windows user $Account"
    } else {
        Write-Output "cleanup: no Windows user $Account"
    }
    if (Get-LocalGroup -Name ('sdu_' + $Account) -ErrorAction SilentlyContinue) {
        Remove-LocalGroup -Name ('sdu_' + $Account)
        Write-Output ("cleanup: removed group sdu_" + $Account)
    }
    # 26 Aug 26 - REMOVE THE PROFILE, NOT THE DIRECTORY.  Deleting
    # C:\Users\<name> leaves the ProfileList registry entry behind, and Windows
    # then honours that entry when an account of the same name next appears, by
    # creating the profile at C:\Users\<name>.<COMPUTERNAME>.  That is where
    # sdacct19.GITORLI, sdacct20.GITORLI and sdacct27.GITORLI came from - THIS
    # script's own prefix, so this line is where they came from too.
    # clean-test-profiles.ps1's header carries the full account.
    #
    # Counted 26 Aug 2026: 47 ProfileList entries whose directories were
    # already gone, against 30 directories on disk.  Remove-CimInstance takes
    # both halves.  The Remove-Item fallback stays for a directory with no
    # ProfileList entry - $workdir is one, and is handled separately below
    # precisely because it is NOT a profile.
    $prof = Join-Path $env:SystemDrive ('Users\' + $Account)
    $ent  = @(Get-CimInstance Win32_UserProfile -ErrorAction SilentlyContinue |
              Where-Object { $_.LocalPath -eq $prof })
    foreach ($p in $ent) {
        try {
            Remove-CimInstance -InputObject $p -ErrorAction Stop
            Write-Output "cleanup: removed profile $prof (directory and ProfileList entry)"
        } catch {
            Write-Output ("cleanup: WARNING profile {0} not removed - {1}" -f $prof, $_.Exception.Message)
        }
    }
    if (Test-Path -LiteralPath $prof) {
        if ($ent.Count -eq 0) {
            Remove-Item -Recurse -Force -LiteralPath $prof -ErrorAction SilentlyContinue
        } else {
            Write-Output "cleanup: note $prof still present after the profile went"
        }
    }
    if (Test-Path $workdir) { Remove-Item -Recurse -Force $workdir -ErrorAction SilentlyContinue }
}

try {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        # Measured: unelevated, CREATE.ACCOUNT reaches create_user and stops
        # with "Create User Failed, OS Error: 5", creating nothing.
        Write-Output "verify-createaccount: not elevated - CREATE_USER needs an elevated token"
        exit 2
    }

    if ($Cleanup) { Remove-Made; exit 0 }

    if (-not (Test-Path $sdExe)) { Write-Output "verify-createaccount: no $sdExe"; exit 2 }
    if (-not (Get-LocalGroup -Name $Group -ErrorAction SilentlyContinue)) {
        Write-Output "verify-createaccount: the $Group group does not exist - that is the whole point of this test"
        Write-Output "  create it with verify-sshonly.ps1, or rebuild and re-run the installer"
        exit 2
    }
    if (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue) {
        Write-Output "verify-createaccount: $Account already exists - run with -Cleanup first"
        exit 2
    }

    # THE SD SIDE SURVIVES A RUN ON PURPOSE (see the summary at the end), which
    # means a second run of the same name is refused by CREATE.ACCOUNT itself
    # with "Account already exists" - long after it has made a Windows account
    # for it.  Say so here instead, where nothing has been created yet.
    if (Test-Path $acctDir) {
        Write-Output "verify-createaccount: $acctDir already exists, so SD will refuse the name"
        Write-Output "  A previous run left it deliberately - removing it is DELETE.ACCOUNT's job"
        Write-Output "  and 7 step 1c has not settled what that should do."
        Write-Output ""
        Write-Output "  Use a fresh name:      -Account sdacct2"
        Write-Output "  Or clear it by hand:   Remove-Item -Recurse -Force '$acctDir'"
        Write-Output "                         and DELETE ACCOUNTS $($Account.ToUpper()) from inside SD"
        exit 2
    }

    Add-Type -TypeDefinition $logonSig -Language CSharp | Out-Null
    if (Test-Path $workdir) { Remove-Item -Recurse -Force $workdir }
    New-Item -ItemType Directory -Path $workdir | Out-Null

    if ((Get-Process sdwind -ErrorAction SilentlyContinue | Measure-Object).Count -eq 0) {
        Write-Output "  SD is not running, starting it"
        if (-not (Start-SD)) {
            Write-Output "verify-createaccount: SD would not start"
            exit 2
        }
    }

    # Same alphabet as verify-sshonly.ps1: no ambiguous glyphs, and nothing
    # cmd.exe treats specially, because it passes through the askpass helper.
    $alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789'
    $bytes = New-Object byte[] 20
    ([System.Security.Cryptography.RandomNumberGenerator]::Create()).GetBytes($bytes)
    $plain = (-join ($bytes | ForEach-Object { $alphabet[$_ % $alphabet.Length] })) + '-Aa9'

    # -Password EXISTS FOR THE HAND-DRIVEN CASE, and it is worth saying why the
    # generated one is not simply shortened.  The unattended run never types the
    # password - it goes to CREATE.ACCOUNT down a pipe and to LogonUser and ssh
    # through an askpass helper - so 24 random characters cost nothing there and
    # are the right default.  But -Keep leaves a REAL account behind for somebody
    # to ssh into by hand, and a 24-character random string is close to untypeable
    # at a prompt that does not echo.  Supplying one is the fix; weakening the
    # default for everybody is not.
    #
    # It lands in shell history, so use it only for throwaway test accounts on a
    # development machine - which is all this script ever makes.  It must still
    # satisfy the Windows password policy or CREATE.ACCOUNT's SET_PASSWD leg
    # fails, and that failure looks like a broken verb rather than a rejected
    # password.  PROJECT_STATUS.md section 6.
    if ($Password -ne '') {
        $plain = $Password
        Write-Output ("  using the -Password given rather than a generated one")
    }

    Write-Output ""
    # 03 Sep 26 - THE COMMAND LINE IS BUILT ONCE AND ECHOED, rather than being
    # described.  Rule 1 of the instrument section: a -Tier that failed to reach
    # the command is the failure this print exists to make visible, and it is
    # the exact shape the $args clobber had.
    $createCmd = ('CREATE.ACCOUNT USER ' + $Account + ' ' + $Tier + ' SSH') -replace '\s+', ' '
    Write-Output "=== 1. $createCmd ====================================="
    Write-Output ("  tier requested: '{0}'{1}" -f $Tier, $(if ($Tier -eq '') { "  (none - SD's default)" } else { '' }))
    $sdOut = Invoke-SD @($createCmd, $plain, $plain)
    Write-Output "  --- what SD said ---"
    ($sdOut -split "`n") | Where-Object {
        $_ -match '\S' -and $_ -notmatch 'Ladybridge|WARRANTY|welcome to modify|conditions\.|free software|version 1\.0|is not in your VOC|^:?\s*$'
    } | ForEach-Object { Write-Output ("    " + $_.Trim()) }

    # PRINT THE PASSWORD HERE, NOT AT THE END, WHEN -Keep IS GIVEN.  It used to
    # appear only in the closing summary, which is fine right up until the run
    # does not reach the closing summary: on 14 Aug 2026 LIST ACCOUNTS hung on
    # the fifth account and took the password with it, leaving a real Windows
    # account nobody could log in as.  A credential you only learn if everything
    # succeeds is lost by any failure after it is set, and the account outlives
    # the run.  PROJECT_STATUS.md section 6.
    if ($Keep) {
        Write-Output ""
        Write-Output ("  -Keep: " + $Account + " password is  " + $plain)
        Write-Output "  (printed now rather than at the end, so a later failure cannot lose it)"
    }

    Write-Output ""
    Write-Output "=== 2. what it made ===================================================="

    Note 'the Windows account exists' 'yes' $(if (Get-LocalUser -Name $Account -ErrorAction SilentlyContinue) { 'yes' } else { 'no' }) $true
    Note 'account is enabled' 'yes' $(if ((Get-LocalUser -Name $Account -ErrorAction SilentlyContinue).Enabled) { 'yes' } else { 'no' }) $true
    Note 'member of sdusers' 'yes' $(if (Test-Member 'sdusers' $Account) { 'yes' } else { 'no' }) $true
    Note ('member of sdu_' + $Account) 'yes' $(if (Test-Member ('sdu_' + $Account) $Account) { 'yes' } else { 'no' }) $true
    # THE BRANCH THAT HAD NEVER RUN.
    Note ('member of ' + $Group) 'yes' $(if (Test-Member $Group $Account) { 'yes' } else { 'no' }) $true
    # And the default must NOT be an administrator.
    Note 'NOT an administrator' 'no' $(if (Test-Member 'Administrators' $Account) { 'yes' } else { 'no' }) $true
    Note 'message 10034 (ssh only) shown' 'yes' $(if ($sdOut -match 'ssh only') { 'yes' } else { 'no' }) $true

    Note 'account directory' 'yes' $(if (Test-Path $acctDir) { 'yes' } else { 'no' }) $true
    # $svlists, not $savedlists.  CREATEA prints "Creating $savedlists..." and
    # then creates a directory called $svlists - the message is the VOC name,
    # the directory is the DH file name.  This test asserted the message and
    # failed against a perfectly good account on 14 Aug 2026.  (The VOC name was
    # $SAVEDLISTS until 5.12 (b) lower-cased it; the DH name never moved.)
    #
    # 18 Aug 26 - CASE EXACT, AND Test-Path CANNOT DO IT.  The names below are
    # lower case as of PROJECT_STATUS.md 5.12 (a), and Test-Path on NTFS matches
    # $HOLD against $hold, so it would pass whichever case CREATEA wrote and
    # assert nothing about the rename.  Compare against the directory listing
    # with -ceq instead.
    #
    # 19 Aug 26 - voc JOINED THEM, 5.12 (a)'s wide half (CREATEA:581).  bp.out
    # is still absent from this list because BASIC makes it, not CREATE.ACCOUNT.
    $onDisk = @(Get-ChildItem -LiteralPath $acctDir -Force | Select-Object -ExpandProperty Name)
    foreach ($f in @('voc', '$hold', '$hold.dic', '$svlists', 'bp', 'cat')) {
        $hit = @($onDisk | Where-Object { $_ -ceq $f }).Count
        Note ('  ' + $f + ' (exact case)') 'yes' $(if ($hit -eq 1) { 'yes' } else { 'no' }) $true
    }

    # NO.PAGE IS NOT OPTIONAL, AND THE REASON ONLY APPEARS WITH USE.  A piped
    # session cannot answer "Press RETURN to continue", so once the register
    # grows past one screen this call BLOCKS FOREVER and the script stops here
    # with no error - measured 14 Aug 2026, on the fifth account, leaving an
    # sd.exe waiting on stdin.  Four accounts fitted a page and three earlier
    # runs passed, which is exactly why it was not found sooner.  bootstrap.py
    # line 205 takes the same precaution.  PROJECT_STATUS.md section 6.
    $accts = Invoke-SD @('LIST ACCOUNTS NO.PAGE')
    Note 'record in ACCOUNTS' 'yes' $(if ($accts -match [regex]::Escape($Account)) { 'yes' } else { 'no' }) $true

    Write-Output ""
    Write-Output "=== 3. does the restriction SD applied actually hold? ==================="
    Write-Output "  Same three measurements verify-sshonly.ps1 makes, on an account SD"
    Write-Output "  created rather than one the test made for itself."

    Note 'LogonUser INTERACTIVE (console)'  'refused 1385' (LogonResult $Account $plain 2) $true
    Note 'LogonUser NETWORK_CLEARTEXT'      'admitted'     (LogonResult $Account $plain 8) $true
    Note 'ssh with the password SD set'     'admitted'     (SshPassword $plain)            $true

    Write-Output ""
    Write-Output "=== summary ============================================================"
    $results | Format-Table -AutoSize -Wrap | Out-String | Write-Output

    if ($Keep) {
        Write-Output ("-Keep given.  " + $Account + " is a REAL Windows account, password " + $plain)
        Write-Output ("  Remove it with:  powershell -File verify-createaccount.ps1 -Cleanup")
    } else {
        Remove-Made
    }

    Write-Output ""
    Write-Output "WHAT CLEANUP DOES NOT REMOVE, deliberately: the SD side.  The ACCOUNTS"
    Write-Output ("record and " + $acctDir + " are left in place, because")
    Write-Output "removing them is DELETE.ACCOUNT's job and what DELETE.ACCOUNT should do is"
    Write-Output "still an open decision - PROJECT_STATUS.md 7, step 1c.  Inventing a cleanup"
    Write-Output "here would presuppose that decision.  Remove them by hand if you want the"
    Write-Output "tree pristine, and note what a half-removed account looks like while you do:"
    Write-Output "it is the thing 1c has to settle."

    # LAST, AFTER THE CLEANUP PROSE, DELIBERATELY.  Putting it beside the
    # summary table left eight lines between the verdict and the end of the
    # file, so a `tail` of the log - which is how these are read - showed the
    # prose and not the result.  The verdict is the last thing printed.
    Write-Verdict 'verify-createaccount'

    if ($fatal) { exit 1 }
    exit 0
}
catch {
    Write-Output ("verify-createaccount: FAILED - " + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    Write-Output "--- cleaning up the Windows half after the failure ---"
    try { Remove-Made } catch { Write-Output ("cleanup itself failed: " + $_.Exception.Message) }
    exit 1
}
finally {
    Remove-Item Env:\SDACCTPW -ErrorAction SilentlyContinue
    # 19 Aug 26 - EVERY exit INSIDE THE try ABOVE PASSES THROUGH HERE, which is
    # why the transcript is closed here rather than beside each one.  It matters
    # when this is called from post-cycle-elevated.ps1: a transcript left running
    # would swallow the NEXT verifier's output into this file.
    try { Stop-Transcript | Out-Null } catch { }
}
