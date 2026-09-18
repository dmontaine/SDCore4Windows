#!/usr/bin/env python3
r"""test-groupmember-units.py - K$GROUP.MEMBER answers THREE ways, and the third
must never collapse into the second.  Free: no install, no elevation, no run
token, no SD.  RELEASE_1.1 55.

WHAT IT GUARDS.  gplsrc/win32group.c answers "is USER in GROUP" as
1 / 0 / could-not-tell, and that third answer is the whole point of the file:
a lookup that FAILED used to arrive as "not a member", the account gate read it
as "not granted", and a DLL-initialisation failure was investigated as a
refused grant for seven runs (b184-b190).  The contract has three layers and
each is kept by hand:

  C      win32_group_has_member() returns FALSE (not TRUE-with-0) when the
         group does not exist or the lookup failed, and sets *member = 0
         before its guards so a caller that ignores the return value reads 0
         rather than stack.
  KERNEL op_kernel.c's K_GROUP_MEMBER case starts from -1 and takes the
         member value ONLY on the answered path.
  BASIC  gpl.bp/is_grp_member maps 1 -> @true, 0 -> @false, -1 -> @false
         WITH status 1, and every caller either reads status() or is declared
         here as deliberately fail-closed, with the reason.

Nothing in the tree exercises the C except an authenticated API session on a
cycled install, so this builds probe-groupmember.c against the LIVE
win32group.c with the sd target's own compiler and flags (Makefile C_FLAGS,
MSYS2's gcc through its own bash, the way cycle.ps1 runs make) and asks it
real questions about real groups.  The oracle for the real rows is whoami
/groups - the token's own view of the current user's membership, an
instrument that shares no code with the thing under test.

THE ROWS THAT MATTER are the ones a two-valued answer cannot pass: a group
that does not exist (NERR_GroupNotFound, 2220) must be told=0, and a user who
is not in a real group must be told=1 member=0 - DIFFERENT lines for "no" and
"cannot say".  A MUTANT copy of win32group.c that reports the missing group as
an ordinary "no" is built and driven too, and the guard must see the
difference; a check that has never been seen to fail is not yet a check.

NOTES, FOUND BY WRITING THE PARTITION (17 Sep 2026).  Seventeen call sites,
not seven: a hand-typed file list had missed login and modifya, which is the
kind of miss a walk does not make.  ONE site reads status(); sixteen fail
closed, and two of those write an audit reason that still conflates the two
answers - apisrvr's sdapi gate says 'not in sdapi' and LOGIN says 'not a
member of sdusers' on a could-not-tell as well as on a real no.  Neither is
wrong to refuse; each is the vb.account shape before 55 split branch=4.  They
are DECLARED here, not fixed here, so the conflation is on record rather than
hidden by a green row.

Exit 0 every row passed, 1 a row failed, 2 the compiler or a source is not
there or the oracle could not answer - never a vacuous pass.

SD_GPLSRC and SD_GPLBP override the two source trees (used to drive it against
copies); SD_MSYS_BASH overrides the MSYS2 bash.
"""

import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
GPLSRC = os.environ.get("SD_GPLSRC") or os.path.join(HERE, "..", "gplsrc")
GPLBP = os.environ.get("SD_GPLBP") or os.path.join(HERE, "..", "sdsys", "gpl.bp")
MSYS_BASH = os.environ.get("SD_MSYS_BASH") or r"C:\msys64\usr\bin\bash.exe"
PROBE_SRC = os.path.join(HERE, "probe-groupmember.c")
WHOAMI = os.path.join(os.environ.get("SystemRoot", r"C:\Windows"), "System32", "whoami.exe")

# The sd target's C_FLAGS (Makefile), minus the include path only the full
# tree has.  Same compiler, same standard, same warnings: a probe that built
# under a different dialect would be measuring a different file.
CFLAGS = ("-std=gnu17 -Wall -Wformat=2 -Wno-format-nonliteral "
          "-D_FILE_OFFSET_BITS=64 -DGPL")

ADMINS = "S-1-5-32-544"
USERS = "S-1-5-32-545"

# Every is_grp_member() call site in gpl.bp is one of these two.  Keyed by
# file and the call's own line, stripped, so a line number moving does not
# break it and a second call on the same file cannot hide behind the first.
# READS_STATUS: the next statement captures status(), so -1 is distinguished.
# FAIL_CLOSED: the caller takes @false either way, deliberately, and the
# reason says why that is acceptable THERE.  A site in neither fails, so a new
# caller cannot be written without somebody deciding which it is.
READS_STATUS = {
    ("apisrvr", "acc.member = is_grp_member(kernel(K$USERNAME, 0), acc.group)"):
        "vb.account: acc.told = status() on the next line; branch=4 splits "
        "group.lookup.failed from not.in.group in the audit trail",
}
FAIL_CLOSED = {
    ("apisrvr", "if not(is_grp_member(scram.user, 'sdapi')) then"):
        "the sdapi gate at SCRAM: an access check fails closed; the refusal "
        "reason 'not in sdapi' does not tell a failed lookup from a real no "
        "(the same conflation vb.account no longer has - see NOTES)",
    ("cproc", "if not(is_grp_member(@logname,acc.record<ACC$GROUP>)) then"):
        "the logto gate: an access check fails closed with 10003",
    ("createa", "if not(is_grp_member(acc.uname,'sdusers')) then"):
        "create account: a could-not-tell goes on to os_group ADDMEM, which "
        "is idempotent and reports its own failure",
    ("createa", 'if adopt or is_grp_member(acc.uname, "S-1-5-32-544") then'):
        "create account: asked about the well-known Administrators SID, "
        "which always resolves; a could-not-tell would add the user to "
        "sdsshonly, which os_group can undo",
    ("granta", "if is_grp_member(user, grp) then"):
        "grant: a could-not-tell falls through to os_group ADDMEM, which "
        "reports its own failure rather than claiming success",
    ("granta", "if not(is_grp_member(user, grp)) then"):
        "revoke: a could-not-tell reports 'has not been granted', which the "
        "site's own comment already accepts for an orphaned SID",
    ("login", "if not(is_grp_member(lgn.id,'sdusers')) then"):
        "the sdusers gate at LOGIN: an access check fails closed with 5009; "
        "the audit reason 'not a member of sdusers' does not tell a failed "
        "lookup from a real no (see NOTES)",
    ("modifya", "if is_grp_member(user.name,'sdusers') then"):
        "group add: a could-not-tell refuses the add as 'not in sdusers'; "
        "an administrator's verb, nothing is granted by mistake",
    ("modifya", "if is_grp_member(user.name,group.name) THEN"):
        "group add/delete (two sites, same line): 'already a member' is "
        "skipped and os_group ADDMEM/DELMEM reports its own failure",
    ("modifya", "user.ok = is_grp_member(acc.user,'sdusers')"):
        "account.user: a could-not-tell refuses with 10020, fail closed",
    ("modifya", "has.ssh = is_grp_member(acc.user, 'sdssh')"):
        "route change: a could-not-tell reads as 'does not have it', so the "
        "idempotent ADDMEM runs and reports its own failure",
    ("modifya", "has.api = is_grp_member(acc.user, 'sdapi')"):
        "route change: same as has.ssh",
}

# 18 Sep 26 - RELEASE_1.1 64 DELETED TWO DECLARED SITES: the administrator
# refusal in route.set and the tier-set was.admin probe.  The tiers are gone,
# so nothing asks about the Administrators SID in MODIFYA any more; the sites
# and their entries above left together.

checks = 0
fails = 0


def check(ok, text):
    global checks, fails
    checks += 1
    if not ok:
        fails += 1
    print("  [%s] %s" % ("PASS" if ok else "FAIL", text))
    return ok


def cannot(text):
    print("test-groupmember-units: CANNOT RUN - %s" % text)
    sys.exit(2)


def msys_path(p):
    """C:\\a\\b -> /c/a/b, for a command handed to MSYS2's bash."""
    p = os.path.abspath(p).replace("\\", "/")
    if len(p) > 1 and p[1] == ":":
        p = "/" + p[0].lower() + p[2:]
    return p


def msys(cmd):
    """Run one command line inside MSYS2's own bash, the way cycle.ps1 runs
    make - the gcc there does not start from any other shell."""
    env = dict(os.environ, MSYSTEM="MSYS")
    r = subprocess.run([MSYS_BASH, "-lc", cmd], capture_output=True,
                       text=True, env=env)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def build(workdir, group_c, exe_name):
    """Compile the probe against ONE win32group.c into workdir.  Returns the
    exe's MSYS path; prints the command it ran, per the instrument rule."""
    exe = os.path.join(workdir, exe_name)
    cmd = ("cd %s && gcc %s -I%s -o %s %s %s -lnetapi32"
           % (msys_path(workdir), CFLAGS, msys_path(GPLSRC), msys_path(exe),
              msys_path(PROBE_SRC), msys_path(group_c)))
    print("  build: %s" % cmd)
    rc, out = msys(cmd)
    if rc != 0 or not os.path.isfile(exe):
        cannot("gcc failed (rc %d):\n%s" % (rc, out.strip()))
    if out.strip():
        # -Wall is on; a warning is not a build failure but it is printed.
        print("  gcc said: %s" % out.strip())
    return msys_path(exe)


LINE = re.compile(r"^user=(.*) group=(.*) told=(\d) member=(-?\d+) why=(.*)$")


def ask(exe, user, group):
    """Drive the probe once.  Returns (told, member, why) and prints the raw
    line - the inputs are in it, which is what makes it evidence."""
    cmd = "%s '%s' '%s'" % (exe, user or "-", group or "-")
    rc, out = msys(cmd)
    line = out.strip().splitlines()[-1] if out.strip() else ""
    print("    %s" % (line or "(no output, rc %d)" % rc))
    m = LINE.match(line)
    if rc != 0 or not m:
        cannot("the probe did not answer for %r / %r: rc %d, %r"
               % (user, group, rc, out))
    return int(m.group(3)), int(m.group(4)), m.group(5)


def token_groups():
    """whoami /groups as {SID: bare group name}; the oracle for the real rows.
    Only groups the token holds are listed, deny-only ones included, which is
    exactly the membership fact a live SAM query should agree with."""
    r = subprocess.run([WHOAMI, "/groups", "/fo", "csv", "/nh"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        cannot("whoami /groups failed: %s" % (r.stderr or r.stdout).strip())
    out = {}
    for row in r.stdout.splitlines():
        cells = [c.strip('"') for c in row.split('","')]
        if len(cells) >= 3 and cells[2].startswith("S-"):
            out[cells[2]] = cells[0].split("\\")[-1]
    return out


def mutate(src, dst):
    """A COPY of win32group.c whose 'group not found / lookup failed' branch
    answers like an ordinary no.  The live file is never touched; the copy
    is asserted to differ in exactly one place."""
    with open(src, encoding="latin-1") as f:
        text = f.read()
    marker = "NetLocalGroupGetMembers(%.80s) failed, status %lu"
    at = text.find(marker)
    if at < 0:
        cannot("the mutant's anchor is not in win32group.c any more")
    tail = text[at:]
    n_before = tail.count("return 0;")
    tail2 = tail.replace("return 0;", "*member = 0; return 1;", 1)
    if tail2.count("return 0;") != n_before - 1:
        cannot("the mutant did not land exactly once")
    with open(dst, "w", encoding="latin-1", newline="") as f:
        f.write(text[:at] + tail2)


def static_rows():
    """The KERNEL and BASIC layers of the contract, read from source."""
    opk = os.path.join(GPLSRC, "op_kernel.c")
    with open(opk, encoding="latin-1") as f:
        text = f.read()
    start = text.find("case K_GROUP_MEMBER:")
    if start < 0:
        cannot("op_kernel.c has no K_GROUP_MEMBER case")
    nxt = re.search(r"\n\s*case K_", text[start + 10:])
    body = text[start:start + 10 + (nxt.start() if nxt else len(text))]
    call = body.find("win32_group_has_member(")
    minus1 = body.find("result.data.value = -1;")
    check(call > 0 and 0 < minus1 < call,
          "op_kernel.c: K_GROUP_MEMBER starts from -1 before it asks")
    takes = [m.start() for m in re.finditer(r"result\.data\.value = member;", body)]
    check(len(takes) == 1 and takes[0] > call
          and "if (win32_group_has_member(" in body,
          "op_kernel.c: the member value is taken once, on the answered path only")

    igm = os.path.join(GPLBP, "is_grp_member")
    with open(igm, encoding="latin-1") as f:
        src = [l.rstrip("\r\n") for l in f]
    code = [l for l in src if not l.lstrip().startswith("*")]
    joined = "\n".join(code)
    check("kernel(K$GROUP.MEMBER, user : @fm : group)" in joined,
          "is_grp_member asks K$GROUP.MEMBER with user<FM>group")
    m = re.search(r"case grp\.answer = 1\s*\n\s*user_found = @true", joined)
    check(bool(m), "is_grp_member: 1 -> @true")
    m = re.search(r"case grp\.answer = 0\s*\n\s*user_found = @false", joined)
    check(bool(m), "is_grp_member: 0 -> @false")
    m = re.search(r"case 1\s*\n(?:\s*\*.*\n)*\s*user_found = @false\s*\n\s*set\.status 1",
                  joined)
    check(bool(m), "is_grp_member: anything else -> @false WITH status 1 "
                   "(the row this file exists for)")

    # The caller partition.
    sites = []
    for name in sorted(os.listdir(GPLBP)):
        if name == "is_grp_member":
            continue
        path = os.path.join(GPLBP, name)
        if not os.path.isfile(path):
            continue
        with open(path, encoding="latin-1") as f:
            for i, line in enumerate(f, 1):
                s = line.strip()
                if s.startswith("*") or "is_grp_member(" not in s.lower():
                    continue
                if s.lower().startswith("deffun"):
                    continue
                sites.append((name, i, s))
    check(len(sites) >= 5,
          "control: the walk found real call sites (%d)" % len(sites))
    unclassified = []
    for name, i, s in sites:
        key = (name, s)
        if key in READS_STATUS:
            tag = "reads status()"
        elif key in FAIL_CLOSED:
            tag = "fail-closed"
        else:
            tag = "UNCLASSIFIED"
            unclassified.append("%s:%d %s" % (name, i, s))
        print("    %-8s %-4d %-14s %s" % (name, i, tag, s[:60]))
    check(not unclassified,
          "every caller reads status() or is declared fail-closed with a "
          "reason (unclassified: %s)" % ("; ".join(unclassified) or "none"))
    stale = [k for k in list(READS_STATUS) + list(FAIL_CLOSED)
             if k not in {(n, s) for n, _, s in sites}]
    check(not stale, "no declared site has gone (stale: %s)"
          % ("; ".join("%s: %s" % k for k in stale) or "none"))
    # The one declared reader must really read it on the next statement.
    for (name, s), why in READS_STATUS.items():
        path = os.path.join(GPLBP, name)
        with open(path, encoding="latin-1") as f:
            lines = [l.strip() for l in f]
        try:
            at = lines.index(s)
        except ValueError:
            continue
        nxt = next((l for l in lines[at + 1:at + 4] if l and not l.startswith("*")), "")
        check("status()" in nxt,
              "%s: the statement after the call captures status() (%s)" % (name, nxt))


def main():
    print("test-groupmember-units")
    for p, what in ((os.path.join(GPLSRC, "win32group.c"), "win32group.c"),
                    (os.path.join(GPLSRC, "win32group.h"), "win32group.h"),
                    (os.path.join(GPLSRC, "op_kernel.c"), "op_kernel.c"),
                    (os.path.join(GPLBP, "is_grp_member"), "is_grp_member"),
                    (PROBE_SRC, "probe-groupmember.c")):
        if not os.path.isfile(p):
            cannot("%s is not there (%s)" % (what, os.path.normpath(p)))
    if not os.path.isfile(MSYS_BASH):
        cannot("MSYS2's bash is not at %s; the sd toolchain is what builds the "
               "probe" % MSYS_BASH)
    if not os.path.isfile(WHOAMI):
        cannot("%s is not there" % WHOAMI)

    user = os.environ.get("USERNAME") or ""
    domain = os.environ.get("USERDOMAIN") or ""
    if not user:
        cannot("USERNAME is not set, so there is no real user to ask about")
    groups = token_groups()
    in_admins = ADMINS in groups
    in_users = USERS in groups
    print("  user %s (domain %s); whoami says Administrators=%s Users=%s"
          % (user, domain, int(in_admins), int(in_users)))
    if not (in_admins or in_users):
        cannot("whoami puts %s in neither Administrators nor Users, so no "
               "positive row can be measured" % user)

    print("")
    print("Static: the KERNEL and BASIC layers")
    static_rows()

    workdir = tempfile.mkdtemp(prefix="sd-groupmember-")
    try:
        print("")
        print("Live: the C, built from %s" % os.path.normpath(GPLSRC))
        exe = build(workdir, os.path.join(GPLSRC, "win32group.c"), "probe-live.exe")
        nosuch = "NoSuchGroup%d" % os.getpid()
        nouser = "NoSuchUser%d" % os.getpid()

        t, m, w = ask(exe, "", USERS)
        check(t == 0 and m == 0, "empty user: could not tell (told=0), member left at 0")
        t, m, w = ask(exe, user, "")
        check(t == 0 and m == 0, "empty group: could not tell (told=0), member left at 0")
        t, m, w = ask(exe, user, nosuch)
        check(t == 0 and "2220" in w,
              "a group that does not exist is COULD NOT TELL, naming 2220 "
              "(NERR_GroupNotFound) - not an ordinary no")
        t, m, w = ask(exe, nouser, USERS)
        check(t == 1 and m == 0,
              "a user who is not in a real group is ANSWERED: told=1 member=0")
        t, m, w = ask(exe, user, ADMINS)
        check(t == 1 and m == int(in_admins),
              "%s / Administrators by SID agrees with whoami (%d)" % (user, int(in_admins)))
        t, m, w = ask(exe, user, USERS)
        check(t == 1 and m == int(in_users),
              "%s / Users by SID agrees with whoami (%d)" % (user, int(in_users)))

        # The name branch, the domain-qualified spelling and the case rule,
        # all on a group whoami says the user IS in, so each row is a 1 and a
        # broken comparison cannot pass as a coincidental 0.
        sid = USERS if in_users else ADMINS
        gname = groups[sid]
        t, m, w = ask(exe, user, gname)
        check(t == 1 and m == 1, "by NAME (%s): member, same as by SID" % gname)
        t, m, w = ask(exe, "%s\\%s" % (domain, user), sid)
        check(t == 1 and m == 1, "DOMAIN\\user spelling matches the bare name")
        t, m, w = ask(exe, user.swapcase(), sid)
        check(t == 1 and m == 1, "the user name is compared case-insensitively")

        print("")
        print("Mutant: a COPY whose lookup failure answers like a no")
        mut_c = os.path.join(workdir, "win32group.c")
        mutate(os.path.join(GPLSRC, "win32group.c"), mut_c)
        shutil.copy(os.path.join(GPLSRC, "win32group.h"), workdir)
        mexe = build(workdir, mut_c, "probe-mutant.exe")
        t, m, w = ask(mexe, user, nosuch)
        check(t == 1 and m == 0,
              "control: the mutant DOES report the missing group as told=1 "
              "member=0, so the row above is the one that would catch it")
        with open(os.path.join(GPLSRC, "win32group.c"), encoding="latin-1") as f:
            check("*member = 0; return 1;" not in f.read(),
                  "the live win32group.c does not carry the mutant")
    finally:
        shutil.rmtree(workdir, ignore_errors=True)

    print("")
    print("test-groupmember-units: %d checks, %d failed" % (checks, fails))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
