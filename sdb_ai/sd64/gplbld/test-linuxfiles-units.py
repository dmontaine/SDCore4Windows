"""test-linuxfiles-units.py - every BASIC source file Linux has is here too, or listed below with the reason it is not.

WHY IT EXISTS.  Linux is the template (CLAUDE.md, the core direction), and a Linux change reaches this tree by a carry
that someone picks the files for.  On 10 Nov 2026 HOME in SDSYS stopped with "Unable to load '!sdsysn' object code":
the TUI carry (f55e5fa5) took tool_home and tool_sessions and not _sdsysn, which came from an earlier Linux commit
(13d30532).  A comparison of file NAMES between the two gpl.bp directories showed 15 Linux files with no file here, and
_sdsysn was the only one the record gave no reason for.  The same comparison found three more with no decision
anywhere (LOCK.TRACER, SET.MODE, tool.remote: RELEASE_1.1 228), whose carried suites are NotRun, so nothing had
noticed.  A content diff is no use for this: every shared file differs, by its Windows history and adaptations.

WHAT IT CHECKS.  The file names of the Linux tree's sdsys/gpl.bp against this tree's.  A Linux file with no file of the
same name here fails unless NOT_HERE lists it; each NOT_HERE reason must cite its evidence (a row, a commit, or OS:);
a NOT_HERE name that is now here, or that Linux no longer has, fails as stale.

WHAT IT DOES NOT CLAIM.  That a file of the same name has Linux's changes (it says nothing about content), or anything
about files outside gpl.bp.  It reads the Linux clone as it is on disk, so pull it first.

The Linux tree is SD_LINUX_GPLBP if set, else the SDCore4Linux clone beside this repository.  Without one it exits
2, NO TREE, as a fresh checkout would.  Free: reads directory listings, no SD, no install.  --selftest runs its cases
on made-up trees in a temporary directory.
"""
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OURS = os.path.normpath(os.path.join(HERE, '..', 'sdsys', 'gpl.bp'))
LINUX_REPO = 'SDCore4Linux'
LINUX = os.environ.get('SD_LINUX_GPLBP') or os.path.normpath(
    os.path.join(HERE, '..', '..', '..', '..', LINUX_REPO, 'sdb_ai', 'sd64', 'sdsys', 'gpl.bp'))

NOT_HERE = {   # 13 Nov 26: ai, setai and tool_ai are carried (RELEASE_1.1 246) and left this list
    'audit_read':       'tool.audit (Linux S.75 A5) is not carried yet: RELEASE_1.1 247',
    'tool_audit':       'tool.audit (Linux S.75 A5) is not carried yet: RELEASE_1.1 247',
    'define_install.h': 'removed here as dead code with the PRE_RELEASE 168 chain (aafca0bb)',
    'euid_restore':     'OS: Linux\'s sudo identity switch (seteuid); a Windows process has no effective user id',
    'euid_set':         'OS: Linux\'s sudo identity switch (seteuid); a Windows process has no effective user id',
    'setmode':          'OS: SET.MODE (Linux 3b435253) sets POSIX permission bits; Windows files have ACLs, not mode bits (agreed with Linux, mail 2026-11-11T0630)',
    'peer_local':       'removed here with the administrator predicate (RELEASE_1.1 64, fdded05a)',
}

EVIDENCE = re.compile(r'(RELEASE_1\.1 \d+|SOLO \d+|\b[0-9a-f]{7,8}\b|^OS: )')


def names(d):
    return set(n for n in os.listdir(d) if os.path.isfile(os.path.join(d, n)) and not n.startswith('.'))


def check(ours, linux, not_here, quiet=False):
    say = (lambda *a: None) if quiet else print
    if not os.path.isdir(linux):
        say('test-linuxfiles-units: NO TREE - no Linux clone at %s (set SD_LINUX_GPLBP)' % linux)
        return 2, []
    if not os.path.isdir(ours):
        say('test-linuxfiles-units: NO TREE - %s is not a directory' % ours)
        return 2, []
    lin, us = names(linux), names(ours)
    missing = sorted(lin - us)
    say('Linux gpl.bp  : %s, %d files' % (linux, len(lin)))
    say('this gpl.bp   : %s, %d files' % (ours, len(us)))
    say('Linux only    : %d, of which NOT_HERE gives a reason for %d' % (len(missing), len([n for n in missing if n in not_here])))
    problems = []
    if len(lin) < 50 or len(us) < 50:
        problems.append('NULL CASE: %d Linux files, %d here - that is not a result' % (len(lin), len(us)))
    for n in missing:
        if n in not_here:
            say('  not here    : %-18s %s' % (n, not_here[n]))
        else:
            problems.append('NOT CARRIED, NO REASON: Linux has %s and this tree does not; carry it, or list it in NOT_HERE with its row' % n)
    for n in sorted(not_here):
        if n in us:
            problems.append('STALE: %s is here now - take it off NOT_HERE' % n)
        elif n not in lin:
            problems.append('STALE: Linux no longer has %s - take it off NOT_HERE' % n)
        if not EVIDENCE.search(not_here[n]):
            problems.append('NO EVIDENCE: the reason for %s cites no row, commit or OS: - "%s"' % (n, not_here[n]))
    for p in problems:
        say('  ' + p)
    return (1 if problems else 0), problems


def selftest():
    results = []
    tmp = tempfile.mkdtemp(prefix='linuxfiles-')
    try:
        lin = os.path.join(tmp, 'linux')
        us = os.path.join(tmp, 'ours')
        os.mkdir(lin)
        os.mkdir(us)
        for i in range(60):
            for d in (lin, us):
                open(os.path.join(d, 'f%02d' % i), 'w').close()
        open(os.path.join(lin, 'only_linux'), 'w').close()
        open(os.path.join(lin, '.gitattributes'), 'w').close()

        def case(label, not_here, want_rc, want_text, ours=us, linux=lin):
            rc, problems = check(ours, linux, not_here, quiet=True)
            ok = rc == want_rc and all(any(t in p for p in problems) for t in want_text)
            results.append(ok)
            shown = '; '.join(problems[:2]) + ('; and %d more' % (len(problems) - 2) if len(problems) > 2 else '')
            print('  [%s] %s (exit %d; %s)' % ('PASS' if ok else 'FAIL', label, rc, shown or 'no problems'))

        case('M1: a Linux file with no file here and no reason fails', {}, 1, ['NOT CARRIED, NO REASON', 'only_linux'])
        case('control: the same file listed with a row passes', {'only_linux': 'owed: RELEASE_1.1 1'}, 0, [])
        case('M2: a reason that cites nothing fails', {'only_linux': 'because'}, 1, ['NO EVIDENCE', 'only_linux'])
        case('M3: a listed name that is here now is stale', {'only_linux': 'RELEASE_1.1 1', 'f01': 'RELEASE_1.1 1'}, 1, ['STALE', 'f01'])
        case('M4: a listed name Linux no longer has is stale', {'only_linux': 'RELEASE_1.1 1', 'gone': 'RELEASE_1.1 1'}, 1, ['STALE', 'gone'])
        case('M5: OS: and a commit hash count as evidence', {'only_linux': 'OS: no such thing (0123abcd)'}, 0, [])
        case('M6: no Linux tree is NO TREE (exit 2), not a pass', {}, 2, [], linux=os.path.join(tmp, 'nowhere'))
        empty = os.path.join(tmp, 'empty')
        os.mkdir(empty)
        case('M7: an empty tree is refused, not passed', {'only_linux': 'RELEASE_1.1 1'}, 1, ['NULL CASE'], ours=empty)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    passed = sum(results)
    print('selftest: %d of %d cases as expected' % (passed, len(results)))
    return 0 if passed == len(results) else 1


if __name__ == '__main__':
    if '--selftest' in sys.argv[1:]:
        sys.exit(selftest())
    rc, problems = check(OURS, LINUX, NOT_HERE)
    if rc == 0:
        print('test-linuxfiles-units: PASSED - every Linux gpl.bp file is here, or NOT_HERE says why (%d listed)' % len(NOT_HERE))
    elif rc == 1:
        print('test-linuxfiles-units: FAILED - %d problem(s)' % len(problems))
    sys.exit(rc)
