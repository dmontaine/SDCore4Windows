#!/usr/bin/env python3
#
# test-xfun-units.py - the intrinsic function tables of bcomp and the XFUN opcode, read off the source.  QM4 gaps bundle Q-1.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-xfun-units.py [--selftest]
#
# No sudo, no install, no sd.  Exit 0 every check held, 1 one did not.  --selftest breaks a copy of the sources in six
# ways and expects each to be caught by exactly the check that owns it.
#
# START-HISTORY:
# 15 Oct 26 dm  Written when the OP.XFUN functions were added: bcomp's list of intrinsic names and its list of handlers
#               are two parallel lists that nothing ties together except order, and `locate ... by 'AL'` needs the names
#               sorted.  A name put in one list and not the other, or in the wrong place, gives the next function the
#               wrong handler without any message.  This checks the pairing for every intrinsic, not only the new ones.
# END-HISTORY
#
# WHAT IT CHECKS
#   1. intrinsics: the names bcomp lists are in ascending ASCII order (the order LOCATE BY 'AL' needs), no name twice.
#   2. handlers: the handler list that follows has one entry for every name and the comment on each entry (";* NAME")
#      is that name, in the same order - so the pairing is by name and not by counting.
#   3. every name given OP.XFUN has the handler in.xfun, and every in.xfun handler belongs to a name given OP.XFUN.
#   4. xfun.rows: each name's row says the function number, the arguments written, an optional last argument, and
#      whether it is multivalued; every row's name is an OP.XFUN intrinsic and every OP.XFUN intrinsic has a row.
#   5. op_xfun.c: each function number in xfun.rows is a #define XF_ constant with a case in op_xfun(), and no XF_
#      constant is without a row.

import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
BCOMP = os.path.join(SD64, "sdsys", "gpl.bp", "bcomp")
XFUN_C = os.path.join(SD64, "gplsrc", "op_xfun.c")

passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def read(path):
    with open(path, encoding="latin-1") as f:
        return f.read()


def parse(bcomp_text, c_text):
    d = {}
    # the names, in the order bcomp lists them: `intrinsics = "ABS" ; intrinsic.opcodes = OP.ABS` then `<-1>` for the rest
    d["names"] = []
    d["opcodes"] = {}
    for m in re.finditer(r'(?m)^\s*intrinsics(?:<-1>)? = "([A-Z0-9.$]+)"\s*;\s*intrinsic\.opcodes(?:<-1>)? = (OP\.[A-Z0-9.$]+|\'\')', bcomp_text):
        d["names"].append(m.group(1))
        d["opcodes"][m.group(1)] = m.group(2)
    # the handler list of the ordinary intrinsics: the `on i goto` whose first entry is commented ;* ABS (the one before it
    # is the list for the internal-mode intrinsics, ABORT.CAUSE on, which has its own names)
    m = re.search(r"(?m)^\s*on i goto in\.[a-z0-9.]+,\s*;\*\s*ABS\s*$", bcomp_text)
    block = bcomp_text[m.start():] if m else ""
    d["handlers"] = []
    for m in re.finditer(r"(?m)^\s*(?:on i goto )?(in\.[a-z0-9.]+),?\s*;\*\s*([A-Z0-9.$]+)\b.*$", block):
        d["handlers"].append((m.group(1), m.group(2)))
        # the list ends at the first line that is not an entry; stop when the names run out
        if m.group(2) == d["names"][-1]:
            break
    # xfun.rows
    d["rows"] = {}
    rows_text = ""
    for m in re.finditer(r'(?m)^\s*xfun\.rows\s*:?=\s*(.*)$', bcomp_text):
        rows_text += m.group(1) + "\n"
    for m in re.finditer(r'"([A-Z0-9.]+),(\d+),(\d+),(\d*),([01])"', rows_text):
        d["rows"][m.group(1)] = (int(m.group(2)), int(m.group(3)), m.group(4), int(m.group(5)))
    # the numbers a handler of its own loads: the line that does it carries the constant's name in its comment
    d["own_loads"] = {}
    for m in re.finditer(r"(?m)^\s*n = (\d+) ; gosub emit\.numeric\.load\s*;\*\s*(XF_[A-Z]+)", bcomp_text):
        d["own_loads"][m.group(2)] = int(m.group(1))
    d["xf_defs"] = {m.group(1): int(m.group(2)) for m in re.finditer(r"(?m)^#define (XF_[A-Z_]+) (\d+)", c_text)}
    d["xf_cases"] = set(re.findall(r"case (XF_[A-Z_]+):", c_text))
    return d


def checks(d):
    res = []
    names = d["names"]
    res.append(("1. the intrinsic names are in ascending order, none twice",
                names == sorted(names) and len(set(names)) == len(names),
                "first out of order: %s" % next((b for a, b in zip(names, names[1:]) if a >= b), "-")))
    h = d["handlers"]
    # two comments in the list are the spelling of the old opcode names and have always differed from the intrinsic's name
    legacy = {"ARG.COUNT": "ARGCT", "SOCKET.INFO": "SOCKETINFO"}
    res.append(("2. one handler for every name, each commented with its own name, in the same order",
                len(h) == len(names) and all(b[1] == legacy.get(a, a) for a, b in zip(names, h)),
                "lists differ at %s" % next((("name %s, handler comment %s" % (a, b[1])) for a, b in zip(names, h) if b[1] != legacy.get(a, a)),
                                            "the end (%d names, %d handlers)" % (len(names), len(h)))))
    # ARG.PRESENT is given OP.XFUN too, but reads a variable name and so has a handler of its own
    own = {"ARG.PRESENT": "in.arg.present", "REUSING": "in.reusing"}
    xnames = {n for n in names if d["opcodes"][n] == "OP.XFUN" and n not in own}
    hx = {n for hh, n in h if hh == "in.xfun"}
    res.append(("3. the names given OP.XFUN are the names with the handler in.xfun (ARG.PRESENT has in.arg.present)",
                xnames == hx and all(d["opcodes"].get(n) == "OP.XFUN" and (hh, n) in h for n, hh in own.items()),
                "only one side: %s" % sorted(xnames ^ hx)))
    rows = d["rows"]
    res.append(("4. xfun.rows has a row for every OP.XFUN name and for no other",
                set(rows) == xnames, "only one side: %s" % sorted(set(rows) ^ xnames)))
    bad = [n for n, (sel, argc, opt, mv) in rows.items() if not (1 <= argc <= 3) or (mv and not 1 <= argc <= 3)]
    res.append(("4b. every row writes one to three arguments", not bad and len(rows) > 0, "rows: %s" % bad))
    sels = {sel for sel, _a, _o, _m in rows.values()}
    # XF_CASING (a statement) and XF_ARGPRESENT (ARG.PRESENT's own handler) are loaded by code of their own, not by a row
    own_c = {"XF_CASING": 19, "XF_ARGPRESENT": 20, "XF_REUSING": 24}
    defs = {v for k, v in d["xf_defs"].items() if k not in own_c}
    res.append(("5. every function number of xfun.rows is an XF_ constant of op_xfun.c and the reverse", sels == defs and len(defs) > 0,
                "only one side: %s" % sorted(sels ^ defs)))
    res.append(("5a. CASING, ARG.PRESENT and REUSING load the numbers op_xfun.c gives XF_CASING, XF_ARGPRESENT and XF_REUSING",
                all(d["xf_defs"].get(k) == v and d["own_loads"].get(k) == v for k, v in own_c.items()),
                "op_xfun.c says %s, bcomp loads %s" % ({k: d["xf_defs"].get(k) for k in own_c}, d["own_loads"])))
    res.append(("5b. every XF_ constant has a case in op_xfun()", set(d["xf_defs"]) <= d["xf_cases"] | {"XF_IS_ALNUM", "XF_IS_ALPHA", "XF_IS_DIGIT", "XF_IS_GRAPH", "XF_IS_MARK", "XF_IS_SPACE"} and d["xf_cases"] <= set(d["xf_defs"]),
                "defined without a case: %s" % sorted(set(d["xf_defs"]) - d["xf_cases"])))
    return res


def run_checks(bcomp_text, c_text):
    d = parse(bcomp_text, c_text)
    ok_all = True
    for name, ok, detail in checks(d):
        row(name, ok, detail)
        ok_all = ok_all and ok
    return d, ok_all


def selftest():
    b = read(BCOMP)
    c = read(XFUN_C)
    mutants = [
        ("a name moved out of order", b.replace('intrinsics<-1> = "LAST"            ; intrinsic.opcodes<-1> = OP.XFUN\n   intrinsics<-1> = "LASTS"           ; intrinsic.opcodes<-1> = OP.XFUN',
                                                'intrinsics<-1> = "LASTS"           ; intrinsic.opcodes<-1> = OP.XFUN\n   intrinsics<-1> = "LAST"            ; intrinsic.opcodes<-1> = OP.XFUN'), c, "1."),
        ("a handler entry left out", b.replace("                      in.xfun,        ;* LEFT\n", ""), c, "2."),
        ("a handler with the wrong comment name", b.replace(";* IS.MARK", ";* IS.MARX"), c, "2."),
        ("a row left out", b.replace('"IS.MARK,9,1,,0":@fm:', ""), c, "4."),
        ("a function number changed", b.replace('"RIGHT,12,2,,0"', '"RIGHT,19,2,,0"'), c, "5."),
        ("a case removed from op_xfun()", b, c.replace("    case XF_NS:\n      x_nv(TRUE);\n      break;\n", ""), "5b."),
        ("ARG.PRESENT loading another number", b.replace("n = 20 ; gosub emit.numeric.load      ;* XF_ARGPRESENT", "n = 21 ; gosub emit.numeric.load      ;* XF_ARGPRESENT"), c, "5a."),
    ]
    ok_all = True
    for label, bm, cm, want in mutants:
        if bm == b and cm == c:
            row("selftest: %s" % label, False, "the mutation changed nothing")
            ok_all = False
            continue
        d = parse(bm, cm)
        fails = [name.split(" ")[0] for name, ok, _ in checks(d) if not ok]
        row("selftest: %s is caught by check %s" % (label, want), want in fails, "failed checks: %s" % fails)
        ok_all = ok_all and (want in fails)
    return ok_all


def main():
    print("test-xfun-units: %s" % BCOMP)
    b = read(BCOMP)
    c = read(XFUN_C)
    if "--list-comments" in sys.argv:   # every handler whose comment is not the name above it (the legacy ones are in LEGACY)
        d = parse(b, c)
        for a, hh in zip(d["names"], d["handlers"]):
            if a != hh[1]:
                print("  %s: %s" % (a, hh[1]))
        return
    d, ok = run_checks(b, c)
    row("the tables are not empty (%d intrinsics, %d handlers, %d rows, %d XF_ constants)" % (len(d["names"]), len(d["handlers"]), len(d["rows"]), len(d["xf_defs"])),
        len(d["names"]) > 100 and len(d["rows"]) >= 19 and len(d["xf_defs"]) >= 18)
    if "--selftest" in sys.argv:
        selftest()
    print("\ntest-xfun-units: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
