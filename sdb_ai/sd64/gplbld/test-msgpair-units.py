"""test-msgpair-units.py - a message a carried program names says here what it says on Linux, or ALLOWED says why not.

WHY IT EXISTS (RELEASE_1.1 257).  Message ids are renumbered when a Linux program is carried (Linux 11xxx is Windows 11xxx + 1005, 14xxx
+ 1000; CLAUDE.md), so a carry can bring the program and leave the texts behind.  On 12 Nov 2026 SD Core Solo's IDE and CED were Core's
programs while 13 of their messages still held the old IDE's texts: the menu bar offered "Edit in SED" and keys the program did not have
(SOLO 65, a release blocker).  Nothing noticed, because every message file existed; only the TEXT was wrong.  The parity audit's scratch
check that found it pairs ids by code position; this is that check made a free guard.  The same check also found Core's 12642/12948 missing
(row 246).

WHAT IT CHECKS.  For every file in sdsys/gpl.bp and gplsrc that both trees have, the code lines (comments dropped, white space collapsed,
every id 10000-15999 masked) are aligned with difflib; on each line that matches, the ids are paired in order (Linux id, our id).  A pair
fails when our message file is missing, or its text (white space collapsed, lower case) is not Linux's - unless ALLOWED lists the pair with
a reason that cites its evidence (a row, a commit, or OS:).  An ALLOWED pair that is no longer found, or no longer differs, fails as stale.

WHAT IT DOES NOT CLAIM.  That a message a program names on a line that differs from Linux is right (those lines are not paired), or
anything about a program Linux does not have.  It reads the Linux clone as it is on disk (carriage returns are dropped), so pull it first.

The Linux tree is SD_LINUX_SD64 if set, else the LINUX_REPO clone beside this repository.  Without one it exits 2, NO TREE, as a fresh
checkout would.  Free: reads files, no SD, no install.  --selftest runs its cases on made-up trees in a temporary directory.
"""
import difflib
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
OURS = os.path.normpath(os.path.join(HERE, '..'))
LINUX_REPO = 'SDCore4Linux'
LINUX = os.environ.get('SD_LINUX_SD64') or os.path.normpath(os.path.join(HERE, '..', '..', '..', '..', LINUX_REPO, 'sdb_ai', 'sd64'))

# (Linux id, our id): reason.  Each reason cites its evidence.  Read 12 Nov 2026 (RELEASE_1.1 257), text against text.
# 13 Nov 2026 (RELEASE_1.1 253(b)): 11447/12452 and 11448/12453 left this list - run.in debugs on Windows too, so the texts are Linux's.
ALLOWED = {
    ('10002', '10002'): 'OS: Linux enters SDSYS as the sdsys OS user; on Windows by a Windows sign-in as SDSYS (RELEASE_1.1 64)',
    ('10024', '10024'): 'OS: a Windows group, not a Linux group',
    ('10003', '10051'): 'OS: two different refusals that sit on the same LOGIN line; ours names LOGTO (RELEASE_1.1 64)',
    ('10084', '10084'): 'OS: the Windows account, not a Linux user',
    ('10114', '10087'): 'OS: modifya is the Windows program; different messages line up on a matching line (group account, no remote access)',
    ('10114', '10104'): 'OS: modifya is the Windows program; the OS-access change has its own refusal here',
    ('10105', '10105'): 'OS: a Windows user, not a Linux user',
    ('10909', '10122'): 'OS: create_account sets a Windows password, then SD\'s credential; different failures on a matching line',
    ('10130', '10130'): 'OS: the Windows account and its removal, not a Linux user',
    ('10133', '10133'): 'OS: api-listener.ps1 and its statuses, not the root helper',
    ('10139', '10139'): 'OS: the Windows firewall rule and its statuses, not ufw',
    ('10137', '10140'): 'OS: Windows has a "no ssh server" answer (exit 2) where Linux shows the syntax; different messages on a matching line',
    ('10158', '10158'): 'OS: the same words, wrapped at another place (RELEASE_1.1 128)',
    ('10910', '10920'): 'OS: create_account checks the password rule itself (pw_complex) where Linux reports PAM\'s refusal',
    ('11904', '11904'): 'sl_put\'s 11904 is a character code (CJK radicals), not a message id; Linux has the same literal (RELEASE_1.1 258)',
    ('11010', '12007'): 'OS: a Windows account SD made is reused with a new password; Linux keeps the Linux password',
    ('11332', '12337'): 'OS: the job helper is a Task Scheduler script, not a root helper (RELEASE_1.1 222)',
    ('11458', '12463'): 'OS: a Windows user, not a Linux user',
    ('11462', '12467'): 'OS: a Windows login, not a Linux login',
    ('11936', '12941'): 'OS: SD is a Windows service (sd -restart, Stop-Service / Start-Service) (RELEASE_1.1 218)',
    ('11983', '12988'): 'OS: Windows has no sdsys group; SDSYS reaches every account by ACL, and the upgrade updates every account (CLAUDE.md, S.103)',
    ('11930', '12935'): 'OS: a Windows file\'s rights are its access list, not chmod modes; the cure names the principals win32gcat.c judges (RELEASE_1.1 249)',
}

MSG = re.compile(r'\b1[0-5]\d{3}\b')
WS = re.compile(r'\s+')
EVIDENCE = re.compile(r'(RELEASE_1\.1 \d+|SOLO \d+|\b[0-9a-f]{7,8}\b|^OS: )')
SUBDIRS = (('sdsys/gpl.bp', False), ('gplsrc', True))


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


def messages(root):
    d = os.path.join(root, 'sdsys', 'messages')
    m = {}
    for n in os.listdir(d):
        p = os.path.join(d, n)
        if os.path.isfile(p):
            m[n] = WS.sub(' ', read(p).strip().lower())
    return m


def pairs_of(linux, ours):
    pairs = {}
    nfiles = 0
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
            am, bm = [MSG.sub('#', x) for x in a], [MSG.sub('#', x) for x in b]
            sm = difflib.SequenceMatcher(None, am, bm, autojunk=False)
            for tag, i1, i2, j1, j2 in sm.get_opcodes():
                if tag != 'equal':
                    continue
                for k in range(i2 - i1):
                    la, lo = MSG.findall(a[i1 + k]), MSG.findall(b[j1 + k])
                    if len(la) == len(lo):
                        for x, y in zip(la, lo):
                            pairs.setdefault((x, y), set()).add(n)
    return pairs, nfiles


def check(ours, linux, allowed, quiet=False):
    say = (lambda *a: None) if quiet else print
    for root, what in ((linux, 'no Linux clone at %s (set SD_LINUX_SD64)'), (ours, '%s has no sdsys/messages')):
        if not os.path.isdir(os.path.join(root, 'sdsys', 'messages')):
            say('test-msgpair-units: NO TREE - ' + what % root)
            return 2, []
    lm, om = messages(linux), messages(ours)
    pairs, nfiles = pairs_of(linux, ours)
    say('Linux tree    : %s, %d messages' % (linux, len(lm)))
    say('this tree     : %s, %d messages' % (ours, len(om)))
    say('files compared: %d (gpl.bp and gplsrc names in both); id pairs on matching lines: %d' % (nfiles, len(pairs)))
    problems = []
    if nfiles < 50 or len(pairs) < 100:
        problems.append('NULL CASE: %d files and %d pairs compared - that is not a result' % (nfiles, len(pairs)))
    seen = set()
    nbad = 0
    for (x, y), files in sorted(pairs.items(), key=lambda kv: (int(kv[0][1]), int(kv[0][0]))):
        if x not in lm:
            continue                                   # an id Linux has no text for is a number, not a message
        where = ','.join(sorted(files))
        if y not in om:
            fault = 'MISSING: our %s (Linux %s) is named in %s and has no message file here; Linux says "%s"' % (y, x, where, lm[x][:100])
        elif lm[x] != om[y]:
            fault = 'TEXT DIFFERS: our %s (Linux %s) in %s\n      Linux: %s\n      here : %s' % (y, x, where, lm[x][:160], om[y][:160])
        else:
            continue
        nbad += 1
        if (x, y) in allowed:
            seen.add((x, y))
            say('  allowed     : %s / %s in %s - %s' % (x, y, where, allowed[(x, y)]))
        else:
            problems.append(fault)
    for k in sorted(allowed):
        if k not in seen:
            problems.append('STALE: ALLOWED %s / %s is not a differing pair any more - take it off' % k)
        if not EVIDENCE.search(allowed[k]):
            problems.append('NO EVIDENCE: the reason for %s / %s cites no row, commit or OS: - "%s"' % (k[0], k[1], allowed[k]))
    say('differing or missing pairs: %d, of which ALLOWED gives a reason for %d' % (nbad, len(seen)))
    for p in problems:
        say('  ' + p)
    return (1 if problems else 0), problems


def selftest():
    results = []
    tmp = tempfile.mkdtemp(prefix='msgpair-')
    try:
        def tree(name, prog_ids, texts):
            root = os.path.join(tmp, name)
            for sub, _ in SUBDIRS:
                os.makedirs(os.path.join(root, *sub.split('/')))
            os.makedirs(os.path.join(root, 'sdsys', 'messages'))
            for i in range(60):
                with open(os.path.join(root, 'sdsys', 'gpl.bp', 'p%02d' % i), 'w', newline='\n') as f:
                    for j, mid in enumerate(prog_ids):
                        f.write('   display sysmsg(%s, x%d)   ;* a comment\n' % (mid, j))
            for mid, t in texts.items():
                with open(os.path.join(root, 'sdsys', 'messages', mid), 'w', newline='\n') as f:
                    f.write(t + '\n')
            return root

        lids = [str(11000 + i) for i in range(4)]
        oids = [str(12005 + i) for i in range(4)]
        ltext = dict((m, 'text %s' % k) for k, m in enumerate(lids))
        good = dict((m, 'text %s' % k) for k, m in enumerate(oids))
        linux = tree('linux', lids, ltext)

        def case(label, root, allowed, want_rc, want_text):
            rc, problems = check(root, linux, allowed, quiet=True)
            ok = rc == want_rc and all(any(t in p for p in problems) for t in want_text)
            results.append(ok)
            print('  [%s] %s (exit %d; %s)' % ('PASS' if ok else 'FAIL', label, rc, '; '.join(p.split('\n')[0] for p in problems[:2]) or 'no problems'))

        # pairs: 4 ids x 60 files give 4 distinct pairs, so lower the NULL CASE floor for the made-up tree by giving it many ids
        many_l = [str(11000 + i) for i in range(120)]
        many_o = [str(12005 + i) for i in range(120)]
        linux = tree('linux2', many_l, dict((m, 'text %s' % k) for k, m in enumerate(many_l)))
        ok_tree = tree('ok', many_o, dict((m, 'text %s' % k) for k, m in enumerate(many_o)))
        case('control: every paired text equal passes', ok_tree, {}, 0, [])
        bad = dict((m, 'text %s' % k) for k, m in enumerate(many_o))
        bad['12010'] = 'the old IDE text'
        case('M1: a paired text that differs fails (the SOLO 65 fault)', tree('bad', many_o, bad), {}, 1, ['TEXT DIFFERS', '12010'])
        miss = dict((m, 'text %s' % k) for k, m in enumerate(many_o))
        del miss['12011']
        case('M2: a paired message with no file here fails', tree('miss', many_o, miss), {}, 1, ['MISSING', '12011'])
        case('control: the differing pair allowed with a row passes', os.path.join(tmp, 'bad'), {('11005', '12010'): 'product wording: SOLO 1'}, 0, [])
        case('M3: an allowed pair that no longer differs is stale', ok_tree, {('11005', '12010'): 'SOLO 1'}, 1, ['STALE'])
        case('M4: a reason that cites nothing fails', os.path.join(tmp, 'bad'), {('11005', '12010'): 'because'}, 1, ['NO EVIDENCE'])
        rc, _ = check(ok_tree, os.path.join(tmp, 'nowhere'), {}, quiet=True)
        results.append(rc == 2)
        print('  [%s] M5: no Linux tree is NO TREE (exit 2), not a pass (exit %d)' % ('PASS' if rc == 2 else 'FAIL', rc))
        empty = tree('empty', [], {})
        rc, problems = check(empty, linux, {}, quiet=True)
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
        print('test-msgpair-units: PASSED - every paired message says what Linux says, or ALLOWED says why (%d listed)' % len(ALLOWED))
    elif rc == 1:
        print('test-msgpair-units: FAILED - %d problem(s)' % len(problems))
    sys.exit(rc)
