#!/usr/bin/env python3
"""test-createaudit-units.py - the create.account audit line names the gates it granted (owner, 19 Oct 2026), read off createa as text.

  python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-createaudit-units.py
  python3 .../test-createaudit-units.py --selftest

No sudo, no install, no sd.  Exit 0 every check passed, 1 a check failed, 2 it could not run.

THE RULE.  modify.account audits each word it applies; create.account USER name files-on files-write-on made the same grants and left one line that
named none of them (SDNet audit K8f).  The line is now  create.account account=<a> type=<t> gates=<words>  with the words in lower case, in the order of
the usage line, and "none" when there are none; it is written only after !create_account reported no error.  Every word the parser (more.args)
accepts that grants or withdraws an access must be named by the builder, so a gate word added later fails here until the audit line learns it.

***IT READS createa AS TEXT.***  CREATE.ACCOUNT makes Linux users, so no sandbox suite runs it: that the line really reads
"... gates=sh-on,os-on" is for a real install's audit file (verify-auditwords.py reads it, as sdsys).  --selftest requires each mutation to be caught
and to match its text exactly once.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CA = os.path.join(HERE, os.pardir, "sdsys", "gpl.bp", "createa")

# (setting, word) in the order of the usage line
PAIRS = [("CA$ROUTE.SSH", "ssh"), ("CA$ROUTE.API", "api"), ("CA$OS.SH", "sh-on"), ("CA$OS.EXECUTE", "os-on"), ("CA$VOC.EDIT", "voc-on"),
         ("CA$BP.EDIT", "bp-on"), ("CA$DICT.EDIT", "dict-on"), ("CA$NET", "net-on"), ("CA$FILES", "files-on"), ("CA$FILESWRITE", "files-write-on"), ("CA$FILESADMIN", "files-admin-on"), ("CA$SHARED.READ.OFF", "shared-read-off"), ("CA$SHARED.WRITE", "shared-write-on")]
# 25 Oct 26 Windows port: the list is Linux's, files-admin-on (S.73 item 3) included; the account name is upcased here
# (this port's own case) and the create call passes the type upcased.
AUDIT = "void kernel(K$AUDIT, 'create.account account=' : upcase(acc.name) : ' type=' : downcase(acc.type) : ' gates=' : gates)"
CREATE_CALL = "call !create_account(upcase(acc.type), acc.name, settings, err)"


def strip(src):
    return "\n".join(re.sub(r"\s*;\*.*$", "", ln) for ln in src.split("\n") if not ln.lstrip().startswith("*"))


def checks(src):
    c = strip(src)
    rows = []

    def ck(name, ok, detail=""):
        rows.append((name, bool(ok), detail))

    a = c.find(AUDIT)
    cr = c.find(CREATE_CALL)
    refuse = c.find("stop sysmsg(err<1,1>", cr if cr >= 0 else 0)
    ck("A1 the audit line is written once, with gates= after type=", c.count(AUDIT) == 1 and c.count("K$AUDIT") == 1, "audit sites: %d" % c.count("K$AUDIT"))
    ck("A2 ...and only after !create_account reported no error", 0 <= cr < refuse < a, "create %s refuse %s audit %s" % (cr, refuse, a))
    built = re.findall(r"if settings<(CA\$[A-Z.]+)> = 1 then gates<-1> = '([a-z-]+)'", c)
    ck("A3 gates is built from exactly these settings, one word each, in the order of the usage line", built == PAIRS, "%s" % built)
    ck("A3b ...and before the audit line, from an empty start", 0 <= c.find("   gates = ''\n") < c.find("gates<-1>") < a)
    ck("A4 an empty list says none, a list is written comma separated", "if gates = '' then gates = 'none' else gates = convert(@fm, ',', gates)" in c
       and c.find("gates = 'none'") < a)
    more = c[c.find("\nmore.args:\n"):]
    parser_words = set(re.findall(r"upcase\(token\) = '([A-Z-]+)'", more))
    named = {w.upper() for _, w in PAIRS}
    grants = parser_words - {"NONE", "BOTH", "ATTACH", "ADMINISTRATOR", "PROGRAMMER"}   # the last two are refused tier words on this port
    ck("A5 every access word more.args accepts is named by the builder (both is ssh and api; none is nothing; attach grants nothing)",
       parser_words and grants <= named and named <= grants | {"SSH", "API"}, "parser-only %s, audit-only %s" % (sorted(grants - named), sorted(named - grants)))
    return rows


def load():
    with open(CA, encoding="latin-1") as f:
        return f.read()


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        bad += 0 if ok else 1
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "   <- " + detail))
    return bad


MUTANTS = [
    ("the audit line loses gates=", " : ' gates=' : gates)", ")"),
    ("the audit line is written before create_account", CREATE_CALL,
     "void kernel(K$AUDIT, 'create.account account=' : upcase(acc.name) : ' type=' : downcase(acc.type) : ' gates=' : gates)\n   " + CREATE_CALL),
    ("shared-write-on is not named", "   if settings<CA$SHARED.WRITE> = 1 then gates<-1> = 'shared-write-on'\n", ""),
    ("sh and os are swapped", "settings<CA$OS.SH> = 1 then gates<-1> = 'sh-on'", "settings<CA$OS.EXECUTE> = 1 then gates<-1> = 'sh-on'"),
    ("voc-on is named bp-on", "settings<CA$VOC.EDIT> = 1 then gates<-1> = 'voc-on'", "settings<CA$VOC.EDIT> = 1 then gates<-1> = 'bp-on'"),
    ("an empty list is not none", "if gates = '' then gates = 'none' else", "if gates = '' then gates = '' else"),
    ("the words are not separated", "gates = convert(@fm, ',', gates)", "gates = convert(@fm, '', gates)"),
    ("a new gate word is accepted and not audited", "         case upcase(token) = 'DICT-ON'\n", "         case upcase(token) = 'DICT-OK'\n            settings<CA$NET> = 1\n         case upcase(token) = 'DICT-ON'\n"),
]


def selftest():
    src = load()
    if any(not ok for _, ok, _ in checks(src)):
        print("REFUSING - the unmutated source already fails", file=sys.stderr)
        return 2
    holes = 0
    print("--- self-test: each mutation must be CAUGHT and match its text once ---")
    for name, old, new in MUTANTS:
        if src.count(old) != 1:
            print("  [FAIL] %s: the text matches %d times, not once" % (name, src.count(old)))
            holes += 1
            continue
        caught = [n for n, ok, _ in checks(src.replace(old, new)) if not ok]
        print("  [%s] %s%s" % ("pass" if caught else "FAIL", name, ": caught by " + ", ".join(caught[:3]) if caught else ": NOT CAUGHT"))
        holes += 0 if caught else 1
    print("\n%d of %d mutants caught, %d missed" % (len(MUTANTS) - holes, len(MUTANTS), holes))
    return 1 if holes else 0


def main():
    if not os.path.isfile(CA):
        print("test-createaudit-units: CANNOT RUN - %s is not readable" % CA, file=sys.stderr)
        return 2
    if "--selftest" in sys.argv[1:]:
        return selftest()
    rows = checks(load())
    bad = report(rows)
    print("\ntest-createaudit-units: %d checks, %d failed" % (len(rows), bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
