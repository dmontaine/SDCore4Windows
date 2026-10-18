#!/usr/bin/env python3
#
# sandbox-audit-b9.py - 1.2-0 bundle B-9 (openQM runtime bug-fix audit): test SD against each reported QM defect
#                       first, change the kernel only where the test fails.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-audit-b9.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (its sd binary is the one `make` last built).  With --build
# it is built first from THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed,
# 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for 1.2-0 bundle B-9.  Failed on the build before the fixes: 259 (SEEK from the end with a
#               negative offset gave error 3028) and 527 (LOCATE of a number into a lone text item, last-item arm).
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets, one probe per openQM item number.  Each
# probe ends by printing its own line; a probe that crashes the program prints nothing and the row fails with
# "no output".  Most rows have a CONTROL beside them, so a row cannot pass by printing nothing.
#
# Audited and found NOT to be SD defects (rows below are the evidence): 475, 562, 556, 265, 330, 526, 559.
# 328: ITYPE of a string that is not object code stops the program with an ordinary run-time error (op_misc.c
# `inva_i_type`), no crash; no row, because a stopped program prints nothing for a row to read.
# 528: SD stops the program with run-time error 000000E2 (illegal record id), so the id IS trapped; no row.
# 557: SD returns the empty trailing elements as delimiters ("x/y///"); a row records the present behaviour.
# Not testable here: 249 (sockets), 263, 266, 275, 279, 280, 317, 338, 342, 382, 525, 542 (no encodings), 590.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

# (label, BASIC statements, one per line, that leave the value to show in x, wanted value)
CASES = [
    ("475 CONTROL: appending three fields with <-1> reads back field 2",
     "x = ''\nx<-1> = 'a'\nx<-1> = 'b'\nx<-1> = 'c'\nx = x<2>", "b"),
    ("475 THE ROW: after the appends, INS before a new last field, fields 4, 5 and 3 are right",
     "x = ''\nx<-1> = 'a'\nx<-1> = 'b'\nx<-1> = 'c'\nins 'd' before x<4>\nins 'e' before x<5>\nx = x<4>:'/':x<5>:'/':x<3>",
     "d/e/c"),
    ("475 an insert at field 1 then an append reads every field",
     "x = 'b':@fm:'c'\nins 'a' before x<1>\nx<-1> = 'd'\nx = x<1>:x<2>:x<3>:x<4>", "abcd"),
    ("527 CONTROL: LOCATE AR of 6 in 1,5,9 gives 3",
     "s = '1':@fm:'5':@fm:'9'\nlocate 6 in s<0> by 'AR' setting p else null\nx = p", "3"),
    ("527 CONTROL: LOCATE AR of 10 in 1,5,9 gives 4",
     "s = '1':@fm:'5':@fm:'9'\nlocate 10 in s<0> by 'AR' setting p else null\nx = p", "4"),
    ("527 CONTROL: with TWO text items the number goes before them (position 1)",
     "s = 'abc':@fm:'abd'\nlocate 5 in s<0> by 'AR' setting p else null\nx = p", "1"),
    ("527 THE ROW: with ONE text item the number goes before it too (position 1; it said 2)",
     "s = 'abc'\nlocate 5 in s<0> by 'AR' setting p else null\nx = p", "1"),
    ("527 THE ROW: and descending, the number goes after the lone text item (position 2)",
     "s = 'abc'\nlocate 5 in s<0> by 'DR' setting p else null\nx = p", "2"),
    ("556 a 400 digit numeric into 1,2 does not end the program and goes last",
     "n = str('9', 400)\ns = '1':@fm:'2'\nlocate n in s<0> by 'AR' setting p else null\nx = p", "3"),
    ("557 CONTROL: MATBUILD of a full matrix",
     "dim a(3)\na(1) = 'x'\na(2) = 'y'\na(3) = 'z'\nmatbuild s from a\nx = change(s, @fm, '/')", "x/y/z"),
    ("557 the present behaviour: trailing unassigned elements come out as empty fields",
     "dim a(5)\na(1) = 'x'\na(2) = 'y'\nmatbuild s from a\nx = change(s, @fm, '/')", "x/y///"),
    ("562 CONTROL: MATCHFIELD with a plain pattern",
     "x = matchfield('ab12', '2A2N', 1)", "ab"),
    ("562 n-mX at the start of the pattern, first piece",
     "x = matchfield('ab12', '1-3A2N', 1)", "ab"),
    ("562 n-mX at the start of the pattern, second piece",
     "x = matchfield('ab12', '1-3A2N', 2)", "12"),
    ("562 and a longer run for the range",
     "x = matchfield('abc12', '1-3A2N', 1)", "abc"),
    ("265 FORMLIST of data delimited with value marks does not end the program",
     "formlist 'a':@vm:'b' to 5\nx = 'ok'", "ok"),
    ("259 CONTROL: SEEK 0 from the start",
     "openseq 'zzb9.txt' to f then null else null\nweofseq f\nwriteseq 'hello world' to f else null\ncloseseq f\n"
     "openseq 'zzb9.txt' to f else null\nseek f, 0, 0 then x = 'ok' else x = 'err'", "ok"),
    ("259 THE ROW: SEEK -3 from the end (it gave error 3028) reads the last bytes",
     "openseq 'zzb9.txt' to f else null\nseek f, -3, 2 then ok = 1 else ok = 0\nreadseq a from f else a = 'none'\nx = ok:'/':a",
     "1/ld"),
    ("259 a positive offset from the end still means that many bytes before it",
     "openseq 'zzb9.txt' to f else null\nseek f, 3, 2 then ok = 1 else ok = 0\nreadseq a from f else a = 'none'\nx = ok:'/':a",
     "1/ld"),
    ("259 an offset beyond the start is still refused",
     "openseq 'zzb9.txt' to f else null\nseek f, -50, 0 then x = 'ok' else x = 'err'", "err"),
    ("330 the record cache reads a changed record under another case of its id",
     "execute 'CREATE.FILE zzb9f' capturing junk\nopen 'zzb9f' to fv else null\nwrite 'one' on fv, 'ABC'\n"
     "read r1 from fv, 'abc' then null else r1 = 'none'\nwrite 'two' on fv, 'abc'\n"
     "read r2 from fv, 'ABC' then null else r2 = 'none'\nx = r1:'/':r2", "one/two"),
    ("526 RETURNING of EXECUTE and CSVDQ in one module keeps the return code",
     "execute 'LIST.TERM.TYPES NOPAGE' capturing junk returning rc\ny = csvdq('a,b')\nx = (rc = @system.return.code)", "1"),
    ("559 READV of a field beyond the end of the record, and of field 2",
     "open 'zzb9f' to vv else null\nwrite 'a':@fm:'b' on vv, 'r1'\nreadv v from vv, 'r1', 7 then null else v = 'none'\n"
     "readv w from vv, 'r1', 2 then null else w = 'none'\nx = v:'/':w", "/b"),
]


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
    say("sandbox-audit-b9: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-audit-b9.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-audit-b9: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-audit-b9: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    # one program per case, so a program that ends abnormally costs only its own row
    cmds = []
    names = []
    for i, (_, body, _w) in enumerate(CASES):
        nm = "zzb9%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write("   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'C%02d[':x:']'\nend\n" % i)
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        say("\n--- the probes ----------------------------------------------------------------")
        for i, (label, _body, want) in enumerate(CASES):
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            row("%s: wanted %r" % (label, want), got == want, "got %r" % got if m else "no output")
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, nm)
                if os.path.exists(p):
                    os.remove(p)
        p = os.path.join(box, "user_accounts", "zzb9.txt")
        if os.path.exists(p):
            os.remove(p)

    say("\nsandbox-audit-b9: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
