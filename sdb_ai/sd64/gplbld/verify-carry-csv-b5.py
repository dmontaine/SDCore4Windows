#!/usr/bin/env python3
#
# sandbox-csv-b5.py - 1.2-0 bundle B-5, sheet 173 and 200: the CSV.MODE statement.
#                     CSV.MODE mode {, delim} sets the quoting rules (1 RFC 4180, 2 all non-null items but numbers, 3 all items)
#                     and the delimiter that FORMCSV(), PRINTCSV and WRITECSV use; SYSTEM(1043) and SYSTEM(1046) read them back;
#                     a called program inherits the setting and a change in it is undone on return; EXECUTE starts at the default.
#                     No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-csv-b5.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 173 and 200.
# END-HISTORY
#
# THE INSTRUMENT.  Every value is printed in a tag, name[value], and read from the session output, anchored to the start of a
# line.  Expected strings are the examples of the openQM V4 manual (CSV.MODE) and the mode 1 output before this change is the
# control: the default behaviour must be what it was.

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
    say("sandbox-csv-b5: CANNOT RUN - " + msg)
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


def after(lines, marker):
    """The line printed straight after the marker line (what the PRINTCSV that follows it wrote)."""
    for i, ln in enumerate(lines):
        if ln == marker:
            return lines[i + 1] if i + 1 < len(lines) else None
    return None


def has(lines, pattern):
    return any(re.search(pattern, ln) for ln in lines)


PROGS = {
    "zzcvm": ("   s = 'ABC':@fm:'123':@fm:'A\"B':@fm:'A,B':@fm:''\n"
              "   crt 'D0[':system(1043):'][':system(1046):']'\n"
              "   crt 'F0:'\n   printcsv s\n"
              "   for m = 1 to 3\n      csv.mode m\n      crt 'F':m:':'\n      printcsv s\n      crt 'K':m:'[':system(1043):'][':system(1046):']'\n   next m\n"
              "   csv.mode 1\n   crt 'F4:'\n   printcsv s\n"
              "   csv.mode 1, '*'\n   crt 'W1:'\n   printcsv 'ABC', 'D*E', 'F,G'\n   crt 'W1D[':system(1046):']'\n"
              "   crt 'PA:'\n   printcsv 'ABC', 'DEF', 'GHI'\n   crt 'PB:'\n   printcsv 'A*B', 'C,D'\n"
              "   csv.mode 2, ';'\n   crt 'W2:'\n   printcsv 'x', '7', 'a;b', '', '1,5'\n"
              "   csv.mode 1, ''\n   crt 'N1[':system(1046):']'\n"
              "   csv.mode 1, '|X'\n   crt 'N2[':system(1046):']'\n"
              "   csv.mode 3\n   csv.mode 7\n   crt 'B1[':system(1043):'][':system(1046):']'\n"
              "   csv.mode 0, '+'\n   crt 'B2[':system(1043):'][':system(1046):']'\n"
              "   m = 2 ; d = '!'\n   csv.mode m, d\n   crt 'V1[':system(1043):'][':system(1046):']'\n"
              "   crt 'END'\nend\n"),
    "zzcvs": ("   subroutine zzcvs\n   crt '  S0[':system(1043):system(1046):']'\n   csv.mode 3, '#'\n   crt '  S1[':system(1043):system(1046):']'\n"
              "   crt '  S2:'\n   printcsv 'a', 'b'\n   return\nend\n"),
    "zzcvp": ("   csv.mode 2, ';'\n   call zzcvs\n   crt 'P1[':system(1043):system(1046):']'\n"
              "   crt 'P2:'\n   printcsv 'a', '7'\nend\n"),
    "zzcvx": ("   crt '  X0[':system(1043):system(1046):']'\nend\n"),
    "zzcve": ("   csv.mode 3, '#'\n   execute 'RUN bp zzcvx'\n   crt 'E1[':system(1043):system(1046):']'\nend\n"),
    "zzcvw": ("   csv.mode 2, '|'\n"
              "   openseq 'zzcvout.txt' to f then null else\n      create f else stop 'no create'\n   end\n"
              "   weofseq f\n"
              "   writecsv 'a', '12', 'b|c' to f else stop 'no write'\n"
              "   writecsv 'x' : @fm : 'y,z', '' to f else stop 'no write'\n"
              "   weofseq f\n   close f\n"
              "   openseq 'zzcvout.txt' to f else stop 'no f2'\n"
              "   readseq l1 from f else l1 = 'none'\n   readseq l2 from f else l2 = 'none'\n"
              "   crt 'WR1[':l1:']'\n   crt 'WR2[':l2:']'\n   close f\n"
              "   csv.mode 1\n   crt 'DONE'\nend\n"),
    "zzcvbad": "   csv.mode\nend\n",
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-csv-b5.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-csv-b5: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-csv-b5: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        for nm, text in PROGS.items():
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write(text)
            made.append(nm)
        good = [n for n in PROGS if n != "zzcvbad"]
        out = sess(box, "BASIC bp " + " ".join(good), "CATALOG bp zzcvs LOCAL")
        row("setup: the probes compile with no errors", has(out, r"^Compiled %d program\(s\) with no errors" % len(good)), "\n".join(out[-8:]))
        out = sess(box, "BASIC bp zzcvbad")
        row("CSV.MODE with no mode is a compile error", has(out, r"^Compiled 0 program\(s\)|error"), "\n".join(out[-4:]))

        say("\n--- the modes (manual: ABC,123,\"A\"\"B\",\"A,B\" / \"ABC\",123,... / \"ABC\",\"123\",...) ---")
        out = sess(box, "RUN bp zzcvm")
        row("the run reached its end", has(out, r"^END$"), "\n".join(out[-6:]))
        row("CONTROL: the default is mode 1 and a comma", tag(out, "D0") == "1][,", repr(tag(out, "D0")))
        row("CONTROL: before any CSV.MODE the output is RFC 4180: ABC,123,\"A\"\"B\",\"A,B\", (a null item is empty)",
            after(out, "F0:") == 'ABC,123,"A""B","A,B",', repr(after(out, "F0:")))
        row("173: mode 1 gives the same", after(out, "F1:") == 'ABC,123,"A""B","A,B",', repr(after(out, "F1:")))
        row("173: mode 2 encloses every non-null item but a number", after(out, "F2:") == '"ABC",123,"A""B","A,B",', repr(after(out, "F2:")))
        row("173: mode 3 encloses every item, a null one too", after(out, "F3:") == '"ABC","123","A""B","A,B",""', repr(after(out, "F3:")))
        row("173: SYSTEM(1043) and SYSTEM(1046) follow the setting", tag(out, "K1") == "1][," and tag(out, "K2") == "2][," and
            tag(out, "K3") == "3][,", "%r %r %r" % (tag(out, "K1"), tag(out, "K2"), tag(out, "K3")))
        row("173: back to mode 1 gives mode 1 again", after(out, "F4:") == after(out, "F1:"), repr(after(out, "F4:")))

        say("\n--- the delimiter (200) ---")
        row("200: CSV.MODE 1, '*' joins with * and encloses an item holding *, not one holding a comma",
            after(out, "W1:") == 'ABC*"D*E"*F,G' and tag(out, "W1D") == "*", "%r %r" % (after(out, "W1:"), tag(out, "W1D")))
        row("200: PRINTCSV prints with the delimiter (the manual's example)", after(out, "PA:") == "ABC*DEF*GHI", repr(after(out, "PA:")))
        row("200: ... and encloses by the same rule", after(out, "PB:") == '"A*B"*C,D', repr(after(out, "PB:")))
        row("200: mode 2 with ; encloses a text item, not a number, and a null stays null; '1,5' is not a number",
            after(out, "W2:") == '"x";7;"a;b";;"1,5"', repr(after(out, "W2:")))
        row("200: a null delimiter is a comma", tag(out, "N1") == ",", repr(tag(out, "N1")))
        row("200: only the first character of a longer delimiter is used", tag(out, "N2") == "|", repr(tag(out, "N2")))
        row("a mode outside 1 - 3 is ignored (mode 3 stays) and the delimiter given back to a comma when none is given",
            tag(out, "B1") == "3][,", repr(tag(out, "B1")))
        row("... mode 0 is ignored too, and its delimiter is taken", tag(out, "B2") == "3][+", repr(tag(out, "B2")))
        row("the mode and the delimiter may be variables", tag(out, "V1") == "2][!", repr(tag(out, "V1")))

        say("\n--- calls and EXECUTE ---")
        out = sess(box, "RUN bp zzcvp")
        row("a called subroutine starts with the caller's mode and delimiter", tag(out, "  S0") == "2;", repr(tag(out, "  S0")))
        row("... changes its own, and that takes effect there", tag(out, "  S1") == "3#" and after(out, "  S2:") == '"a"#"b"',
            "%r %r" % (tag(out, "  S1"), after(out, "  S2:")))
        row("... and on return the caller has its own again", tag(out, "P1") == "2;" and after(out, "P2:") == '"a";7',
            "%r %r" % (tag(out, "P1"), after(out, "P2:")))
        out = sess(box, "RUN bp zzcve")
        row("EXECUTE starts a new command level at the defaults (mode 1, comma)", tag(out, "  X0") == "1,", repr(tag(out, "  X0")))
        row("... and the caller's setting comes back after it", tag(out, "E1") == "3#", repr(tag(out, "E1")))

        say("\n--- WRITECSV ---")
        out = sess(box, "RUN bp zzcvw")
        row("the run reached its end", has(out, r"^DONE$"), "\n".join(out[-6:]))
        row("200: WRITECSV in mode 2 with | writes the delimiter and the quoting", tag(out, "WR1") == '"a"|12|"b|c"', repr(tag(out, "WR1")))
        row("200: ... field marks make separate items, a null item is empty", tag(out, "WR2") == '"x"|"y,z"|', repr(tag(out, "WR2")))
    finally:
        sess(box, "DELETE.CATALOG zzcvs LOCAL")
        if os.path.exists(os.path.join(sysd, "zzcvout.txt")):
            os.remove(os.path.join(sysd, "zzcvout.txt"))
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        subprocess.run([sys.executable, TOOL, box, "stop"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\nsandbox-csv-b5: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
