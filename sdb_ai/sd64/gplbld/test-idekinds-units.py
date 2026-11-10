#!/usr/bin/env python3
"""test-idekinds-units.py - the IDE's record kinds and locks (the editor merge, stage B; ~/Documents/Audits/TUI/Opus_TUI_Plan.txt section 11), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-idekinds-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-idekinds-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
28 Oct 26 dm  New with stage B.
28 Oct 26 dm  Two of the owner's approved items of 28 Oct: K30-K32 a record holding bytes 128 to 247 is read-only (na.mark, ro.check 'ascii', ro.box, na.check) and
              K33-K36 the AUTOLOGOUT countdown (idle.count, idle.text, messages 12755-12759 and 12766); K20 follows ro.box; 20 mutants from M_NA.  On a screen these
              are rows of sandbox-ide-kinds.py (NA) and sandbox-ide.py (IDLE), written, not run.
28 Oct 26 dm  Review fixes (findings 4 and 9 of the L2 review): K24 follows do.compile saving first only when there is something to save (is.dirty, untitled, new), two mutants;
              K33 and K34 follow the countdown reading the KERNEL's inactivity clock (kernel(K$AUTOLOGOUT, -2)) - the IDE's own bookkeeping (idle.count, IDL.SLACK, idl.t0/fp) is gone;
              four countdown mutants replaced.
29 Oct 26 dm  Review R3 and R8: K10, K37 and K39 follow the collection text in the text area's field-mark form (convert(char(10), @fm, jbuild(...))), the guard before JBUILD of the disk
              record, the text compare and the conditional reload; seven mutants replaced or added.
END-HISTORY

WHAT IT HOLDS (gpl.bp/ide).  `ide dict file id` and `ide voc id` start on a dictionary item or a VOC record; CREATING.SEQKEY in the place of the id takes the file's
next sequential id ($seqkey, after the account's edit gate), and the same word in quotes is a record of that name.  A file's records are listed by SELECT and READNEXT
stopped at MAXREC, never by an SSELECT of the whole file (the tree, Find in the records, a select list at the start).  The tree has a dictionary node under a file that
has a dictionary, and its items are read only when it is opened.  A record is opened under its lock (lock.take: READU through a file variable the tab keeps in tfv, the
LOCKED clause naming the holder by STATUS()), a collection file's record is refused BEFORE any read of it, a record another session holds opens read-only and cannot
be changed or saved, and a record that is not there opens as a new one only where the caller asked for it and only after the account's edit gate.  A tab that holds
its lock saves with WRITEU through that file variable and never RELEASEs it; closing a tab, every way out of the IDE, Save as and a Cancel give locks back; the screen
taken back from a program takes them again (RECORDLOCKU ... LOCKED).  The token form follows the kind (test-recarr-units.py I11-I14).  Every write asks edit.check on
the open file's own path.  A dictionary item is not compiled.

***IT RUNS NOTHING, SO IT CANNOT SAY THAT A LOCK IS HELD OR A GATE REFUSES***: that is sandbox-ide-kinds.py (a second live session holding a lock, an ordinary account
with dict-off, the disk as the evidence).  --selftest breaks each property the way an edit plausibly would and requires a check to notice.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
NEWMSG = list(range(12689, 12704))
NEWMSG2 = [12755, 12756, 12757, 12758, 12759, 12766]     # 28 Oct 26: the AUTOLOGOUT countdown and the read-only tab for bytes outside ASCII
FIELDS_LABELS = ("fields.enter", "fields.leave", "fields.view.on", "fields.form", "fields.apply", "fields.sync", "fields.sync.tab", "fields.parse", "fields.rebuild", "fields.drop", "fields.esc",
                 "fields.key", "fields.after", "fields.writeback", "fields.fill", "fields.pull", "fields.show", "fields.label")     # 30 Oct 26 (stage 2b): the pane's labels in gpl.bp/ide
NEWMSG3 = [12748, 12749, 12750]                         # 29 Oct 26 (stage F): JSON that will not parse, a collection record is not a program, a text is not saved into a collection file


def strip(src):
    """the code without comment lines and trailing ;* comments"""
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def label(text, name):
    """the body of internal subroutine `name:` up to the next label at the start of a line"""
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


def before(text, a, b):
    i, j = text.find(a), text.find(b)
    return 0 <= i < j


def load():
    src = {}
    try:
        with open(os.path.join(GPL, "ide"), encoding="latin-1") as f:
            src["ide"] = f.read()
    except OSError:
        src["ide"] = ""
    try:
        with open(os.path.join(GPL, "ide_name"), encoding="latin-1") as f:
            src["ide_name"] = f.read()
    except OSError:
        src["ide_name"] = ""
    for n in NEWMSG + NEWMSG2 + NEWMSG3 + [12220, 12231]:
        try:
            with open(os.path.join(MSG, str(n)), encoding="latin-1") as f:
                src["m%d" % n] = f.read()
        except OSError:
            src["m%d" % n] = ""
    return src


def checks(src):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    raw = src["ide"]
    ide = strip(raw)
    L = {n: label(ide, n) for n in ("load.file", "load.dict", "list.ids", "do.find", "tree.nodes", "do.act", "lock.take", "lock.free", "tab.unlock", "release.all",
                                     "tab.lock", "relock.all", "ro.check", "open.record", "save.one", "close.current", "retake.quiet", "do.saveas", "do.writeas",
                                     "seq.take", "do.new", "open.select", "do.compile", "do.include", "kind.of", "dict.trim", "load.current", "new.form",
                                     "do.replace", "do.fields", "ai.apply", "edit.check", "name.untitled", "add.new.record", "tab.find", "status.line",
                                     "tab.state", "ro.box", "idle.text", "rc.untitled", "coll.text", "coll.value", "path.not.for", "ed.get", "write.copy")}
    head = ide[: ide.find("gosub open.screen")]
    main = ide[: ide.find("apply.theme:")]
    ck("K0", "NULL CASE: the IDE was read and every routine this check reads is there (a check on nothing would pass)",
       len(ide) > 60000 and all(len(v) > 20 for v in L.values()), repr(sorted(k for k, v in L.items() if len(v) <= 20)))

    # ---- the start ----------------------------------------------------------------------------------------------------------------------------------------------------
    ck("K1", "the start form: a first word DICT sets the dictionary flag and moves the file and the id one word on; CREATING.SEQKEY (unquoted, any case) is seq0; an id in "
       "quotes loses them (so \"creating.seqkey\" is a record of that name); the file name is lower case",
       ordered(head, "dflag0 = ''", "if upcase(fn0) = 'DICT' then", "dflag0 = 'DICT'", "fn0 = field(sent.in, ' ', 3)", "id0 = field(sent.in, ' ', 4)",
               "fn0 = downcase(fn0)", "seq0 = (upcase(id0) = 'CREATING.SEQKEY')", "id0 = id0[2, len(id0) - 2]"), "")
    st = main[main.find("gosub new.form\n   begin case"):]
    ck("K2", "the start opens: CREATING.SEQKEY through seq.take and then a NEW record of that id; a named record with or.mknew = 1 (a record that is not there is a new one) and the "
       "dictionary flag; an active select list through open.select; the editor is never left without a buffer",
       ordered(st, "case fn0 # '' and seq0", "gosub seq.take", "if sq.id # '' then", "or.dict = dflag0", "or.mknew = 1", "gosub open.record",
               "case fn0 # '' and id0 # ''", "or.dict = dflag0", "or.mknew = 1", "gosub open.record", "case sel0 # ''", "gosub open.select", "if nbuf = 0 then", "gosub add.untitled"), "")
    ck("K3", "an active select list is read from list 0 BEFORE build.files, by READNEXT stopped at MAXREC (not READLIST, which would finish a list still being made), and then cleared",
       ordered(main, "if selectinfo(0, SL$ACTIVE) then", "readnext sel.id from 0 else exit", "if sel0.n >= MAXREC then", "clearselect 0", "gosub build.files")
       and "readlist" not in main[: main.find("gosub build.files")], "")
    ck("K4", "open.select lists every id read in the table (Return opens one, with the dictionary flag) and opens at most MAXSEL of them in tabs",
       ordered(L["open.select"], "for os.i = 1 to os.n", "sid<-1> = sel0<os.i>", "out.dict = dflag0", "gosub err.load", "if os.open > MAXSEL then os.open = MAXSEL",
               "for os.i = 1 to os.open", "or.dict = dflag0", "gosub open.record")
       and "or.dict = out.dict" in label(ide, "act.error"), "")

    # ---- bounded listing ------------------------------------------------------------------------------------------------------------------------------------------------
    li = L["list.ids"]
    ck("K5", "list.ids: SELECT fv TO 9 (made a group at a time) with ON ERROR, READNEXT stopped once MAXREC ids are read (lr.more), the ids put in order, and CLEARSELECT 9 at "
       "the end so a part-read select does not stay on the file",
       ordered(li, "select fv to 9 on error", "clearselect 9", "return", "loop", "readnext lr.id from 9 else exit", "if lr.n >= MAXREC then", "lr.more = @true", "exit",
               "locate lr.id in lr.ids<1,1> by 'AL' setting lr.p else null", "ins lr.id before lr.ids<1, lr.p>", "repeat", "clearselect 9")   # <1,1>: in <1> LOCATE walks fields (S.185)
       and li.count("sselect") == 1 and "execute 'sselect '" in li and "readlist" not in li, li[:200])      # 9 Nov 26: the one sselect is a filter's, which the person asked for (S.184 stage 5)
    ck("K6", "NO SSELECT AND NO READLIST OF A WHOLE FILE ANYWHERE in the IDE but the VOC walk of build.files: the tree (load.file, load.dict) and Find in the records (do.find) "
       "read through list.ids, and say when the list was cut (12224)",
       len(re.findall(r"^\s*sselect\b", ide, re.M)) == 1 and "sselect vocf to 9" in label(ide, "build.files")
       and all("gosub list.ids" in L[n] for n in ("load.file", "load.dict", "do.find"))
       and all("sselect" not in L[n] and "readlist" not in L[n] for n in ("load.file", "load.dict", "do.find"))
       and all("sysmsg(12224" in L[n] for n in ("load.file", "load.dict", "do.find")), "")
    ck("K7", "Find in the records refuses a collection file (12703) before it reads a record",
       ordered(L["do.find"], "if fileinfo(fv, FL$COLLECTION) then", "msg = sysmsg(12703, ctx.file)", "return", "gosub list.ids", "read r from fv"), "")

    # ---- the tree ---------------------------------------------------------------------------------------------------------------------------------------------------------
    tn = L["tree.nodes"]
    ck("K8", "the tree: a file that has a dictionary (ldict) gets a node of its own (12698, code D:), its items at depth 3 (code Q:) only once that dictionary is listed (dfiles)",
       ordered(tn, "if ldict<lp> then", "nodes<-1> = sysmsg(12698) : @sm : 2 : @sm : 'D:' : nm", "if dp then", "c2 = 'Q:' : nm : ':' : dids<1, j>",
               "nodes<-1> = dids<1, j> : @sm : 3 : @sm : c2", "ids = lrecs<lp>")
       and ordered(L["load.file"], "open 'DICT', lf.name to lf.dv then lf.dict = 1") and "del ldict<lp>" in L["do.act"], "")
    da = L["do.act"]
    ck("K9", "Return on the dictionary node reads its items THEN (load.dict, lazily) or closes it; Return on an item opens it with the dictionary flag",
       ordered(da, "case code[1, 2] = 'D:'", "gosub load.dict", "case code[1, 2] = 'R:' or code[1, 2] = 'Q:'", "if code[1, 2] = 'Q:' then or.dict = 'DICT'", "gosub open.record")
       and "open 'DICT', ld.name to fv" in L["load.dict"], "")

    # ---- the lock -----------------------------------------------------------------------------------------------------------------------------------------------------------
    lt = L["lock.take"]
    ck("K10", "lock.take opens the file WITH the dictionary flag, knows a collection file BEFORE any read (kind 'coll', not kind.of: a collection file has no dictionary part to ask about), and finds a free "
       "slot (12695 when there is none); since stage F (29 Oct 26) the record is READ as the collection it is and made text AFTER the read (coll.text), the lock given back when it is neither a "
       "collection nor an array (12689) or has no JSON form",
       ordered(lt, "open lk.dict, lk.file to fv else", "lk.coll = (fileinfo(fv, FL$COLLECTION) + 0 # 0)", "if lk.coll then", "lk.kind = 'coll'", "end else", "gosub kind.of",
               "if tused<lk.s> = '' then exit", "lk.err = sysmsg(12695)", "tfv(lk.s) = fv", "readu ", "if lk.coll and lk.err = '' and lk.exists then gosub coll.text", "if lk.err # '' then lk.got = @false")
       and lt.find("FL$COLLECTION") < lt.find("readu ") and lt.find("FL$COLLECTION") < lt.find("read lk.rec")
       and ordered(L["coll.text"], "lk.ct = jtype(lk.rec)", "convert(char(10), @fm, jbuild(lk.rec, JB$PRETTY))", "if lk.cj = '' then", "lk.err = sysmsg(12689, lk.name, lk.id)", "if lk.got then release tfv(lk.s), lk.id"), "")
    cx = L["coll.value"]
    ck("K37", "stage F: the text of a collection file's record is parsed by JPARSE with its STATUS() and INMAT() taken at once, and refused in a box (12748) unless it is a collection or an array; "
       "save.one writes sv.out - the parsed collection for kind 'coll', else the text - and compares the disk record AS JBUILD'S TEXT, in the text area's form (lines joined by field marks, "
       "as coll.text made it - 29 Oct 26 review R3), with what the tab read, AS TEXT; a disk value that is not a collection or an array (a read trigger's string: JBUILD would stop the program) is a "
       "change; the kept text is the JBUILD layout, so a compact text is not 'changed' for ever, and the editor is loaded again (its undo steps gone) only when that layout differs from what it showed",
       ordered(cx, "cv.y = jparse(convert(@fm, char(10), sv.text))", "cv.st = status()", "cv.at = inmat()", "cv.ok = (cv.st = 0)", "jtype(cv.y) = 'collection' or jtype(cv.y) = 'array'", "sysmsg(12748, sv.name, sv.id, cv.at)", "gosub refuse.box")
       and ordered(L["save.one"], "sv.out = sv.text", "if sv.kind = 'coll' then", "gosub coll.value", "if not(cv.ok) then return", "sv.out = cv.y", "readu disk from fv, sv.id locked",
                   "if sv.kind = 'coll' then", "if jtype(disk) = 'collection' or jtype(disk) = 'array' then", "disk = convert(char(10), @fm, jbuild(disk, JB$PRETTY))", "disk = ''",
                   "if (disk : '|') # (sv.saved : '|') then", "writeu sv.out on fv", "write sv.out on fv", "sv.reload = srcc.update", "if sv.kind = 'coll' then", "sv.shown = sv.text",
                   "sv.text = convert(char(10), @fm, jbuild(sv.out, JB$PRETTY))", "if (sv.text : '|') # (sv.shown : '|') then sv.reload = @true",
                   "k = 's' : u", "bx{k} = sv.text", "if sv.reload and sv.i = cb then gosub load.current"), "")
    ck("K38", "stage F: a record of a collection file that is not there opens as a NEW record holding {} (an empty collection), in open.record and in New record (add.new.record), unless the person took a copy",
       "if lk.kind = 'coll' and or.new and rc.choice # 'use' then tb.shown = '{}'" in L["open.record"]
       and "if lk.kind = 'coll' and rc.choice # 'use' then bx{k} = '{}'" in L["add.new.record"], "")
    fo = L["do.fields"]
    ck("K39", "stage F: Edit as fields on a collection record parses the tab's text FIRST (and says so in a box when it will not parse: the screen is not left), hands CED the collection with data type 0 and "
       "no file and no id (CED writes nothing), and takes the JBUILD text back; path.not.for is asked with pa.allow = 'coll' for this command only",
       ordered(fo, "pa.allow = 'coll'", "gosub path.not.for", "pa.allow = ''", "if pa.no then return", "fd.coll = (bx{k} = 'coll')", "gosub coll.value", "if not(cv.ok) then return", "fd.c = cv.y",
               "fz.type = 0", "fz.c = fd.c", "fz.type = 2", "gosub fields.enter")
       and ordered(label(ide, "fields.writeback"), "fz.txt = convert(char(10), @fm, jbuild(fz.nc, JB$PRETTY))")         # 30 Oct 26 (stage 2b): the JBUILD text goes back into the tab at each change
       and "pa.allow = ''" in main
       and 0 <= fo.find("pa.allow = 'coll'") < fo.find("gosub path.not.for")             # the allowance comes before the FIRST path.not.for of the command, not only before the one after a save
       and "gosub leave.screen" not in fo and "$cedit" not in fo
       and not re.search(r"\b(write|writeu|writev|delete|readu|execute)\b", "\n".join(label(ide, n) for n in FIELDS_LABELS)), "")
    pn = L["path.not.for"]
    ck("K40", "stage F: path.not.for refuses a collection record for compile, run, debug, catalog, SED, Save as and the include (12749) unless pa.allow is 'coll', and keeps its operating-system-file "
       "lines (12744) after it; the name form refuses a text saved into a collection file under a new name (12750) except for New record",
       ordered(pn, "pa.k = 'k' : bu<cb>", "if bx{pa.k} = 'coll' and pa.allow # 'coll' then", "sysmsg(12749, bn<cb>, bi<cb>)", "return", "if bn<cb> # 'path:' then return", "sysmsg(12744, bn<cb>, bi<cb>)")
       and ordered(strip(src["ide_name"]), "if mode # 'new' and (fileinfo(fv, FL$COLLECTION) + 0) # 0 then", "sysmsg(12750, ff)", "file = ff", "res = 'ok'")
       and all((re.search(r"gosub (\S+)", L[n]) or [None, ""])[1] == "path.not.for" for n in ("do.compile", "do.include")), "")
    ck("K11", "lock.take reads with READU THROUGH THE TAB'S OWN FILE VARIABLE tfv(slot), ON ERROR; LOCKED takes the holder from STATUS() and reads without a lock (read-only); the "
       "slot is kept only when this session got the lock, otherwise the file variable is let go",
       ordered(lt, "readu lk.rec from tfv(lk.s), lk.id on error", "end locked", "lk.owner = status()", "read lk.rec from tfv(lk.s), lk.id then", "end then", "lk.got = @true",
               "end else", "lk.got = @true", "if lk.got then", "lk.slot = lk.s", "tused<lk.s> = 1", "end else", "tfv(lk.s) = 0"), "")
    orc = L["open.record"]
    ck("K12", "open.record takes or.dict and or.mknew at its first statements and puts them back ('' and 0) before anything else is called, and looks for the record's tab by "
       "file, id AND dictionary flag",
       ordered(orc, "od = or.dict", "omk = or.mknew", "or.dict = ''", "or.mknew = 0", "tf.dict = od", "gosub tab.find") and orc.find("or.mknew = 0") < orc.find("gosub ")
       and "bx{tf.k} = tf.dict" in L["tab.find"], "")
    ck("K13", "open.record: the lock first; a record that is not there and that another session is making is refused (12691); with or.mknew the account's edit gate is asked BEFORE "
       "a tab is made (refused: the lock given back, the reason in a box), else 'not found' (12206) and the lock given back",
       ordered(orc, "gosub lock.take", "if lk.err # '' then", "if not(lk.exists) then", "if lk.owner # '' then", "msg = sysmsg(12691, or.name, or.id, lk.owner)", "return",
               "gosub rc.offer", "case omk", "gosub edit.check", "if not(edit.ok) then", "gosub lock.free", "gosub refuse.box", "return", "case 1", "gosub lock.free",
               "msg = sysmsg(12206, or.id, or.name)", "return", "nbuf += 1"), "")
    ck("K14", "open.record keeps the lock with the tab (tab.state: kind, dictionary flag, slot, owner) and says a read-only open (12694)",
       ordered(orc, "ts.kind = lk.kind", "ts.dict = od", "ts.slot = lk.slot", "ts.owner = lk.owner", "gosub tab.state", "msg = sysmsg(12694, or.name, or.id, lk.owner)")
       and ordered(L["tab.state"] if "tab.state" in L else label(ide, "tab.state"), "k = 'l' : uid", "bx{k} = ts.slot", "k = 'o' : uid", "bx{k} = ts.owner"), "")
    so = L["save.one"]
    ck("K15", "save.one: a read-only tab is refused first (ro.check); a tab holding its lock uses fv = tfv(slot), ITS OWN file variable, and writes with WRITEU, with no RELEASE "
       "on that path; a tab with none opens the file with its dictionary flag, writes and releases",
       ordered(so, "gosub ro.check", "if not(ro.ok) then", "gosub refuse.box", "return", "if bi<sv.i> = '' then", "sv.slot = bx{k} + 0", "if sv.slot then", "fv = tfv(sv.slot)",
               "end else", "open sv.dict, bn<sv.i> to fv else", "gosub edit.check", "readu disk from fv, sv.id locked", "if sv.slot then",
               "writeu sv.out on fv, sv.id on error", "end else", "write sv.out on fv, sv.id on error", "release fv, sv.id")
       and "release" not in so[so.find("writeu sv.out"): so.find("end else", so.find("writeu sv.out") + 1) + 10]
       and "if not(sv.slot) then release fv, sv.id" in so, "")
    ck("K16", "save.one compares a dictionary item with the disk record trimmed the same way (dict.trim: an A, C, I or S item without its compiled code from DICT.SYS.INFO on)",
       ordered(so, "if sv.kind = 'dict' then", "gosub dict.trim", "if (disk : '|') # (sv.saved : '|') then")
       and "dt.rec = trim(field(dt.rec, @fm, 1, DICT.SYS.INFO - 1), @fm, 'T')" in L["dict.trim"] and "$include dictdict.h" in raw
       and ordered(orc, "if lk.kind = 'dict' then", "gosub dict.trim"), "")
    ck("K17", "the locks are given back: tab.unlock RELEASEs through the tab's file variable and frees the slot; Close calls it before the tab goes; release.all runs for every tab "
       "before the screen is closed at the end; a Cancel in open.record gives back (lock.free)",
       ordered(L["tab.unlock"], "tu.s = bx{tu.k} + 0", "if tu.s then", "release tfv(tu.s), bi<tu.i>", "tfv(tu.s) = 0", "tused<tu.s> = ''", "bx{tu.k} = 0")
       and ordered(L["close.current"], "gosub tab.unlock", "del bn<cb>")
       and ordered(L["release.all"], "for tu.i = 1 to nbuf", "gosub tab.unlock")
       and ordered(ide, "until done\n   repeat", "gosub release.all", "screen close")
       and ordered(L["lock.free"], "release tfv(lk.slot), lk.id", "tfv(lk.slot) = 0", "tused<lk.slot> = ''"), "")
    ck("K18", "the screen taken back from a program (retake.quiet: Run, Debug, SED, CED) takes the locks again BEFORE the form is made, with RECORDLOCKU ... LOCKED through the tab's "
       "file variable; one another session took makes the tab read-only (12697)",
       ordered(L["retake.quiet"], "gosub open.screen", "gosub relock.all", "gosub new.form")
       and ordered(L["relock.all"], "recordlocku tfv(rl.s), bi<rl.i> locked", "rl.lost = @true", "rl.owner = status()", "if rl.lost then", "tused<rl.s> = ''", "bx{k} = rl.owner",
                   "msg = sysmsg(12697"), "")
    ck("K19", "Save as lets go of the old record's lock, clears read-only and the dictionary flag, and takes the new record's lock; a record open in another tab is refused (12696) "
       "by Save as, Write a copy, New record and the first save of an untitled buffer",
       ordered(L["do.saveas"], "gosub tab.find", "msg = sysmsg(12696, sa.file, sa.id)", "gosub tab.unlock", "k = 'o' : u", "bx{k} = ''", "k = 'd' : u", "bx{k} = ''", "gosub tab.lock",
               "gosub save.one")
       and all("sysmsg(12696" in L[n] and "gosub tab.find" in L[n] for n in ("do.writeas", "do.new", "name.untitled"))
       and ordered(L["name.untitled"], "gosub tab.find", "bn<sv.i> = nm.file", "gosub tab.lock"), "")
    ck("K20", "a read-only tab: the memo is readonly while bx o is set (load.current, new.form); Replace, Edit as fields and an AI edit refuse it (ro.check), the status line "
       "names the holder (12692)",
       "ro = (bx{k} # '')" in L["load.current"] and "ed.ro = (bx{k} # '')" in L["new.form"]
       and all(ordered(L[n], "ro.i = cb", "gosub ro.check", "if not(ro.ok) then", "gosub ro.box", "return") for n in ("do.fields", "ai.apply", "ed.get"))
       and "gosub ed.get" in L["do.replace"]                       # (Replace and the other editing commands of stage D ask the same test through ed.get)
       and "sysmsg(12692, bx{k})" in L["status.line"] and "msg = sysmsg(12693, bf.name, bf.id, bx{ro.k})" in L["ro.check"], "")

    # ---- the gates, seqkey, compile, SED, include -----------------------------------------------------------------------------------------------------------------------
    ck("K21", "edit.check asks the kernel on the OPEN file's own path (K$EDIT.OK with fileinfo(fv, FL$PATH)); every way to write asks it: save.one, Write a copy, CREATING.SEQKEY "
       "before the id is taken, and a new record named on the command line before its tab",
       ordered(L["edit.check"], "edit.p = fileinfo(fv, FL$PATH)", "if kernel(K$EDIT.OK, edit.p) then return")
       and ordered(L["write.copy"], "open wa.file to fv else", "gosub edit.check", "write wa.text on fv") and "gosub write.copy" in L["do.writeas"]       # (stage D: Write a copy and Export write through write.copy)
       and ordered(L["seq.take"], "open sq.dict, sq.file to fv else", "gosub edit.check", "if not(edit.ok) then", "return", "call $seqkey(fv, @true, sq.id, sq.why)")
       and ordered(L["save.one"], "gosub edit.check", "write"), "")
    ck("K22", "New record: CREATING.SEQKEY (any case) takes the next sequential id through seq.take; in quotes it is a record of that name",
       ordered(L["do.new"], "if upcase(nm.id) = 'CREATING.SEQKEY' then", "gosub seq.take", "if sq.id = '' then return", "nm.id = sq.id", "end else",
               "nm.id = nm.id[2, len(nm.id) - 2]", "gosub add.new.record"), "")
    ck("K23", "New record locks the new record for its creation after the recovery copy's question, and refuses one that is now there (12222) or being made (12691)",
       ordered(L["add.new.record"], "gosub rc.offer", "if rc.choice = 'cancel' then return", "gosub lock.take", "if lk.exists then", "gosub lock.free",
               "msg = sysmsg(12222, nm.id, nm.file)", "if lk.owner # '' then", "msg = sysmsg(12691", "nbuf += 1", "ts.slot = lk.slot", "gosub tab.state"), "")
    ck("K24", "a dictionary item is not compiled (12702, after the save, before BASIC is run), and SED is given DICT for one; the save before a build is made only when there is "
       "something to save (a changed text, an untitled buffer or a record not on the disk yet), so a read-only tab with nothing to save can be compiled, run, debugged and catalogued",
       ordered(L["do.compile"], "gosub stash.current", "gosub is.dirty", "if dirty or bi<cb> = '' or bx{k} then", "gosub save.current", "if not(sv.ok) then return",
               "if bx{k} = 'dict' then", "msg = sysmsg(12702, c.file, c.id)", "return", "execute 'basic '")
       , "")
    di = L["do.include"]
    ck("K25", "Open the include: the first word is $include (a comment after ; is cut), one word looks in the tab's file and then syscom, two words name the file; a collection file "
       "is passed over before a read; not found says where it looked (12701); found opens it through open.record",
       ordered(di, "in.line = trim(field(in.line, ';', 1))", "if downcase(field(in.line, ' ', 1)) # '$include' then", "msg = sysmsg(12700)", "case in.n = 2", "in.files = bn<cb>",
               "in.files<-1> = 'syscom'", "case in.n = 3", "in.files = field(in.line, ' ', 2)", "if fileinfo(fv, FL$COLLECTION) then continue", "read in.x from fv, in.rec on error",
               "msg = sysmsg(12701", "gosub open.record"), "")
    ko = L["kind.of"]
    ck("K26", "kind.of: dict for the dictionary flag, voc / dict / source from the kernel's own edit kind of the open file's path, source for a directory file, data otherwise",
       ordered(ko, "ko.kind = 'data'", "if ko.dict # '' then", "ko.kind = 'dict'", "ko.ek = kernel(K$EDIT.KIND, fileinfo(fv, FL$PATH))", "case ko.ek = 1", "ko.kind = 'voc'",
               "case ko.ek = 2", "ko.kind = 'dict'", "case ko.ek = 3", "ko.kind = 'source'", "case fileinfo(fv, FL$TYPE) = FL$TYPE.DIR", "ko.kind = 'source'"), "")
    ck("K27", "the file variables of the locks: dim tfv(MAXLOCK) at the start, every slot 0, no slot in use",
       ordered(head, "MAXLOCK = 100", "dim tfv(MAXLOCK)", "mat tfv = 0", "tused = ''"), "")

    # ---- messages -----------------------------------------------------------------------------------------------------------------------------------------------------------
    miss = [n for n in NEWMSG if not src["m%d" % n].strip()]
    want = {12689: "%2", 12690: "%2", 12691: "%3", 12692: "%1", 12693: "%3", 12694: "%3", 12696: "%2", 12697: "%3", 12699: "%2", 12701: "%2", 12702: "%2", 12703: "%1"}
    bad = [n for n, p in want.items() if p not in src["m%d" % n]]
    cited = [n for n in NEWMSG if ("sysmsg(%d" % n) not in ide]
    ck("K28", "messages 12689-12703 are there, each takes the substitutions the IDE passes, and the IDE cites every one of them",
       not miss and not bad and not cited, repr((miss, bad, cited)))
    ck("K29", "the help names the locks and the include; the Go menu has Open the include",
       "Locks" in src["m12220"] and "read-only" in src["m12220"] and "Open the include" in src["m12220"] and "&Open the include~~include" in src["m12231"], "")

    loop = ide[ide.find("   loop\n      gosub fields.sync"): ide.find("until done")]
    ck("K33", "the countdown keeps no clock of its own (28 Oct 26, the L2 review: the IDE's guess was late by an AI wait and by a stall): no idl.t0, idl.fp, idl.el, idl.now, idle.count or "
       "IDL.SLACK anywhere in the IDE and no idl.ms set to 0; the loop waits one second and a timeout runs rc.tick; a program run needs no reset in retake.quiet",
       not any(w in ide for w in ("idl.t0", "idl.fp", "idl.el", "idl.now", "idle.count", "IDL.SLACK", "idl.ms = 0"))
       and ordered(loop, "gosub fields.sync", "gosub status.line", "screen wait f timeout 1 returning ev then", "case ev<1> = 'timeout'", "gosub rc.tick", "case 1", "gosub fields.esc")
       and ordered(label(ide, "fields.esc"), "if fv.on and focus.id = 'fld' then", "if fz.st{'path'} # '' then", "fz.key = 'esc'", "gosub fields.key", "return", "cmd = 'menu'", "gosub run.cmd"), loop[:150])
    ck("K34", "idle.text reads the time waited with nothing typed from the KERNEL's inactivity clock (K$AUTOLOGOUT asked with -2), after the period test and before the seconds left "
       "are worked out, and nothing else assigns idl.ms",
       ordered(L["idle.text"], "idl.al = kernel(K$AUTOLOGOUT, -1) + 0", "if idl.al <= 0 then return", "idl.ms = kernel(K$AUTOLOGOUT, -2) + 0", "idl.left = int((idl.al - idl.ms + 999) / 1000)")
       and len(re.findall(r"\bidl\.ms\s*(?:\+|-)?=", ide)) == 1, "")
    ck("K35", "idle.text: the period is the kernel's (K$AUTOLOGOUT asked with -1, as the autologout verb asks it) and 0 shows nothing; the line shows only in the last IDL.WARN (60) "
       "seconds; no unsaved change says 12757, unsaved changes 12756 with the recovery switch on and 12755 without; the status line puts it first",
       ordered(L["idle.text"], "idl.txt = ''", "idl.al = kernel(K$AUTOLOGOUT, -1) + 0", "if idl.al <= 0 then return", "idl.left = int((idl.al - idl.ms + 999) / 1000)",
               "if idl.left > IDL.WARN then return", "gosub is.dirty", "case not(idl.dirty)", "sysmsg(12757, idl.left)", "case rc.on", "sysmsg(12756, idl.left)", "case 1",
               "sysmsg(12755, idl.left)")
       and re.search(r"^\s*IDL\.WARN = 60\b", main, re.M) is not None
       and ordered(L["status.line"], "gosub idle.text", "if idl.txt # '' then t = idl.txt", "t = '[' : pn : ']'"), "")
    m2 = {n: src["m%d" % n] for n in NEWMSG2}
    ck("K41", "stage F: messages 12748-12750 are there, one line each; 12748 takes the character the parse stopped at (%3), 12749 and 12750 are cited by the IDE and the name form",
       all(src["m%d" % n].strip() and src["m%d" % n].count("\n") == 1 for n in NEWMSG3) and "%3" in src["m12748"] and "%2" in src["m12749"] and "sysmsg(12748" in ide and "sysmsg(12749" in ide
       and "sysmsg(12750" in strip(src["ide_name"]), "")
    ck("K36", "messages 12755-12759 and 12766 are there, one line each; the countdown's three begin 'Idle: signing out in %1 s' and say what happens to the changes; the refusal "
       "and the open note name the record (%1 %2); the help names the read-only rule and the countdown",
       all(t.count("\n") == 1 and t.endswith("\n") for t in m2.values())
       and all(m2[n].startswith("Idle: signing out in %1 s") for n in (12755, 12756, 12757))
       and "unsaved changes will be lost" in m2[12755] and "recovery copy is kept" in m2[12756]
       and "%1 %2" in m2[12759] and "%1 %2" in m2[12766] and "ASCII" in m2[12758]
       and "outside ASCII" in src["m12220"] and "counts down" in src["m12220"] and "AUTOLOGOUT" not in "".join(m2.values()) + src["m12220"], repr({n: t[:30] for n, t in m2.items()}))
    return rows


def sub(key, old, new):
    def f(src):
        r = dict(src)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:80]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


MUTANTS = [
    ("the DICT word is not read", "K1", sub("ide", "   if upcase(fn0) = 'DICT' then\n      dflag0 = 'DICT'", "   if upcase(fn0) = 'DICTX' then\n      dflag0 = 'DICT'")),
    ("a quoted id keeps its quotes", "K1", sub("ide", "then id0 = id0[2, len(id0) - 2]", "then null")),
    ("a named record that is not there is 'not found' again", "K2", sub("ide", "         or.mknew = 1                          ;* 28 Oct 26 (stage B): a record that is not there", "         null                          ;* 28 Oct 26 (stage B): a record that is not there")),
    ("the select list is read whole", "K3", sub("ide", "            readnext sel.id from 0 else exit\n", "            readlist sel0 from 0 else exit\n")),
    ("the select list is not bounded", "K3", sub("ide", "            if sel0.n >= MAXREC then\n               sel0.more = @true", "            if 0 then\n               sel0.more = @true")),
    ("every listed record opens in a tab", "K4", sub("ide", "   if os.open > MAXSEL then os.open = MAXSEL\n", "")),
    ("the tree sorts the whole file again", "K6", sub("ide", "   gosub list.ids\n   if lr.more then msg = sysmsg(12224, MAXREC, lf.name)", "   sselect fv to 9\n   readlist lr.ids from 9 else lr.ids = ''\n   if lr.more then msg = sysmsg(12224, MAXREC, lf.name)")),
    ("list.ids does not stop", "K5", sub("ide", "      if lr.n >= MAXREC then\n         lr.more = @true\n         exit\n      end\n", "")),
    ("list.ids leaves the select open", "K5", sub("ide", "   repeat\n   clearselect 9                       ;* a select left part read", "   repeat\n   null                       ;* a select left part read")),
    ("Find reads a collection file", "K7", sub("ide", "   if fileinfo(fv, FL$COLLECTION) then\n      msg = sysmsg(12703, ctx.file)", "   if 0 then\n      msg = sysmsg(12703, ctx.file)")),
    ("the dictionary node is never shown", "K8", sub("ide", "         if ldict<lp> then\n            nn += 1", "         if 0 then\n            nn += 1")),
    ("a dictionary item opens as a data record", "K9", sub("ide", "               if code[1, 2] = 'Q:' then or.dict = 'DICT'", "               null")),
    ("a collection record is read as a text (the collection is not known before the read)", "K10", sub("ide", "   lk.coll = (fileinfo(fv, FL$COLLECTION) + 0 # 0)", "   lk.coll = 0")),
    ("a collection record is shown without its JSON", "K10", sub("ide", "   if lk.coll and lk.err = '' and lk.exists then gosub coll.text", "   null")),
    ("a record that is not a collection keeps its lock", "K10", sub("ide", "      if lk.got then release tfv(lk.s), lk.id ", "      null ")),
    ("a collection record is treated as a dictionary-part kind", "K10", sub("ide", "   if lk.coll then\n      lk.kind = 'coll'\n   end else", "   if 0 then\n      lk.kind = 'coll'\n   end else")),
    ("JSON that will not parse is written", "K37", sub("ide", "      gosub coll.value\n      if not(cv.ok) then return\n      sv.out = cv.y", "      cv.ok = 1\n      sv.out = sv.text")),
    ("the status is read after INMAT", "K37", sub("ide", "   cv.st = status()\n   cv.at = inmat()", "   cv.at = inmat()\n   cv.st = status()")),
    ("a plain value passes for a collection", "K37", sub("ide", "   if cv.ok then cv.ok = (jtype(cv.y) = 'collection' or jtype(cv.y) = 'array')", "   null")),
    ("the disk record is compared as a collection variable, not as text", "K37", sub("ide", "            disk = convert(char(10), @fm, jbuild(disk, JB$PRETTY))", "            null")),
    ("the disk record is compared in JBUILD's own line feeds", "K37", sub("ide", "            disk = convert(char(10), @fm, jbuild(disk, JB$PRETTY))", "            disk = jbuild(disk, JB$PRETTY)")),
    ("a disk value that is not a collection reaches JBUILD", "K37", sub("ide", "         if jtype(disk) = 'collection' or jtype(disk) = 'array' then\n            disk = convert", "         if 1 then\n            disk = convert")),
    ("the disk record is compared as a number", "K37", sub("ide", "      if (disk : '|') # (sv.saved : '|') then", "      if disk # sv.saved then")),
    ("the text written is the typed text", "K37", sub("ide", "      sv.text = convert(char(10), @fm, jbuild(sv.out, JB$PRETTY))\n", "")),
    ("JPARSE is given the field marks of the text area", "K37", sub("ide", "cv.y = jparse(convert(@fm, char(10), sv.text))", "cv.y = jparse(sv.text)")),
    ("the kept text has JBUILD's line feeds", "K37", sub("ide", "      sv.text = convert(char(10), @fm, jbuild(sv.out, JB$PRETTY))\n", "      sv.text = jbuild(sv.out, JB$PRETTY)\n")),
    ("the editor is loaded again after every save of a collection record", "K37", sub("ide", "   if sv.reload and sv.i = cb then gosub load.current", "   if sv.kind = 'coll' and sv.i = cb then gosub load.current")),
    ("a collection record is read with JBUILD's line feeds", "K10", sub("ide", "lk.cj = convert(char(10), @fm, jbuild(lk.rec, JB$PRETTY))", "lk.cj = jbuild(lk.rec, JB$PRETTY)")),
    ("a new collection record starts empty text", "K38", sub("ide", "   if lk.kind = 'coll' and or.new and rc.choice # 'use' then tb.shown = '{}'", "   null")),
    ("New record in a collection file starts empty text", "K38", sub("ide", "   if lk.kind = 'coll' and rc.choice # 'use' then bx{k} = '{}'", "   null")),
    ("Edit as fields does not parse first", "K39", sub("ide", "      gosub coll.value\n      if not(cv.ok) then return\n      fd.c = cv.y", "      fd.c = collection()")),
    ("the fields view is given the data mode for a collection", "K39", sub("ide", "      fz.type = 0\n      fz.c = fd.c", "      fz.type = 2\n      fz.c = fd.c")),
    ("the fields view writes the record itself", "K39", sub("ide", "fields.after:\n   fz.st{'done'} = @false", "fields.after:\n   writeu fz.nc on fv, fd.id\n   fz.st{'done'} = @false")),
    ("the screen is left for the fields view again", "K39", sub("ide", "   fz.title = fd.file : ' ' : fd.id\n   gosub fields.enter", "   gosub leave.screen\n   fz.title = fd.file : ' ' : fd.id\n   gosub fields.enter")),
    ("the pane's write-back loses JBUILD's line feeds", "K39", sub("ide", "      fz.txt = convert(char(10), @fm, jbuild(fz.nc, JB$PRETTY))", "      fz.txt = jbuild(fz.nc, JB$PRETTY)")),
    ("the loop does not keep the pane in step with the text", "K33", sub("ide", "      gosub fields.sync                           ;* 30 Oct 26", "      null                                        ;* 30 Oct 26")),
    ("Esc in the pane always opens the menu", "K33", sub("ide", "      if fz.st{'path'} # '' then\n         msg = ''\n         fz.key = 'esc'", "      if 0 then\n         msg = ''\n         fz.key = 'esc'")),
    ("a collection record is compiled", "K40", sub("ide", "   if bx{pa.k} = 'coll' and pa.allow # 'coll' then", "   if 0 then")),
    ("Edit as fields is refused for a collection", "K39", sub("ide", "   pa.allow = 'coll'                    ;* 29 Oct 26 (stage F)", "   pa.allow = ''                    ;* 29 Oct 26 (stage F)")),
    ("a stage F message is empty", "K41", sub("m12749", "\n", "")),
    ("a text is saved into a collection file under a new name", "K40", sub("ide_name", "                  if mode # 'new' and (fileinfo(fv, FL$COLLECTION) + 0) # 0 then", "                  if 0 then")),
    ("the dictionary flag is not used to open", "K10", sub("ide", "   open lk.dict, lk.file to fv else\n      lk.err", "   open lk.file to fv else\n      lk.err")),
    ("the lock is taken through fv, not the tab's variable", "K11", sub("ide", "   readu lk.rec from tfv(lk.s), lk.id on error", "   readu lk.rec from fv, lk.id on error")),
    ("a record another session holds is taken over", "K11", sub("ide", "      lk.owner = status()\n      read lk.rec from tfv(lk.s), lk.id then", "      read lk.rec from tfv(lk.s), lk.id then")),
    ("or.mknew is not put back", "K12", sub("ide", "   or.dict = ''\n   or.mknew = 0\n   tf.dict = od", "   or.dict = ''\n   tf.dict = od")),
    ("the tab of the data record is taken for the dictionary item", "K12", sub("ide", "and bx{tf.k} = tf.dict then", "then")),
    ("a new record skips the gate", "K13", sub("ide", "         case omk\n            * 28 Oct 26 (stage B): a record named on the command line that is not there is a new one - after the account's edit gate, as the name form asks it\n            gosub edit.check\n            if not(edit.ok) then",
                                                "         case omk\n            * 28 Oct 26 (stage B): a record named on the command line that is not there is a new one - after the account's edit gate, as the name form asks it\n            edit.ok = 1\n            if not(edit.ok) then")),
    ("a record being made elsewhere is opened", "K13", sub("ide", "      if lk.owner # '' then\n         msg = sysmsg(12691, or.name, or.id, lk.owner)     ;* %1 %2 is being made", "      if 0 then\n         msg = sysmsg(12691, or.name, or.id, lk.owner)     ;* %1 %2 is being made")),
    ("the tab forgets its lock", "K14", sub("ide", "   ts.slot = lk.slot\n   ts.owner = lk.owner\n   gosub tab.state\n   tm.u = uid", "   ts.slot = 0\n   ts.owner = lk.owner\n   gosub tab.state\n   tm.u = uid")),
    ("a read-only tab is saved", "K15", sub("ide", "save.one:\n   sv.ok = @false\n   ro.i = sv.i\n   gosub ro.check", "save.one:\n   sv.ok = @false\n   ro.i = sv.i\n   ro.ok = 1")),
    ("the save opens its own file variable (the lock moves to it)", "K15", sub("ide", "   if sv.slot then\n      fv = tfv(sv.slot)\n   end else", "   if sv.slot then\n      open sv.dict, bn<sv.i> to fv else null\n   end else")),
    ("the save gives the tab's lock away", "K15", sub("ide", "      writeu sv.out on fv, sv.id on error", "      write sv.out on fv, sv.id on error")),
    ("a dictionary item always looks changed", "K16", sub("ide", "      if sv.kind = 'dict' then\n         dt.rec = disk\n         gosub dict.trim", "      if 0 then\n         dt.rec = disk\n         gosub dict.trim")),
    ("Close keeps the lock", "K17", sub("ide", "   tu.i = cb\n   gosub tab.unlock                              ;* 28 Oct 26 (stage B): and its record's lock", "   tu.i = cb")),
    ("the end keeps the locks", "K17", sub("ide", "   gosub release.all                           ;* 28 Oct 26 (stage B)", "   null                           ;* 28 Oct 26 (stage B)")),
    ("Cancel keeps the lock", "K17", sub("ide", "lock.free:\n   if lk.slot then\n      release tfv(lk.slot), lk.id", "lock.free:\n   if lk.slot then\n      null")),
    ("the locks are not taken back after a program", "K18", sub("ide", "   gosub relock.all                      ;* 28 Oct 26 (stage B)", "   null                      ;* 28 Oct 26 (stage B)")),
    ("a lost lock leaves the tab writable", "K18", sub("ide", "            bx{k} = rl.owner\n", "            null\n")),
    ("Save as keeps the old record's lock", "K19", sub("ide", "   tu.i = cb\n   gosub tab.unlock\n   u = bu<cb>\n   k = 'o' : u", "   tu.i = cb\n   u = bu<cb>\n   k = 'o' : u")),
    ("Write a copy writes a record open in a tab", "K19", sub("ide", "   if tf.p then\n      msg = sysmsg(12696, wa.file, wa.id)\n      return\n   end\n", "")),
    ("a read-only tab is editable", "K20", sub("ide", "      ro = (bx{k} # '')", "      ro = 0")),
    ("Replace changes a read-only tab (the shared test of the editing commands is gone)", "K20", sub("ide", "ed.get:\n   ed.ok = @false\n   if nbuf = 0 then\n      msg = sysmsg(12223)\n      return\n   end\n   ro.i = cb\n   gosub ro.check", "ed.get:\n   ed.ok = @false\n   if nbuf = 0 then\n      msg = sysmsg(12223)\n      return\n   end\n   ro.i = cb\n   ro.ok = 1")),
    ("CREATING.SEQKEY skips the gate", "K21", sub("ide", "      msg = sysmsg(12205, sq.name)\n      return\n   end\n   gosub edit.check", "      msg = sysmsg(12205, sq.name)\n      return\n   end\n   edit.ok = 1")),
    ("New record does not take CREATING.SEQKEY", "K22", sub("ide", "   if upcase(nm.id) = 'CREATING.SEQKEY' then\n      sq.dict = ''", "   if 0 then\n      sq.dict = ''")),
    ("New record takes no lock", "K23", sub("ide", "   lk.dict = ''\n   lk.file = nm.file\n   lk.id = nm.id\n   gosub lock.take\n", "   lk.dict = ''\n   lk.file = nm.file\n   lk.id = nm.id\n   lk.slot = 0 ; lk.err = '' ; lk.exists = 0 ; lk.owner = ''\n")),
    ("a dictionary item is compiled", "K24", sub("ide", "   if bx{k} = 'dict' then\n      msg = sysmsg(12702, c.file, c.id)", "   if 0 then\n      msg = sysmsg(12702, c.file, c.id)")),
    ("SED gets the data record for a dictionary item", "K24", sub("ide", "   if sd.dict # '' then qp.f = 'dict ' : qp.f\n", "")),
    ("a build saves first whatever the tab holds (a read-only tab cannot be built)", "K24", sub("ide", "   if dirty or bi<cb> = '' or bx{k} then\n      gosub save.current", "   if 1 then\n      gosub save.current")),
    ("a new record or an untitled buffer is built without its save", "K24", sub("ide", "   if dirty or bi<cb> = '' or bx{k} then\n      gosub save.current", "   if dirty then\n      gosub save.current")),
    ("the include does not look in syscom", "K25", sub("ide", "         if in.files # 'syscom' then in.files<-1> = 'syscom'\n", "")),
    ("the include reads a collection record", "K25", sub("ide", "      if fileinfo(fv, FL$COLLECTION) then continue\n", "")),
    ("a directory file is data", "K26", sub("ide", "      case fileinfo(fv, FL$TYPE) = FL$TYPE.DIR\n         ko.kind = 'source'", "      case fileinfo(fv, FL$TYPE) = FL$TYPE.DIR\n         ko.kind = 'data'")),
    ("the VOC is data", "K26", sub("ide", "      case ko.ek = 1\n         ko.kind = 'voc'", "      case ko.ek = 1\n         ko.kind = 'data'")),
    ("a message loses its user number", "K28", sub("m12694", "%3", "a user")),
    ("the help forgets the locks", "K29", sub("m12220", "Locks            ", "Records          ")),
]
# 28 Oct 26: bytes outside ASCII and the AUTOLOGOUT countdown (approved by the owner)
M_NA = len(MUTANTS)
MUTANTS += [
    ("the IDE keeps its own clock again: the start of a wait is noted", "K33", sub("ide", "      screen wait f timeout 1 returning ev then\n", "      idl.t0 = system(1081)\n      screen wait f timeout 1 returning ev then\n")),
    ("Esc zeroes a count of the IDE's own", "K33", sub("ide", "            case 1\n               gosub fields.esc         ;* Esc", "            case 1\n               idl.ms = 0\n               gosub fields.esc         ;* Esc")),
    ("the countdown reads the period as the clock", "K34", sub("ide", "idl.ms = kernel(K$AUTOLOGOUT, -2) + 0", "idl.ms = kernel(K$AUTOLOGOUT, -1) + 0")),
    ("the clock is read before the period is known", "K34", sub("ide", "   if idl.al <= 0 then return\n   idl.ms = kernel(K$AUTOLOGOUT, -2) + 0", "   idl.ms = kernel(K$AUTOLOGOUT, -2) + 0\n   if idl.al <= 0 then return")),
    ("the countdown shows with AUTOLOGOUT off", "K35", sub("ide", "   if idl.al <= 0 then return\n", "")),
    ("the countdown shows the whole period", "K35", sub("ide", "   if idl.left > IDL.WARN then return\n", "")),
    ("unsaved changes are said to be kept without the switch", "K35", sub("ide", "      case rc.on\n         idl.txt = sysmsg(12756, idl.left)", "      case 1\n         idl.txt = sysmsg(12756, idl.left)")),
    ("the countdown is not on the status line", "K35", sub("ide", "   if idl.txt # '' then t = idl.txt", "   if 0 then t = idl.txt")),
    ("the countdown names the verb in capitals", "K36", sub("m12220", "With autologout set", "With AUTOLOGOUT set")),
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
    holes = 0
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
    print("test-idekinds-units: tree %s" % os.path.dirname(GPL))
    if not src["ide"]:
        print("test-idekinds-units: CANNOT RUN - %s is not there" % os.path.join(GPL, "ide"))
        return 2
    rows = checks(src)
    bad = report(rows)
    print("\ntest-idekinds-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(src) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
