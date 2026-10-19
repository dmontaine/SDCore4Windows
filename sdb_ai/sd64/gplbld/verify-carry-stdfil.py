#!/usr/bin/env python3
#
# sandbox-stdfil.py - $MODE STDFIL, the default file variable (openQM 4, sheet item 17).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-stdfil.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  bcomp (stdfil.var.load, stdfil.no.operand, stdfil.fvar.test) compiles the file-variable-less
#               forms of OPEN, READ, MATREAD, WRITE, MATWRITE, DELETE, CLOSE, CLEARFILE, FILELOCK, FILEUNLOCK,
#               RELEASE and SELECT against a hidden variable under the mode.  Compiler only: no kernel change.
# END-HISTORY
#
# Every verdict is anchored on a word the program prints only on the path it names.  Not run when written: the
# first run is expected to show which rows need adjusting.

import os
import re
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
    say("sandbox-stdfil: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def shared_rows(box, sysd):
    """$MODE STDFIL.SHARED (16 Oct 26, QM4 gap 225): @STDFIL is one variable for every program of a command level; an
    EXECUTE starts a level with a fresh one and gets its own back.  The controls are $MODE STDFIL (a variable per program)
    and the two modes together (STDFIL wins)."""
    fa, fb = "zzsa" + RUN, "zzsb" + RUN
    sub, lsub, inner, setup, msh, mloc, mboth, mexe = ("zzsh%s%s" % (RUN, c) for c in "sltimcbe")

    progs = {
        setup: """   open '%(a)s' to f else stop
   write 'FROMA' to f, 'k1'
   open '%(b)s' to g else stop
   write 'FROMB' to g, 'k1'
end
""" % {"a": fa, "b": fb},
        sub: ("$mode stdfil.shared\n   subroutine %s(what, id)\n   begin case\n   case what = 'READ'\n"
              "      read r from id then crt 'SUBREAD ':r else crt 'SUBREAD-MISSING'\n   case what = 'OPENB'\n"
              "      open '%s' else crt 'SUBOPEN-FAILED'\n   end case\n   return\nend\n") % (sub, fb),
        lsub: ("$mode stdfil\n   subroutine %s(what, id)\n   begin case\n   case what = 'READ'\n"
               "      read r from id then crt 'SUBREAD ':r else crt 'SUBREAD-MISSING'\n   case what = 'OPENB'\n"
               "      open '%s' else crt 'SUBOPEN-FAILED'\n   end case\n   return\nend\n") % (lsub, fb),
        inner: ("$mode stdfil.shared\n   if @stdfil = 0 then crt 'INNER-FRESH' else crt 'INNER-NOT-FRESH'\n"
                "   open '%s' else crt 'INNER-OPEN-FAILED' ; stop\n   read r from 'k1' then crt 'INNER-READ ':r else crt 'INNER-MISSING'\nend\n") % fb,
        msh: ("$mode stdfil.shared\n   open '%(a)s' else crt 'OPEN-FAILED' ; stop\n   call %(s)s('READ', 'k1')\n"
              "   call %(s)s('OPENB', '')\n   read r from 'k1' then crt 'AFTER-SUB ':r else crt 'AFTER-SUB-MISSING'\nend\n") % {"a": fa, "s": sub},
        mexe: ("$mode stdfil.shared\n   open '%(a)s' else crt 'OPEN-FAILED' ; stop\n   execute 'RUN bp %(i)s'\n"
               "   read r from 'k1' then crt 'AFTER-EXEC ':r else crt 'AFTER-EXEC-MISSING'\nend\n") % {"a": fa, "i": inner},
        mloc: ("$mode stdfil\n   open '%(a)s' else crt 'OPEN-FAILED' ; stop\n   call %(s)s('OPENB', '')\n"
               "   read r from 'k1' then crt 'LOCAL-AFTER-SUB ':r else crt 'LOCAL-AFTER-SUB-MISSING'\nend\n") % {"a": fa, "s": lsub},
        mboth: ("$mode stdfil.shared, stdfil\n   open '%(a)s' else crt 'OPEN-FAILED' ; stop\n   call %(s)s('OPENB', '')\n"
                "   read r from 'k1' then crt 'BOTH-AFTER-SUB ':r else crt 'BOTH-AFTER-SUB-MISSING'\nend\n") % {"a": fa, "s": sub},
    }
    for name, body in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(body)

    say("\n--- $MODE STDFIL.SHARED ----------------------------------------------------------------------------------")
    names = list(progs)
    out = sess(box, "DELETE.FILE %s" % fa, "DELETE.FILE %s" % fb, "CREATE.FILE %s" % fa, "CREATE.FILE %s" % fb,
               *(["BASIC bp %s" % n for n in names] + ["CATALOG bp %s" % sub, "CATALOG bp %s" % lsub, "RUN bp %s" % setup]))
    row("setup: all eight programs compiled with no errors", len(re.findall(r"Compiled 1 program\(s\) with no errors", out)) == len(names), out[-900:])
    o = sess(box, "RUN bp %s" % msh)
    row("a called subroutine uses the file the main program opened (shared across programs of one level)",
        re.search(r"(?m)^SUBREAD FROMA\s*$", o) is not None, o[-400:])
    row("a file the subroutine opens becomes the main program's default as well",
        re.search(r"(?m)^AFTER-SUB FROMB\s*$", o) is not None, o[-400:])
    o = sess(box, "RUN bp %s" % mexe)
    row("an EXECUTEd command starts with a fresh @STDFIL", re.search(r"(?m)^INNER-FRESH\s*$", o) is not None, o[-400:])
    row("the EXECUTEd command opens and reads its own file", re.search(r"(?m)^INNER-READ FROMB\s*$", o) is not None, o[-400:])
    row("on return from the EXECUTE the caller's @STDFIL is the file it had", re.search(r"(?m)^AFTER-EXEC FROMA\s*$", o) is not None, o[-400:])
    o = sess(box, "RUN bp %s" % mloc)
    row("CONTROL, $MODE STDFIL: a subroutine's open leaves the main program's default alone",
        re.search(r"(?m)^LOCAL-AFTER-SUB FROMA\s*$", o) is not None, o[-400:])
    o = sess(box, "RUN bp %s" % mboth)
    row("CONTROL, STDFIL and STDFIL.SHARED together are STDFIL: the main program's default is its own",
        re.search(r"(?m)^BOTH-AFTER-SUB FROMA\s*$", o) is not None, o[-400:])
    sess(box, "DELETE.CATALOG %s" % sub, "DELETE.CATALOG %s" % lsub, "DELETE.FILE %s" % fa, "DELETE.FILE %s" % fb)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-stdfil.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-stdfil: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-stdfil: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    fil = "zzsf" + RUN
    other = "zzso" + RUN
    pon, pcl, poff, pneg = ("zzsd%s%s" % (RUN, c) for c in "ocbn")
    progs = {
        # the mode on: every statement without a file variable, and the same statements with one
        pon: """$mode stdfil
   open '%(f)s' else crt 'OPEN-FAILED' ; stop
   crt 'OPEN-DEFAULT-OK'
   write 'alpha':@fm:'beta' to 'k1'
   read r from 'k1' then crt 'READ-DEFAULT ':r<2> else crt 'READ-DEFAULT-MISSING'
   id = 'k1'
   readu r2 from id locked
      crt 'READU-LOCKED'
   end then
      crt 'READU-DEFAULT ':r2<1>
   end else
      crt 'READU-MISSING'
   end
   release , id
   dim m(2)
   matread m from id then crt 'MATREAD-DEFAULT ':m(2) else crt 'MATREAD-MISSING'
   m(1) = 'gamma'
   matwrite m to id
   read r3 from id then crt 'MATWRITE-DEFAULT ':r3<1>
   read r4 from id<1,1> then crt 'SUBSCRIPT-ID-OK ':r4<1> else crt 'SUBSCRIPT-ID-MISSING'
   write 'one' to 'k2' ; write 'two' to 'k3'
   select to 4
   n = 0
   loop readnext kk from 4 else exit
      n += 1
   repeat
   crt 'SELECT-DEFAULT ':n
   filelock ; fileunlock
   crt 'FILELOCK-DEFAULT-OK'
   open '%(o)s' to g then
      write 'zed' to g, 'k9'
      read r5 from g, 'k9' then crt 'EXPLICIT-FILE ':r5
      close g
   end
   read r6 from 'k9' else crt 'DEFAULT-NOT-DISTURBED'
   delete 'k1'
   read r7 from 'k1' then crt 'DELETE-DEFAULT-FAILED' else crt 'DELETE-DEFAULT-OK'
   crt 'ATVAR ':(if unassigned(@stdfil) then 'UNASSIGNED' else 'ASSIGNED')
   clearfile
   read r8 from 'k2' then crt 'CLEARFILE-DEFAULT-FAILED' else crt 'CLEARFILE-DEFAULT-OK'
   close
   crt 'CLOSE-DEFAULT-OK'
end
""" % {"f": fil, "o": other},
        # the mode on, a statement that names its file variable on every line: unchanged
        pcl: """$mode stdfil
   open '%(f)s' to f else crt 'OPEN-FAILED' ; stop
   write 'one' to f, 'c1'
   read r from f, 'c1' then crt 'NAMED-READ ':r else crt 'NAMED-READ-MISSING'
   readu r2 from f, 'c1' then crt 'NAMED-READU ':r2
   release f, 'c1'
   delete f, 'c1'
   read r3 from f, 'c1' then crt 'NAMED-DELETE-FAILED' else crt 'NAMED-DELETE-OK'
   close f
end
""" % {"f": fil},
        # the mode off: the same default-file statement is a compile error, as it always was
        poff: """   open '%(f)s' to f else stop
   read r from 'k1' then crt 'OFF-COMPILED-AND-RAN' else crt 'OFF-ELSE'
end
""" % {"f": fil},
        # the mode off: the plain program is untouched
        pneg: """   open '%(f)s' to f else crt 'OPEN-FAILED' ; stop
   write 'x' to f, 'n1'
   read r from f, 'n1' then crt 'OFF-NAMED-READ ':r
   delete f, 'n1'
   close f
end
""" % {"f": fil},
    }
    for name, body in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(body)

    say("\n--- $MODE STDFIL -----------------------------------------------------------------------------------------")
    out = sess(box, "DELETE.FILE %s" % fil, "DELETE.FILE %s" % other, "CREATE.FILE %s" % fil, "CREATE.FILE %s" % other,
               "BASIC bp %s" % pon, "BASIC bp %s" % pcl, "BASIC bp %s" % poff, "BASIC bp %s" % pneg,
               "RUN bp %s" % pon, "RUN bp %s" % pcl, "RUN bp %s" % pneg, "DELETE.FILE %s" % fil, "DELETE.FILE %s" % other)
    comp = out.split("RUN bp %s" % pon, 1)[0]
    ok_compiles = len(re.findall(r"Compiled 1 program\(s\) with no errors", comp))
    row("setup: exactly three of the four programs compiled (the mode-on pair and the plain control)", ok_compiles == 3, comp[-800:])
    row("CONTROL, the mode off: the default-file READ is the one that did not compile",
        ok_compiles == 3 and "OFF-COMPILED-AND-RAN" not in out, comp[-800:])
    ran = out.split("RUN bp %s" % pon, 1)[-1]
    row("OPEN name (no TO) opens the default file", "OPEN-DEFAULT-OK" in ran and "OPEN-FAILED" not in ran, ran[-600:])
    row("WRITE rec TO id and READ rec FROM id use it", "READ-DEFAULT beta" in ran, ran[-600:])
    row("READU rec FROM id LOCKED ... uses it", "READU-DEFAULT alpha" in ran, ran[-600:])
    row("MATREAD mat FROM id and MATWRITE mat TO id use it", "MATREAD-DEFAULT beta" in ran and "MATWRITE-DEFAULT gamma" in ran, ran[-600:])
    row("a record id with a subscript (a comma inside <>) is an id, not a file variable",
        "SUBSCRIPT-ID-OK gamma" in ran, ran[-600:])
    row("SELECT TO 4 selects the default file (k1, k2, k3)", "SELECT-DEFAULT 3" in ran, ran[-600:])
    row("FILELOCK and FILEUNLOCK take the default file", "FILELOCK-DEFAULT-OK" in ran, ran[-600:])
    row("a statement naming its file variable still uses that file and leaves the default alone",
        "EXPLICIT-FILE zed" in ran and "DEFAULT-NOT-DISTURBED" in ran, ran[-600:])
    row("DELETE id deletes from the default file", "DELETE-DEFAULT-OK" in ran and "DELETE-DEFAULT-FAILED" not in ran, ran[-600:])
    row("@STDFIL is the default file variable", "ATVAR ASSIGNED" in ran, ran[-600:])
    row("CLEARFILE empties the default file", "CLEARFILE-DEFAULT-OK" in ran, ran[-600:])
    row("CLOSE closes the default file", "CLOSE-DEFAULT-OK" in ran, ran[-600:])
    row("mode on, every file variable named: the program behaves as it always did",
        "NAMED-READ one" in ran and "NAMED-READU one" in ran and "NAMED-DELETE-OK" in ran, ran[-900:])
    row("CONTROL, the mode off: a program that names its file variables is untouched", "OFF-NAMED-READ x" in ran, ran[-900:])
    row("CONTROL, the mode off: the default-file program was never run (no compiled object)",
        "OFF-COMPILED-AND-RAN" not in out and "OFF-ELSE" not in out, out[-400:])

    shared_rows(box, sysd)

    say("")
    say("sandbox-stdfil: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
