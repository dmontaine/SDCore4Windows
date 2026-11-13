#!/usr/bin/env python3
#
# test-nomergemarks-units.py - no tracked file of the product holds a line that is a git merge-conflict marker (a line of seven <, = or >, alone
# or followed by a space and a name).  2 Nov 2026: the shipped changelog carried a "<<<<<<< ours" line on Dev 1c127f7c - a conflict resolved by
# hand lost its closing markers but kept its opening one, and no check read the file for it.  Free: no install, no sudo, no sd.
#
#   python sdb_ai/sd64/gplbld/test-nomergemarks-units.py [--selftest]
#
# 13 Nov 26 Windows port - from Linux b1d496df (RELEASE_1.1 254, the test-subset audit's item 1): the self-test plants its markers in
# a copy of gplbld/sd.iss in place of Linux's installsdcore.sh.  Wanted here too: the carries are git apply --3way, and on 13 Nov
# five files of the OPENTEMP carry were resolved by hand.
#
# What it reads: `git ls-files` of the repository (the real list, printed as a count), every text file of it (a file with a NUL byte is taken as
# binary and skipped, and counted).  It refuses the null case: fewer than 1000 files read is "could not run" (exit 2).
# A Markdown or Python file that DESCRIBES a marker in prose or in a string does not match: only a line that IS a marker counts.
# --selftest plants each kind of marker in a scratch copy of three real files and requires each to be found, and a near miss (six <, a marker
# inside a sentence) not to be.
import os, re, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
MARK = re.compile(r"^(?:<{7}|>{7})(?: .*)?$|^={7}$")


def scan(paths, base):
    bad, read, binary = [], 0, 0
    for rel in paths:
        p = os.path.join(base, rel)
        try:
            data = open(p, "rb").read()
        except OSError:
            continue
        if b"\0" in data:
            binary += 1
            continue
        read += 1
        for n, line in enumerate(data.decode("latin-1").split("\n"), 1):
            if MARK.match(line.rstrip("\r")):
                bad.append("%s:%d: %s" % (rel, n, line[:40]))
    return bad, read, binary


def tracked():
    # regress.sh --snapshot copies the tree without .git and names the repository in SDREGRESS_REPO: the list comes from it, the files from the copy
    src = ROOT if os.path.exists(os.path.join(ROOT, ".git")) else os.environ.get("SDREGRESS_REPO", ROOT)
    r = subprocess.run(["git", "-C", src, "ls-files", "-z"], capture_output=True)
    if r.returncode != 0:
        return None
    return [x for x in r.stdout.decode("utf-8", "replace").split("\0") if x]


def selftest():
    cases = [("<" * 7 + " ours", True), ("=" * 7, True), (">" * 7 + " theirs", True), ("<" * 7, True),
             ("<" * 6 + " six", False), ("text " + "<" * 7 + " inside", False), ("=" * 8, False)]
    src = ["sdb_ai/sd64/sdsys/changelog", "sdb_ai/sd64/gplbld/sd.iss", "sdb_ai/sd64/gplsrc/revstamp.h"]
    ok = True
    with tempfile.TemporaryDirectory() as d:
        for i, (planted, want) in enumerate(cases):
            rels = []
            for s in src:
                t = open(os.path.join(ROOT, s), "rb").read().decode("latin-1").split("\n")
                t.insert(min(3, len(t)), planted)
                rel = "c%d_%s" % (i, os.path.basename(s))
                open(os.path.join(d, rel), "wb").write("\n".join(t).encode("latin-1"))
                rels.append(rel)
            bad, read, _ = scan(rels, d)
            found = len(bad) == len(src)
            got = found if want else (len(bad) == 0)
            print("  [%s] planted %r in 3 files: %s" % ("caught" if want and got else "ok" if got else "MISSED", planted, "found %d" % len(bad)))
            ok = ok and got
    print("test-nomergemarks-units --selftest: %s" % ("all cases right" if ok else "a case was wrong"))
    return 0 if ok else 1


def main():
    if "--selftest" in sys.argv[1:]:
        return selftest()
    files = tracked()
    if files is None:
        print("test-nomergemarks-units: CANNOT RUN - git ls-files failed in %s" % ROOT)
        return 2
    bad, read, binary = scan(files, ROOT)
    print("test-nomergemarks-units: %d tracked files listed, %d text files read, %d binary skipped, in %s" % (len(files), read, binary, ROOT))
    if read < 1000:
        print("test-nomergemarks-units: CANNOT RUN - only %d text files read (the null case)" % read)
        return 2
    for b in bad:
        print("  [FAIL] a merge-conflict marker: " + b)
    print("test-nomergemarks-units: %d passed, %d failed" % (0 if bad else 1, len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
