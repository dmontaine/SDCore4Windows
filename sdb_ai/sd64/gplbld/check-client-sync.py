"""Is the shipped API client in sync across the three trees?

THE DUTY IS THE OWNER'S, 26 Aug 2026: "..\\sdclilib32 and ..\\winsdclilib are the
two other directories that contain the api clients that have been maintained by
this project and need to be in sync with the files internal to the project.
those were created so that client installers could be made as opposed to the
user having to look through the installed system to find them."

WHY A SCRIPT RATHER THAN A HABIT.  PROJECT_STATUS records what the absence of
this check has already cost, twice:

  - the 32-bit client SHIPPED SENDING PASSWORDS IN CLEAR, built from a
    winsdclilib that had not moved since 15 Aug and had no SCRAM in it, "with
    nothing in either project able to report it";
  - the SV_EMSG_PAIR / SV_ECONTXT transposition survived from 5 to 15 Aug 2026
    in three repositories at once.

Both were found by a human running a grep on a hunch.  Neither was found by
anything that runs.

WHAT IT CHECKS
  1. gplsrc/sdclilib is THE SOURCE OF TRUTH and ../winsdclilib is a MIRROR of
     it - so the seven source files must be byte-identical.  The arrow turned
     round on 19 Aug 2026; do not reverse it.
  2. ../sdclilib32 HOLDS NO SOURCE.  Its Makefile SRCDIR must point INTO this
     tree - one hop.  It pointed at ../winsdclilib until 19 Aug 2026, which is
     the two-hop arrangement that let the 32-bit client lag.
  3. Its built DLLs must be NEWER than the library source they were built from.

  Exit 0 in sync - 1 out of sync - 2 could not run.

THE NULL CASE IS REFUSED OUT LOUD.  A missing sibling, a missing file list, or
a source directory with no files in it exits 2, not 0: "nothing differed"
because nothing was compared is the failure this project names most often.
"""

import hashlib
import io
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
# gplbld -> sd64 -> sdb_ai -> repo root -> Projects
REPO = os.path.normpath(os.path.join(HERE, os.pardir, os.pardir, os.pardir))
PROJECTS = os.path.normpath(os.path.join(REPO, os.pardir))

TRUTH = os.path.join(REPO, "sdb_ai", "sd64", "gplsrc", "sdclilib")
MIRROR = os.path.join(PROJECTS, "winsdclilib")
LIB32 = os.path.join(PROJECTS, "sdclilib32")

# THE THREE PATHS ARE OVERRIDABLE SO THIS CAN BE WATCHED FAILING.  A checker
# that can only ever run against the real trees exits 0 forever and nobody
# learns whether it still works - the same argument that put a control test
# beside check-stale-leads.py.  "--self-test" builds broken fixtures in %TEMP%
# and requires a non-zero exit from each; see self_test() at the foot.
SELF_TEST = "--self-test" in sys.argv
if not SELF_TEST and len(sys.argv) == 4:
    TRUTH, MIRROR, LIB32 = (os.path.abspath(p) for p in sys.argv[1:4])

# The library's source set.  Listed rather than globbed: a file that stops
# being copied to the mirror would silently leave a glob-driven comparison.
FILES = ["err.h", "revstamp.h", "scram_client.h", "sdclient.h",
         "sdclilib.bi", "sdclilib.c", "sdclilib.h"]

def self_test():
    """Build broken fixtures and require this script to REJECT each one.

    Case [0] is a POSITIVE control - an intact fixture set must PASS, or every
    rejection below it proves only that the script dislikes %TEMP%.
    """
    import shutil
    import subprocess
    import tempfile

    def build(root, mirror_edit=None, srcdir=None, dll_old=False,
              extra_mirror=None):
        t = os.path.join(root, "truth")
        m = os.path.join(root, "winsdclilib")
        l = os.path.join(root, "sdclilib32")
        for d in (t, m, l):
            os.makedirs(d)
        for f in FILES:
            body = "/* %s */\n" % f
            io.open(os.path.join(t, f), "w", newline="").write(body)
            b = body
            if mirror_edit == f:
                b = body + "/* the mirror drifted */\n"
            io.open(os.path.join(m, f), "w", newline="").write(b)
        if extra_mirror:
            io.open(os.path.join(m, extra_mirror), "w", newline="").write("x\n")
        rel = srcdir if srcdir else os.path.relpath(t, l).replace("\\", "/")
        io.open(os.path.join(l, "Makefile"), "w", newline="").write(
            "SRCDIR ?= %s\n" % rel)
        dll = os.path.join(l, "qmclilib.dll")
        io.open(dll, "w", newline="").write("MZ\n")
        if dll_old:
            old = min(os.path.getmtime(os.path.join(t, f)) for f in FILES) - 600
            os.utime(dll, (old, old))
        return t, m, l

    def run(t, m, l):
        env = dict(os.environ)
        env["PYTHONIOENCODING"] = "utf-8"
        p = subprocess.run([sys.executable, os.path.abspath(__file__), t, m, l],
                           env=env, capture_output=True, text=True,
                           encoding="utf-8")
        return p.returncode, (p.stdout or "") + (p.stderr or "")

    cases = [
        ("intact fixtures must PASS (positive control)", {}, 0),
        ("a drifted mirror file", {"mirror_edit": "sdclilib.c"}, 1),
        ("SRCDIR pointing via the mirror (two-hop)",
         {"srcdir": "../winsdclilib"}, 1),
        ("a DLL older than the source", {"dll_old": True}, 1),
        ("mirror carrying source the truth lacks",
         {"extra_mirror": "rogue.c"}, 1),
    ]
    ok = 0
    print("=== self-test: does check-client-sync REJECT what it should? ===")
    for name, kw, want in cases:
        root = tempfile.mkdtemp(prefix="clisync-")
        try:
            t, m, l = build(root, **kw)
            rc, _out = run(t, m, l)
            good = (rc == want)
            ok += 1 if good else 0
            print("  [%s] %-46s rc=%d (want %d)"
                  % ("PASS" if good else "FAIL", name, rc, want))
        finally:
            shutil.rmtree(root, ignore_errors=True)
    # A missing sibling must REFUSE (2), not pass.
    root = tempfile.mkdtemp(prefix="clisync-")
    try:
        t, m, l = build(root)
        shutil.rmtree(m)
        rc, out = run(t, m, l)
        good = (rc == 2 and "CANNOT RUN" in out)
        ok += 1 if good else 0
        print("  [%s] %-46s rc=%d (want 2)"
              % ("PASS" if good else "FAIL", "a missing sibling must REFUSE", rc))
    finally:
        shutil.rmtree(root, ignore_errors=True)

    total = len(cases) + 1
    print("")
    print("  %d of %d self-test cases passed." % (ok, total))
    return 0 if ok == total else 1


if SELF_TEST:
    sys.exit(self_test())


rows = []


def note(ok, what, detail=""):
    rows.append((ok, what, detail))
    print("  [%s] %s%s" % ("PASS" if ok else "FAIL", what,
                           ("  " + detail) if detail else ""))


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest().upper()


def refuse(msg):
    print("")
    print("check-client-sync: CANNOT RUN - " + msg)
    sys.exit(2)


print("=== what this run is comparing ====================================")
print("  source of truth : %s" % TRUTH)
print("  mirror          : %s" % MIRROR)
print("  32-bit build    : %s" % LIB32)
print("  files           : %d" % len(FILES))
print("")

for p, label in ((TRUTH, "source of truth"), (MIRROR, "mirror"),
                 (LIB32, "32-bit build")):
    if not os.path.isdir(p):
        refuse("%s is not a directory: %s" % (label, p))

# THE NULL CASE.  An empty or renamed source directory would make every
# comparison below vacuous.
present = [f for f in FILES if os.path.isfile(os.path.join(TRUTH, f))]
if len(present) != len(FILES):
    refuse("the source of truth is missing %s - the file list is wrong, or "
           "the library moved" % ", ".join(sorted(set(FILES) - set(present))))

print("=== [1] the mirror must be byte-identical to the source ===========")
for f in FILES:
    a = os.path.join(TRUTH, f)
    b = os.path.join(MIRROR, f)
    if not os.path.isfile(b):
        note(False, "mirror has " + f, "MISSING")
        continue
    ha, hb = sha(a), sha(b)
    note(ha == hb, "identical: " + f,
         ha[:16] if ha == hb else ("src=%s mirror=%s" % (ha[:16], hb[:16])))

# And the other direction: a file the mirror has and the source does not means
# the mirror is carrying something nothing here can regenerate.
extra = []
for f in os.listdir(MIRROR):
    if re.search(r"\.(c|h|bi)$", f) and f not in FILES:
        extra.append(f)
note(not extra, "mirror carries no source the truth lacks",
     ("EXTRA: " + ", ".join(sorted(extra))) if extra else "")

print("")
print("=== [2] sdclilib32 must point INTO this tree, one hop ==============")
mk = os.path.join(LIB32, "Makefile")
if not os.path.isfile(mk):
    refuse("no Makefile in " + LIB32)
with io.open(mk, encoding="utf-8", errors="replace", newline="") as fh:
    mktext = fh.read()
m = re.search(r"^\s*SRCDIR\s*\??=\s*(\S+)", mktext, re.M)
if not m:
    refuse("no SRCDIR assignment in " + mk)
srcdir = m.group(1)
print("  SRCDIR = %s" % srcdir)
resolved = os.path.normpath(os.path.join(LIB32, srcdir))
print("  resolves to %s" % resolved)
note(os.path.normcase(resolved) == os.path.normcase(TRUTH),
     "SRCDIR resolves to the source of truth")
# The specific regression: it pointed at the MIRROR until 19 Aug 2026, which is
# the two-hop arrangement that let the 32-bit client ship without SCRAM.
note("winsdclilib" not in srcdir,
     "SRCDIR does not go via the mirror (the two-hop fault)")

print("")
print("=== [3] the 32-bit build must be newer than the source ============")
newest_src, newest_name = 0.0, ""
for f in FILES:
    t = os.path.getmtime(os.path.join(TRUTH, f))
    if t > newest_src:
        newest_src, newest_name = t, f


def stamp(t):
    import datetime
    return datetime.datetime.fromtimestamp(t).strftime("%d %b %Y %H:%M:%S")


print("  newest library source : %s  (%s)" % (stamp(newest_src), newest_name))
dlls = [f for f in os.listdir(LIB32) if f.lower().endswith(".dll")]
if not dlls:
    note(False, "sdclilib32 holds a built DLL", "none found - never built here")
for d in sorted(dlls):
    t = os.path.getmtime(os.path.join(LIB32, d))
    note(t >= newest_src, "%s is not older than the source" % d, stamp(t))

print("")
print("=== summary =======================================================")
bad = [r for r in rows if not r[0]]
print("  %d checked, %d failed" % (len(rows), len(bad)))
if bad:
    print("")
    for _, what, detail in bad:
        print("  OUT OF SYNC: %s  %s" % (what, detail))
    print("")
    print("check-client-sync: OUT OF SYNC - read the rows above.")
    print("  gplsrc/sdclilib is the SOURCE; push to the mirror, do not pull.")
    sys.exit(1)
print("")
print("check-client-sync: IN SYNC - the mirror matches the source byte for")
print("  byte, sdclilib32 builds straight from this tree, and its DLLs are")
print("  not older than the source they were built from.")
