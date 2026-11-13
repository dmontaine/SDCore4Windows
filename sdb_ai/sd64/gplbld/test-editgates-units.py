#!/usr/bin/env python3
"""test-editgates-units.py - the edit gates voc.edit, bp.edit and dict.edit (S.64), as invariants read off the source.

  python sdb_ai/sd64/gplbld/test-editgates-units.py
  python sdb_ai/sd64/gplbld/test-editgates-units.py --selftest

13 Nov 26 Windows port - from Linux's test-editgates-units.py (RELEASE_1.1 254).  Message ids +1005 (11405-11410 are 12410-12415).  The
installer checks (B10, B11, B13) are aimed at upgrade-gates.ps1 (run by sd.iss's RefreshGates) and attach-account.ps1 -OpenGates; B12
(check-storewriters, Linux's euid test) and C20 (the socket trace log, not built here: owner, 25 Oct 26) are dropped.  OSPATH for a user
program is pub_ospath() in op_dio2.c; the catalogue and leaf tests resolve with fullpath / path_fold.  Each change is marked "Windows:".

No elevation, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.  Written 17 Oct 26.

***WHAT THIS IS, AND WHAT IT IS NOT.***  It reads the C and BASIC sources as text, with comments removed, so a gate that survives only
in a comment does not count.  ***IT DOES NOT RUN ANYTHING, SO IT CANNOT SAY THAT A GATE REFUSES ANYBODY***: that is Linux's sandbox-editgates.py, not carried
here (ordinary sessions on a private SD; the program's own read-back and the disk are the evidence).  What a text check is for: the gate is
reached from many places - op_dio3.c, op_seqio.c, to_file.c, op_kernel.c, op_sh.c, login, the API server, and the twelve BASIC programs
the kernel's own test lets through because they are $internal - and the invariants that make it a gate are mostly ORDERING (the refusal
before an id is taken or a lock is held, the load at SIGN-ON and nowhere else, the install walk's marker after the walk).  An edit that
moves one still compiles.

***AND THE CHECKS ARE THEMSELVES CHECKED.***  --selftest breaks each invariant in the way an edit plausibly would and requires some
check to notice.  A mutant that nothing catches is reported as a FAILURE of the self-test.
"""

import os
import re
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.abspath(os.path.join(HERE, os.pardir))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
GPLSRC = os.path.join(SD64, "gplsrc")

# Windows: op_dio2.c holds pub_ospath (Linux's x_ospath); op_skt.c is not read (no socket trace log here, C20)
C_FILES = ("op_sh.c", "op_dio3.c", "op_seqio.c", "op_kernel.c", "to_file.c", "kernel.c", "keys.h", "sysseg.h", "sd.h",
           "op_xfun.c", "op_dio2.c", "op_dio1.c", "object.c")
BP_PROGRAMS = ("login", "cproc", "apisrvr", "modifya", "createa", "create_account", "acc_os_info", "restorea", "upgrade_editgates", "edit_guard",
               "clearfl", "delete", "copy", "cname", "ed", "edit", "deletef", "ide", "ced_edit", "basic", "catalog", "delcat",
               "decat", "_oscopy", "_ioscopy",
               # S.64 part 2: the $internal verbs that write, delete or clear a record of a file the user names
               "fixdir", "format", "mapcat", "spview", "settrig", "ide_name", "copylst", "dellist", "getlist", "savelst", "sortlst", "qproc", "cd",
               "generate", "como", "createf", "writelist", "_mksavedlists")
FILES = {n: os.path.join(GPLSRC, n) for n in C_FILES}
FILES.update({n: os.path.join(GPL, n) for n in BP_PROGRAMS})
FILES.update({"int$keys.h": os.path.join(GPL, "int$keys.h"), "syscom/keys.h": os.path.join(SDSYS, "syscom", "keys.h"),
              "createacc.h": os.path.join(SDSYS, "syscom", "createacc.h"),
              # Windows: the installer is sd.iss; the walks run in upgrade-gates.ps1, the installing user's gates in attach-account.ps1
              "sd.iss": os.path.join(HERE, "sd.iss"), "upgrade-gates.ps1": os.path.join(HERE, "upgrade-gates.ps1"),
              "attach-account.ps1": os.path.join(HERE, "attach-account.ps1")})
SH_FILES = ("upgrade-gates.ps1", "attach-account.ps1")
ISS_FILES = ("sd.iss",)


def strip_c(src):
    def blank(m):
        return "\n" * m.group(0).count("\n")
    src = re.sub(r"/\*.*?\*/", blank, src, flags=re.S)
    return re.sub(r"//[^\n]*", "", src)


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


def strip_sh(src):
    return "\n".join("" if l.lstrip().startswith("#") else l for l in src.split("\n"))


def strip_iss(src):
    return "\n".join("" if l.lstrip().startswith(";") else l for l in src.split("\n"))


def code(name, src):
    if name in C_FILES:
        return strip_c(src)
    if name in SH_FILES:
        return strip_sh(src)
    if name in ISS_FILES:
        return strip_iss(src)
    return strip_bas(src)


def at(text, needle, start=0):
    return text.find(needle, start)


def func_body(text, signature):
    """The text of the C function that begins at SIGNATURE, up to the matching close brace (comments already removed)."""
    i = text.find(signature)
    if i < 0:
        return ""
    j = text.find("{", i)
    depth = 0
    for k in range(j, len(text)):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                return text[i:k + 1]
    return text[i:]


# S.64 part 2: (program, the file variable the guard is asked of, the statement that opens it, what must come AFTER the ask)
GUARD_TABLE = [
    ("fixdir", "f", "open fname to f else", ["select f to 11", "write rec to f, id"]),
    ("format", "src.f", "open file.name to src.f else", ["readlist id.list", "readu in.rec from src.f", "write out.rec to src.f"]),
    ("mapcat", "map.f", "open file.name to map.f else", ["display sysmsg(3044", "filelock map.f", "clearfile map.f", "write map.rec to map.f"]),
    ("settrig", "fu", "open dict.flag, filename to fu else", ["gosub validate.call.name", "set.trigger fu, trigger.name, modes"]),
    ("copylst", "tgt.file", "open tgt.file.name to tgt.file else", ["select src.file to 11", "write list.rec to tgt.file", "delete src.file, src.list"]),
    ("copylst", "src.file", "open src.file.name to src.file else", ["select src.file to 11", "write list.rec to tgt.file", "delete src.file, src.list"]),
    ("dellist", "saved.lists.file", "open saved.name to saved.lists.file else",
     ["readvu list.rec from saved.lists.file", "delete saved.lists.file, list.name"]),
    ("getlist", "saved.lists.file", "open saved.name to saved.lists.file else",
     ["read list.rec from saved.lists.file", "formlist list.rec to list.no", "delete saved.lists.file, list.name"]),
    ("savelst", "saved.lists.file", "open saved.name to saved.lists.file else",
     ["readlist list.rec from list.no", "recordlocku saved.lists.file, list.name", "write list.rec to saved.lists.file, list.name"]),
    ("sortlst", "list.f", "open file.name to list.f else", ["readu list.rec from list.f", "write sorted to list.f"]),
    ("cd", "dict.f", "open file.to.open to dict.f else", ["select dict.f to 11", "readu itype.rec from dict.f", "write itype.rec to dict.f"]),
    ("generate", "dict.file", "open 'DICT', dict.name to dict.file else", ["display sysmsg(6862)", "write incl.rec to dict.file, '$INCLUDE'"]),
    ("generate", "target.f", "open file.name to target.f else", ["openseq file.name, record.name overwrite"]),
    ("qproc", "pageseq.f", "open token to pageseq.f else", ["readvu pageseq from pageseq.f"]),
]


def checks(srcs, messages_dir):
    rows = []

    def ck(i, ok, detail=""):
        rows.append((i, bool(ok), detail))

    c = {name: code(name, text) for name, text in srcs.items()}

    # ---- K. numbers, bits, fields -----------------------------------------------------------------------------------------
    want = {"K_VOC_EDIT": 121, "K_BP_EDIT": 122, "K_DICT_EDIT": 123, "K_EDIT_OK": 124, "K_EDIT_KIND": 125, "K_EDIT_OS_OK": 126}
    got = {m.group(1): int(m.group(2)) for m in re.finditer(r"#define\s+(K_[A-Z0-9_]+)\s+(\d+)", c["keys.h"])}
    ck("K1 the six kernel keys have their numbers in keys.h", all(got.get(k) == v for k, v in want.items()), repr({k: got.get(k) for k in want}))
    by_num = {}
    for k, v in got.items():
        by_num.setdefault(v, []).append(k)
    ck("K2 no kernel key number is used twice", all(len(v) == 1 for v in by_num.values()), repr({n: v for n, v in by_num.items() if len(v) > 1}))
    bas = {m.group(1): int(m.group(2)) for m in re.finditer(r"\$define\s+(K\$[A-Z0-9.]+)\s+(\d+)", c["int$keys.h"])}
    mirror = {"K$VOC.EDIT": 121, "K$BP.EDIT": 122, "K$DICT.EDIT": 123, "K$EDIT.OK": 124, "K$EDIT.KIND": 125, "K$EDIT.OS.OK": 126}
    ck("K3 int$keys.h carries the same numbers", all(bas.get(k) == v for k, v in mirror.items()), repr({k: bas.get(k) for k in mirror}))
    acc = {m.group(1): int(m.group(2)) for m in re.finditer(r"\$define\s+(ACC\$[A-Z0-9.]+)\s+(\d+)", c["syscom/keys.h"])}
    ck("K4 register fields 10, 11, 12 are ACC$VOC.EDIT, ACC$BP.EDIT, ACC$DICT.EDIT and nothing else uses them",
       (acc.get("ACC$VOC.EDIT"), acc.get("ACC$BP.EDIT"), acc.get("ACC$DICT.EDIT")) == (10, 11, 12)
       and sorted(v for v in acc.values() if 10 <= v < 13) == [10, 11, 12], repr(acc))       # 13 and 14 are reserved, 15 is ACC$NET (S.65)
    ss = c["sysseg.h"]
    ck("K5 the user table has its own gates word and the three bits (the flags word is full)",
       re.search(r"u_int16_t\s+gates\s*;", ss) is not None and re.search(r"#define\s+UG_VOC_EDIT\s+0x0001", ss) is not None
       and re.search(r"#define\s+UG_BP_EDIT\s+0x0002", ss) is not None and re.search(r"#define\s+UG_DICT_EDIT\s+0x0004", ss) is not None, "")
    kc = c["kernel.c"]
    f_off = at(kc, "my_uptr->flags = 0;")
    g_off = at(kc, "my_uptr->gates = 0;")
    ck("K6 a process taking its user entry starts with the gates off (gates zeroed beside flags)", 0 <= f_off < g_off < f_off + 400, "%d %d" % (f_off, g_off))
    ca = c["createacc.h"]
    ck("K7 createacc.h has CA$VOC.EDIT 32, CA$BP.EDIT 33, CA$DICT.EDIT 34 in the Linux-only block",
       all(re.search(r"\$define\s+%s\s+%d" % (re.escape(n), v), ca) for n, v in (("CA$VOC.EDIT", 32), ("CA$BP.EDIT", 33), ("CA$DICT.EDIT", 34))), "")

    # ---- C. the kernel ---------------------------------------------------------------------------------------------------
    sh = c["op_sh.c"]
    kind = func_body(sh, "Private int edit_kind_of_name(const char *path)")
    ck("C1 edit_kind_of_name knows voc, *.dic, bp, bp.out, *.bp and *.bp.out, and ignores case",
       all(s in kind for s in ('"voc"', '".dic"', '"bp"', '"bp.out"', '".bp"', '".bp.out"')) and kind.count("strncasecmp") >= 6, "")
    kpath = func_body(sh, "int edit_kind_of_path(const char *path)")
    ck("C1b edit_kind_of_path asks the name first and the private catalogue second, and the catalogue is a PROGRAM file (S.64 part 2)",
       0 <= at(kpath, "edit_kind_of_name(path)") < at(kpath, "path_is_private_catalogue(path)") and "return EDIT_PROG" in kpath, "")
    pcat = func_body(sh, "Private bool path_is_private_catalogue(const char *path)")
    ck("C1c the catalogue test is by PLACE, not by the bare name: the cheap last-component compare comes before the realpath, the place is "
       "compared with catalogue_position == 1, and a path that cannot be placed fails closed",
       # Windows: resolved by fullpath() and folded by path_fold() (drive letters, either separator), not realpath against the cwd
       0 <= at(pcat, "strncasecmp(last, cat_last, n)") < at(pcat, "fullpath(resolved, (char *)path)") < at(pcat, "catalogue_position(folded) == 1")
       and re.search(r"path_fold\(resolved, folded\)\)\s*\n\s*return TRUE;", pcat) is not None, "")
    cpos = func_body(sh, "Private int catalogue_position(const char *folded)")
    ck("C1d catalogue_position: 1 for the directory itself, 2 only below a '/' (a lookalike such as cat2 is 0)",
       "return 1;" in cpos and "folded[n] == '/'" in cpos and "return 0;" in cpos, "")
    lc = func_body(sh, "bool edit_leaf_counts(const char *name)")
    ck("C1e edit_leaf_counts: lstat, and only a name that is there and not a plain file counts (a link counts, a name not made yet does not)",
       "lstat(resolved, &sb)" in lc and "!S_ISREG(sb.st_mode)" in lc and "return FALSE" in lc, "")     # Windows: lstat of the fullpath()
    perm = func_body(sh, "bool edit_permitted(int kind)")
    ck("C2 edit_permitted lets the administrator through BEFORE it looks at any gate",
       0 <= at(perm, "MY_ADMIN()") < at(perm, "UG_VOC_EDIT"), "")
    ck("C3 edit_permitted reads each kind's own bit", "UG_VOC_EDIT" in perm and "UG_BP_EDIT" in perm and "UG_DICT_EDIT" in perm, "")
    osr = func_body(sh, "int edit_os_path_refusal(const char *name, bool include_leaf)")
    ck("C4 edit_os_path_refusal passes the administrator, refuses a path it cannot resolve, and leaves an OS.EXECUTE account alone outside its own directory",
       "MY_ADMIN()" in osr and "return EDIT_VOC" in osr and "USR_OS_EXEC" in osr, "")
    ck("C4b ...takes include_leaf: the final name is classified only when include_leaf (or something follows it), bare components by edit_kind_of_name",
       "include_leaf || (*more != '\\0')" in osr and "edit_kind_of_name(comp)" in osr and "edit_kind_of_path(comp)" not in osr, "")
    ck("C4c ...the private catalogue is a program file by place: catalogue_position before the component loop, below it always, the directory itself "
       "only with include_leaf, and the bp.edit bit decides",
       0 <= at(osr, "catalogue_position(folded)") < at(osr, "edit_kind_of_name(comp)")       # Windows: the folded fullpath()
       and "((cat_pos == 2) || ((cat_pos == 1) && include_leaf)) && !edit_permitted(EDIT_PROG)" in osr, "")
    d3 = c["op_dio3.c"]
    ref = func_body(d3, "Private int edit_refusal(FILE_VAR *fvar)")
    ck("C5 edit_refusal: a $internal program and the administrator pass BEFORE the path is read",
       0 <= at(ref, "HDR_INTERNAL") < at(ref, "->pathname") and 0 <= at(ref, "MY_ADMIN()") < at(ref, "->pathname"), "")
    wr = func_body(d3, "void op_write()")
    # 21 Oct 26 (S.73 item 3): the NET arm (a remote file) handles P_SEQKEY first and is behind refuse_net_file, whose net_gate asks the edit gate by the REMOTE file's name; the local
    # CREATING.SEQKEY id is still taken after edit_refusal(fvar), the next P_SEQKEY after it
    ck("C6 op_write asks edit_refusal BEFORE a CREATING.SEQKEY id is taken from the file (a local file; a remote file's SEQKEY write is behind refuse_net_file, which comes first)",
       0 <= at(wr, "refuse_net_file(") < at(wr, "P_SEQKEY") < at(wr, "edit_refusal(fvar)") < at(wr, "P_SEQKEY", at(wr, "edit_refusal(fvar)")), "")
    wv = func_body(d3, "void op_writev()")
    ck("C7 op_writev asks BEFORE the recursive pcode, whose flags are internal", 0 <= at(wv, "edit_refusal(") < at(wv, "k_recurse(pcode_writev"), "")
    dl = func_body(d3, "void op_delete()")
    ck("C8 op_delete asks after the read-only test and before a record lock is taken or the record is read",
       0 <= at(dl, "FV_RDONLY") < at(dl, "edit_refusal(fvar)") < at(dl, "check_lock("), "")
    cl = func_body(d3, "void op_clrfile()")
    ck("C9 op_clrfile asks before it takes the file lock (StartExclusive)", 0 <= at(cl, "edit_refusal(fvar)") < at(cl, "StartExclusive("), "")
    ck("C10 a refusal without ON ERROR is an error that gives the reason (k_error with the message of edit_refused_message(kind): 12410 to 12412 for the S.64 kinds, 12518 and 12519 since S.66, op_sh.c)",
       d3.count("k_error(sysmsg(EDIT_REFUSED_MSG(edit_kind)))") >= 4 and "#define EDIT_REFUSED_MSG(kind) edit_refused_message(kind)" in d3
       and re.search(r"int edit_refused_message\(int kind\) \{[^}]*12409 \+ kind", c["op_sh.c"]) is not None, "")
    kn = c["op_kernel.c"]
    setter = kn[at(kn, "case K_VOC_EDIT:"):at(kn, "case K_NET:")]      # 18 Oct 26 (S.66): to the next case, not to K_EDIT_OK - the NET and shared cases have HDR_INTERNAL tests of their own
    ck("C11 the three gate keys are set only from a $internal program",
       re.search(r"if \(n >= 0\) \{\s*if \(process\.program\.flags & HDR_INTERNAL\)\s*SET_MY_GATE\(edit_bit, n > 0\);", setter) is not None, "")
    okh = kn[at(kn, "case K_EDIT_OK:"):at(kn, "case K_EDIT_OS_OK:")]
    ck("C12 K_EDIT_OK passes the administrator, refuses an empty pathname (it starts with no name and the answer starts at 0) and asks edit_ok_for_path",
       "MY_ADMIN()" in okh and re.search(r"edit_name\[0\] = '\\0';\s*result\.data\.value = 0;", okh) is not None and "edit_ok_for_path(edit_name)" in okh, "")
    osk = kn[at(kn, "case K_EDIT_OS_OK:"):at(kn, "case K_PATH_OK:")]
    ck("C13 K_EDIT_OS_OK passes the administrator and otherwise asks edit_os_path_refusal on the argument", "MY_ADMIN()" in osk
       and "edit_os_path_refusal(edit_os_name, edit_leaf_counts(edit_os_name))" in osk, "")
    sq = c["op_seqio.c"]
    ops = func_body(sq, "void op_delseq()")
    ck("C14 DELETESEQ asks edit_os_path_refusal after the path is built and before the file is looked at (stat)",
       0 <= at(ops, "edit_os_path_refusal(file_name, FALSE)") < at(ops, "stat(file_name"), "")
    opn = sq[at(sq, "edit_blocked = FALSE"):]
    ck("C15 OPENSEQ works out edit_blocked once the full path is known and before the file is opened (dio_open), leaf not counted (a record called sample.bp)",
       0 <= at(opn, "edit_blocked = (edit_os_path_refusal(fullpathname, FALSE)") < at(opn, "dio_open("), "")
    ck("C16 ...makes an existing file read only, refuses CREATING there (ER_PERM) and marks the file variable read only",
       "|| edit_blocked) {" in opn and "(op_flags & 0x400) && edit_blocked" in opn and "read_only || edit_blocked" in opn, "")
    ck("C17 a $internal program is not asked (as os_path_open_ok does)", "!(process.program.flags & HDR_INTERNAL)" in opn and '#include "header.h"' in sq, "")
    tf = c["to_file.c"]
    ck("C18 a print file is refused in a guarded file, after the OS gate and before the file is made",
       0 <= at(tf, "os_path_ok_for_account(fn)") < at(tf, "if (edit_os_path_refusal(fn, FALSE) != EDIT_NONE) {") < at(tf, "open_file:"), "")

    # ---- C2. the other routes to an OS path (S.64 part 2) ------------------------------------------------------------------
    # Windows: OSPATH() of a user program is pub_ospath() in op_dio2.c, which op_xfun.c calls for XF_OSPATH.  Linux also tests HDR_INTERNAL inside
    #   the condition; here the opcode alone keeps a $internal program out (the compiler emits XF_OSPATH only outside internal mode, as Linux's
    #   own comment says), so the check asks for the dispatch instead of the redundant flag test.
    xo = func_body(c["op_dio2.c"], "void pub_ospath() {")
    ck("C19 OSPATH keys 5, 13 and 14 of a user program ask the edit gates AFTER the S.63 test, a $internal program is not asked, key 5 counts the "
       "leaf only for what is not a plain file, 13 and 14 always, and the refusal is ER_PERM",
       0 <= at(xo, "os_path_open_ok(path)") < at(xo, "(key == 5) || (key == 13) || (key == 14)")
       and re.search(r"case XF_OSPATH:\s*\n\s*pub_ospath\(\);", c["op_xfun.c"]) is not None
       and "if (((key == 5) || (key == 13) || (key == 14)) && (edit_os_path_refusal(path, (key == 5) ? edit_leaf_counts(path) : TRUE) != EDIT_NONE))" in xo
       and re.search(r"EDIT_NONE\)\)\s*\{\s*process\.status = ER_PERM;\s*goto pub_ospath_done;", xo) is not None, "")
    ck("C19b ...and the question comes before the delete (unlink / rmdir) and before make_path",
       0 <= at(xo, "edit_os_path_refusal(path,") < at(xo, "rmdir(path)") and at(xo, "edit_os_path_refusal(path,") < at(xo, "make_path(path)"), "")
    # Windows: C20 (SET.SOCKET.MODE SKT$INFO.TRACE asks the edit gates) is dropped - the socket trace log is not built here (owner, 25 Oct 26; keys.h K 10)
    d1 = c["op_dio1.c"]
    cer = func_body(d1, "Private int create_edit_refusal(const char* path)")
    ck("C21 create_edit_refusal: a $internal program passes first, anybody else is asked edit_os_path_refusal with the leaf NOT counted",
       0 <= at(cer, "HDR_INTERNAL") < at(cer, "edit_os_path_refusal(path, FALSE)"), "")
    dh = func_body(d1, "void op_create_dh()")
    ck("C21b op_create_dh asks create_edit_refusal AFTER the name check and BEFORE the file is made (dh_create_file), -ER_PERM with the reason unless ON ERROR",
       0 <= at(dh, "name_len < 1") < at(dh, "create_edit_refusal(path_name)") < at(dh, "dh_create_file(")
       and "k_error(sysmsg(edit_refused_message(edit_kind)))" in dh and "process.status = -ER_PERM" in dh, "")
    t1 = func_body(d1, "void op_create_t1()")
    ck("C21c op_create_t1 asks BEFORE make_path, and only for a name that was given (name_len > 0)",
       0 <= at(t1, "create_edit_refusal(path_name)") < at(t1, "make_path(path_name)") and "(name_len > 0) ? create_edit_refusal(path_name)" in t1, "")
    ot = func_body(d1, "void op_opentemp()")
    ck("C21d OPENTEMP of a NAMED file asks BEFORE the file is made (stat / dh_create_file), the generated name is not asked, and it sets the flag open_file takes",
       0 <= at(ot, "(name_len > 0) && (create_edit_refusal(path) != EDIT_NONE)") < at(ot, "dh_create_file(") and "opentemp_edit_refused = TRUE" in ot, "")
    osig = "Private void open_file(bool map_name)"       # the first one is the prototype
    of = func_body(d1[d1.find(osig) + len(osig):], osig)
    ck("C21e open_file takes the OPENTEMP flag in its declarations (so it cannot survive to the next OPEN), clears it, and answers ER_PERM after the S.63 test",
       0 <= at(of, "bool temp_refused = opentemp_edit_refused;") < at(of, "opentemp_edit_refused = FALSE;")
       < at(of, "net_path_permitted(pathname, TRUE)") < at(of, "if (temp_refused) {")      # Windows: the S.63 test of an open is net_path_permitted / net_vocpath_permitted
       and re.search(r"if \(temp_refused\) \{\s*process\.status = ER_PERM;\s*goto exit_op_open;", of) is not None, "")
    ob = func_body(c["object.c"], "void* load_object(char* name, bool abort_on_error) {")
    ck("C22 load_object clears HDR_INTERNAL from an object that is not from the global catalogue unless the session is the administrator, in this process's "
       "copy, after the header is read and converted and before the object is returned or runs (the owner's .out ruling: a user cannot set the bit by patching a file)",
       re.search(r"if \(\(obj->code\.flags & HDR_INTERNAL\) && !\(flags & OBJ_GLOBAL\) && !MY_ADMIN\(\)\)\s*obj->code\.flags &= ~HDR_INTERNAL;", ob) is not None
       and 0 <= at(ob, "convert_object_header(") < at(ob, "obj->code.flags &= ~HDR_INTERNAL") < ob.rfind("return (void*)(&(obj->code));"), "")

    # ---- B. the BASIC side -------------------------------------------------------------------------------------------------
    lg, cp, ap = c["login"], c["cproc"], c["apisrvr"]
    ck("B1 LOGIN loads the three keys from the register, off unless 'yes'",
       all(re.search(r"kernel\(K\$%s,\s*upcase\(trim\(acc\.rec<ACC\$%s>\)\) = 'YES'\)" % (k, k), lg) for k in ("VOC.EDIT", "BP.EDIT", "DICT.EDIT")), "")
    # 11 Nov 26 (S.213): run.in, and only run.in, now sets the three gates in CPROC - ri.narrow turns on the one its command needs for that command and
    #   revert.account puts back what the session had, from ri.sw<7..9> kept before the run.  That is not LOGTO loading them: no ACC$ field is read, and
    #   outside those two routines and the line that keeps them CPROC still never touches them.
    cp_out = cp
    for lab in ("ri.narrow:", "revert.account:"):
        i = cp_out.find(lab)
        if i >= 0:
            j = cp_out.find("\n   return", i)
            cp_out = cp_out[:i] + cp_out[j:] if j > i else cp_out
    cp_out = re.sub(r"ri\.sw<7> = kernel\(K\$VOC\.EDIT, -1\) ; ri\.sw<8> = kernel\(K\$BP\.EDIT, -1\) ; ri\.sw<9> = kernel\(K\$DICT\.EDIT, -1\)", "", cp_out)
    ck("B2 CPROC (LOGTO) never loads, restores or stacks them: the sign-on account decides (owner, 17 Oct); run.in's narrowing and its revert are the one exception (S.213), and read no register field",
       all(s not in cp_out for s in ("K$VOC.EDIT", "K$BP.EDIT", "K$DICT.EDIT")) and all(s not in cp for s in ("ACC$VOC.EDIT", "ACC$BP.EDIT", "ACC$DICT.EDIT"))
       and "ri.narrow:" in cp and "revert.account:" in cp, "")
    m = re.search(r"if not\(master\.login\.done\) then\s*\n\s*void kernel\(K\$VOC\.EDIT,\s*api\.voc\.grant\)\s*\n\s*void kernel\(K\$BP\.EDIT,\s*api\.bp\.grant\)\s*"
                  r"\n\s*void kernel\(K\$DICT\.EDIT,\s*api\.dict\.grant\)\s*\n\s*end", ap)
    ck("B3 the API server loads them at the FIRST entry only (inside the master.login.done test), not at an SDLogto", m is not None, "")
    ck("B3b ...and that test comes before master.login.done is set", m is not None and at(ap, "master.login.done = @true", m.start()) > m.start(), "")
    ck("B4 each of the three fields starts off for every call of the API server's account routine",
       all(re.search(r"api\.%s\.grant = @false" % k, ap) for k in ("voc", "bp", "dict")), "")
    mo = c["modifya"]
    ck("B5 MODIFY.ACCOUNT has the six words, each through os.set with its own field, and os.set allows them on any account",
       # Windows: Core's main loop reads "case upcase(action) = 'X'", and os.field and os.want are on lines of their own
       all(re.search(r"case upcase\(action\) = '%s'\s*\n\s*os\.field = ACC\$%s\s*\n\s*os\.want\s*= @%s\s*\n\s*gosub os\.set" % (w, f, b), mo)
           for w, f, b in (("VOC-ON", "VOC.EDIT", "true"), ("VOC-OFF", "VOC.EDIT", "false"), ("BP-ON", "BP.EDIT", "true"),
                           ("BP-OFF", "BP.EDIT", "false"), ("DICT-ON", "DICT.EDIT", "true"), ("DICT-OFF", "DICT.EDIT", "false")))
       and "os.field # ACC$VOC.EDIT" in mo and "sysmsg(12414" in mo, "")
    cr, ca2 = c["createa"], c["create_account"]
    ck("B6 CREATE.ACCOUNT takes VOC-ON, BP-ON and DICT-ON, and !create_account writes 'no' explicitly for a user account unless named",
       all(("case upcase(token) = '%s'" % w) in cr for w in ("VOC-ON", "BP-ON", "DICT-ON"))
       and all(re.search(r"acc\.rec<ACC\$%s> = if edit\.%s\.want then 'yes' else 'no'" % (f, k), ca2)
               for f, k in (("VOC.EDIT", "voc"), ("BP.EDIT", "bp"), ("DICT.EDIT", "dict"))), "")
    ai, rs = c["acc_os_info"], c["restorea"]
    ck("B7 the manifest carries edit.voc, edit.bp and edit.dict, and RESTORE.ACCOUNT reads them back into the settings",
       all(("'edit.%s: '" % k) in ai for k in ("voc", "bp", "dict"))
       and all(("'edit.%s'" % k) in rs for k in ("voc", "bp", "dict")) and "settings<CA$VOC.EDIT>" in rs, "")
    ue = c["upgrade_editgates"]
    walk = at(ue, "select acc.f to 12")
    ck("B8 upgrade_editgates tests its marker BEFORE the walk and writes it AFTER the walk, and only when nothing failed",
       0 <= at(ue, "ospath(marker, OS$EXISTS)") < walk < at(ue, "if failed # 0 then") < at(ue, "openseq marker to marker.f"), "")
    ck("B9 ...touches only a USER account (sdu_), and only a field that is BLANK (an explicit no is somebody's decision)",
       # Windows: the sdu_ test folds case (Windows group names)
       "downcase(rec<ACC$GROUP>[1, 4]) = 'sdu_'" in ue and all(("if trim(rec<ACC$%s>) = '' then" % f) in ue for f in ("VOC.EDIT", "BP.EDIT", "DICT.EDIT")), "")
    # Windows: the walks run in upgrade-gates.ps1, which sd.iss's RefreshGates runs elevated at an upgrade (a first install has no user account to
    #   walk).  Linux's "before the register is chowned to sdsys" has no counterpart: Windows has no POSIX owner, the register's ACL is not changed.
    ug, iss = c["upgrade-gates.ps1"], c["sd.iss"]
    og = at(ug, "@('-internal', 'RUN', 'gpl.bp', 'UPGRADE_GATES', 'NO.PAGE')")
    oe = at(ug, "@('-internal', 'RUN', 'gpl.bp', 'UPGRADE_EDITGATES', 'NO.PAGE')")
    ck("B10 the installer runs upgrade_editgates elevated after upgrade_gates (upgrade-gates.ps1, from sd.iss's RefreshGates)",
       0 <= og < oe and ("upgrade-gates.ps1') + '" + '" -AppDir "') in iss and "GatesMsg := RefreshGates;" in iss, "%d %d" % (og, oe))
    ck("B11 ...and says COMPLETE is what it waits for, as for the other walks",
       "$ev = Get-EditGatesVerdict $e.Text" in ug and "if (-not $ev.Complete) {" in ug
       and re.search(r"function Get-EditGatesVerdict\(\[string\] \$Text\) \{\s*\n\s*\$complete = \$Text -match '\(\?m\)\^\\s\*COMPLETE\\s\*\$'", ug) is not None, "")
    # Windows: B12 (check-storewriters lists upgrade_editgates as an install-run writer) is dropped - that guard tests Linux's euid 0 around a
    #   write to a root-owned store; Windows has no euid, and upgrade-gates.ps1 is run elevated by the installer (B10).
    ck("B13 the installer gives the installing user's account the three words (attach-account.ps1 -OpenGates: MODIFY.ACCOUNT with $GateWords)",
       re.search(r"\$GateWords = @\([^)\n]*'voc-on', 'bp-on', 'dict-on'", c["attach-account.ps1"]) is not None
       and "Invoke-Sd (@('-internal', 'MODIFY.ACCOUNT', $Account) + $GateWords)" in c["attach-account.ps1"], "")

    # ---- G. the programs that must ask ---------------------------------------------------------------------------------------
    eg = c["edit_guard"]
    ck("G1 !edit_guard is an internal function that asks the kernel by the pathname of the open file and is the administrator's pass",
       "$internal" in eg and "$catalog !edit_guard" in eg and "fileinfo(f, FL$PATH)" in eg and "kernel(K$EDIT.OK, p)" in eg
       and "kernel(K$EDIT.KIND, p)" in eg and "K$ADMINISTRATOR" in eg, "")
    asks = {"clearfl": 1, "delete": 1, "copy": 2, "cname": 1, "ed": 4, "edit": 1}
    for prog, n in asks.items():
        have = len(re.findall(r"\bedit_guard\(", c[prog])) - len(re.findall(r"deffun\s+edit_guard", c[prog]))
        ck("G2 %s asks edit_guard at least %d time(s) and declares it" % (prog, n), have >= n and "deffun edit_guard" in c[prog], "asks=%d" % have)
    ck("G2b COPY asks about the source when it moves records out (DELETING)",
       re.search(r"if deleting then\s*\n\s*if not\(edit_guard\(src\.file\)\)", c["copy"]) is not None, "")
    ck("G3 CNAME of a FILE asks the kernel for the old path and the new name (a rename cannot take a program file out of its name)",
       "kernel(K$EDIT.OK, ek.path)" in c["cname"] and "ek.path = rec<2>" in c["cname"] and "ek.path = new.file.name" in c["cname"], "")
    ck("G4 DELETE.FILE asks for the data part, and for a dictionary deleted on its own, and the ask is a subroutine at the END of the program",
       c["deletef"].count("gosub edit.check.path") == 2 and at(c["deletef"], "edit.check.path:") > at(c["deletef"], "delete.dict:"), "")
    ide = c["ide"]
    # 28 Oct 26 (the editor merge, stage B): the IDE has more callers of edit.check now (a new record named on the command line, CREATING.SEQKEY), so the count
    #   alone no longer proves that the save and the copy ask: each is held by its own order, from its open of the file to its write
    ide_sv = ide[ide.find("\nsave.one:"):ide.find("\nname.untitled:")]
    ide_wa = ide[ide.find("\ndo.writeas:"):ide.find("\ndo.open:")]
    ck("G7 IDE asks before it saves and before it writes a copy (edit.check, after the file is open and before the write; the reason goes to msg and to a box, not DISPLAY)",
       ide.count("gosub edit.check") >= 2 and "msg = edit_msg(edit.kind)" in ide and "$include syscom keys.h" in ide
       and 0 < at(ide_sv, "gosub edit.check") < at(ide_sv, "write sv.out on fv") and at(ide_sv, "open sv.dict, bn<sv.i> to fv") < at(ide_sv, "gosub edit.check")
       and 0 < at(ide_wa, "open wa.file to fv") < at(ide_wa, "gosub edit.check") < at(ide_wa, "write wa.text on fv"), "")
    inm = c["ide_name"]
    ck("G7b the IDE's name form (new record, first save, save as, write a copy) asks the kernel by the pathname of the OPEN file and says the reason in the form",
       "kernel(K$EDIT.OK, ep)" in inm and "edit_msg(kernel(K$EDIT.KIND, ep))" in inm and "fileinfo(fv, FL$PATH)" in inm and "$include syscom keys.h" in inm
       and "$include int$keys.h" in inm and "$internal" in inm, "")
    ce = c["ced_edit"]
    ck("G8 CED asks before it writes a record, and includes the header that defines FL$PATH",
       "kernel(K$EDIT.OK, edit.p)" in ce and "$include syscom keys.h" in ce, "")
    ck("G8b CED asks only for a record of a FILE: !CED() on a variable has no id and no file path, and the kernel refuses a null path by design",
       re.search(r"if id # '' then\s*\n\s+edit\.p = fileinfo\(fv, FL\$PATH\)\s*\n\s+if not\(kernel\(K\$EDIT\.OK, edit\.p\)\) then", ce) is not None, "")
    for prog in ("basic", "catalog", "delcat", "decat"):
        cc = c[prog]
        first_parse = at(cc, '"!PARSER"') if prog != "basic" else at(cc, "num.programs = 0")
        gate = at(cc, "kernel(K$BP.EDIT, -1)")
        ck("G9 %s refuses a session without bp.edit (the administrator passes) before it does anything" % prog,
           0 <= gate and "kernel(K$ADMINISTRATOR, -1)" in cc and "sysmsg(12413)" in cc and (first_parse < 0 or gate < first_parse), "")
    ck("G10 !OSCOPY and !IOSCOPY refuse a copy INTO a guarded path (the target only)",
       "kernel(K$EDIT.OS.OK, target)" in c["_oscopy"] and "kernel(K$EDIT.OS.OK, target)" in c["_ioscopy"], "")

    # ---- G2. S.64 part 2: the $internal verbs that write, delete or clear a record of a file the USER names ------------------------
    for prog, var, open_text, sinks in GUARD_TABLE:
        cc = c[prog]
        o = at(cc, open_text)
        g_at = at(cc, "if not(edit_guard(%s)) then" % var)
        sink_at = [at(cc, s) for s in sinks]
        ck("G11 %s asks edit_guard(%s) after the open and before %s" % (prog, var, " / ".join(sinks)),
           "deffun edit_guard(f) calling '!edit_guard'" in cc and 0 <= o < g_at and all(0 <= g_at < s for s in sink_at),
           "open=%d guard=%d sinks=%r" % (o, g_at, sink_at))
        form = (r"if not\(edit_guard\(%s\)\) then\s*\n\s*@system\.return\.code = -ER\$PERM\s*\n(\s*clearselect\s*\n)?\s*(stop|goto exit\.qproc)\s*\n\s*end"
                % re.escape(var))
        ck("G11b %s: a refusal sets the return code -ER$PERM and stops (edit_guard has said why)" % prog, re.search(form, cc) is not None, "")
    cl_ = c["copylst"]
    ck("G12 COPY.LIST asks the target when it copies to a file, and the source only with DELETING (CRT and LPTR change no file)",
       re.search(r"if to\.file then\s*\n\s*if not\(edit_guard\(tgt\.file\)\)", cl_) is not None
       and re.search(r"if deleting then\s*\n\s*if not\(edit_guard\(src\.file\)\)", cl_) is not None, "")
    ck("G12b GET.LIST asks only with DELETING (a plain GET.LIST reads), and SET.TRIGGER only when a second argument asks for a change",
       re.search(r"if deleting then\s*\n\s*if not\(edit_guard\(saved\.lists\.file\)\)", c["getlist"]) is not None
       and re.search(r"if token\.type # PARSER\$END then\s*\n\s*if not\(edit_guard\(fu\)\)", c["settrig"]) is not None, "")
    st = c["settrig"]
    ck("G12c SET.TRIGGER asks before the call name is validated and before the exclusive-access test names the holders",
       0 <= at(st, "if not(edit_guard(fu)) then") < at(st, "gosub validate.call.name"), "")
    cdp = c["cd"]
    ck("G13 CD asks only for the DATA form (a data file read as dictionary items): the flag is set in the DATA case and the ask tests it",
       "data.form = @false" in cdp and "data.form = @true" in cdp and re.search(r"if data\.form then\s*\n\s*if not\(edit_guard\(dict\.f\)\)", cdp) is not None
       and 0 <= at(cdp, "data.form = @false") < at(cdp, "data.form = @true"), "")
    gn = c["generate"]
    ck("G14 GENERATE asks about the dictionary BEFORE its questions are put, and about the include target before either OPENSEQ overwrite",
       0 <= at(gn, "if not(edit_guard(dict.file)) then") < at(gn, "display sysmsg(6862)")
       and 0 <= at(gn, "if not(edit_guard(target.f)) then") < at(gn, "openseq file.name, record.name overwrite")
       and gn.count("openseq file.name, record.name overwrite") >= 2, "")
    mp = c["mapcat"]
    ck("G15 MAP FILE asks inside the 'file name given' block, so plain MAP and the default $map are not asked",
       0 <= at(mp, "if file.name # '' then") < at(mp, "if not(edit_guard(map.f)) then"), "")
    fd = c["fixdir"]
    ck("G16 FIXDIR asks after its 'is not a directory file' test (a VOC and a dictionary stop there) and before the select",
       0 <= at(fd, "sysmsg(12076") < at(fd, "if not(edit_guard(f)) then") < at(fd, "select f to 11"), "")
    sv = c["spview"]
    di = sv[at(sv, "delete.item:"):]
    di = di[:di.find("show.data.page:")]
    ck("G17 SP.VIEW asks the KERNEL (not edit_guard: it would DISPLAY over the page) at the top of delete.item, before the Y/N question, the lock and the delete",
       "kernel(K$EDIT.OK, edit.p)" in di and "edit_msg(edit.kind)" in di and "edit_guard" not in sv
       and 0 <= at(di, "edit.p = fileinfo(data.f, FL$PATH)") < at(di, "kernel(K$EDIT.OK, edit.p)") < at(di, "sysmsg(12110") < at(di, "readvu dummy")
       < at(di, "delete data.f, item.name") and "$include keys.h" in sv and "$include int$keys.h" in sv, "")
    qp = c["qproc"]
    ck("G18 REFORMAT / SREFORMAT: check.reformat.target is gosub'd after the TO clause's open and after the Output file: prompt, and asks edit_guard(reformat.f)",
       qp.count("gosub check.reformat.target") == 2 and "if edit_guard(reformat.f) then return" in qp
       and re.search(r"check\.reformat\.target:\s*\n\s*if edit_guard\(reformat\.f\) then return\s*\n\s*@system\.return\.code = -ER\$PERM\s*\n\s*goto exit\.qproc", qp) is not None
       and "deffun edit_guard(f) calling '!edit_guard'" in qp, "")
    ck("G18b PAGESEQ asks edit_guard(pageseq.f) BEFORE the control record is read and locked",
       0 <= at(qp, "if not(edit_guard(pageseq.f)) then") < at(qp, "readvu pageseq from pageseq.f"), "")
    ck("G19 a delimited report TO a pathname asks the S.63 gate then the edit gates, BEFORE openseq truncates or creates it, and names the kind of the first path "
       "component that explains the refusal (edit.os.message)",
       0 <= at(qp, "if not(kernel(K$PATH.OK, csv.pathname)) then") < at(qp, "if not(kernel(K$EDIT.OS.OK, csv.pathname)) then") < at(qp, "openseq csv.pathname to csv.f")
       and "gosub edit.os.message" in qp and "kernel(K$EDIT.KIND, field(eom.path, '/', eom.i))" in qp and "eom.msg = 12415" in qp, "")
    cm = c["como"]
    ck("G20 COMO ON asks K$EDIT.OS.OK on the pathname the COMO statement will be given, BEFORE the statement, and closes the $COMO file it opened on a refusal",
       0 <= at(cm, "if not(kernel(K$EDIT.OS.OK, target.dir : @ds : mapped.name)) then") < at(cm, "como (if append then")
       and "if fileinfo(como.file, FL$OPEN) then close como.file" in cm and "gosub edit.os.message" in cm, "")
    cpc = c["cproc"]
    ck("G21 CPROC's .S asks (voc.edit.ask) only when the VOC record EXISTS, before the Overwrite question, and releases the id; .D asks before its first readu; "
       "a NEW sentence is not asked",
       cpc.count("gosub voc.edit.ask") == 2 and "voc.edit.ok = kernel(K$EDIT.OK, fileinfo(voc, FL$PATH))" in cpc
       and re.search(r"readvu voc\.rec from voc, arg1, 0 then\s*\n\s*gosub voc\.edit\.ask\s*\n\s*if not\(voc\.edit\.ok\) then\s*\n\s*release voc, arg1\s*\n\s*goto exit\.stack\.command\s*\n\s*end\s*\n\s*loop\s*\n\s*display sysmsg\(5045", cpc) is not None
       and re.search(r"del command\.stack<n>\s*\n\s*end else\s*\n\s*gosub voc\.edit\.ask\s*\n\s*if not\(voc\.edit\.ok\) then goto exit\.stack\.command\s*\n\s*at\.command = trimf\(trimb\(at\.command\)\)\s*\n\s*readu voc\.rec", cpc) is not None, "")
    cf = c["createf"]
    ck("G22 CREATE.FILE on an EXISTING pointer changes none of its data paths (28 Oct 26, multifiles gone: no conversion, so no edit.check.existing, no Convert question, nothing written to field 4)",
       "edit.check.existing" not in cf and "sysmsg(6195" not in cf
       and "voc.rec<4" not in cf and "voc.rec<2,-1>" not in cf, "")
    wl, mk = c["writelist"], c["_mksavedlists"]
    ck("G23 !WRITELIST makes the $savedlists pointer through !MKSAVEDLISTS (so a session without voc.edit can still save a list) and no longer writes it itself",
       "call !mksavedlists(mk.err)" in wl and "write 'F'" not in wl and "'$svlists'" not in wl, "")
    ck("G24 !MKSAVEDLISTS is $internal, takes no name or path, re-reads $savedlists and returns WITHOUT writing when it exists, and writes one fixed record",
       "$internal" in mk and "$catalog !mksavedlists" in mk and "subroutine mksavedlists(err)" in mk
       and 0 <= at(mk, "read s from @voc, '$savedlists' then") < at(mk, "create.file '$svlists' dynamic")
       and re.search(r"read s from @voc, '\$savedlists' then\s*\n\s*release @voc, '\$savedlists'\s*\n\s*return\s*\n\s*end", mk) is not None
       and mk.count("write ") == 1 and "write 'F' : @fm : '$svlists' to @voc, '$savedlists'" in mk, "")
    ap2 = c["apisrvr"]
    # 21 Oct 26 (S.73 item 3): eight calls - the six and two more: the file administration verb (every operation but the report) and FCONTROL (every key but the question)
    ck("G25 the API server's file operations ask check.edit BEFORE the statement: write, writeu, delete, deleteu, clearfile, the SEQKEY writes, the file administration verb and FCONTROL",
       ap2.count("gosub check.edit") == 8 and all(
           0 <= at(ap2, lbl) < at(ap2, "gosub check.edit", at(ap2, lbl)) < at(ap2, stmt, at(ap2, lbl))
           for lbl, stmt in (("vb.write:", "write cmnd["), ("vb.writeu:", "writeu cmnd["), ("vb.delete:", "delete files(fno), id"),
                              ("vb.deleteu:", "deleteu files(fno), id"), ("vb.clearfile:", "clearfile files(fno)"),
                              ("writeseqkey.common:", "writeu wk.data to files(fno) creating.seqkey"),
                              ("vb.fileadmin:", "execute fa.cmd capturing response"), ("vb.fcontrol:", "response = fcontrol(files(fno), fc.key)")))
       and len(re.findall(r"gosub check\.edit[^\n]*\n\s*if err then return", ap2)) == 8 and "clearfile files(i)" not in ap2, "")
    ck("G25b check.edit refuses an unreadable pathname (12415) and a file the session may not change (K$EDIT.OK, kind by K$EDIT.KIND), as an error",
       # Windows: the routine's lines are indented
       re.search(r"check\.edit:\s*\n\s*err = @true\s*\n\s*ed\.path = fileinfo\(files\(fno\), FL\$PATH\)\s*\n\s*if ed\.path = '' then", ap2) is not None
       and "sysmsg(12415)" in ap2 and "kernel(K$EDIT.OK, ed.path)" in ap2 and "edit_msg(ed.kind)" in ap2, "")
    ck("G25c SDOpenSeq opens READ ONLY (os.m = 1) when the pathname or the file is one the session may not change",
       "os.edit.ok = kernel(K$EDIT.OS.OK, os.name)" in ap2 and "os.edit.ok = kernel(K$EDIT.OK, fileinfo(os.tf, FL$PATH))" in ap2
       and 0 <= at(ap2, "os.m = 0") < at(ap2, "if not(os.edit.ok) then os.m = 1") < at(ap2, "case os.path and os.m = 0"), "")
    # Windows: Linux loads the three gates ON for the OS user sdsys entering sdsys, because its API session carries no administrator flag.  Here the
    #   API server admits SDSYS to sdsys ONLY as the local, ELEVATED Windows account SDSYS (K$ADMINISTRATOR), and the administrator passes every
    #   edit test (C2, C12, C13, G9), so the grant is the admission rule itself; anyone else is refused before the gates are loaded.
    ck("G25d SDSYS in its own account over the API passes the three gates: it is admitted only when the session is the administrator, and the entry "
       "rule is asked before the first-entry load of the register's own gates",
       "ent.member = local.session and (ent.who = 'SDSYS') and kernel(K$ADMINISTRATOR, -1)" in ap2
       and re.search(r"if upcase\(ent\.name\) = 'SDSYS' then\s*\n\s*ent\.who = upcase\(kernel\(K\$USERNAME, 0\)\)", ap2) is not None
       and 0 <= at(ap2, "ent.member = local.session and (ent.who = 'SDSYS')") < at(ap2, "void kernel(K$VOC.EDIT,  api.voc.grant)"), "")

    # ---- M. the messages ------------------------------------------------------------------------------------------------------
    texts = {}
    for n in range(12410, 12416):
        p = os.path.join(messages_dir, str(n))
        texts[n] = open(p).read().strip() if os.path.exists(p) else None
    ck("M1 messages 12410 to 12415 exist", all(texts.values()), repr([n for n, t in texts.items() if not t]))
    ck("M2 each refusal names its gate and the word that gives it (voc-on, dict-on, bp-on)",
       "voc.edit" in (texts[12410] or "") and "modify.account" in (texts[12410] or "") and "voc-on" in (texts[12410] or "")
       and "dict.edit" in (texts[12411] or "") and "dict-on" in (texts[12411] or "")
       and "bp.edit" in (texts[12412] or "") and "bp-on" in (texts[12412] or "") and "bp.edit" in (texts[12413] or ""), "")
    ck("M3 12414 takes the account and the three states", "%1" in (texts[12414] or "") and "%4" in (texts[12414] or ""), "")
    return rows


def load():
    srcs = {}
    for name, path in FILES.items():
        if not os.path.exists(path):
            print("test-editgates-units: CANNOT RUN - %s is missing" % path)
            sys.exit(2)
        with open(path, encoding="utf-8", errors="replace") as f:
            srcs[name] = f.read()
    return srcs


def mutate(srcs, name, old, new, count=1):
    s = dict(srcs)
    if callable(old):                       # a mutant made by a function of the source text (raises KeyError when it does not apply)
        s[name] = old(s[name])
        return s
    if old not in s[name]:
        raise KeyError("mutant text not in %s: %r" % (name, old[:70]))
    s[name] = s[name].replace(old, new, count)
    return s


MUTANTS = [
    ("edit_refusal forgets that a $internal program passes", "op_dio3.c", "  if (process.program.flags & HDR_INTERNAL)\n    return EDIT_NONE;\n  if (MY_ADMIN())\n    return EDIT_NONE;\n\n  /* The file table is shared memory", "  if (MY_ADMIN())\n    return EDIT_NONE;\n\n  /* The file table is shared memory"),
    ("op_write does not ask before the SEQKEY id is taken", "op_dio3.c", "Before anything is taken from the file. */\n    int edit_kind = edit_refusal(fvar);", "Before anything is taken from the file. */\n    int edit_kind = EDIT_NONE;"),     # Windows: Core's comment
    ("op_writev asks nothing before the recursive pcode", "op_dio3.c", "    edit_kind = edit_refusal(wv_fvar->data.fvar);", "    edit_kind = EDIT_NONE;"),
    ("op_clrfile asks after the lock", "op_dio3.c", "    int edit_kind = edit_refusal(fvar); /* 17 Oct 26 S.64: the edit gates */\n\n    if (edit_kind != EDIT_NONE) {\n      if (!(op_flags & P_ON_ERROR))\n        k_error(sysmsg(EDIT_REFUSED_MSG(edit_kind)));\n      /* ON ERROR", "    int edit_kind = EDIT_NONE; /* 17 Oct 26 S.64: the edit gates */\n\n    if (edit_kind != EDIT_NONE) {\n      if (!(op_flags & P_ON_ERROR))\n        k_error(sysmsg(EDIT_REFUSED_MSG(edit_kind)));\n      /* ON ERROR"),
    ("edit_permitted looks at the gate before the administrator", "op_sh.c", "bool edit_permitted(int kind) {\n  if (MY_ADMIN())\n    return TRUE;\n  switch (kind) {\n    case EDIT_VOC:\n      return MY_GATE(UG_VOC_EDIT);", "bool edit_permitted(int kind) {\n  switch (kind) {\n    case EDIT_VOC:\n      return MY_GATE(UG_VOC_EDIT);"),
    ("a bp.out file is no longer a program file", "op_sh.c", '  if ((n == 6) && (strncasecmp(last, "bp.out", 6) == 0))\n    return EDIT_PROG;\n', ""),
    ("K_EDIT_OK answers 1 for an empty pathname", "op_kernel.c", "edit_name[0] = '\\0';\n      result.data.value = 0;\n", "edit_name[0] = '\\0';\n      result.data.value = 1;\n"),
    ("the gate keys can be set from a user program", "op_kernel.c", "      if (n >= 0) {\n        if (process.program.flags & HDR_INTERNAL)\n          SET_MY_GATE(edit_bit, n > 0);", "      if (n >= 0) {\n        if (1)\n          SET_MY_GATE(edit_bit, n > 0);"),
    ("OPENSEQ no longer makes a blocked file read only", "op_seqio.c", "      if ((op_flags & P_READONLY) || access(fullpathname, 2) || edit_blocked) {", "      if ((op_flags & P_READONLY) || access(fullpathname, 2)) {"),
    ("DELETESEQ asks after the file is looked at", "op_seqio.c", "  if (!(process.program.flags & HDR_INTERNAL) && (edit_os_path_refusal(file_name, FALSE) != EDIT_NONE)) {\n    process.status = ER_PERM;\n    goto exit_op_delseq;\n  }\n\n  /* Check file exists */\n\n  if (stat(file_name, &stat_buf) != 0) {\n    process.status = ER_FNF;\n    goto exit_op_delseq;\n  }", "  /* Check file exists */\n\n  if (stat(file_name, &stat_buf) != 0) {\n    process.status = ER_FNF;\n    goto exit_op_delseq;\n  }\n\n  if (!(process.program.flags & HDR_INTERNAL) && (edit_os_path_refusal(file_name, FALSE) != EDIT_NONE)) {\n    process.status = ER_PERM;\n    goto exit_op_delseq;\n  }"),
    ("a print file is not looked at", "to_file.c", "    if (edit_os_path_refusal(fn, FALSE) != EDIT_NONE) {", "    if (0) {"),
    ("LOGTO reloads the VOC gate", "cproc", "   void kernel(K$SD.ACCOUNTS, upcase(trim(acc.record<ACC$SD.ACCOUNTS>)) = 'YES')", "   void kernel(K$VOC.EDIT, upcase(trim(acc.record<ACC$VOC.EDIT>)) = 'YES')\n   void kernel(K$SD.ACCOUNTS, upcase(trim(acc.record<ACC$SD.ACCOUNTS>)) = 'YES')"),
    ("LOGIN forgets the bp gate", "login", "   void kernel(K$BP.EDIT,   upcase(trim(acc.rec<ACC$BP.EDIT>)) = 'YES')\n", ""),
    ("the API server reloads at every SDLogto", "apisrvr", "if not(master.login.done) then\n   void kernel(K$VOC.EDIT,  api.voc.grant)", "if 1 then\n   void kernel(K$VOC.EDIT,  api.voc.grant)"),
    ("MODIFY.ACCOUNT loses DICT-OFF", "modifya", "case upcase(action) = 'DICT-OFF'", "case upcase(action) = 'DICT-OFFX'"),     # Windows: Core's word order
    ("a new user account is written with the voc field blank", "create_account", "     acc.rec<ACC$VOC.EDIT> = if edit.voc.want then 'yes' else 'no'\n", ""),
    ("the manifest drops edit.bp", "acc_os_info", "info<-1> = 'edit.bp: ' : (if upcase(trim(acc.rec<ACC$BP.EDIT>)) = 'YES' then 1 else 0)", "null"),     # Windows: Core's spacing
    ("upgrade_editgates writes its marker before the walk", "upgrade_editgates", "   changed = 0\n   kept = 0", "   openseq marker to marker.f then\n      weofseq marker.f\n   end else\n      create marker.f else null\n   end\n   changed = 0\n   kept = 0"),
    ("upgrade_editgates overwrites an explicit no", "upgrade_editgates", "if trim(rec<ACC$VOC.EDIT>) = '' then rec<ACC$VOC.EDIT> = 'yes'", "rec<ACC$VOC.EDIT> = 'yes'"),
    ("the installer stops running upgrade_editgates", "upgrade-gates.ps1", "'gpl.bp', 'UPGRADE_EDITGATES', 'NO.PAGE'", "'gpl.bp', 'UPGRADE_NOTHING', 'NO.PAGE'"),     # Windows
    ("the installer stops running upgrade-gates.ps1", "sd.iss", "GatesMsg := RefreshGates;", "GatesMsg := '';"),     # Windows
    ("the edit-gates walk is not held to COMPLETE", "upgrade-gates.ps1", "if (-not $ev.Complete) {", "if ($false) {"),     # Windows
    ("the installing user's account is not given bp-on", "attach-account.ps1", "'voc-on', 'bp-on', 'dict-on'", "'voc-on', 'dict-on'"),     # Windows
    ("ED forgets to ask when it saves", "ed", "   if not(edit_guard(n.file)) then return\n\n   readvu s from n.file, new.record, 0 locked", "   readvu s from n.file, new.record, 0 locked"),
    ("COPY forgets the source of a move", "copy", "   if deleting then\n      if not(edit_guard(src.file)) then", "   if 0 then\n      if not(edit_guard(src.file)) then"),
    ("CNAME forgets the new name", "cname", "      if ek = 1 then ek.path = rec<2> else ek.path = new.file.name", "      if ek = 1 then ek.path = rec<2> else ek.path = ''"),
    ("IDE's write-a-copy forgets to ask at the write", "ide", "   gosub edit.check                  ;* asked again at the write, as save.one does: the form's answer is not the gate\n   if not(edit.ok) then\n      rf.text = msg\n      gosub refuse.box\n      return\n   end\n   * under the record's lock", "   * under the record's lock"),
    ("IDE's save forgets to ask (stage B)", "ide", "   gosub edit.check                  ;* 17 Oct 26 dm - S.64; the dictionary's own path", "   null                  ;* 17 Oct 26 dm - S.64; the dictionary's own path"),
    ("IDE's name form forgets to ask", "ide_name", "            if kernel(K$EDIT.OK, ep) then", "            if 1 then"),
    ("CED saves without asking", "ced_edit", "   if not(kernel(K$EDIT.OK, edit.p)) then", "   if 0 then"),
    ("CED asks about a variable too (no id, no file)", "ced_edit", "   if id # '' then\n      edit.p = fileinfo(fv, FL$PATH)", "   if 1 then\n      edit.p = fileinfo(fv, FL$PATH)"),
    ("BASIC compiles for anybody", "basic", "   if not(kernel(K$ADMINISTRATOR, -1)) and not(kernel(K$BP.EDIT, -1)) then", "   if 0 then"),
    ("CATALOG forgets the gate", "catalog", "   if not(kernel(K$ADMINISTRATOR, -1)) and not(kernel(K$BP.EDIT, -1)) then", "   if 0 then"),
    ("DELETE.FILE forgets a dictionary on its own", "deletef", "         if not(delete.data) then\n            ef.path = dict.path\n            gosub edit.check.path\n         end", ""),
    ("!OSCOPY forgets the target", "_oscopy", "end else if not(kernel(K$EDIT.OS.OK, target)) then", "end else if 0 then"),
    ("message 12410 stops naming the word", "MESSAGE:12410", "voc-on", "voc-add"),
    # ---- S.64 part 2: the C routes ----
    # Windows: OSPATH is pub_ospath() in op_dio2.c; the two socket trace mutants are dropped with C20
    ("OSPATH keys 5, 13 and 14 are not asked", "op_dio2.c", "if (((key == 5) || (key == 13) || (key == 14)) && (edit_os_path_refusal(", "if (0 && (edit_os_path_refusal("),
    ("OSPATH makes a directory with the leaf not counted", "op_dio2.c", ": TRUE) != EDIT_NONE)) {\n        process.status = ER_PERM;", ": FALSE) != EDIT_NONE)) {\n        process.status = ER_PERM;"),
    ("OSPATH delete counts a plain file called x.bp", "op_dio2.c", "(key == 5) ? edit_leaf_counts(path) : TRUE", "TRUE"),
    ("OSPATH() of a user program no longer reaches pub_ospath", "op_xfun.c", "      pub_ospath();", "      null_ospath();"),
    ("an object of a local catalogue keeps its own internal bit", "object.c", "!(flags & OBJ_GLOBAL) && !MY_ADMIN())", "0 && !MY_ADMIN())"),
    ("the administrator loses the internal bit too", "object.c", "&& !MY_ADMIN())\n    obj->code.flags", ")\n    obj->code.flags"),
    ("CREATE.FILE DYNAMIC is not asked", "op_dio1.c", "edit_kind = create_edit_refusal(path_name);", "edit_kind = EDIT_NONE;"),
    ("CREATE.FILE DIRECTORY is not asked", "op_dio1.c", "? create_edit_refusal(path_name) : EDIT_NONE", "? EDIT_NONE : EDIT_NONE"),
    ("create_edit_refusal asks a $internal program (createf would be refused)", "op_dio1.c", "  if (process.program.flags & HDR_INTERNAL)\n    return EDIT_NONE;\n  return edit_os_path_refusal(path, FALSE);", "  return edit_os_path_refusal(path, FALSE);"),
    ("create_edit_refusal counts the name being made", "op_dio1.c", "return edit_os_path_refusal(path, FALSE);", "return edit_os_path_refusal(path, TRUE);"),
    ("OPENTEMP of a named file is not asked", "op_dio1.c", "(create_edit_refusal(path) != EDIT_NONE)", "(0)"),
    ("OPENTEMP's flag is never taken by open_file", "op_dio1.c", "bool temp_refused = opentemp_edit_refused;", "bool temp_refused = FALSE;"),
    ("OPENSEQ counts the record name (a record called sample.bp is refused)", "op_seqio.c", "edit_blocked = (edit_os_path_refusal(fullpathname, FALSE)", "edit_blocked = (edit_os_path_refusal(fullpathname, TRUE)"),
    ("a print file counts its own name", "to_file.c", "if (edit_os_path_refusal(fn, FALSE) != EDIT_NONE) {", "if (edit_os_path_refusal(fn, TRUE) != EDIT_NONE) {"),
    ("K_EDIT_OS_OK never counts the target's name (a copy INTO bp is allowed)", "op_kernel.c", "edit_os_path_refusal(edit_os_name, edit_leaf_counts(edit_os_name))", "edit_os_path_refusal(edit_os_name, FALSE)"),
    ("the private catalogue is no longer a program file (edit_kind_of_path)", "op_sh.c", "if ((kind == EDIT_NONE) && path_is_private_catalogue(path))", "if (0)"),
    ("the private catalogue is found by the bare name", "op_sh.c", "  return catalogue_position(folded) == 1;", "  return TRUE;"),     # Windows: folded
    ("a path that cannot be placed is taken as NOT the catalogue", "op_sh.c", "    return TRUE;\n  return catalogue_position(folded) == 1;", "    return FALSE;\n  return catalogue_position(folded) == 1;"),
    ("an OS path below the private catalogue is not refused", "op_sh.c", "((cat_pos == 2) || ((cat_pos == 1) && include_leaf)) && !edit_permitted(EDIT_PROG)", "0"),
    ("edit_os_path_refusal ignores include_leaf", "op_sh.c", "(include_leaf || (*more != '\\0'))", "1"),
    ("edit_leaf_counts counts a plain file", "op_sh.c", "return !S_ISREG(sb.st_mode);", "return TRUE;"),
    # ---- S.64 part 2: the BASIC verbs ----
    ("SP.VIEW deletes without asking", "spview", "if not(kernel(K$EDIT.OK, edit.p)) then", "if 0 then"),
    ("REFORMAT's check forgets edit_guard", "qproc", "if edit_guard(reformat.f) then return", "return"),
    ("a delimited report TO a path forgets the edit gates", "qproc", "if not(kernel(K$EDIT.OS.OK, csv.pathname)) then", "if 0 then"),
    ("a delimited report TO a path forgets the OS-access gate", "qproc", "if not(kernel(K$PATH.OK, csv.pathname)) then", "if 0 then"),
    ("COMO ON forgets the edit gates", "como", "if not(kernel(K$EDIT.OS.OK, target.dir : @ds : mapped.name)) then", "if 0 then"),
    (".S asks of a record that does not exist yet too", "cproc", "readvu voc.rec from voc, arg1, 0 then\n", "readvu voc.rec from voc, arg1, 0 else\n"),
    (".S and .D never get the answer", "cproc", "voc.edit.ok = kernel(K$EDIT.OK, fileinfo(voc, FL$PATH))", "voc.edit.ok = 1"),
    (".S leaves the VOC record locked on a refusal", "cproc", "release voc, arg1\n               goto exit.stack.command", "goto exit.stack.command"),
    ("!WRITELIST writes the pointer itself again", "writelist", "call !mksavedlists(mk.err)", "write 'F':@fm:'$svlists' to @voc, '$savedlists'"),
    ("!MKSAVEDLISTS replaces an entry that is there", "_mksavedlists", "read s from @voc, '$savedlists' then\n      release @voc, '$savedlists'\n      return\n   end\n", ""),
    # Windows: Core's comments on these lines
    ("the API server writes without asking", "apisrvr", "gosub check.edit   ;* 23 Oct 26, Linux b6186cc (S.64 part 2): this program is $internal", "null   ;* 23 Oct 26, Linux b6186cc (S.64 part 2): this program is $internal"),
    ("the API server clears the wrong file again", "apisrvr", "clearfile files(fno)   ;* 23 Oct 26, Linux b6186cc: was files(i)", "clearfile files(i)   ;* 23 Oct 26, Linux b6186cc: was files(i)"),
    ("SDOpenSeq opens a guarded file read and write", "apisrvr", "if not(os.edit.ok) then os.m = 1", "null"),
    ("SDSYS over the API is admitted without being the administrator", "apisrvr", "(ent.who = 'SDSYS') and kernel(K$ADMINISTRATOR, -1)", "(ent.who = 'SDSYS')"),     # Windows: G25d
    ("CD asks for the DICT form too, or never", "cd", "data.form = @true", "data.form = @false"),
    ("SET.TRIGGER asks for the report form too", "settrig", "if token.type # PARSER$END then\n      if not(edit_guard(fu)) then", "if 1 then\n      if not(edit_guard(fu)) then"),
    ("GET.LIST asks for a plain read", "getlist", "if deleting then\n      if not(edit_guard(saved.lists.file)) then", "if 1 then\n      if not(edit_guard(saved.lists.file)) then"),
    ("COPY.LIST forgets the source of DELETING", "copylst", "if deleting then\n         if not(edit_guard(src.file)) then", "if 0 then\n         if not(edit_guard(src.file)) then"),
]


def guard_block(var):
    return re.compile(r"[ \t]*if not\(edit_guard\(%s\)\) then[ \t]*\n[ \t]*@system\.return\.code = -ER\$PERM[ \t]*\n(?:[ \t]*clearselect[ \t]*\n)?"
                      r"[ \t]*(?:stop|goto exit\.qproc)[ \t]*\n[ \t]*end[ \t]*\n" % re.escape(var))


def late_guard(var, sink):
    """A mutant that asks AFTER the first SINK instead of before it: the first guard block is cut out and put back after the sink's line."""
    def f(text):
        m = guard_block(var).search(text)
        if m is None:
            raise KeyError("no guard block for %s" % var)
        block = m.group(0)
        rest = text[:m.start()] + text[m.end():]
        i = rest.find(sink)
        if i < 0:
            raise KeyError("no sink %r" % sink)
        eol = rest.find("\n", i) + 1
        return rest[:eol] + block + rest[eol:]
    return f


for _prog, _var, _open, _sinks in GUARD_TABLE:
    MUTANTS.append(("%s never asks edit_guard(%s)" % (_prog, _var), _prog, "if not(edit_guard(%s)) then" % _var, "if 0 then"))
    # asked after the first thing it must precede (the select, the read, the lock, the write)
    MUTANTS.append(("%s asks edit_guard(%s) only after %s" % (_prog, _var, _sinks[0]), _prog, late_guard(_var, _sinks[0]), None))


def run(srcs, messages_dir):
    rows = checks(srcs, messages_dir)
    return rows


def main():
    srcs = load()
    messages_dir = os.path.join(SDSYS, "messages")
    if "--selftest" in sys.argv:
        base = run(srcs, messages_dir)
        bad = [i for i, ok, d in base if not ok]
        if bad:
            print("test-editgates-units: the unmutated source already fails: %s" % bad)
            return 2
        missed = 0
        for label, name, old, new in MUTANTS:
            if name.startswith("MESSAGE:"):
                mdir = os.path.join(tempfile.gettempdir(), "editgates-msgs-%d" % os.getpid())     # Windows: no /tmp
                os.makedirs(mdir, exist_ok=True)
                for n in range(12410, 12416):
                    with open(os.path.join(messages_dir, str(n))) as f:
                        t = f.read()
                    if str(n) == name.split(":")[1]:
                        t = t.replace(old, new)
                    with open(os.path.join(mdir, str(n)), "w") as f:
                        f.write(t)
                rows = checks(srcs, mdir)
                for n in range(12410, 12416):
                    os.remove(os.path.join(mdir, str(n)))
                os.rmdir(mdir)
            else:
                try:
                    rows = checks(mutate(srcs, name, old, new), messages_dir)
                except KeyError as e:
                    print("  [FAIL] mutant is not applicable: %s (%s)" % (label, e))
                    missed += 1
                    continue
            caught = [i for i, ok, d in rows if not ok]
            if caught:
                print("  [PASS] mutant caught: %s  <- %s" % (label, ", ".join(caught[:3])))
            else:
                print("  [FAIL] MUTANT NOT CAUGHT: %s" % label)
                missed += 1
        print("\ntest-editgates-units --selftest: %d mutants, %d missed" % (len(MUTANTS), missed))
        return 1 if missed else 0
    rows = run(srcs, messages_dir)
    failed = 0
    for i, ok, d in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", i, "" if ok or not d else "   <- " + d))
        failed += 0 if ok else 1
    print("\ntest-editgates-units: %d checks, %d failed" % (len(rows), failed))
    # Windows: Linux's sandbox-editgates.py is not carried; verify-catgate.ps1 runs the catalogue gate on an install
    print("NOT MEASURED HERE: whether a gate refuses anybody.  That is a run on an install (Linux: sandbox-editgates.py; here verify-catgate.ps1, the catalogue gate).")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
