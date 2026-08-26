#
# checksyntax.py - validate a micro syntax file without micro and without a
# YAML library.
#
#   python checksyntax.py sdbasic.yaml
#
# TWO FAULTS, AND NEITHER SHOWS UP AS AN ERROR ANYWHERE.  micro reports a
# syntax file it cannot parse by simply not highlighting, which looks exactly
# like a file that did not match the filename.
#
#   1. AN ILLEGAL YAML ESCAPE.  Inside a double-quoted scalar, YAML allows
#      only a fixed set of escapes.  "\." is not one of them - a regex written
#      the way you would write it in Python makes the FILE invalid, not just
#      the pattern.  Every backslash a regex needs has to be doubled, which is
#      why micro's own c.yaml reads "\\.".
#   2. A PATTERN THAT DOES NOT COMPILE.  micro uses Go's RE2, which has no
#      lookahead or backreferences; Python's engine is a superset for
#      everything used here, so a pattern Python rejects RE2 would reject too.
#      The reverse is not true, so this also flags lookahead by name.
#
import re
import sys

P = sys.argv[1]

with open(P, 'r', encoding='utf-8', newline='') as f:
    lines = f.read().split('\n')

# YAML's double-quoted escapes.  Anything else after a backslash is an error.
LEGAL = set('0abtnvfre"/\\N_LP xuU\t')

SCALAR = re.compile(r':\s*"((?:[^"\\]|\\.)*)"\s*$')

bad = 0
checked = 0
for i, line in enumerate(lines, 1):
    s = line.strip()
    if s.startswith('#') or not s:
        continue
    m = SCALAR.search(s)
    if not m:
        continue
    raw = m.group(1)
    checked += 1

    j = 0
    while j < len(raw):
        if raw[j] == '\\':
            if j + 1 >= len(raw) or raw[j + 1] not in LEGAL:
                nxt = raw[j + 1] if j + 1 < len(raw) else '<end>'
                print('  BAD YAML ESCAPE  line %d: "\\%s" is not a YAML escape'
                      % (i, nxt))
                bad += 1
                break
            j += 2
        else:
            j += 1

    # YAML unescaping, for the two that appear here.
    pattern = raw.replace('\\\\', '\x00').replace('\\"', '"').replace('\x00', '\\')

    if '(?=' in pattern or '(?!' in pattern or '(?<' in pattern:
        print('  RE2 CANNOT DO IT  line %d: lookaround in %s'
              % (i, pattern[:60]))
        bad += 1
        continue
    try:
        re.compile(pattern)
    except re.error as e:
        print('  WILL NOT COMPILE  line %d: %s   in %s' % (i, e, pattern[:60]))
        bad += 1

print('checksyntax: %s' % P)
print('checksyntax: %d quoted pattern(s) checked, %d bad' % (checked, bad))
if checked == 0:
    sys.exit('checksyntax: no patterns found at all - refusing to report a pass')
sys.exit(1 if bad else 0)
