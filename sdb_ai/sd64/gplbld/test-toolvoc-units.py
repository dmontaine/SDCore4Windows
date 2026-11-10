#!/usr/bin/env python3
"""test-toolvoc-units.py - the VOC page, TOOL.VOC (`gpl.bp/tool_voc`), as invariants read off the source (S.75, development app DV3).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-toolvoc-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT AN ENTRY IS DELETED OR THAT THE IDE OPENS***: that is
`sandbox-tool-voc.py` (a private SD, ordinary sessions on a pseudo-terminal, the VOC read back by a separate session as the evidence).  What a text check is for: the properties that make the
page a FRONT END for an account holder - it is a USER app, it opens the base before it reads anything, it WRITES NOTHING ITSELF (an entry is changed by the IDE or by the DELETE verb, whose
checks, including the kernel's voc-edit rule, are the wall), the one command it runs through $tk_run is DELETE on the VOC after a box and the id typed, the terminal is handed over only to the IDE
on an id that passed the same character check, and what it classifies is read from the VOC and NEWVOC and nowhere else.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_voc"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.voc"),
    "newvoc": os.path.join(SDSYS, "newvoc", "tool.voc"),
    "help": os.path.join(SDSYS, "helptext", "tool.voc.page"),
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
    return re.sub(r"'[^'\n]*'|\"[^\"\n]*\"", "''", text)


def block(text, label):
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
    ck("TV0", "NULL CASE: the page, both VOC entries, the help record and $tk_run were found and are not empty (a check on nothing would pass)",
       len(pg) > 9000 and raw["voc"].strip() != "" and raw["newvoc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and len(raw["run"]) > 500, "%d" % len(pg))
    ck("TV1", "the page is an internal program catalogued as $tool_voc, and EVERY account has it as a verb: newvoc and SDSYS's VOC both run that program",
       re.search(r"^\$internal\s*\nprogram \$tool_voc\s*\n\$catalog \$tool_voc\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_voc"]
       and raw["newvoc"].split("\n")[1:3] == ["CA", "$tool_voc"], repr((raw["voc"][:30], raw["newvoc"][:60])))
    op = pg.find("call $tk_open('tool.voc', '', ctx, err)")
    ck("TV2", "it is a USER app: the base is opened with no audience and BEFORE anything is read - the VOC, NEWVOC, a file, a gate",
       0 <= op < pg.find("open 'VOC'") and op < pg.find("open 'newvoc'") and op < pg.find("kernel(K$") and "'admin'" not in pg and pg.count("K$ADMINISTRATOR") == 1
       and "if err # '' then\n      display err\n      stop" in pg, op)
    ck("TV3", "the one command it runs through $tk_run is DELETE (declared once at the top); the only other execute is the hand-over of the terminal in hand.over",
       re.findall(r"\ballow = '([^']*)'", pg) == ["delete"] and pg.count("call $tk_run(allow, sent, out, stat, rerr)") == 1 and "$tk_runx" not in pg
       and len(re.findall(r"^\s*execute\b", code, re.M)) == 1 and "execute sent" in block(pg, "hand.over"), repr(re.findall(r"^\s*execute\b[^\n]*", pg, re.M)))
    ck("TV4", "the page writes nothing itself: no write, writev, delete, clearfile or osdelete statement (a record is changed by SED or by the DELETE verb) and the VOC is opened to be read",
       not re.search(r"^\s*(write|writev|writet|delete|clearfile|osdelete|oswrite|rename|logto)\b", code, re.M) and pg.count("open 'VOC' to vocf then") == 1 and pg.count("open 'VOC' to vf2 then") == 1, "")
    de = block(pg, "do.delete")
    ed = block(pg, "do.edit")
    ck("TV5", "DELETE asks for the id typed, runs only when the box answers Run, builds the sentence 'delete voc ' + the id after the id passed the character check, and reads the VOC again after",
       "sent = 'delete voc ' : vid" in de and "call $tk_confirm(sent, lines, vid, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   call $tk_run(allow, sent, out, stat, rerr)" in de
       and de.find("gosub check.name") < de.find("call $tk_confirm") < de.find("call $tk_run") < de.find("gosub read.all"), "")
    ck("TV6", "EDIT hands the terminal to the IDE on 'ide voc ' + the id (S.88 stage C; it was SED), only after the same character check, and the page is taken again (its layout declared again for the window as it is) and the VOC read again afterwards",
       "sent = 'ide voc ' : vid" in ed and "gosub declare.layout" in block(pg, "hand.over") and ed.find("gosub check.name") < ed.find("gosub hand.over") and "call $tk_close(ctx)" in block(pg, "hand.over") and "call $tk_open('tool.voc', '', ctx, err)" in block(pg, "hand.over")
       and block(pg, "hand.over").find("execute sent") > block(pg, "hand.over").find("call $tk_close(ctx)") and "gosub read.all" in block(pg, "hand.over"), "")
    nm = block(pg, "check.name")
    ck("TV7", "an id goes into a command only when it is made of the characters $tk_run lets through (the same list, at most 63 long); the refusal says which command to type instead",
       "good = '%s'" % SAFE in nm and "okname = (len(vid) > 0 and len(vid) <= 63)" in nm and "okname = @false" in nm and ("good = '%s'" % SAFE) in raw["run"]
       and all(b.count("gosub check.name") == 1 and "if not(okname) then" in b for b in (de, ed)) and "type  ide voc " in ed and "type  delete voc " in de, "")
    # 28 Oct 26, S.88 phase 2 (plan 2.3, defect S4): DELETE VOC ALL asks "Delete all records in VOC?" into the output the page captures, so the page refuses a VOC keyword before any box
    wd = strip_bas(raw["word"])
    ck("TV7b", "S4: D asks $tk_word - the routine TOOL.FILES and TOOL.DICT's rule is now in - whether the id is a keyword of the VOC (type K: all, detail, no.query ...) AFTER the character check and BEFORE the sentence is built, the box is shown or anything runs, and a refusal "
       "returns with the routine's own words; $tk_word opens the VOC, reads the id and refuses a first letter K, and changes nothing; E (SED) is not held back by it",
       ordered(de, "gosub check.name", "call $tk_word(vid, kwok, kwwhy)", "if not(kwok) then\n      msg = kwwhy\n      return\n   end", "sent = 'delete voc ' : vid", "call $tk_confirm", "call $tk_run")
       and "$tk_word" not in ed and pg.count("$tk_word") == 1
       and ordered(wd, "open 'VOC' to kwf then", "read kwr from kwf, name then", "upcase(kwr<1>[1, 1]) = 'K'", "ok = @false", "why = sysmsg(12760, name)") and not re.search(r"^\s*(write|delete|execute|clearfile)\b", wd, re.M), "")
    cl = block(pg, "classify")
    ck("TV8", "the types are read from the first letters of field 1 (PA, PH and PQ as two), a file or Q-pointer is OPENED to see whether it works, and an entry is compared with the shipped VOC (newvoc) record for record: same, changed, added",
       "ety = t1[1, 1]" in cl and "if t1[1, 2] = 'PA' or t1[1, 2] = 'PH' or t1[1, 2] = 'PQ' then ety = t1[1, 2]" in cl and cl.count("open vid to tf then") == 2
       and "edif = (if sr = r then 'same' else 'changed')" in cl and "edif = 'added'" in cl and "read sr from nvf, vid then" in cl, "")
    ck("TV9", "the list can be cut by type, by state (all, differing from the shipped VOC, broken pointers) and by a part of the id, and is in id order; the cursor goes back to the entry it was on",
       "if ok and ssel = 2 then ok = (emeta<i, 4> = 'changed' or emeta<i, 4> = 'added')" in pg and "if ok and ssel = 3 then ok = (emeta<i, 3> = 'NO')" in pg
       and "locate enames<i> in shown<1> by 'AL' setting lp else" in pg and "sel.e = shown<ci>" in block(pg, "read.all") and "if shown<i> = sel.e then" in block(pg, "read.all"), "")
    ck("TV10", "the gates the session holds are ASKED of the kernel (voc-edit, dict-edit, bp-edit, with -1) and shown; the delete box says when voc-edit is off; nothing is tried to learn them",
       all(("kernel(K$%s, -1)" % k) in block(pg, "gate.words") for k in ("ADMINISTRATOR", "VOC.EDIT", "DICT.EDIT", "BP.EDIT")) and "gosub gate.words" in block(pg, "draw.foot") and "on (administrator)" in block(pg, "gate.words") and "voc-edit is off for you: the delete is expected to be refused." in de, "")
    ck("TV11", "a letter is the same key in either case, and every key the page acts on has a place in the key table",
       "if len(nm) = 1 then nm = downcase(nm)" in pg and all(("call $tk_keys('add', keys, '%s'," % k) in pg for k in ("f1", "e", "d", "t", "s", "/", "f5", "ctrl-q")), "")
    ck("TV12", "the layout fits the 140 by 43 frame, through the layout service (S.88 L2): the two panes are declared in the reference sizes (the list 138 by 22, the detail 138 by 17), so the boxes are rows 1-22 and 23-39; "
               "the list has lh - 6 rows (16 at y 3-18), the summary and the gates line stand at the foot of the list (lh - 4 and lh - 3: rows 19 and 20), the detail has dh - 2 rows (15 at y 24-38)",
       "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 :" in pg and "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 : @vm : 138 :" in pg
       and "screen box at lx,ly size lw,lh title ttl" in pg and "screen box at dx,dy size dw,dh title 'The entry under the cursor'" in pg and "VIS = lh - 6" in pg and "VIS = 16 " in pg
       and "at lx + 2,ly + lh - 4 attr 'bold' width tw" in pg and "at lx + 2,ly + lh - 3 width tw" in pg
       and "for r = 1 to dh - 2" in block(pg, "draw.detail") and "at dx + 2,dy + r width tw" in block(pg, "draw.detail"), "")
    ck("TV13", "the key read is screen key (the cursor lock and the end of the input are the library's), the end of the input ends the page, and the base is closed on the way out",
       "screen key returning nm" in pg and "if status() = ER$EOF then exit" in pg and "case nm = 'guardquit'\n            exit" in pg and pg.find("call $tk_close(ctx)") > pg.find("repeat"), "")
    ck("TV14", "the help record names a page of the documentation, and the page asks for it by that name",
       "tool.voc.page" in pg and re.match(r"^[^\n]{1,60}\n[0-9a-z-]+\n", raw["help"]) is not None, repr(raw["help"][:60]))
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
    ("the page is opened for the administrator only", "TV2", sub("page", "call $tk_open('tool.voc', '', ctx, err)", "call $tk_open('tool.voc', 'admin', ctx, err)")),
    ("the page reads NEWVOC before it opens the base", "TV2", sub("page", "   call $tk_open('tool.voc', '', ctx, err)\n", "   open 'newvoc' to nvx then close nvx\n   call $tk_open('tool.voc', '', ctx, err)\n")),
    ("an ordinary account has no verb", "TV1", setkey("newvoc", "")),
    ("SDSYS's verb runs another program", "TV1", sub("voc", "$tool_voc", "$tool_keys")),
    ("a VOC keyword may be deleted", "TV7b", sub("page", "   call $tk_word(vid, kwok, kwwhy)\n   if not(kwok) then\n      msg = kwwhy\n      return\n   end\n", "")),
    ("the keyword test is asked after the box", "TV7b", sub("page", "   call $tk_word(vid, kwok, kwwhy)\n   if not(kwok) then\n      msg = kwwhy\n      return\n   end\n   sent = 'delete voc ' : vid", "   sent = 'delete voc ' : vid\n   call $tk_word(vid, kwok, kwwhy)\n   if not(kwok) then\n      msg = kwwhy\n      return\n   end")),
    ("the keyword refusal does not return", "TV7b", sub("page", "      msg = kwwhy\n      return\n   end\n   sent = 'delete voc ' : vid", "      msg = kwwhy\n   end\n   sent = 'delete voc ' : vid")),
    ("the keyword test reads no VOC", "TV7b", sub("word", "      read kwr from kwf, name then\n", "      read kwr from kwf, 'x-none' then\n")),
    ("the keyword test takes any type", "TV7b", sub("word", "upcase(kwr<1>[1, 1]) = 'K'", "upcase(kwr<1>[1, 1]) = 'Z'")),
    ("the page may run another command", "TV3", sub("page", "allow = 'delete'", "allow = 'delete sh'")),
    ("the page runs a second command with execute", "TV3", sub("page", "   crt\n   crt sysmsg(12870) :", "   execute 'who'\n   crt\n   crt sysmsg(12870) :")),
    ("the page writes a record", "TV4", sub("page", "   ttl = 'The VOC of ' : @who\n", "   ttl = 'The VOC of ' : @who\n   write 'x' on vocx, 'y'\n")),
    ("the page deletes a record itself", "TV4", sub("page", "   ttl = 'The VOC of ' : @who\n", "   ttl = 'The VOC of ' : @who\n   delete vocx, 'y'\n")),
    ("delete does not ask for the id typed", "TV5", sub("page", "call $tk_confirm(sent, lines, vid, res, cmsg)", "call $tk_confirm(sent, lines, '', res, cmsg)")),
    ("delete runs whatever the box answered", "TV5", sub("page", "   call $tk_confirm(sent, lines, vid, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   call $tk_run(allow, sent, out, stat, rerr)", "   call $tk_confirm(sent, lines, vid, res, cmsg)\n   call $tk_run(allow, sent, out, stat, rerr)")),
    ("delete takes the id from the neighbour", "TV5", sub("page", "   sent = 'delete voc ' : vid", "   sent = 'delete voc ' : shown<ci + 1>")),
    ("the hand-over does not lay the new context out", "TV6", sub("page", "   gosub declare.layout                                         ;* the new context", "   null                                                         ;* the new context")),
    ("edit opens another record", "TV6", sub("page", "sent = 'ide voc ' : vid", "sent = 'ide voc ' : filt")),
    ("edit hands over without checking the id", "TV7", sub("page", "do.edit:\n   if ns < 1 then return\n   vid = shown<ci>\n   gosub check.name\n   if not(okname) then\n      msg = 'this id has a character the page does not give to a command: type  ide voc ' : vid : '  at the prompt'\n      return\n   end\n", "do.edit:\n   if ns < 1 then return\n   vid = shown<ci>\n")),
    ("the id list lets a dollar through", "TV7", sub("page", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-$'")),
    ("the hand-over does not give the screen back to the library", "TV6", sub("page", "   call $tk_close(ctx)\n   execute sent", "   execute sent")),
    ("a pointer is not opened to see if it works", "TV8", sub("page", "      case ety = 'Q'\n         esum = 'file ' : r<3> : ' in the account ' : r<2>\n         open vid to tf then", "      case ety = 'Q'\n         esum = 'file ' : r<3> : ' in the account ' : r<2>\n         open 'voc' to tf then")),
    ("every entry is the same as the shipped VOC", "TV8", sub("page", "edif = (if sr = r then 'same' else 'changed')", "edif = 'same'")),
    ("an added entry is told as changed", "TV8", sub("page", "         edif = 'added'", "         edif = 'changed'")),
    ("a paragraph is read as P", "TV8", sub("page", "if t1[1, 2] = 'PA' or t1[1, 2] = 'PH' or t1[1, 2] = 'PQ' then ety = t1[1, 2]", "if 0 then ety = t1[1, 2]")),
    ("the broken-pointer view lists everything", "TV9", sub("page", "if ok and ssel = 3 then ok = (emeta<i, 3> = 'NO')", "if ok and ssel = 3 then ok = 1")),
    ("the list is not in id order", "TV9", sub("page", "locate enames<i> in shown<1> by 'AL' setting lp else", "locate enames<i> in shown<1> by 'AR' setting lp else")),
    ("the cursor does not go back to its entry", "TV9", sub("page", "   if ns > 0 and ci >= 1 and ci <= ns then sel.e = shown<ci>\n", "")),
    ("a gate is not asked", "TV10", sub("page", "kernel(K$BP.EDIT, -1)", "1")),
    ("the delete box does not say voc-edit is off", "TV10", sub("page", "   if not(kernel(K$VOC.EDIT, -1)) then lines<-1> = 'voc-edit is off for you: the delete is expected to be refused.'\n", "")),
    ("a capital E is not a key", "TV11", sub("page", "   if len(nm) = 1 then nm = downcase(nm)                         ;* E and e are one key\n", "")),
    ("a key is missing from the key table", "TV11", sub("page", "   call $tk_keys('add', keys, 'e', 'edit', 'edit', '', 1)\n", "")),
    ("the detail overruns the border", "TV12", sub("page", "for r = 1 to dh - 2", "for r = 1 to dh - 1")),
    ("the first box overlaps the second", "TV12", sub("page", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 :", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 23 :")),
    ("the list has a row too many", "TV12", sub("page", "VIS = lh - 6 ", "VIS = lh - 5 ")),
    ("the page waits with no key reader of the library", "TV13", sub("page", "screen key returning nm", "input nm,1")),
    ("the end of the input is not seen", "TV13", sub("page", "            if status() = ER$EOF then exit\n", "")),
    ("the help record names no page", "TV14", sub("help", "29c-sd-tcl-the-development-tools", "")),
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
    print("test-toolvoc-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-toolvoc-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolvoc-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
