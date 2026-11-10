#!/usr/bin/env python3
"""test-fieldspane-units.py - the IDE's fields PANE (CED in the IDE, stage 2b, 30 Oct 2026), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-fieldspane-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-fieldspane-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
30 Oct 26 dm  New with stage 2b: F12 shows the engine ($ced_core) in the IDE's form as a pane of the TAB, not a mode of the IDE.
END-HISTORY

WHAT IT HOLDS (gpl.bp/ide).  A tab that shows its fields has bx v<uid> = 1 and an engine state in fvs{e<uid>}.  THE TAB'S TEXT (bx t) IS THE RECORD: the engine's data is that text in another
shape, written back at each change (fields.after / fields.writeback: only when the data differs from the stamp, only after the conversion succeeded, with the token mode worked out again), so
Save, Compile, the recovery copy and the status line's marker never see anything else.  The hidden text area holds an older text: stash.current returns before it reads it, the commands that
work on its text refuse (15998), and Esc, Return and the keys the IDE has no use of go to the pane only while the focus is on it, after every IDE key.  Whatever else changes the text (the
overwrite question's Reload, SED, an AI edit) is noticed by fields.sync once a time round the loop: the same data in another layout only moves the stamp, other data makes the engine again in the
container it was in, and a text that is no record ends the pane (15999) without touching the text.  A resize, a program run and a tab switch put the pane back (fields.form, fields.apply).

***IT RUNS NOTHING, SO IT CANNOT SAY THAT THE PANE WORKS ON A SCREEN***: that is sandbox-recarr.py and sandbox-ide-fields.py.  --selftest breaks each property the way an edit plausibly would
and requires a check to notice.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
NEWMSG = {15995: None, 15998: "ed.read", 15999: "fields.drop"}


def strip(src):
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def label(text, name):
    m = re.search(r"^%s:\n" % re.escape(name), text, re.M)
    if not m:
        return ""
    rest = text[m.end():]
    n = re.search(r"^[a-z][a-z0-9.]*:\s*$", rest, re.M)
    return rest[:n.start()] if n else rest


def ordered(text, *parts):
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def read(path):
    try:
        with open(path, encoding="latin-1") as f:
            return f.read()
    except OSError:
        return ""


def load():
    src = {"ide": read(os.path.join(GPL, "ide"))}
    for n in NEWMSG:
        src["m%d" % n] = read(os.path.join(MSG, str(n)))
    return src


LABELS = ("fields.enter", "fields.leave", "fields.state", "fields.is.on", "fields.view.on", "fields.view.off", "fields.form", "fields.apply", "fields.sync", "fields.sync.tab", "fields.parse",
          "fields.rebuild", "fields.drop", "fields.esc", "fields.key", "fields.after", "fields.writeback", "fields.pull", "fields.fill", "fields.pathtext", "fields.label", "fields.show",
          "stash.current", "status.line", "do.key", "do.act", "focus.to", "indicator.texts", "new.form", "load.current", "close.current", "ed.read", "do.goto", "do.include", "ai.selection",
          "ai.go", "run.cmd", "do.fields")


def checks(src):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    ide = strip(src["ide"])
    L = {n: label(ide, n) for n in LABELS}
    main = ide[: ide.find("apply.theme:")]
    ck("F0", "NULL CASE: the IDE was read and every routine this check reads is there (a check on nothing would pass)", len(ide) > 80000 and all(len(v) > 20 for v in L.values()),
       repr(sorted(k for k, v in L.items() if len(v) <= 20)))

    ck("F1", "the pane's state: fvs{'e' : uid} is the engine's collection and bx v<uid> says the tab shows it; both are made in fields.enter (after the engine's init, with the text stamps h.text, h.from, "
       "h.sig) and both are let go in fields.leave, fields.drop and close.current; the main program makes fvs",
       "fvs = collection()" in main
       and ordered(L["fields.enter"], "call $ced_core('init', fz.st, '', fz.out)", "fz.st{'h.text'} = bx{fz.k1}", "fz.st{'h.from'} = bx{fz.k1}", "fz.st{'h.sig'} = jbuild(fz.c)", "fvs{'e' : fz.u} = fz.st",
               "bx{fz.k1} = 1", "gosub fields.view.on", "ft.id = 'fld'", "gosub focus.to")
       and ordered(L["fields.leave"], "bx{fz.k1} = 0", "fvs{'e' : fz.u} = ''") and ordered(L["fields.drop"], "bx{fz.k1} = 0", "fvs{'e' : fz.u} = ''")
       and ordered(L["close.current"], "k = 'v' : bu<cb>", "bx{k} = 0", "fvs{'e' : bu<cb>} = ''", "del bu<cb>"), "")

    ck("F2", "THE HIDDEN TEXT AREA IS NEVER READ AS THE RECORD: stash.current returns before it reads the area when the tab shows its fields; ed.read (and so Replace, case, Import, Export, Format, ...), "
       "Go to line and Open the include refuse with 15998 before they touch the area; since stage 4 the AI selection explains the selected element through the engine (fields.ai) and the AI line sends a typed request there, "
       "and the other kinds of the AI line (a compile message) refuse with 15998, all before they touch the area",
       ordered(L["stash.current"], "k = 'v' : bu<cb>", "if bx{k} then return", "screen get f, 'ed' returning txt", "bx{k} = txt")
       and all(ordered(L[n], "gosub fields.is.on", "if fv.on then", "msg = sysmsg(15998)", "return", "call $sl_form('find', f, '', 'ed', en)") for n in ("ed.read", "do.goto", "do.include"))
       and ordered(L["ai.selection"], "gosub fields.is.on", "if fv.on then", "fz.op = 'ai.explain'", "gosub fields.ai", "return", "call $sl_form('find', f, '', 'ed', en)")
       and ordered(L["ai.go"], "gosub fields.is.on", "if fv.on then", "if ai.kind = 'ask' then", "fz.op = 'ai.request'", "gosub fields.ai", "msg = sysmsg(15998)", "return", "call $sl_form('find', f, '', 'ed', en)"), "")

    ck("F3", "the keys: every IDE key in do.key comes before the pane's case, which is the LAST case, guarded by the focus being on the table and passing the key on; Return in the table (do.act) "
       "is the engine's Return; Esc (no event) goes to fields.esc, which goes up a level only on the table and not at the top, else the IDE's menu",
       ordered(L["do.key"], "case edata = 'f1'", "case edata = 'ctrl-s'", "case edata = 'f12'", "case edata = 'guardquit'", "case edata = 'mouse'", "case focus.id = 'fld'", "fz.key = edata", "gosub fields.key", "end case")
       and ordered(L["do.act"], "case focus.id = 'ai'", "case focus.id = 'fld'", "fz.key = 'enter'", "gosub fields.key", "case 1")
       and ordered(label(ide, "fields.esc"), "if fv.on and focus.id = 'fld' then", "if fz.st{'path'} # '' then", "fz.key = 'esc'", "gosub fields.key", "return", "cmd = 'menu'", "gosub run.cmd")
       and ordered(main, "gosub fields.sync", "gosub status.line", "screen wait f timeout 1 returning ev then", "gosub fields.esc"), "")

    ck("F4", "fields.key: the keys the pane must not give the engine are dropped (the mouse, Tab, F2, a resize, the cursor lock, and Q: the engine's Q leaves a CED), Alt-T is the engine's F4 (8 Nov 26, "
       "S.179: Ctrl-T is the theme on every page), Left and Backspace are its Esc; the selection comes from the table before the engine is called and fields.after follows",
       ordered(L["fields.key"], "if fz.k = 'mouse' or fz.k = 'tab' or fz.k = 'btab' or fz.k = 'f2' or fz.k = 'resize' or fz.k = 'guardquit' then return", "if upcase(fz.k) = 'Q' then return",
               "if fz.k = 'alt-t' then fz.k = 'f4'", "if fz.k = 'left' or fz.k = 'bs' then fz.k = 'esc'", "gosub fields.state", "gosub fields.pull", "call $ced_core('key', fz.st, fz.k, fz.out)",
               "gosub fields.after"), "")

    ck("F5", "fields.after: the engine has no end of its own here (done, quit.all and req are cleared); the data is written back only when its signature differs from the stamp; a pane that ended "
       "(fields.drop) gives the screen back to the text area before anything is drawn; the engine's message is the IDE's; the table is drawn and the focus kept",
       ordered(L["fields.after"], "fz.st{'done'} = @false", "fz.st{'quit.all'} = @false", "fz.st{'req'} = ''", "fz.sig = jbuild(fz.nc)", "if (fz.sig : '|') # (fz.st{'h.sig'} : '|') then gosub fields.writeback",
               "gosub fields.is.on", "if not(fv.on) then", "gosub load.current", "return", "msg = fz.st{'msg'}", "gosub fields.show", "ft.id = 'fld'", "gosub focus.to"), "")

    ck("F6", "fields.writeback: a record's data is turned into text by $recarr 'from' (data type 2) and a JSON record's by JBUILD with line feeds made into field marks; a conversion that fails puts the engine "
       "back to the TAB'S text (the last that was good) BEFORE anything is assigned to bx t and says 12993; only a conversion that worked assigns the tab's text, clears the cursor, works the token mode out "
       "again and stamps the engine",
       ordered(L["fields.writeback"], "if fz.st{'ftype'} + 0 = 2 then", "call $recarr('from', fz.nc, fz.txt, fz.ok)", "fz.txt = convert(char(10), @fm, jbuild(fz.nc, JB$PRETTY))", "if not(fz.ok) then",
               "fz.txt = bx{fz.k1}", "gosub fields.parse", "gosub fields.rebuild", "fz.st{'msg'} = sysmsg(12993)", "gosub fields.drop", "return", "bx{fz.k1} = fz.txt", "bx{fz.k1} = ''", "gosub set.token.mode",
               "fz.st{'h.text'} = fz.txt", "fz.st{'h.sig'} = fz.sig"), "")

    ck("F7", "fields.sync.tab: the tab's text against the stamp - the same text does nothing; text the pane cannot show ends the pane (fields.drop); the same data in another layout moves the stamp and "
       "leaves the engine alone (a save keeps JBUILD's layout, and the person stays where they were); other data makes the engine again",
       ordered(L["fields.sync.tab"], "fz.txt = bx{fz.k1}", "if (fz.txt : '|') = (fz.st{'h.text'} : '|') then return", "gosub fields.parse", "if not(fz.ok) then", "gosub fields.drop", "return",
               "fz.sig = jbuild(fz.nc)", "if (fz.sig : '|') = (fz.st{'h.sig'} : '|') then", "fz.st{'h.text'} = fz.txt", "return", "gosub fields.rebuild")
       and ordered(L["fields.parse"], "call $recarr('to', fz.txt, fz.nc, fz.ok)", "fz.nc = jparse(convert(@fm, char(10), fz.txt))", "fz.ok = (status() = 0)", "fz.kind = jtype(fz.nc)",
                   "if fz.kind # 'collection' and fz.kind # 'array' then fz.ok = @false", "fz.kind # 'array' then fz.ok = @false")
       and ordered(L["fields.sync"], "gosub fields.is.on", "if not(fv.on) then return", "gosub fields.sync.tab", "if fv.on then", "gosub fields.label", "gosub load.current"), "")

    ck("F8", "fields.rebuild: the engine is made again with init for the same type, title and size; the container it was in is kept only when EVERY component of its path is still a collection or an array "
       "in the new data, with the selection and the window, and the engine is laid out for it; the clip stays; the stamps are the new text and signature; fvs is replaced",
       ordered(L["fields.rebuild"], "fz.old = fz.st", "fz.st = collection()", "fz.st{'ftype'} = fz.old{'ftype'}", "call $ced_core('init', fz.st, '', fz.out)", "fz.good = @true", "for fz.j = 1 to fz.np",
               "if fz.good then", "fz.x = fz.x{fz.pth<fz.j>}", "if fz.t # 'collection' and fz.t # 'array' then fz.good = @false", "next fz.j", "if fz.good and fz.np > 0 then",
               "fz.st{'path'} = fz.pth", "fz.st{'sel'} = fz.old{'sel'}", "call $ced_core('layout', fz.st, ew : @fm : (mh + 3), fz.out)", "fz.st{'clip.has'} = fz.old{'clip.has'}",
               "fz.st{'h.text'} = fz.txt", "fz.st{'h.sig'} = fz.sig", "fvs{'e' : fz.u} = fz.st"), "")

    ck("F9", "fields.leave: the text area is shown and given the tab's text only when it differs (ONE undo step through ed.set; entering and leaving without a change touches nothing); the token form is "
       "worked out by tab.display first; the focus goes to the text area",
       ordered(L["fields.leave"], "gosub tab.display", "gosub fields.view.off", "if (tb.disp : '|') # (ed.mw{'value'} : '|') then", "gosub ed.set", "ft.id = 'ed'", "gosub focus.to"), "")

    ck("F10", "the form and the tabs: a form made again (new.form) calls fields.form before the tree is applied; load.current ends with fields.apply; fields.apply syncs the engine to the text before it "
       "shows the pane, and takes the pane away when the tab shows its text; focus.to maps ed to fld and fld to ed by the tab; the indicator [*] follows the pane; the pane ring names the table",
       ordered(L["new.form"], "ind.cur = ind.want", "gosub fields.form", "gosub tree.apply")
       and ordered(L["load.current"], "if not(lc.nodraw) then gosub redraw.editor", "gosub fields.apply", "return")
       and ordered(label(ide, "fields.apply"), "gosub fields.is.on", "gosub fields.sync.tab", "case fv.on", "gosub fields.view.on", "case fv.shown", "gosub fields.view.off")
       and ordered(L["focus.to"], "gosub fields.is.on", "if ft.id = 'ed' and fv.on then ft.id = 'fld'", "if ft.id = 'fld' and not(fv.on) then ft.id = 'ed'", "focus.id = ft.id")
       and ordered(L["indicator.texts"], "ind.at = focus.id", "if ind.at = 'fld' then ind.at = 'ed'")
       and ordered(L["run.cmd"], "gosub fields.is.on", "(if fv.on then 'fld' else 'ed')"), "")

    ck("F11", "the pane's shape: view.on lays the engine out when the form is another size, hides the text area, shows the table and the path line, fills and draws; view.off is the opposite; fill does not "
       "draw (quiet is put back as it was); the path line carries the tab's marker (changed since read or saved, or a new record holding text), not the engine's dirty flag",
       ordered(L["fields.view.on"], "gosub fields.state", "call $ced_core('layout', fz.st, ew : @fm : (mh + 3), fz.out)", "screen set f, 'ed' visible 0", "screen set f, 'fld' visible 1", "screen set f, 'fpath' visible 1",
               "fv.shown = @true", "gosub fields.fill", "gosub redraw")
       and ordered(L["fields.view.off"], "screen set f, 'fld' visible 0", "screen set f, 'fpath' visible 0", "screen set f, 'ed' visible 1", "fv.shown = @false", "gosub redraw")
       and ordered(L["fields.fill"], "fz.tt{'stay'} = 1", "call $sl_widget_init(fz.tt)", "gosub fields.pathtext", "fz.q = f{'quiet'} + 0", "f{'quiet'} = 1", "screen set f, 'fpath' text fz.pt", "f{'quiet'} = fz.q")
       and ordered(L["fields.pathtext"], "fz.dd = ((bx{fz.k2} : '|') # (bx{fz.k3} : '|'))", "if bx{fz.k3} and bx{fz.k2} # '' then fz.dd = @true", "if fz.dd then fz.pt := ' *'")
       and "dirty" not in L["fields.pathtext"].replace("fz.dd", ""), "")

    ck("F12", "the status line: while the tab shows its fields the keys of the pane (15995) take the place of the cursor's line and column, unless a message is to be said; the pane is named as the editor",
       ordered(L["status.line"], "gosub fields.is.on", "if fv.on then", "if msg = '' then t := '   ' : sysmsg(15995)", "end else", "sysmsg(12218, mw{'cy'}, mw{'cx'})")
       and "case focus.id = 'ed' or focus.id = 'fld'" in L["status.line"], "")

    mm = {n: src["m%d" % n] for n in NEWMSG}
    bad = []
    for n, lab in NEWMSG.items():
        t = mm[n]
        body = ide if lab is None else L.get(lab, "")
        mt = re.search(r"sysmsg\(%d(?:,\s*([^\n]*))?\)" % n, body)
        top = max([int(x) for x in re.findall(r"%(\d)", t)] or [0])
        nargs = 0 if (not mt or not mt.group(1)) else len([a for a in re.split(r",", mt.group(1).rstrip(") ")) if a.strip()])
        if not t.strip() or t.count("\n") != 1 or not mt or nargs != top:
            bad.append((n, bool(mt), nargs, top))
    ck("F13", "messages 15995, 15998 and 15999 are there, one line each, cited where they are said with as many arguments as the text has %n; 15995 names the pane's keys (Ctrl-T type, Ctrl-S save, F12 text)",
       not bad and "Ctrl-T" in mm[15995] and "Ctrl-S" in mm[15995] and "F12" in mm[15995], repr(bad))
    return rows


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:240]))
        bad += 0 if ok else 1
    return bad


def sub1(old, new):
    def f(src):
        r = dict(src)
        if old not in r["ide"]:
            raise KeyError("ide: %r is not in the file, so the mutant cannot be made" % old[:90])
        r["ide"] = r["ide"].replace(old, new, 1)
        return r
    return f


def setmsg(n, text):
    def f(src):
        r = dict(src)
        r["m%d" % n] = text
        return r
    return f


M = []


def mut(name, row, fn):
    M.append((name, row, fn))


mut("the stash reads the hidden area", "F2", sub1("      if bx{k} then return              ;* 30 Oct 26 (stage 2b)", "      if 0 then return              ;* 30 Oct 26 (stage 2b)"))
mut("Replace works on the hidden area", "F2", sub1("   gosub fields.is.on\n   if fv.on then\n      msg = sysmsg(15998)               ;* 30 Oct 26 (stage 2b): the commands that work", "   gosub fields.is.on\n   if 0 then\n      msg = sysmsg(15998)               ;* 30 Oct 26 (stage 2b): the commands that work"))
mut("Go to line moves the hidden cursor", "F2", sub1("      msg = sysmsg(15998)               ;* 30 Oct 26 (stage 2b): it moves the cursor", "      msg = ''               ;* 30 Oct 26 (stage 2b): it moves the cursor"))
mut("the AI line reads the hidden area", "F2", sub1("      end else\n         msg = sysmsg(15998)\n      end\n      return\n   end\n   call $sl_form('find', f, '', 'ed', en)\n   mw = f{'widgets', en}\n   ai.lines", "      end else\n         msg = ''\n      end\n      return\n   end\n   call $sl_form('find', f, '', 'ed', en)\n   mw = f{'widgets', en}\n   ai.lines"))
mut("the AI selection falls through to the hidden area", "F2", sub1("      gosub fields.ai\n      return\n   end\n   call $sl_form('find', f, '', 'ed', en)\n   mw = f{'widgets', en}\n   ai.my", "      gosub fields.ai\n   end\n   call $sl_form('find', f, '', 'ed', en)\n   mw = f{'widgets', en}\n   ai.my"))
def pane_first(src):
    """the pane's case moved from the end of do.key's cases to the start: every IDE key then goes to the engine while the focus is on the table"""
    r = dict(src)
    t = r["ide"]
    case = ("      case focus.id = 'fld'\n         * 30 Oct 26 (stage 2b): the keys the IDE has no use of go to the fields view, last, so that every IDE key (F1, Ctrl-S, F4-F10, Ctrl-N / O / W / Q / E / L / R, F12) wins\n"
            "         fz.key = edata\n         gosub fields.key\n")
    head = "   begin case\n      case edata = 'f1'\n"
    if case not in t or head not in t:
        raise KeyError("ide: the pane's case or do.key's first case is not in the file, so the mutant cannot be made")
    r["ide"] = t.replace(case, "", 1).replace(head, "   begin case\n" + case + "      case edata = 'f1'\n", 1)
    return r


mut("the pane's keys win over the IDE's", "F3", pane_first)
mut("Return in the table is not the engine's", "F3", sub1("      case focus.id = 'fld'\n         fz.key = 'enter'", "      case focus.id = 'fldx'\n         fz.key = 'enter'"))
mut("Esc always goes up", "F3", sub1("      if fz.st{'path'} # '' then\n         msg = ''\n         fz.key = 'esc'", "      if 1 then\n         msg = ''\n         fz.key = 'esc'"))
mut("the loop does not follow the text", "F3", sub1("      gosub fields.sync                           ;* 30 Oct 26", "      null                                        ;* 30 Oct 26"))
mut("Q leaves the pane through the engine", "F4", sub1("   if upcase(fz.k) = 'Q' then return", "   if 0 then return"))
mut("Tab goes to the engine (an insert)", "F4", sub1("fz.k = 'tab' or fz.k = 'btab' or fz.k = 'f2'", "fz.k = 'btab' or fz.k = 'f2'"))
mut("Shift-Tab goes to the engine (S.176: the key reader names it btab, not shift-tab)", "F4", sub1("fz.k = 'tab' or fz.k = 'btab' or fz.k = 'f2'", "fz.k = 'tab' or fz.k = 'shift-tab' or fz.k = 'f2'"))
mut("Alt-T is not the type", "F4", sub1("   if fz.k = 'alt-t' then fz.k = 'f4'", "   null"))
mut("Left is not up", "F4", sub1("   if fz.k = 'left' or fz.k = 'bs' then fz.k = 'esc'", "   null"))
mut("the engine's end is kept", "F5", sub1("   fz.st{'done'} = @false\n   fz.st{'quit.all'} = @false", "   fz.st{'quit.all'} = @false"))
mut("every key writes back", "F5", sub1("   if (fz.sig : '|') # (fz.st{'h.sig'} : '|') then gosub fields.writeback", "   gosub fields.writeback"))
mut("an ended pane is drawn", "F5", sub1("   if not(fv.on) then\n      gosub load.current                                    ;* the view ended", "   if 0 then\n      gosub load.current                                    ;* the view ended"))
mut("a failed conversion is assigned", "F6", sub1("   if not(fz.ok) then\n      fz.k1 = 't' : fz.u\n      fz.txt = bx{fz.k1}", "   if 0 then\n      fz.k1 = 't' : fz.u\n      fz.txt = bx{fz.k1}"))
mut("a failed conversion is not told", "F6", sub1("         fz.st{'msg'} = sysmsg(12993)", "         null"))
mut("the write-back forgets the token mode", "F6", sub1("   tm.u = fz.u\n   tm.raw = fz.txt\n   gosub set.token.mode\n", ""))
mut("the write-back is not stamped", "F6", sub1("   fz.st{'h.sig'} = fz.sig\n   return\n", "   return\n"))
mut("the same text rebuilds the engine", "F7", sub1("   if (fz.txt : '|') = (fz.st{'h.text'} : '|') then return", "   null"))
mut("a text that is no record is rebuilt", "F7", sub1("   if not(fz.ok) then\n      gosub fields.drop\n      return\n   end\n   fz.sig = jbuild(fz.nc)", "   fz.sig = jbuild(fz.nc)"))
mut("the same data is rebuilt", "F7", sub1("   if (fz.sig : '|') = (fz.st{'h.sig'} : '|') then\n      fz.st{'h.text'} = fz.txt\n      return\n   end\n", ""))
mut("a number is a record", "F7", sub1("      if fz.kind # 'collection' and fz.kind # 'array' then fz.ok = @false\n      if fz.st", "      if 0 then fz.ok = @false\n      if fz.st"))
mut("the path is kept whatever the data", "F8", sub1("         if fz.t # 'collection' and fz.t # 'array' then fz.good = @false", "         null"))
mut("the rebuilt engine is not laid out", "F8", sub1("      call $ced_core('layout', fz.st, ew : @fm : (mh + 3), fz.out)          ;* resolves", "      null          ;* resolves"))
mut("the clip is lost on a rebuild", "F8", sub1("   fz.st{'clip.has'} = fz.old{'clip.has'}\n", ""))
mut("leaving always sets the text", "F9", sub1("   if (tb.disp : '|') # (ed.mw{'value'} : '|') then\n      ed.new = tb.disp\n      ed.cy = 0\n      gosub ed.set\n   end\n", "   ed.new = tb.disp\n   ed.cy = 0\n   gosub ed.set\n"))
mut("leaving does not work the token form out", "F9", sub1("   tb.raw = bx{fz.k1}\n   gosub tab.display\n   gosub fields.view.off", "   tb.disp = bx{fz.k1}\n   gosub fields.view.off"))
mut("a form made again forgets the pane", "F10", sub1("   gosub fields.form                    ;* 30 Oct 26", "   null                                 ;* 30 Oct 26"))
mut("a tab shown does not follow its view", "F10", sub1("   gosub fields.apply                    ;* 30 Oct 26 (stage 2b): the tab now shown", "   null                                  ;* 30 Oct 26 (stage 2b): the tab now shown"))
mut("a tab shown is not synced", "F10", sub1("      gosub fields.state\n      gosub fields.sync.tab\n   end\n   begin case", "      gosub fields.state\n   end\n   begin case"))
mut("the focus stays on a hidden area", "F10", sub1("   if ft.id = 'ed' and fv.on then ft.id = 'fld'", "   null"))
mut("the indicator ignores the pane", "F10", sub1("   if ind.at = 'fld' then ind.at = 'ed'", "   null"))
mut("the pane ring has the hidden area", "F10", sub1("(if fv.on then 'fld' else 'ed')", "'ed'"))
mut("the view is not laid out again", "F11", sub1("   gosub fields.state\n   if fz.st{'w'} + 0 # ew or fz.st{'h'} + 0 # (mh + 3) then\n      call $ced_core('layout', fz.st, ew : @fm : (mh + 3), fz.out)\n      fz.st{'path.row'} = ystat\n      fz.st{'msg.row'} = ystat\n   end\n   f{'quiet'} = 1\n   screen set f, 'ed' visible 0", "   gosub fields.state\n   f{'quiet'} = 1\n   screen set f, 'ed' visible 0"))
mut("the text area stays after the view is on", "F11", sub1("   screen set f, 'ed' visible 0\n   screen set f, 'fld' visible 1\n   screen set f, 'fpath' visible 1\n   f{'quiet'} = 0\n   fv.shown = @true\n   gosub fields.fill\n   gosub redraw",
                                                              "   screen set f, 'fld' visible 1\n   screen set f, 'fpath' visible 1\n   f{'quiet'} = 0\n   fv.shown = @true\n   gosub fields.fill\n   gosub redraw"))
mut("the path line uses the engine's flag", "F11", sub1("   if fz.dd then fz.pt := ' *'", "   if fz.st{'dirty'} then fz.pt := ' *'"))
mut("the table lets Up and Down leave the pane", "F11", sub1("   fz.tt{'stay'} = 1 ", "   fz.tt{'stay'} = 0 "))
mut("the fill draws", "F11", sub1("   fz.q = f{'quiet'} + 0\n   f{'quiet'} = 1\n   screen set f, 'fpath' text fz.pt\n   f{'quiet'} = fz.q", "   screen set f, 'fpath' text fz.pt"))
mut("the status line keeps the cursor's line", "F12", sub1("         if msg = '' then t := '   ' : sysmsg(15995)", "         null"))
mut("the pane is not named", "F12", sub1("      case focus.id = 'ed' or focus.id = 'fld'", "      case focus.id = 'ed'"))
mut("15995 forgets Ctrl-T", "F13", setmsg(15995, "F1 help   Return open   Esc up   Ins insert   Del delete   F3 rename   F4 type   Ctrl-S save   F12 text\n"))
mut("15998 has two lines", "F13", setmsg(15998, "This works on the text\nof the record\n"))
mut("15999 wants a third argument", "F13", setmsg(15999, "%1 %2 %3 is no longer text\n"))
mut("15999 is not said", "F13", sub1("   msg = sysmsg(15999, bf.name, bf.id)", "   msg = ''"))


def selftest(src, first):
    base = [r[0] for r in checks(src) if not r[2]]
    if base:
        print("selftest: the unchanged tree fails %s, so a mutant's own failure cannot be told from the tree's; run the plain check first" % base)
        return 1
    holes = 0
    ran = 0
    for n, (name, want, fn) in enumerate(M):
        if n < first:
            continue
        ran += 1
        try:
            m = fn(src)
        except KeyError as exc:
            print("  [FAIL] selftest %d: %s  <- %s" % (n, name, exc))
            holes += 1
            continue
        failed = sorted({r[0] for r in checks(m) if not r[2]})
        hit = want in failed
        print("  [%s] selftest %d: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", n, name, want, " ".join(failed) or "none"))
        holes += 0 if hit else 1
    print("selftest: %d mutants run (of %d), %d not caught" % (ran, len(M), holes))
    return 1 if holes else 0


def main(argv):
    src = load()
    print("test-fieldspane-units: tree %s" % SDSYS)
    if not src["ide"]:
        print("test-fieldspane-units: CANNOT RUN - gpl.bp/ide is not there")
        return 2
    rows = checks(src)
    bad = report(rows)
    print("\ntest-fieldspane-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        first = 0
        for a in argv:
            if a.startswith("--from="):
                first = int(a.split("=", 1)[1])
        rc = (selftest(src, first) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
