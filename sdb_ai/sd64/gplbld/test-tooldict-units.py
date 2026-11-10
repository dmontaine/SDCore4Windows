#!/usr/bin/env python3
"""test-tooldict-units.py - the dictionary page, TOOL.DICT (`gpl.bp/tool_dict`), as invariants read off the source (S.75, development app DV2).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-tooldict-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT AN ITEM IS WRITTEN, REFUSED, DELETED OR COMPILED***: that is
`sandbox-tool-dict.py` (a private SD, ordinary sessions on a pseudo-terminal, the disk as the evidence).  What a text check is for: the properties that make the page a FRONT END for an account
holder, which are mostly ORDER and ABSENCE, and an edit that moves one still compiles.  The one that matters most is the page's ONE WRITE: the page is $internal, so the kernel does not refuse a
write to a dictionary on its own account; the page asks (K$EDIT.OK, as SED and the IDE do) BEFORE the write, and a page that forgot would write into a dictionary the person may not change.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_dict"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.dict"),
    "newvoc": os.path.join(SDSYS, "newvoc", "tool.dict"),
    "help": os.path.join(SDSYS, "helptext", "tool.dict.page"),
    "run": os.path.join(GPL, "tk_run"),
}
SAFE = "abcdefghijklmnopqrstuvwxyz0123456789._-"


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
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


def nostr(text):
    """the code with the quoted text taken out, so that a word in a message is not read as a statement"""
    return re.sub(r"'[^'\n]*'|\"[^\"\n]*\"", "''", text)


def block(text, label):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def labels(text):
    return re.findall(r"^([a-z][a-z.0-9]*):\s*$", text, re.M)


def inorder(text, *parts):
    """every part is found, each after the one before"""
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            return False
        pos = i
    return True


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    code = nostr(pg)
    ck("TD0", "NULL CASE: the page, both VOC entries, the help record and $tk_run were found and are not empty (a check on nothing would pass)",
       len(pg) > 20000 and raw["voc"].strip() != "" and raw["newvoc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and len(raw["run"]) > 500, "%d" % len(pg))
    ck("TD1", "the page is an internal program catalogued as $tool_dict, and EVERY account has it as a verb: newvoc and SDSYS's VOC both run that program",
       re.search(r"^\$internal\s*\nprogram \$tool_dict\s*\n\$catalog \$tool_dict\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_dict"]
       and raw["newvoc"].split("\n")[1:3] == ["CA", "$tool_dict"], repr((raw["voc"][:30], raw["newvoc"][:60])))
    op = pg.find("call $tk_open('tool.dict', '', ctx, err)")
    ck("TD2", "it is a USER app: the base is opened with no audience (an account holder is never refused for being one) and BEFORE anything is read - the VOC, a file, a gate, the file named after the verb is only read as text",
       0 <= op < pg.find("open 'VOC'") and op < pg.find("kernel(K$") and op < pg.find("open fn2 to fv") and "'admin'" not in pg and pg.count("K$ADMINISTRATOR") == 1
       and "if err # '' then\n      display err\n      stop" in pg, op)
    hv = block(pg, "hand.over")
    ck("TD3", "the commands it can run are two lists declared once at the top: five verbs run ONLY through $tk_run (allow), and the two it hands the terminal to (show.allow: the IDE and LIST.INDEX), the only thing the one execute statement runs, inside hand.over and after the list was tested",
       re.findall(r"(?<![.\w])allow = '([^']*)'", pg) == ["delete compile.dict create.index build.index delete.index"] and re.findall(r"\bshow\.allow = '([^']*)'", pg) == ["ide list.index"]
       and len(re.findall(r"^\s*execute\b", code, re.M)) == 1 and len(re.findall(r"^\s*execute\b", hv, re.M)) == 1
       and 0 <= hv.find("if index(' ' : show.allow : ' ', ' ' : field(sent, ' ', 1) : ' ', 1) = 0 then") < hv.find("execute sent") and "execute sent capturing" not in pg
       and pg.count("call $tk_run(allow, sent, out, stat, rerr)") == 1 and "$tk_runx" not in pg, repr(re.findall(r"\ballow = '([^']*)'", pg)))
    ck("TD4", "THE PAGE WRITES NOTHING (S.90 stage 3): no write statement of any kind, no delete, clearfile, osdelete, rename, logto, openpath, openseq, oswrite and no execute outside hand.over (every change is a verb, or the IDE's)",
       len(re.findall(r"^[ \t]*(write|writev|writet|matwrite|writeu)(?![.\w])", code, re.M)) == 0
       and not re.search(r"^[ \t]*(delete|clearfile|osdelete|oswrite|rename|logto|openpath|openseq|osopen|writeseq|execute)(?![.\w])", code.replace(nostr(hv), ""), re.M)
       and "openpath" not in code and "$tk_runx" not in pg, "")
    dn = block(pg, "do.new")
    ck("TD5", "N (do.new) asks the id with the id rules and cancels with 'nothing written', checks the FILE's name before it is given to a command, and hands the terminal to the IDE on the new item through hand.over: ide dict FILE ID, the cursor kept on the id; it has no box of its own and writes nothing",
       inorder(dn, "vk = 'id'", "gosub ask.valid", "if not(askok) then\n      msg = 'nothing written'\n      return\n   end", "nid = askv", "cw = fn\n   gosub check.word", "if not(okname) then", "sent = 'ide dict ' : fn : ' ' : nid",
               "keep = nid", "gosub hand.over")
       and "$tk_confirm" not in dn and "screen msgbox" not in dn and "$tk_run" not in dn and not re.search(r"^[ \t]*(write|execute)\b", dn, re.M), "")
    ck("TD6", "the code that made and wrote a record is GONE: no ask.d, ask.i, show.new or write.item, no nrec or fnames.new, and no sysmsg(12957) (that title is tool.query's now)",
       not any(s in pg for s in ("ask.d:", "ask.i:", "show.new:", "write.item:", "nrec", "fnames.new", "sysmsg(12957)", "gosub write.item", "gosub show.new")), "")
    ck("TD7", "N is a key of the Items pane only, with its entry in the Items menu, and its handler is the one case that calls do.new",
       "call $tk_keys('add', keys, 'n', 'new', 'new', 'Items', 1)" in pg and "call $tk_keys('menu', keys, 'new', '&Items', '&New item', '', '')" in pg and len(re.findall(r"gosub do\.new[ \t]*$", pg, re.M)) == 1, "")
    ck("TD8", "the box for DELETE says when the verb will be refused, from the kernel's own answer for the dictionary that is open (not from a guess): dict.access asks K$EDIT.OK of the path of the open file and keeps the kernel's reason",
       inorder(block(pg, "dict.access"), "open 'DICT', fn to dv2 then", "dpath = fileinfo(dv2, FL$PATH)", "close dv2", "if not(kernel(K$EDIT.OK, dpath)) then dref = edit_msg(kernel(K$EDIT.KIND, dpath))")
       and "The delete is expected to be refused" in raw["page"], "")
    de = block(pg, "do.delete")
    ck("TD9", "DELETE is the DELETE verb on the dictionary (delete dict FILE ITEM), built from the item's id and the file's name after both passed the name check, behind the box with the ID TYPED, and nothing is sent unless the box answered Run",
       "sent = 'delete dict ' : fn : ' ' : iid" in de and "iid = iids<ishown<ci>>" in de and de.count("gosub check.word") == 2 and de.find("gosub check.word") < de.find("sent = ")
       and "call $tk_confirm(sent, lines, iid, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent" in de, "")
    co = block(pg, "do.compile")
    ck("TD10", "COMPILE is the COMPILE.DICT verb on an I item only (a C item is refused by the verb itself, message 12998, an A or S item by message 12943; any other type is refused with the reason before a box), built from names that passed the name check, behind the box, and nothing is sent unless it answered Run",
       "if index(' I ', ' ' : ma<1, 1> : ' ', 1) = 0 then" in co and "sent = 'compile.dict ' : fn : ' ' : iid" in co and co.count("gosub check.word") == 2
       and inorder(co, "if index(' I '","gosub check.word", "sent = ", "call $tk_confirm(sent, lines, '', res, cmsg)", "if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent"), "")
    ed = block(pg, "do.edit")
    ck("TD11", "EDIT hands the terminal to the IDE on the item (ide dict FILE ITEM; S.88 stage C, it was SED) with names that passed the name check; the IDE asks no box of its own and makes the kernel's dictionary check when it saves, so there is no write in the page for it",
       "sent = 'ide dict ' : fn : ' ' : iid" in ed and ed.count("gosub check.word") == 2 and "gosub hand.over" in ed and ed.find("gosub check.word") < ed.find("sent = ") < ed.find("gosub hand.over"), "")
    ck("TD12", "a report or a screen is the verb's own, which the page hands over: the base is closed BEFORE the verb runs, the verb is followed by the Press Enter message and a read of the answer, the base is opened again AFTER, the pane is read again and the cursor goes back to the item or index it was on",
       inorder(hv, "call $tk_close(ctx)", "execute sent", "crt sysmsg(12870)", "input junk", "call $tk_open('tool.dict', '', ctx, err)", "gosub reread", "if iids<ishown<q>> = keep then ci = q", "if upcase(xnames<q>) = upcase(keep) then cx = q", "gosub draw.all")
       and "gen += 1" in hv and "ctx<TK.C.GEN> = gen" in hv, "")
    nx = block(pg, "do.newindex")
    bu = block(pg, "do.build")
    di = block(pg, "do.delindex")
    li = block(pg, "do.listindex")
    ck("TD13", "the index verbs: CREATE.INDEX FILE ITEM, then BUILD.INDEX FILE ITEM when that worked (the item picked from the list of the dictionary's own items whose id passed the name check; one that already has an index is refused), BUILD.INDEX FILE INDEX, DELETE.INDEX FILE INDEX (behind the box with the NAME TYPED), and LIST.INDEX FILE INDEX DETAIL handed over; every name passed the name check",
       "sent = 'create.index ' : fn : ' ' : iid" in nx and "screen pick cand.v title 'Index which item?'" in nx and "if okname then\n            cand<-1> = iids<q>" in nx and "already has an index" in nx
       and "sent = 'build.index ' : fn : ' ' : xn" in bu and bu.count("gosub check.word") == 2 and "sent = 'delete.index ' : fn : ' ' : xn" in di and di.count("gosub check.word") == 2
       and "call $tk_confirm(sent, lines, xn, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent" in di
       and "sent = 'list.index ' : fn : ' ' : xn : ' detail'" in li and li.count("gosub check.word") == 2 and "gosub hand.over" in li
       and all(inorder(b, "call $tk_confirm(sent, lines,", "if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent") for b in (nx, bu, di))
       and all(inorder(b, "xn = downcase(xnames<cx>)", "cw = xn", "gosub check.word") for b in (bu, di, li)), "")
    cwb = block(pg, "check.word")
    ck("TD14", "a word goes into a command only when it is made of the characters $tk_run lets through (the same list, at most 63 long), and the refusal in every route says which verb to type instead",
       "good = '%s'" % SAFE in cwb and "okname = (len(cw) > 0 and len(cw) <= 63)" in cwb and "okname = @false" in cwb and ("good = '%s'" % SAFE) in raw["run"]
       and all("at the prompt" in b for b in (ed, de, co, bu, di, li)), "")
    ck("TD15", "the page opens the file named after the verb only after its characters were checked and only if it is one of the account's own files (a VOC entry of type F), as typed in lower case; anything else is said politely and the list of files is shown",
       "fa = downcase(field(trim(@sentence), ' ', 2))" in pg and inorder(block(pg, "open.named"), "cw = fa", "gosub check.word", "if not(okname) then", "if upcase(fnames<q>) = upcase(fa) then", "fn = fnames<found>", "gosub enter.file")
       and "is not a file in this account" in pg, "")
    ck("TD16", "every file the page opens it closes again in the same routine (a build needs the file to itself, and the session's own open counts): for each routine the files opened with OPEN are the files closed with CLOSE",
       all(set(re.findall(r"\bopen\b[^\n]*?\bto (\w[\w.]*)", block(pg, lb))) <= set(re.findall(r"^\s*close (\w[\w.]*)", block(pg, lb), re.M)) for lb in labels(pg)) and len(re.findall(r"\bopen\b[^\n]*?\bto \w", code)) >= 10
       and len(re.findall(r"\bopen\b[^\n]*?\bto \w", code)) <= len(re.findall(r"^\s*close \w", code, re.M)), "")
    ck("TD17", "the gates the session holds are ASKED of the kernel and shown (dict-edit with -1; the dictionary's own answer K$EDIT.OK of its path); every kernel() call of the page is one of those three questions and nothing is set or audited",
       "kernel(K$DICT.EDIT, -1)" in block(pg, "draw.foot") and "on (administrator)" in block(pg, "draw.foot") and sorted(set(re.findall(r"kernel\((K\$[A-Z.]+)", code))) == ["K$ADMINISTRATOR", "K$DICT.EDIT", "K$EDIT.KIND", "K$EDIT.OK"] and "K$AUDIT" not in code
       and len(re.findall(r"kernel\(", code)) == len(re.findall(r"kernel\(K\$(ADMINISTRATOR, -1|DICT\.EDIT, -1|EDIT\.OK, dpath|EDIT\.KIND, dpath)\)", code)), "")
    ck("TD18", "a letter is the same key in either case, and every key the page acts on has a place in the key table (the function-key row shows exactly the keys it uses)",
       "if len(nm) = 1 then nm = downcase(nm)" in pg and all(("call $tk_keys('add', keys, '%s'," % k) in pg for k in ("f1", "enter", "n", "e", "d", "c", "t", "i", "f", "b", "l", "/", "f5", "ctrl-q")), "")
    ck("TD19", "the layout fits the 140 by 43 frame, through the layout service (S.88 L2): the two panes are declared in the reference sizes (the list 138 by 22, the detail 138 by 17), so the boxes are rows 1-22 and 23-39; "
               "the list has lh - 6 rows (16 at y 3-18), the summary and the hint stand at the foot of the list (lh - 4 and lh - 3: rows 19 and 20), the detail has dh - 2 rows (15 at y 24-38); nothing is drawn on a border",
       "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 :" in pg and "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 : @vm : 138 :" in pg
       and "screen box at lx,ly size lw,lh title ttl" in pg and "screen box at dx,dy size dw,dh title btl" in pg and "VIS = lh - 6" in pg and "VIS = 16 " in pg
       and "screen text fmt(s, tw : 'L') at lx + 2,ly + lh - 4 attr 'bold' width tw" in pg and "at lx + 2,ly + lh - 3 width tw" in pg
       and "for r = 1 to dh - 2" in block(pg, "draw.detail") and "at dx + 2,dy + r width tw" in block(pg, "draw.detail"), "")
    ck("TD20", "the page waits on the keyboard only through the base: the key read is screen key, the end of the input ends it, the cursor lock ends it, and the base is closed on the way out",
       "screen key returning nm" in pg and "if status() = ER$EOF then exit" in pg and "case nm = 'guardquit'\n            exit" in pg and pg.find("call $tk_close(ctx)") > pg.find("repeat"), "")
    ck("TD21", "the help record names a page of the documentation, and the page asks for it by that name (the key is the record's name), from the key, the mark and the mouse",
       pg.count("call $tk_help('box', 'tool.dict.page', hm, 0, 0)") == 2 and re.match(r"^[^\n]{1,60}\n[0-9a-z-]+\n", raw["help"]) is not None, repr(raw["help"][:60]))
    ta = block(pg, "test.answer")
    ck("TD22", "the id N asks for is checked, and asked again until it passes or the person cancels: in lower case, a plain word that no SD keyword is, starting with a letter or a digit, and not one that exists in any case; the rules for the fields are the form's (!dict_item) and are gone from the page",
       "case vk = 'id'" in ta and ta.count("case vk = ") == 1 and "askv = downcase(askv)" in ta and "gosub check.word" in ta and "if upcase(iids<xq>) = upcase(askv) then vok = 0" in ta
       and inorder(block(pg, "ask.valid"), "screen ask aq : (if etxt = '' then '' else '   <-  ' : etxt) width aw value adef title atl returning askv", "gosub test.answer", "if vok then", "adef = askv", "repeat"), "")
    ck("TD23", "the page makes no record of its own: no field of a new item is assigned (nrec), there is no wizard for a type (no A-type, Data or Indirect button), and the form's types are not listed here",
       "nrec" not in pg and "ask.a:" not in pg and "DICT.A." not in pg and "&A-type" not in pg and "&Data,&Indirect" not in pg, "")
    dt = block(pg, "do.test")
    ck("TD24", "TRY reads and runs nothing but the item: no write, no execute, no verb; an item that must be compiled and is not is refused with the reason BEFORE anything is asked; the record is READ (not locked) from the data file, ITYPE() is evaluated inside a TRY so a bad item cannot stop the page, and the files are closed",
       not re.search(r"^[ \t]*(write|writev|delete|execute|readu|clearfile)(?![.\w])", nostr(dt), re.M) and "call $tk_run" not in dt
       and inorder(dt, "needs.obj = ", "if needs.obj and (rec<DICT.SYS.INFO> = '' or rec<DICT.ITYPE.OBJECT> = '') then", "call $tk_pickrec(ctx, 'record', fn, rid, pres, pnew)", "read drec from df, rid then", "@id = rid", "@record = drec", "try\n      val = itype(rec)", "catch sys", "failed = @exception.data")
       and "close df" in dt and "close dv" in dt, "")
    ck("TD25", "TRY shows the value of a D or I item only (the other types hold no value), and the value as a query prints it - conversion, then format - only for a format the page can read, each inside a TRY",
       "if index(' D I ', ' ' : ty : ' ', 1) = 0 then" in dt and "fmt.ok = (fs # '' and fw # '' and fj # '' and index('LRCU', fj, 1) > 0)" in dt and inorder(dt, "if cv # '' then shown.v = oconv(one, cv)", "if fmt.ok then shown.v = fmt(shown.v, fs)", "catch sys"), "")
    ck("TD26", "a name that is not the page's to give is never given: no id, file name or index name reaches a command except through the routines above, and the commands are built in one place each (sent = ... appears once per verb)",
       all(pg.count(s) == 1 for s in ("sent = 'delete dict '", "sent = 'compile.dict '", "sent = 'create.index '", "sent = 'delete.index '", "sent = 'list.index '"))
       and pg.count("sent = 'build.index '") == 2 and pg.count("sent = 'ide dict '") == 2, "")      # B, and the build that follows a good create.index in N; E, and N of a new item (S.90 stage 3)
    ck("TD27", "the cursor of each pane goes back to what it was on after the data is read again (the file, the item, the index are found by name), and the cursor is kept inside the list",
       "sel.f = fnames<fshown<cf>>" in block(pg, "read.files") and "sel.i = iids<ishown<ci>>" in block(pg, "read.items") and "sel.x = xnames<cx>" in block(pg, "read.indices")
       and all("if %s > %s then %s = %s" % (a, b, a, b) in block(pg, lb) for lb, a, b in (("read.files", "cf", "nfs"), ("read.items", "ci", "nis"), ("read.indices", "cx", "nx"))), "")
    ck("TD28", "text from a dictionary is cleaned before it is drawn (value and subvalue marks, control characters and bytes above ASCII never reach the screen as they are)",
       "ct = convert(ctl.set, ctl.rep, ct)" in block(pg, "clean.text") and "gosub clean.text" in block(pg, "classify.item") and "gosub clean.text" in block(pg, "read.indices"), "")
    ck("TD29", "the dictionary is read at most MAXV items and the page says so, and the list is in id order (the select is sorted)",
       "MAXV = 3000" in pg and "if n > MAXV then" in block(pg, "read.items") and "sselect dv to 9" in block(pg, "read.items") and "the first ' : MAXV : ' are listed" in pg, "")
    ck("TD30", "a word the account's VOC holds as a keyword (all, no.query, detail, lptr, data, dict, local) is never given to a verb as an item id, an index name or a file name: check.word reads the VOC and refuses a K entry, so DELETE DICT file ALL and DELETE.INDEX file ALL cannot be reached by a box that names one object",
       "open 'VOC' to kwf then" in cwb and "read kwr from kwf, cw then" in cwb and "if upcase(kwr<1>[1, 1]) = 'K' then okname = @false" in cwb and cwb.find("if index(good, cw[cwq, 1], 1) = 0 then okname = @false") < cwb.find("open 'VOC' to kwf then"), "")
    return rows


def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:60]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


def setkey(key, val):
    def f(raw):
        r = dict(raw)
        r[key] = val
        return r
    return f


MUTANTS = [
    ("a VOC keyword is given to a verb as an id", "TD30", sub("page", "            if upcase(kwr<1>[1, 1]) = 'K' then okname = @false\n", "            if 0 then okname = @false\n")),
    ("the VOC is not read for keywords", "TD30", sub("page", "      open 'VOC' to kwf then\n", "      open 'VOC' to kwf else null\n      if 0 then\n")),
    ("the page is opened for the administrator only", "TD2", sub("page", "call $tk_open('tool.dict', '', ctx, err)", "call $tk_open('tool.dict', 'admin', ctx, err)")),
    ("the page reads the VOC before it opens the base", "TD2", sub("page", "   call $tk_open('tool.dict', '', ctx, err)\n", "   open 'VOC' to vocx then close vocx\n   call $tk_open('tool.dict', '', ctx, err)\n")),
    ("an ordinary account has no verb", "TD1", setkey("newvoc", "")),
    ("SDSYS's verb runs another program", "TD1", sub("voc", "$tool_dict", "$tool_keys")),
    ("the page may run another command", "TD3", sub("page", "allow = 'delete compile.dict create.index build.index delete.index'", "allow = 'delete compile.dict create.index build.index delete.index sh'")),
    ("the page may hand the terminal to another command", "TD3", sub("page", "show.allow = 'ide list.index'", "show.allow = 'ide list.index sh'")),
    ("the page hands the terminal over without testing the list", "TD3", sub("page", "   if index(' ' : show.allow : ' ', ' ' : field(sent, ' ', 1) : ' ', 1) = 0 then\n      msg = 'the page does not run ' : field(sent, ' ', 1)\n      return\n   end\n", "")),
    ("the page runs a second execute statement", "TD4", sub("page", "   ttl = 'Files of ' : @who\n", "   ttl = 'Files of ' : @who\n   execute 'sh'\n")),
    ("the page runs a command itself", "TD3", sub("page", "   call $tk_run(allow, sent, out, stat, rerr)\n   if rerr # '' then\n      msg = rerr\n      return\n   end\n   gosub join.out", "   execute sent capturing out\n   gosub join.out")),
    ("the page writes a second record", "TD4", sub("page", "   ttl = 'Files of ' : @who\n", "   ttl = 'Files of ' : @who\n   write 'x' on vocf, 'y'\n")),
    ("the page deletes a record", "TD4", sub("page", "   ttl = 'Files of ' : @who\n", "   ttl = 'Files of ' : @who\n   delete vocf, 'x'\n")),
    ("N hands the IDE a delete instead of a new item", "TD5", sub("page", "   sent = 'ide dict ' : fn : ' ' : nid\n   keep = nid", "   sent = 'delete dict ' : fn : ' ' : nid\n   keep = nid")),
    ("N does not check the file's name", "TD5", sub("page", "   nid = askv\n   cw = fn\n", "   nid = askv\n   cw = nid\n")),
    ("N has a box of its own again", "TD5", sub("page", "   nid = askv\n   cw = fn\n", "   nid = askv\n   call $tk_confirm(sent, lines, '', res, cmsg)\n   cw = fn\n")),
    ("a write.item is back", "TD6", sub("page", "\ndo.new:\n", "\nwrite.item:\n   return\n\ndo.new:\n")),
    ("N has no key", "TD7", sub("page", "   call $tk_keys('add', keys, 'n', 'new', 'new', 'Items', 1)\n", "")),
    ("an id may be asked about a number", "TD22", sub("page", "      case vk = 'id'\n", "      case vk = 'num'\n         vok = 1\n      case vk = 'id'\n")),
    ("the box for DELETE does not say that the delete will be refused", "TD8", sub("page", "'  The delete is expected to be refused.'", "'  ok'")),
    ("the dictionary's answer is not asked of the open file's path", "TD8", sub("page", "if not(kernel(K$EDIT.OK, dpath)) then dref = edit_msg(kernel(K$EDIT.KIND, dpath))", "if not(kernel(K$DICT.EDIT, -1)) then dref = edit_msg(2)")),
    ("DELETE does not ask for the id", "TD9", sub("page", "call $tk_confirm(sent, lines, iid, res, cmsg)", "call $tk_confirm(sent, lines, '', res, cmsg)")),
    ("DELETE runs whatever the box answered", "TD9", sub("page", "   call $tk_confirm(sent, lines, iid, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent", "   call $tk_confirm(sent, lines, iid, res, cmsg)\n   gosub run.sent")),
    ("DELETE does not check the id", "TD9", sub("page", "do.delete:\n   if nis < 1 then return\n   iid = iids<ishown<ci>>\n   cw = iid\n   gosub check.word\n   if not(okname) then\n      msg = 'this id is not given to a command by the page (a character it does not pass, or an SD keyword): type  delete dict ' : fn : ' ' : iid : '  at the prompt'\n      return\n   end\n",
                                                  "do.delete:\n   if nis < 1 then return\n   iid = iids<ishown<ci>>\n")),
    ("DELETE takes the id from the neighbour", "TD9", sub("page", "do.delete:\n   if nis < 1 then return\n   iid = iids<ishown<ci>>", "do.delete:\n   if nis < 1 then return\n   iid = iids<ishown<ci + 1>>")),
    ("DELETE is the plain delete verb", "TD9", sub("page", "sent = 'delete dict ' : fn : ' ' : iid", "sent = 'delete ' : fn : ' ' : iid")),
    ("COMPILE is offered for every type", "TD10", sub("page", "   if index(' I ', ' ' : ma<1, 1> : ' ', 1) = 0 then\n      msg = 'only I items are compiled; ' : iid : ' is of type ' : ma<1, 1>\n      return\n   end\n", "")),
    ("COMPILE runs whatever the box answered", "TD10", sub("page", "   call $tk_confirm(sent, lines, '', res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent\n   gosub read.items\n   gosub draw.all\n   return\n\n* In: fn.  Out: dpath", "   call $tk_confirm(sent, lines, '', res, cmsg)\n   gosub run.sent\n   gosub read.items\n   gosub draw.all\n   return\n\n* In: fn.  Out: dpath")),
    ("COMPILE is the cd verb", "TD10", sub("page", "sent = 'compile.dict ' : fn : ' ' : iid", "sent = 'cd data ' : fn : ' ' : iid")),
    ("EDIT opens the item without checking the name", "TD11", sub("page", "do.edit:\n   if nis < 1 then return\n   iid = iids<ishown<ci>>\n   cw = iid\n   gosub check.word\n   if not(okname) then\n      msg = 'this id is not given to a command by the page (a character it does not pass, or an SD keyword): type  ide dict ' : fn : ' ' : iid : '  at the prompt'\n      return\n   end\n",
                                                           "do.edit:\n   if nis < 1 then return\n   iid = iids<ishown<ci>>\n")),
    ("EDIT opens the record of a file, not the dictionary", "TD11", sub("page", "sent = 'ide dict ' : fn : ' ' : iid", "sent = 'ide ' : fn : ' ' : iid")),
    ("a screen is run with the base still open", "TD12", sub("page", "   call $tk_close(ctx)\n   execute sent\n", "   execute sent\n   call $tk_close(ctx)\n")),
    ("a report does not wait for Enter", "TD12", sub("page", "   input junk\n", "")),
    ("the page is not opened again after a report", "TD12", sub("page", "   call $tk_open('tool.dict', '', ctx, err)\n   if err # '' then\n      display err\n      done = 1\n      return\n   end\n   gosub declare.layout", "   gosub declare.layout")),
    ("the cursor does not go back to the item after a screen", "TD12", sub("page", "         if iids<ishown<q>> = keep then ci = q\n", "         if iids<ishown<q>> = keep then ci = 1\n")),
    ("MAKE.INDEX takes the item from the filter", "TD13", sub("page", "sent = 'create.index ' : fn : ' ' : iid", "sent = 'create.index ' : fn : ' ' : filti")),
    ("an item that is no data is offered for an index", "TD13", sub("page", "         if okname then\n            cand<-1> = iids<q>", "         if 1 then\n            cand<-1> = iids<q>")),
    ("BUILD.INDEX runs whatever the box answered", "TD13", sub("page", "   call $tk_confirm(sent, lines, '', res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent\n   gosub read.indices\n   gosub draw.all\n   return\n\n* D: DELETE.INDEX", "   call $tk_confirm(sent, lines, '', res, cmsg)\n   gosub run.sent\n   gosub read.indices\n   gosub draw.all\n   return\n\n* D: DELETE.INDEX")),
    ("DELETE.INDEX gives the name as it is stored", "TD13", sub("page", "do.delindex:\n   if nx < 1 then return\n   xn = downcase(xnames<cx>)", "do.delindex:\n   if nx < 1 then return\n   xn = xnames<cx>")),
    ("DELETE.INDEX does not ask for the name", "TD13", sub("page", "call $tk_confirm(sent, lines, xn, res, cmsg)", "call $tk_confirm(sent, lines, '', res, cmsg)")),
    ("DELETE.INDEX is run for all", "TD13", sub("page", "sent = 'delete.index ' : fn : ' ' : xn", "sent = 'delete.index ' : fn : ' all'")),
    ("LIST.INDEX is run without detail", "TD13", sub("page", "sent = 'list.index ' : fn : ' ' : xn : ' detail'", "sent = 'list.index ' : fn : ' ' : xn")),
    ("the name list lets a dollar through", "TD14", sub("page", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-$'")),
    ("the name length is not limited", "TD14", sub("page", "okname = (len(cw) > 0 and len(cw) <= 63)", "okname = (len(cw) > 0)")),
    ("the file named after the verb is not checked", "TD15", sub("page", "   cw = fa\n   gosub check.word\n   if not(okname) then", "   okname = 1\n   if not(okname) then")),
    ("the file named after the verb is not put in lower case", "TD15", sub("page", "fa = downcase(field(trim(@sentence), ' ', 2))", "fa = field(trim(@sentence), ' ', 2)")),
    ("the file named after the verb need not be a file of the account", "TD15", sub("page", "      if upcase(fnames<q>) = upcase(fa) then", "      if 1 then")),
    ("a file is left open after the dictionary is looked at", "TD16", sub("page", "      dpath = fileinfo(dv2, FL$PATH)\n      close dv2\n", "      dpath = fileinfo(dv2, FL$PATH)\n")),
    ("the data file is left open after the indices are read", "TD16", sub("page", "      next i\n      close fv\n   end\n   nx = dcount(xnames, @fm)", "      next i\n   end\n   nx = dcount(xnames, @fm)")),
    ("a gate is not asked of the kernel", "TD17", sub("page", "kernel(K$DICT.EDIT, -1)", "1")),
    ("the page sets a switch", "TD17", sub("page", "   ttl = 'Files of ' : @who\n", "   ttl = 'Files of ' : @who\n   void kernel(K$DICT.EDIT, 1)\n")),
    ("the page audits", "TD17", sub("page", "   ttl = 'Files of ' : @who\n", "   ttl = 'Files of ' : @who\n   void kernel(K$AUDIT, 'tool dict')\n")),
    ("a key is missing from the key table", "TD18", sub("page", "   call $tk_keys('add', keys, 'b', 'build', 'build', 'Indices', 1)\n", "")),
    ("a capital N is not a key", "TD18", sub("page", "   if len(nm) = 1 then nm = downcase(nm)                          ;* N and n are one key\n", "")),
    ("the detail overruns the border", "TD19", sub("page", "for r = 1 to dh - 2", "for r = 1 to dh - 1")),
    ("the first box overlaps the second", "TD19", sub("page", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 :", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 23 :")),
    ("the list has a row too many", "TD19", sub("page", "VIS = lh - 6 ", "VIS = lh - 5 ")),
    ("the page waits with no key reader of the library", "TD20", sub("page", "screen key returning nm", "input nm,1")),
    ("the end of the input is not seen", "TD20", sub("page", "            if status() = ER$EOF then exit\n", "")),
    ("the help key names a record that does not exist", "TD21", sub("help", "29c-sd-tcl-the-development-tools", "")),
    ("the id may be in any case", "TD22", sub("page", "         askv = downcase(askv)\n         cw = askv", "         cw = askv")),
    ("an id that exists in another case is accepted", "TD22", sub("page", "if upcase(iids<xq>) = upcase(askv) then vok = 0", "if iids<xq> = askv then vok = 0")),
    ("a wrong answer is not asked again", "TD22", sub("page", "      adef = askv\n   repeat", "      return\n   repeat")),
    ("TRY writes a record", "TD24", sub("page", "   @id = rid\n   @record = drec\n", "   @id = rid\n   @record = drec\n   write drec on df, rid\n")),
    ("TRY evaluates outside a TRY", "TD24", sub("page", "   try\n      val = itype(rec)\n   catch sys\n      failed = @exception.data\n   end\n", "   val = itype(rec)\n")),
    ("TRY does not ask whether the item was compiled", "TD24", sub("page", "   if needs.obj and (rec<DICT.SYS.INFO> = '' or rec<DICT.ITYPE.OBJECT> = '') then", "   if 0 then")),
    ("TRY locks the record", "TD24", sub("page", "      read drec from df, rid then got.rec = 1 else got.rec = 0", "      readu drec from df, rid then got.rec = 1 else got.rec = 0")),
    ("TRY shows every type", "TD25", sub("page", "   if index(' D I ', ' ' : ty : ' ', 1) = 0 then\n      msg = 'only D and I items give a value for a record; '", "   if 0 then\n      msg = 'only D and I items give a value for a record; '")),
    ("a command is built in two places", "TD26", sub("page", "   cw = fn\n   gosub check.word\n   if not(okname) then\n      msg = 'this file name is not given to a command by the page (a character it does not pass, or an SD keyword): type  build.index '", "   sent = 'build.index ' : fn\n   cw = fn\n   gosub check.word\n   if not(okname) then\n      msg = 'this file name is not given to a command by the page (a character it does not pass, or an SD keyword): type  build.index '")),
    ("the cursor does not go back to its item", "TD27", sub("page", "   if nis > 0 and ci >= 1 and ci <= nis then sel.i = iids<ishown<ci>>\n", "")),
    ("text from a dictionary is drawn as it is", "TD28", sub("page", "   ct = convert(ctl.set, ctl.rep, ct)\n", "")),
    ("the number of items is not limited", "TD29", sub("page", "      if n > MAXV then\n         n = MAXV\n         truncated = 1\n      end\n", "")),
]


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:200]))
        bad += 0 if ok else 1
    return bad


def selftest(raw):
    base = [r[0] for r in checks(raw) if not r[2]]
    if base:
        print("selftest: the unchanged tree fails %s, so a mutant's own failure cannot be told from the tree's; run the plain check first" % base)
        return 1
    holes = 0
    for name, want, mut in MUTANTS:
        try:
            m = mut(raw)
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
    raw = load()
    print("test-tooldict-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-tooldict-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-tooldict-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
