#!/usr/bin/env python3
#
# sandbox-wdthenelse.py - $MODE WRITE.DELETE.THEN.ELSE (openQM 4, sheet 368 and 496).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-wdthenelse.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
# The kernel changed (op_dio3.c: P_THEN_ELSE), so --build must be from a tree that has been made.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  Under the mode WRITE, WRITEU, DELETE, DELETEU, MATWRITE and MATWRITEU take THEN / ELSE after any
#               ON ERROR clause; a trigger function's failure takes ELSE (and not ON ERROR), and the trigger's ON.ERROR
#               argument is true.  A statement with no THEN / ELSE behaves exactly as without the mode.
# END-HISTORY
#
# The verdicts are lines the programs print: the branch taken for each statement, the trigger's own report of the
# on.error argument it was given, and STATUS().  The CONTROLS: the mode off (the clause is a compile error, ON ERROR
# is what runs, the trigger is given on.error false and a refusal with no ON ERROR stops the program), and the mode on
# with no clause (the same stop, on.error false).

import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
RUN = "%05d" % (os.getpid() % 100000)
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
    say("sandbox-wdthenelse: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def has(out, text):
    return re.search(r"(?m)^" + re.escape(text) + r"\s*$", out) is not None


F, TS = "zzwdf" + RUN, "zzwdt" + RUN
P_ON, P_ALLOWED_OFF, P_CTRL_OFF, P_NOCLAUSE = ("zzwdon" + RUN, "zzwdoff" + RUN, "zzwdbad" + RUN, "zzwdnc" + RUN)

# The trigger refuses a record whose id starts 'bad' on a pre-write (mode 1) or a pre-delete (mode 2), and says what it
# was given.  The arguments are (mode, id, record, on error).
TRIGGER = """subroutine %(ts)s(mode, id, rec, onerr)
   crt 'TRG mode=':mode:' id=':id:' onerr=':onerr
   if (mode = 1 or mode = 2) and id[1,3] = 'bad' then @trigger.return.code = 7
   return
end
""" % {"ts": TS}

BODY_ON = """   open '%(f)s' to f else crt 'X not open' ; stop
   dim m(2)
   m(1) = 'a' ; m(2) = 'b'
   write 'x' to f, 'good1' then crt 'W1 then' else crt 'W1 else'
   write 'x' to f, 'bad1' then crt 'W2 then' else crt 'W2 else st=':status()
   write 'x' to f, 'bad2' on error crt 'W3 onerror' then crt 'W3 then' else crt 'W3 else'
   write 'x' to f, 'bad3' else crt 'W4 else'
   write 'x' to f, 'good2' then crt 'W5 then'
   write 'x' to f, 'bad4' on error crt 'W6 onerror'
   delete f, 'good1' then crt 'D1 then' else crt 'D1 else'
   delete f, 'bad5' then crt 'D2 then' else crt 'D2 else st=':status()
   delete f, 'bad6' on error crt 'D3 onerror' else crt 'D3 else'
   matwrite m on f, 'bad7' then crt 'M1 then' else crt 'M1 else'
   matwrite m on f, 'good3' then crt 'M2 then' else crt 'M2 else'
   writeu 'x' on f, 'bad8' else crt 'U1 else'
   release f, 'bad8'
   matwriteu m on f, 'bad9' then crt 'U2 then' else crt 'U2 else'
   release f, 'bad9'
   readu r from f, 'bad10' else r = ''
   deleteu f, 'bad10' then crt 'U3 then' else crt 'U3 else'
   write 'x' to f, 'bad11' else
      crt 'B1 else-block'
   end
   write 'x' to f, 'good4' then
      crt 'B2 then-block'
   end else
      crt 'B2 else-block'
   end
   if 1 then
      write 'x' to f, 'good5' else crt 'N1 else'
   end
   crt 'END-OF-RUN'
end
"""

BODY_OFF = """   open '%(f)s' to f else crt 'X not open' ; stop
   write 'x' to f, 'bad4' on error crt 'C1 onerror st=':status()
   write 'x' to f, 'good9' on error crt 'C2 onerror'
   crt 'END-OF-RUN'
end
"""

BODY_ELSE_OFF = """   open '%(f)s' to f else crt 'X not open' ; stop
   write 'x' to f, 'bad4' else crt 'C3 else'
   crt 'END-OF-RUN'
end
"""

BODY_NOCLAUSE = """   open '%(f)s' to f else crt 'X not open' ; stop
   write 'x' to f, 'good8'
   crt 'N2 good write done'
   write 'x' to f, 'badn'
   crt 'NOT-REACHED'
end
"""


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-wdthenelse.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-wdthenelse: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-wdthenelse: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    progs = {
        TS: TRIGGER,
        P_ON: "$mode write.delete.then.else\n" + BODY_ON % {"f": F},
        P_ALLOWED_OFF: BODY_OFF % {"f": F},
        P_CTRL_OFF: BODY_ELSE_OFF % {"f": F},
        P_NOCLAUSE: "$mode write.delete.then.else\n" + BODY_NOCLAUSE % {"f": F},
    }
    for name, text in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(text)

    try:
        say("\n--- setup ---------------------------------------------------------------------------------------")
        out = sess(box, "CREATE.FILE %s" % F, "BASIC bp %s" % TS, "CATALOG bp %s LOCAL" % TS,
                   "SET.TRIGGER %s %s ALL" % (F, TS),
                   "BASIC bp %s" % P_ON, "BASIC bp %s" % P_ALLOWED_OFF, "BASIC bp %s" % P_NOCLAUSE)
        clean = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        # the trigger, the mode-on program, the mode-off ON ERROR program and the mode-on no-clause program compile
        row("setup: the trigger and the three programs that should compile did, and the trigger is set on the file",
            clean == 4 and ("%s added to local catalogue" % TS) in out, out[-700:])
        if clean != 4:
            bail("the fixture did not compile as expected:\n" + out[-700:])
        out = sess(box, "BASIC bp %s" % P_CTRL_OFF)
        row("CONTROL, the mode off: WRITE ... ELSE is a compile error (the clause is not taken)",
            "Compiled 1 program(s) with no errors" not in out and re.search(r"(?mi)(error|expected)", out) is not None,
            out[-500:])

        say("\n--- the mode on --------------------------------------------------------------------------------")
        out = sess(box, "RUN bp %s" % P_ON)
        row("a good WRITE takes THEN, and its trigger is given on.error true", has(out, "W1 then")
            and has(out, "TRG mode=1 id=good1 onerr=1"), out[-900:])
        row("a trigger failure takes ELSE, and STATUS() is 3022", has(out, "W2 else st=3022"), out[-900:])
        row("WITH an ON ERROR clause as well, a trigger failure takes ELSE and not ON ERROR",
            has(out, "W3 else") and not has(out, "W3 onerror") and not has(out, "W3 then"), out[-900:])
        row("ELSE alone, and THEN alone, are accepted", has(out, "W4 else") and has(out, "W5 then"), out[-900:])
        row("a statement with ON ERROR and no THEN / ELSE still runs ON ERROR on a trigger failure, with on.error true",
            has(out, "W6 onerror") and has(out, "TRG mode=1 id=bad4 onerr=1"), out[-900:])
        row("DELETE: a good record takes THEN, a refused one takes ELSE with STATUS() 3022",
            has(out, "D1 then") and has(out, "D2 else st=3022") and has(out, "TRG mode=2 id=bad5 onerr=1"), out[-900:])
        row("DELETE with ON ERROR and ELSE: ELSE", has(out, "D3 else") and not has(out, "D3 onerror"), out[-900:])
        row("MATWRITE: a refusal takes ELSE, a good record THEN", has(out, "M1 else") and has(out, "M2 then"), out[-900:])
        row("WRITEU, MATWRITEU and DELETEU take the clause", has(out, "U1 else") and has(out, "U2 else")
            and has(out, "U3 else"), out[-900:])
        row("multi-line THEN ... END ELSE ... END and ELSE ... END blocks",
            has(out, "B1 else-block") and has(out, "B2 then-block") and not has(out, "B2 else-block"), out[-900:])
        row("a WRITE ... ELSE inside an IF block does not take the IF's ELSE", has(out, "TRG mode=1 id=good5 onerr=1")
            and not has(out, "N1 else"), out[-900:])
        row("the program reached its end (nothing aborted)", has(out, "END-OF-RUN") and "Data validation error" not in out,
            out[-900:])

        say("\n--- controls -----------------------------------------------------------------------------------")
        out = sess(box, "RUN bp %s" % P_ALLOWED_OFF)
        row("CONTROL, the mode off: ON ERROR runs, with on.error true, and the good write is untouched",
            has(out, "C1 onerror st=3022") and has(out, "TRG mode=1 id=bad4 onerr=1")
            and has(out, "TRG mode=1 id=good9 onerr=1") and not has(out, "C2 onerror") and has(out, "END-OF-RUN"), out[-700:])
        out = sess(box, "RUN bp %s" % P_NOCLAUSE)
        row("CONTROL, the mode on and no THEN / ELSE: a good write has on.error false",
            has(out, "TRG mode=1 id=good8 onerr=0") and has(out, "N2 good write done"), out[-700:])
        row("...and a refusal with no ON ERROR and no clause stops the program as it always did",
            "Data validation error" in out and not has(out, "NOT-REACHED"), out[-700:])
    finally:
        say("\n--- cleanup ---------------------------------------------------------------------------------------")
        sess(box, "DELETE.FILE %s" % F, "DELETE.CATALOG %s LOCAL" % TS)
        for nm in (TS, P_ON, P_ALLOWED_OFF, P_CTRL_OFF, P_NOCLAUSE):
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    shutil.rmtree(pth) if os.path.isdir(pth) else os.remove(pth)

    say("")
    say("sandbox-wdthenelse: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
