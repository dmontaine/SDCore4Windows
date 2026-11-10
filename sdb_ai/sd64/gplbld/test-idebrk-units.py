#!/usr/bin/env python3
"""test-idebrk-units.py - the IDE's breakpoints handed to the debugger (S.98 H2), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-idebrk-units.py
  python3 .../test-idebrk-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 2 Nov 26.

THE RULES HELD HERE are the ones a screen cannot show: the IDE arms the named common /idebrk/ (idebrk.h) only when the record on the disk is the text in the tab, and a
session that died with a run armed is forgotten at the next start; the debugger takes the hand-over only in a session with a terminal, marks it taken before it does
anything else, compares the program's source path BEFORE it clears either list of breakpoints, keeps a line only when the kernel says a statement begins there, runs on
only when there is a mark to run to, and writes the live list back on every way out; the kernel compares the RUNNING program's id with a breakpoint's and answers
BREAKPOINT 7 with STATUS(); the memo's mark cell is the IDE's alone (SCREEN MEMO never sets bpon) and only a program tab gets it.

***WHAT THIS IS AND IS NOT.***  It reads gpl.bp/debug, ide, sl_memo, idebrk.h and gplsrc/op_debug.c as text.  It cannot say a mark is drawn or the debugger stops on it:
that is sandbox-idebrk.py (B0-B8).  --selftest mutates the sources one way per check and requires each mutant to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GPL = os.path.abspath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp"))
SRC = os.path.abspath(os.path.join(HERE, os.pardir, "gplsrc"))
FILES = {"debug": os.path.join(GPL, "debug"), "ide": os.path.join(GPL, "ide"), "sl_memo": os.path.join(GPL, "sl_memo"),
         "idebrk.h": os.path.join(GPL, "idebrk.h"), "op_debug.c": os.path.join(SRC, "op_debug.c")}


def code(src, c=False):
    """the source without whole-line comments (BASIC '*', C '/* ... */' blocks and '//' lines are left for C: a C check names code that cannot be in a comment)"""
    if c:
        return re.sub(r"/\*.*?\*/", "", src, flags=re.S)
    return "\n".join(l for l in src.splitlines() if not l.lstrip().startswith("*"))


def label(src, name):
    """the body of a BASIC label: from 'name:' to the first 'return' at three spaces"""
    m = re.search(r"^%s:\s*\n(.*?)^   return\b" % re.escape(name), src, re.S | re.M)
    return m.group(1) if m else ""


def pos(text, pat, start=0):
    m = re.compile(pat, re.M).search(text, start)
    return m.start() if m else -1


def others_mention_bpon():
    hits = []
    for f in sorted(os.listdir(GPL)):
        if f in ("ide", "sl_memo"):
            continue
        p = os.path.join(GPL, f)
        if os.path.isfile(p):
            try:
                if "bpon" in code(open(p, errors="replace").read()):
                    hits.append(f)
            except OSError:
                pass
    return hits


def checks(s, bpon_elsewhere=None):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    d = code(s["debug"])
    i = code(s["ide"])
    m = code(s["sl_memo"])
    k = code(s["op_debug.c"], c=True)

    armed = pos(d, r"^\s*gosub ibk\.armed\b")
    apply_ = pos(d, r"^\s*if ib\.on then\s*\n\s*gosub ibk\.apply\b")
    ck("D1 the debugger asks ibk.armed and calls ibk.apply only inside 'if ib.on', after it", armed >= 0 and apply_ > armed, "armed %d, apply %d" % (armed, apply_))

    ba = label(d, "ibk.armed")
    ck("D2 ibk.armed: never for a phantom, and only for a run the IDE armed (IBK.K.ARMED)", "not(phantom)" in ba and re.search(r"ibk\.mode = IBK\.K\.ARMED then ib\.on = @true", ba), ba[:200])

    re_init = pos(d, r"^\s*if ibk\.mode \+ 0 = IBK\.K\.ARMED then debug\.initialised = @false")
    init = pos(d, r"^\s*if not\(debug\.initialised\) then gosub initialise")
    ck("D8 a run the IDE armed clears debug.initialised BEFORE the debugger decides whether to initialise (an IDE session never passes CPROC's reset: a run-on in the 2nd run never stopped)",
       0 <= re_init < init, "reset %d, initialise %d" % (re_init, init))

    bp = label(d, "ibk.apply")
    first = bp.strip().splitlines()[0] if bp.strip() else ""
    same = pos(bp, r"gosub ibk\.same")
    notsame = pos(bp, r"if not\(ib\.eq\) then")
    idle_ret = pos(bp, r"ibk\.mode = IBK\.K\.IDLE[^\n]*\n(?:[^\n]*\n){0,2}?\s*return", notsame if notsame >= 0 else 0)
    clear = pos(bp, r"gosub dbg\.breakpoint\(BRK\$CLEAR, 0\)")
    ck("D3 ibk.apply marks the hand-over taken (LIVE) as its first statement", first.startswith("ibk.mode = IBK.K.LIVE"), first)
    ck("D4 ...compares the source paths, and on a difference goes back to IDLE and returns, all BEFORE it clears the breakpoints",
       0 <= same < notsame < idle_ret < clear, "same %d, differ %d, idle+return %d, clear %d" % (same, notsame, idle_ret, clear))
    add = pos(bp, r"gosub dbg\.breakpoint\(BRK\$ADD\.LINE, ib\.n\)")
    st = pos(bp, r"if status\(\) then", add if add >= 0 else 0)
    clr = pos(bp, r"gosub dbg\.breakpoint\(BRK\$CLR\.LINE, ib\.n\)", st if st >= 0 else 0)
    ck("D5 ...keeps a line only when the kernel's STATUS() says a statement begins there, and takes it out again otherwise", 0 <= add < st < clr, "add %d, status %d, clr %d" % (add, st, clr))
    run = pos(bp, r"gosub dbg\.breakpoint\(BRK\$RUN, 0\)")
    guard = pos(bp, r"if ibk\.go # 0 and ib\.nset > 0 and bitand\(event, 3\) = 0 then")
    ck("D6 ...runs on (BRK$RUN) only inside the test that there is a mark to run to and the order to go", 0 <= guard < run, "guard %d, run %d" % (guard, run))
    for lab in ("abort.debug", "stop.debug"):
        body = label(d, lab)
        ck("D7 %s writes the live list back (ibk.sync) before it ends the program" % lab, 0 <= pos(body, r"gosub ibk\.sync") < pos(body, r"gosub dbg\.stop"), body[:160])

    ia = label(i, "bk.arm")
    ck("I1 bk.arm sets IDLE first and ARMED only inside the test that the record on the disk is the tab's text (bx t)",
       ia.strip().startswith("ibk.mode = IBK.K.IDLE") and 0 <= pos(ia, r"k = 't' : u") < pos(ia, r"if bk\.rec = bx\{k\} then") < pos(ia, r"ibk\.mode = IBK\.K\.ARMED"),
       ia[:200])
    it = label(i, "bk.take")
    ck("I2 bk.take takes the marks back only from a run the debugger took (LIVE) and leaves the common IDLE",
       re.search(r"if ibk\.mode \+ 0 = IBK\.K\.LIVE and bk\.u # '' then", it) and re.search(r"ibk\.mode = IBK\.K\.IDLE\s*\n\s*bk\.u = ''\s*$", it.rstrip() + "\n", re.M), it[-200:])
    ck("I3 the IDE forgets an armed run at its start (one a session left behind is not handed to the next debugger)",
       re.search(r"^\s*if ibk\.mode \+ 0 # IBK\.K\.LIVE then ibk\.mode = IBK\.K\.IDLE", i, re.M))
    dbg = pos(i, r"^\s*case cmd = 'debug'\s*$")
    seq = [pos(i, p, dbg) for p in (r"gosub bk\.arm", r"execute 'debug '", r"gosub bk\.take", r"gosub retake\.screen")] if dbg >= 0 else [-1]
    ck("I4 F7: bk.arm before the debugger is run, bk.take after it and before the screen is taken back", dbg >= 0 and all(a >= 0 for a in seq) and seq == sorted(seq), repr(seq))
    bf = label(i, "bk.form")
    ck("I5 bk.form gives the mark cell (bpon) to a program tab ('source') only, and starts it off", re.search(r"mw\{'bpon'\} = 0", bf) and
       0 <= pos(bf, r"if bx\{k\} = 'source' then") < pos(bf, r"mw\{'bpon'\} = 1"), bf[:200])

    hits = others_mention_bpon() if bpon_elsewhere is None else bpon_elsewhere
    ck("M1 the memo reads bpon as w{'bpon'} + 0 (SCREEN MEMO, which never sets it, gets no mark cell) and no program but the IDE and the memo names it",
       re.search(r"bpon = w\{'bpon'\} \+ 0", m) and hits == [], repr(hits))

    ck("K1 the kernel compares the RUNNING program's id with a breakpoint's (not the id of the last stop)",
       "obj_hdr->id == breakpoint_list[i].id" in k and "debug_id == breakpoint_list[i].id" not in k)
    ck("K2 BREAKPOINT 7 leaves STATUS() 1 only when a statement begins on that very line",
       re.search(r"process\.status\s*=\s*\(\(debug_line_start\(obj_hdr, n, &line\) >= 0\) && \(line == n\)\) \? 1 : 0;", k))

    h = code(s["idebrk.h"])
    consts = {c.lower() for c in re.findall(r"\$define\s+(\S+)", h)}
    names = {n.lower() for n in re.findall(r"\bibk\.[a-z]+\b", h)}
    ck("H1 no constant of idebrk.h names a variable of its common in another case (SD BASIC folds case in names)", names and not (consts & names), repr(consts & names))
    return out


def mutants(s):
    res = []

    def mut(name, f, old, new):
        if old not in s[f]:
            res.append((name, None))
            return
        t = dict(s)
        t[f] = s[f].replace(old, new, 1)
        res.append((name, t))

    mut("D1 apply called without the armed test", "debug", "   if ib.on then\n      gosub ibk.apply", "   if 1 then\n      gosub ibk.apply")
    mut("D2 a phantom is handed the breakpoints", "debug", "ibk.armed:\n   ib.on = @false\n   if not(phantom) then", "ibk.armed:\n   ib.on = @false\n   if 1 then")   # the label's own test: debug has others
    mut("D3 LIVE is set after the path test", "debug", "ibk.apply:\n   ibk.mode = IBK.K.LIVE", "ibk.apply:\n   ibk.out = ibk.out")
    mut("D4 the lists are cleared before the paths are compared", "debug", "   ib.pa = program.src(idx)\n   ib.pb = ibk.path\n   gosub ibk.same\n",
        "   gosub dbg.breakpoint(BRK$CLEAR, 0)\n   ib.pa = program.src(idx)\n   ib.pb = ibk.path\n   gosub ibk.same\n")
    mut("D5 a line is kept without the kernel's answer", "debug", "                     if status() then           ;* the kernel found",
        "                     if 1 then           ;* the kernel found")
    mut("D6 the run goes on with no mark", "debug", "if ibk.go # 0 and ib.nset > 0 and bitand(event, 3) = 0 then", "if ibk.go # 0 and bitand(event, 3) = 0 then")
    mut("D7 abort.debug no longer writes the list back", "debug", "abort.debug:\n   gosub ibk.sync", "abort.debug:\n   null")
    mut("D8 an armed run no longer restarts the debugger", "debug", "   if ibk.mode + 0 = IBK.K.ARMED then debug.initialised = @false", "   if 0 then debug.initialised = @false")
    mut("I1 armed without the disk test", "ide", "               if bk.rec = bx{k} then", "               if 1 then")
    mut("I2 bk.take from a run that was not taken", "ide", "if ibk.mode + 0 = IBK.K.LIVE and bk.u # '' then", "if bk.u # '' then")
    mut("I3 an armed run survives the IDE's start", "ide", "if ibk.mode + 0 # IBK.K.LIVE then ibk.mode = IBK.K.IDLE", "if 0 then ibk.mode = IBK.K.IDLE")
    mut("I4 bk.arm after the debugger ran", "ide", "            gosub bk.arm\n            bk.first = @false\n", "            bk.first = @false\n")
    mut("I5 every tab gets the mark cell", "ide", "   mw{'bpon'} = 0\n   mw{'bp'} = ''\n", "   mw{'bpon'} = 1\n   mw{'bp'} = ''\n")
    mut("M1 the memo turns the mark cell on by default", "sl_memo", "bpon = w{'bpon'} + 0", "bpon = 1")
    mut("K1 the kernel compares the last stop's id again", "op_debug.c", "(obj_hdr->id == breakpoint_list[i].id)", "(debug_id == breakpoint_list[i].id)")
    mut("K2 BREAKPOINT 7 says 1 for any line", "op_debug.c", "&& (line == n)) ? 1 : 0;", ") ? 1 : 1;")
    mut("H1 a constant spelt as a variable of the common", "idebrk.h", "$define IBK.K.IDLE      0", "$define IBK.MODE      0")
    return res


def main():
    s = {}
    for name, p in FILES.items():
        if not os.path.isfile(p):
            print("test-idebrk-units: CANNOT RUN - no %s at %s" % (name, p))
            return 2
        s[name] = open(p, errors="replace").read()
    for name, p in FILES.items():
        print("%-10s %s" % (name, p))
    if "--selftest" in sys.argv:
        base = checks(s)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated source already fails:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(s)
        for name, t in ms:
            if t is None:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n for n, ok, _ in checks(t, bpon_elsewhere=[]) if not ok]
            print("  [%s] %s%s" % ("caught" if caught else "MISSED", name, "  (%d check(s) failed)" % len(caught) if caught else ""))
            bad += 0 if caught else 1
        print("test-idebrk-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    res = checks(s)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail)[:300] + ")"))
        fails += 0 if ok else 1
    print("test-idebrk-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
