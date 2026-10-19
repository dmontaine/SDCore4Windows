#!/usr/bin/env python3
#
# sandbox-listf-mult.py - openQM sheet 3 and 185: LISTF, LISTFL and LISTFR show a multifile with a line for each subfile,
#                         and take WITH / WITHOUT ENCRYPTION, REPLICATION and TRIGGER.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-listf-mult.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 15 Oct 26 dm  Written for sheets 3 and 185.  The sheet gives no line format for the subfiles; the format is the owner's "pick a
#               format": the type column of LISTF is multivalued, one value for each subfile, so that each subfile's type is on the
#               line of its own pathname; the first value is "Mult " and the type of the first subfile.
# END-HISTORY
#
# THE INSTRUMENT.  The reports are read as text, rows found by file name.  The report lists every F entry of the account's VOC, so
# every row names the fixture it is about (zzlfm a multifile of a hashed and a directory subfile, zzlfs a plain hashed file, zzlfd a
# plain directory file, zzlft a hashed file with a trigger) and looks for that name, not for a count.  Controls: the plain files
# keep their own type words; LISTFL and LISTFR still run; WITHOUT ENCRYPTION and WITHOUT REPLICATION keep every file, which is
# what proves WITH ENCRYPTION and WITH REPLICATION are empty because SD has neither and not because the clause matched nothing.

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
    say("sandbox-listf-mult: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def lines(out):
    return [l.rstrip() for l in out.splitlines()]


def line_of(out, name):
    """The report line that begins with the file name (the VOC id column), or None."""
    for l in lines(out):
        if re.match(r"%s(\s|$)" % re.escape(name), l):
            return l
    return None


def following(out, name, n):
    """The n lines after the line that begins with name."""
    ls = lines(out)
    for i, l in enumerate(ls):
        if re.match(r"%s(\s|$)" % re.escape(name), l):
            return ls[i + 1:i + 1 + n]
    return []


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-listf-mult.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-listf-mult: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-listf-mult: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = ["zzlftrg"]
    try:
        say("\n--- setup ---------------------------------------------------------------------")
        with open(os.path.join(sysd, "bp", "zzlftrg"), "w") as f:
            f.write("subroutine zzlftrg(mode, file, id, rec, ctl)\n   return\nend\n")
        out = sess(box, "BASIC bp zzlftrg", "CATALOG bp zzlftrg LOCAL",
                   "CREATE.FILE zzlfs", "CREATE.FILE zzlfd DIRECTORY", "CREATE.FILE zzlft",
                   "CREATE.FILE zzlfm,sub1", "CREATE.FILE zzlfm,sub2 DIRECTORY",
                   "SET.TRIGGER zzlft zzlftrg PRE.WRITE", quiet=True)
        row("setup: the trigger subroutine compiled", re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None, out[-500:])
        everything = sess(box, "LISTF NO.PAGE")
        for nm in ("zzlfs", "zzlfd", "zzlft", "zzlfm"):
            row("setup: LISTF lists %s" % nm, line_of(everything, nm) is not None, "not in the listing")
        say(everything[-1500:])

        say("\n--- sheet 3: a multifile has a line for each subfile ---------------------------------")
        mf = sess(box, 'LISTF WITH @ID = "zzlfm" NO.PAGE')
        first = line_of(mf, "zzlfm")
        row("3: the multifile's first line says Mult and the type of its first subfile (DH)",
            first is not None and re.search(r"\bMult DH\b", first) is not None, repr(first))
        nxt = [l for l in following(mf, "zzlfm", 3) if l.strip()]
        row("3: the next line holds the type of the second subfile (Dir) and its pathname",
            len(nxt) >= 1 and re.search(r"\bDir\b", nxt[0]) is not None and "sub2" in nxt[0], repr(nxt[:2]))
        row("3: the first subfile's pathname is on the first line, in step with its type",
            first is not None and "sub1" in first, repr(first))
        row("3: Mult appears once", len(re.findall(r"\bMult\b", mf)) == 1, mf[-400:])

        say("\n--- controls: plain files keep their own type ------------------------------------")
        s = sess(box, 'LISTF WITH @ID = "zzlfs" OR WITH @ID = "zzlfd" NO.PAGE')
        ls_, ld_ = line_of(s, "zzlfs"), line_of(s, "zzlfd")
        row("CONTROL: a plain hashed file is DH and not Mult", ls_ is not None and re.search(r"\bDH\b", ls_) and "Mult" not in ls_, repr(ls_))
        row("CONTROL: a plain directory file is Dir and not Mult", ld_ is not None and re.search(r"\bDir\b", ld_) and "Mult" not in ld_, repr(ld_))

        say("\n--- sheet 185: WITH and WITHOUT TRIGGER, ENCRYPTION and REPLICATION ----------------------")
        out = sess(box, "LISTF WITH TRIGGER NO.PAGE")
        row("185: WITH TRIGGER lists the file that has a trigger", line_of(out, "zzlft") is not None, out[-400:])
        row("185: ... and not the one that has none", line_of(out, "zzlfs") is None and line_of(out, "zzlfm") is None, out[-400:])
        t = line_of(out, "zzlft")
        row("185: the type column of the file with the trigger carries T", t is not None and re.search(r"\bDH\b.*\bT\b", t) is not None, repr(t))
        out = sess(box, "LISTF WITHOUT TRIGGER NO.PAGE")
        row("185: WITHOUT TRIGGER lists the files with none", all(line_of(out, n) is not None for n in ("zzlfs", "zzlfd", "zzlfm")), out[-400:])
        row("185: ... and not the one with a trigger", line_of(out, "zzlft") is None, out[-400:])
        for word in ("ENCRYPTION", "REPLICATION"):
            out = sess(box, "LISTF WITH %s NO.PAGE" % word)
            row("185: WITH %s lists none of the files (SD has neither)" % word,
                all(line_of(out, n) is None for n in ("zzlfs", "zzlfd", "zzlft", "zzlfm")), out[-400:])
            out = sess(box, "LISTF WITHOUT %s NO.PAGE" % word)
            row("185: WITHOUT %s lists all of them (so the empty WITH was not a failed clause)" % word,
                all(line_of(out, n) is not None for n in ("zzlfs", "zzlfd", "zzlft", "zzlfm")), out[-400:])

        say("\n--- LISTFL and LISTFR still run, with the widened type column ------------------------")
        out = sess(box, "LISTFL NO.PAGE")
        row("CONTROL: LISTFL lists the local files", line_of(out, "zzlfs") is not None and line_of(out, "zzlfm") is not None, out[-400:])
        out = sess(box, "LISTFR NO.PAGE")
        row("CONTROL: LISTFR runs (the fixtures are local, so none of them is in it)",
            line_of(out, "zzlfs") is None and "error" not in out.lower(), out[-400:])
        out = sess(box, "LISTFL WITH TRIGGER NO.PAGE")
        row("185: LISTFL takes WITH TRIGGER", line_of(out, "zzlft") is not None and line_of(out, "zzlfs") is None, out[-400:])
    finally:
        for nm in made:
            pth = os.path.join(sysd, "bp", nm)
            if os.path.exists(pth):
                os.remove(pth)

    say("\nsandbox-listf-mult: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
