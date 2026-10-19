#!/usr/bin/env python3
#
# sandbox-fix-b10.py - 1.2-0 bundle B-10, small defects and two that were already true:
#                        590  CLEAR.FILE keeps the modulus of a NO.RESIZE file
#                        349  LIST.ITEM numbers lines beyond 999 with as many digits as they need
#                        347  CT opens a file named in lower case          (already true)
#                        249  SOCKET.INFO(var, SKT$INFO.OPEN) on a non-socket (already true)
#                        203  NO.SOURCE.WARNING in the VOC record $DEBUG.OPTIONS silences "unable to find source"
#                        545  xmc#1 in the terminfo entries adds4000 and adds4000-at
#                      No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-fix-b10.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 12 Oct 26 dm  Written for 1.2-0 bundle B-10: sheet 590, 349, 347, 249, 203 and 545.
# END-HISTORY
#
# THE INSTRUMENT.  Programs run in a private SD; what they print is read from the session output, every pattern
# anchored to the start of a line.  Every row has a control beside it.  For 203 the program is compiled for the
# debugger, its source record is then deleted, and it is run twice - without and with the $DEBUG.OPTIONS record -
# so that the message can only be missing because of the option.  THE SANDBOX MUST BE BUILT FROM THE TREE UNDER TEST:
# a stale one answered "no message" to both runs once and looked like a pass.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
TERMINFO = os.path.join(os.path.dirname(HERE), "terminfo.src")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
made = []

PROGS = {
    "zzb10cl": ("$include keys.h\n"
                "   for t = 1 to 2\n      nm = 'zzcl':t\n      execute 'DELETE.FILE ':nm capturing j\n"
                "      execute 'CREATE.FILE ':nm:' DYNAMIC MINIMUM.MODULUS 3' capturing j\n"
                "      open nm to f else stop 'no f'\n      for i = 1 to 3000\n         write str('x', 100) on f, i\n      next i\n"
                "      crt 'M':t:'[':fileinfo(f, FL$MODULUS):']'\n      close f\n   next t\n"
                "   execute 'CONFIGURE.FILE zzcl1 NO.RESIZE' capturing j\n"
                "   for t = 1 to 2\n      nm = 'zzcl':t\n      open nm to f else stop 'no f'\n"
                "      crt 'B':t:'[':fileinfo(f, FL$MODULUS):' ':fileinfo(f, FL$NO.RESIZE):']'\n      close f\n"
                "      execute 'CLEAR.FILE ':nm capturing j\n      open nm to f else stop 'no f'\n"
                "      crt 'A':t:'[':fileinfo(f, FL$MODULUS):']'\n"
                "      read z from f, 1 then crt 'R':t:'[present]' else crt 'R':t:'[empty]'\n      close f\n   next t\n"
                "   crt 'DONE590'\nend\n"),
    "zzb10li": ("   execute 'DELETE.FILE zzli' capturing j\n   execute 'CREATE.FILE zzli' capturing j\n"
                "   open 'zzli' to f else stop 'no f'\n   big = ''\n   for i = 1 to 1200 ; big<i> = 'line':i ; next i\n"
                "   write big on f, 'big'\n   write 'a':@fm:'b':@fm:'c' on f, 'small'\n   write 'cat':@fm:'dog' on f, 'zzct'\n"
                "   execute 'LIST.ITEM zzli big NO.PAGE' capturing out\n"
                "   for i = 1 to dcount(out, @am)\n"
                "      if out<i>[1,5] = '0001:' then crt 'ONE[':out<i>:']'\n"
                "      if out<i>[1,5] = '1000:' then crt 'THOU[':out<i>:']'\n"
                "      if out<i>[1,5] = '1200:' then crt 'LAST[':out<i>:']'\n"
                "      if out<i>[1,4] = '999:' or out<i>[1,5] = '0999:' then crt 'NINE[':out<i>:']'\n"
                "   next i\n"
                "   execute 'LIST.ITEM zzli small NO.PAGE' capturing out\n"
                "   for i = 1 to dcount(out, @am)\n      if out<i>[1,4] = '001:' then crt 'SMALL1[':out<i>:']'\n   next i\n"
                "   execute 'CT zzli zzct' capturing out\n   crt 'CT[':change(out, @am, '|'):']'\n"
                "   crt 'DONE349'\nend\n"),
    "zzb10sk": ("$include keys.h\n   x = 7 ; y = 'str'\n"
                "   crt 'OX[':socket.info(x, SKT$INFO.OPEN):']'\n   crt 'OY[':socket.info(y, SKT$INFO.OPEN):']'\n"
                "   crt 'OZ[':socket.info(zz, SKT$INFO.OPEN):']'\n   crt 'DONE249'\nend\n"),
    "zzb10op": ("   write 'NO.SOURCE.WARNING' on @voc, '$debug.options'\n   crt 'OPTSET'\nend\n"),
    "zzb10nop": ("   delete @voc, '$debug.options'\n   crt 'OPTGONE'\nend\n"),
}
DBGPROG = "zzb10dbg"
DBGSRC = "   x = 5\n   debug\n   crt 'AFTER DEBUG x=':x\nend\n"


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
    say("sandbox-fix-b10: CANNOT RUN - " + msg)
    sys.exit(2)


def tool(box, *args, **kw):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace",
                          timeout=kw.pop("timeout", 900), **kw)


def sess(box, *cmds):
    say("    > %s" % " | ".join(c if len(c) < 60 else c[:57] + "..." for c in cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def tagged(out, tag):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % tag, out)
    return m.group(1) if m else None


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-fix-b10.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-fix-b10: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-fix-b10: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)

    try:
        tool(box, "start", timeout=180)
        cmds = []
        for nm, text in PROGS.items():
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write(text)
            made.append(nm)
            cmds.append("BASIC bp %s" % nm)
        out = sess(box, *cmds)
        n = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        if n != len(PROGS):
            bail("%d of %d programs compiled:\n%s" % (n, len(PROGS), out[-1500:]))

        say("\n--- 590 CLEAR.FILE and NO.RESIZE ---------------------------------------------------")
        out = sess(box, "RUN bp zzb10cl")
        say("    %s" % {t: tagged(out, t) for t in ("M1", "M2", "B1", "B2", "A1", "A2", "R1", "R2")})
        m1 = tagged(out, "M1")
        row("CONTROL: a 3000 record file grew beyond its minimum modulus of 3 (M1 %s)" % m1,
            m1 is not None and m1.isdigit() and int(m1) > 3, out[-300:])
        row("590: the NO.RESIZE file is flagged (B1 ends with 1)", (tagged(out, "B1") or "").endswith(" 1"), "got %r" % tagged(out, "B1"))
        row("590: ... and after CLEAR.FILE keeps the modulus it had", m1 is not None and tagged(out, "A1") == m1,
            "was %r, now %r" % (m1, tagged(out, "A1")))
        row("CONTROL: the file without NO.RESIZE goes back to the minimum modulus, 3", tagged(out, "A2") == "3", "got %r" % tagged(out, "A2"))
        row("590: both files are empty afterwards", tagged(out, "R1") == "empty" and tagged(out, "R2") == "empty", out[-200:])

        say("\n--- 349 LIST.ITEM beyond 999 lines, 347 CT, 249 SOCKET.INFO -----------------------------")
        out = sess(box, "RUN bp zzb10li")
        row("349: line 1 of a 1200 line item is 0001 (four digits)", tagged(out, "ONE") == "0001: line1", "got %r" % tagged(out, "ONE"))
        row("349: line 1000 is 1000", tagged(out, "THOU") == "1000: line1000", "got %r" % tagged(out, "THOU"))
        row("349: line 1200 is 1200", tagged(out, "LAST") == "1200: line1200", "got %r" % tagged(out, "LAST"))
        row("CONTROL: a 3 line item still numbers its lines with three digits (001)", tagged(out, "SMALL1") == "001: a", "got %r" % tagged(out, "SMALL1"))
        row("347: CT opens a file named in lower case and shows the record", tagged(out, "CT") == "zzli zzct|1: cat|2: dog", "got %r" % tagged(out, "CT"))
        out = sess(box, "RUN bp zzb10sk")
        row("249: SOCKET.INFO(.., SKT$INFO.OPEN) of a number, a string and an unassigned variable is 0, no abort",
            tagged(out, "OX") == "0" and tagged(out, "OY") == "0" and tagged(out, "OZ") == "0" and "DONE249" in out, out[-300:])

        say("\n--- 203 NO.SOURCE.WARNING in $DEBUG.OPTIONS ---------------------------------------------")
        with open(os.path.join(sysd, "bp", DBGPROG), "w") as f:
            f.write(DBGSRC)
        made.append(DBGPROG)
        sess(box, "RUN bp zzb10nop")
        out = sess(box, "BASIC bp %s DEBUGGING" % DBGPROG)
        if "Compiled 1 program(s) with no errors" not in out:
            bail("the debug program did not compile:\n" + out[-400:])
        os.remove(os.path.join(sysd, "bp", DBGPROG))
        out = sess(box, "RUN bp %s" % DBGPROG)
        row("203: CONTROL: with its source gone and no option the debugger says it cannot find the source",
            re.search(r"(?m)^\x07?Unable to find source record .*%s\s*$" % DBGPROG, out) is not None, out[-300:])
        row("203: ... and the program carries on (not stopped by the debugger)", re.search(r"(?m)^AFTER DEBUG x=5\s*$", out) is not None, out[-300:])
        sess(box, "RUN bp zzb10op")
        out = sess(box, "RUN bp %s" % DBGPROG)
        row("203: with NO.SOURCE.WARNING in the VOC record $debug.options the message is not shown",
            "Unable to find source" not in out, out[-300:])
        row("203: ... and the program still carries on", re.search(r"(?m)^AFTER DEBUG x=5\s*$", out) is not None, out[-300:])
        sess(box, "RUN bp zzb10nop")
        out = sess(box, "RUN bp %s" % DBGPROG)
        row("203: CONTROL: with the record removed again the message is back",
            re.search(r"(?m)^\x07?Unable to find source record ", out) is not None, out[-300:])

        say("\n--- 545 terminfo adds4000 ----------------------------------------------------------")
        text = open(TERMINFO, errors="replace").read()
        for name in ("adds4000", "adds4000-at"):
            m = re.search(r"(?ms)^%s\|.*?(?=^\S)" % re.escape(name), text)
            row("545: the %s entry has xmc#1" % name, m is not None and re.search(r"\bxmc#1\b", m.group(0)) is not None,
                "no entry" if m is None else "xmc#1 missing")
        row("CONTROL: another entry already carrying xmc#1 is found by the same test",
            re.search(r"(?ms)^\S+\|.*?\bxmc#1\b", text) is not None)
    finally:
        tool(box, "stop", timeout=120)
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-fix-b10: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
