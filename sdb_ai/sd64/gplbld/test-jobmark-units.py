#!/usr/bin/env python3
# test-jobmark-units.py - the kernel's answer to "is THIS process a scheduled administrator job of SD's?" (kernel(K$JOB.MARK)).
#
#   python C:\Users\Don\Projects\SDCore4Windows\sdb_ai\sd64\gplbld\test-jobmark-units.py [--selftest]
#
# 10 Nov 26 Windows port - from Linux 5162a5d1 (S.102 stage 3), carry area 14.  Linux's guard drives sd_jobmark.c on a cgroup file and scratch files owned
# by the test's own uid.  Windows has no cgroup: the mark is the process TOKEN (win32jobmark.c: the local account SDSYS, a batch logon, elevated) and a claim
# ("sd -job <name>") that is only a key to an administrators-only definition.  So this builds gplsrc/sd_jobmark.c and gplsrc/win32jobmark.c with
# gplbld/verify-jobmark.c, with MSYS2's gcc through its own bash and the sd target's flags, and drives:
#   - the DEFINITION LOGIC on scratch files with a stand-in for the ACL test ("trust": a path of the right kind passes), which is Linux's rows less the
#     cgroup ones, with the claim in their place;
#   - the KERNEL'S OWN ACL TEST ("acl") on the same scratch files, which the test's user owns and may open: every one must be REFUSED;
#   - the KERNEL'S OWN TOKEN TEST asked of this very process (an interactive or network logon, never Task Scheduler's): REFUSED;
#   then the source rules a black box cannot see (the kernel passes its own single_command, the claim is only set by -JOB, LOGIN grants only on the mark).
#
# ROWS THAT CANNOT HOLD HERE, AND WHY (recorded, not dropped):
#   - Linux's cgroup rows (another unit, a user slice, two lines, a name below the unit): there is no cgroup; the claim rows stand in for the name rules.
#   - Linux's mode rows (group- or world-writable file or directory, a second hard link, a writable parent): st_mode and st_nlink mean nothing on the MSYS2
#     noacl mount.  Their Windows reading is the DACL and the owner, and a passing ACL needs a file owned by SYSTEM or Administrators, which an
#     unelevated free guard cannot make; so only the REFUSAL half is driven ("acl" rows).  That the kernel ADMITS an administrators-only definition is
#     the installed system's witness, with a real task.
#   - Linux's link rows: a junction or symbolic link to a right-looking file would need an ACL that passes first (see above); the reparse-point test is
#     read in win32jobmark.c, not driven.
#   - That Task Scheduler's S4U logon of SDSYS really carries BATCH, enabled Administrators and no NETWORK or INTERACTIVE: only a real task can say.
#
# Exit 0 every row passed (or every mutant killed), 1 a row failed (or a mutant survived), 2 it could not run (no MSYS2 gcc).  Fewer than 25 rows is a failure.

import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
INC = os.path.join(SD64, "gplsrc")
SRC = "sd_jobmark.c"
WSRC = "win32jobmark.c"
DRIVER = os.path.join(HERE, "verify-jobmark.c")
MSYS_BASH = os.environ.get("SD_MSYS_BASH") or os.path.join("C:" + os.sep, "msys64", "usr", "bin", "bash.exe")
CFLAGS = "-std=gnu17 -Wall -Wextra -Wformat=2 -Wno-format-nonliteral -D_FILE_OFFSET_BITS=64 -DGPL -O2"


def say(s=""):
    print(s, flush=True)


def msys_path(p):
    p = os.path.abspath(p).replace(os.sep, "/")
    if len(p) > 1 and p[1] == ":":
        p = "/" + p[0].lower() + p[2:]
    return p


def win_fwd(p):
    """C:/a/b - the form the kernel passes (win32_job_dir() answers forward slashes)."""
    return os.path.abspath(p).replace(os.sep, "/")


def msys(cmd):
    env = dict(os.environ, MSYSTEM="MSYS")
    r = subprocess.run([MSYS_BASH, "-lc", cmd], capture_output=True, text=True, env=env)
    return r.returncode, (r.stdout or ""), (r.stderr or "")


def build(tmp, src_dir, name):
    exe = os.path.join(tmp, name + ".exe")
    cmd = "gcc %s -I%s -o %s %s %s %s -ladvapi32 -luserenv" % (CFLAGS, msys_path(src_dir), msys_path(exe), msys_path(os.path.join(src_dir, SRC)),
                                                                 msys_path(os.path.join(src_dir, WSRC)), msys_path(DRIVER))
    rc, out, err = msys(cmd)
    return exe, rc, (out + err).strip(), cmd


def q(s):
    return "'" + s.replace("'", "'\\''") + "'"


def rows_for(exe, base):
    rows = []

    def row(label, ok, detail=""):
        rows.append((label, bool(ok), detail))

    n = [0]

    def scene(defn="name=nightly\ncommand=update.accounts all\n", dname="nightly"):
        n[0] += 1
        jd = os.path.join(base, "s%d" % n[0], "sd-jobs")
        os.makedirs(jd)
        if defn is not None:
            with open(os.path.join(jd, dname), "wb") as fh:
                fh.write(defn.encode() if isinstance(defn, str) else defn)
        return jd

    def ask(mode, jd, claim="nightly", command="update.accounts all"):
        rc, out, err = msys("%s %s %s %s %s" % (msys_path(exe), mode, q(win_fwd(jd)), q(claim), q(command)))
        return rc, out.strip() + ("" if not err.strip() else " [stderr] " + err.strip())

    jd = scene()
    rc, out = ask("trust", jd)
    row("ALLOW (trust): the claim nightly, a definition naming nightly and this very command: job=nightly", rc == 0 and out == "job=nightly", out)
    for command, why in (("update.accounts all ", "with a trailing space"), ("UPDATE.ACCOUNTS ALL", "in capitals"), ("update.accounts all; backup.account all", "with a second command"),
                         ("backup.account all", "another job's command"), ("", "empty")):
        rc, out = ask("trust", jd, command=command)
        row("REFUSE (trust): the session's command is %s: no job" % why, rc == 1 and out == "job=", out)
    for claim, why in (("other", "another job's name (no definition by that name)"), ("Nightly", "a name in capitals"), ("nightly-", "a name ending in a dash"),
                       ("a" * 33, "a name of 33 characters"), ("", "no name"), ("../s1/sd-jobs/nightly", "a path up and across"), ("night/ly", "a path below")):
        rc, out = ask("trust", jd, claim=claim)
        row("REFUSE (trust): the claim is %s: no job" % why, rc == 1 and out == "job=", repr(claim[:40]) + " " + out)
    for defn, why in (("name=other\ncommand=update.accounts all\n", "naming another job"),
                      ("command=update.accounts all\n", "with no name line"),
                      ("name=nightly\n", "with no command line"),
                      ("name=nightly\ncommand=update.accounts all\ncommand=backup.account all\n", "with two command lines"),
                      ("name=nightly\nname=nightly\ncommand=update.accounts all\n", "with two name lines"),
                      (b"name=nightly\ncommand=update.accounts all\x00x\n", "holding a NUL byte"),
                      ("name=nightly\ncommand=update.accounts all\n" + "#" * 5000 + "\n", "over 4 KB")):
        j2 = scene(defn=defn)
        rc, out = ask("trust", j2)
        row("REFUSE (trust): the definition is %s: no job" % why, rc == 1 and out == "job=", out)
    j2 = scene(defn=None)
    rc, out = ask("trust", j2)
    row("REFUSE (trust): no definition by the claim's name: no job", rc == 1 and out == "job=", out)
    j2 = scene()
    os.rename(os.path.join(j2, "nightly"), os.path.join(j2, "kept"))
    os.makedirs(os.path.join(j2, "nightly"))
    rc, out = ask("trust", j2)
    row("REFUSE (trust): a DIRECTORY by the claim's name: no job", rc == 1 and out == "job=", out)
    j2 = scene(defn="name=nightly\r\ncommand=update.accounts all\r\n")
    rc, out = ask("trust", j2)
    row("ALLOW (trust, Windows): a definition with CRLF line ends is read as the same lines: job=nightly", rc == 0 and out == "job=nightly", out)
    j2 = scene(defn="name=nightly\ncommand=backup.account all\n")
    rc, out = ask("trust", j2, command="backup.account all")
    row("ALLOW (trust): a command with a space (backup.account all) matches exactly: job=nightly", rc == 0 and out == "job=nightly", out)

    # the kernel's own ACL test: everything this test can make is the test user's and open to it, so every answer is no
    rc, out = ask("acl", jd)
    row("REFUSE (acl): the same right-looking definition, but its directory and file are the test user's (not SYSTEM's or Administrators' only): no job",
        rc == 1 and out == "job=", out)
    rc, out = ask("acl", os.path.join(base, "no-such-dir"))
    row("REFUSE (acl): a definitions directory that is not there: no job", rc == 1 and out == "job=", out)

    # the kernel's own token test, of this very process
    rc, o, e = msys("%s token" % msys_path(exe))
    out = (o.strip() + " " + e.strip()).strip()
    row("REFUSE (token): this test's own process is not Task Scheduler's elevated batch logon of SDSYS: token=0 with a reason",
        rc == 1 and out.startswith("token=0 why=") and len(out) > len("token=0 why="), out)
    return rows


def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()


def text_rows():
    rows = []
    opk = read(os.path.join(INC, "op_kernel.c"))
    ker = read(os.path.join(INC, "k_error.c"))
    sdc = read(os.path.join(INC, "sd.c"))
    w32 = read(os.path.join(INC, WSRC))
    lgn = read(os.path.join(SD64, "sdsys", "gpl.bp", "login"))
    src = read(os.path.join(SD64, "gpl.src")).split()
    case = opk[opk.find("    case K_JOB_MARK: {"):]
    case = case[:case.find("    } break;")]
    t, d, j = case.find("win32_job_token_ok("), case.find("win32_job_dir("), case.find("sd_job_name(")
    rows.append(("TEXT: the kernel asks the token first, names the directory from the registry, and compares its OWN single_command against the claim's definition, once per process",
                 0 < t < d < j and "sd_job_name(jdir, job_claim, single_command, win32_job_admin_path, jn, sizeof(jn)) == 0" in case
                 and "sd_job_active[0] == '\\0'" in case and "connection_type != CN_SOCKET" in case and "k_get_" not in case and "GetString" not in case, case[:120]))
    rows.append(("TEXT: audit_message() ends every record of a job's run with job=<name> (both forms of the record)",
                 'const char* jkey = (sd_job_active[0] != \'\\0\') ? " job=" : "";' in ker and ker.count("jkey, sd_job_active, Newline") == 2, ""))
    rows.append(("TEXT: sd_jobmark and win32jobmark are part of the sd binary (gpl.src)", "sd_jobmark" in src and "win32jobmark" in src, ""))
    rows.append(("TEXT: the directory is named from the profile list (GetAllUsersProfileDirectoryA), never from the environment, and the token needs BATCH, no NETWORK, no INTERACTIVE, enabled Administrators and the local SDSYS's SID",
                 "GetAllUsersProfileDirectoryA" in w32 and "getenv" not in w32 and "GetEnvironmentVariable" not in w32 and "if (!batch || net || inter)" in w32
                 and "if (!admins)" in w32 and '"%s\\\\SDSYS"' in w32 and "EqualSid(user, (PSID)sbuf)" in w32, ""))
    sets = [m.start() for m in re.finditer(r"job_claim = ", sdc)]
    rows.append(("TEXT: the claim is set only by -JOB in sd.c, from the next argument, and nowhere else in the kernel",
                 len(sets) == 1 and '!stricmp(argv[arg], "-JOB")' in sdc[max(0, sets[0] - 900):sets[0]]
                 and all("job_claim = " not in read(os.path.join(INC, f)) for f in os.listdir(INC) if f.endswith(".c") and f != "sd.c"), sets))
    code = "\n".join(l for l in lgn.split("\n") if not l.lstrip().startswith("*"))
    rows.append(("TEXT: LOGIN asks K$JOB.MARK once, only of an SDSYS login, and the SDSYS case admits on the mark; the grant says reason=scheduled job only for a job",
                 code.count("kernel(K$JOB.MARK, 0)") == 1 and "if upcase(@logname) = 'SDSYS' then job.name = kernel(K$JOB.MARK, 0)" in code
                 and "case upcase(@logname) = 'SDSYS' and (kernel(K$ADMINISTRATOR, -1) or job.name # '')" in code
                 and re.search(r"if job.name # '' then\s*\n\s*void kernel\(K\$AUDIT, 'elevation granted account=SDSYS reason=scheduled job'\)", code) is not None, ""))
    return rows


MUTANTS = [
    (SRC, "the command is not compared", "    if (!line_value(def, \"command\", val, sizeof val) || strcmp(val, command) != 0) return -1;\n", ""),
    (SRC, "the name line is not compared", "    if (!line_value(def, \"name\", val, sizeof val) || strcmp(val, claim) != 0) return -1;\n", ""),
    (SRC, "a name may end in a dash", "    if (n[len - 1] == '-') return 0;\n", ""),
    (SRC, "a duplicate key is taken", "            if (found != NULL) return 0;\n", ""),
    (SRC, "a NUL is allowed", "    if (memchr(def, '\\0', (size_t)n) != NULL) return -1;\n", ""),
    (SRC, "a CR is kept in the value", "            if (vlen > 0 && found[vlen - 1] == '\\r') vlen--;\n", ""),
    (SRC, "the claim's name is not checked", "    if (!name_ok(claim)) return -1;\n", ""),
    (WSRC, "any ACL is believed", "    if (owner == NULL || !(IsWellKnownSid(owner, WinLocalSystemSid) || IsWellKnownSid(owner, WinBuiltinAdministratorsSid))) {",
     "    if (0) {"),
    (WSRC, "any token is a job", "    if (!batch || net || inter) {", "    if (0) {"),
]
# (No mutant for the DACL walk alone: with the owner test in place every file this guard can make already fails, so taking the walk out changes no answer here -
#  an equivalent mutant for an unelevated guard.  Likewise the "not elevated" and the SID tests: the batch test refuses this process first.)


def selftest():
    say("test-jobmark-units --selftest")
    origs = {f: read(os.path.join(INC, f)) for f in (SRC, WSRC)}
    for f, name, old, new in MUTANTS:
        if origs[f].count(old) != 1:
            say("  CANNOT RUN - mutant %s: its text occurs %d times in %s (wanted 1)" % (name, origs[f].count(old), f))
            return 2
    tmp = tempfile.mkdtemp(prefix="jobmark-mut-")
    survivors = []
    try:
        d0 = os.path.join(tmp, "base")
        os.makedirs(d0)
        for f in (SRC, WSRC, "sd_jobmark.h"):
            shutil.copy(os.path.join(INC, f), d0)
        exe, rc, out, cmd = build(tmp, d0, "base-exe")
        if rc != 0 or out:
            say("  CANNOT RUN - the unmutated copy does not build cleanly:\n  " + cmd + "\n" + out)
            return 2
        base = os.path.join(tmp, "scenes-base")
        os.makedirs(base)
        rows = rows_for(exe, base)
        bad = [r for r in rows if not r[1]]
        say("  control : the real source, %d rows, %d failed" % (len(rows), len(bad)))
        if bad or len(rows) < 25:
            return 1
        for i, (f, name, old, new) in enumerate(MUTANTS):
            d = os.path.join(tmp, "m%d" % i)
            os.makedirs(d)
            for g in (SRC, WSRC, "sd_jobmark.h"):
                shutil.copy(os.path.join(INC, g), d)
            with open(os.path.join(d, f), "w", encoding="utf-8", newline="\n") as fh:
                fh.write(origs[f].replace(old, new))
            exe, rc, out, cmd = build(tmp, d, "mut%d" % i)
            if rc != 0:
                say("  [KILLED  ] %-45s (does not build)" % name)
                continue
            sc = os.path.join(tmp, "scenes-%d" % i)
            os.makedirs(sc)
            caught = [r for r in rows_for(exe, sc) if not r[1]]
            say("  [%s] %-45s %s" % ("KILLED  " if caught else "SURVIVED", name, ("%d row(s), first: %s" % (len(caught), caught[0][0][:70])) if caught else ""))
            if not caught:
                survivors.append(name)
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    for f in (SRC, WSRC):
        if read(os.path.join(INC, f)) != origs[f]:
            say("  FAILED - the live %s changed during the self-test" % f)
            return 1
    say("")
    if survivors:
        say("test-jobmark-units --selftest: FAILED - %d of %d mutants survived: %s" % (len(survivors), len(MUTANTS), ", ".join(survivors)))
        return 1
    say("test-jobmark-units --selftest: PASSED - %d of %d mutants killed." % (len(MUTANTS), len(MUTANTS)))
    return 0


def main():
    if not os.path.isfile(MSYS_BASH):
        say("test-jobmark-units: CANNOT RUN - no MSYS2 bash at %s (its gcc builds the probe)" % MSYS_BASH)
        return 2
    if "--selftest" in sys.argv[1:]:
        return selftest()
    say("test-jobmark-units")
    tmp = tempfile.mkdtemp(prefix="jobmark-")
    try:
        exe, rc, out, cmd = build(tmp, INC, "verify-jobmark")
        say("  build: %s" % cmd)
        say("  built: %s (%s)" % (exe, "clean" if rc == 0 and not out else "FAILED"))
        if rc != 0 or out:
            say(out)
            return 2 if rc == 127 else 1
        base = os.path.join(tmp, "scenes")
        os.makedirs(base)
        say("  scenes under %s" % base)
        rows = rows_for(exe, base) + text_rows()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)
    bad = [r for r in rows if not r[1]]
    for label, ok, detail in rows:
        say("  [%s] %s%s" % ("PASS" if ok else "FAIL", label, "" if ok or not detail else "  <- " + str(detail)))
    if len(rows) < 25:
        say("test-jobmark-units: FAILED - only %d rows (the null case)" % len(rows))
        return 1
    say("test-jobmark-units: %d passed, %d failed" % (len(rows) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
