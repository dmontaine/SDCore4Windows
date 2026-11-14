#!/usr/bin/env python3
"""test-pipefds-units.py - a child SD detaches with daemon() gives back a pipe on fds 0-2 (S.241).

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-pipefds-units.py
  python3 .../test-pipefds-units.py --selftest

No sudo, no install, no sd.  Exit 0 all checks passed, 1 a check failed, 2 it could not run.  Written 14 Nov 26.

THE DEFECT (found by the Windows port, mail 14 Nov 2026 T1030; measured here on Dev e7fa80b7 the same day): start_lnxd()
forked sdlnxd with daemon(1, 1), which keeps fds 0-2, and nothing re-pointed them, so x=$(sd -start) waited until sd -stop.
The startup command's fork and a phantom (op_kernel.c op_phantom()) have the same shape.  The fix is release_pipe_fds()
(sysseg.c): each of 0-2 that is a FIFO is reopened on /dev/null, a file, a terminal and a socket are kept.

***WHAT THIS IS AND IS NOT.***  It reads gplsrc/sysseg.c, op_kernel.c and sd.h as text (comments removed): the function
tests S_ISFIFO on 0, 1 and 2 only and reopens on /dev/null, and EVERY daemon( call in the kernel sources is followed by a
call of it before the exec.  It cannot say a pipe is given back: sandbox-pipefds.py measures that for sdlnxd and a phantom.
--selftest mutates the source and requires each mutant to be caught.

14 Nov 26 Windows port - from Linux e99979d6 (RELEASE_1.1 284): TWO daemon() sites here, sdwind's (sysseg.c start_sd())
and a phantom's (op_kernel.c); the startup command and its fork are gone on Windows (RELEASE_1.1 119), so its check and
mutant are out.  Run it as python, not python3.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.abspath(os.path.join(HERE, os.pardir, "gplsrc"))
FILES = ("sysseg.c", "op_kernel.c", "sd.h")


def strip_comments(text):
    text = re.sub(r"/\*.*?\*/", lambda m: "\n" * m.group(0).count("\n"), text, flags=re.S)
    return re.sub(r"//[^\n]*", "", text)


def func_body(code, name):
    m = re.search(r"\bvoid\s+" + name + r"\s*\(\s*void\s*\)\s*\{", code)
    if not m:
        return None
    depth, i = 1, m.end()
    while i < len(code) and depth:
        depth += {"{": 1, "}": -1}.get(code[i], 0)
        i += 1
    return code[m.end():i - 1]


def checks(srcs):
    out = []

    def ck(name, ok, detail=""):
        out.append((name, bool(ok), detail))

    code = {f: strip_comments(t) for f, t in srcs.items()}
    body = func_body(code["sysseg.c"], "release_pipe_fds")
    ck("sysseg.c defines void release_pipe_fds(void)", body is not None)
    body = body or ""
    ck("sd.h declares it", re.search(r"\bvoid\s+release_pipe_fds\s*\(\s*void\s*\)\s*;", code["sd.h"]))
    ck("it walks fds 0 to 2 and no further", re.search(r"for\s*\(\s*fd\s*=\s*0\s*;\s*fd\s*<=\s*2\s*;", body), "loop not found")
    ck("it acts only on a FIFO (S_ISFIFO of fstat), so a file, terminal or socket is kept",
       re.search(r"fstat\s*\(\s*fd\s*,\s*&st\s*\)\s*!=\s*0\s*\|\|\s*!\s*S_ISFIFO\s*\(\s*st\.st_mode\s*\)", body)
       and re.search(r"\bcontinue\b", body) and "S_ISREG" not in body and "isatty" not in body)
    ck("it opens /dev/null, read for 0 and write for 1 and 2",
       re.search(r'open\s*\(\s*"/dev/null"\s*,\s*\(\s*fd\s*==\s*0\s*\)\s*\?\s*O_RDONLY\s*:\s*O_WRONLY\s*\)', body))
    ck("it puts /dev/null on the fd with dup2 and closes the spare", re.search(r"dup2\s*\(\s*null_fd\s*,\s*fd\s*\)", body)
       and re.search(r"close\s*\(\s*null_fd\s*\)", body))
    ck("it never closes 0-2 outright (a closed fd would be reused by the next open)", not re.search(r"close\s*\(\s*fd\s*\)", body))

    # every daemon( call is followed, before the next exec, by release_pipe_fds()
    sites = 0
    for f in ("sysseg.c", "op_kernel.c"):
        c = re.sub(r'"(?:[^"\\\n]|\\.)*"', '""', code[f])  # "daemon() failed" in a message is not a call
        for m in re.finditer(r"\bdaemon\s*\(", c):
            sites += 1
            rest = c[m.end():]
            ex = re.search(r"\bexec[lv]p?e?\s*\(", rest)
            rel = re.search(r"\brelease_pipe_fds\s*\(\s*\)\s*;", rest)
            line = c[:m.start()].count("\n") + 1
            ck("%s:%d daemon() is followed by release_pipe_fds() before the exec" % (f, line),
               ex and rel and rel.start() < ex.start(), "release %s, exec %s" % (rel and rel.start(), ex and ex.start()))
    ck("two daemon() sites are found (sdwind, a phantom; Windows has no startup command)", sites == 2, "found %d" % sites)
    return out


def mutants(srcs):
    res = []

    def mut(name, f, old, new):
        if old not in srcs[f]:
            res.append((name, None))
            return
        m = dict(srcs)
        m[f] = srcs[f].replace(old, new, 1)
        res.append((name, m))

    mut("the phantom's call is gone", "op_kernel.c", "    release_pipe_fds(); /* 14 Nov 26 S.241", "    /* 14 Nov 26 S.241")
    mut("sdwind's call is gone", "sysseg.c", "    release_pipe_fds(); /* S.241: after", "    /* S.241: after")
    mut("every fd is reopened, a file too", "sysseg.c", "if (fstat(fd, &st) != 0 || !S_ISFIFO(st.st_mode))",
        "if (fstat(fd, &st) != 0)")
    mut("the loop stops at fd 1", "sysseg.c", "for (fd = 0; fd <= 2; fd++)", "for (fd = 0; fd <= 1; fd++)")
    mut("stdin opened for writing", "sysseg.c", "(fd == 0) ? O_RDONLY : O_WRONLY", "O_WRONLY")
    mut("the fd is closed instead of re-pointed", "sysseg.c", "      dup2(null_fd, fd);\n", "      close(fd);\n")
    mut("the declaration is gone", "sd.h", "void release_pipe_fds(void);", "")
    return res


def main():
    srcs = {}
    for f in FILES:
        p = os.path.join(SRC, f)
        if not os.path.isfile(p):
            print("test-pipefds-units: CANNOT RUN - no %s" % p)
            return 2
        srcs[f] = open(p, errors="replace").read()
    if "--selftest" in sys.argv:
        base = checks(srcs)
        if not all(ok for _, ok, _ in base):
            print("selftest: CANNOT RUN - the unmutated source already fails:")
            for n, ok, d in base:
                if not ok:
                    print("  FAIL %s (%s)" % (n, d))
            return 2
        bad = 0
        ms = mutants(srcs)
        for name, m in ms:
            if m is None:
                print("  [NOT APPLIED] %s" % name)
                bad += 1
                continue
            caught = [n for n, ok, _ in checks(m) if not ok]
            if caught:
                print("  [caught] %s  (%d check(s) failed)" % (name, len(caught)))
            else:
                print("  [MISSED] %s" % name)
                bad += 1
        print("test-pipefds-units --selftest: %d mutant(s), %d not caught" % (len(ms), bad))
        return 1 if bad else 0
    print("sources : %s (%s)" % (SRC, ", ".join(FILES)))
    res = checks(srcs)
    fails = 0
    for name, ok, detail in res:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok or not detail else "  (" + str(detail) + ")"))
        fails += 0 if ok else 1
    print("test-pipefds-units: %d checks, %d failed" % (len(res), fails))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
