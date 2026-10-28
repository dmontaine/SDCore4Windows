#!/usr/bin/env python3
"""test-tkfaults-units.py - the toolkit faults carried from Linux ec8459b (28 Oct 2026), as invariants read off the source.  Free: no install, no elevation, no sd.

    python test-tkfaults-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads BASIC and message files as text.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A WINDOW IS REFUSED OR WHAT A BOX IS TITLED ON THE SCREEN***: that is
a session on a terminal.  What a text check is for here: the ORDER and the ABSENCE that an edit can move without a compile error.

  F1-F3  the largest window a page is given: a session at 200 by 9999 sat at full CPU for minutes opening the screen of a toolkit page, because the library keeps the screen as one value to a
         row of one array (the cost grows with the square of the height).  $tk_open turns the window away BEFORE it takes the screen, after the minimum and the audience have been asked.
  F4     $tk_confirm's optional sixth argument (the title): VAR.ARGS, tested through UNASSIGNED before it is used, the default "Run this command?" (12817) for both boxes it shows.
  F5     no call of $tk_confirm in this tree has a sixth argument yet (the pages that write a record of their own are Linux's; the argument is carried so that they can be).
  F6     message 12870 ("Press Enter to return") names no screen.

This is Linux's test-tkfaults-units.py reduced to what this tree has: tool.dict, tool.query, tool.bulk and tool.test are not carried (their checks, F7 to F9, are not here).
--selftest breaks each invariant in the way an edit plausibly would and requires the named check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
NAMES = ["tk.h", "tk_open", "tk_confirm"]


def load():
    raw = {}
    for n in NAMES:
        try:
            with open(os.path.join(GPL, n), encoding="latin-1") as f:
                raw[n] = f.read()
        except OSError:
            raw[n] = ""
    for n in (12202, 12817, 12869, 12870, 12956):
        try:
            with open(os.path.join(MSG, str(n)), encoding="latin-1") as f:
                raw["m%d" % n] = f.read()
        except OSError:
            raw["m%d" % n] = ""
    pages = {}
    for f in sorted(os.listdir(GPL)):
        if (f.startswith("tool_") or f.startswith("tk_")) and f not in raw:
            with open(os.path.join(GPL, f), encoding="latin-1") as fh:
                pages[f] = fh.read()
    raw["pages"] = pages
    return raw


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = line.find(";*")
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def squeeze(t):
    return re.sub(r"\s+", " ", t).strip()


def ordered(text, *needles):
    pos = -1
    for n in needles:
        p = text.find(n, pos + 1)
        if p < 0:
            return False
        pos = p
    return True


def arg_count(text, name):
    """the number of top-level arguments of each `call <name>(...)` in TEXT"""
    out = []
    for m in re.finditer(r"call\s+" + re.escape(name) + r"\(", text):
        i, depth, n, q = m.end(), 1, 1, ""
        while i < len(text) and depth:
            c = text[i]
            if q:
                q = "" if c == q else q
            elif c in "'\"":
                q = c
            elif c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
            elif c == "," and depth == 1:
                n += 1
            i += 1
        out.append(n)
    return out


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    th, op_raw, cf_raw = raw["tk.h"], raw["tk_open"], raw["tk_confirm"]
    op, cf = squeeze(strip_bas(op_raw)), squeeze(strip_bas(cf_raw))
    ck("F0", "NULL CASE: tk.h, $tk_open, $tk_confirm and the messages were found and are not trivially short (a check on nothing would pass), and other pages of the toolkit exist to be read",
       len(th) > 1500 and len(op) > 800 and len(cf) > 500
       and all(raw["m%d" % n].strip() for n in (12202, 12817, 12869, 12870, 12956)) and len(raw["pages"]) >= 8,
       "%d %d %d, %d other pages" % (len(th), len(op), len(cf), len(raw["pages"])))

    ck("F1", "tk.h fixes the largest window a page is given: TK.MAXW 500 and TK.MAXH 300, each above the minimum (140 by 43) and defined once",
       re.findall(r"^\$define TK\.MAXW\s+(\d+)\b", th, re.M) == ["500"] and re.findall(r"^\$define TK\.MAXH\s+(\d+)\b", th, re.M) == ["300"]
       and re.search(r"\$define TK\.MINW\s+140\b", th) is not None and re.search(r"\$define TK\.MINH\s+43\b", th) is not None, "")
    ck("F2", "ORDER in $tk_open: a phantom is turned away, the minimum is asked, the audience is asked, THEN the window is asked for its size and the maximum applied, and only then the screen is taken - "
             "a window too big is refused before the screen is taken (taking it is what costs the time) and after the audience (so the administrator-only message is the same at every size)",
       ordered(op, "system(25)", "call $sl_need(", "K$ADMINISTRATOR", "call $sl_window(win.w, win.h)", "TK.MAXW", "TK.MAXH", "screen open", "call $sl_guardmode(")
       and op.count("call $sl_window(win.w, win.h)") == 1, "")
    ck("F3", "the refusal says message 12956 with the app, TK.MAXW, TK.MAXH and the size found, and RETURNS (a test of BOTH dimensions; no number is typed into the program), and the message is the shape of 12202",
       re.search(r"if win\.w > TK\.MAXW or win\.h > TK\.MAXH then err = sysmsg\(12956, app, TK\.MAXW, TK\.MAXH, win\.w : ' by ' : win\.h\) return end", op) is not None
       and not re.search(r"\b(500|300|9999)\b", op)
       and raw["m12956"] == "%1 needs a window of at most %2 columns by %3 lines; this one is %4\n"
       and raw["m12202"].replace("at least", "at most") == raw["m12956"], repr(raw["m12956"]))

    ck("F4", "$tk_confirm is VAR.ARGS with a sixth argument that is only ever read after UNASSIGNED() has been tested, in a nested IF (BASIC does not short-circuit): the default is message 12817 and "
             "the one title is given to BOTH boxes the routine shows (the Run / Cancel box and the box that asks for the name typed)",
       "subroutine tk_confirm(sentence, lines, typed, res, msg, boxtitle) var.args" in cf
       and cf.count("boxtitle") == 4 and ordered(cf, "ttl = sysmsg(12817)", "if not(unassigned(boxtitle)) then if boxtitle # '' then ttl = boxtitle end", "screen msgbox body title ttl buttons", "tt = ttl", "screen ask pr width fw title tt")
       and cf.count("sysmsg(12817)") == 1 and "title sysmsg(12817)" not in cf and " and boxtitle" not in cf and " or boxtitle" not in cf, "")
    bad = []
    seen = 0
    for page, text in raw["pages"].items():
        for n in arg_count(strip_bas(text), "$tk_confirm"):
            seen += 1
            if n != 5:
                bad.append((page, n))
    ck("F5", "every call of $tk_confirm in this tree (%d) has five arguments: the sixth is carried for pages this tree does not have" % seen, seen >= 1 and not bad, repr(bad))

    ck("F6", "message 12870 is 'Press Enter to return' and names no screen (it is said after a command run from the home screen and from a page)",
       raw["m12870"] == "Press Enter to return\n" and "home screen" not in raw["m12870"], repr(raw["m12870"]))
    return rows


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok else "   <- " + detail))
    print("\ntest-tkfaults-units: %d checks, %d failed" % (len(rows), bad))
    return bad


MUTANTS = [
    ("the maximum width is gone", "tk.h", "$define TK.MAXW        500", "$define TK.MAXW        5000", "F1"),
    ("the maximum height is typed into $tk_open", "tk_open", "win.w > TK.MAXW or win.h > TK.MAXH", "win.w > TK.MAXW or win.h > 300", "F3"),
    ("only the width is tested", "tk_open", "if win.w > TK.MAXW or win.h > TK.MAXH then", "if win.w > TK.MAXW then", "F3"),
    ("the size is asked before the audience", "tk_open", "   call $sl_need(app, TK.MINW, TK.MINH, need.msg, '')", "   call $sl_window(win.w, win.h)\n   call $sl_need(app, TK.MINW, TK.MINH, need.msg, '')", "F2"),
    ("the refusal falls through", "tk_open", "      err = sysmsg(12956, app, TK.MAXW, TK.MAXH, win.w : ' by ' : win.h)\n      return\n", "      err = sysmsg(12956, app, TK.MAXW, TK.MAXH, win.w : ' by ' : win.h)\n", "F3"),
    ("the title is read before it is tested", "tk_confirm", "   if not(unassigned(boxtitle)) then\n      if boxtitle # '' then ttl = boxtitle\n   end\n", "   if boxtitle # '' then ttl = boxtitle\n", "F4"),
    ("the second box keeps the old title", "tk_confirm", "      tt = ttl", "      tt = sysmsg(12817)", "F4"),
    ("the routine is no longer VAR.ARGS", "tk_confirm", "boxtitle) var.args", "boxtitle)", "F4"),
    ("message 12870 names the home screen", "m12870", "Press Enter to return", "Press Enter to return to the home screen", "F6"),
    ("message 12956 loses its fourth word", "m12956", "this one is %4", "this one is", "F3"),
]


def selftest():
    raw = load()
    if any(not ok for _, _, ok, _ in checks(raw)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT by the row it names, and match its text once ---")
    for name, where, old, new, want in MUTANTS:
        m = dict(raw)
        key = where
        if m[key].count(old) != 1:
            print("  [FAIL] %s: the text matches %d times, not once" % (name, m[key].count(old)))
            holes += 1
            continue
        m[key] = m[key].replace(old, new)
        failed = [i for i, _, ok, _ in checks(m) if not ok]
        if want in failed:
            print("  [caught] %s (row %s failed)" % (name, want))
        else:
            print("  [MISSED] %s: wanted %s, failed %s" % (name, want, failed))
            holes += 1
    print("\nselftest: %d of %d mutants caught, %d missed" % (len(MUTANTS) - holes, len(MUTANTS), holes))
    return 1 if holes else 0


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(1 if report(checks(load())) else 0)
