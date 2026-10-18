#!/usr/bin/env python3
#
# sandbox-try.py - 1.2-0 (12 Oct 2026): TRY / CATCH / THROW, CAUGHT() and @EXCEPTION* (openQM 355; the construct itself
#                  from the openQM TRY/CATCH and CAUGHT() descriptions the owner pasted).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-try.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from THIS tree
# (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 12 Oct 26 dm  Written.
# END-HISTORY
#
# Each case is (label, subs, body, wanted).  subs = {name: source} are catalogued subroutines (lower case names) made
# first; the body is compiled as program zztxNN and the value it leaves in x is printed between brackets.  {p} in a
# wanted value is the program's name.  The rows after the cases are special: compile errors, an unhandled exception,
# DUMPING, an exception that must not cross EXECUTE.

import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

# A subroutine that throws, one that throws two levels down, one that does not throw, one that catches its own
SUB_THROW = "subroutine zztxa(nm, dt)\n   throw nm, dt\n   crt 'NOT REACHED zztxa'\nreturn\nend\n"
SUB_DEEP = "subroutine zztxb(nm)\n   call zztxa(nm, 'deep data')\n   crt 'NOT REACHED zztxb'\nreturn\nend\n"
SUB_QUIET = "subroutine zztxc(res)\n   res = 'quiet'\nreturn\nend\n"
SUB_OWN = ("subroutine zztxd(res)\n   try\n      throw 'inner.thing'\n   catch inner.thing\n      res = 'zztxd caught'\n   end\n"
           "return\nend\n")
SUB_ASK = "subroutine zztxe(res)\n   res = caught('want.this'):'/':caught('other.name')\nreturn\nend\n"
SUB_RETHROW = ("subroutine zztxf(res)\n   try\n      call zztxa('first', 'one')\n   catch first\n      throw 'second', @exception.data:'+'\n"
               "   end\nreturn\nend\n")

CASES = [
    ("CONTROL: with no THROW the TRY clause runs and the CATCH clause does not", {},
     "try\n   x = 'body'\ncatch oops\n   x = 'caught'\nend", "body"),
    ("a THROW in the TRY clause goes to the CATCH clause; what follows it is skipped", {},
     "try\n   throw 'oops'\n   x = 'not reached'\ncatch oops\n   x = 'caught'\nend", "caught"),
    ("names are not case sensitive (THROW upper, CATCH lower)", {},
     "try\n   throw 'OOPS'\ncatch oops\n   x = 'caught'\nend", "caught"),
    ("@EXCEPTION is the name as thrown and @EXCEPTION.DATA the data", {},
     "try\n   throw 'Bad.Thing', 'some details'\ncatch bad.thing\n   x = @exception:'/':@exception.data\nend", "Bad.Thing/some details"),
    ("the data may be left out: @EXCEPTION.DATA is then null", {},
     "try\n   throw 'nodata'\ncatch nodata\n   x = '[':@exception.data:']'\nend", "[]"),
    ("the exception name may be an expression", {},
     "nm = 'built':'.name'\ntry\n   throw nm\ncatch built.name\n   x = 'caught'\nend", "caught"),
    ("a statement may follow TRY on the same line", {},
     "try x = 'same line'\ncatch oops\n   x = 'caught'\nend", "same line"),
    ("a quoted name in CATCH", {},
     "try\n   throw 'a.b'\ncatch 'a.b'\n   x = 'caught'\nend", "caught"),
    ("the first CATCH clause that names it is the one used, the others are skipped", {},
     "try\n   throw 'two'\ncatch one\n   x = 'one'\ncatch two\n   x = 'two'\ncatch three\n   x = 'three'\nend", "two"),
    ("one CATCH clause can name several exceptions", {},
     "try\n   throw 'beta'\ncatch alpha, beta, gamma\n   x = 'caught ':@exception\nend", "caught beta"),
    ("a CATCH clause can be continued onto a second line after a comma", {},
     "try\n   throw 'gamma'\ncatch alpha,\n      gamma\n   x = 'caught'\nend", "caught"),
    ("SYS$ANY catches any exception not named by an earlier clause", {},
     "try\n   throw 'whatever'\ncatch known\n   x = 'known'\ncatch sys$any\n   x = 'any ':@exception\nend", "any whatever"),
    ("SYS$ANY does not take a name that an earlier clause has", {},
     "try\n   throw 'known'\ncatch known\n   x = 'known'\ncatch sys$any\n   x = 'any'\nend", "known"),
    ("SYS$UNHANDLED is used when nothing else anywhere names the exception", {},
     "try\n   throw 'zz'\ncatch other\n   x = 'other'\ncatch sys$unhandled\n   x = 'unhandled ':@exception\nend", "unhandled zz"),
    ("a named handler outside beats a SYS$UNHANDLED one inside", {},
     "try\n   try\n      throw 'zz'\n   catch sys$unhandled\n      x = 'inner unhandled'\n   end\ncatch zz\n   x = 'outer named'\nend",
     "outer named"),
    ("nested: the inner TRY does not name it, so the outer CATCH takes it", {},
     "try\n   try\n      throw 'outer.one'\n   catch inner.one\n      x = 'inner'\n   end\n   x = 'not reached'\ncatch outer.one\n   x = 'outer'\nend",
     "outer"),
    ("nested: the inner CATCH takes it and the outer clause goes on after it", {},
     "try\n   try\n      throw 'both'\n   catch both\n      x = 'inner,'\n   end\n   x := 'continued'\ncatch both\n   x = 'outer'\nend",
     "inner,continued"),
    ("a THROW from inside a CATCH clause goes to the TRY outside it", {},
     "try\n   try\n      throw 'first'\n   catch first\n      throw 'second', 'from first'\n   end\ncatch second\n   x = @exception.data\nend",
     "from first"),
    ("a CATCH clause that cannot be reached by the TRY clause's own exception is not run", {},
     "x = 'start'\ntry\n   x = 'ok'\ncatch never\n   x = 'wrong'\nend\nx := ' end'", "ok end"),
    ("a THROW inside a GOSUB inside the TRY clause: the GOSUB stack is unwound", {},
     "try\n   gosub s1\ncatch oops\n   x = 'caught'\nend\ngosub s2\ngoto fin\ns1:\n   throw 'oops'\n   return\ns2:\n   x := ' then s2'\n   return\nfin: null",
     "caught then s2"),
    ("a RETURN from a GOSUB inside the TRY clause leaves no handler behind", {},
     "gosub s1\nx = 'before:':caught('oops')\ngoto fin\ns1:\n   try\n      return\n   catch oops\n      null\n   end\nfin: null",
     "before:0"),
    ("a THROW in a CALLed subroutine is caught in the caller; the subroutine does not finish", {"zztxa": SUB_THROW},
     "try\n   call zztxa('oops', 'from sub')\ncatch oops\n   x = @exception:'/':@exception.data\nend", "oops/from sub"),
    ("and two CALL levels down", {"zztxa": SUB_THROW, "zztxb": SUB_DEEP},
     "try\n   call zztxb('oops')\ncatch oops\n   x = @exception.data\nend", "deep data"),
    ("after the unwind the caller carries on at its own level", {"zztxa": SUB_THROW, "zztxb": SUB_DEEP, "zztxc": SUB_QUIET},
     "try\n   call zztxb('oops')\ncatch oops\n   null\nend\ncall zztxc(r)\nx = r", "quiet"),
    ("a subroutine that has its own TRY handles its own exception", {"zztxd": SUB_OWN},
     "try\n   call zztxd(r)\ncatch inner.thing\n   r = 'caller caught'\nend\nx = r", "zztxd caught"),
    ("a subroutine's TRY that does not name it lets it through to the caller", {"zztxd": SUB_OWN},
     "try\n   call zztxd(r)\n   throw 'other'\ncatch other\n   x = 'caller caught other'\nend", "caller caught other"),
    ("a CATCH in a subroutine can THROW another exception to the caller", {"zztxa": SUB_THROW, "zztxf": SUB_RETHROW},
     "try\n   call zztxf(r)\ncatch second\n   x = @exception.data\nend", "one+"),
    ("a loop of 200 TRYs, half of them throwing: no handler is left behind (the limit is 64)", {},
     "cnt = 0\nfor i = 1 to 200\n   try\n      if rem(i, 2) then throw 'odd'\n      cnt += 100\n   catch odd\n      cnt += 1\n   end\nnext i\nx = cnt",
     "10100"),
    ("a loop of TRYs that do not throw leaves none either", {},
     "for i = 1 to 200\n   try\n      x = i\n   catch odd\n      x = 'wrong'\n   end\nnext i", "200"),
    ("CAUGHT is 0 with no TRY", {}, "x = caught('oops')", "0"),
    ("CAUGHT is 1 inside a TRY that names it, whatever the case", {},
     "try\n   x = caught('OOPS')\ncatch oops\n   null\nend", "1"),
    ("CAUGHT is 0 for a name no handler has", {},
     "try\n   x = caught('other')\ncatch oops\n   null\nend", "0"),
    ("CAUGHT is 0 again once the TRY is over", {},
     "try\n   null\ncatch oops\n   null\nend\nx = caught('oops')", "0"),
    ("CAUGHT sees the handler of the program that called the subroutine", {"zztxe": SUB_ASK},
     "try\n   call zztxe(r)\ncatch want.this\n   null\nend\nx = r", "1/0"),
    ("CAUGHT with modes 0: a SYS$ANY handler does not count, with 1 it does, 2 is for SYS$UNHANDLED", {},
     "try\n   x = caught('zz'):caught('zz', 0):caught('zz', 1):caught('zz', 2):caught('zz', 3)\ncatch sys$any\n   null\nend",
     "00101"),
    ("CAUGHT with modes 2 counts the SYS$UNHANDLED handler", {},
     "try\n   x = caught('zz'):caught('zz', 1):caught('zz', 2):caught('zz', 3)\ncatch sys$unhandled\n   null\nend", "0011"),
    ("@EXCEPTION.ORIGIN is the program name (its object path, as in error messages), a field mark and the line of the THROW", {},
     "try\n   throw 'where'\ncatch where\n   o = @exception.origin\n   p = field(o, @fm, 1)\n   x = field(p, '/', dcount(p, '/')):'/':field(o, @fm, 2)\nend",
     "{p}/3"),
    ("@EXCEPTION.ORIGIN names the subroutine that threw, not the one that caught", {"zztxa": SUB_THROW},
     "try\n   call zztxa('where', '')\ncatch where\n   x = change(@exception.origin, @fm, '/')\nend", "zztxa/2"),
    ("@EXCEPTION.STACK is null unless SAVING.STACK was asked for", {},
     "try\n   throw 'st'\ncatch st\n   x = '[':@exception.stack:']'\nend", "[]"),
    ("SAVING.STACK fills @EXCEPTION.STACK with the call stack, innermost program first", {"zztxa": SUB_THROW},
     "try\n   call zztxa('st', '')\ncatch st saving.stack\n   p1 = field(field(@exception.stack, @fm, 1), @vm, 1)\n"
     "   p2 = field(field(@exception.stack, @fm, 2), @vm, 1)\n   x = p1:'/':field(p2, '/', dcount(p2, '/'))\nend",
     "zztxa/{p}"),
    ("$MODE EXCEPTION.SAVE.STACK does the same for every CATCH", {},
     "$mode exception.save.stack\ntry\n   throw 'st'\ncatch st\n   x = (@exception.stack # '')\nend", "1"),
    ("qualifiers go with the name they follow: the other name in the list gets no stack", {},
     "try\n   throw 'b'\ncatch a saving.stack, b\n   x = '[':@exception.stack:']'\nend", "[]"),
    ("THROW after an earlier exception resets @EXCEPTION.STACK", {},
     "try\n   throw 'st'\ncatch st saving.stack\n   null\nend\ntry\n   throw 'plain'\ncatch plain\n   x = '[':@exception.stack:']'\nend", "[]"),
    ("an exception name of 63 characters is allowed", {},
     "nm = str('n', 63)\ntry\n   throw nm\ncatch sys$any\n   x = len(@exception)\nend", "63"),
    ("TRY, CATCH, THROW and CAUGHT can still be the names of plain variables", {},
     "try = 1\ncatch = 2\nthrow = 3\ncaught = 4\nx = try + catch + throw + caught", "10"),
]


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
    say("sandbox-try: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


def has(out, pat):
    return re.search(pat, out, re.M) is not None


def source(i, body, wrap=True, final_end=True):
    """The probe program: line 1 is x = '', the body's lines follow from line 2."""
    lines = "".join("   %s\n" % ln for ln in body.split("\n") if ln)
    return "   x = ''\n" + lines + ("   crt 'C%02d[':x:']'\n" % i if wrap else "") + ("end\n" if final_end else "")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-try.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-try: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-try: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    catalogued = []
    try:
        say("\n--- the construct -------------------------------------------------------------")
        for i, (label, subs, body, want) in enumerate(CASES):
            for nm, text in subs.items():
                if nm not in catalogued:
                    p = os.path.join(bp, nm)
                    write(p, text)
                    made.append(p)
                    out = sess(box, "BASIC bp %s" % nm, "CATALOG bp %s" % nm)
                    if not has(out, r"Compiled 1 program\(s\) with no errors|compiled 1 program"):
                        say("  [note] %s: %s" % (nm, out[-200:].replace("\n", " | ")))
                    catalogued.append(nm)
            prog = "zztx%02d" % i
            p = os.path.join(bp, prog)
            write(p, source(i, body))
            made.append(p)
            out = sess(box, "BASIC bp %s" % prog, "RUN bp %s" % prog)
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            want = want.replace("{p}", prog)
            row("%s: wanted %r" % (label, want), got == want, ("got %r" % got) if m else "no output: " + out[-250:].replace("\n", " | "))

        say("\n--- compile errors ------------------------------------------------------------")
        # (label, body, message, final END wanted?) - the cases that end the source inside the construct have no final END
        errcases = [
            ("a TRY without a CATCH clause", "try\n   x = 1\nend", r"TRY needs at least one CATCH", True),
            ("a CATCH with no TRY", "catch oops\n   x = 1\nend", r"Misplaced catch", True),
            ("a CATCH clause that is never ended", "try\n   x = 1\ncatch oops\n   x = 2", r"Unterminated CATCH clause", False),
            ("a TRY clause that never reaches a CATCH", "try\n   x = 1", r"Unterminated TRY clause", False),
            ("a CATCH with no name", "try\n   x = 1\ncatch\n   x = 2\nend", r"Exception name expected", True),
            ("a CATCH qualifier that is not DUMPING or SAVING.STACK", "try\n   x = 1\ncatch oops sideways\n   x = 2\nend",
             r"Unknown CATCH qualifier", True),
            ("a CATCH name of 64 characters", "try\n   x = 1\ncatch " + "n" * 64 + "\n   x = 2\nend", r"longer than 63", True),
        ]
        for j, (label, body, pat, fin) in enumerate(errcases):
            prog = "zztxe%d" % j
            p = os.path.join(bp, prog)
            write(p, source(90 + j, body, wrap=False, final_end=fin))
            made.append(p)
            out = sess(box, "BASIC bp %s" % prog)
            row("%s is refused: %s" % (label, pat), has(out, "(?i)" + pat), out[-250:].replace("\n", " | "))

        say("\n--- run time errors and the barriers ------------------------------------------------")
        prog = "zztxr1"
        p = os.path.join(bp, prog)
        write(p, "   x = ''\n   throw 'nobody.home', 'the data'\n   crt 'NOT REACHED'\nend\n")
        made.append(p)
        out = sess(box, "BASIC bp %s" % prog, "RUN bp %s" % prog)
        row("an exception nobody handles stops the program and says so, with its data",
            has(out, r"Unhandled exception nobody\.home: the data") and not has(out, r"NOT REACHED"), out[-250:].replace("\n", " | "))
        write(p, "   throw 'bare'\nend\n")
        out = sess(box, "BASIC bp %s" % prog, "RUN bp %s" % prog)
        row("...and without data the message has none", has(out, r"Unhandled exception bare( at line|\s*$)") and not has(out, r"bare:"), out[-250:].replace("\n", " | "))
        write(p, "   throw ''\nend\n")
        out = sess(box, "BASIC bp %s" % prog, "RUN bp %s" % prog)
        row("THROW with a null name is refused", has(out, r"THROW needs an exception name"), out[-250:].replace("\n", " | "))
        write(p, "   throw str('n', 64)\nend\n")
        out = sess(box, "BASIC bp %s" % prog, "RUN bp %s" % prog)
        row("THROW with a name of 64 characters is refused", has(out, r"longer than 63 characters"), out[-250:].replace("\n", " | "))

        write(p, "   x = ''\n   try\n      throw 'oops', 'x'\n   catch oops dumping\n      crt 'AFTER_DUMP'\n   end\nend\n")
        out = sess(box, "BASIC bp %s" % prog, "RUN bp %s" % prog)
        row("DUMPING makes a process dump file before the CATCH clause runs",
            has(out, r"Dumping process state as .*sddump\.\d+") and has(out, r"AFTER_DUMP"), out[-300:].replace("\n", " | "))
        for f in os.listdir(sysd):
            if f.startswith("sddump."):
                os.remove(os.path.join(sysd, f))

        # a program run by EXECUTE is a barrier: the exception is unhandled in there and the outer TRY never sees it
        # (an unhandled exception aborts as any run time error does, so the outer program does not go on either)
        inner = os.path.join(bp, "zztxin")
        write(inner, "   throw 'across', 'execute'\nend\n")
        made.append(inner)
        write(p, "   x = ''\n   try\n      execute 'RUN bp zztxin'\n      x = 'after execute'\n   catch across\n      crt 'WRONGLY_CAUGHT'\n   end\n   crt 'BARRIER[':x:']'\nend\n")
        out = sess(box, "BASIC bp zztxin", "BASIC bp %s" % prog, "RUN bp %s" % prog)
        row("an exception thrown inside an EXECUTEd program is not caught by a TRY around the EXECUTE",
            has(out, r"Unhandled exception across: execute") and not has(out, r"WRONGLY_CAUGHT"), out[-300:].replace("\n", " | "))
    finally:
        sess(box, *["DELETE.CATALOG %s" % nm for nm in catalogued])
        for p in made:
            if os.path.exists(p):
                os.remove(p)
        if os.path.isdir(os.path.join(sysd, "bp.out")):
            for f in os.listdir(os.path.join(sysd, "bp.out")):
                if f.startswith("zztx"):
                    os.remove(os.path.join(sysd, "bp.out", f))

    say("\nsandbox-try: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


main()
