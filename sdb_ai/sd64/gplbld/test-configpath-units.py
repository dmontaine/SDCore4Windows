#!/usr/bin/env python3
"""test-configpath-units.py - ONE variable and ONE default for the config file,
kept in step between the server and the client library.

  python sdb_ai/sd64/gplbld/test-configpath-units.py
  python sdb_ai/sd64/gplbld/test-configpath-units.py --selftest
  (13 Nov 26 Windows port - from Linux b1d496df: the default is C:/ProgramData/SD/sd.conf and the client is
  gplsrc/sdclilib/sdclilib.c; the text below is Linux's.)

No sudo, no install, no sd.  A free check.

WHY IT EXISTS.  The server read SCARLET_CONFIG (inipath.c) while the client
library read SD_CONFIG (sdclilib.c), with nothing anywhere saying the two had
to agree - so setting the variable you would expect configured exactly one of
them.  The Windows port hit this on 14 Aug 2026 and the owner's instruction
there was to stop reading SCARLET_CONFIG and settle on SD_CONFIG; that
decision is this port's decision too, and the rename landed here on 15 Sep
2026.  The two values now live in gplsrc/sddefs.h, and sdclilib.c carries its
own copy of them because the client is a separate toolchain that must not
include the server's headers.  NOTHING IN THE BUILD CROSS-CHECKS THAT COPY -
the compiler is happy either way, and the failure is silent at runtime.  That
is what this check is for.

WHAT IT PINS

  gplsrc/sddefs.h    SD_CONFIG_ENV "SD_CONFIG", SD_CONFIG_DEFAULT
                     "/etc/sd.conf"
  gplsrc/inipath.c   reads the SYMBOL SD_CONFIG_ENV, not a literal; bounds the
                     copy at MAX_PATHNAME_LEN + 1; no strcpy into the caller's
                     buffer
  gplsrc/sdclilib.c  its duplicated literals equal sddefs.h's two values
  gplsrc/sdfix.c     read_sdconfig()'s buffer is MAX_PATHNAME_LEN + 1, which
                     is what every other GetConfigPath() caller passes - it
                     was 201 bytes, so the function's contract was whatever
                     the smallest caller happened to be
  gplsrc/*.c, *.h    SCARLET_CONFIG appears in no CODE anywhere (comments
                     explaining the history are allowed, and expected)

CONTROLS.  Every value must be FOUND, so a renamed or deleted definition fails
loudly rather than passing on nothing; the run refuses if fewer checks ran
than expected; and --selftest mutates each pinned fact in memory and requires
the check to go red for it, so a check that cannot fail is itself a failure.

Exit 0 all agree, 1 a mismatch or something not found, 2 it could not run.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)  # sdb_ai/sd64

WANT_ENV = "SD_CONFIG"
# 13 Nov 26 Windows port (RELEASE_1.1 254, the test-subset audit's item 3): the default is the Windows path, held here as the C
# source writes it (each backslash doubled), and the client library is gplsrc/sdclilib/sdclilib.c, its own toolchain's folder.
WANT_DEFAULT = r"C:\\ProgramData\\SD\\sd.conf"
CLIENT = "sdclilib/sdclilib.c"
OLD_NAME = "SCARLET_CONFIG"

# gplsrc files swept for OLD_NAME in code.  Kept as a list rather than a glob
# so a file that disappears is a failure, not a smaller sweep.
SWEPT = ["inipath.c", CLIENT, "sdfix.c", "sd.c", "sdtic.c", "config.c"]

EXPECTED_CHECKS = 2 + 3 + 2 + 1 + len(SWEPT)

checks = 0
fails = 0
messages = []


def out(line):
    messages.append(line)
    print(line)


def read(rel, quiet=False):
    path = os.path.join(ROOT, rel)
    if not quiet:
        out("  reading  : %s" % path)
    if not os.path.isfile(path):
        print("REFUSING - missing file: %s" % path)
        sys.exit(2)
    with open(path, encoding="iso-8859-1") as f:
        return f.read()


def expect(where, label, got, want):
    global checks, fails
    checks += 1
    if got is None:
        fails += 1
        out("  [FAIL] %s: %s NOT FOUND (control)" % (where, label))
    elif got != want:
        fails += 1
        out("  [FAIL] %s: %s is %r, expected %r" % (where, label, got, want))
    else:
        out("  [PASS] %s: %s = %r" % (where, label, got))


def strip_c_comments(text):
    """Comments out, so a check reads CODE.  The history of this rename lives
    in comments in three files and must not satisfy - or trip - a check."""
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    text = re.sub(r"//[^\n]*", " ", text)
    return text


def c_define_string(text, name):
    """The string a #define holds, without its quotes."""
    m = re.search(r'^\s*#define\s+' + re.escape(name) + r'\s+"([^"]*)"', text, re.M)
    return m.group(1) if m else None


def run_checks(src):
    """src: {relative path: file text}.  Everything measurable is measured
    from these strings, so --selftest can hand over a mutated one."""
    sddefs = src["gplsrc/sddefs.h"]
    inipath = strip_c_comments(src["gplsrc/inipath.c"])
    sdcli = strip_c_comments(src["gplsrc/" + CLIENT])
    sdfix = strip_c_comments(src["gplsrc/sdfix.c"])

    env = c_define_string(sddefs, "SD_CONFIG_ENV")
    dflt = c_define_string(sddefs, "SD_CONFIG_DEFAULT")
    expect("gplsrc/sddefs.h", "SD_CONFIG_ENV", env, WANT_ENV)
    expect("gplsrc/sddefs.h", "SD_CONFIG_DEFAULT", dflt, WANT_DEFAULT)

    # The server asks for the variable BY SYMBOL, so sddefs.h is the only
    # place the name is written on the server side.
    sym = "getenv(SD_CONFIG_ENV)" if "getenv(SD_CONFIG_ENV)" in inipath else None
    expect("gplsrc/inipath.c", "asks getenv(SD_CONFIG_ENV)", sym, "getenv(SD_CONFIG_ENV)")

    bounded = None
    if re.search(r"snprintf\s*\(\s*inipath\s*,\s*MAX_PATHNAME_LEN\s*\+\s*1", inipath):
        bounded = "snprintf(inipath, MAX_PATHNAME_LEN + 1"
    expect("gplsrc/inipath.c", "bounds the copy", bounded,
           "snprintf(inipath, MAX_PATHNAME_LEN + 1")

    unbounded = "absent" if not re.search(r"strcpy\s*\(\s*inipath\s*,", inipath) else "present"
    expect("gplsrc/inipath.c", "strcpy into the caller's buffer", unbounded, "absent")

    # The client library's own copy of the same two values.
    m = re.search(r'#define\s+SD_CONFIG_ENV\s+"([^"]*)"', sdcli) or re.search(r'getenv\s*\(\s*"([^"]*)"\s*\)', sdcli)
    expect("gplsrc/" + CLIENT, "its variable literal", m.group(1) if m else None, WANT_ENV)
    m = re.search(r'"(C:\\\\ProgramData\\\\[^"]*\.conf)"', sdcli)
    expect("gplsrc/" + CLIENT, "its default literal", m.group(1) if m else None, WANT_DEFAULT)

    # sdfix's buffer, the one caller that used to be short.
    m = re.search(r"read_sdconfig\s*\(\s*\)\s*\{.*?char\s+path\s*\[([^\]]*)\]", sdfix, re.S)
    expect("gplsrc/sdfix.c", "read_sdconfig()'s path buffer",
           re.sub(r"\s+", " ", m.group(1)).strip() if m else None, "MAX_PATHNAME_LEN + 1")

    for rel in SWEPT:
        code = strip_c_comments(src["gplsrc/" + rel])
        expect("gplsrc/" + rel, "%s in code" % OLD_NAME,
               "absent" if OLD_NAME not in code else "present", "absent")


def load():
    src = {}
    for rel in ["gplsrc/sddefs.h", "gplsrc/inipath.c", "gplsrc/" + CLIENT, "gplsrc/sdfix.c"]:
        src[rel] = read(rel)
    for rel in SWEPT:
        key = "gplsrc/" + rel
        if key not in src:
            src[key] = read(key)
    return src


def reset():
    global checks, fails, messages
    checks = 0
    fails = 0
    messages = []


# Each mutant is (name, file, old text, new text).  A mutant that does not
# make the check go red means the check is not measuring what it claims.
MUTANTS = [
    ("the variable is renamed", "gplsrc/sddefs.h",
     '#define SD_CONFIG_ENV     "SD_CONFIG"', '#define SD_CONFIG_ENV     "SDCONFIG"'),
    ("the default moves", "gplsrc/sddefs.h",
     r'#define SD_CONFIG_DEFAULT "C:\\ProgramData\\SD\\sd.conf"', r'#define SD_CONFIG_DEFAULT "C:\\ProgramData\\SD\\sd2.conf"'),
    ("the server asks for a literal", "gplsrc/inipath.c",
     "getenv(SD_CONFIG_ENV)", 'getenv("SD_CONFIG")'),
    ("the copy goes back to strcpy", "gplsrc/inipath.c",
     "snprintf(inipath, MAX_PATHNAME_LEN + 1, \"%s\", p);", "strcpy(inipath, p);"),
    ("the client drifts from sddefs.h", "gplsrc/" + CLIENT,
     '#define SD_CONFIG_ENV     "SD_CONFIG"', '#define SD_CONFIG_ENV     "SCARLET_CONFIG"'),
    ("the client's default drifts", "gplsrc/" + CLIENT,
     r'"C:\\ProgramData\\SD\\sd.conf"', r'"C:\\ProgramData\\SD\\sd.ini"'),
    # Anchored on the DECLARATION that follows read_sdconfig()'s own comment:
    # sdfix.c has other `char path[MAX_PATHNAME_LEN + 1]` declarations earlier
    # in the file, and a bare anchor mutated one of those instead - which the
    # selftest caught, and which is the reason it exists.
    # 13 Nov 26 Windows: anchored on the function's own opening line, which comes straight before the declaration here.
    ("sdfix shrinks its buffer again", "gplsrc/sdfix.c",
     "read_sdconfig() {\n  char path[MAX_PATHNAME_LEN + 1];", "read_sdconfig() {\n  char path[200 + 1];"),
    ("the old name comes back in code", "gplsrc/config.c",
     "struct CONFIG* read_config(char* errmsg) {",
     "struct CONFIG* read_config(char* errmsg) {\n  (void)getenv(\"SCARLET_CONFIG\");"),
]


def selftest():
    src = load()
    print("")
    print("  --selftest: each pinned fact is mutated in memory; the check must go red")
    bad = 0
    for name, rel, old, new in MUTANTS:
        if old not in src[rel]:
            print("  [FAIL] mutant %-32s : its anchor is not in %s (control)" % (name, rel))
            bad += 1
            continue
        mutated = dict(src)
        mutated[rel] = src[rel].replace(old, new, 1)
        reset()
        saved = sys.stdout
        sys.stdout = open(os.devnull, "w")
        try:
            run_checks(mutated)
        finally:
            sys.stdout.close()
            sys.stdout = saved
        if fails > 0:
            print("  [PASS] mutant %-32s : %d check(s) went red" % (name, fails))
        else:
            print("  [FAIL] mutant %-32s : NOTHING went red" % name)
            bad += 1
    print("")
    print("  mutants: %d, unnoticed: %d" % (len(MUTANTS), bad))
    return 0 if bad == 0 else 1


def main():
    print("test-configpath-units")
    print("  root     : %s" % ROOT)
    src = load()
    reset()
    run_checks(src)
    # Held now, because --selftest runs the checks again over mutated text and
    # leaves the counters describing a mutant rather than the tree.
    real_checks, real_fails = checks, fails
    print("")
    print("  checks: %d (expected %d), failures: %d" % (real_checks, EXPECTED_CHECKS, real_fails))
    if real_checks != EXPECTED_CHECKS:
        print("REFUSING - %d checks ran, %d expected: the run did not measure what it"
              " claims" % (real_checks, EXPECTED_CHECKS))
        return 2
    if "--selftest" in sys.argv:
        rc = selftest()
        if rc:
            return rc
    return 1 if real_fails else 0


if __name__ == "__main__":
    sys.exit(main())
