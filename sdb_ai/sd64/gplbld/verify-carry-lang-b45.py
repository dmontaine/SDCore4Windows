#!/usr/bin/env python3
#
# sandbox-lang-b45.py - 1.2-0 bundles B-4 and B-5, the third sitting (14 Oct 26): four small changes to SD BASIC.  Sheet items
#                       307 (COMPARE() takes an I after the justification letter for a case insensitive comparison), 201
#                       (PRECISION INHERIT), 454 (INMAT() after MATBUILD and MATWRITE is the index of the last element
#                       included) and 430 (the ~= operator).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-lang-b45.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet items 307, 201, 454 and 430.
# END-HISTORY
#
# THE INSTRUMENT.  Probe programs are compiled and run in the sandbox's SDSYS account; every value they print is tagged
# NAME[value] and read from the start of a line, because a session echoes what it was given.  The expected values come from the
# openQM manual's text for each statement (written beside each row), not from what the build printed.  Each item has a
# control: the behaviour that must NOT have changed (COMPARE without an I, a plain =, PRECISION with a number, a matrix whose
# zero element is null, and a ~ that is not part of ~=).

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
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
    say("sandbox-lang-b45: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "sys")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]
    return [ln.rstrip() for ln in out.splitlines() if ln.strip() and not ln.startswith(":")]


def tag(lines, name):
    for ln in lines:
        m = re.match(r"^%s\[(.*)\]\s*$" % re.escape(name), ln)
        if m:
            return m.group(1)
    return None


def has(lines, pattern):
    return any(re.search(pattern, ln) for ln in lines)


PROGS = {
    # 307: every case of the justification argument
    "zzlbcmp": ("   crt 'C1[':compare('abc', 'ABC'):']'\n   crt 'C2[':compare('abc', 'ABC', 'L'):']'\n"
                "   crt 'C3[':compare('abc', 'ABC', 'LI'):']'\n   crt 'C4[':compare('abc', 'ABD', 'LI'):']'\n"
                "   crt 'C5[':compare('b', 'ABD', 'li'):']'\n   crt 'C6[':compare('  ab', 'AB', 'RI'):']'\n"
                "   crt 'C7[':compare('  ab', 'AB', 'R'):']'\n   crt 'C8[':compare('abc', 'abcd', 'LI'):']'\n"
                "   crt 'C9[':compare('ABD', 'abc', 'LI'):']'\n   crt 'C10[':compare('abc', 'ABC', 'X'):']'\n"
                "   crt 'C11[':compare('a1', 'A1', 'LI'):']'\n   crt 'C12[':compare('a[', 'A{', 'LI'):']'\nend\n"),
    # 201: PRECISION INHERIT through a called subroutine
    "zzlbprs": ("   subroutine zzlbprs\n   crt '  S0[':system(1070):']'\n   precision inherit\n   crt '  S1[':system(1070):']'\n"
                "   precision 2\n   crt '  S2[':system(1070):']'\n   return\nend\n"),
    "zzlbpr": ("   crt 'P0[':system(1070):']'\n   call zzlbprs\n   crt 'P1[':system(1070):']'\n   precision 7\n   call zzlbprs\n"
               "   crt 'P2[':system(1070):']'\n   precision 'inherit'\n   crt 'P3[':system(1070):']'\n   precision 3\n   crt 'P4[':system(1070):']'\n"
               "   precision '9'\n   crt 'P5[':system(1070):']'\nend\n"),
    # 454: INMAT() after MATBUILD
    "zzlbmat": ("   dim m(5)\n   mat m = ''\n   m(1) = 'a' ; m(3) = 'c'\n   matbuild s from m\n   crt 'M1[':inmat():'][':change(s, @fm, '/'):']'\n"
                "   m(0) = 'z'\n   matbuild s from m\n   crt 'M2[':inmat():'][':change(s, @fm, '/'):']'\n"
                "   m(0) = ''\n   m(5) = 'e'\n   matbuild s from m\n   crt 'M3[':inmat():'][':change(s, @fm, '/'):']'\n"
                "   mat m = ''\n   matbuild s from m\n   crt 'M4[':inmat():'][':s:']'\n"
                "   dim p(4)\n   mat p = ''\n   p(2) = 'x'\n   matbuild s from p\n   crt 'M6[':inmat():'][':change(s, @fm, '/'):']'\n"
                "   execute 'DELETE.FILE zzlbf' capturing j\n   execute 'CREATE.FILE zzlbf' capturing j\n   open 'zzlbf' to f else stop 'no f'\n"
                "   mat m = ''\n   m(1) = 'u' ; m(4) = 'v'\n   matwrite m to f, 'r1'\n   crt 'M7[':inmat():']'\n"
                "   m(0) = 'zero'\n   matwrite m to f, 'r2'\n   crt 'M8[':inmat():']'\n"
                "   read r from f, 'r2' then crt 'M8REC[':change(r, @fm, '/'):']'\n"
                "   x = inmat()\n   crt 'M9[':x:']'\nend\n"),
    # 430: ~=
    "zzlbtil": ("   a = 'ABC'\n   if a ~= 'abc' then crt 'TILDE-YES' else crt 'TILDE-NO'\n"
                "   if a = 'abc' then crt 'EQ-YES' else crt 'EQ-NO'\n   x = (a ~= 'AbC')\n   crt 'X[':x:']'\n"
                "   crt 'NUM[':(1 ~= 1.0):'][':('00' ~= '0'):'][':('' ~= ''):'][':('a' ~= 'b'):'][':('ab' ~= 'ABC'):'][':('ab' ~= ''):']'\n"
                "   y = 'it~is' ; crt 'STR[':y:']'\n   if a ~= 'abc' and 1 then crt 'AND-YES'\n   if not(a ~= 'x') then crt 'NOT-YES'\n"
                "   z = 'q' ; if z~='Q' then crt 'TIGHT'\n   if z ~= 'Q' or 0 then crt 'OR-YES'\n"
                "   crt 'LONG[':('MixedCase' ~= 'mIXEDcASE'):'][':('MixedCase' ~= 'mIXEDcASf'):']'\n"
                "   if (z ~= 'Q') = 1 then crt 'PAREN-YES'\nend\n"),
    "zzlbbad": "   a = 'x'\n   b = ~a\nend\n",
    "zzlbbad2": "   a = 'x'\n   if a ~ 'x' then crt 'no'\nend\n",
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-lang-b45.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-lang-b45: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-lang-b45: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        for nm, text in PROGS.items():
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write(text)
            made.append(nm)
        good = [n for n in PROGS if not n.startswith("zzlbbad")]
        out = sess(box, "BASIC bp " + " ".join(good), "CATALOG bp zzlbprs LOCAL")
        row("setup: the probes compile with no errors", has(out, r"^Compiled %d program\(s\) with no errors" % len(good)), "\n".join(out[-8:]))

        say("\n--- 307: COMPARE() with an I after the justification letter (manual: 'an optional second character of I') ---")
        out = sess(box, "RUN bp zzlbcmp")
        row("CONTROL: no justification, or L, is case sensitive: 'abc' against 'ABC' is 1 (lower case is the higher)",
            tag(out, "C1") == "1" and tag(out, "C2") == "1", "%r %r" % (tag(out, "C1"), tag(out, "C2")))
        row("LI: the same two strings are equal (0)", tag(out, "C3") == "0", repr(tag(out, "C3")))
        row("LI: 'abc' against 'ABD' is -1, and 'ABD' against 'abc' is 1 (the order is that of the letters, not their case)",
            tag(out, "C4") == "-1" and tag(out, "C9") == "1", "%r %r" % (tag(out, "C4"), tag(out, "C9")))
        row("li (the I in lower case) is accepted, and 'b' against 'ABD' is 1", tag(out, "C5") == "1", repr(tag(out, "C5")))
        row("RI: right justified and case insensitive: '  ab' against 'AB' is equal (0)", tag(out, "C6") == "0", repr(tag(out, "C6")))
        row("CONTROL: R alone is case sensitive: '  ab' against 'AB' is 1", tag(out, "C7") == "1", repr(tag(out, "C7")))
        row("LI: a shorter string that matches as far as it goes is the lesser (-1)", tag(out, "C8") == "-1", repr(tag(out, "C8")))
        row("CONTROL: a justification letter that is neither L nor R is taken as L, case sensitive: 'abc' against 'ABC' is 1",
            tag(out, "C10") == "1", repr(tag(out, "C10")))
        row("LI: digits are unaffected ('a1' and 'A1' are equal), and only letters fold: 'a[' against 'A{' is not 0",
            tag(out, "C11") == "0" and tag(out, "C12") not in (None, "0"), "%r %r" % (tag(out, "C11"), tag(out, "C12")))

        say("\n--- 201: PRECISION INHERIT (manual: the program takes the precision of the one that called it) ---------------")
        out = sess(box, "RUN bp zzlbpr")
        row("CONTROL: a program starts at 4, and a subroutine it calls starts at 4 too, not at its caller's",
            tag(out, "P0") == "4" and tag(out, "  S0") == "4", "%r %r" % (tag(out, "P0"), tag(out, "  S0")))
        row("INHERIT, caller at 4: the subroutine has 4", tag(out, "  S1") == "4", repr(tag(out, "  S1")))
        row("... and setting 2 afterwards changes only the subroutine: the caller is still 4 on return", tag(out, "  S2") == "2" and tag(out, "P1") == "4",
            "%r %r" % (tag(out, "  S2"), tag(out, "P1")))
        lines = [ln for ln in out if re.match(r"^\s+S1\[", ln)]
        row("INHERIT, caller at 7: the subroutine has 7 (the second call)", len(lines) == 2 and lines[1].strip() == "S1[7]", repr(lines))
        row("... and the caller is still 7 after it", tag(out, "P2") == "7", repr(tag(out, "P2")))
        row("INHERIT in the top program takes the command processor's precision, 4: CPROC called it, so it has a caller (it had set 7)",
            tag(out, "P3") == "4", repr(tag(out, "P3")))
        row("CONTROL: PRECISION with a number or a numeric string works as ever", tag(out, "P4") == "3" and tag(out, "P5") == "9",
            "%r %r" % (tag(out, "P4"), tag(out, "P5")))

        say("\n--- 454: INMAT() after MATBUILD and MATWRITE (manual: the index of the final element included) -----------------")
        out = sess(box, "RUN bp zzlbmat")
        row("MATBUILD of a(1) and a(3) in a matrix of 5: INMAT() is 3 and the string is a//c", tag(out, "M1") == "3][a//c", repr(tag(out, "M1")))
        row("with a non-null zero element, which is added at the end, INMAT() is 0", tag(out, "M2") == "0][a//c/z", repr(tag(out, "M2")))
        row("CONTROL: the zero element null again and element 5 set: INMAT() is 5 (trailing nulls are dropped, an inner null stays)",
            tag(out, "M3") == "5][a//c//e", repr(tag(out, "M3")))
        row("a matrix that is all null: INMAT() is 0 and the string is null", tag(out, "M4") == "0][", repr(tag(out, "M4")))
        row("a single element in position 2 only: INMAT() is 2", tag(out, "M6") == "2][/x", repr(tag(out, "M6")))
        row("MATWRITE: INMAT() is the last element written (4) and 0 when the zero element went with it",
            tag(out, "M7") == "4" and tag(out, "M8") == "0", "%r %r" % (tag(out, "M7"), tag(out, "M8")))
        row("... the record MATWRITE made for the zero element case holds it last", tag(out, "M8REC") == "u///v/zero", repr(tag(out, "M8REC")))

        say("\n--- 430: the ~= operator (manual: a case insensitive comparison; = stays case sensitive) --------------------")
        out = sess(box, "RUN bp zzlbtil")
        row("'ABC' ~= 'abc' is true, and the plain = is still false", has(out, r"^TILDE-YES$") and has(out, r"^EQ-NO$"), repr(out[-12:]))
        row("as a value: (a ~= 'AbC') is 1", tag(out, "X") == "1", repr(tag(out, "X")))
        row("the values: 1 ~= 1.0 is 1, '00' ~= '0' is 1 (two numbers compare as numbers), '' ~= '' is 1, 'a' ~= 'b' is 0, 'ab' ~= 'ABC' is 0, 'ab' ~= '' is 0",
            tag(out, "NUM") == "1][1][1][0][0][0", repr(tag(out, "NUM")))
        row("a ~ inside a string is still just a character", tag(out, "STR") == "it~is", repr(tag(out, "STR")))
        row("it takes its place among the other operators: with AND, OR, NOT and brackets",
            has(out, r"^AND-YES$") and has(out, r"^NOT-YES$") and has(out, r"^OR-YES$") and has(out, r"^PAREN-YES$"), repr(out[-12:]))
        row("with no spaces round it (z~='Q') and with them", has(out, r"^TIGHT$"), repr(out[-12:]))
        row("longer strings and every letter folded: 'MixedCase' ~= 'mIXEDcASE' is 1, 'MixedCase' ~= 'mIXEDcASf' is 0",
            tag(out, "LONG") == "1][0", repr(tag(out, "LONG")))
        # (A ~ that is not part of ~= was not refused before this change either - the tokeniser passes it on as an unknown
        # token that the compiler ignores - and is not now: no row asserts a refusal.)
    finally:
        for nm in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, nm)
                if os.path.exists(p):
                    os.remove(p)
        sess(box, "DELETE.CATALOG zzlbprs", "DELETE.FILE zzlbf")

    say("\nsandbox-lang-b45: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
