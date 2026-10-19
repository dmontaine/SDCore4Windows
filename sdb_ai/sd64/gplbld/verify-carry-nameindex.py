#!/usr/bin/env python3
#
# sandbox-nameindex.py - a class with very many public names is looked up through a hash index (QM4 Fixes item 13).  No
# install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-nameindex.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  New.
# END-HISTORY
#
# THE INSTRUMENT.  The sandbox, the sessions and the fixture account are those of sandbox-stmt-q3.py, loaded as a module (as
# sandbox-restricted.py does).  objprog.c scanned an object's name map, a packed list in its object code, for every property
# or method reference; a map of 32 names or more now gets a hash index when the first name is sought in it.  The index must
# change nothing but the time: the rows read every kind of name through a small class (no index: CONTROL) and a big one, the
# UNDEFINED handler, DESTROY.OBJECT, inherited names and RESTRICTED names (sandbox-restricted.py is the full set for the
# last).  The TIMING rows compare 400000 references to the FIRST name of the big class with 400000 to the LAST: a scan makes
# the second many times slower; an index makes them equal.  A time is a relation between two runs of the same session, never
# a number.

import importlib.util
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("q3", os.path.join(HERE, "sandbox-stmt-q3.py"))
q3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q3)
say, row, has, tag, put = q3.say, q3.row, q3.has, q3.tag, q3.put

NP = 1500       # public properties of the big class
NF = 40         # public functions of the big class


def big_class():
    s = ["class zzbig"]
    names = ["p%d" % i for i in range(1, NP + 1)]
    for k in range(0, NP, 10):
        s.append("   public " + ", ".join(names[k:k + 10]))
    for i in range(1, NF + 1):
        s.append("   public function f%d()\n      return %d\n   end" % (i, i * 10))
    s.append("   public subroutine destroy.object()\n      crt 'BIGGONE'\n   end")
    s.append("end")
    return "\n".join(s) + "\n"


USER_PROGS = {
    "zzbig": big_class(),
    "zzsm": "class zzsm\n   public a, b, c\n   public function fa()\n      return 'FA'\nend\nend\n",
    "zzbigc": "class zzbigc inherits zzbig\n   public q1\n   public function g1()\n      return 'G1'\n   end\nend\n",
    # 100 public names and an UNDEFINED handler that returns the name it was given
    "zzbigu": ("class zzbigu\n" + "".join("   public u%d\n" % i for i in range(1, 101)) +
               "   public function undefined(nm)\n      return 'UND:':nm\n   end\nend\n"),
    # a big class that restricts one of its names
    "zzbigr": ("class zzbigr\n" + "".join("   public r%d\n" % i for i in range(1, 60)) +
               "   restricted secret\n   public subroutine setsecret(v)\n      secret = v\n   end\n"
               "   public function getsecret()\n      return secret\n   end\nend\n"),
    "zzbigrc": "class zzbigrc inherits zzbigr\n   public function peek()\n      return zzbigr->secret\n   end\nend\n",
    "zzn1": ("   o = object('zzsm')\n   o->a = 1 ; o->b = 2 ; o->c = 3\n   crt 'S1[':o->a:o->b:o->c:']'\n"
             "   crt 'S2[':o->fa():']'\n   crt 'N1DONE'\nend\n"),
    "zzn2": ("   o = object('zzbig')\n   o->p1 = 'first' ; o->p%d = 'middle' ; o->p%d = 'last'\n"
             "   crt 'B1[':o->p1:']'\n   crt 'B2[':o->p%d:']'\n   crt 'B3[':o->p%d:']'\n"
             % (NP // 2, NP, NP // 2, NP)
             + "".join("   o->p%d = %d\n" % (i, i * 3) for i in range(1, NP + 1))
             + "   bad = 0\n"
             + "".join("   if o->p%d # %d then bad += 1\n" % (i, i * 3) for i in range(1, NP + 1))
             + "   crt 'B4[':bad:']'\n   crt 'N2DONE'\nend\n"),
    "zzn3": ("   o = object('zzbig')\n   crt 'F1[':o->f1():']'\n   crt 'F2[':o->f%d():']'\n   crt 'F3[':o->f%d():']'\n"
             "   crt 'N3DONE'\nend\n") % (NF // 2, NF),
    "zzn4": "   o = object('zzbig')\n   x = o->nosuchname\n   crt 'NOT REFUSED'\nend\n",
    "zzn5": ("   c = object('zzbigc')\n   c->p%d = 'inh'\n   c->q1 = 'own'\n   crt 'I1[':c->p%d:']'\n   crt 'I2[':c->q1:']'\n"
             "   crt 'I3[':c->f%d():']'\n   crt 'I4[':c->g1():']'\n   crt 'N5DONE'\nend\n") % (NP, NP, NF),
    "zzn6": ("   u = object('zzbigu')\n   u->u50 = 'known'\n   crt 'U1[':u->u50:']'\n   crt 'U2[':u->anythingelse:']'\n"
             "   crt 'N6DONE'\nend\n"),
    "zzn7": "   o = object('zzbig')\n   o = ''\n   crt 'N7DONE'\nend\n",
    "zzn8": ("   r = object('zzbigr')\n   r->setsecret('S1')\n   crt 'R1[':r->getsecret():']'\n"
             "   c = object('zzbigrc')\n   c->setsecret('S2')\n   crt 'R2[':c->peek():']'\n   crt 'N8DONE'\nend\n"),
    "zzn9": "   o = object('zzbig')\n   x = o->secret\n   crt 'NOT REFUSED'\nend\n",
    # the timing pair: the same loop, first name and last name
    "zzt1": ("   o = object('zzbig')\n   o->p1 = 1\n   for i = 1 to 400000\n      x = o->p1\n   next i\n   crt 'T1DONE'\nend\n"),
    "zzt2": ("   o = object('zzbig')\n   o->p%d = 1\n   for i = 1 to 400000\n      x = o->p%d\n   next i\n   crt 'T2DONE'\nend\n") % (NP, NP),
}
# zzn9 is a reference to a name of the RESTRICTED class from outside it
USER_PROGS["zzn9"] = "   r = object('zzbigr')\n   x = r->secret\n   crt 'NOT REFUSED'\nend\n"


def timed(cmd):
    t0 = time.monotonic()
    out = q3.adm([cmd])
    return time.monotonic() - t0, out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        q3.bail("usage: sandbox-nameindex.py <dir> [--build]")
    q3.BOX = os.path.abspath(args[0])
    q3.SYS = os.path.join(q3.BOX, "sys")
    q3.SD = os.path.join(q3.SYS, "bin", "sd")
    q3.USER_PROGS = USER_PROGS
    SYS = q3.SYS
    say("sandbox-nameindex: sandbox  %s" % q3.BOX)
    if "--build" in sys.argv:
        if os.path.exists(q3.BOX) and os.listdir(q3.BOX):
            q3.bail("%s is not empty" % q3.BOX)
        r = subprocess.run([sys.executable, q3.TOOL, q3.BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            q3.bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-nameindex: built, bootstrap passed")
    elif not os.path.isfile(q3.SD):
        q3.bail("%s holds no built sandbox (use --build, or point it at one)" % q3.BOX)
    subprocess.run([sys.executable, q3.TOOL, q3.BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation ------------------------------------------------------------------------------------------------")
    q3.prepare()
    for nm, text in USER_PROGS.items():
        put(os.path.join(SYS, "bp", nm), text)
    out = q3.adm(["BASIC bp " + " ".join(USER_PROGS)])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(USER_PROGS)):
        q3.bail("the programs did not compile in SDSYS:\n" + "\n".join(out[-12:]))
    classes = ["zzbig", "zzsm", "zzbigc", "zzbigu", "zzbigr", "zzbigrc"]

    try:
        q3.adm(["CATALOG bp %s LOCAL" % c for c in classes])
        out = q3.adm(["RUN bp zzn1"])
        row("CONTROL  a class of 3 names and a function (no index) works", tag(out, "S1") == ["123"] and tag(out, "S2") == ["FA"]
            and has(out, r"^N1DONE$"), repr(out[-4:]))
        out = q3.adm(["RUN bp zzn2"])
        row("a class of %d names: the first, the middle and the last read back what was set" % NP,
            tag(out, "B1") == ["first"] and tag(out, "B2") == ["middle"] and tag(out, "B3") == ["last"], repr(out[-5:]))
        row("every one of the %d names holds its own value (none found as another)" % NP, tag(out, "B4") == ["0"] and has(out, r"^N2DONE$"),
            repr(out[-3:]))
        out = q3.adm(["RUN bp zzn3"])
        row("the %d public functions of the big class: the first, the middle and the last are called" % NF,
            tag(out, "F1") == ["10"] and tag(out, "F2") == [str(NF // 2 * 10)] and tag(out, "F3") == [str(NF * 10)]
            and has(out, r"^N3DONE$"), repr(out[-5:]))
        out = q3.adm(["RUN bp zzn4"])
        row("a name the big class does not have is refused: 'Unrecognised property/method name (NOSUCHNAME)'",
            has(out, r"Unrecognised property/method name \(NOSUCHNAME\)") and not has(out, r"NOT REFUSED"), repr(out[-3:]))
        out = q3.adm(["RUN bp zzn5"])
        row("a child with a few names reaches the big parent's last name, its function and its own names",
            tag(out, "I1") == ["inh"] and tag(out, "I2") == ["own"] and tag(out, "I3") == [str(NF * 10)] and tag(out, "I4") == ["G1"]
            and has(out, r"^N5DONE$"), repr(out[-6:]))
        out = q3.adm(["RUN bp zzn6"])
        row("the UNDEFINED handler of a class of 100 names still takes a name the class does not have, and a known one is not sent to it",
            tag(out, "U1") == ["known"] and tag(out, "U2") == ["UND:ANYTHINGELSE"] and has(out, r"^N6DONE$"), repr(out[-4:]))
        out = q3.adm(["RUN bp zzn7"])
        row("DESTROY.OBJECT of the big class runs when the object goes", has(out, r"^BIGGONE$") and has(out, r"^N7DONE$"), repr(out[-3:]))
        out = q3.adm(["RUN bp zzn8"])
        row("a RESTRICTED name of a big class: its own methods and a child reach it", tag(out, "R1") == ["S1"] and tag(out, "R2") == ["S2"]
            and has(out, r"^N8DONE$"), repr(out[-4:]))
        out = q3.adm(["RUN bp zzn9"])
        row("a RESTRICTED name of a big class is not there for the main program",
            has(out, r"Unrecognised property/method name \(SECRET\)") and not has(out, r"NOT REFUSED"), repr(out[-3:]))

        say("\n--- time: 400000 references to the first name and to the last name of a class of %d names ---------------------" % NP)
        t1, o1 = timed("RUN bp zzt1")
        t2, o2 = timed("RUN bp zzt2")
        say("    first name %.2f s, last name %.2f s (each includes the session's own start)" % (t1, t2))
        row("the instrument: both timing runs finished", has(o1, r"^T1DONE$") and has(o2, r"^T2DONE$"), repr((o1[-2:], o2[-2:])))
        row("the last name costs about what the first does (%.2f s against %.2f s)" % (t2, t1), t2 <= 2.0 * t1 + 0.5,
            "%.2f against %.2f" % (t2, t1))
    finally:
        for lv_ in q3.lives:
            lv_.kill()
        for nm in list(USER_PROGS):
            for d in ("bp", "bp.out"):
                p = os.path.join(SYS, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-nameindex: %d passed, %d failed" % (q3.passed, q3.failed))
    if q3.passed + q3.failed == 0:
        q3.bail("no row ran - a broken test, not a pass")
    return 1 if q3.failed else 0


if __name__ == "__main__":
    sys.exit(main())
