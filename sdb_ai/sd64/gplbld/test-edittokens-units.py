#
# test-edittokens-units.py - prove the mark-token round trip BEFORE a cycle
# spends time on it.
#
# gpl.bp/EDIT converts @vm <-> "~~" and @sm <-> "~`" so that a Windows editor
# can show a multivalued record.  27 Aug 2026 it also escapes a literal "~"
# that would otherwise be read back as one of those tokens, because THE
# CONVERSION HAS TO BE LOSSLESS RATHER THAN REFUSABLE - owner, 27 Aug 2026,
# after micro refused gpl.bp/EDIT itself:
#
#     This record cannot be edited with micro.
#     Its text and the ~~ and ~` marks cannot be told apart...
#
# EDIT was the ONE source record in the whole shipped tree its own guard
# refused, and it refused it because it contains the token strings as data.
#
# THE SCHEME.  "~" is the escape character.  Going out, left to right:
#
#     @vm                     ->  ~~
#     @sm                     ->  ~`
#     ~  followed by one of   ->  ~-      ("dangerous": ~ ` - @vm @sm)
#     ~  followed by anything ->  ~       (left alone, so ordinary text
#                                          keeps its tildes readable)
#
# Coming back, three change() calls IN THIS ORDER:
#
#     ~~  -> @vm  ,  ~` -> @sm  ,  ~- -> ~
#
# ORDER MATTERS BOTH WAYS AND IT IS NOT ARBITRARY.
#   * "~~" must be decoded before "~`", or "~~`" - a value mark followed by a
#     backtick - is read as a tilde followed by a subvalue mark.
#   * "~-" must be decoded LAST, or an escaped tilde in front of a mark is
#     unescaped before the mark is recognised.
#   * "-" has to be in the dangerous set even though it is not a token by
#     itself: without it, a literal "~-" in the data would decode to "~".
#
# change() replaces left to right without overlapping, which is what Python's
# str.replace does, so the algorithm can be exercised here exactly as SD will
# run it.
#
import itertools
import os
import sys

VM = '\xfd'
SM = '\xfc'
VT = '~~'
ST = '~' + chr(96)
ET = '~-'

DANGEROUS = ('~', chr(96), '-', VM, SM)


def out(rec):
    """SD record -> what the editor is given."""
    w = []
    n = len(rec)
    for i in range(n):
        c = rec[i]
        if c == '~':
            nxt = rec[i + 1] if i + 1 < n else ''
            w.append(ET if nxt in DANGEROUS else '~')
        else:
            w.append(c)
    s = ''.join(w)
    s = s.replace(VM, VT)
    s = s.replace(SM, ST)
    return s


def back(w):
    """What the editor gives back -> SD record."""
    r = w.replace(VT, VM)
    r = r.replace(ST, SM)
    r = r.replace(ET, '~')
    return r


def lossless(rec):
    return back(out(rec)) == rec


def show(s):
    return s.replace(VM, '<VM>').replace(SM, '<SM>')


# The table is now about what the EDITOR SEES, not about what is refused:
# every one of these must survive, including the four that used to be turned
# away.
CASES = [
    ('plain text',                  'HELLO',                       'HELLO'),
    ('two fields',                  'LINE1\xfeLINE2',              'LINE1\xfeLINE2'),
    ('one multivalue',              'SMITH' + VM + 'JONES',        'SMITH~~JONES'),
    ('three values',                'A' + VM + 'B' + VM + 'C',     'A~~B~~C'),
    ('one subvalue',                'A' + SM + 'B',                'A~`B'),
    ('values and subvalues',        'A' + VM + 'B' + SM + 'C',     'A~~B~`C'),
    ('empty value',                 'A' + VM + VM + 'B',           'A~~~~B'),
    ('a lone tilde in data',        'a~b',                         'a~b'),
    ('a lone backtick in data',     'a' + chr(96) + 'b',           'a`b'),
    ('tilde NOT next to a mark',    'a~b' + VM + 'c',              'a~b~~c'),
    # --- the four that USED to be refused -----------------------------
    ('"~~" already in the data',    'a~~b',                        'a~-~b'),
    ('"~`" already in the data',    'a~' + chr(96) + 'b',          'a~-`b'),
    ('tilde immediately before VM', 'a~' + VM + 'b',               'a~-~~b'),
    ('tilde immediately before SM', 'a~' + SM + 'b',               'a~-~`b'),
    # --- and the ones the escape itself makes possible -----------------
    ('"~-" already in the data',    'a~-b',                        'a~--b'),
    ('three tildes',                'a~~~b',                       'a~-~-~b'),
    ('EDIT\'s own two constants',   "'~~'  '~" + chr(96) + "'",    "'~-~'  '~-`'"),
]

print('test-edittokens: VM=%r SM=%r  vm=%r sm=%r esc=%r' % (VM, SM, VT, ST, ET))
print()

bad = 0
for name, rec, expect_seen in CASES:
    seen = out(rec)
    ok = lossless(rec)
    why = ''
    if not ok:
        why = '   ROUND TRIP GAVE %r' % show(back(seen))
    elif seen != expect_seen:
        ok = False
        why = '   EXPECTED THE EDITOR TO SEE %r' % expect_seen
    if not ok:
        bad += 1
    print('  %s %-30s %-24s editor sees %-14s%s'
          % ('ok  ' if ok else 'FAIL', name, show(rec), show(seen), why))

print()
print('test-edittokens: %d case(s), %d wrong' % (len(CASES), bad))

# ---------------------------------------------------------------------------
# EXHAUSTIVE, over the alphabet that can possibly interact.  Every string the
# scheme could get wrong is built out of these six characters; 'a' stands for
# every character that is not special.  Six to the sixth is 46,656 strings and
# it takes under a second, which is a better argument than any table.
# ---------------------------------------------------------------------------
ALPHABET = ('~', chr(96), '-', VM, SM, 'a')
MAXLEN = 6

tried = 0
broke = []
for n in range(0, MAXLEN + 1):
    for tup in itertools.product(ALPHABET, repeat=n):
        rec = ''.join(tup)
        tried += 1
        if not lossless(rec):
            broke.append(rec)

print('test-edittokens: exhaustive over %r up to length %d' % (''.join(ALPHABET), MAXLEN))
print('                 %d string(s) tried, %d not lossless' % (tried, len(broke)))
for rec in broke[:20]:
    print('                 BROKE %-14s -> %-14s -> %s'
          % (show(rec), show(out(rec)), show(back(out(rec)))))
if tried < 1000:
    raise SystemExit('test-edittokens: the exhaustive pass tried almost nothing')

# ---------------------------------------------------------------------------
# AND EVERY SHIPPED BASIC SOURCE RECORD, because the defect that started this
# was a real record in this tree and not a constructed one.  A corpus of zero
# files would sail through, so the count is asserted.
# ---------------------------------------------------------------------------
here = os.path.dirname(os.path.abspath(__file__))
bp = os.path.join(os.path.dirname(here), 'sdsys', 'gpl.bp')

corpus = 0
with_tilde = 0
corpus_broke = []
if os.path.isdir(bp):
    for name in sorted(os.listdir(bp)):
        path = os.path.join(bp, name)
        if not os.path.isfile(path):
            continue
        with open(path, 'r', encoding='latin-1', newline='') as f:
            rec = f.read()
        corpus += 1
        if '~' in rec:
            with_tilde += 1
        if not lossless(rec):
            corpus_broke.append(name)

print('test-edittokens: %s' % bp)
print('                 %d source record(s) read, %d contain a tilde, %d not lossless'
      % (corpus, with_tilde, len(corpus_broke)))
for name in corpus_broke:
    print('                 BROKE %s' % name)
if corpus == 0:
    raise SystemExit('test-edittokens: read no source records - the corpus proves nothing')
if with_tilde == 0:
    raise SystemExit('test-edittokens: no record in the corpus contains a tilde, so it '
                     'cannot be exercising the escape at all')

if bad or broke or corpus_broke:
    raise SystemExit(1)

# The old version of this file checked that the guard refused SOMETHING, so a
# check that refused everything could not pass by accident.  There is nothing
# left to refuse: the point of the change is that every record survives.  What
# replaces it is the assertion above that the corpus really does contain
# tildes - a lossless answer over records with no tilde in them would be true
# and would prove nothing.
print()
print('test-edittokens: every case, every exhaustive string and every shipped '
      'source record survives the round trip.')
