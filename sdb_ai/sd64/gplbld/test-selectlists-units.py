#!/usr/bin/env python3
"""test-selectlists-units.py - no gpl.bp program uses a select list number SD
refuses at run time.  RELEASE_1.1 5 D2, 14 Sep 2026.

    python sdb_ai/sd64/gplbld/test-selectlists-units.py

Exit 0 clean, 1 a program uses a list number out of range, 2 measured nothing.
NO INSTALL, NO ELEVATION, NO RUN TOKEN - a free-tier guard.

WHY THIS EXISTS.  UPGRADE_NOCASE used select lists 13, 14 and 15.  SD allows
0 to HIGH_SELECT (12), and 11-12 only in an $internal program
(gplsrc/sd.h:43-48).  It compiled clean, because the number is only checked
when the statement runs, and on its first measuring run the walk stopped with
1118 "Select list number out of range" - before converting a single file, on
the upgrade path that nothing else exercises.  So the compiler cannot catch
this class and a cycle does not reach it; reading the tree can.

WHAT IT READS.  The two limits come from gplsrc/sd.h, not from this file.  In
every record of sdsys/gpl.bp, after stripping comments and quoted strings, it
finds a LITERAL list number in SELECT-family statements (TO n), READNEXT /
READLIST / READPREV (FROM n), CLEARSELECT n and SELECTINFO(n, ...).  A list
number held in a variable is not seen - said here so a green run is not read
as covering it.

CONTROLS: the fixtures below must each be decided as marked, and the tree scan
must find list numbers at all (a scan that matched nothing would pass).
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
SD_H = os.path.join(SD64, 'gplsrc', 'sd.h')
GPLBP = os.path.join(SD64, 'sdsys', 'gpl.bp')

LIST_USE = [
    re.compile(r'\b(?:select|sselect|selectv|selectn|selecte|selectindex|selectleft|selectright|formlist)\b[^\n]*?\bto\s+(\d+)\b', re.I),
    re.compile(r'\b(?:readnext|readlist|readprev)\b[^\n]*?\bfrom\s+(\d+)\b', re.I),
    re.compile(r'\bclearselect\s+(\d+)\b', re.I),
    re.compile(r'\bselectinfo\s*\(\s*(\d+)\s*,', re.I),
]
INTERNAL = re.compile(r'^\s*\$internal\b', re.I | re.M)


def read_limits(path):
    text = open(path, encoding='latin-1').read()
    hi = re.search(r'#define\s+HIGH_SELECT\s+(\d+)', text)
    hu = re.search(r'#define\s+HIGH_USER_SELECT\s+(\d+)', text)
    if not hi or not hu:
        return None, None
    return int(hi.group(1)), int(hu.group(1))


def strip_line(line):
    """Drop a comment line, a trailing ;* comment and quoted strings."""
    s = line.lstrip()
    if s.startswith('*') or s.startswith('!') or s.upper().startswith('REM '):
        return ''
    line = re.sub(r"'[^']*'|\"[^\"]*\"|\\[^\\]*\\", "''", line)
    cut = line.find(';*')
    if cut >= 0:
        line = line[:cut]
    return line


def violations(text, hi, hu):
    """Return (uses, [(lineno, number, reason)]) for one program's source."""
    internal = bool(INTERNAL.search(text))
    uses = 0
    bad = []
    for n, raw in enumerate(text.splitlines(), 1):
        line = strip_line(raw)
        if not line.strip():
            continue
        for rx in LIST_USE:
            for m in rx.finditer(line):
                uses += 1
                num = int(m.group(1))
                if num > hi:
                    bad.append((n, num, 'above HIGH_SELECT %d' % hi))
                elif num > hu and not internal:
                    bad.append((n, num, 'above HIGH_USER_SELECT %d in a program that is not $internal' % hu))
    return uses, bad


def main():
    fails = 0
    passes = 0

    def row(name, ok, detail=''):
        nonlocal fails, passes
        if ok:
            passes += 1
            print('  [PASS] ' + name)
        else:
            fails += 1
            print('  [FAIL] ' + name + ('  ->  ' + detail if detail else ''))

    print('sd.h   : ' + SD_H)
    print('gpl.bp : ' + GPLBP)
    hi, hu = read_limits(SD_H)
    print('limits : HIGH_SELECT=%s HIGH_USER_SELECT=%s' % (hi, hu))
    if hi is None or not os.path.isdir(GPLBP):
        print('COULD NOT RUN - the limits or gpl.bp were not found')
        return 2

    # ---- fixtures: the decision itself -----------------------------------
    fx = [
        ('internal, list 13 (the UPGRADE_NOCASE defect)', '$internal\n   select f to 13\n', 1),
        ('internal, readnext from 15', '$internal\n   readnext id from 15 else exit\n', 1),
        ('NOT internal, list 11', '   select f to 11\n', 1),
        ('internal, lists 11 and 12', '$internal\n   select f to 11\n   readnext x from 12 else exit\n', 0),
        ('not internal, list 10', '   sselect f to 10\n   readlist l from 10 else null\n', 0),
        ('a comment line naming list 99', '* select f to 99\n   select f to 1\n', 0),
        ('a trailing ;* comment naming list 99', '   select f to 1 ;* not select g to 99\n', 0),
        ('a quoted string naming list 99', "   crt 'select f to 99'\n   select f to 2\n", 0),
        ('clearselect and selectinfo above the limit', '$internal\n   clearselect 14\n   x = selectinfo(13, 1)\n', 2),
    ]
    for name, text, want in fx:
        _, bad = violations(text, hi, hu)
        row('fixture: %s -> %d violation(s)' % (name, want), len(bad) == want, 'got %d: %s' % (len(bad), bad))

    # ---- the tree ---------------------------------------------------------
    total_uses = 0
    files = 0
    found = []
    for name in sorted(os.listdir(GPLBP)):
        path = os.path.join(GPLBP, name)
        if not os.path.isfile(path):
            continue
        files += 1
        uses, bad = violations(open(path, encoding='latin-1').read(), hi, hu)
        total_uses += uses
        for (ln, num, why) in bad:
            found.append('%s:%d list %d %s' % (name, ln, num, why))
    print('tree   : %d records, %d literal list uses' % (files, total_uses))
    row('CONTROL: the tree scan found list uses to judge (40 or more)', total_uses >= 40, '%d' % total_uses)
    row('no gpl.bp program uses a select list number SD refuses', not found, '; '.join(found))
    for f in found:
        print('         ' + f)

    print('test-selectlists-units: %d passed, %d failed' % (passes, fails))
    if passes + fails == 0:
        return 2
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
