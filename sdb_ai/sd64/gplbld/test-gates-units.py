#!/usr/bin/env python3
"""test-gates-units.py - the per-account OS-access gates (S.63), as invariants read off the source.

  python sdb_ai/sd64/gplbld/test-gates-units.py
  python sdb_ai/sd64/gplbld/test-gates-units.py --selftest
  (13 Nov 26 Windows port - from Linux b1d496df, RELEASE_1.1 254: message ids are Linux's + 1005; "the installer" is gplbld/sd.iss, which
  runs upgrade-gates.ps1 from RefreshGates; the I checks are retargeted there and the M2 cross-check against the Windows tree is dropped,
  because this IS the Windows tree.  Every other change is commented where it is made.)

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.  Written 13 Oct 26.  28 Oct 26: B28 pins SED's PATH: (one open, no upcase retry), two mutants.
19 Oct 26 (integration): the mutant "CREATE.ACCOUNT OS-ON sets the wrong field" is anchored on the OS-ON case line.  1daee9d's `gates=` audit line
added a second `settings<CA$OS.EXECUTE> = 1` ahead of the parse, sub() changes the first occurrence only, and so the mutant changed the audit text and
nothing noticed: 70 of 71 on Dev 2a81059 itself (71 of 71 on both lanes, which lack that commit).

***WHAT THIS IS, AND WHAT IT IS NOT.***  It reads the C and BASIC sources as text, with comments removed, so a gate that
survives only in a comment does not count.  ***IT DOES NOT RUN ANYTHING, SO IT CANNOT SAY THAT THE GATE REFUSES ANYBODY***:
that is sandbox-gates.py (ordinary sessions on a private SD, which refuse, run, and leave a sentinel as evidence) and
witness-accounts.sh (the owner's, with sudo, for CREATE.ACCOUNT and the Linux users and groups the sandbox cannot make) - both
Linux's, neither carried to Windows.
What a text check is for: this code is reached from eleven places - op_sh.c, op_seqio.c, op_dio1.c, op_kernel.c, op_sdext.c,
cproc, login, createa, create_account, modifya, edit - and the invariants that make it a gate are mostly ORDERING (the
refusal before the stack is touched, the path test after fullpath() and before the transaction cache, the load at account
entry before the audit line, the upgrade before the register is chowned).  An edit that moves one still compiles.

***AND THE CHECKS ARE THEMSELVES CHECKED.***  --selftest breaks each invariant in the way an edit plausibly would and
requires some check to notice.  A mutant that nothing catches is reported as a FAILURE of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.abspath(os.path.join(HERE, os.pardir))
SDSYS = os.path.join(SD64, "sdsys")
GPL = os.path.join(SDSYS, "gpl.bp")
GPLSRC = os.path.join(SD64, "gplsrc")

FILES = {
    "op_sh.c": os.path.join(GPLSRC, "op_sh.c"),
    "op_seqio.c": os.path.join(GPLSRC, "op_seqio.c"),
    "op_dio1.c": os.path.join(GPLSRC, "op_dio1.c"),
    "op_kernel.c": os.path.join(GPLSRC, "op_kernel.c"),
    "op_sdext.c": os.path.join(GPLSRC, "op_sdext.c"),
    "op_dio4.c": os.path.join(GPLSRC, "op_dio4.c"),
    "op_dio2.c": os.path.join(GPLSRC, "op_dio2.c"),      # 13 Nov 26 Windows port: containment and the SD.ACCOUNTS walk live here
    "sdpy_session.c": os.path.join(GPLSRC, "sdpy_session.c"),      # 13 Nov 26 Windows port: the Python gate is at the helper's start
    "to_file.c": os.path.join(GPLSRC, "to_file.c"),
    "keys.h": os.path.join(GPLSRC, "keys.h"),
    "sysseg.h": os.path.join(GPLSRC, "sysseg.h"),
    "int$keys.h": os.path.join(GPL, "int$keys.h"),
    "syscom/keys.h": os.path.join(SDSYS, "syscom", "keys.h"),
    "cproc": os.path.join(GPL, "cproc"),
    "login": os.path.join(GPL, "login"),
    "createa": os.path.join(GPL, "createa"),
    "create_account": os.path.join(GPL, "create_account"),
    "modifya": os.path.join(GPL, "modifya"),
    "edit": os.path.join(GPL, "edit"),
    "seldir": os.path.join(GPL, "seldir"),
    "_oscopy": os.path.join(GPL, "_oscopy"),
    "_ioscopy": os.path.join(GPL, "_ioscopy"),
    "oscopya": os.path.join(GPL, "oscopya"),
    "setptr": os.path.join(GPL, "setptr"),
    "apisrvr": os.path.join(GPL, "apisrvr"),
    "_voc_ref": os.path.join(GPL, "_voc_ref"),
    "acc_os_info": os.path.join(GPL, "acc_os_info"),
    "upgrade_gates": os.path.join(GPL, "upgrade_gates"),
    "sd.iss": os.path.join(HERE, "sd.iss"),      # 13 Nov 26 Windows port: Linux's installsdcore.sh; RefreshGates runs upgrade-gates.ps1
    "upgrade-gates.ps1": os.path.join(HERE, "upgrade-gates.ps1"),      # 13 Nov 26 Windows port: the step that drives upgrade_gates
}
C_FILES = ("op_sh.c", "op_seqio.c", "op_dio1.c", "op_kernel.c", "op_sdext.c", "op_dio4.c", "op_dio2.c", "sdpy_session.c", "to_file.c", "keys.h",
           "sysseg.h")
SH_FILES = ("upgrade-gates.ps1",)      # '#' comments, as the shell's
ISS_FILES = ("sd.iss",)


def strip_c(src):
    """C with comments removed and every removed newline kept, so offsets still map to lines."""
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
    """13 Nov 26 Windows port: Inno Setup with its comments removed - { ... }, (* ... *) and // in [Code], ';' lines in the
    sections - and newlines kept.  String-aware, because '{app}' inside a quoted string is a constant, not a comment."""
    src = "\n".join("" if l.lstrip().startswith(";") else l for l in src.split("\n"))      # first, so a '{' in one opens nothing
    out = []
    i, n, q = 0, len(src), False
    while i < n:
        ch = src[i]
        if q:
            out.append(ch)
            if ch in "'\n":      # a Pascal string never crosses a line; an apostrophe in a ';' comment line must not run on
                q = False
            i += 1
            continue
        if ch == "'":
            q = True
            out.append(ch)
            i += 1
            continue
        if ch == "{" or src.startswith("(*", i) or src.startswith("//", i):
            end = {"{": "}", "(": "*)", "/": "\n"}[ch]
            j = src.find(end, i + 1)
            j = n if j < 0 else (j if end == "\n" else j + len(end))
            out.append("\n" * src.count("\n", i, j))
            i = j
            continue
        out.append(ch)
        i += 1
    return "".join(out)


def code(name, src):
    if name in C_FILES:
        return strip_c(src)
    if name in SH_FILES:
        return strip_sh(src)
    if name in ISS_FILES:
        return strip_iss(src)
    return strip_bas(src)


def at(text, needle, start=0):
    """Offset of the first occurrence at or after start, or -1."""
    return text.find(needle, start)


def line_of(text, off):
    return text.count("\n", 0, off) + 1 if off >= 0 else None


def checks(srcs, messages_dir):
    """[(id, ok, detail)] - every invariant the gates rest on."""
    rows = []

    def ck(i, ok, detail=""):
        rows.append((i, bool(ok), detail))

    c = {name: code(name, text) for name, text in srcs.items()}

    # ---- K. the key numbers and the flag bits -------------------------------------------------------------------
    nums = {}
    for m in re.finditer(r"#define\s+(K_[A-Z0-9_]+)\s+(\d+)", c["keys.h"]):
        nums.setdefault(int(m.group(2)), []).append(m.group(1))
    for key, want in (("K_SH", 93), ("K_OS_EXEC", 94), ("K_PATH_OK", 95), ("K_PATH_IN", 96)):
        m = re.search(r"#define\s+%s\s+(\d+)" % key, c["keys.h"])
        ck("K1 %s is %d in gplsrc/keys.h" % (key, want), m and int(m.group(1)) == want, m.group(0) if m else "absent")
        bkey = key.replace("K_", "K$").replace("_", ".")
        m2 = re.search(r"\$define\s+%s\s+(\d+)" % re.escape(bkey), srcs["int$keys.h"])
        ck("K2 %s is %d in gpl.bp/int$keys.h, the same number" % (bkey, want), m2 and int(m2.group(1)) == want,
           m2.group(0) if m2 else "absent")
    dups = {n: k for n, k in nums.items() if len(k) > 1}
    ck("K3 no kernel key number in gplsrc/keys.h is used twice", not dups, repr(dups))
    ck("K4 USR_SH and USR_OS_EXEC are defined in sysseg.h and do not share a bit",
       re.search(r"#define\s+USR_SH\s+0x0100", c["sysseg.h"]) and re.search(r"#define\s+USR_OS_EXEC\s+0x0200", c["sysseg.h"]))
    ck("K5 ACC$SH is field 7 and ACC$OS.EXEC field 8 of the register",
       re.search(r"\$define ACC\$SH\s+7\b", srcs["syscom/keys.h"]) and re.search(r"\$define ACC\$OS\.EXEC\s+8\b", srcs["syscom/keys.h"]))

    # ---- C. the kernel -----------------------------------------------------------------------------------------
    sh = c["op_sh.c"]
    fn = at(sh, "Private void sh(bool capture) {")
    # 13 Nov 26 Windows port: os_permitted() takes a PRIV_WHY (PRE_RELEASE_FIXES 96) and logs an undetermined answer before 10054
    refuse = at(sh, "if (!os_permitted(&why)) {", fn)
    getstr = at(sh, "k_get_string(descr)", fn)
    ck("C1 sh() refuses BEFORE it touches the stack (the refusal precedes k_get_string)",
       fn >= 0 and refuse > fn and getstr > refuse, "refusal at line %s, k_get_string at line %s" % (line_of(sh, refuse), line_of(sh, getstr)))
    ck("C2 the refusal is the Windows port's 10054",
       re.search(r"if \(!os_permitted\(&why\)\) \{\s*if \(why != PRIV_ANSWERED\)\s*priv_log_undetermined\([^;]*;\s*k_error\(sysmsg\(10054\)", sh))
    # 13 Nov 26 Windows port: os_permitted() is HDR_INTERNAL, then os_user_permitted(), whose answer is os_gate_open() (RELEASE_1.1 23 split)
    perm = sh[at(sh, "Private bool os_permitted(PRIV_WHY* why) {"):][:400]
    oup = sh[at(sh, "Private bool os_user_permitted(PRIV_WHY* why) {"):]
    oup = oup[:oup.find("\n}") + 2]
    ck("C3 os_permitted(): an $internal program first, then the account's own gate (never an unconditional TRUE)",
       "HDR_INTERNAL" in perm and "return os_user_permitted(why);" in perm and "return os_gate_open();" in oup
       and "return TRUE" not in oup)
    gate = sh[at(sh, "bool os_gate_open(void) {"):]
    gate = gate[:gate.find("\n}") + 2]
    ck("C4 os_gate_open() is the administrator or USR_OS_EXEC, and does NOT look at HDR_INTERNAL",
       "USR_ADMIN" in gate and "USR_OS_EXEC" in gate and "HDR_INTERNAL" not in gate, gate.strip()[:120])
    # 13 Nov 26 Windows port: containment is op_dio2.c's (account_path_permitted, from 21 Aug 26), not Linux's resolve_name/path_inside_dir.
    # The name is resolved by fullpath() (sdrealpath, which follows links since 8 Nov 26), folded into one namespace by net_normalise(),
    # a surviving ".." is refused by has_parent_ref() before any comparison, and path_within() tests the component boundary.
    d2 = c["op_dio2.c"]
    pw = d2[at(d2, "Private bool path_within(char* cand, char* root) {"):]
    pw = pw[:pw.find("\n}") + 2]
    app = d2[at(d2, "bool account_path_permitted(char* path,"):]
    app = app[:app.find("\n}") + 2]
    okfa = sh[at(sh, "bool os_path_ok_for_account(const char *name) {"):]
    okfa = okfa[:okfa.find("\n}") + 2]
    ck("C5 containment resolves the name (fullpath) and folds both sides into one namespace, and tests a path-component boundary",
       "if (!fullpath(resolved, (char *)name))" in okfa and "net_normalise(path, cand)" in app and "net_normalise(item, root) && path_within(cand, root)" in app
       and "strncasecmp(cand, root, root_len)" in pw and "((cand[root_len] == '" + chr(92) + "0') || (cand[root_len] == '/'))" in pw)
    hp = at(app, "if (has_parent_ref(cand))")
    ck("C6 a '..' that survives resolution is refused, before the first comparison",
       0 < hp < at(app, "path_within(") and re.search(r"if \(has_parent_ref\(cand\)\)\s*return FALSE;", app))
    # Linux C6's second half (an account rooted at "/" is refused, Linux op_sh.c:283) is held at C14d below, in os_path_inside() (13 Nov 26).
    # account_path_permitted() (the session's own account) still has no such test: path_within() keeps a "/" root (op_dio2.c:1985).
    ck("C7 os_path_ok_for_account: the gate opens everything, otherwise containment, then (16 Oct 26) the SD.ACCOUNTS gate",
       re.search(r"if \(os_gate_open\(\)\)\s*return TRUE;.*?if \(account_path_permitted\(resolved, TRUE\)\)\s*return TRUE;.*?"
                 r"return MY_PRIV\(USR_SD_ACCOUNTS\) && path_in_enterable_account\(resolved\);", okfa, re.S))
    pea = at(d2, "bool path_in_enterable_account(char* resolved)")
    pea_end = at(d2, "bool account_path_permitted(", pea)
    pea_body = d2[pea:pea_end] if pea > 0 and pea_end > pea else ""
    # 13 Nov 26 Windows port: group membership is a live SAM query (win32_group_has_member), not Linux's user_in_group()
    ck("C7a SD.ACCOUNTS: an account counts only if the user is in its register group and it is not suspended",
       "win32_group_has_member(process.username, line[2], &member, why, sizeof(why)) || !member" in pea_body
       and 'strcasecmp(line[4], "SUSPENDED")' in pea_body)
    # 13 Nov 26 Windows port: a register path is a drive path, so "not absolute" is "an @ token other than @SDSYS", which is skipped
    ck("C7b SD.ACCOUNTS: a register path that is not expanded here is skipped, and the VOC of the account is left out",
       re.search(r"else if \(line\[0\]\[0\] == '@'\) \{\s*continue;", pea_body) and 'strncasecmp(p, "voc", 3)' in pea_body and '".dic"' in pea_body
       and pea_body.count("found = FALSE;") >= 2)       # the declaration, and the VOC branch
    ck("C7c SD.ACCOUNTS: the flag is set only from a $internal program, as K_OS_EXEC is",
       re.search(r"case K_SD_ACCOUNTS:.*?HDR_INTERNAL.*?USR_SD_ACCOUNTS", c["op_kernel.c"], re.S))
    ck("C8 os_path_open_ok: an $internal program is trusted, anyone else is asked",
       re.search(r"bool os_path_open_ok\(const char \*name\) \{\s*if \(process\.program\.flags & HDR_INTERNAL\)\s*return TRUE;\s*"
                 r"return os_path_ok_for_account\(name\);", sh))

    sq = c["op_seqio.c"]
    fnq = at(sq, "Private void openseq(bool map_name) {")
    nam = at(sq, "process.status = ER_NAM;", at(sq, "filename_descr = e_stack - 2;", fnq))      # the OPENSEQP branch
    hook = at(sq, "if (!os_path_open_ok(file_name)) {", fnq)
    port = at(sq, "if (is_port(file_name))", fnq)
    ck("C9 OPENSEQ by pathname is asked AFTER the name is validated and BEFORE the port test and the open",
       nam > 0 and hook > nam and port > hook, "ER_NAM %s, hook %s, is_port %s" % (line_of(sq, nam), line_of(sq, hook), line_of(sq, port)))
    ck("C10 and the refusal is ER_PERM", re.search(r"if \(!os_path_open_ok\(file_name\)\) \{\s*process\.status = ER_PERM;", sq))

    d1 = c["op_dio1.c"]
    fnd = at(d1, "Private void open_file(bool map_name)")
    fp = at(d1, "fullpath(pathname, mapped_name);", fnd)
    # 13 Nov 26 Windows port: OPENPATH (no VOC mapping) asks net_path_permitted(), which is os_path_open_ok()'s test (os_gate_open, then
    # HDR_INTERNAL, then the account's containment, op_dio2.c), for write and then for read; a VOC-mapped name asks net_vocpath_permitted(),
    # which holds network sessions only, because _VOC_REF vets it for the others (the Windows deviation CLAUDE.md lists).
    hk = at(d1, "net_may_write = map_name ? net_vocpath_permitted(pathname, TRUE) : net_path_permitted(pathname, TRUE);", fnd)
    txn = at(d1, "txn_open(pathname)", fnd)
    ck("C11 OPENPATH is asked AFTER fullpath() and BEFORE the transaction cache, and only when no VOC mapped the name",
       fp > 0 and hk > fp and txn > hk, "fullpath %s, hook %s, txn_open %s" % (line_of(d1, fp), line_of(d1, hk), line_of(d1, txn)))
    ck("C12 and the refusal is ER_PERM",
       re.search(r"if \(!net_may_write && !\(map_name \? net_vocpath_permitted\(pathname, FALSE\) : net_path_permitted\(pathname, FALSE\)\)\) \{\s*"
                 r"process\.status = ER_PERM;", d1)
       and re.search(r"bool net_path_permitted\(char\* path,[^{]*\{\s*if \(os_gate_open\(\)\)\s*return TRUE;\s*if \(process\.program\.flags & HDR_INTERNAL\)\s*"
                     r"return TRUE;\s*return account_path_permitted\(path, for_write\);", c["op_dio2.c"]))

    kn = c["op_kernel.c"]
    for case, flag in (("K_SH", "USR_SH"), ("K_OS_EXEC", "USR_OS_EXEC")):
        s0 = at(kn, "case %s:" % case)
        blk = kn[s0:at(kn, "case K_", s0 + 8)]               # this case's own block, not the next one's
        ck("C13 kernel(%s) changes the flag only for an $internal caller, and reports it" % case,
           "HDR_INTERNAL" in blk and ("SET_MY_PRIV(%s," % flag) in blk and ("MY_PRIV(%s)" % flag) in blk and "result.data.value" in blk)
    kp = kn[at(kn, "case K_PATH_OK:"):][:420]
    ck("C14 kernel(K_PATH_OK) answers os_path_ok_for_account (the account's question, not the caller's)",
       "os_path_ok_for_account(path_ok_name)" in kp and "os_path_open_ok" not in kp)

    kin = kn[at(kn, "case K_PATH_IN:"):][:700]
    ck("C14b kernel(K_PATH_IN) splits 'directory, field mark, pathname' and answers the GEOMETRY only (os_path_inside): it does not "
       "ask the gate, so a caller that uses it has decided the directory is one the account may use",
       "FIELD_MARK" in kin and "os_path_inside(path_in_buf, path_in_sep + 1)" in kin and "os_gate_open" not in kin
       and "os_path_ok_for_account" not in kin)
    # 13 Nov 26 Windows port: os_path_inside is op_dio2.c's own (fullpath both, fold, refuse "..", path_within), with no gate in it.
    oin = c["op_dio2.c"][at(c["op_dio2.c"], "bool os_path_inside(const char* rootdir, const char* name) {"):]
    oin = oin[:oin.find("\n}") + 2]
    ck("C14c os_path_inside resolves both names, folds them, refuses a '..' and asks path_within - and does not ask the gate",
       "!fullpath(rr, (char*)rootdir) || !fullpath(cc, (char*)name)" in oin and "if (has_parent_ref(cand))" in oin
       and "return path_within(cand, root);" in oin and "os_gate_open" not in oin and "HDR_INTERNAL" not in oin)
    # 13 Nov 26 (RELEASE_1.1 254): Linux's two root tests, as Core now has them - an absolute directory BEFORE it is resolved (Linux
    # op_sh.c:270), and a directory that is the whole machine ("/" or a drive root; Linux "/" only, op_sh.c:283) refused after folding.
    d2 = c["op_dio2.c"]
    ra = d2[at(d2, "Private bool os_root_absolute(const char* d) {"):]
    ra = ra[:ra.find("\n}") + 2]
    rw = d2[at(d2, "Private bool os_root_whole_machine(const char* root) {"):]
    rw = rw[:rw.find("\n}") + 2]
    oa, ofp = at(oin, "if (!os_root_absolute(rootdir))"), at(oin, "if (!fullpath(rr,")
    onn, owm, opw = at(oin, "if (!net_normalise(rr, root)"), at(oin, "if (os_root_whole_machine(root))"), at(oin, "return path_within(cand, root);")
    ck("C14d os_path_inside requires an absolute directory BEFORE fullpath() and refuses a whole-machine root after folding, before path_within",
       0 < oa < ofp < onn < owm < opw and re.search(r"if \(!os_root_absolute\(rootdir\)\)\s*return FALSE;", oin)
       and re.search(r"if \(os_root_whole_machine\(root\)\)\s*return FALSE;", oin),
       "absolute %s, fullpath %s, fold %s, whole %s, within %s" % (oa, ofp, onn, owm, opw))
    ck("C14e os_root_absolute is a leading separator or a drive letter, colon and separator - nothing else",
       "if ((d[0] == '/') || (d[0] == '" + chr(92) + chr(92) + "'))" in ra and "(d[1] == ':') && ((d[2] == '/') || (d[2] == '" + chr(92) + chr(92) + "'))" in ra and "return TRUE;" in ra
       and ra.count("return") == 2)
    ck("C14f os_root_whole_machine refuses '/' and a bare drive, and a root it cannot convert",
       'if (strcmp(r, "/") == 0)' in rw and re.search(r"cygwin_conv_path\(CCP_POSIX_TO_WIN_A, r, w, sizeof\(w\)\) != 0\)\s*return TRUE;", rw)
       and "return (n == 2) && (w[1] == ':');" in rw)

    # 13 Nov 26 Windows port: Python runs in a helper process (sdpy.exe), and the gate is where the helper is STARTED (sdpy_session.c,
    # may_start_helper), because inside op_sdext.c the program is already the $internal PY_* wrapper (RELEASE_1.1 23).  Every key that
    # needs Python reaches sdpy_session() through py_ext_call(); "is Python running?" asks only an already-running helper.
    sx = c["op_sdext.c"]
    ss = c["sdpy_session.c"]
    msh = ss[at(ss, "static int may_start_helper(PRIV_WHY* why) {"):]
    msh = msh[:msh.find("\n}") + 2]
    sps = ss[at(ss, "SDPY* sdpy_session(int* err_code) {"):]
    g = at(sps, "if (!may_start_helper(&why)) {")
    run = at(sps, "sdpy_start(")
    ck("C15 the Python gate asks the ACCOUNT (sd_os_permitted -> os_user_permitted -> os_gate_open, not the program) and comes before "
       "the helper is started",
       0 < g < run and "return sd_os_permitted(why) ? 1 : 0;" in msh and "HDR_INTERNAL" not in msh
       and re.search(r"bool sd_os_permitted\(PRIV_WHY\* why\) \{\s*return os_user_permitted\(why\);", sh),
       "gate %s, start %s" % (g, run))
    pyc = sx[at(sx, "Private int py_ext_call("):]
    isi = sx[at(sx, "Private void py_ext_isinit(void) {"):]
    isi = isi[:isi.find("\n}") + 2]
    ck("C16 it gates starting the interpreter and running code, and not 'is Python running?'",
       re.search(r"case SD_PyInit:\s*py_ext_int\(", sx) and re.search(r"case SD_PyRunStr:\s*py_ext_int\(", sx)
       and re.search(r"case SD_PyRunFile:\s*py_ext_int\(", sx) and "s = sdpy_session(&err_code);" in pyc[:900]
       and re.search(r"case SD_IsPyInit:\s*py_ext_isinit\(\);", sx)
       and 0 < at(isi, "if (sdpy_session_running()) {") < at(isi, "py_ext_call("))

    # ---- C (second sitting). the other routes to an OS path ------------------------------------------------------
    # 13 Oct 26: the first S.63 asked only OPENSEQ and OPENPATH.  A measured account with both gates off still listed /etc
    # with DIR(), deleted a file outside its directory with DELETESEQ, copied files out of and into other directories
    # with !OSCOPY / !IOSCOPY, and printed into a file outside it with SETPTR ... AS PATHNAME.  Each is asked below.
    d4 = c["op_dio4.c"]
    dr = d4[at(d4, "void op_dir() {"):]
    dgate = at(dr, "if (!os_path_open_ok(pathname)) {")
    dopen = at(dr, "opendir(pathname)")
    ck("C17 DIR() asks the OS gate for the pathname BEFORE opendir(), and the refusal is ER_PERM",
       0 < dgate < dopen and re.search(r"if \(!os_path_open_ok\(pathname\)\) \{\s*process\.status = ER_PERM;", dr),
       "gate %s, opendir %s" % (dgate, dopen))
    ds = sq[at(sq, "void op_delseq() {"):]
    dsrec = at(ds, "strcat(file_name, rec_name);")
    dsgate = at(ds, "if (!os_path_open_ok(file_name)) {", dsrec)
    dsstat = at(ds, "stat(file_name, &stat_buf)")
    ck("C18 DELETESEQ of a bare pathname (no record name) asks the OS gate AFTER the VOC-named form is dealt with and BEFORE it "
       "stats or removes anything, and the refusal is ER_PERM",
       0 < dsrec < dsgate < dsstat and re.search(r"if \(!os_path_open_ok\(file_name\)\) \{\s*process\.status = ER_PERM;\s*goto exit_op_delseq;", ds),
       "record form %s, gate %s, stat %s" % (dsrec, dsgate, dsstat))
    tf = c["to_file.c"]
    tsf = at(tf, "Private void start_file(PRINT_UNIT* pu) {")
    tmark = at(tf, 'sprintf(fn, "$hold%c%s", DS, pu->file_name + 6);', tsf)
    tcpy = at(tf, "strcpy(fn, pu->file_name);", tsf)
    tgate = at(tf, "os_path_ok_for_account(fn)", tsf)
    topen = at(tf, "open_file:", tsf)
    ck("C19 a print unit's FINAL path - whether it came from a raw pathname or from the '$hold name' marker, which a SETPU program "
       "can write itself and which must not climb out with '..' - is asked of the ACCOUNT (not the printing program, which is "
       "usually $internal) after every branch has built it and before dio_open(), and the refusal is 12185",
       0 < tsf < tmark < tgate < topen and tcpy < tgate and "sysmsg_arg1(12185, account())" in tf[tgate:topen]   # 20 Oct 26: names the ACCOUNT, %1 filled in C
       and "os_path_open_ok" not in tf[tsf:topen],
       "start_file %s, marker %s, raw copy %s, gate %s, open_file %s" % (tsf, tmark, tcpy, tgate, topen))

    # ---- B. BASIC ---------------------------------------------------------------------------------------------
    cp = c["cproc"]
    # 3 Nov 26 (S.96): the loads are one routine, load.account.switches, which int.logto CALLS before its audit line (and RUN.IN calls too); the statements are in the routine
    ld = at(cp, "gosub load.account.switches")
    aud = at(cp, "void kernel(K$AUDIT, 'logto account='")
    # 11 Nov 26 (S.213): the two lines also say "and not while RUN.IN is running a command" (not(ri.active) and ...); test-runin-units.py R43 holds that half
    ldr = at(cp, "void kernel(K$SH,      not(ri.active) and (upcase(trim(acc.record<ACC$SH>)) = 'YES'))")
    ck("B1 CPROC's LOGTO loads K$SH and K$OS.EXEC from the register record BEFORE the audit line (the call; the statements are in load.account.switches)",
       0 < ld < aud and ldr > 0 and "upcase(trim(acc.record<ACC$SH>)) = 'YES'" in cp and "upcase(trim(acc.record<ACC$OS.EXEC>)) = 'YES'" in cp,
       "call %s, audit %s, routine %s" % (line_of(cp, ld), line_of(cp, aud), line_of(cp, ldr)))
    sdl = at(cp, "void kernel(K$SD.ACCOUNTS, upcase(trim(acc.record<ACC$SD.ACCOUNTS>)) = 'YES')")
    ck("B1a ... and K$SD.ACCOUNTS (16 Oct 26) from field 9, 'YES' only, in the same routine, called before the audit line (28 Oct 26: STACKED.ACCOUNT and its stk.* variables are gone; 3 Nov 26: revert.account is RUN.IN's own, which puts back what it kept in the /runin/ common)",
       0 < ld < aud and sdl > ldr and "stk.sd.accounts" not in cp and "OPT.STACKED.ACCOUNT" not in cp)
    oc = at(cp, "os.command.text = trimf(voc.rec<3>")
    # 13 Nov 26 Windows port: the grant is read into sh.listed first, then tested
    gate_ = at(cp, "if not(kernel(K$ADMINISTRATOR, -1)) and not(sh.listed) then", oc)
    meta = at(cp, "if not(valid_shell_cmd(os.command.text)) then", oc)
    osx = at(cp, "os.execute os.command.text", oc)
    ck("B2 the SH verb refuses (10053) BEFORE the metacharacter test and BEFORE it runs the command",
       0 < oc < at(cp, "sh.listed = kernel(K$SH, -1)", oc) < gate_ < meta < osx and "sysmsg(10053, @logname)" in cp[gate_:meta],
       "gate %s, filter %s, run %s" % (line_of(cp, gate_), line_of(cp, meta), line_of(cp, osx)))

    lg = c["login"]
    ll = at(lg, "void kernel(K$SH,")
    pth = at(lg, "account.path = ospath(\"\", OS$CWD)")
    ck("B3 LOGIN loads both grants at sign-on, from the 'YES' in fields 7 and 8, before @PATH is set",
       0 < ll < pth and "upcase(trim(acc.rec<ACC$SH>)) = 'YES'" in lg and "upcase(trim(acc.rec<ACC$OS.EXEC>)) = 'YES'" in lg)
    ck("B3a LOGIN loads the SD.ACCOUNTS gate from field 9, 'YES' only, before @PATH is set",
       0 < at(lg, "void kernel(K$SD.ACCOUNTS, upcase(trim(acc.rec<ACC$SD.ACCOUNTS>)) = 'YES')") < pth)

    ca = c["create_account"]
    ck("B4 a new account starts with NO ssh and NO API: a route is on only if the setting is exactly 1",
       "access.ssh = (settings<CA$ROUTE.SSH> = 1)" in ca and "access.api = (settings<CA$ROUTE.API> = 1)" in ca
       and "# '0'" not in ca[ca.find("access.given"):ca.find("access.given") + 900])
    # 13 Nov 26 Windows port: Core's variables are os.sh and os.exec (Linux's os.sh.want and os.exec.want), assigned the comparison
    ck("B5 SH and OS.EXECUTE start off too: a switch is on only if its setting is exactly 1",
       re.search(r"(?m)^\s*os\.sh\s*= settings<CA\$OS\.SH> = 1\s*$", ca) and re.search(r"(?m)^\s*os\.exec = settings<CA\$OS\.EXECUTE> = 1\s*$", ca))
    att = at(ca, "if settings<CA$ATTACH> = 1 then")
    att_end = at(ca, "openpath @sdsys:@ds:'accounts' to acc.f", att)
    ck("B6 ATTACH (the installing user) turns NOTHING on: the install-only branch never sets a route or a switch, so the installing "
       "user's account starts off like every other new account (owner, 13 Oct second sitting: the only exception is the accounts "
       "that exist at an upgrade)",
       0 < att < att_end and at(ca, "err = 2018:@vm:'ATTACH'") > att
       and not any(x in ca[att:att_end] for x in ("access.ssh = @true", "access.api = @true", "os.sh.want = @true", "os.exec.want = @true",
                                                   "os.sh = @true", "os.exec = @true",      # 13 Nov 26 Windows port: Core's names
                                                   "if attach then")),
       "attach block %s..%s" % (att, att_end))
    # 13 Nov 26 Windows port: Core's names are os.sh / os.exec; each branch is held on its own, so losing one refusal is seen
    grp = ca[at(ca, "case acc.type = 'GROUP'"):at(ca, "case acc.type = 'OTHER'")]
    oth = ca[at(ca, "case acc.type = 'OTHER'"):]
    refusal = r"if os\.sh or os\.exec then\s*@system\.return\.code = -ER\$ARGS\s*err = 10105:@vm:acc\.name"
    ck("B7 a GROUP and an OTHER account given SH or OS are refused with 10105 (and a GROUP one given a route with 10087, first, as Linux)",
       re.search(refusal, grp) and re.search(refusal, oth[:1200])
       and 0 < at(grp, "if access.given then") < at(grp, "if os.sh or os.exec then")
       and re.search(r"if access\.given then\s*@system\.return\.code = -ER\$ARGS\s*err = 10087:@vm:acc\.name", grp))
    wr = at(ca, "write acc.rec to acc.f, acc.name")
    usr = at(ca, 'if acc.type = "USER" then')
    ck("B8 the register record gets ACC$SH and ACC$OS.EXEC as yes/no for a USER account, before it is written",
       0 < usr < at(ca, "acc.rec<ACC$SH> = if os.sh then 'yes' else 'no'", usr) < wr
       and 0 < usr < at(ca, "acc.rec<ACC$OS.EXEC> = if os.exec then 'yes' else 'no'", usr) < wr, "user %s, write %s" % (usr, wr))

    cr = c["createa"]
    # 13 Nov 26 Windows port: Core's parse sets os.sh / os.exec, and the settings are filled from them after the parse
    ck("B9 CREATE.ACCOUNT accepts SH-ON and OS-ON, each setting only its own field",
       re.search(r"upcase\(token\) = 'SH-ON'\s*os\.sh = @true\s*case", cr) and re.search(r"upcase\(token\) = 'OS-ON'\s*os\.exec = @true\s*case", cr)
       and "if os.sh then settings<CA$OS.SH> = 1" in cr and "if os.exec then settings<CA$OS.EXECUTE> = 1" in cr)
    ck("B10 its usage says what the default is and names the words",
       "sh-on" in srcs["createa"] and "no ssh, no API, no shell" in srcs["createa"])

    md = c["modifya"]
    for word, field, want in (("SH-ON", "ACC$SH", "@true"), ("SH-OFF", "ACC$SH", "@false"), ("OS-ON", "ACC$OS.EXEC", "@true"),
                              ("OS-OFF", "ACC$OS.EXEC", "@false")):
        # 13 Nov 26 Windows port: Core dispatches on upcase(action), one statement a line
        ck("B11 MODIFY.ACCOUNT %s sets os.field = %s, os.want = %s and calls os.set" % (word, field, want),
           re.search(r"case upcase\(action\) = '%s'\s*os\.field = %s\s*os\.want\s*= %s\s*gosub os\.set" % (re.escape(word), re.escape(field), want), md))
    osset = md[at(md, "\nos.set:"):]
    nxt = re.search(r"\n[a-z][a-z0-9.$_]*:[ \t]*\n", osset[1:])      # 13 Nov 26 Windows port: os.set's body only, up to the next label
    osset = osset[:nxt.start() + 1] if nxt else osset
    rd = at(osset, "readu acc.new from acc.f, acc.name")
    wt = at(osset, "write acc.new to acc.f, acc.name")
    # 13 Nov 26 Windows port: Core's os.set says 10104 for a failed write (Linux 10114, which Core keeps for a failed state change)
    ck("B12 os.set writes the register under a lock (readu before write) and reports a failed write",
       0 < rd < wt and "sysmsg(10104, acc.name)" in osset[wt:])
    ck("B13 os.set reports both fields afterwards (10102), refuses a non-sdu_ account (10105) and says 'no change' (10080)",
       "sysmsg(10102, acc.name, osu.sh, osu.ex)" in osset and "sysmsg(10105, acc.name)" in osset and "sysmsg(10080, acc.name)" in osset)

    ed = c["edit"]
    cpm = ed[at(ed, "check.permitted:"):][:1400]
    tty = at(cpm, "kernel(K$TTY, 0) = ''")
    ox = at(cpm, "kernel(K$OS.EXEC, -1)")
    ck("B14 micro (EDIT) needs OS.EXECUTE: the grant is tested after the terminal test, and a plain 'permitted = @true' "
       "no longer ends check.permitted", 0 < tty < ox and not re.search(r"@system|\n\s*permitted = @true\s*\nreturn", cpm.split("kernel(K$OS.EXEC, -1)")[0][-60:]),
       "tty %s, grant %s" % (tty, ox))

    ai = c["acc_os_info"]
    ck("B15 the account manifest writes os.sh and os.execute (what RESTORE.ACCOUNT reads back)",
       "'os.sh: '" in ai and "'os.execute: '" in ai and "ACC$SH" in ai and "ACC$OS.EXEC" in ai)

    ug = c["upgrade_gates"]
    mk = at(ug, "if ospath(marker, OS$EXISTS) then")
    wk = at(ug, "select acc.f to 12")
    wm = at(ug, "openseq marker to marker.f")
    fl = at(ug, "if failed # 0 then")
    ck("B16 upgrade_gates: the marker is tested BEFORE the walk and written AFTER it, and only when nothing failed",
       0 < mk < wk < fl < wm, "marker test %s, walk %s, failed test %s, marker write %s" % (mk, wk, fl, wm))
    # 13 Nov 26 Windows port: Core's walk copies the old per-person grant from sdsys\os.users (field 1 SH, field 2 OS.EX; 'no' without one),
    # where Linux, which had no such record, sets 'yes' (RELEASE_1.1 170).  What is held is the same: user accounts only, a blank field only.
    ck("B17 it touches USER accounts only (an sdu_ group) and sets a field ONLY where that field is blank - an explicit no is never overwritten - "
       "and to yes only where os.users said yes",
       "if downcase(rec<ACC$GROUP>[1, 4]) = 'sdu_' then" in ug
       and re.search(r"if trim\(rec<ACC\$SH>\) = '' then\s*rec<ACC\$SH> = 'no'\s*if upcase\(trim\(osu\.rec<1>\)\) = 'YES' then rec<ACC\$SH> = 'yes'\s*end", ug)
       and re.search(r"if trim\(rec<ACC\$OS\.EXEC>\) = '' then\s*rec<ACC\$OS\.EXEC> = 'no'\s*if upcase\(trim\(osu\.rec<2>\)\) = 'YES' then "
                     r"rec<ACC\$OS\.EXEC> = 'yes'\s*end", ug)
       and not re.search(r"^\s*rec<ACC\$(SH|OS\.EXEC)> = 'yes'", ug, re.M))
    ck("B17b the walk counts a record as already done when NEITHER field is blank (a no counts), not when both say yes",
       "if trim(rec<ACC$SH>) # '' and trim(rec<ACC$OS.EXEC>) # '' then" in ug and not re.search(r"trim\(rec<ACC\$(SH|OS\.EXEC)>\)\) = 'YES'", ug))

    # the $internal programs that act for the user on an OS path: the kernel exempts them, so each asks K$PATH.OK itself
    sdr = c["seldir"]
    sg = at(sdr, "if not(kernel(K$PATH.OK, path)) then")
    sd_ = at(sdr, "entries = dir(path)")
    ck("B18 SELECT.DIR asks K$PATH.OK for the directory BEFORE it reads it, says 12185, and includes int$keys.h",
       0 < sg < sd_ and "sysmsg(12185, @who)" in sdr[sg:sd_] and "$include int$keys.h" in sdr,
       "ask %s, dir() %s" % (sg, sd_))
    oc_ = c["_oscopy"]
    o1, o2 = at(oc_, "kernel(K$PATH.OK, source)"), at(oc_, "kernel(K$PATH.OK, target)")
    oe = at(oc_, "ospath(source, OS$EXISTS)")
    ck("B19 !OSCOPY asks K$PATH.OK for BOTH paths BEFORE it tests that the source exists (so -2 does not say what exists "
       "elsewhere), and the answer is status -4",
       0 < o1 < oe and 0 < o2 < oe and "status = -4" in oc_[o1:oe], "source %s, target %s, exists %s" % (o1, o2, oe))
    io_ = c["_ioscopy"]
    i1, i2 = at(io_, "kernel(K$PATH.OK, source)"), at(io_, "kernel(K$PATH.OK, target)")
    ie = at(io_, "ospath(source, OS$EXISTS)")
    ck("B20 !IOSCOPY the same: both paths asked before the existence test, status -4",
       0 < i1 < ie and 0 < i2 < ie and "status = -4" in io_[i1:ie], "source %s, target %s, exists %s" % (i1, i2, ie))
    oa = c["oscopya"]
    ck("B21 the OSCOPY verb answers -4 in 12185's words, before its catch-all",
       re.search(r"case status = -4\s*display sysmsg\(12185, @who\)\s*case 1", oa))
    # the API server enters an account itself, through neither LOGIN nor CPROC's LOGTO, so it loads the switches itself
    ap = c["apisrvr"]
    a0 = at(ap, "api.sh.grant = @false")
    a1 = at(ap, "api.sh.grant = (upcase(trim(acc.rec<ACC$SH>)) = 'YES')")
    a2 = at(ap, "api.os.grant = (upcase(trim(acc.rec<ACC$OS.EXEC>)) = 'YES')")
    a_cd = at(ap, "if not(ospath(account.path, OS$CD)) then")
    a_voc = at(ap, 'openpath "voc" to new.voc else')
    a_ld = at(ap, "void kernel(K$SH,      api.sh.grant)")
    a_ld2 = at(ap, "void kernel(K$OS.EXEC, api.os.grant)")
    a_login = at(ap, "readv i from @voc, 'LOGIN', 0")
    ck("B23 the API server reads the account's two switches from the register ('YES' only), starting from OFF on every call, and "
       "loads them only AFTER the account has been entered (after the last revert) and before the LOGIN paragraph runs",
       0 < a0 < a1 < a2 and 0 < a_voc < a_ld < a_ld2 < a_login and a_cd < a_voc and "api.os.grant = @false" in ap[a0:a1],
       "reset %s, read %s/%s, cd %s, voc %s, load %s/%s, login %s" % (a0, a1, a2, a_cd, a_voc, a_ld, a_ld2, a_login))
    # a VOC pointer is a way to NAME a file: the F-pointer's target, and the account a Q-pointer leads into (second sitting)
    vr = c["_voc_ref"]
    vr_top = at(vr, "vr.admin = kernel(K$ADMINISTRATOR, -1)")
    vr_free = at(vr, "vr.free = vr.admin or kernel(K$OS.EXEC, -1)")
    q_chk = at(vr, "gosub check.q.hop")
    q_dir = at(vr, "dir = qpath", q_chk)
    q_open = at(vr, "openpath qpath:@ds:'voc' to qvoc", q_chk)
    ck("B24 _voc_ref derives 'administrator' and 'holds os-on' from the session, and a Q-pointer is checked (not for the administrator) "
       "BEFORE its target account's VOC is opened, the refusal being ER$PERM",
       0 < vr_top < vr_free < q_chk < q_dir < q_open
       and re.search(r"if not\(vr\.admin\) then\s*gosub check\.q\.hop\s*if not\(q\.ok\) then\s*set\.status ER\$PERM\s*return", vr),
       "admin %s, free %s, hop %s, dir %s, open %s" % (vr_top, vr_free, q_chk, q_dir, q_open))
    hop = vr[at(vr, "check.q.hop:"):]
    reg = hop[at(hop, "if q.registered then"):at(hop, "q.ok = vr.free or")]
    ck("B25 check.q.hop: a stock pointer (the same record in NEWVOC) first; a REGISTERED account only on LOGTO's own test - not suspended, "
       "and a member of its group - and WITHOUT looking at os-on (the owner: 'only into an account the user can logto in any case'); "
       "a path or a name that is no account is the OS gate's question",
       "stock.found and upcase(stock.rec[1,1]) = 'Q'" in hop and "stock.rec<2> = q.named" in hop
       and "upcase(trim(q.susp)) # 'SUSPENDED'" in reg and "is_grp_member(@logname, q.group)" in reg and "vr.free" not in reg
       and "q.ok = vr.free or kernel(K$PATH.OK, qpath)" in hop)
    f_chk = at(vr, "gosub check.f.path")
    f_ret = at(vr, "set.status 0", f_chk)
    fcp = vr[at(vr, "check.f.path:"):at(vr, "check.q.hop:")]
    ck("B26 _voc_ref asks about the file an F-pointer finally names, after the name is made absolute and before it is returned, "
       "unless the session is free: inside the account, or inside the account a Q-pointer led into (K$PATH.IN), or what the stock "
       "VOC says (same id, same field in NEWVOC)",
       0 < f_chk < f_ret and re.search(r"if not\(vr\.free\) then\s*gosub check\.f\.path\s*if not\(path\.ok\) then\s*pathname = ''\s*set\.status ER\$PERM", vr)
       and "kernel(K$PATH.OK, pathname)" in fcp and "kernel(K$PATH.IN, qroot : @fm : pathname)" in fcp
       and "upcase(stock.rec[1,1]) = 'F' and stock.rec<fno> = f.raw" in fcp,
       "check %s, return %s" % (f_chk, f_ret))
    ck("B27 the PATH: form (FILERULE) is gone (28 Oct 26, S.87), and an absolute Q-pointer target is remembered as qroot",
       "case upcase(x1) = 'PATH'" not in vr and "config('FILERULE')" not in vr
       and "if qpath[1,1] = @ds then qroot = qpath" in vr)
    afi = vr.find("if dcount(voc.id, ':') = 2")
    afb = vr[afi:vr.find("\n      end\n", afi)] if afi >= 0 else ""
    ck("B27b the Account:File form (back 3 Nov 26, always on) only builds a Q record and goes to parse.as.q.pointer, so every Q-pointer check applies: "
       "it opens nothing and sets no pathname itself",
       "voc.rec = 'Q' : @fm : field(voc.id, ':', 1) : @fm : field(voc.id, ':', 2)" in afb and "goto parse.as.q.pointer" in afb
       and "pathname" not in afb and "openpath" not in afb.lower(), afb[:200])
    spt = c["setptr"]
    sp0 = at(spt, "ospath(file.name, OS$PATHNAME)")
    sp1 = at(spt, "kernel(K$PATH.OK, file.name)")
    ck("B22 SETPTR ... AS PATHNAME asks K$PATH.OK after it has checked the name is a pathname, and says 12185",
       0 < sp0 < sp1 and "sysmsg(12185, @who)" in spt[sp1:sp1 + 120], "valid %s, ask %s" % (sp0, sp1))


    # ---- I. the installer ---------------------------------------------------------------------------------------
    # 13 Nov 26 Windows port: sd.iss's RefreshGates runs upgrade-gates.ps1, which runs upgrade_gates.  Linux's "as root" is the elevated
    # installer itself (no sudo on the line, an OS difference); its "before the register is chowned to sdsys and CPROC is recompiled
    # without IS_INSTALL" is dropped: Windows protects the register by ACL (no chown), and cproc carries no IS_INSTALL blocks (cproc:191).
    ins = c["sd.iss"]
    rg = at(ins, "function RefreshGates: String;")
    rg_end = at(ins, "\nend;", rg)
    rgb = ins[rg:rg_end] if 0 < rg < rg_end else ""
    vc = at(ins, "VocMsg := RefreshAccountVocs;")
    nc = at(ins, "NocaseMsg := RefreshNocase;")
    run_ = at(ins, "GatesMsg := RefreshGates;")
    mk_sdsys = at(ins, "SdsysCode := MakeSdsysAccount;")
    attach = at(ins, "AttachCode := AttachInstallerAccount;")
    ck("I1 the installer runs upgrade_gates (RefreshGates -> upgrade-gates.ps1) only on a kept data tree, after the VOC and case walks and "
       "BEFORE the SDSYS and installing user's accounts are written with their own grants",
       0 < rg and "if DataTreeWasAbsent then Exit;" in rgb and "upgrade-gates.ps1" in rgb
       and 0 < vc < nc < run_ < mk_sdsys < attach,
       "RefreshGates %s, vocs %s, nocase %s, gates %s, sdsys %s, attach %s" % (rg, vc, nc, run_, mk_sdsys, attach))
    ug_ps = c["upgrade-gates.ps1"]
    ck("I1a upgrade-gates.ps1 runs upgrade_gates through sd -internal",
       "Invoke-Sd @('-internal', 'RUN', 'gpl.bp', 'UPGRADE_GATES', 'NO.PAGE')" in ug_ps)
    ck("I2 a run that did not print COMPLETE is reported and the install goes on: the script tests for COMPLETE on a line of its own and "
       "says so, and RefreshGates turns a non-zero exit into a message, not an abort",
       r"$Text -match '(?m)^\s*COMPLETE\s*$'" in ug_ps[at(ug_ps, "function Get-GatesVerdict"):at(ug_ps, "function Get-EditGatesVerdict")]
       and "UPGRADE_GATES did not reach COMPLETE" in ug_ps
       and "case Code of" in rgb and "Result :=" in rgb.split("case Code of")[-1]
       and not any(x in rgb for x in ("Abort", "RaiseException", "Halt")))

    # ---- M. the messages ----------------------------------------------------------------------------------------
    want = {"10053": ("%1 is not permitted to use the operating system shell", True),
            "10054": ("%s is not permitted to use OS.EXECUTE", True),
            "10080": ("%1 already had that access; nothing changed", True),
            "10102": ("Account %1 has SH %2, OS.EXECUTE %3", False),
            "10105": ("%1 is a group account and has no Windows user, so it has no shell to permit", False),      # 13 Nov 26 Windows port: Windows
            "12185": ("%1 has no OS access", False)}   # Linux 11180 (was Linux 11167, which the unmerged screen branch also allocates)
    for num, (text, same_as_windows) in want.items():
        path = os.path.join(messages_dir, num)
        try:
            with open(path) as f:
                body = f.read().rstrip("\n")
        except OSError as exc:
            ck("M1 message %s exists" % num, False, str(exc))
            continue
        ck("M1 message %s exists and starts as the code expects" % num, body.startswith(text), repr(body[:80]))
        # 13 Nov 26 Windows port: Linux's M2 (word for word the Windows port's message) is dropped - this is the Windows tree.
    return rows


# --------------------------------------------------------------- self-test
def sub(name, old, new):
    def f(srcs):
        s = dict(srcs)
        if old not in s[name]:
            return s
        s[name] = s[name].replace(old, new, 1)
        return s
    return f


def sub_after(name, anchor, old, new):
    """13 Nov 26 Windows port: sub(), but the first OLD at or after ANCHOR (op_dio2.c says the same line in several functions)."""
    def f(srcs):
        s = dict(srcs)
        t = s[name]
        a = t.find(anchor)
        i = t.find(old, a) if a >= 0 else -1
        if i < 0:
            return s
        s[name] = t[:i] + new + t[i + len(old):]
        return s
    return f


def swap(name, a, b):
    """Swap two exclusive substrings of the file (order mutants)."""
    def f(srcs):
        s = dict(srcs)
        t = s[name]
        if a not in t or b not in t:
            return s
        t = t.replace(a, "\0A\0", 1).replace(b, a, 1).replace("\0A\0", b, 1)
        s[name] = t
        return s
    return f


def _move_seq_hook(srcs):
    """Take the OPENSEQ pathname test out from before the port test and put it after fullpath() in the other branch,
    so it is still there, still compiles, and sits where the port test has already run."""
    s = dict(srcs)
    t = s["op_seqio.c"]
    hook = ("    if (!os_path_open_ok(file_name)) {\n      process.status = ER_PERM;\n      goto exit_op_openseq;\n    }\n")
    anchor = "      fullpath(fullpathname, file_name);\n"
    if hook not in t or anchor not in t:
        return s
    t = t.replace(hook, "", 1)
    t = t.replace(anchor, anchor + hook.replace("    if", "      if", 1), 1)
    s["op_seqio.c"] = t
    return s


def _gate_only_raw_print_path(srcs):
    """Move the print-path question into the raw-pathname branch of start_file(), so it still exists and still compiles but a
    "$hold ../.." marker is never asked."""
    s = dict(srcs)
    t = s["to_file.c"]
    gate = ("    if (!os_path_ok_for_account(fn)) {\n      k_error(sysmsg_arg1(12185, account()));\n    }\n")      # 18 Oct 26 (S.66): no longer followed by the open_file label
    raw = "      strcpy(fn, pu->file_name);\n    }\n"
    if gate not in t or raw not in t:
        return s
    t = t.replace(gate, "", 1)
    t = t.replace(raw, "      if (!os_path_ok_for_account(pu->file_name)) {\n        k_error(sysmsg_arg1(12185, account()));\n      }\n" + raw, 1)
    s["to_file.c"] = t
    return s


MUTANTS = [
    # 13 Nov 26 Windows port: the op_sh.c, op_dio2.c and op_dio1.c mutants are aimed at Core's form of the same invariant
    ("sh(): the refusal is removed", sub("op_sh.c", "if (!os_permitted(&why)) {", "if (0) {")),
    ("os_permitted() always true", sub("op_sh.c", "    *why = PRIV_ANSWERED;\n\n  return os_gate_open();", "    *why = PRIV_ANSWERED;\n\n  return TRUE;")),
    ("os_permitted() no longer asks the account", sub_after("op_sh.c", "Private bool os_permitted(PRIV_WHY* why) {", "return os_user_permitted(why);", "return TRUE;")),
    ("the Python gate's wrapper goes through os_permitted (TRUE for the $internal PY_* wrapper)", sub("op_sh.c", "bool sd_os_permitted(PRIV_WHY* why) {\n  return os_user_permitted(why);", "bool sd_os_permitted(PRIV_WHY* why) {\n  return os_permitted(why);")),
    ("os_gate_open() asks the program instead of the account", sub("op_sh.c", "return MY_PRIV(USR_ADMIN | USR_OS_EXEC);", "return (process.program.flags & HDR_INTERNAL) != 0;")),
    ("containment compares prefixes without a component boundary", sub("op_dio2.c", "return ((cand[root_len] == '" + chr(92) + "0') || (cand[root_len] == '/'));", "return 1;")),
    ("containment no longer resolves the name (links, relative names)", sub("op_sh.c", "if (!fullpath(resolved, (char *)name))", "if (!strcpy(resolved, name))")),
    ("containment no longer folds the candidate into the account's namespace", sub("op_dio2.c", "  if (!net_normalise(path, cand))\n    return FALSE;\n", "  strcpy(cand, path);\n")),
    ("an unresolved .. is allowed", sub_after("op_dio2.c", "bool account_path_permitted(char* path,", "if (has_parent_ref(cand))", "if (0)")),
    ("OPENSEQ hook moved below the port test", lambda srcs: _move_seq_hook(srcs)),
    ("OPENPATH hook removed", sub("op_dio1.c", "if (!net_may_write && !(map_name ? net_vocpath_permitted(pathname, FALSE) : net_path_permitted(pathname, FALSE))) {", "if (0) {")),
    ("OPENPATH asks only the network sessions' question", sub("op_dio1.c", "net_may_write = map_name ? net_vocpath_permitted(pathname, TRUE) : net_path_permitted(pathname, TRUE);", "net_may_write = net_vocpath_permitted(pathname, TRUE);")),
    ("a pathname open is let through for a console session", sub("op_dio2.c", "  return account_path_permitted(path, for_write);", "  return TRUE;")),
    ("OPENPATH hook asks before the name is resolved", swap("op_dio1.c", "  fullpath(pathname, mapped_name);\n", "  net_may_write = map_name ? net_vocpath_permitted(pathname, TRUE) : net_path_permitted(pathname, TRUE);\n")),
    ("os_path_inside asks the gate (a caller can no longer use it for geometry)", sub("op_dio2.c", "  return path_within(cand, root);\n}", "  return os_gate_open() || path_within(cand, root);\n}")),
    ("os_path_inside takes a relative directory", sub("op_dio2.c", "  if (!os_root_absolute(rootdir))\n    return FALSE;\n", "")),
    ("os_path_inside tests the directory only after resolving it", swap("op_dio2.c", "  if (!os_root_absolute(rootdir))\n    return FALSE;\n", "  if (!fullpath(rr, (char*)rootdir) || !fullpath(cc, (char*)name))\n    return FALSE;\n")),
    ("os_path_inside accepts a whole-machine root", sub("op_dio2.c", "  if (os_root_whole_machine(root))\n    return FALSE;\n", "")),
    ("a drive root no longer counts as the whole machine", sub("op_dio2.c", "return (n == 2) && (w[1] == ':');", "return FALSE;")),
    ("'/' no longer counts as the whole machine", sub("op_dio2.c", 'if (strcmp(r, "/") == 0)', 'if (strcmp(r, "//") == 0)')),
    ("a drive-relative name ('C:x') counts as absolute", sub("op_dio2.c", "(d[1] == ':') && ((d[2] == '/') || (d[2] == '" + chr(92) + chr(92) + "'))", "(d[1] == ':')")),
    ("kernel(K_SH) lets any caller set the flag", sub("op_kernel.c", "case K_SH:\n      GetInt(descr);\n      n = descr->data.value;\n      if (n >= 0) {\n        if (process.program.flags & HDR_INTERNAL)\n", "case K_SH:\n      GetInt(descr);\n      n = descr->data.value;\n      if (n >= 0) {\n        if (1)\n")),
    ("kernel(K_PATH_OK) answers the caller's question", sub("op_kernel.c", "os_path_ok_for_account(path_ok_name)", "os_path_open_ok(path_ok_name)")),
    # 13 Nov 26 Windows port: the Python gate is sdpy_session.c's may_start_helper; "is Python running?" must not start the helper
    ("the Python gate asks the program", sub("sdpy_session.c", "return sd_os_permitted(why) ? 1 : 0;", "return (process.program.flags & HDR_INTERNAL) ? 1 : 0;")),
    ("the Python gate is gone", sub("sdpy_session.c", "if (!may_start_helper(&why)) {", "if (0) {")),
    ("PY_RUNSTR no longer goes through the helper (and its gate)", sub("op_sdext.c", "    case SD_PyRunStr:\n      py_ext_int(", "    case SD_PyRunStr:\n      py_ext_none(")),
    ("'is Python running?' starts a helper (and so meets the gate)", sub("op_sdext.c", "  if (sdpy_session_running()) {", "  if (1) {")),
    ("key K_SH renumbered in the kernel only", sub("keys.h", "#define K_SH                 93", "#define K_SH                 92")),
    ("key K_OS_EXEC clashes with K_SH", sub("keys.h", "#define K_OS_EXEC            94", "#define K_OS_EXEC            93")),
    ("USR_SH and USR_OS_EXEC share a bit", sub("sysseg.h", "USR_OS_EXEC     0x0200", "USR_OS_EXEC     0x0100")),
    ("LOGTO no longer loads the grants", sub("cproc", "   void kernel(K$SH,      not(ri.active) and (upcase(trim(acc.record<ACC$SH>)) = 'YES'))\n", "")),
    ("LOGTO loads them after the audit line", swap("cproc", "   gosub load.account.switches   ;* the account-scoped switches, from the new account's own register record (3 Nov 26: one routine, shared with RUN.IN)", "   void kernel(K$AUDIT, 'logto account=' : new.account)")),
    ("LOGTO no longer calls load.account.switches", sub("cproc", "   gosub load.account.switches   ;* the account-scoped", "   gosub nothing.loaded   ;* the account-scoped")),
    ("LOGTO no longer loads the SD.ACCOUNTS gate", sub("cproc", "   void kernel(K$SD.ACCOUNTS, upcase(trim(acc.record<ACC$SD.ACCOUNTS>)) = 'YES')", "   void kernel(K$SD.ACCOUNTS, 1)")),
    ("LOGIN grants the SD.ACCOUNTS gate to everyone", sub("login", "void kernel(K$SD.ACCOUNTS, upcase(trim(acc.rec<ACC$SD.ACCOUNTS>)) = 'YES')", "void kernel(K$SD.ACCOUNTS, 1)")),
    # 13 Nov 26 Windows port: the SD.ACCOUNTS walk is op_dio2.c's
    ("the SD.ACCOUNTS test lets a suspended account in", sub("op_dio2.c", "if (strcasecmp(line[4], \"SUSPENDED\") == 0)\n      continue;", "")),
    ("the SD.ACCOUNTS test ignores the user's groups", sub("op_dio2.c", "if (!win32_group_has_member(process.username, line[2], &member, why, sizeof(why)) || !member)\n      continue;", "")),
    ("the SD.ACCOUNTS test opens the VOC of the account", sub("op_dio2.c", "      found = FALSE;\n    else\n      found = TRUE;", "      found = TRUE;\n    else\n      found = TRUE;")),
    ("the SD.ACCOUNTS test trusts an unexpanded @ token", sub("op_dio2.c", "    } else if (line[0][0] == '@') {\n      continue;", "    } else if (0) {\n      continue;")),
    ("the SH verb gate is removed", sub("cproc", "   if not(kernel(K$ADMINISTRATOR, -1)) and not(sh.listed) then\n      display sysmsg(10053, @logname)", "   if @false then\n      display sysmsg(10053, @logname)")),
    ("the SH verb gate no longer reads the account's grant", sub("cproc", "   sh.listed = kernel(K$SH, -1)\n", "   sh.listed = @true\n")),
    ("the SH verb gate comes after the command has run", swap("cproc", "   if not(kernel(K$ADMINISTRATOR, -1)) and not(sh.listed) then\n      display sysmsg(10053, @logname) ;* %1 is not permitted to use the shell\n      return\n   end\n", "   os.execute os.command.text\n")),
    ("LOGIN grants everyone both", sub("login", "void kernel(K$SH,      upcase(trim(acc.rec<ACC$SH>)) = 'YES')", "void kernel(K$SH,      1)")),
    ("a new account is on both routes by default again", sub("create_account", "access.ssh = (settings<CA$ROUTE.SSH> = 1)", "access.ssh = settings<CA$ROUTE.SSH> # '0'")),
    ("a new account gets the shell by default", sub("create_account", "os.sh   = settings<CA$OS.SH> = 1", "os.sh   = settings<CA$OS.SH> # '0'")),
    ("ATTACH turns the four on again for the installing user", sub("create_account", "         return\n      end\n* 23 Oct 26 Windows port - from Linux abcda0c", "         return\n      end\n      access.ssh = @true\n      os.sh = @true\n* 23 Oct 26 Windows port - from Linux abcda0c")),
    ("a GROUP account may be given a shell", sub("create_account", "     if os.sh or os.exec then\n       @system.return.code = -ER$ARGS\n       err = 10105:@vm:acc.name ;* %1 is a group account", "     if @false then\n       @system.return.code = -ER$ARGS\n       err = 10105:@vm:acc.name ;* %1 is a group account")),
    ("a GROUP account may be given a route", sub("create_account", "     if access.given then\n       @system.return.code = -ER$ARGS\n       err = 10087", "     if @false then\n       @system.return.code = -ER$ARGS\n       err = 10087")),
    ("an OTHER account may be given a shell", sub("create_account", "     if os.sh or os.exec then\n       @system.return.code = -ER$ARGS\n       err = 10105", "     if @false then\n       @system.return.code = -ER$ARGS\n       err = 10105")),
    ("the register is written without the gate fields", sub("create_account", "      acc.rec<ACC$SH> = if os.sh then 'yes' else 'no'\n", "")),
    ("CREATE.ACCOUNT OS-ON sets the wrong field", sub("createa", "         case upcase(token) = 'OS-ON'\n            os.exec = @true", "         case upcase(token) = 'OS-ON'\n            os.sh = @true")),
    ("CREATE.ACCOUNT never passes OS-ON on", sub("createa", "if os.exec then settings<CA$OS.EXECUTE> = 1", "if @false then settings<CA$OS.EXECUTE> = 1")),
    ("MODIFY.ACCOUNT SH-OFF turns the shell on", sub("modifya", "case upcase(action) = 'SH-OFF'\n            os.field = ACC$SH\n            os.want  = @false", "case upcase(action) = 'SH-OFF'\n            os.field = ACC$SH\n            os.want  = @true")),
    ("MODIFY.ACCOUNT OS-ON changes the shell field", sub("modifya", "case upcase(action) = 'OS-ON'\n            os.field = ACC$OS.EXEC", "case upcase(action) = 'OS-ON'\n            os.field = ACC$SH")),
    ("os.set writes without the lock", sub("modifya", "   readu acc.new from acc.f, acc.name else acc.new = acc.rec\n   if os.want", "   acc.new = acc.rec\n   if os.want")),
    ("micro needs no grant", sub("edit", "   if kernel(K$OS.EXEC, -1) then\n      permitted = @true\n      return\n   end\n", "   permitted = @true\n   return\n")),
    ("the manifest leaves out os.sh", sub("acc_os_info", "info<-1> = 'os.sh: '", "info<-1> = 'zz.sh: '")),
    ("upgrade_gates tests its marker after the walk", swap("upgrade_gates", "   if ospath(marker, OS$EXISTS) then", "   select acc.f to 12")),
    ("upgrade_gates writes the marker even when a record failed", sub("upgrade_gates", "   if failed # 0 then", "   if @false then")),
    # 13 Nov 26 Windows port: Core's walk copies os.users into blank fields
    ("upgrade_gates touches group accounts", sub("upgrade_gates", "if downcase(rec<ACC$GROUP>[1, 4]) = 'sdu_' then", "if @true then")),
    ("upgrade_gates overwrites an explicit no in sh (24 Oct: a keep-accounts reinstall turned the gates back on)", sub("upgrade_gates", "if trim(rec<ACC$SH>) = '' then\n               rec<ACC$SH> = 'no'", "if @true then\n               rec<ACC$SH> = 'no'")),
    ("upgrade_gates overwrites an explicit no in os.execute", sub("upgrade_gates", "if trim(rec<ACC$OS.EXEC>) = '' then\n               rec<ACC$OS.EXEC> = 'no'", "if @true then\n               rec<ACC$OS.EXEC> = 'no'")),
    ("upgrade_gates gives sh to every blank account, whatever os.users said", sub("upgrade_gates", "if upcase(trim(osu.rec<1>)) = 'YES' then rec<ACC$SH> = 'yes'", "rec<ACC$SH> = 'yes'")),
    ("upgrade_gates counts only yes / yes as done, so a no / no is written", sub("upgrade_gates", "if trim(rec<ACC$SH>) # '' and trim(rec<ACC$OS.EXEC>) # '' then", "if upcase(trim(rec<ACC$SH>)) = 'YES' and upcase(trim(rec<ACC$OS.EXEC>)) = 'YES' then")),
    ("DIR() no longer asks", sub("op_dio4.c", "if (!os_path_open_ok(pathname)) {", "if (0) {")),
    ("DELETESEQ of a pathname no longer asks", sub("op_seqio.c", "if (!os_path_open_ok(file_name)) {\n      process.status = ER_PERM;\n      goto exit_op_delseq;", "if (0) {\n      process.status = ER_PERM;\n      goto exit_op_delseq;")),
    ("a print unit's pathname is no longer asked", sub("to_file.c", "if (!os_path_ok_for_account(fn)) {", "if (0) {")),
    ("a print unit's pathname asks the printing program, not the account", sub("to_file.c", "os_path_ok_for_account(fn)", "os_path_open_ok(fn)")),
    ("only the raw pathname of a print unit is asked, not the $hold marker's", lambda srcs: _gate_only_raw_print_path(srcs)),
    ("SELECT.DIR no longer asks", sub("seldir", "if not(kernel(K$PATH.OK, path)) then", "if @false then")),
    ("!OSCOPY asks about the source only", sub("_oscopy", " or not(kernel(K$PATH.OK, target))", "")),
    ("!OSCOPY no longer asks", sub("_oscopy", "if not(kernel(K$PATH.OK, source)) or not(kernel(K$PATH.OK, target)) then", "if @false then")),
    ("!IOSCOPY no longer asks", sub("_ioscopy", "if not(kernel(K$PATH.OK, source)) or not(kernel(K$PATH.OK, target)) then", "if @false then")),
    ("the OSCOPY verb says nothing about -4", sub("oscopya", "case status = -4\n         display sysmsg(12185, @who)", "case status = -4\n         display sysmsg(12066, source, target)")),
    ("SETPTR AS PATHNAME no longer asks", sub("setptr", "if not(kernel(K$PATH.OK, file.name)) then", "if @false then")),
    ("the API server no longer loads the switches", sub("apisrvr", "void kernel(K$SH,      api.sh.grant)", "void kernel(K$SH,      0)")),
    ("the API server grants everybody OS.EXECUTE", sub("apisrvr", "void kernel(K$OS.EXEC, api.os.grant)", "void kernel(K$OS.EXEC, 1)")),
    ("the API server's switches carry over from the previous call", sub("apisrvr", "api.sh.grant = @false\napi.os.grant = @false\n", "")),
    ("the API server loads the switches before the account has been entered", swap("apisrvr", "void kernel(K$SH,      api.sh.grant)    ;* 23 Oct 26 - S.63, Linux abcda0c: see where they were read, above\nvoid kernel(K$OS.EXEC, api.os.grant)\n", "if not(ospath(account.path, OS$CD)) then")),      # 13 Nov 26 Windows port: Core's line carries a comment
    ("the Account:File form sets the path itself, past the Q-pointer checks", sub("_voc_ref", "         voc.rec = 'Q' : @fm : field(voc.id, ':', 1) : @fm : field(voc.id, ':', 2)\n         goto parse.as.q.pointer",
                                                                                     "         pathname = field(voc.id, ':', 2)\n         set.status 0\n         return")),
    ("a Q-pointer into any account is followed again",sub("_voc_ref", "               if not(vr.admin) then\n                  gosub check.q.hop", "               if @false then\n                  gosub check.q.hop")),
    ("a Q-pointer into a registered account asks nothing of an account that holds os-on", sub("_voc_ref", "q.ok = is_grp_member(@logname, q.group)", "q.ok = vr.free or is_grp_member(@logname, q.group)")),
    ("a Q-pointer into a suspended account is followed", sub("_voc_ref", "if upcase(trim(q.susp)) # 'SUSPENDED' then", "if @true then")),
    ("a Q-pointer into an account the user is not a member of is followed", sub("_voc_ref", "q.ok = is_grp_member(@logname, q.group)", "q.ok = @true")),
    ("the stock Q-pointers are refused too (sd.accounts breaks)", sub("_voc_ref", "if stock.found and upcase(stock.rec[1,1]) = 'Q' and stock.rec<2> = q.named", "if @false and upcase(stock.rec[1,1]) = 'Q' and stock.rec<2> = q.named")),
    ("any Q-pointer id passes the stock test (the pointer is not compared)", sub("_voc_ref", " and stock.rec<2> = q.named and stock.rec<3> = voc.rec<3> then", " then")),
    ("an F-pointer to a path outside the account is followed again", sub("_voc_ref", "            if not(vr.free) then\n               gosub check.f.path", "            if @false then\n               gosub check.f.path")),
    ("an F-pointer is checked by id only (the path is not compared with the stock one)", sub("_voc_ref", "upcase(stock.rec[1,1]) = 'F' and stock.rec<fno> = f.raw", "upcase(stock.rec[1,1]) = 'F'")),
    ("the directory of an account a Q-pointer led into is not trusted", sub("_voc_ref", "path.ok = kernel(K$PATH.IN, qroot : @fm : pathname)", "path.ok = @false")),
    ("the administrator is held to the Q-pointer rule", sub("_voc_ref", "vr.admin = kernel(K$ADMINISTRATOR, -1)", "vr.admin = @false")),
    ("kernel(K_PATH_IN) asks the gate (a caller can no longer use it for geometry)", sub("op_kernel.c", "os_path_inside(path_in_buf, path_in_sep + 1) ? 1 : 0", "os_path_ok_for_account(path_in_sep + 1) ? 1 : 0")),
    # 13 Nov 26 Windows port: the installer mutants, aimed at sd.iss and upgrade-gates.ps1
    ("the installer stops running upgrade_gates", sub("sd.iss", "    GatesMsg := RefreshGates;\n", "")),
    ("upgrade-gates.ps1 runs some other program", sub("upgrade-gates.ps1", "'UPGRADE_GATES', 'NO.PAGE')", "'UPGRADE_NOTHING', 'NO.PAGE')")),
    ("the installer runs upgrade_gates after the installing user's account is made", swap("sd.iss", "    GatesMsg := RefreshGates;\n", "    AttachCode := AttachInstallerAccount;\n")),
    ("upgrade_gates runs on a first install too", sub("sd.iss", "  if DataTreeWasAbsent then Exit;\n\n  SayStep('Carrying each account", "\n  SayStep('Carrying each account")),
    ("the installer aborts when upgrade_gates fails", sub("sd.iss", "              'folder.' + #13#10#13#10;\n  end;\nend;", "              'folder.' + #13#10#13#10;\n    Abort;\n  end;\nend;")),
    ("upgrade-gates.ps1 no longer tests for COMPLETE", sub("upgrade-gates.ps1", r"$complete = $Text -match '(?m)^\s*COMPLETE\s*$'", "$complete = $true")),
]


def selftest(srcs, messages_dir):
    print("--- self-test: each mutation must be CAUGHT by at least one check ---")
    base_bad = [n for n, ok, _ in checks(srcs, messages_dir) if not ok]
    if base_bad:
        print("REFUSING - the unmutated source already fails: %s" % ", ".join(base_bad), file=sys.stderr)
        return 2
    holes = 0
    for name, fn in MUTANTS:
        mutated = fn(srcs)
        if mutated == srcs:
            print("  [FAIL] %s: the mutation did not change the file (this test no longer understands the source)" % name)
            holes += 1
            continue
        caught = [n for n, ok, _ in checks(mutated, messages_dir) if not ok]
        if caught:
            print("  [pass] %s: caught by %s" % (name, ", ".join(caught[:4])))
        else:
            print("  [FAIL] %s: NOT CAUGHT by any check" % name)
            holes += 1
    print("\n%d of %d mutants caught" % (len(MUTANTS) - holes, len(MUTANTS)))
    return 1 if holes else 0


def main(argv):
    srcs = {}
    for name, path in FILES.items():
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                srcs[name] = f.read()
        except OSError as exc:
            print("CANNOT RUN - %s: %s" % (path, exc), file=sys.stderr)
            return 2
    messages_dir = os.path.join(SDSYS, "messages")
    print("reading %d sources under %s" % (len(srcs), SD64))
    if "--selftest" in argv:
        return selftest(srcs, messages_dir)
    rows = checks(srcs, messages_dir)
    if not rows:
        print("REFUSING - no checks ran", file=sys.stderr)
        return 2
    failed = 0
    for name, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, ("   <- " + detail) if (detail and not ok) else ""))
        failed += 0 if ok else 1
    print("\n%d passed, %d failed" % (len(rows) - failed, failed))
    print("NOT MEASURED HERE: whether any gate refuses anybody.  On Linux that is sandbox-gates.py and witness-accounts.sh; "
          "neither is carried to Windows (13 Nov 26), so here it is a running install's verify suite.")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
