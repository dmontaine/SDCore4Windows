#!/usr/bin/env python3
"""test-tkrestart-units.py - the restart box's audit line and when tool.config offers it (RELEASE_1.1 390, Linux S.301).

Linux took our row 382's restart box as its S.301 and added two points, carried here 22 Nov 2026:
  R1  $tk_restart writes ONE audit line each time a restart is asked for, "sd restart app=<the page> status=asked|refused", lower
      case, AFTER the restart script answered (so before SD stops) and before the wait; the page's name is taken before $tk_close.
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
AUDIT = "void kernel(K$AUDIT, 'sd restart app=' : downcase(app) : ' status=' : (if rc = 0 then 'asked' else 'refused'))"


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
    pw = c.find("if rc = 0 then")
    out.append(("R1a", "tk_restart writes exactly one sd restart audit line, asked or refused, the page name in lower case",
                c.count("'sd restart app='") == 1 and pu >= 0))
    out.append(("R1b", "the line is written after the restart script answered and before the wait",
                0 <= pa < pu < pw))
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
    ("the audit line removed", "tk", lambda t: t.replace(AUDIT, "null")),
    ("the audit line moved before the restart script", "tk",
     lambda t: t.replace("   " + AUDIT, "", 1).replace("   rs = ps_script_out(ps, @true)", "   " + AUDIT + "\n   rs = ps_script_out(ps, @true)", 1)),
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
