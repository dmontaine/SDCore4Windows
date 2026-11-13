#!/usr/bin/env python3
"""test-pathroot-units.py - K_PATH_IN's directory must be absolute and must not hold the whole machine (op_dio2.c os_root_absolute(),
os_root_whole_machine(); RELEASE_1.1 254, Linux op_sh.c path_inside_dir(): "an account at "/" would contain the whole machine: refuse").

  python sdb_ai/sd64/gplbld/test-pathroot-units.py
  python sdb_ai/sd64/gplbld/test-pathroot-units.py --selftest

It CUTS the two functions out of gplsrc/op_dio2.c (from the signature to the closing brace at the start of a line), compiles them with
MSYS2 gcc (the server's toolchain, the cygwin_conv_path() the server uses) beside a main(), and runs them on each input below.  Each row
prints the input and the answer.  os_path_inside() calls both before anything else, which W0 checks as text.

  absolute:        C:\\x, c:/x, /x, \\\\server\\share   -> yes;   x, .\\x, C:x, '' -> no
  whole machine:   / , // , /cygdrive/c , /cygdrive/c/  -> yes;   /c (a folder inside SD's root on SD's runtime), /cygdrive/c/ProgramData/SD/user_accounts/x, /usr -> no
  (the probe runs on a runtime root laid out as SD's: the DLL in usr\bin, SD's etc\fstab; 13 Nov 26)

Exit 0 every row held, 1 a row failed, 2 no MSYS2 bash.  --selftest mutates the C text (each must match once), rebuilds, and needs a red row.
"""
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(os.path.dirname(HERE), "gplsrc", "op_dio2.c")
BASH = "C:/msys64/usr/bin/bash.exe"
DLL = "C:/msys64/usr/bin/msys-2.0.dll"     # the runtime the probe is linked against (the same file SD ships, 13 Nov 26)
BS = chr(92)

MAIN = r'''
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/cygwin.h>
#define Private static
#define MAX_PATHNAME_LEN 1023
#include <stdbool.h>
#define TRUE 1
#define FALSE 0
%s
int main(int argc, char** argv) {
  const char* which = getenv("PR_WHICH");
  const char* arg = getenv("PR_ARG");
  if (which == NULL || arg == NULL) return 3;
  printf("%%d\n", strcmp(which, "abs") == 0 ? os_root_absolute(arg) : os_root_whole_machine(arg));
  return 0;
}
'''

# 13 Nov 26: the probe runs on a runtime root laid out as SD's (usr\bin with the DLL, etc\fstab with SD's one line, so the
# drive prefix is /cygdrive).  It ran on C:\msys64's root before, whose fstab maps /c to C:, a mapping SD's runtime does not
# have: there /c is a folder inside SD's root, not the drive.  Found when the guard went red in a shell whose PATH put another
# runtime first.  The rows are production's truth.
FSTAB = "C:/ProgramData/SD/shm /dev/shm ntfs binary 0 0\n"     # what stage.py writes into SD's etc\fstab
ROWS = [("abs", "C:" + BS + "x", 1), ("abs", "c:/x", 1), ("abs", "/x", 1), ("abs", BS + BS + "server" + BS + "share", 1),
        ("abs", "x", 0), ("abs", "." + BS + "x", 0), ("abs", "C:x", 0), ("abs", "", 0),
        ("whole", "/", 1), ("whole", "//", 1), ("whole", "/cygdrive/c", 1), ("whole", "/cygdrive/c/", 1),
        ("whole", "/c", 0), ("whole", "/cygdrive/c/ProgramData/SD/user_accounts/x", 0), ("whole", "/usr", 0)]


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
    a = cut(text, "Private bool os_root_absolute(const char* d) {")
    b = cut(text, "Private bool os_root_whole_machine(const char* root) {")
    if a is None or b is None:
        return False, "a function was not found in op_dio2.c (null case)"
    open(os.path.join(work, "p.c"), "w", newline="\n").write(MAIN % (a + "\n" + b))
    r = subprocess.run([BASH, "-lc", 'cd "%s" && gcc -O2 -Wall -o "%s" p.c' % (to_msys(work), to_msys(exe))],
                       capture_output=True, text=True, env=dict(os.environ, MSYSTEM="MSYS"))
    if r.returncode != 0:
        return False, (r.stdout + r.stderr).strip()
    # SD's layout: the exe beside the runtime DLL in <root>\usr\bin, and <root>\etc\fstab as SD's.  The runtime takes its
    # root from the DLL's folder, so this root's fstab (not C:\msys64's) decides what /c means.
    root = os.path.join(os.path.dirname(exe), "sdroot-" + os.path.splitext(os.path.basename(exe))[0])
    os.makedirs(os.path.join(root, "usr", "bin"), exist_ok=True)
    os.makedirs(os.path.join(root, "etc"), exist_ok=True)
    shutil.copy2(DLL, os.path.join(root, "usr", "bin", "msys-2.0.dll"))
    shutil.copy2(exe, os.path.join(root, "usr", "bin", os.path.basename(exe)))
    with open(os.path.join(root, "etc", "fstab"), "w", newline="\n") as h:
        h.write(FSTAB)
    return True, os.path.join(root, "usr", "bin", os.path.basename(exe))


def rows(exe, text, quiet=False):
    bad = 0
    body = text[text.find("bool os_path_inside(const char* rootdir, const char* name) {"):]
    body = body[:body.find("\n}\n")]
    held = 0 <= body.find("!os_root_absolute(rootdir)") < body.find("fullpath(") and body.find("net_normalise(") < body.find("os_root_whole_machine(root)") < body.find("path_within(")
    bad += 0 if held else 1
    if not quiet:
        print("  [%s] W0 os_path_inside() asks os_root_absolute() before it resolves, and os_root_whole_machine() before path_within()" % ("PASS" if held else "FAIL"))
    for which, arg, want in ROWS:
        r = subprocess.run([exe], capture_output=True, text=True, env=dict(os.environ, PR_WHICH=which, PR_ARG=arg))
        got = r.stdout.strip()
        ok = got == str(want)
        bad += 0 if ok else 1
        if not quiet:
            print("  [%s] %-5s %-40r -> %s (want %d)" % ("PASS" if ok else "FAIL", which, arg, got or "NOTHING (null case)", want))
    return bad


MUTANTS = [
    ("a relative directory passes", "  if ((d[0] == '/') || (d[0] == '" + BS + BS + "'))\n    return TRUE;\n  return",
     "  if ((d[0] == '/') || (d[0] == '" + BS + BS + "'))\n    return TRUE;\n  return 1 ||"),
    ("'/' passes", '  if (strcmp(r, "/") == 0)\n    return TRUE;', '  if (strcmp(r, "/") == 0)\n    return FALSE;'),
    ("a drive root passes", "  return (n == 2) && (w[1] == ':');", "  return 0;"),
    ("os_path_inside() skips the whole-machine test", "  if (os_root_whole_machine(root))\n    return FALSE;\n", ""),
]


def main():
    print("test-pathroot-units: source %s" % SRC)
    if not os.path.isfile(BASH):
        print("NO TREE: no MSYS2 bash at %s" % BASH)
        return 2
    text = open(SRC, encoding="latin-1", newline="").read()
    work = tempfile.mkdtemp(prefix="pathroot-")
    try:
        exe = os.path.join(work, "p.exe")
        ok, msg = build(work, text, exe)
        if not ok:
            print("BUILD FAILED: " + msg)
            return 1
        print("probe runs as %s (runtime root %s, its fstab: %s)" % (msg, os.path.dirname(os.path.dirname(os.path.dirname(msg))),
                                                                   FSTAB.strip()))
        bad = rows(msg, text)
        print("%d rows failed" % bad)
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
                caught = (not ok) or rows(msg, mt, quiet=True) > 0
                print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, "" if caught else ": NOT CAUGHT"))
                holes += 0 if caught else 1
            print("self-test: %d mutants, %d not caught" % (len(MUTANTS), holes))
            return 1 if holes else 0
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
