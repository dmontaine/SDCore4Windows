#!/usr/bin/env python3
#
# sandbox-akcase.py - index maintenance must use the record id AS STORED, not an upper-cased copy.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-akcase.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built, which is how the same script is run against an OLD tree to prove
# it can fail.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for the "upper case id" fault found in part 32 (PROJECT_STATUS, 1.2-0 second sitting):
#               dh_write.c and dh_del.c gave the index routine (_ak) the record id UPPER-CASED on every NOCASE file, and
#               since D2 (7 Oct) every hashed file is NOCASE.  BUILD.INDEX stores the id as it is stored (lower case in
#               this system), so a new record was indexed as R4, a delete of r3 left r3 in the index, and a changed
#               record was taken out of nothing and put in under a second spelling.  The Windows port has the same code.
# END-HISTORY
#
# WHAT IT MEASURES.  A file zzak<run> with one D-type index (CITY, field 1).  Three records are written with lower
# case ids and the index is BUILT (so it holds the stored spelling), then, one step at a time, with the lists the
# index gives for each city printed after every step (SELECTINDEX, the index's own answer):
#   S1 a new record          S2 a delete           S3 a change under the same spelling
#   S4 a change under ANOTHER spelling of the id, same record size (the record is rewritten in place)
#   S5 a change under another spelling, larger (the record is deleted and added again)
# and finally the ids the file itself holds, and the lists after a BUILD.INDEX, which must equal S5's: an index kept
# up to date by writes must say what an index built from the file says.
# S5 also settles a second thing the index forced: the spelling an id is STORED in.  dh_write.c added a record again,
# after a size change, under the spelling the writer happened to use, so the stored id (and what SELECT lists)
# changed with the size of the data; the first spelling now stays.
#
# THE INSTRUMENT IS WHAT THE PROGRAM PRINTED between brackets.  Lists are compared as sorted sets (the order inside
# an index entry is not the point) and CASE SENSITIVELY.  Row S0 is the control that the fixture and the printing
# work at all; if it is not as expected the run stops with exit 2 and no verdict.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
F = "zzak" + RUN
PW, PS, PR = "zzakw" + RUN, "zzaks" + RUN, "zzakr" + RUN
VALS = ["Paris", "Rome", "Oslo", "Copenhagen"]
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
    say("sandbox-akcase: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


SHOW = """show:
   x = ''
   for i = 1 to %d
      v = vals<i>
      selectindex 'CITY', v from f to 5
      readlist l from 5 else l = ''
      x := v:'=':change(l, @fm, ','):';'
   next i
   return
""" % len(VALS)

VALS_LINE = "   vals = " + ":@fm:".join("'%s'" % v for v in VALS) + "\n"


def prog_setup():
    return ("   open '%s' to f else stop 'no file'\n   open 'DICT %s' to d else stop 'no dict'\n"
            "   write 'D':@fm:'1':@fm:'':@fm:'City':@fm:'12L':@fm:'S' on d, 'CITY'\n"
            "   write 'Paris' on f, 'r1'\n   write 'Rome' on f, 'r2'\n   write 'Paris' on f, 'r3'\nend\n" % (F, F))


def prog_steps():
    out = "   open '%s' to f else stop 'no file'\n" % F + VALS_LINE
    out += "   gosub show ; crt 'S0[':x:']'\n"
    out += "   write 'Paris' on f, 'r4'\n   gosub show ; crt 'S1[':x:']'\n"
    out += "   delete f, 'r3'\n   gosub show ; crt 'S2[':x:']'\n"
    out += "   write 'Rome' on f, 'r1'\n   gosub show ; crt 'S3[':x:']'\n"
    out += "   write 'Oslo' on f, 'R2'\n   gosub show ; crt 'S4[':x:']'\n"
    out += "   write 'Copenhagen' on f, 'R2'\n   gosub show ; crt 'S5[':x:']'\n"
    out += "   select f to 6\n   readlist ids from 6 else ids = ''\n   crt 'IDS[':change(ids, @fm, ','):']'\n"
    out += "   stop\n" + SHOW + "end\n"
    return out


def prog_read():
    return ("   open '%s' to f else stop 'no file'\n" % F + VALS_LINE
            + "   gosub show ; crt 'RB[':x:']'\n   stop\n" + SHOW + "end\n")


def parse(text, tag):
    """{city: sorted ids} from 'tag[Paris=r1,r3;Rome=...;]', or None when the line is not there."""
    m = re.search(r"(?m)^" + tag + r"\[(.*)\]\s*$", text)
    if not m:
        return None
    d = {}
    for part in m.group(1).split(";"):
        if "=" in part:
            k, v = part.split("=", 1)
            d[k] = sorted(i for i in v.split(",") if i)
    return d


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-akcase.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-akcase: sandbox %s" % box)
    say("sandbox-akcase: tree    %s" % os.path.dirname(HERE))
    say("sandbox-akcase: file    %s, programs %s %s %s" % (F, PW, PS, PR))
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-akcase: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    names = (PW, PS, PR)
    for nm, body in ((PW, prog_setup()), (PS, prog_steps()), (PR, prog_read())):
        with open(os.path.join(sysd, "bp", nm), "w") as fh:
            fh.write(body)
    try:
        say("\n--- the fixture: a file, a D-type item on field 1, three records, an index BUILT from them --------")
        out = sess(box, "DELETE.FILE %s" % F, "CREATE.FILE %s" % F, "BASIC bp %s" % PW, "BASIC bp %s" % PS, "BASIC bp %s" % PR)
        clean = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        row("setup: the three programs compiled with no errors", clean == 3, "clean compiles: %d of 3" % clean)
        if clean != 3:
            bail("the programs did not compile - nothing below would read an index:\n" + out[-600:])
        out = sess(box, "RUN bp %s" % PW, "CREATE.INDEX %s CITY" % F, "BUILD.INDEX %s CITY" % F, "LIST.INDEX %s" % F)
        row("setup: the index exists (LIST.INDEX names CITY)", re.search(r"CITY", out) is not None, out[-300:])
        say("\n--- the steps, each followed by what the index says -----------------------------------------------")
        out = sess(box, "RUN bp %s" % PS)
        s = {t: parse(out, t) for t in ("S0", "S1", "S2", "S3", "S4", "S5")}
        m = re.search(r"(?m)^IDS\[(.*)\]\s*$", out)
        ids = sorted(i for i in m.group(1).split(",") if i) if m else None
        for t in ("S0", "S1", "S2", "S3", "S4", "S5"):
            say("    %s %s" % (t, s[t]))
        say("    IDS %s" % ids)
        if s["S0"] != {"Paris": ["r1", "r3"], "Rome": ["r2"], "Oslo": [], "Copenhagen": []}:
            bail("the control step S0 is not what BUILD.INDEX of three lower case ids must give - the fixture or the "
                 "printing is wrong, so no verdict would mean anything:\n" + out[-600:])
        row("S0 (control): an index BUILT from the file holds the ids as stored, lower case", True)

        def want(tag, paris, rome, oslo, cph):
            return s[tag] == {"Paris": paris, "Rome": rome, "Oslo": oslo, "Copenhagen": cph}

        row("S1: a new record r4 is indexed under r4 (not R4)", want("S1", ["r1", "r3", "r4"], ["r2"], [], []), repr(s["S1"]))
        row("S2: deleting r3 takes r3 out of the index", want("S2", ["r1", "r4"], ["r2"], [], []), repr(s["S2"]))
        row("S3: changing r1 from Paris to Rome moves r1 (out of Paris, into Rome)",
            want("S3", ["r4"], ["r1", "r2"], [], []), repr(s["S3"]))
        row("S4: writing r2 under the spelling R2, same size (in place), moves the stored r2",
            want("S4", ["r4"], ["r1"], ["r2"], []), repr(s["S4"]))
        row("S5: writing it under R2 again, larger (deleted and added again), moves the stored r2",
            want("S5", ["r4"], ["r1"], [], ["r2"]), repr(s["S5"]))
        row("the file holds r1, r2, r4: the FIRST spelling of an id stays through a rewrite under another",
            ids == ["r1", "r2", "r4"], repr(ids))
        out = sess(box, "BUILD.INDEX %s CITY" % F, "RUN bp %s" % PR)
        rb = parse(out, "RB")
        say("    RB %s" % rb)
        row("an index kept up to date by the writes says what an index built from the file says",
            rb is not None and rb == s["S5"], "maintained %r, rebuilt %r" % (s["S5"], rb))
    finally:
        say("\n--- cleanup -------------------------------------------------------------------------------------")
        sess(box, "DELETE.FILE %s" % F)
        for nm in names:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        left = [n for n in (F,) if any(os.path.exists(os.path.join(box, d, n)) for d in ("sys", "user_accounts"))]
        row("cleanup: the fixture file is gone", not left, " ".join(left))

    say("\nsandbox-akcase: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
