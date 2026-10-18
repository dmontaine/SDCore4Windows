#!/usr/bin/env python3
#
# sandbox-conv-b3.py - 1.2-0 bundle B-3 (openQM features after 2.6.6, conversion codes in the kernel):
#                      MCN- and MC/N-, MCS, MCP with a replacement character, and MT with M.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-conv-b3.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (its sd binary is the one `make` last built, so a C change
# needs a make first).  With --build it is built first from THIS tree (it must be empty or absent).
# Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 11 Oct 26 dm  Written for 1.2-0 bundle B-3.
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE oconv() GAVE, printed between brackets by a BASIC program, beside the plain
# conversion on the same data as the CONTROL, so a row cannot pass because the program printed nothing.
#
#   MCN-, MC/N-  (openQM ref 298)    MCS  (183)    MCP*, MCP'*'  (488)    MT with M  (198)

import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0

# (label, BASIC expression, wanted output between the brackets)
CASES = [
    ("CONTROL: MCN keeps only digits", "oconv('-12ab3', 'MCN')", "123"),
    ("THE ROW: MCN- keeps a leading minus too", "oconv('-12ab3', 'MCN-')", "-123"),
    ("MCN- keeps only a LEADING minus", "oconv('1-2ab3', 'MCN-')", "123"),
    ("CONTROL: MC/N deletes the digits", "oconv('-12ab3', 'MC/N')", "-ab"),
    ("THE ROW: MC/N- deletes a leading minus with them", "oconv('-12ab3', 'MC/N-')", "ab"),
    ("CONTROL: MCP shows a non-printing character as a dot", "oconv('a':char(1):'b', 'MCP')", "a.b"),
    ("THE ROW: MCP* shows it as *", "oconv('a':char(1):'b', 'MCP*')", "a*b"),
    ("THE ROW: MCP'?' takes the character from the quotes", "oconv('a':char(1):'b', \"MCP'?'\")", "a?b"),
    ("THE ROW: MCP\"#\" likewise with double quotes", "oconv('a':char(1):'b', 'MCP\"#\"')", "a#b"),
    ("CONTROL: MCT capitalises every word", "oconv('hello world. this is it', 'MCT')", "Hello World. This Is It"),
    ("THE ROW: MCS capitalises each sentence only",
     "oconv('hello world. this is it! ok? yes', 'MCS')", "Hello world. This is it! Ok? Yes"),
    ("MCS: the first LETTER of a sentence, so a leading number does not end one", "oconv('3.5 apples. then pears', 'MCS')",
     "3.5 Apples. Then pears"),
    ("CONTROL: MTS of 45296 seconds", "oconv(45296, 'MTS')", "12:34:56"),
    ("THE ROW: MTSM of the same time in milliseconds", "oconv(45296789, 'MTSM')", "12:34:56"),
    ("THE ROW: and MTMS, the options in the other order", "oconv(45296789, 'MTMS')", "12:34:56"),
    ("MTHSM: twelve hour clock with milliseconds", "oconv(45296789, 'MTHSM')", "12:34:56pm"),
    ("CONTROL: TRIM removes spaces but not tabs", "trim(char(9):'  a':char(9):'  b  ')", "\t a\t b"),
    ("THE ROW (ref 302): TRIMW removes every white space character at the ends and collapses runs",
     "trimw(char(9):'  a':char(9):char(9):'b  ':char(10))", "a b"),
    ("TRIMW of a string with no white space is itself", "trimw('abc')", "abc"),
    ("TRIMW of nothing but white space is the null string", "trimw(char(9):' ':char(10))", ""),
    ("CONTROL: MD2ZT, in the old order, shows a zero as nothing", "oconv(0, 'MD2ZT')", ""),
    ("THE ROW: MD2TZ, the options the other way round, does too", "oconv(0, 'MD2TZ')", ""),
    ("CONTROL: MD2CZ puts cr after a negative value (-567 is -5.67 with two places)", "oconv(-567, 'MD2CZ')", "5.67cr"),
    ("THE ROW: MD2ZC, Z before the sign option, gives the same", "oconv(-567, 'MD2ZC')", "5.67cr"),
    ("THE ROW: and the same with T between: MD2TZC truncates -5.678 to -5.67", "oconv(-567.8, 'MD2TZC')", "5.67cr"),
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
    say("sandbox-conv-b3: CANNOT RUN - " + msg)
    sys.exit(2)


def sess(box, *cmds):
    say("    > " + " | ".join(cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, timeout=600)
    out = ANSI.sub("", p.stdout + p.stderr)
    out = out.split(":TERM 200,9999", 1)[-1]
    return out


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-conv-b3.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-conv-b3: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-conv-b3: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    prog = os.path.join(bp, "zzb3cv")
    try:
        lines = []
        for i, (_, expr, _w) in enumerate(CASES):
            lines.append("   x = %s" % expr)
            lines.append("   crt 'C%02d[':x:']'" % i)
        lines.append("end")
        with open(prog, "w") as f:
            f.write("\n".join(lines) + "\n")
        out = sess(box, "BASIC bp zzb3cv", "RUN bp zzb3cv")
        say("\n--- the conversions -----------------------------------------------------------")
        row("setup: the probe compiled with no errors", re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None,
            "no success wording")
        for i, (label, expr, want) in enumerate(CASES):
            m = re.search(r"(?m)^C%02d\[(.*)\]\s*$" % i, out)
            got = m.group(1) if m else None
            row("%s: %s gives %r" % (label, expr, want), got == want, "got %r" % got)
    finally:
        for d in ("bp", "bp.out"):
            p = os.path.join(sysd, d, "zzb3cv")
            if os.path.exists(p):
                os.remove(p)

    say("\nsandbox-conv-b3: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
