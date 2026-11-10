#!/usr/bin/env python3
"""test-idepath-units.py - operating system files in the IDE (the editor merge's stage E; ~/Documents/Audits/TUI/Opus_TUI_Plan.txt section 11, handoff-s88 step 4), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-idepath-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-idepath-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
28 Oct 26 dm  New with stage E.
30 Oct 26 dm  Stage E2 (the IDE MAKES operating system files): the helper has two more operations, 'create' and 'list' (P2, P11), and write.file is split into make.data and put.data (P7); the tab is made
              in path.tab.make (P12, P12b); the name form takes path: in every mode (P18); messages 12732 is gone and 12751-12754 and 12767-12770 are new (P21); the file's new rules are
              test-ideos-units.py's.  P8 also pins ER_EXISTS and ER_FNF to err.h.
END-HISTORY

WHAT IT HOLDS.  `ide path:/full/name`, and path:/full/name in Open's form, open an operating system file in a tab of its own (bn 'path:', bi the exact path, kind 'path').
THE POINT OF THE DESIGN IS WHO ASKS THE KERNEL'S GATES: the IDE is $internal, and the kernel trusts a $internal program with an OPENSEQ by pathname (no OS gate, no edit gate), so
every touch of the file is in gpl.bp/ide_osfile, which is NOT $internal - the OPENSEQ in it is asked as the account is.  The IDE therefore contains no OPENSEQ, READBLK, WRITEBLK,
WEOFSEQ or SEEK at all (P10), and the helper contains no other way to the file than its one OPENSEQ (P2).  The helper opens for reading and writing WITHOUT truncation (no
OVERWRITE, no READONLY: the kernel makes the file variable read-only itself when the account may not write), refuses a name that is not written in the one form (absolute, no . or
.., no doubled or final slash, no control character), a device / pipe / port (closed again before it is read), a file over 2 MB, a NUL or a byte from 248 to 255, reads the file
whole and checks the byte count against the size (the kernel reports a read error as the end of the file), and writes IN PLACE: SEEK 0, WRITEBLK, then WEOFSEQ at the new length - the
same inode, owner, mode and links (a directory-file write truncates or renames, and always adds a newline).  The IDE keeps the file variable (and with it the SD lock) in the tab,
asks K$PATH.OK of the same string first for its own message, reads the file once more before it writes and asks the overwrite question when it differs (text, CR LF, final line end),
keeps no recovery copy, and refuses compile, run, SED, fields, Save as, Write a copy and the include for such a tab.

***IT RUNS NOTHING, SO IT CANNOT SAY THAT A GATE REFUSES OR THAT A BYTE SURVIVES A SAVE***: that is sandbox-ide-path.py (fixture accounts with the OS gate off and on, the
disk as the evidence, inode / mode / owner / link count before and after).  --selftest breaks each property the way an edit plausibly would and requires a check to notice.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
ERRH = os.path.join(SD64, "gplsrc", "err.h")
NEWMSG = list(range(12733, 12748)) + [12751, 12752, 12753, 12754, 12767, 12768, 12769, 12770]      # 12732 was deleted 30 Oct 26 (stage E2: every mode takes a path: name)


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


def first_gosub(text):
    m = re.search(r"gosub (\S+)", text)
    return m.group(1) if m else ""


def split_args(s):
    """the top-level arguments of a call's argument text"""
    out, depth, quote, cur = [], 0, "", ""
    for ch in s:
        if quote:
            cur += ch
            if ch == quote:
                quote = ""
        elif ch in "'\"":
            quote = ch
            cur += ch
        elif ch == "(":
            depth += 1
            cur += ch
        elif ch == ")":
            depth -= 1
            cur += ch
        elif ch == "," and depth == 0:
            out.append(cur.strip())
            cur = ""
        else:
            cur += ch
    out.append(cur.strip())
    return out


def read(path):
    try:
        with open(path, encoding="latin-1") as f:
            return f.read()
    except OSError:
        return ""


def load():
    src = {"ide": read(os.path.join(GPL, "ide")), "ide_name": read(os.path.join(GPL, "ide_name")), "osf": read(os.path.join(GPL, "ide_osfile")), "errh": read(ERRH)}
    for n in NEWMSG + [12219, 12185, 12732]:
        src["m%d" % n] = read(os.path.join(MSG, str(n)))
    return src


def checks(src):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    ide = strip(src["ide"])
    inm = strip(src["ide_name"])
    osf = strip(src["osf"])
    LI = {n: label(ide, n) for n in ("open.path", "path.tab.make", "path.refusal", "path.not.for", "save.one", "save.path", "tab.state", "tab.unlock", "relock.all", "ro.check", "rc.tick",
                                       "load.current", "tab.labels", "default.file", "get.context", "do.open", "do.compile", "do.fields", "do.writeas", "do.saveas",
                                       "do.include", "ai.go", "status.line", "is.dirty", "new.form")}
    LO = {n: label(osf, n) for n in ("check.name", "open.file", "read.file", "read.all", "parse.raw", "write.file", "make.data", "put.data", "create.file", "list.dir")}
    ta = label(inm, "try.accept")
    head = ide[: ide.find("gosub open.screen")]
    main = ide[: ide.find("apply.theme:")]
    ck("P0", "NULL CASE: the IDE, the name form and the helper were read and every routine this check reads is there (a check on nothing would pass)",
       len(ide) > 60000 and len(inm) > 3000 and len(osf) > 3000 and all(len(v) > 20 for v in list(LI.values()) + list(LO.values())) and len(ta) > 100,
       repr(sorted(k for k, v in list(LI.items()) + list(LO.items()) if len(v) <= 20)))

    # ---- the helper: what it is and the one way it touches a file -----------------------------------------------------------------------------------------------------
    ck("P1", "the helper is NOT $internal (the kernel then asks the account's OS gate and the edit gates for its OPENSEQ), is a !-routine (a $ name is refused by the compiler without $internal) "
       "and has the six parameters every call passes",
       re.search(r"^\$internal", osf, re.M) is None and "$catalog !ide_osfile" in osf and "subroutine ide_osfile(op, path, f, text, info, why)" in osf, "")
    opens = re.findall(r"^[ \t]*(?:openseqp?|openpath|opendb|open)[ \t]+.*$", osf, re.M | re.I)
    ck("P2", "the helper's ONLY ways to a file are two OPENSEQs, `openseq path to f ...` in open.file and `openseq path creating to f ...` in create.file (30 Oct 26) - no OVERWRITE (it truncates), no "
       "SHARED (it keeps open-or-create where a plain CREATING is exclusive), no READONLY, no APPEND, no record form, no OPENPATH, no EXECUTE, no OSPATH, no delete",
       opens == ["   openseq path to f on error", "   openseq path creating to f on error"] and LO["open.file"].count("openseq") == 1 and LO["create.file"].count("openseq") == 1
       and "creating" not in LO["open.file"] and not re.search(r"\b(execute|ospath|oswrite|osread|osdelete|writeseq|readseq|delete|sh)\b", osf, re.I), repr(opens))
    o = LO["open.file"]
    ck("P3", "open.file: the name is checked first; OPENSEQ has ON ERROR (it returns itself) and LOCKED, and the LOCKED flag is tested AFTER the statement - the clauses END the statement, so an ELSE is never "
       "reached from LOCKED and the next FILEINFO would meet a file variable that was never assigned (the reviewer's finding 1); the ELSE branch CLOSES the variable (an OPENSEQ that took ELSE keeps the "
       "name locked) before it decides why; absent, the gate (ER_PERM) and not-a-file (ER_NSEQ) each have their own answer and anything else is 'cant' with the status",
       ordered(o, "gosub check.name", "if why # '' then return", "openseq path to f on error", "why = 'cant'", "return", "end locked", "lk.user = 1", "end then", "end else", "op.st = status()",
               "if not(unassigned(f)) then close f", "case op.st = 0", "why = 'none'", "case op.st = ER.PERM", "why = 'gate'", "case op.st = ER.NSEQ", "why = 'dir'", "why = 'cant'", "info<6> = op.st",
               "if lk.user then", "why = 'locked'", "return", "FL$SEQTYPE")
       and "case lk.user" not in o, "")
    ck("P4", "after the open: a port, device, pipe or block device (FL$SEQTYPE) is closed again BEFORE anything is read; the read-only state of the variable is noted; a failed read closes the "
       "file it opened; the read-only flag is INFO<3>",
       ordered(o, "if (fileinfo(f, FL$SEQTYPE) + 0) # 0 then", "close f", "why = 'special'", "return", "ro = fileinfo(f, FL$READONLY) + 0", "gosub read.file", "if why # '' then", "close f",
               "info<3> = ro"), "")
    ra = LO["read.all"]
    ck("P5", "read.all asks the size first (SEEK to the end, FL$SEQPOS), refuses a file over OSF.MAX BEFORE the READBLK loop, and demands that the bytes read come to that size",
       ordered(ra, "seek f, 0, 2 else why = 'io'", "fsize = fileinfo(f, FL$SEQPOS) + 0", "if fsize > OSF.MAX then", "why = 'big'", "seek f, 0, 0 else why = 'io'", "readblk blk from f, OSF.BLK else exit",
               "if len(raw) # fsize then why = 'io'"), "")
    pr = LO["parse.raw"]
    ck("P6", "parse.raw refuses a NUL or a byte from 248 to 255 (the set is built from char(0) and 248 to 255), takes CR LF only when EVERY line ends so (as many CR as LF, and as many CR LF), "
       "remembers whether the last line had its line end, and splits on that end",
       ordered(osf, "nope = char(0)", "for j = 248 to 255", "nope := char(j)") and ordered(pr, "if convert(nope, '', raw) # raw then", "why = 'bytes'", "n.lf = count(raw, lf.c)", "count(raw, cr.c) = n.lf",
       "count(raw, cr.c : lf.c) = n.lf", "crlf = 1", "fin = 1", "text = change(body, eol, @fm)"), "")
    wf = LO["write.file"]
    ck("P7", "write.file: a read-only file variable is not written (FL$READONLY, no write tried); the text is checked (make.data, shared with 'create') for NUL and the marks (the field marks that are its line "
       "ends taken out first) and for the size BEFORE put.data; the write is SEEK 0, WRITEBLK, WEOFSEQ ON ERROR in that order (IN PLACE: nothing is truncated until the new text is written); and none of the three opens anything",
       ordered(wf, "if fileinfo(f, FL$READONLY) then", "why = 'ro'", "gosub make.data", "if why # '' then return", "gosub put.data")
       and ordered(LO["make.data"], "flat = convert(@fm, '', text)", "if convert(nope, '', flat) # flat then", "why = 'bytes'", "if len(data) > OSF.MAX then", "why = 'big'")
       and ordered(LO["put.data"], "seek f, 0, 0 else", "writeblk data to f else", "weofseq f on error", "gosub read.all", "if len(raw) # len(data) or raw # data then", "why = 'io'", "gosub parse.raw")
       and "openseq" not in wf + LO["make.data"] + LO["put.data"], "")
    rf_ = LO["read.file"]
    ck("P7b", "the second look ('reread', rr.again): the file variable's buffer is thrown away first (a WRITEBLK of nothing, not on a read-only variable: a SEEK keeps the buffer and a same-size change by "
       "another program was read back as the old text), and after the read the link count of the variable (STATUS field 7, an fstat) being 0 is 'gone' - removed, or replaced by a rename; open does neither",
       ordered(rf_, "if rr.again then", "writeblk '' to f", "gosub read.all", "gosub parse.raw", "if rr.again then", "status st.f from f", "(st.f<7> + 0) = 0", "why = 'gone'")
       and "FL$READONLY" in rf_[: rf_.find("gosub read.all")] and "rr.again = 0" in osf and ordered(osf, "case op = 'reread'", "rr.again = 1", "gosub read.file"), "")
    cons = {m.group(1): m.group(2) for m in re.finditer(r"#define\s+(ER_NSEQ|ER_PERM|ER_FNF|ER_EXISTS)\s+(\d+)", src["errh"])}
    ck("P8", "the status numbers the helper compares are gplsrc/err.h's (ER_NSEQ, ER_PERM, ER_FNF for a directory that is not there, ER_EXISTS for the exclusive create) and the size cap is 2 MB as message 12737 says",
       all(cons.get(n) for n in ("ER_NSEQ", "ER_PERM", "ER_FNF", "ER_EXISTS")) and ("ER.NSEQ = %s" % cons["ER_NSEQ"]) in osf and ("ER.PERM = %s" % cons["ER_PERM"]) in osf
       and ("ER.FNF = %s" % cons["ER_FNF"]) in osf and ("ER.EXISTS = %s" % cons["ER_EXISTS"]) in osf and "OSF.MAX = 2097152" in osf
       and "2 MB" in src["m12737"], repr(cons))
    cn = LO["check.name"]
    ck("P9", "the name is written in the one form: at least two characters, at most 1000, absolute, no final slash, no control character (0 to 31 and 127 are built in the helper), no // /./ /../ and no "
       "final /. or /..",
       all(s in cn for s in ("p.n < 2", "p.n > 1000", "path[1, 1] # '/'", "path[p.n, 1] = '/'", "convert(ctl, '', path) # path", "index(path, '//', 1)", "index(path, '/./', 1)",
                              "index(path, '/../', 1)", "path[p.n - 1, 2] = '/.'", "path[p.n - 2, 3] = '/..'"))
       and ordered(osf, "ctl = char(127)", "for j = 0 to 31", "ctl := char(j)", "for j = 248 to 255", "ctl := char(j)"), "")

    # ---- the IDE touches no file itself --------------------------------------------------------------------------------------------------------------------------------
    bad = re.findall(r"\b(openseqp?|openpath|readblk|writeblk|weofseq|readseq|writeseq|ospath|oswrite|osread|osdelete)\b|^\s*seek\b", ide + "\n" + inm, re.I | re.M)
    ck("P10", "the IDE and the name form contain NO OPENSEQ, OPENPATH, READBLK, WRITEBLK, WEOFSEQ, SEEK, READSEQ, WRITESEQ or OSPATH: every touch of the operating system's file is the helper's, "
       "where the kernel asks the account's gates", not bad, repr(bad))
    calls = re.findall(r"call !ide_osfile\((.*)\)", ide + "\n" + inm)
    ops = sorted(set(split_args(c)[0] for c in calls))
    ck("P11", "every call of !ide_osfile has six arguments (a wrong count stops only when the call runs) and the operations are exactly check, create, list, open, reread and save (create and list since 30 Oct 26)",
       bool(calls) and all(len(split_args(c)) == 6 for c in calls) and ops == ["'check'", "'create'", "'list'", "'open'", "'reread'", "'save'"], repr((len(calls), ops)))

    # ---- opening ------------------------------------------------------------------------------------------------------------------------------------------------------
    op = LI["open.path"]
    ck("P12", "open.path: the spelling is checked, the tab already holding the file is found (and nothing else is done), K$PATH.OK is asked of the same string (message 12185) BEFORE the helper opens, a "
       "free lock slot is found, and the tab takes the file variable and CLOSES the call's own copy (the tab's variable is the one that holds the lock)",
       ordered(op, "call !ide_osfile('check', op.path", "gosub tab.find", "if not(kernel(K$PATH.OK, op.path)) then", "sysmsg(12185, @who)", "for op.s = 1 to MAXLOCK", "call !ide_osfile('open', op.path",
               "tfv(op.s) = op.f", "close op.f", "tused<op.s> = 1", "gosub path.tab.make"), "")
    ptm = LI["path.tab.make"]
    ck("P12b", "path.tab.make (the tail of open.path, which New with an operating system name uses too since 30 Oct 26): an untitled clean buffer is taken away before the tab is made; file 'path:', "
       "record the path, kind 'path', no dictionary flag, the slot, the line ends, the read-only flag, never the token form, and bytes 128 to 247 make it read-only (na.mark)",
       ordered(ptm, "gosub stash.current", "gosub drop.clean.untitled", "nbuf += 1", "bn<nbuf> = 'path:'", "bi<nbuf> = op.path", "ts.kind = 'path'", "ts.dict = ''", "ts.slot = op.s", "gosub tab.state",
               "k = 'm' : uid", "bx{k} = 0", "k = 'p' : uid", "bx{k} = (op.info<1> + 0) : @fm : (op.info<2> + 0)", "k = 'z' : uid", "bx{k} = op.info<3> + 0", "gosub load.current"), "")
    ck("P13", "a new tab starts with no read-only flag and no line ends (tab.state), so a tab that is not an operating system file is never read-only for it",
       ordered(LI["tab.state"], "k = 'z' : uid", "bx{k} = 0", "k = 'p' : uid", "bx{k} = ''"), "")
    rf = LI["path.refusal"]
    ck("P13b", "every answer of the helper has its message: name 12733, none 12734, gate 12185, dir and special 12735, locked 12736, big 12737, bytes 12738, anything else 12739",
       ordered(rf, "'name'", "12733", "'none'", "12734", "'gate'", "12185", "'dir'", "'special'", "12735", "'locked'", "12736", "'big'", "12737", "'bytes'", "12738", "12739"), "")

    # ---- saving ---------------------------------------------------------------------------------------------------------------------------------------------------------
    so = LI["save.one"]
    ck("P14", "save.one: a read-only tab is refused first (ro.check), 'nothing to save' is judged as for a record, and then a path tab goes to save.path BEFORE the record's file variable, "
       "edit.check and WRITEU are reached",
       ordered(so, "gosub ro.check", "if not(sv.new) and (sv.text : '|') = (sv.saved : '|') then", "if sv.kind = 'path' then", "gosub save.path", "return", "if sv.slot then\n      fv = tfv(sv.slot)", "gosub edit.check"), "")
    sp = LI["save.path"]
    ck("P14b", "save.path: no lock slot is a failure, the file is READ AGAIN through the tab's own variable, compared with what was read (text, CR LF, final line end) and a difference - or a file that is not "
       "text now - is the overwrite question with Cancel the default; only then is the helper asked to save; sv.ok is set only when it answered ''",
       ordered(sp, "if sv.slot = 0 then", "call !ide_osfile('reread', sv.id, tfv(sv.slot), sp.text, sp.info, sp.why)", "if sp.why = 'gone' then", "sysmsg(12747, sv.name, sv.id)", "return",
               "sp.same = (sp.why = '')", "(sp.text : '|') = (sv.saved : '|')", "sp.info<1> + 0 = sv.pinfo<1> + 0", "sp.info<2> + 0 = sv.pinfo<2> + 0", "buttons 'Overwrite,Cancel' default 2",
               "if b # 1 then return", "sp.sent = sv.text", "call !ide_osfile('save', sv.id, tfv(sv.slot), sv.text, sp.winfo, sp.why)", "case sp.why = ''", "k = 's' : u", "bx{k} = sv.text",
               "k = 'p' : u", "bx{k} = (sp.winfo<1> + 0) : @fm : (sp.winfo<2> + 0)", "if (sv.text : '|') # (sp.sent : '|') then", "if sv.i = cb then gosub load.current", "sv.ok = @true",
               "case sp.why = 'ro'") and sp.count("sv.ok = @true") == 1, "")
    ck("P14c", "a failed write is said in a box (12743 'may be partly written', 12746 for text it will not write) and leaves the tab's baseline alone, so the next save asks again",
       ordered(sp, "case sp.why = 'bytes' or sp.why = 'big'", "12746", "gosub refuse.box", "case 1", "12743", "sp.winfo<6>", "gosub refuse.box") and sp.count("k = 's' : u") == 1
       and sp[sp.find("case sp.why = 'ro'"):].count("sv.ok") == 0, "")
    ck("P15", "read-only: ro.check refuses a path tab the session may not change (bx z, message 12742) before it asks about a lock; the editor is read-only for it; the status line says so (12741)",
       ordered(LI["ro.check"], "ro.k = 'z' : bu<ro.i>", "ro.why = 'osro'", "sysmsg(12742, bf.name, bf.id)", "ro.k = 'o' : bu<ro.i>")
       and "ro.k = 'z' : bu<ro.i>\n   if bx{ro.k} then\n      ro.ok = @false" in LI["ro.check"]
       and ordered(LI["load.current"], "k = 'z' : u", "if bx{k} then ro = 1") and ordered(LI["status.line"], "k = 'z' : bu<cb>", "if bx{k} then t := '  ' : sysmsg(12741)"), "")
    ck("P16", "closing a path tab CLOSES its file variable (a record is RELEASEd; bi is a path, not a record id), the locks are not taken again after a program (nothing a program does has that lock "
       "by name), and no recovery copy is kept (rc.tick skips the tab before it looks at changes)",
       ordered(LI["tab.unlock"], "if bx{tu.k2} = 'path' then", "close tfv(tu.s)", "end else", "release tfv(tu.s), bi<tu.i>")
       and ordered(LI["relock.all"], "if bx{rl.k2} = 'path' then rl.s = 0", "if rl.s then")
       and ordered(LI["rc.tick"], "gosub is.dirty", "if bx{rk.pk} = 'path' then continue", "if not(dirty) then"), "")

    # ---- what does not apply ----------------------------------------------------------------------------------------------------------------------------------------
    pnf = LI["path.not.for"]
    ck("P17", "path.not.for answers true, and says why (12744), for a tab whose file is 'path:'; compile (and so run, debug and catalogue), SED, fields and the include ask it FIRST; Save as asks it after the "
       "non-ASCII check and before it asks the form; WRITE A COPY DOES NOT ASK IT: it puts the text in a record and touches neither the file nor the tab, and it is the way out of a save that failed (finding 4)",
       ordered(pnf, "if nbuf = 0 then return", "if bn<cb> # 'path:' then return", "pa.no = @true", "sysmsg(12744, bn<cb>, bi<cb>)")
       and all(first_gosub(LI[n]) == "path.not.for" and "if pa.no then return" in LI[n] for n in ("do.compile", "do.include"))
       and ordered(LI["do.fields"], "gosub fields.is.on", "gosub fields.leave", "gosub path.not.for", "if pa.no then return", "gosub ro.check")         # 30 Oct 26 (stage 2b): F12 on a tab that shows its fields leaves; otherwise the file is asked first
       and ordered(LI["do.saveas"], "gosub path.not.for", "if pa.no then return", "gosub stash.current")
       and "path.not.for" not in LI["do.writeas"] and ordered(LI["do.writeas"], "wa.text = bx{k}", "gosub write.copy"), "")
    ck("P17b", "the forms start from a file of records (default.file and get.context never answer 'path:'), and the AI is told it is an operating system file, not a record",
       "if df = 'path:' then df = ''" in LI["default.file"] and "if ctx.file = 'path:' then ctx.file = ''" in LI["get.context"]
       and ordered(LI["ai.go"], "if bn<cb> = 'path:' then", "It is the operating system file", "end else", "'File ' : bn<cb>"), "")

    # ---- naming it --------------------------------------------------------------------------------------------------------------------------------------------------
    ck("P18", "the name form takes path: BEFORE it asks for a record id and from the name as typed (pw, never the folded ff), in EVERY mode since 30 Oct 26 (12732 is gone); the spelling is "
       "$ide_osfile's 'check'; Open returns the file 'path:' and the name with no kernel key asked and nothing opened; the other modes ask K$PATH.OK and then K$EDIT.OS.OK of the name first (the "
       "details are test-ideos-units.py's O-rows); the branch opens no file or record itself",
       ordered(ta, "pw = trimf(trimb(w1{'value'}))", "ff = downcase(pw)", "case ff = ''", "case ff[1, 5] = 'path:'", "op.path = trimf(trimb(pw[6, 9999]))",
               "if op.path = '' then op.path = trimf(trimb(w2{'value'}))", "call !ide_osfile('check', op.path", "msg = sysmsg(12733, op.path)", "case mode = 'open'", "file = 'path:'", "id = op.path", "res = 'ok'",
               "case not(kernel(K$PATH.OK, op.path))", "case not(kernel(K$EDIT.OS.OK, op.path))", "case 1", "file = 'path:'", "id = op.path", "res = 'ok'", "case ii = ''")
       and "sysmsg(12732" not in ta and "downcase(pw" not in ta.replace("ff = downcase(pw)", "")
       and not re.search(r"^\s*open\b", ta[ta.find("case ff[1, 5] = 'path:'"): ta.find("case ii = ''")], re.M)
       and "kernel(" not in ta[ta.find("case mode = 'open'"): ta.find("case not(kernel(K$PATH.OK")], "")
    ck("P19", "the command line: the path is the rest of the sentence after the first word, as typed (never folded or split), the file and record words are cleared, it opens after the form is made, "
       "and the bare start's recovery offer is skipped",
       ordered(head, "path0 = ''", "rest0 = field(sent.in, ' ', 2, 9999)", "if upcase(rest0[1, 5]) = 'PATH:' then", "path0 = trimf(trimb(rest0[6, 9999]))", "fn0 = ''", "id0 = ''", "dflag0 = ''", "seq0 = 0")
       and "downcase(path0" not in ide and "downcase(rest0" not in ide
       and ordered(main, "gosub new.form", "if path0 # '' then", "op.path = path0", "gosub open.path", "screen focus f, 'ed'", "and path0 = '' then gosub rc.untitled"), "")
    ck("P20", "Open (Ctrl-O) hands a 'path:' answer to open.path with the name as the form gave it (never folded), before it would open a record; the tab strip shows the last name with 'os '; "
       "the language follows that name (no file, the suffix or a #! line)",
       ordered(LI["do.open"], "if op.file = 'path:' then", "op.path = op.id", "gosub open.path", "return", "or.file = op.file") and "downcase(op.id" not in LI["do.open"]
       and "if bn<i> = 'path:' then labels<1, i> = 'os ' : field(bi<i>, '/', dcount(bi<i>, '/'))" in LI["tab.labels"]
       and ordered(LI["load.current"], "if bn<cb> = 'path:' then", "sy.file = ''", "sy.id = field(bi<cb>, '/', dcount(bi<cb>, '/'))", "gosub syntax.for"), "")
    ck("P21", "the messages 12733-12747, 12751-12754 and 12767-12770 exist, are one line, and each is used by the IDE (12733 by the name form too); 12732 is gone from the tree and from the code; the help names path:",
       all(src["m%d" % n].strip() and src["m%d" % n].count("\n") == 1 for n in NEWMSG)
       and all(("sysmsg(%d" % n) in ide for n in NEWMSG) and "sysmsg(12733" in inm
       and not src["m12732"].strip() and "12732" not in ide + inm + osf
       and "Ctrl-O           Open a record by file and name; path:/full/name there opens an operating system file" in src["m12219"],
       repr([n for n in NEWMSG if not src["m%d" % n].strip() or ("sysmsg(%d" % n) not in ide]))
    ck("P22", "the reviewer's smaller findings: a path is trimmed at its ENDS only (TRIM squeezes blanks inside a name: open.path, the command line, the name form); texts are compared as strings in is.dirty "
       "(# compares two numbers as numbers, so a one-line 1.0 made 1 was no change); the form made again after a resize keeps an operating system file read-only and names its language by its last component",
       "op.path = trimf(trimb(op.path))" in LI["open.path"] and "trim(" not in re.sub(r"trim[fb]\(", "", LI["open.path"]) and "dirty = ((d1 : '|') # (d2 : '|'))" in LI["is.dirty"]
       and ordered(LI["new.form"], "k = 'z' : u", "if bx{k} then ed.ro = 1", "if bn<cb> = 'path:' then", "sy.file = ''", "sy.id = field(bi<cb>, '/', dcount(bi<cb>, '/'))")
       and not re.search(r"(?<![a-z])trim\(", head[head.find("path0 = ''"): head.find("seq0 = 0")]) and not re.search(r"(?<![a-z])trim\(", ta[ta.find("case ff[1, 5] = 'path:'"): ta.find("case ii = ''")]), "")
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
    ("the helper is $internal", "P1", sub("osf", "subroutine ide_osfile(", "$internal\nsubroutine ide_osfile(")),
    ("the helper truncates (OVERWRITE)", "P2", sub("osf", "   openseq path to f on error", "   openseq path overwrite to f on error")),
    ("the helper opens read-only", "P2", sub("osf", "   openseq path to f on error", "   openseq path readonly to f on error")),
    ("the helper has a second way in", "P2", sub("osf", "   gosub read.file\n   if why # '' then\n      close f", "   openpath path to f2 else null\n   gosub read.file\n   if why # '' then\n      close f")),
    ("the ELSE keeps the name locked", "P3", sub("osf", "      op.st = status()\n      if not(unassigned(f)) then close f\n      begin case", "      op.st = status()\n      begin case")),
    ("a gate refusal is said as 'cannot'", "P3", sub("osf", "         case op.st = ER.PERM\n            why = 'gate'", "         case op.st = ER.PERM\n            why = 'cant'")),
    ("a locked file is read as an open one (the stop of the IDE)", "P3", sub("osf", "   if lk.user then\n      why = 'locked'\n      return\n   end\n", "")),
    ("the LOCKED clause sets nothing", "P3", sub("osf", "   end locked\n      lk.user = 1", "   end locked\n      lk.user = 0")),
    ("MAXRLOCK stops the IDE again (no ON ERROR)", "P3", sub("osf", "   openseq path to f on error\n      op.st = status()\n      if not(unassigned(f)) then close f\n      why = 'cant'\n      info<6> = op.st\n      return\n   end locked",
                                                         "   openseq path to f locked\n      lk.user = 1\n   end")),
    ("the second look keeps the buffer", "P7b", sub("osf", "      if not(fileinfo(f, FL$READONLY)) then writeblk '' to f else null", "      null")),
    ("a replaced file is saved into", "P7b", sub("osf", "         if (st.f<7> + 0) = 0 then why = 'gone'", "         null")),
    ("the write is not read back", "P7", sub("osf", "   if len(raw) # len(data) or raw # data then", "   if 0 then")),
    ("a mark byte is allowed in a path", "P9", sub("osf", "   for j = 248 to 255                      ;* and SD's marks", "   for j = 249 to 255                      ;* and SD's marks")),
    ("a device is read", "P4", sub("osf", "   if (fileinfo(f, FL$SEQTYPE) + 0) # 0 then\n      close f\n      why = 'special'\n      return\n   end\n", "")),
    ("a failed read keeps the file open", "P4", sub("osf", "   gosub read.file\n   if why # '' then\n      close f\n      return\n   end\n   info<3> = ro", "   gosub read.file\n   if why # '' then\n      return\n   end\n   info<3> = ro")),
    ("the size cap is gone", "P5", sub("osf", "   if fsize > OSF.MAX then", "   if 0 then")),
    ("a short read is a text", "P5", sub("osf", "   if len(raw) # fsize then why = 'io'", "   null")),
    ("a NUL is text", "P6", sub("osf", "   nope = char(0) ", "   nope = '' ")),
    ("byte 248 is text", "P6", sub("osf", "for j = 248 to 255", "for j = 249 to 255")),
    ("a lone CR makes the file CR LF", "P6", sub("osf", "count(raw, cr.c) = n.lf and count(raw, cr.c : lf.c) = n.lf", "count(raw, cr.c : lf.c) = n.lf")),
    ("a read-only file is written", "P7", sub("osf", "   if fileinfo(f, FL$READONLY) then\n      why = 'ro'", "   if 0 then\n      why = 'ro'")),
    ("the save does not go to the start", "P7", sub("osf", "   seek f, 0, 0 else why = 'io'\n   if why # '' then\n      info<6> = status()\n      return\n   end\n   writeblk", "   writeblk")),
    ("the marks are written", "P7", sub("osf", "   if convert(nope, '', flat) # flat then", "   if 0 then")),
    ("the save has no size cap", "P7", sub("osf", "   if len(data) > OSF.MAX then", "   if 0 then")),
    ("ER_PERM is another number", "P8", sub("osf", "ER.PERM = 3035", "ER.PERM = 3034")),
    ("the cap is 4 MB", "P8", sub("osf", "OSF.MAX = 2097152", "OSF.MAX = 4194304")),
    ("the message says 4 MB", "P8", sub("m12737", "2 MB", "4 MB")),
    ("a .. component is taken", "P9", sub("osf", "index(path, '/../', 1) or ", "")),
    ("a relative path is taken", "P9", sub("osf", "path[1, 1] # '/' or ", "")),
    ("a control character is taken", "P9", sub("osf", "or convert(ctl, '', path) # path then", "then")),
    ("the IDE opens a file itself", "P10", sub("ide", "   call !ide_osfile('open', op.path, op.f, op.text, op.info, op.why)", "   openseqp op.path to op.f else null\n   call !ide_osfile('open', op.path, op.f, op.text, op.info, op.why)")),
    ("a call loses an argument", "P11", sub("ide", "call !ide_osfile('reread', sv.id, tfv(sv.slot), sp.text, sp.info, sp.why)", "call !ide_osfile('reread', sv.id, tfv(sv.slot), sp.text, sp.info)")),
    ("the IDE does not ask the gate for its own message", "P12", sub("ide", "   if not(kernel(K$PATH.OK, op.path)) then", "   if 0 then")),
    ("the tab does not close the call's copy", "P12", sub("ide", "   close op.f ", "   null ")),
    ("an open tab is opened again", "P12", sub("ide", "   gosub tab.find\n   if tf.p then\n      new.cb = tf.p\n      if new.cb # cb then gosub switch.to\n      return\n   end\n   if not(kernel(K$PATH.OK",
                                                    "   if not(kernel(K$PATH.OK")),
    ("the tab is a record's", "P12b", sub("ide", "   ts.kind = 'path'", "   ts.kind = 'source'")),
    ("a tab never loses an old flag", "P13", sub("ide", "   k = 'z' : uid\n   bx{k} = 0 ", "   k = 'z' : uid\n   null ")),
    ("a refusal has no message", "P13b", sub("ide", "      case op.why = 'locked'\n         msg = sysmsg(12736, op.path)", "      case op.why = 'locked'\n         msg = ''")),
    ("a path tab is written as a record", "P14", sub("ide", "   if sv.kind = 'path' then\n      gosub save.path ", "   if 0 then\n      gosub save.path ")),
    ("the file is not read again", "P14b", sub("ide", "   call !ide_osfile('reread', sv.id, tfv(sv.slot), sp.text, sp.info, sp.why)\n   if sp.why = 'gone' then",
                                                 "   sp.text = sv.saved\n   sp.info = sv.pinfo\n   sp.why = ''\n   if sp.why = 'gone' then")),
    ("a removed or replaced file is saved into", "P14b", sub("ide", "   if sp.why = 'gone' then", "   if 0 then")),
    ("the texts are compared as numbers", "P14b", sub("ide", "(sp.text : '|') = (sv.saved : '|')", "sp.text = sv.saved")),
    ("the baseline is what was typed, not what the disk gives", "P14b", sub("ide", "         k = 'p' : u\n         bx{k} = (sp.winfo<1> + 0) : @fm : (sp.winfo<2> + 0)\n", "")),
    ("TRIM squeezes the blanks in a path", "P22", sub("ide", "   op.path = trimf(trimb(op.path))", "   op.path = trim(op.path)")),
    ("a one-line 1.0 made 1 is no change", "P22", sub("ide", "dirty = ((d1 : '|') # (d2 : '|'))", "dirty = (d1 # d2)")),
    ("the form made again forgets a read-only file", "P22", sub("ide", "      k = 'z' : u\n      if bx{k} then ed.ro = 1", "      k = 'z' : u\n      if 0 then ed.ro = 1")),
    ("Overwrite is the default", "P14b", sub("ide", "buttons 'Overwrite,Cancel' default 2 returning b else b = 0\n      if b # 1 then return\n   end\n   sp.winfo", "buttons 'Overwrite,Cancel' default 1 returning b else b = 0\n      if b # 1 then return\n   end\n   sp.winfo")),
    ("a change of line ends is not a change", "P14b", sub("ide", " and sp.info<1> + 0 = sv.pinfo<1> + 0 and sp.info<2> + 0 = sv.pinfo<2> + 0", "")),
    ("a failed write is said saved", "P14c", sub("ide", "      case 1\n         rf.text = sysmsg(12743, sv.name, sv.id, sp.winfo<6>)", "      case 1\n         sv.ok = @true\n         rf.text = sysmsg(12743, sv.name, sv.id, sp.winfo<6>)")),
    ("a read-only file is saved", "P15", sub("ide", "   ro.k = 'z' : bu<ro.i>\n   if bx{ro.k} then\n      ro.ok = @false", "   ro.k = 'z' : bu<ro.i>\n   if 0 then\n      ro.ok = @false")),
    ("the editor is writable for it", "P15", sub("ide", "      k = 'z' : u\n      if bx{k} then ro = 1", "      k = 'z' : u\n      if 0 then ro = 1")),
    ("the status line says nothing", "P15", sub("ide", "      if bx{k} then t := '  ' : sysmsg(12741)", "      if 0 then t := '  ' : sysmsg(12741)")),
    ("Close releases a path as a record id", "P16", sub("ide", "         close tfv(tu.s) ", "         release tfv(tu.s), bi<tu.i> ")),
    ("a program run gives the lock another name", "P16", sub("ide", "      if bx{rl.k2} = 'path' then rl.s = 0", "      null")),
    ("a recovery copy is kept of a file", "P16", sub("ide", "      if bx{rk.pk} = 'path' then continue", "      null")),
    ("a file is compiled", "P17", sub("ide", "   gosub path.not.for                   ;* 28 Oct 26 (stage E): an operating system file is not a program\n   if pa.no then return\n", "")),
    ("a file is handed to SED", "P17", sub("ide", "   gosub path.not.for                   ;* 28 Oct 26 (stage E): SED opens records, and none of the operating system's files since S.87\n   if pa.no then return\n", "")),
    ("a file is edited as fields", "P17", sub("ide", "   gosub path.not.for\n   pa.allow = ''\n   if pa.no then return\n", "   pa.allow = ''\n   pa.no = @false\n")),
    ("a file is saved as a record", "P17", sub("ide", "   gosub path.not.for                   ;* 28 Oct 26 (stage E): Save as would make the tab another record; Write a copy keeps the text\n   if pa.no then return\n", "")),
    ("Write a copy is refused for a file (no way out of a failed save)", "P17", sub("ide", "   if not(na.ok) then return\n   * 28 Oct 26 (stage E, review finding 4): Write a copy WORKS",
                                                                                   "   if not(na.ok) then return\n   gosub path.not.for\n   if pa.no then return\n   * 28 Oct 26 (stage E, review finding 4): Write a copy WORKS")),
    ("a file has an include", "P17", sub("ide", "   gosub path.not.for                   ;* 28 Oct 26 (stage E): a $include names a record of the account's files\n   if pa.no then return\n", "")),
    ("path.not.for lets a file through", "P17", sub("ide", "   if bn<cb> # 'path:' then return", "   if 0 then return")),
    ("a form starts from path:", "P17b", sub("ide", "   if df = 'path:' then df = ''", "   null")),
    ("the name form takes path: after the id", "P18", sub("ide_name", "      case ff[1, 5] = 'path:'", "      case ii # '' and ff[1, 5] = 'path:'")),
    ("the name form folds the path", "P18", sub("ide_name", "         op.path = trimf(trimb(pw[6, 9999]))", "         op.path = trimf(trimb(ff[6, 9999]))")),
    ("the name form squeezes the blanks in a path", "P22", sub("ide_name", "         op.path = trimf(trimb(pw[6, 9999]))", "         op.path = trim(pw[6, 9999])")),
    ("a creating mode skips the OS gate", "P18", sub("ide_name", "            case not(kernel(K$PATH.OK, op.path))\n               msg = sysmsg(12185, @who)\n", "")),
    ("a creating mode skips the edit gates", "P18", sub("ide_name", "            case not(kernel(K$EDIT.OS.OK, op.path))\n", "            case 0\n")),
    ("Open asks a kernel key", "P18", sub("ide_name", "            case mode = 'open'\n               file = 'path:'", "            case mode = 'open' and kernel(K$PATH.OK, op.path)\n               file = 'path:'")),
    ("message 12732 is back in the name form", "P21", sub("ide_name", "            case op.why # ''\n               msg = sysmsg(12733, op.path)", "            case op.why # ''\n               msg = sysmsg(12732)")),
    ("a create is not the second openseq of the helper", "P2", sub("osf", "   openseq path creating to f on error", "   openseq path creating shared to f on error")),
    ("the exclusive create has no ER_EXISTS number", "P8", sub("osf", "ER.EXISTS = 6032", "ER.EXISTS = 6033")),
    ("make.data is skipped by a save", "P7", sub("osf", "   gosub make.data\n   if why # '' then return\n   gosub put.data\n   return", "   gosub put.data\n   return")),
    ("the tab is not made by path.tab.make", "P12", sub("ide", "   tused<op.s> = 1\n   gosub path.tab.make\n   return", "   tused<op.s> = 1\n   return")),
    ("the name form opens the file", "P18", sub("ide_name", "               file = 'path:'\n", "               open op.path to fv else null\n               file = 'path:'\n")),
    ("the command line folds the path", "P19", sub("ide", "      path0 = trimf(trimb(rest0[6, 9999]))", "      path0 = downcase(trimf(trimb(rest0[6, 9999])))")),
    ("the command line squeezes the blanks in a path", "P22", sub("ide", "      path0 = trimf(trimb(rest0[6, 9999]))", "      path0 = trim(rest0[6, 9999])")),
    ("the bare start's copies are offered", "P19", sub("ide", " and path0 = '' then gosub rc.untitled", " then gosub rc.untitled")),
    ("Open folds the path", "P20", sub("ide", "      op.path = op.id ", "      op.path = downcase(op.id) ")),
    ("the tab strip says nothing", "P20", sub("ide", "      if bn<i> = 'path:' then labels<1, i> = 'os ' :", "      if 0 then labels<1, i> = 'os ' :")),
    ("a message is empty", "P21", sub("m12740", "\n", "")),
    ("the help forgets path:", "P21", sub("m12219", "path:/full/name there opens an operating system file", "")),
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
    print("test-idepath-units: tree %s" % SD64)
    if not src["ide"] or not src["osf"]:
        print("test-idepath-units: CANNOT RUN - gpl.bp/ide or gpl.bp/ide_osfile is not there")
        return 2
    rows = checks(src)
    bad = report(rows)
    print("\ntest-idepath-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(src) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
