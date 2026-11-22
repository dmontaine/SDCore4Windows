#!/usr/bin/env python3
"""test-tkrestart-units.py - the restart box's audit line and when tool.config offers it (RELEASE_1.1 390, Linux S.301).

Linux took our row 382's restart box as its S.301 and added two points, carried here 22 Nov 2026:
  R1  $tk_restart writes an audit line each time a restart is asked for, "sd restart app=<the page> status=asked", lower case, BEFORE
      the restart step (VM sit15, 22 Nov: written after it, the line was lost - our restart step returns only once SD is stopping, and
      the audit writer and the session go with it; Linux's helper returns first, so Linux writes its one line after); a restart that
      could not be started adds "status=refused"; the page's name is taken before $tk_close.
  R2  tool.config offers the box only when the file and the running SD then differ (the row's own * mark, pdiff): a value set back to
      what SD runs with needs no restart.
Linux's own test-tkrestart-units.py drives its sd-elevate sd-restart, which Windows has not; this is the Windows form, the same file in
both Windows products (each one's tk_restart restarts SD its own way: Core restart-sd.ps1 -Detach, Solo sd-solo -restart).
--selftest breaks a copy of each program in each guarded way (the live files are not touched) and every break must be caught.
Exit 0 every row passed, 1 a row failed (or a mutant was missed), 2 nothing to read.

START-HISTORY:
22 Nov 26  Written for RELEASE_1.1 390.
END-HISTORY
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GPLBP = os.path.normpath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp"))
# 22 Nov 26 (VM sit15): the "asked" line is written BEFORE the restart step - written after it, the line was lost, because our restart step
# returns only once SD is stopping and the audit writer and the session go with it - and a refusal adds a second, "refused", line after it.
AUDIT = "void kernel(K$AUDIT, 'sd restart app=' : downcase(app) : ' status=asked')"
REFUSED = "if rc # 0 then void kernel(K$AUDIT, 'sd restart app=' : downcase(app) : ' status=refused')"


def read(name):
    p = os.path.join(GPLBP, name)
    if not os.path.isfile(p):
        return None
    with open(p, encoding="latin-1") as h:
        return h.read()


def code(text):
    """The program's lines without whole-line comments."""
    return "\n".join(l for l in text.split("\n") if not l.lstrip().startswith("*"))


def checks(tkr, cfg):
    """[(id, name, ok)] for the two programs' texts."""
    out = []
    c = code(tkr)
    pa = c.find("rs = ps_script_out(ps, @true)")
    pu = c.find(AUDIT)
    pr = c.find(REFUSED)
    pw = c.find("if rc = 0 then")
    out.append(("R1a", "tk_restart writes the sd restart audit line (asked) once, and a refused line only when the restart was not started",
                c.count("'sd restart app='") == 2 and c.count(AUDIT) == 1 and c.count(REFUSED) == 1))
    out.append(("R1b", "the asked line is written BEFORE the restart step (after it, it was lost: VM sit15), the refused one after its answer",
                0 <= pu < pa < pr < pw))
    pc = c.find("call $tk_close(ctx)")
    pp = c.find("app = ctx<TK.C.APP>")
    out.append(("R1c", "the page's name is taken from its context before $tk_close", 0 <= pp < pc and "$include tk.h" in c))
    g = code(cfg)
    out.append(("R2a", "tool.config asks $tk_restart only when the file and the running SD now differ",
                # the old form as a STATEMENT on a line of its own (line 881's inline "(if k.eff = 'restart' then ' until ...')" is an expression)
                "if k.eff = 'restart' and differs then" in g and re.search(r"(?m)^\s*if k\.eff = 'restart' then\s*$", g) is None
                and "if rj > 0 then differs = pdiff<rj>" in g and g.count("call $tk_restart(") == 1))
    return out


MUTANTS = [
    ("the asked line removed", "tk", lambda t: t.replace(AUDIT, "null")),
    ("the asked line moved after the restart step (the sit15 defect)", "tk",
     lambda t: t.replace("   " + AUDIT + "\n", "", 1).replace("   rc = rs<1>\n", "   rc = rs<1>\n   " + AUDIT + "\n", 1)),
    ("the refused line written whatever the answer", "tk", lambda t: t.replace(REFUSED, REFUSED.replace("if rc # 0 then ", ""), 1)),
    ("the page name taken after $tk_close", "tk",
     lambda t: t.replace("   app = ctx<TK.C.APP>\n   call $tk_close(ctx)", "   call $tk_close(ctx)\n   app = ctx<TK.C.APP>", 1)),
    ("tool.config asks whether or not the value differs", "cfg", lambda t: t.replace("if k.eff = 'restart' and differs then", "if k.eff = 'restart' then", 1)),
]

tkr = read("tk_restart")
cfg = read("tool_config")
if tkr is None or cfg is None:
    print("test-tkrestart-units: CANNOT RUN - no tk_restart or tool_config under " + GPLBP)
    sys.exit(2)
print("test-tkrestart-units: " + GPLBP)
failed = 0
for cid, name, ok in checks(tkr, cfg):
    print("  [%s] %s %s" % ("PASS" if ok else "FAIL", cid, name))
    failed += 0 if ok else 1
if "--selftest" in sys.argv:
    missed = 0
    for name, which, fn in MUTANTS:
        t2, c2 = (fn(tkr), cfg) if which == "tk" else (tkr, fn(cfg))
        changed = (t2 != tkr) or (c2 != cfg)
        caught = changed and not all(ok for _, _, ok in checks(t2, c2))
        print("  [%s] %s" % ("caught" if caught else "MISSED", name))
        missed += 0 if caught else 1
    print("selftest: %d caught, %d missed" % (len(MUTANTS) - missed, missed))
    failed += missed
print("test-tkrestart-units: %s" % ("PASSED" if failed == 0 else "FAILED (%d)" % failed))
sys.exit(0 if failed == 0 else 1)
