#!/usr/bin/env python3
#
# sandbox-list-q2.py - QM4 gaps bundle Q-2 (select lists): FORMLISTV, GETLISTV, WRITELIST, MOVELIST, MOVELISTV.  No install,
# no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-list-q2.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for QM4 gaps bundle Q-2.
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets, made by reading the ids of a list out one at a time
# with READNEXT: a list is judged by what comes out of it, so a list that is empty, moved away or never made cannot pass.
# The older statements that do the same on numbered lists (FORMLIST, GETLIST, SELECT) are the controls.  A body line that
# starts with a dollar sign is written at the left margin.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

CASES = []
AUX = []


def case(label, body, want, has=(), lacks=()):
    CASES.append((label, body, want, tuple(has), tuple(lacks)))


def drain(src, into):
    """BASIC that reads every id left in the numbered list or select list variable src into the variable into, comma separated."""
    return ("%(v)s = ''\nloop\n   readnext id from %(s)s else exit\n   %(v)s<-1> = id\nrepeat\n%(v)s = change(%(v)s, @fm, ',')\n"
            % {"v": into, "s": src})


# ---- FORMLISTV ----------------------------------------------------------------------------------------------------------
case("CONTROL: FORMLIST makes a numbered list from an array and READNEXT reads it",
     "formlist 'a':@fm:'b':@fm:'c' to 3\n" + drain("3", "x"), "a,b,c")
case("FORMLISTV makes a select list variable from an array", "formlistv 'a':@fm:'b':@fm:'c' to sl\n" + drain("sl", "x"), "a,b,c")
case("FORMLISTV of a null array is an empty list", "formlistv '' to sl\n" + drain("sl", "x") + "x = x : '/'", "/")
case("FORMLISTV from a variable, and the variable it makes can be read twice over with a copy",
     "v = 'p':@fm:'q'\nformlistv v to sl\nsl2 = sl\n" + drain("sl", "x") + drain("sl2", "y") + "x = x : '|' : y", "p,q|p,q")
case("FORMLISTV of a single literal is a one item list (the literal is not read as a file name)",
     "formlistv 'abc' to sl\n" + drain("sl", "x"), "abc")
case("FORMLISTV of a null literal is an empty list", "formlistv '' to sl\n" + drain("sl", "x") + "x = x : '/'", "/")
case("FORMLISTV does not touch list 0", "formlist 'z' to 0\nformlistv 'a':@fm:'b' to sl\n" + drain("0", "x"), "z")

# ---- WRITELIST and GETLISTV ---------------------------------------------------------------------------------------------
case("CONTROL: GETLIST of a list that is not there takes ELSE", "getlist 'zzq2none' to 4 then x = 'then' else x = 'else'", "else")
case("WRITELIST then GETLIST (the numbered form) reads back what was written",
     "writelist 'x1':@fm:'x2':@fm:'x3' to 'zzq2a'\ngetlist 'zzq2a' to 4 then\n" + drain("4", "x") + "end else x = 'else'", "x1,x2,x3")
case("GETLISTV makes a select list variable of a saved list and sets the count",
     "writelist 'x1':@fm:'x2':@fm:'x3' to 'zzq2b'\ngetlistv 'zzq2b' to sl setting n then\n" + drain("sl", "x") + "x = x : '/' : n : '/' : @selected\nend else x = 'else'",
     "x1,x2,x3/3/3")
case("GETLISTV with no SETTING clause works too", "writelist 'k1':@fm:'k2' to 'zzq2c'\ngetlistv 'zzq2c' to sl then\n" + drain("sl", "x") + "end else x = 'else'", "k1,k2")
case("GETLISTV of a list that is not there takes ELSE and leaves the count at zero",
     "n = 9\ngetlistv 'zzq2nosuch' to sl setting n then x = 'then' else x = 'else/' : n", "else/0")
case("WRITELIST takes ON as well as TO", "writelist 'o1':@fm:'o2' on 'zzq2d'\ngetlistv 'zzq2d' to sl then\n" + drain("sl", "x") + "end else x = 'else'", "o1,o2")
case("WRITELIST replaces what was there",
     "writelist 'old1':@fm:'old2' to 'zzq2e'\nwritelist 'new1' to 'zzq2e'\ngetlistv 'zzq2e' to sl then\n" + drain("sl", "x") + "end else x = 'else'", "new1")
case("WRITELIST of a list a program read with READ", "open '$savedlists' to f else x = 'noopen'\nwritelist 'r1':@fm:'r2' to 'zzq2f'\nread rec from f, 'zzq2f' then x = change(rec, @fm, ',') else x = 'else'",
     "r1,r2")
case("The saved list is still there after GETLISTV (the disk copy is not removed)",
     "writelist 'k':@fm:'l' to 'zzq2g'\ngetlistv 'zzq2g' to sl then null\ngetlistv 'zzq2g' to s2 setting n then x = n else x = 'else'", "2")

# ---- MOVELIST and MOVELISTV ---------------------------------------------------------------------------------------------
case("MOVELIST moves one numbered list to another and clears the first",
     "formlist 'a':@fm:'b' to 3\nmovelist 3 to 5\n" + drain("5", "x") + drain("3", "y") + "x = x : '|' : y : '|'", "a,b||")
case("MOVELIST KEEP leaves the source as it was", "formlist 'a':@fm:'b' to 3\nmovelist 3 to 5 keep\n" + drain("5", "x") + drain("3", "y") + "x = x : '|' : y", "a,b|a,b")
case("MOVELIST moves the items that have not been read yet", "formlist 'a':@fm:'b':@fm:'c' to 3\nreadnext first from 3 else null\nmovelist 3 to 4\n" + drain("4", "x") + "x = first : '|' : x",
     "a|b,c")
case("MOVELIST replaces what the target held", "formlist 'old' to 6\nformlist 'n1':@fm:'n2' to 3\nmovelist 3 to 6\n" + drain("6", "x"), "n1,n2")
case("MOVELIST to list 0 and from list 0", "formlist 'z1':@fm:'z2' to 7\nmovelist 7 to 0\n" + drain("0", "x"), "z1,z2")
case("MOVELIST of a list to itself does nothing", "formlist 'a':@fm:'b' to 3\nmovelist 3 to 3\n" + drain("3", "x"), "a,b")
case("MOVELIST of an empty list gives an empty list", "movelist 8 to 9\n" + drain("9", "x") + "x = x : '/'", "/")
case("MOVELISTV makes a select list variable from a numbered list and clears the list",
     "formlist 'a':@fm:'b' to 3\nmovelistv 3 to sl\n" + drain("sl", "x") + drain("3", "y") + "x = x : '|' : y : '|'", "a,b||")
case("MOVELISTV KEEP leaves the numbered list", "formlist 'a':@fm:'b' to 3\nmovelistv 3 to sl keep\n" + drain("sl", "x") + drain("3", "y") + "x = x : '|' : y", "a,b|a,b")
case("MOVELIST from a select list variable to a numbered list",
     "formlistv 'v1':@fm:'v2' to sl\nmovelist sl to 5\n" + drain("5", "x"), "v1,v2")
case("MOVELIST from a variable with KEEP leaves the variable readable",
     "formlistv 'v1':@fm:'v2' to sl\nmovelist sl to 5 keep\n" + drain("5", "x") + drain("sl", "y") + "x = x : '|' : y", "v1,v2|v1,v2")
case("MOVELISTV from one variable to another", "formlistv 'v1':@fm:'v2' to sl\nmovelistv sl to s2\n" + drain("s2", "x"), "v1,v2")
case("A list number out of range stops the program with the select list message", "movelist 11 to 0\nx = 'went on'", None)


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
    say("sandbox-list-q2: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > %d commands" % len(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def source(i, body):
    lines = ["   x = ''"]
    for ln in body.split("\n"):
        lines.append(ln if ln.startswith("$") else "   " + ln)
    lines.append("   crt 'C%03d[':x:']'" % i)
    lines.append("end")
    return "\n".join(lines) + "\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-list-q2.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-list-q2: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-list-q2: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    cmds, names = [], []
    for i, (_label, body, _w, _h, _l) in enumerate(CASES):
        nm = "zzq2%03d" % i
        names.append(nm)
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(source(i, body))
        cmds += ["BASIC bp %s" % nm, "RUN bp %s" % nm]
    try:
        out = sess(box, *cmds)
        if os.environ.get("SDSUITE_RAW"):
            say(out)
        say("\n--- the select list statements -------------------------------------------------")
        for i, (label, _body, want, has, lacks) in enumerate(CASES):
            m = re.search(r"(?s):BASIC bp zzq2%03d\b(.*?):RUN bp zzq2%03d\b" % (i, i), out)
            seg = m.group(1) if m else ""
            m = re.search(r"(?m)^C%03d\[(.*)\]\s*$" % (i,), out)
            got = m.group(1) if m else None
            ok = (got == want) if want is not None else (got is None)
            ok = ok and all(w in seg for w in has) and not any(w in seg for w in lacks)
            row("%s: wanted %r" % (label, want), ok, "got %r, compiler said %r" % (got, " ".join(seg.split())[:300]))
    finally:
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-list-q2: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
