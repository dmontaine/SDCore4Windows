#!/usr/bin/env python3
#
# sandbox-proc-a5.py - 1.2-0 bundle A-5 (openQM features after 2.6.6, process reporting): WHO USER,
#                      PSTAT USER <name>, and the !LISTU subroutine.  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-proc-a5.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be
# empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 10 Oct 26 dm  Written for 1.2-0 bundle A-5.
# END-HISTORY
#
# The sandbox's one session is the only process, played by whoever runs this script (getpass), so the
# login name in every expected value is that user's, taken at run time and not written here.
#
#   1  WHO and WHO USER (openQM ref 289)
#   2  PSTAT USER name (77)
#   3  !LISTU (12)
#   Not run: PSTAT's "held by user n (name)" (121) needs a second process waiting on a lock.

import getpass
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
passed = failed = 0
ME = getpass.getuser()


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
    say("sandbox-proc-a5: CANNOT RUN - " + msg)
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


def segments(out, cmds):
    segs, cur = {}, None
    for line in out.splitlines():
        r = line.rstrip()
        for i, c in enumerate(cmds):
            if r.startswith(":") and r.lstrip(":") == c.rstrip() and i not in segs:
                cur = i
                segs[i] = []
                break
        else:
            if cur is not None:
                segs[cur].append(line)
    return {i: "\n".join(v) for i, v in segs.items()}


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-proc-a5.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    bp = os.path.join(sysd, "bp")
    say("sandbox-proc-a5: sandbox %s, played by user %s" % (box, ME))
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-proc-a5: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    prog = os.path.join(bp, "zza5lu")
    try:
        with open(prog, "w") as f:
            f.write("   call !listu(d)\n   crt 'N[':dcount(d,@fm):']'\n   crt 'U[':d<1,1>:'][':d<1,6>:']'\n"
                    "   crt 'P[':(d<1,2> + 0 > 0):']'\n   crt 'T[':(d<1,8> + 0 > 1700000000):']'\nend\n")

        say("\n--- leg 1: WHO USER (ref 289) --------------------------------------------------")
        c = ["WHO", "WHO USER"]
        sg = segments(sess(box, *c), c)
        a = [l.strip() for l in sg.get(0, "").splitlines() if re.match(r"^\s*\d+ \S+", l)]
        b = [l.strip() for l in sg.get(1, "").splitlines() if re.match(r"^\s*\d+ \S+", l)]
        row("CONTROL: WHO shows the user number and the account, and not the login name",
            len(a) == 1 and ME not in a[0].split(), "got %r" % a)
        row("THE ROW: WHO USER shows the login name after them: ends with %s" % ME,
            len(b) == 1 and b[0].split()[-1] == ME and b[0].startswith(a[0]) if a and b else False, "got %r" % b)

        say("\n--- leg 2: PSTAT USER name (ref 77) --------------------------------------------")
        c = ["PSTAT USER zzznosuchuser", "PSTAT USER " + ME]
        sg = segments(sess(box, *c), c)
        row("a name that no process has is refused: no process is running for user",
            re.search(r"(?i)no process is running for user zzznosuchuser", sg.get(0, "")) is not None, "no refusal")
        row("a name that a process has is reported: its Account and Command lines are shown",
            re.search(r"Account:", sg.get(1, "")) is not None and re.search(r"Command: PSTAT USER " + re.escape(ME), sg.get(1, "")) is not None,
            "no report")

        say("\n--- leg 3: !LISTU (ref 12) -----------------------------------------------------")
        out = sess(box, "BASIC bp zza5lu", "RUN bp zza5lu")
        row("setup: the probe compiled with no errors", re.search(r"(?m)^Compiled 1 program\(s\) with no errors", out) is not None,
            "no success wording")
        row("one user (this session)", re.search(r"(?m)^N\[1\]\s*$", out) is not None, "no N[1]")
        row("value 1 is the user number and value 6 the login name %s" % ME,
            re.search(r"(?m)^U\[[1-9]\d*\]\[%s\]\s*$" % re.escape(ME), out) is not None, "no U[n][name]")
        row("the pid is positive and the login time is after 2023",
            re.search(r"(?m)^P\[1\]\s*$", out) is not None and re.search(r"(?m)^T\[1\]\s*$", out) is not None, "P/T not 1")
    finally:
        if os.path.exists(prog):
            os.remove(prog)
        for d in ("bp.out",):
            p = os.path.join(sysd, d, "zza5lu")
            if os.path.exists(p):
                os.remove(p)

    say("\nsandbox-proc-a5: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
