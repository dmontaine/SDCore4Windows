#!/usr/bin/env python3
"""test-ideos-units.py - the IDE MAKES operating system files (the editor merge's stage E2, 30 Oct 2026), read off the source as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-ideos-units.py
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-ideos-units.py --selftest
  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-ideos-units.py --selftest --from=N      (only the mutants from number N on; N is printed by --selftest)

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

START-HISTORY:
30 Oct 26 dm  New with stage E2.  WRITTEN, NOT RUN against a sandbox: the rows that would say a file appears with the right bytes and mode, or that a refusal leaves the tab alone,
              are sandbox-ide-os.py's (not written yet).  Every row here is an ordering or a shape in the source, with comments removed.
02 Nov 26 dm  S.88 A3 and A5 (the second Opus review of E2): O1 reads the create in its new place, O1e (the file is made after the SD lock is taken, so a LOCKED create leaves
              nothing), O16b (DIR()'s ER.PERM told apart: 12185 only when the account may not reach the directory, else 12604), message 12604; mutants from M_A35B.
END-HISTORY

WHAT IT HOLDS.  New, Save as, the first save of an untitled buffer, Write a copy and Export (and Import, the other way) take path:/full/name and make or read an operating system file.
THE DESIGN IS THE SAME AS STAGE E'S: the IDE is $internal and the kernel trusts a $internal program with an OPENSEQ by pathname, so EVERY touch of a file is in gpl.bp/ide_osfile, which is
NOT $internal - the kernel asks the account's OS gate and the edit gates for what it does.  What is new:

  KERNEL.  OPENSEQ ... CREATING of a name that is not there is O_CREAT | O_EXCL (op_seqio.c, DIO_NEW; a name taken since the stat, or a dangling link, is ER_EXISTS 6032); SHARED keeps
  open-or-create.  The file's mode is default_access minus the session's umask (dh_file.c passes default_access to open(); no literal mode).  DIR() tells a file from a directory with
  S_ISREG / S_ISDIR (a socket was a file and a block device a directory).
  HELPER.  'create': the name is checked and the TEXT is checked (bytes, size) BEFORE the OPENSEQ, so a refusal touches nothing; the OPENSEQ ... CREATING has ON ERROR and LOCKED (the flag
  tested AFTER the statement); an existing EMPTY plain file is filled, a file with content is closed and never written, a device or read-only file is closed; the write is put.data's, the
  same as 'save', and is last.  'list' holds the IDE's only DIR().
  IDE.  The name form asks K$PATH.OK and then K$EDIT.OS.OK for every mode that makes a file, before it sets file, id or res.  A file is made BEFORE anything else changes (os.slot, os.create,
  and only then the tab, the record's lock and its recovery copy); path.tab.make is the one place a tab for a file is made; the tree has an 'Operating system files' node only when
  K$PATH.OK '/' is true, lists a directory only on Return, and opens a file in a tab; Import reads the text of a tab that holds the file, else opens and closes through the helper.

***IT RUNS NOTHING, SO IT CANNOT SAY THAT A GATE REFUSES OR THAT A BYTE SURVIVES***: that is the sandbox suite (not written).  --selftest breaks each property the way an edit plausibly
would and requires a row to notice.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
MSG = os.path.join(SDSYS, "messages")
SRC = os.path.join(SD64, "gplsrc")
NEWMSG = {12751: "tree.os", 12752: "os.load", 12753: "os.load", 12754: "os.create", 12767: "os.create", 12768: "os.create", 12769: "os.create", 12770: "os.create",
          15996: "os.create", 15997: "os.create", 12604: "os.load"}
DELETED = (12732, 12563)

_miss = []


def strip(src):
    """BASIC without comment lines and trailing ;* comments"""
    out = []
    for ln in src.split("\n"):
        if ln.lstrip().startswith("*"):
            continue
        out.append(re.sub(r"\s*;\*.*$", "", ln))
    return "\n".join(out)


def cstrip(src):
    """C without comments (a comment becomes one blank)"""
    src = re.sub(r"/\*.*?\*/", " ", src, flags=re.S)
    return re.sub(r"//[^\n]*", " ", src)


def norm(s):
    return re.sub(r"\s+", " ", s).strip()


def labels(text):
    """every internal subroutine of a stripped BASIC program: name -> body up to the next label"""
    ms = list(re.finditer(r"^([a-z][a-z0-9.]*):[ \t]*$", text, re.M))
    out = {}
    for i, m in enumerate(ms):
        out[m.group(1)] = text[m.end(): ms[i + 1].start() if i + 1 < len(ms) else len(text)]
    return out


def ordered(text, *parts):
    """true when the parts occur in the text in this order; the first part not found is kept for the row's detail"""
    pos = -1
    for p in parts:
        i = text.find(p, pos + 1)
        if i < 0:
            _miss.append(p)
            return False
        pos = i
    return True


def between(text, a, b):
    i = text.find(a)
    if i < 0:
        return ""
    j = text.find(b, i + len(a))
    return text[i: j if j >= 0 else len(text)]


def callers(lab, name):
    """the labels that GOSUB `name`"""
    pat = re.compile(r"gosub %s(?![\w.])" % re.escape(name))
    return sorted(n for n, body in lab.items() if pat.search(body))


def split_args(s):
    out, depth, quote, cur = [], 0, "", ""
    for ch in s:
        if quote:
            cur += ch
            if ch == quote:
                quote = ""
        elif ch in "'\"":
            quote = ch
            cur += ch
        elif ch in "(<":
            depth += 1
            cur += ch
        elif ch in ")>":
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
    src = {"ide": read(os.path.join(GPL, "ide")), "inm": read(os.path.join(GPL, "ide_name")), "osf": read(os.path.join(GPL, "ide_osfile")),
           "seqio": read(os.path.join(SRC, "op_seqio.c")), "dio4": read(os.path.join(SRC, "op_dio4.c")), "dhfile": read(os.path.join(SRC, "dh_file.c")),
           "sdh": read(os.path.join(SRC, "sd.h"))}
    for n in list(NEWMSG) + list(DELETED) + [12219, 12744, 12207]:
        src["m%d" % n] = read(os.path.join(MSG, str(n)))
    allbp = []
    try:
        for fn in sorted(os.listdir(GPL)):
            p = os.path.join(GPL, fn)
            if os.path.isfile(p):
                allbp.append(read(p))
    except OSError:
        pass
    src["allbp"] = "\n".join(allbp)
    return src


FORBID_TAB = re.compile(r"\b(nbuf|tfv|tused|uid)\b|\b(bn|bi|bu)<|bx\{|gosub (tab|rc|stash|drop|load|path|switch)\.?")


def checks(src):
    rows = []

    def ck(i, what, ok, detail=""):
        det = detail
        if not ok and not det and _miss:
            det = "not found, in this order: " + repr(_miss[-1])
        del _miss[:]
        rows.append((i, what, bool(ok), det))

    ide = strip(src["ide"])
    inm = strip(src["inm"])
    osf = strip(src["osf"])
    LI = labels(ide)
    LO = labels(osf)
    ta = labels(inm).get("try.accept", "")
    need_i = ("open.path", "path.tab.make", "path.refusal", "os.create", "os.slot", "os.new", "os.convert", "copy.to.os", "tree.nodes", "tree.os", "os.find", "os.load", "os.collapse",
              "os.refresh", "do.act", "save.one", "name.untitled", "do.saveas", "do.new", "do.writeas", "write.copy", "do.export", "do.import")
    need_o = ("check.name", "open.file", "write.file", "make.data", "put.data", "create.file", "list.dir")
    cs = cstrip(src["seqio"])
    nb = norm(cs)
    dh = cstrip(src["dhfile"])
    d4 = cstrip(src["dio4"])
    ck("O0", "NULL CASE: the IDE, the name form, the helper and the three C files were read and every routine this check reads is there (a check on nothing would pass)",
       len(ide) > 60000 and len(inm) > 3000 and len(osf) > 3000 and len(cs) > 5000 and len(dh) > 5000 and len(d4) > 5000 and all(len(LI.get(n, "")) > 20 for n in need_i)
       and all(len(LO.get(n, "")) > 20 for n in need_o) and len(ta) > 100 and len(src["allbp"]) > 1000000,
       repr(sorted([n for n in need_i if len(LI.get(n, "")) <= 20] + [n for n in need_o if len(LO.get(n, "")) <= 20])))

    # ---- the kernel ---------------------------------------------------------------------------------------------------------------------------------------------------
    # 02 Nov 26 (S.88 A3): the CREATING branch only sets create_after_lock; the create itself is the `if (create_after_lock) {` block after the lock
    m = re.search(r"else if \(op_flags & 0x400\) \{(.*?)\} else \{", nb)
    m2 = re.search(r"if \(create_after_lock\) \{(.*?)\} \}", nb)
    br = m2.group(1) if (m and m.group(1).strip() == "create_after_lock = TRUE;" and m2) else ""
    ck("O1", "op_seqio.c: OPENSEQ ... CREATING of a name that is not there is EXCLUSIVE - dio_open(.., SHARED ? DIO_OVERWRITE : DIO_NEW) - and the failure is ER_EXISTS only when errno is EEXIST AND the "
       "call is not SHARED (SHARED keeps open-or-create), read straight after the open (nothing between can change errno); the 'may not change here' refusal (ER_PERM) comes before it; an "
       "existing file is opened WITHOUT truncating (no DIO_REPLACE); DIO_NEW is used nowhere else in the file",
       bool(m) and ordered(br, "fu = dio_open(fullpathname, (op_flags & 0x800) ? DIO_OVERWRITE : DIO_NEW);", "if (!ValidFileHandle(fu)) {",
                           "process.status = (!(op_flags & 0x800) && errno == EEXIST) ? ER_EXISTS : ER_FNF;", "goto exit_op_openseq;")
       and "DIO_NEW); if (!ValidFileHandle(fu)) { process.status = (!(op_flags & 0x800) && errno == EEXIST)" in br
       and ordered(nb, "else if ((op_flags & 0x400) && edit_blocked)", "process.status = ER_PERM;", "else if (op_flags & 0x400)")
       and "(read_only) ? DIO_READ : DIO_OVERWRITE" in nb and "DIO_REPLACE" not in nb and nb.count("DIO_NEW") == 1, "")
    ck("O1c", "op_seqio.c: the name GIVEN is looked at with lstat() BEFORE fullpath() resolves it (fullpath follows a link at the end of the name, even a dangling one, and the OS gate's realpath() "
       "takes a dangling link for a name not made yet inside the account); a CREATING (SHARED included) of a link to nothing is refused ER_EXISTS before any file is made, and after the 'may not "
       "change here' refusal",
       ordered(nb, "lstat(file_name, &leaf_stat_buf) == 0 && S_ISLNK(leaf_stat_buf.st_mode)", "leaf_is_link = TRUE;", "fullpath(fullpathname, file_name);")
       and ordered(nb, "else if ((op_flags & 0x400) && edit_blocked)", "else if ((op_flags & 0x400) && leaf_is_link)", "process.status = ER_EXISTS;", "else if (op_flags & 0x400)")
       and nb.count("leaf_is_link") == 5, repr(nb.count("leaf_is_link")))        # 5 since S.88 A1: the declaration, the two places that set it (pathname form, file,record form), the CREATING refusal, the read-only mark
    ck("O1d", "op_seqio.c (S.88 A1, the second Opus review): the OPENSEQ file,record form looks at the raw record name with lstat() BEFORE fullpath() resolves it, so a CREATING of a record that is a "
       "link to nothing is refused as in the pathname form; an OPENSEQ that found a link to nothing and opened nothing marks the file variable read only (the first WRITESEQ is refused: fullpath() "
       "has already replaced the name by the link's target, so the create cannot tell any more); the create a WRITESEQ makes on a first write never follows a link at the end of the name "
       "(DIO_OVERWRITE_NOFOLLOW = O_RDWR | O_CREAT | O_NOFOLLOW)",
       ordered(nb, "lstat(pathname, &leaf_stat_buf) == 0 && S_ISLNK(leaf_stat_buf.st_mode)", "leaf_is_link = TRUE;", "fullpath(fullpathname, pathname);")
       and ordered(nb, "if (leaf_is_link && !(flags & SQ_PORT) && !ValidFileHandle(fu))", "fvar->flags |= FV_RDONLY;")
       and "fu = dio_open(sq_file->pathname, DIO_OVERWRITE_NOFOLLOW);" in nb
       and re.search(r"case DIO_OVERWRITE_NOFOLLOW:.*?O_RDWR \| O_CREAT \| O_NOFOLLOW", dh, re.S) is not None
       and "DIO_OVERWRITE_NOFOLLOW" in src["sdh"], repr((nb.count("DIO_OVERWRITE_NOFOLLOW"), "DIO_OVERWRITE_NOFOLLOW" in src.get("sdh", ""))))
    ck("O1e", "op_seqio.c (S.88 A3, 02 Nov 26): CREATING of a name that is not there makes the file only AFTER the SD lock on it is taken - the branch sets create_after_lock and opens nothing, "
       "lock_record() comes next, a name another session holds takes the LOCKED clause (or waits: pc -= 2) with nothing made, and the create is the block after the lock switch and before the "
       "SQ_FILE is set up; a failed create goes to the exit, which gives the lock back; the lock-conflict branch marks the handle it closed invalid (the exit must not close it again)",
       ordered(nb, "bool create_after_lock = FALSE;", "else if (op_flags & 0x400) { create_after_lock = TRUE; } else {", "blocking_user = lock_record(fvar, unmapped_name",
               "default: if (ValidFileHandle(fu)) CloseFile(fu); fu = INVALID_FILE_HANDLE;", "process.status = ER_LCK;", "pc -= 2;", "Sleep(250); return; } }",
               "if (create_after_lock) { fu = dio_open(fullpathname, (op_flags & 0x800) ? DIO_OVERWRITE : DIO_NEW); if (!ValidFileHandle(fu)) {",
               "goto exit_op_openseq; } }", "sq_file = (SQ_FILE*)k_alloc(68", "exit_op_openseq:", "if ((fvar != NULL) && record_locked) { (void)unlock_record(")
       and nb.count("create_after_lock") == 3 and nb.count("dio_open(fullpathname, (op_flags & 0x800)") == 1, repr(nb.count("create_after_lock")))
    dio = re.search(r"OSFILE dio_open\(char\* fn, int mode\) \{(.*?)\n\}\n", dh, re.S)
    dio = dio.group(1) if dio else ""
    nbd = norm(dio)
    ck("O1b", "dh_file.c dio_open: DIO_NEW is O_RDWR | O_CREAT | O_EXCL, DIO_OVERWRITE has O_CREAT and no O_EXCL, and BOTH calls to open() pass default_access - the file's mode is that minus the session's "
       "umask, never a literal 0666 or 0644 (the sandbox suite must measure the mode, not assume one)",
       len(dio) > 300 and "case DIO_NEW: open_modes = O_RDWR | O_CREAT | O_EXCL | O_BINARY; break;" in nbd
       and "case DIO_OVERWRITE: open_modes = O_RDWR | O_CREAT | O_BINARY; break;" in nbd and nbd.count("OpenFile(fn, open_modes, default_access)") == 2
       and re.search(r"\b0[0-7]{3}\b", dio) is None, repr(nbd[:80]))
    od = re.search(r"void op_dir\(\) \{(.*?)\n\}\n", d4, re.S)
    od = od.group(1) if od else ""
    nod = norm(od)
    ck("O2", "op_dio4.c op_dir (the function DIR() runs): a file is S_ISREG and a directory S_ISDIR (in that order, anything else skipped), and st_mode is never tested there with `& S_IFREG` or `& S_IFDIR` "
       "(those bits are also set for a socket and for a block device).  ONLY op_dir: dir_select() of the same file (SELECT.DIR) still tests `& S_IFREG` - an open problem, not this stage's",
       len(od) > 500 and "if (S_ISREG(statbuf.st_mode)) mode = 'F'; else if (S_ISDIR(statbuf.st_mode)) mode = 'D'; else continue;" in nod and not re.search(r"&\s*S_IF(REG|DIR)", od)
       and "stat(name, &statbuf)" in nod, repr(re.findall(r"&\s*S_IF\w+", od)))

    # ---- the helper: 'create' -----------------------------------------------------------------------------------------------------------------------------------------
    cf = LO.get("create.file", "")
    ck("O3a", "create.file: the name is checked and the TEXT is checked (make.data: bytes, size) BEFORE the OPENSEQ - a refusal touches nothing; the OPENSEQ is `creating` with ON ERROR (it returns itself) and "
       "LOCKED, the flag tested AFTER the statement; ON ERROR and the ELSE branch each CLOSE the variable when it is assigned; ON ERROR says cantmade (the file may have been made, empty, "
       "before the error: S.88 A3); the ELSE says exists (ER_EXISTS), gate, dir or cant with the status (the helper is not $internal and has no kernel(): the IDE's os.create tells an edit gate from "
       "the OS gate, row O7)",
       ordered(cf, "gosub check.name", "if why # '' then return", "gosub make.data", "if why # '' then return", "lk.user = 0", "openseq path creating to f on error", "op.st = status()",
               "if not(unassigned(f)) then close f", "why = 'cantmade'", "info<6> = op.st", "return", "end locked", "lk.user = 1", "end then", "null", "end else", "op.st = status()",
               "if not(unassigned(f)) then close f", "case op.st = ER.EXISTS", "why = 'exists'", "case op.st = ER.PERM", "why = 'gate'", "case op.st = ER.NSEQ", "why = 'dir'", "case 1",
               "why = 'cant'", "info<6> = op.st", "return", "if lk.user then", "why = 'locked'", "return")
       and cf.count("if not(unassigned(f)) then close f") == 2 and cf.count("openseq") == 1 and "case lk.user" not in cf
       and re.findall(r"^[ \t]*openseq\b.*$", cf, re.M) == ["   openseq path creating to f on error"], repr(re.findall(r"^[ \t]*openseq\b.*$", cf, re.M)))
    ck("O3b", "create.file, after the open: a device, pipe or port is closed (special); a read-only variable is closed (ro); the end is asked (SEEK to the end, FL$SEQPOS) and a file with content is 'exists': "
       "closed and NEVER written; only then put.data, which is the last thing done; a failed put.data closes the file and keeps the status; success leaves the file OPEN (the SD lock is the caller's) "
       "and info<3> is 0; create.file writes nothing itself (no WRITEBLK, WEOFSEQ, or SEEK to the start)",
       ordered(cf, "if lk.user then", "if (fileinfo(f, FL$SEQTYPE) + 0) # 0 then", "close f", "why = 'special'", "return", "if fileinfo(f, FL$READONLY) then", "close f", "why = 'ro'", "return",
               "seek f, 0, 2 else why = 'io'", "if (fileinfo(f, FL$SEQPOS) + 0) # 0 then why = 'exists'", "if why # '' then", "close f", "return", "gosub put.data", "if why # '' then",
               "info<6> = status()", "close f", "return", "info<3> = 0", "return")
       and not re.search(r"\b(writeblk|weofseq|writeseq|write)\b", cf) and "seek f, 0, 0" not in cf and cf.count("close f") == 6 and "close" not in cf[cf.rfind("info<3> = 0"):]
       and "gosub" not in cf[cf.rfind("gosub put.data") + 15:], "")
    ck("O4", "the helper's operations: check, open, reread, save, create, list each have their own case and routine and an unknown op is 'op'; make.data and put.data are shared by write.file and create.file "
       "ONLY (so a save and a create write the same way and cannot differ); put.data is not reached from anywhere else",
       ordered(osf, "case op = 'check'", "gosub check.name", "case op = 'open'", "gosub open.file", "case op = 'reread'", "rr.again = 1", "gosub read.file", "case op = 'save'", "gosub write.file",
               "case op = 'create'", "gosub create.file", "case op = 'list'", "gosub list.dir", "case 1", "why = 'op'")
       and callers(LO, "put.data") == ["create.file", "write.file"] and callers(LO, "make.data") == ["create.file", "write.file"] and callers(LO, "create.file") == []
       and osf.count("gosub create.file") == 1 and osf.count("gosub list.dir") == 1 and osf.count("gosub put.data") == 2 and osf.count("gosub make.data") == 2,
       repr((callers(LO, "put.data"), callers(LO, "make.data"))))

    # ---- the helper: 'list' -------------------------------------------------------------------------------------------------------------------------------------------
    ld = LO.get("list.dir", "")
    ck("O5", "list.dir: a path other than '/' is checked first; DIR() is asked and its STATUS read at once - the gate (ER_PERM) is 'gate', a directory not there 'none', anything else 'cant' with the status; an "
       "entry is left out AND counted when its name is empty, holds a control byte or one of SD's marks, is . or .., or holds a slash, and the entries past OSF.LIST are left out and counted; the "
       "directories and the files are each kept in the order of the names (LOCATE ... BY AL) and the output is the directories first, then the files, each as name, value mark, D or F, value mark, "
       "size; info<4> is how many kept, info<5> how many left out; nothing is opened",
       ordered(ld, "if path # '/' then", "gosub check.name", "if why # '' then return", "ld.raw = dir(path)", "ld.st = status()", "case ld.st = ER.PERM", "why = 'gate'", "return",
               "case ld.st = 0 or ld.st = ER.FNF", "why = 'none'", "case 1", "why = 'cant'", "info<6> = ld.st", "ld.n = dcount(ld.raw, @fm)", "ld.name = ld.e<1, 1>", "ld.type = ld.e<1, 2>",
               "if ld.name = ''", "convert(ctl, '', ld.name) # ld.name", "ld.name = '.'", "ld.name = '..'", "index(ld.name, '/', 1)", "ld.skip += 1", "if ld.kept >= OSF.LIST then", "ld.skip += 1",
               "ld.kept += 1", "if ld.type = 'D' then", "locate ld.name in ld.dnames<1> by 'AL' setting ld.pos else null", "ins ld.name before ld.dnames<ld.pos>",
               "locate ld.name in ld.fnames<1> by 'AL' setting ld.pos else null", "ins ld.name before ld.fnames<ld.pos>", "ins ld.e<1, 3> before ld.fsizes<ld.pos>",
               "text<-1> = ld.dnames<ld.j> : @vm : 'D' : @vm : 0", "text<-1> = ld.fnames<ld.j> : @vm : 'F' : @vm : ld.fsizes<ld.j>", "info<4> = ld.kept", "info<5> = ld.skip")
       and re.search(r"^[ \t]*OSF\.LIST = 1000$", osf, re.M) is not None and "openseq" not in ld and "gosub put.data" not in ld, "")
    nd = len(re.findall(r"\bdir\(", osf))
    ck("O5b", "the helper's list.dir holds the ONLY DIR() of the IDE: one in ide_osfile, none in ide or ide_name (the kernel asks the account's OS gate for it; the IDE itself asks nothing of the disk)",
       nd == 1 and re.search(r"\bdir\(", ld) is not None and re.search(r"\bdir\(", ide + inm) is None, repr((nd, len(re.findall(r"\bdir\(", ide + inm)))))

    # ---- the name form ------------------------------------------------------------------------------------------------------------------------------------------------
    br2 = ta[ta.find("case ff[1, 5] = 'path:'"): ta.find("case ii = ''")]
    pre = br2[: br2.find("case not(kernel(K$PATH.OK")]
    post = br2[br2.find("case not(kernel(K$EDIT.OS.OK"):]
    ck("O6", "ide_name, path:/full/name in EVERY mode: the spelling is checked first (!ide_osfile 'check'); Open returns the name with no kernel key asked; every other mode asks K$PATH.OK and then "
       "K$EDIT.OS.OK of the name (each with its own message) BEFORE file, id or res is set, so a refusal is said in the form and the form stays; only the last case (all gates passed) sets them; "
       "one of each key, both asked of op.path, the same string the file is made with",
       ordered(br2, "call !ide_osfile('check', op.path", "case op.why # ''", "msg = sysmsg(12733, op.path)", "case mode = 'open'", "file = 'path:'", "id = op.path", "res = 'ok'",
               "case not(kernel(K$PATH.OK, op.path))", "msg = sysmsg(12185, @who)", "case not(kernel(K$EDIT.OS.OK, op.path))", "ek = kernel(K$EDIT.KIND, op.path)", "ep = op.path",
               "while ek = 0 and len(ep) > 1", "if ep # '' then ek = kernel(K$EDIT.KIND, ep)", "if ek = 0 then", "msg = sysmsg(12768, op.path, 3035)", "msg = edit_msg(ek)", "case 1",
               "file = 'path:'", "id = op.path", "res = 'ok'", "if res # 'ok' and focus = 2 then gosub swap.focus")
       and pre.count("res = 'ok'") == 1 and "kernel(" not in pre and br2.count("res = 'ok'") == 2 and br2.count("file = 'path:'") == 2 and br2.count("kernel(K$PATH.OK") == 1
       and br2.count("kernel(K$EDIT.OS.OK") == 1 and "res = 'ok'" in post and post.count("res = 'ok'") == 1 and "case mode # " not in br2, "")

    # ---- the IDE: making a file, and nothing else changes until it is made --------------------------------------------------------------------------------------------
    oc = LI.get("os.create", "")
    ck("O7", "os.create is the ONLY caller of !ide_osfile 'create' (five arguments after the op: path, file variable, text, info, why) and says each answer in its words - exists or ro 12767, dir or special "
       "12754, locked 15997, cantmade 15996, bytes or big 12770, cant 12768 with the status, name 12733, gate 12185, anything else (io) 12769; exists or ro, locked, cantmade and io are each in a "
       "BOX (S.88 9g and A3: the status line cut the sentence, and a file may be there); a refusal changes "
       "NO tab, lock, copy or buffer (os.create touches none of them)",
       ide.count("call !ide_osfile('create'") == 1 and ordered(oc, "call !ide_osfile('create', cr.path, cr.f, cr.text, cr.info, cr.why)", "case cr.why = ''", "null", "case cr.why = 'name'",
       "sysmsg(12733, cr.path)", "case cr.why = 'gate'", "if kernel(K$EDIT.OS.OK, cr.path) then", "sysmsg(12185, @who)", "end else", "sysmsg(12768, cr.path, 3035)",
       "case cr.why = 'exists' or cr.why = 'ro'", "rf.text = sysmsg(12767, cr.path)", "msg = rf.text", "gosub refuse.box",
       "case cr.why = 'dir' or cr.why = 'special'",
       "sysmsg(12754, cr.path)", "case cr.why = 'locked'", "rf.text = sysmsg(15997, cr.path)", "msg = rf.text", "gosub refuse.box", "case cr.why = 'cantmade'",
       "rf.text = sysmsg(15996, cr.path, cr.info<6>)", "msg = rf.text", "gosub refuse.box", "case cr.why = 'bytes' or cr.why = 'big'", "sysmsg(12770, cr.path)", "case cr.why = 'cant'",
       "sysmsg(12768, cr.path, cr.info<6>)", "case 1", "rf.text = sysmsg(12769, cr.path, cr.info<6>)", "msg = rf.text", "gosub refuse.box") and FORBID_TAB.search(oc) is None,
       repr(FORBID_TAB.findall(oc)[:3]))
    sl = LI.get("os.slot", "")
    ck("O8", "os.slot (before any file is made): the tab that already holds the name is refused with 12696, a free lock slot is found or 12695 is said, a slot is given only at the end; it calls no helper, "
       "opens nothing and takes no slot (tfv, tused)",
       ordered(sl, "cr.slot = 0", "tf.dict = ''", "tf.file = 'path:'", "tf.id = cr.path", "gosub tab.find", "if tf.p then", "msg = sysmsg(12696, 'path:', cr.path)", "return",
               "for cr.s = 1 to MAXLOCK", "if tused<cr.s> = '' then exit", "if cr.s > MAXLOCK then", "msg = sysmsg(12695)", "return", "cr.slot = cr.s", "return")
       and "!ide_osfile" not in sl and "openseq" not in sl and "tfv(" not in sl and "tused<cr.s> = 1" not in sl, "")
    on = LI.get("os.new", "")
    ck("O9", "New with a name of the operating system: the slot first, then an EMPTY file is made (os.create), a refusal returns with cr.why set (initially 'slot', so do.new does not focus a tab that was "
       "not made), and only then the file variable goes in its slot, the call's own copy is closed, the tab is made by path.tab.make and the directory in the tree is listed again",
       ordered(on, "cr.path = nm.id", "cr.why = 'slot'", "gosub os.slot", "if not(cr.slot) then return", "cr.text = ''", "cr.info = 0 : @fm : 0", "gosub os.create", "if cr.why # '' then return",
               "op.s = cr.slot", "op.f = cr.f", "op.path = cr.path", "op.text = cr.text", "op.info = cr.info", "tfv(op.s) = op.f", "close op.f", "tused<op.s> = 1", "gosub path.tab.make",
               "msg = sysmsg(12207, 'path:', op.path)", "os.fp = op.path", "gosub os.refresh", "return")
       and "nbuf" not in on and "bn<" not in on, "")
    cv = LI.get("os.convert", "")
    pre_cv = cv[: cv.find("gosub os.create")]
    ck("O10", "Save as / the first save of an untitled buffer with a name of the operating system: os.slot and os.create come BEFORE the tab lets go of anything - nothing before os.create assigns a tab "
       "field, takes a slot, drops the recovery copy or the record's lock - then the slot, the copy (rc.drop.tab), the lock (tab.unlock), the tab's file and kind (tab.state for THIS tab's uid, "
       "put back), the line ends, the baseline as the disk gives it back (the buffer keeps the typed text only when it differs), na.mark, the message, the editor if it shows this tab, the tree",
       ordered(cv, "oc.ok = @false", "cr.path = oc.path", "gosub os.slot", "if not(cr.slot) then return", "oc.u = bu<oc.i>", "k = 't' : oc.u", "cr.text = bx{k}", "cr.info = 0 : @fm : (cr.text # '')",
               "oc.sent = cr.text", "gosub os.create", "if cr.why # '' then return", "oc.s = cr.slot", "tfv(oc.s) = cr.f", "close cr.f", "tused<oc.s> = 1", "ri = oc.i", "gosub rc.drop.tab",
               "tu.i = oc.i", "gosub tab.unlock", "bn<oc.i> = 'path:'", "bi<oc.i> = oc.path", "uid = oc.u", "ts.kind = 'path'", "ts.dict = ''", "ts.slot = oc.s", "gosub tab.state", "uid = oc.uid",
               "k = 'm' : oc.u", "bx{k} = 0", "k = 'p' : oc.u", "bx{k} = (cr.info<1> + 0) : @fm : (cr.info<2> + 0)", "k = 's' : oc.u", "bx{k} = cr.text",
               "if (cr.text : '|') # (oc.sent : '|') then", "k = 't' : oc.u", "bx{k} = cr.text", "oc.ok = @true", "msg = sysmsg(12207, 'path:', oc.path)",
               "if oc.i = cb then gosub load.current", "os.fp = oc.path", "gosub os.refresh")
       and "oc.uid = uid" in cv and cv.find("oc.uid = uid") < cv.find("uid = oc.u\n") and re.search(r"bx\{[^}]*\}\s*=", pre_cv) is None
       and re.search(r"\b(tfv|tused)\b|\b(bn|bi)<|gosub (tab|rc)\.|\bri =", pre_cv) is None, "")
    ct = LI.get("copy.to.os", "")
    ck("O11", "Write a copy / Export with a name of the operating system: the text goes to a file that is made for it, the file is CLOSED at once (no lock is kept) and no tab is made; the message and the "
       "directory in the tree follow only a success; the routine touches no tab (no tfv, tused, nbuf, bn, bi, tab. or path.tab.make)",
       ordered(ct, "cr.path = wa.id", "cr.text = wa.text", "cr.info = 0 : @fm : (cr.text # '')", "gosub os.create", "if cr.why = '' then", "close cr.f", "msg = sysmsg(12207, 'path:', wa.id)",
               "os.fp = wa.id", "gosub os.refresh") and FORBID_TAB.search(ct) is None, repr(FORBID_TAB.findall(ct)[:3]))
    ptm = LI.get("path.tab.make", "")
    ck("O12", "who calls whom: path.tab.make (the one place a tab for a file is made: one `nbuf += 1`, one `bn<nbuf> = 'path:'`) is called by open.path and os.new only; os.create by os.new, os.convert and "
       "copy.to.os only; os.slot by os.new and os.convert; os.convert by do.saveas and name.untitled; os.new by do.new; copy.to.os by write.copy; os.refresh by the three that make a file",
       callers(LI, "path.tab.make") == ["open.path", "os.new"] and ptm.count("nbuf += 1") == 1 and ide.count("bn<nbuf> = 'path:'") == 1
       and "nbuf" not in LI.get("open.path", "") and "nbuf" not in LI.get("os.new", "")
       and callers(LI, "os.create") == ["copy.to.os", "os.convert", "os.new"] and callers(LI, "os.slot") == ["os.convert", "os.new"]
       and callers(LI, "os.convert") == ["do.saveas", "name.untitled"] and callers(LI, "os.new") == ["do.new"] and callers(LI, "copy.to.os") == ["write.copy"]
       and callers(LI, "os.refresh") == ["copy.to.os", "os.convert", "os.new"],
       repr((callers(LI, "path.tab.make"), callers(LI, "os.create"), callers(LI, "os.slot"), callers(LI, "os.convert"), callers(LI, "os.new"), callers(LI, "copy.to.os"), callers(LI, "os.refresh"))))
    dn, ds, wc, dw, dx = (LI.get(n, "") for n in ("do.new", "do.saveas", "write.copy", "do.writeas", "do.export"))
    ck("O13", "the commands send a path: name to the operating system BEFORE they would make a record: New (os.new, and focus only when a tab was made), Save as (os.convert, then return - the record's "
       "tab is not touched), Write a copy / Export (write.copy's first test; both ask the form in the 'copy' mode and refuse a name another tab holds, 12696, before they write)",
       ordered(dn, "call $ide_name('new', nm.file, nm.id, nm.res)", "if nm.res # 'ok' then return", "if nm.file = 'path:' then", "gosub os.new", "if nbuf > 0 and cr.why = '' then", "ft.id = 'ed'",
               "gosub focus.to", "gosub redraw.tabs", "return", "upcase(nm.id) = 'CREATING.SEQKEY'", "gosub add.new.record")
       and ordered(ds, "gosub path.not.for", "if pa.no then return", "gosub stash.current", "call $ide_name('saveas', sa.file, sa.id, sa.res)", "if sa.res # 'ok' then return",
                   "if sa.file = 'path:' then", "oc.i = cb", "oc.path = sa.id", "gosub os.convert", "return", "gosub tab.find", "gosub tab.unlock")
       and ordered(wc, "if wa.file = 'path:' then", "gosub copy.to.os", "return", "open wa.file to fv else")
       and ordered(dw, "call $ide_name('copy', wa.file, wa.id, wa.res)", "if wa.res # 'ok' then return", "tf.file = wa.file", "gosub tab.find", "if tf.p then", "sysmsg(12696, wa.file, wa.id)",
                   "return", "gosub write.copy")
       and ordered(dx, "call $ide_name('copy', wa.file, wa.id, wa.res)", "if wa.res # 'ok' then return", "tf.file = wa.file", "gosub tab.find", "if tf.p then", "sysmsg(12696, wa.file, wa.id)",
                   "return", "gosub write.copy"), "")
    so, nu = LI.get("save.one", ""), LI.get("name.untitled", "")
    ck("O14", "the first save of an untitled buffer: name.untitled sends a path: name to os.convert and reports sv.named / sv.osdone only when the file was made (a refusal returns with sv.named false, "
       "before any record is named); save.one returns at sv.osdone (the file is made with the text, so it has nothing more to write) and sv.osdone is set nowhere else",
       ordered(so, "gosub ro.check", "if bi<sv.i> = '' then", "sv.osdone = @false", "gosub name.untitled", "if not(sv.named) then return", "if sv.osdone then", "sv.ok = @true", "return", "u = bu<sv.i>")
       and ordered(nu, "call $ide_name(nm.mode, nm.file, nm.id, nm.res)", "if nm.res # 'ok' then return", "if nm.file = 'path:' then", "oc.i = sv.i", "oc.path = nm.id", "gosub os.convert",
                   "if oc.ok then", "sv.named = @true", "sv.osdone = @true", "end", "return", "tf.file = nm.file", "gosub tab.find", "bn<sv.i> = nm.file")
       and ide.count("sv.osdone = @true") == 1 and ide.count("sv.osdone = @false") == 1, "")

    # ---- the tree -------------------------------------------------------------------------------------------------------------------------------------------------------
    tn, to, ol, rf, da, oco = (LI.get(n, "") for n in ("tree.nodes", "tree.os", "os.load", "os.refresh", "do.act", "os.collapse"))
    seg = between(da, "case code[1, 2] = 'O:'", "case code[1, 2] = 'R:' or code[1, 2] = 'Q:'")
    ck("O15", "the tree has the 'Operating system files' node (message 12751, code O:/) only when os.on, which is K$PATH.OK '/' asked once at the start (one assignment); tree.os draws only what is already "
       "listed (it makes no call) - directories as O:<path> nodes, files as P:<path> nodes - and is called from tree.nodes alone, under `if os.on`",
       "if os.on then gosub tree.os" in tn and callers(LI, "tree.os") == ["tree.nodes"] and ide.count("os.on =") == 1 and "os.on = kernel(K$PATH.OK, '/') + 0" in ide
       and ordered(to, "nn += 1", "os.rootn = nn", "nodes<-1> = sysmsg(12751) : @sm : 1 : @sm : 'O:/'", "os.dir = '/'", "gosub os.find", "if not(os.q) then return", "os.c = 'O:' : os.pth",
                   "nodes<-1> = os.nm : '/' : @sm : os.lv : @sm : os.c", "os.c = 'P:' : os.pth", "nodes<-1> = os.nm : @sm : os.lv : @sm : os.c")
       and "call " not in to and "!ide_osfile" not in to, "")
    ck("O16", "a directory is listed only through os.load, which holds the ONLY call of !ide_osfile 'list' (five arguments after the op) and says a refusal in words (name 12733, gate 12185, none 12734, "
       "anything else 12752 with the status) and returns; entries left out are said (12753); do.act lists on the first Return on an O: node and takes it back, with everything listed under it, "
       "on the second (os.collapse deletes from the END of the list, a directory and what is under it only), and a P: node is opened by open.path with the path as the tree gave it (never folded)",
       ide.count("call !ide_osfile('list'") == 1 and "call !ide_osfile('list'" in ol and callers(LI, "os.load") == ["do.act", "os.refresh"] and callers(LI, "os.collapse") == ["do.act"]
       and ordered(ol, "os.ok = @false", "call !ide_osfile('list', os.dir, os.lf, os.lt, os.li, os.lw)", "if os.lw # '' then", "case os.lw = 'name'", "sysmsg(12733, os.dir)", "case os.lw = 'gate'",
                   "sysmsg(12185, @who)", "case os.lw = 'none'", "sysmsg(12734, os.dir)", "case 1", "sysmsg(12752, os.dir, os.li<6>)", "return", "os.ents<1, -1> = os.lt<os.j, 2> : os.lt<os.j, 1>",
                   "gosub os.find", "ofiles<-1> = os.dir", "orecs<os.q> = os.ents", "if os.li<5> + 0 then msg = sysmsg(12753, os.dir, os.li<5>)", "os.ok = @true")
       and ordered(seg, "case code[1, 2] = 'O:'", "os.dir = code[3, 9999]", "gosub os.find", "if os.q then", "gosub os.collapse", "end else", "gosub os.load", "cur.code = code", "gosub tree.apply",
                   "gosub redraw.tree", "case code[1, 2] = 'P:'", "op.path = code[3, 9999]", "cur.code = code", "gosub open.path", "if nbuf > 0 then", "ft.id = 'ed'", "gosub focus.to")
       and "downcase(" not in seg and ordered(da, "case focus.id = 'tree'", "case code[1, 2] = 'O:'", "case focus.id = 'err'")
       and ordered(oco, "for os.j = os.nf to 1 step -1", "os.pp = ofiles<os.j>", "os.pp = os.dir or os.dir = '/' or os.pp[1, len(os.dir) + 1] = os.dir : '/'", "del ofiles<os.j>", "del orecs<os.j>"), "")
    ck("O16b", "S.88 A5 (02 Nov 26): DIR() says ER.PERM both for the OS gate and for a directory the operating system will not open, so the helper's list gives the DIR()'s STATUS() and "
       "OS.ERROR() (taken straight after it) for 'gate', and os.load says 12185 (no OS access) only when the account may NOT reach the directory (K$PATH.OK of that directory), else 12604 "
       "with the operating system's error",
       ordered(LO.get("list.dir", ""), "ld.raw = dir(path)", "ld.st = status()", "ld.oserr = os.error()", "begin case", "case ld.st = ER.PERM", "why = 'gate'", "info<6> = ld.st",
               "info<7> = ld.oserr", "return")
       and ordered(ol, "case os.lw = 'gate'", "if kernel(K$PATH.OK, os.dir) then", "msg = sysmsg(12604, os.dir, os.li<7>)", "end else", "msg = sysmsg(12185, @who)", "end",
                   "case os.lw = 'none'"), "")
    ck("O17", "after a file is made the directory it is in is listed again, but only when the tree has the node (os.on) and lists that directory (os.find): then os.load, tree.apply, redraw.tree",
       ordered(rf, "if not(os.on) then return", "os.dir = '/'", "gosub os.find", "if os.q then", "gosub os.load", "gosub tree.apply", "gosub redraw.tree"), "")

    # ---- Import ----------------------------------------------------------------------------------------------------------------------------------------------------------
    di = LI.get("do.import", "")
    ck("O18", "Import with a name of the operating system: the text of a tab that holds the file is taken from the TAB (opening it again would give away its lock), any other file is opened and read "
       "through !ide_osfile 'open' (the account's gates), a refusal is said by path.refusal and returns, and the variable is closed again at once; the checks for marks and bytes 128 to 247 come after "
       "either way; nothing is created or written; a record's file is opened only in the other branch",
       ordered(di, "gosub ed.get", "if not(ed.ok) then return", "call $ide_name('open', im.file, im.id, im.res)", "if im.res # 'ok' then return", "if im.file = 'path:' then", "tf.dict = ''",
               "tf.file = 'path:'", "tf.id = im.id", "gosub tab.find", "if tf.p then", "im.k = 't' : bu<tf.p>", "im.x = bx{im.k}", "if tf.p = cb then im.x = ed.t", "end else",
               "call !ide_osfile('open', im.id, im.f, im.x, im.info, im.why)", "if im.why # '' then", "op.why = im.why", "op.path = im.id", "op.info = im.info", "gosub path.refusal", "return",
               "close im.f", "end else", "open im.file to fv else", "read im.x from fv, im.id else", "index(im.x, @vm, 1)", "convert(NA.CHARS, '', im.x) # im.x")
       and "'create'" not in di and "write" not in di and ide.count("call !ide_osfile('open'") == 2, "")

    # ---- messages --------------------------------------------------------------------------------------------------------------------------------------------------------
    bad = []
    for n, lab in NEWMSG.items():
        t = src["m%d" % n]
        body = LI.get(lab, "")
        mm = re.search(r"sysmsg\(%d(?:,\s*([^\n]*))?\)" % n, body)
        nargs = 0 if (not mm or not mm.group(1)) else len(split_args(mm.group(1)))
        top = max([int(x) for x in re.findall(r"%(\d)", t)] or [0])
        if not t.strip() or t.count("\n") != 1 or not mm or nargs != top:
            bad.append((n, bool(mm), nargs, top))
    ck("O19", "messages 12751-12754, 12767-12770, 15996 and 15997 exist, are one line, each is cited in the routine that says it (tree.os, os.load, os.create) with exactly as many arguments as the text has %n",
       not bad, repr(bad))
    gone = [n for n in DELETED if src["m%d" % n].strip()]
    cited = [n for n in DELETED if re.search(r"sysmsg\(\s*%d\b" % n, src["allbp"])]
    ck("O20", "the deleted messages 12732 (the name form's 'Open only') and 12563 (Import's refusal) are gone from the message directory and cited by no program of gpl.bp",
       not gone and not cited, repr((gone, cited)))
    ck("O21", "the help (12219) says that Save and New take path:/full/name and make a file of the operating system, and 12744 says Write a copy may keep the text in another operating system file",
       "an untitled one asks for its file and name; path:/full/name there makes a file of the operating system" in src["m12219"]
       and "New record (path:/full/name makes an empty file of the operating system and opens it)" in src["m12219"] and "or in another operating system file" in src["m12744"], "")
    # 30 Oct 26, the E2 review's finding 1: the save of an untitled buffer can turn the tab into an operating system file's, so compile (run, debug, catalogue), SED and Edit as fields ask
    #   path.not.for AGAIN after save.current and return before they go on
    bad22 = []
    for lab, marks in (("do.compile", ("gosub save.current", "if not(sv.ok) then return", "gosub path.not.for", "if pa.no then return", "c.file = bn<cb>")),
                       ("do.fields", ("gosub save.current", "if not(sv.ok) then return", "pa.allow = 'coll'", "gosub path.not.for", "pa.allow = ''", "if pa.no then return", "fd.u = bu<cb>"))):
        body = LI.get(lab, "")
        if not body:
            bad22.append(lab + " is not there")
        elif not ordered(body, *marks):
            bad22.append(lab + " does not ask path.not.for again after save.current")
    ck("O22", "compile, SED and Edit as fields ask path.not.for AGAIN right after the save of an untitled buffer (it may have made the tab an operating system file) and return before they go on",
       not bad22, "; ".join(bad22))
    return rows


def sub1(key, old, new):
    """a mutant: `old` must be in the file exactly once"""
    def f(src):
        n = src[key].count(old)
        if n != 1:
            raise KeyError("%s: %r occurs %d times, so the mutant cannot be made" % (key, old[:70], n))
        r = dict(src)
        r[key] = src[key].replace(old, new, 1)
        return r
    return f


def add_bp(text):
    def f(src):
        r = dict(src)
        r["allbp"] = src["allbp"] + "\n" + text
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


# ---- kernel
M_E2 = len(M)                       # the first mutant of stage E2 (all of this file's are; --selftest --from=N runs the ones from N on)
mut("a link to nothing is looked at after fullpath has followed it", "O1c", sub1("seqio", "lstat(file_name, &leaf_stat_buf)", "lstat(fullpathname, &leaf_stat_buf)"))
mut("a CREATING of a link to nothing is not refused", "O1c", sub1("seqio", "else if ((op_flags & 0x400) && leaf_is_link)", "else if ((op_flags & 0x400) && 0)"))
mut("a plain CREATING is not exclusive", "O1", sub1("seqio", "fu = dio_open(fullpathname, (op_flags & 0x800) ? DIO_OVERWRITE : DIO_NEW);", "fu = dio_open(fullpathname, DIO_OVERWRITE);"))
mut("SHARED becomes exclusive too", "O1", sub1("seqio", "fu = dio_open(fullpathname, (op_flags & 0x800) ? DIO_OVERWRITE : DIO_NEW);", "fu = dio_open(fullpathname, DIO_NEW);"))
mut("EEXIST is not told from any other failure", "O1", sub1("seqio", "process.status = (!(op_flags & 0x800) && errno == EEXIST) ? ER_EXISTS : ER_FNF;", "process.status = ER_FNF;"))
mut("SHARED reports ER_EXISTS", "O1", sub1("seqio", "process.status = (!(op_flags & 0x800) && errno == EEXIST) ? ER_EXISTS : ER_FNF;", "process.status = (errno == EEXIST) ? ER_EXISTS : ER_FNF;"))
mut("the edit-gate refusal is gone from CREATING", "O1", sub1("seqio", "} else if ((op_flags & 0x400) && edit_blocked)", "} else if (0)"))
mut("an existing file is truncated", "O1", sub1("seqio", "(read_only) ? DIO_READ : DIO_OVERWRITE", "(read_only) ? DIO_READ : DIO_REPLACE"))
mut("DIO_NEW has no O_EXCL", "O1b", sub1("dhfile", "open_modes = O_RDWR | O_CREAT | O_EXCL | O_BINARY;", "open_modes = O_RDWR | O_CREAT | O_BINARY;"))
mut("the file is made with a literal mode", "O1b", sub1("dhfile", "  fu = OpenFile(fn, open_modes, default_access);\n  if (!ValidFileHandle(fu) &&", "  fu = OpenFile(fn, open_modes, 0666);\n  if (!ValidFileHandle(fu) &&"))
mut("a socket is a file again", "O2", sub1("dio4", "if (S_ISREG(statbuf.st_mode))", "if (statbuf.st_mode & S_IFREG)"))
mut("a block device is a directory again", "O2", sub1("dio4", "else if (S_ISDIR(statbuf.st_mode))", "else if (statbuf.st_mode & S_IFDIR)"))
# ---- helper create
mut("create truncates", "O3a", sub1("osf", "   openseq path creating to f on error", "   openseq path creating overwrite to f on error"))
mut("create is not creating", "O3a", sub1("osf", "   openseq path creating to f on error", "   openseq path to f on error"))
mut("the text is checked after the open", "O3a", sub1("osf", "   gosub check.name\n   if why # '' then return\n   gosub make.data\n   if why # '' then return\n   lk.user = 0", "   gosub check.name\n   if why # '' then return\n   lk.user = 0"))
mut("the name is not checked", "O3a", sub1("osf", "create.file:\n   gosub check.name\n   if why # '' then return\n", "create.file:\n"))
mut("ON ERROR keeps the name locked", "O3a", sub1("osf", "   openseq path creating to f on error\n      op.st = status()\n      if not(unassigned(f)) then close f\n", "   openseq path creating to f on error\n      op.st = status()\n"))
mut("the ELSE keeps the name locked", "O3a", sub1("osf", "      if not(unassigned(f)) then close f\n      begin case\n         case op.st = ER.EXISTS", "      begin case\n         case op.st = ER.EXISTS"))
mut("a taken name is only cant", "O3a", sub1("osf", "         case op.st = ER.EXISTS\n            why = 'exists'", "         case op.st = ER.EXISTS\n            why = 'cant'"))
mut("the OS gate is only cant", "O3a", sub1("osf", "            why = 'exists'\n         case op.st = ER.PERM\n            why = 'gate'\n", "            why = 'exists'\n         case op.st = ER.PERM\n            why = 'cant'\n"))
mut("a locked file is written", "O3b", sub1("osf", "   if lk.user then\n      why = 'locked'\n      return\n   end\n   if (fileinfo(f, FL$SEQTYPE) + 0) # 0 then\n      close f\n      why = 'special'\n      return\n   end\n   if fileinfo(f, FL$READONLY) then", "   if (fileinfo(f, FL$SEQTYPE) + 0) # 0 then\n      close f\n      why = 'special'\n      return\n   end\n   if fileinfo(f, FL$READONLY) then"))
mut("a device is kept open", "O3b", sub1("osf", "      close f\n      why = 'special'\n      return\n   end\n   if fileinfo(f, FL$READONLY) then", "      why = 'special'\n      return\n   end\n   if fileinfo(f, FL$READONLY) then"))
mut("a read-only file is written", "O3b", sub1("osf", "   if fileinfo(f, FL$READONLY) then\n      close f\n      why = 'ro'\n      return\n   end\n   seek f, 0, 2", "   seek f, 0, 2"))
mut("a read-only file is kept open", "O3b", sub1("osf", "      close f\n      why = 'ro'", "      why = 'ro'"))
mut("a file with content is filled", "O3b", sub1("osf", "      if (fileinfo(f, FL$SEQPOS) + 0) # 0 then why = 'exists'", "      null"))
mut("a file with content is only compared", "O3b", sub1("osf", "if (fileinfo(f, FL$SEQPOS) + 0) # 0 then why = 'exists'", "if (fileinfo(f, FL$SEQPOS) + 0) < 0 then why = 'exists'"))
mut("a file with content is left open", "O3b", sub1("osf", "   if why # '' then\n      close f\n      return\n   end\n   gosub put.data", "   if why # '' then\n      return\n   end\n   gosub put.data"))
mut("a failed write leaves the file open", "O3b", sub1("osf", "      info<6> = status()\n      close f\n      return\n   end\n   info<3> = 0", "      info<6> = status()\n      return\n   end\n   info<3> = 0"))
mut("create writes itself", "O3b", sub1("osf", "   gosub put.data\n   if why # '' then\n      info<6> = status()\n      close f", "   writeblk data to f else null\n   gosub put.data\n   if why # '' then\n      info<6> = status()\n      close f"))
mut("create closes the file it made", "O3b", sub1("osf", "   info<3> = 0\n   return\n\n* In: path, a directory", "   info<3> = 0\n   close f\n   return\n\n* In: path, a directory"))
mut("'create' runs open.file", "O4", sub1("osf", "      case op = 'create'\n         gosub create.file", "      case op = 'create'\n         gosub open.file"))
mut("'list' is not wired", "O4", sub1("osf", "      case op = 'list'\n         gosub list.dir", "      case op = 'list'\n         why = 'op'"))
mut("a save no longer checks the text first", "O4", sub1("osf", "   gosub make.data\n   if why # '' then return\n   gosub put.data\n   return", "   gosub put.data\n   return"))
mut("create has its own write", "O4", sub1("osf", "   gosub put.data\n   if why # '' then\n      info<6> = status()\n      close f", "   gosub put.data\n   gosub put.data\n   if why # '' then\n      info<6> = status()\n      close f"))
# ---- helper list
mut("the gate of DIR() is only cant", "O5", sub1("osf", "      case ld.st = ER.PERM\n         why = 'gate'\n         info<6> = ld.st", "      case ld.st = ER.PERM\n         why = 'cant'\n         info<6> = ld.st"))
mut("a name with a control byte is listed", "O5", sub1("osf", "convert(ctl, '', ld.name) # ld.name or ", ""))
mut("a name with a slash is listed", "O5", sub1("osf", " or index(ld.name, '/', 1) then", " then"))
mut("the cap is gone", "O5", sub1("osf", "         if ld.kept >= OSF.LIST then", "         if 0 then"))
mut("the cap is a hundred thousand", "O5", sub1("osf", "OSF.LIST = 1000", "OSF.LIST = 100000"))
mut("the directories are not sorted", "O5", sub1("osf", "locate ld.name in ld.dnames<1> by 'AL' setting ld.pos else null", "ld.pos = 1"))
mut("the files are not sorted", "O5", sub1("osf", "locate ld.name in ld.fnames<1> by 'AL' setting ld.pos else null", "ld.pos = 1"))
mut("the files come first", "O5", sub1("osf", "text<-1> = ld.fnames<ld.j> : @vm : 'F'", "text<1> = ld.fnames<ld.j> : @vm : 'F'"))
mut("an unlisted path is not checked", "O5", sub1("osf", "   if path # '/' then\n      gosub check.name\n      if why # '' then return\n   end\n   ld.raw", "   ld.raw"))
mut("what was left out is not counted", "O5", sub1("osf", "   info<5> = ld.skip", "   info<5> = 0"))
mut("the size is not kept", "O5", sub1("osf", "ins ld.e<1, 3> before ld.fsizes<ld.pos>", "ins 0 before ld.fsizes<ld.pos>"))
mut("list opens the directory as a file", "O5", sub1("osf", "   ld.raw = dir(path)\n", "   openseq path to f2 else null\n   ld.raw = dir(path)\n"))
mut("the IDE lists a directory itself", "O5b", sub1("ide", "   call !ide_osfile('list', os.dir, os.lf, os.lt, os.li, os.lw)", "   os.junk = dir(os.dir)\n   call !ide_osfile('list', os.dir, os.lf, os.lt, os.li, os.lw)"))
# ---- name form
mut("a creating mode is not asked the OS gate", "O6", sub1("inm", "            case not(kernel(K$PATH.OK, op.path))\n               msg = sysmsg(12185, @who)\n", ""))
mut("a creating mode is not asked the edit gates", "O6", sub1("inm", "            case not(kernel(K$EDIT.OS.OK, op.path))\n", "            case 0\n"))
mut("the edit gate's reason is the last component's only (the VOC's words for a new file)", "O6", sub1("inm", "while ek = 0 and len(ep) > 1", "while 0"))
mut("a refusal with no gate to name says the VOC's words", "O6", sub1("inm", "msg = sysmsg(12768, op.path, 3035)", "msg = edit_msg(0)"))
mut("every mode is open mode", "O6", sub1("inm", "            case mode = 'open'\n", "            case mode # 'zzz'\n"))
mut("the edit gate is asked of another string", "O6", sub1("inm", "case not(kernel(K$EDIT.OS.OK, op.path))", "case not(kernel(K$EDIT.OS.OK, pw))"))
mut("Open asks the OS gate in the form", "O6", sub1("inm", "            case mode = 'open'\n               file = 'path:'", "            case mode = 'open' and not(kernel(K$PATH.OK, op.path))\n               msg = sysmsg(12185, @who)\n            case mode = 'open'\n               file = 'path:'"))
# ---- the IDE
mut("a refusal changes the tab", "O7", sub1("ide", "      case cr.why = 'gate'\n         if kernel(K$EDIT.OS.OK, cr.path) then\n", "      case cr.why = 'gate'\n         nbuf += 1\n         if kernel(K$EDIT.OS.OK, cr.path) then\n"))
mut("a taken name says the directory is missing", "O7", sub1("ide", "      case cr.why = 'exists' or cr.why = 'ro'\n         rf.text = sysmsg(12767, cr.path)", "      case cr.why = 'exists' or cr.why = 'ro'\n         rf.text = sysmsg(12768, cr.path, cr.info<6>)"))
mut("a bad byte says the file is not whole", "O7", sub1("ide", "      case cr.why = 'bytes' or cr.why = 'big'\n         msg = sysmsg(12770, cr.path)", "      case cr.why = 'bytes' or cr.why = 'big'\n         msg = sysmsg(12769, cr.path, cr.info<6>)"))
mut("a half-written file is not boxed", "O7", sub1("ide", "         rf.text = sysmsg(12769, cr.path, cr.info<6>)\n         msg = rf.text\n         gosub refuse.box", "         msg = sysmsg(12769, cr.path, cr.info<6>)"))
mut("a second create call", "O7", sub1("ide", "   gosub os.create\n   if cr.why = '' then\n      close cr.f", "   call !ide_osfile('create', cr.path, cr.f, cr.text, cr.info, cr.why)\n   if cr.why = '' then\n      close cr.f"))
mut("a file open in a tab is made again", "O8", sub1("ide", "   tf.id = cr.path\n   gosub tab.find\n   if tf.p then", "   tf.id = cr.path\n   gosub tab.find\n   if 0 then"))
mut("os.slot has no limit", "O8", sub1("ide", "   if cr.s > MAXLOCK then", "   if 0 then"))
mut("os.slot takes the slot", "O8", sub1("ide", "   cr.slot = cr.s\n   return", "   cr.slot = cr.s\n   tused<cr.s> = 1\n   return"))
mut("New does not look for a slot", "O9", sub1("ide", "   gosub os.slot\n   if not(cr.slot) then return\n   cr.text = ''", "   cr.slot = 1\n   cr.text = ''"))
mut("New with no slot looks made", "O9", sub1("ide", "   cr.why = 'slot'", "   cr.why = ''"))
mut("New goes on after a refusal", "O9", sub1("ide", "   cr.info = 0 : @fm : 0\n   gosub os.create\n   if cr.why # '' then return", "   cr.info = 0 : @fm : 0\n   gosub os.create"))
mut("New keeps the call's variable too", "O9", sub1("ide", "   tfv(op.s) = op.f\n   close op.f\n   tused<op.s> = 1\n   gosub path.tab.make\n   msg = sysmsg(12207", "   tfv(op.s) = op.f\n   tused<op.s> = 1\n   gosub path.tab.make\n   msg = sysmsg(12207"))
mut("New makes a file with a line in it", "O9", sub1("ide", "   cr.text = ''\n   cr.info = 0 : @fm : 0", "   cr.text = 'x'\n   cr.info = 0 : @fm : 0"))
mut("New does not list the directory again", "O9", sub1("ide", "   os.fp = op.path\n   gosub os.refresh                             ;* the directory it is in, when the tree lists it\n   return", "   return"))
mut("Save as drops the record's copy first", "O10", sub1("ide", "   oc.sent = cr.text\n   gosub os.create\n   if cr.why # '' then return", "   oc.sent = cr.text\n   ri = oc.i\n   gosub rc.drop.tab\n   gosub os.create\n   if cr.why # '' then return"))
mut("Save as gives the record's lock back first", "O10", sub1("ide", "   oc.sent = cr.text\n   gosub os.create\n   if cr.why # '' then return", "   oc.sent = cr.text\n   tu.i = oc.i\n   gosub tab.unlock\n   gosub os.create\n   if cr.why # '' then return"))
mut("Save as renames the tab first", "O10", sub1("ide", "   oc.sent = cr.text\n   gosub os.create\n   if cr.why # '' then return", "   oc.sent = cr.text\n   bn<oc.i> = 'path:'\n   gosub os.create\n   if cr.why # '' then return"))
mut("Save as goes on after a refusal", "O10", sub1("ide", "   gosub os.create\n   if cr.why # '' then return\n   oc.s = cr.slot", "   gosub os.create\n   oc.s = cr.slot"))
mut("Save as does not look for a slot", "O10", sub1("ide", "   cr.path = oc.path\n   gosub os.slot\n   if not(cr.slot) then return\n   oc.u = bu<oc.i>", "   cr.path = oc.path\n   cr.slot = 1\n   oc.u = bu<oc.i>"))
mut("Save as keeps the typed text as the baseline", "O10", sub1("ide", "   k = 's' : oc.u\n   bx{k} = cr.text", "   k = 's' : oc.u\n   bx{k} = oc.sent"))
mut("Save as forgets the recovery copy", "O10", sub1("ide", "   ri = oc.i\n   gosub rc.drop.tab                            ;* the text is in the file now; a recovery copy of the buffer or record goes\n", ""))
mut("Save as leaves the uid on this tab", "O10", sub1("ide", "   uid = oc.uid\n", ""))
mut("Save as does not list the directory again", "O10", sub1("ide", "   if oc.i = cb then gosub load.current\n   os.fp = oc.path\n   gosub os.refresh", "   if oc.i = cb then gosub load.current"))
mut("Write a copy keeps the lock", "O11", sub1("ide", "      close cr.f\n      msg = sysmsg(12207, 'path:', wa.id)", "      msg = sysmsg(12207, 'path:', wa.id)"))
mut("Write a copy makes a tab", "O11", sub1("ide", "      close cr.f\n      msg = sysmsg(12207, 'path:', wa.id)", "      close cr.f\n      gosub path.tab.make\n      msg = sysmsg(12207, 'path:', wa.id)"))
mut("Write a copy does not list the directory", "O11", sub1("ide", "      os.fp = wa.id\n      gosub os.refresh", "      os.fp = wa.id"))
mut("open.path makes its own tab again", "O12", sub1("ide", "   tused<op.s> = 1\n   gosub path.tab.make\n   return", "   tused<op.s> = 1\n   nbuf += 1\n   gosub path.tab.make\n   return"))
mut("a third maker of path tabs", "O12", sub1("ide", "   gosub os.create\n   if cr.why = '' then\n      close cr.f", "   gosub os.create\n   if cr.why = '' then\n      gosub path.tab.make\n      close cr.f"))
mut("do.new does not send a path: name to os.new", "O13", sub1("ide", "   if nm.file = 'path:' then\n      * 30 Oct 26 (stage E2): a name of the operating system: an empty file is made and opened in a tab of its own\n      gosub os.new", "   if 0 then\n      gosub os.new"))
mut("do.new focuses a tab that was not made", "O13", sub1("ide", "      if nbuf > 0 and cr.why = '' then", "      if nbuf > 0 then"))
mut("Save as goes on to the record's tab", "O13", sub1("ide", "      oc.path = sa.id\n      gosub os.convert\n      return", "      oc.path = sa.id\n      gosub os.convert"))
mut("Write a copy does not send a path: name", "O13", sub1("ide", "   if wa.file = 'path:' then\n      gosub copy.to.os                  ;* 30 Oct 26 (stage E2): a name of the operating system: a file is made for the text\n      return\n   end\n", ""))
mut("Write a copy writes over a tab's file", "O13", sub1("ide", "   gosub tab.find\n   if tf.p then\n      msg = sysmsg(12696, wa.file, wa.id)\n      return\n   end\n   gosub write.copy\n   return\n\n* In: wa.text, wa.file", "   gosub write.copy\n   return\n\n* In: wa.text, wa.file"))
mut("untitled's first save forgets it was a file", "O14", sub1("ide", "         sv.named = @true\n         sv.osdone = @true\n      end", "         sv.named = @true\n      end"))
mut("save.one goes on after a file was made", "O14", sub1("ide", "      if sv.osdone then\n         sv.ok = @true", "      if 0 then\n         sv.ok = @true"))
mut("untitled's refusal still names a record", "O14", sub1("ide", "         sv.osdone = @true\n      end\n      return", "         sv.osdone = @true\n      end"))
mut("the OS node is there for everyone", "O15", sub1("ide", "   if os.on then gosub tree.os", "   gosub tree.os"))
mut("the OS gate is not asked for the node", "O15", sub1("ide", "os.on = kernel(K$PATH.OK, '/') + 0", "os.on = 1"))
mut("the node's title is hard-coded", "O15", sub1("ide", "nodes<-1> = sysmsg(12751) : @sm : 1 : @sm : 'O:/'", "nodes<-1> = 'Operating system files' : @sm : 1 : @sm : 'O:/'"))
mut("tree.os lists the disk itself", "O15", sub1("ide", "   os.rootn = nn\n", "   os.rootn = nn\n   call !ide_osfile('list', '/', os.xf, os.xt, os.xi, os.xw)\n"))
mut("a second Return does not close a directory", "O16", sub1("ide", "               if os.q then\n                  gosub os.collapse", "               if 0 then\n                  gosub os.collapse"))
mut("a file of the tree is opened folded", "O16", sub1("ide", "               op.path = code[3, 9999]                     ;* a file", "               op.path = downcase(code[3, 9999])                     ;* a file"))
mut("a refusal to list is not said", "O16", sub1("ide", "            msg = sysmsg(12752, os.dir, os.li<6>)", "            msg = ''"))
mut("collapse goes forward", "O16", sub1("ide", "   for os.j = os.nf to 1 step -1\n      os.pp = ofiles<os.j>", "   for os.j = 1 to os.nf\n      os.pp = ofiles<os.j>"))
mut("collapse takes a sibling with the same start", "O16", sub1("ide", " or os.pp[1, len(os.dir) + 1] = os.dir : '/' then", " or os.pp[1, len(os.dir)] = os.dir then"))
mut("what was left out is not said", "O16", sub1("ide", "   if os.li<5> + 0 then msg = sysmsg(12753, os.dir, os.li<5>)", "   null"))
mut("the tree is not drawn again", "O17", sub1("ide", "   if os.q then\n      gosub os.load\n      gosub tree.apply\n      gosub redraw.tree\n   end\n   i = os.keep.i", "   if os.q then\n      gosub os.load\n   end\n   i = os.keep.i"))
mut("the tree lists a directory it did not list", "O17", sub1("ide", "   if not(os.on) then return\n   os.keep.i = i", "   os.keep.i = i"))
mut("Import takes the file from disk even when a tab holds it", "O18", sub1("ide", "      if tf.p then\n         im.k = 't' : bu<tf.p>", "      if 0 then\n         im.k = 't' : bu<tf.p>"))
mut("Import of the tab in the editor takes the stored text, not the live one", "O18", sub1("ide", "         if tf.p = cb then im.x = ed.t ", "         if 0 then im.x = ed.t "))
mut("compile goes on with a tab the save made an operating system file", "O22", sub1("ide", "gosub path.not.for                ;* 30 Oct 26 (E2): the save of an untitled buffer", "pa.no = @false                    ;* 30 Oct 26 (E2): the save of an untitled buffer"))
mut("SED goes on with a tab the save made an operating system file", "O22", sub1("ide", "gosub path.not.for                ;* 30 Oct 26 (E2): the save may have made the tab an operating system file's (path:/name): SED", "pa.no = @false                    ;* 30 Oct 26 (E2): the save may have made the tab an operating system file's (path:/name): SED"))
mut("Edit as fields goes on with a tab the save made an operating system file", "O22", sub1("ide", "gosub path.not.for                ;* 30 Oct 26 (E2): the save may have made the tab an operating system file's (path:/name), which has no fields", "pa.no = @false                    ;* 30 Oct 26 (E2): the save may have made the tab an operating system file's (path:/name), which has no fields"))
mut("Import keeps the file open", "O18", sub1("ide", "         close im.f\n      end\n   end else", "      end\n   end else"))
mut("Import does not say a refusal", "O18", sub1("ide", "            op.info = im.info\n            gosub path.refusal\n            return", "            op.info = im.info\n            return"))
mut("Import creates the file", "O18", sub1("ide", "call !ide_osfile('open', im.id, im.f, im.x, im.info, im.why)", "call !ide_osfile('create', im.id, im.f, im.x, im.info, im.why)"))
# ---- messages
mut("12751 is hard-coded", "O19", sub1("ide", "nodes<-1> = sysmsg(12751) :", "nodes<-1> = sysmsg(12204) :"))
mut("12754 is empty", "O19", setmsg(12754, ""))
mut("12767 has two lines", "O19", setmsg(12767, "%1 was not made\nand more\n"))
mut("12768 wants a third argument", "O19", setmsg(12768, "%1 was not made (error %2, %3)\n"))
mut("12770 is not cited", "O19", sub1("ide", "sysmsg(12770, cr.path)", "sysmsg(12736, cr.path)"))
mut("12732 comes back as a file", "O20", setmsg(12732, "Open only\n"))
mut("12563 is cited again", "O20", add_bp(" msg = sysmsg(12563)"))
mut("12732 is cited again", "O20", add_bp(" msg = sysmsg(12732)"))
mut("the help forgets Save", "O21", sub1("m12219", "an untitled one asks for its file and name; path:/full/name there makes a file of the operating system", "an untitled one asks for its file and name"))
mut("the help forgets New", "O21", sub1("m12219", "New record (path:/full/name makes an empty file of the operating system and opens it)", "New record"))
mut("12744 forgets the file copy", "O21", sub1("m12744", ", or in another operating system file", ""))
M_A1 = len(M)                       # the first mutant of S.88 A1 (30 Oct 26): --selftest --from=N with this N runs only these four
mut("the file,record form does not look at the raw record name", "O1d", sub1("seqio", "if (lstat(pathname, &leaf_stat_buf) == 0 && S_ISLNK(leaf_stat_buf.st_mode))", "if (lstat(pathname, &leaf_stat_buf) == 1 && S_ISLNK(leaf_stat_buf.st_mode))"))
mut("a link to nothing no longer marks the file variable read only", "O1d", sub1("seqio", "if (leaf_is_link && !(flags & SQ_PORT) && !ValidFileHandle(fu))", "if (0 && !(flags & SQ_PORT) && !ValidFileHandle(fu))"))
mut("the create on a first write follows a link again", "O1d", sub1("seqio", "fu = dio_open(sq_file->pathname, DIO_OVERWRITE_NOFOLLOW);", "fu = dio_open(sq_file->pathname, DIO_OVERWRITE);"))
mut("the new open mode has no O_NOFOLLOW", "O1d", sub1("dhfile", "open_modes = O_RDWR | O_CREAT | O_NOFOLLOW | O_BINARY;", "open_modes = O_RDWR | O_CREAT | O_BINARY;"))
M_A345 = len(M)                     # the first mutant of S.88 A3 and A5 and the boxes (30 Oct 26): --selftest --from=N with this N runs only these
mut("an ON ERROR of the create is only cant", "O3a", sub1("osf", "      why = 'cantmade'", "      why = 'cant'"))
mut("the gate answer is always the OS gate", "O7", sub1("ide", "         if kernel(K$EDIT.OS.OK, cr.path) then\n            msg = sysmsg(12185, @who)\n         end else\n            msg = sysmsg(12768, cr.path, 3035)", "         if 1 then\n            msg = sysmsg(12185, @who)\n         end else\n            msg = sysmsg(12768, cr.path, 3035)"))
mut("the edit gate is asked of another name", "O7", sub1("ide", "if kernel(K$EDIT.OS.OK, cr.path) then", "if kernel(K$EDIT.OS.OK, '') then"))
mut("the edit gate is never the OS gate's words", "O7", sub1("ide", "            msg = sysmsg(12185, @who)\n         end else", "            msg = sysmsg(12768, cr.path, 3035)\n         end else"))
mut("a locked file says the old words", "O7", sub1("ide", "rf.text = sysmsg(15997, cr.path)", "rf.text = sysmsg(12736, cr.path)"))
mut("a locked file is not boxed", "O7", sub1("ide", "         rf.text = sysmsg(15997, cr.path)                       ;* 30 Oct 26 (S.88 A3); since 02 Nov 26 the kernel makes nothing when the name is locked\n         msg = rf.text\n         gosub refuse.box", "         msg = sysmsg(15997, cr.path)"))
mut("an error that may have left a file is not boxed", "O7", sub1("ide", "         rf.text = sysmsg(15996, cr.path, cr.info<6>)           ;* 30 Oct 26 (S.88 A3): an ON ERROR ended the create; the file may have been made\n         msg = rf.text\n         gosub refuse.box", "         msg = sysmsg(15996, cr.path, cr.info<6>)"))
mut("a taken name is not boxed", "O7", sub1("ide", "         rf.text = sysmsg(12767, cr.path)                       ;* 30 Oct 26 (S.88 9g): in a box, the status line cut it\n         msg = rf.text\n         gosub refuse.box", "         msg = sysmsg(12767, cr.path)"))
mut("the cantmade case is gone", "O7", sub1("ide", "      case cr.why = 'cantmade'\n", "      case cr.why = 'cantmaid'\n"))
mut("15996 wants a third argument", "O19", setmsg(15996, "%1 may have been made (error %2, %3)\n"))
mut("15997 has two lines", "O19", setmsg(15997, "%1 is locked\nand more\n"))
mut("15996 is not cited", "O19", sub1("ide", "sysmsg(15996, cr.path, cr.info<6>)", "sysmsg(12769, cr.path, cr.info<6>)"))
M_A35B = len(M)                     # the first mutant of 02 Nov 26 (S.88 A3 in the kernel, A5 for DIR()): --selftest --from=N with this N runs only these
mut("the create is made before the lock again", "O1e", sub1("seqio", "      create_after_lock = TRUE;\n", "      fu = dio_open(fullpathname, (op_flags & 0x800) ? DIO_OVERWRITE : DIO_NEW);\n"))
mut("the deferred create is never made", "O1e", sub1("seqio", "  if (create_after_lock) {\n", "  if (0) {\n"))
mut("the lock-conflict branch leaves the closed handle valid", "O1e", sub1("seqio", "        fu = INVALID_FILE_HANDLE; /* 02 Nov 26", "        /* 02 Nov 26"))
mut("a failed deferred create does not reach the exit", "O1e", sub1("seqio", "      process.status = (!(op_flags & 0x800) && errno == EEXIST) ? ER_EXISTS : ER_FNF;\n      goto exit_op_openseq;\n    }\n  }\n", "      process.status = (!(op_flags & 0x800) && errno == EEXIST) ? ER_EXISTS : ER_FNF;\n    }\n  }\n"))
mut("the helper does not keep the OS error of a refused DIR()", "O16b", sub1("osf", "         info<7> = ld.oserr", "         null"))
mut("the OS error is read after another statement", "O16b", sub1("osf", "   ld.st = status()\n   ld.oserr = os.error()\n", "   ld.oserr = os.error()\n   ld.st = status()\n"))
mut("an unreadable directory says no OS access", "O16b", sub1("ide", "            if kernel(K$PATH.OK, os.dir) then\n", "            if 0 then\n"))
mut("the OS gate says the unreadable words", "O16b", sub1("ide", "               msg = sysmsg(12185, @who)\n            end\n         case os.lw = 'none'", "               msg = sysmsg(12604, os.dir, os.li<7>)\n            end\n         case os.lw = 'none'"))
mut("12604 wants a third argument", "O19", setmsg(12604, "%1 could not be listed (%2, %3)\n"))
mut("12604 is not cited", "O19", sub1("ide", "sysmsg(12604, os.dir, os.li<7>)", "sysmsg(12752, os.dir, os.li<7>)"))


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:240]))
        bad += 0 if ok else 1
    return bad


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
    print("test-ideos-units: tree %s" % SD64)
    if not src["ide"] or not src["osf"] or not src["seqio"]:
        print("test-ideos-units: CANNOT RUN - gpl.bp/ide, gpl.bp/ide_osfile or gplsrc/op_seqio.c is not there")
        return 2
    rows = checks(src)
    bad = report(rows)
    print("\ntest-ideos-units: %d passed, %d failed" % (len(rows) - bad, bad))
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
