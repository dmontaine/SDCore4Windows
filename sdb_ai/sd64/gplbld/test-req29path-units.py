#!/usr/bin/env python3
"""test-req29path-units.py - API request 29 asks the OS switch of an F-pointer that leads out of the account, as invariants read off apisrvr.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-req29path-units.py
  python3 .../test-req29path-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.  Written 20 Oct 26.

THE RULE (the owner delegated the choice on 20 Oct 2026, "request 29 your choice": close it).  Request 29 (vb.open.sdnet) opens the file the VOC of the account NAMED
holds an F-pointer to, with `openpath` from an internal program, which the OS gate exempts.  So a pointer at a directory OUTSIDE the account (a path, a relative path that
climbs out, a link, a sibling directory, a system file) was opened for any caller the NET gate admitted.  Now the pointer must lead inside the account's directory
(`kernel(K$PATH.IN, <account directory> : @fm : <path>)`: the geometry alone, ".." and links resolved) unless the account NAMED holds os-on in its register record, or the
caller is SDSYS entering its own account.  A refusal is error ELSE with status 3035 (ER$PERM, what DIR and OPENSEQ answer) and an audit line
`api refused request=29 reason=os gate off user=... account=... path=...`.

***WHAT THIS IS, AND WHAT IT IS NOT.***  It reads the BASIC source as text with the comments removed.  IT RUNS NOTHING, so it cannot say that the rule refuses anybody:
sandbox-req29.py section X does (a real `sd -Q`, eight pointers in two accounts, the planted record read back from the disk, and four mutants on the sandbox's own copy).
What a text check is for here is the ADMINISTRATOR CLAUSE, which no sandbox can run (an API session of the OS user sdsys needs that user), and ORDER: the question is
asked of the account NAMED and not of the session's account (K$PATH.OK would be the session's), after the pointer is made absolute and before the file is opened, and the
refusal returns.

--selftest runs every check on the real source and then on a copy with one deliberate fault at a time: each must make a check fail.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.normpath(os.path.join(HERE, ".."))
APISRVR = os.path.join(SD64, "sdsys", "gpl.bp", "apisrvr")

FREE = "net.free = (upcase(trim(net.rec<ACC$OS.EXEC>)) = 'YES' or (downcase(@logname) = 'sdsys' and net.acct = 'sdsys'))"


def strip_bas(src):
    out = []
    for line in src.split("\n"):
        s = line.lstrip()
        if s.startswith("*") or s.startswith("!"):
            out.append("")
            continue
        cut = line.find(";*")
        out.append(line if cut < 0 else line[:cut])
    return "\n".join(out)


def squeeze(text):
    return re.sub(r"\s+", " ", text).strip()


def body_of(text, first, last):
    """From the line `first:` to the line `last:` (labels in column 1); empty when either is missing."""
    a = re.search(r"^%s:\s*$" % re.escape(first), text, re.M)
    b = re.search(r"^%s:\s*$" % re.escape(last), text, re.M)
    if not a or not b or b.start() < a.start():
        return ""
    return text[a.start():b.start()]


def ordered(text, *needles):
    pos = -1
    for n in needles:
        p = text.find(n, pos + 1)
        if p < 0:
            return False
        pos = p
    return True


def checks(raw):
    """[(id, what, ok, detail)] for the apisrvr text RAW."""
    code = strip_bas(raw)
    body = squeeze(body_of(code, "vb.open.sdnet", "vb.lock.record"))
    acct = squeeze(body_of(code, "sdnet.account.check", "vb.account"))
    out = []

    def add(i, what, ok, detail=""):
        out.append((i, what, bool(ok), detail))

    add("P0", "NULL CASE: the text of vb.open.sdnet and of sdnet.account.check was found (a check on nothing would pass)", len(body) > 500 and len(acct) > 300, "%d / %d bytes" % (len(body), len(acct)))
    make_abs = "path = acc : @ds : path"
    ask = "if not(kernel(K$PATH.IN, acc : @fm : path)) then"
    opn = "openpath path to files(i)"
    add("P1", "ORDER: the pointer is made absolute, then the exemption is worked out, then the geometry is asked, and only then is the file opened",
        ordered(body, make_abs, FREE, ask, opn), "")
    add("P2", "THE EXEMPTION is exactly the account NAMED holding os-on (its register record), or SDSYS in its own account: no other clause, and the administrator by name only for the sdsys account",
        body.count(FREE) == 1 and body.count("net.free") == 2, "")
    add("P3", "THE QUESTION IS THE NAMED ACCOUNT'S: K$PATH.IN with the account's directory (acc, from its register record), and K$PATH.OK - the session's own account - is not asked in this request",
        body.count(ask) == 1 and "K$PATH.OK" not in body, "")
    add("P4", "THE ACCOUNT DIRECTORY is the one the register gave: acc is net.acc.path, which sdnet.account.check sets from the record's path and only when every rule passed",
        "acc = net.acc.path" in body and "net.acc.path = parse.pathname.tokens(net.rec<ACC$PATH>)" in acct, "")
    refusal = ""
    m = re.search(re.escape(ask) + r"(.*?)\bend end\b", body)
    if m:
        refusal = m.group(1)
    add("P5", "THE REFUSAL audits, answers status 3035 (ER$PERM) with error ELSE, and RETURNS before the file is opened",
        ordered(refusal, "kernel(K$AUDIT,", "set.status ER$PERM", "server.error = SV$ELSE", "return"), refusal[:200])
    add("P6", "THE AUDIT LINE is lower case and names the user, the account and the path: 'api refused request=29 reason=os gate off user=' @logname ' account=' net.acct ' path=' path",
        "'api refused request=29 reason=os gate off user=' : @logname : ' account=' : net.acct : ' path=' : path)" in refusal, "")
    add("P7", "THE REGISTER IS READ AT EACH REQUEST: sdnet.account.check clears net.rec, reads the account's record and net.rec is not set anywhere else",
        "net.rec = ''" in acct and "read net.rec from net.f, net.acct" in acct and len(re.findall(r"\bnet\.rec\s*=", body)) == 0, "")
    add("P8", "THE ACCOUNT RULES COME FIRST: sdnet.account.check is asked, and returns when it refused, before the pointer is read from the VOC",
        ordered(body, "gosub sdnet.account.check", "if net.refused then return", "qvoc.path", "path = voc.rec<j>", ask), "")
    add("P9", "BOTH HALVES OF THE POINTER are judged by the one question: the data path and the DICT path are chosen into `path` (j = 2 or 3) before it, and nothing between the choice and the open changes `path` again but the @SDSYS prefix and the relative form",
        ordered(body, "path = voc.rec<j>", "path = @sdsys:path[7,9999]", make_abs, ask, opn) and len(re.findall(r"(?<![\w.])(?<!if )path = ", body)) == 3,
        "%d assignments of path" % len(re.findall(r"(?<![\w.])(?<!if )path = ", body)))
    return out


def run(raw, quiet=False):
    rows = checks(raw)
    bad = [r for r in rows if not r[2]]
    if not quiet:
        for i, what, ok, detail in rows:
            print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, ("   <- " + detail) if (detail and not ok) else ""))
    return rows, bad


MUTANTS = [
    ("the geometry is the SESSION's account's: K$PATH.OK instead of K$PATH.IN", "kernel(K$PATH.IN, acc : @fm : path)", "kernel(K$PATH.OK, path)"),
    ("the arguments of K$PATH.IN are swapped", "kernel(K$PATH.IN, acc : @fm : path)", "kernel(K$PATH.IN, path : @fm : acc)"),
    ("the administrator clause is gone", FREE, "net.free = (upcase(trim(net.rec<ACC$OS.EXEC>)) = 'YES')"),
    ("the administrator clause is any account of SDSYS", FREE, FREE.replace("(downcase(@logname) = 'sdsys' and net.acct = 'sdsys')", "(downcase(@logname) = 'sdsys')")),
    ("the exemption is anybody who asks for sdsys's account", FREE, FREE.replace("(downcase(@logname) = 'sdsys' and net.acct = 'sdsys')", "(net.acct = 'sdsys')")),
    ("the exemption reads the sh switch, not os", FREE, FREE.replace("ACC$OS.EXEC", "ACC$SH")),
    ("the exemption reads the net gate, not os", FREE, FREE.replace("ACC$OS.EXEC", "ACC$NET")),
    ("nobody is exempt: the switch test is a constant false", FREE, "net.free = @false"),
    ("everybody is exempt", FREE, "net.free = @true"),
    ("the refusal does not return", "set.status ER$PERM\n                                       server.error = SV$ELSE\n                                       return\n", "set.status ER$PERM\n                                       server.error = SV$ELSE\n"),
    ("the refusal answers another status", "set.status ER$PERM", "set.status ER$XREMOTE"),
    ("the refusal is not audited", "void kernel(K$AUDIT, 'api refused request=29 reason=os gate off user=' : @logname : ' account=' : net.acct : ' path=' : path)", "null"),
    ("the audit words are upper case", "'api refused request=29 reason=os gate off user='", "'API REFUSED REQUEST=29 REASON=OS GATE OFF USER='"),
    ("the audit line leaves the path out", " : ' path=' : path)", ")"),
    ("the register record is cached across requests", "net.rec = ''\nnet.found = @false", "net.found = @false"),
    ("the account directory is the session's working directory", "acc = net.acc.path", "acc = ospath('', os$cwd)"),
]


def selftest():
    with open(APISRVR, encoding="utf-8", errors="replace") as f:
        raw = f.read()
    rows, bad = run(raw)
    if bad:
        print("selftest: the real source already fails %d check(s)" % len(bad))
        return 1
    killed = 0
    missed = []
    for what, old, new in MUTANTS:
        if raw.count(old) != 1:
            print("  [CANNOT] %s: the text to change is found %d times, not once" % (what, raw.count(old)))
            return 2
        rows_m, bad_m = run(raw.replace(old, new), quiet=True)
        if bad_m:
            killed += 1
            print("  [killed] %s  <- %s" % (what, ", ".join(r[0] for r in bad_m)))
        else:
            missed.append(what)
            print("  [MISSED] %s" % what)
    print("selftest: %d mutants, %d killed, %d missed" % (len(MUTANTS), killed, len(missed)))
    return 0 if not missed else 1


def main():
    if not os.path.isfile(APISRVR):
        print("CANNOT RUN: %s is not there" % APISRVR)
        return 2
    if "--selftest" in sys.argv:
        return selftest()
    with open(APISRVR, encoding="utf-8", errors="replace") as f:
        raw = f.read()
    rows, bad = run(raw)
    print("test-req29path-units: %d passed, %d failed" % (len(rows) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
