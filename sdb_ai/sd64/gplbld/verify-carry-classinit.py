#!/usr/bin/env python3
#
# sandbox-classinit.py - class modules: initial values (565), values for inherited classes (356) and MAIN (484).  No install, no
# sudo.  QM4 Fixes items 565, 356 and 484.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-classinit.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.
# END-HISTORY
#
# THE INSTRUMENT.  The sandbox, the sessions and the fixture account are those of sandbox-stmt-q3.py, loaded as a module (as
# sandbox-restricted.py does).
#
#   565  PUBLIC / PRIVATE var {= value} and a matrix given a value: the value is a number (signed, a float), a string, CHAR(n) or a
#        constant @-variable, and it is there when CREATE.OBJECT runs (it prints what it finds), for PUBLIC, PRIVATE, READONLY and
#        matrices.  A value that is not a constant is a compile error (11394).
#   356  CLASS c INHERITS other(values) and INHERITS other AS name(values): the values reach the inherited class's CREATE.OBJECT as
#        its arguments.  CONTROL: INHERITS with no values, as before; more than 32 values is a compile error (11393).
#   484  a class with a MAIN subroutine is run by RUN and by its catalogue name: CREATE.OBJECT, then MAIN, then the object goes and
#        DESTROY.OBJECT runs.  A class without MAIN gets the object reference's message for MAIN.  A CALL of a class is still
#        refused (3450).

import importlib.util
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("q3", os.path.join(HERE, "sandbox-stmt-q3.py"))
q3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q3)
say, row, has, tag, put = q3.say, q3.row, q3.has, q3.tag, q3.put

USER_PROGS = {
    # --- 565 ------------------------------------------------------------------------------------------------------------------
    "zzci1": ("class zzci1\n"
              "   public a = 5, b = \"text\", c = 1.5, d = -7\n"
              "   public e readonly = \"RO\"\n"
              "   public f = char(65), g = @fm, h = @true\n"
              "   private p = 10, q = 'priv'\n"
              "   public m(3) = 0\n"
              "   public n(2,2) = \"X\"\n"
              "   public subroutine create.object()\n"
              "      crt 'CO a=':a:' p=':p:' q=':q:' m2=':m(2):' n22=':n(2,2)\n"
              "      a = a + 1\n"
              "   end\n"
              "   public function getp()\n      return p:'/':q\n   end\n"
              "   public function mcount()\n      return m(1):m(2):m(3):n(1,1):n(2,2)\n   end\n"
              "end\n"),
    "zzci0": ("class zzci0\n   public a\n   private p\n   public subroutine create.object()\n      a = 'SET' ; p = 'PSET'\n   end\n"
              "   public function getp()\n      return p\n   end\nend\n"),
    "zzci1r": ("   o = object('zzci1')\n   crt 'A[':o->a:']'\n   crt 'B[':o->b:']'\n   crt 'C[':o->c:']'\n   crt 'D[':o->d:']'\n"
               "   crt 'E[':o->e:']'\n   crt 'F[':o->f:']'\n   crt 'G[':oconv(o->g, 'MX0C'):']'\n   crt 'H[':o->h:']'\n"
               "   crt 'P[':o->getp():']'\n   crt 'M[':o->mcount():']'\n   crt 'M1[':o->m(1):']'\n   crt 'R1DONE'\nend\n"),
    "zzci0r": ("   o = object('zzci0')\n   crt 'Z1[':o->a:']'\n   crt 'Z2[':o->getp():']'\n   crt 'R0DONE'\nend\n"),
    "zzcie1": "class zzcie1\n   public x = y\nend\n",
    "zzcie2": "class zzcie2\n   private p = @userno\nend\n",
    "zzcie3": "class zzcie3\n   public x = 5 + 1\nend\n",
    # --- 356 ------------------------------------------------------------------------------------------------------------------
    "zzci2": ("class zzci2\n   public rate, count\n   public subroutine create.object(r, n)\n      rate = r ; count = n\n"
              "      crt 'BASE got ':r:' ':n\n   end\nend\n"),
    "zzci3": ("class zzci3 inherits zzci2(\"RATE\", 25)\n   public function info()\n      return zzci2->rate:'/':zzci2->count\n   end\nend\n"),
    "zzci4": ("class zzci4 inherits zzci2 as base(-3, 'x y')\n   public function info()\n      return base->rate:'/':base->count\n   end\nend\n"),
    "zzci5": ("class zzci5 inherits zzci2(char(65), 1.5)\n   public function info()\n      return zzci2->rate:'/':zzci2->count\n   end\nend\n"),
    "zzci6": ("class zzci6 inherits zzci2(@vm, @true)\n   public function info()\n      return oconv(zzci2->rate, 'MX0C'):'/':zzci2->count\n   end\nend\n"),
    "zzci7": "class zzci7\n   public tag\n   public subroutine create.object()\n      tag = 'NOARGS'\n   end\nend\n",
    "zzci8": "class zzci8 inherits zzci7\n   public function info()\n      return zzci7->tag\n   end\nend\n",
    "zzci2r": ("   a = object('zzci3')\n   crt 'I3[':a->info():']'\n   b = object('zzci4')\n   crt 'I4[':b->info():']'\n"
               "   c = object('zzci5')\n   crt 'I5[':c->info():']'\n   d = object('zzci6')\n   crt 'I6[':d->info():']'\n"
               "   e = object('zzci8')\n   crt 'I8[':e->info():']'\n   crt 'R2DONE'\nend\n"),
    "zzcie4": "class zzcie4 inherits zzci2(" + ", ".join(str(i) for i in range(33)) + ")\nend\n",
    # --- 484 ------------------------------------------------------------------------------------------------------------------
    "zzcm1": ("class zzcm1\n   private n = 3\n   public subroutine create.object()\n      crt 'CREATED n=':n\n   end\n"
              "   public subroutine main()\n      crt 'MAIN RAN n=':n\n   end\n"
              "   public subroutine destroy.object()\n      crt 'DESTROYED'\n   end\nend\n"),
    "zzcm2": "class zzcm2\n   public subroutine create.object()\n      crt 'CREATED2'\n   end\nend\n",
    "zzcmcall": "   call zzcm1\n   crt 'NOT REFUSED'\nend\n",
}
CLASSES = ["zzci1", "zzci0", "zzci2", "zzci3", "zzci4", "zzci5", "zzci6", "zzci7", "zzci8", "zzcm1", "zzcm2"]
ERROR_PROGS = ["zzcie1", "zzcie2", "zzcie3", "zzcie4"]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        q3.bail("usage: sandbox-classinit.py <dir> [--build]")
    q3.BOX = os.path.abspath(args[0])
    q3.SYS = os.path.join(q3.BOX, "sys")
    q3.SD = os.path.join(q3.SYS, "bin", "sd")
    q3.USER_PROGS = USER_PROGS
    SYS = q3.SYS
    say("sandbox-classinit: sandbox  %s" % q3.BOX)
    if "--build" in sys.argv:
        if os.path.exists(q3.BOX) and os.listdir(q3.BOX):
            q3.bail("%s is not empty" % q3.BOX)
        r = subprocess.run([sys.executable, q3.TOOL, q3.BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            q3.bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-classinit: built, bootstrap passed")
    elif not os.path.isfile(q3.SD):
        q3.bail("%s holds no built sandbox (use --build, or point it at one)" % q3.BOX)
    subprocess.run([sys.executable, q3.TOOL, q3.BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation ------------------------------------------------------------------------------------------------")
    q3.prepare()
    good = [n for n in USER_PROGS if n not in ERROR_PROGS]
    for nm, text in USER_PROGS.items():
        put(os.path.join(SYS, "bp", nm), text)
    # compile the classes in dependency order (zzci2 before the classes that inherit it is not needed to compile, only to run)
    out = q3.adm(["BASIC bp " + " ".join(good)])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(good)):
        # not all of them compiled (a compiler without the new syntax refuses the class files): say which, and go on, so that
        # each row below fails or passes on its own
        say("    NOT ALL COMPILED; compiling one at a time:")
        for nm in good:
            one = q3.adm(["BASIC bp " + nm])
            say("      %-9s %s" % (nm, "compiled" if has(one, r"^Compiled 1 program\(s\) with no errors") else "REFUSED: " + next((l for l in one if ": " in l and "rror" not in l[:3]), "?")[:100]))

    try:
        q3.adm(["CATALOG bp %s LOCAL" % c for c in CLASSES])

        say("\n--- 565: initial values --------------------------------------------------------------------------------------")
        out = q3.adm(["RUN bp zzci0r"])
        row("CONTROL  a class with no initial values works as before (CREATE.OBJECT sets them)", tag(out, "Z1") == ["SET"]
            and tag(out, "Z2") == ["PSET"] and has(out, r"^R0DONE$"), repr(out[-4:]))
        out = q3.adm(["RUN bp zzci1r"])
        row("565  CREATE.OBJECT finds the values already set: PUBLIC, PRIVATE, a string and a matrix element",
            has(out, r"^CO a=5 p=10 q=priv m2=0 n22=X$"), repr(out[-14:]))
        row("565  a public number, a string, a float and a negative number", tag(out, "A") == ["6"] and tag(out, "B") == ["text"]
            and tag(out, "C") == ["1.5"] and tag(out, "D") == ["-7"], repr(out[-14:]))
        row("565  a READONLY public variable has its value", tag(out, "E") == ["RO"], repr(out[-14:]))
        row("565  CHAR(65), @FM and @TRUE", tag(out, "F") == ["A"] and tag(out, "G") == ["FE"] and tag(out, "H") == ["1"], repr(out[-14:]))
        row("565  a private variable", tag(out, "P") == ["10/priv"], repr(out[-14:]))
        row("565  a matrix given a value: every element has it", tag(out, "M") == ["000XX"] and tag(out, "M1") == ["0"], repr(out[-14:]))
        out = q3.adm(["BASIC bp zzcie1 zzcie2 zzcie3"])
        row("565  a value that is not a constant (a variable name) is a compile error", has(out, r"initialisation value must be a numeric"), repr(out[:10]))
        row("565  nor is a changing @-variable (@USERNO)", len([l for l in out if "initialisation value must be a numeric" in l]) >= 2, repr(out[:12]))
        row("565  nor is an expression: after the constant 5 the + 1 is not a statement (a compile error; the old compiler refused the whole line)",
            has(out, r"^2: Unrecognised statement$") and has(out, r"^   zzcie3$"), repr(out[:14]))

        say("\n--- 356: values for the inherited classes ----------------------------------------------------------------------")
        out = q3.adm(["RUN bp zzci2r"])
        row("356  INHERITS zzci2(\"RATE\", 25): the base class's CREATE.OBJECT gets them", has(out, r"^BASE got RATE 25$") and tag(out, "I3") == ["RATE/25"], repr(out[-14:]))
        row("356  INHERITS zzci2 AS base(-3, 'x y'): after the object variable name", has(out, r"^BASE got -3 x y$") and tag(out, "I4") == ["-3/x y"], repr(out[-14:]))
        row("356  CHAR(65) and a float", tag(out, "I5") == ["A/1.5"], repr(out[-14:]))
        row("356  @VM and @TRUE", tag(out, "I6") == ["FD/1"], repr(out[-14:]))
        row("CONTROL  INHERITS with no values still works", tag(out, "I8") == ["NOARGS"] and has(out, r"^R2DONE$"), repr(out[-14:]))
        out = q3.adm(["BASIC bp zzcie4"])
        row("356  more than 32 values is a compile error", has(out, r"At most 32 initialisation values"), repr(out[:8]))

        say("\n--- 484: running a class module -----------------------------------------------------------------------------")
        out = q3.adm(["RUN bp zzcm1"])
        row("484  RUN bp zzcm1: CREATE.OBJECT, then MAIN, then the object goes (DESTROY.OBJECT)",
            [l for l in out if l in ("CREATED n=3", "MAIN RAN n=3", "DESTROYED")] == ["CREATED n=3", "MAIN RAN n=3", "DESTROYED"], repr(out[-8:]))
        out = q3.adm(["zzcm1"])
        row("484  the catalogue name does the same", [l for l in out if l in ("CREATED n=3", "MAIN RAN n=3", "DESTROYED")] == ["CREATED n=3", "MAIN RAN n=3", "DESTROYED"], repr(out[-8:]))
        out = q3.adm(["RUN bp zzcm2"])
        row("484  a class with no MAIN: CREATE.OBJECT ran and the reference to MAIN is refused",
            has(out, r"^CREATED2$") and has(out, r"Unrecognised property/method name \(MAIN\)"), repr(out[-6:]))
        out = q3.adm(["BASIC bp zzcmcall", "RUN bp zzcmcall"])
        row("CONTROL  a CALL of a class is still refused: 'A CLASS routine may not be used in this way'",
            has(out, r"A CLASS routine may not be used in this way") and not has(out, r"NOT REFUSED"), repr(out[-6:]))
    finally:
        for lv_ in q3.lives:
            lv_.kill()
        for nm in list(USER_PROGS):
            for d in ("bp", "bp.out"):
                p = os.path.join(SYS, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-classinit: %d passed, %d failed" % (q3.passed, q3.failed))
    if q3.passed + q3.failed == 0:
        q3.bail("no row ran - a broken test, not a pass")
    return 1 if q3.failed else 0


if __name__ == "__main__":
    sys.exit(main())
