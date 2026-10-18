#!/usr/bin/env python3
#
# sandbox-bcomp-a1.py - 1.2-0 bundle A-1 (openQM features after 2.6.6, BCOMP only): does the compiler do
#                       what each item says?  Needs no install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-bcomp-a1.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (a private SD built from a tree, its own IPC keys, never the
# live system).  With --build the sandbox is built first from THIS tree and <dir> must be empty or absent.
# Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 10 Oct 26 dm  Written for 1.2-0 bundle A-1, one leg per item as it was built.
# END-HISTORY
#
# THE INSTRUMENT IS WHAT THE COMPILED PROGRAM DID, not that the compiler said nothing: each row compiles a
# probe (and demands the compiler's own success wording, which is printed only when it compiled) and RUNS it,
# and each feature has a CONTROL (the same program without the feature) that must show the OLD behaviour, so
# a row cannot pass because the probe never reached the statement it is about.
#
# Legs and openQM reference numbers (column A of openQM-feature-evaluation_bp_261008.xlsx):
#   1  IMPLIED.STOP mode, ref 81
#   2  $MODE with a comma separated list, ref 105
#   3  $BASIC.OPTIONS MODE with a list and with a minus, refs 105 and 406
#   4  @LINE, ref 211, and @BUILD.TIME, ref 506

import importlib.util
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
OK = r"(?m)^Compiled 1 program\(s\) with no errors"


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
    say("sandbox-bcomp-a1: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    for line in out.splitlines():
        if line.strip() and not line.startswith(":") and not line.startswith("exit "):
            say("      | " + line.rstrip()[:120])
    return out


def write(path, lines):
    with open(path, "wb") as f:
        f.write(("\n".join(lines) + "\n").encode("ascii"))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-bcomp-a1.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-bcomp-a1: sandbox %s" % box)
    say("sandbox-bcomp-a1: tree    %s" % os.path.dirname(HERE))
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-bcomp-a1: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    bp = os.path.join(sysd, "bp")
    made = []

    def prog(name, lines):
        write(os.path.join(bp, name), lines)
        made.append(name)

    try:
        # --- leg 1: IMPLIED.STOP -------------------------------------------------------------
        say("\n--- leg 1: IMPLIED.STOP (ref 81) -----------------------------------------------")
        prog("zza1s0", ["subroutine zza1s0", "   crt 'IN0'", "end"])
        prog("zza1s1", ["$mode implied.stop", "subroutine zza1s1", "   crt 'IN1'", "end"])
        prog("zza1m0", ["   call zza1s0", "   crt 'AFTER0'", "end"])
        prog("zza1m1", ["   call zza1s1", "   crt 'AFTER1'", "end"])
        out = sess(box, "BASIC bp zza1s0 zza1s1 zza1m0 zza1m1", "CATALOG bp zza1s0 LOCAL", "CATALOG bp zza1s1 LOCAL")
        row("setup: the four programs compiled with no errors",
            re.search(r"(?m)^Compiled 4 program\(s\) with no errors", out) is not None, "no success wording")
        out = sess(box, "RUN bp zza1m0", "RUN bp zza1m1")
        row("CONTROL: without the mode a subroutine that runs off its END returns (AFTER0 shown)",
            re.search(r"(?m)^IN0\s*$", out) and re.search(r"(?m)^AFTER0\s*$", out), "no IN0/AFTER0")
        row("THE ROW: with IMPLIED.STOP the same subroutine stops the program (IN1 shown, AFTER1 not)",
            re.search(r"(?m)^IN1\s*$", out) and not re.search(r"(?m)^AFTER1\s*$", out), "IN1/AFTER1 lines wrong")

        # --- leg 2: $MODE list --------------------------------------------------------------
        say("\n--- leg 2: $MODE name list (ref 105) -------------------------------------------")
        prog("zza1l1", ["$mode implied.stop, pick.substr", "subroutine zza1l1", "   crt 'L1'", "end"])
        prog("zza1l2", ["$mode pick.substr,-implied.stop", "subroutine zza1l2", "   crt 'L2'", "end"])
        prog("zza1l3", ["$mode pick.substr,no.such.mode", "subroutine zza1l3", "end"])
        # a trailing comma is a line continuation in SD source, so the next line holds the next name
        prog("zza1l4", ["$mode pick.substr,", "   implied.stop", "subroutine zza1l4", "end"])
        prog("zza1m2", ["   call zza1l2", "   crt 'AFTER2'", "end"])
        out = sess(box, "BASIC bp zza1l1")
        row("a two name list compiles with no errors", re.search(OK, out) is not None, "no success wording")
        out = sess(box, "BASIC bp zza1l2", "CATALOG bp zza1l2 LOCAL", "BASIC bp zza1m2", "RUN bp zza1m2")
        row("a list with -NAME second compiles, and the minus turned the mode OFF (AFTER2 shown)",
            re.search(r"(?m)^L2\s*$", out) and re.search(r"(?m)^AFTER2\s*$", out), "L2/AFTER2 lines wrong")
        out = sess(box, "BASIC bp zza1l3")
        row("a list with an unknown name is refused with 2842",
            re.search(OK, out) is None and re.search(r"(?i)unrecognised mode name", out) is not None, "no refusal")
        out = sess(box, "BASIC bp zza1l4")
        row("a list continued onto the next line after a comma compiles with no errors",
            re.search(OK, out) is not None, "no success wording")

        # --- leg 3: $BASIC.OPTIONS ----------------------------------------------------------------
        say("\n--- leg 3: $BASIC.OPTIONS MODE (refs 105, 406) -----------------------------------")
        opt = os.path.join(bp, "$BASIC.OPTIONS")
        prog("zza1o1", ["subroutine zza1o1", "   crt 'O1'", "end"])
        prog("zza1m3", ["   call zza1o1", "   crt 'AFTER3'", "end"])
        try:
            write(opt, ["X", "MODE IMPLIED.STOP,PICK.SUBSTR"])
            out = sess(box, "BASIC bp zza1o1", "CATALOG bp zza1o1 LOCAL", "BASIC bp zza1m3", "RUN bp zza1m3")
            row("MODE a,b in $BASIC.OPTIONS turns IMPLIED.STOP on (O1 shown, AFTER3 not)",
                re.search(r"(?m)^O1\s*$", out) and not re.search(r"(?m)^AFTER3\s*$", out), "lines wrong")
            write(opt, ["X", "MODE IMPLIED.STOP", "MODE -IMPLIED.STOP"])
            out = sess(box, "BASIC bp zza1o1", "CATALOG bp zza1o1 LOCAL", "RUN bp zza1m3")
            row("a later MODE -IMPLIED.STOP turns it off again (AFTER3 shown)",
                re.search(r"(?m)^O1\s*$", out) and re.search(r"(?m)^AFTER3\s*$", out), "lines wrong")
        finally:
            if os.path.exists(opt):
                os.remove(opt)

        # --- leg 4: @LINE and @BUILD.TIME --------------------------------------------------------
        say("\n--- leg 4: @LINE (ref 211), @BUILD.TIME (ref 506) -------------------------------------")
        prog("zza1t", ["* line 1", "   crt 'LINE[':@line:']'", "   crt 'AT[':@build.time:']'", "   x = @line", "   crt 'X[':x:']'", "end"])
        t0 = time.time()
        out = sess(box, "BASIC bp zza1t", "RUN bp zza1t")
        t1 = time.time()
        row("setup: the probe compiled with no errors", re.search(OK, out) is not None, "no success wording")
        m = re.search(r"(?m)^LINE\[(\d+)\]\s*$", out)
        row("@LINE is the source line it stands on (2)", m is not None and m.group(1) == "2", "got %r" % (m.group(1) if m else None))
        m = re.search(r"(?m)^X\[(\d+)\]\s*$", out)
        row("@LINE can be assigned to a variable, on line 4", m is not None and m.group(1) == "4", "got %r" % (m.group(1) if m else None))
        m = re.search(r"(?m)^AT\[(\d+)\]\s*$", out)
        local_off = time.localtime(t0).tm_gmtoff
        lo, hi = int(t0) + local_off - 60, int(t1) + local_off + 60
        row("@BUILD.TIME is the compile time as seconds since 1970 (local time), within a minute of now",
            m is not None and lo <= int(m.group(1)) <= hi, "got %r, wanted %d..%d" % (m.group(1) if m else None, lo, hi))

        # --- leg 5: $IFDEF / $IFNDEF with AND and OR ------------------------------------------
        say("\n--- leg 5: $IFDEF and $IFNDEF with AND, OR (ref 219) ---------------------------------")
        # defined here: SD (always).  NOSUCH1 and NOSUCH2 are not.
        cases = [
            ("zza1d1", "$ifdef sd and nosuch1", False, "SD AND NOSUCH1 is false"),
            ("zza1d2", "$ifdef sd and sd", True, "SD AND SD is true"),
            ("zza1d3", "$ifdef nosuch1 or sd", True, "NOSUCH1 OR SD is true"),
            ("zza1d4", "$ifdef nosuch1 or nosuch2", False, "NOSUCH1 OR NOSUCH2 is false"),
            ("zza1d5", "$ifdef nosuch1 and nosuch2 or sd", True, "AND binds tighter: (N1 AND N2) OR SD is true"),
            ("zza1d6", "$ifdef sd or nosuch1 and nosuch2", True, "SD OR (N1 AND N2) is true"),
            ("zza1d7", "$ifndef sd and nosuch1", True, "IFNDEF is the negation: not (SD AND N1) is true"),
            ("zza1d8", "$ifndef nosuch1 or nosuch2", True, "IFNDEF: not (N1 OR N2) is true"),
            ("zza1d9", "$ifndef sd or nosuch1", False, "IFNDEF: not (SD OR N1) is false"),
            ("zza1da", "$ifdef sd", True, "the old single-name form still works (SD)"),
            ("zza1db", "$ifdef nosuch1", False, "the old single-name form still works (NOSUCH1)"),
            ("zza1dc", "$ifdef", False, "no name at all is false, as before"),
        ]
        for name, directive, want, label in cases:
            prog(name, [directive, "   crt 'IN'", "$endif", "   crt 'END'", "end"])
        out = sess(box, "BASIC bp " + " ".join(c[0] for c in cases))
        row("setup: all %d $IFDEF probes compiled with no errors" % len(cases),
            re.search(r"(?m)^Compiled %d program\(s\) with no errors" % len(cases), out) is not None, "no success wording")
        out = sess(box, *["RUN bp " + c[0] for c in cases])
        # each run prints END; IN appears first if the group was kept.  Walk the output in order.
        seq = re.findall(r"(?m)^(IN|END)\s*$", out)
        got, cur = [], False
        for w in seq:
            if w == "IN":
                cur = True
            else:
                got.append(cur)
                cur = False
        row("every probe ran to its END line (%d of %d)" % (len(got), len(cases)), len(got) == len(cases), "runs: %d" % len(got))
        if len(got) == len(cases):
            for (name, directive, want, label), g in zip(cases, got):
                row("%s: '%s' -> %s" % (label, directive, "kept" if want else "skipped"), g == want,
                    "was %s" % ("kept" if g else "skipped"))

        # --- leg 6: $MODE STRICT.EQUATE ------------------------------------------------------
        say("\n--- leg 6: $MODE STRICT.EQUATE (ref 582) --------------------------------------------")
        prog("zza1e0", ["   equate crt to 5", "   equate myname to 6", "$define index 1", "end"])
        prog("zza1e1", ["$mode strict.equate", "   equate crt to 5", "   equate myname to 6",
                        "$define index 1", "$define fine.name 1", "end"])
        out = sess(box, "BASIC bp zza1e0")
        row("CONTROL: without the mode there is no warning",
            re.search(OK, out) is not None and re.search(r"(?i)also the name of a statement", out) is None,
            "a warning appeared, or no success wording")
        out = sess(box, "BASIC bp zza1e1")
        warns = re.findall(r"(?i)(\w+) is also the name of a statement or function", out)
        row("with the mode: warnings for CRT (EQUATE) and INDEX ($DEFINE), none for MYNAME or FINE.NAME",
            sorted(w.lower() for w in warns) == ["crt", "index"], "warned for: %r" % warns)
        row("and they are warnings, not errors (compiled with no errors)", re.search(OK, out) is not None, "no success wording")

        # --- leg 7: NO.QUERY on $CATALOGUE, in $BASIC.OPTIONS and on the BASIC command ----------------
        say("\n--- leg 7: NO.QUERY (refs 27, 191) --------------------------------------------")
        cat = os.path.join(sysd, "cat")

        def private_fixture(name, header):
            """A program with <header> as its first line, already in the PRIVATE catalogue."""
            prog(name, ["subroutine " + name, "   return", "end"])
            sess(box, "BASIC bp " + name, "CATALOG bp " + name)
            row("setup: %s is in the private catalogue" % name, os.path.exists(os.path.join(cat, name)),
                "no cat/%s" % name)
            prog(name, ([header] if header else []) + ["subroutine " + name, "   return", "end"])

        # control: with no NO.QUERY the compile asks, and answering N keeps the private entry
        private_fixture("zza1q0", "$catalogue local")
        out = sess(box, "BASIC bp zza1q0", "N")
        row("CONTROL: without NO.QUERY the compiler asks 'Remove (y/<n>)?'",
            re.search(r"(?i)also in private catalogue", out) is not None, "no prompt")
        row("CONTROL: and answering N left the private entry in place",
            os.path.exists(os.path.join(cat, "zza1q0")), "entry gone")

        # $CATALOGUE LOCAL NO.QUERY
        private_fixture("zza1q1", "$catalogue local no.query")
        out = sess(box, "BASIC bp zza1q1")
        row("$CATALOGUE LOCAL NO.QUERY: compiled with no errors and no prompt",
            re.search(OK, out) is not None and re.search(r"(?i)also in private catalogue", out) is None, "prompt or error")
        row("$CATALOGUE LOCAL NO.QUERY: the private entry was removed without asking",
            not os.path.exists(os.path.join(cat, "zza1q1")), "cat/zza1q1 still there")
        row("$CATALOGUE LOCAL NO.QUERY: and the program is in the local catalogue",
            re.search(r"(?i)zza1q1 added to local catalogue", out) is not None, "no 'added to local catalogue'")

        # $CATALOGUE NO.QUERY LOCAL (the other order, the first word a keyword)
        private_fixture("zza1q2", "$catalogue no.query local")
        out = sess(box, "BASIC bp zza1q2")
        row("$CATALOGUE NO.QUERY LOCAL: no prompt, private entry removed",
            re.search(r"(?i)also in private catalogue", out) is None and not os.path.exists(os.path.join(cat, "zza1q2")),
            "prompt, or entry still there")

        # the BASIC command's NO.QUERY
        private_fixture("zza1q3", "$catalogue local")
        out = sess(box, "BASIC bp zza1q3 NO.QUERY")
        row("BASIC ... NO.QUERY: no prompt, private entry removed",
            re.search(OK, out) is not None and re.search(r"(?i)also in private catalogue", out) is None
            and not os.path.exists(os.path.join(cat, "zza1q3")), "prompt, error, or entry still there")

        # $BASIC.OPTIONS: CATALOGUE LOCAL NO.QUERY
        private_fixture("zza1q4", "")
        write(opt, ["X", "CATALOGUE LOCAL NO.QUERY"])
        try:
            out = sess(box, "BASIC bp zza1q4")
        finally:
            os.remove(opt)
        row("$BASIC.OPTIONS CATALOGUE LOCAL NO.QUERY: no prompt, private entry removed, cataloguing local",
            re.search(r"(?i)also in private catalogue", out) is None and not os.path.exists(os.path.join(cat, "zza1q4"))
            and re.search(r"(?i)zza1q4 added to local catalogue", out) is not None, "prompt, entry present, or not local")
    finally:
        for n in made:
            for d in ("bp", "bp.out"):
                p = os.path.join(sysd, d, n)
                if os.path.exists(p):
                    os.remove(p)
        cmds = ["DELETE.CATALOG %s LOCAL" % n for n in
                ("zza1s0", "zza1s1", "zza1l2", "zza1o1", "zza1q0", "zza1q1", "zza1q2", "zza1q3", "zza1q4")]
        sess(box, *cmds)
        for n in ("zza1q0", "zza1q1", "zza1q2", "zza1q3", "zza1q4"):
            p = os.path.join(sysd, "cat", n)
            if os.path.exists(p):
                os.remove(p)

    say("\nsandbox-bcomp-a1: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
