# verify-createaccount.ps1 - run CREATE.ACCOUNT USER against a throwaway name
# and check both halves of what it makes, including the ssh-only branch.
#
#   powershell -File verify-createaccount.ps1            create, check, clean up
#   powershell -File verify-createaccount.ps1 -Keep      leave the account behind
#   powershell -File verify-createaccount.ps1 -Cleanup   remove one left by -Keep
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
    [string]$Account = 'sdacct1',
    [string]$Group   = 'sdsshonly',
    [switch]$Keep,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'

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
function Invoke-Native {
    param([string]$Exe, [string[]]$CmdArgs)
    $so = Join-Path $workdir 'native.out'
    $se = Join-Path $workdir 'native.err'
    $si = Join-Path $workdir 'native.in'
    Set-Content -Path $si -Value $null -Encoding ascii
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
            ($Account + '@localhost'), 'whoami')
    } finally {
        Remove-Item Env:\SDACCTPW, Env:\SSH_ASKPASS, Env:\SSH_ASKPASS_REQUIRE, Env:\DISPLAY -ErrorAction SilentlyContinue
        Remove-Item $askpass -ErrorAction SilentlyContinue
    }
    if ($r.ExitCode -eq 0 -and $r.Out -match [regex]::Escape($Account)) { return 'admitted' }
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
    $body = "`n" + (($commands + @('OFF')) -join "`n") + "`n"
    $out = $body | & $sdExe -ASDSYS
    return (($out -replace "`e\[[0-9]*[A-Za-z]", '') -join "`n")
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
    if (Test-Path (Join-Path $env:SystemDrive ('Users\' + $Account))) {
        Remove-Item -Recurse -Force (Join-Path $env:SystemDrive ('Users\' + $Account)) -ErrorAction SilentlyContinue
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

    Write-Output ""
    Write-Output "=== 1. CREATE.ACCOUNT USER $Account ====================================="
    $sdOut = Invoke-SD @(('CREATE.ACCOUNT USER ' + $Account), $plain, $plain)
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
    # $SVLISTS, not $SAVEDLISTS.  CREATEA prints "Creating $SAVEDLISTS..." and
    # then creates a directory called $SVLISTS - the message is the VOC name,
    # the directory is the DH file name.  This test asserted the message and
    # failed against a perfectly good account on 14 Aug 2026.
    foreach ($f in @('VOC', '$HOLD', '$SVLISTS', 'BP')) {
        Note ('  ' + $f) 'yes' $(if (Test-Path (Join-Path $acctDir $f)) { 'yes' } else { 'no' }) $true
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
}
