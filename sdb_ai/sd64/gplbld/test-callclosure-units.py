"""test-callclosure-units.py - every CALL !name and CALL $name in sdsys/gpl.bp has a $CATALOG of that name in sdsys/gpl.bp.

WHY IT EXISTS.  On 10 Nov 2026 HOME in the SDSYS account stopped with
    00001FAA: Unable to load '!sdsysn' object code at line 800 of $tool_home
The TUI carry (f55e5fa5) had brought tool_home and tool_sessions from Linux, and both call !SDSYSN, but not the file
that defines it (Linux 13d30532).  A CALL to a catalogued name is resolved when it runs, so both callers compiled,
the bootstrap reported 0 errors, the cycle completed, and the gap showed only when a person opened the page.  A
compile cannot see this class; a name-to-name match over the source can, and it found two more the same day, both in
Solo (restorea's !create_account, SOLO 52; SED's $seqkey, SOLO 53).

WHAT IT CHECKS.  The names that follow CALL ! and CALL $ in the code of every file in sdsys/gpl.bp (comment lines and
the part of a line after ;* are left out), against the names of every $CATALOG line there (a $CATALOG name with or
without its $ or ! prefix).  A name called and catalogued nowhere is a failure unless KNOWN below lists it with the
row that owns it; a KNOWN name that is now catalogued, or no longer called, is a failure too, so the list cannot rot.

WHAT IT DOES NOT CLAIM.  That a subroutine takes the arguments its callers pass; CALL @var (the name in a variable);
a name catalogued at run time by an installer script.  Only that each name written after CALL ! or CALL $ is
catalogued by some program in this tree.

Free: reads files, no SD, no install, no elevation.  Exit 0 pass, 1 fail, 2 no tree.  --selftest runs its mutants
against a copy in a temporary directory and checks the live tree is byte-identical afterwards.
"""
import hashlib
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GPLBP = os.path.normpath(os.path.join(HERE, '..', 'sdsys', 'gpl.bp'))

# A name called and catalogued nowhere in this tree, while a row is open for it.  Each entry names its row.
KNOWN = {}

CALL = re.compile(r'\bcall\s+([!$])([a-z0-9_.%]+)', re.I)
CAT = re.compile(r'^\s*\$catalog\s+[!$]?([a-z0-9_.%]+)', re.I)
COMMENT_TAIL = re.compile(r';\s*[*!]')


def code_of(line):
    """The code part of a line: '' for a comment line, the text before ;* or ;! otherwise (outside a quoted string)."""
    s = line.lstrip()
    if not s or s[0] in '*!' or s[:4].upper() == 'REM ':
        return ''
    quote = None
    for i, c in enumerate(line):
        if quote:
            if c == quote:
                quote = None
        elif c in '\'"':
            quote = c
        elif c == ';' and COMMENT_TAIL.match(line, i):
            return line[:i]
    return line


def scan(gplbp):
    called = {}        # name -> [(file, line number, prefix)]
    catalogued = set()
    files = 0
    for name in sorted(os.listdir(gplbp)):
        path = os.path.join(gplbp, name)
        if not os.path.isfile(path) or name.startswith('.'):
            continue
        files += 1
        with open(path, 'rb') as f:
            text = f.read().decode('latin-1')
        for n, raw in enumerate(text.splitlines(), 1):
            m = CAT.match(raw)
            if m:
                catalogued.add(m.group(1).lower())
            for m in CALL.finditer(code_of(raw)):
                called.setdefault(m.group(2).lower(), []).append((name, n, m.group(1)))
    return files, called, catalogued


def check(gplbp, known, quiet=False):
    say = (lambda *a: None) if quiet else print
    if not os.path.isdir(gplbp):
        say('test-callclosure-units: NO TREE - %s is not a directory' % gplbp)
        return 2, []
    files, called, catalogued = scan(gplbp)
    say('gpl.bp        : %s' % gplbp)
    say('files read    : %d' % files)
    say('names called  : %d (after CALL ! or CALL $)' % len(called))
    say('catalogued    : %d names' % len(catalogued))
    problems = []
    if files < 50 or not called or not catalogued:
        problems.append('NULL CASE: %d files, %d names called, %d catalogued - that is not a result' % (files, len(called), len(catalogued)))
    for name in sorted(called):
        if name in catalogued:
            continue
        where = ', '.join('%s:%d' % (f, n) for f, n, p in called[name][:4])
        prefix = called[name][0][2]
        if name in known:
            say('known         : %s%s, called at %s - %s' % (prefix, name, where, known[name]))
        else:
            problems.append('NOT CATALOGUED: %s%s is called at %s and no $CATALOG in this tree names it' % (prefix, name, where))
    for name in sorted(known):
        if name in catalogued:
            problems.append('STALE KNOWN: %s is catalogued now - take it off KNOWN' % name)
        elif name not in called:
            problems.append('STALE KNOWN: %s is no longer called - take it off KNOWN' % name)
    for p in problems:
        say('  ' + p)
    return (1 if problems else 0), problems


def tree_hash(d):
    h = hashlib.sha256()
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if os.path.isfile(p):
            h.update(name.encode('utf-8'))
            with open(p, 'rb') as f:
                h.update(f.read())
    return h.hexdigest()


def selftest():
    before = tree_hash(GPLBP)
    print('selftest: live tree %s, sha256 %s' % (GPLBP, before[:16]))
    results = []

    def case(label, mutate, known, want_rc, want_text):
        tmp = tempfile.mkdtemp(prefix='callclosure-')
        try:
            copy = os.path.join(tmp, 'gpl.bp')
            shutil.copytree(GPLBP, copy)
            mutate(copy)
            rc, problems = check(copy, known, quiet=True)
            ok = rc == want_rc and all(any(t in p for p in problems) for t in want_text)
            results.append(ok)
            print('  [%s] %s (exit %d; %s)' % ('PASS' if ok else 'FAIL', label, rc, '; '.join(problems) or 'no problems'))
        finally:
            shutil.rmtree(tmp, ignore_errors=True)

    files, called, catalogued = scan(GPLBP)
    present = sorted(n for n in called if n in catalogued)
    victim = present[0] if present else None
    victim_file = None
    if victim:
        for name in sorted(os.listdir(GPLBP)):
            p = os.path.join(GPLBP, name)
            if os.path.isfile(p):
                with open(p, 'rb') as f:
                    for raw in f.read().decode('latin-1').splitlines():
                        m = CAT.match(raw)
                        if m and m.group(1).lower() == victim:
                            victim_file = name
                            break
            if victim_file:
                break

    def append(copy, text):
        with open(os.path.join(copy, victim_file or sorted(os.listdir(copy))[0]), 'ab') as f:
            f.write(text.encode('latin-1'))

    case('control: the tree as it is passes', lambda c: None, KNOWN, 0, [])
    if victim_file:
        case('M1: remove %s, which catalogues %s: it is reported' % (victim_file, victim),
             lambda c: os.remove(os.path.join(c, victim_file)), KNOWN, 1, ['NOT CATALOGUED', victim])
    else:
        results.append(False)
        print('  [FAIL] M1: found no catalogued name to remove - the selftest cannot run')
    case('M2: a new CALL !zz.no.such.sub is reported', lambda c: append(c, '\n   call !zz.no.such.sub(x)\n'), KNOWN, 1, ['!zz.no.such.sub'])
    case('M3: a new CALL $zz_no_such_local is reported', lambda c: append(c, '\n   call $zz_no_such_local(x)\n'), KNOWN, 1, ['$zz_no_such_local'])
    case('M4: a CALL in a comment line is not', lambda c: append(c, '\n* call !zz.commented(x)\n'), KNOWN, 0, [])
    case('M5: a CALL after ;* is not', lambda c: append(c, '\n   x = 1 ;* call !zz.tail(x)\n'), KNOWN, 0, [])
    case('M6: KNOWN keeps a reported name quiet', lambda c: append(c, '\n   call !zz.owed(x)\n'), dict(KNOWN, **{'zz.owed': 'a test row'}), 0, [])
    if victim:
        case('M7: a KNOWN name that is catalogued is stale', lambda c: None, dict(KNOWN, **{victim: 'a test row'}), 1, ['STALE KNOWN', victim])
    case('M8: a KNOWN name nobody calls is stale', lambda c: None, dict(KNOWN, **{'zz.nobody.calls': 'a test row'}), 1, ['STALE KNOWN', 'zz.nobody.calls'])
    case('M9: an empty tree is refused, not passed', lambda c: [os.remove(os.path.join(c, n)) for n in os.listdir(c)], {}, 1, ['NULL CASE'])

    after = tree_hash(GPLBP)
    same = after == before
    print('selftest: live tree after %s - %s' % (after[:16], 'unchanged' if same else 'CHANGED'))
    passed = sum(results)
    print('selftest: %d of %d cases as expected' % (passed, len(results)))
    return 0 if (same and passed == len(results) and results) else 1


if __name__ == '__main__':
    if '--selftest' in sys.argv[1:]:
        sys.exit(selftest())
    rc, problems = check(GPLBP, KNOWN)
    if rc == 0:
        print('test-callclosure-units: PASSED - every name called after CALL ! or CALL $ is catalogued here%s'
              % (' (%d known, each with its row)' % len(KNOWN) if KNOWN else ''))
    elif rc == 1:
        print('test-callclosure-units: FAILED - %d problem(s)' % len(problems))
    sys.exit(rc)
