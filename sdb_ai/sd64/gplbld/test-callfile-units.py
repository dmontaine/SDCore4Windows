#!/usr/bin/env python3
#
# test-callfile-units.py - the Pick style CALL "file name" (QM4 Fixes 208) read off the sources: that it can only ever reach a
# file the VOC names, and that CALL and CALLV share the one routine that decides.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/test-callfile-units.py [--selftest]
#
# No sudo, no install, no sd.  Exit 0 every check held, 1 one did not.  --selftest breaks a copy of the sources in five ways and
# expects each to be caught by exactly the check that owns it.  It cannot say that a call works or is refused: that is
# sandbox-callfile.py.
#
# START-HISTORY:
# 17 Oct 26 dm  Written with pick_style_runfile().  The owner's ruling was "VOC file names only" (no operating system path): a
#               later change that let a path through, or that handled the name in one of the two call opcodes and not the
#               other, would make nothing fail that the suite does not already try, so the shape is checked here too.
# END-HISTORY
#
# WHAT IT CHECKS
#   1. pick_style_runfile() takes the directory from get_voc_file_reference() and from nothing else (no dio_open, no fullpath).
#   2. ...refuses a path separator in either part and a catalogue prefix in the program part, before any lookup.
#   3. ...puts STATUS() back after the lookup.
#   4. op_call() and op_callv() both get the name to load from call_name_to_load(), and neither tests valid_call_name() itself.
#   5. the compiler offers the form only to a string with a space in it.

import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SD64 = os.path.dirname(HERE)
PATHS = {"op_jumps": os.path.join(SD64, "gplsrc", "op_jumps.c"), "bcomp": os.path.join(SD64, "sdsys", "gpl.bp", "bcomp")}

passed = failed = 0


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        print("  [PASS] " + name)
    else:
        failed += 1
        print("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def read(path):
    with open(path, encoding="latin-1") as f:
        return f.read()


def body(text, start_re):
    m = re.search(start_re, text)
    if not m:
        return ""
    e = re.search(r"(?m)^}\s*$", text[m.start():])
    return text[m.start():m.start() + e.end()] if e else text[m.start():]


def checks(src):
    res = []
    oj = src["op_jumps"]
    pk = body(oj, r"(?m)^Private bool pick_style_runfile\(")
    res.append(("1. the object directory comes from get_voc_file_reference() and nothing that opens a path",
                "get_voc_file_reference(" in pk and not re.search(r"\b(dio_open|fullpath|realpath|open|stat)\(", pk.replace("get_voc_file_reference(", "")),
                "pick_style_runfile: %s" % pk[:60].replace("\n", " ")))
    i_ds = pk.find("strchr(file, DS)")
    i_pre = pk.find('strchr("*$!_", prog[0])')
    i_voc = pk.find("get_voc_file_reference(")
    res.append(("2. a path separator in either part and a catalogue prefix are refused before the lookup",
                0 <= i_ds < i_voc and 0 <= i_pre < i_voc and "strchr(prog, DS)" in pk, "positions %d, %d, lookup %d" % (i_ds, i_pre, i_voc)))
    res.append(("3. STATUS() is saved before the lookup and put back after it",
                0 <= pk.find("saved_status = process.status") < i_voc < pk.find("process.status = saved_status"), "no save and restore around the lookup"))
    oc = body(oj, r"(?m)^void op_call\(\) \{")
    ov = body(oj, r"(?m)^void op_callv\(\) \{")
    res.append(("4. op_call() and op_callv() both ask call_name_to_load() and neither tests valid_call_name() itself",
                "call_name_to_load(" in oc and "call_name_to_load(" in ov and "valid_call_name(" not in oc and "valid_call_name(" not in ov,
                "op_call %s, op_callv %s" % ("call_name_to_load(" in oc, "call_name_to_load(" in ov)))
    bc = src["bcomp"]
    i = bc.find("else if look.ahead.token = TKN.STRING then")
    seg = bc[i:i + 900] if i >= 0 else ""
    res.append(("5. the compiler takes a string after CALL only when it has a space in it",
                i >= 0 and "if index(s, ' ', 1) = 0 then" in seg and "gosub emit.direct.call.reference" in seg, "bcomp st.call string branch: %s" % seg[:60].replace("\n", " ")))
    return res


def selftest(src):
    ok_all = True
    oj, bc = src["op_jumps"], src["bcomp"]
    muts = [
        ("an OS path allowed in the file part", "op_jumps", oj.replace("if ((strchr(file, DS) != NULL) || (strchr(prog, DS) != NULL))", "if (strchr(prog, DS) != NULL)", 1), "2."),
        ("the lookup replaced by a direct open", "op_jumps", oj.replace("found = get_voc_file_reference(voc_name, FALSE, path, NULL) && (path[0] != '\\0');",
                                                                       "found = (dio_open(voc_name, DIO_READ) != INVALID_FILE_HANDLE);", 1), "1."),
        ("STATUS() not put back", "op_jumps", oj.replace("process.status = saved_status;", "", 1), "3."),
        ("op_callv() testing the name itself again", "op_jumps", oj.replace("load_name = call_name_to_load(subr_descr, call_name, runfile);",
                                                                          "if (!valid_call_name(call_name)) k_illegal_call_name();\n      load_name = call_name;", 1), "4."),
        ("the compiler taking any string", "bcomp", bc.replace("if index(s, ' ', 1) = 0 then\n         err.msg = sysmsg(2883)", "if 0 then\n         err.msg = sysmsg(2883)", 1), "5."),
    ]
    for label, key, text, want in muts:
        if text == src[key]:
            row("selftest: %s" % label, False, "the mutation changed nothing")
            ok_all = False
            continue
        s2 = dict(src)
        s2[key] = text
        fails = [name.split(" ")[0] for name, ok, _ in checks(s2) if not ok]
        got = want in fails
        row("selftest: %s is caught by check %s" % (label, want), got, "failed checks: %s" % fails)
        ok_all = ok_all and got
    return ok_all


def main():
    print("test-callfile-units: %s" % PATHS["op_jumps"])
    src = {k: read(p) for k, p in PATHS.items()}
    for name, ok, detail in checks(src):
        row(name, ok, detail)
    if "--selftest" in sys.argv:
        selftest(src)
    print("\ntest-callfile-units: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
