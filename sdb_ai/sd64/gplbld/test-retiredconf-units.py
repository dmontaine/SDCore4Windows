#!/usr/bin/env python3
# test-retiredconf-units.py - the installer's RemoveRetiredConf list (sd.iss) against config.c.
#
# 8 Nov 26 Windows port - RELEASE_1.1 197, from Linux 843344ba (S.87 batch 15) and its
# test-install-retiredconf.sh.  config.c refuses an unrecognised sd.conf parameter and SD then
# does not start, so the installer removes a retired parameter's line from a kept sd.conf at
# ssInstall.  This holds the three things that make that work:
#
#   R1  every name in RetiredConfNames is one config.c no longer parses (a live name in the
#       list would be deleted from every upgraded sd.conf);
#   R2  the list holds every parameter S.87 retired (one left out stops SD on an upgrade);
#   R3  RemoveRetiredConf is called when CurStep = ssInstall, before any [Run] entry;
#   R4  IsRetiredConfLine matches only NAME= at the start of a line (no key with a space).
#
# --selftest breaks a copy of the text in memory four ways; each mutant must turn its row red.
# Free: no SD, no install.  Exit 0 all rows passed, 1 a row failed, 2 could not run.

import os, re, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ISS = os.path.join(HERE, "sd.iss")
CONFIG_C = os.path.join(HERE, "..", "gplsrc", "config.c")

# The parameters S.87 retired (Linux 843344ba and cf405b48).  A later retirement adds its name here and in sd.iss.
RETIRED = {"INVCASE", "CODEPAGE", "EXCLREM", "RINGWAIT", "TXCHAR", "APILOGIN", "CREATUSR",
           "JNLDIR", "JNLMODE", "GDI", "FIXUSERS", "PORTMAP"}


def read(p):
    with open(p, encoding="latin-1") as f:
        return f.read()


def listed(iss):
    m = re.search(r"function RetiredConfNames: String;\s*begin\s*Result := '([^']*)';", iss)
    return None if m is None else m.group(1).split()


def parsed_by_config(cfg):
    # every NAME the read loop accepts: sscanf(rec, "NAME=..." or strncmp(rec, "NAME=", n)
    code = re.sub(r"/\*.*?\*/", "", cfg, flags=re.S)
    return set(re.findall(r'(?:sscanf|strncmp)\(rec, "([A-Z0-9]+)=', code))


def checks(iss, cfg):
    rows = []
    names = listed(iss)
    rows.append(("R0 sd.iss defines RetiredConfNames", names is not None and len(names) > 0, "%r" % names))
    names = names or []
    live = parsed_by_config(cfg)
    rows.append(("R0 config.c's read loop was found (it parses NUMUSERS)", "NUMUSERS" in live, "%d names" % len(live)))
    clash = sorted(set(names) & live)
    rows.append(("R1 no listed name is still parsed by config.c", not clash, "still parsed: %s" % clash))
    missing = sorted(RETIRED - set(names))
    rows.append(("R2 the list holds every retired parameter", not missing, "missing: %s" % missing))
    proc = re.search(r"procedure CurStepChanged\(CurStep: TSetupStep\);.*?\bbegin\b(.*?)if CurStep = ssPostInstall then", iss, re.S)
    rows.append(("R3 RemoveRetiredConf runs when CurStep = ssInstall, ahead of ssPostInstall",
                 proc is not None and re.search(r"if CurStep = ssInstall then\s*RemoveRetiredConf;", proc.group(1)) is not None, ""))
    fn = re.search(r"function IsRetiredConfLine\(L: String\): Boolean;(.*?)\nend;", iss, re.S)
    body = fn.group(1) if fn else ""
    rows.append(("R4 IsRetiredConfLine takes the key up to '=' and refuses one with a space",
                 "K := Copy(L, 1, Eq - 1);" in body and "if Pos(' ', K) > 0 then" in body, ""))
    return rows


def report(rows):
    bad = 0
    for name, ok, detail in rows:
        print("  [%s] %s%s" % ("PASS" if ok else "FAIL", name, "" if ok else "  -> " + detail))
        bad += 0 if ok else 1
    return bad


def selftest(iss, cfg):
    base = checks(iss, cfg)
    if any(not ok for _, ok, _ in base):
        print("selftest: the real tree already fails")
        return 1
    mutants = [
        ("a live parameter (NUMUSERS) added to the list", iss.replace("FIXUSERS PORTMAP'", "FIXUSERS PORTMAP NUMUSERS'"), cfg, "R1"),
        ("GDI left out of the list", iss.replace(" GDI ", " "), cfg, "R2"),
        ("the ssInstall call removed", iss.replace("if CurStep = ssInstall then\n    RemoveRetiredConf;", ""), cfg, "R3"),
        ("the space refusal removed", iss.replace("if Pos(' ', K) > 0 then", "if False then"), cfg, "R4"),
    ]
    fails = 0
    for label, mi, mc, want in mutants:
        if mi == iss and mc == cfg:
            print("  [FAIL] selftest: %s (the mutation changed nothing)" % label)
            fails += 1
            continue
        got = [n.split()[0] for n, ok, _ in checks(mi, mc) if not ok]
        caught = want in got
        print("  [%s] selftest: %s%s" % ("PASS" if caught else "FAIL", label, "" if caught else " (NOT CAUGHT; failed: %s)" % got))
        fails += 0 if caught else 1
    print("test-retiredconf-units selftest: %d of %d mutants caught" % (len(mutants) - fails, len(mutants)))
    return 0 if fails == 0 else 1


def main():
    for p in (ISS, CONFIG_C):
        if not os.path.exists(p):
            print("COULD NOT RUN: no %s" % p)
            return 2
    iss, cfg = read(ISS), read(CONFIG_C)
    print("test-retiredconf-units: %s" % os.path.normpath(ISS))
    print("                        %s" % os.path.normpath(CONFIG_C))
    if "--selftest" in sys.argv:
        return selftest(iss, cfg)
    rows = checks(iss, cfg)
    bad = report(rows)
    print("\ntest-retiredconf-units: %d passed, %d failed" % (len(rows) - bad, bad))
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
