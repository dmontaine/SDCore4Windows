#
# test-logtohalftree-units.py - free-tier guard for two owner rulings of 14 Nov 2026.
#
# command line: python gplbld/test-logtohalftree-units.py
# Exits 0 if every check passes and every mutant is caught, 1 otherwise.  Reads cproc, the message file and sd.iss only.
# A READ OF THE SOURCE, NOT A RUN OF IT: what the installer and LOGTO then do on a real machine is witnessed in the VM sitting.
#
# RELEASE_1.1 275 - LOGTO out of an elevated SDSYS session.  The Windows token cannot be dropped, so SD's own administrator
#   rights end (as Linux) and the administrator is TOLD, once per LOGTO, by message 12987.  Not shown to anyone who was not an
#   administrator, and never at LOGTO into SDSYS.
# RELEASE_1.1 294 - a half data tree (sdsys there, no account in sdsys\accounts) is REFUSED before anything is copied, with the
#   reason and how to correct it.  A machine with no data tree, and a tree with accounts, are not refused.
#
# EACH MUTANT BREAKS ONE PIECE IN MEMORY and a check must go red.  Nothing on disk is written.

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
CPROC = os.path.join(SD64, 'sdsys', 'gpl.bp', 'cproc')
MSG = os.path.join(SD64, 'sdsys', 'messages', '12987')
ISS = os.path.join(HERE, 'sd.iss')


def read(p):
    with open(p, 'r', encoding='utf-8', errors='replace', newline='') as f:
        return f.read()


def body(t, header):
    m = re.search(r'^' + re.escape(header) + r'.*?^end;', t, re.S | re.M)
    return m.group(0) if m else ''


def checks(cproc, msg, iss):
    bad = []

    def need(name, ok):
        if not ok:
            bad.append(name)

    # ---- 275
    m = re.search(r"if was\.admin then(.*?)\n      end\n   end", cproc, re.S)
    blk = m.group(1) if m else ''
    need('275: the LOGTO out of SDSYS block exists', bool(blk))
    need("275: the warning is inside 'if was.admin' (only an administrator is told)", 'display sysmsg(12987, new.account)' in blk)
    i_stop = blk.find("elevate('STOP', '')")
    i_msg = blk.find('display sysmsg(12987, new.account)')
    need('275: it comes after the elevated helper is stopped', 0 <= i_stop < i_msg)
    need('275: it is the only place the message is shown', cproc.count('sysmsg(12987') == 1)
    need("275: LOGTO into sdsys does not show it", "if new.account = 'sdsys' then" in cproc
         and cproc.find("if new.account = 'sdsys' then") < cproc.find('sysmsg(12987'))
    need('275: the message file names the account twice and says how to correct',
         msg.count('%1') == 2 and 'Sign out' in msg and 'administrator' in msg)

    # ---- 294
    fn = body(iss, 'function DataTreeHasNoAccounts: Boolean;')
    need('294: the helper looks in sdsys\\accounts', r"sdsys\accounts\*" in fn)
    need('294: the helper counts files, not directories', 'FILE_ATTRIBUTE_DIRECTORY) = 0' in fn)
    need('294: the helper skips . and ..', "R.Name <> '.'" in fn and "R.Name <> '..'" in fn)
    need('294: the helper says no account when there is no register', re.search(r'Result := True;\s*if FindFirst', fn) is not None)
    need('294: the helper stops at the first account', 'until (not Result)' in fn)
    ref = re.search(r"if \(not DataTreeWasAbsent\) and DataTreeHasNoAccounts then(.*?)\n  end;", iss, re.S)
    rb = ref.group(1) if ref else ''
    need('294: the refusal exists and is only for a tree that is there (not DataTreeWasAbsent)', bool(ref))
    need('294: the refusal says what is wrong and how to correct it', 'has a system folder and no accounts' in rb and 'To correct it: delete' in rb)
    need('294: the refusal stops setup', 'Result := False;' in rb and 'Exit;' in rb)
    need('294: the refusal is logged', "Log('SD: refusing - '" in rb)
    i_ref = iss.find('if (not DataTreeWasAbsent) and DataTreeHasNoAccounts then')
    i_sam = iss.find('ApiConfWasAbsent := not FileExists')
    need('294: the refusal comes after the tree has been sampled', 0 <= i_sam < i_ref)
    return bad


MUTANTS = [
    ('the LOGTO warning is shown to everyone (moved out of the administrator block)',
     lambda c, m, i: (c.replace('         display sysmsg(12987, new.account)\n      end\n   end',
                                '      end\n   end\n   display sysmsg(12987, new.account)', 1), m, i)),
    ('the LOGTO warning is gone', lambda c, m, i: (c.replace('display sysmsg(12987, new.account)', 'void 0', 1), m, i)),
    ('the warning message file loses its remedy', lambda c, m, i: (c, m.replace('Sign out and sign in', 'Carry on'), i)),
    ('a half tree check counts directories as accounts',
     lambda c, m, i: (c, m, i.replace('FILE_ATTRIBUTE_DIRECTORY) = 0)', 'FILE_ATTRIBUTE_DIRECTORY) <> 0)', 1))),
    ('a machine with no data tree is refused too',
     lambda c, m, i: (c, m, i.replace('if (not DataTreeWasAbsent) and DataTreeHasNoAccounts then', 'if DataTreeHasNoAccounts then', 1))),
    ('the refusal no longer stops setup',
     lambda c, m, i: (c, m, re.sub(r"(To correct it: delete.*?mbError, MB_OK, IDOK\);\n)    Result := False;\n    Exit;", r"\1    Result := True;", i, count=1, flags=re.S))),
    ('the refusal gives no remedy',
     lambda c, m, i: (c, m, i.replace('To correct it: delete', 'Sorry: delete', 1))),
]


def main():
    for p in (CPROC, MSG, ISS):
        if not os.path.isfile(p):
            print('NO TREE: %s is not here' % p)
            return 2
    c, m, i = read(CPROC), read(MSG), read(ISS)
    print('cproc %d bytes, message 12987 %d bytes, sd.iss %d bytes' % (len(c), len(m), len(i)))
    fails = 0
    bad = checks(c, m, i)
    if bad:
        for b in bad:
            print('FAIL  %s' % b)
        fails += len(bad)
    else:
        print('PASS  every check on the live files')
    for name, mut in MUTANTS:
        c2, m2, i2 = mut(c, m, i)
        if (c2, m2, i2) == (c, m, i):
            print('FAIL  mutant did not apply (anchor drifted): %s' % name)
            fails += 1
            continue
        caught = checks(c2, m2, i2)
        if caught:
            print('PASS  mutant caught (%d red): %s' % (len(caught), name))
        else:
            print('FAIL  mutant NOT caught: %s' % name)
            fails += 1
    print('')
    if fails == 0:
        print('logto and half tree units: ALL PASS (%d mutants, all caught)' % len(MUTANTS))
        return 0
    print('logto and half tree units: %d FAILED' % fails)
    return 1


if __name__ == '__main__':
    sys.exit(main())
