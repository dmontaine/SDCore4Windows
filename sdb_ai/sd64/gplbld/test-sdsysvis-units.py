#!/usr/bin/env python3
"""test-sdsysvis-units.py - SDSYS may have more than one session, and a second one is VISIBLE (S.76, the owner's decision of 26 Oct 2026), as invariants read off the source.  Free: no install, no sudo, no sd.

    python C:/Users/Don/Projects/SDCore4Windows/sdb_ai/sd64/gplbld/test-sdsysvis-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the BASIC of four programs as text, with comments removed: the routine `!SDSYSN` that counts the sessions of SDSYS on a terminal, `login`
(the audit line), `tool_sessions` (the mark on the rows) and `tool_home` (the home screen's signed-on line).  ***IT RUNS NOTHING, SO IT CANNOT SAY THAT A LINE REACHES THE AUDIT
TRAIL OR THAT A ROW SHOWS A MARK.***  What a text check is for: the properties that decide WHAT COUNTS - the account, the terminal, the flags - and WHEN a thing is said, which an
edit moves without a compile error.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.

12 Nov 26 Windows port - carried from SD Core for Linux with LOGIN's half of S.76 (RELEASE_1.1 252, P-15).  Two adaptations, both to this port's text and not to
what is checked: SV4 accepts the sign-on line as this port writes it ('login account=' : audit.account, the same name at that point), and SV9 reads BBPROC's
list without regard to case (this port's list is upper case, '_SDSYSN').
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "rt": os.path.join(GPL, "_sdsysn"),
    "login": os.path.join(GPL, "login"),
    "ts": os.path.join(GPL, "tool_sessions"),
    "th": os.path.join(GPL, "tool_home"),
    "bb": os.path.join(GPL, "bbproc"),
}


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    return raw


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


def block(text, label):
    """The text of an internal subroutine: from its label to the next label at the start of a line (or to END)."""
    m = re.search(r"^" + re.escape(label) + r":\s*$", text, re.M)
    if not m:
        return ""
    n = re.search(r"^[a-z][a-z.0-9]*:\s*$|^end\s*$", text[m.end():], re.M)
    return text[m.start(): m.end() + (n.start() if n else len(text))]


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    rt, lg, ts, th = (strip_bas(raw[k]) for k in ("rt", "login", "ts", "th"))
    ck("SV0", "NULL CASE: the routine, login, the sessions page and the home screen were found and are not empty (a check on nothing would pass)",
       all(len(x) > 400 for x in (rt, lg, ts, th)), repr([len(x) for x in (rt, lg, ts, th)]))
    ck("SV1", "!SDSYSN is an internal subroutine with four arguments (the count, the user numbers, whether the caller is one, whether the caller is on a terminal), read from the kernel's user table and nowhere else",
       "subroutine sdsysn(n, uids, mine, mytty)" in rt and "$catalog !SDSYSN" in rt and "$internal" in rt and "users = kernel(K$USERS, 0)" in rt and "for i = 1 to dcount(users, @fm)" in rt, "")
    ck("SV2", "what counts as a session of SDSYS: the account is sdsys (any case) AND it is on a terminal AND it is not a phantom, an API process, an SDNet process or a session being logged out; the caller is 'mine' by its user number, whatever its own account field says",
       "downcase(uv<1, K$USERS.ACCOUNT>) = 'sdsys' and has.tty" in rt and "has.tty = (uv<1, K$USERS.DEV> # '')" in rt
       and all(("not(bitand(flg, USR$%s))" % f) in rt for f in ("PHANTOM", "SDVBSRVR", "SDNET", "LOGOUT")) and "uids<-1> = uid" in rt and "if uid = @userno then mine = 1" in rt and "if uid = @userno then mytty = has.tty" in rt, "")
    ck("SV3", "the routine only reads: no audit line, no write, delete, execute or screen statement",
       "K$AUDIT" not in rt and not re.search(r"^\s*(write|writev|delete|execute|screen|display|crt|print)\b", rt, re.M), "")
    # login (Windows: the sign-on line names audit.account)
    i_login = max(lg.find("'login account=' : initial.account)"), lg.find("'login account=' : audit.account)"))
    i_call = lg.find("call !sdsysn(sd.n, sd.uids, sd.mine, sd.tty)")
    i_aud = lg.find("'sdsys second session others='")
    i_ok = lg.find("   ok = @true\n   return")
    ck("SV4", "login writes the second line ONLY for a sign-on to SDSYS, ONLY from a session on a terminal and ONLY when another session of SDSYS is on one (the caller may not have entered its account yet, so 'others' is the count less the caller if it is in it), after the sign-on's own line, in the success branch, once",
       0 <= i_login < i_call < i_aud < i_ok and lg.count("call !sdsysn(") == 1 and lg.count("'sdsys second session others='") == 1
       and "if downcase(initial.account) = 'sdsys' then" in lg and "if sd.tty and sd.n - sd.mine > 0 then void kernel(K$AUDIT, 'sdsys second session others=' : sd.n - sd.mine)" in lg
       and lg.find("if mode = 0 then") < i_login, "")
    ck("SV5", "the audit words are lower case (the owner's rule for the whole trail): the key and every word before the equals sign",
       re.fullmatch(r"[a-z ]+", "sdsys second session others") is not None and "SDSYS SECOND" not in lg, "")
    # tool_sessions
    ra = block(ts, "read.all")
    sl = block(ts, "session.line")
    ds = block(ts, "draw.sessions")
    rs = block(ts, "row.session")
    ck("SV6", "tool.sessions asks !SDSYSN once, when it reads the sessions (not on every draw), and says it three ways only when SDSYS is in more than one place: 'sdsys xN' in the State column of those rows only, 'SDSYS in N places' in the counts line, a sentence under the cursor",
       ts.count("call !sdsysn(") == 1 and "call !sdsysn(nsd, sduids, sdmine, sdtty)" in ra
       and "if nsd > 1 and index(@fm : sduids : @fm, @fm : v<1, 1> : @fm, 1) > 0 then stt := (if stt = '' then '' else ' ') : 'sdsys x' : nsd" in sl
       and "if nsd > 1 then s := 'SDSYS in ' : nsd : ' places.   '" in ds
       and "if nsd > 1 and index(@fm : sduids : @fm, @fm : uid : @fm, 1) > 0 then lines<-1> = 'One of ' : nsd : ' sessions of SDSYS on a terminal." in rs, "")
    ck("SV7", "tool.sessions changes nothing for this: it still runs the same three commands (the allow list is unchanged) and writes no audit line for the mark",
       "allow = 'logout unlock inhibit.login'" in ts and ts.count("allow = ") == 1 and "sdsys second session" not in re.sub(r"'One of[^\n]*", "", ts), "")
    # tool_home
    ls = block(th, "live.sessions")
    ck("SV8", "the home screen's signed-on line is 'N signed on' as before, and 'N signed, M sdsys' (18 characters for two-digit numbers, the tile is 19 wide) only when SDSYS is in more than one place; the routine is asked in that one routine",
       th.count("call !sdsysn(") == 1 and "call !sdsysn(sdn, sdids, sdmine, sdtty)" in ls and "txt = n : ' signed on'" in ls and "if sdn > 1 then txt = n : ' signed, ' : sdn : ' sdsys'" in ls, "")
    # bbproc (Windows: the list is upper case, so it is read lower-cased)
    bb = strip_bas(raw["bb"]).lower()
    ck("SV9", "the bootstrap compiles !SDSYSN BEFORE LOGIN first runs as SDSYS (every pass after the first signs on as SDSYS: without it SECOND.COMPILE died \"Unable to load '!SDSYSN' object code in $LOGIN\", measured on Linux 26 Oct 2026): it is on BBPROC's list, after login",
       "src.list<-1> = '_sdsysn'" in bb and 0 <= bb.find("src.list<-1> = 'login'") < bb.find("src.list<-1> = '_sdsysn'") < bb.find("src.cnt = dcount(src.list,@fm)"), "")
    return rows


def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        n = r[key].count(old)
        if n != 1:
            raise KeyError("%s: %r is found %d times, not once, so the mutant cannot be made" % (key, old[:70], n))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


def setkey(key, val):
    def f(raw):
        r = dict(raw)
        r[key] = val
        return r
    return f


MUTANTS = [
    ("the routine counts a session with no terminal", "SV2", sub("rt", "'sdsys' and has.tty then", "'sdsys' then")),
    ("the routine counts a phantom", "SV2", sub("rt", "not(bitand(flg, USR$PHANTOM)) and ", "")),
    ("the routine counts an API process", "SV2", sub("rt", " and not(bitand(flg, USR$SDVBSRVR))", "")),
    ("the routine counts a session being logged out", "SV2", sub("rt", " and not(bitand(flg, USR$LOGOUT))", "")),
    ("the account is compared in its own case", "SV2", sub("rt", "downcase(uv<1, K$USERS.ACCOUNT>) = 'sdsys'", "uv<1, K$USERS.ACCOUNT> = 'sdsys'")),
    ("the caller is 'mine' by its pid", "SV2", sub("rt", "if uid = @userno then mine = 1", "if uv<1, K$USERS.PID> = @userno then mine = 1")),
    ("the routine writes an audit line itself", "SV3", sub("rt", "   return\nend", "   void kernel(K$AUDIT, 'x')\n   return\nend")),
    ("login says it for every account", "SV4", sub("login", "if downcase(initial.account) = 'sdsys' then", "if 1 then")),
    ("login says it for the first session too", "SV4", sub("login", "sd.n - sd.mine > 0 then", "sd.n - sd.mine >= 0 then")),
    ("login says it for a session with no terminal", "SV4", sub("login", "if sd.tty and sd.n - sd.mine > 0 then", "if sd.n - sd.mine > 0 then")),
    ("login counts the caller as another session", "SV4", sub("login", "'sdsys second session others=' : sd.n - sd.mine)", "'sdsys second session others=' : sd.n)")),
    ("the audit words are upper case", "SV4", sub("login", "'sdsys second session others='", "'SDSYS second session others='")),
    ("the sessions page asks the routine on every draw", "SV6", sub("ts", "   s = ns : ' sessions: '", "   call !sdsysn(nsd, sduids, sdmine, sdtty)\n   s = ns : ' sessions: '")),
    ("every row is marked", "SV6", sub("ts", "if nsd > 1 and index(@fm : sduids : @fm, @fm : v<1, 1> : @fm, 1) > 0 then stt", "if index(@fm : sduids : @fm, @fm : v<1, 1> : @fm, 1) > 0 then stt")),
    ("the counts line always says it", "SV6", sub("ts", "if nsd > 1 then s := 'SDSYS in '", "if 1 then s := 'SDSYS in '")),
    ("the sessions page can run another command", "SV7", sub("ts", "allow = 'logout unlock inhibit.login'", "allow = 'logout unlock inhibit.login sh'")),
    ("the home tile says it for one session", "SV8", sub("th", "if sdn > 1 then txt", "if sdn > 0 then txt")),
    ("the home tile loses the old text", "SV8", sub("th", "   txt = n : ' signed on'\n   call !sdsysn(", "   txt = n : ' on'\n   call !sdsysn(")),
    ("the routine is not on the bootstrap list", "SV9", sub("bb", "src.list<-1> = '_SDSYSN'\n", "")),
    ("the routine is not found", "SV0", setkey("rt", "")),
]


def report(rows):
    bad = 0
    for i, what, ok, detail in rows:
        print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, "" if ok or not detail else "   <- " + str(detail)[:200]))
        bad += 0 if ok else 1
    return bad


def selftest(raw):
    base = [r[0] for r in checks(raw) if not r[2]]
    if base:
        print("selftest: the unchanged tree fails %s, so a mutant's own failure cannot be told from the tree's; run the plain check first" % base)
        return 1
    holes = 0
    for name, want, mut in MUTANTS:
        try:
            m = mut(raw)
        except KeyError as exc:
            print("  [FAIL] selftest: %s  <- %s" % (name, exc))
            holes += 1
            continue
        failed = sorted({r[0] for r in checks(m) if not r[2]})
        hit = want in failed
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("PASS" if hit else "FAIL", name, want, " ".join(failed) or "none"))
        holes += 0 if hit else 1
    print("selftest: %d mutants, %d not caught" % (len(MUTANTS), holes))
    return 1 if holes else 0


def main(argv):
    raw = load()
    print("test-sdsysvis-units: tree %s" % os.path.dirname(GPL))
    if not raw["rt"]:
        print("test-sdsysvis-units: CANNOT RUN - %s is not there" % FILES["rt"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-sdsysvis-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
