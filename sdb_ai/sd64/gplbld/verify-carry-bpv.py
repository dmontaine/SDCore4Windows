#!/usr/bin/env python3
#
# sandbox-bpv.py - 1.2-0 item 232 (bundle A-3): the X breakpoint control option saves the previous value of
#                  the breakpoint field in @BPV.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-bpv.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for item 232.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT LIST PRINTED for five records in two groups (ga ga gb gb gb).  The I-type item
# `bpv.t` is: detail line (@NB = 0) its name, grand total (@NB = 255) 'Total', a breakpoint line 'P=' : @BPV.
# So a breakpoint line that shows P=ga carries the value, and P= alone is the empty @BPV.
#
#   1  BREAK.ON "'X'" grp : the two breakpoint lines show P=ga and P=gb, the grand total shows Total
#   2  CONTROL: BREAK.ON grp with no X : the breakpoint lines show P= only (@BPV is empty)
#   3  the detail lines are unchanged (their names)
#   4  X beside another code ("'XU'") still sets @BPV

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
    say("sandbox-bpv: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    if not quiet:
        for line in out.splitlines():
            if line.strip() and not line.startswith(":") and not line.startswith("exit "):
                say("      | " + line.rstrip()[:130])
    return out


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("ascii"))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-bpv.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-bpv: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-bpv: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    try:
        say("\n--- setup ---------------------------------------------------------------------")
        data = [("r1", "alpha", "50", "ga"), ("r2", "bravo", "40", "ga"), ("r3", "charlie", "30", "gb"),
                ("r4", "delta", "20", "gb"), ("r5", "echo", "10", "gb")]
        for rid, n, num, g in data:
            prog("zzbv" + rid, "%s\n%s\n%s\n" % (n, num, g))
        for i, nm in ((1, "name"), (2, "num"), (3, "grp")):
            prog("zzbvd%d" % i, "D\n%d\n\n%s\n10L\nS\n" % (i, nm))
        prog("zzbvit", "I\nif @nb = 0 then name else if @nb = 255 then 'Total' else 'P=' : @bpv\n\nbpv.t\n12L\nS\n")
        cmds = ["DELETE.FILE DICT zzbv", "DELETE.FILE zzbv", "CREATE.FILE zzbv"]
        for rid, *_ in data:
            cmds.append("COPY FROM BP TO zzbv zzbv%s,%s" % (rid, rid))
        for i, nm in ((1, "name"), (2, "num"), (3, "grp")):
            cmds.append("COPY FROM BP TO DICT zzbv zzbvd%d,%s" % (i, nm))
        cmds.append("COPY FROM BP TO DICT zzbv zzbvit,bpv.t")
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: all 9 COPY commands each copied one record", copied == 9, "copied lines: %d" % copied)

        def run(brk):
            cmd = 'LIST zzbv BY grp BREAK.ON %s grp name CALC bpv.t ID.SUP' % brk
            out = sess(box, cmd)
            return out.split(cmd, 1)[-1]

        say("\n--- leg 1: X saves the value (ref 232) -------------------------------------------")
        body = run("\"'X'\"")
        row("THE ROW: the breakpoint lines show P=ga and P=gb",
            re.search(r"(?m)P=ga\s*$", body) is not None and re.search(r"(?m)P=gb\s*$", body) is not None, "no P=ga / P=gb")
        row("the grand total line shows Total", re.search(r"(?m)^\s*Total\s*$", body) is not None, "no Total")
        row("the detail lines still show their names",
            all(re.search(r"(?m)\b%s\s+%s\s*$" % (n, n), body) for n in ("alpha", "echo")), "names missing")

        say("\n--- leg 2: CONTROL, no X -------------------------------------------------------")
        body = run("")
        row("CONTROL: with no X the breakpoint lines show P= and no group value",
            re.search(r"(?m)P=\s*$", body) is not None and "P=ga" not in body and "P=gb" not in body, "P=g seen, or no P=")

        say("\n--- leg 3: X beside another code -------------------------------------------------")
        body = run("\"'XU'\"")
        row("'XU' still sets @BPV: P=ga and P=gb",
            "P=ga" in body and "P=gb" in body, "no P=ga / P=gb")
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zzbv", "DELETE.FILE zzbv", quiet=True)

    say("\nsandbox-bpv: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
