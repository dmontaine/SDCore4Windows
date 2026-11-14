# test-remoteadmin-units.ps1 - remote administration over ssh (RELEASE_1.1 202): the broker's checks, the sshd arm, the pipe's ends
#
#   powershell -ExecutionPolicy Bypass -File C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-remoteadmin-units.ps1 [-SelfTest]
#
# 13 Nov 26 Windows port - written for RELEASE_1.1 202 (Linux S.106's remote.sdsys, the Windows form).  Free: no install, no elevation, no sd,
# no pipe, no Task Scheduler, no sshd.
# 13 Nov 26 Windows port - RELEASE_1.1 202, Linux parity: REMOTE.SSH {on | off} and REMOTE.API {on | local | off}, and each with no word, are
# accepted (Q1) and every other word, a second word and a password refused (Q3); six mutants break the two lists and their checks.
#
# WHAT IT DRIVES.  sd-radmin.ps1's "# BEGIN radmin_request" region - the broker's whole wall against a request (the keys, the words, the names,
# the password's shape, the command built from checked words) - with good requests and bad ones; remote-admin.ps1's "# BEGIN radmin_functions"
# region - the sshd arm written, read back, removed byte for byte, and "sshd -T" output judged - on synthetic text; sd-jobs.ps1 in its dry run
# (a scratch folder, no Task Scheduler) for the radmin- names it now leaves to the broker.  WHAT IT READS AS TEXT, in order: the broker asks
# the caller's token before it reads the request, the password goes to the job's standard input and nowhere else, the pipe admits two
# SIDs, nothing kills a process; the client deletes the request before it connects and checks the pipe's owner before it sends; -On refuses an
# administrator before it changes anything and puts sshd_config back byte for byte when sshd disagrees.
#
# WHAT IT CANNOT SHOW (the VM witness): that Win32-OpenSSH honours the Match block for either spelling of the name, what its "sshd -T" prints,
# that an S4U SDSYS task's child gets K$JOB.MARK's yes, that the caller's token from sshd carries NETWORK, that the pipe's access list admits
# SDRADMIN's ssh processes and refuses another user, and what the console verbs do with the DATA queue.
#
# -SelfTest breaks each region and file the way an edit plausibly would and requires a row to go red; a mutant nothing catches fails the
# self-test.  The live files are only read: every mutant is a string in memory.  Three checks of the request have no mutant, because a later
# check refuses the same requests and the mutant would be (rightly) not caught: the verb list in ConvertFrom-RadminRequest (Get-RadminPlan's
# default refuses an unknown verb), the shape of a word, and the printable-ASCII test (every word is then a listed keyword or passes
# Test-RadminName, the nonce and the password have their own patterns).  Exit 0 every row passed, 1 a row failed, 2 it could not run.

param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = @{
    broker = Join-Path $here 'sd-radmin.ps1'
    admin  = Join-Path $here 'remote-admin.ps1'
    client = Join-Path $here 'sd-radmin-client.ps1'
    jobs   = Join-Path $here 'sd-jobs.ps1'
    allow  = Join-Path $here 'allow-ssh-groups.ps1'
    # 13 Nov 26 - RELEASE_1.1 281: the task folder's one rule and the two other places that use it.
    taskfolder = Join-Path $here 'sd-taskfolder.ps1'
    finish     = Join-Path $here 'finish-install.ps1'
    stage      = Join-Path $here 'stage.py'
}
Write-Output "test-remoteadmin-units: subjects $($files.broker), $($files.admin), $($files.client), $($files.jobs), $($files.allow), $($files.taskfolder), $($files.finish), $($files.stage)"
$texts = @{}
foreach ($k in @($files.Keys)) {
    if (-not (Test-Path -LiteralPath $files[$k])) { Write-Output "test-remoteadmin-units: CANNOT RUN - $($files[$k]) is missing"; exit 2 }
    $texts[$k] = [IO.File]::ReadAllText($files[$k])
}

function Get-Region([string]$text, [string]$name) {
    $b = $text.IndexOf("# BEGIN $name"); $e = $text.IndexOf("# END $name")
    if ($b -lt 0 -or $e -lt $b) { return '' }
    return $text.Substring($b, $e - $b)
}

function ConvertTo-Hex([string]$s) { return (([Text.Encoding]::ASCII.GetBytes($s) | ForEach-Object { $_.ToString('x2') }) -join '') }

function Get-Rows([hashtable]$t) {
    $rows = New-Object System.Collections.ArrayList
    $reqRegion = Get-Region $t.broker 'radmin_request'
    $armRegion = Get-Region $t.admin 'radmin_functions'
    $null = $rows.Add(@('F0 NULL CASE: both regions were found and are not short (a check on nothing would pass)', (($reqRegion.Length -gt 4000) -and ($armRegion.Length -gt 3000)), "request $($reqRegion.Length) arm $($armRegion.Length)"))
    if ($reqRegion -eq '' -or $armRegion -eq '') { return ,$rows }

    $inner = & {
        param($rq, $am)
        $out = New-Object System.Collections.ArrayList
        function Add-Row([string]$l, $ok, [string]$d = '') { $null = $out.Add(@($l, [bool]$ok, $d)) }
        try {
            . ([scriptblock]::Create($rq))
            . ([scriptblock]::Create($am))
        } catch { Add-Row 'F1 the regions load' $false $_.Exception.Message; return ,$out }
        $want = 'Test-RadminName', 'ConvertFrom-RadminRequest', 'Test-RadminWordSet', 'Get-RadminPlan', 'Get-RadminArmLines', 'Remove-RadminBlockText', 'Add-RadminBlockText', 'Get-RadminArmState', 'Test-RadminEffective'
        $missing = @($want | Where-Object { -not (Get-Command $_ -CommandType Function -ErrorAction SilentlyContinue) })
        Add-Row 'F1 the regions define the nine functions' ($missing.Count -eq 0) ($missing -join ',')

        $nonce = '0123456789abcdef'
        $pw = ConvertTo-Hex 'Correct-Horse9'
        function Q([string[]]$lines) { return ((@($lines) -join "`n") + "`n") }
        function Plan([string]$text) {
            $r = ConvertFrom-RadminRequest $text
            if (-not $r.Ok) { return @{ Ok = $false; Why = $r.Why; Stage = 'request' } }
            $p = Get-RadminPlan $r
            $p.Stage = 'plan'
            return $p
        }

        # Q: good requests, and exactly the command each builds
        $goods = @(
            @(@('version=1', 'verb=create.account', 'word1=user', 'word2=bob', 'word3=ssh', 'word4=sh-on', "nonce=$nonce", "secret=$pw", 'end'), 'remote.sdsys run create.account user bob ssh sh-on', $true, 'bob'),
            @(@('version=1', 'verb=create.account', 'word1=group', 'word2=sales', 'word3=start-menu', "nonce=$nonce", 'end'), 'remote.sdsys run create.account group sales start-menu', $false, 'sales'),
            @(@('version=1', 'verb=modify.account', 'word1=bob', 'word2=sh-on', 'word3=os-on', 'word4=suspended', "nonce=$nonce", 'end'), 'remote.sdsys run modify.account bob sh-on os-on suspended', $false, 'bob'),
            @(@('version=1', 'verb=modify.account', 'word1=sales', 'word2=add', 'word3=bob', "nonce=$nonce", 'end'), 'remote.sdsys run modify.account sales add bob', $false, 'sales,bob'),
            @(@('version=1', 'verb=delete.account', 'word1=bob', "nonce=$nonce", 'end'), 'remote.sdsys run delete.account bob', $false, 'bob'),
            @(@('version=1', 'verb=modify.password', 'word1=bob', "nonce=$nonce", "secret=$pw", 'end'), 'remote.sdsys run modify.password bob', $true, 'bob'),
            @(@('version=1', 'verb=remote.sdsys', 'word1=off', "nonce=$nonce", 'end'), 'remote.sdsys run remote.sdsys off', $false, ''),
            @(@('version=1', 'verb=remote.sdsys', 'word1=audit', 'word2=500', "nonce=$nonce", 'end'), 'remote.sdsys run remote.sdsys audit 500', $false, ''),
            @(@('version=1', 'verb=remote.sdsys', 'word1=status', "nonce=$nonce", 'end'), 'remote.sdsys run remote.sdsys status', $false, ''),
            @(@('version=1', 'verb=remote.ssh', 'word1=off', "nonce=$nonce", 'end'), 'remote.sdsys run remote.ssh off', $false, ''),
            @(@('version=1', 'verb=remote.ssh', 'word1=on', "nonce=$nonce", 'end'), 'remote.sdsys run remote.ssh on', $false, ''),
            @(@('version=1', 'verb=remote.ssh', "nonce=$nonce", 'end'), 'remote.sdsys run remote.ssh', $false, ''),
            @(@('version=1', 'verb=remote.api', 'word1=local', "nonce=$nonce", 'end'), 'remote.sdsys run remote.api local', $false, ''),
            @(@('version=1', 'verb=remote.api', 'word1=off', "nonce=$nonce", 'end'), 'remote.sdsys run remote.api off', $false, ''),
            @(@('version=1', 'verb=remote.api', "nonce=$nonce", 'end'), 'remote.sdsys run remote.api', $false, '')
        )
        foreach ($g in $goods) {
            $p = Plan (Q $g[0])
            Add-Row "Q1 accepted, with exactly the command '$($g[1])'" ($p.Ok -and ($p.Command -ceq $g[1]) -and ($p.NeedsSecret -eq $g[2]) -and ((@($p.Targets) -join ',') -ceq $g[3])) "$($p.Why) | $($p.Command) | $($p.NeedsSecret) | $(@($p.Targets) -join ',')"
        }
        $r = ConvertFrom-RadminRequest (Q $goods[0][0])
        Add-Row 'Q2 the password comes back as its bytes, and only from secret=' ($r.Ok -and ([Text.Encoding]::ASCII.GetString($r.Secret) -ceq 'Correct-Horse9')) ''

        # Q3: refused, each for its own reason, never an empty one
        $base = @('version=1', 'verb=delete.account', 'word1=bob', "nonce=$nonce")
        $bads = @(
            @('an unknown key', (Q ($base + 'extra=1' + 'end'))),
            @('a key twice', (Q (@('version=1', 'verb=delete.account', 'word1=bob', 'word1=sue', "nonce=$nonce", 'end')))),
            @('no nonce', (Q (@('version=1', 'verb=delete.account', 'word1=bob', 'end')))),
            @('a nonce in upper case', (Q (@('version=1', 'verb=delete.account', 'word1=bob', 'nonce=0123456789ABCDEF', 'end')))),
            @('a nonce of 15 digits', (Q (@('version=1', 'verb=delete.account', 'word1=bob', 'nonce=0123456789abcde', 'end')))),
            @('version 2', (Q (@('version=2', 'verb=delete.account', 'word1=bob', "nonce=$nonce", 'end')))),
            @('no version', (Q (@('verb=delete.account', 'word1=bob', "nonce=$nonce", 'end')))),
            @('verb set.config', (Q (@('version=1', 'verb=set.config', 'word1=x', "nonce=$nonce", 'end')))),
            @('verb logto', (Q (@('version=1', 'verb=logto', 'word1=sdsys', "nonce=$nonce", 'end')))),
            @('verb sh', (Q (@('version=1', 'verb=sh', "nonce=$nonce", 'end')))),
            @('verb ssh.server', (Q (@('version=1', 'verb=ssh.server', 'word1=remove', "nonce=$nonce", 'end')))),
            @('remote.ssh status (the report is no keyword)', (Q (@('version=1', 'verb=remote.ssh', 'word1=status', "nonce=$nonce", 'end')))),
            @('remote.ssh open', (Q (@('version=1', 'verb=remote.ssh', 'word1=open', "nonce=$nonce", 'end')))),
            @('remote.ssh local', (Q (@('version=1', 'verb=remote.ssh', 'word1=local', "nonce=$nonce", 'end')))),
            @('remote.ssh on off', (Q (@('version=1', 'verb=remote.ssh', 'word1=on', 'word2=off', "nonce=$nonce", 'end')))),
            @('remote.ssh off with an account name', (Q (@('version=1', 'verb=remote.ssh', 'word1=off', 'word2=bob', "nonce=$nonce", 'end')))),
            @('remote.ssh ON in capitals', (Q (@('version=1', 'verb=remote.ssh', 'word1=ON', "nonce=$nonce", 'end')))),
            @('remote.ssh with a password', (Q (@('version=1', 'verb=remote.ssh', 'word1=off', "nonce=$nonce", "secret=$pw", 'end')))),
            @('remote.api restart', (Q (@('version=1', 'verb=remote.api', 'word1=restart', "nonce=$nonce", 'end')))),
            @('remote.api on y (an answer to the restart question)', (Q (@('version=1', 'verb=remote.api', 'word1=on', 'word2=y', "nonce=$nonce", 'end')))),
            @('remote.api on local', (Q (@('version=1', 'verb=remote.api', 'word1=on', 'word2=local', "nonce=$nonce", 'end')))),
            @('remote.api status', (Q (@('version=1', 'verb=remote.api', 'word1=status', "nonce=$nonce", 'end')))),
            @('remote.api a port number', (Q (@('version=1', 'verb=remote.api', 'word1=4243', "nonce=$nonce", 'end')))),
            @('remote.api with a password', (Q (@('version=1', 'verb=remote.api', 'word1=on', "nonce=$nonce", "secret=$pw", 'end')))),
            @('verb CREATE.ACCOUNT in capitals', (Q (@('version=1', 'verb=CREATE.ACCOUNT', 'word1=group', 'word2=x', "nonce=$nonce", 'end')))),
            @('target sdsys', (Q (@('version=1', 'verb=delete.account', 'word1=sdsys', "nonce=$nonce", 'end')))),
            @('target sdradmin', (Q (@('version=1', 'verb=modify.password', 'word1=sdradmin', "nonce=$nonce", "secret=$pw", 'end')))),
            @('target shared', (Q (@('version=1', 'verb=delete.account', 'word1=shared', "nonce=$nonce", 'end')))),
            @('target administrator', (Q (@('version=1', 'verb=modify.account', 'word1=administrator', 'word2=suspended', "nonce=$nonce", 'end')))),
            @('target sdusers', (Q (@('version=1', 'verb=create.account', 'word1=group', 'word2=sdusers', "nonce=$nonce", 'end')))),
            @('a name of 21 characters', (Q (@('version=1', 'verb=delete.account', 'word1=abcdefghijklmnopqrstu', "nonce=$nonce", 'end')))),
            @('a name with a dot', (Q (@('version=1', 'verb=delete.account', 'word1=a..b', "nonce=$nonce", 'end')))),
            @('a name starting with a digit', (Q (@('version=1', 'verb=delete.account', 'word1=1abc', "nonce=$nonce", 'end')))),
            @('a name in capitals', (Q (@('version=1', 'verb=delete.account', 'word1=Bob', "nonce=$nonce", 'end')))),
            @('a word with a backslash', (Q (@('version=1', 'verb=delete.account', 'word1=bob\x', "nonce=$nonce", 'end')))),
            @('a word with a space', (Q (@('version=1', 'verb=delete.account', 'word1=bob x', "nonce=$nonce", 'end')))),
            @('a word with a quote', (Q (@('version=1', 'verb=delete.account', "word1=bob'", "nonce=$nonce", 'end')))),
            @('a word with a semicolon', (Q (@('version=1', 'verb=delete.account', 'word1=bob;x', "nonce=$nonce", 'end')))),
            @('a gap in the words', (Q (@('version=1', 'verb=delete.account', 'word1=bob', 'word3=sue', "nonce=$nonce", 'end')))),
            @('a password for delete.account', (Q ($base + "secret=$pw" + 'end'))),
            @('no password for modify.password', (Q (@('version=1', 'verb=modify.password', 'word1=bob', "nonce=$nonce", 'end')))),
            @('no password for create.account user', (Q (@('version=1', 'verb=create.account', 'word1=user', 'word2=bob', "nonce=$nonce", 'end')))),
            @('a password for create.account group', (Q (@('version=1', 'verb=create.account', 'word1=group', 'word2=g', "nonce=$nonce", "secret=$pw", 'end')))),
            @('a password holding a line feed', (Q (@('version=1', 'verb=modify.password', 'word1=bob', "nonce=$nonce", ('secret=' + $pw + '0a' + $pw), 'end')))),
            @('a password of odd length', (Q (@('version=1', 'verb=modify.password', 'word1=bob', "nonce=$nonce", ('secret=' + $pw + 'a'), 'end')))),
            @('a password over 256 bytes', (Q (@('version=1', 'verb=modify.password', 'word1=bob', "nonce=$nonce", ('secret=' + ('41' * 257)), 'end')))),
            @('a password not in hexadecimal', (Q (@('version=1', 'verb=modify.password', 'word1=bob', "nonce=$nonce", 'secret=Correct-Horse9', 'end')))),
            @('remote.sdsys on', (Q (@('version=1', 'verb=remote.sdsys', 'word1=on', "nonce=$nonce", 'end')))),
            @('remote.sdsys run', (Q (@('version=1', 'verb=remote.sdsys', 'word1=run', 'word2=delete.account', 'word3=bob', "nonce=$nonce", 'end')))),
            @('remote.sdsys audit 501', (Q (@('version=1', 'verb=remote.sdsys', 'word1=audit', 'word2=501', "nonce=$nonce", 'end')))),
            @('remote.sdsys audit 0', (Q (@('version=1', 'verb=remote.sdsys', 'word1=audit', 'word2=0', "nonce=$nonce", 'end')))),
            @('remote.sdsys off with more', (Q (@('version=1', 'verb=remote.sdsys', 'word1=off', 'word2=now', "nonce=$nonce", 'end')))),
            @('remote.sdsys with nothing', (Q (@('version=1', 'verb=remote.sdsys', "nonce=$nonce", 'end')))),
            @('two routes', (Q (@('version=1', 'verb=modify.account', 'word1=bob', 'word2=ssh', 'word3=api', "nonce=$nonce", 'end')))),
            @('a word twice', (Q (@('version=1', 'verb=modify.account', 'word1=bob', 'word2=sh-on', 'word3=sh-on', "nonce=$nonce", 'end')))),
            @('two start words', (Q (@('version=1', 'verb=modify.account', 'word1=bob', 'word2=start-menu', 'word3=start-default', "nonce=$nonce", 'end')))),
            @('a modify word not in the list', (Q (@('version=1', 'verb=modify.account', 'word1=bob', 'word2=administrator', "nonce=$nonce", 'end')))),
            @('modify add with no user', (Q (@('version=1', 'verb=modify.account', 'word1=sales', 'word2=add', "nonce=$nonce", 'end')))),
            @('modify add sdradmin', (Q (@('version=1', 'verb=modify.account', 'word1=sales', 'word2=add', 'word3=sdradmin', "nonce=$nonce", 'end')))),
            @('modify add with a gate word', (Q (@('version=1', 'verb=modify.account', 'word1=sales', 'word2=add', 'word3=bob', 'word4=sh-on', "nonce=$nonce", 'end')))),
            @('create other', (Q (@('version=1', 'verb=create.account', 'word1=other', 'word2=x', "nonce=$nonce", 'end')))),
            @('a word that is punctuation first', (Q (@('version=1', 'verb=remote.sdsys', 'word1=audit', 'word2=-5', "nonce=$nonce", 'end')))),
            @('create user attach', (Q (@('version=1', 'verb=create.account', 'word1=user', 'word2=bob', 'word3=attach', "nonce=$nonce", "secret=$pw", 'end')))),
            @('create user no.query', (Q (@('version=1', 'verb=create.account', 'word1=user', 'word2=bob', 'word3=no.query', "nonce=$nonce", "secret=$pw", 'end')))),
            @('create user sh-off', (Q (@('version=1', 'verb=create.account', 'word1=user', 'word2=bob', 'word3=sh-off', "nonce=$nonce", "secret=$pw", 'end')))),
            @('create group ssh', (Q (@('version=1', 'verb=create.account', 'word1=group', 'word2=g', 'word3=ssh', "nonce=$nonce", 'end')))),
            @('delete with a second name', (Q (@('version=1', 'verb=delete.account', 'word1=bob', 'word2=sue', "nonce=$nonce", 'end')))),
            @('modify.password with two names', (Q (@('version=1', 'verb=modify.password', 'word1=bob', 'word2=sue', "nonce=$nonce", "secret=$pw", 'end')))),
            @('no line end', (Q ($base))),
            @('a byte that is not ASCII', ((Q ($base + 'end')).Replace('bob', ('b' + [char]0xE9 + 'b')))),
            @('a request of 4097 bytes', ((Q ($base + 'end')).Replace('word1=bob', ('word1=bob' + "`n" + 'version=1' + ('x' * 4097))))),
            @('an empty request', ''),
            @('only the line end', "end`n"),
            @('a line that is not key=value', (Q (@('version=1', 'verb=delete.account', 'word1=bob', 'garbage', "nonce=$nonce", 'end'))))
        )
        foreach ($b in $bads) {
            $p = Plan $b[1]
            Add-Row "Q3 refused: $($b[0])" ((-not $p.Ok) -and ($p.Why -ne '')) "$($p.Stage): $($p.Why)"
        }
        Add-Row 'Q4 Test-RadminName: bob, a, a_b-c and a name of 20 are names; sdsys, Bob, a.b, -a and 21 characters are not' ((Test-RadminName 'bob') -and (Test-RadminName 'a') -and (Test-RadminName 'a_b-c') -and (Test-RadminName ('a' * 20)) -and -not (Test-RadminName 'sdsys') -and -not (Test-RadminName 'Bob') -and -not (Test-RadminName 'a.b') -and -not (Test-RadminName '-a') -and -not (Test-RadminName ('a' * 21))) ''

        # A: the sshd arm
        $sd = 'C:\Program Files\SD\usr\bin\sd.exe'
        $open = Get-RadminArmLines 'open' 'HOST1' $sd
        $closed = Get-RadminArmLines 'closed' 'HOST1' $sd
        Add-Row 'A1 the open arm: the fence, "Match User sdradmin,host1\sdradmin", Linux''s keywords (no GSSAPI), ForceCommand sd.exe quoted, the fence''s end' (($open[0] -ceq $RadminBegin) -and ($open[1] -ceq 'Match User sdradmin,host1\sdradmin') -and ($open -ccontains '    PasswordAuthentication yes') -and ($open -ccontains '    AuthenticationMethods password') -and ($open -ccontains '    PubkeyAuthentication no') -and ($open -ccontains '    AuthorizedKeysFile none') -and ($open -ccontains '    DisableForwarding yes') -and ($open -ccontains '    AllowTcpForwarding no') -and ($open -ccontains '    PermitTunnel no') -and ($open -ccontains '    MaxAuthTries 3') -and ($open[$open.Count - 2] -ceq ('    ForceCommand "' + $sd + '"')) -and ($open[$open.Count - 1] -ceq $RadminEnd) -and -not (@($open) -match 'GSSAPI') -and ($open.Count -eq 19)) ($open -join ' | ')
        Add-Row 'A2 the closed arm is the fence, the Match line and "DenyUsers *" alone' (($closed.Count -eq 4) -and ($closed[2] -ceq '    DenyUsers *')) ($closed -join ' | ')
        Add-Row 'A3 a form that is neither is $null' ($null -eq (Get-RadminArmLines 'opened' 'HOST1' $sd)) ''
        foreach ($nl in @("`r`n", "`n")) {
            $cfg = (@('# sshd_config', 'Port 22', 'Match Group administrators', '    AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys', '') -join $nl)
            $withOpen = Add-RadminBlockText $cfg $open
            $back = Remove-RadminBlockText $withOpen
            Add-Row "A4 open then removed gives the file back byte for byte ($(if ($nl.Length -eq 2) { 'CRLF' } else { 'LF' }))" ($back -ceq $cfg) ''
            Add-Row 'A5 the block goes after the last line of the file, after every Match, in the file''s own line ends' ($withOpen.StartsWith($cfg) -and $withOpen.EndsWith($RadminEnd + $nl) -and ($withOpen.Substring($cfg.Length) -ceq (($open -join $nl) + $nl))) ''
            $twice = Add-RadminBlockText (Add-RadminBlockText $withOpen $closed) $open
            Add-Row 'A6 writing the arm again replaces it: one fence, never two' (([regex]::Matches($twice, [regex]::Escape($RadminBegin))).Count -eq 1 -and ((Remove-RadminBlockText $twice) -ceq $cfg)) ''
            Add-Row 'A7 the state: open, closed, none' (((Get-RadminArmState $withOpen) -ceq 'open') -and ((Get-RadminArmState (Add-RadminBlockText $cfg $closed)) -ceq 'closed') -and ((Get-RadminArmState $cfg) -ceq 'none')) "$(Get-RadminArmState $withOpen)"
        }
        $noEnd = 'Port 22'
        Add-Row 'A8 a file with no last line end gets one before the block' ((Add-RadminBlockText $noEnd $closed) -ceq ("Port 22`n" + ($closed -join "`n") + "`n")) ''
        $cut = ((Add-RadminBlockText "Port 22`n" $open) -replace [regex]::Escape($RadminEnd), '')
        $edited = (Add-RadminBlockText "Port 22`n" $open).Replace('    PasswordAuthentication yes', '    PasswordAuthentication yes' + "`n" + '    PermitRootLogin yes')
        $two = "Port 22`n" + ($open -join "`n") + "`n" + ($open -join "`n") + "`n"
        $noEndExact = "Port 22`n" + (@($open[0..($open.Count - 2)]) -join "`n")
        Add-Row 'A9 damaged: a fence with no end (with and without what follows), a fence holding a line of somebody else''s, two fences' (((Get-RadminArmState $cut) -ceq 'damaged') -and ((Get-RadminArmState $noEndExact) -ceq 'damaged') -and ((Get-RadminArmState $edited) -ceq 'damaged') -and ((Get-RadminArmState $two) -ceq 'damaged')) "$(Get-RadminArmState $cut) $(Get-RadminArmState $noEndExact) $(Get-RadminArmState $edited) $(Get-RadminArmState $two)"

        # E: what sshd -T says, judged
        $t = @('port 22', 'allowgroups sdssh host1\sdssh', 'authenticationmethods password', 'kbdinteractiveauthentication no', 'passwordauthentication yes', 'pubkeyauthentication no',
               'hostbasedauthentication no', 'authorizedkeysfile none', 'maxauthtries 3', 'disableforwarding yes', 'x11forwarding no', 'allowagentforwarding no',
               'allowtcpforwarding no', 'allowstreamlocalforwarding no', 'permittunnel no', 'permituserrc no', 'permittty yes', ('forcecommand "' + $sd + '"'))
        Add-Row 'E1 sshd giving exactly the open arm is accepted' ((Test-RadminEffective $t 'open' $sd) -eq '') (Test-RadminEffective $t 'open' $sd)
        $ebad = @(
            @('password sign-in off', @($t | ForEach-Object { $_ -replace '^passwordauthentication yes$', 'passwordauthentication no' })),
            @('keys allowed', @($t | ForEach-Object { $_ -replace '^pubkeyauthentication no$', 'pubkeyauthentication yes' })),
            @('forwarding allowed', @($t | ForEach-Object { $_ -replace '^allowtcpforwarding no$', 'allowtcpforwarding yes' })),
            @('another forced command', @($t | ForEach-Object { $_ -replace '^forcecommand .*$', 'forcecommand cmd.exe' })),
            @('no forced command', @($t | Where-Object { $_ -notmatch '^forcecommand' })),
            @('a keyword sshd did not report', @($t | Where-Object { $_ -notmatch '^kbdinteractiveauthentication' })),
            @('a DenyUsers in force', @($t + 'denyusers bob')),
            @('an AllowUsers in force', @($t + 'allowusers bob')),
            @('no AllowGroups sdssh', @($t | Where-Object { $_ -notmatch '^allowgroups' })),
            @('AllowGroups without sdssh', @($t | ForEach-Object { $_ -replace '^allowgroups .*$', 'allowgroups users' })),
            @('NULL CASE: sshd printed nothing', @()),
            @('NULL CASE: sshd printed three lines', @('port 22', 'passwordauthentication yes', 'permittty yes'))
        )
        foreach ($e in $ebad) { Add-Row "E2 refused: $($e[0])" ((Test-RadminEffective $e[1] 'open' $sd) -ne '') (Test-RadminEffective $e[1] 'open' $sd) }
        Add-Row 'E3 the first value sshd prints is the one that counts' ((Test-RadminEffective (@('passwordauthentication no') + $t) 'open' $sd) -ne '') ''
        $tc = @($t | Where-Object { $_ -notmatch '^forcecommand' }) + 'denyusers *'
        Add-Row 'E4 closed: a DenyUsers * is accepted, none is refused' (((Test-RadminEffective $tc 'closed' $sd) -eq '') -and ((Test-RadminEffective ($t) 'closed' $sd) -ne '')) ''
        return ,$out
    } $reqRegion $armRegion
    foreach ($x in $inner) { $null = $rows.Add($x) }

    # P: the broker, read as text, in order
    $b = $t.broker
    $inv = $b.Substring([Math]::Max(0, $b.IndexOf('function Invoke-Request')))
    $ord = @('$pipe.RunAsClient(', "notcontains 'S-1-5-2'", 'Read-Request $pipe', 'ConvertFrom-RadminRequest $text', 'Get-RadminPlan $req', "Join-Path `$StateDir 'state'", 'Test-RadminTarget $t', 'Write-JobDefinition $jobName', '[Diagnostics.Process]::Start($psi)')
    $pos = @($ord | ForEach-Object { $inv.IndexOf($_) })
    $sorted = ($pos -join ',') -ceq ((@($pos | Sort-Object)) -join ',')
    $null = $rows.Add(@('P1 the broker asks the caller''s token (SDRADMIN, a NETWORK logon) before it reads a word, then the request, the plan, the state, the targets on Windows, the definition, and only then starts the job', ((@($pos | Where-Object { $_ -lt 0 }).Count -eq 0) -and $sorted), ($pos -join ',')))
    $np = $b.Substring([Math]::Max(0, $b.IndexOf('function New-RadminPipe')))
    $np = $np.Substring(0, [Math]::Max(0, $np.IndexOf("`n}")))
    $null = $rows.Add(@('P2 the pipe: no inherited access, exactly two rules (SDSYS full control, SDRADMIN read and write), one instance', (($np -match 'SetAccessRuleProtection\(\$true, \$false\)') -and ([regex]::Matches($np, 'AddAccessRule\(').Count -eq 2) -and ($np -match '\$sdsysSid\)\), \[IO\.Pipes\.PipeAccessRights\]::FullControl') -and ($np -match '\$radminSid\)\), \[IO\.Pipes\.PipeAccessRights\]''ReadWrite, Synchronize''') -and ($np -match "NamedPipeServerStream\('sd-radmin', \[IO\.Pipes\.PipeDirection\]::InOut, 1,") -and ($np -notmatch 'Everyone|S-1-1-0|S-1-5-11|sdusers')), ''))
    $secretUses = @([regex]::Matches($b, '[^\r\n]*\$req\.Secret[^\r\n]*') | ForEach-Object { $_.Value.Trim() })
    $logLines = @($b -split "`r?`n" | Where-Object { $_ -match 'Write-Log' })
    $null = $rows.Add(@('P3 the password goes to the job''s STANDARD INPUT and nowhere else: never to a log line, the arguments or a file; it is scrubbed from the answer and dropped after', (($b -match '\$p\.StandardInput\.BaseStream\.Write\(\$req\.Secret, 0, \$req\.Secret\.Length\)') -and ($b -match '\$out = \$out\.Replace\(\$Latin1\.GetString\(\$req\.Secret\), ''\*\*\*\*\*\*\*\*''\)') -and ($b -match '\$req\.Secret = \$null') -and (@($logLines | Where-Object { $_ -match '(?i)secret|\$pw' }).Count -eq 0) -and ($b -match "\`$psi\.Arguments = '-job ' \+ \`$jobName \+ ' ' \+ \`$plan\.Command") -and (@($secretUses | Where-Object { $_ -match 'WriteAllText|AppendAllText|Arguments|Write-Log' }).Count -eq 0)), ($secretUses -join ' || ')))
    $null = $rows.Add(@('P4 an SD process is never killed: no Kill, Stop-Process or taskkill; a run past 180 seconds is answered timeout= and left', (($b -notmatch '\.Kill\(|Stop-Process|taskkill') -and ($b -match 'WaitForExit\(180000\)') -and ($b -match "timeout=")), ''))
    $null = $rows.Add(@('P5 the one-shot definition is removed whatever happened (finally), and a nonce already used is refused', (($b -match "finally \{\s*\r?\n\s*\`$req\.Secret = \`$null\s*\r?\n\s*\`$def = Join-Path \`$JobsDir \`$jobName\s*\r?\n\s*if \(Test-Path -LiteralPath \`$def\) \{ Remove-Item") -and ($b -match "if \(Test-Path -LiteralPath \`$target\) \{ return 'that nonce has been used' \}")), ''))
    $null = $rows.Add(@('P6 a target that is a Windows user must be SD''s ("SD account") and not in Administrators (S-1-5-32-544)', (($b -match "\`$u\.Description -cne 'SD account'") -and ($b -match "Get-LocalGroupMember -SID 'S-1-5-32-544'")), ''))

    # C: the client
    $c = $t.client
    # The deletion that counts is the unconditional one on a line of its own (the catch's own clean-up is for a read that failed).
    $del = [regex]::Match($c, '\n[ ]+Remove-Item -LiteralPath \$Request -Force\r?\n')
    $cp = @($c.IndexOf('[IO.File]::ReadAllBytes($Request)'), $(if ($del.Success) { $del.Index } else { -1 }), $c.IndexOf('$pipe.Connect(5000)'), $c.IndexOf('GetOwner('), $c.IndexOf('$pipe.Write($out'))
    $null = $rows.Add(@('C1 the client reads the request, DELETES it, connects, checks the pipe''s owner (SDSYS, Administrators or SYSTEM), and only then sends; identification-level impersonation only', ((@($cp | Where-Object { $_ -lt 0 }).Count -eq 0) -and (($cp -join ',') -ceq ((@($cp | Sort-Object)) -join ',')) -and ($c -match "@\('S-1-5-18', 'S-1-5-32-544', \`$sdsys\) -notcontains \`$owner") -and ($c -match 'TokenImpersonationLevel\]::Identification')), ($cp -join ',')))
    $null = $rows.Add(@('C2 the client prints nothing of the request (no Out-Line or Write-Host of $text or $bytes)', (@($c -split "`r?`n" | Where-Object { $_ -match '(Out-Line|Write-Host|Write-Output)[^#]*\$(text|bytes|out)\b' }).Count -eq 0), ''))

    # R: remote-admin.ps1's -On and -Remove
    $a = $t.admin
    $on = $a.Substring([Math]::Max(0, $a.IndexOf('# -------------------------------------------------------------------- -On')))
    # 13 Nov 26 (RELEASE_1.1 280): Enable-LocalUser moved BEFORE the arm check - sshd -T -C cannot resolve a disabled account (measured).
    $rp = @($on.IndexOf("Test-InGroup 'S-1-5-32-544' `$userSid"), $on.IndexOf('Remove-FromGroup $g[0]'), $on.IndexOf('Enable-LocalUser'), $on.IndexOf("Write-SshdArm `$cfg `$sshd 'open'"), $on.IndexOf("Add-ToGroup `$sshSid"), $on.IndexOf("Set-StateFile 'on'"))
    $null = $rows.Add(@('R1 -On refuses an administrator (and an account SD did not make) before it changes anything; SDRADMIN is enabled (outside sdssh) before the arm is proved, since sshd -T cannot resolve a disabled account; sdssh after the proof; the state says on last', ((@($rp | Where-Object { $_ -lt 0 }).Count -eq 0) -and (($rp -join ',') -ceq ((@($rp | Sort-Object)) -join ',')) -and ($on.IndexOf("Description -cne 'SD account'") -lt $rp[1]) -and ($on.IndexOf("Description -cne 'SD account'") -ge 0)), ($rp -join ',')))
    $ws = $a.Substring([Math]::Max(0, $a.IndexOf('function Write-SshdArm')))
    $ws = $ws.Substring(0, [Math]::Max(0, $ws.IndexOf("`n}")))
    $null = $rows.Add(@('R2 a change sshd disagrees with is undone BYTE FOR BYTE (ReadAllBytes before, WriteAllBytes on any reason)', (($ws -match '\$orig = \[IO\.File\]::ReadAllBytes\(\$cfg\)') -and ($ws -match "if \(\`$why -ne ''\) \{ \[IO\.File\]::WriteAllBytes\(\`$cfg, \`$orig\) \}") -and ($ws -match 'catch \{ \$why = ')), ''))
    $null = $rows.Add(@('R3 the deny rights are console, Remote Desktop, batch and service - and NEVER network (sshd signs a password in with a network logon)', (($a -match "\`$DenyRights = @\('SeDenyInteractiveLogonRight', 'SeDenyRemoteInteractiveLogonRight', 'SeDenyBatchLogonRight', 'SeDenyServiceLogonRight'\)") -and ($a -notmatch "'SeDenyNetworkLogonRight'")), ''))
    $null = $rows.Add(@('R4 -On takes SDRADMIN out of Users, Remote Desktop Users, Remote Management Users, Backup Operators, sdapi and the sdfiles groups, and never adds it to any but sdsshonly and sdssh', (($on -match "'S-1-5-32-545', 'Users'") -and ($on -match "'S-1-5-32-555'") -and ($on -match "'S-1-5-32-580'") -and ($on -match "'S-1-5-32-551'") -and ($on -match "Get-GroupSid 'sdapi'") -and ($on -match "Get-GroupSid 'sdfilesadmin'") -and (@([regex]::Matches($a, 'Add-ToGroup \$\w+') | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ',') -ceq 'Add-ToGroup $onlySid,Add-ToGroup $sshSid'), ''))
    $null = $rows.Add(@('R5 -Remove leaves SDRADMIN in sdusers (the uninstaller''s accounts question reads sdusers) and only ever removes it from sdssh', ((@([regex]::Matches($a, "Remove-FromGroup \(Get-GroupSid '(\w+)'\)") | ForEach-Object { $_.Groups[1].Value }) -join ',') -ceq 'sdssh'), ''))
    $ta = $a.Substring([Math]::Max(0, $a.IndexOf('function Test-SshdArm')))
    $ta = $ta.Substring(0, [Math]::Max(0, $ta.IndexOf("`n}")))
    $null = $rows.Add(@('R7 (RELEASE_1.1 280) for a disabled SDRADMIN the arm check refuses an OPEN arm and checks a shut one with sshd -t, saying so; only one Enable-LocalUser, in -On',
        (($ta -match "if \(\`$mode -cne 'closed'\) \{ return 'SDRADMIN is disabled") -and ($ta -match "\`$psi\.Arguments = '-t'") -and ($ta -match "-not \`$acct\.Enabled") -and ($ta -match "\`$script:ArmCheck = 'sshd -t only") -and ($a -match 'checked by \$script:ArmCheck') -and (@([regex]::Matches($a, 'Enable-LocalUser')).Count -eq 1)), ''))
    $it = $a.Substring([Math]::Max(0, $a.IndexOf('function Invoke-SshdT(')))
    $it = $it.Substring(0, [Math]::Max(0, $it.IndexOf("`n}")))
    $is = $a.Substring([Math]::Max(0, $a.IndexOf('function Invoke-SystemTask')))
    $is = $is.Substring(0, [Math]::Max(0, $is.IndexOf("`n}")))
    $null = $rows.Add(@('R8 (RELEASE_1.1 280) sshd -T -C about SDRADMIN runs as SYSTEM: anyone else hands it to a one-shot SYSTEM task, which is always unregistered and its files deleted, and whose registration and start stop on error',
        (($it -match "if \(\[Security\.Principal\.WindowsIdentity\]::GetCurrent\(\)\.User\.Value -ne 'S-1-5-18'\) \{ return \(Invoke-SshdTAsSystem \`$sshd \`$spec\) \}") -and ($is -match "New-ScheduledTaskPrincipal -UserId 'S-1-5-18'") -and ($is -match '-EncodedCommand ') -and ($is -match "-Principal \`$pr -Force -ErrorAction Stop") -and ($is -match "Start-ScheduledTask -TaskPath '\\SD\\' -TaskName 'sdcore-radmin-check' -ErrorAction Stop") -and ($is -match "\} finally \{\s*\r?\n\s*Unregister-ScheduledTask -TaskPath '\\SD\\' -TaskName 'sdcore-radmin-check'") -and ($is -match 'foreach \(\$f in \$files\) \{ if \(Test-Path -LiteralPath \$f\) \{ Remove-Item')), ''))
    # R9: the broker.  Every task cmdlet stops on error (a module's cmdlets do not see the script's $ErrorActionPreference); -On is
    # SDSYS's alone (RELEASE_1.1 282: exit 4, nothing changed, for anyone else) and registers the broker task BEFORE any wall moves, as
    # SDSYS, with no password route anywhere; "running" is printed only once the broker's pipe exists; no Enable-ScheduledTask in -On.
    $rb = $a.Substring([Math]::Max(0, $a.IndexOf('function Register-BrokerTask')))
    $rb = $rb.Substring(0, [Math]::Max(0, $rb.IndexOf("`n}")))
    $taskLines = @($a -split "`r?`n" | Where-Object { $_ -match '^\s+[^#]*\b(Register|Enable|Disable|Start|Stop|Unregister)-ScheduledTask\b' -and $_ -notmatch "'sdcore-radmin-check' -Confirm:\`$false -ErrorAction SilentlyContinue" })
    $noStop = @($taskLines | Where-Object { $_ -notmatch '-ErrorAction Stop' })
    $iExit4 = $on.IndexOf("Exit-With 4 'remote administration is opened by SDSYS")
    $iReg = $on.IndexOf('Register-BrokerTask (Get-BrokerXml $sdsysSid) $sdsysSid')
    $iWall = $on.IndexOf('Remove-FromGroup $g[0]')
    $null = $rows.Add(@('R9 (RELEASE_1.1 280, 282) every task cmdlet stops on error; -On is SDSYS''s alone (exit 4 otherwise) and registers the broker task, as SDSYS, before any wall moves; no password route; "running" only once \\.\pipe\sd-radmin exists',
        (($taskLines.Count -ge 7) -and ($noStop.Count -eq 0) -and ($iExit4 -ge 0) -and ($iExit4 -lt $iReg) -and ($iReg -lt $iWall) -and
         ($on -match "if \(\[Security\.Principal\.WindowsIdentity\]::GetCurrent\(\)\.User\.Value -ne \`$sdsysSid\) \{\s*\r?\n\s*Exit-With 4 ") -and
         ($on -match "if \(-not \(Test-BrokerPipe\)\) \{ throw ") -and ($on.IndexOf("if (-not (Test-BrokerPipe)) { throw ") -lt $on.IndexOf('the broker is running: ')) -and ($on.IndexOf('the broker is running: ') -ge 0) -and
         ($on -notmatch '(?m)^\s+Enable-ScheduledTask') -and
         ($rb -match "if \(\[Security\.Principal\.WindowsIdentity\]::GetCurrent\(\)\.User\.Value -ne \`$sdsysSid\) \{ throw ") -and
         ($rb.IndexOf('throw ''the broker task is registered by SDSYS only''') -lt $rb.IndexOf('Register-ScheduledTask')) -and
         ($a -notmatch 'SdsysPassword|RegisterTaskDefinition|SecureStringToBSTR') -and ($rb -notmatch 'Invoke-SystemTask')),
        ("task cmdlet lines {0}, without -ErrorAction Stop: {1}; exit4 {2} < register {3} < first wall {4}" -f $taskLines.Count, ($noStop -join ' | '), $iExit4, $iReg, $iWall)))
    # R10 (RELEASE_1.1 280): the task folder \SD.  Measured 13 Nov: the root folder gives Authenticated Users write, inherited, and an
    # ordinary user can make a top-level folder and own it.  \SD is made protected, SYSTEM and Administrators only; an existing one is used
    # only when SYSTEM, Administrators or a member owns it and is then tightened; both SD tasks are deleted before they are registered.
    # 13 Nov 26 (RELEASE_1.1 281): the rule is ONE copy, sd-taskfolder.ps1, which remote-admin.ps1 dot-sources and no longer defines.
    $tf = $t.taskfolder
    $sf = $tf.Substring([Math]::Max(0, $tf.IndexOf('function Initialize-SdTaskFolder')))
    $sf = $sf.Substring(0, [Math]::Max(0, $sf.IndexOf("`n}")))
    $ao = $tf.Substring([Math]::Max(0, $tf.IndexOf('function Test-SdAdminOwner')))
    $ao = $ao.Substring(0, [Math]::Max(0, $ao.IndexOf("`n}")))
    $null = $rows.Add(@('R10 (RELEASE_1.1 280, 281) \SD is made protected, SYSTEM and Administrators only; an existing one is used only when SYSTEM, Administrators or a member owns it, then tightened; the broker and the SYSTEM check task are vetted into it and deleted before they are registered',
        ($tf.Contains("`$SdTaskFolderSddl = 'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'") -and
         ($sf -match "catch \{ return \`$svc\.GetFolder\('\\'\)\.CreateFolder\('SD', \`$SdTaskFolderSddl\) \}") -and
         ($sf -match "if \(\`$null -eq \`$owner -or -not \(Test-SdAdminOwner \`$owner\.Value\)\) \{\s*\r?\n\s*throw ") -and ($sf -match "\`$f\.SetSecurityDescriptor\(\`$SdTaskFolderSddl, 0\)") -and
         ($sf.IndexOf('throw (') -lt $sf.IndexOf('$f.SetSecurityDescriptor(')) -and
         ($ao -match "if \(@\('S-1-5-18', 'S-1-5-32-544'\) -contains \`$sid\) \{ return \`$true \}") -and ($ao -match "\} catch \{ return \`$false \}") -and
         ($a.Contains(". (Join-Path `$PSScriptRoot 'sd-taskfolder.ps1')")) -and -not $a.Contains('function Initialize-SdTaskFolder') -and -not $a.Contains('$SdTaskFolderSddl = ') -and
         ($rb -match "\`$folder = Initialize-SdTaskFolder \`$svc") -and ($rb.IndexOf("try { `$folder.DeleteTask('sdcore-radmin', 0) } catch { }") -ge 0) -and
         ($rb.IndexOf("try { `$folder.DeleteTask('sdcore-radmin', 0) } catch { }") -lt $rb.IndexOf('Register-ScheduledTask -TaskName')) -and
         ($is -match "\`$sdFolder = Initialize-SdTaskFolder \`$svc") -and ($is.IndexOf("try { `$sdFolder.DeleteTask('sdcore-radmin-check', 0) } catch { }") -ge 0) -and
         ($is.IndexOf("try { `$sdFolder.DeleteTask('sdcore-radmin-check', 0) } catch { }") -lt $is.IndexOf('Register-ScheduledTask -TaskName'))), ''))
    # R11 (RELEASE_1.1 281): SET.JOB's tasks under the same rule, every sd-jobs task cmdlet stopping on error, \SD made at install, the rule shipped.
    $jb = $t.jobs
    $js = $jb.Substring([Math]::Max(0, $jb.IndexOf("'job-set' {")))
    $js = $js.Substring(0, [Math]::Max(0, $js.IndexOf("'job-delete' {")))
    $jobTaskLines = @($jb -split "`r?`n" | Where-Object { $_ -match '^\s+[^#]*\b(Register|Enable|Disable|Start|Stop|Unregister)-ScheduledTask\b' })
    $jobNoStop = @($jobTaskLines | Where-Object { $_ -notmatch '-ErrorAction Stop' })
    $fi = $t.finish
    $fiBlock = $fi.Substring([Math]::Max(0, $fi.IndexOf("    . (Join-Path `$PSScriptRoot 'sd-taskfolder.ps1')")))
    $null = $rows.Add(@('R11 (RELEASE_1.1 281) job-set vets \SD and deletes the job''s task before registering it; every sd-jobs task cmdlet stops on error; finish-install makes \SD at install; stage.py ships sd-taskfolder.ps1',
        ($jb.Contains(". (Join-Path `$PSScriptRoot 'sd-taskfolder.ps1')") -and -not $jb.Contains('function Initialize-SdTaskFolder') -and
         ($js -match "\`$sdFolder = Initialize-SdTaskFolder \`$svc") -and ($js.IndexOf('try { $sdFolder.DeleteTask("sdcore-job-$n", 0) } catch { }') -ge 0) -and
         ($js.IndexOf('try { $sdFolder.DeleteTask("sdcore-job-$n", 0) } catch { }') -lt $js.IndexOf('Register-ScheduledTask -TaskName')) -and
         ($jobTaskLines.Count -ge 4) -and ($jobNoStop.Count -eq 0) -and
         ($fiBlock -match "^\s*\. \(Join-Path \`$PSScriptRoot 'sd-taskfolder\.ps1'\)\s*\r?\n\s*\`$tsSvc = New-Object -ComObject Schedule\.Service\s*\r?\n\s*\`$tsSvc\.Connect\(\)\s*\r?\n\s*\`$null = Initialize-SdTaskFolder \`$tsSvc") -and
         ($fi.IndexOf('$null = Initialize-SdTaskFolder $tsSvc') -lt $fi.IndexOf('# AND ON TO THE CHECK')) -and
         $t.stage.Contains("'sd-taskfolder.ps1',")),
        ("sd-jobs task cmdlet lines {0}, without -ErrorAction Stop: {1}" -f $jobTaskLines.Count, ($jobNoStop -join ' | '))))
    # R12 (RELEASE_1.1 291, 14 Nov 26): a RUNNING task is stopped before it is unregistered - measured in the VM, Unregister-ScheduledTask alone leaves
    # the process running and its files locked, and the uninstaller's removal of the running broker left C:\ProgramData\SD half deleted.  The helper
    # is in sd-taskfolder.ps1 once; the broker's -Remove branch and sd-jobs' job-purge call it BEFORE their Unregister; and the helper itself is
    # DRIVEN here on stubs (not running: no stop; running: stopped and waited for; stuck: false; absent: true).
    $tfx = $t.taskfolder
    $stopFn = [regex]::Match($tfx, '(?ms)^function Stop-SdTaskBeforeRemoval.*?^\}').Value
    $beh = @()
    if ($stopFn -ne '') {
        $beh = & {
            function Get-ScheduledTask { if ($script:tsGone) { return $null }; return [pscustomobject]@{ State = $script:tsState } }
            function Stop-ScheduledTask { $script:tsCalls += 'stop'; if (-not $script:tsStuck) { $script:tsState = 'Ready' } }
            function Start-Sleep { }
            . ([scriptblock]::Create($stopFn))
            $r = @()
            $script:tsGone = $false; $script:tsStuck = $false; $script:tsCalls = @(); $script:tsState = 'Ready'
            $r += ('notrunning:' + (Stop-SdTaskBeforeRemoval '\SD\' 'x' 1) + ':' + $script:tsCalls.Count)
            $script:tsCalls = @(); $script:tsState = 'Running'
            $r += ('running:' + (Stop-SdTaskBeforeRemoval '\SD\' 'x' 1) + ':' + $script:tsCalls.Count)
            $script:tsCalls = @(); $script:tsState = 'Running'; $script:tsStuck = $true
            $r += ('stuck:' + (Stop-SdTaskBeforeRemoval '\SD\' 'x' 1) + ':' + $script:tsCalls.Count)
            $script:tsStuck = $false; $script:tsGone = $true
            $r += ('absent:' + (Stop-SdTaskBeforeRemoval '\SD\' 'x' 1))
            $r
        }
    }
    $rm = $a.Substring([Math]::Max(0, $a.IndexOf("if (`$armMode -ceq 'none') {")))
    $rm = $rm.Substring(0, [Math]::Max(0, $rm.IndexOf("Out-Line `"`${Prog}: the broker task is removed`"")))
    $jpu = $jb.Substring([Math]::Max(0, $jb.IndexOf("'job-purge' {")))
    $jpu = $jpu.Substring(0, [Math]::Max(0, $jpu.IndexOf('Out-Line "${Prog}: task $($t.TaskName) removed"')))
    $null = $rows.Add(@('R12 (RELEASE_1.1 291) a running task is stopped and waited for before it is unregistered: the helper is in sd-taskfolder.ps1 and works (driven on stubs), and the broker''s -Remove and sd-jobs'' job-purge call it before Unregister-ScheduledTask',
        (($tfx -match 'function Stop-SdTaskBeforeRemoval') -and ($tfx -match 'Stop-ScheduledTask -TaskPath \$taskPath -TaskName \$taskName -ErrorAction Stop') -and ($tfx -match "while \(\`$null -ne \`$t -and \[string\]\`$t\.State -eq 'Running'") -and
         (($beh -join ' ') -ceq 'notrunning:True:0 running:True:1 stuck:False:1 absent:True') -and
         ($rm.IndexOf("Stop-SdTaskBeforeRemoval '\SD\' 'sdcore-radmin'") -ge 0) -and ($rm.IndexOf("Stop-SdTaskBeforeRemoval '\SD\' 'sdcore-radmin'") -lt $rm.IndexOf('Unregister-ScheduledTask')) -and
         ($jpu.IndexOf('Stop-SdTaskBeforeRemoval $JobTaskPath $t.TaskName') -ge 0) -and ($jpu.IndexOf('Stop-SdTaskBeforeRemoval $JobTaskPath $t.TaskName') -lt $jpu.IndexOf('Unregister-ScheduledTask'))),
        ('helper driven: ' + ($beh -join ' '))))
    $null = $rows.Add(@('R6 the success lines are open, closed and removed, each printed only at the end of its branch', (($a -match 'Out-Line "\$\{Prog\}: open"\s*\r?\n\s*exit 0') -and ($a -match 'Out-Line "\$\{Prog\}: closed"\s*\r?\n\s*exit 0') -and ($a -match 'Out-Line "\$\{Prog\}: removed"\s*\r?\n\s*exit 0')), ''))

    # G: allow-ssh-groups.ps1 reads remote-admin's fence as SD's own
    $g = $t.allow
    $null = $rows.Add(@('G1 allow-ssh-groups.ps1 does not count the remote administration fence''s DenyUsers as somebody else''s restriction, and puts its own block above that fence', (($g -match "if \(\`$l\.StartsWith\('# --- BEGIN SD remote administration \(RELEASE_1\.1 202\)'\)\) \{ \`$inRadmin = \`$true; continue \}") -and ($g -match "if \(\`$inOurs -or \`$inRadmin\) \{ continue \}") -and ($g -match "if \(\`$lines\[\`$i\]\.StartsWith\('# --- BEGIN SD remote administration \(RELEASE_1\.1 202\)'\)\) \{ \`$at = \`$i; break \}") -and $t.admin.Contains("'# --- BEGIN SD remote administration (RELEASE_1.1 202) - remote-admin.ps1 writes this; do not edit within this fence ---'") -and $t.admin.Contains("'# --- END SD remote administration ---'") -and $g.Contains("'# --- END SD remote administration ---'")), ''))
    return ,$rows
}

function Show-Rows($rows) {
    # Prints with [Console]::Out and RETURNS only the count: a function that does both through Write-Output hands its caller an array.
    $bad = 0
    foreach ($r in $rows) {
        $line = "  [{0}] {1}{2}" -f $(if ($r[1]) { 'PASS' } else { 'FAIL' }), $r[0], $(if ($r[1] -or $r[2] -eq '') { '' } else { '   <- ' + ([string]$r[2]).Substring(0, [Math]::Min(200, ([string]$r[2]).Length)) })
        [Console]::Out.WriteLine($line)
        if (-not $r[1]) { $bad++ }
    }
    return $bad
}

$rows = Get-Rows $texts

# J: sd-jobs.ps1 leaves the radmin- names to the broker (its dry run: a scratch folder, Task Scheduler never asked)
$tmp = Join-Path ([IO.Path]::GetTempPath()) ('remoteadmin-units-' + [Guid]::NewGuid().ToString('N'))
$jd = Join-Path $tmp 'sd-jobs'
try {
    New-Item -ItemType Directory -Path $jd -Force | Out-Null
    function Run-Jobs([string[]]$words) {
        $a = @('-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', $files.jobs) + $words + @('-DryRun', '-TestJobsDir', $jd)
        $o = & powershell.exe @a | ForEach-Object { "$_" }
        return @{ Rc = $LASTEXITCODE; Out = @($o); Cmd = ($words -join ' ') }
    }
    $r = Run-Jobs @('job-set', 'radmin-0123456789abcdef', 'backup-all', 'hourly')
    Write-Output "  ran: sd-jobs.ps1 $($r.Cmd) -DryRun -> exit $($r.Rc)"
    $rows += , @('J1 job-set refuses a name that starts radmin- (exit 1) and writes nothing', (($r.Rc -eq 1) -and (@($r.Out) -match 'radmin- is the remote administration broker').Count -gt 0 -and -not (Test-Path -LiteralPath (Join-Path $jd 'radmin-0123456789abcdef'))), ($r.Out -join ' | '))
    [IO.File]::WriteAllText((Join-Path $jd 'radmin-0123456789abcdef'), "name=radmin-0123456789abcdef`njob=radmin`ncommand=remote.sdsys run remote.sdsys status`nschedule=once`n", [Text.Encoding]::ASCII)
    $r = Run-Jobs @('job-list')
    Write-Output "  ran: sd-jobs.ps1 $($r.Cmd) -DryRun -> exit $($r.Rc) with one radmin- definition in the folder"
    $rows += , @('J2 job-list does not show a radmin- definition, as damaged or otherwise (exit 0, "no job is defined")', (($r.Rc -eq 0) -and (@($r.Out | Where-Object { $_ -match 'radmin-' }).Count -eq 0) -and (@($r.Out) -contains 'sd-jobs: no job is defined')), ($r.Out -join ' | '))
    $r = Run-Jobs @('job-run', 'radmin-0123456789abcdef')
    $rows += , @('J3 job-run does not start a radmin- definition ("no job named", exit 0)', (($r.Rc -eq 0) -and (@($r.Out) -contains 'sd-jobs: no job named radmin-0123456789abcdef; nothing was started')), ($r.Out -join ' | '))
} finally {
    if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}

$bad = Show-Rows $rows
$n = @($rows).Count
Write-Output ''
Write-Output "test-remoteadmin-units: $($n - $bad) passed, $bad failed of $n rows"
if ($n -lt 110) { Write-Output "test-remoteadmin-units: FAIL - only $n rows; a real run has more than 110"; $bad++ }
$rc = $(if ($bad -gt 0) { 1 } else { 0 })

if ($SelfTest) {
    $mutants = @(
        @('a key not on the list is read', 'Q3', 'broker', '        if ($RadminKeys -cnotcontains $key) { $r.Why = "the request has a key it may not have ($key)"; return $r }', ''),
        @('a key may come twice', 'Q3', 'broker', '        if ($f.ContainsKey($key)) { $r.Why = "the request has the key $key twice"; return $r }', ''),
        @('any nonce', 'Q3', 'broker', '-cmatch ''^[0-9a-f]{16}$'') { $r.Nonce', '-cmatch ''.'') { $r.Nonce'),
        @('a reserved name is a target', 'Q3', 'broker', '    return ($RadminReserved -cnotcontains $n)', '    return $true'),
        @('a name may be 21 long', 'Q3', 'broker', '''^[a-z][a-z0-9_-]{0,19}$''', '''^[a-z][a-z0-9_-]{0,20}$'''),
        @('a name may hold a dot', 'Q3', 'broker', '''^[a-z][a-z0-9_-]{0,19}$''', '''^[a-z][a-z0-9_.-]{0,19}$'''),
        @('a password may hold a control character', 'Q3', 'broker', '            if ($b -lt 0x20 -or $b -eq 0x7f) { $r.Why = ''the password holds a control character''; return $r }', ''),
        @('a password where none belongs', 'Q3', 'broker', "    if (-not `$p.NeedsSecret -and `$null -ne `$req.Secret) { `$p.Why = 'this command takes no password and the request has one'; return `$p }", ''),
        @('no password where one belongs', 'Q3', 'broker', "    if (`$p.NeedsSecret -and `$null -eq `$req.Secret) { `$p.Why = 'this command needs the new password and the request has none'; return `$p }", ''),
        @('remote.sdsys on is allowed', 'Q3', 'broker', "`$RadminReports = @('off', 'status', 'audit', 'accounts')", "`$RadminReports = @('on', 'off', 'status', 'audit', 'accounts')"),
        @('remote.ssh takes any one word', 'Q3', 'broker', "(`$w.Count -eq 1 -and `$RadminSshWords -cnotcontains `$w[0])) { `$p.Why = 'remote.ssh", "(`$false)) { `$p.Why = 'remote.ssh"),
        @('remote.ssh takes two words', 'Q3', 'broker', "            if (`$w.Count -gt 1 -or (`$w.Count -eq 1 -and `$RadminSshWords", "            if ((`$w.Count -eq 1 -and `$RadminSshWords"),
        @('remote.api takes restart', 'Q3', 'broker', "`$RadminApiWords = @('on', 'local', 'off')", "`$RadminApiWords = @('on', 'local', 'off', 'restart')"),
        @('remote.api takes an answer after the keyword', 'Q3', 'broker', "            if (`$w.Count -gt 1 -or (`$w.Count -eq 1 -and `$RadminApiWords", "            if ((`$w.Count -eq 1 -and `$RadminApiWords"),
        @('remote.api is off the list', 'Q1', 'broker', "'remote.sdsys', 'remote.ssh', 'remote.api')", "'remote.sdsys', 'remote.ssh')"),
        @('remote.ssh is off the plan', 'Q1', 'broker', "        'remote.ssh' {`n", "        'remote.ssh.x' {`n"),
        @('two routes allowed', 'Q3', 'broker', "    if (`$routes -gt 1) { return 'more than one of ssh, api, both and none' }", ''),
        @('a word may repeat', 'Q3', 'broker', '        if ($seen.ContainsKey($w)) { return "$w is given twice" }', ''),
        @('create.account other is allowed', 'Q3', 'broker', "(`$w[0] -cne 'user' -and `$w[0] -cne 'group')", "(`$w[0] -cne 'user' -and `$w[0] -cne 'group' -and `$w[0] -cne 'other')"),
        @('the modify list takes a word it should not', 'Q3', 'broker', "'suspended', 'unsuspended')", "'suspended', 'unsuspended', 'administrator')"),
        @('the audit limit is gone', 'Q3', 'broker', "if (`$w.Count -eq 2 -and [int]`$w[1] -gt 500)", "if (`$w.Count -eq 2 -and [int]`$w[1] -gt 999)"),
        @('a gap in the words is let through', 'Q3', 'broker', "    if (`$nw -ne `$words.Count) { `$r.Why = 'the words of the request are not numbered from 1 without a gap'; return `$r }", ''),
        @('the command takes the verb as typed', 'Q1', 'broker', "    `$p.Command = (@('remote.sdsys', 'run', `$v) + `$w) -join ' '", "    `$p.Command = (@('remote.sdsys', 'run', `$v) + `$w) -join '  '"),
        @('the job is started before the targets are checked', 'P1', 'broker', '        foreach ($t in $plan.Targets) { if ($why -eq '''') { $why = Test-RadminTarget $t } }', '        $null = 1'),
        @('the pipe admits Everyone', 'P2', 'broker', "[IO.Pipes.PipeAccessRights]'ReadWrite, Synchronize', 'Allow')))", "[IO.Pipes.PipeAccessRights]'ReadWrite, Synchronize', 'Allow')))`n    `$sec.AddAccessRule((New-Object IO.Pipes.PipeAccessRule((New-Object Security.Principal.SecurityIdentifier('S-1-1-0')), [IO.Pipes.PipeAccessRights]::ReadWrite, 'Allow')))"),
        @('the pipe takes more than one instance', 'P2', 'broker', "[IO.Pipes.PipeDirection]::InOut, 1,", "[IO.Pipes.PipeDirection]::InOut, 4,"),
        @('the password is logged', 'P3', 'broker', '            Write-Log "done verb=', '            Write-Log "secret=$($req.Secret) done verb='),
        @('the password is not scrubbed from the answer', 'P3', 'broker', "            if (`$null -ne `$req.Secret) { `$out = `$out.Replace(`$Latin1.GetString(`$req.Secret), '********') }", ''),
        @('the password goes on the command line', 'P3', 'broker', "`$psi.Arguments = '-job ' + `$jobName + ' ' + `$plan.Command", "`$psi.Arguments = '-job ' + `$jobName + ' ' + `$plan.Command + ' ' + `$Latin1.GetString(`$req.Secret)"),
        @('a slow job is killed', 'P4', 'broker', "            `$answer += ('timeout=' + `$p.Id)", "            `$p.Kill()`n            `$answer += ('timeout=' + `$p.Id)"),
        @('a nonce may be used twice', 'P5', 'broker', "    if (Test-Path -LiteralPath `$target) { return 'that nonce has been used' }", ''),
        @('a Windows user SD did not make is a target', 'P6', 'broker', "    if (`$u.Description -cne 'SD account') { return `"`$name is a Windows account SD did not make`" }", ''),
        @('the client connects before it deletes the request', 'C1', 'client', "    Remove-Item -LiteralPath `$Request -Force`n", "`n"),
        @('the client sends to any pipe', 'C1', 'client', "if (@('S-1-5-18', 'S-1-5-32-544', `$sdsys) -notcontains `$owner -or `$owner -eq '')", "if (`$false)"),
        @('the client prints the request', 'C2', 'client', "    `$out = [Text.Encoding]::ASCII.GetBytes(`$text)", "    Out-Line `$text`n    `$out = [Text.Encoding]::ASCII.GetBytes(`$text)"),
        @('the open arm loses PasswordAuthentication yes', 'A1', 'admin', "    @('PasswordAuthentication', 'yes'),`n", ''),
        @('the open arm forwards', 'A1', 'admin', "    @('DisableForwarding', 'yes'),", "    @('DisableForwarding', 'no'),"),
        @('the closed arm lets SDRADMIN in', 'A2', 'admin', "        `$lines += '    DenyUsers *'", "        `$lines += '    DenyUsers nobody'"),
        @('removal leaves the fence''s end', 'A4', 'admin', "        if (`$in) { if (`$l -ceq `$RadminEnd) { `$in = `$false }; continue }", "        if (`$in) { if (`$l -ceq `$RadminEnd) { `$in = `$false; `$null = `$out.Add(`$l) }; continue }"),
        @('the block goes first in the file', 'A5', 'admin', "    return (`$base + (`$arm -join `$nl) + `$nl)", "    return ((`$arm -join `$nl) + `$nl + `$base)"),
        @('a fence with no end reads as open', 'A9', 'admin', "    if (`$begins -ne 1 -or `$ends -ne 1) { return 'damaged' }", ''),
        @('a forced command that is not SD passes', 'E2', 'admin', "    if (`$fc -ine `$sdExe) { return ('sshd would force `"' + `$fc + '`" and not SD (' + `$sdExe + ')') }", ''),
        @('a DenyUsers in force passes', 'E2', 'admin', "    if (`$eff.ContainsKey('denyusers')) { return ('a DenyUsers (`"' + `$eff['denyusers'] + '`") applies to SDRADMIN, so the open arm would not open') }", ''),
        @('the last value sshd prints counts', 'E3', 'admin', "        if (-not `$eff.ContainsKey(`$k)) { `$eff[`$k] = `$l.Substring(`$sp + 1).Trim() }", "        `$eff[`$k] = `$l.Substring(`$sp + 1).Trim()"),
        @('-On does not refuse an administrator', 'R1', 'admin', "    if (Test-InGroup 'S-1-5-32-544' `$userSid) { Exit-With 1 'SDRADMIN is a member of Administrators; remote administration is never opened for an administrator - take it out first' }", ''),
        @('-On proves the arm before SDRADMIN is enabled (RELEASE_1.1 280)', 'R1', 'admin', "    # 13 Nov 26 - RELEASE_1.1 280: ENABLED BEFORE THE ARM IS CHECKED.", "    `$why = Write-SshdArm `$cfg `$sshd 'open' `$SdExe`n    # 13 Nov 26 - RELEASE_1.1 280: ENABLED BEFORE THE ARM IS CHECKED."),
        @('an open arm is checked for a disabled SDRADMIN', 'R7', 'admin', "        if (`$mode -cne 'closed') { return 'SDRADMIN is disabled, and sshd cannot resolve a disabled account to check an open arm' }", ''),
        @('a shut arm checked by sshd -t does not say so', 'R7', 'admin', "        `$script:ArmCheck = 'sshd -t only: SDRADMIN is disabled, which sshd -T cannot resolve'", ''),
        @('the arm is checked from the caller''s own token (RELEASE_1.1 280)', 'R8', 'admin', "    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne 'S-1-5-18') { return (Invoke-SshdTAsSystem `$sshd `$spec) }", ''),
        @('the SYSTEM check task is left registered', 'R8', 'admin', "        Unregister-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin-check' -Confirm:`$false -ErrorAction SilentlyContinue", ''),
        @('-On says the broker runs without its pipe (RELEASE_1.1 280)', 'R9', 'admin', "        if (-not (Test-BrokerPipe)) { throw ('the broker started but its pipe \\.\pipe\sd-radmin did not appear in 20 seconds (task state ' + (Get-TaskState) + ')') }", ''),
        @('a task cmdlet in -On carries on after an error', 'R9', 'admin', "        Start-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin' -ErrorAction Stop", "        Start-ScheduledTask -TaskPath '\SD\' -TaskName 'sdcore-radmin'"),
        @('-On goes on for a caller that is not SDSYS', 'R9', 'admin', "        Exit-With 4 'remote administration is opened by SDSYS: run REMOTE.SDSYS ON at SDSYS''s console; nothing was changed'", "        `$null = 4"),
        @('the broker is registered for a caller that is not SDSYS', 'R9', 'admin', "    if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -ne `$sdsysSid) { throw 'the broker task is registered by SDSYS only' }", ''),
        @('\SD is made with inherited defaults (Authenticated Users write)', 'R10', 'taskfolder', "catch { return `$svc.GetFolder('\').CreateFolder('SD', `$SdTaskFolderSddl) }", "catch { return `$svc.GetFolder('\').CreateFolder('SD') }"),
        @('the \SD access list grants Authenticated Users write', 'R10', 'taskfolder', "'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)'", "'O:BAG:SYD:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)(A;OICI;FW;;;AU)'"),
        @('an \SD owned by anybody is used', 'R10', 'taskfolder', "    if (`$null -eq `$owner -or -not (Test-SdAdminOwner `$owner.Value)) {", "    if (`$false) {"),
        @('a doubtful membership lookup trusts the owner', 'R10', 'taskfolder', "    } catch { return `$false }", "    } catch { return `$true }"),
        @('remote-admin keeps its own copy of the rule', 'R10', 'admin', ". (Join-Path `$PSScriptRoot 'sd-taskfolder.ps1')", "function Initialize-SdTaskFolder(`$svc) { return `$svc.GetFolder('\SD') }"),
        @('a job''s task already there is updated in place', 'R11', 'jobs', '                try { $sdFolder.DeleteTask("sdcore-job-$n", 0) } catch { }', ''),
        @('job-set registers into an unvetted \SD', 'R11', 'jobs', '                $sdFolder = Initialize-SdTaskFolder $svc', '                $sdFolder = $svc.GetFolder(''\SD'')'),
        @('a refused job registration falls through to "scheduled"', 'R11', 'jobs', 'Register-ScheduledTask -TaskName "sdcore-job-$n" -TaskPath $JobTaskPath -Xml $xml -Force -ErrorAction Stop | Out-Null', 'Register-ScheduledTask -TaskName "sdcore-job-$n" -TaskPath $JobTaskPath -Xml $xml -Force | Out-Null'),
        @('a refused job start falls through to "started"', 'R11', 'jobs', 'try { Start-ScheduledTask -TaskPath $JobTaskPath -TaskName "sdcore-job-$n" -ErrorAction Stop } catch {', 'try { Start-ScheduledTask -TaskPath $JobTaskPath -TaskName "sdcore-job-$n" } catch {'),
        @('the installer does not make \SD', 'R11', 'finish', '    $null = Initialize-SdTaskFolder $tsSvc', '    $null = 0'),
        @('sd-taskfolder.ps1 does not ship', 'R11', 'stage', "                   'sd-taskfolder.ps1',", ''),
        @('a running broker is unregistered without being stopped', 'R12', 'admin', 'Stop-SdTaskBeforeRemoval ''\SD\'' ''sdcore-radmin''', '$true'),
        @('a running job is unregistered without being stopped', 'R12', 'jobs', 'Stop-SdTaskBeforeRemoval $JobTaskPath $t.TaskName', '$true'),
        @('the helper never stops the task', 'R12', 'taskfolder', 'Stop-ScheduledTask -TaskPath $taskPath -TaskName $taskName -ErrorAction Stop', '$null = 0'),
        @('the helper does not wait for the task to end', 'R12', 'taskfolder', '} while ($null -ne $t -and [string]$t.State -eq ''Running'' -and (Get-Date) -lt $deadline)', '} while ($false)'),
        @('a broker task already there is updated in place', 'R10', 'admin', "    try { `$folder.DeleteTask('sdcore-radmin', 0) } catch { }", ''),
        @('a SYSTEM check task already there is updated in place', 'R10', 'admin', "        try { `$sdFolder.DeleteTask('sdcore-radmin-check', 0) } catch { }", ''),
        @('sshd_config is not put back', 'R2', 'admin', "    if (`$why -ne '') { [IO.File]::WriteAllBytes(`$cfg, `$orig) }", ''),
        @('network logon denied', 'R3', 'admin', "'SeDenyBatchLogonRight', 'SeDenyServiceLogonRight')", "'SeDenyBatchLogonRight', 'SeDenyServiceLogonRight', 'SeDenyNetworkLogonRight')"),
        @('SDRADMIN stays in Remote Desktop Users', 'R4', 'admin', "@('S-1-5-32-555', 'Remote Desktop Users'), ", ''),
        @('-Remove takes SDRADMIN out of sdusers', 'R5', 'admin', "        try { Remove-FromGroup (Get-GroupSid 'sdssh') `$userSid 'sdssh' }", "        try { Remove-FromGroup (Get-GroupSid 'sdssh') `$userSid 'sdssh'; Remove-FromGroup (Get-GroupSid 'sdusers') `$userSid 'sdusers' }"),
        @('allow-ssh-groups counts the fence''s DenyUsers', 'G1', 'allow', "        if (`$inOurs -or `$inRadmin) { continue }", "        if (`$inOurs) { continue }")
    )
    $holes = 0
    foreach ($m in $mutants) {
        $mt = @{}
        foreach ($k in @($texts.Keys)) { $mt[$k] = $texts[$k] }
        if (-not $mt[$m[2]].Contains($m[3])) { Write-Output "  [FAIL] selftest: $($m[0])  <- the text to break is not in $($m[2])"; $holes++; continue }
        $mt[$m[2]] = $mt[$m[2]].Replace($m[3], $m[4])
        $failed = @((Get-Rows $mt) | Where-Object { -not $_[1] } | ForEach-Object { ($_[0] -split ' ')[0] } | Sort-Object -Unique)
        $hit = ($failed -contains $m[1])
        Write-Output ("  [{0}] selftest: {1} is caught by {2} (failed: {3})" -f $(if ($hit) { 'PASS' } else { 'FAIL' }), $m[0], $m[1], $(if ($failed.Count) { $failed -join ' ' } else { 'none' }))
        if (-not $hit) { $holes++ }
    }
    foreach ($k in @($files.Keys)) {
        if ([IO.File]::ReadAllText($files[$k]) -cne $texts[$k]) { Write-Output "  [FAIL] selftest: $($files[$k]) changed during the self-test"; $holes++ }
    }
    Write-Output "selftest: $($mutants.Count) mutants, $holes not caught"
    if ($holes -gt 0) { $rc = 1 }
}
exit $rc
