#!/usr/bin/env python3
# test-segtrust-units.py - W.11 F9 (security-model evaluation, 24 Oct 2026): what a process TRUSTS is not read from the shared segment.  FREE CHECK, text
# only (comments removed), no install, no sudo, no sd.
#
#   python sdb_ai/sd64/gplbld/test-segtrust-units.py
#   python sdb_ai/sd64/gplbld/test-segtrust-units.py --selftest      (mutants)
#   (13 Nov 26 Windows port - from Linux b1d496df, RELEASE_1.1 254: K_OS_EXEC's case is followed by K_SD_ACCOUNTS here; otherwise Linux's
#   text.  On Windows the segment's wall is the shm folder's ACL, sdusers only - test-shmmode-units.)
#
# The segment is 0660 sdusers (F1), and every SD user with an operating-system shell is in sdusers, so whatever other processes TAKE from the segment
# is something such a user can write.  Four things were taken from it (plan: .claude/plan-f9-segment-trust.md):
#
#   S1  the system directory: no source file reads sysseg->sysdir to decide a path (sysseg.c assigns it and compares it, sysdump.c prints it), they ask sd_sysdir()
#   S2  sd_sysdir() (config.c) reads SDSYS= of the [sd] section of the CONFIGURATION FILE, tolerantly, never the segment
#   S3  a session (bind_sysseg's attach branch) takes the process configuration (pcfg) from read_config(), not from the segment's template, and
#       a failure returns directly - it must not reach exit_bind_sysseg, whose stop_sd() would take the running SD down
#   S4  the p-code every session runs is read from <sysdir>/bin/pcode into the process (and refused if others or sdusers can write it), not run from the segment
#   S5  the session's privilege bits (administrator, SH, OS.EXECUTE, SD.ACCOUNTS) and its gates word are decided from process-private words
#       (my_priv_flags, my_priv_gates): no source line reads them from my_uptr->flags / my_uptr->gates
#   S6  the setters write both, the private word first; each key case uses them; kernel.c zeroes both where it zeroes the entry
# NOT SAID HERE: that a session ignores a changed segment - that is sandbox-segtrust.py.  What is NOT closed (the lock, file and user tables) is in the plan.
import glob
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "gplsrc"))
passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def code(name):
    path = os.environ.get("SEG_" + re.sub(r"\W", "_", name).upper(), os.path.join(SRC, name))
    s = open(path, encoding="latin-1").read()
    s = re.sub(r"/\*.*?\*/", "", s, flags=re.S)
    return re.sub(r"//[^\n]*", "", s)


def func(src, head):
    # the definition, not a prototype: after the head comes a "{" before any ";"
    m = re.search(re.escape(head) + r"[^;{]*\{.*?\n\}", src, re.S)
    return m.group(0) if m else ""


def between(src, a, b):
    i = src.find(a)
    j = src.find(b, i + len(a)) if i >= 0 else -1
    return src[i:j] if i >= 0 and j >= 0 else ""


ALLOWED_SYSDIR = {"sysseg.c": 2, "sysdump.c": 1}     # sysseg.c: the assignment from the configuration and the comparison; sysdump.c: the printed line
PRIV_FLAGS = r"USR_(ADMIN|SH|OS_EXEC|SD_ACCOUNTS)\b"


def run():
    names = sorted(os.path.basename(p) for p in glob.glob(os.path.join(SRC, "*.c")))

    # --- S1 ------------------------------------------------------------------------------------------------------------------
    bad = []
    for n in names:
        c = code(n).count("sysseg->sysdir")
        if c != ALLOWED_SYSDIR.get(n, 0):
            bad.append("%s:%d (allowed %d)" % (n, c, ALLOWED_SYSDIR.get(n, 0)))
    row("S1 no source file but sysseg.c (2) and sysdump.c (1) reads sysseg->sysdir", not bad, ", ".join(bad))
    sd_ = code("sysseg.c")
    row("S1 sysseg.c: the two uses are the assignment from the configuration and the comparison with it",
        bool(re.search(r"strcpy\(\(char\*\)\(sysseg->sysdir\), cfg->sysdir\)", sd_)) and bool(re.search(r"strcmp\(\(const char \*\)\(sysseg->sysdir\), c->sysdir\)", sd_)))

    # --- S2 ------------------------------------------------------------------------------------------------------------------
    cf = code("config.c")
    body = func(cf, "const char* sd_sysdir(void)")
    row("S2 sd_sysdir() is defined in config.c", bool(body))
    row("S2 sd_sysdir() never mentions the segment", bool(body) and "sysseg" not in body, body[:200])
    row("S2 it asks the configuration scan once and keeps the answer", "config_sysdir_scan(" in body and "trusted_sysdir" in body)
    scan = func(cf, "Private bool config_sysdir_scan(char *out)")
    row("S2 config_sysdir_scan() is defined, reads config_path, takes SDSYS= of the SD section only, the last one as read_config() does",
        bool(scan) and "fopen(config_path" in scan and 'strcmp(section, "SD")' in scan and 'strncmp(rec, "SDSYS=", 6)' in scan and "sysseg" not in scan, scan[:200])
    row("S2 sd_sysdir_trust() sets the private copy", "trusted_sysdir" in func(cf, "void sd_sysdir_trust(const char* dir)"))

    # --- S3 ------------------------------------------------------------------------------------------------------------------
    attach = between(sd_, "if (attach_shared_memory()) {", "if (!create) {")
    row("S3 the attach branch is found", bool(attach))
    row("S3 the attach branch no longer copies the segment's template into pcfg", bool(attach) and "pcfg_offset" not in attach and "memcpy(&pcfg" not in attach, attach[:200])
    row("S3 it calls session_trust() and, if that fails, unbinds, forgets the segment and RETURNS (no goto exit_bind_sysseg: that runs stop_sd())",
        bool(re.search(r"if \(!session_trust\(errmsg\)\) \{\s*unbind_sysseg\(\);\s*sysseg = NULL;\s*return FALSE;\s*\}", attach)), attach[:300])
    st = func(sd_, "Private bool session_trust(char* errmsg)")
    row("S3 session_trust() is defined", bool(st))
    i_mem, i_read, i_trust = st.find("memset(&pcfg, 0, sizeof(pcfg))"), st.find("read_config("), st.find("sd_sysdir_trust(c->sysdir)")
    row("S3 it clears pcfg, then reads the configuration file, then makes the file's system directory the trusted one", 0 <= i_mem < i_read < i_trust, "%d %d %d" % (i_mem, i_read, i_trust))
    row("S3 it does not stop SD, does not touch the segment's template and frees what read_config() allocated",
        "stop_sd" not in st and "pcfg_offset" not in st and "k_free(c)" in st)
    create = between(sd_, "if ((cfg = read_config(errmsg)) == NULL)", "max_users = cfg->max_users;")
    row("S3 the starter makes its own system directory the trusted one right after read_config()", "sd_sysdir_trust(cfg->sysdir)" in create, create[:200])

    # --- S4 ------------------------------------------------------------------------------------------------------------------
    sdc = code("sd.c")
    lp = func(sdc, "Private bool load_pcode(char *pname, u_char **ptr)")
    row("S4 load_pcode() is found", bool(lp))
    row("S4 load_pcode() searches the process's own image and never the segment", "pcode_image" in lp and "sysseg" not in lp, lp[:200])
    row("S4 sd.c never reads the segment's pcode copy", "pcode_offset" not in sdc and "pcode_len" not in sdc and "sysseg->pcode" not in sdc)
    rp = func(sdc, "Private bool read_pcode_image(void)")
    row("S4 read_pcode_image() reads <sd_sysdir()>/bin/pcode and says so when there is no system directory",
        bool(rp) and bool(re.search(r'"%s%cbin%cpcode", sd_sysdir\(\), DS, DS', rp)) and "sd_sysdir()[0] == '\\0'" in rp, rp[:200])
    row("S4 it refuses a file that others, or the group sdusers, can write, and one it cannot examine",
        "fstat(" in rp and "S_IWOTH" in rp and "S_IWGRP" in rp and 'getgrnam("sdusers")' in rp)
    row("S4 it reads the whole file or fails", "malloc(" in rp and "read(" in rp and "!= pcode_image_len" in rp)

    # --- S5 ------------------------------------------------------------------------------------------------------------------
    bad = []
    for n in names + ["sysseg.h"]:
        for ln in code(n).split("\n"):
            if "my_uptr->flags" in ln and re.search(PRIV_FLAGS, ln):
                bad.append("%s: %s" % (n, ln.strip()[:80]))
            if "my_uptr->gates" in ln and n not in ("kernel.c", "sysseg.h"):
                bad.append("%s: %s" % (n, ln.strip()[:80]))
    row("S5 no line reads or writes a privilege bit or the gates word through my_uptr (outside the macros and kernel.c's zeroing)", not bad, "; ".join(bad[:6]))
    sh = code("sysseg.h")
    row("S5 sysseg.h holds the two private words and their macros",
        all(t in sh for t in ("my_priv_flags", "my_priv_gates", "#define MY_PRIV(", "#define MY_ADMIN()", "#define MY_GATE(", "#define SET_MY_PRIV(", "#define SET_MY_GATE(")))
    row("S5 and the prototype of sd_sysdir()", "const char *sd_sysdir(void);" in sh)

    # --- S6 ------------------------------------------------------------------------------------------------------------------
    sp = between(sh, "#define SET_MY_PRIV(", "#define SET_MY_GATE(")
    row("S6 SET_MY_PRIV() writes the private word and then the segment's copy", bool(sp) and 0 <= sp.find("my_priv_flags") < sp.find("my_uptr->flags"), sp[:200])
    sg = sh[sh.find("#define SET_MY_GATE("):][:600]
    row("S6 SET_MY_GATE() writes the private word and then the segment's copy", "my_priv_gates" in sg and 0 <= sg.find("my_priv_gates") < sg.find("my_uptr->gates"), sg[:200])
    ok = code("op_kernel.c")
    # each case from its label to the label that follows it in the source
    for case, nxt, word in (("K_ADMINISTRATOR", "K_SET_ACCOUNT", "USR_ADMIN"), ("K_SH", "K_OS_EXEC", "USR_SH"), ("K_OS_EXEC", "K_SD_ACCOUNTS", "USR_OS_EXEC"),      # 13 Nov 26 Windows: K_SD_ACCOUNTS follows here
                            ("K_SD_ACCOUNTS", "K_VOC_EDIT", "USR_SD_ACCOUNTS")):
        blk = between(ok, "case %s:" % case, "case %s:" % nxt)
        row("S6 %s sets %s with SET_MY_PRIV() and answers from MY_PRIV()" % (case, word), bool(blk) and ("SET_MY_PRIV(" + word) in blk and ("MY_PRIV(" + word + ")") in blk and "my_uptr" not in blk, blk[:160])
    for case, nxt in (("K_DICT_EDIT", "K_NET"), ("K_NET", "K_EDIT_OK"), ("K_SHARED_WRITE", "K_SHARED_REF")):
        blk = between(ok, "case %s:" % case, "case %s:" % nxt)
        row("S6 %s sets the gate with SET_MY_GATE() and answers from MY_GATE(), and never reads my_uptr" % case,
            bool(blk) and "SET_MY_GATE(" in blk and "MY_GATE(" in blk and "my_uptr" not in blk, blk[:160])
    kc = code("kernel.c")
    row("S6 kernel.c zeroes both private words where it zeroes the user table entry's flags and gates",
        "my_priv_flags = 0;" in kc and "my_priv_gates = 0;" in kc and "my_uptr->gates = 0;" in kc and kc.find("my_priv_flags = 0;") < kc.find("my_uptr->flags = 0;"))
    print("test-segtrust-units: %d passed, %d failed" % (passed, failed))
    return 0 if failed == 0 else 1


# (name, file, old text, new text): each puts one trusted read back where the segment was read before, or takes one safeguard out.  All of the 24 Oct F9 sitting.
MUTANTS = [
    ("object-reads-segment-dir", "object.c", '"%s%cgcat%c%s", sd_sysdir(),', '"%s%cgcat%c%s", sysseg->sysdir,'),
    ("messages-read-segment-dir", "messages.c", '"%s%cmessages", sd_sysdir(),', '"%s%cmessages", sysseg->sysdir,'),
    ("audit-reads-segment-dir", "k_error.c", '"%s%caudit", sd_sysdir(), DS', '"%s%caudit", sysseg->sysdir, DS'),
    ("sysdir-opcode-reads-segment", "op_dio2.c", "(char*)sd_sysdir()", "(char*)(sysseg->sysdir)"),
    ("sd-sysdir-reads-segment", "config.c", "(void)config_sysdir_scan(trusted_sysdir);",
     'snprintf(trusted_sysdir, sizeof(trusted_sysdir), "%s", (const char *)sysseg->sysdir);'),
    ("scan-any-section", "config.c", '!strcmp(section, "SD") && ', ""),
    ("scan-wrong-key", "config.c", '&& (strncmp(rec, "SDSYS=", 6) == 0)) {', '&& (strncmp(rec, "SDSYS ", 6) == 0)) {'),
    ("attach-copies-template", "sysseg.c", "    if (!session_trust(errmsg)) {",
     "    memcpy(&pcfg, ((char*)sysseg) + sysseg->pcfg_offset, sizeof(struct PCFG));\n    if (!session_trust(errmsg)) {"),
    ("session-failure-stops-sd", "sysseg.c", "      unbind_sysseg();\n      sysseg = NULL;\n      return FALSE;", "      goto exit_bind_sysseg;"),
    ("session-trust-no-memset", "sysseg.c", "  memset(&pcfg, 0, sizeof(pcfg)); /* the template used to replace every byte of it */\n", ""),
    ("session-trust-keeps-sysdir", "sysseg.c", "  sd_sysdir_trust(c->sysdir);\n  if (strcmp(", "  if (strcmp("),
    ("session-trust-leaks", "sysseg.c", "  k_free(c);\n  return TRUE;", "  return TRUE;"),
    ("starter-no-trust", "sysseg.c", "  sd_sysdir_trust(cfg->sysdir); /* W.11 F9", "  (void)0; /* W.11 F9"),
    ("pcode-from-segment", "sd.c", "  pcode = pcode_image;", "  pcode = ((u_char *)sysseg) + sysseg->pcode_offset;"),
    ("pcode-length-from-segment", "sd.c", "i < pcode_image_len;", "i < sysseg->pcode_len;"),
    ("pcode-others-may-write", "sd.c", "(st.st_mode & S_IWOTH) ||", "0 ||"),
    ("pcode-wrong-group", "sd.c", 'getgrnam("sdusers")', 'getgrnam("nobody")'),
    ("pcode-short-read-ok", "sd.c", "read(fd, pcode_image, pcode_image_len) != pcode_image_len", "read(fd, pcode_image, pcode_image_len) < 0"),
    ("pcode-no-sysdir", "sd.c", '"%s%cbin%cpcode", sd_sysdir(), DS, DS', '"%s%cbin%cpcode", "", DS, DS'),
    ("admin-from-entry-op_sh", "op_sh.c", "  if (MY_ADMIN())\n    return TRUE;\n  switch (kind) {", "  if (my_uptr->flags & USR_ADMIN)\n    return TRUE;\n  switch (kind) {"),
    ("gate-from-entry-op_sh", "op_sh.c", "return MY_GATE(UG_VOC_EDIT);", "return (my_uptr->gates & UG_VOC_EDIT) != 0;"),
    ("os-exec-from-entry", "op_sh.c", "} else if (MY_PRIV(USR_OS_EXEC)) {", "} else if (my_uptr->flags & USR_OS_EXEC) {"),
    ("sd-accounts-from-entry", "op_sh.c", "return MY_PRIV(USR_SD_ACCOUNTS) &&", "return (my_uptr->flags & USR_SD_ACCOUNTS) &&"),
    ("net-gate-from-entry", "netfiles.c", "return MY_ADMIN() || MY_GATE(UG_NET);", "return ((my_uptr->flags & USR_ADMIN) != 0) || MY_GATE(UG_NET);"),
    ("object-admin-from-entry", "object.c", "!(flags & OBJ_GLOBAL) && !MY_ADMIN())", "!(flags & OBJ_GLOBAL) && !(my_uptr->flags & USR_ADMIN))"),
    ("sh-setter-only-segment", "op_kernel.c", "SET_MY_PRIV(USR_SH, n > 0);", "if (n > 0) my_uptr->flags |= USR_SH; else my_uptr->flags &= ~USR_SH;"),
    ("os-getter-from-entry", "op_kernel.c", "result.data.value = MY_PRIV(USR_OS_EXEC);", "result.data.value = (my_uptr->flags & USR_OS_EXEC) != 0;"),
    ("net-getter-from-entry", "op_kernel.c", "        result.data.value = MY_GATE(UG_NET);\n        break;", "        result.data.value = (my_uptr->gates & UG_NET) != 0;\n        break;"),
    ("priv-macro-no-private-word", "sysseg.h", "my_priv_flags |= (u_int16_t)(bits); my_uptr->flags |= (bits);", "my_uptr->flags |= (bits);"),
    ("gate-macro-no-private-word", "sysseg.h", "my_priv_gates |= (u_int16_t)(bit); my_uptr->gates |= (u_int16_t)(bit);", "my_uptr->gates |= (u_int16_t)(bit);"),
    ("kernel-no-zero", "kernel.c", "    my_priv_flags = 0; /* 24 Oct 26", "    (void)0; /* 24 Oct 26"),
]


def selftest():
    import shutil
    t = tempfile.mkdtemp()
    caught = missed = 0

    def mutant(name, which, old, new):
        nonlocal caught, missed
        real = open(os.path.join(SRC, which), encoding="latin-1").read()
        if old not in real:
            print("  [MISSED] %s: the text to change is not there" % name)
            missed += 1
            return
        f = os.path.join(t, name + "-" + which)
        open(f, "w", encoding="latin-1").write(real.replace(old, new, 1))
        env = dict(os.environ)
        env["SEG_" + re.sub(r"\W", "_", which).upper()] = f
        r = subprocess.run([sys.executable, os.path.abspath(__file__)], env=env, capture_output=True, text=True)
        if r.returncode != 0:
            print("  [caught] %s (exit %d)" % (name, r.returncode))
            caught += 1
        else:
            print("  [MISSED] %s: the check still passed" % name)
            missed += 1

    print("selftest: the real files first (must pass), then mutants (each must not)")
    r = subprocess.run([sys.executable, os.path.abspath(__file__)], capture_output=True, text=True)
    if r.returncode != 0:
        print("  [FAIL] the real files do not pass:\n" + r.stdout[-900:])
        return 1
    print("  [ok] the real files pass")
    for m in MUTANTS:
        mutant(*m)
    shutil.rmtree(t, ignore_errors=True)
    print("selftest: %d of %d mutants caught, %d missed" % (caught, caught + missed, missed))
    return 0 if missed == 0 and caught > 0 else 1


if __name__ == "__main__":
    sys.exit(selftest() if "--selftest" in sys.argv else run())
