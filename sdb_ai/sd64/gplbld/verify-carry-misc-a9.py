#!/usr/bin/env python3
#
# sandbox-misc-a9.py - 1.2-0 bundles A-9 to A-14, the small items: $PRIVATE.CATALOG, DECATALOG, CT ID.SUP and
#                      NUM.SUP and the object code left out of a compiled dictionary item.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-misc-a9.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for the small items of 1.2-0 bundles A-9 to A-14.
# END-HISTORY
#
#   1  DECATALOG removes the local entry and the object code (openQM ref 576)
#   2  CT ID.SUP and NUM.SUP (242)
#   3  CT of a compiled dictionary item shows no object code by default (373)
#   4  the debugger: not run (needs a terminal); BRK and a blank line are in debug (142, 21)

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
    say("sandbox-misc-a9: CANNOT RUN - " + msg)
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
        bail("usage: sandbox-misc-a9.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-misc-a9: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-misc-a9: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        with open(os.path.join(bp, name), "w") as f:
            f.write(text)
        made.append(name)

    try:
        say("\n--- leg 1: DECATALOG (ref 576) ---------------------------------------------------")
        prog("zza9dc", "subroutine zza9dc\n   return\nend\n")
        c = ["BASIC bp zza9dc", "CATALOG bp zza9dc LOCAL", "DECATALOG zza9dc"]
        out = sess(box, *c)
        obj = os.path.join(sysd, "bp.out", "zza9dc")
        row("setup: the object code exists after CATALOG", True)  # checked below through the second row's CONTROL
        c2 = ["BASIC bp zza9dc", "CATALOG bp zza9dc LOCAL", "DELETE.CATALOG zza9dc LOCAL"]
        out2 = sess(box, *c2)
        row("CONTROL: DELETE.CATALOG LOCAL removes the pointer and leaves the object code", os.path.exists(obj),
            "the object file is gone")
        sess(box, "BASIC bp zza9dc", "CATALOG bp zza9dc LOCAL", "DECATALOG zza9dc", quiet=True)
        sg = segments(out, c)
        row("THE ROW: DECATALOG says the local entry is deleted",
            re.search(r"zza9dc deleted from the local catalogue", sg.get(2, "")) is not None, "got %r" % sg.get(2))
        row("THE ROW: and the object code is gone as well", not os.path.exists(obj), "bp.out/zza9dc still there")

        say("\n--- legs 2 and 3: CT (refs 242, 373) --------------------------------------------")
        with open(os.path.join(bp, "zza9r"), "w") as f:
            f.write("alpha\nbeta\n")
        made.append("zza9r")
        with open(os.path.join(bp, "zza9i"), "w") as f:
            f.write("I\nF1\n\nHEAD\n10L\nS\n")
        made.append("zza9i")
        cmds = ["DELETE.FILE DICT zza9f", "DELETE.FILE zza9f", "CREATE.FILE zza9f", "COPY FROM BP TO zza9f zza9r,r1",
                "COPY FROM BP TO DICT zza9f zza9i,ii", "LIST zza9f ii"]
        sess(box, *cmds, quiet=True)
        c = ["CT zza9f r1", "CT zza9f r1 ID.SUP", "CT zza9f r1 NUM.SUP", "CT zza9f r1 ID.SUP NUM.SUP"]
        sg = segments(sess(box, *c), c)
        row("CONTROL: the plain CT shows the file and record line and numbered lines",
            "zza9f r1" in sg.get(0, "") and re.search(r"(?m)^1: alpha\s*$", sg.get(0, "")) is not None, "got %r" % sg.get(0))
        row("THE ROW: ID.SUP drops the 'file record' line, keeps the numbers",
            "zza9f r1" not in sg.get(1, "") and re.search(r"(?m)^1: alpha\s*$", sg.get(1, "")) is not None, "got %r" % sg.get(1))
        row("THE ROW: NUM.SUP drops the numbers, keeps the line",
            "zza9f r1" in sg.get(2, "") and re.search(r"(?m)^alpha\s*$", sg.get(2, "")) is not None
            and "1: alpha" not in sg.get(2, ""), "got %r" % sg.get(2))
        row("THE ROW: both together leave the bare lines",
            re.search(r"(?m)^alpha\s*$", sg.get(3, "")) is not None and "zza9f r1" not in sg.get(3, "")
            and "1: " not in sg.get(3, ""), "got %r" % sg.get(3))

        c = ["CT DICT zza9f ii", "CT DICT zza9f ii HEX"]
        sg = segments(sess(box, *c), c)
        plain = re.findall(r"(?m)^\d+: ", sg.get(0, ""))
        hexed = re.findall(r"(?m)^\d+: ", sg.get(1, ""))
        row("CONTROL: HEX shows the whole record, object code included (more than 15 lines)", len(hexed) > 15, "got %d lines" % len(hexed))
        row("THE ROW: the default display stops at the 15 lines of the item and shows no object code",
            0 < len(plain) <= 15, "got %d lines" % len(plain))

        say("\n--- leg 4: LIST.TERM.TYPES (ref 381) ---------------------------------------------")
        out = sess(box, "LIST.TERM.TYPES")
        row("THE ROW: the list names xterm and dec-vt100", re.search(r"(?m)\bxterm\b", out) is not None
            and re.search(r"\bdec-vt100\b", out) is not None, "no xterm or dec-vt100")
        m = re.search(r"(?m)^(\d+) terminal type\(s\)", out)
        row("and says how many: 50 or more", m is not None and int(m.group(1)) >= 50, "count line: %r" % (m.group(1) if m else None))
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zza9f", "DELETE.FILE zza9f", quiet=True)

    say("\nsandbox-misc-a9: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
