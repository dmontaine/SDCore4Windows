#!/usr/bin/env python3
#
# sandbox-option-a4.py - 1.2-0 bundle A-4 (openQM features after 2.6.6, OPTION command modes): does each
#                        new OPTION name exist, and change what it says it changes?  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-option-a4.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 10 Oct 26 dm  Written for 1.2-0 bundle A-4.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT THE COMMAND PRINTED.  Each leg runs the same command twice in one session, once
# before the option and once after OPTION <name>, on data where the two must differ, so a row cannot pass
# because the command printed nothing: the CONTROL is the first run.
#
#   1  QUERY.STRING.COMP (openQM ref 140)      4  DEFAULT.MV (205)
#   2  QUERY.STR.COMP.ALL (299)                5  BACKSLASH.NOT.QUOTE (165)
#   3  QUERY.SORT.NO.CASE (412)                6  CLEAR.SELECT (403)
#   0  the six names are known to OPTION

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
NAMES = ("QUERY.STRING.COMP", "QUERY.STR.COMP.ALL", "QUERY.SORT.NO.CASE", "BACKSLASH.NOT.QUOTE",
         "DEFAULT.MV", "CLEAR.SELECT")


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
    say("sandbox-option-a4: CANNOT RUN - " + msg)
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


def write(path, data):
    with open(path, "wb") as f:
        f.write(data if isinstance(data, bytes) else data.encode("latin-1"))


def segments(out, cmds):
    """Split a session's output into one text per command, at the echoed command lines (':' then the command)."""
    segs = {}
    cur = None
    for line in out.splitlines():
        for i, c in enumerate(cmds):
            if line.rstrip().startswith(":") and line.rstrip().lstrip(":") == c.rstrip() and i not in segs:
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
        bail("usage: sandbox-option-a4.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-option-a4: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-option-a4: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, data):
        write(os.path.join(bp, name), data)
        made.append(name)

    try:
        say("\n--- leg 0: the names ------------------------------------------------------------")
        out = sess(box, "OPTION")
        for n in NAMES:
            row("OPTION lists %s" % n, re.search(r"(?m)^%s\b" % re.escape(n), out) is not None, "not in the listing")

        say("\n--- setup ---------------------------------------------------------------------")
        # name, num, mv field (value marks), zzo4 ids r1..r6
        recs = [("r1", "Bob", "1", "x\xfdy\xfdz"), ("r2", "alice", "1.0", "p"), ("r3", "Carol", "01", "q"),
                ("r4", "dave", "2", "r"), ("r5", "ed", "9", "s"), ("r6", "fay", "100", "t")]
        # r5 9 and r6 100 and r2/r3/r4 give the numeric-versus-string cases
        for rid, name, num, mv in recs:
            prog("zzo4" + rid, "%s\n%s\n%s\n" % (name, num, mv))
        dicts = {"name": "D\n1\n\nname\n10L\nS\n", "num": "D\n2\n\nnum\n10R\nS\n", "numl": "D\n2\n\nnuml\n10L\nS\n",
                 "mv": "D\n3\n\nmv\n10L\n\n"}
        for k, v in dicts.items():
            prog("zzo4d" + k, v)
        write(os.path.join(bp, "zzo4bs"), "a\\b\n5\nm\n")       # a record whose name has a backslash
        made.append("zzo4bs")
        cmds = ["DELETE.FILE DICT zzo4", "DELETE.FILE zzo4", "CREATE.FILE zzo4"]
        for rid, *_ in recs:
            cmds.append("COPY FROM BP TO zzo4 zzo4%s,%s" % (rid, rid))
        cmds.append("COPY FROM BP TO zzo4 zzo4bs,r7")
        for k in dicts:
            cmds.append("COPY FROM BP TO DICT zzo4 zzo4d%s,%s" % (k, k))
        out = sess(box, *cmds, quiet=True)
        copied = len(re.findall(r"(?m)^1 record\(s\) copied\.", out))
        row("setup: all %d COPY commands each copied one record" % (len(cmds) - 3), copied == len(cmds) - 3,
            "copied lines: %d" % copied)

        def names_in(seg):
            return [m for m in re.findall(r"(?m)^(Bob|alice|Carol|dave|ed|fay|a\\b)\s*$", seg or "")]

        say("\n--- leg 1: QUERY.STRING.COMP (ref 140) -----------------------------------------------")
        c = ['LIST zzo4 name WITH num = "1" ID.SUP', "OPTION QUERY.STRING.COMP", 'LIST zzo4 name WITH num = "1" ID.SUP ']
        sg = segments(sess(box, *c), c)
        a, b = names_in(sg.get(0)), names_in(sg.get(2))
        row("CONTROL: numerically 1 = 1.0 = 01, so three records: Bob alice Carol", sorted(a) == ["Bob", "Carol", "alice"],
            "got %r" % a)
        row("THE ROW: as strings only '1' matches: Bob", b == ["Bob"], "got %r" % b)

        say("\n--- leg 2: QUERY.STR.COMP.ALL (ref 299) ----------------------------------------------")
        c = ['LIST zzo4 name WITH num > "20" ID.SUP', 'LIST zzo4 name WITH numl > "20" ID.SUP', "OPTION QUERY.STR.COMP.ALL",
             'LIST zzo4 name WITH num > "20" ID.SUP ', 'LIST zzo4 name WITH numl > "20" ID.SUP ']
        sg = segments(sess(box, *c), c)
        c_num, c_numl, p_num, p_numl = (names_in(sg.get(i)) for i in (0, 1, 3, 4))
        row("CONTROL: numeric > 20 on a right aligned item: only fay (100)", c_num == ["fay"], "got %r" % c_num)
        row("THE ROW: as strings '9' > '20' and '5' > '20', '100' and '2' are not: ed a\\b", sorted(p_num) == sorted(["ed", "a\\b"]),
            "got %r" % p_num)
        row("CONTROL: a left aligned item is left alone by the option", c_numl == ["fay"] and p_numl == ["fay"],
            "before %r, after %r" % (c_numl, p_numl))

        say("\n--- leg 3: QUERY.SORT.NO.CASE (ref 412) ----------------------------------------------")
        c = ["LIST zzo4 name BY name ID.SUP", "OPTION QUERY.SORT.NO.CASE", "LIST zzo4 name BY name ID.SUP "]
        sg = segments(sess(box, *c), c)
        a, b = names_in(sg.get(0)), names_in(sg.get(2))
        row("CONTROL: ASCII order, capitals first: Bob Carol a\\b alice dave ed fay",
            a == ["Bob", "Carol", "a\\b", "alice", "dave", "ed", "fay"], "got %r" % a)
        row("THE ROW: upper-cased keys: alice (ALICE) a\\b (A\\B) Bob Carol dave ed fay",
            b == ["alice", "a\\b", "Bob", "Carol", "dave", "ed", "fay"], "got %r" % b)

        say("\n--- leg 4: DEFAULT.MV (ref 205) ----------------------------------------------------")
        c = ['LIST zzo4 name WITH mv = "y" ID.SUP', "OPTION DEFAULT.MV", 'LIST zzo4 name WITH mv = "y" ID.SUP ']
        sg = segments(sess(box, *c), c)
        a, b = names_in(sg.get(0)), names_in(sg.get(2))
        row("CONTROL: a blank S/M flag is single valued, so 'y' is not the whole of x]y]z: no record", a == [], "got %r" % a)
        row("THE ROW: with DEFAULT.MV it is multivalued and 'y' is one of its values: Bob", b == ["Bob"], "got %r" % b)

        say("\n--- leg 5: BACKSLASH.NOT.QUOTE (ref 165) -------------------------------------------")
        c = ["LIST zzo4 name WITH name = a\\b ID.SUP", "OPTION BACKSLASH.NOT.QUOTE", "LIST zzo4 name WITH name = a\\b ID.SUP "]
        sg = segments(sess(box, *c), c)
        row("CONTROL: a backslash opens a quoted string and the line is refused",
            re.search(r"(?i)unpaired", sg.get(0) or "") is not None and names_in(sg.get(0)) == [], "no 'unpaired' message, or a record was listed")
        row("THE ROW: with the option it is an ordinary character: the record a\\b is listed", names_in(sg.get(2)) == ["a\\b"],
            "got %r" % names_in(sg.get(2)))

        say("\n--- leg 6: CLEAR.SELECT (ref 403) ------------------------------------------------------")
        out = sess(box, "SELECT zzo4 WITH num > 1.5", "DATE", "LIST zzo4 name ID.SUP")
        a = names_in(segments(out, ["SELECT zzo4 WITH num > 1.5", "DATE", "LIST zzo4 name ID.SUP"]).get(2))
        c = ["OPTION CLEAR.SELECT", "SELECT zzo4 WITH num > 1.5", "DATE", "LIST zzo4 name ID.SUP"]
        b = names_in(segments(sess(box, *c), c).get(3))
        row("CONTROL: the list survives DATE and LIST uses it: 4 records", len(a) == 4, "got %r" % a)
        row("THE ROW: with CLEAR.SELECT the waiting list is cleared by DATE, so LIST gets all 7 records", len(b) == 7,
            "got %r" % b)
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.FILE DICT zzo4", "DELETE.FILE zzo4", quiet=True)

    say("\nsandbox-option-a4: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
