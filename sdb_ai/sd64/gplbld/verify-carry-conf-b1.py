#!/usr/bin/env python3
#
# sandbox-conf-b1.py - 1.2-0 bundle B-1 (openQM configuration parameters and command line options).  No install,
#                      no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-conf-b1.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py (needs a `make`d bin/sd).  With --build it is built first from
# THIS tree (it must be empty or absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 12 Oct 26 dm  The rest of B-1: LGNWAIT (46), DHCACHE (90), PWDELAY (106), MAXRLOCK (313), USERPOOL (551), the
#               startup process's @TTY (91) and the call-name limit (241).  Rows that need a parameter in sd.conf
#               stop the sandbox, rewrite the config below a marker line, start it again and say whether SD started.
# 11 Oct 26 dm  Written for 1.2-0 bundle B-1: the INTPREC default 11 (6), SORTMEM default 4096 kb (535), the new
#               INVCASE parameter (399) and `sd -status` (511).
# END-HISTORY
#
# THE INSTRUMENT IS THE VALUE A BASIC PROGRAM PRINTED between brackets (CONFIG() reads), and, for -status, the
# sandbox's own bin/sd run against the sandbox's own shared memory (SD_CONFIG points at its config).  A CONTROL on
# each: FSYNC, a parameter that already existed, must read back its default (0); MAXRLOCK 0 grants every lock; the
# default USERPOOL rotates user numbers; LGNWAIT 0 refuses at once; DHCACHE 10 keeps both files.  EVERY RESTART
# SAYS WHETHER SD STARTED: a row after a restart that did not start is a FAIL, not a pass over nothing.
#
# WHAT THIS CANNOT SAY.  PWDELAY's effect (the delay after a refused network login) needs an API client and is
# witness-release-run.sh A3d's job; here it is read and set back.  STARTUP running as the sdsys OS user needs that
# user: a sandbox run by an ordinary user is refused by `sd -asdsys`, so @TTY is tested by giving a session the
# variable the way sysseg.c does, and sysseg.c's half by the environment of the exec (strace; skipped if absent).

import os
import re
import shutil
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
MARK = "# --- sandbox-conf-b1 below ---"
passed = failed = 0
made = []   # programs written into the sandbox's bp, removed at the end

CASES = [
    ("CONTROL: FSYNC, an existing parameter, reads its default", "x = config('FSYNC')", "0"),
    ("6: INTPREC defaults to 11", "x = config('INTPREC')", "11"),
    ("535: SORTMEM defaults to 4096 (kb)", "x = config('SORTMEM')", "4096"),
    ("399: INVCASE exists and defaults to 0", "x = config('INVCASE')", "0"),
    ("46: LGNWAIT defaults to 0 (no wait)", "x = config('LGNWAIT')", "0"),
    ("90: DHCACHE defaults to 10, the number that was fixed before", "x = config('DHCACHE')", "10"),
    ("106: PWDELAY defaults to 3 seconds", "x = config('PWDELAY')", "3"),
    ("313: MAXRLOCK defaults to 0 (no limit)", "x = config('MAXRLOCK')", "0"),
    ("551: USERPOOL defaults to 1023, the number that was fixed before", "x = config('USERPOOL')", "1023"),
    ("551: SYSTEM(1053), the highest user number, is that 1023 (NUMUSERS here is 20)", "x = system(1053)", "1023"),
    ("106: PWDELAY is set and read back in a session, and a value out of range is refused and changes nothing",
     "execute 'CONFIG PWDELAY 7' capturing j\nx = config('PWDELAY')\nexecute 'CONFIG PWDELAY 4000' capturing j\n"
     "x = x:'/':config('PWDELAY'):'/':(index(j, 'Invalid value', 1) > 0)", "7/7/1"),
]

# ---- 313 MAXRLOCK: locks of one process, every way a lock is taken.  A lock the process holds already is not
# counted again, an unlock gives the place back, and with no ON ERROR the process stops with message 11162.
MAXRLOCK_PROG = """\
   execute 'DELETE.FILE zzb1l' capturing j
   execute 'CREATE.FILE zzb1l' capturing j
   execute 'DELETE.FILE zzb1ld' capturing j
   execute 'CREATE.FILE zzb1ld DIRECTORY' capturing j
   open 'zzb1l' to f else stop 'no f'
   open 'zzb1ld' to d else stop 'no d'
   execute 'CONFIG MAXRLOCK 0' capturing j
   err = 0
   for i = 1 to 6
      readu r from f, 'c':i on error err = status() else null
   next i
   release
   crt 'ML0[':err:']'
   execute 'CONFIG MAXRLOCK 3' capturing j
   crt 'MLCFG[':config('MAXRLOCK'):']'
   for i = 1 to 3
      readu r from f, 'k':i else null
   next i
   err = 0
   readu r from f, 'k4' on error err = status() else null
   crt 'MLREADU[':err:']'
   err = 0
   readu r from f, 'k1' on error err = status() else null
   crt 'MLOWN[':err:']'
   err = 0
   release f, 'k1'
   readu r from f, 'k4' on error err = status() else null
   crt 'MLAFTER[':err:']'
   release f, 'k4'
   err = 0
   readl r from f, 'k6' on error err = status() else null
   readl r from f, 'k7' on error err = status() else null
   crt 'MLREADL[':err:']'
   err = 0
   readvu v from f, 'k8', 1 on error err = status() else null
   crt 'MLREADVU[':err:']'
   err = 0
   recordlocku f, 'k9' on error err = status()
   crt 'MLRLU[':err:']'
   err = 0
   openseq 'zzb1ld', 'rec' to s on error err = status() else null
   crt 'MLOPENSEQ[':err:']'
   release
   err = 0
   for i = 1 to 3
      readu r from f, 'again':i on error err = err + status() else null
   next i
   crt 'MLREL[':err:']'
   execute 'CONFIG MAXRLOCK 200000' capturing j
   crt 'MLRANGE[':config('MAXRLOCK'):'/':(index(j, 'Invalid value', 1) > 0):']'
   release
   readu r from f, 'last1' else null
   readu r from f, 'last2' else null
   readu r from f, 'last3' else null
   readu r from f, 'last4' else null
   crt 'MLNOTREACHED'
end
"""

# ---- 90 DHCACHE: how many closed files are kept.  The programs create their files first (EXECUTE flushes the
# cache, so the parameter is set after it and before the opens).
DHCACHE_PROG = """\
   execute 'DELETE.FILE zzb1c1' capturing j
   execute 'CREATE.FILE zzb1c1' capturing j
   execute 'DELETE.FILE zzb1c2' capturing j
   execute 'CREATE.FILE zzb1c2' capturing j
   execute 'CONFIG DHCACHE %d' capturing j
   open 'zzb1c1' to f else stop 'no f'
   close f
   open 'zzb1c2' to g else stop 'no g'
   close g
   crt 'DC%d[':config('DHCACHE'):'/':(index(system(1003), 'zzb1c1', 1) > 0):(index(system(1003), 'zzb1c2', 1) > 0):']'
end
"""
DHRANGE_PROG = """\
   execute 'CONFIG DHCACHE 5000' capturing j
   crt 'DCBIG[':config('DHCACHE'):'/':(index(j, 'Invalid value', 1) > 0):']'
   execute 'CONFIG DHCACHE -1' capturing j
   crt 'DCNEG[':config('DHCACHE'):'/':(index(j, 'Invalid value', 1) > 0):']'
end
"""

USER_PROG = "   crt 'UN[':@userno:'][':system(1053):'][':config('USERPOOL'):']'\nend\n"
HOLD_PROG = "   crt 'HOLD[':@userno:']'\n   sleep 5\n   crt 'HOLD DONE'\nend\n"
LGN_PROG = ("   crt 'LW[':@userno:'][':system(1036):'][':change(system(1055), @fm, '/'):'][':config('LGNWAIT'):']'\nend\n")
TTY_PROG = ("   crt 'TTY[':@tty:']'\n   os.execute 'echo \"ENV[${SD_STARTUP:-none}]\"' capturing out\n"
            "   crt out\nend\n")
CALL_PROG = ("   x = 0\n   call %s(x)\n   crt 'CALL[':x:']'\nend\n")
NAMECALL_PROG = ("   nm = '%s'\n   x = 0\n   call @nm(x)\n   crt 'NEVER'\nend\n")
STARTUP_PROG = "   crt 'startup ran'\nend\n"


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
    say("sandbox-conf-b1: CANNOT RUN - " + msg)
    sys.exit(2)


def put(sysd, name, text):
    with open(os.path.join(sysd, "bp", name), "w") as f:
        f.write(text)
    made.append(name)


def tool(box, *args, **kw):
    return subprocess.run([sys.executable, TOOL, box] + list(args), capture_output=True, text=True, errors="replace",
                          timeout=kw.pop("timeout", 900), **kw)


def sess(box, *cmds, env=None):
    say("    > %s" % " | ".join(c if len(c) < 60 else c[:57] + "..." for c in cmds))
    p = subprocess.run([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts")] + list(cmds),
                       capture_output=True, text=True, errors="replace", timeout=900, env=env)
    out = ANSI.sub("", p.stdout + p.stderr)
    return out.split(":TERM 200,9999", 1)[-1]


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


def tagged(out, tag):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % tag, out)
    return m.group(1) if m else None


def compile_all(box, sysd, progs):
    """Write the programs, compile them in one session and refuse to go on if any did not compile."""
    cmds = []
    for nm, text in progs:
        put(sysd, nm, text)
        cmds.append("BASIC bp %s" % nm)
    out = sess(box, *cmds)
    n = len(re.findall(r"(?m)^Compiled 1 program\(s\) with no errors", out))
    if n != len(progs):
        bail("%d of %d programs compiled:\n%s" % (n, len(progs), out[-1500:]))


def holders(box, n, prog="zzb1hold"):
    ps = [subprocess.Popen([sys.executable, TOOL, box, "sess", os.path.join(box, "user_accounts"), "RUN bp " + prog],
                           stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, errors="replace")
          for _ in range(n)]
    time.sleep(2.5)     # each logs in, prints HOLD[n] and sleeps 5 seconds
    return ps


def finish(ps):
    return [ANSI.sub("", p.communicate(timeout=60)[0]) for p in ps]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-conf-b1.py <dir> [--build]")
    box = os.path.abspath(args[0])
    sysd = os.path.join(box, "sys")
    say("sandbox-conf-b1: sandbox %s" % box)
    if "--build" in sys.argv:
        if os.path.exists(box) and os.listdir(box):
            bail("%s is not empty" % box)
        r = tool(box, "all")
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-conf-b1: built, bootstrap passed")
    elif not os.path.isfile(os.path.join(sysd, "bin", "sd")):
        bail("%s holds no built sandbox (use --build, or point it at one)" % box)
    if not restart(box):
        bail("SD does not start with the sandbox's own sd.conf")

    try:
        progs = []
        for i, (_, body, _w) in enumerate(CASES):
            progs.append(("zzb1%02d" % i, "   x = ''\n" + "".join("   %s\n" % ln for ln in body.split("\n")) +
                          "   crt 'C%02d[':x:']'\nend\n" % i))
        progs += [("zzb1ml", MAXRLOCK_PROG), ("zzb1dc0", DHCACHE_PROG % (0, 0)), ("zzb1dc1", DHCACHE_PROG % (1, 1)),
                  ("zzb1dc10", DHCACHE_PROG % (10, 10)), ("zzb1dcr", DHRANGE_PROG), ("zzb1un", USER_PROG),
                  ("zzb1hold", HOLD_PROG), ("zzb1lw", LGN_PROG), ("zzb1tty", TTY_PROG), ("zzb1st", STARTUP_PROG)]
        compile_all(box, sysd, progs)

        say("\n--- the parameters, as built ----------------------------------------------------")
        out = sess(box, *["RUN bp zzb1%02d" % i for i in range(len(CASES))])
        for i, (label, _body, want) in enumerate(CASES):
            got = tagged(out, "C%02d" % i)
            row("%s: wanted %r" % (label, want), got == want, "got %r" % got if got is not None else "no output")

        say("\n--- sd -status ----------------------------------------------------------------")
        p = status(box)
        say("    " + p.replace("\n", "\n    ").rstrip())
        row("511: -status names the version", re.search(r"(?m)^SD \(\S+\)$", p) is not None, p[:80])
        row("511: -status shows a start time from this year or later",
            re.search(r"(?m)^Started   20(2[6-9]|[3-9]\d)-\d\d-\d\d \d\d:\d\d:\d\d$", p) is not None, p[:120])
        row("511: -status counts the process counts and the limit",
            re.search(r"(?m)^Users     \d+ interactive, \d+ phantom, \d+ API, limit \d+$", p) is not None, p[:160])
        row("511: -status does not claim SD is inactive", "not active" not in p)

        say("\n--- 313 MAXRLOCK ----------------------------------------------------------------")
        out = sess(box, "RUN bp zzb1ml")
        for tag, want, label in [
                ("ML0", "0", "CONTROL: with MAXRLOCK 0 six locks are all granted"),
                ("MLCFG", "3", "CONFIG MAXRLOCK 3 is read back"),
                ("MLREADU", "3060", "the fourth READU is refused with error 3060"),
                ("MLOWN", "0", "a record this process has locked already is not a new lock"),
                ("MLAFTER", "0", "after a release the place is free for a new lock"),
                ("MLREADL", "3060", "READL at the limit is refused"),
                ("MLREADVU", "3060", "READVU at the limit is refused"),
                ("MLRLU", "3060", "RECORDLOCKU at the limit is refused"),
                ("MLOPENSEQ", "3060", "OPENSEQ at the limit is refused"),
                ("MLREL", "0", "after RELEASE all three places are free again"),
                ("MLRANGE", "3/1", "CONFIG MAXRLOCK 200000 is refused and leaves 3")]:
            got = tagged(out, tag)
            row("313: %s: wanted %r" % (label, want), got == want, "got %r" % got if got is not None else "no output")
        row("313: with no ON ERROR the process stops with message 11162",
            re.search(r"(?m)^[0-9A-F]{8}: Record lock limit \(MAXRLOCK\) reached at line \d+ of ", out) is not None,
            out[-300:])
        row("313: ... and does not carry on", "MLNOTREACHED" not in out)

        say("\n--- 90 DHCACHE ------------------------------------------------------------------")
        # the range program goes first: the others leave DHCACHE at 10, 1 and 0 for the rest of the session
        out = sess(box, "RUN bp zzb1dcr", "RUN bp zzb1dc10", "RUN bp zzb1dc1", "RUN bp zzb1dc0")
        for tag, want, label in [
                ("DC10", "10/11", "10 keeps both closed files"),
                ("DC1", "1/01", "1 keeps only the file closed last"),
                ("DC0", "0/00", "0 keeps none"),
                ("DCBIG", "10/1", "CONFIG DHCACHE 5000 is refused and changes nothing"),
                ("DCNEG", "10/1", "CONFIG DHCACHE -1 is refused and changes nothing")]:
            got = tagged(out, tag)
            row("90: %s: wanted %r" % (label, want), got == want, "got %r" % got if got is not None else "no output")

        say("\n--- 91 @TTY of the process STARTUP starts ---------------------------------------")
        out = sess(box, "RUN bp zzb1tty")
        row("91: CONTROL: an ordinary session has no @TTY of 'startup'", tagged(out, "TTY") not in (None, "startup"),
            "got %r" % tagged(out, "TTY"))
        out = sess(box, "RUN bp zzb1tty", env=dict(os.environ, SD_STARTUP="1", SD_CONFIG=os.path.join(box, "sd.conf")))
        row("91: a session that is given SD_STARTUP (as sysseg.c gives it) has @TTY 'startup'",
            tagged(out, "TTY") == "startup", "got %r" % tagged(out, "TTY"))
        row("91: ... and what it runs does not inherit the variable", tagged(out, "ENV") == "none",
            "got %r" % tagged(out, "ENV"))
        src = open(os.path.join(HERE, "..", "gplsrc", "sysseg.c")).read()
        m = re.search(r'setenv\("SD_STARTUP", "1", 1\);\s*execl\(path, path, "-asdsys", sysseg->startup', src)
        row("91: sysseg.c sets SD_STARTUP in the child just before it execs 'sd -asdsys <startup>'", m is not None)

        say("\n--- 551 USERPOOL, and what sd.conf refuses ------------------------------------------")
        if restart(box):
            a = sess(box, "RUN bp zzb1un")
            b = sess(box, "RUN bp zzb1un")
            ma, mb = (re.search(r"(?m)^UN\[(\d+)\]\[(\d+)\]\[(\d+)\]", t) for t in (a, b))
            ok = bool(ma and mb)
            row("551: CONTROL: with the default two sessions are given consecutive user numbers",
                ok and int(mb.group(1)) == int(ma.group(1)) + 1, "%s then %s" % (ma and ma.group(0), mb and mb.group(0)))
        else:
            row("551: CONTROL: SD started with the config as built", False, "did not start")
        if restart(box, "USERPOOL=0"):
            a = sess(box, "RUN bp zzb1un")
            b = sess(box, "RUN bp zzb1un")
            ma, mb = (re.search(r"(?m)^UN\[(\d+)\]\[(\d+)\]\[(\d+)\]", t) for t in (a, b))
            ok = bool(ma and mb)
            row("551: USERPOOL=0 reads 0 and the highest user number falls to NUMUSERS (20)",
                ok and ma.group(2) == "20" and ma.group(3) == "0", ma and ma.group(0))
            row("551: ... and the lowest free user number is taken again each time",
                ok and ma.group(1) == mb.group(1), "%s then %s" % (ma and ma.group(0), mb and mb.group(0)))
        else:
            row("551: USERPOOL=0 starts SD", False, "did not start")
        if restart(box, "USERPOOL=2000"):
            ma = re.search(r"(?m)^UN\[(\d+)\]\[(\d+)\]\[(\d+)\]", sess(box, "RUN bp zzb1un"))
            row("551: USERPOOL=2000 reads 2000 and is the highest user number", bool(ma) and ma.group(2) == "2000" and
                ma.group(3) == "2000", ma and ma.group(0))
        else:
            row("551: USERPOOL=2000 starts SD", False, "did not start")
        for bad in ("USERPOOL=20000", "LGNWAIT=40000", "DHCACHE=2000", "MAXRLOCK=-1", "PWDELAY=5000"):
            up = restart(box, bad)
            log = ""
            try:
                log = open(os.path.join(box, "start.log")).read()
            except OSError:
                pass
            word = bad.split("=")[0]
            row("%s: a value out of range stops SD starting, and the log names the parameter" % bad,
                (not up) and ("Invalid value for %s configuration parameter" % word) in log,
                "SD %s; log tail %r" % ("STARTED" if up else "did not start", log[-120:]))

        say("\n--- 46 LGNWAIT ---------------------------------------------------------------------")
        for wait, label in (("0", "CONTROL: 0 refuses a login to a full table at once"),
                            ("10", "10 (one second) waits and then refuses, and counts the failure"),
                            ("100", "100 (ten seconds) waits for a place, logs in, and counts the delay")):
            if not restart(box, "NUMUSERS=2", "LGNWAIT=" + wait):
                row("46: LGNWAIT=%s starts SD" % wait, False, "did not start")
                continue
            ps = holders(box, 2)
            t0 = time.time()
            third = sess(box, "RUN bp zzb1lw")
            took = time.time() - t0
            finish(ps)
            after = sess(box, "RUN bp zzb1lw")
            refused = re.search(r"(?m)^\x07?User limit reached\s*$", third) is not None   # the message follows a BEL
            m = re.search(r"(?m)^LW\[(\d+)\]\[(\d+)\]\[([\d/]+)\]\[(\d+)\]", third)
            stats = tagged(after, "LW") and re.search(r"(?m)^LW\[\d+\]\[\d+\]\[([\d/]+)\]", after).group(1)
            say("    third login %.1f s, refused=%s, its line %r, stats afterwards %r" % (took, refused, m and m.group(0), stats))
            if wait == "100":
                row("46: %s" % label, (not refused) and bool(m) and 10 <= int(m.group(2)) <= 99 and stats == "1/1/0/1/0",
                    "refused=%s line=%r stats=%r" % (refused, m and m.group(0), stats))
            else:
                want = "0/0/0/0/0" if wait == "0" else "1/0/0/1/1"
                row("46: %s" % label, refused and (not m) and stats == want,
                    "refused=%s line=%r stats=%r (wanted %s)" % (refused, m and m.group(0), stats, want))

        say("\n--- 241 the longest call name -----------------------------------------------------")
        # The control is 55 characters: BASIC also writes a listing record, the name and ".LIS", so a program name
        # of 60 or more cannot be compiled at the default MAXIDLEN of 63, whatever the call name rule says.
        n63, n100, n129 = "zz" + "a" * 53, "zz" + "b" * 98, "zz" + "c" * 127
        for nm in (n63, n100, n129):
            put(sysd, nm, "   subroutine %s(x)\n   x = %d\n   return\nend\n" % (nm, len(nm)))
        put(sysd, "zzb1c63", CALL_PROG % n63)
        put(sysd, "zzb1c100", CALL_PROG % n100)
        put(sysd, "zzb1nc80", NAMECALL_PROG % ("zz" + "d" * 78))
        for limit in ("", "MAXIDLEN=200"):
            if not restart(box, *([limit] if limit else [])):
                row("241: SD starts (%s)" % (limit or "as built"), False, "did not start")
                continue
            # an entry left by an earlier phase or run would let a name that cannot be catalogued pass for one that can
            sess(box, *["DELETE.CATALOG " + n for n in (n63, n100, n129)])
            out = sess(box, "BASIC bp " + n63, "CATALOG bp " + n63, "BASIC bp zzb1c63", "RUN bp zzb1c63",
                       "BASIC bp zzb1nc80", "RUN bp zzb1nc80")
            row("241: CONTROL (%s): a %d character name catalogues and is called" % (limit or "as built", len(n63)),
                tagged(out, "CALL") == str(len(n63)), "got %r" % tagged(out, "CALL"))
            long_err = re.search(r"Illegal call name", out.split("RUN bp zzb1nc80", 1)[-1]) is not None
            if not limit:
                row("241: as built, calling a computed 80 character name is 'Illegal call name'", long_err,
                    out.split("RUN bp zzb1nc80", 1)[-1][-200:])
            else:
                row("241: MAXIDLEN=200, calling a computed 80 character name gets past the name test (it is not catalogued)",
                    (not long_err) and "NEVER" not in out, out.split("RUN bp zzb1nc80", 1)[-1][-200:])
                out = sess(box, "BASIC bp " + n100, "CATALOG bp " + n100, "BASIC bp zzb1c100", "RUN bp zzb1c100",
                           "BASIC bp " + n129, "CATALOG bp " + n129)
                row("241: MAXIDLEN=200, a 100 character name catalogues and is called", tagged(out, "CALL") == "100",
                    "got %r" % tagged(out, "CALL"))
                row("241: MAXIDLEN=200, a 129 character name is refused: the limit is the lower of 128 and MAXIDLEN",
                    re.search(r"(?m)^Illegal call name \(zzc", out) is not None, out[-300:])

        say("\n--- 91 the environment of the process sysseg.c starts for STARTUP --------------------")
        if shutil.which("strace") is None:
            say("  [SKIP] strace is not installed; sysseg.c's half is only read from the source above")
        else:
            tool(box, "stop", timeout=120)
            with open(os.path.join(box, "sd.conf")) as f:
                base = f.read().split(MARK)[0].rstrip("\n") + "\n"
            with open(os.path.join(box, "sd.conf"), "w") as f:
                f.write(base + MARK + "\nSTARTUP=RUN bp zzb1st\n")
            trace = os.path.join(box, "strace-start.out")
            if os.path.exists(trace):
                os.remove(trace)
            env = dict(os.environ, SD_CONFIG=os.path.join(box, "sd.conf"))
            sp = subprocess.Popen(["strace", "-f", "-v", "-s", "20000", "-e", "trace=execve", "-o", trace,
                                   os.path.join(sysd, "bin", "sd"), "-start"], env=env, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
            line = ""
            for _ in range(40):
                time.sleep(0.5)
                if os.path.exists(trace):
                    for l in open(trace, errors="replace"):
                        if '"-asdsys"' in l and "execve" in l:
                            line = l
                if line:
                    break
            sp.terminate()
            try:
                sp.wait(timeout=20)
            except subprocess.TimeoutExpired:
                sp.kill()
            say("    exec seen: %s" % (re.sub(r'\[".*?\], \[/\* .*', '...', line)[:140] if line else "none"))
            row("91: the exec of 'sd -asdsys <startup>' carries SD_STARTUP=1 in its environment",
                bool(line) and 'RUN bp zzb1st' in line and '"SD_STARTUP=1"' in line,
                "no such exec was traced" if not line else "environment lacks SD_STARTUP=1")
    finally:
        tool(box, "stop", timeout=120)
        with open(os.path.join(box, "sd.conf")) as f:
            base = f.read().split(MARK)[0].rstrip("\n") + "\n"
        with open(os.path.join(box, "sd.conf"), "w") as f:
            f.write(base)
        for nm in made + ["zzb1c63", "zzb1c100", "zzb1nc80"]:
            for d in ("bp", "bp.out"):
                pth = os.path.join(sysd, d, nm)
                if os.path.exists(pth):
                    os.remove(pth)

    say("\nsandbox-conf-b1: %d passed, %d failed" % (passed, failed))
    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
