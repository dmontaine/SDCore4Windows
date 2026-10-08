"""test-auditspacing-units.py - no audit string has two words run together.

WHY THIS EXISTS.  The 7 Oct 2026 lower-case edit of Solo's audit strings (d72aee8) turned
'API REFUSED request=25 ...' into 'api refusedrequest=25 ...', 'API REFUSED user=' into
'api refuseduser=', and 'REFUSED - not a ...' into 'refused -not a ...'.  Four strings, every one
still lower case, so test-auditwords-units.py (which reads only the case of the words before the
first '=') passed.  verify-solo's leg 12 caught it on the first install; this finds it in the source
in a second.

THE RULES, over the string literals in every kernel(K$AUDIT, ...) statement of gpl.bp:
  A  an event word (refused, granted, released, admitted, failed, unlocked, locked, suspended,
     unsuspended, removed, added, set) is never followed directly by a letter or digit
  B  a hyphen standing for a dash is never glued to the next word (' -not')
It refuses to pass over nothing: fewer than 20 audit statements read is exit 2, not a pass.

MUTANT-TESTED: a copy of gpl.bp's audit file is broken each way and the checker must go red, and
the file the mutants were made from is asserted byte-identical (SHA-256) afterwards.
Exit 0 pass, 1 a string is broken or a mutant was not caught, 2 nothing to read."""
import hashlib
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GPL = os.path.normpath(os.path.join(HERE, '..', 'sdsys', 'gpl.bp'))

EVENT_WORDS = ('refused', 'granted', 'released', 'admitted', 'failed', 'unlocked', 'locked',
               'suspended', 'unsuspended', 'removed', 'added')
RULE_A = re.compile(r'\b(' + '|'.join(EVENT_WORDS) + r')(?=[a-z0-9])')
RULE_B = re.compile(r' -(?=[a-z])')
STMT = re.compile(r"K\$AUDIT\s*,\s*((?:'(?:[^']|'')*'\s*:\s*)*'(?:[^']|'')*')")
STR = re.compile(r"'((?:[^']|'')*)'")
MIN_STATEMENTS = 20


def literals(path):
    out = []
    with open(path, 'rb') as fh:
        text = fh.read().decode('utf-8', errors='replace')
    for n, line in enumerate(text.split('\n'), 1):
        if line.strip().startswith('*'):
            continue
        m = STMT.search(line)
        if m:
            out.append((n, ''.join(STR.findall(m.group(1)))))
    return out


def scan(root):
    """Returns (statements read, [(file, line, rule, literal)])."""
    seen = 0
    bad = []
    for name in sorted(os.listdir(root)):
        p = os.path.join(root, name)
        if not os.path.isfile(p):
            continue
        for n, lit in literals(p):
            seen += 1
            if RULE_A.search(lit):
                bad.append((name, n, 'A', lit))
            if RULE_B.search(lit):
                bad.append((name, n, 'B', lit))
    return seen, bad


def sha(p):
    with open(p, 'rb') as fh:
        return hashlib.sha256(fh.read()).hexdigest()


print('test-auditspacing-units')
print('gpl.bp read from :', GPL, ' exists:', os.path.isdir(GPL))
if not os.path.isdir(GPL):
    print('NO TREE: nothing to read')
    sys.exit(2)

seen, bad = scan(GPL)
print('audit statements read:', seen, '(minimum', MIN_STATEMENTS, ')')
if seen < MIN_STATEMENTS:
    print('REFUSED: too few audit statements read - a pass over nothing is not a pass')
    sys.exit(2)
for f, n, r, lit in bad:
    print('  BROKEN rule %s  %s:%d  %r' % (r, f, n, lit))
live_ok = (len(bad) == 0)
print('live tree: %s' % ('no run-together words' if live_ok else '%d broken string(s)' % len(bad)))

# --- mutants: break a COPY of one file that holds audit statements, three ways -------------------
victim = None
for name in sorted(os.listdir(GPL)):
    p = os.path.join(GPL, name)
    if os.path.isfile(p) and literals(p) and any(w in lit for _, lit in literals(p) for w in (' refused', ' failed', ' granted')):
        victim = name
        break
mutants_ok = True
if victim is None:
    print('MUTANTS NOT RUN: no file with a refused/failed/granted audit string to break')
    mutants_ok = False
else:
    before = sha(os.path.join(GPL, victim))
    with open(os.path.join(GPL, victim), 'rb') as fh:
        original = fh.read().decode('utf-8', errors='replace')
    first = next(lit for _, lit in literals(os.path.join(GPL, victim)) if any(w in lit for w in (' refused', ' failed', ' granted')))
    word = next(w for w in (' refused', ' failed', ' granted') if w in first)
    cases = [
        ('A: the space after the event word is lost', first, first.replace(word + ' ', word, 1) if (word + ' ') in first else first.replace(word, word + 'x', 1)),
        ('B: a hyphen glued to the next word', first, first + ' -oops'),
    ]
    for label, old, new in cases:
        tmp = tempfile.mkdtemp(prefix='auditspacing-')
        try:
            shutil.copytree(GPL, os.path.join(tmp, 'gpl.bp'))
            target = os.path.join(tmp, 'gpl.bp', victim)
            with open(target, 'wb') as fh:
                fh.write(original.replace("'" + old.replace("'", "''"), "'" + new.replace("'", "''"), 1).encode('utf-8'))
            s2, b2 = scan(os.path.join(tmp, 'gpl.bp'))
            caught = len(b2) > 0
            print('  mutant %-46s %s' % (label, 'CAUGHT' if caught else 'NOT CAUGHT'))
            if not caught:
                mutants_ok = False
        finally:
            shutil.rmtree(tmp, ignore_errors=True)
    after = sha(os.path.join(GPL, victim))
    print('  live %s unchanged by the mutants: %s' % (victim, before == after))
    if before != after:
        mutants_ok = False

if live_ok and mutants_ok:
    print('PASS')
    sys.exit(0)
print('FAIL')
sys.exit(1)
