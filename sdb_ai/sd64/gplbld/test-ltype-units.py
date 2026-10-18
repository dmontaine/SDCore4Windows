#!/usr/bin/env python3
#
# test-ltype-units.py - L-type dictionary links (QM4 Fixes 7) read off the sources: what $linkref can answer, that both
# of its callers handle every answer, and the order of the steps in the I-type compiler that make a link work.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-ltype-units.py [--selftest]
#
# No sudo, no install, no sd.  Exit 0 every check held, 1 one did not.  --selftest breaks a copy of the sources in six
# ways and expects each to be caught by exactly the check that owns it.  It cannot say that a link works: that is
# sandbox-ltype.py.
#
# START-HISTORY:
# 17 Oct 26 dm  Written with $linkref.  The compiler and the query processor each turn the answer of $linkref (a status
#               from 1 to 6) into a message, and nothing ties the two lists to the routine: a status one caller forgot
#               would let a bad link go on as if it had resolved.
# END-HISTORY
#
# WHAT IT CHECKS
#   1. every status $linkref sets (2 to 6) has a case in icomp's link.reference and in qproc's L case, with a message
#      that exists.
#   2. icomp: link.reference is reached only after the dictionary reads and the VOC read have failed, before the F-number
#      test; the F-number test is nested (BASIC does not stop at the first false condition of an AND).
#   3. icomp: a link makes its TRANS() source and goes to splice.nested.source, the label inside the nested I-type case.
#   4. icomp: in.trans takes link.dict.pending before it reads the file name expression.
#   5. qproc: the L case asks $linkref, then compiles the reference itself with $icomp (no TRANS() of its own).

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
GPL = os.path.join(SD64, "sdsys", "gpl.bp")
PATHS = {"linkref": os.path.join(GPL, "linkref"), "icomp": os.path.join(GPL, "icomp"), "qproc": os.path.join(GPL, "qproc")}
MSGDIR = os.path.join(SD64, "sdsys", "messages")

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


def between(text, start_re, end_re):
    m = re.search(start_re, text)
    if not m:
        return ""
    e = re.search(end_re, text[m.end():])
    return text[m.start():m.end() + e.start()] if e else text[m.start():]


def checks(src):
    res = []
    lr = src["linkref"]
    statuses = sorted(set(int(n) for n in re.findall(r"status = (\d)", lr)) - {0, 1})
    ic = between(src["icomp"], r"(?m)^link\.reference:", r"(?m)^\* ={20,}\s*\n\* ERROR")
    qp = between(src["qproc"], r"(?m)^\s*case type = 'L'", r"(?m)^\s*case 1\s*\n\s*display sysmsg\(7275")
    bad = []
    for st in statuses:
        for name, text in (("icomp", ic), ("qproc", qp)):
            m = re.search(r"case link\.status = %d\s*\n(?:\s*\*[^\n]*\n)*\s*(?:err\.msg = |display )sysmsg\((\d+)" % st, text)
            if not m or not os.path.isfile(os.path.join(MSGDIR, m.group(1))):
                bad.append("%s status %d%s" % (name, st, "" if not m else " (message %s missing)" % m.group(1)))
    res.append(("1. every status $linkref sets (%s) has a case with an existing message in icomp and in qproc" % statuses,
                statuses == [2, 3, 4, 5, 6] and not bad, "%s" % bad))

    i = src["icomp"]
    lookup = i.find("read field.rec from @voc, token.string else")
    link = i.find("if index(token.string, '%', 1) then goto link.reference")
    ftest = i.find("if len(u.token.string) > 1 and u.token.string[1,1] = 'F' then")
    res.append(("2a. link.reference is reached after the VOC read has failed and before the F-number test",
                0 <= lookup < link < ftest, "positions: voc read %d, link %d, F test %d" % (lookup, link, ftest)))
    res.append(("2b. the F-number test is nested: no condition tests a number and adds to it in the same AND",
                ftest >= 0 and not re.search(r"u\.token\.string\[1,1\] = 'F'[^\n]*~", i), "the F test is a single condition again"))

    lrb = between(i, r"(?m)^link\.reference:", r"(?m)^\* ={20,}\s*\n\* ERROR")
    nested = i.find("splice.nested.source:")
    case_i = i.find('case type = "I"  ;* Nested I-type')
    res.append(("3. link.reference makes a TRANS() source and goes to splice.nested.source, which is inside the nested I-type case",
                "nested.source = 'TRANS('" in lrb and "goto splice.nested.source" in lrb and 0 <= case_i < nested < i.find("max.nested.tokens = 200") and i.count("splice.nested.source:") == 1,
                "label at %d, case at %d" % (nested, case_i)))

    tr = between(i, r"(?m)^in\.trans:", r"(?m)^\*\*\* TRIM\(\)")
    res.append(("4. in.trans takes link.dict.pending (and clears it) before it reads the file name expression, and only for a link",
                0 <= tr.find("token = tkn.lbr and link.dict.pending # ''") < tr.find("ins link.dict.pending before trans.stack<1>") < tr.find("link.dict.pending = ''") < tr.find("gosub expr"),
                "in.trans: %s" % tr[:80].replace("\n", " ")))

    res.append(("5. qproc's L case asks $linkref and compiles the reference itself with $icomp; it writes no TRANS()",
                0 <= qp.find("call $linkref(") < qp.find("call $icomp(") and "item.expression(item.index) = token" in qp and not re.search(r"item\.expression\(item\.index\) = [^\n]*TRANS", qp),
                "qproc L case: %s" % qp[:80].replace("\n", " ")))
    return res


def selftest(src):
    ok_all = True
    i, q = src["icomp"], src["qproc"]
    muts = [
        ("qproc leaving status 5 unhandled", "qproc", q.replace("                  display sysmsg(7272, link.detail) ;* Link item xx not found\n", "                  null\n", 1), "1."),
        ("icomp reading the link before the VOC fallback", "icomp",
         i.replace("if index(token.string, '%', 1) then goto link.reference", "").replace("read field.rec from @voc, token.string else", "if index(token.string, '%', 1) then goto link.reference\n                     read field.rec from @voc, token.string else", 1), "2a."),
        ("the F-number test written as one AND again", "icomp",
         i.replace("u.token.string[1,1] = 'F' then", "u.token.string[1,1] = 'F' ~\n and num(u.token.string[2,99]) then", 1), "2b."),
        ("link.reference not splicing", "icomp", i.replace("goto splice.nested.source\n\n* ====", "goto error\n\n* ====", 1), "3."),
        ("in.trans reading the file name before the pending dictionary", "icomp",
         i.replace("ins link.dict.pending before trans.stack<1>\n            link.dict.pending = ''\n            gosub expr", "gosub expr\n            ins link.dict.pending before trans.stack<1>\n            link.dict.pending = ''", 1), "4."),
        ("qproc writing a TRANS() of its own again", "qproc", q.replace("item.expression(item.index) = token\n            s = link.attr<1>", "item.expression(item.index) = 'TRANS(':token:')'\n            s = link.attr<1>", 1), "5."),
    ]
    for label, key, text, want in muts:
        if text == src[key]:
            row("selftest: %s" % label, False, "the mutation changed nothing")
            ok_all = False
            continue
        s2 = dict(src)
        s2[key] = text
        fails = [name.split(" ")[0] for name, ok, _ in checks(s2) if not ok]
        got = want in fails
        row("selftest: %s is caught by check %s" % (label, want), got, "failed checks: %s" % fails)
        ok_all = ok_all and got
    return ok_all


def main():
    print("test-ltype-units: %s" % PATHS["linkref"])
    src = {k: read(p) for k, p in PATHS.items()}
    for name, ok, detail in checks(src):
        row(name, ok, detail)
    if "--selftest" in sys.argv:
        selftest(src)
    print("\ntest-ltype-units: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
