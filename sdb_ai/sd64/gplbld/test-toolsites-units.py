#!/usr/bin/env python3
#
# test-toolsites-units.py - every place a full-screen page (gpl.bp/tool_*) writes or deletes a record or EXECUTEs a sentence is on a list, with the
# reason it is safe.  No install, no sudo, no sd: the programs are read as text.
#
#   python sdb_ai/sd64/gplbld/test-toolsites-units.py [--selftest]
#
# START-HISTORY:
# 9 Nov 26 dm  New (S.186, Fable's review of the TUI: "a free check over every write site in tool_*" and "every bare execute in tool_* is on a named
#              list").  The pages are $internal, so the kernel trusts them: a page that writes a record is the edit gate for that write, and a page that
#              EXECUTEs a sentence it built is the check on what the sentence may be.  Each site below was read on 9 Nov 26 and its guard named.
# 13 Nov 26 Windows port - from Linux b1d496df (RELEASE_1.1 254, the test-subset audit's item 6): tool_ai's and tool_audit's sites are not
#              listed, because Core has neither page yet (rows 246 and 247); they come back with the pages.
# END-HISTORY
#
# WHAT IT HOLDS.  A TRIPWIRE, NOT A PROOF: it finds every WRITE, WRITEU, WRITEV, MATWRITE, DELETE and EXECUTE statement in a tool_* program (comments
# and string literals taken out; a label such as delete.reached: is not a statement) and compares them, as their statement text, with SITES.  A new
# site, a changed one or one that went fails, naming it: whoever adds it reads its guard and lists it with the reason.  It cannot say that the guard
# named holds - the page's own suite and the kernel's gates do that.
#
# The reasons, one word each:
#   own        the page's own store: $hold, &queries&, the undo files, temporary pointers in SDSYS's VOC
#   gated      the page asked the account's edit gate (K$EDIT.OK) for the file first
#   admin      an administrator-only page (tk_open 'admin' first; the administrator passes the edit gates); tool.entries also keeps the pointer rule
#   confirmed  the sentence is shown in $tk_confirm and run only when the answer is Run
#   allowed    the sentence's first word is on the page's own short list, or it is built only from words the page checked
#   fixed      the sentence is a constant
#   home       the home screen runs a tile's command or a LOGTO as if typed at the prompt: the command processor applies the account's gates to it

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
GPL = os.path.join(HERE, "..", "sdsys", "gpl.bp")

STMT = re.compile(r"^\s*(execute|write|writeu|writev|writevu|matwrite|matwriteu|delete|deleteu)\s+(.*\S)\s*$", re.I)

# (program, kind, statement text with single blanks) -> reason
SITES = {
    ("tool_accounts", "execute", "execute sent"): "confirmed",
    ("tool_bulk", "execute", "execute ssent trapping aborts capturing sout rtnlist slv"): "allowed",
    ("tool_bulk", "execute", "execute MKUNDO trapping aborts capturing mkout"): "confirmed",
    ("tool_bulk", "write", "write hdr on uf, 'last' on error"): "own",
    ("tool_bulk", "write", "write id : @fm : digest(newrec, 0, 'MD5') : @fm : rec on uf, n.written on error"): "own",
    ("tool_bulk", "writeu", "writeu newrec on fv, id on error"): "gated",
    ("tool_bulk", "delete", "delete uf, n.written"): "own",
    ("tool_bulk", "writeu", "writeu ur on fv, uid on error"): "gated",
    ("tool_bulk", "write", "write uid : @fm : 'restored' : @fm : ur on uf, un.i on error null"): "own",
    ("tool_bulk", "write", "write uh on uf, 'last' on error null"): "own",
    ("tool_dict", "execute", "execute sent"): "allowed",
    ("tool_entries", "write", "write qrec on svf, qn on error"): "own",
    ("tool_entries", "delete", "delete svf, sw.id"): "own",
    ("tool_entries", "delete", "delete svf, qn"): "own",
    ("tool_entries", "delete", "delete tf, eid on error delok = @false"): "admin",
    ("tool_entries", "delete", "delete dof, doid on error dores = 'failed'"): "admin",
    ("tool_entries", "execute", "execute csent capturing cout"): "admin",
    ("tool_entries", "execute", "execute dbsent"): "admin",
    ("tool_entries", "execute", "execute sent"): "allowed",
    ("tool_entries", "write", "write ghdr on uf, 'last' on error"): "own",
    ("tool_entries", "write", "write ghdr on uf, 'last' on error null"): "own",
    ("tool_entries", "write", "write ea : @fm : gkw : @fm : (if efl = '' then 'voc' else efl) : @fm : eid : @fm : digest(gnew, 0, 'MD5') : @fm : grec on uf, gun on error"): "own",
    ("tool_entries", "writeu", "writeu gnew on gf, eid on error"): "admin",
    ("tool_entries", "delete", "delete uf, gun"): "own",
    ("tool_entries", "execute", "execute MKUNDO trapping aborts capturing mkout"): "admin",
    ("tool_entries", "writeu", "writeu ur on gf, uid on error"): "admin",
    ("tool_entries", "write", "write ur2 on uf, un.i on error null"): "own",
    ("tool_entries", "write", "write uh on uf, 'last' on error null"): "own",
    ("tool_files", "execute", "execute sent"): "allowed",
    ("tool_home", "execute", "execute 'quit'"): "fixed",
    ("tool_home", "execute", "execute sentence trapping aborts"): "home",
    ("tool_home", "execute", "execute 'logto ' : acct trapping aborts"): "home",
    ("tool_query", "execute", "execute run.s trapping aborts capturing out"): "allowed",
    ("tool_query", "execute", "execute qsent trapping aborts capturing mk"): "confirmed",
    ("tool_query", "write", "write wrec to qf, qname on error writeok = @false"): "own",
    ("tool_query", "delete", "delete qf, lname on error delok = @false"): "own",
    ("tool_remote", "execute", "execute sent"): "confirmed",
    ("tool_voc", "execute", "execute sent"): "allowed",
}
# a statement that is in a program more than once is counted: the list says how many times
COUNTS = {("tool_home", "execute", "execute 'quit'"): 2, ("tool_bulk", "write", "write hdr on uf, 'last' on error"): 2}
REASONS = {"own", "gated", "admin", "confirmed", "allowed", "fixed", "home"}

passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))
    return ok


def code_of(line):
    """The code of one line: a comment line is empty; string literals keep their quotes and lose their text; ;* ends the code."""
    s = line.rstrip("\n")
    t = s.lstrip()
    if t.startswith("*") or t.startswith("!"):
        return "", ""
    out, q = [], None
    for i, ch in enumerate(s):
        if q:
            out.append(ch if ch == q else " ")
            if ch == q:
                q = None
            continue
        if ch in "'\"":
            q = ch
            out.append(ch)
            continue
        if ch == ";" and s[i:i + 2] == ";*":
            return "".join(out), s[:i]
        out.append(ch)
    return "".join(out), s


def sites_of(texts):
    """texts: {program: source}.  Returns {(program, kind, statement): count}, the statement as written (strings kept), blanks made single."""
    found = {}
    for prog, src in texts.items():
        for line in src.split("\n"):
            code, raw = code_of(line)
            if not code.strip():
                continue
            # split at statement separators found in the CODE (a ; inside a string is not one), and cut the raw text at the same places
            pos, start = [], 0
            for i, ch in enumerate(code):
                if ch == ";":
                    pos.append((start, i))
                    start = i + 1
            pos.append((start, len(code)))
            for a, b in pos:
                m = STMT.match(code[a:b])
                if not m:
                    continue
                stmt = " ".join(raw[a:b].split())
                key = (prog, m.group(1).lower(), stmt)
                found[key] = found.get(key, 0) + 1
    return found


def read_tree():
    texts = {}
    for name in sorted(os.listdir(GPL)):
        if name.startswith("tool_") and os.path.isfile(os.path.join(GPL, name)):
            with open(os.path.join(GPL, name), encoding="latin-1") as f:
                texts[name] = f.read()
    return texts


def judge(texts, quiet=False):
    """The rows; returns the names of the rows that failed."""
    global passed, failed
    p0, f0 = passed, failed
    bad = []
    found = sites_of(texts)

    def r(name, ok, detail=""):
        if quiet:
            if not ok:
                bad.append(name.split()[0])
            return ok
        if not row(name, ok, detail):
            bad.append(name.split()[0])
        return ok

    r("T0 the pages were read and have sites (not a run on nothing): %d programs, %d sites" % (len(texts), sum(found.values())),
      len(texts) >= 20 and sum(found.values()) >= 30, "%d programs, %d sites" % (len(texts), sum(found.values())))
    r("T1 every reason on the list is one of the seven", all(v in REASONS for v in SITES.values()), repr(sorted(set(SITES.values()) - REASONS)))
    new = sorted(k for k in found if k not in SITES)
    r("T2 no write, delete or execute in a tool_* page that is not on the list (read its guard, then list it with the reason)", not new,
      "; ".join("%s: %s" % (k[0], k[2]) for k in new))
    gone = sorted(k for k in SITES if k not in found)
    r("T3 every listed site is still in its page (a stale entry is taken off the list)", not gone, "; ".join("%s: %s" % (k[0], k[2]) for k in gone))
    wrong = sorted("%s: %s (%d, listed %d)" % (k[0], k[2], n, COUNTS.get(k, 1)) for k, n in found.items() if k in SITES and n != COUNTS.get(k, 1))
    r("T4 a statement in a page more than once is listed with that number", not wrong, "; ".join(wrong))
    lab = [k for k in found if re.match(r"^(delete|write)\.", k[2], re.I)]
    r("T5 control: a label such as delete.reached: is not taken for a statement", not lab, repr(lab))
    if quiet:
        passed, failed = p0, f0
    return bad


MUTANTS = [
    ("a new execute in tool_gates", "tool_gates", lambda s: s.replace("\nend\n", "\n   execute 'sh rm -rf x'\nend\n", 1), "T2"),
    ("a write to a user's file in tool_voc", "tool_voc", lambda s: s.replace("\nend\n", "\n   write rec on vf, vid\nend\n", 1), "T2"),
    ("a listed site taken out (tool_accounts' execute)", "tool_accounts", lambda s: s.replace("   execute sent\n", "   null\n", 1), "T3"),
    ("a listed site changed (tool_remote's sentence)", "tool_remote", lambda s: s.replace("   execute sent\n", "   execute sent trapping aborts\n", 1), "T2"),
    ("a second copy of a listed statement", "tool_files", lambda s: s.replace("   execute sent\n", "   execute sent\n   execute sent\n", 1), "T4"),
    ("a site behind ; on one line", "tool_voc", lambda s: s.replace("\nend\n", "\n   x = 1 ; delete vf, vid\nend\n", 1), "T2"),
]
CONTROLS = [
    ("an execute in a comment", "tool_gates", lambda s: s.replace("\nend\n", "\n* execute 'sh rm -rf x'\nend\n", 1)),
    ("an execute inside a string", "tool_gates", lambda s: s.replace("\nend\n", "\n   msg = 'execute sent'\nend\n", 1)),
    ("an execute after ;*", "tool_gates", lambda s: s.replace("\nend\n", "\n   x = 1    ;* execute sent\nend\n", 1)),
]


def selftest():
    texts = read_tree()
    missed = 0
    for name, prog, fn, want in MUTANTS:
        t = dict(texts)
        t[prog] = fn(texts[prog])
        if t[prog] == texts[prog]:
            print("  [FAIL] selftest: %s - the mutation did not apply" % name)
            missed += 1
            continue
        bad = judge(t, quiet=True)
        ok = want in bad
        print("  [%s] selftest: %s is caught by %s (failed: %s)" % ("pass" if ok else "MISS", name, want, ", ".join(bad) or "nothing"))
        missed += 0 if ok else 1
    for name, prog, fn in CONTROLS:
        t = dict(texts)
        t[prog] = fn(texts[prog])
        bad = judge(t, quiet=True)
        ok = not bad and t[prog] != texts[prog]
        print("  [%s] control: %s changes no verdict (failed: %s)" % ("pass" if ok else "MISS", name, ", ".join(bad) or "nothing"))
        missed += 0 if ok else 1
    print("selftest: %d mutants and %d controls, %d missed" % (len(MUTANTS), len(CONTROLS), missed))
    return 1 if missed else 0


def main():
    print("test-toolsites-units: the write, delete and execute sites of %s/tool_*" % os.path.normpath(GPL))
    if "--selftest" in sys.argv:
        return selftest()
    judge(read_tree())
    print("test-toolsites-units: %d passed, %d failed" % (passed, failed))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
