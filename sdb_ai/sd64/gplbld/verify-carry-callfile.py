#!/usr/bin/env python3
#
# sandbox-callfile.py - 17 Oct 2026, QM4 Fixes 208: the Pick style CALL "file name" - a compiled program is called by the
#                       VOC name of the file it was compiled into and its own name, past the catalogue.  The owner's ruling:
#                       VOC file names only, no operating system path.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-callfile.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from THIS tree
# (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 17 Oct 26 dm  Written.
# END-HISTORY
#
# THE FILES.  zzcfsub is compiled in the account's bp file and NOT catalogued, so only the file form can reach it.  zzcfbp is a
# second directory file with zzcfsub2 compiled in it.  The rows are run as programs, as sandbox-try.py's are; an error that
# must happen is caught with TRY, so that the row can say which one it was.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

SUB1 = "subroutine zzcfsub(a, b)\n   b = a : '!'\nreturn\nend\n"
SUB2 = "subroutine zzcfsub2(a, b)\n   b = a : '?'\nreturn\nend\n"


def refused(call, name="sys.program.invalid_call_name"):
    return "try\n   %s\n   x = 'NOT REFUSED'\ncatch %s\n   x = @exception\nend" % (call, name)


# (label, body, wanted)
CASES = [
    ("CALL \"file name\" calls the program compiled into that file, which is not in the catalogue",
     'call "bp zzcfsub"(1, r)\nx = r', "1!"),
    ("...through a variable that holds the string (an indirect call)", "nm = 'bp zzcfsub'\ncall @nm(2, r)\nx = r", "2!"),
    ("...and again, through the link the first call made", 'for i = 1 to 3\n   call "bp zzcfsub"(i, r)\n   x := r\nnext i', "1!2!3!"),
    ("...the string is not case sensitive (names are lower case in SD)", 'call "BP ZZCFSUB"(4, r)\nx = r', "4!"),
    ("...the file can be any file that has a VOC entry and an object directory", 'call "zzcfbp zzcfsub2"(5, r)\nx = r', "5?"),
    ("CONTROL: an ordinary call of the same program by name finds nothing, the catalogue is not touched",
     refused("call zzcfsub(1, r)", "sys.program.not_found"), "SYS.PROGRAM.NOT_FOUND"),
    ("a file that is not in the VOC is an illegal call name", refused('call "zzcfnone zzcfsub"(1, r)'), "SYS.PROGRAM.INVALID_CALL_NAME"),
    ("an operating system path is refused: absolute", refused('call "/tmp zzcfsub"(1, r)'), "SYS.PROGRAM.INVALID_CALL_NAME"),
    ("...relative", refused('call "../bp zzcfsub"(1, r)'), "SYS.PROGRAM.INVALID_CALL_NAME"),
    ("...a path in the program part", refused('call "bp ../bp.out/zzcfsub"(1, r)'), "SYS.PROGRAM.INVALID_CALL_NAME"),
    ("a program name with a catalogue prefix ($ ! * _) is refused", refused('nm = "bp $zzcfsub"\ncall @nm(1, r)'), "SYS.PROGRAM.INVALID_CALL_NAME"),
    ("...also !", refused('nm = "bp !zzcfsub"\ncall @nm(1, r)'), "SYS.PROGRAM.INVALID_CALL_NAME"),
    ("a third word is refused", refused('nm = "bp zzcfsub extra"\ncall @nm(1, r)'), "SYS.PROGRAM.INVALID_CALL_NAME"),
    ("a name with nothing after the file is refused", refused('nm = "bp "\ncall @nm(1, r)'), "SYS.PROGRAM.INVALID_CALL_NAME"),
    ("a program that is not in the file is reported as not found", refused('call "bp zzcfnone"(1, r)', "sys.program.not_found"), "SYS.PROGRAM.NOT_FOUND"),
    ("STATUS() is left as it was by the lookup of the file",
     "open 'zzcfnofile' to nf else null\ns1 = status()\ncall \"bp zzcfsub\"(1, r)\ns2 = status()\nx = (s1 # 0):(s1 = s2)", "11"),
    ("CALLV, a call with the argument list in a matrix, takes the file form too", 'dim m(2)\nm(1) = 6\ncall "bp zzcfsub"(m(1), r)\nx = r', "6!"),
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
    say("sandbox-callfile: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-callfile.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-callfile: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-callfile: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        write(os.path.join(bp, "zzcfsub"), SUB1)
        made.append(os.path.join(bp, "zzcfsub"))
        out = sess(box, "BASIC bp zzcfsub", "CREATE.FILE zzcfbp DIRECTORY")
        if not re.search(r"(?i)compiled 1 program", out):
            bail("zzcfsub did not compile:\n" + out[-500:])
        write(os.path.join(sysd, "zzcfbp", "zzcfsub2"), SUB2)
        out = sess(box, "BASIC zzcfbp zzcfsub2")
        if not re.search(r"(?i)compiled 1 program", out):
            bail("zzcfsub2 did not compile:\n" + out[-500:])

        say("\n--- CALL \"file name\" -----------------------------------------------------------------------")
        for i, (label, body, want) in enumerate(CASES):
            prog = "zzcf%02d" % i
            p = os.path.join(bp, prog)
            write(p, "   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) + "   crt 'C%02d[':x:']'\nend\n" % i)
            made.append(p)
            out = sess(box, "BASIC bp %s" % prog, "RUN bp %s" % prog)
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            row("%s: wanted %r" % (label, want), got == want, ("got %r" % got) if m else "no output: " + out[-300:].replace("\n", " | "))

        say("\n--- the compiler ----------------------------------------------------------------------------")
        p = os.path.join(bp, "zzcfbad")
        write(p, '   call "nospaceinthis"(1, r)\nend\n')
        made.append(p)
        out = sess(box, "BASIC bp zzcfbad")
        row("a string with no space in it is not the file form and is refused at compile time, as it always was",
            re.search(r"Expected direct or indirect subroutine reference", out) is not None, out[-300:].replace("\n", " | "))
    finally:
        sess(box, "DELETE.FILE zzcfbp", "DELETE.FILE zzcfbp.out")
        for p in made:
            if os.path.exists(p):
                os.remove(p)
        for d in ("bp.out",):
            if os.path.isdir(os.path.join(sysd, d)):
                for f in os.listdir(os.path.join(sysd, d)):
                    if f.startswith("zzcf"):
                        os.remove(os.path.join(sysd, d, f))

    say("\nsandbox-callfile: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


main()
