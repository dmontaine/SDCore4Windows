"""test-tkrunwrap-units.py - RELEASE_1.1 380: $tk_run and $tk_runx join a line the capture wrapped.

Measured 21 Nov 2026 on VM sit12 (ZZCAP): EXECUTE ... CAPTURING on Windows wraps a long line, and the piece after the wrap
starts with a CR (byte 13).  REMOTE.API OFF NO.RESTART's message 10136 came back as "... takes effect when SD is next" and
"<13>started.", and every page that shows the command's last line showed "Mstarted.".

What this checks, in sdsys/gpl.bp/tk_run and tk_runx (this tree's):
  R1  "gosub join.wrapped" comes straight after "status = @system.return.code", which comes after the EXECUTE ... CAPTURING out
  R2  join.wrapped exists, joins a piece whose first character is char(13) to the line before WITH A SPACE, drops other CRs,
      and puts the result back in out
  R3  the logic, run here on the measured sample in Python (a transcription of join.wrapped, not the BASIC itself), gives
      the whole message on one line

--selftest breaks a COPY of each file in five ways and requires a red for each; the live files are hashed before and after.
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
    gs = t.find('gosub join.wrapped', st if st >= 0 else 0)
    between = t[st:gs] if (st >= 0 and gs >= 0) else ''
    r1 = ex >= 0 and st > ex and gs > st and between.count('\n') == 1
    rows.append(('R1 %s: gosub join.wrapped straight after the capture' % name, r1,
                 'execute@%d status@%d gosub@%d' % (ex, st, gs)))
    m = re.search(r'(?ms)^join\.wrapped:\n(.*?)^   return\n', t)
    body = m.group(1) if m else ''
    r2 = (m is not None
          and "if jl[1, 1] = char(13) and jn > 0 then" in body
          and "jo<jn> = jo<jn> : ' ' : convert(char(13), '', jl)" in body
          and "jo<jn> = convert(char(13), '', jl)" in body
          and "out = jo" in body)
    rows.append(('R2 %s: join.wrapped joins a CR piece with a space, drops other CRs, returns out' % name, r2,
                 'block found' if m else 'no join.wrapped block'))
    return rows


def join_wrapped(lines):
    """A transcription of join.wrapped."""
    jo = []
    for jl in lines:
        if jl[:1] == '\r' and jo:
            jo[-1] = jo[-1] + ' ' + jl.replace('\r', '')
        else:
            jo.append(jl.replace('\r', ''))
    return jo


def run(texts):
    rows = []
    for name in FILES:
        rows += check_text(name, texts[name])
    sample = ['Making the change (a few seconds)...', 'The SD API is now OFF.',
              'SD was not restarted. The setting is written and takes effect when SD is next', '\rstarted.']
    got = join_wrapped(sample)
    want = 'SD was not restarted. The setting is written and takes effect when SD is next started.'
    rows.append(('R3 the measured sample comes back whole', len(got) == 3 and got[-1] == want, repr(got[-1])))
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
            ('tk_run', 'the gosub removed', '   gosub join.wrapped\n', ''),
            ('tk_runx', 'the gosub removed', '   gosub join.wrapped\n', ''),
            ('tk_run', 'joined without the space', "jo<jn> : ' ' : convert", 'jo<jn> : convert'),
            ('tk_run', 'a CR piece not recognised', 'if jl[1, 1] = char(13) and jn > 0 then', 'if jl[1, 1] = char(10) and jn > 0 then'),
            ('tk_runx', 'the result not put back', '   out = jo\n', ''),
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
