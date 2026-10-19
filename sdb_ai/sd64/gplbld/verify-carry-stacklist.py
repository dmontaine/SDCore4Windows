#!/usr/bin/env python3
#
# sandbox-stacklist.py - 1.2-0 bundle B-5, sheet 61: EXECUTE ... STACKLIST keeps the default select list (list 0) as it was and
#                        puts it back when the command returns.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-stacklist.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 61.
# END-HISTORY
#
# THE INSTRUMENT.  List 0 holds the ids of file zzsl1 (a b c).  The executed command is SELECT zzsl2 (x y), which replaces list 0.
# The program then reads list 0 with READNEXT and prints what it finds: without STACKLIST it finds x y (the control), with it
# a b c.  A second probe reads one id before the EXECUTE (the remove pointer is part of the state), a third has the command
# consume the list (SAVE.LIST) to show the command was given it, and a fourth combines STACKLIST with CAPTURING and
# SETTING in either order.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
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
    say("sandbox-stacklist: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "sys")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]
    return [ln.rstrip() for ln in out.splitlines() if ln.strip() and not ln.startswith(":")]


def tag(lines, name):
    for ln in lines:
        m = re.match(r"^%s\[(.*)\]\s*$" % re.escape(name), ln)
        if m:
            return m.group(1)
    return None


def has(lines, pattern):
    return any(re.search(pattern, ln) for ln in lines)


# a helper written into each probe: print list 0 as the ids it holds, read to the end
DRAIN = ("   ids = ''\n   loop\n      readnext id else exit\n      ids := id : ' '\n   repeat\n")

SETUP = ("   for t = 1 to 2\n      nm = 'zzsl':t\n      execute 'DELETE.FILE ':nm capturing j\n      execute 'CREATE.FILE ':nm capturing j\n"
         "      open nm to f else stop 'no f'\n"
         "      if t = 1 then\n         write 'r' on f, 'a' ; write 'r' on f, 'b' ; write 'r' on f, 'c'\n"
         "      end else\n         write 'r' on f, 'x' ; write 'r' on f, 'y'\n      end\n   next t\n"
         "   open 'zzsl1' to f1 else stop 'no f1'\n")

PROGS = {
    "zzsl": (SETUP +
             # control: no STACKLIST, the command's SELECT replaces the list
             "   select f1\n   execute 'CLEAR.SELECT':@fm:'SELECT zzsl2' capturing j\n"
             + DRAIN.replace("ids", "ids") + "   crt 'C[':trim(ids):']'\n"
             # STACKLIST
             "   select f1\n   execute 'CLEAR.SELECT':@fm:'SELECT zzsl2' capturing j stacklist\n"
             + DRAIN + "   crt 'S[':trim(ids):']'\n"
             # STACKLIST first, then CAPTURING, and SETTING
             "   select f1\n   execute 'CLEAR.SELECT':@fm:'SELECT zzsl2' stacklist capturing j setting st\n"
             + DRAIN + "   crt 'S2[':trim(ids):']'\n"
             # the remove pointer is part of the state
             "   select f1\n   readnext first.id else first.id = 'none'\n"
             "   execute 'CLEAR.SELECT':@fm:'SELECT zzsl2' capturing j stacklist\n"
             "   readnext second.id else second.id = 'none'\n   crt 'P[':first.id:'/':second.id:']'\n"
             # a count that is right: the list is still 3 long less the one read
             "   select f1\n   crt 'N0[':system(11):']'\n   execute 'CLEAR.SELECT':@fm:'SELECT zzsl2' capturing j stacklist\n"
             "   crt 'N[':system(11):']'\n"
             # the command was given the list: SAVE.LIST takes list 0 and the program's list is still whole afterwards
             "   execute 'DELETE.LIST zzslsv' capturing j\n"
             "   select f1\n   execute 'SAVE.LIST zzslsv' capturing j stacklist\n"
             + DRAIN + "   crt 'V[':trim(ids):']'\n"
             "   getlist 'zzslsv' to 5 then\n      ids = ''\n      loop\n         readnext id from 5 else exit\n         ids := id : ' '\n      repeat\n"
             "      crt 'G[':trim(ids):']'\n   end else crt 'G[nolist]'\n"
             # no list at all before: the command's list does not leak, and nothing is made up
             "   clearselect\n   execute 'CLEAR.SELECT':@fm:'SELECT zzsl2' capturing j stacklist\n"
             + DRAIN + "   crt 'E[':trim(ids):']'\n"
             "   crt 'END'\nend\n"),
    "zzslbad1": "   p = ''\n   execute 'SELECT zzsl2' passlist p stacklist\nend\n",
    "zzslbad2": "   r = ''\n   execute 'SELECT zzsl2' rtnlist r stacklist\nend\n",
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-stacklist.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-stacklist: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-stacklist: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        for nm, text in PROGS.items():
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write(text)
            made.append(nm)
        out = sess(box, "BASIC bp zzsl")
        row("setup: the probe compiles with no errors", has(out, r"^Compiled 1 program\(s\) with no errors"), "\n".join(out[-8:]))
        for nm in ("zzslbad1", "zzslbad2"):
            out = sess(box, "BASIC bp " + nm)
            row("61: STACKLIST with %s is refused at compile time" % ("PASSLIST" if nm.endswith("1") else "RTNLIST"),
                not has(out, r"^Compiled 1 program\(s\) with no errors") and has(out, r"STACKLIST cannot be used with PASSLIST or RTNLIST"),
                "\n".join(out[-4:]))

        out = sess(box, "RUN bp zzsl")
        row("the run reached its end", has(out, r"^END$"), "\n".join(out[-8:]))
        row("CONTROL: without STACKLIST the list the command made (x y) is what the program finds afterwards, not a b c",
            tag(out, "C") == "x y", repr(tag(out, "C")))
        row("61: with STACKLIST list 0 is back as it was (a b c)", tag(out, "S") == "a b c", repr(tag(out, "S")))
        row("61: ... in either order with CAPTURING and SETTING", tag(out, "S2") == "a b c", repr(tag(out, "S2")))
        row("61: ... and the remove pointer is part of it (a was read before, so b is next)", tag(out, "P") == "a/b", repr(tag(out, "P")))
        row("61: ... and SYSTEM(11), the state of list 0, is what it was before the command (and not the null of an empty list)",
            tag(out, "N") == tag(out, "N0") and tag(out, "N0") not in (None, "", "0"), "%r then %r" % (tag(out, "N0"), tag(out, "N")))
        row("61: the command was given the list (SAVE.LIST saved a b c) and the program still has it whole afterwards",
            tag(out, "G") == "a b c" and tag(out, "V") == "a b c", "%r %r" % (tag(out, "G"), tag(out, "V")))
        row("61: with no list before it, a list made inside the command is not left behind (E is empty)", tag(out, "E") == "", repr(tag(out, "E")))
    finally:
        sess(box, "DELETE.FILE zzsl1", "DELETE.FILE zzsl2", "DELETE.LIST zzslsv")
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        subprocess.run([sys.executable, TOOL, box, "stop"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\nsandbox-stacklist: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
