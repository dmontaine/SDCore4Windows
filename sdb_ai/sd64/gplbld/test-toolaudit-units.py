#!/usr/bin/env python3
"""test-toolaudit-units.py - the audit trail page, TOOL.AUDIT (`gpl.bp/tool_audit`), and its reader $AUDIT_READ (`gpl.bp/audit_read`), as invariants read off the source (S.75, administrator
app A5).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-toolaudit-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the two programs' BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT THE PAGE SHOWS THE FILE'S LINES***: that is
`sandbox-tool-audit.py` (a private SD, a fixture audit file of 1,500 lines, a Python reader written from the line format, and the lines the page saves read back from the disk).  What a text
check is for: the properties that make the page a READER and not a second way to change anything - the reader asks the kernel for the administrator before it touches a file, opens only a
file whose name is audit or audit.yyyymmdd-hhmmss in the system directory, opens it for reading only, and reads it from the end in blocks; the page runs no command, and its one write is
the record X makes in the administrator's own $HOLD file, followed by its audit line.  Those are mostly ORDER and ABSENCE, and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
# 14 Nov 26 Windows port (RELEASE_1.1 247): the Windows guide, as test-toolaccounts-units.py finds it; its chapter is 20, not Linux's 21.
DOCROOT = os.environ.get("SD_DOCS_CHECKOUT") or os.path.normpath(os.path.join(SD64, "..", "..", "..", "SDCore4WindowsDocs"))
DOCS = os.path.join(DOCROOT, "Administrator", "markdown", "20-the-audit-trail.md")
FILES = {
    "page": os.path.join(GPL, "tool_audit"),
    "rd": os.path.join(GPL, "audit_read"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.audit"),
    "help": os.path.join(SDSYS, "helptext", "tool.audit.page"),
    "docs": DOCS,
}
NEWVOC = os.path.join(SDSYS, "newvoc", "tool.audit")
MSGDIR = os.path.join(SDSYS, "messages")
READER_OPS = {"files", "back", "fwd", "parse"}


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    raw["newvoc_has"] = "1" if os.path.exists(NEWVOC) else ""
    try:
        with open(os.path.join(MSGDIR, "2001"), encoding="latin-1") as f:
            raw["msg2001"] = f.read()
    except OSError:
        raw["msg2001"] = ""
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


def block(text, label):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    rd = strip_bas(raw["rd"])
    ck("AU0", "NULL CASE: the page, the reader, the VOC entry, the help record and the docs page were found and are not empty (a check on nothing would pass)",
       len(pg) > 8000 and len(rd) > 5000 and raw["voc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and raw["docs"].strip() != "" and raw["msg2001"].strip() != "", "%d %d" % (len(pg), len(rd)))
    ck("AU1", "the page is an internal program catalogued as $tool_audit, the reader an internal subroutine catalogued as $audit_read, SDSYS's VOC has the verb for the page, and the shared VOC (newvoc) has NO tool.audit",
       re.search(r"^\$internal\s*\nprogram \$tool_audit\s*\n\$catalog \$tool_audit\b", pg, re.M) is not None
       and re.search(r"^\$internal\s*\nsubroutine audit_read\(op, which, filt, arg, out, err\)\s*\n\$catalog \$audit_read\b", rd, re.M) is not None
       and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_audit"] and raw["newvoc_has"] == "", repr((raw["voc"][:30], raw["newvoc_has"])))
    i_open = pg.find("call $tk_open('tool.audit', 'admin', ctx, err)")
    i_audit = pg.find("kernel(K$AUDIT, 'tool start app=tool.audit')")
    i_first = pg.find("call $audit_read(")
    ck("AU2", "the page opens the toolkit's base for the ADMINISTRATOR first (a refusal is shown and the program stops), before its first read of the file; one audit line says it started",
       0 < i_open < i_audit < i_first and re.search(r"call \$tk_open\('tool\.audit', 'admin', ctx, err\)\s*\n\s*if err # '' then\s*\n\s*display err\s*\n\s*stop\s*\n\s*end", pg) is not None
       and pg.count("'tool start app=tool.audit'") == 1, "open %s, audit %s, first read %s" % (i_open, i_audit, i_first))
    i_adm = rd.find("kernel(K$ADMINISTRATOR, -1)")
    i_files = min([x for x in (rd.find("openpath"), rd.find("openseq"), rd.find("ospath("), rd.find("select ")) if x >= 0] or [10 ** 9])
    ck("AU3", "the reader asks the kernel for the administrator BEFORE it opens, selects or inspects anything, and a refusal returns message 2001 and nothing else",
       0 < i_adm < i_files and re.search(r"if not\(kernel\(K\$ADMINISTRATOR, -1\)\) then\s*\n\s*err = sysmsg\(2001\)\s*\n\s*return\s*\n\s*end", rd) is not None and "administrator" in raw["msg2001"], repr((i_adm, i_files)))
    ck("AU4", "the reader READS ONLY: the one OS file is opened 'readonly' and the system directory with openpath for a name list; it never writes, appends, overwrites, deletes, executes, changes an owner or makes a directory",
       rd.count("openseq path readonly to f") == 1 and rd.count("openseq") == 1 and not re.search(r"\b(writeseq|writeseqf|write|writev|writeu|delete|deleteseq|execute|perform|chain|os\.execute|overwrite|append)\b", rd)
       and not re.search(r"OS\$(DELETE|CHOWN|MKDIR|MKPATH|UNIQUE|CD|FLUSH)", rd), "")
    ch = block(rd, "chk.name")
    oa = block(rd, "open.audit")
    ck("AU5", "the file is named audit or audit.yyyymmdd-hhmmss and nothing else: chk.name allows 'audit' or 21 characters 'audit.' + 8 digits + '-' + 6 digits, open.audit runs it on the name BEFORE it builds the path, and the path is the system directory plus that name",
       "if cn = 'audit' then" in ch and "len(cn) # 21 or cn[1, 6] # 'audit.'" in ch and "for ci = 1 to 15" in ch and "if ci = 9 then" in ch and "if cc # '-' then return" in ch and "index('0123456789', cc, 1) = 0" in ch
       and 0 < oa.find("gosub chk.name") < oa.find("path = @sdsys : @ds : cn") and "if not(cn.ok) then" in oa, ch[:160])
    ops = set(re.findall(r"call \$audit_read\('([a-z]+)'", pg))
    ck("AU6", "the page uses only the reader's operations files, back, fwd and parse, and every call passes the file name the page holds (cur.file) or null for parse and files",
       ops == READER_OPS and len(re.findall(r"call \$audit_read\(", pg)) == len(re.findall(r"call \$audit_read\('(?:back|fwd)', cur\.file, flt, |call \$audit_read\('(?:files|parse)', '', '', ", pg)), repr(sorted(ops)))
    ck("AU7", "the page runs NO command and opens no OS file: no $tk_run, $tk_confirm, execute, perform, chain, openseq, openpath, writeseq, delete or matwrite",
       not re.search(r"\$tk_run|\$tk_confirm|\b(execute|os\.execute|perform|chain|openseq|openpath|writeseq|writeseqf|delete|deleteseq|matwrite|matwriteu|writev|writeu)\b", pg), "")
    ex = block(pg, "do.export")
    ck("AU8", "the one write is X: a record in the administrator's $HOLD file, named audit.<date>.<time>, the audit line 'tool export app=tool.audit lines=n record=id' written only after the write did not fail, "
       "and nothing is written when there is no line or $HOLD will not open",
       len(re.findall(r"\bwrite\b", pg)) == 1 and "write etxt to hold.f, rid on error" in ex and pg.count("kernel(K$AUDIT") == 2 and "if nent = 0 then" in ex and "open '$hold' to hold.f else" in ex
       and 0 < ex.find("write etxt to hold.f, rid on error") < ex.find("kernel(K$AUDIT, 'tool export app=tool.audit lines=' : nent : ' record=' : rid)") and "rid = 'audit.' : @year4 : mm : dd : '.' : tm" in ex
       and 0 < ex.find("if nent = 0 then") < ex.find("open '$hold'"), ex[:200])
    rb = block(rd, "read.back")
    tl = block(rd, "take.lines")
    ck("AU9", "the reader reads BACKWARDS in blocks of 65,536 bytes: it seeks to pos - CHUNK and reads the block before the one it has, holds the first piece of a block as the end of an older line (carry) and joins it to the next block, "
       "takes a block's lines newest first into the FRONT of the result, and stops as soon as it has the number asked for",
       "CHUNK = 65536" in rd and "st = pos - CHUNK" in rb and "seek f, st, 0" in rb and "readblk blk from f, pos - st else blk = ''" in rb and "buf = blk : buf" in rb
       and "carry = buf[1, k]" in tl and "body = buf[k + 1, len(buf)]" in tl and "if k = 0 then return" in tl and "for i = nlines to 1 step -1" in tl and "found = ls : @vm : ln : (if found = '' then '' else @fm : found)" in tl
       and "if nfound >= maxl then" in tl and "newbefore = ls" in tl and "if pos <= 0 or nfound >= maxl then exit" in rb, rb[:200])
    ck("AU10", "a last piece of the file with no line feed is not a line: reading from the end drops it (only when the read starts at the end of the file), reading forward holds it back until it is whole (nlines is the count of line feeds, "
       "the rest is the tail)",
       "if before = fsize and buf # '' then" in rb and "if buf[len(buf), 1] # LF then" in rb and "bend -= len(buf) - k" in rb and "endoff = bend" in rb
       and "nlines = dcount(buf, LF) - 1" in block(rd, "read.fwd") and "tail = buf[e - base + 1, len(buf)]" in block(rd, "read.fwd") and "tailpos = e" in block(rd, "read.fwd"), "")
    ck("AU11", "a byte of the mark range 248 to 255 in a line is read as a question mark, in both directions, before the line is filtered or kept",
       rd.count("convert char(248) : char(249) : char(250) : char(251) : char(252) : char(253) : char(254) : char(255) to '????????' in ln") == 2
       and 0 < tl.find("convert char(248)") < tl.find("gosub line.passes") and 0 < block(rd, "read.fwd").find("convert char(248)") < block(rd, "read.fwd").find("gosub line.passes"), "")
    lp = block(rd, "line.passes")
    ck("AU12", "the filter: from keeps a line whose stamp is not before it and to one not after it (by prefix, so a date covers its day), text is a case-blind substring of the whole line, event is a case-blind substring of the event words, "
       "account is account= equal to it, user is user= or sudo= equal to it; every test must pass and a null field passes everything",
       "if ln[1, len(s)] < s then" in lp and "if ln[1, len(s)] > s then" in lp and "index(downcase(ln), downcase(s), 1) = 0" in lp and "index(downcase(p.event), downcase(s), 1) = 0" in lp
       and "if downcase(p.pairs<pi>) = 'account=' : downcase(s) then okl = 1" in lp and "if downcase(p.user) # downcase(s) and downcase(p.sudo) # downcase(s) then okl = 0" in lp and "if filt = '' then return" in lp
       and "if filt<3> = '' and filt<4> = '' and filt<5> = '' then return" in lp, lp[:200])
    pl = block(rd, "parse.line")
    ck("AU13", "the parts of a line: the stamp is the first 19 characters, user=, sudo=, uid= and pid= are taken only before the first pair, the event words are the words without '=' after them, and a word without '=' after a pair "
       "belongs to that pair",
       "p.stamp = ln[1, 19]" in pl and "rest = ln[21, len(ln)]" in pl and "in.event and eqp = 0 and (p.pid # '' or p.uid # '')" in pl and "case eqp = 0" in pl and "p.pairs<cur> = p.pairs<cur> : ' ' : w" in pl
       and all(("case in.event and w[1, eqp] = '%s=' and p.%s = ''" % (k, k)) in pl for k in ("user", "sudo", "uid", "pid")), pl[:200])
    ck("AU14", "the page's numbers: the list rows are the box's less 3 (17 at 140 by 43), 200 lines read at a time, 3000 kept, new lines read every 3 seconds only in follow mode (a timed tick does nothing otherwise), at most 10 reads of 200 for one F5",
       re.search(r"^\s*VL = lst\.h - 3\b", pg, re.M) is not None and re.search(r"^\s*BLK = 200\s*$", pg, re.M) is not None and re.search(r"^\s*MAXENT = 3000\s*$", pg, re.M) is not None
       and "screen key timeout 3 returning nm" in pg and "if follow then gosub timed.follow" in pg and "for iter = 1 to 10" in block(pg, "read.newer"), "")
    acts = sorted(set(re.findall(r"call \$tk_keys\('add', keys, '[^']+', '[^']+', '([a-z]+)'", pg)))
    ck("AU15", "the key table has exactly: help, filter, clear, goto, file, follow, export, refresh, quit; the dispatch has F, C, D, O, L, X, F1/?, F5 and Ctrl-Q",
       acts == sorted(["help", "filter", "clear", "goto", "file", "follow", "export", "refresh", "quit", "menu"])
       and all(("case nm = '%s'" % k) in pg for k in ("f", "c", "d", "o", "l", "x", "f5", "ctrl-q")) and "case nm = 'f1' or nm = '?'" in pg, " ".join(acts))
    ck("AU16", "the page has a [?] and F1, ? and a click show tool.audit.page, whose record exists with a title, the audit trail page of the administrator guide (which exists) and a body",
       pg.count("'tool.audit.page'") == 2 and "call $tk_help('mark', top.x + top.w - 5, top.y + 1, 0, 0)" in pg and "call $tk_help('hit', mev, top.x + top.w - 5, top.y + 1, hit.m)" in pg
       and raw["help"].split("\n")[0].strip() != "" and raw["help"].split("\n")[1].strip() == "administrator-20-the-audit-trail" and raw["help"].split("\n")[2].strip() != "" and raw["docs"].startswith("Title: The Audit Trail"), "")
    dl = block(pg, "draw.all")
    dsl = block(pg, "draw.list")
    dd = block(pg, "draw.detail")
    dc = block(pg, "declare.layout")
    gr = block(pg, "get.rects")
    ck("AU17", "the layout is the layout service's (S.88 L2): three panes declared at the 140 by 43 sizes (rows 6, 20 and 13 of 138), their rectangles asked of $tk_layout and drawn as boxes; the filter text on rows 1 to 4 of the top box with the [?] on "
       "its first row (so its first line is 10 narrower than the box's text), the heading and the list rows in the list box, the line under the cursor in the detail box's rows (less 2); (the numbers at 140 by 43 are test-l2-admin-units.py's)",
       "ld<1> = 'trail' : @vm : 1 : @vm : 1 : @vm : 6 : @vm : 138" in dc and "ld<2> = 'lines' : @vm : 2 : @vm : 1 : @vm : 20 : @vm : 138" in dc and "ld<3> = 'detail' : @vm : 3 : @vm : 1 : @vm : 13 : @vm : 138" in dc
       and "call $tk_layout('declare', ctx, ld, perr)" in dc and "VL = lst.h - 3" in gr and "DR = det.h - 2" in gr
       and "screen box at top.x,top.y size top.w,top.h" in dl and "screen box at lst.x,lst.y size lst.w,lst.h" in dl and "screen box at det.x,det.y size det.w,det.h" in dl
       and "screen text s at top.x + 2,top.y + 1 attr 'bold' width ttw - 6" in block(pg, "draw.filter")
       and "at lst.x + 2,lst.y + 1 attr 'header'" in dsl and "at lst.x + 2,lst.y + 1 + r attr rat" in dsl and "for r = 1 to DR" in dd and "at det.x + 2,det.y + r width dtw" in dd and "for r = 1 to VL" in dsl, "")
    cs = block(pg, "chk.stamp")
    ck("AU18", "a time typed for the filters or go-to is digits, '-', ' ' and ':' only and at most 19 characters, and a refused time stops the dialog before anything is changed; Esc at any question returns without applying the filters",
       "if len(v) > 19 then stamp.ok = 0" in cs and "index('0123456789- :', v[si, 1], 1) = 0" in cs and block(pg, "do.filter").count("gosub chk.stamp") == 2 and block(pg, "do.filter").count("call $tk_form('close'") == 2
       and block(pg, "do.filter").find("flt = nf") > block(pg, "do.filter").rfind("call $tk_form('close'") > block(pg, "do.filter").find("call $tk_form('say'") > block(pg, "do.filter").find("call $tk_form('run'"), cs[:200])
    ck("AU19", "when the file shrinks (a rotation) the page reads from the end again and says so; older lines past the 3000 kept drop the newest, newer lines past it drop the oldest, and the cursor and scroll position are moved with them",
       "if res<2> < hi then" in block(pg, "read.newer") and "the audit file was rotated" in block(pg, "read.newer") and "ci -= ncut" in block(pg, "read.newer") and "ta -= ncut" in block(pg, "read.newer")
       and "del ent<i>" in block(pg, "load.older") and "ci += n.old" in block(pg, "load.older") and "ta += n.old" in block(pg, "load.older"), "")
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
    ("the page is opened for anyone", "AU2", sub("page", "call $tk_open('tool.audit', 'admin', ctx, err)", "call $tk_open('tool.audit', '', ctx, err)")),
    ("the page reads before it opens the base", "AU2", sub("page", "   call $tk_open('tool.audit', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n", "   call $audit_read('files', '', '', '', fl0, ferr0)\n   call $tk_open('tool.audit', 'admin', ctx, err)\n   if err # '' then\n      display err\n      stop\n   end\n")),
    ("an ordinary account gets the verb", "AU1", setkey("newvoc_has", "1")),
    ("the reader does not ask for the administrator", "AU3", sub("rd", "   if not(kernel(K$ADMINISTRATOR, -1)) then\n      err = sysmsg(2001)\n      return\n   end\n", "")),
    ("the reader opens before it asks", "AU3", sub("rd", "   out = ''\n   err = ''\n   opened = 0\n", "   out = ''\n   err = ''\n   opened = 0\n   openpath @sdsys to sysf0 else null\n")),
    ("the reader refuses with another message", "AU3", sub("rd", "      err = sysmsg(2001)\n", "      err = 'no'\n")),
    ("the reader opens the file for writing", "AU4", sub("rd", "openseq path readonly to f then", "openseq path to f then")),
    ("the reader writes a line", "AU4", sub("rd", "close.audit:\n   if opened then close f", "close.audit:\n   if opened then writeseq 'x' to f else null\n   if opened then close f")),
    ("any name is an audit file", "AU5", sub("rd", "   if len(cn) # 21 or cn[1, 6] # 'audit.' then return\n", "   if cn[1, 6] # 'audit.' then return\n")),
    ("a name with a slash passes", "AU5", sub("rd", "      if ci = 9 then\n         if cc # '-' then return\n", "      if ci = 9 then\n         if cc # '-' and cc # '/' then return\n")),
    ("the path is built before the name is checked", "AU5", sub("rd", "   cn = which\n   if cn = '' then cn = 'audit'\n   gosub chk.name\n", "   cn = which\n   if cn = '' then cn = 'audit'\n   path = @sdsys : @ds : cn\n   gosub chk.name\n")),
    ("the page calls a fifth operation", "AU6", sub("page", "   call $audit_read('files', '', '', '', fl, ferr)", "   call $audit_read('size', '', '', '', fl, ferr)")),
    ("a call passes another file name", "AU6", sub("page", "call $audit_read('back', cur.file, flt, lo : @fm : BLK, res, rerr)", "call $audit_read('back', 'audit', flt, lo : @fm : BLK, res, rerr)")),
    ("the page runs a command", "AU7", sub("page", "   void kernel(K$AUDIT, 'tool start app=tool.audit')\n", "   void kernel(K$AUDIT, 'tool start app=tool.audit')\n   execute 'who' capturing xx\n")),
    ("the page opens an OS file", "AU7", sub("page", "   keys = ''\n", "   openseq '/etc/passwd' to pf else null\n   keys = ''\n")),
    ("the export audit line comes before the write", "AU8", sub("page", "   write etxt to hold.f, rid on error\n      msg = 'the record could not be written (status ' : status() : ')'\n      return\n   end\n   void kernel(K$AUDIT, 'tool export app=tool.audit lines=' : nent : ' record=' : rid)\n",
                                                                "   void kernel(K$AUDIT, 'tool export app=tool.audit lines=' : nent : ' record=' : rid)\n   write etxt to hold.f, rid on error\n      msg = 'the record could not be written (status ' : status() : ')'\n      return\n   end\n")),
    ("a second write", "AU8", sub("page", "   rid = 'audit.' : @year4", "   write 'x' to hold.f, 'zz'\n   rid = 'audit.' : @year4")),
    ("X writes with no line loaded", "AU8", sub("page", "   if nent = 0 then\n      msg = 'there is no line to save'\n      return\n   end\n", "")),
    ("the block size changes", "AU9", sub("rd", "CHUNK = 65536", "CHUNK = 4096")),
    ("the carry is thrown away", "AU9", sub("rd", "      carry = buf[1, k]\n", "      carry = ''\n")),
    ("a line is put at the end instead of the front", "AU9", sub("rd", "found = ls : @vm : ln : (if found = '' then '' else @fm : found)", "found = (if found = '' then '' else found : @fm) : ls : @vm : ln")),
    ("reading back does not stop at the count", "AU9", sub("rd", "      if pos <= 0 or nfound >= maxl then exit\n", "      if pos <= 0 then exit\n")),
    ("a partial last line is taken when reading back", "AU10", sub("rd", "            if buf[len(buf), 1] # LF then\n", "            if 0 then\n")),
    ("a partial last line is taken when reading forward", "AU10", sub("rd", "      nlines = dcount(buf, LF) - 1\n", "      nlines = dcount(buf, LF)\n")),
    ("the trim is done for every read", "AU10", sub("rd", "         if before = fsize and buf # '' then\n", "         if buf # '' then\n")),
    ("a mark-range byte is kept when reading back", "AU11", sub("rd", "         convert char(248) : char(249) : char(250) : char(251) : char(252) : char(253) : char(254) : char(255) to '????????' in ln\n         gosub line.passes\n         if okl then\n            found = ls", "         gosub line.passes\n         if okl then\n            found = ls")),
    ("from is inclusive of the wrong side", "AU12", sub("rd", "      if ln[1, len(s)] < s then\n         okl = 0", "      if ln[1, len(s)] > s then\n         okl = 0")),
    ("to is case or length blind", "AU12", sub("rd", "      if ln[1, len(s)] > s then\n         okl = 0", "      if ln[1, 10] > s then\n         okl = 0")),
    ("text is case sensitive", "AU12", sub("rd", "      if index(downcase(ln), downcase(s), 1) = 0 then", "      if index(ln, s, 1) = 0 then")),
    ("user ignores sudo", "AU12", sub("rd", "      if downcase(p.user) # downcase(s) and downcase(p.sudo) # downcase(s) then okl = 0", "      if downcase(p.user) # downcase(s) then okl = 0")),
    ("account is a substring", "AU12", sub("rd", "if downcase(p.pairs<pi>) = 'account=' : downcase(s) then okl = 1", "if index(downcase(p.pairs<pi>), downcase(s), 1) > 0 then okl = 1")),
    ("an empty filter is not short-circuited", "AU12", sub("rd", "   if filt = '' then return\n", "")),
    ("a pair's value loses its spaces", "AU13", sub("rd", "if cur > 0 then p.pairs<cur> = p.pairs<cur> : ' ' : w", "if cur > 0 then p.pairs<cur> = p.pairs<cur> : w")),
    ("user= is taken after the event too", "AU13", sub("rd", "case in.event and w[1, eqp] = 'user=' and p.user = ''", "case w[1, eqp] = 'user=' and p.user = ''")),
    ("200 becomes 2000", "AU14", sub("page", "BLK = 200 ", "BLK = 2000 ")),
    ("the page follows without being asked", "AU14", sub("page", "            if follow then gosub timed.follow", "            gosub timed.follow")),
    ("a key is added to the table", "AU15", sub("page", "   call $tk_keys('add', keys, 'x', 'save', 'export', '', 1)\n", "   call $tk_keys('add', keys, 'x', 'save', 'export', '', 1)\n   call $tk_keys('add', keys, 'k', 'kill', 'kill', '', 1)\n")),
    ("the help key names a record that does not exist", "AU16", sub("page", "call $tk_help('box', 'tool.audit.page', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'", "call $tk_help('box', 'tool.audit.nopage', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'")),
    ("the help record names no page", "AU16", sub("help", "20-the-audit-trail", "")),
    ("the lines box overruns the detail", "AU17", sub("page", "ld<2> = 'lines' : @vm : 2 : @vm : 1 : @vm : 20", "ld<2> = 'lines' : @vm : 2 : @vm : 1 : @vm : 21")),
    ("the first filter line runs under the [?]", "AU17", sub("page", "attr 'bold' width ttw - 6", "attr 'bold' width ttw")),
    ("a time with letters is allowed", "AU18", sub("page", "index('0123456789- :', v[si, 1], 1) = 0", "index('0123456789- :abc', v[si, 1], 1) = 0")),
    ("To is not tested as a time", "AU18", sub("page", "      v = trim(fv<2>)\n      gosub chk.stamp\n", "      v = trim(fv<2>)\n")),
    ("a rotation is not noticed", "AU19", sub("page", "      if res<2> < hi then\n", "      if @false then\n")),
    ("going back leaves the cursor where it was", "AU19", sub("page", "   nent += n.old\n   ci += n.old\n", "   nent += n.old\n")),
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
    print("test-toolaudit-units: tree %s" % SDSYS)
    if not raw["page"] or not raw["rd"]:
        print("test-toolaudit-units: CANNOT RUN - %s or %s is not there" % (FILES["page"], FILES["rd"]))
        return 2
    print("test-toolaudit-units: guide %s" % DOCS)
    if not raw["docs"]:
        print("test-toolaudit-units: NO TREE - the guide is not there (set SD_DOCS_CHECKOUT to the SDCore4WindowsDocs checkout)")
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolaudit-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
