#!/usr/bin/env python3
#
# sandbox-lock-b6.py - 1.2-0 bundle B-6 (openQM diagnostics): the time a lock was acquired (487), DEADLOCK=2 (500),
#                      SYSTEM(1083) (587), a process blocked on a full lock table that must still log out (344) and the
#                      persistent data of an object variable in a process dump (125).  No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-lock-b6.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 12 Oct 26 dm  Written for 1.2-0 bundle B-6, second part: sheet 125, 344, 487, 500 and 587.
# END-HISTORY
#
# THE INSTRUMENT.  Locks are held by LIVE sessions - bin/sd started with a pipe whose write end this script keeps
# open, so a program that is waiting for a lock is still waiting when another session looks at it (a pipe that is
# closed ends the session).  What a session printed is read from its output file, and every pattern is anchored to
# the start of a line, because a session echoes the command it was given.  A deadlock is two such sessions, each
# holding one record and asking for the other's.
#
# THE TIME ZONE IS Asia/Kathmandu, +05:45, set for this script and so for everything it starts: a time shown in UTC
# or in a whole-hour zone would be wrong by a visible amount, and a row proves the zone took (SYSTEM(1019) = 20700).
# A time is judged against this script's own clock in that zone, within two minutes.
#
# WHAT THIS CANNOT SAY.  GETLOCKS() is an internal function; its seventh value is seen through LIST.READU, which is
# what reads it.  The DEADLOCK=2 file is checked for its layout and contents, not for how a person would use it.

import datetime
import getpass
import os
import re
import subprocess
import sys
import time

os.environ["TZ"] = "Asia/Kathmandu"
time.tzset()

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
MARK = "# --- sandbox-lock-b6 below ---"
USER = getpass.getuser()
passed = failed = 0
made = []
lives = []

PROGS = {
    "zzb6cfg": "   crt 'DL[':config('DEADLOCK'):']'\n   crt 'ZONE[':system(1019):']'\nend\n",
    # A holds a and, three seconds later, wants b; B holds b and, five seconds later, wants a.
    "zzb6a": ("   execute 'DELETE.FILE zzb6dl' capturing j\n   execute 'CREATE.FILE zzb6dl' capturing j\n"
              "   open 'zzb6dl' to f else stop 'no f'\n   crt 'DLA[':@userno:']'\n"
              "   readu r from f, 'a' else null\n   sleep 3\n   readu r from f, 'b' else null\n   crt 'DLA DONE'\nend\n"),
    "zzb6b": ("   open 'zzb6dl' to f else stop 'no f'\n   crt 'DLB[':@userno:']'\n"
              "   readu r from f, 'b' else null\n   sleep 5\n   readu r from f, 'a' else null\n   crt 'DLB NOT EXPECTED'\nend\n"),
    "zzb6q": "   crt 'DLQ[':change(change(system(1083), @fm, '/'), @vm, '|'):']'\nend\n",
    "zzb6lk": ("   execute 'DELETE.FILE zzb6lk' capturing j\n   execute 'CREATE.FILE zzb6lk' capturing j\n"
               "   execute 'DELETE.FILE zzb6lk2' capturing j\n   execute 'CREATE.FILE zzb6lk2' capturing j\n"
               "   open 'zzb6lk' to f else stop 'no f'\n   open 'zzb6lk2' to g else stop 'no g'\n"
               "   readu r from f, 'k1' else null\n   readl r from f, 'k2' else null\n   filelock g\n"
               "   execute 'LIST.READU NO.PAGE' capturing out\n"
               "   for i = 1 to dcount(out, @fm)\n      crt 'LN:':out<i>\n   next i\n"
               "   execute 'LIST.READU DETAIL NO.PAGE' capturing out\n"
               "   for i = 1 to dcount(out, @fm)\n      crt 'LR:':out<i>\n   next i\n"
               "   crt 'LRDONE'\nend\n"),
    "zzb6wh": ("   execute 'DELETE.FILE zzb6wf' capturing j\n   execute 'CREATE.FILE zzb6wf' capturing j\n"
               "   open 'zzb6wf' to f else stop 'no f'\n   readu r from f, 'w1' else null\n   crt 'WH[':@userno:']'\n"
               "   sleep 10\n   crt 'WH DONE'\nend\n"),
    "zzb6ww": ("   open 'zzb6wf' to f else stop 'no f'\n   crt 'WW[':@userno:']'\n"
               "   readu r from f, 'w1' else null\n   crt 'WW DONE'\nend\n"),
    "zzb6obs": ("   execute 'LIST.READU WAIT DETAIL NO.PAGE' capturing out\n"
                "   for i = 1 to dcount(out, @fm)\n      crt 'WT:':out<i>\n   next i\n   crt 'WTDONE'\nend\n"),
    # 125: a class module with public and private variables, and a program that holds an object of it and dumps itself
    "zzb6cls": ("class zzb6cls\npublic pubvar\nprivate privvar, counter\npublic subroutine create.object\n"
                "   pubvar = 'hello-public'\n   privvar = 'hello-private'\n   counter = 42\nend\n"
                "public function bump\n   counter += 1\n   return counter\nend\nend\n"),
    "zzb6obj": ("   obj = object('zzb6cls')\n   x = obj->bump()\n   crt 'OBJ[':@userno:'][':x:']'\n   pdump\n"
                "   crt 'OBJDONE'\nend\n"),
    "zzb6full": ("   execute 'DELETE.FILE zzb6fl' capturing j\n   execute 'CREATE.FILE zzb6fl' capturing j\n"
                 "   open 'zzb6fl' to f else stop 'no f'\n   crt 'FULL[':@userno:']'\n"
                 "   for i = 1 to 20\n      crt 'LOCKING ':i\n      readu r from f, 'k':i else null\n   next i\n"
                 "   crt 'FULL DONE'\nend\n"),
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
    for lv in lives:
        lv.kill()
    say("sandbox-lock-b6: CANNOT RUN - " + msg)
    sys.exit(2)


def tool(box, *args, **kw):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace",
                          timeout=kw.pop("timeout", 900), **kw)


def sess(box, *cmds):
    say("    > %s" % " | ".join(c if len(c) < 60 else c[:57] + "..." for c in cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900)
    return ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]


def status(box):
    env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
    p = subprocess.run([os.path.join(box, "sys", "bin", "sd"), "-status"], capture_output=True, text=True,
                       errors="replace", env=env, timeout=60)
    return p.stdout + p.stderr


def started(box):
    return re.search(r"(?m)^Started\s+20\d\d-", status(box)) is not None


def restart(box, *extra):
    """Stop the sandbox, put `extra` lines in sd.conf below the marker, start it, and say whether SD is running."""
    conf = os.path.join(box, "sd.conf")
    tool(box, "stop", timeout=120)
    with open(conf) as f:
        base = f.read().split(MARK)[0].rstrip("\n") + "\n"
    with open(conf, "w") as f:
        f.write(base + ((MARK + "\n" + "".join(l + "\n" for l in extra)) if extra else ""))
    tool(box, "start", timeout=180)
    ok = started(box)
    say("  -- sd.conf %s: SD %s" % (("+ " + " ".join(extra)) if extra else "as built", "started" if ok else "NOT STARTED"))
    return ok


class Live:
    """A session on a pipe kept open.  With hold=True it is not told to end, so what it is waiting for stays held."""

    def __init__(self, box, tag, cmds, hold=False):
        self.out = os.path.join(box, "live-%s.out" % tag)
        env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
        self.fh = open(self.out, "w")
        self.p = subprocess.Popen([os.path.join(box, "sys", "bin", "sd")], stdin=subprocess.PIPE, stdout=self.fh,
                                  stderr=subprocess.STDOUT, cwd=os.path.join(box, "user_accounts"), env=env, text=True)
        self.p.stdin.write("\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + ("" if hold else "OFF\n"))
        self.p.stdin.flush()
        say("    > live %s: %s" % (tag, " | ".join(cmds)))
        lives.append(self)

    def text(self):
        self.fh.flush()
        return ANSI.sub("", open(self.out, errors="replace").read())

    def wait(self, seconds):
        try:
            self.p.wait(timeout=seconds)
            return True
        except subprocess.TimeoutExpired:
            return False

    def kill(self):
        if self.p.poll() is None:
            self.p.kill()
            self.p.wait()
        try:
            self.fh.close()
        except OSError:
            pass


def tagged(out, tag):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % tag, out)
    return m.group(1) if m else None


def near_now(stamp, fmt, seconds=120):
    """True when the stamp, in this script's zone, is within `seconds` of the clock now."""
    try:
        t = datetime.datetime.strptime(stamp, fmt)
    except ValueError:
        return False
    return abs((datetime.datetime.now() - t).total_seconds()) <= seconds


def compile_all(box, sysd):
    cmds = []
    for nm, text in PROGS.items():
        with open(os.path.join(sysd, "bp", nm), "w") as f:
            f.write(text)
        made.append(nm)
        cmds.append("BASIC bp %s" % nm)
    out = sess(box, *cmds)
    n = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
    if n != len(PROGS):
        bail("%d of %d programs compiled:\n%s" % (n, len(PROGS), out[-1500:]))
    # the class is called by its catalogued name; an entry left by an earlier run is removed first
    out = sess(box, "DELETE.CATALOG zzb6cls", "CATALOG bp zzb6cls")
    if re.search(r"(?m)^zzb6cls added to private catalogue", out) is None:
        bail("the class module was not catalogued:\n" + out[-600:])


def deadlock_run(box, with_query=True):
    """A and B deadlock.  Returns (A's text, B's text)."""
    a = Live(box, "a", ["RUN bp zzb6a"])
    time.sleep(1)
    b = Live(box, "b", ["RUN bp zzb6b"] + (["RUN bp zzb6q"] if with_query else []))
    for lv in (a, b):
        if not lv.wait(40):
            lv.kill()
            say("    (a session had to be killed)")
    return a.text(), b.text()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-lock-b6.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    dumps = os.path.join(sysd, "dumps")
    say("sandbox-lock-b6: sandbox %s, TZ=%s" % (box, os.environ["TZ"]))
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-lock-b6: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)

    try:
        if not restart(box, "DEADLOCK=2", "NUMLOCKS=10"):
            bail("SD does not start with DEADLOCK=2 NUMLOCKS=10")
        compile_all(box, sysd)

        say("\n--- the parameter and the zone ---------------------------------------------------")
        out = sess(box, "RUN bp zzb6cfg")
        row("500: DEADLOCK=2 reads back as 2", tagged(out, "DL") == "2", "got %r" % tagged(out, "DL"))
        row("the zone took: SYSTEM(1019) is +05:45 in seconds", tagged(out, "ZONE") == "20700",
            "got %r" % tagged(out, "ZONE"))

        say("\n--- 487 when a lock was acquired, and when a wait began --------------------------")
        out = sess(box, "RUN bp zzb6lk")
        ln = re.findall(r"(?m)^LN:\s+Locked ", out)
        row("487: CONTROL: without DETAIL no 'Locked' line is shown", "LRDONE" in out and not ln,
            "%d lines" % len(ln))
        stamps = re.findall(r"(?m)^LR:\s+Locked (\d\d \w{3} \d\d \d\d:\d\d:\d\d)\s*$", out)
        row("487: DETAIL shows a 'Locked' line for each of the three locks (RU, RL, FX)", len(stamps) == 3,
            "%d lines" % len(stamps))
        row("487: ... each in this zone and within two minutes of now: %s" % stamps,
            len(stamps) == 3 and all(near_now(s, "%d %b %y %H:%M:%S") for s in stamps),
            "now is %s" % datetime.datetime.now().strftime("%d %b %y %H:%M:%S"))
        pairs, cur = [], None
        for l in (x[3:] for x in out.splitlines() if x.startswith("LR:")):
            if re.match(r"^\s*\d+\s+\d+ ", l):          # a lock line: user, file, path, then the type in column 43
                cur = l[42:46].strip()
            elif re.match(r"^\s+Locked ", l) and cur:   # its time follows the lock line and any wrapped path lines
                pairs.append(cur)
                cur = None
        row("487: ... one after each lock line: RU, RL and FX each have theirs %s" % pairs,
            sorted(pairs) == ["FX", "RL", "RU"], str(pairs))

        h = Live(box, "wh", ["RUN bp zzb6wh"])
        time.sleep(1.5)
        w = Live(box, "ww", ["RUN bp zzb6ww"])
        time.sleep(3)
        o = Live(box, "obs", ["RUN bp zzb6obs"])
        o.wait(30)
        ot = o.text()
        wait_stamps = re.findall(r"(?m)^WT:\s+Wait since (\d\d \w{3} \d\d \d\d:\d\d:\d\d)\s*$", ot)
        lock_stamps = re.findall(r"(?m)^WT:\s+Locked (\d\d \w{3} \d\d \d\d:\d\d:\d\d)\s*$", ot)
        say("    waiting since %s, holder locked %s" % (wait_stamps, lock_stamps))
        row("487: WAIT DETAIL shows 'Wait since' for the waiting process, within two minutes of now",
            len(wait_stamps) == 1 and near_now(wait_stamps[0], "%d %b %y %H:%M:%S"), ot[-300:])
        row("487: ... and 'Locked' for the process holding it", len(lock_stamps) == 1 and
            near_now(lock_stamps[0], "%d %b %y %H:%M:%S"), ot[-300:])
        row("487: the wait began after the lock was taken", len(wait_stamps) == 1 and len(lock_stamps) == 1 and
            datetime.datetime.strptime(wait_stamps[0], "%d %b %y %H:%M:%S") >=
            datetime.datetime.strptime(lock_stamps[0], "%d %b %y %H:%M:%S"))
        for lv in (h, w):
            lv.wait(30)

        say("\n--- 587 and 500: a deadlock, DEADLOCK=2 --------------------------------------------")
        out = sess(box, "RUN bp zzb6q")
        row("587: CONTROL: SYSTEM(1083) is null before any deadlock", tagged(out, "DLQ") == "", "got %r" % tagged(out, "DLQ"))
        for f in os.listdir(dumps):
            if f.startswith("deadlock."):
                os.remove(os.path.join(dumps, f))
        a_txt, b_txt = deadlock_run(box)
        ua, ub = tagged(a_txt, "DLA"), tagged(b_txt, "DLB")
        say("    A is user %s, B is user %s" % (ua, ub))
        row("the deadlock happened: B was aborted with 'Deadlock detected' and A got the lock it wanted",
            re.search(r"(?m)^[0-9A-F]{8}: Deadlock detected at line \d+ of ", b_txt) is not None and
            "DLA DONE" in a_txt and "DLB NOT EXPECTED" not in b_txt, (a_txt + b_txt)[-300:])
        q = tagged(b_txt, "DLQ")
        m = re.match(r"^(\d+)\|(.*/zzb6dl)\|(\w+)/(\d+)\|(.*/zzb6dl)\|(\w+)$", q or "")
        row("587: SYSTEM(1083) after the abort: a field for each process, user | file | id of the lock it waits for",
            bool(m) and m.group(1) == ub and m.group(4) == ua and m.group(2) == m.group(5) and
            m.group(3).upper() == "A" and m.group(6).upper() == "B", "got %r" % q)
        dfile = os.path.join(dumps, "deadlock.%s" % ub)
        row("500: DEADLOCK=2 left deadlock.%s in the dump directory" % ub, ub is not None and os.path.isfile(dfile),
            "listing: %s" % sorted(os.listdir(dumps))[:6])
        row("500: B was told where the state was saved",
            re.search(r"(?m)^The state of the locks was saved as .*deadlock\.%s\s*$" % re.escape(str(ub)), b_txt) is not None,
            b_txt[-300:])
        blocks = []
        if os.path.isfile(dfile):
            blocks = [b.split("\n") for b in open(dfile).read().strip().split("\n\n")]
            say("    deadlock.%s: %d lock(s)" % (ub, len(blocks)))
            for b in blocks:
                say("      " + " | ".join(b))
        row("500: the file holds the two record locks, four lines each", len(blocks) == 2 and all(len(b) == 4 for b in blocks),
            "%d blocks, line counts %s" % (len(blocks), [len(b) for b in blocks]))
        by_user = {b[0].split()[0]: b for b in blocks if len(b) == 4}
        row("500: line 1 is the user number and the user name", ua in by_user and ub in by_user and
            all(b[0] == "%s %s" % (u, USER) for u, b in by_user.items()), str(list(by_user)))
        row("500: line 2 is the file number and its pathname", all(re.match(r"^\d+ .*/zzb6dl$", b[1]) for b in blocks) and
            len(blocks) == 2)
        row("500: line 3 is the lock type and the record id: A holds 'a', B holds 'b'",
            ua in by_user and ub in by_user and by_user[ua][2].upper() == "RU A" and by_user[ub][2].upper() == "RU B",
            str({u: b[2] for u, b in by_user.items()}))
        row("500: line 4 is when it was acquired, in this zone and within two minutes of now",
            len(blocks) == 2 and all(near_now(b[3], "%Y-%m-%d %H:%M:%S", 180) for b in blocks),
            str([b[3] for b in blocks if len(b) == 4]))
        mode = os.stat(dfile).st_mode & 0o777 if os.path.isfile(dfile) else None
        row("500: the file is private to its owner (0600)", mode == 0o600, "mode %s" % (oct(mode) if mode else None))

        say("\n--- 344 a process blocked on a full lock table still logs out ---------------------")
        full = Live(box, "full", ["RUN bp zzb6full"], hold=True)
        time.sleep(5)
        ft = full.text()
        row("344: CONTROL: the holder took 10 locks and is blocked asking for the 11th",
            re.search(r"(?m)^LOCKING 11\s*$", ft) is not None and "FULL DONE" not in ft and full.p.poll() is None,
            ft[-200:])
        # With the table completely full no other session can run a command - each takes a lock for an instant, to
        # look the command up in the VOC - so the LOGOUT command cannot be given.  What an administrator has then is
        # the command line: sd -k n.  It needs no lock; the question is whether the blocked process answers it.
        who = tagged(ft, "FULL")
        say("    the holder is user %s; sd -k %s" % (who, who))
        k = None
        if who:
            k = subprocess.run([os.path.join(sysd, "bin", "sd"), "-k", who], capture_output=True, text=True,
                               errors="replace", timeout=60, env=dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf")))
            say("    sd -k said: %s" % (k.stdout + k.stderr).strip().replace("\n", " | ")[:200])
        gone = full.wait(15)
        row("344: after sd -k the process that filled the lock table ends within 15 seconds",
            bool(who) and k is not None and k.returncode == 0 and gone, "still running" if not gone else "")
        full.kill()

        say("\n--- 125 a process dump shows the persistent data of an object variable -------------")
        out = sess(box, "RUN bp zzb6obj")
        m = re.search(r"(?m)^OBJ\[(\d+)\]\[(\d+)\]\s*$", out)
        dtxt = ""
        if m and os.path.isfile(os.path.join(dumps, "sddump.%s" % m.group(1))):
            dtxt = open(os.path.join(dumps, "sddump.%s" % m.group(1)), errors="replace").read()
        row("125: CONTROL: the dump names the object variable and an ordinary one beside it",
            bool(m) and m.group(2) == "43" and re.search(r"(?m)^\s+OBJ: Object$", dtxt) is not None and
            re.search(r"(?m)^\s+X: Int: 43$", dtxt) is not None, (dtxt[-300:] if dtxt else out[-300:]))
        row("125: ... and under the object, its persistent variables by name: public, private and a counter bumped once",
            re.search(r'(?m)^(\s+)OBJ: Object\n\1  PUBVAR: String \(len=12\): "hello-public"\n'
                      r'\1  PRIVVAR: String \(len=13\): "hello-private"\n\1  COUNTER: Int: 43\n', dtxt) is not None,
            re.sub(r"(?s).*?(\s+OBJ: Object.{0,200}).*", r"\1", dtxt) if dtxt else out[-300:])

        say("\n--- 500 DEADLOCK=1 and what sd.conf refuses ------------------------------------------")
        if restart(box, "DEADLOCK=1", "NUMLOCKS=10"):
            for f in os.listdir(dumps):
                if f.startswith("deadlock."):
                    os.remove(os.path.join(dumps, f))
            a_txt, b_txt = deadlock_run(box, with_query=False)
            ub = tagged(b_txt, "DLB")
            row("500: CONTROL: with DEADLOCK=1 the deadlock is still trapped",
                re.search(r"(?m)^[0-9A-F]{8}: Deadlock detected at line ", b_txt) is not None and "DLA DONE" in a_txt,
                (a_txt + b_txt)[-300:])
            row("500: ... and no deadlock.n file is written", ub is not None and
                not any(f.startswith("deadlock.") for f in os.listdir(dumps)), str(sorted(os.listdir(dumps))[:6]))
            row("500: ... and no 'state of the locks' message", "The state of the locks" not in b_txt)
        else:
            row("500: DEADLOCK=1 starts SD", False, "did not start")
        up = restart(box, "DEADLOCK=3")
        log = ""
        try:
            log = open(os.path.join(box, "start.log")).read()
        except OSError:
            pass
        row("500: DEADLOCK=3 stops SD starting, and the log names the parameter",
            (not up) and "Invalid value for DEADLOCK configuration parameter" in log,
            "SD %s; log tail %r" % ("STARTED" if up else "did not start", log[-120:]))
        if restart(box):
            row("500: DEADLOCK defaults to 0", tagged(sess(box, "RUN bp zzb6cfg"), "DL") == "0")
        else:
            row("500: SD starts with the config as built", False, "did not start")
    finally:
        for lv in lives:
            lv.kill()
        tool(box, "stop", timeout=120)
        conf = os.path.join(box, "sd.conf")
        if os.path.exists(conf):
            with open(conf) as f:
                base = f.read().split(MARK)[0].rstrip("\n") + "\n"
            with open(conf, "w") as f:
                f.write(base)
        for nm in made:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-lock-b6: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
