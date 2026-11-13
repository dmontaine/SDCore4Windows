#!/usr/bin/env python3
# test-noreturn-units.py - a C file that redeclares k_error() __attribute__((noreturn)) never makes a call that returns (S.125, 7 Nov 2026).
# k_error() RETURNS when its message begins '!' (k_error.c: fatal = (*message != '!')).  Fourteen files redeclare it noreturn "for the
# analyzer" (Composer AI, Jun 2026).  At -O0 the attribute changed nothing; at -O2 (S.125) the compiler believes it and emits nothing after
# the call, so a '!' call in such a file runs off the end of its function: op_skt.c's SOCKET_DEBUG connect messages did, and a refused
# OPEN.SOCKET died with Fault type 11 in op_setskt (sandbox-qmclient.py O1, the complete regression of 7 Nov).  op_skt.c's redeclaration was
# removed.  This check refuses, in every file that makes the promise:
#   N1 a call whose message is a string literal beginning '!';
#   N2 a call of sysmsg(N) whose message file sdsys/messages/N begins '!';
#   N3 a call whose message is neither a literal nor sysmsg(...): a text this check cannot see;
#   N4 the null case - fewer than 10 such files or fewer than 100 calls read means the scan read nothing it should.
# FREE CHECK: the C read as text, comments removed; no build.  It cannot see a call made through a pointer or a macro.
#
#   python sdb_ai/sd64/gplbld/test-noreturn-units.py
#   python sdb_ai/sd64/gplbld/test-noreturn-units.py --selftest
#   (13 Nov 26 Windows port - from Linux b1d496df, RELEASE_1.1 254, the test-subset audit's item 2: the commands only.)
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.normpath(os.path.join(HERE, "..", "gplsrc"))
MSG = os.path.normpath(os.path.join(HERE, "..", "sdsys", "messages"))
DECL = re.compile(r"void\s+k_error\s*\(\s*char\s+msg\s*\[\s*\]\s*,\s*\.\.\.\s*\)\s*__attribute__\s*\(\(\s*noreturn\s*\)\)\s*;")


def strip_comments(s):
    """C comments out, string literals kept (a '/*' inside a string is not a comment)"""
    out, i, n = [], 0, len(s)
    while i < n:
        if s.startswith("/*", i):
            j = s.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif s.startswith("//", i):
            j = s.find("\n", i)
            i = n if j < 0 else j
        elif s[i] in "\"'":
            q, j = s[i], i + 1
            while j < n and s[j] != q:
                j += 2 if s[j] == "\\" else 1
            out.append(s[i:j + 1])
            i = j + 1
        else:
            out.append(s[i])
            i += 1
    return "".join(out)


def message_text(num, msgdir):
    p = os.path.join(msgdir, str(num))
    if not os.path.isfile(p):
        return None
    with open(p, encoding="latin-1") as f:
        return f.read()


def scan(files, msgdir):
    """files: {name: text}.  Returns (declaring files, calls read, faults)"""
    decl, ncalls, faults = [], 0, []
    for name, text in sorted(files.items()):
        c = strip_comments(text)
        if not DECL.search(c):
            continue
        decl.append(name)
        body = DECL.sub(" ", c)
        for m in re.finditer(r"\bk_error\s*\(\s*", body):
            ncalls += 1
            line = body.count("\n", 0, m.start()) + 1
            rest = body[m.end():]
            if rest.startswith('"'):
                if rest.startswith('"!'):
                    faults.append("N1 %s:%d a '!' literal - k_error() returns here" % (name, line))
            elif rest.startswith("sysmsg"):
                mm = re.match(r"sysmsg\s*\(\s*(\d+)\s*\)", rest)
                if mm:
                    t = message_text(mm.group(1), msgdir)
                    if t is not None and t.startswith("!"):
                        faults.append("N2 %s:%d sysmsg(%s) begins '!' - k_error() returns here" % (name, line, mm.group(1)))
            else:
                faults.append("N3 %s:%d a message this check cannot see: %s" % (name, line, rest[:40].split("\n")[0]))
    return decl, ncalls, faults


def load(srcdir):
    files = {}
    for p in glob.glob(os.path.join(srcdir, "*.c")):
        with open(p, encoding="latin-1") as f:
            files[os.path.basename(p)] = f.read()
    return files


def verdict(files, msgdir, quiet=False):
    decl, ncalls, faults = scan(files, msgdir)
    rows = [("N1-N3 no call that returns in a file that promises it never does", not faults, "; ".join(faults)),
            ("N4 the scan read something (%d files declaring noreturn, %d calls; need 10 and 100)" % (len(decl), ncalls),
             len(decl) >= 10 and ncalls >= 100, "")]
    if not quiet:
        print("test-noreturn-units: source %s, messages %s" % (SRC, MSG))
        print("  files that redeclare k_error() noreturn: %s" % " ".join(decl))
        for name, ok, detail in rows:
            print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, ("  <- " + detail) if (detail and not ok) else ""))
        good = sum(1 for _, ok, _ in rows if ok)
        print("%d passed, %d failed" % (good, len(rows) - good))
    return all(ok for _, ok, _ in rows)


def selftest():
    base = load(SRC)
    tmp_msg = {}
    results = []

    def mutant(label, mutate, msgdir=MSG):
        files = dict(base)
        mutate(files)
        ok = verdict(files, msgdir, quiet=True)
        results.append((label, not ok))

    def first_declaring(files):
        return next(n for n in sorted(files) if DECL.search(strip_comments(files[n])))

    def plant_bang(files):
        n = first_declaring(files)
        files[n] += '\nvoid zz(void) { k_error("!planted %d\\n", 1); }\n'

    def put_back_skt(files):
        files["op_skt.c"] = "void k_error(char msg[], ...) __attribute__((noreturn));\n" + files["op_skt.c"]

    def plant_variable(files):
        n = first_declaring(files)
        files[n] += "\nvoid zz(char *m) { k_error(m); }\n"

    def plant_bang_message(files):
        n = first_declaring(files)
        files[n] += "\nvoid zz(void) { k_error(sysmsg(12190)); }\n"   # 12190 (Linux 11185) is the one shipped text that begins '!'

    def empty(files):
        files.clear()

    def bang_in_comment_only(files):
        n = first_declaring(files)
        files[n] += '\n/* k_error("!only a comment"); */\n'

    mutant("a '!' literal planted in a declaring file", plant_bang)
    mutant("op_skt.c's redeclaration put back (its three '!' calls)", put_back_skt)
    mutant("a call with a variable message", plant_variable)
    mutant("sysmsg(12190), a message that begins '!'", plant_bang_message)
    mutant("nothing to read (null case)", empty)
    # a control: a '!' call inside a comment is not a call, and must NOT fail
    files = dict(base)
    bang_in_comment_only(files)
    control_ok = verdict(files, MSG, quiet=True)
    print("test-noreturn-units --selftest")
    for label, caught in results:
        print("  [%s] mutant: %s" % ("CAUGHT" if caught else "NOT CAUGHT", label))
    print("  [%s] control: a '!' call inside a comment passes" % ("PASS" if control_ok else "FAIL"))
    n_ok = sum(1 for _, c in results if c) + (1 if control_ok else 0)
    print("%d passed, %d failed" % (n_ok, len(results) + 1 - n_ok))
    return n_ok == len(results) + 1


if __name__ == "__main__":
    if "--selftest" in sys.argv[1:]:
        sys.exit(0 if selftest() else 1)
    sys.exit(0 if verdict(load(SRC), MSG) else 1)
