#!/usr/bin/env python3
"""test-toolbulk-units.py - the bulk update page, TOOL.BULK (`gpl.bp/tool_bulk`), as invariants read off the source (S.75, development app DV5).  Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-toolbulk-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A RECORD WAS CHANGED, SKIPPED OR PUT BACK***: that is
`sandbox-tool-bulk.py` (a private SD, ordinary sessions on a pseudo-terminal, the records read back by a SEPARATE session as the evidence).  What a text check is for: the properties that
make the page SAFE to give an account holder - it is a USER app that adds no access, the file is judged by the kernel as well as by the page, the only commands it runs are two (a select
built from the page's own words, and the one that makes the undo file), a value reaches the select only through the one function that quotes it, the dry run cannot write, a write
happens only in the apply and the undo and only in the order that keeps the old record first, a locked record is skipped, one write error stops the run, and the one audit line is written.
These are mostly ORDER and ABSENCE, and an edit that moves one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_bulk"),
    "voc": os.path.join(SDSYS, "voc_template", "tool.bulk"),
    "newvoc": os.path.join(SDSYS, "newvoc", "tool.bulk"),
    "help": os.path.join(SDSYS, "helptext", "tool.bulk.page"),
    "run": os.path.join(GPL, "tk_run"),
    "own": os.path.join(GPL, "tk_ownfile"),
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
        out.append((line if cut < 0 else line[:cut]).rstrip())
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


def order(text, *parts):
    """True when every part is in the text and they come in this order"""
    at = -1
    for p in parts:
        i = text.find(p, at + 1)
        if i < 0:
            return False
        at = i
    return True


WRITERS = r"^\s*(write|writeu|writev|writet|matwrite|delete|clearfile)\b"


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    code = nostr(pg)
    main = pg[: pg.find("\nbuild.keys:")] if "\nbuild.keys:" in pg else pg
    ck("TB0", "NULL CASE: the page, both VOC entries, the help record and $tk_run were found and are not empty (a check on nothing would pass)",
       len(pg) > 20000 and raw["voc"].strip() != "" and raw["newvoc"].strip() != "" and len(raw["help"].split("\n")) >= 4 and len(raw["run"]) > 500, "%d" % len(pg))
    ck("TB1", "the page is an internal program catalogued as $tool_bulk, and EVERY account has it as a verb: newvoc and SDSYS's VOC both run that program",
       re.search(r"^\$internal\s*\nprogram \$tool_bulk\s*\n\$catalog \$tool_bulk\b", pg, re.M) is not None and raw["voc"].split("\n")[:3] == ["V", "CA", "$tool_bulk"]
       and raw["newvoc"].split("\n")[1:3] == ["CA", "$tool_bulk"], repr((raw["voc"][:30], raw["newvoc"][:60])))
    op = pg.find("call $tk_open('tool.bulk', '', ctx, err)")
    ck("TB2", "it is a USER app that adds no access: the base is opened with no audience (an account holder is never refused for being one) and BEFORE anything is read - the VOC, a file, a gate",
       0 <= op < pg.find("open 'VOC'") and op < pg.find("kernel(K$") and op < pg.find("open ") and "'admin'" not in pg and "K$ADMINISTRATOR" not in pg
       and "if err # '' then\n      display err\n      stop" in pg, op)
    rs = block(pg, "run.select")
    uf = block(pg, "undo.file")
    ck("TB3", "the page runs exactly TWO commands: the select built by build.select (run.select, EXECUTE ... TRAPPING ABORTS CAPTURING ... RTNLIST) and the constant that makes the undo file (undo.file); it runs nothing through $tk_run, "
       "reaches no operating system command, file, account or program (no os.execute, openseq, openpath, logto, perform, chain, enter, sh)",
       len(re.findall(r"^\s*execute\b", code, re.M)) == 2 and len(re.findall(r"^\s*execute\b", nostr(rs), re.M)) == 1 and len(re.findall(r"^\s*execute\b", nostr(uf), re.M)) == 1
       and "execute ssent trapping aborts capturing sout rtnlist slv" in rs and "execute MKUNDO trapping aborts capturing mkout" in uf
       and not re.search(r"^\s*(os\.execute|osopen|oswrite|osread|osdelete|oslist|openseq|openpath|logto|perform|chain|enter|sh|execute\.list)\b", code, re.M)
       and "$tk_run" not in pg and "$tk_runx" not in pg and "!sh" not in pg, "")
    bs = block(pg, "build.select")
    ck("TB4", "the select sentence is made in ONE place from the page's own words: the file's name after check.name, an item that is @id or a name that passed check.name, an operator found in the page's own table, and a value only as quote.val returned it (qout); "
       "no other statement assigns it, and each piece is checked again where it is put in",
       len(re.findall(r"^\s*ssent\b", pg, re.M)) == len(re.findall(r"^\s*ssent\b", bs, re.M)) and "ssent := (if bi = 1 then ' with ' else (if seljoin = 'or' then ' or with ' else ' and with ')) : bitem : ' ' : cnd.op<bi> : ' ' : qout" in bs
       and order(bs, "nmv = bf", "gosub check.name", "if not(okname) then", "ssent = 'select ' : bf") and "if bitem # '@id' then\n         nmv = bitem\n         gosub check.name" in bs
       and "if index(@fm : cw : @fm, @fm : cnd.op<bi> : @fm, 1) = 0 then serr =" in bs and order(bs, "qv = cnd.val<bi>", "gosub quote.val", "if not(qok) then serr =", "if serr # '' then\n         ssent = ''\n         return", "ssent :=")
       and "cnd.val<bi> :" not in bs.split("ssent :=")[-1] and "ssent = ''" in bs, "")
    qb = block(pg, "quote.val")
    am = re.search(r"allowed = '([^']*)'", qb)
    allowed = am.group(1) if am else ""
    ck("TB5", "ONE function quotes a value and it refuses everything but letters, digits, space and . , : + - _ / @ ( ) % * - so no quote of either kind, backslash, semicolon, ampersand, bar, dollar, backquote, bracket, mark or control character; "
       "an empty value, one over 60 characters and one with a space at either end; the value comes back only in double quotes",
       allowed != "" and set(allowed) <= set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 .,:+-_/@()%*") and all(c in allowed for c in "aZ09 .,:+-_/@()%*")
       and not any(c in allowed for c in "\"'\\;&|$`[]<>{}^~!#=?") and "if qv = '' or len(qv) > 60 then" in qb and "if qv[1, 1] = ' ' or qv[len(qv), 1] = ' ' then" in qb
       and "if index(allowed, qv[q, 1], 1) = 0 then\n         qok = 0" in qb and "if qok then qout = '\"' : qv : '\"'" in qb, repr(allowed))
    cwm = re.search(r"^\s*cw = (.*)$", pg, re.M)
    kwm = re.search(r"^\s*kw = (.*)$", pg, re.M)
    ao = block(pg, "apply.ops")
    kinds = ["set", "null", "append", "prepend", "replace", "add", "upper", "lower", "copy"]
    ck("TB6", "the operators are a closed table of eight words (eq ne lt le gt ge like unlike) and the operations a closed table of nine (set null append prepend replace add upper lower copy), each with a case in apply.ops; "
       "apply.ops is plain string handling: no execute, no call, no gosub, no evaluation of anything the person typed",
       cwm is not None and re.findall(r"'([a-z]+)'", cwm.group(1)) == ["eq", "ne", "lt", "le", "gt", "ge", "like", "unlike"] and kwm is not None and re.findall(r"'([a-z]+)'", kwm.group(1)) == kinds
       and all(("case okind = '%s'" % k) in ao for k in kinds) and not re.search(r"\b(execute|call|gosub|perform|evaluate|calculate|itype|oconv|iconv)\b", nostr(ao)), "")
    cf = block(pg, "check.file")
    ck("TB7", "the file is judged by the page AND by the kernel, and the kernel's own words come first: check.name, the open, K$EDIT.KIND and K$EDIT.OK of the file's pathname (the page is $internal, which the kernel's edit gates let through, so it asks for itself), "
       "then a refusal with edit_msg when the kernel says no, then the page's own up-front refusals by kind (VOC, dictionary, program file), by type (dynamic files only) and read only",
       "deffun edit_msg(kind) calling '!edit_msg'" in pg and cf.find("case not(ceo)") < cf.find("case cek >= 1") and order(cf,"gosub check.name", "open cf to cfv else", "cpath = fileinfo(cfv, FL$PATH)", "cek = kernel(K$EDIT.KIND, cpath)", "ceo = kernel(K$EDIT.OK, cpath)", "case not(ceo)", "cwhy = edit_msg(cek)",
                                                                              "case cek >= 1 and cek <= 3", "case cft # FL$TYPE.DH", "case fileinfo(cfv, FL$READONLY) = 1", "case 1\n         cok = 1"), "")
    ro = block(pg, "reopen.file")
    dd = block(pg, "do.dry")
    da = block(pg, "do.apply")
    ar = block(pg, "apply.run")
    du = block(pg, "do.undo")
    df = block(pg, "do.file")
    ck("TB8", "the file is judged again at every step that matters: at the choice (do.file), at the dry run, before the apply's box, inside the apply, and before the undo - a gate or a file that changed in between is met, not assumed",
       "gosub check.file" in df and "cf = bf\n   gosub check.file" in ro and all("gosub reopen.file" in b for b in (dd, da, ar)) and "gosub check.file" in du and da.find("gosub reopen.file") < da.find("call $tk_confirm") and "gosub reopen.file" in ar, "")
    writers = {}
    for m in re.finditer(r"^(\w[\w.]*):\s*$", pg, re.M):
        writers[m.group(1)] = len(re.findall(WRITERS, block(pg, m.group(1)), re.M))
    ck("TB9", "data is written, deleted or cleared in two routines only - apply.run and do.undo - and nowhere else, and no statement of any other routine (or of the main program) writes",
       {k for k, v in writers.items() if v} == {"apply.run", "do.undo"} and not re.search(WRITERS, main, re.M), repr({k: v for k, v in writers.items() if v}))
    ck("TB10", "the DRY RUN writes nothing and cannot reach the apply: do.dry and every routine it uses (run.select, build.select, quote.val, apply.ops, diff.line, safe.text, make.fp, need.ready, reopen.file, check.file, check.name) hold no write, no delete, no clearfile and no audit line, "
       "and it never performs the apply, the undo file or the undo",
       not any(re.search(WRITERS, block(pg, b), re.M) or "K$AUDIT" in block(pg, b) for b in ("do.dry", "run.select", "build.select", "quote.val", "apply.ops", "diff.line", "safe.text", "make.fp", "need.ready", "reopen.file", "check.file", "check.name"))
       and not any(("gosub " + x) in dd for x in ("apply.run", "undo.file", "do.apply", "do.undo")) and "readu" not in dd and "readu" not in block(pg, "run.select"), "")
    ck("TB11", "APPLY is offered only after a dry run of EXACTLY the same settings: it needs the settings complete, makes the fingerprint of what is on the screen, refuses unless a dry run stands AND its fingerprint equals it, refuses a run that found nothing, "
       "re-judges the file, makes sure the undo file exists, shows the box with the FILE'S NAME TYPED and performs the run only when the box answered Run - and the run is performed from there only, once",
       order(da, "gosub need.ready", "gosub make.fp", "if not(dr.valid) or dr.fp # fp then", "if dr.chg < 1 then", "gosub reopen.file", "gosub undo.file", "call $tk_confirm(sent, lines, bf, res, cmsg, sysmsg(12959))", "if res # 'run' then", "gosub apply.run")
       and "      msg = cmsg\n      return\n   end\n   gosub apply.run" in da and len(re.findall(r"gosub apply\.run\b", code)) == 1, "")
    ck("TB12", "inside the run, for each record and IN THIS ORDER: READU with a LOCKED clause (a record another session holds is skipped and counted), a check that the record is still what the dry run read (digest), the operations, the old record to the undo file, WRITEU, RELEASE; "
       "the undo file is cleared and its header written BEFORE the first record, the first error stops the run, and every readu has a locked clause",
       order(ar, "clearfile uf", "hdr = 'bulk-undo' : @fm : bf", ": 'running'", "readu rec from fv, id locked", "case lk\n            n.lock += 1", "case ('S' : digest(rec, 0, 'MD5')) # ('S' : emd)", "gosub apply.ops", "write id : @fm : digest(newrec, 0, 'MD5') : @fm : rec on uf, n.written on error",
                 "writeu newrec on fv, id on error", "release fv, id", "if halt.why # '' then exit", ": 'done'")
       and len(re.findall(r"\breadu\b", nostr(ar + du))) == len(re.findall(r"\blocked\b", nostr(ar + du))) == 2 and "if halt.why = '' then\n                  writeu newrec on fv, id on error" in ar, "")
    ck("TB13", "the audit trail gets one line from a run and one from an undo, each after the write and not before: 'bulk update file=<file> records=<written>' and 'bulk undo file=<file> records=<put back>' in lower case, no data, and these are the only kernel(K$AUDIT, ...) in the program",
       len(re.findall(r"kernel\(K\$AUDIT,", pg)) == 2 and "void kernel(K$AUDIT, 'bulk update file=' : bf : ' records=' : n.written)" in ar and ar.find("while dl do repeat") < ar.find("kernel(K$AUDIT,")
       and "void kernel(K$AUDIT, 'bulk undo file=' : uf.name : ' records=' : u.back)" in du and du.find("next un.i") < du.find("kernel(K$AUDIT,") and "'bulk update file='" == "'bulk update file='".lower(), "")
    ck("TB14", "UNDO puts a record back only if it is still exactly what the run wrote: the header and the file are judged first, the box asks for the file's name typed, a record put back by an earlier U is passed over BEFORE any lock, a locked one is skipped, "
       "the digest is compared BEFORE the write, and the header says undone only when nothing was left locked or failed",
       order(du, "gosub read.undo.info", "if not(un.have) then", "if un.state = 'undone' then", "gosub check.file", "call $tk_confirm(sent, lines, uf.name, res, cmsg, sysmsg(12960))", "if res # 'run' then", "if uemd = 'restored' then", "readu cur from fv, uid locked",
             "case ('S' : digest(cur, 0, 'MD5')) # ('S' : uemd)", "writeu ur on fv, uid on error", "@fm : 'restored' : @fm : ur on uf, un.i", "if u.lock = 0 and u.err = 0 then", "uh<6> = 'undone'"), "")
    ck("TB15", "the undo file is &bulk.undo& of the person's own account; it is made by the one constant command create.file &bulk.undo&, shown in a box first, and only when the box answered Run; create.file is run nowhere else",
       "UNDOF = '&bulk.undo&'" in pg and "MKUNDO = 'create.file &bulk.undo&'" in pg and order(uf, "sent = MKUNDO", "call $tk_confirm(sent, lines, '', res, cmsg)", "if res # 'run' then", "return", "execute MKUNDO trapping aborts capturing mkout")
       and pg.count("create.file") == 1, "")
    ck("TB16", "the limits are numbers declared once and tested where they matter: 4 conditions, 10 operations, 100000 records in one run, 20000 ids in a saved list, 20 changes shown, 120 characters of text; a fifth condition, an eleventh operation, a bigger selection and a bigger list are refused",
       all(re.search(r"^\s*%s = %s\s*$" % (k, v), pg, re.M) for k, v in (("NCOND", "4"), ("NOPS", "10"), ("MAXSEL", "100000"), ("MAXLIST", "20000"), ("NPREV", "20"), ("MAXTXT", "120"))) and "if nsc >= NCOND then" in pg and "if nopr >= NOPS then" in pg
       and "if lcnt > MAXLIST then" in rs and "if sel.n > MAXSEL then\n      sel.big = 1" in rs and "if not(sel.ok) or sel.big then" in dd, "")
    ao2 = block(pg, "ask.op")
    pa = block(pg, "pick.attr")
    ct = block(pg, "check.text")
    ck("TB17", "the texts and numbers a person gives are checked before they are kept: text is printable ASCII (32 to 126) and at most MAXTXT long, and every text question is followed by that check; Add needs a number; an attribute is a whole number from 1 to 999 (never 0, "
       "the record id), and a copy onto the same attribute is refused",
       "if d < 32 or d > 126 then" in ct and "if len(tv) > MAXTXT then" in ct and ao2.count("gosub check.text") == 4 and "if tv = '' or not(num(tv)) or len(tv) > 15 then" in ao2
       and "index(tn, '.', 1) > 0 or tn < 1 or tn > 999" in pa and "if ra.n = o.attr then" in ao2 and "dat >= 1 and dat <= 999" in block(pg, "dict.items"), "")
    dl = block(pg, "diff.line")
    sf = block(pg, "safe.text")
    ck("TB18", "nothing read from a file reaches the screen as it is: every value in the preview and the id go through safe.text, which shows the marks as ] \\ ^ and every byte that is not printable ASCII as a dot, and cuts the value",
       dl.count("gosub safe.text") == 3 and "if d2 >= 32 and d2 <= 126 then st2 := c2 else st2 := '.'" in sf and "sv = sv[1, 40]" in sf and "sv = change(change(change(sv, @vm, ']'), @sm, '\\'), @fm, '^')" in sf
       and "gosub safe.text" in block(pg, "draw.sel") and "gosub safe.text" in block(pg, "read.undo.info"), "")
    bk = block(pg, "build.keys")
    ck("TB19", "every key the page acts on has a place in the key table (the function-key row shows exactly the keys it uses), and A is on the row only while a dry run stands and U only while there is a run to put back",
       all(("call $tk_keys('add', keys, '%s'," % k) in bk for k in ("f1", "f6", "f", "m", "j", "l", "n", "e", "x", "r", "a", "u", "f5", "ctrl-q")) and "'apply', 'apply', '', (if dr.valid then 1 else 0))" in bk
       and "'undo', 'undo', '', (if un.have and un.state # 'undone' then 1 else 0))" in bk and "if len(nm) = 1 then nm = downcase(nm)" in pg, "")
    ck("TB20", "the layout fits the 140 by 43 frame (S.88 L2: the four boxes are the layout service's panes, declared 4, 9, 13 and 13 rows by 138 and drawn from their rectangles; the numbers at 140 by 43 are "
               "test-l2-files-units.py's): four boxes (rows 1-4, 5-13, 14-26, 27-39), 4 condition rows at the Which box's y + 3, 10 operation rows at the What box's y + 2, 7 preview rows (the Result box's height less 6) at its y + 5; "
               "nothing is drawn on a border",
       all(s in pg for s in ("dcl<1> = 'file' : @vm : 1 : @vm : 1 : @vm : 4 : @vm : 138 :", "dcl<2> = 'which' : @vm : 2 : @vm : 1 : @vm : 9 : @vm : 138 :", "dcl<3> = 'what' : @vm : 3 : @vm : 1 : @vm : 13 : @vm : 138 :",
                             "dcl<4> = 'result' : @vm : 4 : @vm : 1 : @vm : 13 : @vm : 138 :", "screen box at fx,fy size fw,fh title 'File'", "screen box at sx,sy size sw,sh title 'Which records'",
                             "screen box at ox,oy size ow,oh title 'What to do to them'", "screen box at rx,ry size rw,rh title 'Result'", "VP = rh - 6"))
       and "at sx + 2,sy + 2 + yr" in block(pg, "draw.sel") and "at ox + 2,oy + 1 + yr" in block(pg, "draw.ops") and "at rx + 2,ry + 4 + yr" in block(pg, "draw.result") and "for yr = 1 to VP" in block(pg, "draw.result"), "")
    ck("TB21", "the page waits on the keyboard only through the base: the key read is screen key, the end of the input ends it, and the base is closed on the way out",
       "screen key returning nm" in pg and "if status() = ER$EOF then exit" in pg and "case nm = 'guardquit'\n            exit" in pg and pg.find("call $tk_close(ctx)") > pg.find("repeat"), "")
    ck("TB22", "the help record names a page of the documentation, and the page asks for it by that name (the key is the record's name), from F1, ? and a click on [?]",
       pg.count("call $tk_help('box', 'tool.bulk.page', hm, 0, 0)") == 2 and "call $tk_help('mark', fx + fw - 5, fy + 1, 0, 0)" in pg and "call $tk_help('hit', mev, fx + fw - 5, fy + 1, hit.m)" in pg and re.match(r"^[^\n]{1,60}\n[0-9a-z-]+\n", raw["help"]) is not None, repr(raw["help"][:60]))
    ck("TB23", "the gates the session holds are ASKED of the kernel (voc-edit, dict-edit, bp-edit, with -1) and shown; nothing is tried to learn them",
       all(("kernel(K$%s, -1)" % k) in block(pg, "draw.file") for k in ("VOC.EDIT", "DICT.EDIT", "BP.EDIT")), "")
    mf = block(pg, "make.fp")
    ck("TB24", "the fingerprint of a dry run covers everything the run depends on: the file, how records are chosen, the list name, all or any, the number of conditions and operations, and every condition and operation field",
       all(s in mf for s in ("fp = bf : @fm : selmode : @fm : selname : @fm : seljoin : @fm : nsc : @fm : nopr", "cnd.item<fi> : @vm : cnd.op<fi> : @vm : cnd.val<fi>", "opr.kind<fi> : @vm : opr.attr<fi> : @vm : opr.a1<fi> : @vm : opr.a2<fi>")), "")
    ed = ["do.file", "do.mode", "do.join", "do.list", "do.cnew", "do.cedit", "do.cdel", "do.onew", "do.oedit", "do.odel"]
    ck("TB25", "any edit makes a dry run stale: every routine that changes the file, the selection or an operation calls drop.dry, and a run (apply or undo) uses the dry run up",
       all("gosub drop.dry" in block(pg, b) for b in ed) and "dr.valid = 0" in block(pg, "drop.dry") and "dr.valid = 0" in ar and "dr.valid = 0" in du, [b for b in ed if "gosub drop.dry" not in block(pg, b)])
    ck("TB26", "choosing another file clears the selection and the operations (nothing of one file's settings is carried into another file)",
       order(df, "if ('S' : cf) # ('S' : bf) then", "nsc = 0", "cnd.item = ''", "nopr = 0", "opr.kind = ''", "end", "fileok = 1"), "")
    ck("TB27", "a saved list is read by name in BASIC and no command is built for it: the list branch of run.select holds no execute and no build.select, takes a list of at most MAXLIST ids and takes a name that is in it twice once",
       "execute" not in nostr(rs.split("gosub build.select")[0]) and "getlistv selname to slv setting lcnt then" in rs and "locate sid in sel.ids<1> by 'AL' setting lp else" in rs and rs.find("getlistv") < rs.find("gosub build.select"), "")
    ck("TB28", "a select counts as done only on the SUCCESS wording ('n record(s) selected to list 0'); anything else is a refusal that shows the verb's own first line, and nothing is selected",
       "suffix = ' record(s) selected to list 0'" in rs and "if sn = '' or not(num(sn)) then" in rs and "sel.why = (if sline = '' then 'the select said nothing' else sline[1, 100])" in rs and order(rs, "clearselect", "execute ssent"), "")
    ck("TB29", "an operation changes a record only where it really differs (an attribute past the end is not padded for nothing), Add needs an attribute that holds a number (an empty one or text leaves the whole record alone), and a record that cannot be worked out is not touched",
       "if ('S' : nv) # ('S' : ov) then newrec<oa> = nv" in ao and "if ov = '' or not(num(ov)) then\n               cant = 1" in ao and "if cant then exit" in ao and "case cant\n                  n.cant += 1" in dd and "case ('S' : newrec) = ('S' : rec)\n                  n.same += 1" in dd
       and "if cant or ('S' : newrec) = ('S' : rec) then\n               n.moved += 1" in ar
       and "if len(field(ov, '.', 2)) > 4 or len(field(opr.a1<oj>, '.', 2)) > 4 or len(ov) > 15 or len(opr.a1<oj>) > 15 then cant = 1" in ao, "")
    ck("TB30", "a run is refused when the dry run found nothing to change, and the records it works on are the ids and digests the dry run kept (never a new select)",
       "if dr.chg < 1 then" in da and "lids = dr.ids\n   lmd = dr.md5" in ar and "gosub run.select" not in ar and "gosub build.select" not in ar, "")
    ck("TB31", "the old record is kept before the new one is written, and if the data write fails the old record kept for it is taken out again and the run stops",
       order(ar, "write id : @fm : digest(newrec, 0, 'MD5') : @fm : rec on uf, n.written on error", "writeu newrec on fv, id on error", "delete uf, n.written") and "n.written -= 1" in ar, "")
    cu = block(pg, "check.undo")
    ow = strip_bas(raw["own"])
    ow_ok = ("uct # FL$TYPE.DH" in ow and "fileinfo(fv, FL$READONLY) = 1" in ow and "ucd = '' or ucp # ucd : '/' : name" in ow and "ucek = kernel(K$EDIT.KIND, ucp)" in ow and "uceo = kernel(K$EDIT.OK, ucp)" in ow
             and "ucek >= 1 and ucek <= 3" in ow and "case not(uceo)" in ow)
    ck("TB32", "the undo file is checked before anything is cleared, written or read back from it (the page is $internal, which the kernel lets through): check.undo wants a dynamic file, not read only, directly in the account's own directory under its own name, and the kernel's edit rules (K$EDIT.KIND outside the VOC, dictionary and program kinds, K$EDIT.OK) to allow it; undo.file (both opens), apply.run and do.undo call it right after the open and refuse before the first clearfile or write",
       # 28 Oct 26 (S.88 phase 2, S2): the test itself is in $tk_ownfile now (raw["own"]), which TOOL.QUERY calls too; check.undo only calls it with the open undo file and its name
       "call $tk_ownfile(uf, UNDOF, uck, ucw)" in cu and ow_ok
       and uf.count("gosub check.undo") == 2 and order(ar, "open UNDOF to uf else", "gosub check.undo", "if not(uck) then", "clearfile uf") and order(du, "open UNDOF to uf else", "gosub check.undo", "if not(uck) then", "n.undo = 0"), "")
    return rows


def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:70]))
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
    ("the page is opened for the administrator only", "TB2", sub("page", "call $tk_open('tool.bulk', '', ctx, err)", "call $tk_open('tool.bulk', 'admin', ctx, err)")),
    ("the page reads the VOC before it opens the base", "TB2", sub("page", "   call $tk_open('tool.bulk', '', ctx, err)\n", "   open 'VOC' to vocx then close vocx\n   call $tk_open('tool.bulk', '', ctx, err)\n")),
    ("an ordinary account has no verb", "TB1", setkey("newvoc", "")),
    ("SDSYS's verb runs another program", "TB1", sub("voc", "$tool_bulk", "$tool_keys")),
    ("the page runs a third command", "TB3", sub("page", "   dr.line = 'No dry run yet.", "   execute 'sh'\n   dr.line = 'No dry run yet.")),
    ("the page runs a command through $tk_run", "TB3", sub("page", "   dr.line = 'No dry run yet.", "   call $tk_run('sh', 'sh', xo, xs, xe)\n   dr.line = 'No dry run yet.")),
    ("the page opens a file of the operating system", "TB3", sub("page", "   dr.line = 'No dry run yet.", "   openseq '/etc/passwd' to xs then null\n   dr.line = 'No dry run yet.")),
    ("a value is put into the select without quote.val", "TB4", sub("page", "' ' : cnd.op<bi> : ' ' : qout", "' ' : cnd.op<bi> : ' ' : cnd.val<bi>")),
    ("the select sentence is built outside build.select", "TB4", sub("page", "   clearselect\n   execute ssent", "   ssent := ' ' : cnd.val<1>\n   clearselect\n   execute ssent")),
    ("the item is not checked", "TB4", sub("page", "      if bitem # '@id' then\n         nmv = bitem\n         gosub check.name\n         if not(okname) then serr = 'item ' : bi : ' is not a name the page gives to a command'\n      end\n", "")),
    ("the operator is not looked up in the table", "TB4", sub("page", "      if index(@fm : cw : @fm, @fm : cnd.op<bi> : @fm, 1) = 0 then serr = 'condition ' : bi : ' has an operator the page does not know'\n", "")),
    ("the file name is not checked before the select", "TB4", sub("page", "   nmv = bf\n   gosub check.name\n   if not(okname) then\n      serr = 'the file name is not one the page gives to a command'\n      return\n   end\n", "")),
    ("a double quote is allowed in a value", "TB5", sub("page", "0123456789 .,:+-_/@()%*'", "0123456789 .,:+-_/@()%*\"'")),
    ("a semicolon is allowed in a value", "TB5", sub("page", "0123456789 .,:+-_/@()%*'", "0123456789 .,:+-_/@()%*;'")),
    ("a long value is allowed", "TB5", sub("page", "if qv = '' or len(qv) > 60 then", "if qv = '' then")),
    ("a value with a space at the end is allowed", "TB5", sub("page", "      if qv[1, 1] = ' ' or qv[len(qv), 1] = ' ' then", "      if qv[1, 1] = '~' then")),
    ("a seventh operator", "TB6", sub("page", "@fm : 'like' : @fm : 'unlike'", "@fm : 'like' : @fm : 'unlike' : @fm : 'sh'")),
    ("an operation with no case", "TB6", sub("page", "         case okind = 'lower'\n            nv = downcase(ov)\n", "")),
    ("an operation evaluates the text", "TB6", sub("page", "            nv = change(ov, opr.a1<oj>, opr.a2<oj>)", "            nv = oconv(ov, opr.a1<oj>)")),
    ("the kernel is not asked about the file", "TB7", sub("page", "   ceo = kernel(K$EDIT.OK, cpath)\n", "   ceo = 1\n")),
    ("the kernel's refusal is not shown in its words", "TB7", sub("page", "cwhy = edit_msg(cek)", "cwhy = 'refused'")),
    ("the page's own kind check comes before the kernel's", "TB7", sub("page", "      case not(ceo)\n         cwhy = edit_msg(cek)", "      case cek >= 1 and cek <= 3 and ceo\n         cwhy = 'x'\n      case not(ceo)\n         cwhy = edit_msg(cek)")),
    ("a directory file is taken", "TB7", sub("page", "      case cft # FL$TYPE.DH\n", "      case 0\n")),
    ("the file is not judged again before the apply", "TB8", sub("page", "   gosub reopen.file\n   if not(fok) then return\n   close fv\n   gosub undo.file", "   gosub undo.file")),
    ("the file is not judged again for the undo", "TB8", sub("page", "   uf.name = un.file\n   cf = uf.name\n   gosub check.file\n   if not(cok) then", "   uf.name = un.file\n   cok = 1\n   if not(cok) then")),
    ("the dry run writes a record", "TB9", sub("page", "                  dr.md5 := digest(rec, 0, 'MD5')\n", "                  dr.md5 := digest(rec, 0, 'MD5')\n                  write newrec on fv, id\n")),
    ("the page writes a record outside the run", "TB9", sub("page", "   dr.line = 'No dry run yet.", "   write 'x' on bf, 'y'\n   dr.line = 'No dry run yet.")),
    ("the dry run calls the apply", "TB10", sub("page", "   gosub make.fp\n   dr.fp = fp\n   dr.valid = 1", "   gosub apply.run\n   gosub make.fp\n   dr.fp = fp\n   dr.valid = 1")),
    ("the dry run takes a lock", "TB10", sub("page", "         read rec from fv, id then\n            gosub apply.ops\n            begin case\n               case cant\n                  n.cant", "         readu rec from fv, id locked null then\n            gosub apply.ops\n            begin case\n               case cant\n                  n.cant")),
    ("apply does not need a dry run", "TB11", sub("page", "   if not(dr.valid) or dr.fp # fp then", "   if 0 then")),
    ("a stale dry run is accepted", "TB11", sub("page", "   if not(dr.valid) or dr.fp # fp then", "   if not(dr.valid) then")),
    ("apply does not ask for the file's name", "TB11", sub("page", "call $tk_confirm(sent, lines, bf, res, cmsg, sysmsg(12959))", "call $tk_confirm(sent, lines, '', res, cmsg, sysmsg(12959))")),
    ("apply runs whatever the box answered", "TB11", sub("page", "   call $tk_confirm(sent, lines, bf, res, cmsg, sysmsg(12959))\n   if res # 'run' then\n      msg = cmsg\n      return\n   end\n   gosub apply.run", "   call $tk_confirm(sent, lines, bf, res, cmsg, sysmsg(12959))\n   gosub apply.run")),
    ("apply is performed a second time", "TB11", sub("page", "   gosub read.undo.info\n   gosub draw.all\n   return\n\n* The run itself", "   gosub apply.run\n   gosub read.undo.info\n   gosub draw.all\n   return\n\n* The run itself")),
    ("a locked record is waited for", "TB12", sub("page", "      readu rec from fv, id locked\n         lk = 1\n      end then\n         got = 1\n      end else\n         got = 0\n      end\n      begin case\n         case lk\n            n.lock += 1",
                                                  "      read rec from fv, id then got = 1 else got = 0\n      begin case\n         case lk\n            n.lock += 1")),
    ("a record that moved is written over", "TB12", sub("page", "         case ('S' : digest(rec, 0, 'MD5')) # ('S' : emd)\n", "         case 0\n")),
    ("the old record is kept after the new one is written", "TB12", sub("page", "               write id : @fm : digest(newrec, 0, 'MD5') : @fm : rec on uf, n.written on error\n                  n.err += 1\n                  n.written -= 1\n                  halt.why = 'the undo file could not be written (status ' : status() : ')'\n               end\n               if halt.why = '' then\n                  writeu newrec on fv, id on error\n                     n.err += 1\n                     halt.why = 'a record could not be written (status ' : status() : ')'\n                     delete uf, n.written                       ;* the old record of a write that did not happen is not kept\n                     n.written -= 1\n                  end\n               end\n",
                                                                                                                   "               writeu newrec on fv, id on error\n                  n.err += 1\n                  halt.why = 'a record could not be written'\n                  delete uf, n.written\n                  n.written -= 1\n               end\n               write id : @fm : digest(newrec, 0, 'MD5') : @fm : rec on uf, n.written on error\n                  n.err += 1\n               end\n")),
    ("the run goes on after a write error", "TB12", sub("page", "      if halt.why # '' then exit\n", "")),
    ("the undo file is not cleared", "TB12", sub("page", "   clearfile uf\n", "")),
    ("a second audit line", "TB13", sub("page", "   dr.line = 'No dry run yet.", "   void kernel(K$AUDIT, 'bulk start')\n   dr.line = 'No dry run yet.")),
    ("the audit line comes before the run", "TB13", sub("page", "   close fv\n   hdr = 'bulk-undo' : @fm : bf : @fm : date() : @fm : time() : @fm : n.written", "   close fv\n   void kernel(K$AUDIT, 'bulk update file=' : bf : ' records=' : n.written)\n   hdr = 'bulk-undo' : @fm : bf : @fm : date() : @fm : time() : @fm : n.written")),
    ("the audit line is in capitals", "TB13", sub("page", "'bulk update file='", "'BULK UPDATE FILE='")),
    ("undo asks for no name", "TB14", sub("page", "call $tk_confirm(sent, lines, uf.name, res, cmsg, sysmsg(12960))", "call $tk_confirm(sent, lines, '', res, cmsg, sysmsg(12960))")),
    ("undo puts back a record that has changed since", "TB14", sub("page", "         case ('S' : digest(cur, 0, 'MD5')) # ('S' : uemd)\n", "         case 0\n")),
    ("undo is marked done when a record was locked", "TB14", sub("page", "   if u.lock = 0 and u.err = 0 then", "   if 1 then")),
    ("undo does not skip a record put back already", "TB14", sub("page", "      if uemd = 'restored' then\n         u.done += 1", "      if 0 then\n         u.done += 1")),
    ("the undo file is made without a box", "TB15", sub("page", "   call $tk_confirm(sent, lines, '', res, cmsg)\n   if res # 'run' then\n      msg = 'no undo file, so nothing was applied'\n      return\n   end\n", "")),
    ("the undo file is made with another command", "TB15", sub("page", "MKUNDO = 'create.file &bulk.undo&'", "MKUNDO = 'create.file &bulk.undo& directory'")),
    ("a fifth condition", "TB16", sub("page", "NCOND = 4 ", "NCOND = 5 ")),
    ("an eleventh operation", "TB16", sub("page", "   if nopr >= NOPS then\n      msg = 'at most ' : NOPS : ' operations'\n      return\n   end\n", "")),
    ("a bigger selection is read", "TB16", sub("page", "MAXSEL = 100000", "MAXSEL = 100000000")),
    ("text with a control character is taken", "TB17", sub("page", "      if d < 32 or d > 126 then", "      if d < 0 then")),
    ("a replace text is not checked", "TB17", sub("page", "               emptyok = 1\n               gosub check.text\n               emptyok = 0\n", "               emptyok = 1\n               emptyok = 0\n")),
    ("attribute 0 is taken", "TB17", sub("page", "tn < 1 or tn > 999", "tn < 0 or tn > 999")),
    ("a copy onto the same attribute is taken", "TB17", sub("page", "         if ra.n = o.attr then\n            msg = 'copying an attribute onto itself changes nothing'\n            return\n         end\n", "")),
    ("the preview shows a value as it is", "TB18", sub("page", "         sv = rec<fd>\n         gosub safe.text\n         bef = sv", "         sv = rec<fd>\n         bef = sv")),
    ("a control character is not turned into a dot", "TB18", sub("page", "if d2 >= 32 and d2 <= 126 then st2 := c2 else st2 := '.'", "st2 := c2")),
    ("apply is always on the function-key row", "TB19", sub("page", "(if dr.valid then 1 else 0))", "1)")),
    ("a key is missing from the key table", "TB19", sub("page", "   call $tk_keys('add', keys, 'x', 'remove', 'remove', 'Selection' : @sm : 'Operations', 1)\n", "")),
    ("the preview overruns the border", "TB20", sub("page", "VP = rh - 6", "VP = rh - 5")),
    ("the first box overlaps the second", "TB20", sub("page", "dcl<1> = 'file' : @vm : 1 : @vm : 1 : @vm : 4 : @vm : 138 :", "dcl<1> = 'file' : @vm : 1 : @vm : 1 : @vm : 5 : @vm : 138 :")),
    ("the end of the input is not seen", "TB21", sub("page", "            if status() = ER$EOF then exit\n", "")),
    ("the help key names a page that does not exist", "TB22", sub("help", "29c-sd-tcl-the-development-tools", "")),
    ("the help box is not reached from F1", "TB22", sub("page", "         call $tk_help('box', 'tool.bulk.page', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'", "         msg = 'help'\n      case nm = 'f5'")),
    ("a gate is not asked", "TB23", sub("page", "kernel(K$DICT.EDIT, -1)", "1")),
    ("the fingerprint leaves the operations out", "TB24", sub("page", "fp := @fm : opr.kind<fi> : @vm : opr.attr<fi> : @vm : opr.a1<fi> : @vm : opr.a2<fi>", "fp := @fm : opr.kind<fi> : @vm : opr.attr<fi>")),
    ("the fingerprint leaves the conditions' values out", "TB24", sub("page", "cnd.item<fi> : @vm : cnd.op<fi> : @vm : cnd.val<fi>", "cnd.item<fi> : @vm : cnd.op<fi>")),
    ("deleting an operation leaves the dry run standing", "TB25", sub("page", "   if oc < 1 then oc = 1\n   gosub drop.dry\n   gosub draw.all", "   if oc < 1 then oc = 1\n   gosub draw.all")),
    ("a run does not use the dry run up", "TB25", sub("page", "   dr.valid = 0                                                 ;* the data moved: the dry run is spent", "   dr.valid = dr.valid                                          ;* the data moved: the dry run is spent")),
    ("another file keeps the operations of the last", "TB26", sub("page", "      nopr = 0 ; opr.kind = '' ; opr.attr = '' ; opr.a1 = '' ; opr.a2 = '' ; opr.name = ''\n      sc = 1 ; oc = 1", "      sc = 1 ; oc = 1")),
    ("a saved list is run as a command", "TB27", sub("page", "         sel.n = dcount(sel.ids, @fm)\n         if sel.ids = '' then sel.n = 0", "         execute 'get.list ' : selname\n         sel.n = dcount(sel.ids, @fm)\n         if sel.ids = '' then sel.n = 0")),
    ("a name that is in the list twice is taken twice", "TB27", sub("page", "locate sid in sel.ids<1> by 'AL' setting lp else", "locate sid in sel.ids<1> by 'AL' setting lp then null else")),
    ("any output of the select counts as done", "TB28", sub("page", "   if sn = '' or not(num(sn)) then", "   if 0 then")),
    ("an old list 0 is not cleared before the select", "TB28", sub("page", "   clearselect\n   execute ssent", "   execute ssent")),
    ("Add pads an empty attribute", "TB29", sub("page", "            if ov = '' or not(num(ov)) then\n               cant = 1", "            if not(num(ov)) then\n               cant = 1")),
    ("an attribute is assigned even when it did not change", "TB29", sub("page", "      if ('S' : nv) # ('S' : ov) then newrec<oa> = nv", "      newrec<oa> = nv")),
    ("the undo file is not checked before it is cleared", "TB32", sub("page", "   gosub check.undo\n   if not(uck) then\n      close fv\n      close uf\n", "   uck = 1\n   if not(uck) then\n      close fv\n      close uf\n")),
    ("the undo file may stand anywhere", "TB32", sub("own", "      case ucd = '' or ucp # ucd : '/' : name\n", "      case 0\n")),
    ("the kernel's edit kind of the undo file is not asked", "TB32", sub("own", "      case ucek >= 1 and ucek <= 3\n", "      case 0\n")),
    ("the kernel's edit rules are not asked of the undo file", "TB32", sub("own", "      case not(uceo)\n", "      case 0\n")),
    ("the undo file's test is no longer asked of the shared routine", "TB32", sub("page", "   call $tk_ownfile(uf, UNDOF, uck, ucw)\n", "   uck = 1\n")),
    ("two numeric looking values are compared as numbers", "TB29", sub("page", "if ('S' : nv) # ('S' : ov) then newrec<oa> = nv", "if nv # ov then newrec<oa> = nv")),
    ("an Add that would lose decimals goes ahead", "TB29", sub("page", " or len(ov) > 15 or len(opr.a1<oj>) > 15 then cant = 1", " then cant = 0")),
    ("a record that cannot be worked out is changed", "TB29", sub("page", "      if cant then exit\n", "")),
    ("the apply selects again", "TB30", sub("page", "   lids = dr.ids\n   lmd = dr.md5\n   n.todo = dr.chg", "   gosub run.select\n   lids = dr.ids\n   lmd = dr.md5\n   n.todo = dr.chg")),
    ("a run with nothing to change is accepted", "TB30", sub("page", "   if dr.chg < 1 then\n      msg = 'the dry run found nothing to change'\n      return\n   end\n", "")),
    ("a failed data write keeps its old record", "TB31", sub("page", "                     delete uf, n.written                       ;* the old record of a write that did not happen is not kept\n", "")),
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
    print("test-toolbulk-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-toolbulk-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolbulk-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
