#!/usr/bin/env python3
#
# sandbox-inputraw.py - 1.2-0 bundle B-5, sheet 548: INPUT var, length RAW reads exactly `length` characters with no special
#                       interpretation of newline or the erase key; the length is required.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-inputraw.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 548.
# END-HISTORY
#
# THE INSTRUMENT.  A session piped to `sd -internal` (as sandbox-input.py), where the bytes after the RUN line are the keys.  The
# probe prints what it got with the control characters spelled out (<BS> <LF> <CR>), so that what the INPUT did with a newline and
# a backspace can be read off.  Controls: the same bytes into a plain INPUT (which ends at the newline and erases on the backspace).

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
    say("sandbox-inputraw: CANNOT RUN - " + msg)
    sys.exit(2)


def session(box, body_after_tern):
    """body_after_tern is the text sent after the TERM line, exactly as given (it holds the keys of the probe)."""
    say("    > [sd -internal] " + repr(body_after_tern)[:120])
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + body_after_tern + "OFF\n"
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body,
                       cwd=os.path.join(box, "sys"), env=env, capture_output=True, text=True, errors="replace", timeout=180)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


def tag(out, name):
    m = re.search(r"(?m)^\??%s\[(.*)\]\s*$" % name, out)
    return None if m is None else m.group(1)


SPELL = "change(change(change(%s, char(8), '<BS>'), char(10), '<LF>'), char(13), '<CR>')"

PROGS = {
    "zzraw": ("   input a, 6 raw\n   crt 'R[':" + SPELL % "a" + ":']'\n   crt 'END'\nend\n"),
    "zzrawd": ("   data 'queued'\n   input a, 6 raw\n   crt 'D[':a:']'\n   crt 'END'\nend\n"),
    "zzrawc": ("   input a, 6\n   crt 'C[':" + SPELL % "a" + ":']'\n   crt 'END'\nend\n"),
    "zzrawu": ("   input a, 3 raw upcase\n   crt 'U[':a:']'\n   crt 'END'\nend\n"),
    "zzrawbad": "   input a raw\nend\n",
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-inputraw.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-inputraw: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-inputraw: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        for nm, text in PROGS.items():
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write(text)
            made.append(nm)
        good = [n for n in PROGS if n != "zzrawbad"]
        out = session(box, "BASIC bp " + " ".join(good) + "\n")
        row("setup: the probes compile with no errors", re.search(r"(?m)^Compiled %d program\(s\) with no errors" % len(good), out) is not None, out[-500:])
        out = session(box, "BASIC bp zzrawbad\n")
        row("548: INPUT ... RAW without a length is a compile error (INPUT with RAW needs a length)",
            re.search(r"INPUT with RAW needs a length", out) is not None and "Compiled 1 program(s) with no errors" not in out, out[-400:])

        out = session(box, "RUN bp zzraw\nab\x08c\nd\n")
        row("548: RAW takes exactly 6 characters, the backspace and the newline among them (SD's input layer delivers a typed newline as a CR)",
            tag(out, "R") == "ab<BS>c<CR>d", repr(tag(out, "R")))
        out = session(box, "RUN bp zzrawc\nab\x08c\nd\n")
        row("CONTROL: a plain INPUT of the same bytes ends at the newline and erases (a c, the backspace taken out)",
            tag(out, "C") == "ac", repr(tag(out, "C")))
        out = session(box, "RUN bp zzrawd\n")
        row("548: a DATA queue item is taken whole, as for any INPUT", tag(out, "D") == "queued", repr(tag(out, "D")))
        out = session(box, "RUN bp zzrawu\nabcdef\n")
        row("548: RAW stops at its length (3) and UPCASE still applies", tag(out, "U") == "ABC", repr(tag(out, "U")))
    finally:
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-inputraw: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
