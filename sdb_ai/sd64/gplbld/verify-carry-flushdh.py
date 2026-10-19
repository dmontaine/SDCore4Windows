#!/usr/bin/env python3
#
# sandbox-flushdh.py - 1.2-0 bundle B-5, sheet 83 and 123: FLUSH.DH.CACHE {LOCAL | NO.WAIT}.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-flushdh.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 83 and 123.
# END-HISTORY
#
# THE INSTRUMENT.  The statement has no effect a program can read, so the evidence is (1) that the three forms compile and run on, and
# (2) how long each takes beside another process: the default form asks every process to flush and waits for each to say it
# has (up to four seconds), NO.WAIT asks and goes on, LOCAL asks nobody.  The other process is a live session on a pipe
# kept open: one in a loop that looks at its events (it answers within a second), and one waiting at an INPUT (which does
# not look at its events until a key arrives, so it answers only when the four seconds are up).  Times are whole seconds read
# from the clock inside the program, so a difference of three seconds cannot be a rounding.

import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
lives = []


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
    say("sandbox-flushdh: CANNOT RUN - " + msg)
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


class Live:
    """A session on a pipe kept open (it is not told to end), to be another process for the statement to ask."""

    def __init__(self, box, cmds):
        env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
        self.p = subprocess.Popen([os.path.join(box, "sys", "bin", "sd")], stdin=subprocess.PIPE, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, cwd=os.path.join(box, "sys"), env=env, text=True)
        self.p.stdin.write("\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds))
        self.p.stdin.flush()
        say("    > live: %s" % " | ".join(cmds))
        lives.append(self)

    def kill(self):
        if self.p.poll() is None:
            self.p.kill()
            self.p.wait()


PROGS = {
    # the probe: each form, timed by the clock in whole seconds
    "zzfdh": ("   for k = 1 to 3\n"
              "      t0 = date() * 86400 + time()\n"
              "      begin case\n"
              "         case k = 1 ; flush.dh.cache\n"
              "         case k = 2 ; flush.dh.cache local\n"
              "         case k = 3 ; flush.dh.cache no.wait\n"
              "      end case\n"
              "      crt 'T':k:'[':(date() * 86400 + time() - t0):']'\n"
              "   next k\n"
              "   crt 'END'\nend\n"),
    # another process that looks at its events: it naps in a loop
    "zzfdhn": "   for i = 1 to 60\n      nap 200\n   next i\nend\n",
    # another process that waits at an INPUT
    "zzfdhi": "   input x\nend\n",
    "zzfdbad": "   flush.dh.cache both\nend\n",
}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-flushdh.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-flushdh: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-flushdh: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    made = []
    try:
        for nm, text in PROGS.items():
            with open(os.path.join(sysd, "bp", nm), "w") as f:
                f.write(text)
            made.append(nm)
        good = [n for n in PROGS if n != "zzfdbad"]
        out = sess(box, "BASIC bp " + " ".join(good))
        row("setup: the probes compile with no errors", has(out, r"^Compiled %d program\(s\) with no errors" % len(good)), "\n".join(out[-6:]))
        out = sess(box, "BASIC bp zzfdbad")
        row("a word after FLUSH.DH.CACHE other than LOCAL or NO.WAIT is not taken as part of the statement (a compile error)",
            not has(out, r"^Compiled 1 program\(s\) with no errors"), "\n".join(out[-4:]))

        say("\n--- alone: nobody to wait for ---")
        out = sess(box, "RUN bp zzfdh")
        row("83: the three forms run to the end", has(out, r"^END$"), "\n".join(out[-6:]))
        row("83: with no other process none of them waits (0 or 1 second)",
            all(tag(out, "T%d" % k) in ("0", "1") for k in (1, 2, 3)), "%r %r %r" % (tag(out, "T1"), tag(out, "T2"), tag(out, "T3")))

        say("\n--- beside a process that looks at its events ---")
        Live(box, ["RUN bp zzfdhn"])
        time.sleep(3)
        out = sess(box, "RUN bp zzfdh")
        row("83: the default form, with a process napping in a loop, is answered inside 3 seconds",
            tag(out, "T1") in ("0", "1", "2"), "T1 = %r" % tag(out, "T1"))
        row("123: LOCAL and NO.WAIT are at once", tag(out, "T2") in ("0", "1") and tag(out, "T3") in ("0", "1"),
            "%r %r" % (tag(out, "T2"), tag(out, "T3")))
        for lv in lives:
            lv.kill()
        del lives[:]

        say("\n--- beside a process waiting at an INPUT (it answers only when a key arrives) ---")
        Live(box, ["RUN bp zzfdhi"])
        time.sleep(3)
        out = sess(box, "RUN bp zzfdh")
        say("    T1 %r  T2 %r  T3 %r" % (tag(out, "T1"), tag(out, "T2"), tag(out, "T3")))
        row("83: the default form waits for it, and gives up after four seconds (3 to 6 on the clock)",
            tag(out, "T1") in ("3", "4", "5", "6"), "T1 = %r" % tag(out, "T1"))
        row("123: NO.WAIT does not wait (0 or 1)", tag(out, "T3") in ("0", "1"), "T3 = %r" % tag(out, "T3"))
        row("123: LOCAL does not wait (0 or 1)", tag(out, "T2") in ("0", "1"), "T2 = %r" % tag(out, "T2"))
    finally:
        for lv in lives:
            lv.kill()
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        subprocess.run([sys.executable, TOOL, box, "stop"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\nsandbox-flushdh: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
