#!/usr/bin/env python3
#
# sandbox-classas.py - CLASS ... INHERITS name AS variable (openQM 4 release item, sheet 374).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-classas.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty
# or absent); without it <dir> must already be built.  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  New.  bcomp (CLASS statement): INHERITS name AS var names the private object variable explicitly.
# END-HISTORY
#
# The verdicts: the inherited object is reached through the name given by AS, and through the class name when AS is
# absent (the control); a second class in one list takes its own AS name; a missing name and a duplicate name are
# compile errors.  The inherited public function is also found through the child object.

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
    say("sandbox-classas: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-classas.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-classas: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-classas: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    ba, bb = "zzcab" + RUN, "zzcbb" + RUN          # two base classes
    c_as, c_def, c_two = "zzcas" + RUN, "zzcdf" + RUN, "zzctw" + RUN
    d_noname, d_dup = "zzcnn" + RUN, "zzcdu" + RUN
    t_as, t_def, t_two = "zzcrun" + RUN, "zzcrund" + RUN, "zzcrunt" + RUN
    c_sub, t_sub = "zzcsub" + RUN, "zzcrsub" + RUN

    def base(name, word):
        return "class %s\n   public function hello()\n      return '%s'\n   end\nend\n" % (name, word)

    def runner(cls, expr):
        return "   o = object('%s')\n%s   crt 'DONE'\nend\n" % (cls, expr)

    progs = {
        ba: base(ba, "ALPHA"),
        bb: base(bb, "BETA"),
        # AS: the private variable is called myb and the class's own method reaches the base through it
        c_as: "class %s inherits %s as myb\n   public function viamyb()\n      return myb->hello()\n   end\nend\n" % (c_as, ba),
        # control, no AS: the variable carries the class name
        c_def: "class %s inherits %s\n   public function viadef()\n      return %s->hello()\n   end\nend\n" % (c_def, ba, ba),
        # two classes, each with its own name
        c_two: ("class %s inherits %s as first, %s as second\n   public function one()\n      return first->hello()\n   end\n"
                "   public function two()\n      return second->hello()\n   end\nend\n") % (c_two, ba, bb),
        # sheet 237: an empty pair of brackets on a method reference, as a statement and in an expression
        c_sub: "class %s\n   public subroutine note()\n      crt 'NOTED'\n   end\n   public function word()\n      return 'WORD'\n   end\nend\n" % c_sub,
        t_sub: runner(c_sub, "   o->note()\n   o->note\n   x = o->word()\n   y = o->word\n   crt 'EMPTY-BRACKETS ':x:' ':y\n"),
        d_noname: "class %s inherits %s as\nend\n" % (d_noname, ba),
        d_dup: "class %s inherits %s as x, %s as x\nend\n" % (d_dup, ba, bb),
        t_as: runner(c_as, "   crt 'VIA-AS ':o->viamyb()\n   crt 'INHERITED ':o->hello()\n"),
        t_def: runner(c_def, "   crt 'VIA-DEF ':o->viadef()\n   crt 'INHERITED-DEF ':o->hello()\n"),
        t_two: runner(c_two, "   crt 'TWO-ONE ':o->one()\n   crt 'TWO-TWO ':o->two()\n"),
    }
    for name, text in progs.items():
        with open(os.path.join(sysd, "bp", name), "w") as fh:
            fh.write(text)

    say("\n--- CLASS INHERITS ... AS ---------------------------------------------------------------------------------")
    good = (ba, bb, c_as, c_def, c_two, t_as, t_def, t_two)
    cmds = []
    for n in good[:5]:
        cmds += ["BASIC bp %s" % n, "CATALOG bp %s LOCAL" % n]
    cmds += ["BASIC bp %s" % n for n in good[5:]]
    out = sess(box, *cmds)
    row("setup: eight programs compiled with no errors, the classes catalogued",
        out.count("Compiled 1 program(s) with no errors") == 8, out[-800:])

    o = sess(box, "RUN bp %s" % t_def)
    row("CONTROL, no AS: the base is reached through a variable named after its class, and its function through the child",
        re.search(r"(?m)^VIA-DEF ALPHA\s*$", o) and re.search(r"(?m)^INHERITED-DEF ALPHA\s*$", o) and "DONE" in o, o[-400:])
    o = sess(box, "RUN bp %s" % t_as)
    row("AS myb: the class's own method reaches the base through myb", re.search(r"(?m)^VIA-AS ALPHA\s*$", o) is not None, o[-400:])
    row("AS myb: the inherited public function is still found through the child object",
        re.search(r"(?m)^INHERITED ALPHA\s*$", o) is not None and "DONE" in o, o[-400:])
    o = sess(box, "RUN bp %s" % t_two)
    row("two classes in one list, each with its own AS name, each reaches its own base",
        re.search(r"(?m)^TWO-ONE ALPHA\s*$", o) and re.search(r"(?m)^TWO-TWO BETA\s*$", o), o[-400:])

    o = sess(box, "BASIC bp %s" % c_sub, "CATALOG bp %s LOCAL" % c_sub, "BASIC bp %s" % t_sub, "RUN bp %s" % t_sub)
    row("sheet 237: o->note() as a statement and o->word() in an expression compile (an empty pair of brackets), "
        "and give what the bracket-less forms give",
        o.count("Compiled 1 program(s) with no errors") == 2 and o.count("NOTED") == 2
        and re.search(r"(?m)^EMPTY-BRACKETS WORD WORD\s*$", o) is not None, o[-500:])

    o = sess(box, "BASIC bp %s" % d_noname)
    row("AS with no name after it is a compile error (variable name not found)",
        "no errors" not in o and re.search(r"(?i)variable name not found", o) is not None, o[-400:])
    o = sess(box, "BASIC bp %s" % d_dup)
    row("the same AS name for two classes is a duplicate symbol",
        "no errors" not in o and re.search(r"(?i)duplicate", o) is not None, o[-400:])

    say("")
    say("sandbox-classas: %d passed, %d failed" % (passed, failed))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
