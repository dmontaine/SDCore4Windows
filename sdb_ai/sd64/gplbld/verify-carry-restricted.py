#!/usr/bin/env python3
#
# sandbox-restricted.py - RESTRICTED in a class module (QM4 gaps, 16 Oct 26).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-restricted.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  Written for RESTRICTED var / SUBROUTINE / FUNCTION (bcomp st.restricted, the name map's RESTRICTED bit, objprog.c).
# END-HISTORY
#
# THE INSTRUMENT.  The sandbox, the sessions and the fixture account are those of sandbox-stmt-q3.py, loaded as a module.  The
# classes are compiled, catalogued LOCAL and used by small programs that each try one thing; a refusal is the message the run
# time gives for a name that is not there, and the programs print NOT REFUSED if it did not come.
#
#   zzrpar declares a public property and method and restricted ones (a variable, a read-only variable, a function, a subroutine);
#   zzrchi inherits it and uses the restricted names through its parent; zzroth is a class with no relation to it.
#   D1 the public names and a public method that uses the restricted variable work from outside (the control)
#   D2 the main program cannot reach a restricted function, variable or subroutine
#   D3 the child reaches all of them through its parent (read and write; the read-only variable only to read)
#   D4 the child object does not pass the parent's restricted names on to the main program; D5 an unrelated class cannot reach them
#   D6 READONLY holds; D7 compile errors: a name public in one routine and restricted in another, RESTRICTED outside a class

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
    "zzrpar": ("class zzrpar\n   public x\n   restricted r\n   restricted rr readonly\n"
               "   public subroutine create.object()\n      rr = 'RO1'\n   end\n"
               "   public subroutine setr(v)\n      r = v\n   end\n"
               "   public function getr()\n      return r\n   end\n"
               "   restricted function secret()\n      return 'SECRET'\n   end\n"
               "   restricted subroutine hush()\n      crt 'HUSHED'\n   end\nend\n"),
    "zzrchi": ("class zzrchi inherits zzrpar\n"
               "   public function viaparent()\n      return zzrpar->secret()\n   end\n"
               "   public function varviaparent()\n      zzrpar->r = 'CHILDSET'\n      return zzrpar->r\n   end\n"
               "   public subroutine callhush()\n      zzrpar->hush()\n   end\n"
               "   public function readro()\n      return zzrpar->rr\n   end\n"
               "   public subroutine setro()\n      zzrpar->rr = 9\n   end\nend\n"),
    "zzroth": ("class zzroth\n   public function peek()\n      o = object('zzrpar')\n      return o->secret()\n   end\nend\n"),
    "zzrr1": "   o = object('zzrpar')\n   o->x = 5\n   crt 'PUB[':o->x:']'\n   o->setr('V1')\n   crt 'GETR[':o->getr():']'\n   crt 'R1DONE'\nend\n",
    "zzrr2": "   o = object('zzrpar')\n   x = o->secret()\n   crt 'NOT REFUSED'\nend\n",
    "zzrr3": "   o = object('zzrpar')\n   x = o->r\n   crt 'NOT REFUSED'\nend\n",
    "zzrr4": "   o = object('zzrpar')\n   o->hush()\n   crt 'NOT REFUSED'\nend\n",
    "zzrr5": ("   c = object('zzrchi')\n   crt 'C1[':c->viaparent():']'\n   crt 'C2[':c->varviaparent():']'\n   c->callhush()\n"
              "   crt 'RO[':c->readro():']'\n   crt 'R5DONE'\nend\n"),
    "zzrr6": "   c = object('zzrchi')\n   x = c->secret()\n   crt 'NOT REFUSED'\nend\n",
    "zzrr7": "   o = object('zzroth')\n   x = o->peek()\n   crt 'NOT REFUSED'\nend\n",
    "zzrr8": "   c = object('zzrchi')\n   c->setro()\n   crt 'NOT REFUSED'\nend\n",
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        q3.bail("usage: sandbox-restricted.py <dir> [--build]")
    q3.BOX = os.path.abspath(args[0])
    q3.SYS = os.path.join(q3.BOX, "sys")
    q3.SD = os.path.join(q3.SYS, "bin", "sd")
    q3.USER_PROGS = USER_PROGS
    SYS = q3.SYS
    say("sandbox-restricted: sandbox  %s" % q3.BOX)
    if "--build" in sys.argv:
        if os.path.exists(q3.BOX) and os.listdir(q3.BOX):
            q3.bail("%s is not empty" % q3.BOX)
        r = subprocess.run([sys.executable, q3.TOOL, q3.BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            q3.bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-restricted: built, bootstrap passed")
    elif not os.path.isfile(q3.SD):
        q3.bail("%s holds no built sandbox (use --build, or point it at one)" % q3.BOX)
    subprocess.run([sys.executable, q3.TOOL, q3.BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation ------------------------------------------------------------------------------------------------")
    q3.prepare()
    for nm, text in USER_PROGS.items():
        put(os.path.join(SYS, "bp", nm), text)
    out = q3.adm(["BASIC bp " + " ".join(USER_PROGS)])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(USER_PROGS)):
        q3.bail("the probes did not compile in SDSYS:\n" + "\n".join(out[-8:]))

    try:
        q3.adm(["CATALOG bp zzrpar LOCAL", "CATALOG bp zzrchi LOCAL", "CATALOG bp zzroth LOCAL"])
        out = q3.adm(["RUN bp zzrr1"])
        row("D1: CONTROL: a public property and a public method that uses the restricted variable inside the class work from outside",
            tag(out, "PUB") == ["5"] and tag(out, "GETR") == ["V1"] and has(out, r"^R1DONE$"), repr(out[-4:]))
        for prog, name, what in (("zzrr2", "SECRET", "a restricted function"), ("zzrr3", "R", "a restricted variable (read)"),
                                 ("zzrr4", "HUSH", "a restricted subroutine")):
            out = q3.adm(["RUN bp " + prog])
            row("D2: the main program cannot reach %s: 'Unrecognised property/method name (%s)'" % (what, name),
                has(out, r"Unrecognised property/method name \(%s\)" % name) and not has(out, r"NOT REFUSED"), repr(out[-3:]))
        out = q3.adm(["RUN bp zzrr5"])
        row("D3: a class that inherits the parent reaches the restricted function, variable (read and write), subroutine and read-only "
            "variable (read) through its parent",
            tag(out, "C1") == ["SECRET"] and tag(out, "C2") == ["CHILDSET"] and has(out, r"^HUSHED$") and tag(out, "RO") == ["RO1"]
            and has(out, r"^R5DONE$"), repr(out[-6:]))
        out = q3.adm(["RUN bp zzrr6"])
        row("D4: the child object does not pass the parent's restricted function on to the main program",
            has(out, r"Unrecognised property/method name \(SECRET\)") and not has(out, r"NOT REFUSED"), repr(out[-3:]))
        out = q3.adm(["RUN bp zzrr7"])
        row("D5: a class with no relation to the parent cannot reach its restricted function either",
            has(out, r"Unrecognised property/method name \(SECRET\)") and not has(out, r"NOT REFUSED"), repr(out[-3:]))
        out = q3.adm(["RUN bp zzrr8"])
        row("D6: READONLY holds for a restricted variable: the child can read it (D3) and cannot assign it",
            has(out, r"Unrecognised property/method name \(RR\)") and not has(out, r"NOT REFUSED"), repr(out[-3:]))
        # compile errors
        put(os.path.join(SYS, "bp", "zzre1"), "class zzre1\n   public subroutine foo()\n   end\n   restricted function foo()\n      return 1\n   end\nend\n")
        put(os.path.join(SYS, "bp", "zzre2"), "   restricted xvar\n   crt 'X'\nend\n")
        put(os.path.join(SYS, "bp", "zzre3"), "class zzre3\n   restricted a, b\n   restricted c readonly\n   public function sum()\n      a = 1 ; b = 2\n      return a + b\n   end\nend\n")
        out = q3.adm(["BASIC bp zzre1", "BASIC bp zzre2", "BASIC bp zzre3"])
        row("D7: one name cannot be public in one routine and restricted in another: a compile error (already defined)",
            has(out, r"(?i)already been defined"), repr(out[:6]))
        row("D7: RESTRICTED outside a class is a compile error ('Misplaced RESTRICTED')", has(out, r"^1: Misplaced RESTRICTED$"), repr(out[:12]))
        row("D7: a list of restricted variables compiles (the third program is good)", has(out, r"^Compiled 1 program\(s\) with no errors"), repr(out[-3:]))
    finally:
        for lv_ in q3.lives:
            lv_.kill()
        for nm in list(USER_PROGS) + ["zzre1", "zzre2", "zzre3"]:
            for d in ("bp", "bp.out"):
                p = os.path.join(SYS, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-restricted: %d passed, %d failed" % (q3.passed, q3.failed))
    if q3.passed + q3.failed == 0:
        q3.bail("no row ran - a broken test, not a pass")
    return 1 if q3.failed else 0


if __name__ == "__main__":
    sys.exit(main())
