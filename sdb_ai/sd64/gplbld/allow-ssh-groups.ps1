# allow-ssh-groups.ps1 - the second layer of the ssh-only model: decide who may
# ssh into this machine at all.  PROJECT_STATUS.md 5.6.2.
#
#   powershell -File allow-ssh-groups.ps1            write the block and restart sshd
#   powershell -File allow-ssh-groups.ps1 -Check     print what it would write, touch nothing
#   powershell -File allow-ssh-groups.ps1 -Remove    take SD's block back out
#
# Exit 0 done (or nothing to do), 1 failed, 2 refused - see "WHEN IT REFUSES".
#
# The deny rights in deny-logon.ps1 say where an account may NOT log in.  This
# says who may ssh.  Two independent controls: an account has to be in an
# allowed group AND not be denied the console, and neither one implies the
# other.  Suggested by the repository owner, 14 Aug 2026.
#
# WHEN IT REFUSES, and why refusing is the point.
#
#   1. If SD did not install this ssh server.  PROJECT_STATUS.md 5.9: we never
#      reconfigure an ssh server we did not install - it may be there for
#      something else and may be managed by policy.  The installer only offers
#      this alongside its own OpenSSH install; the -Installed switch is how it
#      says so, and without it this script does nothing.
#   2. If sshd_config already restricts who may connect.  An existing
#      AllowGroups, AllowUsers, DenyGroups or DenyUsers line is somebody's
#      policy, and merging into it blind is how you either widen it silently or
#      lock its author out.  SD's OWN block is exempt: it is fenced by the
#      markers below, so re-running replaces it rather than stacking.
#
# THE LIST MUST INCLUDE ADMINISTRATORS, or the machine's own administrator
# loses ssh - the caution in 5.6.2, and the reason this is an offer rather than
# something a verb does silently.
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
    [switch]$Remove
)

$ErrorActionPreference = 'Stop'

$cfg     = Join-Path $env:ProgramData 'ssh\sshd_config'
$backup  = Join-Path $env:ProgramData 'ssh\sshd_config.before-sd'
$sshd    = Join-Path $env:SystemRoot  'System32\OpenSSH\sshd.exe'
$begin   = '# --- BEGIN SD ssh-only model - PROJECT_STATUS.md 5.6.2 ---'
$end     = '# --- END SD ssh-only model ---'

# Returns the AllowGroups patterns, or $null with a reason on stdout.
function Get-Patterns {
    $admins = Get-LocalGroup -SID 'S-1-5-32-544' -ErrorAction SilentlyContinue
    if ($null -eq $admins) {
        Write-Output "allow-ssh-groups: cannot resolve S-1-5-32-544 - refusing to guess at the administrators group"
        return $null
    }
    $names = @('sdusers', $admins.Name)
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
# EXACTLY THREE LINES, AND NO BLANK ONE FOR READABILITY.  A blank line looks
# harmless and is not: it falls outside the markers, so Remove-OurBlock leaves
# it behind and every apply/remove cycle grows the file by one line.  Measured
# 14 Aug 2026 - the round trip was not byte-identical and a second run was not
# idempotent.  Add and Remove have to be exact inverses; the markers are
# comments and separate the block well enough on their own.
function Add-OurBlock([string[]]$lines, [string[]]$patterns) {
    $block = @($begin, ('AllowGroups ' + ($patterns -join ' ')), $end)
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
        Write-Output "allow-ssh-groups: -Installed not given - SD only configures an ssh server it installed itself (5.9)"
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

    $new = Add-OurBlock (Remove-OurBlock $lines) $patterns
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
