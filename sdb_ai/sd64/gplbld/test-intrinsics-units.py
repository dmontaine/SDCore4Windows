#
# test-intrinsics-units.py - unit test for BCOMP's two positional intrinsic
#                            lists, plus a live check of the real file.
#
# command line: python3 gplbld/test-intrinsics-units.py
# Exits 0 if every check passes, 1 otherwise.  Reads two files and writes
# nothing.  Needs no build, no install, no elevation and no run token, so it is
# in neither post-cycle runner.
#
# WHY THIS EXISTS.  gpl.bp/bcomp registers each intrinsic in int.intrinsics and
# dispatches it through an "on i goto" list MATCHED BY POSITION.  The two lists
# are kept in step by hand.  Adding or removing a name from one and not the
# other MISROUTES EVERY INTRINSIC AFTER IT - and that fault compiles cleanly and
# produces wrong code, so nothing downstream reports it.  The 13 Aug 2026 commit
# that removed embedded Python said so in its own message, and left a comment in
# BCOMP saying so, because a comment was the only guard available.  This is the
# guard.
#
# ***THE LIVE CHECK IS THE POINT AND THE FIXTURES ARE WHAT MAKE IT TRUSTWORTHY.***
# A checker that only reads the real file is green on the day it is written and
# has never been shown to go red, which is the vacuous pass section 0 forbids.
# The fixtures drive each way the lists can disagree - including the two that
# bit a real session, below - so the live rows mean something.
#
# TWO THINGS LOOK LIKE FAULTS AND ARE NOT.  Both were measured on 12 Sep 2026,
# and both made the first version of this checker report a false MISALIGNED:
#
#   * THE FIRST REGISTRATION INITIALISES THE LIST.  It is
#     'int.intrinsics = "ABORT.CAUSE"' with no <-1>, and the rest append.  A
#     pattern that requires <-1> drops it and then reports every later position
#     as off by one - 38 names against 39, all of them "wrong".
#   * ONE DISPATCH COMMENT IS SPELLED WITHOUT ITS DOT.  EXPAND.HF is registered
#     and the dispatch entry is commented ';* EXPANDHF'.  The dispatch comments
#     are labels, not names - alignment is positional - so this is cosmetic and
#     is reported as such rather than as a misalignment.
#

import os
import re
import sys

# Resolved from THIS FILE, never from the working directory.  The free tier is
# run from wherever the caller happens to be, and a cwd-relative path turns
# "run it from gplbld" into a failure that reads like a real misalignment.
HERE = os.path.dirname(os.path.abspath(__file__))
BCOMP = os.path.normpath(
    os.path.join(HERE, '..', 'sdsys', 'gpl.bp', 'BCOMP'))


def read_registrations(lines):
    """The int.intrinsics names, in file order, with their line numbers."""
    names = []
    where = []
    for n, line in enumerate(lines, 1):
        m = re.search(r'int\.intrinsics(?:<-1>)?\s*=\s*"([^"]+)"', line)
        if m:
            names.append(m.group(1))
            where.append(n)
    return names, where


def read_dispatch(lines):
    """The "on i goto" labels, in file order, with their line numbers.

    The block starts at the "on i goto" whose first entry is commented
    ABORT.CAUSE - BCOMP has a second, unrelated "on i goto" for the function
    table - and ends at the first entry with no trailing comma."""
    start = None
    for n, line in enumerate(lines):
        if 'on i goto' in line and 'ABORT.CAUSE' in line:
            start = n
            break
    if start is None:
        return None, None

    names = []
    where = []
    for n in range(start, len(lines)):
        line = lines[n]
        m = re.search(r';\*\s*([A-Z0-9._]+)\s*$', line.rstrip())
        if m:
            names.append(m.group(1))
            where.append(n + 1)
        code = line.split(';*')[0].rstrip()
        if code and not code.endswith(',') and names:
            break
    return names, where


def norm(s):
    return s.replace('.', '')


def compare(reg, dis):
    """Returns (problems, cosmetic).  Empty problems means aligned."""
    problems = []
    cosmetic = []
    if len(reg) != len(dis):
        problems.append('length: %d registrations vs %d dispatch entries'
                        % (len(reg), len(dis)))
    for i in range(min(len(reg), len(dis))):
        if norm(reg[i]) != norm(dis[i]):
            problems.append('position %d: registered %s, dispatched %s'
                            % (i + 1, reg[i], dis[i]))
        elif reg[i] != dis[i]:
            cosmetic.append('position %d: %s / %s' % (i + 1, reg[i], dis[i]))
    ndis = [norm(x) for x in dis]
    nreg = [norm(x) for x in reg]
    for x in reg:
        if norm(x) not in ndis:
            problems.append('registered but never dispatched: %s' % x)
    for x in dis:
        if norm(x) not in nreg:
            problems.append('dispatched but never registered: %s' % x)
    return problems, cosmetic


# --- fixtures --------------------------------------------------------------
# Small stand-ins with the same SHAPE as BCOMP: an initialising registration,
# appending ones, and an "on i goto" whose last entry has no comma.

def build(reg_names, dis_names):
    out = []
    for i, name in enumerate(reg_names):
        op = '<-1>' if i else ''
        out.append('   int.intrinsics%s = "%s"    ; int.intrinsic.opcodes%s = OP.%s'
                   % (op, name, op, norm(name)))
    out.append('')
    for i, name in enumerate(dis_names):
        lead = '         on i goto ' if i == 0 else '                    '
        comma = ',' if i < len(dis_names) - 1 else ' '
        out.append('%sin.none%s      ;* %s' % (lead, comma, name))
    return out


ALIGNED = ['ABORT.CAUSE', 'AKMAP', 'SDEXT', 'SDPYOBJ', 'SORTDATA']


def main():
    fails = []
    ran = []
    print('test-intrinsics-units: BCOMP at %s' % BCOMP)
    print('checks:')

    # The tally is COUNTED, not written down.  A hardcoded total disagreed with
    # the rows this actually ran the first time it was executed - 9 claimed
    # against 10 run - which is the whole complaint section 0 makes about an
    # instrument reporting something other than what it did.
    def row(ok, label, detail=''):
        ran.append(label)
        print('  [%s] %s%s' % ('PASS' if ok else 'FAIL', label,
                               ('  - ' + detail) if detail else ''))
        if not ok:
            fails.append(label)

    # 1. the aligned fixture is aligned, and the extractors find everything
    lines = build(ALIGNED, ALIGNED)
    reg, _ = read_registrations(lines)
    dis, _ = read_dispatch(lines)
    row(reg == ALIGNED, 'fixture: every registration is read, initialiser included',
        'read %s' % reg)
    row(dis == ALIGNED, 'fixture: every dispatch entry is read', 'read %s' % dis)
    problems, cosmetic = compare(reg, dis)
    row(not problems, 'fixture: an aligned pair reports no problem',
        '; '.join(problems))

    # 2. the documented failure mode: dropped from the dispatch list only
    lines = build(ALIGNED, [x for x in ALIGNED if x != 'SDPYOBJ'])
    reg, _ = read_registrations(lines)
    dis, _ = read_dispatch(lines)
    problems, _ = compare(reg, dis)
    row(any('SDPYOBJ' in p for p in problems),
        'MUTANT: dropping the dispatch entry is caught and names it',
        '; '.join(problems[:2]))

    # 3. the mirror image: dropped from the registrations only
    lines = build([x for x in ALIGNED if x != 'SDPYOBJ'], ALIGNED)
    reg, _ = read_registrations(lines)
    dis, _ = read_dispatch(lines)
    problems, _ = compare(reg, dis)
    row(any('SDPYOBJ' in p for p in problems),
        'MUTANT: dropping the registration is caught and names it',
        '; '.join(problems[:2]))

    # 4. same names, wrong order - the case a membership check cannot see
    swapped = ['ABORT.CAUSE', 'AKMAP', 'SDPYOBJ', 'SDEXT', 'SORTDATA']
    lines = build(ALIGNED, swapped)
    reg, _ = read_registrations(lines)
    dis, _ = read_dispatch(lines)
    problems, _ = compare(reg, dis)
    row(any(p.startswith('position') for p in problems),
        'MUTANT: same names in the WRONG ORDER is caught',
        '; '.join(problems[:2]))

    # 5. the dot difference is cosmetic, not a misalignment
    lines = build(['ABORT.CAUSE', 'EXPAND.HF'], ['ABORT.CAUSE', 'EXPANDHF'])
    reg, _ = read_registrations(lines)
    dis, _ = read_dispatch(lines)
    problems, cosmetic = compare(reg, dis)
    row(not problems and len(cosmetic) == 1,
        'fixture: a dot-only label difference is cosmetic, not a fault',
        '; '.join(problems) or ('cosmetic: ' + '; '.join(cosmetic)))

    # 6. REFUSE THE NULL CASE - two empty lists compare equal and prove nothing
    dis, _ = read_dispatch(['nothing here', 'nor here'])
    row(dis is None, 'null case: a file with no dispatch block is refused, '
                     'not reported aligned')

    # --- the live file -----------------------------------------------------
    if not os.path.isfile(BCOMP):
        row(False, 'live: BCOMP is readable', 'not found at %s' % BCOMP)
        print('')
        print('%d check(s) failed' % len(fails))
        return 1

    with open(BCOMP, 'r', encoding='latin-1') as fh:
        lines = fh.read().split('\n')
    reg, reg_lines = read_registrations(lines)
    dis, dis_lines = read_dispatch(lines)

    if dis is None:
        row(False, 'live: the intrinsic "on i goto" block is found',
            'not found - this check measured nothing')
        print('')
        print('%d check(s) failed' % len(fails))
        return 1

    print('  live: %d registrations (lines %d-%d), %d dispatch entries '
          '(lines %d-%d)'
          % (len(reg), reg_lines[0], reg_lines[-1],
             len(dis), dis_lines[0], dis_lines[-1]))

    # A plausibility floor: BCOMP has had dozens of intrinsics for twenty
    # years, so a handful means the extractor broke, not that they were deleted.
    row(len(reg) >= 30 and len(dis) >= 30,
        'live: both lists are plausibly long (>= 30)',
        '%d and %d' % (len(reg), len(dis)))

    problems, cosmetic = compare(reg, dis)
    for c in cosmetic:
        print('  note: cosmetic label difference, not a misalignment - %s' % c)
    row(not problems, 'live: the two lists are aligned, same names same order',
        '; '.join(problems[:4]))

    print('')
    if fails:
        print('test-intrinsics-units: %d of %d check(s) failed: %s'
              % (len(fails), len(ran), '; '.join(fails)))
        return 1
    # REFUSE THE NULL CASE one last time: a run that somehow reached here
    # having asserted nothing must not print a pass.
    if len(ran) < 10:
        print('test-intrinsics-units: only %d checks ran - expected at least '
              '10, so this run is NOT a pass' % len(ran))
        return 1
    print('test-intrinsics-units: %d passed, 0 failed (%d intrinsics aligned)'
          % (len(ran), len(reg)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
