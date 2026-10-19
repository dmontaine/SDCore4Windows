#!/usr/bin/env python3
#
# sandbox-lang-a15.py - 1.2-0 bundle A-15, the cheapest BASIC items left on the openQM sheet:
#                         64   OPEN / OPENPATH ... NON.TRANSACTIONAL
#                         41   trailing substring assignment, var[n] = expr
#                         215  REDIMENSION (REDIM) of a matrix passed in as an argument
#                         44 and 519  a MAT argument needs no DIM statement
#                         111  IF MAT a = MAT b THEN
#                         206  a READ / OPEN / READNEXT ... statement as a WHILE or UNTIL condition
#                       No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-lang-a15.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 12 Oct 26 dm  Written for 1.2-0 bundle A-15: sheet 41, 44, 64, 111, 206, 215 and 519.
# END-HISTORY
#
# THE INSTRUMENT.  Programs are compiled and run in a private SD; what they print is read back from the session's
# output, every pattern anchored to the start of a line (a session echoes the command it was given).  Each row has
# a control beside it: the same thing done the old way, or the thing that must still be refused.
#
# WHAT THIS CANNOT SAY.  IF MAT a = MAT b compares shapes and every element, but it is a comparison of two
# strings made by MATSTR, so two matrices whose elements are numerically equal but written differently (1 and
# 1.0, say) compare as the strings they are.

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
made = []

PROGS = {
    # 64: the option, alone and with READONLY, in either order, for OPEN and OPENPATH, and what a transaction does
    "zzl64": ("$include keys.h\n"
              "   execute 'DELETE.FILE zzl64f' capturing j\n   execute 'CREATE.FILE zzl64f' capturing j\n"
              "   open 'voc' to v1 then crt 'N1[':fileinfo(v1, FL$READONLY):fileinfo(v1, FL$NON.TXN):']'\n"
              "   open 'voc' non.transactional to v2 then crt 'N2[':fileinfo(v2, FL$READONLY):fileinfo(v2, FL$NON.TXN):']'\n"
              "   open 'voc' readonly non.transactional to v3 then crt 'N3[':fileinfo(v3, FL$READONLY):fileinfo(v3, FL$NON.TXN):']'\n"
              "   open 'voc' non.transactional readonly to v4 then crt 'N4[':fileinfo(v4, FL$READONLY):fileinfo(v4, FL$NON.TXN):']'\n"
              "   open 'voc' readonly to v5 then crt 'N5[':fileinfo(v5, FL$READONLY):fileinfo(v5, FL$NON.TXN):']'\n"
              "   openpath '/tmp' non.transactional to v6 then crt 'N6[':fileinfo(v6, FL$READONLY):fileinfo(v6, FL$NON.TXN):']'\n"
              "   open 'zzl64f' non.transactional to nt else stop 'no nt'\n   open 'zzl64f' to pl else stop 'no pl'\n"
              "   begin transaction\n      recordlocku pl, 'plain'\n      write 'p' on pl, 'plain'\n      write 'n' on nt, 'nontxn'\n"
              "   rollback\n   end transaction\n"
              "   read z from pl, 'nontxn' then crt 'KEPT[yes]' else crt 'KEPT[no]'\n"
              "   read z from pl, 'plain' then crt 'GONE[no]' else crt 'GONE[yes]'\n   crt 'L64DONE'\nend\n"),
    # 41: var[n] = expr
    "zzl41": ("   s = 'abcdefgh' ; s[3] = 'XY' ; crt 'T1[':s:']'\n"
              "   s = 'abcdefgh' ; s[3] = 'XYZW' ; crt 'T2[':s:']'\n"
              "   s = 'abcdefgh' ; s[3] = 'Q' ; crt 'T3[':s:']'\n"
              "   s = 'abc' ; s[10] = 'XY' ; crt 'T4[':s:']'\n"
              "   s = 'abcdefgh' ; s[0] = 'Z' ; crt 'T5[':s:']'\n"
              "   s = '' ; s[3] = 'ab' ; crt 'T6[':s:']'\n"
              "   dim b(2) ; b(1) = 'hello' ; b(1)[2] = 'ZZ' ; crt 'T7[':b(1):']'\n"
              "   n = 4 ; s = 'abcdefgh' ; s[n + 1] = '12345' ; crt 'T8[':s:']'\n"
              "   s = 'abcdefgh' ; s[3, 2] = 'XY' ; crt 'T9[':s:']'\n"
              "   crt 'L41DONE'\nend\n"),
    # 215 and 44/519: the subroutines are catalogued locally
    "zzl215s": ("   subroutine zzl215s(mat a)\n   dim a(1)\n   a(3) = 'changed'\n   redim a(10)\n   a(8) = 'eight'\n   return\nend\n"),
    "zzl215": ("   dim a(5)\n   for i = 1 to 5 ; a(i) = i ; next i\n   call zzl215s(mat a)\n"
               "   crt 'R1[':a(3):']'\n   crt 'R2[':a(8):']'\n   crt 'L215DONE'\nend\n"),
    "zzl44s": ("   subroutine zzl44s(mat a)\n   a(2) = 'two'\n   x = a(3)\n   return\nend\n"),
    "zzl44": ("   dim a(4) ; a(3) = 'three'\n   call zzl44s(mat a)\n   crt 'M1[':a(2):']'\n"
              "   dim q(4)\n   q(4) = 'last'\n   gosub zloc2(mat q)\n   crt 'M2[':q(2):q(4):']'\n"
              "   dim p(2,2)\n   gosub zloc3(mat p)\n   crt 'M3[':p(2,2):']'\n   crt 'L44DONE'\n   stop\n\n"
              "local subroutine zloc2(mat a)\n   a(2) = 'set'\n   return\nend\n\n"
              "local subroutine zloc3(mat a)\n   a(2,2) = 'two-d'\n   return\nend\n"),
    # 111
    "zzl111": ("   dim a(2,2), b(2,2), d(4), e(2,2), f(3), g(3), h(3)\n"
               "   mat a = 1 ; mat b = 1\n"
               "   if mat a = mat b then crt 'C1[equal]' else crt 'C1[different]'\n"
               "   b(2,2) = 9\n"
               "   if mat a = mat b then crt 'C2[equal]' else crt 'C2[different]'\n"
               "   if mat a # mat b then crt 'C3[different]' else crt 'C3[equal]'\n"
               "   mat d = 5 ; mat e = 5\n"
               "   if mat d = mat e then crt 'C4[equal]' else crt 'C4[different]'\n"
               "   f(1) = 'x' ; g(1) = 'x' ; h(1) = 'x' ; h(3) = 'y'\n"
               "   if mat f = mat g then crt 'C5[equal]' else crt 'C5[different]'\n"
               "   if mat f = mat h then crt 'C6[equal]' else crt 'C6[different]'\n"
               "   crt 'L111DONE'\nend\n"),
    # 206
    "zzl206": ("   open 'voc' to v else stop 'no voc'\n"
               "   select v to 1\n   n = 0\n   loop while readnext id from 1 do n += 1 repeat\n   crt 'W1[':(n > 10):']'\n"
               "   k = 0\n   loop while read r from v, 'nosuchvocitem' do k += 1 repeat\n   crt 'W2[':k:']'\n"
               "   loop while read r from v, 'LOGTO' do k += 1 ; exit repeat\n   crt 'W3[':k:']'\n"
               "   m = 0\n   loop\n      m += 1\n   until read r from v, 'LOGTO' do\n   repeat\n   crt 'U1[':m:']'\n"
               "   m = 0\n   loop\n      m += 1\n   until read r from v, 'nosuchvocitem' do if m > 3 then exit\n   repeat\n   crt 'U2[':m:']'\n"
               "   j = 0\n   loop while open 'voc' to w do j += 1 ; exit repeat\n   crt 'W4[':j:']'\n"
               "   j = 0\n   loop while open 'nosuchfile' to w2 do j += 1 repeat\n   crt 'W5[':j:']'\n"
               "   x = 7\n   loop while x < 10 do x += 1 repeat\n   crt 'W6[':x:']'\n"
               "   crt 'L206DONE'\nend\n"),
}

# programs that must NOT compile, with the message the compiler must give
BAD = {
    "zzl44bad": ("   x = b(1)\n   dim c(2)\n   crt 'x'\nend\n", r"(?m)^\d+: Matrix B is not referenced in a DIM statement"),
    "zzl206bad": ("   open 'voc' to v else stop 'no voc'\n   loop while read r from v, 'LOGTO' then crt 'x' do repeat\nend\n", None),
}


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
    say("sandbox-lang-a15: CANNOT RUN - " + msg)
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
        bail("usage: sandbox-lang-a15.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-lang-a15: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-lang-a15: built, bootstrap passed")
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
            if nm in ("zzl215s", "zzl44s"):
                cmds.append("CATALOG bp %s LOCAL" % nm)
        out = sess(box, *cmds)
        n = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
        if n != len(PROGS):
            # On a tree that cannot compile the new syntax this is the RED result, not a reason to stop: a program
            # that did not compile is not run, and every row that reads its output fails.  It is said out loud.
            bad = re.findall(r"(?m)^Compiled 1 program\(s\) with errors in:\n\s+(\w+)", out)
            say("  !! %d of %d programs compiled; not compiled: %s" % (n, len(PROGS), ", ".join(bad) or "?"))
            if n == 0:
                bail("no program compiled:\n" + out[-1500:])

        say("\n--- 64 NON.TRANSACTIONAL on OPEN and OPENPATH ---------------------------------------")
        out = sess(box, "RUN bp zzl64")
        row("CONTROL: a plain OPEN is neither read-only nor non-transactional (N1 00)", tagged(out, "N1") == "00", "got %r" % tagged(out, "N1"))
        row("64: OPEN ... NON.TRANSACTIONAL TO (N2 01)", tagged(out, "N2") == "01", "got %r" % tagged(out, "N2"))
        row("64: READONLY NON.TRANSACTIONAL together (N3 11)", tagged(out, "N3") == "11", "got %r" % tagged(out, "N3"))
        row("64: ... and in the other order (N4 11)", tagged(out, "N4") == "11", "got %r" % tagged(out, "N4"))
        row("CONTROL: READONLY alone is read-only only (N5 10)", tagged(out, "N5") == "10", "got %r" % tagged(out, "N5"))
        row("64: OPENPATH ... NON.TRANSACTIONAL (N6 01)", tagged(out, "N6") == "01", "got %r" % tagged(out, "N6"))
        row("64: a write through the non-transactional open survives ROLLBACK", tagged(out, "KEPT") == "yes", out[-300:])
        row("CONTROL: ... and a write through a plain open does not", tagged(out, "GONE") == "yes", out[-300:])

        say("\n--- 41 trailing substring assignment ------------------------------------------------")
        out = sess(box, "RUN bp zzl41")
        got ={t: tagged(out, t) for t in ("T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9")}
        say("    %s" % got)
        row("41: s[3] = 'XY' fills the last 3 characters, padding with a space", got["T1"] == "abcdeXY ", "got %r" % got["T1"])
        row("41: a value longer than the substring loses its trailing characters", got["T2"] == "abcdeXYZ", "got %r" % got["T2"])
        row("41: a shorter value is padded with spaces", got["T3"] == "abcdeQ  ", "got %r" % got["T3"])
        row("41: n above the length is the length", got["T4"] == "XY ", "got %r" % got["T4"])
        row("41: n below 1 is 1", got["T5"] == "abcdefgZ", "got %r" % got["T5"])
        row("41: an empty string stays empty", got["T6"] == "", "got %r" % got["T6"])
        row("41: a matrix element, b(1)[2] = 'ZZ'", got["T7"] == "helZZ", "got %r" % got["T7"])
        row("41: an expression for n, s[n + 1] = '12345' (5 characters, 5 given)", got["T8"] == "abc12345", "got %r" % got["T8"])
        row("CONTROL: the ordinary s[3, 2] = 'XY' still overlays at character 3", got["T9"] == "abXYefgh", "got %r" % got["T9"])

        say("\n--- 215 REDIMENSION of an argument, 44 and 519 a MAT argument with no DIM ---------")
        out = sess(box, "RUN bp zzl215")
        row("215: the caller sees what the subroutine stored (a(3))", tagged(out, "R1") == "changed", "got %r" % tagged(out, "R1"))
        row("215: REDIM a(10) in the subroutine made the caller's matrix 10 long (a(8))", tagged(out, "R2") == "eight",
            out[-300:])
        out = sess(box, "RUN bp zzl44")
        row("44: a subroutine with (MAT a) and no DIM compiles and stores into the caller's matrix", tagged(out, "M1") == "two", out[-300:])
        row("519: a LOCAL SUBROUTINE with a one dimensional MAT argument and no DIM", tagged(out, "M2") == "setlast", out[-300:])
        row("519: ... and a two dimensional one", tagged(out, "M3") == "two-d", out[-300:])
        for nm, (text, pat) in BAD.items():
            if pat is None:
                continue
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write(text)
            made.append(nm)
            out = sess(box, "BASIC bp %s" % nm)
            row("CONTROL: an ordinary matrix with no DIM is still refused (%s)" % nm, re.search(pat, out) is not None, out[-300:])

        say("\n--- 111 IF MAT a = MAT b ------------------------------------------------------------")
        out = sess(box, "RUN bp zzl111")
        row("111: two equal matrices are equal", tagged(out, "C1") == "equal", out[-300:])
        row("111: matrices that differ in one element are different", tagged(out, "C2") == "different", out[-300:])
        row("111: # says so too", tagged(out, "C3") == "different", out[-300:])
        row("111: a 4 element and a 2 by 2 matrix holding the same value are different (shape counts)",
            tagged(out, "C4") == "different", out[-300:])
        row("111: matrices that differ only in trailing empty elements are equal when they really are", tagged(out, "C5") == "equal", out[-300:])
        row("111: ... and different when one has a value the other has not", tagged(out, "C6") == "different", out[-300:])

        say("\n--- 206 READ / OPEN / READNEXT as a WHILE or UNTIL condition -------------------------")
        out = sess(box, "RUN bp zzl206")
        row("206: LOOP WHILE READNEXT id FROM 1 DO runs once for each item (more than 10 in the VOC)", tagged(out, "W1") == "1", out[-300:])
        row("206: LOOP WHILE READ ... a record that is not there: the body never runs", tagged(out, "W2") == "0", out[-300:])
        row("206: ... one that is there: the body runs", tagged(out, "W3") == "1", out[-300:])
        row("206: LOOP ... UNTIL READ ... of a record that is there stops after one go", tagged(out, "U1") == "1", out[-300:])
        row("206: ... of one that is not there keeps going until the loop's own EXIT", tagged(out, "U2") == "4", out[-300:])
        row("206: LOOP WHILE OPEN ... TO a file that exists", tagged(out, "W4") == "1", out[-300:])
        row("206: ... a file that does not exist", tagged(out, "W5") == "0", out[-300:])
        row("CONTROL: LOOP WHILE x < 10 is unchanged", tagged(out, "W6") == "10", out[-300:])
        with open(os.path.join(sysd, "bp", "zzl206bad"), "w") as f:
            f.write(BAD["zzl206bad"][0])
        made.append("zzl206bad")
        out = sess(box, "BASIC bp zzl206bad")
        row("206: a condition statement given a THEN clause of its own is refused, not miscompiled",
            re.search(r"(?m)^\d+: .*[Ss]yntax", out) is not None or "1 error(s)" in out, out[-300:])
    finally:
        tool(box, "stop", timeout=120)
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-lang-a15: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
