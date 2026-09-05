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
  3. The built DLLs in BOTH siblings must be NEWER than the library source they
     were built from - ../sdclilib32's 32-bit pair AND ../winsdclilib's own
     shipped DLLs.  The mirror half was added 4 Sep 2026; before that a mirror
     whose SOURCE was current and whose SHIPPED DLL had never been rebuilt
     passed, which is the incident above wearing a clean shirt.

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
              extra_mirror=None, mirror_dll_old=False, no_mirror_dll=False):
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
        old = min(os.path.getmtime(os.path.join(t, f)) for f in FILES) - 600
        dll = os.path.join(l, "qmclilib.dll")
        io.open(dll, "w", newline="").write("MZ\n")
        if dll_old:
            os.utime(dll, (old, old))
        # THE MIRROR SHIPS A DLL TOO, AND THE FIXTURE HAD NONE - so before
        # 4 Sep 2026 the positive control passed partly because check 3 never
        # looked at this tree.  A fixture that cannot exhibit the fault cannot
        # witness the fix.
        if not no_mirror_dll:
            mdll = os.path.join(m, "sdclilib.dll")
            io.open(mdll, "w", newline="").write("MZ\n")
            if mirror_dll_old:
                os.utime(mdll, (old, old))
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
        # THE TWO CASES THE OLD CHECK COULD NOT FAIL.  Both pass against the
        # pre-4 Sep 2026 script, which is the point of adding them: a stale
        # SHIPPED client in the mirror, and a mirror that ships none at all.
        ("a stale DLL in the MIRROR", {"mirror_dll_old": True}, 1),
        ("a mirror shipping no DLL at all", {"no_mirror_dll": True}, 1),
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
print("=== [3] every shipped build must be newer than the source =========")
newest_src, newest_name = 0.0, ""
for f in FILES:
    t = os.path.getmtime(os.path.join(TRUTH, f))
    if t > newest_src:
        newest_src, newest_name = t, f


def stamp(t):
    import datetime
    return datetime.datetime.fromtimestamp(t).strftime("%d %b %Y %H:%M:%S")


print("  newest library source : %s  (%s)" % (stamp(newest_src), newest_name))

# ***BOTH SIBLINGS SHIP DLLs AND ONLY ONE OF THEM WAS EVER CHECKED.***
# Extended 4 Sep 2026, on the owner's instruction, after he asked whether the
# DLLs in the two trees match this one and the honest answer was "sdclilib32's
# are checked, winsdclilib's are not looked at at all".  This check tested
# LIB32 only, while ../winsdclilib ships sdclilib.dll and sdclient.dll of its
# own and nothing verified they were not stale.
#
# THAT IS THE EXACT SHAPE OF THE INCIDENT IN THIS FILE'S OWN HEADER: "the
# 32-bit client SHIPPED SENDING PASSWORDS IN CLEAR, built from a winsdclilib
# that had not moved since 15 Aug and had no SCRAM in it, with nothing in
# either project able to report it".  Check 1 compares the mirror's SOURCE, so
# a stale mirror source is caught - but a mirror whose source is current and
# whose SHIPPED DLL was never rebuilt is the same defect wearing a clean shirt,
# and until now it passed.
#
# .dll ONLY, WHICH EXCLUDES THE IMPORT LIBRARIES BY CONSTRUCTION:
# libsdclilib.dll.a does not end in ".dll", so nothing has to name it.
for tree, label in ((LIB32, "sdclilib32"), (MIRROR, "winsdclilib")):
    dlls = [f for f in os.listdir(tree) if f.lower().endswith(".dll")]
    # THE NULL CASE, PER TREE.  "No DLL was older than the source" is trivially
    # true of a tree holding no DLL, and that tree ships nothing - which is a
    # worse answer than a stale one, not a better one.
    if not dlls:
        note(False, "%s holds a built DLL" % label,
             "none found - never built here")
    for d in sorted(dlls):
        t = os.path.getmtime(os.path.join(tree, d))
        note(t >= newest_src, "%s/%s is not older than the source" % (label, d),
             stamp(t))

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
print("  byte, sdclilib32 builds straight from this tree, and the shipped")
print("  DLLs in BOTH siblings are not older than the source they were")
print("  built from.")
