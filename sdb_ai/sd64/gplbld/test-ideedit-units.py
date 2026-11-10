#!/usr/bin/env python3
"""test-ideedit-units.py - the IDE's editing commands (the editor merge's stage D, 29 Oct 2026), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-ideedit-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-ideedit-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
29 Oct 26 dm  New with stage D, first slice.
29 Oct 26 dm  The review's findings (R1-R8): E11 and E12 follow the new code; E14 (Replace on the record), E15 (an element is assigned to a variable that has a value) and E16 (no 99,999 cut, the 256
              limit) are new, with their mutants.
30 Oct 26 dm  Stage E2: message 12563 is deleted (Import takes an operating system file now): NEWMSG loses it (E13) and its mutant goes; E10's words follow.
9 Nov 26 dm  S.184 stage 3: E17 (the active select list asked about, Go > Next record from the list), E18 (the files and records history in /idehist/ and Up / Down in Open's
             form, gpl.bp/ide_name), E19 (View > List of tabs), E20 (Build > Run a command at the terminal), E21 (messages 15047-15054 and the help); 21 mutants from M_S184C.
END-HISTORY

WHAT IT HOLDS (gpl.bp/ide, the end of the program).  Every command works on the TEXT AREA'S LIVE TEXT (mw{'value'}) and sets it ONCE through ed.set, which puts the old text and cursor on the
undo steps ($sl_memo 'snap') BEFORE it assigns: Replace was set through load.current, which forgot the undo steps.  ed.get refuses a tab that cannot be changed (ro.check); the commands that only
look (List matching lines, Export the selection) use ed.read.  The find options (match case on as delivered, how Replace has always compared; whole words off) are find.in.line's.  Query
replace asks about each match and sets the text once at the end.  Upcase / Downcase change only the characters between the mark and the cursor, by the same range as the AI's selection.  Export
writes through write.copy (Write a copy's own write: the gate asked again, the record locked and looked at again).  Import refuses what the editor cannot keep.  Run a command goes through
EXECUTE, so the prompt's command processor and its gates, keeps the changed texts' copies first (rc.tick) and takes the tabs' locks again after (relock.all).  The menus' new entries are at the END
of their menus, so that no existing entry moves.

***IT RUNS NOTHING, SO IT CANNOT SAY THAT A COMMAND DOES WHAT IT SAYS ON A SCREEN***: that is sandbox-ide-edit.py (written, not run).  --selftest breaks each property the way an edit
plausibly would and requires a check to notice.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
NEWMSG = [12548, 12549, 12550, 12551, 12552, 12553, 12554, 12555, 12556, 12557, 12558, 12559, 12560, 12561, 12562, 12564]      # 12563 (Import refuses an operating system file) was deleted 30 Oct 26
CMDS = ["view", "qreplace", "findopts", "upcase", "downcase", "import", "export", "xeq", "refresh", "xeqterm", "tablist"]      # 9 Nov 26 (S.184 stage 3): Run a command at the terminal, List of tabs
S184C = [15047, 15048, 15049, 15050, 15051, 15052, 15053, 15054]                                                       # 9 Nov 26 (S.184 stage 3): the select list, the history, the tabs, the terminal


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
    src = {"ide": read(os.path.join(GPL, "ide")), "tk_ai": read(os.path.join(GPL, "tk_ai")), "ide_name": read(os.path.join(GPL, "ide_name")),
           "screen_ask": read(os.path.join(GPL, "screen_ask")), "bcomp": read(os.path.join(GPL, "bcomp")), "sl_memo": read(os.path.join(GPL, "sl_memo"))}
    for n in NEWMSG + S184C + [12214, 12221, 12231, 12232, 12233, 12234, 15019, 15055, 15059, 15060]:
        src["m%d" % n] = read(os.path.join(MSG, str(n)))
    return src


def checks(src):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    ide = strip(src["ide"])
    names = ("ed.read", "ed.get", "ed.set", "find.in.line", "replace.line", "do.replace", "do.qreplace", "do.view", "do.findopts", "sel.range", "do.case", "do.export", "do.import", "do.xeq",
             "do.refresh", "do.goto", "do.writeas", "write.copy", "run.cmd", "ed.source", "ed.shown", "do.find", "save.one", "source.control.hook", "do.spool", "spool.close", "do.filter", "filter.clause", "list.ids", "load.file")
    L = {n: label(ide, n) for n in names}
    main = ide[: ide.find("apply.theme:")]
    ck("E0", "NULL CASE: the IDE was read and every routine this check reads is there (a check on nothing would pass)", len(ide) > 80000 and all(len(v) > 20 for v in L.values()),
       repr(sorted(k for k, v in L.items() if len(v) <= 20)))

    # ---- the menus ----------------------------------------------------------------------------------------------------------------------------------------------------
    m27, m28, m29 = (src["m%d" % n].strip() for n in (12232, 12233, 12234))
    def cmds_of(m):
        return [e.split("~")[2] for e in m.split("|")[1:]]
    def mnem_ok(m, old=0):
        """the mnemonics of the entries after the first OLD ones are different from each other and from the old ones' (Build has two old entries that share a C: not this stage's)"""
        ms = [re.search(r"&(.)", e.split("~")[0]).group(1).lower() for e in m.split("|")[1:] if "&" in e.split("~")[0]]
        new = ms[old:]
        return len(new) == len(set(new)) and not (set(new) & set(ms[:old]))
    ck("E1", "the new entries are at the END of their menus, so no existing entry moves (Search keeps Find and Replace first, Build its four, View its Theme), each runs a command run.cmd knows, and the "
       "mnemonics of a menu are all different",
       # 8 Nov 26 (S.179): the keys the entries show moved (Shift-F9 build, F9 run, Ctrl-T theme); the entries did not
       m27.startswith("&Search|&Find in the records~~find|&Replace in the record~^R~replace|") and m28.startswith("&Build|&Compile~F8~compile|Compile and cat&alog~Shift-F9~catalog|&Run~F9~run|&Debug~F7~debug|")
       and m29.startswith("&View|&Theme~^T~theme|") and all(c in cmds_of(m27) + cmds_of(m28) + cmds_of(m29) for c in CMDS)
       and all(("case cmd = '%s'" % c) in L["run.cmd"] for c in CMDS) and mnem_ok(m27) and mnem_ok(m28, 4) and mnem_ok(m29), repr((cmds_of(m27), cmds_of(m28), cmds_of(m29))))

    # ---- the one place a text is set ----------------------------------------------------------------------------------------------------------------------------------
    ck("E2", "ed.get asks ro.check before it reads (a tab that cannot be changed gets no command that changes it) and ed.read does not; ed.set puts the old text on the undo steps BEFORE it "
       "assigns the new one, takes the mark away and draws the editor",
       ordered(L["ed.get"], "if nbuf = 0 then", "gosub ro.check", "if not(ro.ok) then", "gosub ro.box", "gosub ed.read") and "ro.check" not in L["ed.read"]
       and ordered(L["ed.set"], "call $sl_memo('snap', ed.mw", "ed.mw{'value'} = ed.new", "ed.mw{'mx'} = 0", "ed.mw{'my'} = 0", "gosub redraw.editor"), "")
    ck("E3", "find.in.line: case is folded on BOTH sides unless fo.case; a whole-word match must have no word character before it and none after it, the set built from digits, letters and ._$%; "
       "the search goes on after a match that fails the test",
       ordered(L["find.in.line"], "if not(fo.case) then", "fp.hay = upcase(fp.hay)", "fp.nee = upcase(fp.nee)", "fp.ln = len(fp.nee)", "if fp.ln > FINDMAX then return", "fp.hl = len(fp.hay)",
               "index(fp.hay[fp.p, fp.hl], fp.nee, 1)", "if fo.word then",
               "convert(WORDCH, '', fp.hay[fp.s - 1, 1]) = ''", "convert(WORDCH, '', fp.c) = ''", "if fp.good then", "fp.p = fp.s + 1")
       and ordered(main, "WORDCH = '._$%'", "for wc.i = 48 to 57", "for wc.i = 65 to 90", "char(wc.i) : char(wc.i + 32)")
       and ordered(main, "fo.case = @true", "fo.word = @false"), "")
    rp = L["do.replace"]
    ck("E4", "Replace (Ctrl-R) is ONE undo step: it reads the live text through ed.get, sets it once through ed.set and does NOT go through bx / load.current (which forgot the undo steps); the whole text "
       "is changed at once only with the delivered options, else line by line",
       ordered(rp, "gosub ed.get", "if len(rp.old) > FINDMAX then", "sysmsg(12557, FINDMAX)", "gosub ed.source", "if fo.case and not(fo.word) then", "rp.n = count(ed.src, rp.old)", "ed.new = change(ed.src, rp.old, rp.new)",
               "end else", "rl.line = ed.src<rp.j>", "gosub replace.line", "gosub ed.shown", "if not(ed.ok) then return", "gosub ed.set")
       and "load.current" not in rp and "bx{k}" not in rp and rp.count("gosub ed.set") == 1 and not re.search(r"\bed\.t\b", rp.split("gosub ed.source")[1]), "")
    qr = L["do.qreplace"]
    ck("E5", "Query replace asks about each match with Yes, No, All and Quit (Quit is the default answer if the box is left), takes the line with it, builds the text in ed.new and sets it ONCE at the "
       "end; nothing is changed when nothing was answered Yes",
       ordered(qr, "gosub ed.get", "if len(qr.old) > FINDMAX then", "sysmsg(12557, FINDMAX)", "gosub ed.source", "ed.new = ed.src", "qr.line = ed.src<qr.j>", "gosub find.in.line",
               "buttons 'Yes,No,All,Quit' default 1 returning qr.b else qr.b = 4", "qr.quit = @true", "if qr.yes = 0 then", "return", "gosub ed.shown", "if not(ed.ok) then return", "gosub ed.set")
       and qr.count("gosub ed.set") == 1 and "sysmsg(12551, qr.old, qr.new, qr.j)" in qr and "qr.shown" in qr.split("sysmsg(12551")[1].split("\n")[0] and "qr.shown = ed.t<qr.j>" in qr
       and not re.search(r"\bed\.t\b", qr.split("gosub ed.source")[1].replace("qr.shown = ed.t<qr.j>", "")), "")
    vw = L["do.view"]
    ck("E6", "List matching lines reads the text without the read-only test (a locked record can be looked at), puts the line number and the trimmed line in the table (err.rows, err.lines), stops at "
       "MAXHIT, and marks the table 'view' so that Return goes to the line",
       ordered(vw, "gosub ed.read", "gosub find.in.line", "err.rows<-1> = vw.j", "err.lines<-1> = vw.j", "until vw.n >= MAXHIT", "out.kind = 'view'", "gosub err.load") and "ed.get" not in vw
       and "gl.n = err.lines<k2> + 0" in strip(src["ide"]), "")
    ck("E7", "Find options sets both options from the answer (C and W, any case; blank is neither) and says what they are",
       ordered(L["do.findopts"], "screen ask sysmsg(12553)", "upcase(fo.text)", "fo.case = (index(fo.text, 'C', 1) > 0)", "fo.word = (index(fo.text, 'W', 1) > 0)", "sysmsg(12554"), "")
    ck("E8", "sel.range orders the mark and the cursor and leaves out the character under the later end (as the AI's selection does) and answers no range for no mark or nothing between; Upcase and "
       "Downcase change only that range of each line (the first line from x1, the last up to x2 - 1) and set the text once",
       ordered(L["sel.range"], "if sr.my < 1 or sr.mx < 1 then return", "if sr.my < sr.cy or (sr.my = sr.cy and sr.mx <= sr.cx) then", "if sr.y1 = sr.y2 and sr.x1 = sr.x2 then return", "sr.ok = @true")
       and ordered(L["do.case"], "gosub ed.get", "gosub sel.range", "if not(sr.ok) then", "sysmsg(12556)", "if dc.j = sr.y1 then dc.a = sr.x1", "if dc.j = sr.y2 then dc.z = sr.x2 - 1",
                   "dc.part = dc.ln[dc.a, dc.z - dc.a + 1]", "upcase(dc.part)", "downcase(dc.part)", "dc.ln[1, dc.a - 1] : dc.part : dc.ln[dc.z + 1, len(dc.ln)]", "gosub ed.set")
       and L["do.case"].count("gosub ed.set") == 1, "")
    ex = L["do.export"]
    ck("E9", "Export the selection reads without the read-only test, takes the AI's selection text, asks the name form in the 'copy' mode, refuses a record a tab holds, and writes through write.copy - "
       "itself it holds no write; Write a copy writes through the same label",
       ordered(ex, "gosub ed.read", "gosub sel.range", "call $tk_ai('select', ed.t", "wa.text = change(xp.res<1>, char(10), @fm)", "ed.kk = 'm' : bu<cb>", "if bx{ed.kk} then",
               "xp.last = ed.t<sr.y2>", "if sr.x1 = 1 and sr.x2 > len(xp.last) then", "call $recarr('fromtext', wa.text, ex.rec, ed.ok2)", "wa.text = ex.rec", "call $ide_name('copy', wa.file, wa.id, wa.res)", "gosub tab.find", "if tf.p then", "gosub write.copy")
       and not re.search(r"^\s*(write|writeu|readu)\s", ex, re.M) and ordered(L["do.writeas"], "call $ide_name('copy', wa.file, wa.id, wa.res)", "gosub tab.find", "gosub write.copy")
       and ordered(L["write.copy"], "open wa.file to fv else", "gosub edit.check", "readu x from fv, wa.id locked", "write wa.text on fv, wa.id on error", "release fv, wa.id", "gosub refresh.tree.for"), "")
    im = L["do.import"]
    ck("E10", "Import a record here needs a tab that can be changed, asks the name form in the 'open' mode (the record must exist; path:/full/name names an operating system file since 30 Oct 26, whose "
       "reading is test-ideos-units.py's O-rows), refuses a collection file, a record holding "
       "value, subvalue or text marks or bytes 128 to 247, and puts the lines in at the cursor through ed.set; it writes no record",
       ordered(im, "gosub ed.get", "call $ide_name('open', im.file, im.id, im.res)", "if im.file = 'path:' then", "FL$COLLECTION", "read im.x from fv, im.id else", "index(im.x, @vm, 1)", "index(im.x, @sm, 1)",
               "index(im.x, @tm, 1)", "convert(NA.CHARS, '', im.x) # im.x", "im.block = im.ln[1, im.cx - 1] : im.x", "im.block := im.ln[im.cx, len(im.ln)]", "ed.new<im.cy> = im.block", "gosub ed.set")
       and ordered(im, "FL$COLLECTION", "sysmsg(12562, im.file)", "read im.x from fv, im.id else") and "sysmsg(12703" not in im
       and not re.search(r"\b(write|writeu|readu|delete)\b", im), "")
    xq = L["do.xeq"]
    ck("E11", "Run a command keeps the changed texts' copies BEFORE it runs (the command may end the session), runs it with EXECUTE ... TRAPPING ABORTS CAPTURING (the prompt's command processor: its gates; "
       "a command that aborts is stopped, as Run and Debug's are - without TRAPPING ABORTS the abort cast the IDE off with every unsaved tab, 29 Oct 26 review R2), takes the tabs' "
       "locks again AFTER it, and shows what it printed in the table (rows that jump nowhere: err.lines 0)",
       ordered(xq, "screen ask sysmsg(12559)", "gosub rc.tick", "execute xq.cmd trapping aborts capturing xq.out", "gosub relock.all", "err.rows<-1> = xq.n", "err.lines<-1> = 0", "out.kind = 'xeq'", "gosub err.load")
       and all(("execute 'run ' : qp.f : ' ' : qp.i : ra.args trapping aborts" in L["run.cmd"], "execute 'debug ' : qp.f : ' ' : qp.i trapping aborts" in L["run.cmd"])), "")    # 9 Nov 26 (S.184 stage 3): Run with arguments
    gt = L["do.goto"]
    ck("E12", "Go to takes a line, a line and column, or field, value and subvalue (the value after the (v - 1)-th ':@vm:', the subvalue after the (s - 1)-th ':@sm:' inside it, found in any case, "
       "a number out of range going to the last); each number must be a number of at least 1 and is made whole; gl.p is given a value BEFORE its first element is assigned (29 Oct 26 review R1: "
       "an element of an unassigned variable stops the program, and the first Go to line was its end); the cursor is put inside the line",
       ordered(gt, "screen ask sysmsg(12214)", "gl.k > 3", "gl.p = ''", "num(gl.v)", "gl.v = int(gl.v + 0)", "if gl.v < 1 then return", "if gl.v > 99999999 then gl.v = 99999999", "gl.p<gl.i> = gl.v", "gosub goto.line", "gl.lo = downcase(gl.ln)",
               "index(gl.lo, ':@vm:', gl.p<2> + 0 - 1)", "dcount(gl.lo, ':@vm:') - 1", "gl.from = gl.q + 5", "gl.seg = gl.lo[gl.from, len(gl.lo)]", "index(gl.seg, ':@sm:', gl.p<3> + 0 - 1)",
               "dcount(gl.seg, ':@sm:') - 1", "gl.col = gl.from + gl.q + 4", "if gl.col > len(gl.ln) + 1 then gl.col = len(gl.ln) + 1", "mw{'cx'} = gl.col")
       and "gosub do.goto" in L["run.cmd"] and ordered(L["do.refresh"], "screen refresh", "last.status = char(1)", "last.foot = ''"), "")
    ck("E13", "messages 12548-12564 (the ones used) are there, one line each, and the IDE cites each; the Go to prompt names the forms and the help names the new menu entries",
       all(src["m%d" % n].strip() and src["m%d" % n].count("\n") == 1 for n in NEWMSG) and all(("sysmsg(%d" % n) in ide for n in NEWMSG if n not in (12214,))
       and "line,column" not in "" and "field,value,subvalue" in src["m12214"] and "line,column" in src["m12214"]
       and all(w in src["m12221"] for w in ("List matching lines", "Query replace", "Find options", "Upcase", "Import", "Export", "Run a command", "Refresh")), repr([n for n in NEWMSG if ("sysmsg(%d" % n) not in ide]))

    # ---- the review of 29 Oct 26 (R1-R8), each a property a free check can hold ---------------------------------------------------------------------------------------
    es, eh = L["ed.source"], L["ed.shown"]
    ck("E14", "R4: Replace and Query replace change the RECORD a token-form tab stands for, not the text it shows: ed.source reads the tab's token flag (bx m) and takes the record with 'fromtext', ed.shown "
       "shows the result with 'totext' and, when a field would be just the text of a mark token, says so (12997), leaves the text as it was and returns ed.ok false; both commands call ed.source before they "
       "look at the text and ed.shown before ed.set, and neither reads ed.t after ed.source (only Query replace's box shows the line the person sees, qr.shown)",
       ordered(es, "ed.src = ed.t", "ed.kk = 'm' : bu<cb>", "ed.tok = bx{ed.kk}", "if ed.tok then call $recarr('fromtext', ed.t, ed.src, ed.ok2)")
       and ordered(eh, "ed.ok = @true", "if ed.tok then", "call $recarr('totext', ed.new, ed.disp, ed.ok2)", "if ed.ok2 then", "ed.new = ed.disp", "msg = sysmsg(12239, 0) : '. ' : sysmsg(12997, ed.disp)", "ed.ok = @false"), "")
    ck("E15", "R1: in the new commands (do.goto, do.replace, do.qreplace, do.view, do.case, do.import, do.xeq) every variable that takes an ELEMENT (x<n> = ...) has been assigned a whole value earlier in the same "
       "routine, because an element of a variable that has no value stops the program ('Unassigned variable') and no compile warning says so",
       all(unassigned_targets(L[n]) == [] for n in ("do.goto", "do.replace", "do.qreplace", "do.view", "do.case", "do.import", "do.xeq", "replace.line", "ed.shown")),
       repr({n: unassigned_targets(L[n]) for n in ("do.goto", "do.replace", "do.qreplace", "do.view", "do.case", "do.import", "do.xeq", "replace.line", "ed.shown") if unassigned_targets(L[n])}))
    ck("E16", "R5/R6: no string is cut at 99,999 characters in the new commands (the rest of a line is taken with len() of the same string), and the text to find is refused above FINDMAX = 256 characters in "
       "Replace, Query replace and List matching lines (INDEX cuts at 256 and COUNT stops the program) with message 12557, the backstop in find.in.line",
       all(not re.search(r"\b99999\b", L[n]) for n in ("find.in.line", "replace.line", "do.replace", "do.qreplace", "do.view", "do.case", "do.import", "do.goto", "do.export")) and re.search(r"^\s*FINDMAX = 256\b", main, re.M)
       and all(ordered(L[n], "len(%s) > FINDMAX" % v, "sysmsg(12557, FINDMAX)") for n, v in (("do.replace", "rp.old"), ("do.qreplace", "qr.old"), ("do.view", "vw.pat"), ("do.find", "pat")))
       and "t.part = t.ln[t.x1, len(t.ln)]" in strip(src["tk_ai"]) and "t.ln[t.x1, 99999]" not in strip(src["tk_ai"]), "")

    # ---- 9 Nov 26 (S.184 stage 3): the select list, the history, the list of tabs, a command at the terminal ---------------------------------------------------------------
    S = {n: label(ide, n) for n in ("open.select", "do.nextsel", "open.record", "hist.push", "hist.add", "do.tablist", "do.xeqterm")}
    nm = strip(src["ide_name"])
    hr = label(nm, "hist.recall")
    m26 = src["m12231"].strip()
    ck("E17", "the active select list: the IDE asks (15047, Yes the default) after it has read and cleared list 0 and before anything else is built; any answer but Yes empties sel0, so the tree "
       "opens as with no list; open.select keeps the ids and the place after the tabs it opened (lst.next = os.open + 1); Go > Next record from the list (the last entry of Go, no key) takes the "
       "next id from lst.ids - never a SELECT or READNEXT -, passes over one already in a tab, opens one record in a tab, and says 15048 with no list and 15050 when the list is used up",
       all(len(v) > 20 for v in S.values())
       and ordered(main, "clearselect 0", "if sel0 # '' then", "screen msgbox sysmsg(15047, lq.n, sel0<1>) buttons 'Yes,No' default 1", "if lq.b # 1 then", "sel0 = ''", "gosub build.files")
       and ordered(S["open.select"], "gosub open.record", "lst.ids = sel0", "lst.file = fn0", "lst.dict = dflag0", "lst.next = os.open + 1")
       and ordered(S["do.nextsel"], "if lst.ids = '' then", "sysmsg(15048)", "ns.id = lst.ids<lst.next>", "lst.next += 1", "gosub tab.find", "if tf.p = 0 then", "gosub open.record", "sysmsg(15050, ns.n)")
       and not re.search(r"\b(select|sselect|readnext|readlist)\b", re.sub(r"'[^']*'", "''", S["do.nextsel"])) and S["do.nextsel"].count("gosub open.record") == 1
       and m26.endswith("|Next &record from the list~~nextsel|Filter the r&ecords~~filter") and "case cmd = 'nextsel'\n         gosub do.nextsel" in L["run.cmd"], "")
    ck("E18", "the history (SED's stacks): /idehist/ is declared the same in ide and ide_name and set up once (ih.on); open.record pushes the file and the record for a record of a FILE (not a dictionary "
       "item, od = '') both when it opens a tab and when the record is already in one; hist.add moves a name already there to the top and keeps IH.MAX = 20; ide_name's Up and Down bring them back in "
       "Open's form only, the file entry from ih.files and the record entry from ih.recs, move the focus when nothing is kept, and never write the common",
       "common /idehist/ ih.on, ih.files, ih.recs, ih.cmds" in ide and "common /idehist/ ih.on, ih.files, ih.recs, ih.cmds" in nm and re.search(r"^\s*IH\.MAX = 20\b", main, re.M)
       and ordered(main, "if ih.on + 0 # 1 then", "ih.files = ''", "ih.recs = ''", "ih.on = 1")
       and S["open.record"].count("if od = '' then gosub hist.push") == 2
       and ordered(S["hist.push"], "hp.item = or.file", "hp.list = ih.files", "gosub hist.add", "ih.files = hp.list", "hp.item = or.id", "hp.list = ih.recs", "gosub hist.add", "ih.recs = hp.list")
       and ordered(S["hist.add"], "if hp.item = '' then return", "locate hp.item in hp.list<1> setting hp.at then del hp.list<hp.at>", "hp.list = hp.item : @fm : hp.list",
                   "if dcount(hp.list, @fm) > IH.MAX then hp.list = field(hp.list, @fm, 1, IH.MAX)")
       and "case (nk = 'up' or nk = 'down') and mode = 'open'\n                  gosub hist.recall" in nm
       and ordered(hr, "if ih.on + 0 = 1 then", "if focus = 1 then hr.list = ih.files else hr.list = ih.recs", "if hr.n = 0 then", "gosub swap.focus")
       and not re.search(r"^\s*ih\.(on|files|recs)\s*(=|:=|<)", nm, re.M), "")
    ck("E19", "View > List of tabs (the last entry of View): the text in the editor is kept first (stash.current), one row a tab with its number, file, record, changed mark and lines, in $sl_pickwin "
       "titled 15051 with the columns of 15052, starting on the current tab; only Enter (status 0) goes to the tab chosen; nothing is read from the disk",
       ordered(S["do.tablist"], "if nbuf = 0 then return", "gosub stash.current", "tq.items = ''", "for i = 1 to nbuf", "gosub buf.label", "gosub is.dirty", "tq.items<i, 1> = i",
               "call $sl_pickwin(tq.items, sysmsg(15051), 0, cb, tq.ret, tq.st,", "if tq.st = 0 then", "gosub switch.to")
       and "change(sysmsg(15052), '|', @vm)" in S["do.tablist"] and not re.search(r"\b(read|readu|open|openpath)\b", S["do.tablist"])
       and src["m12234"].strip().endswith("|List of ta&bs~~tablist"), "")
    ck("E20", "Build > Run a command at the terminal (the last entry of Build): asked with 15053, the text kept (stash.current), the screen given over (leave.screen), ONE execute with TRAPPING ABORTS and "
       "no CAPTURING, and the screen taken back with Run's Press Return (retake.screen: the locks too); do.xeq still captures into the table",
       ordered(S["do.xeqterm"], "screen ask sysmsg(15053) history ih.cmds returning xm.cmd else return", "if xm.cmd = '' then return", "gosub stash.current", "gosub leave.screen",
               "execute xm.cmd trapping aborts", "gosub retake.screen", "sysmsg(15054, xm.cmd)")
       and S["do.xeqterm"].count("execute") == 1 and "capturing" not in S["do.xeqterm"] and "retake.quiet" not in S["do.xeqterm"]
       and "execute xq.cmd trapping aborts capturing xq.out" in L["do.xeq"] and src["m12233"].strip().endswith("|Run a command at the termi&nal~~xeqterm"), "")
    ck("E21", "the messages 15047-15054 are there and not empty, and the help (12221) names the four: Run a command at the terminal, Next record from the list, Up and Down in Open, List of tabs",
       all(src["m%d" % n].strip() for n in S184C) and all(w in src["m12221"] for w in ("Run a command at the terminal", "Next record from the list", "Up, Down in the file or the record", "List of tabs")),
       repr([n for n in S184C if not src["m%d" % n].strip()]))
    hk = L["source.control.hook"]
    ck("E22", "S.184 stage 4: save.one calls source.control.hook after the overwrite question and BEFORE the write, as SED and ED do, and stops when it says no; the hook looks once for the catalogued subroutine, does nothing without one, "
       "passes SED's arguments (dict flag, file, record as copies, the text, 1, allowed, updated), draws the screen again after it, refuses with 6653 and gives a lock it took back, and an update reaches the tab's text and what is written, a collection's through coll.value; the editor is loaded again",
       ordered(L["save.one"], "Overwrite,Cancel", "gosub source.control.hook", "if not(srcc.ok) then return", "writeu sv.out on fv", "sv.reload = srcc.update")
       and ordered(hk, "srcc.ok = @true", "srcc.update = @false", "if srcc.active < 0 then srcc.active = catalogued(srcc.name)", "if not(srcc.active) then return",
                   "call @srcc.name((sv.dict), (bn<sv.i>), (sv.id), sv.text, 1, srcc.allowed, srcc.update)", "screen refresh", "last.status = char(1)", "if not(srcc.allowed) then",
                   "if not(sv.slot) then release fv, sv.id", "srcc.ok = @false", "sysmsg(6653)", "if srcc.update then", "bx{k} = sv.text", "gosub coll.value", "sv.out = cv.y", "sv.out = sv.text")
       and "srcc.name = 'source.control'" in ide and "srcc.active = -1" in ide, "")
    sa = strip(src["screen_ask"])
    ck("E23", "SCREEN ASK ... HISTORY: the compiler's row for ASK has the keyword after MASK and the subroutine takes hist between mask and ret; a MASK question recalls nothing and an empty list leaves Up and Down as they were; Up stops at the "
       "oldest and keeps what was typed, Down gives it back; both IDE prompts offer ih.cmds and remember what was run through one routine, in the common's last place",
       '"MASK:F":@sm:"HISTORY:1"' in src["bcomp"] and "subroutine screen_ask(prompt, value, width, title, ax, ay, mask, hist, ret, status)" in sa
       and "hn = if mask # '' or hist = '' then 0 else dcount(hist, @fm)" in sa and "if (k = 'up' or k = 'down') and hn > 0 then" in sa
       and ordered(sa, "recall:", "if hi >= hn then return", "if hi = 0 then draft = w{'value'}", "hi += 1", "if hi = 0 then return", "hi -= 1", "w{'value'} = if hi then hist<hi> else draft", "$sl_entry('init'", "$sl_entry('draw'")
       and "screen ask sysmsg(12559) history ih.cmds returning xq.cmd" in ide and "screen ask sysmsg(15053) history ih.cmds returning xm.cmd" in ide
       and ide.count("gosub hist.command") == 2 and "ih.cmds = hp.list" in ide, "")
    me = strip(src["sl_memo"])
    ck("E24", "keyboard macros: every key the area gets goes through macro.key; a program's passkeys come first; nothing happens to the two keys while a macro plays; a new recording empties the old; only a key the area acted on is recorded and a paste never; "
       "the play stops at a key it does not act on and is not nested; the IDE keeps the macro across a remade form and has both on the Edit menu",
       "gosub count\n         gosub macro.key" in me
       and ordered(me, "macro.key:", "not(index(@vm : w{'passkeys'} : @vm, @vm : key : @vm, 1))", "if w{'macrun'} + 0 then return", "w{'macrec'} = 1", "w{'macro'} = ''", "if w{'macrec'} + 0 or w{'macro'} = '' then return",
                   "w{'macrun'} = 1", "call $sl_memo('key', w, scr, m.list<m.i>, m.ret)", "while m.ret<1> = 'handled'", "w{'macrun'} = 0", "gosub handle.key", "if w{'macrec'} + 0 and ret<1> = 'handled' and m.key # 'paste' then")
       and "mw{'macro'} = ed.macro" in ide and "ed.macro = ow{'macro'}" in ide and "|Start or end a macr&o~Alt-R~macrec|E&xecute the macro~Alt-P~macrun" in src["m15019"]
       and src["m15055"].strip() != "" and "ctrl-down,alt-r,alt-p'" in ide, "")
    sq = L["do.spool"]
    ck("E25", "File, Spool the text: the words are at, lnum and region and anything else is refused before the printer is touched; region without a selection is refused; the text is the editor's, the record is neither read nor written; "
       "a refused location ends the job and puts the unit back; after the job the screen is drawn again",
       ordered(sq, "gosub ed.read", "screen ask sysmsg(15056)", "sp.c = 'at'", "sysmsg(6696", "sp.c = 'lnum'", "sp.c = 'region'", "sysmsg(15057", "sysmsg(12556)", "printer on", "!setpu(PU$LOCATION, 0, sp.at", "if sp.code then", "gosub spool.close", "return", "sp.l = ed.t<sp.ln>", "gosub spool.close")
       and "write" not in re.sub(r"!setpu|sysmsg\([^)]*\)", "", sq).lower().replace("writeas", "")
       and ordered(L["spool.close"], "printer off", "printer close", "printer on", "!setpu(PU$BANNER", "!setpu(PU$LOCATION", "printer off", "printer close", "screen refresh", "last.status = char(1)"), "")
    fi, ls, lo = L["do.filter"], L["list.ids"], L["load.file"]
    ck("E26", "Go, Filter the records and the tree's pages: a list the tree asks for names its key, and a caller with no key (Find in the records) sees every record; a bare word becomes WITH @ID LIKE, a quoted text is checked as SED checks it; a change goes back to page 0; "
       "the filter goes through the query processor with its output captured and a refusal lists nothing; a page skips the earlier records; the N and B rows change the page and load the list again",
       ordered(lo, "lr.key = 'F:' : lf.name", "gosub list.ids", "lr.key = ''") and ordered(ls, "if lr.key # '' then", "lr.tmpl = lt.text<lr.p>", "lr.skip = (lt.page<lr.p> + 0) * MAXREC", "if lr.tmpl # '' then",
       "execute 'sselect ' : lr.sent : ' ' : lr.tmpl : ' to 9' trapping aborts capturing lr.cap", "if @system.return.code < 0 then", "lr.ok = @false", "msg = sysmsg(15063", "for lr.s = 1 to lr.skip", "readnext lr.id from 9 else exit")
       and ordered(L["filter.clause"], "'LIKE '", "'WITH '", "sysmsg(6674)", "with @id like", "sysmsg(6675)", "fx.t = 'with @id like \"' : fx.t : '\"'") and ordered(fi, "gosub get.context", "sysmsg(15059)", "screen ask sysmsg(15060", "gosub filter.clause", "lt.text<fx.at> = fx.t", "lt.page<fx.at> = 0", "gosub load.dict", "gosub load.file", "gosub tree.apply")
       and "case code[1, 2] = 'N:' or code[1, 2] = 'B:'" in ide and "lmore<lp> = lr.more" in ide and "del lmore<lp>" in ide and "lr.key = ''" in ide, "")
    return rows


def unassigned_targets(body):
    """the variables of a routine's ELEMENT assignments (x<n> = ..., x<-1> = ..., also after THEN, ELSE or ;) that no earlier plain assignment (x = ... as a statement of its own) DOMINATES: one at the
    same or a shallower indent whose block is still open.  A line that is less indented than an assignment closes its block (so the branches of an IF do not give each other a value), and an
    assignment after THEN or ELSE on the same line is conditional and counts for nothing (review of the fixes, CB2: the first version saw only line starts and counted any assignment anywhere)."""
    bad = []
    seen = {}                                                   # name -> the indent of the assignment that gives it a value
    for ln in body.split("\n"):
        if not ln.strip():
            continue
        ind = len(ln) - len(ln.lstrip())
        for k in [k for k, v in seen.items() if v > ind]:       # the block of those assignments is closed
            del seen[k]
        for piece in ln.split(";"):
            for m in re.finditer(r"(?:^\s*|\bthen\s+|\belse\s+)([a-z][a-z0-9.]*)<[^>]*>\s*(?::=|\+=|=)", piece):
                if m.group(1) not in seen and m.group(1) not in bad:
                    bad.append(m.group(1))
            m = re.match(r"\s*([a-z][a-z0-9.]*)\s*(=|:=)\s", piece)
            if m:
                seen[m.group(1)] = ind
    return bad


def helper_selftest():
    """the helper itself: the four snippets the reviewer ran and two more"""
    cases = [("   x<1> = 2", ["x"]), ("   x = ''\n   x<1> = 2", []), ("   if c then x<1> = 5", ["x"]), ("   a = 1 ; x<2> = y", ["x"]),
             ("   if c then\n      x = ''\n   end\n   x<1> = 1", ["x"]), ("   if c then\n      x = ''\n      x<1> = 1\n   end", []),
             ("   if c then\n      x = 1\n   end else\n      x<1> = 1\n   end", ["x"]), ("   x = ''\n   for i = 1 to 3\n      x<i> = i\n   next i", [])]
    bad = 0
    for body, want in cases:
        got = unassigned_targets(body)
        ok = (got == want)
        print("  [%s] selftest: unassigned_targets(%r) is %r" % ("PASS" if ok else "FAIL", body, got))
        bad += 0 if ok else 1
    return bad


def sub(key, old, new):
    def f(src):
        r = dict(src)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:80]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


MUTANTS = [
    ("a menu entry moved: Search starts with List", "E1", sub("m12232", "&Search|&Find in the records~~find|", "&Search|&List matching lines~~view|&Find in the records~~find|")),
    ("a menu entry has no command", "E1", sub("ide", "      case cmd = 'xeq'\n         gosub do.xeq", "      case cmd = 'xeqq'\n         gosub do.xeq")),
    ("two entries share a mnemonic", "E1", sub("m12232", "Find &options", "&Find options")),
    ("ed.get skips the read-only test", "E2", sub("ide", "   ro.i = cb\n   gosub ro.check\n   if not(ro.ok) then\n      gosub ro.box\n      return\n   end\n   gosub ed.read", "   gosub ed.read")),
    ("ed.set assigns before it snaps", "E2", sub("ide", "   call $sl_memo('snap', ed.mw, '', '', ed.sr)\n   ed.old = ed.mw{'value'}\n   ed.mw{'value'} = ed.new", "   ed.old = ed.mw{'value'}\n   ed.mw{'value'} = ed.new\n   call $sl_memo('snap', ed.mw, '', '', ed.sr)")),
    ("ed.set leaves the mark", "E2", sub("ide", "   ed.mw{'mx'} = 0\n   ed.mw{'my'} = 0\n   ed.nl", "   ed.nl")),
    ("whole words ignore the character before", "E3", sub("ide", "            if convert(WORDCH, '', fp.hay[fp.s - 1, 1]) = '' then fp.good = @false", "            null")),
    ("whole words ignore the character after", "E3", sub("ide", "            if convert(WORDCH, '', fp.c) = '' then fp.good = @false", "            null")),
    ("a failed whole-word match ends the search", "E3", sub("ide", "      fp.p = fp.s + 1\n   repeat", "      exit\n   repeat")),
    ("case is folded on the pattern only", "E3", sub("ide", "      fp.hay = upcase(fp.hay)\n      fp.nee = upcase(fp.nee)", "      fp.nee = upcase(fp.nee)")),
    ("the options are on as delivered", "E3", sub("ide", "   fo.case = @true\n   fo.word = @false", "   fo.case = @false\n   fo.word = @false")),
    ("Replace goes through load.current again", "E4", sub("ide", "   ed.cy = 0\n   gosub ed.set\n   msg = sysmsg(12239, rp.n)", "   ed.cy = 0\n   gosub ed.set\n   gosub load.current\n   msg = sysmsg(12239, rp.n)")),
    ("Replace takes the quick way with options on", "E4", sub("ide", "   if fo.case and not(fo.word) then\n      rp.n = count(ed.src, rp.old)", "   if 1 then\n      rp.n = count(ed.src, rp.old)")),
    ("Replace changes the text the tab shows, not its record", "E4", sub("ide", "   gosub ed.source\n   if fo.case and not(fo.word) then", "   ed.src = ed.t\n   if fo.case and not(fo.word) then")),
    ("Replace puts the record's marks in the text as characters", "E4", sub("ide", "   gosub ed.shown\n   if not(ed.ok) then return\n   ed.cy = 0", "   ed.ok = @true\n   ed.cy = 0")),
    ("Replace takes a text over 256 characters", "E16", sub("ide", "   if len(rp.old) > FINDMAX then\n      msg = sysmsg(12557, FINDMAX)\n      return\n   end\n   screen ask sysmsg(12238) returning rp.new else return\n   gosub ed.source",
                                                          "   screen ask sysmsg(12238) returning rp.new else return\n   gosub ed.source")),
    ("List matching lines takes a text over 256 characters", "E16", sub("ide", "   if len(vw.pat) > FINDMAX then\n      msg = sysmsg(12557, FINDMAX)\n      return\n   end\n", "")),
    ("find.in.line has no backstop for a long text", "E3", sub("ide", "   if fp.ln > FINDMAX then return", "   null")),
    ("find.in.line cuts the line at 99999 again", "E3", sub("ide", "index(fp.hay[fp.p, fp.hl], fp.nee, 1)", "index(fp.hay[fp.p, 99999], fp.nee, 1)")),
    ("Query replace cuts a line at 99999 again", "E16", sub("ide", "      qr.out := qr.line[qr.from, len(qr.line)]", "      qr.out := qr.line[qr.from, 99999]")),
    ("Replace cuts a line at 99999 again", "E16", sub("ide", "   rl.out := rl.line[rl.from, len(rl.line)]", "   rl.out := rl.line[rl.from, 99999]")),
    ("Query replace sets the text for each match", "E5", sub("ide", "            if qr.take then\n               qr.out := qr.new", "            if qr.take then\n               gosub ed.set\n               qr.out := qr.new")),
    ("Query replace has no Quit", "E5", sub("ide", "buttons 'Yes,No,All,Quit' default 1 returning qr.b else qr.b = 4", "buttons 'Yes,No,All' default 1 returning qr.b else qr.b = 2")),
    ("Query replace finds its matches in the shown text", "E5", sub("ide", "      qr.line = ed.src<qr.j>", "      qr.line = ed.t<qr.j>")),
    ("Query replace asks about the record's line, marks as characters", "E5", sub("ide", " : @vm : qr.shown", " : @vm : qr.line")),
    ("Query replace puts the record's marks in the text as characters", "E5", sub("ide", "   gosub ed.shown\n   if not(ed.ok) then return\n   ed.cy = qr.last", "   ed.cy = qr.last")),
    ("ed.source does not read the tab's token flag", "E14", sub("ide", "   ed.tok = bx{ed.kk}", "   ed.tok = 0")),
    ("ed.shown goes on when the token form refuses the record", "E14", sub("ide", "         ed.ok = @false", "         ed.ok = @true")),
    ("a refused Replace does not say that nothing was replaced", "E14", sub("ide", "msg = sysmsg(12239, 0) : '. ' : sysmsg(12997, ed.disp)", "msg = sysmsg(12997, ed.disp)")),
    ("ed.shown does not read the record back", "E14", sub("ide", "      call $recarr('totext', ed.new, ed.disp, ed.ok2)", "      ed.disp = ed.new ; ed.ok2 = 1")),
    ("Query replace writes when nothing was answered Yes", "E5", sub("ide", "   if qr.yes = 0 then\n      msg = sysmsg(12552, 0, qr.no)\n      return\n   end", "   if 0 then\n      msg = sysmsg(12552, 0, qr.no)\n      return\n   end")),
    ("List matching lines asks the read-only test", "E6", sub("ide", "do.view:\n   gosub ed.read", "do.view:\n   gosub ed.get")),
    ("List matching lines has no limit", "E6", sub("ide", "   until vw.n >= MAXHIT\n   next vw.j", "   next vw.j")),
    ("List matching lines marks the table 'search'", "E6", sub("ide", "   out.kind = 'view'\n   gosub zoom.leave", "   out.kind = 'search'\n   gosub zoom.leave")),
    ("Find options reads W as C", "E7", sub("ide", "   fo.word = (index(fo.text, 'W', 1) > 0)", "   fo.word = (index(fo.text, 'C', 1) > 0)")),
    ("the selection includes the character under the later end", "E8", sub("ide", "      if dc.j = sr.y2 then dc.z = sr.x2 - 1", "      if dc.j = sr.y2 then dc.z = sr.x2")),
    ("the selection ignores where it starts", "E8", sub("ide", "      if dc.j = sr.y1 then dc.a = sr.x1", "      dc.a = 1")),
    ("nothing selected is the whole text", "E8", sub("ide", "   if sr.y1 = sr.y2 and sr.x1 = sr.x2 then return\n   sr.ok = @true", "   sr.ok = @true")),
    ("Export asks the read-only test", "E9", sub("ide", "do.export:\n   gosub ed.read", "do.export:\n   gosub ed.get")),
    ("Export writes itself", "E9", sub("ide", "      msg = sysmsg(12696, wa.file, wa.id)\n      return\n   end\n   gosub write.copy\n   return\n\n* Search / Import", "      msg = sysmsg(12696, wa.file, wa.id)\n      return\n   end\n   write wa.text on fv, wa.id\n   return\n\n* Search / Import")),
    ("Write a copy loses the gate", "E9", sub("ide", "   open wa.file to fv else\n      msg = sysmsg(12205, wa.file)\n      return\n   end\n   gosub edit.check", "   open wa.file to fv else\n      msg = sysmsg(12205, wa.file)\n      return\n   end\n   edit.ok = 1")),
    ("Import takes a record with value marks", "E10", sub("ide", "   if index(im.x, @vm, 1) or index(im.x, @sm, 1) or index(im.x, @tm, 1) or convert(NA.CHARS, '', im.x) # im.x then", "   if convert(NA.CHARS, '', im.x) # im.x then")),
    ("Import takes a collection file's record", "E10", sub("ide", "if fileinfo(fv, FL$COLLECTION) then\n         msg = sysmsg(12562, im.file)", "if 0 then\n         msg = sysmsg(12562, im.file)")),
    ("Import refuses a collection file in the Find message's words", "E10", sub("ide", "      msg = sysmsg(12562, im.file)", "      msg = sysmsg(12703, im.file)")),
    ("Import cuts the line at 99999 again", "E10", sub("ide", "   im.block := im.ln[im.cx, len(im.ln)]", "   im.block := im.ln[im.cx, 99999]")),
    ("Export writes the token text, not the record", "E9", sub("ide", "         call $recarr('fromtext', wa.text, ex.rec, ed.ok2)\n         wa.text = ex.rec", "         null")),
    ("Export converts a cut that is inside a line", "E9", sub("ide", "      if sr.x1 = 1 and sr.x2 > len(xp.last) then", "      if 1 then")),
    ("Export reads another key for the token flag", "E9", sub("ide", "   ed.kk = 'm' : bu<cb>\n   if bx{ed.kk} then\n      * Only", "   ed.kk = 'n' : bu<cb>\n   if bx{ed.kk} then\n      * Only")),
    ("Go to takes a number over 32 bits", "E12", sub("ide", "      if gl.v > 99999999 then gl.v = 99999999", "      null")),
    ("a conditional assignment gives gl.p its value", "E15", sub("ide", "   gl.p = ''", "   if gl.k > 1 then gl.p = ''")),
    ("an element of gl.p is assigned before gl.p has a value", "E15", sub("ide", "   gl.p = ''", "   if 1 then gl.p<1> = 1\n   gl.p = ''")),
    ("Find in the records takes a text over 256 characters", "E16", sub("ide", "   if len(pat) > FINDMAX then", "   if 0 then")),
    ("the AI selection cuts the first line at 99999 again", "E16", sub("tk_ai", "t.part = t.ln[t.x1, len(t.ln)]", "t.part = t.ln[t.x1, 99999]")),
    ("Upcase cuts the last line at 99999 again", "E8", sub("ide", "dc.ln[dc.z + 1, len(dc.ln)]", "dc.ln[dc.z + 1, 99999]")),
    ("Import works in a read-only tab", "E10", sub("ide", "do.import:\n   gosub ed.get", "do.import:\n   gosub ed.read")),
    ("Run a command does not keep the copies first", "E11", sub("ide", "   gosub rc.tick\n   xq.out = ''", "   xq.out = ''")),
    ("Run a command does not take the locks again", "E11", sub("ide", "   execute xq.cmd trapping aborts capturing xq.out\n   gosub relock.all", "   execute xq.cmd trapping aborts capturing xq.out")),
    ("Run a command shows the output on the terminal", "E11", sub("ide", "   execute xq.cmd trapping aborts capturing xq.out", "   execute xq.cmd trapping aborts")),
    ("Run a command is not stopped when the command aborts", "E11", sub("ide", "   execute xq.cmd trapping aborts capturing xq.out", "   execute xq.cmd capturing xq.out")),
    ("Run a command forgets the table's rows", "E15", sub("ide", "   err.rows = ''\n   err.lines = ''\n   xq.n = 0", "   err.lines = ''\n   xq.n = 0")),
    ("Go to takes a zero", "E12", sub("ide", "      if gl.v < 1 then return", "      null")),
    ("Go to counts the value from the wrong mark", "E12", sub("ide", "index(gl.lo, ':@vm:', gl.p<2> + 0 - 1)", "index(gl.lo, ':@vm:', gl.p<2> + 0)")),
    ("Go to gives gl.p no value before its first element", "E12", sub("ide", "   gl.p = ''", "   null")),
    ("Go to gives gl.p no value before its first element (the element check)", "E15", sub("ide", "   gl.p = ''", "   null")),
    ("Go to takes a fraction", "E12", sub("ide", "      gl.v = int(gl.v + 0)", "      gl.v = gl.v + 0")),
    ("Go to finds only a lower case token", "E12", sub("ide", "   gl.lo = downcase(gl.ln)", "   gl.lo = gl.ln")),
    ("Go to stays at the value's start for a subvalue out of range", "E12", sub("ide", "         if gl.q = 0 then gl.q = index(gl.seg, ':@sm:', dcount(gl.seg, ':@sm:') - 1)", "         null")),
    ("Go to cuts the value at 99999 again", "E12", sub("ide", "gl.seg = gl.lo[gl.from, len(gl.lo)]", "gl.seg = gl.lo[gl.from, 99999]")),
    ("a message is empty", "E13", sub("m12551", "\n", "")),
    ("the length message is empty", "E13", sub("m12557", "\n", "")),
    ("the Import collection message is empty", "E13", sub("m12562", "\n", "")),
    ("the help forgets the new entries", "E13", sub("m12221", "Query replace", "Query")),
]

M_S184C = len(MUTANTS)          # 9 Nov 26 (S.184 stage 3): --selftest --from is not taken by this check; the marker says where this sitting's mutants begin
MUTANTS += [
    ("the select list is opened without asking", "E17", sub("ide", "         if sel0 # '' then\n            lq.n", "         if 0 then\n            lq.n")),
    ("No keeps the select list", "E17", sub("ide", "            if lq.b # 1 then\n               sel0 = ''", "            if lq.b = 3 then\n               sel0 = ''")),
    ("open.select forgets where the tabs ended", "E17", sub("ide", "   lst.next = os.open + 1", "   lst.next = 1")),
    ("Next record selects again", "E17", sub("ide", "      ns.id = lst.ids<lst.next>", "      readnext ns.id else exit")),
    ("Next record opens a record already in a tab again", "E17", sub("ide", "      if tf.p = 0 then\n         ns.done = @true", "      if 1 then\n         ns.done = @true")),
    ("Next record never says the list is used up", "E17", sub("ide", "      msg = sysmsg(15050, ns.n)", "      msg = ''")),
    ("the history keeps a dictionary item", "E18", sub("ide", "   if od = '' then gosub hist.push          ;*", "   gosub hist.push          ;*")),
    ("the history keeps a name twice", "E18", sub("ide", "   locate hp.item in hp.list<1> setting hp.at then del hp.list<hp.at>", "   null")),
    ("the history has no limit", "E18", sub("ide", "   if dcount(hp.list, @fm) > IH.MAX then hp.list = field(hp.list, @fm, 1, IH.MAX)", "   null")),
    ("Up and Down recall in Save as too", "E18", sub("ide_name", "case (nk = 'up' or nk = 'down') and mode = 'open'", "case (nk = 'up' or nk = 'down')")),
    ("the record entry recalls files", "E18", sub("ide_name", "if focus = 1 then hr.list = ih.files else hr.list = ih.recs", "hr.list = ih.files")),
    ("ide_name writes the history", "E18", sub("ide_name", "   hr.n = dcount(hr.list, @fm)", "   ih.recs = ''\n   hr.n = dcount(hr.list, @fm)")),
    ("ide_name's common is another shape", "E18", sub("ide_name", "common /idehist/ ih.on, ih.files, ih.recs", "common /idehist/ ih.files, ih.recs")),
    ("List of tabs counts the editor's text as it was", "E19", sub("ide", "   gosub stash.current                           ;* the tab in the editor", "   null                           ;* the tab in the editor")),
    ("List of tabs goes to a tab on Esc", "E19", sub("ide", "   if tq.st = 0 then\n      new.cb = tq.ret + 0", "   if 1 then\n      new.cb = tq.ret + 0")),
    ("the terminal command's output is captured", "E20", sub("ide", "   execute xm.cmd trapping aborts\n", "   execute xm.cmd trapping aborts capturing xm.out\n")),
    ("an abort of the terminal command ends the IDE", "E20", sub("ide", "   execute xm.cmd trapping aborts\n", "   execute xm.cmd\n")),
    ("the terminal command loses the editor's text", "E20", sub("ide", "   hp.item = xm.cmd\n   gosub hist.command\n   gosub stash.current\n", "   hp.item = xm.cmd\n   gosub hist.command\n")),
    ("the terminal command's screen comes back with no Press Return", "E20", sub("ide", "   execute xm.cmd trapping aborts\n   gosub retake.screen", "   execute xm.cmd trapping aborts\n   gosub retake.quiet")),
    ("the select list question is empty", "E21", sub("m15047", "A select list is active: %1 record(s), the first %2.  Open them in tabs?  (No leaves the list unused and clears it.)\n", "\n")),
    ("the help forgets List of tabs", "E21", sub("m12221", "List of tabs", "the tabs")),
]

M_S184D = len(MUTANTS)          # 9 Nov 26 (S.184 stage 4)
MUTANTS += [
    ("the hook runs after the write", "E22", sub("ide", "   gosub source.control.hook         ;*", "   null         ;*")),
    ("a refusal does not stop the save", "E22", sub("ide", "   if not(srcc.ok) then return\n", "   null\n")),
    ("the hook is called when it is not catalogued", "E22", sub("ide", "   if not(srcc.active) then return\n", "   null\n")),
    ("the screen is not drawn again", "E22", sub("ide", "   prompt ''\n   screen refresh\n", "   prompt ''\n")),
    ("a refusal keeps a lock the save took", "E22", sub("ide", "   if not(srcc.allowed) then\n      if not(sv.slot) then release fv, sv.id\n", "   if not(srcc.allowed) then\n")),
    ("an update does not reach what is written", "E22", sub("ide", "      end else\n         sv.out = sv.text\n      end\n   end\n   return", "      end\n   end\n   return")),
    ("an update does not reach the tab", "E22", sub("ide", "   if srcc.update then\n      k = 't' : u\n      bx{k} = sv.text\n", "   if srcc.update then\n")),
    ("the editor is not loaded again after an update", "E22", sub("ide", "   sv.reload = srcc.update ", "   sv.reload = @false ")),
    ("the hook is told it is not a full screen editor", "E22", sub("ide", "sv.text, 1, srcc.allowed", "sv.text, 0, srcc.allowed")),
    ("the compiler does not know HISTORY", "E23", sub("bcomp", ':@sm:"HISTORY:1"', "")),
    ("a password question recalls", "E23", sub("screen_ask", "hn = if mask # '' or hist = '' then 0", "hn = if hist = '' then 0")),
    ("Up runs past the oldest", "E23", sub("screen_ask", "      if hi >= hn then return\n", "")),
    ("what was typed is lost", "E23", sub("screen_ask", "      if hi = 0 then draft = w{'value'}\n", "")),
    ("the field is not drawn again", "E23", sub("screen_ask", "   call $sl_entry('draw', w, scr, '', r)\n", "")),
    ("the terminal prompt offers no history", "E23", sub("ide", "screen ask sysmsg(15053) history ih.cmds returning", "screen ask sysmsg(15053) returning")),
    ("a command is not remembered", "E23", sub("ide", "   hp.item = xq.cmd\n   gosub hist.command\n", "")),
    ("the memo takes keys past the macro", "E24", sub("sl_memo", "         gosub count\n         gosub macro.key", "         gosub count\n         gosub handle.key")),
    ("a program's passkey is taken for the macro", "E24", sub("sl_memo", " and not(index(@vm : w{'passkeys'} : @vm, @vm : key : @vm, 1)) then", " then")),
    ("a recording keeps the old keys", "E24", sub("sl_memo", "            w{'macrec'} = 1\n            w{'macro'} = ''\n", "            w{'macrec'} = 1\n")),
    ("a macro plays inside itself", "E24", sub("sl_memo", "      if w{'macrun'} + 0 then return\n", "")),
    ("the play runs past a key the area refused", "E24", sub("sl_memo", "      while m.ret<1> = 'handled'\n", "")),
    ("a refused key is recorded", "E24", sub("sl_memo", "and ret<1> = 'handled' and m.key # 'paste'", "and m.key # 'paste'")),
    ("a resize loses the macro", "E24", sub("ide", "      ed.macro = ow{'macro'}\n", "")),
    ("a word Spool does not know is ignored", "E25", sub("ide", "            msg = sysmsg(15057, sp.c)\n            return\n", "            null\n")),
    ("region with no selection prints everything", "E25", sub("ide", "      if not(sr.ok) then\n         msg = sysmsg(12556)\n         return\n      end\n      sp.from = sr.y1", "      sp.from = sr.y1")),
    ("a refused location leaves the printer on", "E25", sub("ide", "         sp.at = ''                           ;* nothing to put back: the location was not changed\n         gosub spool.close\n", "         sp.at = ''                           ;* nothing to put back: the location was not changed\n")),
    ("the banner is not put back", "E25", sub("ide", "   if sp.mode # 3 then call !setpu(PU$BANNER, 0, sp.banner, sp.code)\n", "")),
    ("the screen is left as the job left it", "E25", sub("ide", "   printer close\n   screen refresh\n", "   printer close\n")),
    ("a filter's output reaches the screen", "E26", sub("ide", " to 9' trapping aborts capturing lr.cap", " to 9' trapping aborts")),
    ("a refused filter lists on", "E26", sub("ide", "         lr.ok = @false\n         msg = sysmsg(15063, lr.tmpl)\n         return\n", "         lr.ok = @false\n")),
    ("a page does not skip", "E26", sub("ide", "   for lr.s = 1 to lr.skip ", "   for lr.s = 1 to 0 ")),
    ("Find in the records is filtered", "E26", sub("ide", "   gosub list.ids\n   lr.key = ''\n   if lr.more and lr.skip = 0", "   gosub list.ids\n   if lr.more and lr.skip = 0")),
    ("a new filter keeps the page", "E26", sub("ide", "   lt.page<fx.at> = 0\n", "")),
    ("a word is taken as a query", "E26", sub("ide", "            fx.t = 'with @id like \"' : fx.t : '\"'", "            null")),
]


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:200]))
        bad += 0 if ok else 1
    return bad


def selftest(src):
    base = [r[0] for r in checks(src) if not r[2]]
    if base:
        print("selftest: the unchanged tree fails %s, so a mutant's own failure cannot be told from the tree's; run the plain check first" % base)
        return 1
    holes = helper_selftest()
    for name, want, mut in MUTANTS:
        try:
            m = mut(src)
        except KeyError as exc:
            print("  [FAIL] selftest: %s  <- %s" % (name, exc))
            holes += 1
            continue
        failed = sorted({r[0] for r in checks(m) if not r[2]})
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        holes += 0 if hit else 1
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS), holes))
    return 1 if holes else 0


def main(argv):
    src = load()
    print("test-ideedit-units: tree %s" % os.path.dirname(GPL))
    if not src["ide"]:
        print("test-ideedit-units: CANNOT RUN - %s is not there" % os.path.join(GPL, "ide"))
        return 2
    rows = checks(src)
    bad = report(rows)
    print("\ntest-ideedit-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(src) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
