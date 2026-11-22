"""test-tkrunwrap-units.py - RELEASE_1.1 380: $tk_run and $tk_runx drop the CR a message's own line break leaves, and keep the lines.

Measured 21 Nov 2026 on VM sit12 (ZZCAP): REMOTE.API OFF NO.RESTART's message 10136 came back as "... takes effect when SD is
next" and "<13>started.", and a page's status line drew the CR as "M".  The cause (the Linux agent, mail 2026-11-22T0530):
messages.c turns a "\n" written in a message into LF and CR, and the capture splits at the LF.  The capture does not wrap.  A first
fix here joined such pieces back into one line, which would have flattened every multi-line message; this guard now holds the
corrected rule: drop the CR, keep every line (Linux S.300 is the template for joining a message whole on a status line).

What this checks, in sdsys/gpl.bp/tk_run and tk_runx (this tree's):
  R1  "gosub drop.cr" comes straight after "status = @system.return.code", which comes after the EXECUTE ... CAPTURING out
  R2  drop.cr is "out = convert(char(13), '', out)" and nothing joins lines (no "jo<jn>", no join.wrapped)
  R3  the logic, run here on the measured sample in Python (a transcription, not the BASIC), keeps four lines and no CR

--selftest breaks a COPY of each file in four ways and requires a red for each; the live files are hashed before and after.
Exit 0 all rows pass, 1 a row failed, 2 the tree is not there.
"""
import hashlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.path.normpath(os.path.join(HERE, '..', 'sdsys', 'gpl.bp'))
FILES = ['tk_run', 'tk_runx']


def check_text(name, text):
    """Returns a list of (row, ok, why)."""
    rows = []
    t = text.replace('\r\n', '\n')
    ex = t.find('execute s trapping aborts capturing out')
    st = t.find('status = @system.return.code', ex if ex >= 0 else 0)
    gs = t.find('gosub drop.cr', st if st >= 0 else 0)
    between = t[st:gs] if (st >= 0 and gs >= 0) else ''
    r1 = ex >= 0 and st > ex and gs > st and between.count('\n') == 1
    rows.append(('R1 %s: gosub drop.cr straight after the capture' % name, r1,
                 'execute@%d status@%d gosub@%d' % (ex, st, gs)))
    m = re.search(r'(?ms)^drop\.cr:\n(.*?)^   return\n', t)
    body = m.group(1) if m else ''
    r2 = (m is not None and body.strip() == "out = convert(char(13), '', out)"
          and 'jo<jn>' not in t and 'join.wrapped' not in t)
    rows.append(('R2 %s: drop.cr only drops the CR, and nothing joins lines' % name, r2,
                 repr(body.strip()) if m else 'no drop.cr block'))
    return rows


def drop_cr(lines):
    """A transcription of drop.cr on a field-mark list."""
    return [ln.replace('\r', '') for ln in lines]


def run(texts):
    rows = []
    for name in FILES:
        rows += check_text(name, texts[name])
    sample = ['Making the change (a few seconds)...', 'The SD API is now OFF.',
              'SD was not restarted. The setting is written and takes effect when SD is next', '\rstarted.']
    got = drop_cr(sample)
    rows.append(('R3 the measured sample keeps its four lines and loses the CR',
                 len(got) == 4 and got[-1] == 'started.' and not any('\r' in g for g in got), repr(got[-1])))
    return rows


def main():
    texts = {}
    for name in FILES:
        p = os.path.join(BP, name)
        if not os.path.isfile(p):
            print('test-tkrunwrap-units: NO TREE - %s is missing' % p)
            return 2
        with open(p, 'rb') as f:
            texts[name] = f.read().decode('latin-1')
    print('test-tkrunwrap-units: reading %s' % ', '.join(os.path.join(BP, n) for n in FILES))

    if '--selftest' in sys.argv:
        before = {n: hashlib.sha256(texts[n].encode('latin-1')).hexdigest() for n in FILES}
        mutants = [
            ('tk_run', 'the gosub removed', '   gosub drop.cr\n', ''),
            ('tk_runx', 'the gosub removed', '   gosub drop.cr\n', ''),
            ('tk_run', 'a CR kept', "out = convert(char(13), '', out)", "out = convert(char(10), '', out)"),
            ('tk_runx', 'lines joined again', "out = convert(char(13), '', out)", "out = convert(char(13), '', out) ; jo<jn> = ''"),
        ]
        bad = 0
        for target, label, old, new in mutants:
            m = dict(texts)
            src = m[target].replace('\r\n', '\n')
            if old not in src:
                print('  MUTANT NOT APPLIED  %s: %s' % (target, label))
                bad += 1
                continue
            m[target] = src.replace(old, new, 1)
            red = [r for r in run(m) if not r[1]]
            print('  %-6s %s: %s' % ('caught' if red else 'MISSED', target, label))
            if not red:
                bad += 1
        after = {n: hashlib.sha256(open(os.path.join(BP, n), 'rb').read()).hexdigest() for n in FILES}
        same = all(before[n] == after[n] for n in FILES)
        print('  live files unchanged: %s' % same)
        print('selftest: %d of %d mutants caught' % (len(mutants) - bad, len(mutants)))
        return 0 if bad == 0 and same else 1

    rows = run(texts)
    nf = 0
    for label, ok, why in rows:
        print('  %s  %s  (%s)' % ('PASS' if ok else 'FAIL', label, why))
        if not ok:
            nf += 1
    print('test-tkrunwrap-units: %d passed, %d failed' % (len(rows) - nf, nf))
    return 1 if nf else 0


if __name__ == '__main__':
    sys.exit(main())
