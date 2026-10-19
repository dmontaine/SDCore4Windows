#!/usr/bin/env python3
#
# test-screencmd-units.py - the SCREEN statement's three places agree: the verb table in bcomp, the subroutine each
# verb calls, and the header that documents the statement.  No install, no sudo, no sd.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-screencmd-units.py              check the tree
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-screencmd-units.py --selftest   mutate a copy five ways
#
# Exit 0 every check passed, 1 one failed, 2 it could not read what it checks.
#
# WHY.  A verb is a row in bcomp's SCREEN.NAMES / SCREEN.DEFS (verb, catalogued subroutine, how many positional values,
# keywords with their value counts), and the statement compiles into a CALL whose arguments are the positional values,
# then one slot for every keyword value (a flag is one slot), then the RETURNING variable and a status.  If the row and
# the subroutine's argument list drift apart nothing fails to COMPILE: the call is made with the wrong number of
# arguments and the program misbehaves at run time.  Nor does anything notice a subroutine that lost its $catalog line
# or a header that no longer says what the statement takes.  This reads the three and compares them.
#
# START-HISTORY:
# 12 Oct 26 dm  Written with stage 1 of the screen library.
# END-HISTORY

import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)


class Unreadable(Exception):
    pass


def parse_table(src):
    """[(verb, routine, npos, [(keyword, n_or_F)])] from the SCREEN.NAMES / SCREEN.DEFS assignments in bcomp."""
    names = re.findall(r'screen\.names(?:<-1>)?\s*=\s*"([A-Z.]+)"', src)
    defs = re.findall(r'screen\.defs(?:<-1>)?\s*=\s*([^;\n]+)', src)
    if not names or len(names) != len(defs):
        return None
    out = []
    for verb, expr in zip(names, defs):
        toks = re.findall(r'"[^"]*"|@vm|@sm|\d+', expr)
        routine = toks[0].strip('"')
        npos = int(toks[2]) if len(toks) > 2 and toks[1] == "@vm" else -1
        kws = []
        for t in (toks[4:] if len(toks) > 3 and toks[3] == "@vm" else []):
            if t == "@sm":
                continue
            k, n = t.strip('"').split(":")
            kws.append((k, n))
        out.append((verb, routine, npos, kws))
    return out


def check(gpl):
    """Every check against the gpl.bp directory `gpl`: a list of (ok, name, detail)."""
    rows = []

    def row(name, ok, detail=""):
        rows.append((bool(ok), name, detail))

    try:
        bsrc = open(os.path.join(gpl, "bcomp"), encoding="latin-1").read()
    except OSError as e:
        raise Unreadable("cannot read bcomp: %s" % e)
    table = parse_table(bsrc)
    row("bcomp has a verb table: SCREEN.NAMES and SCREEN.DEFS have the same number of rows, and at least one",
        table is not None and len(table) >= 1, "names and defs differ, or none found")
    if not table:
        return rows
    verbs = [t[0] for t in table]
    row("verb names are unique and upper case", len(set(verbs)) == len(verbs) and all(v == v.upper() for v in verbs), repr(verbs))
    row("SCREEN is in the statements list, and st.screen is in the ON GOSUB list right after SAVELIST / st.savelist",
        re.search(r'"SAVELIST":@fm:"SCREEN":@fm:"SEEK"', bsrc) is not None and re.search(r'st\.savelist,\s*\n\s*st\.screen,', bsrc) is not None, "")
    for verb, routine, npos, kws in table:
        name = routine.lstrip("!")
        row("%s: the subroutine is !screen_%s" % (verb, verb.lower()), routine == "!screen_" + verb.lower(), routine)
        path = os.path.join(gpl, name)
        if not os.path.isfile(path):
            row("%s: the source %s exists" % (verb, name), False, path)
            continue
        src = open(path, encoding="latin-1").read()
        m = re.search(r'(?im)^subroutine\s+%s\s*\(([^)]*)\)' % re.escape(name), src)
        params = [p.strip() for p in m.group(1).split(",")] if m else []
        slots = sum(1 if n == "F" else int(n) for _, n in kws)
        want = npos + slots + 2
        row("%s: the subroutine takes %d arguments (%d values + %d keyword slots + ret + status)" % (verb, want, npos, slots),
            m is not None and len(params) == want, "found %d: %s" % (len(params), params))
        row("%s: the last two arguments are ret and status" % verb, params[-2:] == ["ret", "status"], repr(params[-2:]))
        row("%s: it is catalogued as %s" % (verb, routine), re.search(r'(?im)^\$catalog\s+%s\s*$' % re.escape(routine), src) is not None, "no $catalog line")
        row("%s: it is an $internal source (so it may call the $-named routines)" % verb, re.search(r'(?m)^\$internal\s*$', src) is not None, "")
        doc = re.search(r'(?im)^\*\s+SCREEN\s+%s\b(.*)$' % re.escape(verb), src)
        words = set(re.findall(r'[A-Z.]+', doc.group(1))) if doc else set()
        missing = [k for k, _ in kws if k not in words]
        row("%s: its header gives the statement form with every keyword (%s)" % (verb, ", ".join(k for k, _ in kws) or "none"),
            doc is not None and not missing, ("no 'SCREEN %s' line" % verb) if doc is None else "missing " + ", ".join(missing))
    msgs = [os.path.join(os.path.dirname(gpl), "messages", str(n)) for n in (12172, 12173, 12174, 12175)]
    row("the four compile messages 12172 to 12175 exist and do not shout SCREEN (lower case, by the owner's rule)",
        all(os.path.isfile(p) for p in msgs) and all("SCREEN" not in open(p).read() for p in msgs if os.path.isfile(p)), "")
    return rows


def selftest():
    print("test-screencmd-units: --selftest, a copy of bcomp and the screen routines changed five ways")
    gpl = os.path.join(SD64, "sdsys", "gpl.bp")
    files = ["bcomp"] + sorted(f for f in os.listdir(gpl) if f.startswith("screen_"))
    mutants = [
        ("a keyword added to a row without a slot in the subroutine", "bcomp",
         '"TITLE:1":@sm:"BUTTONS:1":@sm:"DEFAULT:1":@sm:"AT:2"', '"TITLE:1":@sm:"BUTTONS:1":@sm:"DEFAULT:1":@sm:"AT:2":@sm:"WIDTH:1"'),
        ("the $catalog line taken out of a routine", "screen_text", "$catalog !screen_text", "* $catalog removed"),
        ("status renamed in a routine's argument list", "screen_key", "subroutine screen_key(timeout, ret, status)", "subroutine screen_key(timeout, ret, st)"),
        ("a keyword missing from a routine's documented form", "screen_box",
         "SCREEN BOX {AT x,y} {SIZE w,h} {TITLE t} {ATTR style} {FILL}", "SCREEN BOX {AT x,y} {SIZE w,h} {TITLE t} {ATTR style}"),
        ("a row pointing at a routine that is not there", "bcomp", '"!screen_size":@vm:0', '"!screen_sizes":@vm:0'),
    ]
    bad = 0
    tmp = tempfile.mkdtemp(prefix="screencmd.")
    try:
        for label, fname, old, new in [(None, None, None, None)] + mutants:
            d = os.path.join(tmp, "case")
            shutil.rmtree(d, ignore_errors=True)
            os.makedirs(os.path.join(d, "gpl.bp"))
            os.makedirs(os.path.join(d, "messages"))
            for f in files:
                shutil.copy(os.path.join(gpl, f), os.path.join(d, "gpl.bp", f))
            for n in (12172, 12173, 12174, 12175):
                shutil.copy(os.path.join(SD64, "sdsys", "messages", str(n)), os.path.join(d, "messages", str(n)))
            if label is not None:
                p = os.path.join(d, "gpl.bp", fname)
                s = open(p, encoding="latin-1").read()
                if s.count(old) != 1:
                    print("  [FAIL] the mutation does not match exactly once in %s: %r" % (fname, old))
                    bad += 1
                    continue
                open(p, "w", encoding="latin-1").write(s.replace(old, new))
            failed_rows = [r for r in check(os.path.join(d, "gpl.bp")) if not r[0]]
            if label is None:
                ok = not failed_rows
                print("  [%s] case 0, the unchanged copy: %d check(s) failed (a positive control: none must)" % ("PASS" if ok else "FAIL", len(failed_rows)))
            else:
                ok = bool(failed_rows)
                print("  [%s] %s: %d check(s) failed (at least one must)" % ("PASS" if ok else "FAIL", label, len(failed_rows)))
            bad += 0 if ok else 1
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    print("\ntest-screencmd-units: selftest %s" % ("passed" if not bad else "FAILED, %d case(s)" % bad))
    return 1 if bad else 0


def main():
    if "--selftest" in sys.argv:
        return selftest()
    print("test-screencmd-units: the verb table, the routines and their headers")
    try:
        rows = check(os.path.join(SD64, "sdsys", "gpl.bp"))
    except Unreadable as e:
        print("test-screencmd-units: CANNOT ANSWER - %s" % e)
        return 2
    for ok, name, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "   <- " + detail))
    nf = sum(1 for r in rows if not r[0])
    print("\ntest-screencmd-units: %d passed, %d failed" % (len(rows) - nf, nf))
    if not rows:
        print("test-screencmd-units: CANNOT ANSWER - no check ran")
        return 2
    return 1 if nf else 0


if __name__ == "__main__":
    sys.exit(main())
