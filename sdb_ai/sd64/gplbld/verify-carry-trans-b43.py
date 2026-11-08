#!/usr/bin/env python3
#
# sandbox-trans-b43.py - sheet 43: TRANS(), RTRANS() and XLATE() on a file that cannot be opened take the action the
#                        code argument names: X null, V null and a message, C the id.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-trans-b43.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 43.
# END-HISTORY
#
# THE INSTRUMENT.  The file zzt43none does not exist (the program deletes it first, and says if it still opens).  Each
# call prints its result in a tag and a marker line before and after it, so that a message SD displays can be
# attributed to the call that caused it.  Controls: an existing file with a missing record keeps X / C / V as before.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
made = []

PROG = ("   execute 'DELETE.FILE zzt43none' capturing j\n"
        "   open 'zzt43none' to nf then stop 'file exists'\n"
        "   execute 'DELETE.FILE zzt43have' capturing j\n   execute 'CREATE.FILE zzt43have' capturing j\n"
        "   open 'zzt43have' to hf else stop 'no have'\n   write 'a':@fm:'b' on hf, 'r1'\n"
        "   crt 'M0'\n   x = trans('zzt43none', 'k1', 1, 'X') ; crt 'X[':x:']'\n"
        "   crt 'M1'\n   x = trans('zzt43none', 'k1', 1, 'V') ; crt 'V[':x:']'\n"
        "   crt 'M2'\n   x = trans('zzt43none', 'k1', 1, 'C') ; crt 'C[':x:']'\n"
        "   crt 'M3'\n   x = trans('zzt43none', 'k1', 1, 'N') ; crt 'N[':x:']'\n"
        "   crt 'M4'\n   x = trans('zzt43none', 'k2', 1, 'C') ; crt 'XL[':x:']'\n"
        "   crt 'M5'\n   x = rtrans('zzt43none', 'k3', 1, 'C') ; crt 'RT[':x:']'\n"
        "   crt 'M6'\n   x = trans('DICT zzt43none', 'k4', 1, 'C') ; crt 'DC[':x:']'\n"
        "   crt 'M7'\n   x = trans('zzt43none', 'k1', 1, 'X') ; crt 'XB[':x:']'\n"
        "   crt 'M8'\n   x = trans('zzt43have', 'r1', 2, 'C') ; crt 'HV[':x:']'\n"
        "   x = trans('zzt43have', 'nokey', 1, 'C') ; crt 'HC[':x:']'\n"
        "   x = trans('zzt43have', 'nokey', 1, 'X') ; crt 'HX[':x:']'\n"
        "   crt 'M9'\n   crt 'DONE43'\nend\n")


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
    say("sandbox-trans-b43: CANNOT RUN - " + msg)
    sys.exit(2)


def tool(box, *args, **kw):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace",
                          timeout=kw.pop("timeout", 900), **kw)


def sess(box, *cmds):
    say("    > %s" % " | ".join(c if len(c) < 60 else c[:57] + "..." for c in cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def tagged(out, tag):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % tag, out)
    return m.group(1) if m else None


def between(out, a, b):
    """The lines printed between marker a and marker b (the messages of the call that sits between them)."""
    m = re.search(r"(?ms)^%s\s*$(.*?)^%s\s*$" % (a, b), out)
    return None if m is None else m.group(1)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-trans-b43.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-trans-b43: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-trans-b43: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)

    try:
        tool(box, "start", timeout=180)
        with open(os.path.join(sysd, "bp", "zzt43"), "w") as f:
            f.write(PROG)
        made.append("zzt43")
        out = sess(box, "BASIC bp zzt43")
        if "Compiled 1 program(s) with no errors" not in out:
            bail("the program did not compile:\n" + out[-800:])
        out = sess(box, "RUN bp zzt43")
        row("the run reached its end", "DONE43" in out and "file exists" not in out, out[-500:])

        def msg(a, b):
            t = between(out, a, b)
            return None if t is None else re.sub(r"(?m)^[A-Z]+\[.*\]\s*$", "", t).strip()

        row("43: X on a file that will not open gives null", tagged(out, "X") == "", "got %r" % tagged(out, "X"))
        row("43: ... and says nothing (it said 'Cannot open' every time before)", msg("M0", "M1") == "", "got %r" % msg("M0", "M1"))
        row("43: V gives null", tagged(out, "V") == "", "got %r" % tagged(out, "V"))
        row("43: ... and says it could not open the file", "Cannot open 'zzt43none'" in (between(out, "M1", "M2") or ""),
            "got %r" % between(out, "M1", "M2"))
        row("43: C gives the record id", tagged(out, "C") == "k1", "got %r" % tagged(out, "C"))
        row("43: ... and says nothing", msg("M2", "M3") == "", "got %r" % msg("M2", "M3"))
        row("43: a code that is none of X, V, C is taken as X (null, silent)", tagged(out, "N") == "" and msg("M3", "M4") == "",
            "got %r / %r" % (tagged(out, "N"), msg("M3", "M4")))
        row("43: a second TRANS with C gives the id (XLATE, a second name, was removed 27 Oct 26)", tagged(out, "XL") == "k2", "got %r" % tagged(out, "XL"))
        row("43: RTRANS with C gives the id", tagged(out, "RT") == "k3", "got %r" % tagged(out, "RT"))
        row("43: a DICT file that will not open follows the code too", tagged(out, "DC") == "k4", "got %r" % tagged(out, "DC"))
        row("43: the second call for the same missing file does not reuse a stale answer", tagged(out, "XB") == "", "got %r" % tagged(out, "XB"))
        row("CONTROL: an existing file, an existing record, field 2", tagged(out, "HV") == "b", "got %r" % tagged(out, "HV"))
        row("CONTROL: an existing file, a missing record, C gives the id", tagged(out, "HC") == "nokey", "got %r" % tagged(out, "HC"))
        row("CONTROL: ... and X gives null", tagged(out, "HX") == "", "got %r" % tagged(out, "HX"))
    finally:
        tool(box, "stop", timeout=120)
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-trans-b43: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
