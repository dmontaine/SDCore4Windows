#!/usr/bin/env python3
"""test-sysdirsection-units.py - the client library's sysdir() does not read a malformed section header as a section, read off the source.

  python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-sysdirsection-units.py
  python .../test-sysdirsection-units.py --selftest

No elevation, no install, no compiler.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  The same file is in both Windows trees.
Written 11 Nov 26 for RELEASE_1.1 223 (Linux 71d8550b, S.159 finding 5; Linux's test-pathfix-units.py row 5 compiles the function under AddressSanitizer,
which this toolchain does not give, so this reads the shape instead).

THE RULE.  In sd.conf a line "[name]" starts a section.  sysdir() reads SDSYS= only in [sd].  A header with no closing bracket, or a name too long for the
buffer, is NOT a section: what follows belongs to none, so a line SDSYS=... after it is not read as [sd]'s.  Until 11 Nov 26 a long name was TRUNCATED (so it could
become a real section's name) and a header with no ] was a section named by the rest of the line.

WHAT IS HELD.  Inside sysdir(): the closing bracket is looked for first; a header with none, or a name that does not fit, empties the section name and goes on to
the next line BEFORE anything is copied; the copy is of the length that was measured; nothing truncates.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, os.pardir, "gplsrc", "sdclilib", "sdclilib.c")


def body(src):
    """The text of sysdir(), from its definition to the closing brace at column 0."""
    a = src.find("Private char* sysdir(void) {")
    if a < 0:
        return ""
    b = re.search(r"^\}", src[a:], re.M)
    return src[a:a + b.end()] if b else ""


def checks(src):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    f = body(src)
    ck("Y1 sysdir() is found", len(f) > 500, "%d characters" % len(f))
    code = re.sub(r"/\*.*?\*/", "", f, flags=re.S)                               # comments out
    flat = re.sub(r"\s+", " ", code)
    find = flat.find("p = strchr(rec, ']');")
    test = flat.find("if ((p == NULL) || ((size_t)(p - (rec + 1)) >= sizeof(section))) { section[0] = '\\0'; continue; }")
    copy = flat.find("memcpy(section, rec + 1, seclen);")
    ck("Y2 the closing bracket is looked for, then a header with none, or a name that does not fit, empties the section name and goes to the next line",
       find >= 0 and test > find, "strchr %d, refusal %d" % (find, test))
    ck("Y3 that refusal comes BEFORE anything is copied into the section name", test >= 0 and copy > test, "refusal %d, copy %d" % (test, copy))
    mark = flat.find("*p = '\\0'; seclen = strlen(rec + 1);")
    ck("Y4 the bracket is cut off first and the copy is of the measured length", mark > test >= 0 and copy > mark, "cut %d, copy %d" % (mark, copy))
    ck("Y5 nothing truncates a long name any more, and nothing copies it unmeasured",
       "seclen >= sizeof(section)" not in flat and "strcpy(section" not in flat and "strncpy(section" not in flat)
    ck("Y6 SDSYS= is read only in [sd], as before", "strcmp(section, \"SD\") == 0" in flat and "strncmp(rec, \"SDSYS=\", 6) == 0" in flat)
    return out


MUTANTS = [
    ("a header with no ] is a section again", "      if ((p == NULL) || ((size_t)(p - (rec + 1)) >= sizeof(section))) {", "      if (((size_t)(p - (rec + 1)) >= sizeof(section))) {"),
    ("a long name is truncated again", "      if ((p == NULL) || ((size_t)(p - (rec + 1)) >= sizeof(section))) {", "      if (p == NULL) {"),
    ("the refusal leaves the old section name", "        section[0] = '\\0';\n        continue;", "        continue;"),
    ("the name is never copied", "      memcpy(section, rec + 1, seclen);\n      section[seclen] = '\\0';\n", ""),
    ("the name is copied unmeasured", "      memcpy(section, rec + 1, seclen);", "      strcpy(section, rec + 1);"),
    ("SDSYS= is read in any section", "    if (strcmp(section, \"SD\") == 0) /* [sd] items */", "    if (1) /* [sd] items */"),
]


def load():
    with open(SRC, encoding="utf-8", errors="replace") as f:
        return f.read()


def selftest():
    src = load()
    if any(not ok for _, ok, _ in checks(src)):
        print("selftest: the unmutated source already fails; fix that first")
        return 1
    missed = 0
    for name, old, new in MUTANTS:
        if src.count(old) != 1:
            print("  [CANNOT] %-48s the text does not occur exactly once (%d)" % (name, src.count(old)))
            missed += 1
            continue
        caught = [n for n, ok, _ in checks(src.replace(old, new)) if not ok]
        if caught:
            print("  [caught] %-48s by %s" % (name, ", ".join(c.split()[0] for c in caught[:4])))
        else:
            print("  [MISSED] %-48s" % name)
            missed += 1
    print("selftest: %d mutants, %d missed or not applied" % (len(MUTANTS), missed))
    return 0 if missed == 0 else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    try:
        src = load()
    except OSError as e:
        print("cannot read the source: %s" % e)
        return 2
    res = checks(src)
    failed = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
        failed += 0 if ok else 1
    print("test-sysdirsection-units: %d checks, %d failed" % (len(res), failed))
    return 0 if failed == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
