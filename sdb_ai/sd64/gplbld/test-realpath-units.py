#!/usr/bin/env python3
"""test-realpath-units.py - sdrealpath() keeps resolving past a component that does not exist, and reads a link whose target is a drive
letter as a new root (gplsrc/linuxlb.c sdrealpath(); RELEASE_1.1 200, Linux S.159 / its parity audit of 10 Sep 26).

  python sdb_ai/sd64/gplbld/test-realpath-units.py
  python sdb_ai/sd64/gplbld/test-realpath-units.py --selftest

It CUTS sdrealpath() out of gplsrc/linuxlb.c (from the signature to the closing brace at the start of a line), compiles it with MSYS2
gcc (the server's runtime, whose lstat()/readlink() are the thing under test) beside a main(), and runs it on real objects in a scratch
folder made with tempfile.mkdtemp and removed at the end.  Nothing is stubbed: the function needs only libc (PATH_MAX, lstat, readlink,
getcwd, errno), and no SD header is included.  Inputs go in through the environment, never argv, which MSYS2 would glob.  Each row prints
the input, the expected answer and the got answer.

  R1 a plain existing path                                          C:/<scratch>/real/file       -> itself, slashes forward
  R2 the last components do not exist, then ".." and a name         .../real/nope/../again       -> .../real/again (resolution goes on)
  R3 a directory junction (cmd /c mklink /J, no elevation) whose target is a C:\\ path, then a missing component and a ".."
                                                                    .../J/nope/../x              -> <read-back target>/x
  R4 a native symlink to a directory, when one can be made unelevated      NOT POSSIBLE here is reported as such, never passed
  R5 a Cygwin-style link (the runtime's own symlink file, no privilege) read back with a drive-letter target - see the stub

FINDING (D0, D1): the MSYS2 runtime's readlink() returns a POSIX path for EVERY link, a junction's C:\\ target and a stored "C:/..." target
alike (measured 13 Nov 2026: /tmp/..., /c/...).  So no real link object reaches the drive-letter branch of sdrealpath(); a junction goes
through the '/' branch (R3 pins that).  The drive branch is run by R5 through ONE STUB: readlink() answers RP_FAKE, a drive-letter
target, for a path containing "/CY"; lstat(), errno, getcwd() and the rest of the function are real.  Nothing else is stubbed.  The
mutant on the branch turns R5 red, which is the proof that the stubbed answer is what ran it.  If a runtime ever returns a drive letter,
D1 goes red and says so.
Exit 0 every row held, 1 a row failed, 2 no MSYS2 bash.  --selftest mutates the C text (each must match once), rebuilds, and needs a red row.
Written 13 Nov 2026.
"""
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "gplsrc", "linuxlb.c")
BASH = "C:/msys64/usr/bin/bash.exe"
BS = chr(92)

MAIN = r'''
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <limits.h>
#include <errno.h>
#include <unistd.h>
#include <sys/stat.h>
#ifndef PATH_MAX
#define PATH_MAX 4096
#endif
#ifndef TRUE
#define TRUE 1
#define FALSE 0
#endif
/* THE ONE STUB: when RP_FAKE is set, readlink() of a path containing "/CY" answers RP_FAKE (a drive-letter target) instead of the
   runtime's own answer, which is always a POSIX path.  lstat(), getcwd() and everything else are the runtime's. */
static ssize_t fake_readlink(const char* p, char* b, size_t n) {
  const char* f = getenv("RP_FAKE");
  size_t l;
  if (f != NULL && *f != '\0' && strstr(p, "/CY") != NULL) {
    l = strlen(f);
    if (l > n) l = n;
    memcpy(b, f, l);
    return (ssize_t)l;
  }
  return readlink(p, b, n);
}
#define readlink fake_readlink
%s
#undef readlink
int main(void) {
  const char* mode = getenv("RP_MODE");
  const char* in = getenv("RP_IN");
  char out[PATH_MAX + 1], inbuf[PATH_MAX + 1];
  char* r;
  int n;
  if (mode == NULL || in == NULL || strlen(in) > PATH_MAX) return 3;
  if (strcmp(mode, "link") == 0) {
    n = readlink(in, out, PATH_MAX);
    if (n < 0) { printf("READLINK FAILED\n"); return 4; }
    out[n] = '\0';
    printf("%%s\n", out);
    return 0;
  }
  strcpy(inbuf, in);
  r = sdrealpath(inbuf, out);
  printf("%%s\n", r == NULL ? "(NULL)" : r);
  return 0;
}
'''


def cut(text, head):
    i = text.find(head)
    if i < 0:
        return None
    j = text.find("\n}\n", i)
    return text[i:j + 3] if j >= 0 else None


def to_msys(p):
    p = p.replace(BS, "/")
    return "/" + p[0].lower() + p[2:] if len(p) > 1 and p[1] == ":" else p


def build(work, text, exe):
    a = cut(text, "char* sdrealpath(char* inpath,")
    if a is None:
        return False, "sdrealpath() was not found in linuxlb.c (null case)"
    open(os.path.join(work, "p.c"), "w", newline="\n").write(MAIN % a)
    r = subprocess.run([BASH, "-lc", 'cd "%s" && gcc -O2 -Wall -o "%s" p.c' % (to_msys(work), to_msys(exe))],
                       capture_output=True, text=True, env=dict(os.environ, MSYSTEM="MSYS"))
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def run(exe, mode, arg, fake=""):
    r = subprocess.run([exe], capture_output=True, text=True, env=dict(os.environ, MSYSTEM="MSYS", RP_MODE=mode, RP_IN=arg, RP_FAKE=fake))
    return r.stdout.strip() or "NOTHING (null case)"


def fwd(p):
    return p.replace(BS, "/")


def setup(root):
    """Real objects under root.  Returns (target dir, junction path or None, symlink path or None, notes)."""
    notes = []
    real = os.path.join(root, "real")
    os.makedirs(real)
    open(os.path.join(real, "file"), "w").write("x")
    tgt = os.path.join(root, "tgt")
    os.makedirs(tgt)
    jun = os.path.join(root, "J")
    r = subprocess.run(["cmd", "/c", "mklink", "/J", jun, tgt], capture_output=True, text=True)
    if r.returncode != 0 or not os.path.isdir(jun):
        notes.append("junction not made: " + (r.stdout + r.stderr).strip())
        jun = None
    sym = os.path.join(root, "S")
    stgt = os.path.join(root, "stgt")
    os.makedirs(stgt)
    try:
        os.symlink(stgt, sym, target_is_directory=True)
    except (OSError, NotImplementedError) as e:
        notes.append("symlink not made: %s" % e)
        sym = None
    # A Cygwin-style link (the runtime's own: a SYSTEM file holding the target text), which needs no privilege and keeps the target as
    # written, so "C:/..." stays "C:/...".
    cyg = os.path.join(root, "CY")
    ctgt = os.path.join(root, "ctgt")
    os.makedirs(ctgt)
    try:
        open(cyg, "wb").write(b"!<symlink>\xff\xfe" + ctgt.encode("utf-16-le") + b"\0\0")
        subprocess.run(["attrib", "+s", cyg], capture_output=True, check=True)
    except (OSError, subprocess.CalledProcessError) as e:
        notes.append("Cygwin-style link not made: %s" % e)
        cyg = None
    return tgt, jun, sym, stgt, cyg, ctgt, notes


def rows(exe, root, quiet=False):
    """Returns (rows failed, rows not possible)."""
    bad = 0
    nope = 0
    tgt, jun, sym, stgt, cyg, ctgt, notes = SETUP
    if not quiet:
        print("  scratch folder: %s" % fwd(root))
        for n in notes:
            print("  note: " + n)

    def row(name, inp, want, fake=""):
        nonlocal bad
        got = run(exe, "real", inp, fake)
        ok = got == want
        bad += 0 if ok else 1
        if not quiet:
            print("  [%s] %s" % ("PASS" if ok else "FAIL", name))
            print("         input    %s" % inp)
            print("         expected %s" % want)
            print("         got      %s" % got)

    r = fwd(root)
    row("R1 plain existing path", r + "/real/file", r + "/real/file")
    row("R1b plain existing path, backslashes", root + BS + "real" + BS + "file", r + "/real/file")
    row("R2 missing last components, then .. and a name", r + "/real/nope/more/../../again", r + "/real/again")
    row("R2b missing component, trailing", r + "/real/nope", r + "/real/nope")
    row("R2c missing component directly under the drive root, then .. and a name", "C:/q/../b", "C:/b")
    row("R2d .. at the drive root stays at the root", "C:/../..", "C:/")
    if jun is None:
        nope += 1
        if not quiet:
            print("  [NOT POSSIBLE] R3 junction: it could not be made here")
    else:
        lk = run(exe, "link", fwd(jun))
        d0 = lk.startswith("/")
        bad += 0 if d0 else 1
        if not quiet:
            print("  [%s] D0 the runtime reads a junction's C:\\ target back as a POSIX path (so a junction reaches the '/' branch, not the drive one)" % ("PASS" if d0 else "FAIL"))
            print("         readlink %s" % lk)
        row("R3 junction (POSIX read-back), then a missing component and .. and a name", r + "/J/nope/../x", lk + "/x")
        row("R3b junction (POSIX read-back), the link alone", r + "/J", lk)
    if cyg is None:
        nope += 1
        if not quiet:
            print("  [NOT POSSIBLE] R5 Cygwin-style link: it could not be made here")
    else:
        lk = run(exe, "link", fwd(cyg))
        d1 = lk.startswith("/")
        bad += 0 if d1 else 1
        if not quiet:
            print("  [%s] D1 FINDING: the runtime's readlink() turns even a stored C:/ target into a POSIX path, so no real link reaches the drive branch;" % ("PASS" if d1 else "FAIL"))
            print("         the rows below stub readlink() (the only stub) to answer a drive-letter target, to run that branch")
            print("         readlink %s" % lk)
        for tname, tval in (("C:/ target", fwd(ctgt)), ("C:\\ target", ctgt)):
            row("R5 link to a %s (stub), then a missing component and .. and a name  (the drive-letter branch)" % tname,
                r + "/CY/nope/../x", fwd(ctgt) + "/x", tval)
            row("R5b link to a %s (stub), the link alone" % tname, r + "/CY", fwd(ctgt), tval)
            row("R5c link to a %s (stub), then .. past it" % tname, r + "/CY/..", r, tval)
        row("R5d link to a relative-free drive root C:/ (stub), then a name", r + "/CY/Windows", "C:/Windows", "C:/")
    if sym is None:
        nope += 1
        if not quiet:
            print("  [NOT POSSIBLE] R4 symlink: it could not be made here")
    else:
        lk = run(exe, "link", fwd(sym))
        if not quiet:
            print("  info: readlink() of the symlink gave %s" % lk)
        row("R4 symlink to a directory, then a missing component and .. and a name", r + "/S/nope/../x", fwd(stgt) + "/x")
    return bad, nope


SETUP = None

MUTANTS = [
    ("the drive-letter branch of a link target is switched off",
     "(pending[1] == ':')) /* A drive letter: that drive is the root */",
     "(pending[1] == '#')) /* A drive letter: that drive is the root */"),
    ("resolution stops at a component that does not exist",
     "        p = q;\n        continue;\n      }\n\n      if (S_ISLNK(st.st_mode)) {",
     "        *(tgt++) = '/';\n        strcpy(tgt, q);\n        return outpath;\n      }\n\n      if (S_ISLNK(st.st_mode)) {"),
    ("the root of a drive-letter input is taken as five bytes, so .. stops short of it",
     "    root_len = 3;\n    p = inpath + 2;",
     "    root_len = 5;\n    p = inpath + 2;"),
]


def main():
    global SETUP
    print("test-realpath-units: source %s" % SRC)
    if not os.path.isfile(BASH):
        print("NO TREE: no MSYS2 bash at %s" % BASH)
        return 2
    text = open(SRC, encoding="latin-1", newline="").read()
    work = tempfile.mkdtemp(prefix="realpath-")
    try:
        exe = os.path.join(work, "p.exe")
        ok, msg = build(work, text, exe)
        if not ok:
            print("BUILD FAILED: " + msg)
            return 1
        root = os.path.join(work, "scratch")
        os.makedirs(root)
        SETUP = setup(root)
        bad, nope = rows(exe, root)
        print("%d rows failed, %d not possible here" % (bad, nope))
        if bad:
            return 1
        if "--selftest" in sys.argv[1:]:
            holes = 0
            for i, (name, old, new) in enumerate(MUTANTS):
                if text.count(old) != 1:
                    print("  [FAIL] %s: the text to mutate matches %d times" % (name, text.count(old)))
                    holes += 1
                    continue
                mt = text.replace(old, new, 1)
                mexe = os.path.join(work, "m%d.exe" % i)
                ok, msg = build(work, mt, mexe)
                caught = (not ok) or rows(mexe, root, quiet=True)[0] > 0
                print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, "" if caught else ": NOT CAUGHT"))
                holes += 0 if caught else 1
            print("self-test: %d mutants, %d not caught" % (len(MUTANTS), holes))
            return 1 if holes else 0
        return 0
    finally:
        # a junction must be removed as a link, not followed
        j = os.path.join(work, "scratch", "J")
        if os.path.exists(j):
            try:
                os.rmdir(j)
            except OSError:
                pass
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
