#!/usr/bin/env python3
#
# sandbox-numexp.py - OPTION NUMERIC.EXPONENT (openQM 4 release item, sheet 404).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-numexp.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  k_str_to_num() and k_is_num() (k_funcs.c): with the option on, a string of the form 123.45E-2 is
#               numeric - NUM() says so and arithmetic converts it.  Off (the default) it is not numeric.
# END-HISTORY
#
# Each case is a string; the program prints NUM() of it and, when NUM() is 1, the string plus zero.  The option-off
# run is the control: every case must say NUM 0 there, including the ones that are numbers with the option on.

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
    say("sandbox-numexp: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


# label, string, expected value when numeric with the option on (None = not numeric even with the option on)
CASES = [
    ("A1", "123.45E-2", "1.2345"),
    ("A2", "123.45e-2", "1.2345"),
    ("A3", "1E3", "1000"),
    ("A4", "1E+3", "1000"),
    ("A5", "-2.5E1", "-25"),
    ("A6", "+2E0", "2"),
    ("A7", ".5E1", "5"),
    ("A8", "12E-1", "1.2"),
    ("N1", "E5", None),           # no mantissa
    ("N2", "1E", None),           # no exponent digits
    ("N3", "1E+", None),
    ("N4", "1E5.5", None),        # decimal point in the exponent
    ("N5", "1E5E5", None),        # two exponents
    ("N6", "1E--5", None),
    ("N7", "1 E5", None),         # embedded space
    ("N8", "1E 5", None),
    ("N9", "1E999", None),        # out of range
    ("N10", "1EX", None),
    ("N11", "ABC", None),         # control: plain text
    ("C1", "123.45", "123.45"),   # control: ordinary numbers are untouched
    ("C2", "-7", "-7"),
]


def body():
    lines = []
    for lab, s, _ in CASES:
        lines.append("   s = '%s'" % s)
        lines.append("   if num(s) then crt '%s NUM1 ':(s + 0) else crt '%s NUM0'" % (lab, lab))
    return "\n".join(lines) + "\n   crt 'DONE'\nend\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-numexp.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-numexp: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-numexp: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    prog = "zznx" + RUN
    with open(os.path.join(sysd, "bp", prog), "w") as fh:
        fh.write(body())

    say("\n--- OPTION NUMERIC.EXPONENT -----------------------------------------------------------------------------")
    out = sess(box, "BASIC bp %s" % prog)
    row("setup: the program compiled with no errors", "Compiled 1 program(s) with no errors" in out, out[-600:])

    off = sess(box, "RUN bp %s" % prog)
    on = sess(box, "OPTION NUMERIC.EXPONENT", "RUN bp %s" % prog)
    back = sess(box, "OPTION NUMERIC.EXPONENT", "OPTION NUMERIC.EXPONENT OFF", "RUN bp %s" % prog)
    shown = sess(box, "OPTION NUMERIC.EXPONENT DISPLAY", "OPTION")

    def answer(text, lab):
        m = re.search(r"(?m)^%s (NUM1 (\S+)|NUM0)\s*$" % lab, text)
        if not m:
            return "MISSING"
        return m.group(2) if m.group(2) is not None else "NUM0"

    row("CONTROL: the run reached its last line in all three runs",
        all(re.search(r"(?m)^DONE\s*$", t) for t in (off, on, back)), (off + on + back)[-500:])
    row("CONTROL, the option off: no exponent form is numeric (NUM 0 for every one of them)",
        all(answer(off, lab) == "NUM0" for lab, s, v in CASES if v is not None and "E" in s.upper()),
        off[-600:])
    row("CONTROL, the option off: ordinary numbers are unchanged",
        answer(off, "C1") == "123.45" and answer(off, "C2") == "-7", off[-600:])
    for lab, s, v in CASES:
        if v is None:
            row("%s the option on: %r is not numeric" % (lab, s), answer(on, lab) == "NUM0", on[-800:])
        else:
            row("%s the option on: %r is numeric and equals %s" % (lab, s, v), answer(on, lab) == v,
                "got %r" % answer(on, lab))
    row("OPTION NUMERIC.EXPONENT OFF returns to the default", answer(back, "A1") == "NUM0" and answer(back, "C1") == "123.45",
        back[-600:])
    row("OPTION lists NUMERIC.EXPONENT and DISPLAY says On / Off", re.search(r"NUMERIC.EXPONENT: Off", shown) is not None
        and "NUMERIC.EXPONENT" in shown, shown[-500:])

    say("")
    say("sandbox-numexp: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
