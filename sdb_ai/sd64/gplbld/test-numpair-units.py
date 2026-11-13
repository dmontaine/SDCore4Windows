"""test-numpair-units.py - a number the message renumbering moved is a message id on a line that uses messages, or ALLOWED says why.

WHY IT EXISTS (RELEASE_1.1 258).  Linux message ids are renumbered when a program is carried (11xxx + 1005, 14xxx + 1000; CLAUDE.md),
and the tool that did it changed every number in the id range, not every message id.  sl_put's "CJK radicals to Yi" bound, the character
code 11904, became 12909 in both Windows trees, so characters 11904 to 12908 were measured one column wide here and two on Linux.  11904
is also the id of a Linux message, which is why the renumbering took it.  The 12 Nov Solo parity re-audit (X-01) found it with a scratch
numpair.py; this is that check made a free guard.  test-msgpair-units.py does not see this class: it skips a number Linux has no text for
only when the number is not a Linux message, and it does not ask whether the line uses messages at all.

WHAT IT CHECKS.  For every file in sdsys/gpl.bp, gplsrc and sdsys/syscom that both trees have, the code lines (comments dropped, white
space collapsed, every number 10000-15999 masked) are aligned with difflib; on each line that matches, the numbers are paired in order.
A pair whose two numbers differ fails unless Linux's number is a Linux message AND either the line looks like a message use (sysmsg, msg,
err, message, "stop ", %d) or ALLOWED names the file and the line's shape with a reason that cites its evidence.  An ALLOWED shape that
matches no moved number fails as stale.  Whether our moved id has a message, and whether it says what Linux's says, is
test-msgpair-units.py's check, not this one's.

WHAT IT DOES NOT CLAIM.  Anything about a line that differs from Linux after masking (those are not paired), or that a moved message id is
the right one (test-msgpair-units.py compares the texts).  It reads the Linux clone as it is on disk (carriage returns are dropped), so
pull it first.

The Linux tree is SD_LINUX_SD64 if set, else the LINUX_REPO clone beside this repository; this tree is SD_OURS_SD64 if set (a mutant
copy), else the tree this file is in.  Without a Linux tree it exits 2, NO TREE, as a fresh checkout would.  Free: reads files, no SD, no
install.  --selftest runs its cases on made-up trees in a temporary directory.
"""
import difflib
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OURS = os.environ.get('SD_OURS_SD64') or os.path.normpath(os.path.join(HERE, '..'))
LINUX_REPO = 'SDCore4Linux'
LINUX = os.environ.get('SD_LINUX_SD64') or os.path.normpath(os.path.join(HERE, '..', '..', '..', '..', LINUX_REPO, 'sdb_ai', 'sd64'))

# (file, regex on Linux's masked line, '#' for each masked number): reason.  A moved number on a line of that shape is a message id the
# test above cannot see as one (the id is held in a variable or a table and reaches sysmsg later); Linux's number must still be a message.
# Each reason cites its evidence (a row, a commit, or OS:).  Read 12 Nov 2026 (RELEASE_1.1 258), every line, use by use.
ALLOWED = {
    ('ide', r'^(for j = # to #|if (alone and )?j = # (then|and))'): 'menu ids are message ids, shown by sysmsg(j) (SOLO 65)',
    ('importdata', r'^usage = # ;'): 'usage is shown by display sysmsg(usage) (RELEASE_1.1 258)',
    ('netfile', r'^(fail\.num = #|if cn = # or cn = # then$)'): 'fail.num and cn (err<1,1>) are message ids returned as rc<2> (RELEASE_1.1 258)',
    ('setnetlogin', r'^fail\.num = #'): 'fail.num is a message id returned as rc<2>, as in netfile (RELEASE_1.1 258)',
    ('option', r"^opt<-1> = '[A-Z.]+\|\|#'$"): 'an option\'s third field is its help message id (RELEASE_1.1 258)',
    ('k_error.c', r'^\{#, SE_[A-Z]+ "[A-Z_]+"\},$'): 'the k_error table maps a message id to its SE_ code (RELEASE_1.1 251)',
    ('op_sh.c', r'^return #( \+ kind)?;$'): 'op_sh returns the id of the refusal message its caller shows (RELEASE_1.1 258)',
}

NUM = re.compile(r'\b1[0-5]\d{3}\b')
WS = re.compile(r'\s+')
USE = re.compile(r'(?i)sysmsg|msg|err|message|stop |%d\b')
EVIDENCE = re.compile(r'(RELEASE_1\.1 \d+|SOLO \d+|\b[0-9a-f]{7,8}\b|^OS: )')
SUBDIRS = (('sdsys/gpl.bp', False), ('gplsrc', True), ('sdsys/syscom', False))


def read(path):
    with open(path, 'r', encoding='latin-1', newline='') as f:
        return f.read().replace('\r', '')


def code_lines(path, is_c):
    t = read(path)
    if is_c:
        t = re.sub(r'/\*.*?\*/', '', t, flags=re.S)
    out = []
    for line in t.split('\n'):
        s = line.strip()
        if is_c:
            s = re.sub(r'//.*$', '', s).strip()
        else:
            if not s or s[0] in '*!' or re.match(r'(?i)rem\b', s):
                continue
            s = re.sub(r'\s*;\s*\*.*$', '', s)
        s = WS.sub(' ', s)
        if s:
            out.append(s)
    return out


def message_ids(root):
    d = os.path.join(root, 'sdsys', 'messages')
    return set(n for n in os.listdir(d) if os.path.isfile(os.path.join(d, n)))


def check(ours, linux, allowed, quiet=False):
    say = (lambda *a: None) if quiet else print
    for root, what in ((linux, 'no Linux clone at %s (set SD_LINUX_SD64)'), (ours, '%s has no sdsys/messages')):
        if not os.path.isdir(os.path.join(root, 'sdsys', 'messages')):
            say('test-numpair-units: NO TREE - ' + what % root)
            return 2, []
    lm, om = message_ids(linux), message_ids(ours)
    say('Linux tree    : %s, %d messages' % (linux, len(lm)))
    say('this tree     : %s, %d messages' % (ours, len(om)))
    problems = []
    hits = {}
    nfiles = nlines = npairs = nmoved = 0
    for sub, is_c in SUBDIRS:
        dl, do = os.path.join(linux, *sub.split('/')), os.path.join(ours, *sub.split('/'))
        if not (os.path.isdir(dl) and os.path.isdir(do)):
            continue
        for n in sorted(set(os.listdir(dl)) & set(os.listdir(do))):
            pl, po = os.path.join(dl, n), os.path.join(do, n)
            if not (os.path.isfile(pl) and os.path.isfile(po)):
                continue
            nfiles += 1
            a, b = code_lines(pl, is_c), code_lines(po, is_c)
            am, bm = [NUM.sub('#', x) for x in a], [NUM.sub('#', x) for x in b]
            sm = difflib.SequenceMatcher(None, am, bm, autojunk=False)
            for tag, i1, i2, j1, j2 in sm.get_opcodes():
                if tag != 'equal':
                    continue
                for ln in range(i2 - i1):
                    la_line, lo_line = a[i1 + ln], b[j1 + ln]
                    la, lo = NUM.findall(la_line), NUM.findall(lo_line)
                    if la:
                        nlines += 1
                    for x, y in zip(la, lo):
                        npairs += 1
                        if x == y:
                            continue
                        nmoved += 1
                        use = USE.search(la_line) is not None
                        if x in lm and use:
                            continue                   # a message id; test-msgpair-units.py checks ours exists and says what Linux says
                        shape = [s for s in allowed if s[0] == n and re.search(s[1], am[i1 + ln])]
                        if shape and x in lm:
                            hits[shape[0]] = hits.get(shape[0], 0) + 1
                            continue
                        why = []
                        if x not in lm:
                            why.append('Linux has no message %s' % x)
                        if not use:
                            why.append('the line does not use a message')
                        problems.append('MOVED NUMBER: %s/%s Linux %s, here %s (%s)\n      Linux: %s\n      here : %s' % (
                            sub, n, x, y, '; '.join(why), la_line[:150], lo_line[:150]))
    say('files compared: %d (names in both); matching lines with numbers in range: %d; number pairs: %d, moved: %d' % (
        nfiles, nlines, npairs, nmoved))
    for s in sorted(allowed):
        say('  allowed     : %d moved number(s) in %s on lines like /%s/ - %s' % (hits.get(s, 0), s[0], s[1], allowed[s]))
    if nfiles < 50 or npairs < 100:
        problems.append('NULL CASE: %d files and %d number pairs compared - that is not a result' % (nfiles, npairs))
    for s in sorted(allowed):
        if s not in hits:
            problems.append('STALE: ALLOWED %s /%s/ matches no moved number any more - take it off' % s)
        if not EVIDENCE.search(allowed[s]):
            problems.append('NO EVIDENCE: the reason for %s /%s/ cites no row, commit or OS: - "%s"' % (s + (allowed[s],)))
    for p in problems:
        say('  ' + p)
    return (1 if problems else 0), problems


def selftest():
    results = []
    tmp = tempfile.mkdtemp(prefix='numpair-')
    try:
        def tree(name, prog_ids, msg_ids, literal):
            root = os.path.join(tmp, name)
            for sub, _ in SUBDIRS:
                os.makedirs(os.path.join(root, *sub.split('/')))
            os.makedirs(os.path.join(root, 'sdsys', 'messages'))
            for i in range(60):
                with open(os.path.join(root, 'sdsys', 'gpl.bp', 'p%02d' % i), 'w', newline='\n') as f:
                    for j, mid in enumerate(prog_ids):
                        f.write('   display sysmsg(%s, x%d)   ;* a comment\n' % (mid, j))
                    f.write('   case u8.cp >= %s and u8.cp <= 42191 ; u8.w = 2\n' % literal)
            for mid in msg_ids:
                with open(os.path.join(root, 'sdsys', 'messages', mid), 'w', newline='\n') as f:
                    f.write('text\n')
            return root

        lids = [str(11000 + i) for i in range(3)]
        oids = [str(12005 + i) for i in range(3)]
        linux = tree('linux', lids, lids + ['11904'], '11904')
        gap = tree('linuxgap', lids, lids[:2] + ['11904'], '11904')    # Linux names 11002 and has no message 11002

        def case(label, root, allowed, want_rc, want_text, against=linux):
            rc, problems = check(root, against, allowed, quiet=True)
            ok = rc == want_rc and all(any(t in p for p in problems) for t in want_text)
            results.append(ok)
            print('  [%s] %s (exit %d; %s)' % ('PASS' if ok else 'FAIL', label, rc, '; '.join(p.split('\n')[0] for p in problems[:2]) or 'no problems'))

        ok_tree = tree('ok', oids, oids + ['12909'], '11904')
        case('control: message ids moved on sysmsg lines, the literal unchanged, passes', ok_tree, {}, 0, [])
        case('M1: a literal the renumbering moved fails (the RELEASE_1.1 258 fault, 11904 -> 12909)',
             tree('moved', oids, oids + ['12909'], '12909'), {}, 1, ['MOVED NUMBER', 'the line does not use a message'])
        case('M2: a moved number Linux has no message for fails, even on a sysmsg line', ok_tree, {}, 1, ['Linux has no message 11002'],
             against=gap)
        shape = r'^case u8\.cp >= # and'
        case('control: the moved number allowed by its line shape with a row passes', os.path.join(tmp, 'moved'),
             dict((('p%02d' % i, shape), 'RELEASE_1.1 258') for i in range(60)), 0, [])
        case('M3: an allowed shape that matches no moved number is stale', ok_tree, {('p00', shape): 'RELEASE_1.1 258'}, 1, ['STALE'])
        case('M4: a reason that cites nothing fails', os.path.join(tmp, 'moved'),
             dict((('p%02d' % i, shape), 'because') for i in range(60)), 1, ['NO EVIDENCE'])
        case('M7: an allowed shape does not excuse a number Linux has no message for', ok_tree,
             dict((('p%02d' % i, r'^display sysmsg\(#'), 'RELEASE_1.1 258') for i in range(60)), 1, ['Linux has no message 11002'],
             against=gap)
        case('control: a missing message HERE is left to test-msgpair-units.py', tree('nomsg', oids, oids[:2] + ['12909'], '11904'), {}, 0, [])
        rc, _ = check(ok_tree, os.path.join(tmp, 'nowhere'), {}, quiet=True)
        results.append(rc == 2)
        print('  [%s] M5: no Linux tree is NO TREE (exit 2), not a pass (exit %d)' % ('PASS' if rc == 2 else 'FAIL', rc))
        rc, problems = check(tree('empty', [], [], ''), linux, {}, quiet=True)
        ok = rc == 1 and any('NULL CASE' in p for p in problems)
        results.append(ok)
        print('  [%s] M6: a tree with nothing to pair is refused, not passed (exit %d)' % ('PASS' if ok else 'FAIL', rc))
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    passed = sum(results)
    print('selftest: %d of %d cases as expected' % (passed, len(results)))
    return 0 if passed == len(results) else 1


if __name__ == '__main__':
    if '--selftest' in sys.argv[1:]:
        sys.exit(selftest())
    rc, problems = check(OURS, LINUX, ALLOWED)
    if rc == 0:
        print('test-numpair-units: PASSED - every moved number is a message id on a message line, or ALLOWED says why (%d listed)' % len(ALLOWED))
    elif rc == 1:
        print('test-numpair-units: FAILED - %d problem(s)' % len(problems))
    sys.exit(rc)
