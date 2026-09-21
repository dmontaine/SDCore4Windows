#
# test-verifieranchors-units.py - a verifier must not anchor on product wording that
# the product no longer prints.
#
# command line: python3 gplbld/test-verifieranchors-units.py
# Exits 0 if every check passes, 1 otherwise.  Reads files only; needs no build, no
# install, no elevation, no SD.
#
# 21 Sep 2026, RELEASE_1.1 76.  The first seat run of verify-apiadmin and
# verify-privundetermined failed at "credential set" although the product had said
# "Password accepted." - SET_ACC_PASSWORD's success line was reworded that same day
# (it used to be "Password set for account X") and EIGHT verifiers still matched the
# old wording.  test-retired-wording-units.ps1 cannot catch this: it scans SHIPPED text
# and skips test-* and verify-* on purpose, because it holds every retired phrase as a
# literal itself.  So nothing looked at the one place that consumes product wording as
# an ANCHOR, and a stale anchor does not fail loudly - it reports the product broken.
#
# HOW TO USE IT: when you reword a line a verifier matches on, add a row to RETIRED
# below in the SAME commit - the old phrase, the new one, and the product file that must
# print the new one.  This fails while any verify-*.ps1 still carries the old phrase
# outside a comment, or the product source no longer prints the new one.
#
# INSTRUMENT RULES (CLAUDE.md): it echoes the corpus and the phrases; it refuses the
# null case (too few verifiers, a replacement the product does not print, or no
# verifier carrying the replacement anchor at all); and it has a canary - the scanner
# must flag a synthetic file carrying the old phrase and must not flag one without it -
# so "0 stale anchors" cannot come from a dead scan.

import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)

# (retired phrase, live phrase, product file that must print the live phrase, why)
RETIRED = [
    ('Password set for account', 'Password accepted.',
     os.path.join(SD64, 'sdsys', 'gpl.bp', 'set_acc_password'),
     'SET_ACC_PASSWORD success line, reworded 21 Sep 2026'),
]

MIN_VERIFIERS = 40

fails = []


def check(name, cond, detail=''):
    if cond:
        print('  PASS  %s' % name)
    else:
        print('  FAIL  %s  %s' % (name, detail))
        fails.append(name)


def code_lines(text):
    """The non-comment lines of a PowerShell file: a line whose first non-blank
    character is # is documentation and may quote the retired wording."""
    return [l for l in text.splitlines() if not re.match(r'^\s*#', l)]


def stale_hits(text, phrase):
    low = phrase.lower()
    return [i for i, l in enumerate(text.splitlines(), 1)
            if not re.match(r'^\s*#', l) and low in l.lower()]


def product_prints(path, phrase):
    """True if a non-comment BASIC line of the product source contains the phrase.
    BASIC comments start with * in column 1 (or after blanks)."""
    with open(path, encoding='latin-1') as f:
        for l in f.read().splitlines():
            if re.match(r'^\s*\*', l):
                continue
            if phrase in l:
                return True
    return False


def main():
    files = sorted(glob.glob(os.path.join(HERE, 'verify-*.ps1')))
    print('test-verifieranchors-units: %d verify-*.ps1 file(s) under %s' % (len(files), HERE))
    check('the corpus is not empty (a scan of nothing passes every row below)',
          len(files) >= MIN_VERIFIERS, 'found %d, expected at least %d' % (len(files), MIN_VERIFIERS))

    texts = {}
    for p in files:
        with open(p, encoding='utf-8', errors='replace') as f:
            texts[p] = f.read()

    # THE CANARY: the scanner must see a planted phrase and must not invent one.
    planted = 'x\n# a comment naming Password set for account\n$set = ($o -match \'Password set for account\')\n'
    clean = 'x\n# nothing here\n$set = ($o -match \'Password accepted\\.\')\n'
    check('CANARY: a planted code line is flagged, a comment is not',
          stale_hits(planted, 'Password set for account') == [3])
    check('CANARY: a file without the phrase is not flagged',
          stale_hits(clean, 'Password set for account') == [])

    for old, new, product, why in RETIRED:
        print('retired: "%s"  ->  "%s"   (%s)' % (old, new, why))
        check('the product source exists: %s' % os.path.relpath(product, SD64),
              os.path.isfile(product), 'missing')
        if not os.path.isfile(product):
            continue
        check('the product still prints the replacement "%s"' % new,
              product_prints(product, new),
              'not found on a non-comment line of %s - the verifiers now anchor on wording nobody prints'
              % os.path.relpath(product, SD64))
        stale = {os.path.basename(p): stale_hits(t, old) for p, t in texts.items()}
        stale = {k: v for k, v in stale.items() if v}
        check('no verify-*.ps1 anchors on the retired phrase "%s"' % old,
              not stale, 'still in: %s' % ', '.join('%s:%s' % (k, v) for k, v in sorted(stale.items())))
        live = [os.path.basename(p) for p, t in texts.items()
                if re.search(re.escape(new.rstrip('.')), '\n'.join(code_lines(t)))]
        check('the replacement anchor is in use (null case: a scan that cannot see it proves nothing)',
              len(live) >= 1, 'no verifier carries "%s"' % new)
        print('    verifiers carrying the replacement: %d (%s)' % (len(live), ', '.join(sorted(live))))

    print('')
    print('%d check(s) failed' % len(fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
