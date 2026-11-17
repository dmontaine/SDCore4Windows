"""test-sshpin-units.py - both verify runners pin ssh to Windows OpenSSH (RELEASE_1.1 333).

WHAT IT PROTECTS.  The verifiers call bare ssh.  Suite b338 (16 Nov 2026) was started from Git Bash, whose PATH found Git's MSYS
ssh.exe first: UserKnownHostsFile=NUL wrote a file gplbld\\NUL and the ssh steps measured the wrong client.  VerifyInstall1.ps1 and
VerifyInstall2.ps1 now put %SystemRoot%\\System32\\OpenSSH first on their own PATH, say which ssh they found, and refuse a run whose ssh
is anything else, BEFORE the first step.  This guard reads both runners and fails if any of that goes missing or moves below the
first step.

Rows, for each runner:
  P1 the PATH is prefixed with the OpenSSH folder (from SystemRoot, not a typed drive)
  P2 ssh is resolved after the prefix, and the result is printed
  P3 a different (or no) ssh is refused with exit 2
  P4 all of it comes before the runner's first SD check (IS SD ACTUALLY RUNNING), so nothing is spent first

--selftest runs mutants on copies (the live files are hashed before and after and must not change).
Exit 0 every row passed, 1 a row failed, 2 a runner could not be read.
"""
import hashlib
import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
RUNNERS = ['VerifyInstall1.ps1', 'VerifyInstall2.ps1']


def check(text, name, say):
    bad = 0
    m_prefix = re.search(r"\$openSshExe = Join-Path \$env:SystemRoot 'System32\\OpenSSH\\ssh\.exe'\s*\r?\n"
                         r"\$env:PATH = \(Split-Path -Parent \$openSshExe\) \+ ';' \+ \$env:PATH", text)
    m_resolve = re.search(r"\$sshNow = \(Get-Command ssh -CommandType Application[^\n]*\r?\nWrite-Output \('[A-Za-z0-9]+: ssh is ' \+ \$sshNow\)",
                          text)
    m_refuse = re.search(r"if \(\(-not \$sshNow\) -or \(\$sshNow -ne \$openSshExe\)\) \{[^}]*REFUSING[^}]*exit 2\s*\}", text)
    m_first = text.find('IS SD ACTUALLY RUNNING')
    rows = [
        ('P1 %s: PATH starts with the OpenSSH folder from SystemRoot' % name, m_prefix is not None),
        ('P2 %s: ssh is resolved after it and printed' % name, m_resolve is not None and (m_prefix is None or m_resolve.start() > m_prefix.start())),
        ('P3 %s: any other ssh is refused with exit 2' % name, m_refuse is not None),
        ('P4 %s: before the first SD check' % name, m_refuse is not None and m_first > 0 and m_refuse.end() < m_first),
    ]
    for label, ok in rows:
        say('  [%s] %s' % ('PASS' if ok else 'FAIL', label))
        if not ok:
            bad += 1
    return bad


def run(texts, say):
    bad = 0
    for name in RUNNERS:
        bad += check(texts[name], name, say)
    return bad


def read_live():
    texts = {}
    for name in RUNNERS:
        p = os.path.join(HERE, name)
        with open(p, encoding='utf-8-sig') as fh:
            texts[name] = fh.read()
    return texts


def selftest(texts):
    mutants = [
        ('no PATH prefix', 'VerifyInstall1.ps1', "$env:PATH = (Split-Path -Parent $openSshExe) + ';' + $env:PATH", "$env:PATH = $env:PATH"),
        ('no print', 'VerifyInstall2.ps1', "Write-Output ('VerifyInstall2: ssh is ' + $sshNow)", "$null = $sshNow"),
        ('no refusal', 'VerifyInstall1.ps1', 'exit 2\n}\n\n# ---------------------------------------------------------------------------\n# 22 Aug 26 - IS SD',
         '}\n\n# ---------------------------------------------------------------------------\n# 22 Aug 26 - IS SD'),
        ('compare dropped', 'VerifyInstall2.ps1', "-or ($sshNow -ne $openSshExe)", ""),
    ]
    caught = 0
    for label, name, old, new in mutants:
        t = dict(texts)
        src = t[name].replace('\r\n', '\n')
        if old not in src:
            print('  [FAIL] mutant "%s": its text is not in %s (update the mutant)' % (label, name))
            continue
        t[name] = src.replace(old, new, 1)
        b = run(t, lambda s: None)
        print('  [%s] mutant "%s" is caught (%d row(s) red)' % ('PASS' if b else 'FAIL', label, b))
        if b:
            caught += 1
    return caught, len(mutants)


def main():
    try:
        before = {n: hashlib.sha256(open(os.path.join(HERE, n), 'rb').read()).hexdigest() for n in RUNNERS}
        texts = read_live()
    except OSError as e:
        print('test-sshpin: cannot read a runner: %s' % e)
        return 2
    print('test-sshpin: the runners in %s' % HERE)
    bad = run(texts, print)
    if '--selftest' in sys.argv:
        caught, n = selftest(texts)
        after = {n2: hashlib.sha256(open(os.path.join(HERE, n2), 'rb').read()).hexdigest() for n2 in RUNNERS}
        print('  [%s] the live runners are unchanged by the self-test' % ('PASS' if before == after else 'FAIL'))
        if caught != n or before != after:
            bad += 1
        print('mutants caught: %d of %d' % (caught, n))
    print('checks failed: %d' % bad)
    return 1 if bad else 0


sys.exit(main())
