#
# test-upgradeiss-units.py - unit test for stage.py's write_upgrade_iss()
#
# command line: python3 gplbld/test-upgradeiss-units.py
# Exits 0 if every check passes, 1 otherwise.  Touches nothing but %TEMP%,
# needs no build, no install and no elevation, and makes no claim about the
# installed tree - so it is not a verify-* script and is in neither post-cycle
# runner.
#
# WHY THIS ONE HAS A TEST WHEN THE REST OF stage.py DOES NOT.  Everything else
# in that file COPIES; this decides what an upgrade DELETES from a live
# database.  Getting the classification wrong does not produce a broken build,
# it produces an installer that destroys $cred - after which every account is
# unreachable over ssh and the API, which is a state that has already cost two
# sessions to diagnose once.
#
# IT IMPORTS stage.py RATHER THAN RESTATING THE LISTS, on purpose.  A test
# carrying its own copy of SDSYS_SHIP would go on passing after somebody added
# a name to the real one, which is the failure mode it exists to catch.
#

import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stage as S

# Names the BOOTSTRAP and the running system create.  They appear in no list
# in stage.py, and the safety argument is that an upgrade therefore cannot
# reach them however that file is edited.  Asserted below, not assumed.
RUNTIME = ['voc', 'voc.dic', 'dict.dic', 'accounts.dic', '$map', '$map.dic',
           '$ipc', 'errlog', 'stacks', 'dir_dict', 'pstmp', 'audit']

# Which declared names are FILES in a real staged tree rather than directories.
# The emitter picks its form from the disk, so the fixture has to have the
# real shape or the file branch goes untested.
DECLARED_FILES = ['licence', 'contrib'] + [n for n, _w in S.TERMINFO_FILES]

fails = []


def check(name, cond, detail=''):
    if cond:
        print('  PASS  %s' % name)
    else:
        print('  FAIL  %s  %s' % (name, detail))
        fails.append(name)


def expect_die(name, fn):
    try:
        fn()
    except SystemExit as e:
        print('  PASS  %s -> refused: %s' % (name, str(e)[:64]))
        return
    print('  FAIL  %s -> did NOT refuse' % name)
    fails.append(name)


def build_tree(root, skip=(), empty=()):
    """A staged tree with the shape stage.py produces, and nothing in it."""
    sdsys = os.path.join(root, 'ProgramData', 'sdsys')
    os.makedirs(sdsys)
    declared = ([n for n, _w in S.SDSYS_SHIP] + [n for n, _w in S.SDSYS_EMPTY] +
                [n for n, _w in S.TERMINFO_DIRS] +
                [n for n, _w in S.TERMINFO_FILES])
    for n in declared + RUNTIME:
        if n in skip:
            continue
        if n in DECLARED_FILES:
            with open(os.path.join(sdsys, n), 'w') as f:
                f.write('x')
            continue
        os.makedirs(os.path.join(sdsys, n))
        if n not in empty:
            with open(os.path.join(sdsys, n, 'X'), 'w') as f:
                f.write('x')
    return sdsys


def main():
    print('test-upgradeiss-units: stage.py at %s'
          % os.path.join(os.path.dirname(os.path.abspath(__file__)),
                         'stage.py'))

    # --- the positive case -------------------------------------------------

    root = tempfile.mkdtemp()
    try:
        sdsys = build_tree(root)
        path, replace, preserve = S.write_upgrade_iss(root, sdsys, True)
        text = open(path, encoding='ascii').read()
        dels = [l for l in text.splitlines() if l.startswith('Name:')]
        copies = [l for l in text.splitlines() if l.startswith('Source:')]

        print('  emitted   %s' % path)
        print('  REPLACES  %s' % ' '.join(replace))
        print('  PRESERVES %s' % ' '.join(preserve))
        print('  %d InstallDelete, %d Files' % (len(dels), len(copies)))
        print('checks:')

        # THE NULL CASE, REFUSED OUT LOUD.  Every check below is of the form
        # "X does not appear", and all of them pass trivially against an empty
        # file - so the first thing asserted is that something was emitted.
        check('emitted a non-empty pair of sections',
              len(dels) > 0 and len(copies) > 0,
              'an empty emit passes every absence check below')
        retired = [n for n, _w in S.SDSYS_RETIRED]
        check('delete and copy are paired, apart from the retired names',
              len(dels) == len(copies) + len(retired),
              '%d deletes vs %d copies + %d retired'
              % (len(dels), len(copies), len(retired)))
        check('one copy per replace name', len(replace) == len(copies))
        for n in retired:
            check('RETIRED %s is deleted and NOT copied back' % n,
                  any(('\\sdsys\\%s"' % n) in l for l in dels) and
                  not any(('\\sdsys\\%s' % n) in l for l in copies))
        check('every entry is gated on DataTreeUpgrade',
              all('Check: DataTreeUpgrade' in l for l in dels + copies))

        for n in preserve:
            check('PRESERVED %s appears in neither section' % n,
                  ('\\sdsys\\%s"' % n) not in text and
                  ('\\sdsys\\%s\\' % n) not in text)
        for n in replace:
            check('REPLACED %s is deleted and copied back' % n,
                  any(('\\sdsys\\%s"' % n) in l for l in dels) and
                  any(('\\sdsys\\%s"' % n) in l or
                      ('\\sdsys\\%s\\*"' % n) in l for l in copies))
        for n in RUNTIME:
            check('RUNTIME %s is out of reach' % n,
                  ('\\sdsys\\%s"' % n) not in text and
                  ('\\sdsys\\%s\\' % n) not in text)

        check('a declared FILE is emitted as a file, not a wildcard',
              any('\\sdsys\\licence"' in l and '\\*' not in l for l in copies))
        # It ships to {app} now.  It appears in the generated file only as a
        # retired DELETE - asserted just above - so the claim here is the one
        # about the ship lists, not about the text.
        check('changelog is on no ship list any more',
              'changelog' not in [n for n, _w in S.SDSYS_SHIP] and
              'changelog' not in [n for n, _w in S.SDSYS_EMPTY])
    finally:
        shutil.rmtree(root, ignore_errors=True)

    # --- the refusals ------------------------------------------------------

    print('refusals:')

    r = tempfile.mkdtemp()
    try:
        s = build_tree(r, empty=['gcat'])
        expect_die('an EMPTY replace directory',
                   lambda: S.write_upgrade_iss(r, s, True))
    finally:
        shutil.rmtree(r, ignore_errors=True)

    r = tempfile.mkdtemp()
    try:
        s = build_tree(r, skip=['$cred'])
        expect_die('a preserve name the staged tree does not have',
                   lambda: S.write_upgrade_iss(r, s, True))
    finally:
        shutil.rmtree(r, ignore_errors=True)

    r = tempfile.mkdtemp()
    saved = S.SDSYS_PRESERVE
    try:
        s = build_tree(r)
        S.SDSYS_PRESERVE = saved + [('$creed', 'a typo for $cred')]
        os.makedirs(os.path.join(s, '$creed'))
        expect_die('a preserve name no ship list declares',
                   lambda: S.write_upgrade_iss(r, s, True))
    finally:
        S.SDSYS_PRESERVE = saved
        shutil.rmtree(r, ignore_errors=True)

    r = tempfile.mkdtemp()
    saved = S.SDSYS_RETIRED
    try:
        s = build_tree(r)
        S.SDSYS_RETIRED = saved + [('gcat', 'a name that still ships')]
        expect_die('a retired name that a ship list still declares',
                   lambda: S.write_upgrade_iss(r, s, True))
    finally:
        S.SDSYS_RETIRED = saved
        shutil.rmtree(r, ignore_errors=True)

    r = tempfile.mkdtemp()
    try:
        s = build_tree(r)
        p, rep, _pre = S.write_upgrade_iss(r, s, False)
        cold = open(p, encoding='ascii').read()
        check('a cold tree emits #error and no entries at all',
              '#error' in cold and 'Name:' not in cold and rep == [])
    finally:
        shutil.rmtree(r, ignore_errors=True)

    print('')
    print('%d check(s) failed' % len(fails))
    return 1 if fails else 0


if __name__ == '__main__':
    sys.exit(main())
