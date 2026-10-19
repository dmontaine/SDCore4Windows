#!/usr/bin/env python3
#
# sandbox-getdev.py - the GET statement: data from a device opened by OPENSEQ (QM4 Fixes item 583).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-getdev.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or absent).
# Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.
# END-HISTORY
#
# THE INSTRUMENT.  GET var {, length} {SETTING count} FROM dev {UNTIL term} {RETURNING last} {WAITING timeout} {THEN} {ELSE}.  The
# device is a FIFO the test makes and feeds on a clock (a thread opens the write end and writes, with pauses), opened by an
# internal program with OPENSEQ; a regular file is the second device.  The program prints each result with its characters in hex
# (so a line feed is visible).  The pauses are what make the WAITING rows mean something: a read that is cut short by its timeout
# must come back with STATUS() 0 and the data so far, and one that has time enough must get its data.  THE CONTROLS: a class
# module's GET name() declaration still compiles and works (GET is also that), and GET with no FROM is still the class syntax.
#
#   the writer:  hello\n at once, "world" after 1.2 seconds, "XY\n" after a further 2.5 seconds

import os
import re
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
made = []


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
    say("sandbox-getdev: CANNOT RUN - " + msg)
    sys.exit(2)


def tool(box, *args, **kw):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace",
                          timeout=kw.pop("timeout", 900), **kw)


def isess(box, cmds):
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"), env=env,
                       capture_output=True, text=True, errors="replace", timeout=120)
    out = ANSI.sub("", p.stdout + p.stderr)
    return re.sub(r"\x1b\[[0-9;?]*[A-Za-z]|\[[0-9;]*[A-Za-z]", "", out.split(":TERM 200,9999", 1)[-1])


FIFO_PROG = """$internal
   openseq '%(fifo)s' to f else crt 'R[=OPEN FAILED ':status():']' ; stop
   get a, 3 setting c from f
   crt 'R1[=':a:'/':c:']'
   get b setting c from f until char(10) returning l
   crt 'R2[=':oconv(b, 'MX0C'):'/':c:'/':oconv(l, 'MX0C'):']'
   get d, 5 from f waiting 3 then crt 'R3[=':d:' THEN]' else crt 'R3[=':d:' ELSE]'
   t0 = system(1005)
   get e setting c from f until char(10) waiting 1 then crt 'R4[=THEN]' else crt 'R4[=ELSE status=':status():' got=':c:' e=':e:']'
   t1 = system(1005)
   crt 'R4T[=':(t1 - t0):']'
   get g setting c from f until char(10) returning l waiting 6 then crt 'R5[=THEN ':oconv(g, 'MX0C'):'/':c:'/':oconv(l, 'MX0C'):']' else crt 'R5[=ELSE status=':status():']'
   crt 'RDONE[=1]'
end
"""

FILE_PROG = """$internal
   openseq '%(file)s' to f else crt 'F[=OPEN FAILED ':status():']' ; stop
   get x, 4 from f
   crt 'F1[=':x:']'
   get y from f until 'g'
   crt 'F2[=':y:']'
   get one from f
   crt 'F3[=':oconv(one, 'MX0C'):']'
   get z, 100 setting n from f then crt 'F4[=THEN]' else crt 'F4[=ELSE status=':status():' ':oconv(z, 'MX0C'):'/':n:']'
   crt 'FDONE[=1]'
end
"""

CLASS_PROG = """class zzgcls
   private v = 7
   get thing()
      return v
   end
   public subroutine create.object()
      v = v + 1
   end
end
"""
CLASS_RUN = "   o = object('zzgcls')\n   crt 'C[=':o->thing():']'\nend\n"


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-getdev.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-getdev: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-getdev: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    tool(box, "start", timeout=180)

    fifo = os.path.join(box, "getdev.fifo")
    regfile = os.path.join(box, "getdev.dat")
    for p in (fifo, regfile):
        if os.path.exists(p):
            os.remove(p)
    os.mkfifo(fifo)
    with open(regfile, "wb") as f:
        f.write(b"abcdefgh\nij")

    for nm, text in (("zzgfifo", FIFO_PROG % {"fifo": fifo}), ("zzgfile", FILE_PROG % {"file": regfile}), ("zzgcls", CLASS_PROG),
                     ("zzgcrun", CLASS_RUN)):
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(text)
        made.append(nm)

    def writer():
        fd = os.open(fifo, os.O_WRONLY)         # waits for the program to open the read end
        try:
            os.write(fd, b"hello\n")
            time.sleep(1.2)
            os.write(fd, b"world")
            time.sleep(2.5)
            os.write(fd, b"XY\n")
            time.sleep(0.5)
        finally:
            os.close(fd)

    def tag(out, t):
        m = re.search(r"(?m)^%s\[=(.*)\]\s*$" % t, out)
        return m.group(1) if m else None

    try:
        out = isess(box, ["BASIC bp zzgfifo zzgfile zzgcls zzgcrun"])
        n = len(re.findall(r"(?m)^Compiled 4 program\(s\) with no errors", out))
        if n != 1:
            bail("the programs did not compile:\n" + out[-1500:])

        say("\n--- a FIFO fed on a clock (hello\\n; world 1.2 s later; XY\\n 2.5 s after that) -------------------------------")
        th = threading.Thread(target=writer)
        th.start()
        out = isess(box, ["RUN bp zzgfifo"])
        th.join()
        row("the instrument: the program opened the FIFO and ran to the end", tag(out, "RDONE") == "1", repr(out[-400:]))
        row("583  GET a, 3 SETTING c: three characters, counted", tag(out, "R1") == "hel/3", repr(tag(out, "R1")))
        row("583  UNTIL char(10) RETURNING l: reads up to and including the terminator, which is also what last holds",
            tag(out, "R2") == "6C6F0A/3/0A", repr(tag(out, "R2")))
        row("583  WAITING 3 with the data due in 1.2 seconds: the data, THEN", tag(out, "R3") == "world THEN", repr(tag(out, "R3")))
        r4 = tag(out, "R4") or ""
        row("583  WAITING 1 with nothing due for 2.5 seconds: ELSE, STATUS() 0 (a timeout), nothing read", r4 == "ELSE status=0 got=0 e=", repr(r4))
        t = tag(out, "R4T")
        row("...and it waited about the second asked for (not 0, not 2.5)", t is not None and re.fullmatch(r"\d+", t) is not None
            and 1 <= int(t) <= 2, "seconds: %r" % t)
        row("583  the data that came later is still there to read: XY\\n, 3 characters, last LF",
            tag(out, "R5") == "THEN 58590A/3/0A", repr(tag(out, "R5")))

        say("\n--- an ordinary file ------------------------------------------------------------------------------------")
        out = isess(box, ["RUN bp zzgfile"])
        row("the instrument: the program ran to the end", tag(out, "FDONE") == "1", repr(out[-400:]))
        row("583  GET x, 4 from a file", tag(out, "F1") == "abcd", repr(tag(out, "F1")))
        row("583  UNTIL 'g' with no length reads on to the terminator, which it includes", tag(out, "F2") == "efg", repr(tag(out, "F2")))
        row("583  no length and no UNTIL: one character", tag(out, "F3") == "68", repr(tag(out, "F3")))
        row("583  the end of the data before length: ELSE, STATUS() not 0, and what there was is in the variable and counted",
            (tag(out, "F4") or "").startswith("ELSE status=") and (tag(out, "F4") or "").endswith("0A696A/3")
            and not (tag(out, "F4") or "").startswith("ELSE status=0 "), repr(tag(out, "F4")))

        say("\n--- CONTROL: GET is also the class module's name for a public function ---------------------------------------")
        out = isess(box, ["CATALOG bp zzgcls LOCAL", "RUN bp zzgcrun"])
        row("CONTROL  GET thing() in a class compiles and works as before", tag(out, "C") == "8", repr(out[-300:]))
    finally:
        for p in (fifo, regfile):
            if os.path.exists(p):
                os.remove(p)
        for nm in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-getdev: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
