#!/usr/bin/env python3
#
# sandbox-opensock.py - 1.2-0 bundle B-4, sheet 174: OPEN.SOCKET(addr, port, flags, timeout) gives up after `timeout` seconds.  No install,
#                       no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-opensock.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for sheet 174.
# END-HISTORY
#
# THE INSTRUMENT.  A connection that hangs needs no network: a listening socket with a backlog of 0 whose accept queue is full drops
# further SYNs, so a connect to it neither succeeds nor is refused.  The harness proves that precondition first (its own connect with a
# one second limit must time out) and stops with exit 2 if the machine does not behave so.  The elapsed time of each SD run is measured
# from outside, around the whole session, and judged against a start-up time taken from a control run that connects at once.

import os
import re
import socket
import subprocess
import sys
import time

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
    say("sandbox-opensock: CANNOT RUN - " + msg)
    sys.exit(2)


def session(box, *cmds):
    say("    > " + " | ".join(cmds))
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    t0 = time.time()
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-internal"], input=body, cwd=os.path.join(box, "sys"), env=env,
                       capture_output=True, text=True, errors="replace", timeout=180)
    return ANSI.sub("", p.stdout + p.stderr), time.time() - t0


def tag(out, name):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % name, out)
    return None if m is None else m.group(1)


def listener(backlog):
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    s.listen(backlog)
    return s, s.getsockname()[1]


def fill_queue(port, keep):
    """Connect until a further connect no longer completes: the accept queue is full."""
    for _ in range(6):
        c = socket.socket()
        c.setblocking(False)
        try:
            c.connect(("127.0.0.1", port))
        except BlockingIOError:
            pass
        keep.append(c)
        time.sleep(0.1)


def prog(port, timeout_arg):
    t = "" if timeout_arg is None else ", %s" % timeout_arg
    return ("   sk = open.socket('127.0.0.1', %d, 0%s)\n   crt 'ST[':status():']'\n"
            "   if status() = 0 then close.socket sk\n   crt 'END'\nend\n" % (port, t))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-opensock.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-opensock: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = subprocess.run([sys.executable, TOOL, box, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-opensock: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    subprocess.run([sys.executable, TOOL, box, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    keep = []
    srv_full, port_full = listener(0)
    srv_free, port_free = listener(16)
    tmp, port_closed = listener(1)
    tmp.close()
    fill_queue(port_full, keep)
    probe = socket.socket()
    probe.settimeout(1)
    try:
        probe.connect(("127.0.0.1", port_full))
        bail("a connect to the full listener completed: this machine does not hang a connect that way, so the test cannot show a timeout")
    except socket.timeout:
        say("  harness: a connect to the full listener hangs, as the test needs")
    except OSError as e:
        bail("a connect to the full listener failed at once (%s), so the test cannot show a timeout" % e)
    probe.close()

    made = []
    try:
        cases = (("zzosfull2", port_full, 2), ("zzosfull1", port_full, 1), ("zzosfree", port_free, 3), ("zzosfree0", port_free, None),
                 ("zzosclosed", port_closed, 3), ("zzosneg", port_free, -5))
        for nm, port, to in cases:
            with open(os.path.join(sysd, "bp", nm), "w") as fh:
                fh.write(prog(port, to))
            made.append(nm)
        out, _ = session(box, "BASIC bp " + " ".join(n for n, _, _ in cases))
        row("setup: the probes compile with no errors", "Compiled %d program(s) with no errors" % len(cases) in out, out[-600:])

        out, base = session(box, "RUN bp zzosfree")
        row("the run reached its end", re.search(r"(?m)^END\s*$", out) is not None, out[-500:])
        row("CONTROL: with a timeout, a listening port connects (status 0)", tag(out, "ST") == "0", repr(tag(out, "ST")))
        out, _ = session(box, "RUN bp zzosfree0")
        row("CONTROL: with no timeout argument it connects as it always did", tag(out, "ST") == "0", repr(tag(out, "ST")))
        out, _ = session(box, "RUN bp zzosneg")
        row("CONTROL: a negative timeout is the same as none", tag(out, "ST") == "0", repr(tag(out, "ST")))
        out, el = session(box, "RUN bp zzosclosed")
        row("a closed port is refused at once, well before the timeout (7005)", tag(out, "ST") == "7005" and el < base + 1.5,
            "%r in %.1f s (a connect took %.1f s)" % (tag(out, "ST"), el, base))
        out, el = session(box, "RUN bp zzosfull2")
        row("174: a connection that hangs fails with 7005", tag(out, "ST") == "7005", repr(tag(out, "ST")))
        row("174: ... after about the 2 seconds asked for", base + 1.6 <= el <= base + 4.5, "%.1f s (a plain run takes %.1f s)" % (el, base))
        out, el = session(box, "RUN bp zzosfull1")
        row("174: a 1 second timeout gives up after about 1 second", tag(out, "ST") == "7005" and base + 0.7 <= el <= base + 3.0,
            "%r in %.1f s" % (tag(out, "ST"), el))
    finally:
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)
        for c in keep:
            c.close()
        srv_full.close()
        srv_free.close()

    say("\nsandbox-opensock: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
