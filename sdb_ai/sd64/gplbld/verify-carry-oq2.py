#!/usr/bin/env python3
#
# sandbox-oq2.py - 1.2-0, second sitting (12 Oct 2026): the openQM items built with SD's own syntax because the
#                  release notes give none (owner: "implement the functionality as much as possible - the method or
#                  syntax can be different than in openQM").  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-oq2.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 12 Oct 26 dm  Written: 336 names with two underscores, 407 INCLUDE in $BASIC.OPTIONS.
# END-HISTORY
#
# Each case is (label, files, program body, wanted).  files = {name: text} written to the sandbox's bp directory
# first (source, includes and option records); the body is compiled as program zzoqNN and the value it leaves in x
# is printed between brackets.  A COMPILE ERROR is read from the compiler's own "Compiled N program(s) with
# errors" line, and a case that wants one gives wanted = the line number the compiler must report.

import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

CASES = [
    ("CONTROL: a name with one underscore", {}, "a_b = 5\nx = a_b", "5"),
    ("336: a name with two consecutive underscores", {}, "a__b = 7\nx = a__b", "7"),
    ("336: and three, mixed with digits", {}, "a1___b2 = 9\nx = a1___b2", "9"),
    ("63: MD5 of abc is the 32 character lower case digest", {}, "x = md5('abc')", "900150983cd24fb0d6963f7d28e17f72"),
    ("63: MD5 of the openQM example Hello World", {}, "x = md5('Hello World')", "b10a8db164e0754105b7a99be72e3fe5"),
    ("63: MD5 of the null string", {}, "x = md5('')", "d41d8cd98f00b204e9800998ecf8427e"),
    ("63: MD5 of a string with a field mark in it (bytes, not text)", {}, "x = len(md5('a':@fm:'b'))", "32"),
    ("581 CONTROL: TIME() is a whole number of seconds without the mode", {}, "t = time()\nx = (t = int(t))", "1"),
    ("581: $MODE TIME.MS makes TIME() seconds to the millisecond, within half a second of SYSTEM(1020)/1000",
     {}, "$mode time.ms\nt = time()\nx = (abs(t - system(1020) / 1000) < 0.5)", "1"),
    ("581: and it is not a whole number (tried three times; a whole second is one chance in a thousand)",
     {}, "$mode time.ms\nx = 0\nfor i = 1 to 3\n   t = time()\n   if t # int(t) then x = 1\n   sleep 1\nnext i", "1"),
    ("52 CONTROL: a named common block holds its value", {}, "common /zzcn/ a, b\ncommon /zzcm/ c\na = 5 ; b = 6 ; c = 7\nx = a + b + c", "18"),
    ("52: CLEARCOMMON name sets that block to zero and leaves the others",
     {}, "common /zzcn/ a, b\ncommon /zzcm/ c\na = 5 ; b = 6 ; c = 7\nclearcommon zzcn\nx = a:'/':b:'/':c", "0/0/7"),
    ("52: CLEARCOMMON alone still clears the unnamed block only",
     {}, "common a, b\ncommon /zzcm/ c\na = 5 ; b = 6 ; c = 7\nclearcommon\nx = a:'/':b:'/':c", "0/0/7"),
    ("391: SADD of two numbers longer than any float", {},
     "x = sadd('123456789012345678901234567890', '987654321098765432109876543210')", "1111111110111111111011111111100"),
    ("391: SADD with signs", {}, "x = sadd('5', '-8')", "-3"),
    ("391: SSUB", {}, "x = ssub('1000000000000000000000', '1')", "999999999999999999999"),
    ("391: SSUB going negative", {}, "x = ssub('3', '10')", "-7"),
    ("391: SMUL of two 20 digit numbers", {}, "x = smul('12345678901234567890', '98765432109876543210')",
     "1219326311370217952237463801111263526900"),
    ("391: SMUL by zero is 0, not -0", {}, "x = smul('-5', '0')", "0"),
    ("391: SDIV with a fraction, 15 places, trailing zeros dropped", {}, "x = sdiv('10', '4')", "2.5"),
    ("391: SDIV that does not end", {}, "x = sdiv('1', '3')", "0.333333333333333"),
    ("391: SDIV of a negative", {}, "x = sdiv('-7', '2')", "-3.5"),
    ("391: SCMP less, equal, greater", {}, "x = scmp('9', '10'):'/':scmp('5.0', '5'):'/':scmp('-1', '-2')", "-1/0/1"),
    ("468: SADD with decimals", {}, "x = sadd('0.1', '0.2')", "0.3"),
    ("468: SMUL with decimals", {}, "x = smul('1.5', '-2.25')", "-3.375"),
    ("468: SSUB with decimals of different lengths", {}, "x = ssub('10', '0.001')", "9.999"),
    ("472: EREPLACE, the openQM example", {}, "x = ereplace('The quick brown fox jumps over the lazy dog.', 'fox', 'cat')",
     "The quick brown cat jumps over the lazy dog."),
    ("472: EREPLACE replaces every occurrence by default", {}, "x = ereplace('a-b-c-d', '-', '+')", "a+b+c+d"),
    ("472: with an occurrence count", {}, "x = ereplace('a-b-c-d', '-', '+', 2)", "a+b+c-d"),
    ("472: with a count and a start", {}, "x = ereplace('a-b-c-d', '-', '+', 1, 3)", "a-b-c+d"),
    ("472: a count below 1 means all", {}, "x = ereplace('a-b-c-d', '-', '+', 0)", "a+b+c+d"),
    ("472: a null NEW deletes", {}, "x = ereplace('a-b-c', '-', '')", "abc"),
    ("472: a null OLD puts NEW in front of the string", {}, "x = ereplace('world', '', 'hello ')", "hello world"),
    ("472 FIX: the openQM example, default precision 4 rounds 37.73629273 to 37.7363", {}, "x = fix(37.73629273)", "37.7363"),
    ("472 FIX: precision 2 rounds up", {}, "x = fix(37.73629273, 2)", "37.74"),
    ("472 FIX: mode 1 truncates", {}, "x = fix(37.73629273, 2, 1)", "37.73"),
    ("472 FIX: the places asked for are kept, zeros included", {}, "x = fix(37.5, 2)", "37.50"),
    ("472 FIX: precision 0 gives a whole number, rounded", {}, "x = fix(2.5, 0):'/':fix(2.4, 0)", "3/2"),
    ("472 FIX: a negative number rounds away from zero and truncates toward it", {}, "x = fix(-2.675, 2):'/':fix(-2.675, 2, 1)", "-2.68/-2.67"),
    ("472 FIX: the program's PRECISION is the default", {}, "precision 2\nx = fix(1.23456)", "1.23"),
    ("509 MATSTR: the openQM example, a 3 x 2 matrix: a field for each row, a value for each column", {},
     "dim data(3, 2)\ndata(1, 1) = 'John' ; data(1, 2) = 'Doe'\ndata(2, 1) = 'Jane' ; data(2, 2) = 'Smith'\n"
     "data(3, 1) = 'Bob' ; data(3, 2) = 'Johnson'\nx = change(change(matstr(data), @vm, ','), @fm, '/')", "John,Doe/Jane,Smith/Bob,Johnson"),
    ("509 MATSTR: an empty cell in a 2 x 2 keeps its place", {},
     "dim m(2, 2)\nmat m = ''\nm(1, 2) = 'b' ; m(2, 1) = 'c'\nx = change(change(matstr(m), @vm, ','), @fm, '/')", ",b/c,"),
    ("509 MATSTR: a one dimensional matrix is an FM list like MATBUILD, trailing nulls off", {},
     "dim v(5)\nmat v = ''\nv(1) = 'a' ; v(2) = 'b' ; v(3) = 'c'\nx = change(matstr(v), @fm, '/')", "a/b/c"),
    ("509 CONTROL: MATBUILD of the same one dimensional matrix", {},
     "dim v(5)\nmat v = ''\nv(1) = 'a' ; v(2) = 'b' ; v(3) = 'c'\nmatbuild s from v\nx = change(s, @fm, '/')", "a/b/c"),
    ("509 MATSTR: the zero element of a one dimensional matrix is not used", {},
     "dim v(2)\nv(0) = 'zero' ; v(1) = 'a' ; v(2) = 'b'\nx = change(matstr(v), @fm, '/')", "a/b"),
    ("472 CONTROL: CHANGE gives the same as EREPLACE for a non-null OLD", {}, "x = change('a-b-c-d', '-', '+', 2)", "a+b+c-d"),
    ("510: REGEX finds a match anywhere", {}, "x = regex('hello world', 'wor')", "1"),
    ("510: REGEX with an anchor and a class", {}, "x = regex('abc123', '^[a-z]+[0-9]+$'):regex('abc123x', '^[a-z]+[0-9]+$')", "10"),
    ("510: REGEX is case sensitive unless the pattern begins (?i)", {}, "x = regex('ABC', 'abc'):regex('ABC', '(?i)abc')", "01"),
    ("315 CONTROL: a single template that matches leaves INMAT() at 1", {}, "y = ('abc' matches '3A')\nx = inmat()", "1"),
    ("315: MATCHES with a multivalued template - INMAT() is the first value that matched", {},
     "y = ('123' matches '3N':@vm:'3A')\nx = y:'/':inmat()", "1/1"),
    ("315: and the second value", {}, "y = ('abc' matches '3N':@vm:'3A')\nx = y:'/':inmat()", "1/2"),
    ("315: and the third, when the first two do not match", {},
     "y = ('ab12' matches '3N':@vm:'3A':@vm:'2A2N')\nx = y:'/':inmat()", "1/3"),
    ("315: the first value that matches wins when two would", {},
     "y = ('abc' matches '3A':@vm:'3X')\nx = y:'/':inmat()", "1/1"),
    ("315: no value matches - INMAT() is 0, not what the previous MATCHES left", {},
     "y = ('abc' matches '3N':@vm:'3A')\nz = ('a1' matches '3N':@vm:'3A')\nx = z:'/':inmat()", "0/0"),
    ("315: MATCHFIELD sets it too, and still returns the component", {},
     "y = matchfield('abc123', '3N3A':@vm:'3A3N', 2)\nx = inmat():'/':y", "2/123"),
    ("407 CONTROL: without the option record the constant is not defined", {}, "x = unassigned(zzk)", "1"),
    ("407: an INCLUDE line in $BASIC.OPTIONS puts the record at the top of the program",
     {"$BASIC.OPTIONS": "X\nINCLUDE zzincl\n", "zzincl": "zzk = 41\n"}, "x = zzk + 1", "42"),
]

# Not through the option record: a compile error must keep its own line number with includes in front
ERRCASE = ("407: an error on line 4 of the program (the probe's own first line is 1) is still reported as line 4 with two automatic includes in front",
           {"$BASIC.OPTIONS": "X\nINCLUDE zzincl\nINCLUDE zzincl2\n", "zzincl": "zzk = 41\n", "zzincl2": "zzm = 2\n"},
           "x = 1\nx = 2\nx = = 3\n", "4")


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
    say("sandbox-oq2: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=900)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def isess(box, *cmds):
    """A session in INTERNAL mode (sd -internal), where the restricted statements compile: the BTREE ones (ADD, MODIFY, REWIND,
    SCAN, FIND) are internal-only, so a row about them cannot use sess().  The sandbox must be running (sess() starts it)."""
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"), env=env,
                       capture_output=True, text=True, errors="replace", timeout=180)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def write(path, text):
    with open(path, "w") as f:
        f.write(text)


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-oq2.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-oq2: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900,
                           env=dict(os.environ, SDBOX_NEWVOC_MODS="1"))
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-oq2: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    # The $BASIC.OPTIONS record is read from the source file of the program being compiled, so a case that has one
    # gets its own source file (a directory file under the account); the others compile from bp.
    say("\n--- the items -----------------------------------------------------------------")
    made = []
    try:
        for i, (label, files, body, want) in enumerate(CASES + [ERRCASE]):
            iserr = (label == ERRCASE[0])
            dirname = "zzoqd%02d" % i if files else None
            if dirname:
                out0 = sess(box, "CREATE.FILE %s DIRECTORY" % dirname)
                d = os.path.join(sysd, dirname)   # the sandbox's account is the system directory
                made.append(d + ".dic")
                made.append(d)
                for nm, text in files.items():
                    write(os.path.join(d, nm), text)
                srcdir, srcname = dirname, "zzoq%02d" % i
                prog = os.path.join(d, srcname)
            else:
                srcdir, srcname = "bp", "zzoq%02d" % i
                prog = os.path.join(bp, srcname)
                made.append(prog)
            text = "   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n") if ln) + \
                   ("" if iserr else "   crt 'C%02d[':x:']'\n" % i) + "end\n"
            write(prog, text)
            out = sess(box, "BASIC %s %s" % (srcdir, srcname), "RUN %s %s" % (srcdir, srcname))
            if iserr:
                m = re.search(r"(?m)^(\d+): ", out)
                row("%s: wanted line %s" % (label, want), m is not None and m.group(1) == want,
                    "got %r" % (m.group(1) if m else None))
            else:
                m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
                got = m.group(1) if m else None
                row("%s: wanted %r" % (label, want), got == want, "got %r" % got if m else "no output")
    finally:
        # the VOC pointers of the scratch directory files
        sess(box, *["DELETE.FILE zzoqd%02d" % i for i in range(len(CASES) + 1)])
        for p in made:
            if os.path.isdir(p):
                shutil.rmtree(p)
                if os.path.isdir(p + ".out"):
                    shutil.rmtree(p + ".out")
            elif os.path.exists(p):
                os.remove(p)
        for f in os.listdir(os.path.join(sysd, "bp.out")):
            if f.startswith("zzoq"):
                os.remove(os.path.join(sysd, "bp.out", f))

    run_verbs(box, sysd, bp)

    say("\nsandbox-oq2: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


def has(out, pat):
    return re.search(pat, out, re.M) is not None


def slurp(path):
    try:
        with open(path, "rb") as f:
            return f.read()
    except OSError:
        return None


def run_verbs(box, sysd, bp):
    """The new commands and subroutines (A-14): OSCOPY, IOSCOPY, COMPARE.FILES, FIXDIR, MULTISORT."""
    say("\n--- the new commands ----------------------------------------------------------")
    d = os.path.join(sysd, "zzoqw")
    shutil.rmtree(d, ignore_errors=True)
    os.makedirs(d)
    a, b = os.path.join(d, "a"), os.path.join(d, "b")
    write(a, "hello\n")
    probe = os.path.join(bp, "zzoqp1")
    made = [probe]
    try:
        # --- OSCOPY (517) -------------------------------------------------------------------------------
        out = sess(box, "OSCOPY %s %s" % (a, b))
        row("517: OSCOPY copies a file", has(out, r"copied to") and slurp(b) == b"hello\n", out[-120:])
        out = sess(box, "OSCOPY %s %s" % (a, b))
        row("517: and refuses to replace it without an option", has(out, r"already exists") and slurp(b) == b"hello\n", out[-120:])
        out = sess(box, "OSCOPY %s %s APPEND" % (a, b))
        row("517: APPEND adds the source to the end of the target", slurp(b) == b"hello\nhello\n", repr(slurp(b)))
        write(a, "new\n")
        out = sess(box, "OSCOPY %s %s OVERWRITE" % (a, b))
        row("517: OVERWRITE replaces it", slurp(b) == b"new\n", repr(slurp(b)))
        out = sess(box, "OSCOPY %s %s" % (os.path.join(d, "none"), os.path.join(d, "c")))
        row("517: a missing source is reported", has(out, r"not found") and slurp(os.path.join(d, "c")) is None, out[-120:])

        # --- !IOSCOPY (369) and !MULTISORT (568) through a probe program --------------------------------------
        sub = os.path.join(d, "tree", "sub")
        os.makedirs(sub)
        write(os.path.join(d, "tree", "f1"), "one\n")
        write(os.path.join(sub, "f2"), "two\n")
        write(probe, ("   call !ioscopy('%s', '%s', st1)\n"
                      "   data = 'b':@vm:'c':@vm:'a':@fm:'2':@vm:'3':@vm:'1':@fm:'x':@vm:'y':@vm:'z'\n"
                      "   call !multisort(data, 1, 'AL')\n"
                      "   crt 'P1[':st1:'/':change(change(data, @fm, '|'), @vm, ','):']'\n"
                      "   data2 = '10':@vm:'9':@vm:'100':@fm:'p':@vm:'q':@vm:'r'\n"
                      "   call !multisort(data2, 1, 'DR')\n"
                      "   crt 'P2[':change(change(data2, @fm, '|'), @vm, ','):']'\n"
                      "end\n") % (os.path.join(d, "tree"), os.path.join(d, "tree2")))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("369: IOSCOPY copies a directory tree",
            slurp(os.path.join(d, "tree2", "sub", "f2")) == b"two\n" and slurp(os.path.join(d, "tree2", "f1")) == b"one\n",
            "tree2 not copied")
        row("369: and says status 0", has(out, r"^P1\[0/"), out[-200:])
        row("568: MULTISORT sorts list 1 and carries the others (stable, ascending left)",
            has(out, r"^P1\[0/a,b,c\|1,2,3\|z,x,y\]"), out[-200:])
        row("568: DR sorts numerically descending, and the related list follows",
            has(out, r"^P2\[100,10,9\|r,p,q\]"), out[-200:])

        # --- FIXDIR (458) ---------------------------------------------------------------------------------
        sess(box, "DELETE.FILE zzoqfd", "CREATE.FILE zzoqfd DIRECTORY")
        fd = os.path.join(sysd, "zzoqfd")
        write(os.path.join(fd, "r1"), "a\r\nb\r\n")
        write(os.path.join(fd, "r2"), "clean\n")
        out = sess(box, "FIXDIR zzoqfd")
        row("458: FIXDIR removes the carriage returns", slurp(os.path.join(fd, "r1")) == b"a\nb\n", repr(slurp(os.path.join(fd, "r1"))))
        row("458: and leaves a clean record alone and says how many it fixed",
            slurp(os.path.join(fd, "r2")) == b"clean\n" and has(out, r"1 record\(s\) fixed in zzoqfd"), out[-150:])

        # --- COMPARE.FILES (534) --------------------------------------------------------------------------
        write(probe, ("   execute 'CREATE.FILE zzoqc1' capturing j1\n"
                      "   execute 'CREATE.FILE zzoqc2' capturing j2\n"
                      "   open 'zzoqc1' to f1 else stop\n"
                      "   open 'zzoqc2' to f2 else stop\n"
                      "   write 'same' on f1, 'k1'\n   write 'same' on f2, 'k1'\n"
                      "   write 'left' on f1, 'k2'\n   write 'right' on f2, 'k2'\n"
                      "   write 'x' on f1, 'k3'\n"
                      "   write 'y' on f2, 'k4'\n"
                      "end\n"))
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        out = sess(box, "COMPARE.FILES zzoqc1 zzoqc2 DETAIL")
        row("534: COMPARE.FILES counts the records only in the first", has(out, r"Records only in zzoqc1: 1") and has(out, r"^   k3"), out[-300:])
        row("534: only in the second", has(out, r"Records only in zzoqc2: 1") and has(out, r"^   k4"), out[-300:])
        row("534: those that differ", has(out, r"Records in both that differ: 1") and has(out, r"^   k2"), out[-300:])
        row("534: and those that are the same", has(out, r"Records that are the same: 1"), out[-300:])
        out = sess(box, "COMPARE.FILES zzoqc1 zzoqc1")
        row("534: a file against itself differs in nothing",
            has(out, r"Records only in zzoqc1: 0") and has(out, r"Records in both that differ: 0") and has(out, r"same: 3"), out[-300:])

        # --- MAP NO.PAGE / LOCAL, CATALOG RELATIVE, OPTION CATALOGUE.LOCAL, OPTION DIR.SEL.OMIT.HIDDEN ----------
        lc = os.path.join(bp, "zzoqlc")
        lr = os.path.join(bp, "zzoqlr")
        made += [lc, lr]
        write(lc, "   crt 'RAN_LC'\nend\n")
        write(lr, "   crt 'RAN_LR'\nend\n")
        out = sess(box, "BASIC bp zzoqlc", "BASIC bp zzoqlr", "CATALOG bp zzoqlc LOCAL", "MAP LOCAL NO.PAGE")
        row("287: MAP LOCAL lists the locally catalogued programs", has(out, r"^L\s+zzoqlc") and not has(out, r"^\*"), out[-300:])
        row("153: MAP ... NO.PAGE runs and still ends with its total", has(out, r"Total:"), out[-300:])
        out = sess(box, "CATALOG bp zzoqlr LOCAL RELATIVE", "ZZOQLR")
        read_voc = sess(box, "CT VOC zzoqlr")
        row("131: CATALOG ... LOCAL RELATIVE keeps a relative path in the VOC pointer",
            has(read_voc, r"^1: V") and has(read_voc, r"^3: bp\.out/zzoqlr") and not has(read_voc, r"^3: /"), read_voc[-300:])
        row("131: and the program still runs through it", has(out, r"RAN_LR"), out[-200:])
        sess(box, "DELETE.CATALOG zzoqlc LOCAL", "DELETE.CATALOG zzoqlr LOCAL")
        out = sess(box, "OPTION CATALOGUE.LOCAL", "CATALOG bp zzoqlc", "DELETE.CATALOG zzoqlc")
        row("288: with OPTION CATALOGUE.LOCAL, CATALOG with no mode catalogues locally", has(out, r"added to local catalogue"), out[-300:])
        row("288: and DELETE.CATALOG deletes the local entry by default", not has(out, r"not found|not in"), out[-300:])
        out = sess(box, "MAP LOCAL")
        row("288: after that no local entry is left", not has(out, r"zzoqlc"), out[-200:])

        # --- 210 CATALOG ... GLOBAL c: the prefix character for names that have none ------------------------
        gc = os.path.join(bp, "zzoqgp")
        gd = os.path.join(bp, "zzoqgq")
        made += [gc, gd]
        write(gc, "   subroutine zzoqgp(r)\n   r = 'RAN_GP'\n   return\nend\n")
        write(gd, "   subroutine zzoqgq(r)\n   r = 'RAN_GQ'\n   return\nend\n")
        gdir = os.path.join(sysd, "gcat")
        # the kernel stores a * in a file name as %A, so the global entry *zzoqgp is the file %Azzoqgp
        gnames = ("zzoqgp", "%Azzoqgp", "$zzoqgp", "%Azzoqgq", "!zzoqgq", "%A$zzoqgp")
        for g in gnames:
            if os.path.exists(os.path.join(gdir, g)):
                os.remove(os.path.join(gdir, g))
        try:
            out = sess(box, "BASIC bp zzoqgp", "BASIC bp zzoqgq", "CATALOG bp zzoqgp GLOBAL")
            row("210 CONTROL: GLOBAL with no prefix catalogues under the bare name",
                os.path.exists(os.path.join(gdir, "zzoqgp")) and not os.path.exists(os.path.join(gdir, "%Azzoqgp")), out[-300:])
            os.remove(os.path.join(gdir, "zzoqgp"))
            out = sess(box, "CATALOG bp zzoqgp GLOBAL *")
            row("210 GLOBAL * puts the prefix on a name that has none",
                os.path.exists(os.path.join(gdir, "%Azzoqgp")) and not os.path.exists(os.path.join(gdir, "zzoqgp"))
                and has(out, r"added to global catalogue"), out[-300:])
            out = sess(box, "CATALOG bp zzoqgp GLOBAL $")
            row("210 another prefix character, $", os.path.exists(os.path.join(gdir, "$zzoqgp")), out[-300:])
            os.remove(os.path.join(gdir, "$zzoqgp"))
            out = sess(box, "CATALOG bp $zzoqgp GLOBAL *")
            row("210 a name that already has a prefix keeps its own (no ** or *$)",
                os.path.exists(os.path.join(gdir, "$zzoqgp")) and not os.path.exists(os.path.join(gdir, "%A$zzoqgp")) and not os.path.exists(os.path.join(gdir, "$$zzoqgp")), out[-300:])
            out = sess(box, "SELECT bp WITH @ID = 'zzoqgq'", "CATALOG bp GLOBAL !")
            row("210 with a select list the prefix is put on each program",
                os.path.exists(os.path.join(gdir, "!zzoqgq")), out[-300:])
            out = sess(box, "CATALOG bp zzoqgq GLOBAL ?")
            row("210 a character that is not a prefix is refused and nothing is catalogued",
                not os.path.exists(os.path.join(gdir, "?zzoqgq")) and not os.path.exists(os.path.join(gdir, "zzoqgq")), out[-300:])
            out = sess(box, "CATALOG bp zzoqgp LOCAL *")
            row("210 a prefix without GLOBAL is refused", not has(out, r"added to local catalogue"), out[-300:])
            sess(box, "DELETE.CATALOG zzoqgp LOCAL")
        finally:
            for g in gnames:
                if os.path.exists(os.path.join(gdir, g)):
                    os.remove(os.path.join(gdir, g))

        # --- SHOW: B for the last page (477), SORT.SUP (495), record ids not in the file (524) ---------------------
        mk = os.path.join(bp, "zzoqshm")
        rd = os.path.join(bp, "zzoqshr")
        made += [mk, rd]
        write(mk, ("   execute 'CREATE.FILE zzoqsh1 DYNAMIC' capturing junk\n"
                   "   execute 'CREATE.FILE zzoqsh2 DYNAMIC' capturing junk\n"
                   "   open 'zzoqsh1' to f1 else stop 'no zzoqsh1'\n"
                   "   open 'zzoqsh2' to f2 else stop 'no zzoqsh2'\n"
                   "   for i = 1 to 30\n"
                   "      write 'name':i to f1, 'r':fmt(i, 'R%2')\n"
                   "   next i\n"
                   "   ids = 'q7,b2,m9,a1,z3,k5,d8,x4,c6,y0,e2,w1'\n"
                   "   for i = 1 to 12\n"
                   "      write 'name':i to f2, field(ids, ',', i)\n"
                   "   next i\n"
                   "end\n"))
        write(rd, ("   readlist items from 0 else items = 'NONE'\n"
                   "   crt 'ITEMS[':change(items, @fm, ','):']'\n"
                   "end\n"))
        sess(box, "DELETE.FILE zzoqsh1", "DELETE.FILE zzoqsh2")
        out = sess(box, "BASIC bp zzoqshm", "BASIC bp zzoqshr", "RUN bp zzoqshm")
        try:
            def show_list(*cmds):
                """Run the commands (a SHOW and its answers), then read list 0; returns (text, ordered ids or None)."""
                text = sess(box, *(list(cmds) + ["RUN bp zzoqshr"]))
                m = re.search(r"(?m)^ITEMS\[(.*)\]\s*$", text)
                return text, (m.group(1).split(",") if m else None)

            def ids(lo, hi):
                return ["r%02d" % n for n in range(lo, hi + 1)]

            # a 15-line screen gives 10 records to a page, so the 30 records are three pages
            text, got = show_list("TERM 120,15", "SHOW zzoqsh1", "S VIS", "Q")
            row("477 CONTROL: the first page holds r01 to r10", got == ids(1, 10), "%r %s" % (got, text[-300:]))
            text, got = show_list("TERM 120,15", "SHOW zzoqsh1", "N", "S VIS", "Q")
            row("477 CONTROL: N moves to the second page, r11 to r20", got == ids(11, 20), "%r %s" % (got, text[-300:]))
            text, got = show_list("TERM 120,15", "SHOW zzoqsh1", "B", "S VIS", "Q")
            row("477 B moves to the bottom page, r21 to r30", got == ids(21, 30), "%r %s" % (got, text[-300:]))
            text, got = show_list("TERM 120,15", "SHOW zzoqsh1", "B", "T", "S VIS", "Q")
            row("477 T still goes back to the top after B", got == ids(1, 10), "%r %s" % (got, text[-300:]))
            text, got = show_list("TERM 120,15", "SHOW zzoqsh1", "B", "B", "P", "S VIS", "Q")
            row("477 B on the bottom page stays there, and P then goes to the one before", got == ids(11, 20), "%r %s" % (got, text[-300:]))
            text, got = show_list("TERM 120,15", "SHOW zzoqsh1", "b", "S VIS", "Q")
            row("477 a lower-case b does the same", got == ids(21, 30), "%r %s" % (got, text[-300:]))

            text, native = show_list("SELECT zzoqsh2")
            row("495 CONTROL: the file is not held in id order, so SORT.SUP can be seen", native is not None and native != sorted(native) and len(native) == 12,
                "%r %s" % (native, text[-300:]))
            text, got = show_list("SHOW zzoqsh2", "S ALL", "Q")
            row("495 CONTROL: SHOW with no sort clause lists the records in id order", got == sorted(native or []) and len(got or []) == 12, "%r %s" % (got, text[-300:]))
            text, got = show_list("SHOW zzoqsh2 SORT.SUP", "S ALL", "Q")
            row("495 SORT.SUP leaves them in the order the file gives them", got == native, "%r %r" % (got, native))
            text, got = show_list("SHOW zzoqsh2 BY @ID SORT.SUP", "S ALL", "Q")
            row("495 a sort clause still sorts, with SORT.SUP present", got == sorted(native or []) and len(got or []) == 12, "%r %s" % (got, text[-300:]))

            text, got = show_list("SHOW zzoqsh2 a1 b2", "S ALL", "Q")
            row("524 CONTROL: record ids that are all in the file give the list", got == ["a1", "b2"], "%r %s" % (got, text[-300:]))
            text, got = show_list("SHOW zzoqsh2 a1 zznone1 b2 zznone2")
            row("524 ids not in the file are listed, one per line", has(text, r"(?m)^'zznone1' not found") and has(text, r"(?m)^'zznone2' not found"), text[-400:])
            row("524 ...and SHOW stops there: no screen is drawn and no list is made",
                got == ["NONE"] and not has(text, r"Select, Clear, Top") and not has(text, r"record\(s\) selected"), "%r %s" % (got, text[-400:]))
        finally:
            sess(box, "DELETE.FILE zzoqsh1", "DELETE.FILE zzoqsh2")
        hd = os.path.join(sysd, "zzoqhd")
        sess(box, "DELETE.FILE zzoqhd", "CREATE.FILE zzoqhd DIRECTORY")
        write(os.path.join(hd, "visible"), "x\n")
        write(os.path.join(hd, ".hidden"), "x\n")
        out = sess(box, "SELECT zzoqhd", "OPTION DIR.SEL.OMIT.HIDDEN", "SELECT zzoqhd")
        counts = re.findall(r"(\d+) record\(s\) selected", out)
        row("445: SELECT of a directory file sees the dot file without the option and not with it",
            counts[:2] == ["2", "1"], repr(counts) + out[-200:])
        sess(box, "DELETE.FILE zzoqhd")

        # --- PHANTOM NO.MSG / DATA / LOG and !PHLOG (483, 137, 364, 87) ----------------------------------------
        got = os.path.join(bp, "zzoqph")
        made.append(got)
        write(got, "   input x\n   open 'VOC' to v else stop\n   write 'Y':@fm:x on v, 'zzph_got'\nend\n")
        sess(box, "BASIC bp zzoqph", "CATALOG bp zzoqph LOCAL", "DELETE.FILE zzcd2", "CREATE.FILE zzcd2 DIRECTORY")
        write(probe, ("   execute 'PHANTOM LIST.FILES' capturing o1\n   crt 'M1[':o1:']'\n"
                      "   execute 'PHANTOM NO.MSG LIST.FILES' capturing o2\n   uid = @system.return.code\n   crt 'M2[':o2:']'\n"
                      "   data 'zz_data_line'\n   execute 'PHANTOM NO.MSG DATA RUN bp zzoqph' capturing o3\n"
                      "   execute 'PHANTOM NO.MSG LOG zzcd2 LIST.FILES' capturing o4\n"
                      "   sleep 8\n"
                      "   call !phlog(uid, nm)\n   crt 'PHL[':nm:']'\n"
                      "   open 'VOC' to v else stop\n   read r from v, 'zzph_got' then crt 'GOT[':r<2>:']' else crt 'GOT[none]'\n"
                      "   delete v, 'zzph_got'\n   crt 'UID[':uid:']'\n"
                      "   crt 'LEFT[':@data.pending:']'\nend\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("483 CONTROL: PHANTOM says that it started a phantom", has(out, r"^M1\[Started phantom user \d+"), out[-600:])
        row("483: PHANTOM NO.MSG does not", has(out, r"^M2\[\]"), out[-600:])
        row("137: PHANTOM DATA passes the DATA queue to the phantom, which read it with INPUT",
            has(out, r"^GOT\[zz_data_line\]"), out[-600:])
        row("137: and the parent's queue is empty afterwards", has(out, r"^LEFT\[\]"), out[-600:])
        row("87: !PHLOG returns the phantom's log record, PH<user>_...",
            re.search(r"(?m)^PHL\[(PH(\d+)_\S+)\]", out) is not None and
            re.search(r"(?m)^UID\[(\d+)\]", out) is not None and
            re.search(r"(?m)^PHL\[PH(\d+)_", out).group(1) == re.search(r"(?m)^UID\[(\d+)\]", out).group(1), out[-600:])
        zl = [n for n in os.listdir(os.path.join(sysd, "zzcd2"))] if os.path.isdir(os.path.join(sysd, "zzcd2")) else []
        row("364: PHANTOM LOG zzcd2 puts the phantom's log in that directory file", any(n.startswith("PH") for n in zl), repr(zl))
        sess(box, "DELETE.CATALOG zzoqph LOCAL", "DELETE.FILE zzcd2")

        # --- PDUMP statement, string length and environment in the dump (439, 22, 569) --------------------------
        import glob
        for old in glob.glob(os.path.join(sysd, "dumps", "sddump.*")):
            os.remove(old)
        write(probe, "   zzvar = 'abcdefghij'\n   pdump\n   crt 'AFTER_PDUMP'\nend\n")
        os.environ["ZZ_OQ_TOKEN"] = "s3cr3tvalue"
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        del os.environ["ZZ_OQ_TOKEN"]
        dumps = glob.glob(os.path.join(sysd, "dumps", "sddump.*"))
        dtxt = (slurp(dumps[0]) or b"").decode("latin-1") if dumps else ""
        row("439: the PDUMP statement writes a process dump file and the program goes on",
            len(dumps) == 1 and has(out, r"AFTER_PDUMP") and "SD Process Dump" in dtxt, "dumps=%r out=%r" % (dumps, out[-200:]))
        row("22: the dump shows the length of a string variable", re.search(r'(?i)zzvar: String \(len=10\): "abcdefghij"', dtxt) is not None,
            dtxt[:600])
        row("569: the dump lists the environment, and hides the value of a name that looks like a secret",
            "\nEnvironment\n" in dtxt and re.search(r"(?m)^  PATH=", dtxt) is not None and "=(not shown)" not in "".join(
                l for l in dtxt.splitlines() if l.startswith("  PATH=")), dtxt[:400])
        row("569: a variable named TOKEN is listed with its value left out",
            "ZZ_OQ_TOKEN=(not shown)" in dtxt and "s3cr3tvalue" not in dtxt, dtxt[:300])
        for old in dumps:
            os.remove(old)

        # --- Q-pointer with a null file name means VOC (435) ------------------------------------------------
        write(probe, ("   open 'VOC' to v else stop\n   write 'Q':@fm:'':@fm:'' on v, 'zzqnull'\n"
                      "   open 'zzqnull' to f then\n      read r from f, 'zzqnull' then crt 'QN[':r<1>:']' else crt 'QN[norec]'\n"
                      "   end else crt 'QN[noopen]'\n   delete v, 'zzqnull'\nend\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("435: a Q-pointer whose file name is null opens the VOC of the account (here: reads its own record, a Q)",
            has(out, r"^QN\[Q\]"), out[-300:])

        # --- LOGOUT n GROUP (386) ---------------------------------------------------------------------------
        sl = os.path.join(bp, "zzoqsl")
        gp = os.path.join(bp, "zzoqgp")
        gc = os.path.join(bp, "zzoqgc")
        made += [sl, gp, gc]
        write(sl, "   sleep 60\nend\n")
        write(gp, ("   execute 'PHANTOM NO.MSG RUN bp zzoqsl'\n   execute 'PHANTOM NO.MSG RUN bp zzoqsl'\n"
                   "   open 'VOC' to v else stop\n   write 'Y':@fm:@userno on v, 'zzgrp_parent'\n   sleep 40\nend\n"))
        write(gc, ("   include_users = 0\n   open 'VOC' to v else stop\n   read r from v, 'zzgrp_parent' else stop\n   n = r<2>\n"
                   "   gosub count\n   crt 'G1[':c:']'\n"
                   "   execute 'LOGOUT ':n:' GROUP'\n   sleep 4\n   gosub count\n   crt 'G2[':c:']'\n"
                   "   delete v, 'zzgrp_parent'\n   stop\n"
                   "count:\n   c = 0\n   call !listu(u)\n   for i = 1 to dcount(u, @fm)\n"
                   "      if u<i,5> + 0 = n then c += 1\n   next i\n   return\nend\n"))
        sess(box, "BASIC bp zzoqsl", "BASIC bp zzoqgp", "BASIC bp zzoqgc")
        pg = subprocess.Popen([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts"), "RUN bp zzoqgp"],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        time.sleep(9)
        out = sess(box, "RUN bp zzoqgc")
        try:
            pg.wait(timeout=90)
        except subprocess.TimeoutExpired:
            pg.kill()
        row("386 CONTROL: the parent has two phantoms before the LOGOUT", has(out, r"^G1\[2\]"), out[-400:])
        row("386: LOGOUT n GROUP logs out the parent's phantoms as well", has(out, r"^G2\[0\]"), out[-400:])

        # --- OPENSEQ CREATING and SHARED (485, 397) --------------------------------------------------------
        sq = os.path.join(d, "sq.txt")
        sh = os.path.join(d, "shared.txt")
        hp = []
        for tag in ("A", "B"):
            pth = os.path.join(bp, "zzoqs" + tag)
            made.append(pth)
            hp.append(pth)
            write(pth, ("   openseq '%s' shared to f else stop\n   for i = 1 to 300\n      writeseq '%s' : i : ' ' : str('x', 40) to f else stop\n"
                        "   next i\n   closeseq f\nend\n") % (sh, tag))
        write(probe, ("   openseq '%s' to f then crt 'EXISTS_BEFORE' else crt 'MISSING_BEFORE'\n"
                      "   openseq '%s' creating to g then crt 'THEN_G' else crt 'ELSE_G'\n"
                      "   closeseq g\nend\n") % (sq, sq))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("485: OPENSEQ without CREATING of a file that is not there takes the ELSE", has(out, r"MISSING_BEFORE"), out[-300:])
        row("485: OPENSEQ ... CREATING makes the file at once and takes the THEN", has(out, r"THEN_G") and os.path.exists(sq), out[-300:])
        sess(box, "BASIC bp zzoqsA", "BASIC bp zzoqsB")
        pa = subprocess.Popen([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts"), "RUN bp zzoqsA"],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        pb = subprocess.Popen([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts"), "RUN bp zzoqsB"],
                              stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        pa.wait(timeout=120)
        pb.wait(timeout=120)
        body = (slurp(sh) or b"").decode("latin-1")
        lines = [l for l in body.split("\n") if l]
        row("397: two processes appending with SHARED lose no line (600 written, 600 found)", len(lines) == 600,
            "found %d lines" % len(lines))
        row("397: and every line is whole (a number, a space and 40 x)",
            all(re.fullmatch(r"[AB]\d+ x{40}", l) for l in lines), "a damaged line: %r" % [l for l in lines if not re.fullmatch(r"[AB]\d+ x{40}", l)][:2])

        # --- LIST.TRIGGERS with a directory file (321) ----------------------------------------------------------
        trg = os.path.join(bp, "zzoqtr")
        made.append(trg)
        write(trg, "subroutine zzoqtr(mode, file, id, rec, ctl)\n   return\nend\n")
        out = sess(box, "BASIC bp zzoqtr", "CATALOG bp zzoqtr LOCAL", "CREATE.FILE zzoqtd DIRECTORY",
                   "SET.TRIGGER zzoqtd zzoqtr PRE.WRITE", "LIST.TRIGGERS zzoqtd")
        # 16 Oct 26 (QM4 Fixes item 177): this row said SD refuses a trigger on a directory file ("Dynamic file required") and that
        # LIST.TRIGGERS had none to show.  A directory file takes a trigger now (sandbox-dirtrig.py has the rows), so it is listed.
        row("321: a trigger on a directory file is accepted (QM4 Fixes 177), and LIST.TRIGGERS lists it with its mode",
            not has(out, r"Dynamic file required") and has(out, r"(?m)^zzoqtd\s+zzoqtr\s+PRE\.WRITE"), out[-500:])
        sess(box, "DELETE.CATALOG zzoqtr LOCAL", "DELETE.FILE zzoqtd")

        # --- CREATE.FILE COMMENT, MULTIFILE and a relative PATHNAME (383, 522, 278) ----------------------------
        os.makedirs(os.path.join(sysd, "zzoqreld"), exist_ok=True)
        sess(box, "DELETE.FILE zzoqcm", "DELETE.FILE zzoqmf", "DELETE.FILE zzoqrp")
        out = sess(box, 'CREATE.FILE zzoqcm COMMENT "Test file here"', "CT VOC zzoqcm", "CREATE.FILE zzoqmf MULTIFILE",
                   "CT VOC zzoqmf", "CREATE.FILE zzoqrp PATHNAME zzoqreld", "CT VOC zzoqrp")
        row("383: CREATE.FILE ... COMMENT puts the text after the type code in the VOC record", has(out, r"^1: F Test file here"), out[-700:])
        row("522: CREATE.FILE ... MULTIFILE makes the data portion a multifile named for the file",
            has(out, r"^4: zzoqmf"), out[-700:])
        row("278: a relative PATHNAME stays relative in the VOC record", has(out, r"^2: zzoqreld/zzoqrp"), out[-700:])
        sess(box, "DELETE.FILE zzoqcm", "DELETE.FILE zzoqmf", "DELETE.FILE zzoqrp")
        shutil.rmtree(os.path.join(sysd, "zzoqreld"), ignore_errors=True)

        # --- saved lists IN file (494), CREATE.INDEX DELETING and $INDEX.PATH (424, 184), LIST.INDEX LPTR (73) ----
        write(probe, ("   execute 'CREATE.FILE zzix' capturing j1\n   open 'zzix' to f else stop\n"
                      "   open 'DICT', 'zzix' to dv else stop\n"
                      "   write 'D':@fm:'1':@fm:'':@fm:'Fld':@fm:'10L':@fm:'S' on dv, 'FLD'\n"
                      "   write 'b' on f, 'r1'\n   write 'a' on f, 'r2'\n"
                      "   execute 'CREATE.FILE zzsl' capturing j2\n"
                      "   formlist 'p':@fm:'q':@fm:'r' to 0\nend\n"))
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        out = sess(box, "CREATE.INDEX zzix FLD", "CREATE.INDEX zzix FLD")
        row("424 CONTROL: a second CREATE.INDEX of the same index is refused", has(out, r"Duplicate field name \(FLD\)"), out[-400:])
        out = sess(box, "CREATE.INDEX zzix FLD DELETING", "LIST.INDEX zzix ALL")
        row("424: CREATE.INDEX ... DELETING replaces it", not has(out, r"Duplicate field name") and has(out, r"Number of indices = 1"), out[-400:])
        out = sess(box, "LIST.INDEX zzix ALL LPTR")
        row("73: LIST.INDEX ... LPTR sends the report to the printer, not the screen",
            not has(out, r"Alternate key indices for file") and not has(out, r"(?i)unexpected"), out[-300:])
        ixd = os.path.join(d, "ixdir")      # must not exist yet: the first index makes the directory
        sess(box, "DELETE.INDEX zzix ALL")
        write(probe, ("   open 'VOC' to v else stop\n   write 'X':@fm:'%s' on v, '$INDEX.PATH'\nend\n" % ixd))
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        out = sess(box, "CREATE.INDEX zzix FLD", "LIST.INDEX zzix ALL")
        row("184: CREATE.INDEX with no PATHNAME uses the $INDEX.PATH record", has(out, r"Indices relocated to") and ixd in out, out[-400:])
        sess(box, "DELETE.INDEX zzix ALL")
        write(probe, "   open 'VOC' to v else stop\n   delete v, '$INDEX.PATH'\nend\n")
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        out = sess(box, "CREATE.INDEX zzix FLD", "LIST.INDEX zzix ALL")
        row("184: and without that record there is no relocation", not has(out, r"Indices relocated to"), out[-300:])
        write(probe, "   formlist 'p':@fm:'q':@fm:'r' to 0\nend\n")
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1", "SAVE.LIST zzsl1 IN zzsl", "GET.LIST zzsl1 IN zzsl", "GET.LIST zzsl1")
        row("494: SAVE.LIST ... IN file saves in that file and GET.LIST ... IN file reads it back",
            has(out, r"3 record\(s\) selected"), out[-400:])
        row("494: the default saved lists file does not hold it (there is none here, or the list is not in it)",
            has(out, r"Error \d+ opening \$savedlists|Saved select list 'zzsl1' not found"), out[-400:])
        out = sess(box, "DELETE.LIST zzsl1 IN zzsl")
        row("494: DELETE.LIST ... IN file deletes it", has(out, r"Deleted saved select list 'zzsl1'"), out[-300:])
        sess(box, "DELETE.FILE zzix", "DELETE.FILE zzsl")

        # --- inline prompts: control letters in any case, quoted prompt text (171, 377) ---------------------------
        out = sess(box, "SH echo cap_<<A,Name>>_end", "xyz")
        row("171 CONTROL: <<A,Name>> prompts and substitutes the answer", has(out, r"^cap_xyz_end") and has(out, r"Name="), out[-200:])
        out = sess(box, "SH echo low_<<a,Name>>_end", "xyz")
        row("171: <<a,Name>> is the same with a lower case control", has(out, r"^low_xyz_end") and has(out, r"Name="), out[-200:])
        out = sess(box, "SH echo u_<<u,Name>>_end", "xyz")
        row("171: <<u,Name>> (lower case) makes the answer upper case", has(out, r"^u_XYZ_end"), out[-200:])
        out = sess(box, 'SH echo quo_<<A,"Name, please">>_end', "xyz")
        row("377: a quoted prompt text may hold a comma and is shown whole",
            has(out, r"^quo_xyz_end") and has(out, r"Name, please="), out[-250:])

        # --- !OPTION, !VOCPATH, DIR() size (224, 473, 86, 366) ----------------------------------------------------
        sz = os.path.join(d, "sizedir")
        os.makedirs(sz, exist_ok=True)
        write(os.path.join(sz, "f5"), "abcde")
        write(probe, ("   st = ''\n   call !option(40, st)\n   crt 'O1[':st:']'\n"
                      "   st = 1\n   call !option(40, st)\n   st = ''\n   call !option(40, st)\n   crt 'O2[':st:']'\n"
                      "   st = 0\n   call !option(40, st)\n   crt 'O3[':st:']'\n"
                      "   st = ''\n   call !option(999, st)\n   crt 'O4[':st:']'\n"
                      "   call !vocpath('bp', p, s)\n   crt 'V1[':s:'/':(p[len(p) - 1, 2] = 'bp'):']'\n"
                      "   call !vocpath('nonesuchfile', p, s)\n   crt 'V2[':(s # 0):'/':p:']'\n"
                      "   e = dir('%s')\n   crt 'D1[':e<1,1>:'/':e<1,2>:'/':e<1,3>:']'\nend\n") % sz)
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("224 CONTROL: !OPTION reads an option that is off", has(out, r"^O1\[0\]"), out[-400:])
        row("473: !OPTION sets an option and reads it back as on", has(out, r"^O2\[1\]"), out[-400:])
        row("473: and clears it again", has(out, r"^O3\[0\]"), out[-400:])
        row("473: a number that is not an option comes back -1", has(out, r"^O4\[-1\]"), out[-400:])
        row("86: !VOCPATH gives the path of a VOC file name and status 0", has(out, r"^V1\[0/1\]"), out[-400:])
        row("86: and a status and a null path for a name that is not there", has(out, r"^V2\[1/\]"), out[-400:])
        row("366: DIR() returns the size in bytes as a third value", has(out, r"^D1\[f5/F/5\]"), out[-400:])

        # --- MATSTR of a matrix passed to a subroutine (509) -----------------------------------------------------
        ms = os.path.join(bp, "zzoqms")
        made.append(ms)
        write(ms, "   subroutine zzoqms(mat a, out)\n   dim a(2, 2)\n   out = matstr(a)\n   return\nend\n")
        write(probe, ("   dim m(2, 2)\n   m(1, 1) = 'p' ; m(1, 2) = 'q' ; m(2, 1) = 'r' ; m(2, 2) = 's'\n"
                      "   call zzoqms(mat m, r)\n   crt 'MS[':change(change(r, @vm, ','), @fm, '/'):']'\nend\n"))
        out = sess(box, "BASIC bp zzoqms", "CATALOG bp zzoqms LOCAL", "BASIC bp zzoqp1", "RUN bp zzoqp1", "DELETE.CATALOG zzoqms LOCAL")
        row("509: MATSTR of a matrix passed into a subroutine", has(out, r"^MS\[p,q/r,s\]"), out[-400:])

        # --- SETPTR INFORM and EJECT (51, 59) --------------------------------------------------------------------
        hold = os.path.join(sysd, "$hold")
        for nm in ("zzoqjob", "zzoqjob2"):
            if os.path.exists(os.path.join(hold, nm)):
                os.remove(os.path.join(hold, nm))
        write(probe, "   printer on\n   print 'line one'\n   printer close\nend\n")
        out = sess(box, "SETPTR 0,80,60,0,0,3,AS zzoqjob,INFORM,EJECT,BRIEF", "BASIC bp zzoqp1", "RUN bp zzoqp1")
        body = slurp(os.path.join(hold, "zzoqjob")) or b""
        row("51: SETPTR ... INFORM says where the output file is when the job starts",
            has(out, r"Print output is going to .*zzoqjob"), out[-300:])
        row("59: SETPTR ... EJECT ends the job with a form feed", b"line one" in body and body.endswith(b"\f"), repr(body[-30:]))
        out = sess(box, "SETPTR 0,80,60,0,0,3,AS zzoqjob2,BRIEF", "RUN bp zzoqp1")
        body2 = slurp(os.path.join(hold, "zzoqjob2")) or b""
        row("51/59 CONTROL: without the options there is no message and no form feed at the end",
            not has(out, r"Print output is going to") and b"line one" in body2 and not body2.endswith(b"\f"), repr(body2[-30:]) + out[-200:])
        for nm in ("zzoqjob", "zzoqjob2"):
            if os.path.exists(os.path.join(hold, nm)):
                os.remove(os.path.join(hold, nm))
        sess(box, "DELETE.FILE zzoqhf", "CREATE.FILE zzoqhf DIRECTORY")
        sess(box, "SETPTR 0,80,60,0,0,3,AS zzjob3 IN zzoqhf,BRIEF", "RUN bp zzoqp1")
        body3 = slurp(os.path.join(sysd, "zzoqhf", "zzjob3")) or b""
        row("448: SETPTR ... AS name IN dirfile keeps the job in that directory file, not $HOLD",
            b"line one" in body3 and not os.path.exists(os.path.join(hold, "zzjob3")), repr(body3))
        sess(box, "DELETE.FILE zzoqhf")

        # --- SETPTR ... FORM.FEED (139): the sequence sent between pages --------------------------------------
        # Five lines to a page and no margins, eight lines of data: one page throw.
        write(probe, ("   printer on\n   for k = 1 to 8\n      print 'line ':k\n   next k\n   printer close\nend\n"))

        def job(*opts):
            nm = "zzoqff"
            if os.path.exists(os.path.join(hold, nm)):
                os.remove(os.path.join(hold, nm))
            o = sess(box, "SETPTR 0,40,5,0,0,3,AS %s,%sBRIEF" % (nm, "".join(x + "," for x in opts)), "BASIC bp zzoqp1", "RUN bp zzoqp1")
            b = slurp(os.path.join(hold, nm)) or b""
            if os.path.exists(os.path.join(hold, nm)):
                os.remove(os.path.join(hold, nm))
            return b, o

        body, o = job()
        row("139 CONTROL: by default a page throw is a carriage return and a form feed",
            b"line 8" in body and b"\r\f" in body and body.count(b"\f") == body.count(b"\r\f"), repr(body))
        body, o = job("FORM.FEED FF")
        row("139: FORM.FEED FF sends the form feed alone", b"line 8" in body and b"\f" in body and b"\r" not in body, repr(body))
        body, o = job("FORM.FEED CRFF")
        row("139: FORM.FEED CRFF is the default said out loud", b"\r\f" in body and body.count(b"\f") == body.count(b"\r\f"), repr(body))
        body, o = job("form.feed ff")
        row("139: the words may be in lower case", b"\f" in body and b"\r" not in body, repr(body))
        body, o = job("FORM.FEED FF", "NEWLINE CRLF")
        row("139: and it is the form feed only: with NEWLINE CRLF the line ends keep their CR but no FF has one",
            b"\r\n" in body and b"\f" in body and b"\r\f" not in body, repr(body))
        o = sess(box, "SETPTR 0,40,5,0,0,3,AS zzoqff,FORM.FEED XX,BRIEF")
        row("139: any other word is refused", has(o, r"FF or CRFF required after FORM\.FEED"), o[-300:])
        o = sess(box, "SETPTR 0,40,5,0,0,3,AS zzoqff,FORM.FEED FF,BRIEF", "SETPTR 0,DISPLAY")
        row("139: SETPTR 0,DISPLAY shows it, so a captured setting restores it", has(o, r"(?m)^\s*FORM\.FEED FF\s*$") or "FORM.FEED FF" in o, o[-400:])
        o = sess(box, "SETPTR 0,40,5,0,0,3,AS zzoqff,BRIEF", "SETPTR 0,DISPLAY")
        row("139 CONTROL: ...and says CRFF when it is the default", "FORM.FEED CRFF" in o and "FORM.FEED FF" not in o, o[-400:])

        # --- SETPTR ... AS NEXT: the digits of the sequence number (70) ---------------------------------------
        def nextjob(rec_fields):
            """Set the $NEXT record of the $HOLD dictionary, run one NEXT job, return (names made, record afterwards)."""
            for f in os.listdir(hold):
                if f.startswith("zzn"):
                    os.remove(os.path.join(hold, f))
            write(probe, ("   open 'DICT', '$hold' to df else stop 'no hold dict'\n"
                          "   write %s on df, '$NEXT'\n"
                          "   printer on\n   print 'next job'\n   printer close\n"
                          "   read r from df, '$NEXT' then crt 'REC[':change(r, @fm, '/'):']'\nend\n") % rec_fields)
            t = sess(box, "SETPTR 0,80,60,0,0,3,AS NEXT zzn,BRIEF", "BASIC bp zzoqp1", "RUN bp zzoqp1")
            made = sorted(f for f in os.listdir(hold) if f.startswith("zzn"))
            for f in made:
                os.remove(os.path.join(hold, f))
            m = re.search(r"(?m)^REC\[(.*)\]\s*$", t)
            return made, (m.group(1) if m else None), t

        made, rec, t = nextjob("'X':@fm:12")
        row("70 CONTROL: with no digit count the number is four digits and the counter moves on",
            made == ["zzn_0012"] and rec == "X/13", "%r %r %s" % (made, rec, t[-200:]))
        made, rec, t = nextjob("'X':@fm:5:@fm:3")
        row("70: field 3 = 3 makes the number three digits", made == ["zzn_005"] and rec == "X/6/3", "%r %r %s" % (made, rec, t[-200:]))
        made, rec, t = nextjob("'X':@fm:7:@fm:9")
        row("70: ...and 9 makes it nine", made == ["zzn_000000007"] and rec == "X/8/9", "%r %r %s" % (made, rec, t[-200:]))
        made, rec, t = nextjob("'X':@fm:999:@fm:3")
        row("70: the number cycles from the highest three digits hold back to 1", made == ["zzn_999"] and rec == "X/1/3", "%r %r %s" % (made, rec, t[-200:]))
        made, rec, t = nextjob("'X':@fm:9999")
        row("70: ...and by default from 9999 (it used to turn at 1000)", made == ["zzn_9999"] and rec == "X/1", "%r %r %s" % (made, rec, t[-200:]))
        made, rec, t = nextjob("'X':@fm:12:@fm:2")
        row("70: a digit count under 3 is ignored", made == ["zzn_0012"] and rec == "X/13/2", "%r %r %s" % (made, rec, t[-200:]))
        made, rec, t = nextjob("'X':@fm:12:@fm:'abc'")
        row("70: ...and so is one that is not a digit", made == ["zzn_0012"], "%r %r %s" % (made, rec, t[-200:]))
        made, rec, t = nextjob("'X':@fm:5000:@fm:3")
        row("70: a counter too big for its new digit count starts again at 1", made == ["zzn_001"] and rec == "X/2/3", "%r %r %s" % (made, rec, t[-200:]))

        # --- @SEQNO and GETPU(PU$SEQNO) (70) --------------------------------------------------------------------
        write(probe, ("   crt 'BEFORE[':@seqno:'/':getpu(1019, 0):']'\n"
                      "   open 'DICT', '$hold' to df else stop 'no hold dict'\n"
                      "   write 'X':@fm:12:@fm:5 on df, '$NEXT'\n"
                      "   printer on\n   print 'seq job'\n   printer close\n"
                      "   crt 'AFTER[':@seqno:'/':getpu(1019, 0):'/':getpu(1019, 1):']'\nend\n"))
        t = sess(box, "SETPTR 0,80,60,0,0,3,AS NEXT zzn,BRIEF", "BASIC bp zzoqp1", "RUN bp zzoqp1")
        for f in os.listdir(hold):
            if f.startswith("zzn"):
                os.remove(os.path.join(hold, f))
        row("70: @SEQNO and GETPU(PU$SEQNO) are null before a NEXT job", has(t, r"^BEFORE\[/\]"), t[-300:])
        row("70: ...and the number the file was given after one (@SEQNO, that unit, another unit)", has(t, r"^AFTER\[00012/00012/\]"), t[-300:])

        # --- HOLD.FILE.LOGGER, and $SETPTR.DEFAULTS (56) -----------------------------------------------------
        lg = os.path.join(bp, "hold.file.logger")
        made.append(lg)
        write(lg, ("   subroutine hold.file.logger(unit, opening, path)\n"
                   "   crt 'LOG[':unit:'/':opening:'/':path:']'\n   return\nend\n"))
        write(probe, "   printer on\n   print 'line one'\n   printer close\n   crt 'JOB DONE'\nend\n")
        for nm in ("zzoqlg", "zzoqlg6"):
            if os.path.exists(os.path.join(hold, nm)):
                os.remove(os.path.join(hold, nm))
        t = sess(box, "BASIC bp hold.file.logger", "CATALOG bp hold.file.logger LOCAL",
                 "SETPTR 0,80,60,0,0,3,AS zzoqlg,BRIEF", "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("56: a mode 3 job calls HOLD.FILE.LOGGER with the unit, 1 and the file name when the file opens",
            has(t, r"^LOG\[0/1/\$?hold/zzoqlg\]"), t[-400:])
        row("56: ...and again with 0 when it is closed", has(t, r"^LOG\[0/0/\$?hold/zzoqlg\]"), t[-400:])
        row("56: ...the open before the close", t.find("LOG[0/1/") != -1 and t.find("LOG[0/1/") < t.find("LOG[0/0/"), t[-400:])
        t = sess(box, "SETPTR 0,80,60,0,0,6,AS zzoqlg6,BRIEF", "RUN bp zzoqp1")
        row("56: mode 6 (file and printer) does too", has(t, r"^LOG\[0/1/") and has(t, r"^LOG\[0/0/"), t[-400:])
        t = sess(box, "SETPTR 0,80,60,0,0,1,BRIEF", "RUN bp zzoqp1")
        row("56: a plain printer job does not", not has(t, r"^LOG\[") and has(t, r"JOB DONE"), t[-400:])
        sess(box, "DELETE.CATALOG hold.file.logger LOCAL")
        t = sess(box, "SETPTR 0,80,60,0,0,3,AS zzoqlg,BRIEF", "RUN bp zzoqp1")
        row("56 CONTROL: with no such subroutine catalogued the job simply runs", not has(t, r"^LOG\[") and has(t, r"JOB DONE"), t[-400:])
        for nm in ("zzoqlg", "zzoqlg6"):
            if os.path.exists(os.path.join(hold, nm)):
                os.remove(os.path.join(hold, nm))

        write(probe, ("   write 'X':@fm:'NEWLINE CR':@fm:'':@fm:'NEWLINE CRLF, EJECT' on @voc, '$setptr.defaults'\n"
                      "   crt 'DEFAULTS SET'\nend\n"))
        t = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("56 CONTROL: the $SETPTR.DEFAULTS record was written", has(t, r"DEFAULTS SET"), t[-200:])
        write(probe, "   printer on\n   print 'one'\n   print 'two'\n   printer close\nend\n")
        for nm in ("zzoqdf", "zzoqdf2"):
            if os.path.exists(os.path.join(hold, nm)):
                os.remove(os.path.join(hold, nm))
        sess(box, "SETPTR 0,80,60,0,0,3,AS zzoqdf,BRIEF", "BASIC bp zzoqp1", "RUN bp zzoqp1")
        b = slurp(os.path.join(hold, "zzoqdf")) or b""
        row("56: the options for the mode (field 4 for mode 3) apply to a SETPTR that names none of them: CRLF line ends and EJECT",
            b"one\r\ntwo\r\n" in b and b.endswith(b"\f"), repr(b))
        sess(box, "SETPTR 0,80,60,0,0,3,AS zzoqdf2,NEWLINE LF,BRIEF", "RUN bp zzoqp1")
        b = slurp(os.path.join(hold, "zzoqdf2")) or b""
        row("56: an option in the command overrides the default (NEWLINE LF) and the rest of the defaults still apply (EJECT)",
            b"one\ntwo\n" in b and b"\r" not in b and b.endswith(b"\f"), repr(b))
        t = sess(box, "SETPTR 0,,,,,3", "SETPTR 0,DISPLAY")
        row("56: the defaults apply to a SETPTR with no options at all, SETPTR 0,,,,,3", has(t, r"NEWLINE CRLF") and has(t, r"EJECT"), t[-500:])
        t = sess(box, "SETPTR 0,,,,,1", "SETPTR 0,DISPLAY")
        row("56: the mode 1 field (NEWLINE CR) is used for mode 1", has(t, r"NEWLINE CR\s*$") and not has(t, r"NEWLINE CRLF"), t[-500:])
        write(probe, "   delete @voc, '$setptr.defaults'\n   crt 'DEFAULTS GONE'\nend\n")
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        t = sess(box, "SETPTR 0,,,,,3", "SETPTR 0,DISPLAY")
        row("56 CONTROL: without the record nothing is added (the unit is still reported, with the default newline unmentioned)",
            not has(t, r"EJECT") and not has(t, r"NEWLINE") and has(t, r"Mode\s+: 3"), t[-500:])
        for nm in ("zzoqdf", "zzoqdf2"):
            if os.path.exists(os.path.join(hold, nm)):
                os.remove(os.path.join(hold, nm))
        sess(box, "SETPTR 0,80,60,0,0,1,BRIEF")

        # --- PTERM MARK (155, 254): ctrl-\ ctrl-] ctrl-^ typed become SM VM FM -------------------------------------
        write(probe, "   a = keyin() ; b = keyin() ; c = keyin()\n   crt 'KEYS[':seq(a):'/':seq(b):'/':seq(c):']'\nend\n")
        keys = "\x1c\x1d\x1e"
        t = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1", keys)
        row("155 CONTROL: by default ctrl-\\ ctrl-] ctrl-^ arrive as characters 28, 29 and 30", has(t, r"KEYS\[28/29/30\]"), t[-300:])
        t = sess(box, "PTERM MARK ON", "BASIC bp zzoqp1", "RUN bp zzoqp1", keys)
        row("155: after PTERM MARK ON they arrive as the subvalue, value and field marks (252, 253, 254), in that order",
            has(t, r"KEYS\[252/253/254\]"), t[-300:])
        t = sess(box, "PTERM MARK ON", "PTERM MARK OFF", "BASIC bp zzoqp1", "RUN bp zzoqp1", keys)
        row("155: PTERM MARK OFF puts it back", has(t, r"KEYS\[28/29/30\]"), t[-300:])
        write(probe, "   a = keyin() ; b = keyin() ; c = keyin() ; d = keyin()\n   crt 'KEYS[':seq(a):'/':seq(b):'/':seq(c):'/':seq(d):']'\nend\n")
        t = sess(box, "PTERM MARK ON", "BASIC bp zzoqp1", "RUN bp zzoqp1", "\x1bA\x1b\x1f")
        row("155: no other character is touched (27, 65, 27, 31 stay as they are)", has(t, r"KEYS\[27/65/27/31\]"), t[-300:])
        t = sess(box, "PTERM MARK")
        row("155: PTERM MARK alone says it is off", has(t, r"Mark translation: Off"), t[-300:])
        t = sess(box, "PTERM MARK ON", "PTERM MARK")
        row("155: ...and on, once it is", has(t, r"Mark translation: On"), t[-300:])
        t = sess(box, "PTERM DISPLAY")
        row("155: PTERM DISPLAY reports it too", has(t, r"Mark translation: Off"), t[-300:])
        t = sess(box, "PTERM MARK SIDEWAYS")
        row("155: any other word is refused", has(t, r"Unrecognised option \(SIDEWAYS\)"), t[-300:])
        write(probe, "   input s\n   crt 'IN[':change(change(change(s, @sm, '<SM>'), @vm, '<VM>'), @fm, '<FM>'):']'\nend\n")
        t = sess(box, "PTERM MARK ON", "BASIC bp zzoqp1", "RUN bp zzoqp1", "a\x1cb\x1dc\x1ed")
        row("155: INPUT receives the marks as well", has(t, r"IN\[a<SM>b<VM>c<FM>d\]"), t[-300:])

        # --- PTERM ERASE, CTRL.FILTER and QUERY (253) ------------------------------------------------------------
        inp = ("   input s\n   o = ''\n   for i = 1 to len(s)\n      n = seq(s[i, 1])\n"
               "      if n < 32 or n = 127 then o := '<':n:'>' else o := s[i, 1]\n   next i\n   crt 'IN[':o:']'\nend\n")
        write(probe, inp)

        def typed(setup, line):
            """Run the INPUT probe after the PTERM commands in setup, typing line; returns what INPUT stored (control characters as <n>)."""
            t = sess(box, *(list(setup) + ["BASIC bp zzoqp1", "RUN bp zzoqp1", line]))
            m = re.search(r"(?m)^IN\[(.*)\]\s*$", t)
            return (m.group(1) if m else None), t

        got, t = typed([], "ab\x08c")
        row("253 CONTROL: by default INPUT erases on ctrl-H", got == "ac", "%r %s" % (got, t[-200:]))
        got, t = typed([], "ab\x7fc")
        row("253 CONTROL: ...and on DEL (PAL-21)", got == "ac", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM ERASE ON"], "ab\x08c")
        row("253: PTERM ERASE ON makes ctrl-H the erase key", got == "ac", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM ERASE ON"], "ab\x7fc")
        row("253: ...and DEL then is an ordinary character", got == "ab<127>c", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM ERASE 127"], "ab\x7fc")
        row("253: PTERM ERASE 127 makes DEL the erase key", got == "ac", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM ERASE 127"], "ab\x08c")
        row("253: ...and ctrl-H then is not", got == "ab<8>c", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM ERASE ^D"], "ab\x04c")
        row("253: PTERM ERASE ^D names a control key by its letter", got == "ac", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM ERASE OFF"], "ab\x08c")
        row("253: PTERM ERASE OFF leaves INPUT with no erase key: ctrl-H is data", got == "ab<8>c", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM ERASE OFF"], "ab\x7fc")
        row("253: ...and so is DEL", got == "ab<127>c", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM ERASE OFF", "PTERM ERASE DEFAULT"], "ab\x7fc")
        row("253: PTERM ERASE DEFAULT puts it back as it started", got == "ac", "%r %s" % (got, t[-200:]))
        t = sess(box, "PTERM ERASE", "PTERM ERASE ON", "PTERM ERASE", "PTERM ERASE 127", "PTERM ERASE", "PTERM ERASE OFF", "PTERM ERASE")
        row("253: PTERM ERASE alone says which key it is (default, character 8 (^H), 127 (DEL), off)",
            has(t, r"Erase key: Default") and has(t, r"Erase key: character 8 \(\^H\)") and has(t, r"Erase key: character 127 \(DEL\)")
            and has(t, r"Erase key: Off"), t[-500:])
        t = sess(box, "PTERM ERASE 40")
        row("253: a character outside 1 - 31 and 127 is refused", has(t, r"Erase character must be in range 1 - 31 or 127"), t[-300:])
        t = sess(box, "PTERM ERASE ^~")
        row("253: ...so is a ^ key that is not a control key", has(t, r"Invalid erase key"), t[-300:])
        t = sess(box, "PTERM ERASE SIDEWAYS")
        row("253: ...and any other word", has(t, r"Unrecognised option \(SIDEWAYS\)"), t[-300:])
        t = sess(box, "PTERM ERASE 127", "PTERM CTRL.FILTER ON", "PTERM DISPLAY")
        row("253: PTERM DISPLAY reports the erase key and the control filter", has(t, r"Erase key: character 127") and has(t, r"Control character filter: On"), t[-600:])

        got, t = typed([], "a\x01b")
        row("253 CONTROL: by default INPUT keeps a control character it does not know", got == "a<1>b", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM CTRL.FILTER ON"], "a\x01b\x1bc")
        row("253: PTERM CTRL.FILTER ON discards them", got == "abc", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM CTRL.FILTER ON"], "ab\x08c")
        row("253: ...but not the erase key", got == "ac", "%r %s" % (got, t[-200:]))
        got, t = typed(["PTERM CTRL.FILTER ON", "PTERM CTRL.FILTER OFF"], "a\x01b")
        row("253: PTERM CTRL.FILTER OFF puts it back", got == "a<1>b", "%r %s" % (got, t[-200:]))
        t = sess(box, "PTERM CTRL.FILTER", "PTERM CTRL.FILTER ON", "PTERM CTRL.FILTER")
        row("253: PTERM CTRL.FILTER alone says which", has(t, r"Control character filter: Off") and has(t, r"Control character filter: On"), t[-400:])
        # a nested command level has a setting of its own, starting off
        outer = os.path.join(bp, "zzoqp1")
        inner = os.path.join(bp, "zzoqp2")
        made.append(inner)
        write(inner, inp.replace("crt 'IN['", "crt 'INNER['"))
        write(outer, ("   input s\n   o = ''\n   for i = 1 to len(s)\n      n = seq(s[i, 1])\n"
                      "      if n < 32 or n = 127 then o := '<':n:'>' else o := s[i, 1]\n   next i\n   crt 'OUTER[':o:']'\n"
                      "   execute 'RUN bp zzoqp2'\nend\n"))
        t = sess(box, "PTERM CTRL.FILTER ON", "BASIC bp zzoqp2", "BASIC bp zzoqp1", "RUN bp zzoqp1", "a\x01b", "c\x01d")
        row("253: the filter is set for one command level: the program's INPUT drops the control character, a RUN under EXECUTE keeps it",
            has(t, r"OUTER\[ab\]") and has(t, r"INNER\[c<1>d\]"), t[-500:])
        write(probe, inp)
        # Over the pipe every byte is there at once, so the whole of the rest of the input is ONE "key": what the
        # rows can check is the way a sequence is shown, and that the end of the input ends the command.
        t = sess(box, "PTERM QUERY", "\x1b[A")
        row("253: PTERM QUERY shows the bytes of a key in hex and in terminfo form (the cursor-up sequence ESC [ A)",
            has(t, r"Received: 1B 5B 41 0D") and has(t, r"As characters: \.\[A\.") and has(t, r"Terminfo form: \\E\[A\\R"), t[-600:])
        t = sess(box, "PTERM QUERY", "\x04")
        row("253: ...a control key as ^D (a sequence of more than one character is shown in terminfo form whatever it is)",
            has(t, r"Received: 04 0D") and has(t, r"Terminfo form: \^D\\R"), t[-600:])
        t = sess(box, "PTERM QUERY")
        row("253: ...with the prompt line, and the end of the input ends it", has(t, r"Press keys to see what they send"), t[-300:])

        # --- SEARCH ... DISPLAY, SCAN and STRINGS (437, 447, 141) ------------------------------------------------
        write(probe, ("   execute 'CREATE.FILE zzoqsc' capturing j1\n   execute 'CREATE.FILE zzoqst' capturing j2\n"
                      "   open 'zzoqsc' to f else stop 'no file'\n   open 'zzoqst' to g else stop 'no strings file'\n"
                      "   write 'alpha widget one':@fm:'beta':@fm:'gamma widget two' on f, 'r1'\n"
                      "   write 'nothing here':@fm:'widget but also gizmo' on f, 'r2'\n"
                      "   write 'gizmo only' on f, 'r3'\n"
                      "   write 'WIDGET upper' on f, 'r4'\n"
                      "   write 'a':@vm:'widget':@vm:'c' on f, 'r5'\n"
                      "   write 'widget':@fm:'gizmo' on g, 'w'\n"
                      "   write '' on g, 'empty'\n"
                      "   crt 'SC FILES MADE'\nend\n"))
        t = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("437 CONTROL: the search files were made", has(t, r"SC FILES MADE"), t[-200:])

        t = sess(box, 'SEARCH zzoqsc FOR "widget" DISPLAY')
        row("437: SEARCH ... DISPLAY shows the id of a selected record and the lines that hold the string, with their numbers",
            has(t, r"(?m)^r1\s*$") and has(t, r"(?m)^0001:\salpha widget one") and has(t, r"(?m)^0003:\sgamma widget two")
            and has(t, r"(?m)^r2\s*$") and has(t, r"(?m)^0002:\swidget but also gizmo"), t[-600:])
        row("437: ...not the lines that hold none of them", not has(t, r"2: beta|1: nothing here") and not has(t, r"(?m)^0002:\sbeta"), t[-600:])
        row("437: ...not a record without the string, nor (the search being case sensitive) WIDGET", not has(t, r"(?m)^r3\s*$") and not has(t, r"(?m)^r4\s*$"), t[-600:])
        row("437: ...with the marks of a line shown as LIST shows them", has(t, r"(?m)^0001:\sa\]widget\]c"), t[-600:])
        row("437: ...and the usual count of what was selected", has(t, r"3 record\(s\) selected to select list 0|3 record\(s\) selected"), t[-600:])
        t = sess(box, 'SEARCH zzoqsc FOR "widget"')
        row("437 CONTROL: without DISPLAY the lines are not shown", not has(t, r"(?m)^0001:\salpha") and has(t, r"3 record\(s\) selected"), t[-400:])
        t2 = sess(box, 'SCAN zzoqsc FOR "widget"')
        row("447: SCAN is SEARCH with DISPLAY", has(t2, r"(?m)^0003:\sgamma widget two") and has(t2, r"(?m)^r5\s*$") and has(t2, r"3 record\(s\) selected"), t2[-600:])
        t = sess(box, 'SCAN zzoqsc NO.CASE FOR "widget"')
        row("447: NO.CASE finds WIDGET too, and shows it as it is", has(t, r"(?m)^r4\s*$") and has(t, r"(?m)^0001:\sWIDGET upper"), t[-600:])
        t = sess(box, 'SCAN zzoqsc ALL.MATCH FOR "widget" "gizmo"')
        row("447: ALL.MATCH selects only the records holding every string, and shows the lines holding either",
            has(t, r"(?m)^r2\s*$") and not has(t, r"(?m)^r1\s*$") and not has(t, r"(?m)^r3\s*$") and has(t, r"1 record\(s\) selected"), t[-600:])
        t = sess(box, "SCAN zzoqsc", "gizmo", "")
        row("447: with no FOR it prompts for strings, ended by a blank answer",
            has(t, r"String:") and has(t, r"(?m)^r3\s*$") and has(t, r"(?m)^r2\s*$") and not has(t, r"(?m)^r1\s*$"), t[-600:])
        write(probe, "   readlist items from 0 else items = 'NONE'\n   crt 'ITEMS[':change(items, @fm, ','):']'\nend\n")
        t = sess(box, 'SCAN zzoqsc FOR "widget"', "BASIC bp zzoqp1", "RUN bp zzoqp1")
        m = re.search(r"(?m)^ITEMS\[(.*)\]\s*$", t)
        items = set(m.group(1).split(",")) if m else None
        row("447: SCAN leaves the selected ids as select list 0", items == {"r1", "r2", "r5"}, "%r %s" % (items, t[-300:]))

        t = sess(box, "SCAN zzoqsc STRINGS zzoqst w")
        row("141: STRINGS file record takes the strings from the fields of that record (widget and gizmo)",
            has(t, r"(?m)^r1\s*$") and has(t, r"(?m)^r3\s*$") and has(t, r"(?m)^0001:\sgizmo only") and has(t, r"4 record\(s\) selected"), t[-600:])
        t = sess(box, "SEARCH zzoqsc STRINGS zzoqst w")
        row("141: SEARCH takes STRINGS as well", has(t, r"4 record\(s\) selected") and not has(t, r"(?m)^0001:\sgizmo only"), t[-400:])
        t = sess(box, 'SCAN zzoqsc FOR "alpha" STRINGS zzoqst w')
        row("141: STRINGS adds to FOR", has(t, r"(?m)^r1\s*$") and has(t, r"(?m)^r3\s*$") and has(t, r"(?m)^0001:\salpha widget one"), t[-600:])
        t = sess(box, "SCAN zzoqsc STRINGS zzoqnone w")
        row("141: a strings file that does not exist is reported", has(t, r"File not found") and not has(t, r"record\(s\) selected"), t[-300:])
        t = sess(box, "SCAN zzoqsc STRINGS zzoqst nosuchrec")
        row("141: a record that does not exist is reported", has(t, r'Record "nosuchrec" not found') and not has(t, r"record\(s\) selected"), t[-300:])
        t = sess(box, "SCAN zzoqsc STRINGS zzoqst")
        row("141: STRINGS with no record id is reported", has(t, r"Record id required after STRINGS file name"), t[-300:])
        t = sess(box, "SCAN zzoqsc STRINGS zzoqst empty")
        row("141: a record with no fields gives no strings", has(t, r"No search strings") and not has(t, r"record\(s\) selected"), t[-300:])
        sess(box, "DELETE.FILE zzoqsc", "DELETE.FILE zzoqst")

        # --- !TESTLOCK (42) -------------------------------------------------------------------------------------
        write(probe, ("   call !testlock(7, o1)\n   lock 7\n   call !testlock(7, o2)\n   unlock 7\n   call !testlock(7, o3)\n"
                      "   crt 'TL[':o1:'/':(o2 = @userno):'/':o3:']'\nend\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("42: !TESTLOCK is 0 for a free task lock, the owner's user number while held, and 0 again",
            has(out, r"^TL\[0/1/0\]"), out[-300:])

        # --- !MERGELIST (420, 539, 566) -------------------------------------------------------------------------
        def lst(s):
            return "'" + "':@fm:'".join(s.split(",")) + "'" if s else "''"
        merges = [
            ("a,c,e", "b,c,d", "", "a,b,c,d,e", "420: the default merge is the union, in order"),
            ("a,c,e", "b,c,d", "A", "a,b,c,c,d,e", "420: mode A keeps duplicates"),
            ("a,c,e", "b,c,d", "I", "c", "420: mode I is the items in both"),
            ("a,c,e", "b,c,d", "D", "a,e", "420: mode D is list 1 without list 2"),
            ("a,c,e", "b,c,d", "X", "a,b,d,e", "420: mode X is the items in one only"),
            ("a,c,e", "b,c,d", "U DL", "e,d,c,b,a", "420: DL puts the result in descending order"),
            ("10,9", "100,1", "AR", "1,9,10,100", "420: AR orders numerically"),
            ("", "b,a", "U", "a,b", "539: an empty first list"),
            ("a,b", "", "U", "a,b", "539: an empty second list"),
            ("", "b,a", "I", "", "539: an empty list gives no items in both"),
            ("", "", "U", "", "539: two empty lists"),
            ("e,a,c", "d,b", "U N", "a,b,c,d,e", "566: lists that are not in order, with the N word"),
        ]
        body = ""
        for i, (a, b, m, want, label) in enumerate(merges):
            body += ("   l1 = %s\n   l2 = %s\n   call !mergelist(r, l1, l2, '%s')\n   crt 'ML%d[':change(r, @fm, ','):']'\n"
                     % (lst(a), lst(b), m, i))
        write(probe, body + "end\n")
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        for i, (a, b, m, want, label) in enumerate(merges):
            row("%s (%s | %s | %r)" % (label, a, b, m), has(out, r"^ML%d\[%s\]" % (i, re.escape(want))), out[-300:])

        # --- PHANTOM statement (390) ----------------------------------------------------------------------------
        write(probe, ("   phantom 'NO.MSG LIST.FILES' capturing o\n   uid = @system.return.code\n   sleep 6\n"
                      "   call !phlog(uid, nm)\n   crt 'PS[':(uid > 0):'/':(nm[1,2] = 'PH'):']'\nend\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("390: the PHANTOM statement starts a phantom (a user number comes back and it makes its log)",
            has(out, r"^PS\[1/1\]"), out[-300:])

        # --- the log name of the PHANTOM statement may be a variable (351, 14 Oct 26) -----------------------------
        sess(box, "DELETE.FILE zzcd3", "CREATE.FILE zzcd3 DIRECTORY")
        write(probe, ("   lg = 'zzcd3'\n   phantom 'NO.MSG LOG ':lg:' LIST.FILES' capturing o\n   uid = @system.return.code\n"
                      "   sleep 6\n   crt 'PV[':(uid > 0):']'\nend\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        zl = [n for n in os.listdir(os.path.join(sysd, "zzcd3"))] if os.path.isdir(os.path.join(sysd, "zzcd3")) else []
        row("351: PHANTOM 'LOG ':variable starts a phantom whose log goes in the directory file the variable names",
            has(out, r"^PV\[1\]") and any(n.startswith("PH") for n in zl), out[-300:] + repr(zl))
        sess(box, "DELETE.FILE zzcd3")

        # --- REBUILD.ALL.INDICES (58) and REDO (188) -------------------------------------------------------
        write(probe, ("   execute 'CREATE.FILE zzrb' capturing j1\n   open 'zzrb' to f else stop\n"
                      "   open 'DICT', 'zzrb' to dv else stop\n"
                      "   write 'D':@fm:'1':@fm:'':@fm:'Fld':@fm:'10L':@fm:'S' on dv, 'FLD'\n"
                      "   write 'b' on f, 'r1'\n   write 'a' on f, 'r2'\nend\n"))
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1", "CREATE.INDEX zzrb FLD")
        out = sess(box, "REBUILD.ALL.INDICES NO.QUERY")
        row("58: REBUILD.ALL.INDICES rebuilds the indices of a file that has them and says so",
            has(out, r"Indices of zzrb rebuilt") and re.search(r"(?m)^[1-9]\d* file\(s\) had their indices rebuilt", out) is not None, out[-500:])
        out = sess(box, "REBUILD.ALL.INDICES", "N")
        row("58: without NO.QUERY it asks, and N rebuilds nothing", has(out, r"Rebuild the indices of all files") and
            not has(out, r"Indices of zzrb rebuilt"), out[-400:])
        sess(box, "DELETE.INDEX zzrb ALL", "DELETE.FILE zzrb")
        t0 = time.time()
        out = sess(box, "REDO TIMES 3 EVERY 1 SH echo REDO_RAN")
        took = time.time() - t0
        row("188: REDO TIMES 3 runs the command three times", len(re.findall(r"(?m)^REDO_RAN\s*$", out)) == 3, out[-300:])
        row("188: and EVERY 1 spaces the runs a second apart (the whole took at least two seconds)", took >= 2.0, "took %.1f s" % took)

        # --- private vocabulary (1) -------------------------------------------------------------------------
        write(probe, ("   execute 'CREATE.FILE zzpv' capturing j1\n   open 'zzpv' to f else stop\n"
                      "   write 'PA':@fm:'SH echo PV_RAN' on f, 'zzpverb'\nend\n"))
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        out = sess(box, "ZZPVERB")
        row("1 CONTROL: a command in no vocabulary is not run", not has(out, r"^PV_RAN") , out[-300:])
        write(probe, "   open 'VOC' to v else stop\n   write 'X':@fm:'zzpv' on v, '$PRIVATE.VOC'\nend\n")
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        out = sess(box, "ZZPVERB", "zzpverb")
        row("1: with $PRIVATE.VOC naming the file, the command in it is found and run (typed either case)",
            len(re.findall(r"(?m)^PV_RAN\s*$", out)) == 2, out[-300:])
        write(probe, "   open 'VOC' to v else stop\n   delete v, '$PRIVATE.VOC'\nend\n")
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1", "DELETE.FILE zzpv")

        # --- COMO APPEND, IN, mapped names (8, 361, 9) ----------------------------------------------------------
        sess(box, "DELETE.FILE zzcd", "CREATE.FILE zzcd DIRECTORY")
        como_dir = os.path.join(sysd, "$COMO")
        sess(box, "COMO ON zzoqm1", "SH echo MARK_ONE", "COMO OFF")
        first = slurp(os.path.join(como_dir, "zzoqm1")) or b""
        row("8 CONTROL: COMO ON writes the session to the record", b"MARK_ONE" in first, repr(first[-80:]))
        sess(box, "COMO ON zzoqm1 APPEND", "SH echo MARK_TWO", "COMO OFF")
        both = slurp(os.path.join(como_dir, "zzoqm1")) or b""
        row("8: COMO ON ... APPEND adds to the existing record", b"MARK_ONE" in both and b"MARK_TWO" in both, repr(both[-120:]))
        sess(box, "COMO ON zzoqm1", "SH echo MARK_THREE", "COMO OFF")
        again = slurp(os.path.join(como_dir, "zzoqm1")) or b""
        row("8: without APPEND the record is replaced as before", b"MARK_THREE" in again and b"MARK_ONE" not in again, repr(again[-120:]))
        sess(box, "COMO ON zzoqm2 IN zzcd", "SH echo MARK_FOUR", "COMO OFF")
        alt = slurp(os.path.join(sysd, "zzcd", "zzoqm2")) or b""
        row("361: COMO ON ... IN dirfile writes to that directory file", b"MARK_FOUR" in alt, repr(alt[-80:]))
        sess(box, "COMO ON zzoq=m3", "SH echo MARK_FIVE", "COMO OFF")
        names = os.listdir(como_dir)
        row("9: a record name with a restricted character (=) is mapped (%E) as in any directory file",
            "zzoq%Em3" in names and "zzoq=m3" not in names, repr(names))
        for n in ("zzoqm1", "zzoq%Em3"):
            if os.path.exists(os.path.join(como_dir, n)):
                os.remove(os.path.join(como_dir, n))
        sess(box, "DELETE.FILE zzcd")

        # --- paragraph IF: EXISTS, IN, NO.CASE (28, 230, 426, 476) -------------------------------------------
        paras = [
            ("IF EXISTS zzpf r1 THEN SH echo HIT_E1", "HIT_E1", True, "28: IF EXISTS finds a record that is there"),
            ("IF EXISTS zzpf r2 THEN SH echo HIT_E2", "HIT_E2", False, "28: IF EXISTS does not fire for a record that is not"),
            ("IF NOT.EXISTS zzpf r2 THEN SH echo HIT_E3", "HIT_E3", True, "28: IF NOT.EXISTS fires for a missing record"),
            ("IF NOT.EXISTS zzpf r1 THEN SH echo HIT_E4", "HIT_E4", False, "28: and not for one that is there"),
            ("IF b IN a b c THEN SH echo HIT_I1", "HIT_I1", True, "230: IF value IN list, a member"),
            ("IF x IN a b c THEN SH echo HIT_I2", "HIT_I2", False, "230: IN, not a member"),
            ("IF x NOT.IN a b c THEN SH echo HIT_I3", "HIT_I3", True, "230: NOT.IN, not a member"),
            ("IF b NOT.IN a b c THEN SH echo HIT_I4", "HIT_I4", False, "230: NOT.IN, a member"),
            ("IF B IN a b c THEN SH echo HIT_I5", "HIT_I5", False, "426 CONTROL: IN is case sensitive without NO.CASE"),
            ("IF B IN a b c NO.CASE THEN SH echo HIT_I6", "HIT_I6", True, "426: IN with NO.CASE ignores case"),
            ("IF b IN a b AND c IN c d THEN SH echo HIT_I7", "HIT_I7", True, "230: two IN tests joined by AND"),
            ("IF Hello EQ hello THEN SH echo HIT_C1", "HIT_C1", False, "476 CONTROL: a comparison is case sensitive"),
            ("IF Hello EQ hello NO.CASE THEN SH echo HIT_C2", "HIT_C2", True, "476: NO.CASE makes it ignore case"),
            ("IF Hello NE hello NO.CASE THEN SH echo HIT_C3", "HIT_C3", False, "476: and NE then says they are alike"),
        ]
        write(probe, ("   execute 'CREATE.FILE zzpf' capturing j1\n   open 'zzpf' to f else stop\n   write 'x' on f, 'r1'\n"
                      "   open 'VOC' to v else stop\n" +
                      "".join("   write 'PA':@fm:'%s' on v, 'zzpa%d'\n" % (p[0].replace("'", "''") if False else p[0], i)
                              for i, p in enumerate(paras)) + "end\n"))
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        out = sess(box, *["ZZPA%d" % i for i in range(len(paras))])
        for i, (cmd, hit, want, label) in enumerate(paras):
            row("%s (%s)" % (label, cmd), has(out, r"^%s\s*$" % hit) == want, "hit=%s" % has(out, r"^%s\s*$" % hit))
        sess(box, "DELETE.FILE zzpf")

        # --- DELETE with a record locked by someone else (50) -----------------------------------------------
        holder = os.path.join(bp, "zzoqh1")
        made.append(holder)
        write(holder, ("   open 'zzoqc1' to f else stop\n   readu x from f, 'k2' else null\n   sleep 12\n   release\nend\n"))
        sess(box, "BASIC bp zzoqh1")
        p = subprocess.Popen([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts"), "RUN bp zzoqh1"],
                             stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        time.sleep(4)   # the holder has the lock by now
        out = sess(box, "DELETE zzoqc1 k2 k3 NO.QUERY", "DELETE zzoqc1 ALL NO.QUERY")
        p.wait(timeout=60)
        row("50: DELETE of a locked record warns and goes on to the next one", has(out, r"Record 'k2' is locked by another user"), out[-300:])
        row("50: the unlocked record was deleted", has(out, r"1 record\(s\) deleted"), out[-300:])
        row("50: and ALL skips the locked one with the same warning, rather than waiting",
            out.count("is locked by another user") >= 2, out[-300:])

        # --- DELETE.COMMON ALL EXCEPT (425) -----------------------------------------------------------------
        write(probe, ("   common /zzca/ a\n   common /zzcb/ b\n   common /zzcc/ c\n   a = 1 ; b = 2 ; c = 3\n   crt 'made'\nend\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1", "LIST.COMMON",
                   "DELETE.COMMON ALL EXCEPT zzcb", "LIST.COMMON")
        shown = out.split("DELETE.COMMON ALL EXCEPT", 1)
        before, after = shown[0], (shown[1] if len(shown) > 1 else "")
        row("425 CONTROL: all three blocks exist before", has(before, r"^ZZCA") and has(before, r"^ZZCB") and has(before, r"^ZZCC"),
            before[-200:])
        row("425: DELETE.COMMON ALL EXCEPT zzcb keeps zzcb and removes the others",
            has(after, r"^ZZCB") and not has(after, r"^ZZCA") and not has(after, r"^ZZCC"), after[-200:])
        sess(box, "DELETE.COMMON zzcb")

        # --- LISTDICT (10, 75): the Pick style dictionary listing, a paragraph over LIST DICT ----------------------
        write(probe, ("   execute 'CREATE.FILE zzoqld' capturing j1\n"
                      "   open 'DICT', 'zzoqld' to f else stop\n"
                      "   write 'D':@fm:1:@fm:'':@fm:'Name':@fm:'10L':@fm:'S' on f, 'name'\n"
                      "   write 'D':@fm:2:@fm:'MD0':@fm:'Qty':@fm:'5R':@fm:'S' on f, 'qty'\n"
                      "   write 'A':@fm:3:@fm:'Price':@fm:'':@fm:'':@fm:'':@fm:'MD2':@fm:'':@fm:'':@fm:'10':@fm:'R' on f, 'price'\n"
                      "   write 'I':@fm:'QTY * PRICE':@fm:'':@fm:'Total':@fm:'10R':@fm:'S' on f, 'total'\n"
                      "   write 'S':@fm:4:@fm:'Code' on f, 'code'\n"
                      "   write 'PH':@fm:'NAME QTY' on f, 'short'\n"
                      "   write 'X':@fm:'a comment' on f, 'note'\n"
                      "end\n"))
        sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        out = sess(box, "LISTDICT zzoqld")
        full = sess(box, "LIST DICT zzoqld")
        row("10: LISTDICT lists an A-type record with its field number and conversion", has(out, r"^price\s+A\s+3\s+MD2\s+Price"), out[-400:])
        row("75: ...and D-type records", has(out, r"^name\s+D\s+1\s+Name\s+10L\s+S") and has(out, r"^qty\s+D\s+2\s+MD0\s+Qty"), out[-400:])
        row("75: ...and an I-type record with its expression", has(out, r"^total\s+I\s+QTY \* PRICE\s+Total"), out[-400:])
        row("10: ...and an S-type record", has(out, r"^code\s+S\s+4\s+Code"), out[-400:])
        row("10: ...and no phrase and no other type", not has(out, r"^short\s") and not has(out, r"^note\s"), out[-400:])
        row("10 CONTROL: LIST DICT of the same file does show the phrase and the other type",
            has(full, r"^short\s+PH") and has(full, r"^note\s+X"), full[-400:])
        row("10: the A, D, I and S records come to six with the dictionary's own @id", has(out, r"6 record\(s\) listed"), out[-300:])
        row("10: the records come in the order A, D, I, S",
            re.search(r"(?s)^price\s+A.*^name\s+D.*^total\s+I.*^code\s+S", out, re.M) is not None, out[-400:])
        row("10: an upper case file name works", has(sess(box, "LISTDICT ZZOQLD"), r"^price\s+A\s+3"), "")
        row("10: a file that does not exist is reported", has(sess(box, "LISTDICT zzoqnone"), r"File not found"), "")
        out = sess(box, "LISTDICT zzoqld LPTR")
        row("10: LPTR sends the listing to the printer: nothing of it on the screen, and no complaint about the word",
            not has(out, r"^price\s") and not has(out, r"record\(s\) listed") and not has(out, r"(?i)unrecognised|illegal|not found"), out[-300:])

        # --- COPY.LISTP (72): COPYP with the source file defaulting to $savedlists ----------------------------
        out = sess(box, 'SELECT VOC WITH @ID = "copyp" "list" "sort"', "SAVE.LIST zzoqla",
                   'SELECT VOC WITH @ID = "copy"', "SAVE.LIST zzoqlb")
        row("72 CONTROL: the two saved lists were made", has(out, r"3 record\(s\) selected") and not has(out, r"(?i)error|not found|cannot"), out[-300:])
        out = sess(box, "COPY.LISTP zzoqla (T")
        row("72: COPY.LISTP name (T shows the saved list of that name, the source file being $savedlists",
            has(out, r"Item zzoqla") and has(out, r"^0001 copyp") and has(out, r"^0002 list") and has(out, r"^0003 sort")
            and has(out, r"1 record\(s\) copied"), out[-400:])
        out = sess(box, "COPY.LISTP zzoqla (ST")
        row("72: S leaves out the field numbers", has(out, r"^copyp$") and not has(out, r"^0001 copyp"), out[-300:])
        out = sess(box, "COPY.LISTP zzoqla (IT")
        row("72: ...and I the id", not has(out, r"Item zzoqla") and has(out, r"copyp"), out[-300:])
        out = sess(box, "COPY.LISTP $savedlists zzoqla (T")
        row("72: a first word that opens as a file, with a list name after it, is the source file",
            has(out, r"Item zzoqla") and has(out, r"1 record\(s\) copied"), out[-300:])
        out = sess(box, "COPY.LISTP zzoqla zzoqlb (T")
        row("72: two list names are both in $savedlists, whichever of them could be a file",
            has(out, r"Item zzoqla") and has(out, r"Item zzoqlb") and has(out, r"2 record\(s\) copied"), out[-400:])
        out = sess(box, "COPY.LISTP * (T")
        row("72: * is every saved list", has(out, r"Item zzoqla") and has(out, r"Item zzoqlb"), out[-400:])
        out = sess(box, "COPY.LISTP zzoqnone (T")
        row("72: a list that does not exist is reported", has(out, r'Record "zzoqnone" not found') and has(out, r"0 record\(s\) copied"), out[-300:])
        out = sess(box, "COPY.LISTP zzoqla", "zzoqlc")
        row("72: with neither P nor T it asks for the destination and copies within $savedlists",
            has(out, r"Copied item zzoqla from \$savedlists to \$savedlists item zzoqlc"), out[-400:])
        out = sess(box, "COPY.LISTP zzoqlc (ST")
        row("72: and the copy holds the same list", has(out, r"^copyp$") and has(out, r"^list$") and has(out, r"^sort$"), out[-300:])
        out = sess(box, "COPY.LISTP zzoqla", "zzoqlc")
        row("72: an existing destination is not overwritten without O", has(out, r"Item zzoqla already exists in target file"), out[-300:])
        out = sess(box, "COPY.LISTP zzoqla (D", "zzoqld2")
        row("72: D moves the list", has(out, r"Moved item zzoqla from \$savedlists to \$savedlists item zzoqld2"), out[-300:])
        out = sess(box, "COPY.LISTP zzoqla (T")
        row("72: ...so the source list is gone", has(out, r'Record "zzoqla" not found'), out[-300:])
        out = sess(box, "COPY.LISTP DICT zzoqld name (ST")
        row("72: DICT names the dictionary of the file that follows", has(out, r"^D$") and has(out, r"^Name$"), out[-300:])
        out = sess(box, "COPYP voc copyp (ST")
        row("72 CONTROL: COPYP still wants its file name first", has(out, r"^CA$") and has(out, r"1 record\(s\) copied"), out[-300:])

        # --- SELECTINDEX command (119): the values of an AK index, or the ids that have one value ------------------
        write(probe, ("   execute 'CREATE.FILE zzoqix' capturing j1\n"
                      "   open 'zzoqix' to f else stop 'no file'\n"
                      "   open 'DICT', 'zzoqix' to df else stop 'no dict'\n"
                      "   write 'D':@fm:1:@fm:'':@fm:'Colour':@fm:'10L':@fm:'S' on df, 'colour'\n"
                      "   write 'red' on f, 'a'\n   write 'blue' on f, 'b'\n   write 'red' on f, 'c'\n   write 'green' on f, 'd'\n"
                      "   crt 'IX FILE MADE'\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1", "CREATE.INDEX zzoqix colour", "BUILD.INDEX zzoqix colour")
        row("119 CONTROL: the file and its index were made and built",
            has(out, r"IX FILE MADE") and has(out, r"Added index for colour") and has(out, r"4 records processed"), out[-300:])

        def listed(no, *cmds):
            """Run the commands, then show select list no as ITEMS[a,b,c]; returns (text, set of items or None)."""
            write(probe, ("   readlist items from %d else items = 'NONE'\n"
                          "   crt 'ITEMS[':change(items, @fm, ','):']'\n"
                          "end\n") % no)
            text = sess(box, "BASIC bp zzoqp1", *(list(cmds) + ["RUN bp zzoqp1"]))
            m = re.search(r"(?m)^ITEMS\[(.*)\]\s*$", text)
            return text, (set(m.group(1).split(",")) - {""} if m else None)

        text, items = listed(0, "SELECTINDEX zzoqix colour")
        row("119: SELECTINDEX file index gives the values held in the index", items == {"red", "blue", "green"}, "%r %s" % (items, text[-300:]))
        row("119: ...and says how many", has(text, r"3 record\(s\) selected to select list 0"), text[-300:])
        text, items = listed(0, "SELECTINDEX zzoqix colour red")
        row("119: with a value it gives the ids of the records that have it", items == {"a", "c"}, "%r %s" % (items, text[-300:]))
        row("119: ...and says how many", has(text, r"2 record\(s\) selected to select list 0"), text[-300:])
        text, items = listed(0, "SELECTINDEX zzoqix colour purple")
        row("119: a value no record has gives no list (READLIST finds none) and the count says 0",
            items == {"NONE"} and has(text, r"0 record\(s\) selected to select list 0"), "%r %s" % (items, text[-300:]))
        text, items = listed(0, "SELECTINDEX ZZOQIX COLOUR red")
        row("119: the file and index names are found in whichever case", items == {"a", "c"}, "%r %s" % (items, text[-300:]))
        text, items = listed(1, "SELECTINDEX zzoqix colour blue TO 1")
        row("119: TO n builds that list instead", items == {"b"} and has(text, r"1 record\(s\) selected to select list 1"), "%r %s" % (items, text[-300:]))
        text = sess(box, "SELECTINDEX zzoqix nosuchindex")
        row("119: an index that does not exist is reported", has(text, r"Unrecognised index name \(nosuchindex\)"), text[-300:])
        text = sess(box, "SELECTINDEX zzoqnone colour")
        row("119: a file that does not exist is reported", has(text, r"File not found"), text[-300:])
        text = sess(box, "SELECTINDEX zzoqix")
        row("119: no index name is reported", has(text, r"Index name required"), text[-300:])
        text = sess(box, "SELECTINDEX")
        row("119: no file name is reported", has(text, r"File name required"), text[-300:])
        text = sess(box, "SELECTINDEX zzoqix colour red TO")
        row("119: TO with no number is reported", has(text, r"Select list number missing or invalid"), text[-300:])
        text = sess(box, "SELECTINDEX zzoqix colour red blue")
        row("119: a further word is reported", has(text, r"Unexpected token \(blue\)"), text[-300:])
        text = sess(box, "SELECT.DIR /tmp TO", "GET.LIST zzoqnone TO")
        row("119 (found on the way): SELECT.DIR and GET.LIST said 'Error writing saved list record' for a missing list number; they say what 3271 says",
            text.count("Select list number missing or invalid") == 2 and not has(text, r"writing saved list record"), text[-300:])

        # --- TERM with the default printer's size (466) ------------------------------------------------------
        def term_state(text):
            """The last TERM report in the output: (page width, page depth, printer width, printer depth)."""
            got = []
            for key in ("Page width", "Page depth", "Printer width", "Printer depth"):
                m = re.findall(r"(?m)^%s: (\d+)\s*$" % key, text)
                got.append(int(m[-1]) if m else None)
            return tuple(got)

        text = sess(box, "TERM")
        st = term_state(text)
        row("466: TERM reports the page width and depth and the default printer's (the harness set 200 x 9999)",
            st[0] == 200 and st[1] == 9999 and st[2] is not None and st[3] is not None, "%r %s" % (st, text[-300:]))
        text = sess(box, "TERM ,,120,66", "TERM")
        row("466: TERM ,,120,66 sets the printer to 120 x 66 and leaves the screen alone", term_state(text) == (200, 9999, 120, 66),
            "%r %s" % (term_state(text), text[-300:]))
        text = sess(box, "TERM ,,120,66", "TERM 150,40", "TERM")
        row("466: TERM 150,40 sets the screen and leaves the printer alone", term_state(text) == (150, 40, 120, 66),
            "%r %s" % (term_state(text), text[-300:]))
        text = sess(box, "TERM ,,120,66", "TERM ,,,50", "TERM")
        row("466: TERM ,,,50 sets the printer's depth alone", term_state(text) == (200, 9999, 120, 50),
            "%r %s" % (term_state(text), text[-300:]))
        text = sess(box, "TERM ,,100", "TERM")
        row("466: TERM ,,100 sets the printer's width alone", term_state(text)[2] == 100 and term_state(text)[:2] == (200, 9999),
            "%r %s" % (term_state(text), text[-300:]))
        text = sess(box, "TERM 130,45,110,60", "TERM")
        row("466: all four at once", term_state(text) == (130, 45, 110, 60), "%r %s" % (term_state(text), text[-300:]))
        text = sess(box, "TERM ,,100,40", "TERM DEFAULT", "TERM")
        row("466: TERM DEFAULT puts the screen back to 120 x 36 (SD's default, not 80 x 24) and leaves the printer alone",
            term_state(text) == (120, 36, 100, 40), "%r %s" % (term_state(text), text[-300:]))
        text = sess(box, "TERM ,,19")
        row("466: a printer width under 20 is refused", has(text, r"Width must be in range 20 to 32767"), text[-300:])
        text = sess(box, "TERM ,,,9")
        row("466: a printer depth under 10 is refused", has(text, r"Depth must be in range 10 to 32767"), text[-300:])
        text = sess(box, "TERM 100,5")
        row("466 CONTROL: a screen depth under 10 still is", has(text, r"Depth must be in range 10 to 32767"), text[-300:])
        text = sess(box, "TERM 100,30,90,40,5")
        row("466: a fifth number is an unexpected token", has(text, r"Unexpected token"), text[-300:])
        text = sess(box, "TERM ,,100,40 zznosuchterm")
        row("466: a terminal type after four numbers is still read", has(text, r"Unrecognised terminal name"), text[-300:])
        text = sess(box, "TERM 120,36 zznosuchterm")
        row("466 CONTROL: ...and after two", has(text, r"Unrecognised terminal name"), text[-300:])

        # --- SP.VIEW: X deletes the item shown (450) ---------------------------------------------------------
        write(probe, ("   execute 'CREATE.FILE zzoqsv' capturing j1\n"
                      "   open 'zzoqsv' to f else stop 'no file'\n"
                      "   for k = 1 to 5\n      write 'first line of rec':k:@fm:'second line' on f, 'rec':k\n   next k\n"
                      "   crt 'SV FILE MADE'\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("450 CONTROL: five records were made", has(out, r"SV FILE MADE"), out[-200:])

        def left_in_sv():
            t = sess(box, "LIST zzoqsv @ID")        # the id column, then @ID again: "rec4   rec4"
            return set(re.findall(r"(?m)^(rec\d)\s+rec\d\s*$", t)), t

        # Keys arrive one line at a time with a newline after each line, and a stray newline is a Return, so every
        # sequence is ONE line ending in the keys that quit (q, then the line's own newline confirms it), or in a
        # delete that ends the viewer. A sequence that did not end the viewer would wait for input for ever.
        text = sess(box, "SP.VIEW zzoqsv rec1", "xnq")
        ids, listing = left_in_sv()
        row("450: X asks first, and N keeps the item", has(text, r"Delete rec1 from zzoqsv \(Y/N\)\?") and "rec1" in ids, "%r %s" % (ids, text[-300:]))
        text = sess(box, "SP.VIEW zzoqsv rec1", "xy")
        ids, listing = left_in_sv()
        row("450: X then Y deletes it, and only it", ids == {"rec2", "rec3", "rec4", "rec5"}, "%r %s" % (ids, text[-300:]))
        row("450: ...and the viewer ends, as it does when the item was named", not has(text, r"Unable to read item"), text[-300:])
        text = sess(box, "SP.VIEW zzoqsv rec2", "xY")
        ids, listing = left_in_sv()
        row("450: a capital Y does too", ids == {"rec3", "rec4", "rec5"}, "%r %s" % (ids, text[-300:]))
        text = sess(box, "SP.VIEW zzoqsv rec3", "xzq")
        ids, listing = left_in_sv()
        row("450: any other key cancels", "rec3" in ids and len(ids) == 3, "%r %s" % (ids, text[-300:]))
        text = sess(box, "SP.VIEW zzoqsv", "", "xyq")
        ids, listing = left_in_sv()
        row("450: from the pick list: dive in, delete, and the list goes on without it",
            "rec3" not in ids and len(ids) == 2 and has(text, r"2 items|<No items>|rec4|rec5"), "%r %s" % (ids, text[-400:]))

        # --- SP.VIEW file BY field: the pick list's sort clause; Return and Esc-Z in a record -------------------------
        write(probe, ("   execute 'CREATE.FILE zzoqsw' capturing j1\n"
                      "   execute 'CREATE.FILE zzoqsx' capturing j1\n"
                      "   open 'zzoqsw' to f else stop 'no zzoqsw'\n"
                      "   open 'zzoqsx' to g else stop 'no zzoqsx'\n"
                      "   open 'DICT zzoqsw' to df else stop 'no dict'\n"
                      "   open 'DICT zzoqsx' to dg else stop 'no dict'\n"
                      "   d = 'D':@fm:'1':@fm:'':@fm:'Name':@fm:'10L':@fm:'S'\n"
                      "   write d to df, 'name'\n   write d to dg, 'name'\n"
                      "   nm = 'd,b,e,a,c'\n"
                      "   for k = 1 to 5\n      write field(nm, ',', k):@fm:'second line' on f, 'rec':k\n   next k\n"
                      "   big = ''\n   for k = 1 to 30\n      big<-1> = 'big line ':k\n   next k\n   write big on f, 'big'\n"
                      "   write 'B' on g, 'c1'\n   write 'a' on g, 'c2'\n   write 'C' on g, 'c3'\n"
                      "   crt 'SW FILES MADE'\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("SP.VIEW BY CONTROL: the two files were made", has(out, r"SW FILES MADE"), out[-200:])

        def order(text, names):
            """The names that appear in the text, in the order they first appear."""
            return [n for _, n in sorted((text.find(n), n) for n in names if n in text)]

        recs = ["rec1", "rec2", "rec3", "rec4", "rec5", "big"]
        text = sess(box, "SP.VIEW zzoqsw", "q")
        row("SP.VIEW BY CONTROL: with no sort clause the pick list is in id order", order(text, recs) == ["big", "rec1", "rec2", "rec3", "rec4", "rec5"], text[-400:])
        text = sess(box, "SP.VIEW zzoqsw BY name", "q")
        row("SP.VIEW BY name sorts the pick list on that dictionary item", order(text, recs) == ["rec4", "rec2", "big", "rec5", "rec1", "rec3"], text[-400:])
        text = sess(box, "SP.VIEW zzoqsw BY.DSND name", "q")
        row("SP.VIEW BY.DSND name sorts it the other way", order(text, recs) == ["rec3", "rec1", "rec5", "big", "rec2", "rec4"], text[-400:])
        cs = ["c1", "c2", "c3"]
        text = sess(box, "SP.VIEW zzoqsx BY name", "q")
        row("SP.VIEW BY CONTROL: a sort is by case unless asked otherwise (B, C, a)", order(text, cs) == ["c1", "c3", "c2"], text[-400:])
        text = sess(box, "SP.VIEW zzoqsx BY name NO.CASE", "q")
        row("SP.VIEW BY name NO.CASE ignores case (a, B, C)", order(text, cs) == ["c2", "c1", "c3"], text[-400:])
        text = sess(box, "SP.VIEW zzoqsx BY NO.CASE name", "q")
        row("SP.VIEW BY NO.CASE name does too", order(text, cs) == ["c2", "c1", "c3"], text[-400:])
        text = sess(box, "SP.VIEW zzoqsx BY name", "q")
        row("SP.VIEW BY NO.CASE leaves the session's sort option as it found it", order(text, cs) == ["c1", "c3", "c2"], text[-400:])
        text = sess(box, "SP.VIEW zzoqsw BY")
        row("SP.VIEW BY with no field name is refused", has(text, r"Expected field name after BY"), text[-300:])
        text = sess(box, "SP.VIEW zzoqsw BY nosuchfield")
        row("SP.VIEW BY with a field that is not there says so and stops (does not wait for a key)",
            has(text, r"Sort item cannot be a literal value") and not has(text, r"Down/Quit"), text[-300:])
        text = sess(box, "SP.VIEW zzoqsw BY name LPTR 1", "q")
        row("SP.VIEW BY name still takes LPTR after it", has(text, r"Down/Quit") and not has(text, r"Invalid print unit"), text[-300:])

        text = sess(box, "TERM 120,12", "SP.VIEW zzoqsw big", "q")
        row("SP.VIEW CONTROL: a 30-line record opens at the top, 8 lines to a page", has(text, r"top = 1,") and not has(text, r"top = 9,"), text[-300:])
        text = sess(box, "TERM 120,12", "SP.VIEW zzoqsw big", "", "q")
        row("SP.VIEW Return pages forward in a record", has(text, r"top = 9,"), text[-300:])
        text = sess(box, "TERM 120,12", "SP.VIEW zzoqsw big", "", "", "q")
        row("SP.VIEW Return twice is two pages", has(text, r"top = 17,"), text[-300:])
        text = sess(box, "TERM 120,12", "SP.VIEW zzoqsw big", "", "\x1bzq")
        row("SP.VIEW Esc-Z goes back a page", has(text, r"top = 9,") and text.rfind("top = 1,") > text.find("top = 9,"), text[-300:])
        sess(box, "DELETE.FILE zzoqsw", "DELETE.FILE zzoqsx")

        # --- Batch A: 501 (NEWVOC.MODS), 251 (PDEBUG @variable), 94 (qproc IN/NOT.IN), 371 (SORT functions) ----------
        # 501: NEWVOC.MODS in @SDSYS is copied into new/updated accounts and SDSYS during bbproc
        # bbproc runs only in bootstrap pass 1, so a box built here (--build) holds a newvoc.mods from before that pass
        if "--build" in sys.argv:
            write(probe, ("program zzoqp1\n"
                          "   openpath @sdsys:@ds:'voc' to vf else stop 'no sdsys voc'\n"
                          "   read r from vf, 'ZZ.BBPROC.MODS' then crt 'BBM=':r<2> else crt 'BBM=none'\n"
                          "end\n"))
            out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
            row("501: bbproc copied @SDSYS/newvoc.mods into SDSYS's own VOC in bootstrap pass 1",
                has(out, r"BBM=bbproc newvoc\.mods test entry"), out[-300:])
        else:
            say("  [SKIP] 501: bbproc row needs a sandbox built with --build (newvoc.mods must exist before pass 1)")
        nvmods_dir = os.path.join(sysd, "newvoc.mods")
        os.makedirs(nvmods_dir, exist_ok=True)
        with open(os.path.join(nvmods_dir, "ZZ.NVMOD.TEST"), "w", encoding="latin-1") as f:
            f.write("X\nCustom NEWVOC.MODS test entry\n")
        out = sess(box, "UPDATE.ACCOUNTS", "", "CT VOC ZZ.NVMOD.TEST")
        row("501: UPDATE.ACCOUNTS copies records from @SDSYS/newvoc.mods into VOC",
            has(out, r"Custom NEWVOC\.MODS test entry"), out[-300:])
        sess(box, "DELETE VOC ZZ.NVMOD.TEST")
        shutil.rmtree(nvmods_dir, ignore_errors=True)

        # 251: Phantom debugger (@variable evaluated in debugged phantom process rather than PDEBUG client)
        probeph = os.path.join(sysd, "bp", "zzoqph")
        made.append(probeph)
        write(probeph, ("   @user0 = 'PHANTOM.USER0.VAL'\n"
                        "   @user.return.code = 9876\n"
                        "   debug\n"
                        "   x = 1\n"
                        "end\n"))
        write(probe, ("program zzoqp1\n"
                      "   deffun atvar(name) calling '!atvar'\n"
                      "   crt 'ATVAR.NEW=':atvar('UID'):'/':atvar('CRTHIGH'):'/':atvar('SEQNO')\n"
                      "   @user0 = 'CLIENT.USER0.VAL'\n"
                      "   @user.return.code = 111\n"
                      "   execute 'PDEBUG RUN bp zzoqph'\n"
                      "   crt 'CLIENT.AFTER=':@user0:'/':@user.return.code\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqph DEBUGGING", "BASIC bp zzoqp1", "RUN bp zzoqp1",
                   "   /@USER0", "/@USER.RETURN.CODE", "/@TTY", "RUN")
        row("251: !atvar resolves newer @variables (@UID, @CRTHIGH, @SEQNO)",
            has(out, r"ATVAR\.NEW=\d+/\d+/"), out[-400:])
        row("251: phantom debugger displays @USER0 from the phantom, not the client",
            has(out, r'PHANTOM\.USER0\.VAL') and not has(out, r'@USER0.*CLIENT\.USER0\.VAL'), out[-400:])
        row("251: phantom debugger displays @USER.RETURN.CODE and @TTY from the phantom",
            has(out, r"9876") and has(out, r'phantom') and has(out, r"CLIENT\.AFTER=CLIENT\.USER0\.VAL/111"), out[-400:])

        # 94: Query processor IN and NOT.IN operators (saved lists, "file id", NO.CASE, EVERY, WHEN)
        write(probe, ("   execute 'CREATE.FILE zzoqin' capturing j1\n"
                      "   open 'zzoqin' to f else stop 'no zzoqin'\n"
                      "   open 'DICT zzoqin' to df else stop 'no dict zzoqin'\n"
                      "   write 'D':@fm:'1':@fm:'':@fm:'Color':@fm:'10L':@fm:'S' to df, 'color'\n"
                      "   write 'D':@fm:'2':@fm:'':@fm:'Tags':@fm:'12L':@fm:'M':@fm:'TASSOC' to df, 'tags'\n"
                      "   write 'RED':@fm:'alpha':@vm:'beta' to f, 'r1'\n"
                      "   write 'blue':@fm:'beta':@vm:'gamma' to f, 'r2'\n"
                      "   write 'GREEN':@fm:'alpha' to f, 'r3'\n"
                      "   write 'YELLOW':@fm:'delta' to f, 'r4'\n"
                      "   write 'RED':@fm:'BLUE':@fm:'alpha':@vm:'beta' to f, 'allow'\n"
                      "   open '$SAVEDLISTS' to slf else stop 'no $SAVEDLISTS'\n"
                      "   write 'RED':@fm:'GREEN' to slf, 'zzoq.colors'\n"
                      "   write 'alpha':@fm:'beta' to slf, 'zzoq.tags'\n"
                      "   crt 'IN FILE MADE'\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("94 CONTROL: test file and saved lists created", has(out, r"IN FILE MADE"), out[-200:])
        out = sess(box, "LIST zzoqin WITH color IN zzoq.colors @ID")
        row("94: field IN listname selects records whose field is in $SAVEDLISTS",
            has(out, r"\br1\b") and has(out, r"\br3\b") and not has(out, r"\br2\b") and not has(out, r"\br4\b"), out[-300:])
        out = sess(box, "LIST zzoqin WITH color NOT.IN zzoq.colors @ID")
        row("94: field NOT.IN listname selects records whose field is not in $SAVEDLISTS",
            has(out, r"\br2\b") and has(out, r"\br4\b") and not has(out, r"\br1\b") and not has(out, r"\br3\b"), out[-300:])
        out = sess(box, 'LIST zzoqin WITH color IN "zzoqin allow" @ID')
        row('94: field IN "filename id" case-sensitive matches RED but not blue',
            has(out, r"\br1\b") and not has(out, r"\br2\b") and not has(out, r"\br3\b"), out[-300:])
        out = sess(box, 'LIST zzoqin WITH color IN NO.CASE "zzoqin allow" @ID')
        row('94: field IN NO.CASE "filename id" matches both RED and blue',
            has(out, r"\br1\b") and has(out, r"\br2\b") and not has(out, r"\br3\b"), out[-300:])
        out = sess(box, "LIST zzoqin WITH EVERY tags IN zzoq.tags @ID")
        row("94: WITH EVERY mvfield IN listname requires all values to be in list",
            has(out, r"\br1\b") and has(out, r"\br3\b") and not has(out, r"\br2\b") and not has(out, r"\br4\b"), out[-300:])
        out = sess(box, "LIST zzoqin tags WHEN tags IN zzoq.tags")
        row("94: WHEN mvfield IN listname filters displayed multivalues",
            has(out, r"r2\s+beta") and not has(out, r"gamma") and not has(out, r"delta"), out[-300:])
        # audit 16 Oct: in / not.in with the list name left out said "To:" (message 3520, COPYP's prompt); it is message 11400 now
        # (a bare "IN" at the end of the sentence never gets this far: the clause reader says "Field name missing in selection clause")
        out = sess(box, 'LIST zzoqin WITH color IN ""')
        row("94: in with an empty list name says so (message 11400, not 3520's 'To:')",
            has(out, r"A saved list name, or a quoted file and record id, is needed after in or not\.in") and not has(out, r"(?m)^To:"), out[-300:])
        out = sess(box, 'LIST zzoqin WITH color NOT.IN ""')
        row("94: and so does not.in", has(out, r"A saved list name, or a quoted file and record id, is needed after in or not\.in"), out[-300:])
        out = sess(box, "LIST zzoqin WITH color IN zzoq.nosuchlist @ID")
        row("94: a saved list that is not there says Record \"zzoq.nosuchlist\" not found (message 3521; the docs name it)",
            has(out, r'Record "zzoq\.nosuchlist" not found'), out[-300:])
        sess(box, "DELETE.FILE zzoqin", "DELETE.LIST zzoq.colors", "DELETE.LIST zzoq.tags")

        # 371: SORT(), SORTADD, SORTCLEAR, SORTDATA(), SORTNEXT()
        write(probe, ("$include keys.h\n"
                      "   * 1. Single-key right-aligned sort with data and VARTYPE check\n"
                      "   s1 = sort(1, SRT$RIGHT + SRT$DATA)\n"
                      "   vt = vartype(s1)\n"
                      "   sortadd s1, '10', 'ten'\n"
                      "   sortadd s1, '2', 'two'\n"
                      "   sortadd s1, '100', 'hundred'\n"
                      "   d1 = sortdata(s1)\n"
                      "   st1 = status()\n"
                      "   crt 'S1=':vt:'|':st1:'|':change(d1, @fm, ',')\n"
                      "   * 2. SORTNEXT with scalar key and max.items on SORTDATA\n"
                      "   sortclear s1\n"
                      "   s2 = sort(1, SRT$LEFT + SRT$NOCASE + SRT$UNIQUE)\n"
                      "   sortadd s2, 'banana'\n"
                      "   sortadd s2, 'Apple'\n"
                      "   sortadd s2, 'apple'\n"
                      "   sortadd s2, 'Cherry'\n"
                      "   v1 = sortnext(s2, k1) ; st.n1 = status()\n"
                      "   v2 = sortnext(s2)     ; st.n2 = status()\n"
                      "   v3 = sortnext(s2, k3) ; st.n3 = status()\n"
                      "   v4 = sortnext(s2, k4) ; st.n4 = status()\n"
                      "   crt 'S2=':v1:'/':k1:'/':st.n1:'|':v2:'/':st.n2:'|':v3:'/':k3:'/':st.n3:'|':st.n4\n"
                      "   * 3. Multi-key sort with MAT flags, MAT keys, and concurrent sort sessions\n"
                      "   dim flg(2), kv(2), kout(2)\n"
                      "   flg(1) = SRT$LEFT ; flg(2) = SRT$RIGHT + SRT$DESCENDING\n"
                      "   s3 = sort(2, mat flg)\n"
                      "   s4 = sort(1, SRT$COMPOUND)\n"
                      "   kv(1) = 'B' ; kv(2) = '5'  ; sortadd s3, mat kv, 'B5'\n"
                      "   kv(1) = 'A' ; kv(2) = '3'  ; sortadd s3, kv, 'A3'\n"
                      "   kv(1) = 'A' ; kv(2) = '20' ; sortadd s3, mat kv, 'A20'\n"
                      "   for n = 1 to 5\n"
                      "      sortadd s4, 'AB':(6 - n):'CD'\n"
                      "   next n\n"
                      "   r3 = ''\n"
                      "   loop\n"
                      "      item = sortnext(s3, mat kout)\n"
                      "   until status()\n"
                      "      r3<-1> = kout(1):':':kout(2)\n"
                      "   repeat\n"
                      "   c1 = sortdata(s4, 2) ; sc1 = status()\n"
                      "   c2 = sortdata(s4, 2) ; sc2 = status()\n"
                      "   c3 = sortdata(s4, 2) ; sc3 = status()\n"
                      "   crt 'S3=':change(r3, @fm, ',')\n"
                      "   crt 'S4=':change(c1, @fm, ','):'(':sc1:')|':change(c2, @fm, ','):'(':sc2:')|':change(c3, @fm, ','):'(':sc3:')'\n"
                      "   sortclear s3\n"
                      "   sortclear s4\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("371: SORT(1, SRT$RIGHT + SRT$DATA), VARTYPE=VT$SORT (20), SORTADD and SORTDATA()",
            has(out, r"S1=20\|3\|two,ten,hundred"), out[-400:])
        row("371: SORT with SRT$NOCASE + SRT$UNIQUE and SORTNEXT(sortvar {, key})",
            has(out, r"S2=/Apple/0\|banana/0\|/Cherry/0\|1"), out[-400:])
        row("371: multi-key SORT(2, MAT flags), SORTADD with MAT keys, and SORTNEXT(..., MAT kout)",
            has(out, r"S3=A:20,A:3,B:5"), out[-400:])
        row("371: concurrent sort session with SRT$COMPOUND and chunked SORTDATA(sortvar, max.items)",
            has(out, r"S4=AB1CD,AB2CD\(2\)\|AB3CD,AB4CD\(2\)\|AB5CD\(1\)"), out[-400:])
        # 371 (audit, 16 Oct): SORTCLEAR empties a sort and it can be filled again; a sort variable is refused by a BT statement
        # (it is a BTREE header underneath); SORTADD on a variable that is not a sort is refused
        write(probe, ("$include keys.h\n"
                      "   s1 = sort(1, SRT$LEFT)\n"
                      "   sortadd s1, 'b'\n"
                      "   sortadd s1, 'a'\n"
                      "   sortclear s1\n"
                      "   d0 = sortdata(s1) ; st0 = status()\n"
                      "   sortadd s1, 'z'\n"
                      "   sortadd s1, 'y'\n"
                      "   d1 = sortdata(s1)\n"
                      "   crt 'CLR=[':d0:']/':st0:'/':change(d1, @fm, ',')\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("371: SORTCLEAR empties a sort and it can be used again", has(out, r"CLR=\[\]/0/y,z"), out[-300:])
        # The BTREE statements are internal-only, so these programs are compiled and run by `sd -internal` (the first version of this
        # row used an ordinary session, got "Unrecognised statement" and tested nothing).  A real BTree is the control for each
        # statement: it must not be refused, or a refusal of the sort variable proves only that the statement was wrong.
        # (label, the statement, what a real BTree needs first).  MODIFY works on the current element, so its control finds one first;
        # the sort variable gets the bare statement, which the guard refuses before anything else is looked at.
        bt_stmts = [("ADD key,data TO", "   add 'x', 'y' to {V}\n", ""), ("ADD matrix TO", "   mk(1) = 'x'\n   add mk to {V}\n", ""),
                    ("MODIFY", "   modify {V}, 'z'\n", "   r = find({V}, 'x')\n"), ("REWIND", "   rewind {V}\n", ""),
                    ("SCAN(var)", "   r = scan({V})\n", ""), ("SCAN(var, matrix)", "   r = scan({V}, mk)\n", ""),
                    ("FIND(var, key)", "   r = find({V}, 'x')\n", "")]
        for label, stmt, first in bt_stmts:
            body = ("$internal\n   dim m(1), mk(1)\n   m(1) = 0\n   mk(1) = 'k'\n" "   b = btree(1, m)\n   add 'x', 'y' to b\n"
                    + first.replace("{V}", "b") + stmt.replace("{V}", "b") + "   crt 'BT.CONTROL.OK'\nend\n")
            write(probe, body)
            out = isess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
            row("371 CONTROL: %s a real BTree is accepted" % label, has(out, r"BT\.CONTROL\.OK") and not has(out, r"Not a BTree"), out[-300:])
            body = ("$internal\n   dim m(1), mk(1)\n   m(1) = 0\n   mk(1) = 'k'\n   s = sort(1, 0)\n"
                    + stmt.replace("{V}", "s") + "   crt 'BT.NOT.REFUSED'\nend\n")
            write(probe, body)
            out = isess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
            row("371: %s given a sort variable is refused (Not a BTree)" % label, has(out, r"Not a BTree") and not has(out, r"BT\.NOT\.REFUSED"),
                out[-300:])
        # the messages (audit 16 Oct): 11398 for a variable that is not a sort, 11399 for the 256th sort, 11400 for in / not.in with no list
        write(probe, ("   notsort = 'abc'\n"
                      "   sortadd notsort, 'x'\n"
                      "   crt 'SORTADD.NOT.REFUSED'\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("371: SORTADD on a variable that is not a sort is refused, as 'Not a sort variable'",
            not has(out, r"SORTADD\.NOT\.REFUSED") and has(out, r"Not a sort variable") and not has(out, r"SORTDATA executed"), out[-300:])
        write(probe, ("   v = 12\n"
                      "   z = sortnext(v)\n"
                      "   crt 'SORTNEXT.NOT.REFUSED'\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("371: SORTNEXT on a variable that is not a sort says 'Not a sort variable' too",
            not has(out, r"SORTNEXT\.NOT\.REFUSED") and has(out, r"Not a sort variable"), out[-300:])
        write(probe, ("   dim sv(300)\n"
                      "   for i = 1 to 300\n"
                      "      sv(i) = sort(1, 0)\n"
                      "      last = i\n"
                      "   next i\n"
                      "   crt 'SORT.256TH.NOT.REFUSED ':last\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("371: the 256th sort open at once is refused with 'Too many sorts are open', not 'Insufficient memory'",
            not has(out, r"SORT\.256TH\.NOT\.REFUSED") and has(out, r"Too many sorts are open") and not has(out, r"Insufficient memory for sort element"),
            out[-300:])
        write(probe, ("   for i = 1 to 1000\n"
                      "      s = sort(1, 0)\n"
                      "      sortadd s, i\n"
                      "   next i\n"
                      "   crt 'SORT.OVERWRITE.OK'\n"
                      "end\n"))
        out = sess(box, "BASIC bp zzoqp1", "RUN bp zzoqp1")
        row("371 CONTROL: 1000 sorts in turn in one variable (an overwritten sort frees its slot) are not refused",
            has(out, r"SORT\.OVERWRITE\.OK") and not has(out, r"Too many sorts"), out[-300:])
    finally:
        sess(box, "DELETE.FILE zzoqfd", "DELETE.FILE zzoqc1", "DELETE.FILE zzoqc2", "DELETE.FILE zzoqld", "DELETE.FILE zzoqix",
             "DELETE.LIST zzoqla", "DELETE.LIST zzoqlb", "DELETE.LIST zzoqlc", "DELETE.LIST zzoqld2")
        shutil.rmtree(d, ignore_errors=True)
        for p in made:
            if os.path.exists(p):
                os.remove(p)
        for f in ("zzoqp1", "zzoqph"):
            p = os.path.join(sysd, "bp.out", f)
            if os.path.exists(p):
                os.remove(p)


if __name__ == "__main__":
    main()
