#!/usr/bin/env python3
#
# sandbox-locate-b5.py - 1.2-0 bundle B-5, sheet 419: the BY string of LOCATE takes C (force case sensitivity) and N (force
#                        none), with A or D and L or R, in any order.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-locate-b5.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 419.
# END-HISTORY
#
# THE INSTRUMENT.  A tag per call, name[found/position].  The list 'apple', 'Banana', 'cherry' is in case insensitive order and
# NOT in ASCII order (B sorts before a), so a case sensitive ascending search for 'banana' stops at 'cherry' and does not find
# it, while a case insensitive one finds it at 2: the two answers differ, which is what makes a row mean something.  Controls:
# the plain 'AL', 'AR' and 'DL' strings, and an unsorted search, answer as they did.

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
    say("sandbox-locate-b5: CANNOT RUN - " + msg)
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


# (tag, search string, BY string)
CASES = [
    ("A1", "banana", "AL"), ("A2", "banana", "ALN"), ("A3", "banana", "NAL"), ("A4", "banana", "ALC"), ("A5", "banana", "CAL"),
    ("A6", "BANANA", "aln"), ("A7", "banana", "ARN"), ("A8", "banana", "AR"), ("A9", "Banana", ""), ("A10", "Banana", "ALN"),
    ("A11", "banana", "N"), ("A12", "banana", ""), ("A13", "banana", "LAN"),
]

PROG = ("   s = 'apple':@fm:'Banana':@fm:'cherry'\n"
        + "".join("   locate '%s' in s<0> by '%s' setting p then crt '%s[1/':p:']' else crt '%s[0/':p:']'\n" % (t, b, g, g)
                  for g, t, b in CASES)
        + "   d = 'cherry':@fm:'Banana':@fm:'apple'\n"
          "   locate 'banana' in d<0> by 'DLN' setting p then crt 'D1[1/':p:']' else crt 'D1[0/':p:']'\n"
          "   locate 'banana' in d<0> by 'DL' setting p then crt 'D2[1/':p:']' else crt 'D2[0/':p:']'\n"
          "   v = 'apple':@vm:'Banana':@vm:'cherry'\n"
          "   locate 'BANANA' in v<1,1> by 'ALN' setting p then crt 'V1[1/':p:']' else crt 'V1[0/':p:']'\n"
          "   locate 'BANANA' in v<1,1> by 'AL' setting p then crt 'V2[1/':p:']' else crt 'V2[0/':p:']'\n"
          "   locate 'BANANA' in v<1,1> by 'N' setting p then crt 'V3[1/':p:']' else crt 'V3[0/':p:']'\n"
          "   by.s = 'a' : 'l' : 'n'\n"
          "   locate 'BANANA' in s<0> by by.s setting p then crt 'W1[1/':p:']' else crt 'W1[0/':p:']'\n"
          "   crt 'END'\nend\n")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-locate-b5.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-locate-b5: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-locate-b5: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    path = os.path.join(sysd, "bp", "zzlcb5")
    try:
        with open(path, "w") as f:
            f.write(PROG)
        out = sess(box, "BASIC bp zzlcb5", "RUN bp zzlcb5")
        row("setup: the probe compiles and runs to its end",
            has(out, r"^Compiled 1 program\(s\) with no errors") and has(out, r"^END$"), "\n".join(out[-8:]))

        def t(name):
            return tag(out, name)

        row("CONTROL: AL is case sensitive: 'banana' is not found in 'apple','Banana','cherry' (it stops at 3)", t("A1") == "0/3", repr(t("A1")))
        row("419: ALN finds it at 2", t("A2") == "1/2", repr(t("A2")))
        row("419: the letters may come in any order (NAL)", t("A3") == "1/2", repr(t("A3")))
        row("419: ALC is case sensitive, as AL is", t("A4") == "0/3", repr(t("A4")))
        row("419: CAL is too", t("A5") == "0/3", repr(t("A5")))
        row("419: lower case letters are accepted (aln), and the search string may be upper case", t("A6") == "1/2", repr(t("A6")))
        row("419: ARN (right aligned, no case) finds it, where AR does not",
            t("A7") == "1/2" and (t("A8") or "").startswith("0/"), "%r %r" % (t("A7"), t("A8")))
        row("CONTROL: the exact spelling is found by an unsorted search, and 'Banana' by ALN as well",
            t("A9") == "1/2" and t("A10") == "1/2", "%r %r" % (t("A9"), t("A10")))
        row("419: N alone (no sort) searches without regard to case", t("A11") == "1/2", repr(t("A11")))
        row("CONTROL: an empty BY string is an unsorted, case sensitive search: 'banana' is not there",
            (t("A12") or "").startswith("0/"), repr(t("A12")))
        row("the sort letter may follow the others (LAN is ascending, left aligned, no case)", t("A13") == "1/2", repr(t("A13")))
        row("419: descending DLN finds it in a list sorted down; DL does not",
            t("D1") == "1/2" and (t("D2") or "").startswith("0/"), "%r %r" % (t("D1"), t("D2")))
        row("419: values, the Pick style position (v<1>) and (v<1,1>)",
            t("V1") == "1/2" and (t("V2") or "").startswith("0/") and t("V3") == "1/2", "%r %r %r" % (t("V1"), t("V2"), t("V3")))
        row("419: the BY string may be a variable", t("W1") == "1/2", repr(t("W1")))
    finally:
        if os.path.exists(path):
            os.remove(path)
        subprocess.run([sys.executable, TOOL, box, "stop"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\nsandbox-locate-b5: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
