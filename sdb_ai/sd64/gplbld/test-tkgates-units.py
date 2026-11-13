#!/usr/bin/env python3
"""test-tkgates-units.py - the toolkit's gate table (`gpl.bp/tk_gate_info`) held against what the rest of the tree says about the same gates (S.75, TK-0.2).  Free: no install, no sudo, no sd.

    python sdb_ai/sd64/gplbld/test-tkgates-units.py [--selftest]
    (13 Nov 26 Windows port - from Linux b1d496df, RELEASE_1.1 254: "the installer" is gplbld/sd.iss, which creates the Windows groups; message ids
    are Linux's + 1005; the text below is Linux's.)

The table is the one place the gate screens, their help and the confirm box read.  This check is what keeps it true: every row is held against `modifya` (the on and off words, in the
word list modify.account validates, and the conflict slot each word has there), `syscom/keys.h` (the register field), `gpl.bp/int$keys.h` (the kernel key) and the installer (the
Linux group), and the other way round: every gate word `modifya` knows is in a row.  ADDING A GATE IS ONE ROW IN `tk_gate_info`, AND THIS STAYS RED UNTIL THE VERB, THE FIELD AND THE KEY AGREE.

NOT HELD HERE (said so that it is not mistaken for held): the docs page of each gate (the Docs repository is a separate checkout), createa's own words, and whether a gate refuses anybody,
which is `sandbox-gates.py`'s and a witness row's work.  IT READS SOURCE AS TEXT AND RUNS NOTHING.

--selftest runs the checks on the real files and then on a copy with one deliberate fault at a time: each must make a check fail.
"""

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SDSYS = os.path.normpath(os.path.join(HERE, "..", "sdsys"))
ROOT = os.path.normpath(os.path.join(HERE, "..", "..", ".."))
FILES = {
    "info": os.path.join(SDSYS, "gpl.bp", "tk_gate_info"),
    "tkh": os.path.join(SDSYS, "gpl.bp", "tk.h"),
    "modifya": os.path.join(SDSYS, "gpl.bp", "modifya"),
    "keys": os.path.join(SDSYS, "syscom", "keys.h"),
    "ikeys": os.path.join(SDSYS, "gpl.bp", "int$keys.h"),
    "installer": os.path.join(HERE, "sd.iss"),      # 13 Nov 26 Windows port (RELEASE_1.1 254): the installer that creates the Windows groups
    "gates": os.path.join(SDSYS, "gpl.bp", "tk_gates"),
}
FIELDS = ["id", "title", "on", "off", "kind", "field", "group", "key", "when", "default", "slot", "allows", "still", "beyond", "status"]
# 7 Nov 26 (S.166): START-MENU and START-TERMINAL are the home gate's words now; START-DEFAULT (back to the system's default) is still not a gate word.
NOT_GATE_WORDS = {"BOTH", "SUSPENDED", "UNSUSPENDED", "START-DEFAULT", "PINS-ON", "PINS-OFF", "SDSYS-ON", "SDSYS-OFF",
                  "RECOVERY-ON", "RECOVERY-OFF"}      # 28 Oct 26 (S.88 plan 2.9, D2): the editors' recovery copy, ACC$RECOVERY - a convenience the administrator switches, not a wall, and not yet a row of the gate matrix (a follow-up); 26 Oct 26 (F6): SDSYS-ON / SDSYS-OFF are the sdsys user's membership of the account's group, state in /etc/group, no register field and no row of the gate matrix; words of modify.account that are not one gate's on or off word (22 Oct 26: the three START words are one three-state setting, ACC$START, and PINS-ON / PINS-OFF the permission to add one's own programs to the home screen, ACC$PINS; both are managed on the menu management page, tool.menus, not on tool.gates)


def load():
    raw = {}
    for k, p in FILES.items():
        if not os.path.isfile(p):
            raise FileNotFoundError(p)
        with open(p, encoding="latin-1") as f:
            raw[k] = f.read()
    return raw


def rows_of(info):
    return [r.split("|") for r in re.findall(r'rows<-1> = "([^"]*)"', info)]


def checks(raw):
    out = []

    def add(i, what, ok, detail=""):
        out.append((i, what, bool(ok), detail))

    rows = rows_of(raw["info"])
    add("G0", "NULL CASE: the table was found and holds rows (a check on nothing would pass)", len(rows) >= 10 and len(raw["modifya"]) > 1000, "%d rows" % len(rows))
    add("G1", "every row has the %d fields, ids are unique and lower case, the status is built or planned, default is off or on, beyond is 0 or 1" % len(FIELDS),
        all(len(r) == len(FIELDS) for r in rows) and len({r[0] for r in rows}) == len(rows) and all(re.fullmatch(r"[a-z-]+", r[0]) for r in rows)
        and all(r[14] in ("built", "planned") and r[9] in ("off", "on") and r[13] in ("0", "1") for r in rows if len(r) == len(FIELDS)),
        [r[0] for r in rows if len(r) != len(FIELDS)])
    built = [r for r in rows if len(r) == len(FIELDS) and r[14] == "built"]
    planned = [r for r in rows if len(r) == len(FIELDS) and r[14] == "planned"]
    add("G2", "a built gate has both words, a kind, a slot and two sentences; a planned gate has no word, no field, no group and no key (it shows as not yet built)",
        all(r[2] and r[3] and r[4] in ("register", "group", "start") and r[10] and r[11] and r[12] for r in built) and all(not (r[2] or r[3] or r[5] or r[6] or r[7]) for r in planned),
        [r[0] for r in built if not (r[2] and r[3] and r[10])])

    hdr = re.search(r"^\* id\|(\S+)$", raw["info"], re.M)
    add("G3", "the header comment of the rows names the fifteen fields in the order of FIELDS, and tk.h defines TK.G.<name> as 1 to 15 in that order",
        hdr is not None and ("id|" + hdr.group(1)).split("|") == FIELDS
        and [int(m.group(2)) for m in re.finditer(r"^\$define TK\.G\.(\w+)\s+(\d+)", raw["tkh"], re.M)] == list(range(1, 16))
        and [m.group(1).lower() for m in re.finditer(r"^\$define TK\.G\.(\w+)\s+(\d+)", raw["tkh"], re.M)] == FIELDS, "")

    wa = re.search(r"word\.arr = convert\(',', @fm, '([^']*)'\)", raw["modifya"])
    sa = re.search(r"slot\.arr = convert\(',', @fm, '([^']*)'\)", raw["modifya"])
    words = wa.group(1).split(",") if wa else []
    slots = sa.group(1).split(",") if sa else []
    slot_of = dict(zip(words, slots))
    add("G4", "modifya has a word list and a slot list of one length (the table cannot be held against a half)", bool(words) and len(words) == len(slots), "%d words, %d slots" % (len(words), len(slots)))

    mine = set()
    for r in built:
        mine |= {r[2].upper(), r[3].upper()}
    add("G5", "every on and off word of the table is a word modify.account validates, and it has the slot the row says (two words of one slot refuse each other, 12796)",
        all(r[2].upper() in slot_of and r[3].upper() in slot_of and slot_of[r[2].upper()] == r[10] and slot_of[r[3].upper()] == r[10] for r in built),
        [r[0] for r in built if not (r[2].upper() in slot_of and r[3].upper() in slot_of and slot_of.get(r[2].upper()) == r[10] and slot_of.get(r[3].upper()) == r[10])])
    add("G6", "the other way round: every word modify.account validates is a gate's on or off word, or one of the eight that are not (both, suspended, unsuspended, the three start words and the two pins words)",
        bool(words) and set(words) - mine - NOT_GATE_WORDS == set(), sorted(set(words) - mine - NOT_GATE_WORDS))
    order = [w for w in words if w in mine]
    tbl = [r[2].upper() for r in built]
    pos = [order.index(w) for w in tbl if w in order]
    add("G7", "the table lists the built gates in the order modify.account carries its words out (the screens show them in that order)", pos == sorted(pos) and len(pos) == len(built), "")

    keys_defs = dict(re.findall(r"\$define (ACC\$[A-Z.]+)\s+(\d+)", raw["keys"]))
    ik_defs = dict(re.findall(r"\$define (K\$[A-Z.]+)\s+(\d+)", raw["ikeys"]))
    reg = [r for r in built if r[4] == "register"]
    add("G8", "a register gate names an ACC$ field defined in keys.h and a K$ key defined in int$keys.h, and no two gates share either",
        all(r[5] in keys_defs and r[7] in ik_defs for r in reg) and len({keys_defs.get(r[5]) for r in reg}) == len(reg) and len({ik_defs.get(r[7]) for r in reg}) == len(reg),
        [r[0] for r in reg if not (r[5] in keys_defs and r[7] in ik_defs)])
    grp = [r for r in built if r[4] == "group"]
    gcreated = set(re.findall(r"gate_grp (\w+) ", raw["installer"]))
    add("G9", "a group gate names a Linux group that modifya puts the person in or out of, and that the installer creates or opens (sdfilesadmin is named in modifya; the installer's open-gates list is its own)",
        all(r[6] and r[6] in raw["modifya"] and r[5] == "" and r[7] == "" for r in grp) and all(r[6] in raw["installer"] for r in grp), [r[0] for r in grp if r[6] not in raw["installer"]])
    add("G10", "a gate that is on by delivery is exactly shared-read (keys.h: blank means yes for field 13 and for no other yes/no gate) and home (the installer's question's default)",
        {r[0] for r in rows if r[9] == "on"} == {"shared-read", "home"} and re.search(r"FIELD 13 IS THE ONE GATE WHOSE BLANK MEANS YES", raw["keys"]) is not None, [r[0] for r in rows if r[9] == "on"])
    st = [r for r in built if r[4] == "start"]
    keys_defs_all = dict(re.findall(r"\$define (ACC\$[A-Z.]+)\s+(\d+)", raw["keys"]))
    add("G14", "S.166: the one 'start' gate is home: its field is ACC$START (defined in keys.h), it has no group and no kernel key, its words are start-menu / start-terminal in slot ST, "
        "and $tk_gates reads it through $tk_startof",
        [r[0] for r in st] == ["home"] and st[0][5] == "ACC$START" and "ACC$START" in keys_defs_all and st[0][6] == "" and st[0][7] == ""
        and (st[0][2], st[0][3], st[0][10]) == ("start-menu", "start-terminal", "ST")
        and "case gi<TK.G.KIND> = 'start'" in raw["gates"] and "call $tk_startof(rec<ACC$START>, state)" in raw["gates"], [r[0] for r in st])
    add("G11", "a gate that reaches beyond SD is marked as one wherever the operating system, the network or another server is reached: sh os sd net ssh api files files-write files-admin ai sockets",
        {r[0] for r in rows if r[13] == "1"} == {"sh", "os", "sd", "net", "ssh", "api", "files", "files-write", "files-admin", "ai", "sockets"}, sorted(      # 13 Nov 26 Windows: the ai row is in with RELEASE_1.1 246, as Linux
r[0] for r in rows if r[13] == "1"))
    add("G12", "no sentence is empty, holds an escape or ends in a full stop (the screens add their own punctuation), and none starts with a capital (they continue 'on allows ...')",
        all(r[11] and r[12] and not r[11].endswith(".") and not r[12].endswith(".") and r[11][0].islower() and r[12][0].islower() for r in rows), "")
    pairs = re.findall(r"case id = '([a-z-]+)'\s*\n\s*raw = rec<(ACC\$[A-Z.]+)>", raw["gates"])
    got = dict(pairs)
    want = {r[0]: r[5] for r in reg}
    add("G13", "$tk_gates reads, for each register gate, the register field the table names for it (one case each, none extra): %d gates" % len(want),
        len(pairs) == len(got) and got == want and "case 1\n                  raw = 'no'" in raw["gates"], {k: (got.get(k), want.get(k)) for k in set(got) | set(want) if got.get(k) != want.get(k)})
    return out


def run(raw, quiet=False):
    rows = checks(raw)
    bad = [r for r in rows if not r[2]]
    if not quiet:
        for i, what, ok, detail in rows:
            print("  [%s] %s %s%s" % ("PASS" if ok else "FAIL", i, what, ("   <- " + str(detail)) if (detail and not ok) else ""))
    return rows, bad


MUT = [
    ("info", "a row is dropped (the dict gate)", '   rows<-1> = "dict|', '   rows<-0> = "dict|'),
    ("info", "an on word is spelled differently", "|sh-on|sh-off|", "|shell-on|sh-off|"),
    ("info", "a slot is wrong", "|off|BP|save changes", "|off|SH|save changes"),
    ("info", "a register field that keys.h does not define", "ACC$NET|", "ACC$NETWORK|"),
    ("info", "a kernel key that int$keys.h does not define", "K$SHARED.WRITE|", "K$SHARED.WRITER|"),
    ("info", "a row lacks a field", "|sdssh||next login|", "|sdssh|next login|"),
    ("info", "a group that nothing creates", "|sdfilesadmin||", "|sdnothing||"),
    ("info", "a second gate is on by delivery", "|next account entry|off|SD|", "|next account entry|on|SD|"),
    ("info", "a gate is not marked as reaching beyond SD", "inside its own account directory|1|built", "inside its own account directory|0|built"),
    ("info", "the gates are in another order", '   rows<-1> = "ssh|', '   rows<-1> = "files-admin|Files admin|files-admin-on|files-admin-off|group||sdfilesadmin||next login|off|FA|x|y|1|built"\n   rows<-1> = "ssh|'),
    ("info", "a sentence starts with a capital", "|sign in at the machine's own keyboard|", "|Sign in at the machine's own keyboard|"),
    ("gates", "a gate is read from another gate's field", "raw = rec<ACC$SH>", "raw = rec<ACC$BP.EDIT>"),
    ("gates", "a gate has no case", "               case id = 'dict'\n                  raw = rec<ACC$DICT.EDIT>\n", ""),
    ("gates", "a case for a gate that is not in the table", "               case id = 'net'\n", "               case id = 'nett'\n"),
    ("modifya", "a word modifya knows that no row holds", "NET-ON,NET-OFF,", "NET-ON,NET-OFF,PRINT-ON,PRINT-OFF,"),
    ("tkh", "a TK.G number is out of order", "$define TK.G.TITLE     2", "$define TK.G.TITLE     3"),
]


def selftest():
    try:
        raw = load()
    except FileNotFoundError as e:
        print("CANNOT RUN: %s is not there" % e)
        return 2
    rows, bad = run(raw)
    if bad:
        print("selftest: the real files already fail %d check(s)" % len(bad))
        return 1
    killed, missed = 0, []
    for fname, what, old, new in MUT:
        if old == new:
            continue                                  # a mutant that changes nothing is not counted
        if raw[fname].count(old) != 1:
            print("  [CANNOT] %s: the text to change is found %d times in %s, not once" % (what, raw[fname].count(old), fname))
            return 2
        m = dict(raw)
        m[fname] = raw[fname].replace(old, new)
        rows_m, bad_m = run(m, quiet=True)
        if bad_m:
            killed += 1
            print("  [killed] %s  <- %s" % (what, ", ".join(r[0] for r in bad_m)))
        else:
            missed.append(what)
            print("  [MISSED] %s" % what)
    n = sum(1 for m in MUT if m[2] != m[3])
    print("selftest: %d mutants, %d killed, %d missed" % (n, killed, len(missed)))
    return 0 if not missed else 1


def main():
    if "--selftest" in sys.argv:
        return selftest()
    try:
        raw = load()
    except FileNotFoundError as e:
        print("CANNOT RUN: %s is not there" % e)
        return 2
    rows, bad = run(raw)
    print("test-tkgates-units: %d passed, %d failed" % (len(rows) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
