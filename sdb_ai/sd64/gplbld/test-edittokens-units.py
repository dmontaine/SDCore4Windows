#
# test-edittokens-units.py - prove the mark grammar BEFORE a cycle spends time
# on it.  It models gpl.bp/EDIT's marks.out and marks.back exactly.
#
# THE GRAMMAR.  Every token is "~" plus one character, and "~" is the only
# escape character, so a scan only ever has to look at a tilde:
#
#     ~~   value mark        ~-   a literal "~"
#     ~`   subvalue mark     ~,   a literal "," where one would be a separator
#     ~!   text mark
#
# CONSECUTIVE MARKS ARE SEPARATED BY A COMMA - owner, 27 Aug 2026.  A run of
# marks written token against token cannot be read, so text mark, text mark,
# value mark is "~!,~!,~~".  That is why a literal comma standing between two
# marks has to be escaped: "~~,~~" already means two value marks.
#
# THE TEXT MARK IS "~!" AND NOT "`~", which was the first proposal.  The owner
# withdrew it himself on the ground that it breaks the "every token starts with
# ~" rule, and the rule is load-bearing: a token led by a backtick makes the
# BACKTICK a second escape-introducing character needing its own escape, and
# "~`" and "`~" are anagrams, so a run of marks becomes unreadable.
#
# A LITERAL "~" IS ESCAPED ONLY WHERE THE NEXT CHARACTER WOULD MAKE THE PAIR
# LOOK LIKE A TOKEN.  Escaping every tilde is simpler and shows "~-" wherever
# the author wrote "~", which is the complaint this conversion exists to
# answer.  "a~b" is "a~b" in the editor.
#
import itertools
import os
import sys
import time

VM = '\xfd'
SM = '\xfc'
TM = '\xfb'
BQ = chr(96)

MARKS = {VM: '~', SM: BQ, TM: '!'}     # mark character -> its token letter
LETTER = {'~': VM, BQ: SM, '!': TM}    # and back
TOKENCHARS = ('~', BQ, '!', '-', ',')  # what may follow the escape
DANGER = ('~', BQ, '!', '-', ',', VM, SM, TM)


def out(rec):
    """SD record -> what the editor is given.  Models marks.out."""
    w = []
    prev_mark = False
    n = len(rec)
    for i in range(n):
        c = rec[i]
        nxt = rec[i + 1] if i + 1 < n else ''
        if c in MARKS:
            if prev_mark:
                w.append(',')
            w.append('~' + MARKS[c])
            prev_mark = True
            continue
        if c == ',' and prev_mark and nxt in MARKS:
            w.append('~,')
        elif c == '~' and nxt in DANGER:
            w.append('~-')
        else:
            w.append(c)
        prev_mark = False
    return ''.join(w)


def _starts_mark(w, j):
    return j + 1 < len(w) and w[j] == '~' and w[j + 1] in ('~', BQ, '!')


def back(w):
    """What the editor gives back -> SD record.  Models marks.back."""
    r = []
    prev_mark = False
    i = 0
    n = len(w)
    while i < n:
        c = w[i]
        if c == '~' and i + 1 < n and w[i + 1] in TOKENCHARS:
            t = w[i + 1]
            if t in LETTER:
                r.append(LETTER[t])
                prev_mark = True
            elif t == '-':
                r.append('~')
                prev_mark = False
            else:
                r.append(',')
                prev_mark = False
            i += 2
            continue
        if c == ',' and prev_mark and _starts_mark(w, i + 1):
            i += 1                      # the run separator: not data
            continue
        r.append(c)
        prev_mark = False
        i += 1
    return ''.join(r)


def show(s):
    return s.replace(VM, '<VM>').replace(SM, '<SM>').replace(TM, '<TM>')


# Every case must survive.  Nothing is refused any more, so the table is about
# WHAT THE EDITOR SHOWS - the half a round-trip check cannot see.
CASES = [
    ('plain text',               'HELLO',                    'HELLO'),
    ('two fields',               'A\xfeB',                   'A\xfeB'),
    ('one value mark',           'SMITH' + VM + 'JONES',     'SMITH~~JONES'),
    ('one subvalue mark',        'A' + SM + 'B',             'A~`B'),
    ('one text mark',            'A' + TM + 'B',             'A~!B'),
    ("the owner's own example",  TM + TM + VM,               '~!,~!,~~'),
    ('an empty value',           'A' + VM + VM + 'B',        'A~~,~~B'),
    ('value then text mark',     'A' + VM + TM + 'B',        'A~~,~!B'),
    ('subvalue then text mark',  'A' + SM + TM + 'B',        'A~`,~!B'),
    ('a lone tilde',             'a~b',                      'a~b'),
    ('a lone backtick',          'a' + BQ + 'b',             'a`b'),
    ('a lone bang',              'a!b',                      'a!b'),
    ('a lone comma',             'a,b',                      'a,b'),
    ('"~~" in the data',         'a~~b',                     'a~-~b'),
    ('"~`" in the data',         'a~' + BQ + 'b',            'a~-`b'),
    ('"~!" in the data',         'a~!b',                     'a~-!b'),
    ('"~-" in the data',         'a~-b',                     'a~--b'),
    ('"~," in the data',         'a~,b',                     'a~-,b'),
    ('a tilde before a mark',    'a~' + VM + 'b',            'a~-~~b'),
    ('a comma between marks',    VM + ',' + VM,              '~~~,~~'),
    ('a comma after a mark',     VM + ',a',                  '~~,a'),
    ('a backtick before a mark', BQ + VM,                    '`~~'),
    ("EDIT's own constants",     "'~~'  '~" + BQ + "'",      "'~-~'  '~-`'"),
]

print('test-edittokens: ~~ %s   ~` %s   ~! %s   ~- tilde   ~, comma'
      % (show(VM), show(SM), show(TM)))
print()

bad = 0
for name, rec, expect_seen in CASES:
    seen = out(rec)
    trip = back(seen)
    ok = (trip == rec) and (seen == expect_seen)
    note = ''
    if trip != rec:
        note = '   ROUND TRIP GAVE %s' % show(trip)
    elif seen != expect_seen:
        note = '   EXPECTED THE EDITOR TO SHOW %r' % expect_seen
    if not ok:
        bad += 1
    print('  %s %-26s %-22s editor shows %-14s%s'
          % ('ok  ' if ok else 'FAIL', name, show(rec), show(seen), note))

print()
print('test-edittokens: %d case(s), %d wrong' % (len(CASES), bad))

# ---------------------------------------------------------------------------
# EXHAUSTIVE, over the alphabet that can possibly interact.  'a' stands for
# every character that is not special.  This is the argument; the table above
# is only the illustration.
#
# LENGTH 7 HAS BEEN RUN - 5,380,840 strings, none lost - and takes 13 seconds,
# which is too slow to leave in a test that should be run without thinking
# about it.  Raise MAXLEN by hand when the grammar changes.
# ---------------------------------------------------------------------------
ALPHABET = ('~', BQ, '!', '-', ',', VM, SM, TM, 'a')
MAXLEN = 6

t0 = time.time()
tried = 0
broke = []
for n in range(0, MAXLEN + 1):
    for tup in itertools.product(ALPHABET, repeat=n):
        rec = ''.join(tup)
        tried += 1
        if back(out(rec)) != rec:
            broke.append(rec)

print('test-edittokens: exhaustive over %s up to length %d'
      % (''.join(show(c) for c in ALPHABET), MAXLEN))
print('                 %d string(s) tried, %d not lossless, %.1fs'
      % (tried, len(broke), time.time() - t0))
for rec in broke[:20]:
    print('                 BROKE %-16s -> %-16s -> %s'
          % (show(rec), show(out(rec)), show(back(out(rec)))))
if tried < 100000:
    raise SystemExit('test-edittokens: the exhaustive pass tried almost nothing')

# ---------------------------------------------------------------------------
# AND EVERY SHIPPED BASIC SOURCE RECORD, because the defect that started this
# was a real record in this tree and not a constructed one.  A corpus of zero
# files would sail through, so the counts are asserted.
# ---------------------------------------------------------------------------
here = os.path.dirname(os.path.abspath(__file__))
bp = os.path.join(os.path.dirname(here), 'sdsys', 'gpl.bp')

corpus = 0
with_special = 0
corpus_broke = []
if os.path.isdir(bp):
    for name in sorted(os.listdir(bp)):
        path = os.path.join(bp, name)
        if not os.path.isfile(path):
            continue
        with open(path, 'r', encoding='latin-1', newline='') as f:
            rec = f.read()
        corpus += 1
        if '~' in rec or BQ in rec:
            with_special += 1
        if back(out(rec)) != rec:
            corpus_broke.append(name)

print('test-edittokens: %s' % bp)
print('                 %d source record(s) read, %d contain a tilde or a '
      'backtick, %d not lossless' % (corpus, with_special, len(corpus_broke)))
for name in corpus_broke:
    print('                 BROKE %s' % name)
if corpus == 0:
    raise SystemExit('test-edittokens: read no source records - the corpus proves nothing')
if with_special == 0:
    raise SystemExit('test-edittokens: no record in the corpus contains a tilde or a '
                     'backtick, so it cannot be exercising the escape at all')

if bad or broke or corpus_broke:
    raise SystemExit(1)

# The first version of this file checked that the guard refused SOMETHING, so
# that a check refusing everything could not pass by accident.  There is
# nothing left to refuse.  What replaces it is the assertion above that the
# corpus really does contain the characters under test - a lossless answer
# over records without them would be true and would prove nothing.
print()
print('test-edittokens: every case, every exhaustive string and every shipped '
      'source record survives the round trip.')
