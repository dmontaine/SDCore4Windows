#!/usr/bin/env python3
#
# sandbox-file-a8.py - 1.2-0 bundle A-8 (openQM features after 2.6.6, file and trigger commands):
#                      SET.TRIGGER ALL and LIST.TRIGGERS.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-file-a8.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for 1.2-0 bundle A-8.
# END-HISTORY
#
# The trigger function is a catalogued BASIC subroutine; SET.TRIGGER refuses a name that is not catalogued
# (3003), so the fixture compiles and catalogues one.  The instrument is what SET.TRIGGER and LIST.TRIGGERS
# print; the CONTROL for ALL is the same command with an explicit mode, which must give a smaller list.
#
#   1  SET.TRIGGER file name ALL (openQM ref 388)
#   2  LIST.TRIGGERS (74, 187)

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
    say("sandbox-file-a8: CANNOT RUN - " + msg)
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


def segments(out, cmds):
    segs, cur = {}, None
    for line in out.splitlines():
        r = line.rstrip()
        for i, c in enumerate(cmds):
            if r.startswith(":") and r.lstrip(":") == c.rstrip() and i not in segs:
                cur = i
                segs[i] = []
                break
        else:
            if cur is not None:
                segs[cur].append(line)
    return {i: "\n".join(v) for i, v in segs.items()}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-file-a8.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-file-a8: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-file-a8: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = ["zza8trg"]
    try:
        say("\n--- setup ---------------------------------------------------------------------")
        with open(os.path.join(bp, "zza8trg"), "w") as f:
            f.write("subroutine zza8trg(mode, file, id, rec, ctl)\n   return\nend\n")
        out = sess(box, "BASIC bp zza8trg", "CATALOG bp zza8trg LOCAL", "DELETE.FILE DICT zza8a", "DELETE.FILE zza8a",
                   "DELETE.FILE DICT zza8b", "DELETE.FILE zza8b", "CREATE.FILE zza8a", "CREATE.FILE zza8b", quiet=True)
        row("setup: the trigger subroutine compiled and the two files exist",
            re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None
            and "Created DATA part as zza8a" in out and "Created DATA part as zza8b" in out, "setup output unexpected")

        say("\n--- leg 1: SET.TRIGGER ... ALL (ref 388) --------------------------------------------")
        c = ["SET.TRIGGER zza8a zza8trg PRE.WRITE", "SET.TRIGGER zza8b zza8trg ALL"]
        sg = segments(sess(box, *c), c)
        a, b = sg.get(0, ""), sg.get(1, "")
        row("CONTROL: an explicit mode names just that mode", "PRE.WRITE" in a and "POST.DELETE" not in a, "got %r" % a)
        modes = ("PRE.WRITE", "PRE.DELETE", "POST.WRITE", "POST.DELETE", "READ", "PRE.CLEAR", "POST.CLEAR")
        row("THE ROW: ALL names every mode", all(m in b for m in modes), "got %r" % b)

        say("\n--- leg 2: LIST.TRIGGERS (refs 74, 187) -----------------------------------------------")
        c = ["LIST.TRIGGERS NO.PAGE", "LIST.TRIGGERS zza8a", "SET.TRIGGER zza8a ''", "LIST.TRIGGERS zza8a zza8b"]
        out = sess(box, *c)
        sg = segments(out, c)
        r0 = sg.get(0, "")
        row("every file with a trigger is listed: zza8a and zza8b",
            re.search(r"(?m)^zza8a\s+zza8trg\b", r0) is not None and re.search(r"(?m)^zza8b\s+zza8trg\b", r0) is not None, "got %r" % r0)
        row("the modes are shown after the function name: zza8a has PRE.WRITE, zza8b has POST.CLEAR",
            re.search(r"(?m)^zza8a\s+zza8trg\s+PRE.WRITE\s*$", r0) is not None and re.search(r"(?m)^zza8b .*POST.CLEAR", r0) is not None,
            "got %r" % r0)
        row("a file name on the command line restricts the report to it",
            re.search(r"(?m)^zza8a\b", sg.get(1, "")) is not None and "zza8b" not in sg.get(1, ""), "got %r" % sg.get(1))
        row("a file whose trigger was removed is no longer listed", "zza8a" not in sg.get(3, "") and "zza8b" in sg.get(3, ""),
            "got %r" % sg.get(3))
        row("the count line is there", re.search(r"(?m)^\d+ file\(s\) with a trigger function", r0) is not None, "no count line")
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.CATALOG zza8trg LOCAL", "DELETE.FILE DICT zza8a", "DELETE.FILE zza8a", "DELETE.FILE DICT zza8b",
             "DELETE.FILE zza8b", quiet=True)

    say("\nsandbox-file-a8: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
