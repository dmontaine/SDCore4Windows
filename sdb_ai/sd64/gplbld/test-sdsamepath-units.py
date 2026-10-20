"""sdidx and sdfix must decide "is this file open in SD" with sd_same_file_path(), never with a bare string compare.

WHY THIS EXISTS.  19 Oct 2026 (RELEASE_1.1 159).  The test was strcmp(), then strcasecmp(), of the path the tool was given
against the path in SD's table of open files.  NTFS ignores case, so strcmp() missed a path typed in another case; and
strcasecmp() still missed it for SD Core Solo, whose accounts are INSIDE the MSYS runtime's root: the daemon records
/user_accounts/sduser/voc, the runtime matches the root prefix case-sensitively, so C:\\USERS\\DON\\SDCORESOLO\\... came back as
/cygdrive/c/USERS/... and no case-folding of the other string can equal that.  The Solo verify showed sdidx -q and -d and sdfix -F
running on a file a session held open, 12 rows red in verify-carry-toolswin (W3-W6), while Core, whose accounts are outside the
root, passed.  sdsamepath.h turns both sides into the Windows spelling first.  A source check: no SD, no install, no elevation.
Identical in both Windows trees; the header must be byte-identical between them when the other tree is beside this one.

  python gplbld/test-sdsamepath-units.py [gplsrc-dir]

MUTANT-TESTED 19 Oct 2026: six scratch copies of the sources, each with one regression (sdidx back to strcasecmp, sdfix back to
strcmp, the include dropped, the Windows conversion dropped, the case-sensitive compare, the drive-letter case dropped) all went
red; the unchanged copy stayed green and the live sources were byte-identical (SHA-256) afterwards.

Exit 0 all checks passed, 1 a check failed, 2 the tree is not there to read.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.abspath(sys.argv[1]) if len(sys.argv) > 1 else os.path.normpath(os.path.join(HERE, "..", "gplsrc"))

failures = 0
passes = 0


def check(label, ok, detail=""):
    global failures, passes
    if ok:
        passes += 1
        print("  [PASS] " + label)
    else:
        failures += 1
        print("  [FAIL] " + label + ("   <- " + str(detail) if detail else ""))


def read(name):
    p = os.path.join(SRC, name)
    if not os.path.isfile(p):
        print("test-sdsamepath-units: no %s in %s" % (name, SRC))
        sys.exit(2)
    with open(p, encoding="utf-8", errors="replace", newline="") as fh:
        return fh.read()


def code_only(text):
    """The text with comments removed, so a word in a comment cannot satisfy or break a check."""
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def main():
    print("test-sdsamepath-units: %s" % SRC)
    hdr = read("sdsamepath.h")
    hcode = code_only(hdr)
    check("H1 sdsamepath.h defines sd_same_file_path() and sd_win_form()",
          "sd_same_file_path(" in hcode and "sd_win_form(" in hcode)
    check("H2 ... converts with cygwin_conv_path(CCP_POSIX_TO_WIN_A) and compares the Windows spellings with strcasecmp()",
          "cygwin_conv_path(CCP_POSIX_TO_WIN_A" in hcode and re.search(r"strcasecmp\(wa, wb\)", hcode) is not None)
    check("H3 ... takes an entry that already begins with a drive letter as it is (sdsys files are recorded C:/...)",
          re.search(r"isalpha\(\(unsigned char\)p\[0\]\) && \(p\[1\] == ':'\)", hcode) is not None)
    for tool in ("sdidx.c", "sdfix.c"):
        c = code_only(read(tool))
        check("T1 %s includes sdsamepath.h" % tool, '#include "sdsamepath.h"' in read(tool))
        check("T2 %s tests the table entry with sd_same_file_path()" % tool,
              re.search(r"sd_same_file_path\(\(char \*\)\(fptr->pathname\)", c) is not None)
        bad = re.findall(r"str(?:case)?cmp\(\s*\(char \*\)\(fptr->pathname\)", c)
        check("T3 %s does NOT compare fptr->pathname with strcmp() or strcasecmp()" % tool, not bad, bad)
    other = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "SDCore4WindowsSolo", "sdb_ai", "sd64", "gplsrc",
                                          "sdsamepath.h"))
    me = os.path.normpath(os.path.join(HERE, "..", "..", "..", "..", "SDCore4Windows", "sdb_ai", "sd64", "gplsrc", "sdsamepath.h"))
    if os.path.isfile(other) and os.path.isfile(me):
        with open(other, "rb") as a, open(me, "rb") as b:
            check("H4 the header is byte-identical in the two Windows trees", a.read() == b.read())
    print("\ntest-sdsamepath-units: %d passed, %d failed" % (passes, failures))
    if passes == 0:
        print("test-sdsamepath-units: no check ran - a broken test, not a pass")
        return 2
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
