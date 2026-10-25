#!/usr/bin/env python3
"""test-toolmygates-units.py - the account holder's gate page, TOOL.GATES in every account's VOC (`gpl.bp/tool_mygates`), as invariants read off the source (S.75 A2, the user audience).
Free: no install, no sudo, no sd.

    python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-toolmygates-units.py [--selftest]

WHAT THIS IS, AND WHAT IT IS NOT.  It reads the page's BASIC as text, with comments removed.  ***IT RUNS NOTHING, SO IT CANNOT SAY WHAT A SESSION SEES***: that is
`sandbox-tool-mygates.py` (ordinary sessions on a private SD, the disk as the evidence).  What a text check is for: the properties that make the page SAFE FOR EVERYONE and TRUE - it asks for
no administrator, it can change nothing (no write, no command, no confirm box, no audit line, no register opened), every register gate comes from the kernel's own answer for that gate and
every route gate from the group of the person's login name - are mostly ABSENCE and a pairing, and an edit that breaks one still compiles.

--selftest breaks each invariant in the way an edit plausibly would and requires a check to notice; a mutant that nothing catches is a failure of the self-test.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
GPL = os.path.join(SDSYS, "gpl.bp")
FILES = {
    "page": os.path.join(GPL, "tool_mygates"),
    "info": os.path.join(GPL, "tk_gate_info"),
    "newvoc": os.path.join(SDSYS, "newvoc", "tool.gates"),
    "tmpl": os.path.join(SDSYS, "voc_template", "tool.gates"),
    "help": os.path.join(SDSYS, "helptext", "tool.gates.mine"),
}


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


def checks(raw):
    rows = []

    def ck(i, what, ok, detail=""):
        rows.append((i, what, bool(ok), detail))

    pg = strip_bas(raw["page"])
    info_rows = [r.split("|") for r in re.findall(r'rows<-1> = "([^"]*)"', raw["info"])]
    built_reg = [r for r in info_rows if len(r) == 15 and r[14] == "built" and r[4] == "register"]
    built_grp = [r for r in info_rows if len(r) == 15 and r[14] == "built" and r[4] == "group"]

    ck("MG0", "NULL CASE: the page, the gate table and both VOC records were found and are not empty (a check on nothing would pass)", len(pg) > 5000 and len(info_rows) >= 12 and raw["newvoc"].strip() != "" and raw["tmpl"].strip() != "" and len(raw["help"]) > 200,
       "%d %d" % (len(pg), len(info_rows)))
    ck("MG1", "the page is an internal program catalogued as $tool_mygates; EVERY account's VOC (newvoc) runs it under the verb tool.gates, and SDSYS's VOC (voc_template) runs the administrator's matrix, $tool_gates, under the same verb",
       re.search(r"^\$internal\s*\nprogram \$tool_mygates\s*\n\$catalog \$tool_mygates\b", pg, re.M) is not None and raw["newvoc"].split("\n")[:3][0].startswith("Verb - ") and raw["newvoc"].split("\n")[1:3] == ["CA", "$tool_mygates"]
       and raw["tmpl"].split("\n")[:3] == ["V", "CA", "$tool_gates"], repr((raw["newvoc"][:60], raw["tmpl"][:30])))
    ck("MG2", "it asks the base for a USER app (no audience word) and shows the base's error and stops when it refuses (a window under 140 by 43)",
       "call $tk_open('tool.gates', '', ctx, err)" in pg and "'admin'" not in pg and re.search(r"call \$tk_open\('tool\.gates', '', ctx, err\)\s*\n\s*if err # '' then\s*\n\s*display err\s*\n\s*stop\s*\n\s*end", pg) is not None)
    ck("MG3", "THE PAGE CHANGES NOTHING: it has no write, delete, execute, perform or chain, runs no command ($tk_run, $tk_runx), opens no confirm box, writes no audit line and opens no file (not the register, not the group file)",
       not re.search(r"^\s*(?:execute|os\.execute|perform|chain|write[uv]?|delete[uv]?|matwrite|openpath|open|openseq|readu?|readv)\s", pg, re.M) and "$tk_run" not in pg and "$tk_confirm" not in pg and "K$AUDIT" not in pg and "$tk_runx" not in pg)
    used = set(re.findall(r"kernel\((K\$[A-Z.]+), -1\)", pg))
    want_keys = {"K$SH", "K$OS.EXEC", "K$SD.ACCOUNTS", "K$VOC.EDIT", "K$BP.EDIT", "K$DICT.EDIT", "K$NET", "K$SHARED.READ", "K$SHARED.WRITE"}
    ck("MG4", "every register gate is what the SESSION holds - the kernel's own answer for that gate, asked with -1 - and the page asks for exactly the nine and for nothing else of the kernel", used == want_keys and len(re.findall(r"kernel\(", pg)) == len(want_keys), repr(sorted(used ^ want_keys)))
    pairs = dict(re.findall(r"case gid = '([a-z-]+)'\s*\n\s*s = \(if kernel\((K\$[A-Z.]+), -1\)", pg))
    ok = len(built_reg) == len(pairs)
    for r in built_reg:
        ok = ok and pairs.get(r[0]) == r[7]
    ck("MG5", "each register gate of the table is read with the kernel key the TABLE names for it (sh K$SH, os K$OS.EXEC ...)", ok and len(built_reg) == 9, repr((pairs, [(r[0], r[7]) for r in built_reg])))
    ck("MG6", "each route gate is membership of its Linux group by the PERSON's login name (@logname), not by the account name, and the lookup is the system's own !is_grp_member",
       "s = (if is_grp_member(@logname, ggrp<k>) then 1 else 0)" in pg and "deffun is_grp_member(user,group) calling '!is_grp_member'" in pg and "case gkind<k> = 'group'" in pg and len(built_grp) == 5 and "is_grp_member(@who" not in pg)
    keys = re.findall(r"call \$tk_keys\('add', keys, '([^']+)', '[^']+', '([a-z]+)'", pg)
    ck("MG7", "the key table is help, refresh and quit and nothing else: no key to queue, run, drop or toggle anything", sorted(a for _k, a in keys) == ["help", "quit", "refresh"], repr(keys))
    ck("MG8", "the words the page gives for a gate are the table's own on and off words for THIS account (@who) and say that only the administrator changes it; a gate that reaches beyond SD says the administrator is asked for the name",
       "'The administrator withdraws it with: modify.account ' : @who : ' ' : goff<k>" in pg and "'The administrator gives it with: modify.account ' : @who : ' ' : gon<k>" in pg and "so the administrator is asked to type your account name" in pg
       and "Only the administrator can change a gate (modify.account).  Nothing on this page can." in pg)
    ck("MG9", "the edit gates are said to be read ONCE at sign-on, and the row of a gate that is only planned says there is nothing to switch",
       "The edit gates are read ONCE when you sign on" in pg and "is planned and not built yet: there is nothing to switch" in pg and "if gids<k> = 'voc' or gids<k> = 'bp' or gids<k> = 'dict' then" in pg)
    ck("MG10", "there is a [?], F1 and ? and a click show tool.gates.mine, whose record exists; the page calls $tk_help with its five arguments", pg.count("tool.gates.mine") == 2 and "call $tk_help('mark', 134, 2, 0, 0)" in pg
       and "call $tk_help('hit', mev, 134, 2, hit.m)" in pg and raw["help"].split("\n")[0].strip() != "" and all(len(re.split(r",(?![^()]*\))", m)) == 5 for m in re.findall(r"call \$tk_help\(([^\n]*)\)", pg)))
    n = len(info_rows)
    ck("MG11", "the page shows all the gates of the table on one screen: VIS (the rows on the screen) is at least the number of gates, the box and the text starts are where the draw routines put them",
       re.search(r"VIS = (\d+)", pg) is not None and int(re.search(r"VIS = (\d+)", pg).group(1)) >= n and "screen box at 1,1 size 138,21 title 'What this account may do'" in pg and "for r = 1 to VIS" in pg, "%d gates" % n)
    ck("MG12", "the page starts from the system's answers on every F5 (read.all is called again) and not from a copy it kept", "case nm = 'f5'\n         gosub read.all\n         gosub draw.all" in pg and "gst = ''" in pg)
    return rows


def sub(key, old, new):
    def f(raw):
        r = dict(raw)
        if old not in r[key]:
            raise KeyError("%s: %r is not in the file, so the mutant cannot be made" % (key, old[:60]))
        r[key] = r[key].replace(old, new, 1)
        return r
    return f


MUTANTS = [
    ("the verb in every account runs the administrator's matrix", "MG1", sub("newvoc", "$tool_mygates", "$tool_gates")),
    ("SDSYS's verb runs the holder's page", "MG1", sub("tmpl", "$tool_gates", "$tool_mygates")),
    ("the page asks for an administrator", "MG2", sub("page", "call $tk_open('tool.gates', '', ctx, err)", "call $tk_open('tool.gates', 'admin', ctx, err)")),
    ("the page writes a record", "MG3", sub("page", "   gst = ''\n   for k = 1 to NG\n      gid = gids<k>", "   gst = ''\n   write 'x' to nowhere, 'y'\n   for k = 1 to NG\n      gid = gids<k>")),
    ("the page writes an audit line", "MG3", sub("page", "   prompt ''\n", "   prompt ''\n   void kernel(K$AUDIT, 'tool start app=tool.gates')\n")),
    ("the page runs a command", "MG3", sub("page", "         msg = 'asked the system again'", "         execute 'modify.account x sh-on'\n         msg = 'asked the system again'")),
    ("sh is read from the OS key", "MG5", sub("page", "case gid = 'sh'\n            s = (if kernel(K$SH, -1) then 1 else 0)", "case gid = 'sh'\n            s = (if kernel(K$OS.EXEC, -1) then 1 else 0)")),
    ("a gate is asked with 0, not -1", "MG4", sub("page", "kernel(K$NET, -1)", "kernel(K$NET, 0)")),
    ("the net gate is not asked", "MG4", sub("page", "         case gid = 'net'\n            s = (if kernel(K$NET, -1) then 1 else 0)\n", "")),
    ("a route gate is asked of the account name", "MG6", sub("page", "is_grp_member(@logname, ggrp<k>)", "is_grp_member(@who, ggrp<k>)")),
    ("a key queues a change", "MG7", sub("page", "   call $tk_keys('add', keys, 'f5', 'refresh', 'refresh', '', 1)\n", "   call $tk_keys('add', keys, 'f5', 'refresh', 'refresh', '', 1)\n   call $tk_keys('add', keys, 'enter', 'queue', 'queue', '', 1)\n")),
    ("the page names the wrong account", "MG8", sub("page", "'The administrator gives it with: modify.account ' : @who", "'The administrator gives it with: modify.account ' : @logname")),
    ("the page says it can change a gate", "MG8", sub("page", "Only the administrator can change a gate (modify.account).  Nothing on this page can.", "You can change a gate here.")),
    ("the sign-on sentence is gone", "MG9", sub("page", "The edit gates are read ONCE when you sign on", "The edit gates are read when you ask")),
    ("the help call has too few arguments", "MG10", sub("page", "call $tk_help('box', 'tool.gates.mine', hm, 0, 0)\n         if hm # '' then msg = hm\n      case nm = 'f5'", "call $tk_help('box', 'tool.gates.mine', hm)\n         if hm # '' then msg = hm\n      case nm = 'f5'")),
    ("the page has no [?]", "MG10", sub("page", "   call $tk_help('mark', 134, 2, 0, 0)\n", "")),
    ("too few rows for the table", "MG11", sub("page", "VIS = 16 ", "VIS = 10 ")),
    ("F5 does not ask again", "MG12", sub("page", "case nm = 'f5'\n         gosub read.all\n         gosub draw.all", "case nm = 'f5'\n         gosub draw.all")),
]


def load():
    raw = {}
    for k, p in FILES.items():
        try:
            with open(p, encoding="latin-1") as f:
                raw[k] = f.read()
        except OSError:
            raw[k] = ""
    return raw


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
    print("test-toolmygates-units: tree %s" % os.path.dirname(GPL))
    if not raw["page"]:
        print("test-toolmygates-units: CANNOT RUN - %s is not there" % FILES["page"])
        return 2
    rows = checks(raw)
    bad = report(rows)
    print("\ntest-toolmygates-units: %d passed, %d failed" % (len(rows) - bad, bad))
    rc = 1 if bad else 0
    if "--selftest" in argv:
        rc = (selftest(raw) or rc)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
