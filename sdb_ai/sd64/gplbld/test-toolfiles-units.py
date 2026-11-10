#!/usr/bin/env python3
"""test-toolfiles-units.py - the files page, TOOL.FILES (`gpl.bp/tool_files`), as invariants read off the source (S.75, development app DV1).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-toolfiles-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A FILE IS MADE, CLEARED OR DELETED***: that is
`sandbox-tool-files.py` (a private SD, ordinary sessions on a pseudo-terminal, the disk and a separate session's count as the evidence).  What a text check is for: the properties that make
the page a FRONT END for an account holder - it is a USER app (any account, no administrator test), it opens the base before it reads anything, the only commands it runs are six verbs and
it runs them through the one place that runs commands, a command that changes something runs only after the box was answered Run, Clear and Delete ask for the file's name typed, and the
characters it puts in a command are the characters $tk_run lets through - which are mostly ORDER and ABSENCE, and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_files"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.files"),
    "newvoc": os.path.join(SDSYS, "newvoc", "tool.files"),
    "help": os.path.join(SDSYS, "helptext", "tool.files.page"),
    "run": os.path.join(GPL, "tk_run"),
    "word": os.path.join(GPL, "tk_word"),
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


def ordered(text, *needles):
    """every needle is in the text and they come in this order"""
    at = -1
    for n in needles:
        i = text.find(n, at + 1)
        if i < 0:
            return False
        at = i
    return True


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    code = nostr(pg)
    ck("TF0", "NULL CASE: the page, both VOC entries, the help record and $tk_run were found and are not empty (a check on nothing would pass)",
       len(pg) > 9000 and raw["voc"].strip() != "" and raw["newvoc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and len(raw["run"]) > 500, "%d" % len(pg))
    ck("TF1", "the page is an internal program catalogued as $tool_files, and EVERY account has it as a verb: newvoc and SDSYS's VOC both run that program",
       re.search(r"^\$internal\s*\nprogram \$tool_files\s*\n\$catalog \$tool_files\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_files"]
       and raw["newvoc"].split("\n")[1:3] == ["CA", "$tool_files"], repr((raw["voc"][:30], raw["newvoc"][:60])))
    op = pg.find("call $tk_open('tool.files', '', ctx, err)")
    ck("TF2", "it is a USER app: the base is opened with no audience (an account holder is never refused for being one) and BEFORE anything is read - the VOC, a file, a gate",
       0 <= op < pg.find("open 'VOC'") and op < pg.find("kernel(K$") and "'admin'" not in pg and pg.count("K$ADMINISTRATOR") == 1 and "if err # '' then\n      display err\n      stop" in pg, op)
    sw = block(pg, "do.show")
    ck("TF3", "the commands it can run are two lists declared once at the top: three verbs that change something (allow), run ONLY through $tk_run, and the three reporting verbs (show.allow), the only thing the one execute statement runs, inside do.show and after the list was tested",
       re.findall(r"\bshow\.allow = '([^']*)'", pg) == ["analyze.file list.index list.triggers"] and re.findall(r"(?<![.\w])allow = '([^']*)'", pg) == ["create.file clear.file delete.file"]
       and len(re.findall(r"^\s*execute\b", code, re.M)) == 1 and len(re.findall(r"^\s*execute\b", sw, re.M)) == 1
       and 0 <= sw.find("if index(' ' : show.allow : ' ', ' ' : field(sent, ' ', 1) : ' ', 1) = 0 then") < sw.find("execute sent") and "execute sent capturing" not in pg
       and pg.count("call $tk_run(allow, sent, out, stat, rerr)") == 1 and "$tk_runx" not in pg, repr(re.findall(r"\ballow = '([^']*)'", pg)))
    ck("TF4", "the page writes nothing itself: no write, delete, writev, clearfile or osdelete statement (and no execute outside do.show), and it opens a file only to ask the system about it (the VOC to list, each file for fileinfo, DICT to see that it is there)",
       not re.search(r"^\s*(write|writev|writet|delete|clearfile|osdelete|oswrite|rename|logto|execute)\b", code.replace(nostr(sw), ""), re.M) and pg.count("open fn to fv then") == 2 and "open 'DICT', fn to dv then" in pg, "")
    # the three that change something
    cl = block(pg, "do.clear")
    de = block(pg, "do.delete")
    ne = block(pg, "do.new")
    ck("TF5", "CLEAR and DELETE ask for the file's name typed (the box's typed argument is the file) and run only when the box answers Run, before which nothing is sent; the box runs after the name was checked",
       all("call $tk_confirm(sent, lines, fn, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent" in b for b in (cl, de))
       and all(b.find("gosub check.name") < b.find("call $tk_confirm") < b.find("gosub run.sent") for b in (cl, de)), "")
    ck("TF6", "NEW asks no typed name (it destroys nothing) but is still behind the box, after the name was checked; the command is create.file with the name, and directory only when that was chosen",
       "call $tk_confirm(sent, lines, '', res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent" in ne and ne.find("gosub check.name") < ne.find("call $tk_confirm")
       and "sent = 'create.file ' : fn : (if b = 2 then ' directory' else '')" in ne and "if b # 1 and b # 2 then" in ne, "")
    ck("TF7", "the commands are built from the file's name and nothing else: clear.file NAME, delete.file NAME no.query, analyze.file NAME, list.index NAME, list.triggers NAME - the name from the list (shown<ci>), never from text the page read from a file",
       "sent = 'clear.file ' : fn" in cl and "sent = 'delete.file ' : fn : ' no.query'" in de and "fn = shown<ci>" in cl and "fn = shown<ci>" in de
       and all(("sent = '%s ' : shown<ci>" % v) in pg for v in ("analyze.file", "list.triggers")) and "sent = 'list.index ' : shown<ci> : ' all'" in pg, "")
    nm = block(pg, "check.name")
    ck("TF8", "a name goes into a command only when it is made of the characters $tk_run lets through (the same list, at most 63 long), checked in every route that sends one, and the refusal says which verb to type instead",
       "good = '%s'" % SAFE in nm and "okname = (len(fn) > 0 and len(fn) <= 63)" in nm and "okname = @false" in nm and ("good = '%s'" % SAFE) in raw["run"]
       and all(b.count("gosub check.name") == 1 and "if not(okname) then" in b for b in (cl, de, ne, sw)), "")
    # 28 Oct 26, S.88 phase 2 (plan 2.3, defect S4): a VOC keyword is not a name
    kwb = block(pg, "check.kw")
    kw_site = "gosub check.kw\n   if not(kwok) then\n      msg = kwwhy\n      return\n   end\n"
    ck("TF8b", "S4: a name the VOC holds as a keyword (type K: all, detail, no.query ...) is not given to a command: check.kw asks $tk_word, and every route that sends a name (clear, delete, new, the reports) asks it once, AFTER the character check and BEFORE its box or its "
       "command, and returns with the routine's own words; $tk_word is the one test TOOL.VOC and TOOL.DICT make too",
       "call $tk_word(fn, kwok, kwwhy)" in kwb and pg.count("$tk_word") == 1 and all(b.count(kw_site) == 1 and b.find("gosub check.name") < b.find("gosub check.kw") for b in (cl, de, ne, sw))
       and cl.find("gosub check.kw") < cl.find("call $tk_confirm") and de.find("gosub check.kw") < de.find("call $tk_confirm") and ne.find("gosub check.kw") < ne.find("call $tk_confirm") and sw.find("gosub check.kw") < sw.find("execute sent")
       and ordered(strip_bas(raw["word"]), "open 'VOC' to kwf then", "read kwr from kwf, name then", "upcase(kwr<1>[1, 1]) = 'K'", "ok = @false", "why = sysmsg(12760, name)"), "")
    ck("TF9", "a report is the verb's own printout on the terminal, which the page hands over (the verbs print through the print unit, which EXECUTE ... CAPTURING does not catch): the base is closed BEFORE the verb runs, the verb is followed by the Press Enter message and a read of the answer, the base is opened again AFTER (S.88 L2: and the panes are declared again, a new context has none), the files are read again and the cursor goes back to the file it was on",
       0 <= sw.find("keep = fn") < sw.find("call $tk_close(ctx)") < sw.find("execute sent") < sw.find("crt sysmsg(12870)") < sw.find("input junk") < sw.find("call $tk_open('tool.files', '', ctx, err)")
       < sw.find("gosub declare.layout") < sw.find("gosub read.all") < sw.find("if shown<q> = keep then ci = q") < sw.find("gosub draw.all") and "gen += 1" in sw and "ctx<TK.C.GEN> = gen" in sw, "")
    ck("TF10", "the gates the session holds are ASKED of the kernel (voc-edit, dict-edit, bp-edit, with -1) and shown; nothing is tried to learn them",
       all(("kernel(K$%s, -1)" % k) in block(pg, "gate.words") for k in ("ADMINISTRATOR", "VOC.EDIT", "DICT.EDIT", "BP.EDIT")) and "gosub gate.words" in block(pg, "draw.foot") and "on (administrator)" in block(pg, "gate.words"), "")
    rd = block(pg, "read.all")
    ck("TF11", "the list is the VOC entries of type F (the first field F, or a description that starts File), read the way the IDE reads them, in name order; the cursor goes back to the file it was on",
       "t1 = upcase(r<1>)" in rd and "if t1 = 'F' or t1[1, 5] = 'FILE ' then fnames<-1> = ids<i>" in rd and "sel.f = shown<ci>" in rd and "locate fnames<i> in shown<1> by 'AL' setting lp else" in block(pg, "apply.filter")
       and "if shown<i> = sel.f then" in rd, "")
    ck("TF12", "a letter is the same key in either case, and every key the page acts on has a place in the key table (the function-key row shows exactly the keys it uses)",
       "if len(nm) = 1 then nm = downcase(nm)" in pg and all(("call $tk_keys('add', keys, '%s'," % k) in pg for k in ("f1", "n", "c", "d", "a", "i", "t", "/", "f5", "ctrl-q")), "")
    ck("TF13", "the layout fits the 140 by 43 frame (S.88 L2: the two boxes are the layout service's panes, declared 22 and 17 rows by 138 and drawn from their rectangles; the numbers at 140 by 43 are "
               "test-l2-files-units.py's): two boxes (rows 1-22 and 23-39), 16 rows of files (the list's height less 6) at the list's y + 2, the summary and the gates line on its last interior rows, the detail's interior rows",
       "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 :" in pg and "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 : @vm : 138 :" in pg
       and "screen box at lx,ly size lw,lh title ttl" in pg and "screen box at dx,dy size dw,dh title 'The file under the cursor'" in pg and "VIS = lh - 6" in pg
       and "at lx + 2,ly + lh - 4 attr 'bold' width tw" in pg and "at lx + 2,ly + lh - 3 width tw" in pg
       and "for r = 1 to dh - 2" in block(pg, "draw.detail") and "at dx + 2,dy + r width tw" in block(pg, "draw.detail"), "")
    ck("TF14", "the page asks for no terminal it cannot use and waits on the keyboard only through the base: the key read is screen key (the cursor lock and the end of the input are the library's), the end of the input ends it, and the base is closed on the way out",
       "screen key returning nm" in pg and "if status() = ER$EOF then exit" in pg and "case nm = 'guardquit'\n            exit" in pg and pg.find("call $tk_close(ctx)") > pg.find("repeat"), "")
    ck("TF15", "the help record names a page of the documentation, and the page asks for it by that name (the key is the record's name)",
       "tool.files.page" in pg and re.match(r"^[^\n]{1,60}\n[0-9a-z-]+\n", raw["help"]) is not None, repr(raw["help"][:60]))
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
    ("the page is opened for the administrator only", "TF2", sub("page", "call $tk_open('tool.files', '', ctx, err)", "call $tk_open('tool.files', 'admin', ctx, err)")),
    ("the page reads the VOC before it opens the base", "TF2", sub("page", "   call $tk_open('tool.files', '', ctx, err)\n", "   open 'VOC' to vocx then close vocx\n   call $tk_open('tool.files', '', ctx, err)\n")),
    ("an ordinary account has no verb", "TF1", setkey("newvoc", "")),
    ("SDSYS's verb runs another program", "TF1", sub("voc", "$tool_files", "$tool_keys")),
    ("the page may run another command", "TF3", sub("page", "allow = 'create.file clear.file delete.file'", "allow = 'create.file clear.file delete.file sh'")),
    ("the page may hand the terminal to another command", "TF3", sub("page", "show.allow = 'analyze.file list.index list.triggers'", "show.allow = 'analyze.file list.index list.triggers sh'")),
    ("the page hands the terminal to a command without testing the list", "TF3", sub("page", "   if index(' ' : show.allow : ' ', ' ' : field(sent, ' ', 1) : ' ', 1) = 0 then\n      msg = 'the page does not run ' : field(sent, ' ', 1)\n      return\n   end\n", "")),
    ("the page runs a second execute statement", "TF4", sub("page", "   ttl = 'Files in ' : @who\n", "   ttl = 'Files in ' : @who\n   execute 'sh'\n")),
    ("the page runs a command itself", "TF3", sub("page", "   call $tk_run(allow, sent, out, stat, rerr)\n   if rerr # '' then\n      msg = rerr\n      return\n   end\n   gosub first.line", "   execute sent capturing out\n   gosub first.line")),
    ("the page writes a record", "TF4", sub("page", "   ttl = 'Files in ' : @who\n", "   ttl = 'Files in ' : @who\n   write 'x' on vocf, 'y'\n")),
    ("the page deletes a record", "TF4", sub("page", "        rep = ''\n        gosub read.all\n", "        rep = ''\n        delete vocf, 'x'\n        gosub read.all\n") if False else sub("page", "   gosub read.all\n   gosub draw.all\n\n   loop", "   delete vocf, 'x'\n   gosub read.all\n   gosub draw.all\n\n   loop")),
    ("clear does not ask for the name", "TF5", sub("page", "   sent = 'clear.file ' : fn\n   gosub find.meta\n   lines = 'Removes every record of ' : fn : ' (about ' : meta<1, 2> : ').  The file, its dictionary and its indices stay; the records cannot be got back.'\n   call $tk_confirm(sent, lines, fn, res, cmsg)",
                                                    "   sent = 'clear.file ' : fn\n   gosub find.meta\n   lines = 'Removes every record of ' : fn : ' (about ' : meta<1, 2> : ').  The file, its dictionary and its indices stay; the records cannot be got back.'\n   call $tk_confirm(sent, lines, '', res, cmsg)")),
    ("delete does not ask for the name", "TF5", sub("page", "   sent = 'delete.file ' : fn : ' no.query'\n   lines = 'Deletes the file ' : fn : ', its dictionary and its VOC entry.  Nothing can bring them back; a backup can.'\n   call $tk_confirm(sent, lines, fn, res, cmsg)",
                                                    "   sent = 'delete.file ' : fn : ' no.query'\n   lines = 'Deletes the file ' : fn : ', its dictionary and its VOC entry.  Nothing can bring them back; a backup can.'\n   call $tk_confirm(sent, lines, '', res, cmsg)")),
    ("delete runs whatever the box answered", "TF5", sub("page", "   call $tk_confirm(sent, lines, fn, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent\n   gosub read.all\n   gosub draw.all\n   return\n\ndo.filter:",
                                                         "   call $tk_confirm(sent, lines, fn, res, cmsg)\n   gosub run.sent\n   gosub read.all\n   gosub draw.all\n   return\n\ndo.filter:")),
    ("new runs whatever the box answered", "TF6", sub("page", "   call $tk_confirm(sent, lines, '', res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent\n   newname = fn", "   call $tk_confirm(sent, lines, '', res, cmsg)\n   gosub run.sent\n   newname = fn")),
    ("new makes a directory file for dynamic", "TF6", sub("page", "(if b = 2 then ' directory' else '')", "(if b = 1 then ' directory' else '')")),
    ("delete asks the force question", "TF7", sub("page", "sent = 'delete.file ' : fn : ' no.query'", "sent = 'delete.file ' : fn : ' force'")),
    ("clear takes the name from the cursor's neighbour", "TF7", sub("page", "do.clear:\n   if ns < 1 then return\n   fn = shown<ci>", "do.clear:\n   if ns < 1 then return\n   fn = shown<ci + 1>")),
    ("list.index takes a name from somewhere else", "TF7", sub("page", "sent = 'list.index ' : shown<ci>", "sent = 'list.index ' : filt")),
    ("list.index is run without the keyword all (the verb then stops to ask for an index name)", "TF7", sub("page", "sent = 'list.index ' : shown<ci> : ' all'", "sent = 'list.index ' : shown<ci>")),
    ("the name list lets a dollar through", "TF8", sub("page", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-$'")),
    ("the name length is not limited", "TF8", sub("page", "len(fn) <= 63", "len(fn) <= 6300")),
    ("delete does not check the name", "TF8", sub("page", "do.delete:\n   if ns < 1 then return\n   fn = shown<ci>\n   gosub check.name\n   if not(okname) then\n      msg = 'this name has a character the page does not give to a command: type delete.file ' : fn : ' at the prompt'\n      return\n   end\n",
                                                  "do.delete:\n   if ns < 1 then return\n   fn = shown<ci>\n")),
    ("a report is run with the base still open", "TF9", sub("page", "   call $tk_close(ctx)\n   execute sent\n", "   execute sent\n   call $tk_close(ctx)\n")),
    ("a report does not wait for Enter", "TF9", sub("page", "   input junk\n", "")),
    ("a keyword may be the file to delete", "TF8b", sub("page", "      msg = 'this name has a character the page does not give to a command: type delete.file ' : fn : ' at the prompt'\n      return\n   end\n   gosub check.kw\n   if not(kwok) then\n      msg = kwwhy\n      return\n   end\n", "      msg = 'this name has a character the page does not give to a command: type delete.file ' : fn : ' at the prompt'\n      return\n   end\n")),
    ("a keyword may be the file to clear", "TF8b", sub("page", "type clear.file ' : fn : ' at the prompt'\n      return\n   end\n   gosub check.kw\n   if not(kwok) then\n      msg = kwwhy\n      return\n   end\n", "type clear.file ' : fn : ' at the prompt'\n      return\n   end\n")),
    ("a keyword may be the name of a new file", "TF8b", sub("page", "(the page gives nothing else to a command)'\n      return\n   end\n   gosub check.kw\n   if not(kwok) then\n      msg = kwwhy\n      return\n   end\n", "(the page gives nothing else to a command)'\n      return\n   end\n")),
    ("a keyword may be the file of a report", "TF8b", sub("page", "      msg = 'this name has a character the page does not give to a command: type ' : field(sent, ' ', 1) : ' at the prompt'\n      return\n   end\n   gosub check.kw\n   if not(kwok) then\n      msg = kwwhy\n      return\n   end\n", "      msg = 'this name has a character the page does not give to a command: type ' : field(sent, ' ', 1) : ' at the prompt'\n      return\n   end\n")),
    ("the keyword test is not the shared routine", "TF8b", sub("page", "   call $tk_word(fn, kwok, kwwhy)\n", "   kwok = 1\n")),
    ("the keyword test takes any type", "TF8b", sub("word", "upcase(kwr<1>[1, 1]) = 'K'", "upcase(kwr<1>[1, 1]) = 'Z'")),
    ("the page is not opened again after a report", "TF9", sub("page", "   call $tk_open('tool.files', '', ctx, err)\n   if err # '' then\n      display err\n      done = 1\n      return\n   end\n   gosub declare.layout                                          ;* the new context has no panes\n   gen += 1\n   ctx<TK.C.GEN> = gen\n", "   gen += 1\n")),
    ("the panes are not declared again after a report", "TF9", sub("page", "   gosub declare.layout                                          ;* the new context has no panes\n", "")),
    ("the cursor does not go back to the file after a report", "TF9", sub("page", "      if shown<q> = keep then ci = q\n", "      if shown<q> = keep then ci = 1\n")),
    ("the files are not read again after a report", "TF9", sub("page", "   gosub read.all\n   for q = 1 to ns\n      if shown<q> = keep then ci = q", "   for q = 1 to ns\n      if shown<q> = keep then ci = q")),
    ("a gate is not asked", "TF10", sub("page", "' dict-edit ' : (if kernel(K$DICT.EDIT, -1) then 'on' else 'off')", "' dict-edit on'") if False else sub("page", "kernel(K$DICT.EDIT, -1)", "1")),
    ("the files are not in name order", "TF11", sub("page", "locate fnames<i> in shown<1> by 'AL' setting lp else", "locate fnames<i> in shown<1> by 'AR' setting lp else")),
    ("every VOC entry is a file", "TF11", sub("page", "if t1 = 'F' or t1[1, 5] = 'FILE ' then fnames<-1> = ids<i>", "fnames<-1> = ids<i>")),
    ("the cursor does not go back to its file", "TF11", sub("page", "   if ns > 0 and ci >= 1 and ci <= ns then sel.f = shown<ci>\n", "")),
    ("a capital N is not a key", "TF12", sub("page", "   if len(nm) = 1 then nm = downcase(nm)                         ;* N and n are one key\n", "")),
    ("a key is missing from the key table", "TF12", sub("page", "   call $tk_keys('add', keys, 't', 'triggers', 'triggers', '', 1)\n", "")),
    ("the detail overruns the border", "TF13", sub("page", "for r = 1 to dh - 2", "for r = 1 to dh - 1")),
    ("the first box overlaps the second", "TF13", sub("page", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 :", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 23 : @vm : 138 :")),
    ("the page waits with no key reader of the library", "TF14", sub("page", "screen key returning nm", "input nm,1")),
    ("the end of the input is not seen", "TF14", sub("page", "            if status() = ER$EOF then exit\n", "")),
    ("the help key names a record that does not exist", "TF15", sub("page", "call $tk_help('box', 'tool.files.page', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'", "call $tk_help('box', 'tool.files.nopage', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'") if False else sub("help", "29c-sd-tcl-the-development-tools", "")),
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
    print("test-toolfiles-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-toolfiles-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolfiles-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
