# sd-radmin.ps1 - the remote administration broker: one named pipe, one caller, a fixed list of SD account commands
#
# 13 Nov 26 Windows port - written for RELEASE_1.1 202 (design .claude/design-remote-admin-20261113.md, section 5; the owner's answers of
# 13 Nov 2026: Q3 the list, Q8 the job route).
#
#   sd-radmin.ps1 -Serve     the broker; run by the task \SD\sdcore-radmin that remote-admin.ps1 -On registers (SDSYS, S4U, highest run
#                            level, at start-up) and nothing else
#
# WHAT IT IS FOR.  The remote administration account SDRADMIN is an ordinary SD user: unelevated, never in Administrators.  The SD files an
# account command writes (the register, $cred, the account directories, the Windows users and groups) need an elevated SDSYS, which Linux's
# sdsys does not (there sdsys owns SD's files and is not root) - so on Windows the helper's list is a list of SD COMMANDS, each run exactly
# as the console runs it, by an elevated SDSYS scheduled-job process (RELEASE_1.1 222's route: K$JOB.MARK), never a list of OS operations.
#
# THE WALL IS THIS SCRIPT'S CHECKS (Linux F12's lesson: "each verb is a wall only as far as its own checks go"), in this order:
#   1. The pipe \\.\pipe\sd-radmin admits two SIDs: SDSYS (full control) and SDRADMIN (read and write); nobody else can open it.  It is the
#      only instance (maxNumberOfServerInstances 1, which .NET opens with FILE_FLAG_FIRST_PIPE_INSTANCE), so a pipe somebody made first
#      stops the broker rather than being joined.
#   2. The CALLER's token, read by impersonating it (identification level is enough): its user must be SDRADMIN's SID, and it must be a
#      NETWORK logon (sshd's password sign-in) and not an interactive, batch or service one.
#   3. Remote administration must be on (<ProgramData>\SD\remote-admin\state).
#   4. The REQUEST: ASCII "key=value" lines, at most 4096 bytes, ending in a line "end", read within 10 seconds.  version=1, verb=, word1..
#      wordN= (contiguous, at most 16), nonce= (16 lower-case hex), secret= (hex, only for the two commands that take a password).  An
#      unknown, repeated or missing key is a refusal.
#   5. The COMMAND: the verb from five, each word from that verb's own list or an account name (a lower-case letter, then lower-case letters,
#      digits, _ and -, 20 at most), never a reserved name (sdsys, sdradmin, shared, SD's own groups, Windows' built-in accounts).
#      Radmin_request below; the command line is BUILT here from the checked words, no request text is copied into it.
#   6. The TARGETS on Windows: an account name that is a Windows user must carry SD's stamp ("SD account") and must not be in Administrators.
# Then it writes the one-shot job definition <ProgramData>\SD\sd-jobs\radmin-<nonce> (SYSTEM and Administrators only, as sd-jobs.ps1 writes
# them), starts "<app>\usr\bin\sd.exe -job radmin-<nonce> remote.sdsys run <verb> <words>" as its own child (same token: SDSYS's elevated
# batch logon, which K$JOB.MARK asks for), hands the password - when there is one - to the child's STANDARD INPUT, closes it, and waits
# 180 seconds.  REMOTE.SDSYS RUN (gpl.bp/remotesdsys) deletes the definition as it starts (the consumer closes the door, as LOGIN's
# internal marker) and runs the console verb with the password in its DATA queue.
#
# THE PASSWORD IS NEVER ON A COMMAND LINE, IN A FILE THIS SCRIPT WRITES, IN ITS LOG OR IN THE ANSWER: it arrives in the request, goes to the
# child's standard input and nowhere else, and every occurrence of it in what the child printed is replaced by ******** before the
# answer is sent.
#
# THE ANSWER: "nonce=<the request's>", one "out=<line>" per line the command printed, "exit=<the child's exit status>", "end".  A refusal
# is "nonce=...", "refused=<why>", "end" (no nonce when the request could not be read).  When the child has not finished in 180 seconds
# the answer is "timeout=<pid>" and THE CHILD IS LEFT RUNNING: an SD session is never killed (it can leave the shared memory wrong);
# LOGOUT at the console ends it.
#
# THE LOG: <ProgramData>\SD\remote-admin\broker.log, SYSTEM and Administrators only, one line per request: the verb, the words (account
# names and keywords), the caller's SID, the nonce and the result - never the password.  1 MB, then broker.log.1.

param(
    [switch]$Serve
)

$env:PSModulePath = "$env:ProgramFiles\WindowsPowerShell\Modules;$env:SystemRoot\system32\WindowsPowerShell\v1.0\Modules"
$ErrorActionPreference = 'Stop'
$Prog = 'sd-radmin'

# BEGIN radmin_request
# The pure part: reading and checking a request and building the command.  gplbld/test-remoteadmin-units.ps1 lifts this block out and drives
# it with good and bad requests; its mutants break each check here.
$RadminVerbs = @('create.account', 'delete.account', 'modify.account', 'modify.password', 'remote.sdsys')
$RadminRoutes = @('ssh', 'api', 'both', 'none')
$RadminStarts = @('start-menu', 'start-terminal', 'start-default')
$RadminCreateUser = @('ssh', 'api', 'both', 'none', 'sh-on', 'os-on', 'voc-on', 'bp-on', 'dict-on', 'net-on', 'files-on', 'files-write-on',
                      'files-admin-on', 'shared-read-off', 'shared-write-on', 'start-menu', 'start-terminal', 'pins-on', 'recovery-on')
$RadminCreateGroup = @('start-menu', 'start-terminal', 'pins-on')
$RadminModify = @('ssh', 'api', 'both', 'none', 'sh-on', 'sh-off', 'os-on', 'os-off', 'sd-on', 'sd-off', 'voc-on', 'voc-off', 'bp-on', 'bp-off',
                  'dict-on', 'dict-off', 'recovery-on', 'recovery-off', 'net-on', 'net-off', 'files-on', 'files-off', 'files-write-on',
                  'files-write-off', 'files-admin-on', 'files-admin-off', 'shared-read-on', 'shared-read-off', 'shared-write-on',
                  'shared-write-off', 'start-menu', 'start-terminal', 'start-default', 'pins-on', 'pins-off', 'suspended', 'unsuspended')
$RadminReports = @('off', 'status', 'audit', 'accounts')
# Never a target from here: SD's own accounts and groups, and Windows' built-in accounts.  Matched after the name test, so lower case.
$RadminReserved = @('sdsys', 'sdradmin', 'shared', 'sdusers', 'sdssh', 'sdsshonly', 'sdapi', 'sdfiles', 'sdfileswrite', 'sdfilesadmin',
                    'sdaiusers', 'administrator', 'administrators', 'guest', 'defaultaccount', 'wdagutilityaccount', 'system')
$RadminKeys = @('version', 'verb', 'nonce', 'secret') + @(1..16 | ForEach-Object { 'word' + $_ })

function Test-RadminName([string]$n) {
    if ($n -cnotmatch '^[a-z][a-z0-9_-]{0,19}$') { return $false }
    return ($RadminReserved -cnotcontains $n)
}

function ConvertFrom-RadminRequest([string]$text) {
    # @{ Ok = $true; Verb; Words; Nonce; Secret (bytes, or $null) } or @{ Ok = $false; Why; Nonce (when one was read) }
    $r = @{ Ok = $false; Why = ''; Nonce = '' }
    if ($text.Length -gt 4096) { $r.Why = 'the request is longer than 4096 bytes'; return $r }
    if ($text -cmatch '[^\x0a\x0d\x20-\x7e]') { $r.Why = 'the request holds a byte that is not printable ASCII'; return $r }
    $lines = New-Object System.Collections.ArrayList
    foreach ($l in @($text -split "`r?`n")) { $null = $lines.Add($l) }
    while ($lines.Count -gt 0 -and $lines[$lines.Count - 1] -eq '') { $lines.RemoveAt($lines.Count - 1) }
    if ($lines.Count -lt 1 -or $lines[$lines.Count - 1] -cne 'end') { $r.Why = 'the request does not end with the line "end"'; return $r }
    $f = @{}
    for ($i = 0; $i -lt $lines.Count - 1; $i++) {
        $l = $lines[$i]
        $k = $l.IndexOf('=')
        if ($k -lt 1) { $r.Why = 'a line of the request is not key=value'; return $r }
        $key = $l.Substring(0, $k)
        if ($RadminKeys -cnotcontains $key) { $r.Why = "the request has a key it may not have ($key)"; return $r }
        if ($f.ContainsKey($key)) { $r.Why = "the request has the key $key twice"; return $r }
        $f[$key] = $l.Substring($k + 1)
    }
    if ($f.ContainsKey('nonce') -and $f['nonce'] -cmatch '^[0-9a-f]{16}$') { $r.Nonce = $f['nonce'] }
    if ($r.Nonce -eq '') { $r.Why = 'the request has no nonce of 16 lower-case hexadecimal digits'; return $r }
    if (-not $f.ContainsKey('version') -or $f['version'] -cne '1') { $r.Why = 'the request is not version 1'; return $r }
    if (-not $f.ContainsKey('verb') -or $RadminVerbs -cnotcontains $f['verb']) { $r.Why = 'the command is not one remote administration may run'; return $r }
    $words = @()
    for ($i = 1; $i -le 16; $i++) {
        if (-not $f.ContainsKey('word' + $i)) { break }
        $words += $f['word' + $i]
    }
    $nw = @($f.Keys | Where-Object { $_ -cmatch '^word' }).Count
    if ($nw -ne $words.Count) { $r.Why = 'the words of the request are not numbered from 1 without a gap'; return $r }
    foreach ($w in $words) {
        if ($w -cnotmatch '^[a-z0-9][a-z0-9_.-]{0,31}$') { $r.Why = 'a word of the command is not a lower-case word or a number'; return $r }
    }
    $secret = $null
    if ($f.ContainsKey('secret')) {
        $h = $f['secret']
        if ($h -cnotmatch '^([0-9a-f]{2}){1,256}$') { $r.Why = 'the password is not hexadecimal or is longer than 256 bytes'; return $r }
        $secret = New-Object byte[] ($h.Length / 2)
        for ($i = 0; $i -lt $secret.Length; $i++) { $secret[$i] = [Convert]::ToByte($h.Substring($i * 2, 2), 16) }
        foreach ($b in $secret) {
            if ($b -lt 0x20 -or $b -eq 0x7f) { $r.Why = 'the password holds a control character'; return $r }
        }
    }
    return @{ Ok = $true; Why = ''; Verb = $f['verb']; Words = $words; Nonce = $r.Nonce; Secret = $secret }
}

function Test-RadminWordSet([string[]]$ws, [string[]]$allowed) {
    # '' when every word is in the list, none is repeated, and at most one route word and one start word are given; else why.
    $seen = @{}
    $routes = 0; $starts = 0
    foreach ($w in $ws) {
        if ($allowed -cnotcontains $w) { return "$w is not a keyword remote administration may give here" }
        if ($seen.ContainsKey($w)) { return "$w is given twice" }
        $seen[$w] = 1
        if ($RadminRoutes -ccontains $w) { $routes++ }
        if ($RadminStarts -ccontains $w) { $starts++ }
    }
    if ($routes -gt 1) { return 'more than one of ssh, api, both and none' }
    if ($starts -gt 1) { return 'more than one start word' }
    return ''
}

function Get-RadminPlan($req) {
    # @{ Ok; Why; Command; Targets; NeedsSecret }.  THE COMMAND IS BUILT FROM THE CHECKED WORDS ONLY.
    $p = @{ Ok = $false; Why = ''; Command = ''; Targets = @(); NeedsSecret = $false }
    $v = $req.Verb
    $w = @($req.Words)
    switch -CaseSensitive ($v) {
        'create.account' {
            if ($w.Count -lt 2 -or ($w[0] -cne 'user' -and $w[0] -cne 'group')) { $p.Why = 'create.account takes user or group, then the name'; return $p }
            if (-not (Test-RadminName $w[1])) { $p.Why = "$($w[1]) is not an account name remote administration may make"; return $p }
            $rest = @(); if ($w.Count -gt 2) { $rest = @($w[2..($w.Count - 1)]) }
            $why = Test-RadminWordSet $rest $(if ($w[0] -ceq 'user') { $RadminCreateUser } else { $RadminCreateGroup })
            if ($why -ne '') { $p.Why = $why; return $p }
            $p.Targets = @($w[1])
            $p.NeedsSecret = ($w[0] -ceq 'user')
        }
        'delete.account' {
            if ($w.Count -lt 1 -or $w.Count -gt 2 -or ($w.Count -eq 2 -and $w[1] -cne 'remove.home')) { $p.Why = 'delete.account takes one account name (and remove.home)'; return $p }
            if (-not (Test-RadminName $w[0])) { $p.Why = "$($w[0]) is not an account remote administration may delete"; return $p }
            $p.Targets = @($w[0])
        }
        'modify.account' {
            if ($w.Count -lt 2) { $p.Why = 'modify.account takes an account name and what to change'; return $p }
            if (-not (Test-RadminName $w[0])) { $p.Why = "$($w[0]) is not an account remote administration may change"; return $p }
            if ($w[1] -ceq 'add' -or $w[1] -ceq 'delete') {
                if ($w.Count -ne 3 -or -not (Test-RadminName $w[2])) { $p.Why = 'modify.account <account> add | delete takes one user name'; return $p }
                $p.Targets = @($w[0], $w[2])
            } else {
                $why = Test-RadminWordSet @($w[1..($w.Count - 1)]) $RadminModify
                if ($why -ne '') { $p.Why = $why; return $p }
                $p.Targets = @($w[0])
            }
        }
        'modify.password' {
            if ($w.Count -ne 1 -or -not (Test-RadminName $w[0])) { $p.Why = 'modify.password takes the name of one account other than SDRADMIN'; return $p }
            $p.Targets = @($w[0])
            $p.NeedsSecret = $true
        }
        'remote.sdsys' {
            if ($w.Count -lt 1 -or $RadminReports -cnotcontains $w[0]) { $p.Why = 'remote.sdsys takes off, status, audit or accounts here (on is the console''s)'; return $p }
            if ($w[0] -ceq 'audit') {
                if ($w.Count -gt 2 -or ($w.Count -eq 2 -and $w[1] -cnotmatch '^[1-9][0-9]{0,2}$')) { $p.Why = 'remote.sdsys audit takes a number of lines, 1 to 500'; return $p }
                if ($w.Count -eq 2 -and [int]$w[1] -gt 500) { $p.Why = 'remote.sdsys audit takes a number of lines, 1 to 500'; return $p }
            } elseif ($w.Count -ne 1) { $p.Why = "remote.sdsys $($w[0]) takes nothing more"; return $p }
        }
        default { $p.Why = 'the command is not one remote administration may run'; return $p }
    }
    if ($p.NeedsSecret -and $null -eq $req.Secret) { $p.Why = 'this command needs the new password and the request has none'; return $p }
    if (-not $p.NeedsSecret -and $null -ne $req.Secret) { $p.Why = 'this command takes no password and the request has one'; return $p }
    $p.Command = (@('remote.sdsys', 'run', $v) + $w) -join ' '
    if ($p.Command.Length -gt 400) { $p.Why = 'the command is too long'; return $p }
    $p.Ok = $true
    return $p
}
# END radmin_request

# ---------------------------------------------------------------------------------------------------------------- the machine's half
$Latin1 = [Text.Encoding]::GetEncoding(28591)
$StateDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD\remote-admin'
$JobsDir = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD\sd-jobs'
$LogFile = Join-Path $StateDir 'broker.log'

function Get-LocalSid([string]$name) {
    try {
        return (New-Object Security.Principal.NTAccount("$([Environment]::MachineName)\$name")).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { return '' }
}

function Write-Log([string]$t) {
    # Administrators only: made with a protected ACL the first time (the directory grants sdusers read for the state file).
    try {
        if (-not (Test-Path -LiteralPath $LogFile)) {
            $fs = New-Object Security.AccessControl.FileSecurity
            $fs.SetAccessRuleProtection($true, $false)
            foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
                $fs.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', 'Allow')))
            }
            $s = New-Object IO.FileStream($LogFile, [IO.FileMode]::CreateNew, [Security.AccessControl.FileSystemRights]::AppendData, [IO.FileShare]::ReadWrite, 4096, [IO.FileOptions]::None, $fs)
            $s.Dispose()
        } elseif ((Get-Item -LiteralPath $LogFile).Length -gt 1MB) {
            Move-Item -LiteralPath $LogFile -Destination ($LogFile + '.1') -Force
            Write-Log 'log started again; the previous one is broker.log.1'
        }
        [IO.File]::AppendAllText($LogFile, ((Get-Date).ToString('yyyy-MM-dd HH:mm:ss') + ' ' + $t + "`r`n"), [Text.Encoding]::ASCII)
    } catch { }
}

function Test-JobAdminPath([string]$path, [bool]$wantDir) {
    # sd-jobs.ps1's test, the kernel's win32_job_admin_path(): not a link, the right kind, owned by SYSTEM or Administrators, nobody else
    # allowed anything.  Repeated rather than dot-sourced: this script must not run code from another file it does not own.
    $item = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $false }
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    if ($wantDir -ne $item.PSIsContainer) { return $false }
    $ok = @('S-1-5-18', 'S-1-5-32-544')
    try {
        $acl = Get-Acl -LiteralPath $path
        $owner = (New-Object Security.Principal.NTAccount($acl.Owner)).Translate([Security.Principal.SecurityIdentifier]).Value
    } catch { return $false }
    if ($ok -notcontains $owner) { return $false }
    foreach ($r in $acl.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier])) {
        if ($r.AccessControlType -ne 'Allow') { continue }
        if ($r.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) { continue }
        if ($ok -notcontains $r.IdentityReference.Value) { return $false }
    }
    return $true
}

function Write-JobDefinition([string]$name, [string]$command) {
    # '' or why.  The directory as sd-jobs.ps1 makes it (SYSTEM and Administrators only, owned by Administrators); the file owned by
    # Administrators, checked before it is used.  A definition already there under this name is a refusal: a nonce is used once.
    if (-not (Test-Path -LiteralPath $JobsDir)) {
        $ds = New-Object Security.AccessControl.DirectorySecurity
        $ds.SetAccessRuleProtection($true, $false)
        $inh = [Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
        foreach ($sid in @('S-1-5-18', 'S-1-5-32-544')) {
            $ds.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule((New-Object Security.Principal.SecurityIdentifier($sid)), 'FullControl', $inh, 'None', 'Allow')))
        }
        $ds.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        [IO.Directory]::CreateDirectory($JobsDir, $ds) | Out-Null
    }
    if (-not (Test-JobAdminPath $JobsDir $true)) { return "$JobsDir is a link, or is owned by or open to somebody other than SYSTEM and Administrators" }
    $target = Join-Path $JobsDir $name
    if (Test-Path -LiteralPath $target) { return 'that nonce has been used' }
    $tmp = Join-Path $JobsDir ".new.$PID"
    $text = "# a one-shot remote administration request, written by sd-radmin.ps1; REMOTE.SDSYS RUN removes it as it starts`nname=$name`njob=radmin`ncommand=$command`nschedule=once`n"
    try {
        [IO.File]::WriteAllText($tmp, $text, [Text.Encoding]::ASCII)
        $fsec = (Get-Item -LiteralPath $tmp -Force).GetAccessControl([Security.AccessControl.AccessControlSections]::Owner)
        $fsec.SetOwner((New-Object Security.Principal.SecurityIdentifier('S-1-5-32-544')))
        (Get-Item -LiteralPath $tmp -Force).SetAccessControl($fsec)
        [IO.File]::Move($tmp, $target)
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    if (-not (Test-JobAdminPath $target $false)) {
        Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
        return 'the job definition could not be made the administrators'' file'
    }
    return ''
}

function Test-RadminTarget([string]$name) {
    # '' or why.  A name that is not a Windows user passes here (a group account, or an account still to be made); one that is must be SD's
    # and not an administrator.  Asked of Windows, by SID, every time.
    $u = Get-LocalUser -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $u) { return '' }
    if ($u.Description -cne 'SD account') { return "$name is a Windows account SD did not make" }
    foreach ($m in @(Get-LocalGroupMember -SID 'S-1-5-32-544' -ErrorAction Stop)) {
        if ($null -ne $m.SID -and $m.SID.Value -eq $u.SID.Value) { return "$name is a Windows administrator" }
    }
    return ''
}

function Send-Answer($pipe, [string[]]$lines) {
    $b = $Latin1.GetBytes((($lines + 'end') -join "`n") + "`n")
    $pipe.Write($b, 0, $b.Length)
    $pipe.Flush()
    try { $pipe.WaitForPipeDrain() } catch { }
}

function Read-Request($pipe) {
    # The text, or $null when the caller sent nothing usable within 10 seconds, sent more than 4096 bytes, or went away.
    $buf = New-Object byte[] 4097
    $got = 0
    $deadline = [DateTime]::UtcNow.AddSeconds(10)
    while ($true) {
        $ms = [int]($deadline - [DateTime]::UtcNow).TotalMilliseconds
        if ($ms -le 0) { return $null }
        $t = $pipe.ReadAsync($buf, $got, $buf.Length - $got)
        if (-not $t.Wait($ms)) { return $null }
        $n = $t.Result
        if ($n -le 0) { return $null }
        $got += $n
        if ($got -gt 4096) { return $null }
        $text = [Text.Encoding]::ASCII.GetString($buf, 0, $got)
        if ($text -cmatch "(^|`n)end`r?`n$") { return $text }
    }
}

function Invoke-Request($pipe, [string]$radminSid) {
    # One connection: who, what, then the job.  Returns $true when the broker is to stop after it (REMOTE.SDSYS OFF ran and succeeded).
    $script:Caller = @{ User = ''; Groups = @() }
    $pipe.RunAsClient([IO.Pipes.PipeStreamImpersonationWorker]{
        $id = [Security.Principal.WindowsIdentity]::GetCurrent($true)
        if ($null -ne $id) { $script:Caller = @{ User = $id.User.Value; Groups = @($id.Groups | ForEach-Object { $_.Value }) } }
    })
    $c = $script:Caller
    if ($c.User -eq '' -or $c.User -ne $radminSid) {
        Write-Log "refused caller=$($c.User) result=refused:not the remote administration account"
        Send-Answer $pipe @('refused=only the remote administration account may use this')
        return $false
    }
    if ($c.Groups -notcontains 'S-1-5-2' -or $c.Groups -contains 'S-1-5-4' -or $c.Groups -contains 'S-1-5-3' -or $c.Groups -contains 'S-1-5-6') {
        Write-Log "refused caller=$($c.User) result=refused:not an ssh (network) sign-in groups=$((@($c.Groups | Where-Object { $_ -match '^S-1-5-[2346]$' })) -join ',')"
        Send-Answer $pipe @('refused=remote administration is for an ssh sign-in only')
        return $false
    }

    $text = Read-Request $pipe
    if ($null -eq $text) {
        Write-Log "refused caller=$($c.User) result=refused:no complete request within 10 seconds or 4096 bytes"
        try { Send-Answer $pipe @('refused=the request was not complete within 10 seconds, or was longer than 4096 bytes') } catch { }
        # A read may still be pending on this instance: the loop must make a new one rather than hand it the next caller (it disposes on a throw).
        throw 'incomplete request'
    }
    $req = ConvertFrom-RadminRequest $text
    $nl = @(); if ($req.Nonce -ne '') { $nl = @('nonce=' + $req.Nonce) }
    if (-not $req.Ok) {
        Write-Log "refused caller=$($c.User) nonce=$($req.Nonce) result=refused:$($req.Why)"
        Send-Answer $pipe ($nl + ('refused=' + $req.Why))
        return $false
    }
    $words = ($req.Words -join ' ')
    $plan = Get-RadminPlan $req
    $why = ''
    if (-not $plan.Ok) { $why = $plan.Why }
    if ($why -eq '') {
        $sf = Join-Path $StateDir 'state'
        if (-not (Test-Path -LiteralPath $sf) -or ([IO.File]::ReadAllText($sf)).Trim() -cne 'on') { $why = 'remote administration is off' }
    }
    if ($why -eq '') {
        foreach ($t in $plan.Targets) { if ($why -eq '') { $why = Test-RadminTarget $t } }
    }
    if ($why -ne '') {
        Write-Log "refused verb=$($req.Verb) words=$words caller=$($c.User) nonce=$($req.Nonce) result=refused:$why"
        Send-Answer $pipe ($nl + ('refused=' + $why))
        return $false
    }

    $jobName = 'radmin-' + $req.Nonce
    $why = Write-JobDefinition $jobName $plan.Command
    if ($why -ne '') {
        Write-Log "refused verb=$($req.Verb) words=$words caller=$($c.User) nonce=$($req.Nonce) result=refused:$why"
        Send-Answer $pipe ($nl + ('refused=' + $why))
        return $false
    }

    $stop = $false
    $answer = $nl
    try {
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName = Join-Path $PSScriptRoot 'usr\bin\sd.exe'
        $psi.Arguments = '-job ' + $jobName + ' ' + $plan.Command
        $psi.WorkingDirectory = Join-Path ([Environment]::GetFolderPath('CommonApplicationData')) 'SD\sdsys'
        $psi.UseShellExecute = $false
        $psi.RedirectStandardInput = $true
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.StandardOutputEncoding = $Latin1
        $psi.StandardErrorEncoding = $Latin1
        $p = [Diagnostics.Process]::Start($psi)
        $oT = $p.StandardOutput.ReadToEndAsync()
        $eT = $p.StandardError.ReadToEndAsync()
        if ($null -ne $req.Secret) {
            $p.StandardInput.BaseStream.Write($req.Secret, 0, $req.Secret.Length)
            $p.StandardInput.BaseStream.WriteByte(10)
            $p.StandardInput.BaseStream.Flush()
        }
        $p.StandardInput.Close()
        if (-not $p.WaitForExit(180000)) {
            Write-Log "timeout verb=$($req.Verb) words=$words caller=$($c.User) nonce=$($req.Nonce) result=still running pid=$($p.Id)"
            $answer += ('timeout=' + $p.Id)
        } else {
            $p.WaitForExit()
            $out = $oT.Result + $eT.Result
            if ($null -ne $req.Secret) { $out = $out.Replace($Latin1.GetString($req.Secret), '********') }
            $outLines = New-Object System.Collections.ArrayList
            foreach ($l in @($out -split "`r?`n")) { $null = $outLines.Add($l) }
            while ($outLines.Count -gt 0 -and $outLines[$outLines.Count - 1] -eq '') { $outLines.RemoveAt($outLines.Count - 1) }
            foreach ($l in $outLines) { $answer += ('out=' + $l) }
            $answer += ('exit=' + $p.ExitCode)
            Write-Log "done verb=$($req.Verb) words=$words caller=$($c.User) nonce=$($req.Nonce) result=exit $($p.ExitCode)"
            if ($req.Verb -ceq 'remote.sdsys' -and $req.Words[0] -ceq 'off' -and $p.ExitCode -eq 0) { $stop = $true }
        }
    } catch {
        Write-Log "failed verb=$($req.Verb) words=$words caller=$($c.User) nonce=$($req.Nonce) result=$($_.Exception.Message)"
        $answer += ('refused=the command could not be started: ' + $_.Exception.Message)
    } finally {
        $req.Secret = $null
        $def = Join-Path $JobsDir $jobName
        if (Test-Path -LiteralPath $def) { Remove-Item -LiteralPath $def -Force -ErrorAction SilentlyContinue }
    }
    Send-Answer $pipe $answer
    return $stop
}

function New-RadminPipe([string]$sdsysSid, [string]$radminSid) {
    $sec = New-Object IO.Pipes.PipeSecurity
    $sec.SetAccessRuleProtection($true, $false)
    $sec.AddAccessRule((New-Object IO.Pipes.PipeAccessRule((New-Object Security.Principal.SecurityIdentifier($sdsysSid)), [IO.Pipes.PipeAccessRights]::FullControl, 'Allow')))
    $sec.AddAccessRule((New-Object IO.Pipes.PipeAccessRule((New-Object Security.Principal.SecurityIdentifier($radminSid)), [IO.Pipes.PipeAccessRights]'ReadWrite, Synchronize', 'Allow')))
    # One instance: .NET opens the first with FILE_FLAG_FIRST_PIPE_INSTANCE, so a pipe of this name made by anybody else first is an error.
    return (New-Object IO.Pipes.NamedPipeServerStream('sd-radmin', [IO.Pipes.PipeDirection]::InOut, 1, [IO.Pipes.PipeTransmissionMode]::Byte,
                                                       [IO.Pipes.PipeOptions]::Asynchronous, 4096, 4096, $sec))
}

if (-not $Serve) {
    [Console]::Out.WriteLine("${Prog}: usage: sd-radmin.ps1 -Serve (the task \SD\sdcore-radmin runs it; remote-admin.ps1 -On registers the task)")
    exit 2
}

try {
    $me = [Security.Principal.WindowsIdentity]::GetCurrent()
    $sdsysSid = Get-LocalSid 'SDSYS'
    if ($sdsysSid -eq '' -or $me.User.Value -ne $sdsysSid) { Write-Log 'not started: the broker runs as the local account SDSYS only'; exit 1 }
    if (-not ([Security.Principal.WindowsPrincipal]$me).IsInRole([Security.Principal.SecurityIdentifier]'S-1-5-32-544')) { Write-Log 'not started: not elevated'; exit 1 }
    $radminSid = Get-LocalSid 'SDRADMIN'
    if ($radminSid -eq '') { Write-Log 'not started: there is no account SDRADMIN'; exit 1 }
    $sf = Join-Path $StateDir 'state'
    if (-not (Test-Path -LiteralPath $sf) -or ([IO.File]::ReadAllText($sf)).Trim() -cne 'on') { Write-Log 'not started: remote administration is off'; exit 0 }

    Write-Log "started pid=$PID radmin=$radminSid"
    $pipe = $null
    while ($true) {
        if ($null -eq $pipe) { $pipe = New-RadminPipe $sdsysSid $radminSid }
        $pipe.WaitForConnection()
        $stop = $false
        $clean = $false
        try {
            $stop = Invoke-Request $pipe $radminSid
            $clean = $true
        } catch {
            Write-Log "request failed: $($_.Exception.Message)"
        }
        if ($clean) {
            try { $pipe.Disconnect() } catch { $clean = $false }
        }
        if (-not $clean) {
            # A read that did not finish may still be pending on this instance; a new instance cannot be handed the next caller's bytes.
            try { $pipe.Dispose() } catch { }
            $pipe = $null
        }
        if ($stop) { Write-Log 'stopped: remote administration was shut from the remote session'; break }
    }
    if ($null -ne $pipe) { $pipe.Dispose() }
    exit 0
}
catch {
    Write-Log "stopped: $($_.Exception.Message)"
    exit 1
}
