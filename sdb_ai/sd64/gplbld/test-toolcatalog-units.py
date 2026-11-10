#!/usr/bin/env python3
"""test-toolcatalog-units.py - the programs page, TOOL.CATALOG (`gpl.bp/tool_catalog`), as invariants read off the source (S.75, development app DV6).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-toolcatalog-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A PROGRAM IS COMPILED, CATALOGUED OR TAKEN OUT***: that is
`sandbox-tool-catalog.py` (a private SD, ordinary sessions on a pseudo-terminal, the disk and a separate session as the evidence).  What a text check is for: the properties that make the page a FRONT
END for an account holder - it is a USER app (any account, no administrator test), it opens the base before it reads anything, the only commands it runs are four verbs and it runs them through the
one place that runs commands, after a box that was answered Run; the destructive ones ask for the name typed; global cataloguing is never built into a command; a name goes into a command only when
it is made of the characters $tk_run lets through, is not an option word of the verbs and cannot be read as a global name; and the one reader of file times (OSPATH, which a $internal program does
not gate) is asked of the account's OS gate first.  Those are mostly ORDER and ABSENCE, and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_catalog"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.catalog"),
    "newvoc": os.path.join(SDSYS, "newvoc", "tool.catalog"),
    "help": os.path.join(SDSYS, "helptext", "tool.catalog.page"),
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


CONFIRM_RUN = "if res # 'run' then\n      msg = cmsg\n      return\n   end\n"


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    code = nostr(pg)
    ck("TC0", "NULL CASE: the page, both VOC entries, the help record and $tk_run were found and are not empty (a check on nothing would pass)",
       len(pg) > 15000 and raw["voc"].strip() != "" and raw["newvoc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and len(raw["run"]) > 500, "%d" % len(pg))
    ck("TC1", "the page is an internal program catalogued as $tool_catalog, and EVERY account has it as a verb: newvoc and SDSYS's VOC both run that program",
       re.search(r"^\$internal\s*\nprogram \$tool_catalog\s*\n\$catalog \$tool_catalog\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_catalog"]
       and raw["newvoc"].split("\n")[1:3] == ["CA", "$tool_catalog"], repr((raw["voc"][:30], raw["newvoc"][:60])))
    op = pg.find("call $tk_open('tool.catalog', '', ctx, err)")
    ck("TC2", "it is a USER app: the base is opened with no audience (an account holder is never refused for being one) and BEFORE anything is read - the VOC, a file, a gate",
       0 <= op < pg.find("open 'VOC'") and op < pg.find("kernel(K$") and "'admin'" not in pg and pg.count("K$ADMINISTRATOR") == 1 and "gadm = kernel(K$ADMINISTRATOR, -1)" in block(pg, "gate.state") and "if err # '' then\n      display err\n      stop" in pg, op)
    ck("TC3", "the commands it can run are one list declared once at the top (basic, catalog, decatalog, delete.catalog), run ONLY through $tk_run: the page has no execute statement at all, and no $tk_runx",
       re.findall(r"(?<![.\w])allow = '([^']*)'", pg) == ["basic catalog decatalog delete.catalog"]
       and len(re.findall(r"^\s*execute\b", code, re.M)) == 0 and "execute sent" not in pg and pg.count("call $tk_run(allow, sent, out, stat, rerr)") == 1 and "$tk_runx" not in pg,
       repr(re.findall(r"\ballow = '([^']*)'", pg)))
    ospaths = re.findall(r"ospath\(([^()]*(?:\([^()]*\))?[^()]*)\)", pg)
    keys_used = [re.search(r"(OS\$\w+)\s*$", o).group(1) if re.search(r"(OS\$\w+)\s*$", o) else o for o in ospaths]
    ck("TC4", "the page writes nothing itself: no write, delete, clear, rename, logto, execute or sequential-write statement; the only ospath keys are INFO and FULLPATH; the one sequential file it opens is "
       "opened READONLY; the files it opens by path are the private catalogue and gcat, read",
       not re.search(r"^\s*(write|writev|writet|writeu|writeseq|writeblk|delete|deleteseq|clearfile|osdelete|oswrite|rename|logto|execute|oscopy|setptr)\b", code, re.M)
       and keys_used and all(k in ("OS$INFO", "OS$FULLPATH") for k in keys_used)
       and all("readonly" in l for l in re.findall(r"^\s*openseq [^\n]*", code, re.M)) and len(re.findall(r"^\s*openseq [^\n]*", code, re.M)) == 1
       and sorted(re.findall(r"openpath ([^\n]*?) to (\w+) then", pg)) == sorted([("pcname", "pcf"), ("@sdsys : @ds : 'gcat'", "gcf")]), repr(keys_used))
    sents = re.findall(r"^\s*sent = (.*)$", pg, re.M)
    ck("TC5", "the commands are built from the file's and program's name (or the entry's) and nothing else: basic F P no.query, catalog F P {local} no.query, decatalog E, delete.catalog E {local}; "
       "GLOBAL and PCODE are in none of them (global cataloguing is not offered)",
       sorted(sents) == sorted(["'basic ' : pfile : ' ' : pname : ' no.query'",
                                "'catalog ' : pfile : ' ' : pname : (if cmode = 'local' then ' local' else '') : ' no.query'",
                                "'decatalog ' : lid",
                                "'delete.catalog ' : cname : (if which = 2 then ' local' else '')"])
       and not re.search(r"global|pcode", " ".join(sents)), repr(sents))
    ba, ca, de, dl = block(pg, "do.basic"), block(pg, "do.cat"), block(pg, "do.decat"), block(pg, "do.delcat")
    ck("TC6", "B, C, L, X and D each build the command, show the box, and run ONLY when the box answered Run (nothing is sent before)",
       all(b.find("call $tk_confirm(") < b.find("gosub run.sent") and (CONFIRM_RUN + "   gosub run.sent") in b for b in (ba, ca, de, dl)) and all(b.find("sent = ") < b.find("call $tk_confirm(") for b in (ba, ca, de, dl)), "")
    ck("TC7", "X and D ask for the entry's name typed (the box's typed argument), C and L ask for the program's name typed when no.query would also take an entry of the same name out of another catalogue, B asks none",
       "call $tk_confirm(sent, lines, '', res, cmsg)" in ba and "call $tk_confirm(sent, lines, lid, res, cmsg)" in de and "call $tk_confirm(sent, lines, cname, res, cmsg)" in dl
       and "typed.name = (if others # '' then pname else '')" in ca and "call $tk_confirm(sent, lines, typed.name, res, cmsg)" in ca, "")
    nm = block(pg, "check.name")
    pk = block(pg, "pick.program")
    first = "index('abcdefghijklmnopqrstuvwxyz0123456789', "
    ck("TC8", "a name goes into a command only when it is made of the characters $tk_run lets through (the same list, at most 63 long), begins with a letter or digit (else the verb reads it as a global name) and is not an "
       "option word of the verbs - checked in every route that sends one, before the command is built; the refusal says which verb to type",
       "good = '%s'" % SAFE in nm and "okname = (len(fn) > 0 and len(fn) <= 63)" in nm and "okname = @false" in nm and ("good = '%s'" % SAFE) in raw["run"]
       and pk.count("gosub check.name") == 2 and "index(kwords, ' ' : downcase(pname) : ' ', 1) > 0" in pk and "index(kwords, ' ' : downcase(pfile) : ' ', 1) > 0" in pk and first in pk
       and pk.find("gosub check.name") < pk.find("okp = 1") and pk.find("index(kwords") < pk.find("okp = 1")
       and all(b.count("gosub check.name") == 1 and first in b and "index(kwords, ' ' : downcase(" in b and b.find("gosub check.name") < b.find("sent = ") and b.find("index(kwords") < b.find("sent = ") for b in (de, dl))
       and all("gosub pick.program\n   if not(okp) then return" in b for b in (ba, ca)), "")
    st = block(pg, "src.times")
    oc = block(pg, "open.cats")
    me = block(pg, "meta.entry")
    ck("TC9", "the modification times come from OSPATH, which does not ask the OS gate for a $internal program, so BOTH paths are asked of the gate (K$PATH.OK) first; a directory named by $PRIVATE.CATALOGUE is asked before it is "
       "opened; a local entry's pointer is asked before the sequential open",
       0 <= st.find("kernel(K$PATH.OK, msp)") < st.find("ospath(msp, OS$INFO)") and 0 <= st.find("kernel(K$PATH.OK, mop)") < st.find("ospath(mop, OS$INFO)")
       and 0 <= oc.find("kernel(K$PATH.OK, ospath(pcname, OS$FULLPATH))") < oc.find("openpath pcname")
       and 0 <= me.find("kernel(K$PATH.OK, mop)") < me.find("openseq mop readonly to sf then"), "")
    ck("TC10", "the one gate it shows is ASKED of the kernel with -1 (bp-edit), in the summary and in the warning of each box; nothing is tried to learn it; the only kernel keys the page uses are that and the path question",
       "gon = (gadm or kernel(K$BP.EDIT, -1))" in block(pg, "gate.state") and "gosub gate.state" in block(pg, "draw.foot") and "gosub gate.state" in block(pg, "gate.line") and "if not(gon) then" in block(pg, "gate.line")
       and "(if gadm then 'on (administrator)' else 'on')" in block(pg, "draw.foot") and sorted(set(re.findall(r"K\$[A-Z.]+", pg))) == ["K$ADMINISTRATOR", "K$BP.EDIT", "K$PATH.OK"], "")
    ck("TC11", "OPTION CATALOGUE.LOCAL is gone (27 Oct 26, S.87): the page reads no option and names none, so C and a private D never depend on one",
       "OPT.CATALOGUE.LOCAL" not in pg and "catalogue.local" not in pg.lower() and "option(" not in code, "")
    glines = [l.strip() for l in code.split("\n") if re.search(r"\bgcf\b", l)]
    plines = [l.strip() for l in code.split("\n") if re.search(r"\bpcf\b", l)]
    ck("TC12", "the global catalogue is only READ (opened, its names selected, closed) and the private one only read: no line that uses either file variable writes, deletes or clears it",
       glines and all(re.match(r"(openpath .* to gcf then|mark\.mapping gcf, off|select gcf to 7|if gcok then close gcf)$", l) for l in glines)
       and plines and all(re.match(r"(openpath pcname to pcf then|mark\.mapping pcf, off|select pcf to 7|if pcok then close pcf|read pobj from pcf, rn else pobj = '')$", l) for l in plines), repr((glines, plines)))
    tp = block(pg, "test.pfile")
    ck("TC13", "a program file is a directory file named bp, or ending .bp, or with a .out file beside it (a .out file is never a source); at most MAXREC records of one are read, and the page says when it cut a file short",
       "isp = (tl = 'bp')" in tp and "tl[len(tl) - 2, 3] = '.bp' then isp = 1" in tp and "read orr from vocf, vn : '.out' then" in tp and "tl[len(tl) - 3, 4] = '.out' then return" in tp
       and "fileinfo(fv, FL$TYPE) # FL$TYPE.DIR" in tp and "MAXREC = 2000" in pg and "if scnt > MAXREC then" in tp and "snames = field(snames, @fm, 1, MAXREC)" in tp and "capnote = " in tp, "")
    ck("TC14", "every key the page acts on has a place in the key table, and a letter is the same key in either case",
       "if len(nm) = 1 then nm = downcase(nm)" in pg and all(("call $tk_keys('add', keys, '%s'," % k) in pg for k in ("f1", "b", "c", "l", "x", "d", "/", "f5", "ctrl-q")), "")
    ck("TC15", "the layout fits the 140 by 43 frame (S.88 L2: the two boxes are the layout service's panes, declared 22 and 17 rows by 138 and drawn from their rectangles; the numbers at 140 by 43 are "
               "test-l2-files-units.py's): two boxes (rows 1-22 and 23-39), 16 rows of programs (the list's height less 6) at the list's y + 2, the summary and the gate line on its last interior rows, the detail's interior rows",
       "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 :" in pg and "d<2> = 'detail' : @vm : 2 : @vm : 1 : @vm : 17 : @vm : 138 :" in pg
       and "screen box at lx,ly size lw,lh title ttl" in pg and "screen box at dx,dy size dw,dh title 'The program under the cursor'" in pg and "VIS = lh - 6" in pg
       and "at lx + 2,ly + lh - 4 attr 'bold' width tw" in pg and "at lx + 2,ly + lh - 3 width tw" in pg
       and "for r = 1 to dh - 2" in block(pg, "draw.detail") and "at dx + 2,dy + r width tw" in block(pg, "draw.detail"), "")
    ck("TC16", "the page waits on the keyboard only through the base (screen key), the end of the input ends it, and the base and both catalogue files are closed on the way out",
       "screen key returning nm" in pg and "if status() = ER$EOF then exit" in pg and "case nm = 'guardquit'\n            exit" in pg
       and 0 <= pg.find("repeat\n\n   call $tk_close(ctx)\n   gosub close.cats\n   stop"), "")
    ck("TC17", "the help record names a page of the documentation, and the page asks for it by that name (the key is the record's name)",
       "tool.catalog.page" in pg and re.match(r"^[^\n]{1,60}\n[0-9a-z-]+\n", raw["help"]) is not None, repr(raw["help"][:60]))
    ck("TC18", "a refusal by the verb (a negative return code) goes to the status line as the verb said it and opens no report; only a compile that ran is shown in the report box, which wraps the compiler's lines and cuts at 24",
       0 <= ba.find("if stat < 0 then\n      msg = (if said # '' then said else sent : ' was refused')\n      return\n   end\n   gosub show.report") and "call $tk_wrap(" in block(pg, "show.report")
       and "< 24 then" in block(pg, "show.report"), "")
    br = block(pg, "build.rows")
    ck("TC20", "a local entry is matched to its program by the PATH it points at (the object directory and the record), not by its call name; an entry no program accounts for becomes a row of its own",
       "pre = downcase(pfq<bj>) : @ds" in br and "if lpl[1, len(pre)] = pre then" in br and "rloc<rr, -1> = locid<bi>" in br and "rfile<nr> = '(local)'" in br and "rfile<nr> = '(private)'" in br, "")
    mp = block(pg, "meta.program")
    em = block(pg, "ensure.meta")
    ck("TC21", "STALE is said only when both times were read and the source is the newer: the state is '-' without an object, '?' as soon as there is one and stays so until src.times has read both files",
       "mstate = '-'" in em and 0 <= mp.find("mstate = '?'") < mp.find("gosub src.times") and "mstate = (if msm + 0 > mom + 0 then 'stale' else 'current')" in st and st.rstrip().endswith("return"), "")
    ck("TC22", "an object record is read with the mark mapping off (the header holds bytes that are marks), the private catalogue likewise",
       0 <= mp.find("mark.mapping ov, off") < mp.find("read obj from ov, rn") and "mark.mapping pcf, off" in oc, "")
    ck("TC23", "the page writes no audit line of its own (the verbs write theirs)", "K$AUDIT" not in pg, "")
    ck("TC24", "the page adds no message number: its words are literal strings", "sysmsg(" not in pg, "")
    dcat = block(pg, "do.cat")
    ddec = block(pg, "do.decat")
    ck("TC25", "the entry C removes or L replaces is found BY NAME (the verbs act by name under no.query, whatever the entry points at): sname is the call name, locate finds a local entry of that name, one that points at another program is said so and its name is asked for",
       "sname = downcase(pname)" in dcat and "locate sname in locid<1> setting lq else lq = 0" in dcat and "lhere = (lfound and index(@vm : rloc<mk> : @vm, @vm : sname : @vm, 1) > 0)" in dcat
       and "if lfound then others<-1> = 'the local entry ' : sname" in dcat and "if lfound and not(lhere) then others<-1> = 'the local entry ' : sname" in dcat and "change(rloc<mk>, @vm, ' ')" not in dcat, "")
    ck("TC26", "X (decatalog deletes the object file the entry points at, and the verb does not ask whether the account may reach it) is not run on an entry that leads outside the account: the path is asked of the kernel (K$PATH.OK) before the command is built, and the refusal says which command to type",
       0 <= ddec.find("if rtype<mk> # 'p' and (rpath<mk> = '' or not(kernel(K$PATH.OK, rpath<mk>))) then") < ddec.find("sent = 'decatalog ' : lid") and "the page does not run decatalog on it; type decatalog" in ddec, "")
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


TTL = "   ttl = 'Programs in ' : @who\n"
CONF_B = "   call $tk_confirm(sent, lines, '', res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub run.sent\n"

MUTANTS = [
    ("the entry that C removes is looked for by path, not by name", "TC25", sub("page", "locate sname in locid<1> setting lq else lq = 0", "lq = 0")),
    ("an entry of the same name that points elsewhere needs no name typed", "TC25", sub("page", "      if lfound and not(lhere) then others<-1> = 'the local entry ' : sname : ' (it points at another program and is replaced)'\n", "")),
    ("X is run on an entry that leads outside the account", "TC26", sub("page", "   if rtype<mk> # 'p' and (rpath<mk> = '' or not(kernel(K$PATH.OK, rpath<mk>))) then", "   if 0 then")),
    ("the page is opened for the administrator only", "TC2", sub("page", "call $tk_open('tool.catalog', '', ctx, err)", "call $tk_open('tool.catalog', 'admin', ctx, err)")),
    ("the page reads the VOC before it opens the base", "TC2", sub("page", "   call $tk_open('tool.catalog', '', ctx, err)\n", "   open 'VOC' to vocx then close vocx\n   call $tk_open('tool.catalog', '', ctx, err)\n")),
    ("an ordinary account has no verb", "TC1", setkey("newvoc", "")),
    ("SDSYS's verb runs another program", "TC1", sub("voc", "$tool_catalog", "$tool_keys")),
    ("the page may run another command", "TC3", sub("page", "allow = 'basic catalog decatalog delete.catalog'", "allow = 'basic catalog decatalog delete.catalog sh'")),
    ("the page runs a second execute statement", "TC3", sub("page", TTL, TTL + "   execute 'sh'\n")),
    ("the page runs a command itself", "TC3", sub("page", "   call $tk_run(allow, sent, out, stat, rerr)\n", "   execute sent capturing out\n")),
    ("the page runs the command through $tk_runx", "TC3", sub("page", "call $tk_run(allow, sent, out, stat, rerr)", "call $tk_runx(allow, sent, out, stat, rerr)")),
    ("the page writes a record", "TC4", sub("page", TTL, TTL + "   write 'x' on vocf, 'y'\n")),
    ("the page deletes a record", "TC4", sub("page", TTL, TTL + "   delete vocf, 'x'\n")),
    ("the page deletes an operating system file", "TC4", sub("page", "   si = ospath(msp, OS$INFO)\n", "   si = ospath(msp, OS$INFO)\n   void ospath(msp, OS$DELETE)\n")),
    ("the sequential file is opened for writing too", "TC4", sub("page", "openseq mop readonly to sf then", "openseq mop to sf then")),
    ("local cataloguing becomes global", "TC5", sub("page", "(if cmode = 'local' then ' local' else '')", "(if cmode = 'local' then ' global' else '')")),
    ("basic is run without no.query", "TC5", sub("page", "sent = 'basic ' : pfile : ' ' : pname : ' no.query'", "sent = 'basic ' : pfile : ' ' : pname")),
    ("catalog is run without no.query", "TC5", sub("page", "(if cmode = 'local' then ' local' else '') : ' no.query'", "(if cmode = 'local' then ' local' else '')")),
    ("compile runs whatever the box answered", "TC6", sub("page", CONF_B, "   call $tk_confirm(sent, lines, '', res, cmsg)\n   gosub run.sent\n")),
    ("catalog runs whatever the box answered", "TC6", sub("page", "   call $tk_confirm(sent, lines, typed.name, res, cmsg)\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n", "   call $tk_confirm(sent, lines, typed.name, res, cmsg)\n")),
    ("decatalog does not ask for the name", "TC7", sub("page", "call $tk_confirm(sent, lines, lid, res, cmsg)", "call $tk_confirm(sent, lines, '', res, cmsg)")),
    ("delete.catalog does not ask for the name", "TC7", sub("page", "call $tk_confirm(sent, lines, cname, res, cmsg)", "call $tk_confirm(sent, lines, '', res, cmsg)")),
    ("catalog does not ask for the name when it takes other entries out", "TC7", sub("page", "typed.name = (if others # '' then pname else '')", "typed.name = ''")),
    ("the option-word check is gone from pick.program", "TC8", sub("page", "   if index(kwords, ' ' : downcase(pname) : ' ', 1) > 0 or index(kwords, ' ' : downcase(pfile) : ' ', 1) > 0 then\n      msg = 'the name is a word the verbs read as an option (local, global, no.query ...), so no command can name it: rename the record first'\n      return\n   end\n", "")),
    ("the name check is gone from pick.program", "TC8", sub("page", "   fn = pfile\n   gosub check.name\n   ok1 = okname\n   fn = pname\n   gosub check.name\n", "   okname = @true\n   ok1 = @true\n")),
    ("decatalog accepts a name that begins with a prefix character", "TC8", sub("page", "if not(okname) or index('abcdefghijklmnopqrstuvwxyz0123456789', lid[1, 1], 1) = 0 or index(kwords, ' ' : downcase(lid) : ' ', 1) > 0 then", "if not(okname) then")),
    ("delete.catalog does not check the name", "TC8", sub("page", "   fn = cname\n   gosub check.name\n", "   okname = @true\n")),
    ("the name list lets a dollar through", "TC8", sub("page", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-'", "good = 'abcdefghijklmnopqrstuvwxyz0123456789._-$'")),
    ("the source path is not asked of the OS gate", "TC9", sub("page", "if not(kernel(K$PATH.OK, msp)) or not(kernel(K$PATH.OK, mop)) then", "if not(kernel(K$PATH.OK, mop)) then")),
    ("the times are read before the gate is asked", "TC9", sub("page", "   if not(kernel(K$PATH.OK, msp)) or not(kernel(K$PATH.OK, mop)) then", "   si = ospath(msp, OS$INFO)\n   if not(kernel(K$PATH.OK, msp)) or not(kernel(K$PATH.OK, mop)) then")),
    ("the private catalogue directory is not asked of the OS gate", "TC9", sub("page", "      if not(kernel(K$PATH.OK, ospath(pcname, OS$FULLPATH))) then pcsafe = 0\n", "")),
    ("a local entry's pointer is opened without asking", "TC9", sub("page", "if mop = '' or not(kernel(K$PATH.OK, mop)) then", "if mop = '' then")),
    ("the gate is not asked of the kernel", "TC10", sub("page", "gon = (gadm or kernel(K$BP.EDIT, -1))", "gon = 1")),
    ("the administrator is told the gate is off", "TC10", sub("page", "gon = (gadm or kernel(K$BP.EDIT, -1))", "gon = kernel(K$BP.EDIT, -1)")),
    ("the page reads OPTION CATALOGUE.LOCAL again", "TC11", sub("page", "   want = 'catalog'\n   gosub pick.program\n", "   want = 'catalog'\n   if option(OPT.CATALOGUE.LOCAL) then return\n   gosub pick.program\n")),
    ("the global catalogue is written", "TC12", sub("page", "      mark.mapping gcf, off\n      gcok = 1\n", "      mark.mapping gcf, off\n      write 'x' on gcf, 'y'\n      gcok = 1\n")),
    ("a file is read without a limit", "TC13", sub("page", "   if scnt > MAXREC then\n", "   if scnt > MAXREC * 1000 then\n")),
    ("every file is a program file", "TC13", sub("page", "isp = (tl = 'bp')", "isp = 1")),
    ("a key is missing from the key table", "TC14", sub("page", "   call $tk_keys('add', keys, 'x', 'decatalog', 'decatalog', '', 1)\n", "")),
    ("the detail overruns the border", "TC15", sub("page", "for r = 1 to dh - 2", "for r = 1 to dh - 1")),
    ("the first box overlaps the second", "TC15", sub("page", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 22 : @vm : 138 :", "d<1> = 'list' : @vm : 1 : @vm : 1 : @vm : 23 : @vm : 138 :")),
    ("the end of the input is not seen", "TC16", sub("page", "            if status() = ER$EOF then exit\n", "")),
    ("the help record names no page", "TC17", sub("help", "29c-sd-tcl-the-development-tools", "")),
    ("a refusal opens the report box", "TC18", sub("page", "   if stat < 0 then\n      msg = (if said # '' then said else sent : ' was refused')\n      return\n   end\n   gosub show.report", "   gosub show.report")),
    ("a local entry is no longer matched by its path", "TC20", sub("page", "if lpl[1, len(pre)] = pre then", "if 0 then")),
    ("an object is called current before its times were read", "TC21", sub("page", "      mstate = '?'\n      gosub src.times", "      mstate = 'current'\n      gosub src.times")),
    ("stale is said for the wrong file", "TC21", sub("page", "mstate = (if msm + 0 > mom + 0 then 'stale' else 'current')", "mstate = (if msm + 0 < mom + 0 then 'stale' else 'current')")),
    ("an object is read with the marks mapped", "TC22", sub("page", "         mark.mapping ov, off\n", "")),
    ("the page writes an audit line", "TC23", sub("page", TTL, TTL + "   void kernel(K$AUDIT, 'tool.catalog start')\n")),
    ("the page adds a message number", "TC24", sub("page", TTL, TTL + "   msg = sysmsg(15999)\n")),
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
    print("test-toolcatalog-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-toolcatalog-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolcatalog-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
