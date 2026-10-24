#!/usr/bin/env python3
#
# sandbox-listu-a5.py - 1.2-0 bundle A-5, the second sitting (14 Oct 26): the user table and process reporting.  Sheet
#                       items 24 and 29 (LISTU and !LISTU show the account), 38 (LISTU DETAIL, SYSTEM(1056)), 491 (the Hot
#                       Spot Monitor counts opens, reads, writes and deletes) and 577 (PSTAT shows when a wait began).
#                       No install, no sudo.
#
#   python3 /home/don/Projects/SDCore4Linux/sdb_ai/sd64/gplbld/sandbox-listu-a5.py <dir> [--build]
#
# <dir> is a sandbox made by sandbox-fromtree.py.  With --build it is built first from THIS tree (it must be empty or
# absent).  Exit 0 every row passed, 1 a row failed, 2 it could not run.
#
# START-HISTORY:
# 14 Oct 26 dm  Written for 1.2-0 bundle A-5, sheet 24, 29, 38, 491 and 577.
# END-HISTORY
#
# THE INSTRUMENT.  Sessions are real: bin/sd with a pipe on stdin.  A "foreign" user is a live session that renames itself
# (kernel(K$SET.USERNAME), an $internal probe) and then waits, so the viewers below look at a user table that holds
# somebody else's session; the sandbox cannot make a second Linux user, and the rule is about the login name the user
# table holds.  The viewers are ORDINARY sessions in a fixture account (no -internal, SDTEST_ADMIN unset: CPROC is patched,
# as sandbox-gates.py patches it, so that the sandbox user is the administrator only when asked) and an administrator one.
#
#   A  24 and 29: the account in !LISTU (value 9) and in LISTU - one's own session, after a LOGTO, a phantom (it starts in
#      its parent's account), another user's session seen by an ordinary user (blank) and by the administrator (shown)
#   B  38: LISTU DETAIL and SYSTEM(1056) - counts of interactive, API, iPhantom and other phantoms, and the peak
#   C  491: HSM - opens, reads, writes and deletes of one program, exactly, with the OPEN's VOC lookup and the READV /
#      WRITEV recursive code not counted; counters cleared by HSM ON; nothing before HSM ON
#   D  577: PSTAT of a process blocked on a lock shows when the wait began
#
# NOT TESTED HERE: an API session (a sandbox cannot host one) - the API count of SYSTEM(1056) is only seen as 0; the
# refusal of kernel(K$SET.ACCOUNT) from a program that is not $internal (such a program cannot call KERNEL at all, BCOMP);
# HSM USER n (it reads the same hsm_dump through an event).

import datetime
import getpass
import os
import re
import shutil
import subprocess
import sys
import time

os.environ["TZ"] = "Asia/Kathmandu"        # +05:45: a time shown in UTC or in a whole-hour zone is wrong by a visible amount
time.tzset()

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.join(HERE, "sandbox-fromtree.py")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
USER = getpass.getuser()
GROUP = subprocess.run(["id", "-gn"], capture_output=True, text=True).stdout.strip()
passed = failed = 0
BOX = SYS = SD = None
lives = []


def say(s=""):
    print(s)
    sys.stdout.flush()


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
    say("sandbox-listu-a5: CANNOT RUN - " + msg)
    sys.exit(2)


def env(admin):
    e = dict(os.environ, SD_CONFIG=os.path.join(BOX, "sd.conf"))
    e.pop("SSH_CONNECTION", None)
    e.pop("SSH_TTY", None)
    if admin:
        e["SDTEST_ADMIN"] = "1"
    else:
        e.pop("SDTEST_ADMIN", None)
    return e


def sd(cwd, cmds, admin=False, internal=False, account=None):
    """Run sd with the commands on stdin; return the lines it printed after the TERM line, echoed commands removed.
    Prints the real inputs: the working directory, the flags and the commands."""
    argv = [SD] + (["-internal"] if internal else []) + (["-a" + account] if account else [])
    say("    > %s%s%s in %s: %s" % ("[admin] " if admin else "", "[internal] " if internal else "",
                                    ("-a" + account + " ") if account else "", os.path.relpath(cwd, BOX), " | ".join(cmds)))
    body = "\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + "OFF\n"
    p = subprocess.run(argv, input=body, cwd=cwd, env=env(admin), capture_output=True, text=True, errors="replace", timeout=300)
    out = ANSI.sub("", p.stdout + p.stderr).split(":TERM 200,9999", 1)[-1]
    return [ln.rstrip() for ln in out.splitlines() if ln.strip() and not ln.startswith(":")]


def plain(acct, cmds):
    return sd(os.path.join(BOX, "user_accounts", acct), cmds, account=acct)


def adm(cmds, internal=False):
    return sd(SYS, cmds, admin=True, internal=internal)


class Live:
    """A session on a pipe kept open, in a fixture account, ended by OFF unless hold=True."""

    def __init__(self, tag, cmds, account, hold=False):
        self.out = os.path.join(BOX, "live-%s.out" % tag)
        self.fh = open(self.out, "w")
        self.p = subprocess.Popen([SD, "-a" + account], stdin=subprocess.PIPE, stdout=self.fh, stderr=subprocess.STDOUT,
                                  cwd=os.path.join(BOX, "user_accounts", account), env=env(False), text=True)
        self.p.stdin.write("\nTERM 200,9999\n" + "".join(c + "\n" for c in cmds) + ("" if hold else "OFF\n"))
        self.p.stdin.flush()
        say("    > live %s in %s: %s" % (tag, account, " | ".join(cmds)))
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


def has(lines, pattern):
    return any(re.search(pattern, ln) for ln in lines)


def put(path, text):
    with open(path, "w", encoding="ascii") as f:
        f.write(text)


def tagged(text, tag):
    m = re.search(r"(?m)^%s\[(.*)\]\s*$" % tag, text)
    return m.group(1) if m else None


def near_now(stamp, fmt, seconds=120):
    try:
        t = datetime.datetime.strptime(stamp, fmt)
    except ValueError:
        return False
    return abs((datetime.datetime.now() - t).total_seconds()) <= seconds


# ---------------------------------------------------------------------------------------------------------------------
# The probes.  User programs go in the fixture accounts' bp directories; the two that must be $internal are catalogued.

USER_PROGS = {
    # every user of the table, with its login name, its account, and whether it is a phantom - from !LISTU, as any program
    # may call it (the constants of int$keys.h are for $internal programs, so the value numbers are written out)
    "zzluu": ("   call !listu(d)\n   for i = 1 to dcount(d, @fm)\n"
              "      crt 'LU[':d<i,1>:'][':d<i,6>:'][':d<i,9>:'][':(bitand(d<i,4> + 0, 1) # 0):']'\n"
              "   next i\n   crt 'MY[':@userno:'][':@who:']'\n   crt 'LUDONE'\nend\n"),
    "zzluc": ("   execute 'LISTU NO.PAGE' capturing out\n   for i = 1 to dcount(out, @am)\n      crt 'LC:':out<i>\n   next i\n"
              "   crt 'MY[':@userno:'][':@who:']'\n   crt 'LCDONE'\nend\n"),
    "zzlunap": "   for i = 1 to 120\n      nap 100\n   next i\n   crt 'NAPDONE'\nend\n",
    # 15 Oct 26, QM4 gaps Q-5: CHILD and SIGNAL.  The phantom waits for SYSTEM(1062), then leaves a word in a sequential file; the
    # session that started it waits for the phantom to be listed as its child, raises the signal and waits for it to end.
    "zzlusgp": ("   t = 0\n   loop\n   until system(1062) or t >= 150\n      nap 100 ; t += 1\n   repeat\n"
                "   openseq 'zzlusg.txt' to f then null else create f else stop 'no create'\n   weofseq f\n"
                "   writeseq (if t < 150 then 'SIGNALLED' else 'TIMEOUT') to f else null\n   closeseq f\nend\n"),
    "zzlusig": ("   deleteseq 'zzlusg.txt' else null\n   execute 'PHANTOM NO.MSG RUN bp zzlusgp' capturing j\n"
                "   t = 0\n   loop\n      kids = system(1058)\n   until kids # '' or t >= 150\n      nap 100 ; t += 1\n   repeat\n"
                "   uid = kids<1>\n   crt 'CH1[':child(uid):'/':child(0):'/':child(uid + 5000):'/':dcount(kids, @fm):']'\n"
                "   nap 1500\n   r = signal(uid)\n"
                "   t = 0\n   loop\n   until not(child(uid)) or t >= 200\n      nap 100 ; t += 1\n   repeat\n"
                "   openseq 'zzlusg.txt' to f else f = ''\n   readseq a from f else a = 'NOFILE'\n   closeseq f\n"
                "   crt 'SG[':r:'/':a:']'\n   crt 'CH2[':child(uid):']'\n   deleteseq 'zzlusg.txt' else null\n   crt 'SIGDONE'\nend\n"),
    # LISTU DETAIL and SYSTEM(1056) with a phantom alive
    # the phantom's cell is reserved at once but the phantom itself takes a moment to start: wait (up to 15 s) until the table says so
    "zzludet": ("   execute 'PHANTOM NO.MSG RUN bp zzlunap' capturing j\n   up = @false ; t = 0\n"
                "   loop\n      call !listu(d)\n      for i = 1 to dcount(d, @fm)\n"
                "         if bitand(d<i,4> + 0, 1) # 0 then up = @true\n      next i\n"
                "   until up or t >= 150\n      nap 100 ; t += 1\n   repeat\n   crt 'PHUP[':up:'][':t:']'\n"
                "   execute 'LISTU DETAIL NO.PAGE' capturing out\n   for i = 1 to dcount(out, @am)\n      crt 'LD:':out<i>\n   next i\n"
                "   c = system(1056)\n   crt 'C1056[':change(c, @fm, '/'):']'\n"
                "   call !listu(d)\n   for i = 1 to dcount(d, @fm)\n"
                "      crt 'LU[':d<i,1>:'][':d<i,6>:'][':d<i,9>:'][':(bitand(d<i,4> + 0, 1) # 0):']'\n   next i\n"
                # 15 Oct 26, QM4 gaps Q-8: LIST.PHANTOMS, which lists the phantoms and no one else
                "   execute 'LIST.PHANTOMS' capturing out\n   for i = 1 to dcount(out, @am)\n      crt 'LP:':out<i>\n   next i\n"
                "   execute 'LIST.PHANTOMS USER nobody.such' capturing out\n   for i = 1 to dcount(out, @am)\n      crt 'LQ:':out<i>\n   next i\n"
                "   execute 'LIST.PHANTOMS POOL x' capturing out\n   for i = 1 to dcount(out, @am)\n      crt 'LR:':out<i>\n   next i\n"
                "   execute 'LIST.PHANTOMS USER' capturing out\n   for i = 1 to dcount(out, @am)\n      crt 'LS:':out<i>\n   next i\n"
                "   crt 'LDDONE'\nend\n"),
    "zzlucnt": "   c = system(1056)\n   crt 'C1056[':change(c, @fm, '/'):']'\n   crt 'LCNTDONE'\nend\n",
    # the Hot Spot Monitor: one open, three writes and a WRITEV, three reads and two READVs, two deletes
    "zzhsm": ("   open 'zzhsmf' to f else stop 'no f'\n"
              "   write 'a' to f, 'k1'\n   write 'b' to f, 'k2'\n   write 'c' to f, 'k3'\n"
              "   read x from f, 'k1' else null\n   read x from f, 'k2' else null\n   read x from f, 'k3' else null\n"
              "   readv y from f, 'k1', 1 else null\n   readv y from f, 'k2', 1 else null\n"
              "   writev 'z' to f, 'k1', 1\n   delete f, 'k1'\n   delete f, 'k2'\n   crt 'HSMDONE'\nend\n"),
    "zzhsmd": ("   execute 'HSM DISPLAY' capturing out\n   for i = 1 to dcount(out, @am)\n      crt 'HD:':out<i>\n   next i\n"
               "   crt 'HDDONE'\nend\n"),
    # a process blocked on a lock, a holder, and an observer that runs PSTAT for the waiter
    "zzluwh": ("   execute 'DELETE.FILE zzluwf' capturing j\n   execute 'CREATE.FILE zzluwf' capturing j\n"
               "   open 'zzluwf' to f else stop 'no f'\n   readu r from f, 'w1' else null\n   crt 'WH[':@userno:']'\n"
               "   sleep 12\n   crt 'WH DONE'\nend\n"),
    "zzluww": ("   open 'zzluwf' to f else stop 'no f'\n   crt 'WW[':@userno:']'\n"
               "   readu r from f, 'w1' else null\n   crt 'WW DONE'\nend\n"),
}

# $internal: set the session's login name to somebody else's and wait there
GPL_PROGS = {
    "zzluoth": ("$internal\nprogram zzluoth\n$catalog $zzluoth\n$include keys.h\n$include int$keys.h\n"
                "   void kernel(K$SET.USERNAME, 'zzother')\n"
                "   crt 'OTH[':@userno:'][':kernel(K$USERNAME,0):'][':@who:']'\n"
                "   for i = 1 to 250\n      nap 100\n   next i\n   crt 'OTH DONE'\nend\n"),
    # the account the kernel holds for this session, straight from K$USERS, and what K$SET.ACCOUNT does
    "zzluset": ("$internal\nprogram zzluset\n$catalog $zzluset\n$include keys.h\n$include int$keys.h\n"
                "   a = kernel(K$USERS, @userno)<1,K$USERS.ACCOUNT>\n   crt 'SET0[':a:']'\n"
                "   x = kernel(K$SET.ACCOUNT, 'zzname')\n   crt 'SET1[':x:'][':kernel(K$USERS, @userno)<1,K$USERS.ACCOUNT>:']'\n"
                "   x = kernel(K$SET.ACCOUNT, '')\n   crt 'SET2[':x:'][':kernel(K$USERS, @userno)<1,K$USERS.ACCOUNT>:']'\n"
                "   crt 'SETDONE'\nend\n"),
}


def prepare():
    """A CPROC that is not the install build (so the sandbox user is the administrator only when SDTEST_ADMIN=1), the
    internal probes, catalogued."""
    path = os.path.join(SYS, "gpl.bp", "cproc")
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    old = "if downcase(kernel(K$USERNAME, 0)) = '%s' and env('SSH_CONNECTION') = ''" % USER
    new = "if downcase(kernel(K$USERNAME, 0)) = '%s' and env('SDTEST_ADMIN') = '1' and env('SSH_CONNECTION') = ''" % USER
    if "SDTEST_ADMIN" not in text:
        if text.count(old) != 1:
            bail("the sandbox CPROC does not have the one elevation test this suite patches (%d matches)" % text.count(old))
        with open(path, "w", encoding="utf-8") as f:
            f.write(text.replace(old, new))
    put(os.path.join(SYS, "gpl.bp", "define_install.h"), "*comment out * $define IS_INSTALL\n")
    out = adm(["BASIC gpl.bp cproc"], internal=True)
    if not has(out, r"^Compiled 1 program\(s\) with no errors"):
        bail("CPROC did not recompile in the sandbox:\n" + "\n".join(out[-8:]))
    for nm, text in GPL_PROGS.items():
        put(os.path.join(SYS, "gpl.bp", nm), text)
    out = adm(["BASIC gpl.bp " + " ".join(GPL_PROGS)], internal=True)
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(GPL_PROGS)):
        bail("the internal probes did not compile:\n" + "\n".join(out[-8:]))


def build_account(name):
    """A directory with a VOC made from NEWVOC, a bp directory with the user probes in it, VOC verbs for the catalogued
    internal probes, and a register record whose group is the sandbox user's own (so that LOGTO passes its membership test)."""
    path = os.path.join(BOX, "user_accounts", name)
    if os.path.isdir(path):
        shutil.rmtree(path)
    os.makedirs(os.path.join(path, "sub"))
    put(os.path.join(SYS, "bp", "zzfix"), "\n".join([
        "$internal",
        "   acct = '%s'" % path,
        "   create.file acct:'/voc' dynamic on error crt 'FIX create voc failed' ; stop",
        "   openpath acct:'/voc' to v else crt 'FIX open voc failed' ; stop",
        "   openpath '%s/newvoc' to nv else crt 'FIX no newvoc' ; stop" % SYS,
        "   select nv to 11",
        "   loop",
        "      readnext id from 11 else exit",
        "      read rec from nv, id then write rec to v, id",
        "   repeat",
        "   write 'X' to v, '$command.stack'",
    ] + ["   write 'V':@fm:'CA':@fm:'$%s' to v, '%s'" % (n, n) for n in GPL_PROGS] + (
        # LISTU is an administrator's verb: NEWVOC does not carry it.  zzaa is given it, as an administrator could give it
        ["   write 'V':@fm:'CA':@fm:'$listu' to v, 'listu'"] if name == "zzaa" else []) + [
        "   create.file acct:'/bp' directory on error crt 'FIX bp failed' ; stop",
        "   write 'F':@fm:'bp' to v, 'bp'",
        "   create.file acct:'/cat' directory on error crt 'FIX cat failed' ; stop",
        "   crt 'FIX done ':'%s'" % name,
        "end", ""]))
    out = adm(["BASIC bp zzfix", "RUN bp zzfix"], internal=True)
    if not has(out, r"^FIX done " + name + "$"):
        bail("the fixture account %s was not built:\n%s" % (name, "\n".join(out[-6:])))
    put(os.path.join(SYS, "accounts", name), "\n".join([path, "", GROUP, "", "", "", "", "", "", "yes", "yes", "yes"]) + "\n")   # 17 Oct 26: the edit gates (S.64) on
    for nm, text in USER_PROGS.items():
        put(os.path.join(path, "bp", nm), text)
    out = plain(name, ["BASIC bp " + " ".join(USER_PROGS)])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(USER_PROGS)):
        bail("the user probes did not compile in %s:\n%s" % (name, "\n".join(out[-8:])))
    return path


def lu_rows(lines):
    """[(uid, login name, account, is phantom)] from the LU[..] lines."""
    return [m.groups() for m in (re.match(r"^LU\[(\d+)\]\[([^\]]*)\]\[([^\]]*)\]\[(-?\d)\]\s*$", ln) for ln in lines) if m]


def by_name(rows, name):
    return [r for r in rows if r[1] == name]


def main():
    global BOX, SYS, SD
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    if len(args) != 1:
        bail("usage: sandbox-listu-a5.py <dir> [--build]")
    BOX = os.path.abspath(args[0])
    SYS = os.path.join(BOX, "sys")
    SD = os.path.join(SYS, "bin", "sd")
    say("sandbox-listu-a5: sandbox  %s" % BOX)
    say("sandbox-listu-a5: user %s, group %s, TZ %s" % (USER, GROUP, os.environ["TZ"]))
    if "--build" in sys.argv:
        if os.path.exists(BOX) and os.listdir(BOX):
            bail("%s is not empty" % BOX)
        r = subprocess.run([sys.executable, TOOL, BOX, "all"], capture_output=True, text=True, errors="replace", timeout=900)
        if "[FAIL]" in r.stdout or r.returncode != 0 or "[PASS] THIRD.COMPILE" not in r.stdout:
            bail("the sandbox build did not pass:\n" + r.stdout[-800:])
        say("sandbox-listu-a5: built, bootstrap passed")
    elif not os.path.isfile(SD):
        bail("%s holds no built sandbox (use --build, or point it at one)" % BOX)
    subprocess.run([sys.executable, TOOL, BOX, "start"], capture_output=True, text=True, errors="replace", timeout=120)

    say("\n--- preparation: a CPROC that is not the install build, the internal probes, two fixture accounts -----------------")
    prepare()
    for name in ("zzaa", "zzbb"):
        build_account(name)
    # the same user probes in the SDSYS account: its sessions are the administrator's (SDTEST_ADMIN=1), and it is where a
    # phantom can be started in this sandbox (the phantom's own login looks for an account named after the OS user)
    for nm, text in USER_PROGS.items():
        put(os.path.join(SYS, "bp", nm), text)
    out = adm(["BASIC bp " + " ".join(USER_PROGS)])
    if not has(out, r"^Compiled %d program\(s\) with no errors" % len(USER_PROGS)):
        bail("the user probes did not compile in the SDSYS account:\n" + "\n".join(out[-8:]))
    say("  [done] accounts zzaa and zzbb, and the probes in SDSYS")

    try:
        # ---------------------------------------------------------------------------------------------------------
        say("\n--- A. 24 and 29: the account in !LISTU and in LISTU -------------------------------------------------")
        out = plain("zzaa", ["RUN bp zzluu"])
        rows = lu_rows(out)
        mine = by_name(rows, USER)
        row("CONTROL: the session is in the account zzaa (@WHO) and is the only user", has(out, r"^MY\[\d+\]\[zzaa\]$") and len(rows) == 1,
            "rows %r  %r" % (rows, out[-3:]))
        row("24: !LISTU value 9 is the account for the caller's own session: zzaa", len(mine) == 1 and mine[0][2] == "zzaa", repr(rows))
        # LISTU is the administrator's verb (NEWVOC does not carry it): its own line and header are the administrator's
        out = adm(["RUN bp zzluc"])
        mine_line = [ln for ln in out if re.match(r"^LC:\*", ln)]
        row("29: LISTU marks the caller's own line and puts the account after the user name: ': %s, sdsys' (the administrator's)" % USER,
            len(mine_line) == 1 and re.search(r": %s, sdsys\s*$" % re.escape(USER), mine_line[0]) is not None, repr(mine_line))
        row("29: ... and the header names the column", has(out, r"^LC:\s+User\s+Pid\s+Puid\s+Login time\s+Origin : Username, Account\s*$"), repr(out[:4]))
        out = plain("zzaa", ["RUN bp zzluc"])
        mine_line = [ln for ln in out if re.match(r"^LC:\*", ln)]
        row("29: and an ordinary account that was given LISTU (zzaa) sees its own account: ', zzaa'",
            len(mine_line) == 1 and re.search(r": %s, zzaa\s*$" % re.escape(USER), mine_line[0]) is not None, repr(out[:6]))

        out = plain("zzaa", ["LOGTO zzbb", "RUN bp zzluu"])
        row("24: after LOGTO zzbb the user table says zzbb (CPROC's logto sets it)",
            has(out, r"^MY\[\d+\]\[zzbb\]$") and len(by_name(lu_rows(out), USER)) == 1 and by_name(lu_rows(out), USER)[0][2] == "zzbb",
            repr(out[-5:]))
        out = plain("zzaa", ["LOGTO " + os.path.join(BOX, "user_accounts", "zzbb"), "RUN bp zzluu"])
        row("CONTROL: LOGTO to a path is refused for an ordinary user, and the user table still says zzaa",
            has(out, r"User not allowed in requested account") and has(out, r"^MY\[\d+\]\[zzaa\]$")
            and len(by_name(lu_rows(out), USER)) == 1 and by_name(lu_rows(out), USER)[0][2] == "zzaa", repr(out[-5:]))
        out = adm(["LOGTO " + os.path.join(BOX, "user_accounts", "zzbb"), "RUN bp zzluu"])
        row("24: ... and for the administrator it is allowed, and the table says the name of the path's last directory (as @WHO does): zzbb",
            has(out, r"^MY\[\d+\]\[zzbb\]$") and len(by_name(lu_rows(out), USER)) == 1 and by_name(lu_rows(out), USER)[0][2] == "zzbb", repr(out[-5:]))

        out = plain("zzaa", ["zzluset"])
        row("24: kernel(K$USERS) carries the account as value 9: it is what LOGIN set (zzaa)",
            tagged("\n".join(out), "SET0") == "zzaa", repr(out[-5:]))
        row("24: K$SET.ACCOUNT from an $internal program sets it and answers the name as it stands",
            tagged("\n".join(out), "SET1") == "zzname][zzname", repr(out[-4:]))
        row("24: ... an empty name clears it", tagged("\n".join(out), "SET2") == "][", repr(out[-3:]))

        # a phantom starts in its parent's account; another user's session is seen blank by an ordinary user
        oth = Live("oth", ["zzluoth"], "zzbb")
        time.sleep(2.5)
        row("setup: the other user's session is running as zzother in zzbb",
            re.search(r"(?m)^OTH\[\d+\]\[zzother\]\[zzbb\]$", oth.text()) is not None, oth.text()[-300:])
        out = plain("zzaa", ["RUN bp zzluu"])
        rows = lu_rows(out)
        o, m = by_name(rows, "zzother"), by_name(rows, USER)
        row("THE SECURITY ROW: an ordinary user sees another user's session with NO account (value 9 is empty)",
            len(o) == 1 and o[0][2] == "", repr(rows))
        row("... while its own session still shows zzaa", len(m) == 1 and m[0][2] == "zzaa", repr(rows))
        out = plain("zzaa", ["RUN bp zzluc"])
        oline = [ln for ln in out if re.search(r": zzother", ln)]
        row("29: LISTU shows the other user's line without an account for an ordinary user",
            len(oline) == 1 and re.search(r": zzother\s*$", oline[0]) is not None, repr(oline))
        # the administrator: its own !LISTU through a program run in the SDSYS account
        out = adm(["RUN bp zzluu"])
        o = by_name(lu_rows(out), "zzother")
        row("CONTROL: the administrator sees it: zzbb", len(o) == 1 and o[0][2] == "zzbb", repr(lu_rows(out)))
        out = adm(["RUN bp zzluc"])
        oline = [ln for ln in out if re.search(r": zzother", ln)]
        row("CONTROL: ... and LISTU shows ', zzbb' for the administrator", len(oline) == 1 and re.search(r": zzother, zzbb\s*$", oline[0]) is not None,
            repr(oline))
        oth.wait(40)
        oth.kill()

        # ---------------------------------------------------------------------------------------------------------
        say("\n--- B. 38: LISTU DETAIL and SYSTEM(1056) ----------------------------------------------------------------")
        oth = Live("oth2", ["zzluoth"], "zzbb")
        time.sleep(2.5)
        out = adm(["RUN bp zzludet"])           # the administrator's session: it is where a phantom starts in this sandbox
        text = "\n".join(out)
        row("setup: the phantom started (the table flags it) within 15 s: PHUP[%s]" % tagged(text, "PHUP"),
            re.match(r"^1\]\[\d+$", tagged(text, "PHUP") or "") is not None, repr(tagged(text, "PHUP")))
        first = [ln for ln in out if ln.startswith("LD:")][:2]
        row("38: LISTU DETAIL's first line counts the users: 2 interactive (the other session and this one), 0 API, 0 iPhantom, 1 phantom",
            len(first) == 2 and re.match(r"^LD:2 interactive, 0 API, 0 iPhantom, 1 phantom, \d+ peak\s*$", first[0]) is not None, repr(first))
        peak = re.search(r"(\d+) peak", first[0]).group(1) if first and re.search(r"(\d+) peak", first[0]) else "0"
        row("38: ... the peak is at least the 3 there are now (two sessions and the phantom)", int(peak) >= 3, "peak %s" % peak)
        row("38: ... and the report's own header follows the counts", len(first) == 2 and re.match(r"^LD:\s+User\s+Pid\s+Puid", first[1]) is not None, repr(first))
        row("38: SYSTEM(1056) says the same: interactive/API/iPhantom/phantom/peak = 2/0/0/1/%s" % peak,
            tagged(text, "C1056") == "2/0/0/1/" + peak, repr(tagged(text, "C1056")))
        rows = lu_rows(out)
        ph = [r for r in rows if r[3] == "1"]
        row("24: the phantom is listed with its parent's account: sdsys", len(ph) == 1 and ph[0][2] == "sdsys", repr(rows))
        ctl = adm(["LISTU NO.PAGE"])
        row("CONTROL: LISTU without DETAIL has no counts line", not has(ctl, r"\d+ interactive"), repr(ctl[:3]))
        # QM4 gaps Q-8: LIST.PHANTOMS shows only the phantom (the administrator's session, so the account is shown)
        lp = [ln[3:] for ln in out if ln.startswith("LP:")]
        row("Q-8 LIST.PHANTOMS: a header and one line, the phantom's, which is a user number, a pid, a name and the account sdsys",
            len(lp) == 2 and re.match(r"^\s+User\s+Pid\s+Username\s+Login time\s+Account\s*$", lp[0]) is not None
            and re.match(r"^\s*\d+\s+\d+\s+\S+\s+.*\d\d:\d\d\s+sdsys\s*$", lp[1]) is not None, repr(lp))
        row("Q-8 LIST.PHANTOMS: the sessions that are not phantoms are not in it (the other session and the one running it)",
            len(lp) == 2 and not re.search(r"zzother|zzbb", "\n".join(lp)), repr(lp))
        lq = [ln[3:] for ln in out if ln.startswith("LQ:")]
        row("Q-8 LIST.PHANTOMS USER name: no phantom of that user, so the header and nothing else", len(lq) == 1 and "Username" in lq[0], repr(lq))
        lr = [ln[3:] for ln in out if ln.startswith("LR:")]
        row("Q-8 LIST.PHANTOMS POOL is refused (SD has no pools of phantoms)", any("no pools of phantom" in ln for ln in lr), repr(lr))
        ls = [ln[3:] for ln in out if ln.startswith("LS:")]
        row("Q-8 LIST.PHANTOMS USER with no name is refused", any("User name required after USER" in ln for ln in ls), repr(ls))
        oth.wait(40)
        oth.kill()
        time.sleep(1)
        out = adm(["RUN bp zzlucnt"])
        c = (tagged("\n".join(out), "C1056") or "").split("/")
        row("38: with the other sessions gone: 1 interactive, 0 API, 0 iPhantom, 0 phantom now, and the peak is not lowered",
            len(c) == 5 and c[:4] == ["1", "0", "0", "0"] and c[4].isdigit() and int(c[4]) >= 3, repr(c))

        # ---------------------------------------------------------------------------------------------------------
        say("\n--- B2. QM4 gaps Q-5: CHILD, SIGNAL and SYSTEM(1062) with a phantom -------------------------------------------")
        out = adm(["RUN bp zzlusig"])
        text = "\n".join(out)
        row("Q-5 CHILD: the phantom this session started is its child (true), 0 and a number nobody has are not, and there is one child: CH1[%s]" % tagged(text, "CH1"),
            re.match(r"^1/0/0/1$", tagged(text, "CH1") or "") is not None, repr(out[-6:]))
        row("Q-5 SIGNAL: it was true for the phantom, whose SYSTEM(1062) saw it (the phantom wrote SIGNALLED, not TIMEOUT): SG[%s]" % tagged(text, "SG"),
            tagged(text, "SG") == "1/SIGNALLED", repr(out[-6:]))
        row("Q-5 CHILD: once the phantom has ended it is no longer a child: CH2[%s]" % tagged(text, "CH2"), tagged(text, "CH2") == "0", repr(out[-6:]))
        row("the session ran to its end (SIGDONE)", has(out, r"^SIGDONE$"), repr(out[-4:]))

        # ---------------------------------------------------------------------------------------------------------
        say("\n--- C. 491: the Hot Spot Monitor's counters ------------------------------------------------------------")
        out = plain("zzaa", ["DELETE.FILE zzhsmf", "CREATE.FILE zzhsmf", "RUN bp zzhsmd"])
        row("CONTROL: before HSM ON there is nothing to report", has(out, r"^HD:There is no data to report"), repr(out[-3:]))
        out = plain("zzaa", ["HSM ON", "RUN bp zzhsm", "RUN bp zzhsmd"])
        hd = [ln[3:] for ln in out if ln.startswith("HD:")]
        row("the header names the new columns", any(re.match(r"^Calls\.\.\s+CP time\.\.\.\s+Opens\.\.\.\s+Reads\.\.\.\.\s+Writes\.\.\s+Deletes\.\s+Program\s*$", h) for h in hd), repr(hd[:2]))
        line = [h for h in hd if re.search(r"zzhsm\s*$", h)]
        m = re.match(r"^\s*(\d+)\s+(\d+\.\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+\S*zzhsm\s*$", line[0]) if len(line) == 1 else None
        row("491: the program's line: 1 call, 1 open, 5 reads (3 READ + 2 READV), 4 writes (3 WRITE + 1 WRITEV), 2 deletes",
            m is not None and (m.group(1), m.group(3), m.group(4), m.group(5), m.group(6)) == ("1", "1", "5", "4", "2"), repr(line))
        row("491: ... and it is the program's own: the OPEN's VOC lookup and the READV / WRITEV recursive code are not in it (the exact counts above)",
            m is not None and m.group(3) == "1" and m.group(4) == "5", repr(line))
        row("491: the command processor has its own line with counters", any(re.search(r"\$cproc\s*$", h) and re.match(r"^\s*\d+\s+\d+\.\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+", h) for h in hd), repr(hd[:5]))
        out = plain("zzaa", ["HSM ON", "RUN bp zzhsm", "HSM ON", "RUN bp zzhsm", "RUN bp zzhsmd"])
        hd = [ln[3:] for ln in out if ln.startswith("HD:")]
        line = [h for h in hd if re.search(r"zzhsm\s*$", h)]
        m = re.match(r"^\s*(\d+)\s+(\d+\.\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+\S*zzhsm\s*$", line[0]) if len(line) == 1 else None
        row("491: HSM ON clears the counters: two runs with an HSM ON between show one run's counts, not two",
            m is not None and (m.group(1), m.group(3), m.group(4), m.group(5), m.group(6)) == ("1", "1", "5", "4", "2"), repr(line))
        out = plain("zzaa", ["HSM ON", "RUN bp zzhsm", "RUN bp zzhsm", "RUN bp zzhsmd"])
        hd = [ln[3:] for ln in out if ln.startswith("HD:")]
        line = [h for h in hd if re.search(r"zzhsm\s*$", h)]
        m = re.match(r"^\s*(\d+)\s+(\d+\.\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+\S*zzhsm\s*$", line[0]) if len(line) == 1 else None
        row("491: CONTROL: without the HSM ON between, two runs add up: 2 calls, 2 opens, 10 reads, 8 writes, 4 deletes",
            m is not None and (m.group(1), m.group(3), m.group(4), m.group(5), m.group(6)) == ("2", "2", "10", "8", "4"), repr(line))
        plain("zzaa", ["DELETE.FILE zzhsmf"])

        # ---------------------------------------------------------------------------------------------------------
        say("\n--- D. 577: PSTAT shows when a wait began ----------------------------------------------------------------")
        h = Live("wh", ["RUN bp zzluwh"], "zzaa")
        time.sleep(2)
        w = Live("ww", ["RUN bp zzluww"], "zzaa")
        time.sleep(3)
        wno = tagged(w.text(), "WW")
        hno = tagged(h.text(), "WH")
        row("setup: the holder and the waiter are running, and the waiter is blocked", wno is not None and hno is not None and "WW DONE" not in w.text(),
            "WH %r WW %r" % (hno, wno))
        pout = plain("zzaa", ["PSTAT USER " + wno]) if wno else []
        stamps = re.findall(r"(?m)^\s+Wait since (\d\d \w{3} \d\d \d\d:\d\d:\d\d)\s*$", "\n".join(pout))
        row("CONTROL: PSTAT shows the waiter waiting for the record lock held by the holder",
            has(pout, r"Waiting for record lock held by user %s" % hno), repr(pout[-8:]))
        row("577: ... and 'Wait since' with the time the wait began, in this zone, within two minutes of now: %s" % stamps,
            len(stamps) == 1 and near_now(stamps[0], "%d %b %y %H:%M:%S"), "now %s  %r" % (datetime.datetime.now().strftime("%d %b %y %H:%M:%S"), pout[-8:]))
        after = [i for i, ln in enumerate(pout) if "Record " in ln or "Record" in ln]
        wi = [i for i, ln in enumerate(pout) if re.match(r"^\s+Wait since ", ln)]
        row("577: ... printed after the lock lines it belongs to (the file and the record)",
            bool(after) and bool(wi) and wi[0] > max(after), repr(pout[-8:]))
        hpout = plain("zzaa", ["PSTAT USER " + hno]) if hno else []
        row("577: CONTROL: PSTAT of the holder, which is not waiting, has no 'Wait since'", len(hpout) > 0 and not has(hpout, r"Wait since"), repr(hpout[-6:]))
        h.wait(30)
        w.wait(30)
    finally:
        for lv in lives:
            lv.kill()

    say("\nsandbox-listu-a5: %d passed, %d failed" % (passed, failed))
    if passed + failed == 0:
        bail("no row ran - a broken test, not a pass")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
