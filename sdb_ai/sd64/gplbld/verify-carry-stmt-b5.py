#!/usr/bin/env python3
#
# sandbox-stmt-b5.py - 1.2-0 bundle B-5 (openQM new and extended BASIC statements).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-stmt-b5.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for 1.2-0 bundle B-5: SSELECT ... RIGHT.ALIGNED / DESCENDING (243, 367), SSELECTN (209).
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets.  The ids 9, 10, 100 and abc are written
# to a scratch file; each row selects them a different way and prints the ids in list order, joined with /.
# The plain SSELECT is the CONTROL: it must give the old left-aligned order.  The clauses go BEFORE `to n`:
# after it the list-number expression reads the clause word as part of itself (measured; "Unassigned variable").

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

SETUP = ("execute 'CREATE.FILE zzb5f' capturing junk\n"
         "open 'zzb5f' to fv else stop\n"
         "write 'a' on fv, '9'\nwrite 'a' on fv, '10'\nwrite 'a' on fv, '100'\nwrite 'a' on fv, 'abc'\n")
COLLECT = ("x = ''\nloop\n   readnext id from %s else exit\n   x := id : '/'\nrepeat\n")

CASES = [
    ("CONTROL: plain SSELECT sorts left aligned (the old order)",
     SETUP + "sselect fv\n" + COLLECT % "0", "10/100/9/abc/"),
    ("243: RIGHT.ALIGNED sorts numbers by value, text after",
     SETUP + "sselect fv right.aligned\n" + COLLECT % "0", "9/10/100/abc/"),
    ("367: DESCENDING reverses the left aligned order",
     SETUP + "sselect fv descending\n" + COLLECT % "0", "abc/9/100/10/"),
    ("243+367: RIGHT.ALIGNED DESCENDING",
     SETUP + "sselect fv right.aligned descending\n" + COLLECT % "0", "abc/100/10/9/"),
    ("243+367: DESCENDING RIGHT.ALIGNED, the other order, is the same",
     SETUP + "sselect fv descending right.aligned\n" + COLLECT % "0", "abc/100/10/9/"),
    ("243 with TO: the clause before TO, the list goes to list 3",
     SETUP + "sselect fv right.aligned to 3\n" + COLLECT % "3", "9/10/100/abc/"),
    ("209: SSELECTN sorts into a numbered list",
     SETUP + "sselectn fv to 2\n" + COLLECT % "2", "10/100/9/abc/"),
    ("209: SSELECTN takes the clauses as well",
     SETUP + "sselectn fv right.aligned to 2\n" + COLLECT % "2", "9/10/100/abc/"),

    # ---- FOR var = v1, v2, ... and FOR EACH var IN string {DELIMITER d}  (sheet 84, 300; manual FOR / NEXT) ----
    # The classic statement is the CONTROL for each new one: it must still compile as it did.
    ("CONTROL: the classic FOR ... TO ... STEP", "for i = 1 to 10 step 3\n   x := i:'/'\nnext i", "1/4/7/10/"),
    ("CONTROL: a variable called EACH is still a control variable", "for each = 1 to 3\n   x := each\nnext each", "123"),
    ("CONTROL: commas inside a function's brackets do not make a list", "for i = max(1, 2) to 4\n   x := i\nnext i", "234"),
    ("CONTROL: WHILE and UNTIL on the classic loop", "for i = 1 to 9 while i < 6 until i = 4\n   x := i\nnext i", "123"),
    ("FOR var = list: the values in turn", "for i = 5, 7, 22\n   x := i:'/'\nnext i", "5/7/22/"),
    ("...expressions as well as constants", "a = 10\nfor i = a, a * 2, a + 5\n   x := i:'/'\nnext i", "10/20/15/"),
    ("...strings", "for s = 'x', 'y', 'z'\n   x := s\nnext s", "xyz"),
    ("...a list of one value", "for i = 4\n   x := i\nnext i", "4"),
    ("...the control variable keeps the last value on leaving", "for i = 1, 7, 22\nnext i\nx = i", "22"),
    ("...WHILE ends the loop", "for i = 1, 2, 3, 4\nwhile i < 3\n   x := i\nnext i", "12"),
    ("...UNTIL ends the loop before the body for that value", "for i = 1, 2, 3, 4\nuntil i = 3\n   x := i\nnext i", "12"),
    ("...CONTINUE and EXIT", "for i = 1, 2, 3, 4, 5\n   if i = 2 then continue\n   if i = 5 then exit\n   x := i\nnext i", "134"),
    ("...nested lists", "for i = 1, 2\n   for j = 3, 4\n      x := i:j:'/'\n   next j\nnext i", "13/14/23/24/"),
    ("...the same loop entered again starts from its first value",
     "for k = 1 to 2\n   for i = 7, 8\n      x := i\n   next i\nnext k", "7878"),
    ("...an array element as the control variable", "dim a(3)\nfor a(2) = 4, 5\n   x := a(2)\nnext a(2)", "45"),
    ("...a value expression with commas inside brackets", "for i = max(1, 2), min(7, 3)\n   x := i\nnext i", "23"),
    ("FOR EACH: any mark separates the values", "s = 'a':@fm:'b':@vm:'c'\nfor each v in s\n   x := v:'/'\nnext v", "a/b/c/"),
    ("...a null string makes no pass", "s = ''\nfor each v in s\n   x := 'X'\nnext v", ""),
    ("...a null value in the middle is a pass", "s = 'a':@fm:@fm:'c'\nfor each v in s\n   x := v:'/'\nnext v", "a//c/"),
    ("...a trailing mark ends with a null value (as REMOVE would give)", "s = 'a':@fm\nfor each v in s\n   x := v:'/'\nnext v", "a//"),
    ("...no mark is one value", "s = 'abc'\nfor each v in s\n   x := v:'/'\nnext v", "abc/"),
    ("...the value after the loop is the last one", "s = 'a':@fm:'b':@fm:'c'\nfor each v in s\nnext v\nx = v", "c"),
    ("...changing the string inside the loop has no effect", "s = 'a':@fm:'b':@fm:'c'\nfor each v in s\n   s = 'z'\n   x := v\nnext v", "abc"),
    ("...a field of a record as the string", "rec = 'h':@fm:'p':@vm:'q'\nfor each v in rec<2>\n   x := v:'/'\nnext v", "p/q/"),
    ("...an expression as the string", "for each v in change('a,b,c', ',', @fm)\n   x := v\nnext v", "abc"),
    ("...WHILE sees the new value", "s = 'a':@fm:'b':@fm:'c'\nfor each v in s\nwhile v # 'c'\n   x := v\nnext v", "ab"),
    ("...UNTIL, CONTINUE and EXIT", "s = 'a':@fm:'b':@fm:'c':@fm:'d':@fm:'e'\nfor each v in s\nuntil v = 'e'\n   if v = 'b' then continue\n   if v = 'd' then exit\n   x := v\nnext v", "ac"),
    ("...nested", "s = 'a':@fm:'b'\nt = 1:@fm:2\nfor each v in s\n   for each w in t\n      x := v:w:'/'\n   next w\nnext v", "a1/a2/b1/b2/"),
    ("...5000 values (REMOVE keeps its place: one pass, not one scan per value)",
     "s = ''\nfor i = 1 to 5000\n   s<i> = i\nnext i\nn = 0\nfor each v in s\n   n += v\nnext v\nx = n", "12502500"),
    ("FOR EACH DELIMITER: only that character separates", "s = 'a':@fm:'b':@vm:'c'\nfor each v in s delimiter @fm\n   x := change(v, @vm, '~'):'/'\nnext v", "a/b~c/"),
    ("...an ordinary character, with a null value", "s = 'a,b,,d'\nfor each v in s delimiter ','\n   x := v:'/'\nnext v", "a/b//d/"),
    ("...a null string makes no pass", "s = ''\nfor each v in s delimiter ','\n   x := 'X'\nnext v", ""),
    ("...WHILE and CONTINUE after DELIMITER", "s = 'a,b,c,d'\nfor each v in s delimiter ',' while v # 'd'\n   if v = 'b' then continue\n   x := v\nnext v", "ac"),
    ("...the delimiter is an expression", "d = ';'\ns = 'p;q'\nfor each v in s delimiter d : ''\n   x := v\nnext v", "pq"),
    ("...2000 values", "s = ''\nfor i = 1 to 2000\n   s := i : ','\nnext i\nn = 0\nfor each v in s delimiter ','\n   n += v\nnext v\nx = n", "2001000"),
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
    say("sandbox-stmt-b5: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-stmt-b5.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-stmt-b5: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-stmt-b5: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for i, (_, body, _w) in enumerate(CASES):
        nm = "zzb5%02d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write("   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'C%02d[':x:']'\nend\n" % i)
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        say("\n--- the statements ------------------------------------------------------------")
        for i, (label, _body, want) in enumerate(CASES):
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            row("%s: wanted %r" % (label, want), got == want, "got %r" % got if m else "no output")
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-stmt-b5: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
