#!/usr/bin/env python3
"""
test-helpbook-units.py - every help record names its PDF as the pdf directory holds it (RELEASE_1.1 268, Linux S.228 b1d496df).

    python sdb_ai/sd64/gplbld/test-helpbook-units.py

Line 2 of each record in sdsys/helptext is the name of the documentation PDF without .pdf: <book>-<chapter>, the book in lower
case (user, administrator, gettingstarted).  mkrelease.ps1 stores each chapter as exactly that name in the pdf folder beside the installer,
and the installer hands that folder to DOCS.INSTALL, so the help box (message 15046 in Core; Solo's Documentation button runs
pdf <line 2>) names a file that is there only if line 2 has the book in front.  This is Linux test-help-units.py's P12, which
Windows never carried: the chapter must be a page of THAT book in the sibling documentation repository (SDCore4WindowsDocs, or
SDCore4WindowsSoloDocs for Solo).

THE MUTANTS RUN ON A COPY IN MEMORY, never on the files: a record with no book, and a record naming a page of another book, must
each be refused, or the check is not a check.  Exit 0 all held, 1 a check failed, 2 there is nothing to check (no helptext, no
documentation repository beside this one): reported NO TREE by check-free-tier.ps1, not a pass.

13 Nov 26 - written for the S.228 carry; the same bytes are in SDCore4Windows and SDCore4WindowsSolo.
"""
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
REPO = os.path.dirname(os.path.dirname(SD64))
SOLO = os.path.isfile(os.path.join(HERE, 'sd-solo.iss'))
DOCS = os.path.join(os.path.dirname(REPO), 'SDCore4WindowsSoloDocs' if SOLO else 'SDCore4WindowsDocs')
HT = os.path.join(SD64, 'sdsys', 'helptext')
BOOKS = {'user': 'User', 'administrator': 'Administrator', 'gettingstarted': 'GettingStarted'}

print('product   :', 'Solo' if SOLO else 'Core')
print('helptext  :', HT)
print('docs      :', DOCS)
if not os.path.isdir(HT) or not os.listdir(HT):
    print('NO TREE: no help records at', HT)
    sys.exit(2)
if not os.path.isdir(DOCS):
    print('NO TREE: no documentation repository at', DOCS)
    sys.exit(2)

pages = {}
for pre, d in BOOKS.items():
    p = os.path.join(DOCS, d, 'markdown')
    pages[pre] = {f[:-3] for f in os.listdir(p) if f.endswith('.md')} if os.path.isdir(p) else set()
print('pages     :', ', '.join('%s %d' % (k, len(v)) for k, v in pages.items()))
if sum(len(v) for v in pages.values()) == 0:
    print('NO TREE: the documentation repository has no markdown pages')
    sys.exit(2)


def problem(line2):
    """None when line 2 names <book>-<page> of that book, else why not"""
    if not line2:
        return None                                  # a record may name no document
    pre, _, chapter = line2.partition('-')
    if pre not in BOOKS:
        return 'does not start with a book (%s)' % ', '.join(BOOKS)
    if chapter not in pages[pre]:
        return 'is not a page of %s' % BOOKS[pre]
    return None


records = {}
for n in sorted(os.listdir(HT)):
    with open(os.path.join(HT, n), 'rb') as f:
        lines = f.read().decode('latin-1').split('\n')
    records[n] = lines[1].strip() if len(lines) > 1 else ''

fails = 0
named = 0
for n, l2 in records.items():
    why = problem(l2)
    if l2:
        named += 1
    if why:
        print('FAIL  %-28s %s %s' % (n, l2, why))
        fails += 1
print('records   : %d, %d name a document' % (len(records), named))
if named == 0:
    print('FAIL  no record names a document: nothing was checked')
    fails += 1

# the controls: a check that cannot fail is not one
some = next(n for n, l2 in records.items() if l2)
book, _, chapter = records[some].partition('-')
other = next(b for b in BOOKS if b != book and chapter not in pages[b])
for label, value in (('no book', chapter), ('another book', other + '-' + chapter)):
    if problem(value) is None:
        print('FAIL  mutant "%s" (%s = %s) was not refused' % (label, some, value))
        fails += 1
    else:
        print('ok    mutant "%s" (%s = %s) refused: %s' % (label, some, value, problem(value)))

print('helpbook: %s' % ('every record names <book>-<page> of that book' if fails == 0 else '%d FAILED' % fails))
sys.exit(1 if fails else 0)
