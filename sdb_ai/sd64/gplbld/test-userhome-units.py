#!/usr/bin/env python3
"""test-userhome-units.py - SDEXT SD_USER_HOME (112) in its Windows form: win32_user_home() (win32tls.c), the home the editors' recovery store and
SD_USER_HOME answer, and the test it makes of every directory below it.

  python sdb_ai/sd64/gplbld/test-userhome-units.py
  python sdb_ai/sd64/gplbld/test-userhome-units.py --selftest

13 Nov 26 Windows port of Linux's test-userhome-units.py (b1d496df; RELEASE_1.1 254).  Linux cuts user_home_dir() out of op_sdext.c and runs it with
the password database stubbed.  THE WINDOWS FUNCTION IS DIFFERENT CODE (the walk is Win32 ACLs, and a missing directory is MADE, private, rather than
refused - win32tls.c:296, an OS reason), so this is a rewrite, not a carry: it compiles the real win32tls.c with MSYS2 gcc (the server's toolchain,
which links it into sd.exe) beside a small main(), and runs it AS THE PERSON RUNNING THE CHECK against their real profile.

SIDE EFFECT, STATED: it makes folders named sd-userhome-test-<pid>... under the runner's own %LOCALAPPDATA% and deletes them before it exits (a
finally block).  Nothing else is written outside a temporary folder.  Unelevated is the case it is written for; elevated also works.

  the trusted answers:  '' is the runner's AppData\\Local (compared with %LOCALAPPDATA%, which the function itself never reads); a missing word is
                        made and answered, and the folder made is protected (no inherited entry) and holds no BUILTIN\\Users; the same word again
                        (now present) passes; a nested a/b and the same with a backslash
  the refusals:         a folder below the home that Users may modify; '..', '.', an empty word, a trailing or leading separator, and : * ? in a
                        name - each with the reason win32_user_home() gives for it

THE NULL CASE IS REFUSED: the build must succeed and every row must print an answer.  --selftest makes each mutation of win32tls.c (it must match
once), compiles the mutated copy and requires a row to fail.  Exit 0 every row held, 1 a row failed, 2 it could not run (no MSYS2 gcc, no icacls).
"""
import hashlib
import os
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC_C = os.path.join(os.path.dirname(HERE), "gplsrc", "win32tls.c")
BASH = "C:/msys64/usr/bin/bash.exe"
BS = chr(92)
SOURCE = [""]      # the win32tls.c text the probe under test was built from (the real one, or a mutant's), for the text rows

PROBE = r'''
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
int win32_user_home(const char* rel, char* out, size_t out_sz, char* why, size_t whylen);
int main(void) {
  char out[1100], why[600];
  const char* rel = getenv("SD_TEST_REL");   /* not argv: the MSYS2 runtime globs a*b against the current folder */
  int ok = win32_user_home(rel ? rel : "", out, sizeof(out), why, sizeof(why));
  printf("%d|%s\n", ok, ok ? out : why);
  return 0;
}
'''


def to_msys(p):
    p = p.replace(BS, "/")
    return "/" + p[0].lower() + p[2:] if len(p) > 1 and p[1] == ":" else p


def build(work, c_text, exe):
    open(os.path.join(work, "probe.c"), "w").write(PROBE)
    open(os.path.join(work, "w32.c"), "w", encoding="latin-1", newline="").write(c_text)
    cmd = 'cd "%s" && gcc -O2 -o "%s" probe.c w32.c -ladvapi32 -luserenv' % (to_msys(work), to_msys(exe))
    r = subprocess.run([BASH, "-lc", cmd], capture_output=True, text=True, env=dict(os.environ, MSYSTEM="MSYS"))
    return r.returncode == 0, (r.stdout + r.stderr).strip()


def ask(exe, rel):
    # The path goes in the environment, never argv: on 13 Nov 26 the first run passed a*b as an argument, the MSYS2 runtime globbed it to a
    # file name in the current folder, and the function made that folder under the home.  The empty string is passed as an empty variable.
    r = subprocess.run([exe], capture_output=True, text=True, env=dict(os.environ, SD_TEST_REL=rel))
    line = r.stdout.strip()
    if "|" not in line:
        return None, line
    ok, rest = line.split("|", 1)
    return ok == "1", rest


def acl_lines(path):
    r = subprocess.run(["icacls", path], capture_output=True, text=True)
    return r.stdout


def rows(exe, base, quiet=False):
    """Every row; returns the number that failed.  base is a fresh word under %LOCALAPPDATA%."""
    home = os.environ.get("LOCALAPPDATA", "")
    loose = base + "-loose"
    os.makedirs(os.path.join(home, loose))
    subprocess.run(["icacls", os.path.join(home, loose), "/grant", "*S-1-5-32-545:(OI)(CI)M"], capture_output=True)
    bad = 0

    def row(name, rel, want_ok, want_text):
        nonlocal bad
        ok, text = ask(exe, rel)
        if ok is None:
            held = False
            text = "NO ANSWER (null case): " + text
        elif want_ok:
            held = ok and text.lower() == want_text.lower()
        else:
            held = (not ok) and want_text in text
        bad += 0 if held else 1
        if not quiet:
            print("  [%s] %s   rel=%r -> %s %s" % ("PASS" if held else "FAIL", name, rel, "1" if ok else "0", text))
        return held

    row("T1 '' is the runner's AppData" + BS + "Local", "", True, home)
    row("T2 a missing word is made and answered", base, True, home + BS + base)
    made = acl_lines(os.path.join(home, base))
    held = os.path.isdir(os.path.join(home, base)) and "(I)" not in made and "BUILTIN" + BS + "Users" not in made
    bad += 0 if held else 1
    if not quiet:
        print("  [%s] T2 ...the folder made is protected (no inherited entry) and holds no BUILTIN%sUsers" % ("PASS" if held else "FAIL", BS))
    # The P (protected) cannot be seen in a run: a DACL given at creation is not merged with the parent's either way.  It matters when somebody
    # later propagates inheritance onto the folder (icacls /reset /T on a parent), so it is held as text.
    held = '"O:%sD:P(A;OICI;FA;;;%s)(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)"' in SOURCE[0]
    bad += 0 if held else 1
    if not quiet:
        print("  [%s] T2 ...and win32tls.c makes it with a PROTECTED DACL of the user, SYSTEM and Administrators only (text)" % ("PASS" if held else "FAIL"))
    row("T3 the same word again, now present, passes", base, True, home + BS + base)
    row("T4 a nested a/b is made", base + "/a/b", True, home + BS + base + BS + "a" + BS + "b")
    row("T5 ...and the same with a backslash", base + BS + "a" + BS + "b", True, home + BS + base + BS + "a" + BS + "b")
    row("F1 a folder below the home that Users may modify is refused", loose, False, loose)
    row("F2 '..' is refused", "..", False, "an empty name, . or .. below the home")
    row("F3 '.' is refused", base + "/.", False, "an empty name, . or .. below the home")
    row("F4 an empty word is refused", base + "//x", False, "an empty name, . or .. below the home")
    row("F5 a trailing separator is refused", base + "/", False, "a trailing separator")
    row("F6 a leading separator is refused", "/" + base, False, "an empty name, . or .. below the home")
    row("F7 a stream name (:) is refused", base + ":x", False, "may not hold :")
    row("F8 * is refused", "a*b", False, "may not hold *")
    row("F9 ? is refused", "a?b", False, "may not hold ?")
    return bad


def clean(home, prefix):
    for n in os.listdir(home):
        if n.startswith(prefix):
            shutil.rmtree(os.path.join(home, n), ignore_errors=True)


MUTANTS = [
    ("':' is allowed in a name", r'strchr(":*?\"<>|", *e)', r'strchr("*?\"<>|", *e)'),
    ("'..' is allowed", "(wl == 2 && p[0] == '.' && p[1] == '.')", "0"),
    ("a trailing separator is allowed", "if (*e != '\\0' && e[1] == '\\0') {", "if (0) {"),
    ("the folder made is not protected", '"O:%sD:P(A;OICI;FA;;;%s)', '"O:%sD:(A;OICI;FA;;;%s)'),
    ("the folder made lets Users in", "(A;OICI;FA;;;BA)\", us, us);", "(A;OICI;FA;;;BA)(A;OICI;FA;;;BU)\", us, us);"),
    ("a folder below the home is not tested", "    if (!win32_private_to_user(work, 1, why, whylen))\n      return 0;\n  }\n\n  if (len + 1 > out_sz)",
     "    (void)0;\n  }\n\n  if (len + 1 > out_sz)"),
    ("the home is the profile, not AppData" + BS + "Local", '  strcat(work, "\\\\Local");\n', ""),
]


def main():
    print("test-userhome-units: source %s" % SRC_C)
    if not os.path.isfile(SRC_C):
        print("NO TREE: no win32tls.c")
        return 2
    if not os.path.isfile(BASH) or shutil.which("icacls") is None:
        print("NO TREE: MSYS2 bash (%s) or icacls is missing" % BASH)
        return 2
    home = os.environ.get("LOCALAPPDATA", "")
    if not os.path.isdir(home):
        print("NO TREE: %%LOCALAPPDATA%% is not a folder: %r" % home)
        return 2
    text = open(SRC_C, encoding="latin-1", newline="").read()
    before = hashlib.sha256(text.encode("latin-1")).hexdigest()
    prefix = "sd-userhome-test-%d" % os.getpid()
    print("  home    : %s   scratch words: %s*" % (home, prefix))
    work = tempfile.mkdtemp(prefix="userhome-")
    rc = 0
    try:
        exe = os.path.join(work, "probe.exe")
        ok, msg = build(work, text, exe)
        if not ok:
            print("BUILD FAILED: " + msg)
            return 1
        SOURCE[0] = text
        bad = rows(exe, prefix + "-real")
        print("%d rows failed" % bad)
        rc = 1 if bad else 0
        if rc == 0 and "--selftest" in sys.argv[1:]:
            print("--- self-test: each mutation of win32tls.c must match once, compile, and turn a row red ---")
            holes = 0
            for i, (name, old, new) in enumerate(MUTANTS):
                n = text.count(old)
                if n != 1:
                    print("  [FAIL] %s: the text to mutate matches %d times, not once" % (name, n))
                    holes += 1
                    continue
                mexe = os.path.join(work, "m%d.exe" % i)
                SOURCE[0] = text.replace(old, new, 1)
                ok, msg = build(work, SOURCE[0], mexe)
                if not ok:
                    print("  [FAIL] %s: the mutant does not compile: %s" % (name, msg[:200]))
                    holes += 1
                    continue
                mbad = rows(mexe, "%s-m%d" % (prefix, i), quiet=True)
                print("  [%s] %s%s" % ("pass" if mbad else "FAIL", name, "" if mbad else ": NOT CAUGHT"))
                holes += 0 if mbad else 1
            print("self-test: %d mutants, %d not caught" % (len(MUTANTS), holes))
            rc = 1 if holes else 0
    finally:
        clean(home, prefix)
        shutil.rmtree(work, ignore_errors=True)
        left = [n for n in os.listdir(home) if n.startswith(prefix)]
        after = hashlib.sha256(open(SRC_C, "rb").read()).hexdigest()
        print("  cleaned : %s; win32tls.c %s" % ("nothing left under the home" if not left else "LEFT: " + ", ".join(left),
                                                 "unchanged" if after == before else "CHANGED"))
        if left or after != before:
            rc = 1
    return rc


if __name__ == "__main__":
    sys.exit(main())
