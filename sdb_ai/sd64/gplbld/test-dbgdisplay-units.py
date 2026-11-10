#!/usr/bin/env python3
"""test-dbgdisplay-units.py - the debugger's full-screen display in the IDE's style (S.98 H1), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-dbgdisplay-units.py
  python3 .../test-dbgdisplay-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 1 Nov 26.

WHAT THIS HOLDS.  `sdsys/gpl.bp/debug` lays the display out in ONE routine (set.geometry) that every place which changes the window or
the data area's height calls, so the rows cannot disagree: the bar on row 0, the source and the Autos pane, the rule above the messages,
the messages, the command line, and the foot of three rows (status line, border, function keys) at the bottom.  The function-key row is
made from a key table by $tk_keys and $tk_fkeys, and the table lists keys the command loop acts on, so a label cannot name a key the loop
ignores and a key the loop acts on is not left off the row.  The debugger never calls the toolkit's one-app routines ($tk_open, $tk_close,
$tk_frame, $tk_menubar, $tk_help: their state is per app and the debugger runs inside the IDE's EXECUTE).  The Autos pane costs one
dbg.info call a row, stops when a key is waiting, and uses the line of the previous stop only in the same program (a variable number is
the running frame's).  Resize and WINDOW n use scr.in, not the theme.in / theme.out pair that gave the program's theme away.

***WHAT THIS IS NOT.***  It cannot say the screen is right: that is sandbox-dbgui.py (a pseudo-terminal) and, for the window floor and the
cursor lock, sandbox-ide-small.py.  --selftest mutates the source and requires each mutant to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GPL = os.path.abspath(os.path.join(HERE, os.pardir, "sdsys", "gpl.bp"))
DEBUG = os.path.join(GPL, "debug")
DEBUGH = os.path.join(GPL, "debug.h")

# the function keys the command loop acts on that are NOT on the key row, and why: F11 is the internal trace, the paging keys move the source
NOT_ON_ROW = {"f11", "pgup", "pgdn", "ctrl-pgup", "ctrl-pgdn"}
LOOP_KEYS = {"K$F1": "f1", "K$F2": "f2", "K$F3": "f3", "K$F4": "f4", "K$F5": "f5", "K$F7": "f7", "K$F8": "f8", "K$F9": "f9", "K$F10": "f10", "K$F11": "f11",
             "K$CTRL.F7": "ctrl-f7", "K$CTRL.F8": "ctrl-f8", "K$PAGE.UP": "pgup", "K$PAGE.DOWN": "pgdn",
             "K$CTRL.PAGE.UP": "ctrl-pgup", "K$CTRL.PAGE.DOWN": "ctrl-pgdn"}


def code(src):
    """The lines with full-line comments dropped and a trailing ;* comment cut: a rule that exists only in a comment is no rule."""
    out = []
    for line in src.splitlines():
        if line.lstrip().startswith("*") or line.lstrip().startswith("!"):
            continue
        out.append(re.sub(r"\s;\*.*$", "", line).rstrip())
    return "\n".join(out)


def routine(text, name):
    """The body of the label `name:` up to the next label at column 0 (None if there is no such label)"""
    m = re.search(r"(?m)^%s:[^\n]*\n(.*?)(?=^[A-Za-z][\w.]*:|\Z)" % re.escape(name), text, re.S)
    return m.group(1) if m else None


def checks(src, hdr):
    c = code(src)
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    # the floor and the geometry
    ck("LAY.DEPTH is 43: the toolkit's floor, the foot being three rows below the command line", re.search(r"(?m)^\$define LAY\.DEPTH\s+43\b", c))
    ck("LAY.WIDTH is 140 and AUTO.WIDTH 48: the source keeps 91 columns at the floor", re.search(r"(?m)^\$define LAY\.WIDTH\s+140\b", c) and re.search(r"(?m)^\$define AUTO\.WIDTH\s+48\b", c))
    ck("the gutter is two cells wide (a mark and a blank) and the source row is built that way",
       re.search(r"(?m)^\$define GUTTER\.W\s+2\b", c) and re.search(r"ds\.mark : ' ' : numtxt : tx", c), "")
    sg = routine(c, "set.geometry") or ""
    ck("set.geometry exists and puts the command line four rows from the bottom, then the status line, border and key row below it",
       re.search(r"key\.line = lay\.h - 1\b", sg) and re.search(r"border\.line = lay\.h - 2\b", sg) and re.search(r"status\.line = lay\.h - 3\b", sg)
       and re.search(r"command\.line = lay\.h - 4\b", sg), sg[:300])
    ck("...the messages sit above the command line and the rule above them takes one row from the source",
       re.search(r"data\.area = command\.line - data\.lines\b", sg) and re.search(r"source\.area\.lines = data\.area - 2\b", sg), sg[:300])
    ck("...the Autos pane is AUTO.WIDTH wide at the right and the source is the rest less a column for the rule between them",
       re.search(r"auto\.x = lay\.w - AUTO\.WIDTH\b", sg) and re.search(r"src\.cols = auto\.x - 1\b", sg), sg[:300])
    assigns = [m.group(0) for m in re.finditer(r"(?m)^\s*(command\.line|data\.area|source\.area\.lines|status\.line|border\.line|key\.line)\s*=", c)]
    inside = [m.group(0) for m in re.finditer(r"(?m)^\s*(command\.line|data\.area|source\.area\.lines|status\.line|border\.line|key\.line)\s*=", sg)]
    ck("those rows are assigned in set.geometry and nowhere else", len(assigns) == len(inside) == 6, "all %d, in set.geometry %d" % (len(assigns), len(inside)))
    entry = c.split("found.program:")[0]
    first = entry.find("gosub read.layout")
    ck("the entry lays out: read.layout, then set.geometry (after data.lines is known), before anything is drawn",
       0 <= first < entry.find("gosub set.geometry") < entry.find("return.key"), "")
    for nm in ("relayout", "new.window"):
        body = routine(c, nm) or ""
        ck("%s calls set.geometry" % nm, "gosub set.geometry" in body, body[:200])
    ini = routine(c, "initialise") or ""
    ck("initialise lays out again when $debug.options changed the data area's height (WINDOW n)",
       re.search(r"WINDOW.*?gosub set\.geometry", ini, re.S) is not None, "")

    # the theme is the debugger's for the whole stop
    for nm in ("relayout", "new.window"):
        body = routine(c, nm) or ""
        ck("%s does not call theme.in / theme.out (the pair gave the program's theme away at exit)" % nm, "theme.in" not in body and "theme.out" not in body, body[:200])
    rel = routine(c, "relayout") or ""
    ck("relayout takes the library's context again with scr.in (the cursor lock leaves the screen the lock's)", "gosub scr.in" in rel, rel[:200])
    ti = routine(c, "theme.in") or ""
    # 8 Nov 26 (S.179): the person's own theme first - $sl_theme 'site' answers it, else SCREENTHEME - and no direct read of SCREENTHEME is left
    ck("theme.in takes the person's or the site's theme ($sl_theme 'site') when the program asked for none, and classic when there is none or the terminal cannot show it",
       "$sl_theme('site'" in ti and "config('SCREENTHEME')" not in ti and "'classic'" in ti and "gosub scr.in" in ti, ti[:300])
    scr = routine(c, "scr.in") or ""
    ck("scr.in sets the styles the new panes use (status line, line numbers, header, messages, Autos) and whether the language's colours apply",
       all(w in scr for w in ("rev.attr", "num.attr", "head.attr", "data.attr", "auto.attr", "syn.on")), scr[:300])
    ck("the colours of the language are not used in the classic and mono themes", re.search(r"syn\.on = \(syn\.th # 'classic' and syn\.th # 'mono'\)", scr), scr[:300])

    # the source
    ds = routine(c, "display.source") or ""
    ck("a breakpoint is * in the gutter and wins over >: the > is set only in the ELSE of the breakpoint's locate, in the highlight style",
       re.search(r"setting pos then\s*\n(?:[^\n]*\n)*?\s*ds\.mark = '\*'\s*\n(?:[^\n]*\n)*?\s*end else\s*\n\s*if ds\.cur then\s*\n\s*ds\.mark = '>'\s*\n\s*ds\.mc = highlight\.source\.attr", ds), ds[:200])
    ck("the line about to run is highlighted from end to end and takes no colours of the language",
       re.search(r"if ds\.cur then\s*\n\s*txtcode = str\(highlight\.source\.attr, src\.width\)\s*\n\s*end else", ds)
       and re.search(r"end else[^\n]*\n(?:[^\n]*\n)*?\s*if syn\.lang and syn\.on then", ds), "")
    ck("what the language leaves plain (code n) is the pane's text style", re.search(r"convert 'n' to source\.attr in ds\.sty", ds), "")
    ck("the language is SD BASIC and is looked up once for the stop", len(re.findall(r"\$sl_syntax\('index'", ds)) == 1 and "'sd.basic'" in ds, "")
    ck("the bar has the app and the audience at its right end, from the same message the pages use (12808) or the sign-on name",
       re.search(r"ds\.app = 'debugger  ' : ds\.aud", ds) and "sysmsg(12808)" in ds, "")
    ck("a source row is as wide as the source pane (the rows past the end of the program are space(src.cols))", re.search(r"space\(src\.cols\)", ds), "")

    # the foot and the key row
    pl = routine(c, "paint.layout") or ""
    ck("paint.layout draws the rule between the panes, the rule above the messages and calls paint.foot",
       "call $sl_line('v', 0, vc)" in pl and "data.area - 1" in pl and "gosub paint.foot" in pl, pl[:300])
    pf = routine(c, "paint.foot") or ""
    ck("paint.foot writes the status line, the border and the key row on their rows", all(w in pf for w in ("status.line", "border.line", "key.line", "gosub key.text")), pf[:300])
    kt = routine(c, "key.text") or ""
    table = re.findall(r"call \$tk_keys\('add', kr\.keys, '([^']+)', '([^']*)', '([^']*)', '', ''\)", kt)
    adds = re.findall(r"call \$tk_keys\(", kt)
    ck("every key of the table is added with the seven arguments $tk_keys takes", len(table) == len(adds) and len(table) > 0, "%d adds, %d well formed" % (len(adds), len(table)))
    ck("the row is made by $tk_fkeys with its four arguments", re.search(r"call \$tk_fkeys\(kr\.ctx, kr\.keys, '', key\.row\)", kt), kt[-200:])
    loop_cases = set()
    for m in re.finditer(r"(?:case n = |or n = )(K\$[A-Z0-9.]+)", c):     # 8 Nov 26 (S.180): F10 is acted on by get.input, "case n = 27 or n = K$F10"
        if m.group(1) in LOOP_KEYS:
            loop_cases.add(LOOP_KEYS[m.group(1)])
    keys = {k for k, _, _ in table}
    ck("every key on the row is a key the command loop acts on", keys and keys <= loop_cases, "on the row but not in the loop: %s" % sorted(keys - loop_cases))
    ck("every function key the loop acts on is on the row, but F11 (internal) and the paging keys", (loop_cases - NOT_ON_ROW) <= keys,
       "in the loop, not on the row: %s" % sorted((loop_cases - NOT_ON_ROW) - keys))
    ck("every label on the row is a word and no two keys have one label", all(l.strip() for _, l, _ in table) and len({l for _, l, _ in table}) == len(table), "")
    for bad in ("$tk_open", "$tk_close", "$tk_frame", "$tk_menubar", "$tk_help"):
        ck("the debugger never calls %s (one app's state; it runs inside the IDE's EXECUTE)" % bad, bad not in c, "")

    # the Autos pane
    pa = routine(c, "paint.autos") or ""
    ck("paint.autos keeps its first row for the title and stops filling at the pane's height",
       "au.rows = source.area.lines - 1" in pa and re.search(r"dcount\(au\.names, @fm\) >= au\.rows", pa), pa[:200])
    ck("...the rows are drawn until a key is waiting", re.search(r"for au\.k = 1 to au\.rows\s*\n\s*until keyready\(\)", pa), "")
    ck("...the line of the previous stop is used only when it is a line of the program that is running", re.search(r"field\(au\.at, ':', 1\) \+ 0 = idx", pa), "")
    ck("...the order: this stop's line, the previous stop's, the watched variable, then the locals",
       0 < pa.find("auto.here") < pa.find("watch.var.name") < pa.find("symbols(idx)<1>"), "")
    av = routine(c, "auto.value") or ""
    ck("a value costs one dbg.info call", len(re.findall(r"dbg\.info\(", av)) == 1, "")
    ck("a name that is not a variable of the program is not in the pane (find ... else return)", re.search(r"find au\.nm in symbols\(idx\) setting au\.f, au\.v, au\.sv else return", routine(c, "auto.add.word") or ""), "")
    # when the panes are refreshed
    rp = routine(c, "refresh.panes") or ""
    ck("refresh.panes draws the Autos pane and the status line", "gosub paint.autos" in rp and "gosub paint.foot" in rp, rp)
    ck("the panes are refreshed at the first stop, after each command in the loop, after a relayout and after the user's screen is shown",
       re.search(r"gosub display\.source\s*\n\s*if full\.screen then gosub refresh\.panes", c)
       and re.search(r"if full\.screen and not\(done\) then gosub refresh\.panes\s*\n\s*until done", c)
       and "gosub refresh.panes" in (routine(c, "relayout") or "") and "gosub refresh.panes" in (routine(c, "view") or ""), "")
    ck("a fresh alternate screen is drawn whole (paint.layout) before the messages, at every stop", re.search(r"if alt\.screen then\s*\n\s*gosub paint\.layout\s*\n\s*gosub paint\.data\.area", c), "")

    # the common block: the new variables are at the END, so no earlier one moves
    h = code(hdr)
    names = ("data.attr", "auto.attr", "head.attr", "rev.attr", "num.attr", "auto.here", "auto.prev")
    pos = [h.find(n) for n in names]
    store = h.find("dbg.store")
    ck("debug.h holds the new variables, all after dbg.store, the last variable of the block as it was", store > 0 and all(p > store for p in pos), "dbg.store at %d, new at %s" % (store, pos))
    return out


def mutants(src, hdr):
    res = []

    def sub(label, old, new, h=False, count=1):
        base = hdr if h else src
        if old not in base:
            res.append((label, None, None))
            return
        m = base.replace(old, new, count)
        res.append((label, src if h else m, m if h else hdr))

    sub("the F8 key is left off the row", "   call $tk_keys('add', kr.keys, 'f8', 'line', 'line', '', '')\n", "")
    sub("a key the loop ignores (F9) is on the row", "'f8', 'line', 'line'", "'f9', 'line', 'line'")
    sub("the floor is 42 again", "$define LAY.DEPTH             43", "$define LAY.DEPTH             42")
    sub("the command line is the last row again", "command.line = lay.h - 4", "command.line = lay.h - 1")
    sub("relayout does not lay out again", "   gosub read.layout\n   gosub set.geometry\n   gosub scr.in", "   gosub read.layout\n   gosub scr.in")
    sub("WINDOW n does not lay out again", "   data.lines = new.lines + 0\n   gosub set.geometry\n", "   data.lines = new.lines + 0\n")
    sub("relayout gives the program's theme away again", "   gosub scr.in                          ;* the theme is the debugger's already", "   gosub theme.in\n   gosub theme.out\n   gosub scr.in                          ;* the theme is the debugger's already")
    sub("the debugger opens a toolkit app", "   kr.keys = ''\n", "   kr.keys = ''\n   call $tk_open('debugger', '', kr.ctx, kr.err)\n")
    sub("the line about to run gets the colours of the language", "            if ds.cur then\n               txtcode = str(highlight.source.attr, src.width)\n            end else",
        "            if 0 then\n               txtcode = str(highlight.source.attr, src.width)\n            end else")
    sub("the Autos rows are drawn when a key is waiting too", "   for au.k = 1 to au.rows\n   until keyready()\n", "   for au.k = 1 to au.rows\n")
    sub("the previous stop's line is used in another program", "field(au.at, ':', 1) + 0 = idx and ", "")
    sub("a value costs two calls", "   au.info = dbg.info(1, au.vn)\n", "   au.info = dbg.info(1, au.vn)\n   au.info = dbg.info(1, au.vn)\n")
    sub("a breakpoint no longer wins over >", "               ds.mark = '*'\n               ds.mc = breakpoint.source.attr\n            end else\n               if ds.cur then\n                  ds.mark = '>'\n                  ds.mc = highlight.source.attr\n               end\n            end",
        "               ds.mark = '*'\n               ds.mc = breakpoint.source.attr\n            end\n            if ds.cur then\n               ds.mark = '>'\n               ds.mc = highlight.source.attr\n            end")
    sub("the panes are not refreshed after a command", "      if full.screen and not(done) then gosub refresh.panes", "      if 0 then gosub refresh.panes")
    sub("the new variables are before dbg.store in debug.h", "                   dbg.store,", "                   auto.prev,\n                   dbg.store,", h=True)
    sub("the colours of the language are used in classic too", "syn.on = (syn.th # 'classic' and syn.th # 'mono')", "syn.on = 1")
    return res


def main():
    for p in (DEBUG, DEBUGH):
        if not os.path.isfile(p):
            print("test-dbgdisplay-units: CANNOT RUN - no %s" % p)
            return 2
    src = open(DEBUG, errors="replace").read()
    hdr = open(DEBUGH, errors="replace").read()
    if "--selftest" in sys.argv:
        base = checks(src, hdr)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated source already fails:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(src, hdr)
        for name, msrc, mhdr in ms:
            if msrc is None:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n for n, ok, _ in checks(msrc, mhdr) if not ok]
            if caught:
                print("  [caught] %s  (%d check(s) failed)" % (name, len(caught)))
            else:
                print("  [MISSED] %s" % name)
                bad += 1
        print("test-dbgdisplay-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    print("debug   : %s" % DEBUG)
    res = checks(src, hdr)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail).replace("\n", " | ")[:200] + ")"))
        fails += 0 if ok else 1
    print("test-dbgdisplay-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
