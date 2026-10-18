#!/usr/bin/env python3
#
# sandbox-list-a7.py - 1.2-0 bundle A-7 (openQM features after 2.6.6, select lists): GET.LIST and SAVE.LIST
#                      options, a default list name, SORT.LIST and SELECT.DIR.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-list-a7.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for 1.2-0 bundle A-7.
# END-HISTORY
#
# THE INSTRUMENT IS THE LIST ITSELF: a BASIC program reads select list 0 or 1 and prints each id, so a row
# says what the list holds and not what a command said about it.  Each leg has a CONTROL of the old behaviour.
#
#   1  SAVE.LIST KEEP (openQM ref 387), COUNT.SUP (2)
#   2  GET.LIST DELETING (384), COUNT.SUP (2)
#   3  a list name left out (401)
#   4  SORT.LIST (158)
#   5  SELECT.DIR (465)

import os
import re
import subprocess
import sys
import tempfile

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
    say("sandbox-list-a7: CANNOT RUN - " + msg)
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
                say("      | " + line.rstrip()[:120])
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


def ids(seg):
    return re.findall(r"(?m)^L\[(.*)\]\s*$", seg or "")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-list-a7.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-list-a7: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-list-a7: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        with open(os.path.join(bp, name), "w") as f:
            f.write(text)
        made.append(name)

    tmpdir = tempfile.mkdtemp(prefix="zza7dir")
    try:
        say("\n--- setup ---------------------------------------------------------------------")
        for rid, num in (("r1", "50"), ("r2", "40"), ("r3", "30"), ("r4", "20"), ("r5", "10")):
            prog("zza7" + rid, "n%s\n%s\n" % (rid, num))
        prog("zza7d2", "D\n2\n\nnum\n10R\nS\n")
        prog("zza7ls", "   loop\n      readnext x else exit\n      crt 'L[':x:']'\n   repeat\nend\n")
        prog("zza7l1", "   getlist 'zza7sv' to 1 else crt 'NOLIST'\n   loop\n      readnext x from 1 else exit\n"
                       "      crt 'L[':x:']'\n   repeat\nend\n")
        cmds = ["DELETE.FILE DICT zza7", "DELETE.FILE zza7", "CREATE.FILE zza7"]
        for rid in ("r1", "r2", "r3", "r4", "r5"):
            cmds.append("COPY FROM BP TO zza7 zza7%s,%s" % (rid, rid))
        cmds.append("COPY FROM BP TO DICT zza7 zza7d2,num")
        cmds.append("BASIC bp zza7ls")
        out = sess(box, *cmds, quiet=True)
        row("setup: fixture file and probe compiled", len(re.findall(r"(?m)^1 record\(s\) copied\.", out)) == 6
            and re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None, "setup output unexpected")

        say("\n--- leg 1: SAVE.LIST KEEP and COUNT.SUP (refs 387, 2) -------------------------------------")
        c = ["SELECT zza7 WITH num > 25", "SAVE.LIST zza7sv1", "RUN bp zza7ls"]
        sg = segments(sess(box, *c), c)
        row("CONTROL: SAVE.LIST empties the active list: nothing left to read", ids(sg.get(2)) == [], "got %r" % ids(sg.get(2)))
        c = ["SELECT zza7 WITH num > 25", "SAVE.LIST zza7sv2 KEEP", "RUN bp zza7ls"]
        sg = segments(sess(box, *c), c)
        row("THE ROW: with KEEP the list is still there: r1 r2 r3", sorted(ids(sg.get(2))) == ["r1", "r2", "r3"],
            "got %r" % ids(sg.get(2)))
        c = ["SELECT zza7 WITH num > 25", "SAVE.LIST zza7sv3", "SELECT zza7 WITH num > 25", "SAVE.LIST zza7sv4 COUNT.SUP"]
        sg = segments(sess(box, *c), c)
        row("CONTROL: SAVE.LIST says how many records it saved",
            re.search(r"3 records? saved to select list 'zza7sv3'", sg.get(1, "")) is not None, "no 'saved' line")
        row("THE ROW: with COUNT.SUP it does not", "saved to select list" not in sg.get(3, ""), "a 'saved' line was printed")

        say("\n--- leg 2: GET.LIST DELETING and COUNT.SUP (refs 384, 2) ----------------------------------")
        c = ["GET.LIST zza7sv1", "GET.LIST zza7sv2 COUNT.SUP", "GET.LIST zza7sv2 DELETING", "GET.LIST zza7sv2"]
        sg = segments(sess(box, *c), c)
        row("CONTROL: GET.LIST says how many records it selected",
            re.search(r"3 record\(s\) selected to select list 0", sg.get(0, "")) is not None, "no 'selected' line")
        row("THE ROW: COUNT.SUP suppresses that line", "selected to select list" not in sg.get(1, ""), "line printed")
        row("THE ROW: after DELETING the saved list is gone", re.search(r"(?i)not found", sg.get(3, "")) is not None,
            "the list was still there")

        say("\n--- leg 3: a list name left out (ref 401) -----------------------------------------------")
        c = ["SELECT zza7 WITH num > 25", "SAVE.LIST", "GET.LIST 0", "RUN bp zza7ls"]
        sg = segments(sess(box, *c), c)
        row("SAVE.LIST with no name saves under the list number: 0",
            re.search(r"3 records? saved to select list '0'", sg.get(1, "")) is not None, "got %r" % sg.get(1))
        row("and GET.LIST 0 brings back r1 r2 r3", sorted(ids(sg.get(3))) == ["r1", "r2", "r3"], "got %r" % ids(sg.get(3)))

        say("\n--- leg 4: SORT.LIST (ref 158) --------------------------------------------------------")
        c = ["SSELECT zza7 BY.DSND num", "SAVE.LIST zza7sv5", "GET.LIST zza7sv5", "RUN bp zza7ls", "SORT.LIST zza7sv5",
             "GET.LIST zza7sv5", "RUN bp zza7ls"]
        sg = segments(sess(box, *c), c)
        row("CONTROL: the saved list is in descending order of num: r1 r2 r3 r4 r5", ids(sg.get(3)) == ["r1", "r2", "r3", "r4", "r5"],
            "got %r" % ids(sg.get(3)))
        c = ["SSELECT zza7 BY num", "SAVE.LIST zza7sv6", "SORT.LIST zza7sv6", "GET.LIST zza7sv6", "RUN bp zza7ls"]
        sg = segments(sess(box, *c), c)
        row("THE ROW: after SORT.LIST the ids are in ascending order: r1 r2 r3 r4 r5", ids(sg.get(4)) == ["r1", "r2", "r3", "r4", "r5"],
            "got %r" % ids(sg.get(4)))

        say("\n--- leg 5: SELECT.DIR (ref 465) --------------------------------------------------------")
        for n in ("alpha.txt", "beta.txt"):
            open(os.path.join(tmpdir, n), "w").write("x\n")
        os.mkdir(os.path.join(tmpdir, "gamma"))
        c = ["SELECT.DIR " + tmpdir, "RUN bp zza7ls"]
        sg = segments(sess(box, *c), c)
        row("THE ROW: the list holds the two files and the subdirectory", sorted(ids(sg.get(1))) == ["alpha.txt", "beta.txt", "gamma"],
            "got %r" % ids(sg.get(1)))
        c = ["SELECT.DIR " + tmpdir + "/nosuchdir"]
        out = sess(box, *c)
        row("a directory that is not there is refused", re.search(r"(?i)cannot read directory", out) is not None, "no refusal")
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zza7", "DELETE.FILE zza7", "DELETE.LIST zza7sv1", "DELETE.LIST zza7sv2",
             "DELETE.LIST zza7sv3", "DELETE.LIST zza7sv4", "DELETE.LIST zza7sv5", "DELETE.LIST zza7sv6", "DELETE.LIST 0",
             quiet=True)
        for f in os.listdir(tmpdir):
            p = os.path.join(tmpdir, f)
            if os.path.isdir(p):
                os.rmdir(p)
            else:
                os.remove(p)
        os.rmdir(tmpdir)

    say("\nsandbox-list-a7: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
