#!/usr/bin/env python3
# test-memoundo-units.py - the memo's undo steps are kept as they are (S.88 phase 2, D3; 28 Oct 2026), read off the source of sl_memo as text, and a MODEL of the step encoding run over
# random texts.  The behaviour is sandbox-memoundo.py's (a property test of $sl_memo on 250 random records; WRITTEN, not run); this holds what a runtime row cannot see and what a free
# check can:
#   - a step is cursor line, a blank, cursor place, a blank, then the lines VERBATIM: no CONVERT of field marks, no text mark in the step, nothing searched for in the lines (the blanks
#     are found from the front: INDEX(step, ' ', 2)); the old encoding (field marks to value marks, fields cut at text marks) is gone from the program;
#   - the steps live in the widget, one string each (w{'u' : n}, w{'r' : n}); the counts are read at the top and written by store; the old key 'undo' is read only by the migrator;
#   - Ctrl-Z / Ctrl-Y make the step for the OTHER stack from the text as it is BEFORE the text is replaced, and move the counts;
#   - at most 100 steps and 1,000,000 characters, the oldest dropped first and the newest kept; a new edit ends the redo list; a run of typing is still one step;
#   - 'init' clears both stacks; the 'snap' op pushes a step of a kind that never coalesces and stores; the migrator reads newest-first, empties the old keys and ends the redo list;
#   - (28 Oct 26, the TUI phase 2 review) no other program of gpl.bp writes a memo's 'undo' or 'redo' key: the IDE's AI edit goes on through the 'snap' op (M13, M14).
# AND a model in Python of the step (encode / decode as the source writes them) over 5,000 random texts holding field, value, subvalue and text marks and blanks: the round trip is exact,
# and the OLD encoding (the control) is not - for a large share of them.
# FREE CHECK: no install, no sd.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-memoundo-units.py
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-memoundo-units.py --selftest
import os
import random
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.environ.get("BPDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp")))
FM, VM, SM, TM = "\xfe", "\xfd", "\xfc", "\xfb"


def read(name):
    with open(os.path.join(BP, name), encoding="latin-1") as f:
        return f.read()


def section(text, label):
    """The lines of the BASIC label `label:` (column 0) up to the next label at column 0 or the program's end; None if absent."""
    lines = text.split("\n")
    for i, l in enumerate(lines):
        if l.rstrip() == label + ":":
            out = []
            for l2 in lines[i + 1:]:
                if re.match(r"^[A-Za-z][\w.]*:\s*$", l2) or re.match(r"^end\s*$", l2):
                    break
                out.append(l2)
            return out
    return None


def code(lines):
    out = []
    for l in lines or []:
        s = re.sub(r";\*.*$", "", l).rstrip()
        if s.strip() and not s.lstrip().startswith("*"):
            out.append(s.strip())
    return out


def ordered(text, *parts):
    pos = 0
    for p in parts:
        i = text.find(p, pos)
        if i < 0:
            return False
        pos = i + len(p)
    return True


# ---- the model: the step as the source writes it ----
def enc_new(cy, cx, lines):
    return "%d %d %s" % (cy, cx, lines)


def dec_new(step):
    p = step.index(" ", step.index(" ") + 1)          # INDEX(cur, ' ', 2): the second blank
    return int(step.split(" ")[0]), int(step.split(" ")[1]), step[p + 1:]


def enc_old(cy, cx, lines):
    return "%d%s%d%s%s" % (cy, TM, cx, TM, lines.replace(FM, VM))


def dec_old(step):
    parts = step.split(TM)                               # field(cur, @tm, 3, 99999) is the rest, but the step is cut at every text mark by the 3 fields it reads
    return int(parts[0]), int(parts[1]), TM.join(parts[2:]).replace(VM, FM)


def gen_text(rng):
    alpha = ["a", "b", "X", " ", "0", "_", VM, SM, TM, "\x01", FM, FM, "1", "  "]
    return "".join(rng.choice(alpha) for _ in range(rng.randint(0, 40)))


def model_rows():
    rng = random.Random(20261028)
    bad_new = bad_old = n = 0
    marked = 0
    for _ in range(5000):
        t = gen_text(rng)
        cy, cx = rng.randint(1, 9), rng.randint(1, 80)
        n += 1
        if dec_new(enc_new(cy, cx, t)) != (cy, cx, t):
            bad_new += 1
        try:
            if dec_old(enc_old(cy, cx, t)) != (cy, cx, t):
                bad_old += 1
        except (ValueError, IndexError):
            bad_old += 1
        if any(m in t for m in (VM, SM, TM)):
            marked += 1
    return n, bad_new, bad_old, marked


def checks(src):
    memo = src["sl_memo"]
    cm = "\n".join(code(memo.split("\n")))
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    make = "\n".join(code(section(memo, "snap.make")))
    ck("M1 snap.make: cursor line, a blank, place, a blank, the lines as they are - no CONVERT, no text mark", "snap = cy : ' ' : cx : ' ' : lines" in make, make)
    ck("M1b no CONVERT of field marks and no text mark in the steps' code (snap.make, snap.apply, undo.step, redo.step, snap.add, snap.push)",
       all("convert(" not in "\n".join(code(section(memo, l))) and "@tm" not in "\n".join(code(section(memo, l)))
           for l in ("snap.make", "snap.apply", "undo.step", "redo.step", "snap.add", "snap.push")), "")
    app = "\n".join(code(section(memo, "snap.apply")))
    ck("M2 snap.apply finds the second blank from the front and takes everything after it as the lines, verbatim; the cursor numbers come from the first two fields",
       ordered(app, "sn.p = index(cur, ' ', 2)", "lines = cur[sn.p + 1, len(cur)]", "cy = field(cur, ' ', 1) + 0", "cx = field(cur, ' ', 2) + 0") and "field(cur, ' ', 3" not in app, app)
    und = "\n".join(code(section(memo, "undo.step")))
    ck("M3 Ctrl-Z: the last undo step is taken and emptied, the counts move, the CURRENT text is made into the redo step BEFORE the text is replaced, and the step is applied last",
       ordered(und, "if uk.n < 1 then return", "cur = w{'u' : (uk.b + uk.n)}", "w{'u' : (uk.b + uk.n)} = ''", "uk.t -= len(cur)", "uk.n -= 1", "gosub snap.make", "rk.n += 1", "rk.t += len(snap)",
               "w{'r' : (rk.b + rk.n)} = snap", "gosub snap.apply"), und)
    red = "\n".join(code(section(memo, "redo.step")))
    ck("M4 Ctrl-Y: the same the other way round (the last redo step, the current text onto the undo steps first, applied last)",
       ordered(red, "if rk.n < 1 then return", "cur = w{'r' : (rk.b + rk.n)}", "w{'r' : (rk.b + rk.n)} = ''", "rk.t -= len(cur)", "rk.n -= 1", "gosub snap.make", "uk.n += 1", "uk.t += len(snap)",
               "w{'u' : (uk.b + uk.n)} = snap", "gosub snap.apply"), red)
    add = "\n".join(code(section(memo, "snap.add")))
    ck("M5 at most 100 steps and 8,000,000 characters, the oldest dropped first (blanked, the base moved up) and the newest always kept",
       ordered(add, "uk.n += 1", "uk.t += len(snap)", "w{'u' : (uk.b + uk.n)} = snap", "while uk.n > 100 or (uk.t > 8000000 and uk.n > 1)", "uk.t -= len(w{'u' : (uk.b + 1)})", "w{'u' : (uk.b + 1)} = ''",
               "uk.b += 1", "uk.n -= 1"), add)
    push = "\n".join(code(section(memo, "snap.push")))
    ck("M6 snap.push: a run of typing, bs or del is still one step; the step is made, added, and THEN the redo list ends",
       ordered(push, "if kind = k0 and (kind = 'type' or kind = 'bs' or kind = 'del') then return", "gosub snap.make", "gosub snap.add", "gosub snap.redo.clear"), push)
    rc = "\n".join(code(section(memo, "snap.redo.clear")))
    ck("M6b the redo list ends by blanking every redo step and resetting the three redo counts", ordered(rc, "for sn.i = rk.b + 1 to rk.b + rk.n", "w{'r' : sn.i} = ''", "rk.b = 0 ; rk.n = 0 ; rk.t = 0"), rc)
    sto = "\n".join(code(section(memo, "store")))
    ck("M7 store writes the six counts (ukb ukn ukt rkb rkn rkt); the top of the program reads them and reads the old key only to migrate it, once",
       "w{'ukb'} = uk.b ; w{'ukn'} = uk.n ; w{'ukt'} = uk.t" in sto and "w{'rkb'} = rk.b ; w{'rkn'} = rk.n ; w{'rkt'} = rk.t" in sto
       and "uk.b = w{'ukb'} + 0 ; uk.n = w{'ukn'} + 0 ; uk.t = w{'ukt'} + 0" in cm and "rk.b = w{'rkb'} + 0 ; rk.n = w{'rkn'} + 0 ; rk.t = w{'rkt'} + 0" in cm
       and "if w{'undo'} # '' then gosub snap.legacy" in cm and len(re.findall(r"w\{'undo'\}", cm)) == 3 and "undo =" not in cm and "redo =" not in cm, "uses of w{'undo'}: %d" % len(re.findall(r"w\{'undo'\}", cm)))
    clr = "\n".join(code(section(memo, "snap.clear")))
    ck("M8 'init' clears both stacks (the steps blanked, six counts zero)", "gosub snap.clear" in "\n".join(code(memo.split("case op = 'init'")[1].split("case op = 'draw'")[0].split("\n")))
       and ordered(clr, "for sn.i = uk.b + 1 to uk.b + uk.n", "w{'u' : sn.i} = ''", "for sn.i = rk.b + 1 to rk.b + rk.n", "w{'r' : sn.i} = ''", "uk.b = 0 ; uk.n = 0 ; uk.t = 0", "rk.b = 0 ; rk.n = 0 ; rk.t = 0"), clr)
    snap_op = "\n".join(code(memo.split("case op = 'snap'")[1].split("case op = 'draw'")[0].split("\n"))) if "case op = 'snap'" in memo else ""
    ck("M9 the 'snap' op: a kind that never coalesces and no key before it, then snap.push, then store", ordered(snap_op, "kind = 'snap' ; k0 = ''", "gosub snap.push", "gosub store"), snap_op)
    leg = "\n".join(code(section(memo, "snap.legacy")))
    ck("M10 the migrator: takes the old key and empties it and the old redo key, reads newest first, makes each field a step (value marks back to field marks, the cursor numbers from the text-mark fields), "
       "ends the redo list, and writes the counts",
       ordered(leg, "sn.lg = w{'undo'}", "w{'undo'} = ''", "w{'redo'} = ''", "for sn.k = dcount(sn.lg, @fm) to 1 step -1", "snap = field(sn.s, @tm, 1) : ' ' : field(sn.s, @tm, 2) : ' ' : convert(@vm, @fm, field(sn.s, @tm, 3, 99999))",
               "gosub snap.add", "gosub snap.redo.clear", "w{'ukb'} = uk.b"), leg)
    keys = "\n".join(code(memo.split("case key = 'ctrl-z'")[1].split("case len(key) = 1")[0].split("\n"))) if "case key = 'ctrl-z'" in memo else ""
    ck("M11 Ctrl-Z and Ctrl-Y call the two step routines and nothing else (no src / dst shuffling of one string)", keys.split("\n")[:3] == ["gosub undo.step", "case key = 'ctrl-y'", "gosub redo.step"], keys[:200])
    ck("M12 the old routine and its variables are gone (snap.restore, src, dst, the string 'undo' local)", "snap.restore" not in cm and not re.search(r"\bsrc\b", cm) and not re.search(r"\bdst\b", cm), "")
    # 28 Oct 26 (TUI phase 2 review): the IDE pushed its AI edit's step onto mw{'undo'} in the OLD form, which the memo reads as legacy (value marks back to line ends).  A program
    #   that wants a step of its own calls the memo's 'snap' op; none writes the widget's undo or redo key itself.
    writers = sorted(n for n, t in src.items() if n != "sl_memo" and re.search(r"\{'(undo|redo)'\}\s*=", "\n".join(code(t.split("\n")))))
    ck("M13 no program but sl_memo writes a memo's 'undo' or 'redo' key (a step of a program's own goes on through the memo's 'snap' op); %d programs read" % (len(src) - 1),
       not writers and len(src) > 100, "writers: %s" % writers)
    ide = "\n".join(code((src.get("ide") or "").split("\n")))
    ck("M14 the IDE's AI edit goes on the undo steps through the memo's 'snap' op, before the new value is set",
       ordered(ide, "ai.apply:", "call $sl_memo('snap', mw,", "mw{'value'} = change(ai.new"), "")
    n, bad_new, bad_old, marked = model_rows()
    ck("Y1 model: 5,000 random texts with every mark - the new step decodes to exactly what was encoded (%d bad of %d)" % (bad_new, n), bad_new == 0 and n == 5000, "")
    ck("Y2 model, CONTROL: the old encoding damages many of the same texts (%d of %d; %d held a value, subvalue or text mark) - so Y1 could have failed" % (bad_old, n, marked), bad_old > 1000 and marked > 1000, "")
    return rows


def load():
    """every program of gpl.bp (M13 reads them all), sl_memo among them"""
    src = {}
    for n in sorted(os.listdir(BP)):
        if os.path.isfile(os.path.join(BP, n)) and not n.endswith(".h"):
            src[n] = read(n)
    src["sl_memo"] = read("sl_memo")
    return src


def run():
    rows = checks(load())
    bad = 0
    for name, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail[:300]))
        bad += 0 if ok else 1
    print("test-memoundo-units: %d passed, %d failed" % (len(rows) - bad, bad))
    return 1 if bad or not rows else 0


def selftest():
    src = load()
    if not all(ok for _, ok, _ in checks(src)):
        print("  [FAIL] the real source does not pass")
        return 1
    print("  [ok] the real source passes")
    caught = missed = 0

    def mutant(name, old, new, prog="sl_memo"):
        nonlocal caught, missed
        s = dict(src)
        if s[prog].count(old) != 1:
            print("  [MISSED] %s: the text to change is found %d times" % (name, s[prog].count(old)))
            missed += 1
            return
        s[prog] = s[prog].replace(old, new, 1)
        failing = [n for n, ok, _ in checks(s) if not ok]
        if failing:
            print("  [caught] %s (%s)" % (name, ", ".join(f.split()[0] for f in failing)))
            caught += 1
        else:
            print("  [MISSED] %s" % name)
            missed += 1

    mutant("the old step encoding", "   snap = cy : ' ' : cx : ' ' : lines\n", "   snap = cy : @tm : cx : @tm : convert(@fm, @vm, lines)\n")
    mutant("apply cuts at the third blank", "   lines = cur[sn.p + 1, len(cur)]\n", "   lines = field(cur, ' ', 3, 99999)\n")
    mutant("apply finds the first blank twice", "   sn.p = index(cur, ' ', 2)  ", "   sn.p = index(cur, ' ', 1)  ")
    mutant("cap of steps", "while uk.n > 100 or", "while uk.n > 1000 or")
    mutant("cap of characters", "uk.t > 8000000 and uk.n > 1", "uk.t > 1000000000 and uk.n > 1")
    mutant("newest dropped, not oldest", "      w{'u' : (uk.b + 1)} = ''\n      uk.b += 1\n", "      w{'u' : (uk.b + uk.n)} = ''\n      uk.b += 1\n")
    mutant("redo not ended by a new edit", "   gosub snap.add\n   gosub snap.redo.clear\n   return\n\n* snap goes on", "   gosub snap.add\n   return\n\n* snap goes on")
    mutant("undo replaces the text before making the redo step", "   rk.t += len(snap)\n   w{'r' : (rk.b + rk.n)} = snap\n   gosub snap.apply\n",
           "   rk.t += len(snap)\n   gosub snap.apply\n   w{'r' : (rk.b + rk.n)} = snap\n")
    mutant("redo does not move the count", "   rk.t -= len(cur)\n   rk.n -= 1\n", "   rk.t -= len(cur)\n")
    mutant("init does not clear", "         gosub snap.clear                             ;* nothing to undo or redo\n", "")
    mutant("store forgets the redo counts", "   w{'rkb'} = rk.b ; w{'rkn'} = rk.n ; w{'rkt'} = rk.t\n   return\n\n* Keep", "   return\n\n* Keep")
    mutant("typing runs no longer coalesce", "   if kind = k0 and (kind = 'type' or kind = 'bs' or kind = 'del') then return\n   gosub snap.make", "   gosub snap.make")
    mutant("snap op coalesces", "kind = 'snap' ; k0 = ''", "kind = 'type' ; k0 = 'type'")
    mutant("migrator leaves the old key", "   sn.lg = w{'undo'}\n   w{'undo'} = ''\n", "   sn.lg = w{'undo'}\n")
    mutant("migrator oldest first", "for sn.k = dcount(sn.lg, @fm) to 1 step -1", "for sn.k = 1 to dcount(sn.lg, @fm)")
    mutant("migrator keeps value marks", "convert(@vm, @fm, field(sn.s, @tm, 3, 99999))", "field(sn.s, @tm, 3, 99999)")
    mutant("ctrl-z uses the old shuffle", "      case key = 'ctrl-z'\n         gosub undo.step\n", "      case key = 'ctrl-z'\n         src = undo ; dst = redo\n         gosub undo.step\n")
    # 28 Oct 26 (TUI phase 2 review): the IDE's AI step
    mutant("the IDE pushes its AI step in the old form", "   call $sl_memo('snap', mw, '', '', ai.sr)\n",
           "   mw{'undo'} = mw{'cy'} : @tm : mw{'cx'} : @tm : convert(@fm, @vm, mw{'value'}) : @fm : mw{'undo'}\n", "ide")
    mutant("the IDE's AI edit is no undo step", "   call $sl_memo('snap', mw, '', '', ai.sr)\n", "", "ide")
    mutant("another program writes the memo's redo key", "   mw{'lastop'} = ''\n   mw{'cy'} = ai.line1\n", "   mw{'redo'} = ''\n   mw{'lastop'} = ''\n   mw{'cy'} = ai.line1\n", "ide")
    print("selftest: %d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
