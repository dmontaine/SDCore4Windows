# allow-ssh-groups.ps1 - the second layer of the ssh-only model: decide who may
# ssh into this machine at all.  PROJECT_STATUS.md 5.6.2.
#
#   powershell -ExecutionPolicy Bypass -File allow-ssh-groups.ps1 -Installed write the block and restart sshd
#   powershell -ExecutionPolicy Bypass -File allow-ssh-groups.ps1 -Check     print what it would write, touch nothing
#   powershell -ExecutionPolicy Bypass -File allow-ssh-groups.ps1 -Remove    take SD's block back out
#
# Exit 0 done (or nothing to do), 1 failed, 2 refused - see "WHEN IT REFUSES".
#
# 27 Aug 26 - -Installed ADDED TO THE FIRST LINE ABOVE, WHICH HAD BEEN WRONG
# since the 21 Aug change of what that switch asserts.  The bare form documented
# here writes nothing: the test at the foot of this file exits 2 without it.
# -Check and -Remove return before that test and are right as written.
# PRE_RELEASE_FIXES.md 33.
#
# The deny rights in deny-logon.ps1 say where an account may NOT log in.  This
# says who may ssh.  Two independent controls: an account has to be in an
# allowed group AND not be denied the console, and neither one implies the
# other.  Suggested by the repository owner, 14 Aug 2026.
#
# WHEN IT REFUSES, and why refusing is the point.
#
#   1. If -Installed was not passed.  WHAT THAT SWITCH ASSERTS CHANGED ON
#      21 Aug 2026 and the old wording is kept here because it was wrong in a
#      way worth seeing: it said "SD did not install this ssh server", and the
#      installer only offered the task under Check: SshServerAbsent.
#
#      THAT MADE THE TASK A ONE-SHOT.  SD's own first install puts sshd.exe on
#      the machine for ever, uninstall always strips SD's block, and
#      SshServerAbsent asks what was true BEFORE the install began - so after
#      the first cycle the task could never be offered again, and this machine
#      was found on 21 Aug 2026 with a stock sshd_config: no AllowGroups and,
#      worse, no ForceCommand, so an sdsshonly account got a PowerShell prompt.
#
#      SO -Installed NOW MEANS "AN ADMINISTRATOR ASKED FOR THIS", and the task
#      is offered on any machine.
#
#      CORRECTED 24 Aug 2026 - the previous wording here said the task was
#      "unticked by default" and that this backstopped PROJECT_STATUS.md 5.9's
#      "never reconfigure an ssh server we did not install".  Neither half
#      held.  sd.iss:210 carries no Flags: unchecked, so the task is TICKED by
#      default (sd.iss:181-186 records the deliberate flip: "the model is what
#      SD expects to be running under rather than an option somebody
#      remembers").  What is actually left carrying 5.9 is REFUSAL 2 BELOW -
#      the existing-Allow/Deny check - plus the description at sd.iss:210
#      naming scp and sftp as the sharp edges.  On a machine with sshd but
#      NO Allow/Deny line, the default tick will apply the block on the next
#      install unless the administrator unticks it in the wizard.  That is
#      the exposure PROJECT_STATUS.md 5.9 leaves as an owner decision.
#
#      Running this script by hand still needs -Installed, which is what
#      keeps it from being a thing that happens by accident from the CLI.
#   2. If sshd_config already restricts who may connect.  An existing
#      AllowGroups, AllowUsers, DenyGroups or DenyUsers line is somebody's
#      policy, and merging into it blind is how you either widen it silently or
#      lock its author out.  SD's OWN block is exempt: it is fenced by the
#      markers below, so re-running replaces it rather than stacking.
#
# 18 Sep 26, LATER THE SAME DAY - ***THE RESULT STANDS BUT THE REASON CHANGED:
# RELEASE_1.1 64 REMOVES THE TIERS.***  The list stays sdssh-alone, not because
# an administrator has no remote door (64 gives every account ssh), but because
# routes are per-account memberships and no account is special: ssh admission
# is the account's own sdssh grant, and a Windows administrator's SD account is
# an ordinary account.  The 58 entry below is kept as the record of the
# earlier ruling; DisableForwarding stays under either model.
#
# 18 Sep 26 - ***ADMINISTRATORS ARE NOT IN THIS LIST ANY MORE. THE CONSOLE IS
# THE ONLY DOOR THEY HAVE.***  Owner's ruling, 18 Sep 2026, asked for as "the
# most secure solution that is possible": an administrator gets NO remote door,
# neither ssh nor the API, and losing LOCAL admin ssh is accepted - "ssh on the
# local machine is a convenience for us, but we can use a virtual machine to
# test ssh instead.  I don't have any problem with it not being available on the
# local computer."  RELEASE_1.1_FIXES.md 58.
#
# ***THE ARGUMENT THAT STOOD HERE WAS SOUND AND IS KEPT, BECAUSE ONLY ITS
# PREMISE DIED.***  It read: "THE LIST MUST INCLUDE ADMINISTRATORS, or the
# machine's own administrator loses ssh - the caution in 5.6.2"; and, on
# 5 Sep 26, "AND 167 IS NOT A REASON TO TAKE IT OUT.  READ THIS BEFORE YOU DO.
# ... THAT WOULD BREAK THE RULING RATHER THAN ENFORCE IT.  The owner's
# refinement of the same day keeps LOCAL ssh working for an administrator - 'if
# I am at the console, everything works, only remote access is denied' - and
# AllowGroups cannot tell one from the other: it matches on the GROUP, not the
# source, so removing the entry takes loopback with it."  ***EVERY WORD OF THAT
# IS STILL TRUE.  WHAT CHANGED IS THAT LOOPBACK ssh IS NO LONGER WANTED***, so
# the property AllowGroups cannot express is one nobody needs expressed.  The
# same paragraph also said the "Match Address 127.0.0.1,::1" hardening "IS THE
# OWNER'S TO ASK FOR" - he asked for more than it, and a group line he now gets
# to write plainly is safer than a Match block whose scope runs to end of file.
#
# ***AND LOGIN'S PEER TEST STAYS.***  PRE_RELEASE 170 is witnessed (b126) and is
# not being retired: it now guards a door the transport has already shut, which
# is the arrangement to want.  What is NOT acceptable is a single layer, and the
# reason is in the next paragraph.
#
# 18 Sep 26 - ***DisableForwarding, BECAUSE ForceCommand DOES NOT CONSTRAIN A
# FORWARD AND THE API'S PEER TEST CANNOT SEE THROUGH ONE.***  verify-apiremote
# wrote this down on 5 Sep and nothing acted on it: "an 'ssh -L' tunnel
# terminates on this host, so a tunnelled API connection is accepted FROM
# 127.0.0.1 and this gate reads it as local.  No peer test can see through
# that; it is an sshd matter".  Measured 18 Sep 2026 on this machine:
# sshd_config line 58 read "#AllowTcpForwarding yes" - commented, so the default
# (yes) applied - PermitOpen was unset, and "ssh -N" opens no session channel at
# all, so ForceCommand is never consulted on that path.  So any sdssh member
# could have sshd open a connection to 127.0.0.1:4243 on their behalf.
#
#   - DisableForwarding covers tcp, StreamLocal, agent, X11 and tun in one
#     keyword rather than four that can drift apart.  It is a recognised keyword
#     in the shipped server - OpenSSH_for_Windows_9.5p2, and the keyword table
#     was checked in the binary against a negative control.
#   - It is GLOBAL, like ForceCommand and for the same reason: the rule is about
#     the route in, not about who took it.  Nothing in gplbld forwards - the one
#     match across the directory was verify-apiremote's comment above - so no
#     verifier pays for this.
#   - scp and sftp were already gone with ForceCommand; this takes port
#     forwarding, which was the half that survived it.
#
# ***TWO INDEPENDENT LAYERS, DELIBERATELY.***  Administrators leave sdapi in the
# same change (CREATEA, MODIFYA), so a tunnelled connection now reaches a door
# that admits no administrator even if it believes the peer is local.  Either
# layer alone would hold; neither alone is where the boundary should rest.
#
# ***AND SSH_CLIENT ONLY WORKS AS A SECURITY SIGNAL WHILE THIS FILE LEAVES THE
# ENVIRONMENT ALONE.***  Measured 5 Sep 2026: sshd_config carries no AcceptEnv
# line and leaves PermitUserEnvironment at its default of "no", so a client
# cannot send or plant environment variables and sshd sets SSH_CLIENT itself
# after authentication.  If either ever changes here, LOGIN's peer test stops
# being trustworthy - it is the only thing standing between a remote
# administrator and SDSYS.
#
# BY SID, RESOLVED TO A NAME.  sshd's AllowGroups takes name patterns and has
# no SID syntax, but BUILTIN\Administrators is renamed on a localised Windows -
# so the literal "Administrators" is exactly the bug that locks out the German
# machine.  Resolve S-1-5-32-544 to whatever it is called here and write that.
# CREATEA does the same thing for the same reason; see its comment at the
# Administrators add.
#
# FOUR PATTERNS FOR TWO GROUPS, deliberately.  Win32-OpenSSH matches a group as
# "domain\group", with the computer name standing in for the domain on a local
# account, and reports of the bare name working on its own are mixed across
# versions.  Both forms are written for each group.  A pattern that matches
# nothing costs nothing - AllowGroups is a union - so listing both removes a
# question that would otherwise have to be answered per Windows build, and the
# failure it avoids is a lockout.
#
# IT GOES BEFORE THE FIRST Match BLOCK, NOT AT THE END OF THE FILE.  Everything
# after a Match line in sshd_config belongs to that Match, and the sshd_config
# Windows ships ends with "Match Group administrators".  Appending would put
# AllowGroups inside that block, where it would apply to administrators only -
# which reads as working and is the opposite of what it says.
#
# AND IT IS TESTED BEFORE IT IS KEPT.  sshd -T parses the config and exits
# non-zero if it cannot; the original is put back and sshd is left alone if it
# fails.  That catches a malformed file, not a wrong policy - nothing offline
# can tell you a pattern matches the wrong set of people, which is why -Check
# exists and why the installer says what it wrote.

param(
    [switch]$Installed,
    [switch]$Check,
    [switch]$Remove,

    # Where sd.exe is, for the ForceCommand block below.  Set in the body if
    # not given - and NOT as a param default, because $PSScriptRoot comes out
    # empty in one (gplbld/adopt-account.ps1 records what that cost).
    [string]$SdExe = ''
)

$ErrorActionPreference = 'Stop'

if (-not $SdExe) { $SdExe = Join-Path $PSScriptRoot 'usr\bin\sd.exe' }

$cfg     = Join-Path $env:ProgramData 'ssh\sshd_config'
$backup  = Join-Path $env:ProgramData 'ssh\sshd_config.before-sd'
$sshd    = Join-Path $env:SystemRoot  'System32\OpenSSH\sshd.exe'
$begin   = '# --- BEGIN SD ssh-only model - PROJECT_STATUS.md 5.6.2 ---'
$end     = '# --- END SD ssh-only model ---'

# Returns the AllowGroups patterns, or $null with a reason on stdout.
function Get-Patterns {
    # 18 Sep 26 - THE REFUSAL CHANGED TARGET WITH THE LIST.  It used to resolve
    # S-1-5-32-544 and refuse if it could not, because the administrators group
    # was one of the two names written here; that name is gone (see the header),
    # so the guard would have been left measuring nothing - and a guard that
    # cannot fail is the vacuous pass PROJECT_STATUS.md 0 forbids.
    #
    # WHAT IS WORTH REFUSING NOW IS THE LOCKOUT THE PARAGRAPH BELOW DESCRIBES.
    # sdssh is the ONLY name in the line now, so writing it while the group does
    # not exist denies ssh to everybody, with no administrators entry left to
    # get back in through.  sd.iss calls sync-route-groups.ps1 first, which
    # creates and seeds it, so this should never fire on an install - it fires
    # for a hand run in the wrong order, which is exactly when it is wanted.
    $sdssh = Get-LocalGroup -Name 'sdssh' -ErrorAction SilentlyContinue
    if ($null -eq $sdssh) {
        # Write-Host, NOT Write-Output (20 Sep 26): a function's Write-Output lines ARE its return
        # value, so this refusal text was folded into $patterns as a SECOND element next to the
        # $null below, "$null -eq $patterns" was false, and the caller carried on to write an
        # AllowGroups line containing the refusal message.  Found by the scan that
        # test-outputtrap-units.ps1 now makes permanent.  (This file ships; the path is only
        # reachable when sdssh does not exist, which sd.iss's order prevents.)
        Write-Host "allow-ssh-groups: the sdssh group does not exist - refusing to write an AllowGroups line that would deny ssh to every account (run gplbld/sync-route-groups.ps1 first)"
        return $null
    }
    # 21 Aug 26 Windows port - sdssh, NOT sdusers.  sdusers grants access to the
    # data FILES, so while it was the group named here "may read SD's files" and
    # "may ssh into this machine" were one fact: ssh could not be withdrawn from
    # an account without taking its files away as well.  They are separate now -
    # CREATE.ACCOUNT joins both, and MODIFY.ACCOUNT <account> NO.SSH removes only
    # this one.  Owner's decision, 21 Aug 2026.
    #
    # THE GROUP MUST EXIST AND BE POPULATED BEFORE THIS RUNS.  On an existing
    # installation every account is in sdusers and none is in sdssh, so writing
    # this line against an empty group locks all of them out at the next sshd
    # restart.  gplbld/sync-route-groups.ps1 creates it and seeds it from
    # sdusers, and sd.iss calls that FIRST - see the ordering comment there.
    # 18 Sep 26 - sdssh ALONE.  The administrators group left this list on the
    # owner's 18 Sep ruling; the header carries the argument it replaced.
    $names = @('sdssh')
    $out = New-Object System.Collections.ArrayList
    foreach ($n in $names) {
        $null = $out.Add($n)
        $null = $out.Add($env:COMPUTERNAME + '\' + $n)
    }
    return $out.ToArray()
}

# sshd_config lines that already decide who may connect, ignoring SD's own.
function Get-ExistingRestrictions([string[]]$lines) {
    $inOurs = $false
    $found = New-Object System.Collections.ArrayList
    foreach ($l in $lines) {
        if ($l -eq $begin) { $inOurs = $true; continue }
        if ($l -eq $end)   { $inOurs = $false; continue }
        if ($inOurs) { continue }
        if ($l -match '^\s*(AllowGroups|AllowUsers|DenyGroups|DenyUsers)\b') {
            $null = $found.Add($l.Trim())
        }
    }
    return $found.ToArray()
}

function Remove-OurBlock([string[]]$lines) {
    $out = New-Object System.Collections.ArrayList
    $inOurs = $false
    foreach ($l in $lines) {
        if ($l -eq $begin) { $inOurs = $true; continue }
        if ($l -eq $end)   { $inOurs = $false; continue }
        if (-not $inOurs) { $null = $out.Add($l) }
    }
    return $out.ToArray()
}

# See the header: before the first Match, or at the end if there is none.
#
# NO BLANK LINE FOR READABILITY.  (This said "EXACTLY THREE LINES" until
# 18 Sep 26, when DisableForwarding made it four, or five with ForceCommand.
# The count was never the point and naming it here invited this comment to rot;
# verify-allowgroups asserts the arithmetic, which is where it belongs.)
# A blank line looks
# harmless and is not: it falls outside the markers, so Remove-OurBlock leaves
# it behind and every apply/remove cycle grows the file by one line.  Measured
# 14 Aug 2026 - the round trip was not byte-identical and a second run was not
# idempotent.  Add and Remove have to be exact inverses; the markers are
# comments and separate the block well enough on their own.
#
# AND ForceCommand IN THE SAME BLOCK: EVERY ssh SESSION LANDS IN SD.
# Owner's rule, 15 Aug 2026, in two parts - an SD account exists to use SD and
# should not be left at a PowerShell prompt, AND an ADMINISTRATOR CONNECTING
# REMOTELY GETS SD TOO.  So this is global rather than a "Match Group
# sdsshonly" block: the rule is about the route in, not about who took it.
#
# It fits the access model rather than straining it.  An ssh session cannot be
# elevated (PROJECT_STATUS.md 4), so an administrator arriving this way was
# already going to land in their OWN account and not SDSYS; forcing the command
# only removes the shell they could not have administered the machine from
# anyway.  Local console and Remote Desktop are untouched, which is where
# administration happens.
#
# NOT THE DefaultShell REGISTRY KEY.  HKLM\SOFTWARE\OpenSSH\DefaultShell would
# do the same job and lives outside sshd_config, where this script's markers
# cannot reverse it and -Remove could not put the machine back.  One file, one
# marked block, exactly invertible.
#
# scp and sftp stop working for everyone as a consequence - the command is
# forced, so there is no subsystem left to run.  That follows from the
# decision; it is not a side effect that was missed.
function Add-OurBlock([string[]]$lines, [string[]]$patterns, [string]$sdexe = '') {
    # 18 Sep 26 - DisableForwarding IN BOTH ARMS.  It does not depend on whether
    # SdExe resolved: a build that could not find sd.exe still must not leave
    # port forwarding open, and putting it in one arm only is how the two arms
    # drift.  See the header for why it is here at all.
    if ($sdexe) {
        $block = @($begin,
                   ('AllowGroups ' + ($patterns -join ' ')),
                   ('ForceCommand "' + $sdexe + '"'),
                   'DisableForwarding yes',
                   $end)
    }
    else {
        $block = @($begin,
                   ('AllowGroups ' + ($patterns -join ' ')),
                   'DisableForwarding yes',
                   $end)
    }
    $at = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^\s*Match\b') { $at = $i; break }
    }
    if ($at -lt 0) { return @($lines + $block) }
    return @($lines[0..($at - 1)] + $block + $lines[$at..($lines.Count - 1)])
}

try {
    $patterns = Get-Patterns
    if ($null -eq $patterns) { exit 1 }

    if ($Check) {
        # Deliberately does not read sshd_config: this is the half that can be
        # inspected without elevation, and the group names are the half that
        # can be wrong.
        Write-Output ("allow-ssh-groups: would write:  AllowGroups " + ($patterns -join ' '))
        Write-Output ("allow-ssh-groups: administrators group resolves to '" + (Get-LocalGroup -SID 'S-1-5-32-544').Name + "' on this machine")
        Write-Output ("allow-ssh-groups: target " + $cfg)
        exit 0
    }

    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Output "allow-ssh-groups: not elevated - C:\ProgramData\ssh is not readable without it"
        exit 1
    }

    if (-not (Test-Path $cfg)) {
        # sshd writes its config on first start, so this means sshd has never
        # run.  Not an error worth failing an install over.
        Write-Output ("allow-ssh-groups: no " + $cfg + " - sshd has not started yet, nothing to edit")
        exit 2
    }

    $lines = @(Get-Content -Path $cfg)

    if ($Remove) {
        $new = Remove-OurBlock $lines
        if ($new.Count -eq $lines.Count) {
            Write-Output "allow-ssh-groups: no SD block present, nothing removed"
            exit 0
        }
        Set-Content -Path $cfg -Value $new -Encoding ascii
        Restart-Service sshd -ErrorAction SilentlyContinue
        Write-Output "allow-ssh-groups: SD block removed, sshd restarted"
        exit 0
    }

    if (-not $Installed) {
        Write-Output "allow-ssh-groups: -Installed not given - this rewrites sshd_config and restarts sshd, so it has to be asked for"
        exit 2
    }

    $existing = Get-ExistingRestrictions $lines
    if ($existing.Count -gt 0) {
        Write-Output "allow-ssh-groups: sshd_config already says who may connect, leaving it alone:"
        foreach ($e in $existing) { Write-Output ("    " + $e) }
        exit 2
    }

    if (-not (Test-Path $backup)) { Copy-Item -Path $cfg -Destination $backup }
    $original = $lines

    $new = Add-OurBlock (Remove-OurBlock $lines) $patterns $SdExe
    Set-Content -Path $cfg -Value $new -Encoding ascii

    # sshd -T parses the file and exits non-zero if it cannot.  No inline
    # "2>&1": PowerShell 5.1 turns a native program's stderr into a terminating
    # error under 'Stop', which would send a perfectly good config to the catch.
    $errFile = Join-Path $env:TEMP 'sd-sshd-t.err'
    $outFile = Join-Path $env:TEMP 'sd-sshd-t.out'
    $p = Start-Process -FilePath $sshd -ArgumentList '-T' -NoNewWindow -Wait -PassThru `
             -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    if ($p.ExitCode -ne 0) {
        Set-Content -Path $cfg -Value $original -Encoding ascii
        Write-Output ("allow-ssh-groups: sshd -T rejected the result, PUT THE ORIGINAL BACK.  sshd said:")
        if (Test-Path $errFile) { Get-Content $errFile | ForEach-Object { Write-Output ("    " + $_) } }
        Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
        exit 1
    }
    Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue

    Restart-Service sshd
    Write-Output ("allow-ssh-groups: wrote  AllowGroups " + ($patterns -join ' '))
    Write-Output ("allow-ssh-groups: original kept at " + $backup)
    Write-Output ("allow-ssh-groups: sshd is " + (Get-Service sshd).Status)
    exit 0
}
catch {
    Write-Output ("allow-ssh-groups: FAILED - " + $_.Exception.Message)
    Write-Output $_.ScriptStackTrace
    exit 1
}
