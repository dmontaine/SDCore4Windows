#!/usr/bin/env python3
#
# sandbox-qdefaults.py - $QUERY.DEFAULTS fields 3 and 4 (openQM 4 release items, sheets 122 and 405).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-qdefaults.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  qproc: field 3 of $QUERY.DEFAULTS is inserted into SELECT / SSELECT; field 4 is the format of the
#               inserted id column when the dictionary has no @ID (default 12L, message 11243 for a bad one).
# END-HISTORY
#
# The record is written to the DICTIONARY of a scratch file (it is looked for there before the VOC), so no account
# default is disturbed.  The controls: the file with no $QUERY.DEFAULTS record (3 records selected, id left
# justified in 12 columns) and the same file after the record is deleted again.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
passed = failed = 0


def say(s=""):
    print(s)


def row(name, ok, detail=""):
    global passed, failed
    if ok:
        passed += 1
        say("  [PASS] " + name)
    else:
        failed += 1
        say("  [FAIL] " + name + ("   <- " + detail if detail else ""))


def bail(msg):
    say("sandbox-qdefaults: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-qdefaults.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-qdefaults: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-qdefaults: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    f = "zzqf" + RUN
    p = "zzqp" + RUN
    # the program takes a variant number: it writes (or deletes) the dictionary's $QUERY.DEFAULTS record
    prog = """   n = field(@sentence, ' ', 4)
   open 'DICT', '%s' to d else crt 'NO-DICT' ; stop
   delete d, '@id'      ;* field 4 is the format of the id column the query processor invents when the dictionary has no @ID
   delete d, '@ID'
   begin case
      case n = 0 ; delete d, '$QUERY.DEFAULTS'
      case n = 1 ; rec = 'X':@fm:'':@fm:'WITH @ID = "A1"':@fm:''
      case n = 2 ; rec = 'X':@fm:'WITH @ID = "B2"':@fm:'':@fm:'6R'
      case n = 3 ; rec = 'X':@fm:'WITH @ID = "B2"':@fm:'':@fm:'ABC'
      case n = 4 ; rec = 'X':@fm:'':@fm:'WITH @ID = "A1" _':@fm:'OR WITH @ID = "B2"':@fm:''
      case n = 5 ; rec = 'X':@fm:'':@fm:'':@fm:'4R'
   end case
   if n > 0 then write rec to d, '$QUERY.DEFAULTS'
   crt 'VARIANT-SET ':n
end
""" % f
    with open(os.path.join(sysd, "bp", p), "w") as fh:
        fh.write(prog)
    setup = """   open '%s' to fv else crt 'NO-FILE' ; stop
   write 'x' to fv, 'A1'
   write 'y' to fv, 'B2'
   write 'z' to fv, 'C3'
   crt 'DATA-WRITTEN'
end
""" % f
    ps = "zzqs" + RUN
    with open(os.path.join(sysd, "bp", ps), "w") as fh:
        fh.write(setup)

    say("\n--- $QUERY.DEFAULTS fields 3 and 4 ----------------------------------------------------------------------")
    out = sess(box, "CREATE.FILE %s DYNAMIC" % f, "BASIC bp %s" % p, "BASIC bp %s" % ps, "RUN bp %s" % ps)
    row("setup: both programs compiled, three records written",
        out.count("Compiled 1 program(s) with no errors") == 2 and "DATA-WRITTEN" in out, out[-800:])

    def go(variant, *cmds):
        return sess(box, "RUN bp %s %d" % (p, variant), *cmds)

    o = sess(box, "SELECT %s" % f)
    row("CONTROL, no record: SELECT selects all 3", re.search(r"\b3 record", o) is not None, o[-300:])
    o = sess(box, "LIST %s" % f)
    row("CONTROL, no record: the id column is left justified (A1 is not preceded by spaces)",
        re.search(r"^A1\s*$", o, re.M) is not None and "B2" in o, o[-400:])

    o = go(1, "SELECT %s" % f)
    row("field 3 is applied to SELECT: 1 record selected", "VARIANT-SET 1" in o and re.search(r"\b1 record", o) is not None, o[-300:])
    o = go(1, "SSELECT %s" % f)
    row("field 3 is applied to SSELECT: 1 record selected", re.search(r"\b1 record", o) is not None, o[-300:])
    o = go(1, "LIST %s" % f)
    row("field 3 is NOT applied to LIST (all three ids listed)",
        all(re.search(r"^\s*%s\b" % i, o, re.M) for i in ("A1", "B2", "C3")), o[-400:])
    o = go(1, "COUNT %s" % f)
    row("field 3 is NOT applied to COUNT", re.search(r"\b3 record", o) is not None, o[-300:])

    o = go(2, "LIST %s" % f)
    row("field 2 still applies to LIST (only B2)", re.search(r"^\s*B2\b", o, re.M) is not None and re.search(r"^\s*A1\b", o, re.M) is None, o[-400:])
    row("field 4 6R: the id is right justified (the heading, the file name and a dot, is wider than 6, so the column is as wide as that)",
        re.search(r"^ +B2\s*$", o, re.M) is not None, o[-400:])
    o = go(2, "SELECT %s" % f)
    row("field 3 empty: SELECT selects all 3", re.search(r"\b3 record", o) is not None, o[-300:])

    o = go(3, "LIST %s" % f)
    row("field 4 invalid: message 11243 is shown", "field 4 ignored" in o, o[-400:])
    row("field 4 invalid: the id column stays left justified", re.search(r"^B2\s*$", o, re.M) is not None, o[-400:])

    o = go(4, "SELECT %s" % f)
    row("field 3 continuation line is merged: 2 records selected", re.search(r"\b2 record", o) is not None, o[-300:])

    o = go(5, "LIST %s" % f)
    row("field 4 4R alone: ids right justified in 4 columns, all three listed",
        re.search(r"^ +A1\s*$", o, re.M) is not None and re.search(r"^ +C3\s*$", o, re.M) is not None, o[-400:])

    o = go(0, "SELECT %s" % f)
    row("CONTROL, record deleted again: SELECT selects all 3", re.search(r"\b3 record", o) is not None, o[-300:])

    say("\nsandbox-qdefaults: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


main()
