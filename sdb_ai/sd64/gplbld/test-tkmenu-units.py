#!/usr/bin/env python3
# test-tkmenu-units.py - the toolkit's menu bar ($tk_menubar) and F1's list of keys, read off the source as text (S.88 phase 5, F0a, 30 Oct 2026; owner decisions of 29 Oct 2026).
#
# What it holds:
#   M1  $tk_menubar is $internal, catalogued once as $tk_menubar, takes SEVEN arguments, and every call of it in gpl.bp passes seven (a call with fewer stops at run time)
#   M2  it RUNS NOTHING (owner decision 25): no execute, no kernel call, no file statement, no $tk_run or $tk_confirm - it returns an action's id and the key that action has, and the
#       page's own handler does the work, so every gate stays with the handler
#   M3  its menus come only from the key table ($tk_keys 'menus') and the key of a chosen action from $tk_keys 'keyof'; the only key names it knows are f10, esc and alt-
#   M4  a page with no menu rows has no bar and loses nothing: it returns before it draws or reads a key
#   M5  op key: F10 and Alt-letter open a menu; Esc opens the first menu ONLY when the page says nothing of its own is open (the Esc rule: a page closes its own state first); any other
#       key is not the bar's
#   M6  op draw writes only when something differs (width, generation, epoch, pane, menus: ctx<TK.C.BAR>), and tells $tk_frame to write the right end of row 0 again by clearing
#       last.top of the SAME common block - it does not touch ctx<TK.C.GEN>, which a page counts for itself (a bar that bumped it could land on the value the page sets after a resize)
#   M7  a run: init and draw, the start menu set AFTER them, run, the screen context put back, the bar's record and last.top set, 'act' only when an entry was chosen, 'none' otherwise
#   M8  a click is the bar's only for a left press on the menu row; a column with no title is used up ('none'), a title opens its menu
#   M9  Alt-letter picks the menu by the letter marked with & (the first letter without one), in either case, and never a submenu (a title that begins with >)
#   M10 tk.h: TK.C.BAR is slot 27, the slots 1 to 26 are where they were, and no slot is defined twice
#   M11 F1 lists the keys: $tk_frame keeps the key table, the pane and the epoch in common /tkreg/ on every call; $tk_close clears all three; $tk_help declares the same block, asks
#       $tk_keys 'keylist' only while an app is drawing, and shows message 12249 above the page's help text, every line cut to the box
#   M12 message 12249 exists and is one line
#
# FREE CHECK: no install, no sd.     python3 .../test-tkmenu-units.py        python3 .../test-tkmenu-units.py --selftest [--from=N]
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BP = os.environ.get("BPDIR", os.path.normpath(os.path.join(HERE, "..", "sdsys", "gpl.bp")))
MSG = os.path.normpath(os.path.join(BP, "..", "messages"))
NAMES = ("tk_menubar", "tk_frame", "tk_close", "tk_help", "tk.h")


def read(p):
    with open(p, encoding="latin-1") as f:
        return f.read()


def code(t):
    out = []
    for ln in t.split("\n"):
        s = ln.lstrip()
        if s.startswith("*") or not s.strip():
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln).rstrip())
    return "\n".join(out)


def ordered(t, *needles):
    pos = -1
    for n in needles:
        i = t.find(n, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def label(src, name):
    m = re.search(r"(?m)^%s:\n" % re.escape(name), src)
    if not m:
        return ""
    rest = src[m.end():]
    n = re.search(r"(?m)^[A-Za-z][A-Za-z0-9.]*:$|^end$", rest)
    return rest[:n.start()] if n else rest


def load():
    s = {n: read(os.path.join(BP, n)) for n in NAMES}
    s["calls"] = {os.path.basename(p): code(read(p)) for p in glob.glob(os.path.join(BP, "*")) if os.path.isfile(p) and not p.endswith(".h")}
    p = os.path.join(MSG, "12249")
    s["m11244"] = read(p) if os.path.exists(p) else None
    return s


def checks(s):
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    mb = code(s["tk_menubar"])
    fr = code(s["tk_frame"])
    cl = code(s["tk_close"])
    hp = code(s["tk_help"])
    th = s["tk.h"]

    calls = []
    for fn, src in s["calls"].items():
        for m in re.finditer(r"\$tk_menubar\(([^)]*)\)", src):
            if fn != "tk_menubar":
                calls.append((fn, m.group(1)))
    wrong = [(fn, a) for fn, a in calls if len([x for x in a.split(",")]) != 7]
    ck("M1 $tk_menubar is $internal, catalogued once, takes seven arguments, and every call passes seven", "$internal\nsubroutine tk_menubar(op, ctx, keys, pane, a, b, c)\n$catalog $tk_menubar" in mb
       and sum(1 for src in s["calls"].values() if "$catalog $tk_menubar" in src) == 1 and not wrong, repr(wrong))

    bad = [w for w in (r"(?m)^\s*(execute|os\.execute|sh|write|writev|writeu|delete|deletelist|open|openseq|openpath|read|readv|readu|readseq|writeseq|chain|perform)\b", r"\bkernel\(", r"\$tk_run", r"\$tk_confirm") if re.search(w, mb)]
    ck("M2 it runs nothing: no execute, kernel call, file statement, $tk_run or $tk_confirm - the page's own handler does the work (owner decision 25)", not bad, repr(bad))

    names = set(re.findall(r"'([a-z0-9-]+)'", mb))
    # 3 Nov 26 (S.88 K7/K8, track D): the bar also answers F2 (the finder) and Shift-F10 (the context menu) - the owner's
    # "Tab panes, F2 finder" - and no other key of a page's; a page that binds either itself still wins (M5)
    ck("M3 the menus come from $tk_keys 'menus' and the key of the chosen action from $tk_keys 'keyof'; the key names it knows are f10, esc, alt-, f2 and shift-f10",
       "call $tk_keys('menus', keys, '', menus, pane, '', '')" in mb and "call $tk_keys('keyof', keys, r, pane, kn, '', '')" in mb
       and "nm = 'f10'" in mb and "nm = 'esc'" in mb and "nm[1, 4] = 'alt-'" in mb and "nm = 'f2'" in mb and "nm = 'shift-f10'" in mb
       and not (names & {"ctrl-q", "f1", "enter", "tab", "ctrl-s"}), repr(sorted(names)))

    ck("M4 a page with no menu rows returns before it draws or reads a key (after the phantom test, before the op is chosen)",
       ordered(mb, "c = ''", "if system(25) then return", "gosub make.menus", "if nmenu = 0 then return", "begin case", "case op = 'draw'"), mb[:300])

    ok = label(mb, "run.bar")
    kb = re.search(r"case op = 'key'\n(.*?)case op = 'click'", mb, re.S)
    kb = kb.group(1) if kb else ""
    ck("M5 op key: F10 starts on the first menu, Alt and a letter on the menu it marks, Esc on the first menu only when busy is off, F2 the finder, "
       "Shift-F10 the context menu; a key the page binds to an action of its own in this pane wins over all of them; anything else leaves start 0 and takes nothing",
       ordered(kb, "start = 0", "case nm = 'f10'", "start = 1", "case nm = 'esc'", "if not(busy) then", "gosub skip.quit", "case len(nm) = 5 and nm[1, 4] = 'alt-'",
               "gosub find.title", "case nm = 'f2'", "start = -1", "case nm = 'shift-f10'", "start = -2", "if start # 0 then",
               "call $tk_keys('action', keys, nm, pane, pa, '', '')", "if pa # '' and pa # 'menu' then start = 0",
               "case start > 0", "gosub run.bar", "case start = -1", "gosub run.palette", "case start = -2", "gosub run.context"), kb[:300])

    pb = label(mb, "paint.bar")
    sq = label(mb, "skip.quit")
    ck("M5b Esc does not land on Quit: skip.quit opens the first menu whose first entry (value 2, sub-value 3 = the action id) is not quit, and leaves menu 1 when every menu begins with it", ordered(sq, "for k = 1 to nmenu", "if menus<k, 2, 3> # 'quit' then", "start = k", "exit", "next k", "return") and ordered(kb, "case nm = 'esc'", "gosub skip.quit"), sq[:200])
    ck("M6 draw: a signature of width, generation, epoch, pane and menus; nothing is written when it is the same as ctx<TK.C.BAR>; after a draw it records it and clears last.top; ctx<TK.C.GEN> is never assigned",
       "sig = ctx<TK.C.W> : '/' : ctx<TK.C.GEN> : '/' : ctx<TK.C.EPOCH> : '/' : convert(@fm : @vm : @sm, '|~^', menus)" in code(label(mb, "bar.sig")) and ordered(pb, "gosub bar.sig", "if sig = ctx<TK.C.BAR> then return", "call $sl_menu('init'", "call $sl_menu('draw'", "ctx<TK.C.BAR> = sig", "last.top = ''")
       and "common /tkframe/ last.stat, last.keys, last.bord, last.top, last.gen, last.geo" in mb and "common /tkframe/ last.stat, last.keys, last.bord, last.top, last.gen, last.geo" in fr and not re.search(r"ctx<TK\.C\.GEN>\s*=", mb), pb[:300])

    ck("M7 a run: init, draw, the start menu after them, run, the context put back, the bar's record and last.top, then 'act' with the action and its key only when an entry was chosen, else 'none'",
       ordered(ok, "call $sl_menu('init', w, scr, '', r)", "call $sl_menu('draw', w, scr, '', r)", "w<SL.W.S1> = start", "call $sl_menu('run', w, scr, '', r)", "call $sl_scr('put', scr)", "ctx<TK.C.BAR> = sig", "last.top = ''",
               "if r # '' then", "call $tk_keys('keyof'", "c = 'act' : @fm : r : @fm : kn : @fm : (if kn = '' then 'act:' : r else kn)", "end else", "gosub no.answer"), ok[:300])

    cb = re.search(r"case op = 'click'\n(.*?)case op = 'open'", mb, re.S)
    cb = cb.group(1) if cb else ""
    ck("M8 a click is the bar's only for a left press on the menu row; the title under it opens, a column with no title is used up ('none')",
       ordered(cb, "a<1> = 'press' and a<2> = 1 and a<4> + 0 = ctx<TK.C.YMENU> + 0", "call $sl_menu('hit', w, scr, a<3> + 0, start)", "if start > 0 then gosub run.bar else gosub no.answer"), cb[:300])

    ft = label(mb, "find.title")
    ck("M9 Alt-letter: the letter after the & of a title (the first letter without one), either case, never a submenu (a title that begins with >)",
       ordered(ft, "want = upcase(nm[5, 1])", "t = menus<k, 1>", "if t[1, 1] # '>' then", "p = index(t, '&', 1)", "mn = t[p + 1, 1]", "mn = t[1, 1]", "if upcase(mn) = want then", "start = k", "exit"), ft[:300])

    slots = re.findall(r"\$define TK\.C\.([A-Z0-9]+)\s+(\d+)", th)
    nums = [int(n) for _, n in slots]
    ck("M10 tk.h: TK.C.BAR is slot 27, slots 1 to 26 are defined once each, in place, and nothing else uses 27 (TK.C.AIROW is slot 28, 1 Nov 26; TK.C.FOCI is slot 29, S.99 1 Nov 26)", dict(slots).get("BAR") == "27" and dict(slots).get("AIROW") == "28"
       and dict(slots).get("FOCI") == "29" and sorted(nums) == list(range(1, 30)), repr(slots[-4:]))

    ck("M11 F1's list of keys: $tk_frame keeps keys, pane and epoch in common /tkreg/ before it draws; $tk_close clears all three; $tk_help declares the same block, asks 'keylist' only while an app is drawing "
       "(epoch) and shows message 12249 and the lines above the page's text, each cut to the box",
       ordered(fr, "common /tkreg/ reg.keys, reg.pane, reg.epoch", "reg.keys = keys", "reg.pane = pane", "reg.epoch = ctx<TK.C.EPOCH>", "lw = ctx<TK.C.W>", "screen text")
       and ordered(cl, "common /tkreg/ reg.keys, reg.pane, reg.epoch", "screen close", "reg.keys = ''", "reg.pane = ''", "reg.epoch = ''")
       and ordered(hp, "common /tkreg/ reg.keys, reg.pane, reg.epoch", "if reg.epoch + 0 > 0 then call $tk_keys('keylist', reg.keys, reg.pane, rg, '', '', '')", "if rg # '' then", "kb<-1> = sysmsg(12249)",
                   "kb<-1> = '  ' : rg<p>[1, wrapw - 2]", "kb<-1> = ''", "for p = 1 to dcount(lines, @fm)", "call $tk_wrap(lines<p>, wrapw, pieces)",
                   "if kb # '' and dcount(kb, @fm) + dcount(body, @fm) <= scr<SL.S.H> - 14 then body = kb : @fm : body", "screen msgbox body"), "")

    na = label(mb, "no.answer")
    ck("M13 when nothing was chosen the answer is 'none' with NO name to dispatch on (<4> null), so a page's loop takes it as no key and its status message stays", ordered(na, "c = 'none' : @fm : @fm : @fm", "return"), na[:200])
    ck("M13b the answer for nothing chosen has no fourth field", "'none' : @fm : @fm : @fm : " not in na, na[:200])

    mk = label(mb, "make.menus")
    ck("M14 the menus come in the table's order, File (with or without its & mark) first and Help last", ordered(mk, "call $tk_keys('menus', keys, '', menus, pane, '', '')", "if nmenu > 1 then", "tt = change(menus<k, 1>, '&', '')",
                                                                                                     "case tt = 'File'\n               mn.first<-1> = menus<k>", "case tt = 'Help'\n               mn.last<-1> = menus<k>", "case 1\n               mn.mid<-1> = menus<k>",
                                                                                                     "menus = mn.first", "if mn.mid # '' then menus<-1> = mn.mid", "if mn.last # '' then menus<-1> = mn.last"), mk[:300])

    ck("M12 message 12249 exists and is one line", s["m11244"] is not None and len(s["m11244"].rstrip("\n").split("\n")) == 1 and s["m11244"].strip() != "", repr(s["m11244"]))
    return rows


def sub(src, old, new):
    if src.count(old) != 1:
        raise SystemExit("selftest: the old text occurs %d times, not once:\n%s" % (src.count(old), old[:120]))
    return src.replace(old, new)


MUTANTS = [
    ("a call of the bar with six arguments", "tk_close", "   screen close\n", "   screen close\n   call $tk_menubar('draw', ctx, '', '', '', '')\n", "M1"),
    ("the bar executes the action", "tk_menubar", "      call $tk_keys('keyof', keys, r, pane, kn, '', '')\n", "      call $tk_keys('keyof', keys, r, pane, kn, '', '')\n      execute r\n", "M2"),
    ("the bar asks a kernel key", "tk_menubar", "      call $tk_keys('keyof', keys, r, pane, kn, '', '')\n", "      call $tk_keys('keyof', keys, r, pane, kn, '', '')\n      x = kernel(K$AI.STATUS, 0)\n", "M2"),
    ("the bar knows a key of its own", "tk_menubar", "            case nm = 'f10'\n               start = 1\n", "            case nm = 'f10' or nm = 'ctrl-q'\n               start = 1\n", "M3"),
    ("the bar draws before it knows it has menus", "tk_menubar", "   gosub make.menus\n   if nmenu = 0 then return                            ;* a page", "   gosub make.menus\n   null                                                ;* a page", "M4"),
    ("Esc always opens the bar", "tk_menubar", "               if not(busy) then\n                  start = 1\n                  gosub skip.quit\n               end", "               start = 1\n               gosub skip.quit", "M5"),
    ("Esc lands on Quit", "tk_menubar", "                  gosub skip.quit\n", "", "M5b"),
    ("the Quit skip tests the wrong action", "tk_menubar", "if menus<k, 2, 3> # 'quit' then", "if menus<k, 2, 3> # 'refresh' then", "M5b"),
    ("any key opens the bar", "tk_menubar", "            case len(nm) = 5 and nm[1, 4] = 'alt-'\n               gosub find.title\n", "            case 1\n               start = 1\n", "M5"),
    ("the bar draws every time", "tk_menubar", "   if sig = ctx<TK.C.BAR> then return\n", "", "M6"),
    ("the bar bumps the generation", "tk_menubar", "   ctx<TK.C.BAR> = sig\n   last.top = ''                                       ;* row 0 was written whole", "   ctx<TK.C.BAR> = sig\n   ctx<TK.C.GEN> = ctx<TK.C.GEN> + 1\n   last.top = ''                                       ;* row 0 was written whole", "M6"),
    ("the right end of row 0 is not written again", "tk_menubar", "   last.top = ''                                       ;* row 0 was written whole: the app's name and the audience at its right end are written again by the next $tk_frame\n", "", "M6"),
    ("the signature holds field marks (ctx grows on every pass)", "tk_menubar", "convert(@fm : @vm : @sm, '|~^', menus)", "menus", "M6"),
    ("the start menu is set before init", "tk_menubar", "   call $sl_menu('draw', w, scr, '', r)\n   w<SL.W.S1> = start\n   call $sl_menu('run', w, scr, '', r)", "   w<SL.W.S1> = start\n   call $sl_menu('draw', w, scr, '', r)\n   call $sl_menu('run', w, scr, '', r)", "M7"),
    ("a person who leaves is reported as a choice", "tk_menubar", "   if r # '' then\n      call $tk_keys('keyof', keys, r, pane, kn, '', '')", "   if 1 then\n      call $tk_keys('keyof', keys, r, pane, kn, '', '')", "M7"),
    ("a click on any row opens a menu", "tk_menubar", "a<1> = 'press' and a<2> = 1 and a<4> + 0 = ctx<TK.C.YMENU> + 0", "a<1> = 'press' and a<2> = 1", "M8"),
    ("a click beside the titles opens the first menu", "tk_menubar", "if start > 0 then gosub run.bar else gosub no.answer", "if start > 0 then gosub run.bar else start = 1 ; gosub run.bar", "M8"),
    ("a left menu answers with no name to dispatch on", "tk_menubar", "   c = 'none' : @fm : @fm : @fm\n", "   c = 'none'\n", "M13"),
    ("a left menu answers with the name none, which a page's catch-all runs", "tk_menubar", "   c = 'none' : @fm : @fm : @fm\n", "   c = 'none' : @fm : @fm : @fm : 'none'\n", "M13b"),
    ("an action with no key gets no name to dispatch on", "tk_menubar", " : @fm : (if kn = '' then 'act:' : r else kn)", "", "M7"),
    ("the menus are in the table's order only", "tk_menubar", "            case tt = 'File'\n               mn.first<-1> = menus<k>\n", "            case tt = 'File' and 0\n               mn.first<-1> = menus<k>\n", "M14"),
    ("Help is not put last", "tk_menubar", "            case tt = 'Help'\n               mn.last<-1> = menus<k>\n", "            case tt = 'Help' and 0\n               mn.last<-1> = menus<k>\n", "M14"),
    ("a submenu title can be reached by Alt", "tk_menubar", "      if t[1, 1] # '>' then\n", "      if 1 then\n", "M9"),
    ("Alt-letter is case sensitive", "tk_menubar", "         if upcase(mn) = want then", "         if mn = want then", "M9"),
    ("slot 27 is not the bar's", "tk.h", "$define TK.C.BAR       27 ", "$define TK.C.BAR       28 ", "M10"),
    ("the frame forgets to keep the keys", "tk_frame", "   reg.keys = keys\n", "", "M11"),
    ("the close leaves the keys", "tk_close", "   reg.keys = ''                                  ;* F0a: and no app has keys to list\n", "", "M11"),
    ("F1 lists keys with no app drawing", "tk_help", "if reg.epoch + 0 > 0 then call $tk_keys", "if 1 then call $tk_keys", "M11"),
    ("F1's key lines are not cut to the box", "tk_help", "rg<p>[1, wrapw - 2]", "rg<p>", "M11"),
    ("F1 shows the keys even when the box would not fit the screen", "tk_help", "if kb # '' and dcount(kb, @fm) + dcount(body, @fm) <= scr<SL.S.H> - 14 then body = kb : @fm : body", "if kb # '' then body = kb : @fm : body", "M11"),
]


def run(over=None):
    s = load()
    if over:
        s.update(over)
    return checks(s)


def selftest(first=0):
    base = run()
    bad0 = [n.split()[0] for n, ok, _ in base if not ok]
    print("selftest: the unchanged tree fails %d check(s): %s" % (len(bad0), " ".join(bad0) or "none"))
    if bad0:
        return 1
    s0 = load()
    bad = 0
    for name, key, old, new, want in MUTANTS[first:]:
        if s0[key].count(old) != 1:
            print("  [FAIL] selftest: %s: the old text occurs %d times in %s, not once" % (name, s0[key].count(old), key))
            bad += 1
            continue
        over = {key: s0[key].replace(old, new)}
        if key == "tk_close" and name.startswith("a call of the bar"):
            over["calls"] = dict(s0["calls"])
            over["calls"]["tk_close"] = code(over[key])
        failed = [n.split()[0] for n, ok, _ in run(over) if not ok]
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        bad += 0 if hit else 1
    print("selftest: %s" % ("every mutant was caught" if bad == 0 else "%d problem(s)" % bad))
    return 0 if bad == 0 else 1


def main(argv):
    for n in NAMES:
        if not os.path.exists(os.path.join(BP, n)):
            print("test-tkmenu-units: no such program %s" % n)
            return 2
    if "--selftest" in argv:
        first = 0
        for a in argv:
            if a.startswith("--from="):
                first = int(a[len("--from="):])
        return selftest(first)
    rows = run()
    bad = 0
    for n, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", n, "" if ok or not detail else "   <- " + detail[:300]))
        bad += 0 if ok else 1
    print("test-tkmenu-units: %d checks, %d failed" % (len(rows), bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
