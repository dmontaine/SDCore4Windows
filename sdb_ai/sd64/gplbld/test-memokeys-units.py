#!/usr/bin/env python3
# test-memokeys-units.py - the editor's keys of the memo area (S.88 D2, 29 Oct 2026), read off the source of sl_memo and ide as text.  FREE CHECK: no install, no sd.
#   K1  edkeys is an opt-in: sl_memo reads w{'edkeys'} once into ek, every one of the five new cases is guarded by `and ek` (a user program's SCREEN MEMO never gets them), only the
#       IDE sets the flag, and nothing else in gpl.bp does
#   K2  the four movement keys (Ctrl-Home, Ctrl-End, Ctrl-Left, Ctrl-Right) are cases BEFORE `case ro` (a readonly area moves), Ctrl-Del is AFTER it (a readonly area does not delete)
#   K3  Ctrl-Home is line 1 column 1, Ctrl-End the end of the last line; Ctrl-Left / Ctrl-Right are the word code of Ctrl-P / Ctrl-U (blanks, then the word) and cross a line end
#   K4  Ctrl-Del is one undo step of the kind 'delword' (snap.push BEFORE the lines change), deletes the selection if there is one, the blanks and the word at the cursor otherwise,
#       joins the next line at the end of a line, and ends with want = cx and the mark cleared
#   K5  without the flag these keys are not the area's: the final `case 1` answers 'unhandled'
# The behaviour on a screen is sandbox-memokeys.py's (written and run 2 Nov 26: green 11 of 11 under xterm's sequences; never run red, the keys predate it); sandbox-realkeys.py is
# the decoding row.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-memokeys-units.py
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-memokeys-units.py --selftest
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.environ.get("BPDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp")))
NEW_KEYS = ("ctrl-home", "ctrl-end", "ctrl-right", "ctrl-left", "ctrl-del")


def read(name):
    with open(os.path.join(BP, name), encoding="latin-1") as f:
        return f.read()


def strip(src):
    out = []
    for l in src.split("\n"):
        if l.lstrip().startswith("*"):
            continue
        out.append(re.sub(r";\*.*$", "", l).rstrip())
    return "\n".join(out)


def case_block(text, key):
    """the lines of `case key = '<key>' and ek` up to the next case line at the same indent"""
    m = re.search(r"(?m)^( *)case key = '%s' and ek\n" % re.escape(key), text)
    if not m:
        return None
    ind = m.group(1)
    rest = text[m.end():]
    n = re.search(r"(?m)^%scase " % ind, rest)
    return rest[:n.start()] if n else rest


def checks(s):
    rows = []

    def ck(i, ok, detail=""):
        rows.append((i, "", bool(ok), detail))

    memo, ide = strip(s["sl_memo"]), strip(s["ide"])
    others = [os.path.basename(p) for p in glob.glob(os.path.join(BP, "*")) if os.path.basename(p) not in ("sl_memo", "ide")
              and "'edkeys'" in strip(open(p, encoding="latin-1", errors="replace").read())]
    ck("K1 edkeys is an opt-in of the program: read once (ek = w{'edkeys'} + 0), each new case needs `and ek`, only the IDE sets it",
       memo.count("w{'edkeys'}") == 1 and "ek = w{'edkeys'} + 0" in memo and all(("case key = '%s' and ek" % k) in memo for k in NEW_KEYS) and not re.search(r"case key = 'ctrl-(home|end|left|right|del)'\s*\n", memo)
       and ide.count("mw{'edkeys'} = 1") == 1 and not others, repr(others))
    ro = memo.find("      case ro\n")
    pos = {k: memo.find("case key = '%s' and ek" % k) for k in NEW_KEYS}
    ck("K2 the movement keys come before `case ro` and Ctrl-Del after it", ro > 0 and all(0 < pos[k] < ro for k in NEW_KEYS[:4]) and pos["ctrl-del"] > ro, repr((ro, pos)))
    top, end = case_block(memo, "ctrl-home"), case_block(memo, "ctrl-end")
    ck("K3a Ctrl-Home is line 1 column 1 and Ctrl-End the end of the last line", top is not None and "cy = 1" in top and "cx = 1" in top and end is not None and "cy = n" in end and "cx = len(lines<n>) + 1" in end,
       repr((top, end)))
    fwd, back = case_block(memo, "ctrl-right"), case_block(memo, "ctrl-left")
    ck("K3b Ctrl-Right and Ctrl-Left are the blanks-then-word code of Ctrl-U and Ctrl-P, and cross a line end",
       fwd is not None and "while cx <= len(ln) and ln[cx, 1] = ' '" in fwd and "while cx <= len(ln) and ln[cx, 1] # ' '" in fwd and "if cy < n then" in fwd
       and back is not None and "while cx > 1 and ln[cx, 1] = ' '" in back and "while cx > 1 and ln[cx - 1, 1] # ' '" in back and "if cy > 1 then" in back, repr((fwd, back)))
    dw = case_block(memo, "ctrl-del")
    ok = dw is not None
    if ok:
        i = [dw.find(x) for x in ("kind = 'delword'", "gosub snap.push", "if has.sel then", "gosub del.sel", "ce = cx", "lines<cy> = ln[1, cx - 1] : ln[ce, len(ln)]", "del lines<cy + 1>", "want = cx", "my = 0 ; mx = 0")]
        ok = all(x >= 0 for x in i) and i == sorted(i)
    ck("K4 Ctrl-Del is one undo step 'delword' made BEFORE the lines change: the selection, else the blanks and the word, else a join at the end of a line; then want = cx and no mark", ok, repr(dw))
    tail = memo[memo.rfind("      case 1\n"):] if "      case 1\n" in memo else ""
    ck("K5 without the flag the keys fall to `case 1`, which answers unhandled", "ret = 'unhandled' : @fm : key" in tail, tail[:120])
    ins = case_block(memo, "ins")
    ck("K6 overwrite and auto-indent (29 Oct 26): `ov` and `ai` are read from w{'over'} and w{'autoindent'}; Ins (with edkeys, before `case ro`) flips w{'over'} and is no undo step; a typed character replaces the one under the cursor only in overwrite mode, "
       "not over a selection and not at the end of a line; Return with auto-indent begins the new line with the blanks before the cursor (never more than stand before it) and puts the cursor after them",
       "ov = w{'over'} + 0" in memo and "ai = w{'autoindent'} + 0" in memo and ins is not None and "w{'over'} = (if ov then 0 else 1)" in ins and "snap" not in ins and 0 < memo.find("case key = 'ins' and ek") < ro
       and "if ov and kind = 'type' and cx <= len(ln) then" in memo and "ln[1, cx - 1] : key : ln[cx + 1, len(ln)]" in memo
       and "while nb < cx - 1 and ln[nb + 1, 1] = ' '" in memo and "rest = space(nb) : rest" in memo and "cx = nb + 1" in memo and 0 <= memo.find("if ai then") < memo.find("rest = space(nb) : rest"),
       repr(ins))
    dfm = ""
    m = re.search(r"(?m)^do\.format:\n(.*?)(?=^do\.goto:)", ide, re.S)
    if m:
        dfm = m.group(1)
    pos = [dfm.find(x) for x in ("gosub ed.get", "if bx{k} # 'source' then", "fq.quiet = 1", "call !format(ed.t, fm.res, bn<cb>, ed.tab, @false, fm.err)", "fq.quiet = 0", "if fm.err > 0 then",
                                 "if (fm.res : '|') = (ed.t : '|') then", "ed.new = fm.res", "gosub ed.set", "msg = sysmsg(12787, ed.tab)")]
    ck("K7 Build > Format (29 Oct 26): only a program (kind source) of a tab that may be changed; !format() runs in QUIET mode (fq.quiet set just before the call and cleared just after), with the tab width as its indent; "
       "a problem leaves the text alone, an unchanged text says so, and a changed one goes in through ed.set as ONE undo step (nothing is saved); /fmtq/ is declared once",
       all(x >= 0 for x in pos) and pos == sorted(pos) and ide.count("common /fmtq/ fq.quiet, fq.log") == 1 and "write" not in dfm and "call !format(" in dfm and dfm.count("call !format(") == 1, repr(pos))
    dtw = re.search(r"(?m)^do\.tabwidth:\n(.*?)(?=^\S)", ide, re.S)
    dtw = dtw.group(1) if dtw else ""
    ck("K8 the IDE keeps the three modes: ed.over, ed.auto and ed.tab start at 0, 0 and 3, new.form gives all three to the editor, relayout reads overwrite back from the old editor before the form is made again, "
       "the tab width is a whole number from 1 to 99 (anything else leaves it as it was; 1 to 8 until 9 Nov 26, S.184 stage 3: SED's TABS took more), and the status line shows [overwrite] (12771) only in that mode",
       "ed.over = 0" in ide and "ed.auto = 0" in ide and "ed.tab = 3" in ide and ide.count("mw{'over'} = ed.over") == 2 and ide.count("mw{'autoindent'} = ed.auto") == 2 and ide.count("mw{'tabindent'} = ed.tab") == 2
       and re.search(r"relayout:\n   gosub stash\.current\n   if have\.form then\n.*?ed\.over = ow\{'over'\} \+ 0.*?end\n   screen clear", ide, re.S) is not None
       and "if tw.n < 1 or tw.n > 99 then return" in dtw and "if tw.text = '' or not(num(tw.text)) then return" in dtw and "if mw{'over'} + 0 then t := '  ' : sysmsg(12771)" in ide, repr(dtw[:200]))
    dsel = re.search(r"(?m)^del\.sel:\n(.*?)(?=^\S)", memo, re.S)
    dsel = dsel.group(1) if dsel else ""
    pst = re.search(r"(?m)^paste\.t:\n(.*?)(?=^\S)", memo, re.S)
    pst = pst.group(1) if pst else ""
    ck("K9 a long selection or paste (more than 100 lines) is put together ONCE (the lines before, the new middle, the lines after; no DEL or INS for each line); up to 100 lines the old loops are kept as they were",
       "if ey - sy > 100 then" in dsel and "nl := head : tail" in dsel and "field(lines, @fm, 1, sy - 1)" in dsel and "field(lines, @fm, ey + 1, 99999999)" in dsel and "lines = nl" in dsel and "for i = ey to sy + 1 step -1" in dsel and "del lines<i>" in dsel
       and "if nt > 100 then" in pst and "field(lines, @fm, 1, cy - 1)" in pst and "field(t, @fm, 2, nt - 2)" in pst and "field(lines, @fm, cy + 1, 99999999)" in pst and "lines = nl" in pst and "ins t<nt> : tail before lines<cy + nt - 1>" in pst,
       repr((dsel[:80], pst[:80])))
    return rows


def run():
    s = {"sl_memo": read("sl_memo"), "ide": read("ide")}
    bad = 0
    for i, what, ok, detail in checks(s):
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", i, "" if ok else "   <- " + str(detail)[:300]))
        bad += 0 if ok else 1
    print("\ntest-memokeys-units: %d passed, %d failed" % (len(checks(s)) - bad, bad))
    return 1 if bad else 0


def selftest():
    s0 = {"sl_memo": read("sl_memo"), "ide": read("ide")}
    if any(not ok for _, _, ok, _ in checks(s0)):
        print("selftest: the unchanged tree fails, so a mutant's failure cannot be told from the tree's")
        return 1
    caught = missed = 0

    def mutant(name, prog, old, new):
        nonlocal caught, missed
        s = dict(s0)
        if old not in s[prog]:
            print("  [MISSED] %s: the text to change is not there" % name)
            missed += 1
            return
        s[prog] = s[prog].replace(old, new, 1)
        failing = [i.split()[0] for i, _, ok, _ in checks(s) if not ok]
        if failing:
            print("  [caught] %s (%s)" % (name, ", ".join(failing)))
            caught += 1
        else:
            print("  [MISSED] %s" % name)
            missed += 1

    mutant("Ctrl-Del is for everyone", "sl_memo", "case key = 'ctrl-del' and ek", "case key = 'ctrl-del'")
    mutant("Ctrl-Home is for everyone", "sl_memo", "case key = 'ctrl-home' and ek", "case key = 'ctrl-home'")
    mutant("the IDE does not set the flag", "ide", "mw{'edkeys'} = 1", "mw{'edkeys'} = 0")
    mutant("the flag is not read", "sl_memo", "ek = w{'edkeys'} + 0", "ek = 1")
    mutant("Ctrl-Del before `case ro`", "sl_memo", "      case ro\n", "      case key = 'zz-never'\n         null\n      case ro\n         ret = 'unhandled' : @fm : key\n      case key = 'ctrl-del' and ek\n         null\n      case key = 'zz-never2'\n")
    mutant("Ctrl-End goes to the first line", "sl_memo", "         cy = n\n         cx = len(lines<n>) + 1\n      case key = 'ctrl-right' and ek", "         cy = 1\n         cx = len(lines<n>) + 1\n      case key = 'ctrl-right' and ek")
    mutant("Ctrl-Right does not cross a line end", "sl_memo", "         ln = lines<cy>\n         if cx > len(ln) then\n            if cy < n then\n               cy += 1\n               cx = 1\n            end\n         end else\n            loop\n            while cx <= len(ln) and ln[cx, 1] = ' '\n               cx += 1\n            repeat\n            loop\n            while cx <= len(ln) and ln[cx, 1] # ' '\n               cx += 1\n            repeat\n         end\n      case key = 'ctrl-left' and ek", "         ln = lines<cy>\n         if cx > len(ln) then\n            null\n         end else\n            loop\n            while cx <= len(ln) and ln[cx, 1] = ' '\n               cx += 1\n            repeat\n            loop\n            while cx <= len(ln) and ln[cx, 1] # ' '\n               cx += 1\n            repeat\n         end\n      case key = 'ctrl-left' and ek")
    mutant("Ctrl-Del is no undo step", "sl_memo", "         kind = 'delword'\n         gosub snap.push\n", "         kind = 'delword'\n")
    mutant("Ctrl-Del leaves the mark", "sl_memo", "               end\n            end\n         end\n         want = cx\n         my = 0 ; mx = 0\n      case key = 'ctrl-k'", "               end\n            end\n         end\n         want = cx\n      case key = 'ctrl-k'")
    mutant("overwrite replaces at the end of a line too", "sl_memo", "if ov and kind = 'type' and cx <= len(ln) then", "if ov and kind = 'type' then")
    mutant("overwrite replaces over a selection", "sl_memo", "if ov and kind = 'type' and cx <= len(ln) then", "if ov and cx <= len(ln) then")
    mutant("Ins is an undo step", "sl_memo", "         w{'over'} = (if ov then 0 else 1)", "         gosub snap.push\n         w{'over'} = (if ov then 0 else 1)")
    mutant("auto-indent copies more blanks than stand before the cursor", "sl_memo", "while nb < cx - 1 and ln[nb + 1, 1] = ' '", "while ln[nb + 1, 1] = ' '")
    mutant("auto-indent always on", "sl_memo", "         if ai then\n            * 29 Oct 26 (S.88 D2): the new line", "         if 1 then\n            * 29 Oct 26 (S.88 D2): the new line")
    mutant("Format runs with the dots on", "ide", "   fq.quiet = 1\n   call !format(", "   call !format(")
    mutant("Format leaves quiet mode on", "ide", "   fq.quiet = 0\n   if fm.err > 0 then", "   if fm.err > 0 then")
    mutant("Format changes a program that has problems", "ide", "   if fm.err > 0 then", "   if 0 then")
    mutant("Format is for any record", "ide", "   if bx{k} # 'source' then\n      msg = sysmsg(12784)", "   if 0 then\n      msg = sysmsg(12784)")
    mutant("Format writes the text without an undo step", "ide", "   ed.cy = 0\n   gosub ed.set\n   msg = sysmsg(12787", "   ed.cy = 0\n   ed.mw{'value'} = ed.new\n   msg = sysmsg(12787")
    mutant("the tab width may be 99", "ide", "if tw.n < 1 or tw.n > 8 then return", "if tw.n < 1 or tw.n > 99 then return")
    mutant("a resize forgets overwrite", "ide", "      ed.over = ow{'over'} + 0 ", "      ed.over = 0 ")
    mutant("the selection threshold is 1", "sl_memo", "if ey - sy > 100 then", "if ey - sy > 1 then")
    mutant("the long cut keeps the line after the selection out", "sl_memo", "field(lines, @fm, ey + 1, 99999999)", "field(lines, @fm, ey + 2, 99999999)")
    mutant("the long paste loses the line before", "sl_memo", "field(lines, @fm, 1, cy - 1) : @fm", "field(lines, @fm, 1, cy - 2) : @fm")
    mutant("the long paste drops the last pasted line", "sl_memo", "field(t, @fm, 2, nt - 2)", "field(t, @fm, 2, nt - 3)")
    mutant("the short loops are gone from the paste", "sl_memo", "ins t<nt> : tail before lines<cy + nt - 1>", "null")
    print("selftest: %d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if missed == 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
