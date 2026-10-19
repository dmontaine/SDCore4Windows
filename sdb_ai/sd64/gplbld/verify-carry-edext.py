#!/usr/bin/env python3
#
# sandbox-edext.py - ED external commands: catalogued subroutines named in $ED.OPTIONS (QM4 Fixes items 305 and 331).  No install,
# no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-edext.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or absent).
# Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.  gpl.bp/ed: EXTERNAL name pattern {pattern ...} in $ED.OPTIONS; external.command.
# END-HISTORY
#
# HOW IT DRIVES ED.  Through a pipe session (sandbox-fromtree.py sess), as sandbox-edbug.py does: ED reads its commands from the lines
# that follow it.  The subroutine zzedx1 is the external command handler: WHERE prints the whole of INFO, DUMP the lines of INFO(3),
# UPCASE changes INFO(3), ADD word appends a line and moves to it, BAD sets ERROR, TOOFAR gives positions outside the record.  zzedx2
# replaces a standard command (B).  The patterns are given in the way the task asks: several, one after another, unquoted
# (WHERE DUMP UPCASE BAD TOOFAR) and a quoted template ("'ADD '0X"; a MATCHES template needs a count in each element, as the editor's own "'.'0A0X" has).  Every verdict is a line the handler prints (X[...], D[...],
# MYB[...]) or the final content of the record, read back by CT after ED has gone.  CONTROLS: ED with no $ED.OPTIONS record says
# WHERE is not a command; a standard command that is not overridden (L) still works with the options in place.

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
    say("sandbox-edext: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds, quiet=False):
    if not quiet:
        say("    > %d lines sent: %s ..." % (len(cmds), " | ".join(cmds[:3])))
    try:
        p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                           capture_output=True, text=True, errors="replace", timeout=180)
    except subprocess.TimeoutExpired:
        # ED waits for an answer the commands did not give and, at the end of the input, asks again for ever.  Say so, end the
        # session, and let the rows that needed its output fail rather than hang the run.
        say("    ! the session did not end in 180 seconds: ED is waiting for an answer the commands did not give")
        subprocess.run(["pkill", "-f", "^" + os.path.join(box, "sys", "bin", "sd")], capture_output=True)
        return "SESSION TIMED OUT"
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def write(path, text):
    with open(path, "wb") as f:
        f.write(text.encode("ascii"))


H1 = """subroutine zzedx1(mat info, err)
   dim info(8)
   cmd = upcase(info(7))
   begin case
      case cmd = 'WHERE'
         crt 'X[file=':info(1):' rec=':info(2):' posn=':info(4):' b1=':info(5):' b2=':info(6):' cmd=':info(7):' ev=':info(8):' lines=':dcount(info(3), @fm):']'
      case cmd = 'DUMP'
         s = ''
         for i = 1 to dcount(info(3), @fm)
            s := field(info(3), @fm, i) : '|'
         next i
         crt 'D[':s:']'
      case cmd = 'UPCASE'
         info(3) = upcase(info(3))
      case cmd[1,4] = 'ADD '
         info(3) = info(3) : @fm : info(7)[5,99]
         info(4) = dcount(info(3), @fm)
      case cmd = 'BAD'
         info(3) = 'CHANGED BUT ERROR WAS SET'
         err = @true
      case cmd = 'TOOFAR'
         info(4) = 999
         info(5) = -3
         info(6) = 999
   end case
   return
end
"""

H2 = """subroutine zzedx2(mat info, err)
   dim info(8)
   crt 'MYB[':info(4):']'
   return
end
"""

VOCW = """   open 'VOC' to v else crt 'V[=NO VOC]' ; stop
   rec = 'X'
   rec<-1> = 'EXTERNAL zzedx1 WHERE DUMP UPCASE BAD TOOFAR ' : '"' : "'" : 'ADD ' : "'" : '0X' : '"'
   rec<-1> = 'EXTERNAL zzedx2 B'
   write rec to v, '$ED.OPTIONS'
   crt 'V[=DONE]'
end
"""
VOCD = """   open 'VOC' to v else crt 'V[=NO VOC]' ; stop
   delete v, '$ED.OPTIONS'
   crt 'V[=GONE]'
end
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-edext.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-edext: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-edext: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []

    def prog(name, text):
        write(os.path.join(bp, name), text)
        made.append(name)

    prog("zzedx1", H1)
    prog("zzedx2", H2)
    prog("zzedvw", VOCW)
    prog("zzedvd", VOCD)
    prog("zzedr", "one\ntwo\nthree\n")

    try:
        out = sess(box, "BASIC bp zzedx1 zzedx2 zzedvw zzedvd", "CATALOG bp zzedx1 LOCAL", "CATALOG bp zzedx2 LOCAL")
        if len(re.findall(r"(?m)^Compiled 4 program\(s\) with no errors", out)) != 1:
            bail("the programs did not compile:\n" + out[-1200:])

        say("\n--- CONTROL: no $ED.OPTIONS record ------------------------------------------------------------------------------")
        # An unrecognised line is followed by "Did you mean to insert this text (y/<n>)?", which loops until it has Y, N or an empty
        # answer: without the N the session never ends (it did not, 16 Oct 26, 20 minutes).
        out = sess(box, "RUN bp zzedvd", "ED bp zzedr", "WHERE", "N", "Q")
        row("CONTROL  without the option WHERE is not an ED command: 'Unrecognised command'", "Unrecognised command" in out and "X[file=" not in out,
            repr(out[-400:]))

        say("\n--- the external commands ----------------------------------------------------------------------------------------")
        cmds = ["RUN bp zzedvw", "ED bp zzedr",
                "WHERE", "2", "where", "UPCASE", "OOPS", "DUMP", "UPCASE", "DUMP", "ADD four", "WHERE", "BAD", "WHERE", "TOOFAR", "WHERE",
                "1", "B", "WHERE", "L", "FI", "CT bp zzedr"]
        out = sess(box, *cmds)
        xs = re.findall(r"(?m)^X\[(.*)\]\s*$", out)
        ds = re.findall(r"(?m)^D\[(.*)\]\s*$", out)
        for x in xs:
            say("      X[%s]" % x)
        for d in ds:
            say("      D[%s]" % d)
        row("the instrument: the options record was written and ED ran the commands", "V[=DONE]" in out and len(xs) >= 6, repr(out[-400:]))
        row("305  WHERE at the top: INFO(1) is the file, INFO(2) the record, positions zero, INFO(7) as typed, three lines",
            xs and xs[0] == "file=bp rec=zzedr posn=0 b1=0 b2=0 cmd=WHERE ev=0 lines=3", repr(xs[:1]))
        row("305  matched in lower case (where), after '2': INFO(4) is 2 and INFO(7) keeps the case it was typed in",
            len(xs) > 1 and xs[1] == "file=bp rec=zzedr posn=2 b1=0 b2=0 cmd=where ev=0 lines=3", repr(xs[1:2]))
        row("305  OOPS undoes an external command (Undoing 'UPCASE'), and the data is as it was", "Undoing 'UPCASE'" in out and ds and ds[0] == "one|two|three|",
            repr(ds[:1]))
        row("305  UPCASE changes INFO(3): the editor takes it", len(ds) > 1 and ds[1] == "ONE|TWO|THREE|", repr(ds[1:2]))
        row("305  ADD four (the quoted template): a line is added and INFO(4) moves the position to it", len(xs) > 2 and "posn=4" in xs[2] and xs[2].endswith("lines=4"),
            repr(xs[2:3]))
        row("305  ERROR set true: the message 'External command zzedx1 failed' and nothing changed (still four lines at 4)",
            "External command zzedx1 failed" in out and len(xs) > 3 and "posn=4" in xs[3] and xs[3].endswith("lines=4"), repr(xs[3:4]))
        row("305  positions outside the record are brought inside: 999 becomes the last line, -3 the top",
            len(xs) > 4 and xs[4].startswith("file=bp rec=zzedr posn=4 b1=0 b2=4 "), repr(xs[4:5]))
        row("305  an external command replaces a standard one: B shows MYB[1], and the position stays at line 1 (the standard B would go to the bottom)",
            "MYB[1]" in out and len(xs) > 5 and "posn=1 " in xs[5], repr(xs[5:6]))
        row("CONTROL  a standard command not overridden still works with the options in place (L shows a line)", re.search(r"(?m)^0001: ONE\s*$", out) is not None,
            repr(out[-300:]))
        # CT numbers its lines.  UPCASE changed the three lines; ADD four appended its text as it was typed, which is lower case.
        ct = out.split(":CT bp zzedr", 1)[-1]
        row("305  the record filed has what the external commands left: ONE TWO THREE in capitals, then four as it was typed",
            all(re.search(r"(?m)^%s\s*$" % s, ct) for s in ("1: ONE", "2: TWO", "3: THREE", "4: four")), repr(ct[-300:]))
        row("331  five patterns written one after another with no quotes, and a quoted template, were all taken (WHERE, DUMP, UPCASE, BAD, TOOFAR, ADD)",
            len(xs) >= 6 and len(ds) >= 2 and "External command zzedx1 failed" in out, repr((len(xs), len(ds))))
    finally:
        sess(box, "RUN bp zzedvd", "DELETE.CATALOG zzedx1 LOCAL", "DELETE.CATALOG zzedx2 LOCAL", quiet=True)
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-edext: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
