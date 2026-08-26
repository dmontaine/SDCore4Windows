#
# testtokens.py - prove the mark-token round trip and its guard BEFORE a cycle
# spends time on it.
#
# gpl.bp/EDIT converts @vm <-> "~~" and @sm <-> "~`" with change(), then
# converts BACK and compares; a record that does not survive that is refused.
# change() replaces left to right without overlapping, which is what Python's
# str.replace does, so the algorithm can be exercised here exactly as SD will
# run it.
#
VM = '\xfd'
SM = '\xfc'
VT = '~~'
ST = '~' + chr(96)


def out(rec):
    w = rec.replace(VM, VT)
    w = w.replace(SM, ST)
    return w


def back(w):
    r = w.replace(VT, VM)
    r = r.replace(ST, SM)
    return r


def edit_ok(rec):
    """What EDIT's guard decides: does this record survive the round trip?"""
    return back(out(rec)) == rec


def show(s):
    return s.replace(VM, '<VM>').replace(SM, '<SM>')


CASES = [
    ('plain text',                 'HELLO',                       True),
    ('two fields',                 'LINE1\xfeLINE2',              True),
    ('one multivalue',             'SMITH' + VM + 'JONES',        True),
    ('three values',               'A' + VM + 'B' + VM + 'C',     True),
    ('one subvalue',               'A' + SM + 'B',                True),
    ('values and subvalues',       'A' + VM + 'B' + SM + 'C',     True),
    ('empty value',                'A' + VM + VM + 'B',           True),
    ('a lone tilde in data',       'a~b',                         True),
    ('a lone backtick in data',    'a' + chr(96) + 'b',           True),
    ('tilde NOT next to a mark',   'a~b' + VM + 'c',              True),
    # --- the ones that must be refused --------------------------------
    ('"~~" already in the data',   'a~~b',                        False),
    ('"~`" already in the data',   'a~' + chr(96) + 'b',          False),
    ('tilde immediately before VM', 'a~' + VM + 'b',              False),
    ('tilde immediately before SM', 'a~' + SM + 'b',              False),
]

print('testtokens: VM=%r  SM=%r  vm.token=%r  sm.token=%r' % (VM, SM, VT, ST))
print()

bad = 0
for name, rec, expect_ok in CASES:
    got = edit_ok(rec)
    mark = 'ok  ' if got == expect_ok else 'FAIL'
    if got != expect_ok:
        bad += 1
    print('  %s %-30s %-22s editor sees %-18s round trip %s'
          % (mark, name, show(rec), show(out(rec)),
             'lossless' if got else 'REFUSED'))

print()
print('testtokens: %d case(s), %d wrong' % (len(CASES), bad))
if bad:
    raise SystemExit(1)

# A refusal must not be the answer to everything - a check that refuses
# every record would "pass" the table above by accident if the table were
# all-negative.  It is not, and this says so out loud.
allowed = sum(1 for _, r, _ in CASES if edit_ok(r))
print('testtokens: %d of %d records are editable, %d refused - both non-zero'
      % (allowed, len(CASES), len(CASES) - allowed))
if allowed == 0 or allowed == len(CASES):
    raise SystemExit('testtokens: the guard is answering the same way to everything')
