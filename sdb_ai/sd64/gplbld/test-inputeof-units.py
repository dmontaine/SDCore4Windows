#!/usr/bin/env python3
"""test-inputeof-units.py - do_input() does not read a stale errno at end of file (15 Oct 26).

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-inputeof-units.py
  python3 .../test-inputeof-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.

THE DEFECT (found 15 Oct 2026 by the client library's thread test, six runs of two API sessions writing to one file and
disconnecting at the same moment: two of six left both servers running at 100% of a processor for ever): linuxio.c's
do_input() read a byte with `if (read(0, &c, 1) <= 0) { if (errno == EAGAIN) goto again; ... connection_lost }`.  End of
file is a read that returns 0 and does NOT set errno, so an EAGAIN left by any EARLIER call - a lock attempt that failed,
a write that would have blocked - made the test true, and an ended connection went round the loop for ever (poll said
hung up, read said nothing, errno still said try again).  errno means something only after a read that returned -1.

***WHAT THIS IS AND IS NOT.***  It reads gplsrc/linuxio.c as text.  It cannot say a server exits when its client goes; that
is `sandbox-qmclient.py` part R (six threads, sessions closed together; red on the kernel before).  It says the form is
still written, so a later edit that puts the errno test back in front of the result fails here before a sandbox is built.
--selftest mutates the source three ways and requires each to be caught.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
LINUXIO = os.path.abspath(os.path.join(HERE, os.pardir, "gplsrc", "linuxio.c"))


def do_input_body(src):
    m = re.search(r"^Private void do_input\(\) \{\n(.*?)^\}\n", src, re.S | re.M)
    return m.group(1) if m else None


def strip_comments(text):
    return re.sub(r"/\*.*?\*/", "", text, flags=re.S)


def checks(src):
    body = do_input_body(src)
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    ck("do_input() is there", body is not None)
    if body is None:
        return out
    code = strip_comments(body)
    reads = re.findall(r"^\s*(\w+)\s*=\s*read\(0,\s*&c,\s*1\)\s*;", code, re.M)
    ck("the byte is read into a variable, not tested inline against errno", len(reads) == 1, "reads: %r" % reads)
    if len(reads) != 1:
        return out
    v = reads[0]
    ck("the result is declared (ssize_t or int)", re.search(r"\b(ssize_t|int|long)\s+%s\s*;" % re.escape(v), code) is not None)
    eagain = [m.start() for m in re.finditer(r"errno\s*==\s*EAGAIN", code)]
    ck("errno is consulted exactly once, for EAGAIN", len(eagain) == 1, "%d" % len(eagain))
    ck("the EAGAIN test is conditional on the read having returned a NEGATIVE value (a 0 leaves errno as it was)",
       re.search(r"if\s*\(\s*\(\s*%s\s*<\s*0\s*\)\s*&&\s*\(\s*errno\s*==\s*EAGAIN\s*\)\s*\)" % re.escape(v), code) is not None)
    lost = re.search(r"if\s*\(\s*%s\s*<=\s*0\s*\)\s*\{\s*connection_lost\s*=\s*TRUE" % re.escape(v), code)
    ck("a read of 0 or less that was not EAGAIN is a lost connection", lost is not None)
    if eagain and lost:
        ck("the EAGAIN retry comes before the lost-connection test", eagain[0] < lost.start())
    return out


def mutants(src):
    res = []
    old = re.sub(
        r"    got = read\(0, &c, 1\);\n(?:.*?\n)*?    if \(\(got < 0\) && \(errno == EAGAIN\)\)\n      goto again;[^\n]*\n\n    if \(got <= 0\) \{\n",
        "    if (read(0, &c, 1) <= 0) {\n      if (errno == EAGAIN)\n        goto again;\n\n", src, count=1)
    res.append(("the old form: read tested inline, errno consulted after a result of 0", old))
    res.append(("the EAGAIN test no longer needs a negative result",
                src.replace("if ((got < 0) && (errno == EAGAIN))", "if (errno == EAGAIN)", 1)))
    res.append(("a read of 0 no longer loses the connection",
                src.replace("    if (got <= 0) {\n      connection_lost", "    if (got < 0) {\n      connection_lost", 1)))
    return res


def main():
    if not os.path.isfile(LINUXIO):
        print("test-inputeof-units: CANNOT RUN - no linuxio.c at %s" % LINUXIO)
        return 2
    src = open(LINUXIO).read()
    if "--selftest" in sys.argv:
        base = checks(src)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated source already fails:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(src)
        for name, msrc in ms:
            if msrc == src:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n for n, ok, _ in checks(msrc) if not ok]
            if caught:
                print("  [caught] %s  (%d check(s) failed)" % (name, len(caught)))
            else:
                print("  [MISSED] %s" % name)
                bad += 1
        print("test-inputeof-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    print("linuxio : %s" % LINUXIO)
    res = checks(src)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail) + ")"))
        fails += 0 if ok else 1
    print("test-inputeof-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
