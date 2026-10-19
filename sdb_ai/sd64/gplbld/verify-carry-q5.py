#!/usr/bin/env python3
#
# sandbox-q5.py - QM4 gaps, the 16 Oct 26 sitting: the CLEANUP parameter, the PHANTOMS parameter, PHANTOM USER n and LOCK.TRACER.
#                 No install, no sudo.  (RESTRICTED is in sandbox-restricted.py: a compiler change should not run these rows.)
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-q5.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 16 Oct 26 dm  Written for the CLEANUP parameter (sheet 98) and PHANTOMS / PHANTOM USER (sheet 31).
# END-HISTORY
#
# THE INSTRUMENT.  The sandbox, the sessions and the fixture account are those of sandbox-stmt-q3.py, which this file loads as a
# module (its harness is the one place that knows how a fixture account is made, how SD is restarted with other lines in
# sd.conf, and how a session is kept open).  The sandbox is restarted for each configuration; a configuration SD must refuse
# is shown by SD not starting.
#
#   A  CLEANUP: the default (300), what is refused (29, 3601), 30 and 3600 accepted, and the effect: a session killed with
#      SIGKILL leaves its row in the user table, and sdlnxd removes it within the interval - with CLEANUP=30 in well under
#      a minute, with the default not within the same time (the control)
#   B  PHANTOMS and PHANTOM USER n: the parameter's value and what it refuses; a phantom started with USER gets that user
#      number; a number already in use, outside the kept numbers or not a number is refused with its own message and no
#      phantom is made; a session or a phantom started WITHOUT USER never takes a kept number (and does take it when nothing
#      is kept: the control); two kept blocks side by side are both skipped (FIXUSERS then PORTMAP: the old code stopped on
#      the second)
#   C  LOCK.TRACER: off by default (no file), ON makes locktrace (mode 0620), the eight lock actions of a probe in the log in order
#      with their record ids and source line numbers (the raw file is the oracle), an ordinary session logged too, the report and
#      its USER / error forms, a program's own release at its end, a refused lock not logged, OFF stops it, ON again empties it,
#      a link in the file's place refused

import importlib.util
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("q3", os.path.join(HERE, "sandbox-stmt-q3.py"))
q3 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(q3)
say, row, has, tag, put = q3.say, q3.row, q3.has, q3.tag, q3.put

LK_LINES = [
    "   open 'zzq5lf' to f else stop 'no f'",                  # 1
    "   crt 'LKUNO[':@userno:']'",                              # 2
    "   readu x from f, 'REC1' else null",                      # 3   new update lock          code 1
    "   readl y from f, 'REC2' else null",                      # 4   new read lock            code 2
    "   readu y from f, 'REC2' else null",                      # 5   read lock up to update   code 4
    "   readl y from f, 'REC2' else null",                      # 6   update lock down to read code 3
    "   release f, 'REC1'",                                     # 7   record lock let go       code 6
    "   release f, 'REC2'",                                     # 8   record lock let go       code 6
    "   filelock f",                                            # 9   file lock                code 5
    "   fileunlock f",                                          # 10  file lock let go         code 7
    "   crt 'LKDONE'",
    "end",
]
LK_WANT = [(1, "REC1", 3), (2, "REC2", 4), (4, "REC2", 5), (3, "REC2", 6), (6, "REC1", 7), (6, "REC2", 8), (5, "", 9), (7, "", 10)]

USER_PROGS = {
    # the session's own user number, and the configuration in one line
    "zzq5un": "   crt 'UNO[':@userno:']'\nend\n",
    "zzq5cf": "   crt 'CF[':config('CLEANUP'):'][':config('PHANTOMS'):']'\nend\n",
    # every user number in the user table
    "zzq5ul": ("   call !listu(d)\n   s = ''\n   for i = 1 to dcount(d, @fm)\n      s<-1> = d<i,1>\n   next i\n"
               "   crt 'UL[':change(s, @fm, ','):']'\nend\n"),
    # start a phantom from the rest of the sentence; say the return code and what PHANTOM printed.  The sleeper keeps the
    # phantom alive while the table is looked at (SLEEP 40), the other writes the user number it had to a record and ends.
    "zzq5ph": ("   cmd = field(@sentence, ' ', 4, 30)\n"
               "   execute cmd\n   rc = @system.return.code\n"
               "   crt 'PHRC[':rc:']'\nend\n"),
    # C: the locks LOCK.TRACER logs.  One statement to a line, the source lines are the oracle for the line numbers in the log
    "zzq5lk": "\n".join(LK_LINES) + "\n",
    # a session that ends holding a lock
    "zzq5lo": "   open 'zzq5lf' to f else stop 'no f'\n   readu x from f, 'RECX' else null\n   crt 'LOUNO[':@userno:']'\nend\n",
    # a holder that keeps its lock until it is told to go on, and a session that asks for the same record and is refused
    "zzq5lh": ("   open 'zzq5lf' to f else stop 'no f'\n   readu x from f, 'RECH' else null\n   crt 'LHUNO[':@userno:']'\n   input z\n"
               "   crt 'LHDONE'\nend\n"),
    "zzq5lw": ("   open 'zzq5lf' to f else stop 'no f'\n   crt 'LWUNO[':@userno:']'\n"
               "   readu x from f, 'RECH' locked crt 'LWBLOCKED' else crt 'LWGOT'\n   crt 'LWDONE'\nend\n"),
    "zzq5pd": "   open 'bp' to f else stop\n   write @userno to f, 'zzq5pun'\nend\n",
    "zzq5pu": ("   open 'bp' to f else stop 'no bp'\n   delete f, 'zzq5pun'\n"
               "   cmd = field(@sentence, ' ', 4, 30)\n   execute cmd\n   rc = @system.return.code\n"
               "   t = 0\n   r = ''\n   loop\n      read r from f, 'zzq5pun' then exit\n      t += 1\n   until t >= 150\n      nap 100\n   repeat\n"
               "   crt 'PHRC[':rc:']'\n   crt 'PHUNO[':r:']'\nend\n"),
}


def tables(out):
    """The user numbers of the user table, as a list of ints, from the zzq5ul line (None if it did not print)."""
    t = tag(out, "UL")
    if len(t) != 1:
        return None
    return [int(x) for x in t[0].split(",") if x.strip().isdigit()]


def started_with(*lines):
    """Restart SD with these sd.conf lines; return whether it started (the refusal of a bad value is SD not starting)."""
    stop_daemons()
    return q3.restart(*lines)


def refused(why, *lines):
    """Restart SD with these sd.conf lines and say whether it refused to start AND gave this reason.  The reason matters: a build
    that does not know the parameter refuses it too ("Unrecognised configuration parameter"), and a row that only saw 'did not
    start' would pass on it."""
    ok = not started_with(*lines)
    try:
        log = open(os.path.join(q3.BOX, "start.log"), errors="replace").read().strip()
    except OSError:
        log = ""
    return ok and re.search(why, log) is not None, log[-160:]


daemons = []


def start_daemon():
    """A sandbox has no sdlnxd of its own: sandbox-fromtree.py start kills every process of the sandbox's binaries a second after
    SD -start, so that nothing outlives the run.  CLEANUP is sdlnxd's, so this starts the sandbox's sdlnxd (it attaches to the
    sandbox's shared memory) and says that it is running."""
    log = open(os.path.join(q3.BOX, "sdlnxd.log"), "w")
    p = subprocess.Popen([os.path.join(q3.SYS, "bin", "sdlnxd")], stdout=log, stderr=subprocess.STDOUT, env=q3.env(False))
    daemons.append(p)
    time.sleep(1.5)
    say("  -- sdlnxd of the sandbox started, pid %d, %s" % (p.pid, "running" if p.poll() is None else "EXITED %s" % p.returncode))
    return p.poll() is None


def stop_daemons():
    while daemons:
        p = daemons.pop()
        if p.poll() is None:
            p.terminate()
            try:
                p.wait(timeout=15)
            except subprocess.TimeoutExpired:
                p.kill()


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        q3.bail("usage: sandbox-q5.py <dir> [--build]")
    q3.BOX = os.path.abspath(args[0])
    q3.SYS = os.path.join(q3.BOX, "sys")
    q3.SD = os.path.join(q3.SYS, "bin", "sd")
    q3.USER_PROGS = USER_PROGS
    BOX, SYS, SD = q3.BOX, q3.SYS, q3.SD
    say("sandbox-q5: sandbox  %s" % BOX)
    if "--build" in sys.argv:
        if os.path.exists(BOX) and os.listdir(BOX):
            q3.bail("%s is not empty" % BOX)
        r = subprocess.run([sys.executable, q3.TOOL, BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            q3.bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-q5: built, bootstrap passed")
    elif not os.path.isfile(SD):
        q3.bail("%s holds no built sandbox (use --build, or point it at one)" % BOX)
    subprocess.run([sys.executable, q3.TOOL, BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation ------------------------------------------------------------------------------------------------")
    q3.prepare()
    q3.build_account("zzaa")
    for nm, text in USER_PROGS.items():
        put(os.path.join(SYS, "bp", nm), text)
    out = q3.adm(["BASIC bp " + " ".join(USER_PROGS)])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(USER_PROGS)):
        q3.bail("the probes did not compile in SDSYS:\n" + "\n".join(out[-8:]))

    try:
        # -------------------------------------------------------------------------------------------------------------
        say("\n--- A. CLEANUP ----------------------------------------------------------------------------------------------")
        out = q3.adm(["RUN bp zzq5cf", "CONFIG"])
        row("A1: CONTROL: with no CLEANUP in sd.conf, CONFIG('CLEANUP') is 300 and none of PHANTOMS is kept (the old fixed five minutes)",
            tag(out, "CF") == ["300]["], repr(tag(out, "CF")))
        row("A1: ... and the CONFIG verb lists it", has(out, r"^CLEANUP\s+300 seconds$"), repr([l for l in out if "CLEANUP" in l]))
        row("A1: ... and lists no PHANTOMS line while none are kept", not has(out, r"^PHANTOMS\s"), repr([l for l in out if "PHANTOM" in l]))

        for bad in ("CLEANUP=29", "CLEANUP=3601", "CLEANUP=0", "CLEANUP=-5"):
            ok, log = refused(r"Invalid value for CLEANUP configuration parameter", bad)
            row("A2: sd.conf %s: SD does not start and names CLEANUP (30 to 3600 only)" % bad, ok, log)
        row("A2: sd.conf CLEANUP=3600 is the largest accepted", started_with("CLEANUP=3600") and
            tag(q3.adm(["RUN bp zzq5cf"]), "CF") == ["3600]["])

        # the effect.  A session killed with SIGKILL leaves its row in the user table until a cleanup removes it; sdlnxd does
        # that every CLEANUP seconds.
        def reaped(seconds):
            """Start a held session, SIGKILL it, and poll the user table for up to `seconds`.  Returns (its number, whether
            it was in the table before the kill, seconds until it was gone or None)."""
            h = q3.Live("cu%d" % int(time.time()), ["RUN bp zzq5un"], admin=True, hold=True)
            if not h.wait_for(r"(?m)^UNO\[\d+\]", 30):
                return None, False, None
            n = int(re.search(r"(?m)^UNO\[(\d+)\]", h.text()).group(1))
            before = tables(q3.adm(["RUN bp zzq5ul"]))
            seen = before is not None and n in before
            h.kill()
            t0 = time.time()
            while time.time() - t0 < seconds:
                time.sleep(4)
                now = tables(q3.adm(["RUN bp zzq5ul"]))
                if now is not None and n not in now:
                    return n, seen, int(time.time() - t0)
            return n, seen, None

        if started_with("CLEANUP=30"):
            out = q3.adm(["RUN bp zzq5cf", "CONFIG"])
            row("A3: sd.conf CLEANUP=30: CONFIG('CLEANUP') is 30 and the CONFIG verb says so",
                tag(out, "CF") == ["30]["] and has(out, r"^CLEANUP\s+30 seconds$"), repr(tag(out, "CF")))
            if not start_daemon():
                row("A3: the sandbox's sdlnxd runs", False, "it exited")
            n, seen, took = reaped(85)
            row("A3: ... a session killed with SIGKILL was in the user table (user %s) and was removed by sdlnxd within 85 seconds (%s s)"
                % (n, took), seen and took is not None, "seen=%s took=%s" % (seen, took))
        else:
            row("A3: SD starts with CLEANUP=30", False, "did not start")
        if started_with() and start_daemon():
            n, seen, took = reaped(50)
            row("A3: CONTROL: with the default (300) the killed session (user %s) is still in the table after 50 seconds" % n,
                seen and took is None, "seen=%s took=%s" % (seen, took))
            if n:
                q3.adm(["LOGOUT %d" % n])

        # -------------------------------------------------------------------------------------------------------------
        say("\n--- B. PHANTOMS and PHANTOM USER ---------------------------------------------------------------------------")
        started_with()
        out = q3.adm(["RUN bp zzq5ph PHANTOM NO.MSG USER 901 RUN bp zzq5pd"])
        rc = tag(out, "PHRC")
        row("B1: CONTROL: with no PHANTOMS, PHANTOM USER 901 is refused (message 11357) and no phantom starts (a negative return code)",
            has(out, r"^user number 901 is not one of the numbers the phantoms parameter keeps$") and len(rc) == 1 and
            re.match(r"^-\d+$", rc[0]) is not None, repr(out))

        if not started_with("PHANTOMS=900,4"):
            row("B2: SD starts with PHANTOMS=900,4", False, "did not start")
        else:
            out = q3.adm(["RUN bp zzq5cf", "CONFIG"])
            row("B2: PHANTOMS=900,4: CONFIG('PHANTOMS') is 900,4 and the CONFIG verb lists it",
                tag(out, "CF") == ["300][900,4"] and has(out, r"^PHANTOMS\s+900,4$"), repr(out[:6]))
            out = q3.adm(["RUN bp zzq5pu PHANTOM NO.MSG USER 901 RUN bp zzq5pd"])
            ph = tag(out, "PHUNO")
            row("B3: PHANTOM USER 901: the phantom's @USERNO is 901, and so is the return code",
                ph == ["901"] and tag(out, "PHRC") == ["901"], repr(out[-4:]))
            out = q3.adm(["RUN bp zzq5ph PHANTOM NO.MSG USER 903 SLEEP 40", "RUN bp zzq5ul"])
            tb = tables(out)
            row("B4: a sleeping phantom started with USER 903 holds user number 903 in the user table",
                tag(out, "PHRC") == ["903"] and tb is not None and 903 in tb, repr(tag(out, "PHRC")) + repr(tb))
            out = q3.adm(["RUN bp zzq5ph PHANTOM NO.MSG USER 903 SLEEP 40", "RUN bp zzq5ul"])
            tb = tables(out)
            row("B5: a second PHANTOM USER 903 while the first runs is refused (message 11358) and 903 is in the table once",
                has(out, r"^user number 903 is already in use$") and tb is not None and tb.count(903) == 1, repr(out))
            q3.adm(["LOGOUT 903"])
            for bad, why in (("899", "just below the kept numbers"), ("904", "just above them"), ("0", "zero"), ("1", "an ordinary user number")):
                out = q3.adm(["RUN bp zzq5ph PHANTOM NO.MSG USER %s SLEEP 1" % bad])
                want = (r"^phantom user needs a user number$" if bad == "0" else
                        r"^user number %s is not one of the numbers the phantoms parameter keeps$" % bad)
                row("B6: PHANTOM USER %s (%s) is refused with its own message" % (bad, why), has(out, want), repr(out))
            for bad in ("", "abc", "1.5", "-3"):
                out = q3.adm(["RUN bp zzq5ph PHANTOM NO.MSG USER %s" % bad] if bad else ["RUN bp zzq5ph PHANTOM NO.MSG USER"])
                row("B6: PHANTOM USER %r is refused: a user number is needed" % bad,
                    has(out, r"^phantom user needs a user number$"), repr(out))

        # kept numbers are not given to anybody else.  USERPOOL=0 takes the lowest free number, so a holder is user 1 and
        # the session after it would be 2 - unless 2 to 4 are kept for phantoms.
        def second_session():
            h = q3.Live("kept%d" % int(time.time() * 1000), ["RUN bp zzq5un"], admin=True, hold=True)
            h.wait_for(r"(?m)^UNO\[\d+\]", 30)
            first = re.search(r"(?m)^UNO\[(\d+)\]", h.text())
            out = q3.adm(["RUN bp zzq5un", "RUN bp zzq5pu PHANTOM NO.MSG RUN bp zzq5pd"])
            h.p.stdin.write("OFF\n")
            h.p.stdin.flush()
            h.wait(30)
            return (first.group(1) if first else None), tag(out, "UNO"), tag(out, "PHUNO")

        if started_with("USERPOOL=0"):
            first, un, phun = second_session()
            row("B7: CONTROL: nothing kept (USERPOOL=0): with user %s held, the next session is %s and a phantom started without USER is %s "
                "(the lowest free numbers)" % (first, un, phun),
                first == "1" and un == ["2"] and phun == ["3"], "%r %r %r" % (first, un, phun))
        if started_with("USERPOOL=0", "PHANTOMS=2,3"):
            first, un, phun = second_session()
            row("B7: PHANTOMS=2,3: with user %s held, the next session is 5 and a phantom started without USER is 6 - neither takes 2 to 4"
                % first, first == "1" and un == ["5"] and phun == ["6"], "%r %r %r" % (first, un, phun))
            out = q3.adm(["RUN bp zzq5pu PHANTOM NO.MSG USER 3 RUN bp zzq5pd"])
            row("B7: ... and USER 3 still gives a phantom user number 3 (the kept numbers are for it)",
                tag(out, "PHUNO") == ["3"] and tag(out, "PHRC") == ["3"], repr(out[-4:]))
        # two kept blocks side by side: FIXUSERS 2-3 and PORTMAP 4-5.  The old code skipped the first and handed out 4.
        if started_with("USERPOOL=0", "FIXUSERS=2,2", "PORTMAP=9990,4,2"):
            first, un, phun = second_session()
            row("B8: FIXUSERS=2,2 and PORTMAP=9990,4,2 side by side: with user %s held, the next session is 6, not 4" % first,
                first == "1" and un == ["6"], "%r %r %r" % (first, un, phun))
        if started_with("USERPOOL=0", "FIXUSERS=2,2", "PHANTOMS=4,2"):
            first, un, phun = second_session()
            row("B8: FIXUSERS=2,2 and PHANTOMS=4,2 side by side: the next session is 6", first == "1" and un == ["6"],
                "%r %r %r" % (first, un, phun))

        # what read_config refuses
        for bad, why in ((("PHANTOMS=0,3",), r"PHANTOMS user numbers must lie between 1 and"),
                         (("PHANTOMS=5,0",), r"PHANTOMS user numbers must lie between 1 and"),
                         (("PHANTOMS=30000,5",), r"PHANTOMS user numbers must lie between 1 and"),
                         (("FIXUSERS=10,5", "PHANTOMS=12,3"), r"PHANTOMS and FIXUSERS user numbers overlap"),
                         (("PORTMAP=9990,10,5", "PHANTOMS=12,3"), r"PHANTOMS and PORTMAP user numbers overlap")):
            ok, log = refused(why, *bad)
            row("B9: sd.conf %s: SD does not start and says why" % " ".join(bad), ok, log)
        row("B9: PHANTOMS=900,4 beside FIXUSERS=10,5 (no overlap) starts", started_with("PHANTOMS=900,4", "FIXUSERS=10,5"))
        # USPLIT ignores the kept numbers, but USER n still takes a free one of PHANTOMS' numbers
        if started_with("PHANTOMS=900,4", "USPLIT=1"):
            out = q3.adm(["RUN bp zzq5pu PHANTOM NO.MSG USER 901 RUN bp zzq5pd"])
            row("B10: USPLIT=1 with PHANTOMS=900,4: PHANTOM USER 901 still gives the phantom user number 901",
                tag(out, "PHUNO") == ["901"] and tag(out, "PHRC") == ["901"], repr(out[-4:]))
        else:
            row("B10: SD starts with USPLIT=1 and PHANTOMS=900,4", False, "did not start")

        # -------------------------------------------------------------------------------------------------------------
        say("\n--- C. LOCK.TRACER ------------------------------------------------------------------------------------------")
        started_with()
        trace = os.path.join(SYS, "locktrace")
        if os.path.lexists(trace):
            os.remove(trace)
        q3.adm(["CREATE.FILE zzq5lf DYNAMIC"])
        q3.plain("zzaa", ["CREATE.FILE zzq5lf DYNAMIC"])

        def trace_lines():
            try:
                raw = open(trace, "rb").read().decode("latin-1")
            except OSError:
                return None
            return [ln.split("\xfd") for ln in raw.split("\n") if ln]

        out = q3.adm(["LOCK.TRACER", "RUN bp zzq5lk"])
        row("C1: CONTROL: LOCK.TRACER has not been switched on: it says there is no lock trace, and the probe's locks left no file",
            has(out, r"^there is no lock trace: lock\.tracer on starts one$") and not os.path.lexists(trace), repr(out[:3]))
        t0 = time.time()
        def of_probe(lines):
            """The lines about the probe's file zzq5lf.  The log holds every lock of every session, SD's own included (the login
            of a session takes $ipc, the command processor $command.stack, the verb itself reads locktrace), so a row looks at
            the lines whose file it knows."""
            return [f for f in (lines or []) if len(f) == 8 and f[2].endswith("zzq5lf")]

        out = q3.adm(["LOCK.TRACER ON"])
        st = os.stat(trace) if os.path.exists(trace) else None
        row("C2: LOCK.TRACER ON says so and makes locktrace in the system directory, mode 0620, in the system directory's group, "
            "with nothing yet about the probe's file",
            has(out, r"^lock tracing is on$") and st is not None and (st.st_mode & 0o777) == 0o620
            and st.st_gid == os.stat(SYS).st_gid and of_probe(trace_lines()) == [],
            repr(out[:3]) + (" %o" % (st.st_mode & 0o777) if st else " no file"))
        out = q3.adm(["RUN bp zzq5lk"])
        uno = tag(out, "LKUNO")
        tl = trace_lines()
        mine = [f for f in of_probe(tl) if uno and f[1] == uno[0]]
        got = [(int(f[4]), f[3], int(f[7])) for f in mine if f[4].isdigit() and f[7].lstrip("-").isdigit()]
        row("C3: the probe's eight lock actions are in the log in order, as (action, record id, line): 1 REC1 3, 2 REC2 4, 4 REC2 5, "
            "3 REC2 6, 6 REC1 7, 6 REC2 8, 5 (file) 9, 7 (file) 10 - the lines are the source lines of the program",
            got == LK_WANT, repr(got))
        row("C3: ... every line has eight fields; the user number is the session's; the program is zzq5lk (its object's pathname); "
            "the file is zzq5lf; the offset is hexadecimal; the time is the time of the run",
            len(mine) == 8 and all(len(f) == 8 and f[5].endswith("/zzq5lk") and f[2].endswith("zzq5lf") and re.fullmatch(r"[0-9A-F]+", f[6])
                                   and t0 - 5 <= int(f[0]) <= time.time() + 5 for f in mine),
            repr(mine[:2]))
        before = len(tl or [])
        out = q3.plain("zzaa", ["RUN bp zzq5lk"])
        uno2 = tag(out, "LKUNO")
        tl2 = trace_lines()
        mine2 = [f for f in of_probe((tl2 or [])[before:]) if uno2 and f[1] == uno2[0]]
        row("C4: an ORDINARY session's locks are logged too (the users of SD may append): eight lines, its own user number, its file "
            "in its own account",
            len(mine2) == 8 and all("zzaa" in f[2] and f[2].endswith("zzq5lf") for f in mine2) and [int(f[4]) for f in mine2] == [w[0] for w in LK_WANT],
            repr(mine2[:2]))

        # the report
        out = q3.adm(["LOCK.TRACER USER %s" % uno[0]]) if uno else []
        rows_ = [ln for ln in out if re.match(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\s", ln) and "zzq5lf" in ln]
        acts = [re.match(r"^\S+ \S+\s+\d+\s+(.{7})", ln).group(1).strip() for ln in rows_ if re.match(r"^\S+ \S+\s+\d+\s+(.{7})", ln)]
        row("C5: LOCK.TRACER USER n lists that session's lines with the action's words, in order",
            acts == ["Get RU", "Get RL", "RL->RU", "RU->RL", "Rel RX", "Rel RX", "Get FX", "Rel FX"], repr(acts))
        row("C5: ... with the record ids and the line numbers in their columns",
            len(rows_) == 8 and all(re.search(r"\s%d\s+\S*zzq5lf\s+%s$" % (w[2], re.escape(w[1])) if w[1] else r"\s%d\s+\S*zzq5lf\s*$" % w[2], ln)
                                    for ln, w in zip(rows_, LK_WANT)), repr(rows_[:2]))
        if mine:
            import datetime
            import zoneinfo
            when = datetime.datetime.fromtimestamp(int(mine[0][0]), zoneinfo.ZoneInfo("Asia/Kathmandu")).strftime("%Y-%m-%d %H:%M:%S")
            row("C5: ... the date and time are the lock's epoch time in the session's time zone (%s)" % when,
                bool(rows_) and rows_[0].startswith(when), repr(rows_[:1]))
        out = q3.adm(["LOCK.TRACER", "LOCK.TRACER USER 99999", "LOCK.TRACER BOGUS", "LOCK.TRACER USER x"])
        row("C5: the whole log lists both sessions' lines about the probe's file (16) and SD's own locks as well; a user with none gets "
            "its own sentence; a word it does not know is refused",
            len([ln for ln in out if re.match(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\s", ln) and "zzq5lf" in ln]) == 16
            and len([ln for ln in out if re.match(r"^\d{4}-\d\d-\d\d \d\d:\d\d:\d\d\s", ln) and "$ipc" in ln]) > 0
            and has(out, r"^no locks were logged for user 99999$")
            and has(out, r"Unexpected token \(BOGUS\)") and has(out, r"Unexpected token \(X\)"), repr(out[-5:]))

        # a program that ends while holding a lock: the lock it lets go at its end is logged, as the program's act, on the line of END
        n_before = len(trace_lines() or [])
        out = q3.adm(["RUN bp zzq5lo"])
        uno3 = tag(out, "LOUNO")
        tail = of_probe((trace_lines() or [])[n_before:])
        row("C6: a program that ends while holding a lock logs the lock (action 1, RECX, line 2) and the release at its end (action 6, "
            "RECX, line 4)",
            len(tail) == 2 and all(f[1] == (uno3[0] if uno3 else None) and f[3] == "RECX" and f[5].endswith("/zzq5lo") for f in tail)
            and [(f[4], f[7]) for f in tail] == [("1", "2"), ("6", "4")], repr(tail))

        # a lock that is refused (held by another session) is not a line; the holder's is
        h = q3.Live("lkh", ["RUN bp zzq5lh"], admin=True, hold=True)
        h.wait_for(r"(?m)^LHUNO\[\d+\]", 30)
        holder = re.search(r"(?m)^LHUNO\[(\d+)\]", h.text())
        out = q3.adm(["RUN bp zzq5lw"])
        blocked = has(out, r"^LWBLOCKED$")
        tailh = [f for f in of_probe(trace_lines()) if f[3] == "RECH"]
        h.p.stdin.write("OFF\n")
        h.p.stdin.flush()
        h.wait(30)
        row("C6: a lock that is refused (the record is held by session %s) is not logged: the log has the holder's Get RU on RECH and "
            "none from the session that was told LOCKED" % (holder.group(1) if holder else "?"),
            holder is not None and blocked and [(f[1], f[4]) for f in tailh][:1] == [(holder.group(1), "1")] and
            all(f[1] == holder.group(1) for f in tailh), repr(tailh))

        # OFF, and ON again empties
        n_probe = len(of_probe(trace_lines()))
        out = q3.adm(["LOCK.TRACER OFF", "RUN bp zzq5lk"])
        row("C7: LOCK.TRACER OFF says so and the probe's locks after it add nothing to the file (%d lines about the probe's file, before "
            "and after)" % n_probe, has(out, r"^lock tracing is off$") and n_probe >= 18 and len(of_probe(trace_lines())) == n_probe,
            repr(out[:3]) + " %d -> %d" % (n_probe, len(of_probe(trace_lines()))))
        out = q3.adm(["LOCK.TRACER ON"])
        row("C7: switching it on again empties the file (openQM: re-enabling overwrites it): the probe's old lines are gone",
            has(out, r"^lock tracing is on$") and of_probe(trace_lines()) == [] and b"REC1" not in open(trace, "rb").read(),
            repr(out[:2]) + " %d" % len(of_probe(trace_lines())))
        q3.adm(["LOCK.TRACER OFF"])

        # a link left in the file's place is not written through, and is not started on
        target = os.path.join(BOX, "zzq5target")
        with open(target, "w") as fh:
            fh.write("keep\n")
        os.remove(trace)
        os.symlink(target, trace)
        out = q3.adm(["LOCK.TRACER ON", "RUN bp zzq5lk"])
        with open(target) as fh:
            kept = fh.read()
        row("C8: with a link in the place of locktrace, LOCK.TRACER ON is refused (could not be started) and the link's target is not "
            "written to, not even by the locks that follow", has(out, r"^lock tracing could not be started$") and kept == "keep\n", repr(out[:3]) + repr(kept))
        os.remove(trace)
        os.remove(target)
    finally:
        for lv_ in q3.lives:
            lv_.kill()
        stop_daemons()
        started_with()
        for stray in ("locktrace", "zzq5target"):
            sp = os.path.join(SYS if stray == "locktrace" else BOX, stray)
            if os.path.lexists(sp):
                os.remove(sp)
        for nm in list(USER_PROGS) + ["zzq5pun"]:
            for d in ("bp", "bp.out"):
                p = os.path.join(SYS, d, nm)
                if os.path.exists(p):
                    os.remove(p)

    say("\nsandbox-q5: %d passed, %d failed" % (q3.passed, q3.failed))
    if q3.passed + q3.failed == 0:
        q3.bail("no row ran - a broken test, not a pass")
    return 1 if q3.failed else 0


if __name__ == "__main__":
    sys.exit(main())
